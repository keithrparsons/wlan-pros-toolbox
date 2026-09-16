// Joins THIS Windows machine's own radio to a network, via Win32 Native Wifi.
//
// WHAT IS HERE AND WHAT IS DELIBERATELY NOT. This file is as thin as it could be
// made, because nothing in it can be tested anywhere but on Windows against a
// real radio. The profile XML it sends, and the mapping from our security model
// to Microsoft's vocabulary, live in `windows_join_profile.dart`, which is pure
// Dart and covered by tests that run on any machine. If you are looking for the
// logic, it is there. What is here is allocation, one call, and the wait.
//
// THE WAIT IS THE WHOLE CORRECTNESS PROBLEM. `WlanConnect` is ASYNCHRONOUS. It
// returns ERROR_SUCCESS when the REQUEST is accepted, not when the machine is
// associated. A caller that treats that return as "connected" will tell the user
// they joined a network they did not join, and will do it instantly and
// confidently, which is worse than failing. So this polls the interface state
// until Windows says connected, or gives up and says so.
//
// The same class of defect as the scan side's frozen counter and the sniffer
// that agreed with itself: a call that succeeds is not a result.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'pi_backend_client.dart' show PiJoinSecurity;
import 'windows_join_profile.dart';

/// Why a join attempt ended without the machine being associated.
enum WindowsJoinFailure {
  /// No wireless interface, or the Native Wifi service did not open.
  noInterface,

  /// `WlanConnect` itself refused the request. The profile was rejected, or the
  /// interface was in a state that cannot accept a connection.
  requestRejected,

  /// The request was accepted and the machine never reached the connected
  /// state before the timeout. **This is the honest outcome for a wrong
  /// passphrase**: Windows accepts the profile, tries, and quietly fails, and
  /// the only signal an unprivileged caller gets is that it never connects.
  neverConnected,
}

/// Thrown when a join attempt does not end with the machine associated.
class WindowsJoinException implements Exception {
  const WindowsJoinException(this.failure, this.message);
  final WindowsJoinFailure failure;
  final String message;
  @override
  String toString() => 'WindowsJoinException(${failure.name}): $message';
}

const int _kErrorSuccess = 0;
const int _kWlanClientVersion = 2;
const int _kBssTypeInfrastructure = 1;

/// Associates this machine's wireless interface with [ssid].
///
/// Uses a TEMPORARY profile, which Windows holds in memory for the duration of
/// the connection and never writes to the machine's profile store. That is a
/// requirement rather than a detail: Keith, on this tool, *"this is a TEST
/// tool"*. A persisted profile would leave the passphrase on the machine after
/// the app exits, and would also make the network a preferred one that Windows
/// silently rejoins later.
///
/// Completes normally only when Windows reports the interface CONNECTED.
/// Throws [WindowsJoinException] otherwise, and [JoinProfileUnsupported] when
/// the network cannot be expressed as a profile at all.
Future<void> joinWifiNetworkWindows({
  required String ssid,
  required PiJoinSecurity security,
  String? passphrase,
  Duration timeout = const Duration(seconds: 25),
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  // Built FIRST, before any handle is opened, so an unjoinable network costs
  // nothing and fails with a message about the network rather than about Win32.
  final String profileXml = buildWindowsJoinProfileXml(
    ssid: ssid,
    security: security,
    passphrase: passphrase,
  );

  final Pointer<Uint32> pdwNegotiated = calloc<Uint32>();
  final Pointer<IntPtr> phClientHandle = calloc<IntPtr>();
  try {
    if (WlanOpenHandle(
          _kWlanClientVersion,
          nullptr,
          pdwNegotiated,
          phClientHandle,
        ) !=
        _kErrorSuccess) {
      throw const WindowsJoinException(
        WindowsJoinFailure.noInterface,
        'The Windows WLAN service did not open.',
      );
    }
    final int handle = phClientHandle.value;
    try {
      final Pointer<GUID> guidPtr = calloc<GUID>();
      try {
        _fillFirstWirelessInterfaceGuid(handle, guidPtr);
        _issueConnect(handle, guidPtr, profileXml);
        await _awaitConnected(handle, guidPtr, timeout, pollInterval, ssid);
      } finally {
        calloc.free(guidPtr);
      }
    } finally {
      WlanCloseHandle(handle, nullptr);
    }
  } finally {
    calloc.free(pdwNegotiated);
    calloc.free(phClientHandle);
  }
}

/// Writes the first wireless interface's GUID into [guidPtr].
///
/// Takes the FIRST interface rather than the connected one, because the whole
/// point here is to act on an interface that is very likely not connected yet.
void _fillFirstWirelessInterfaceGuid(int handle, Pointer<GUID> guidPtr) {
  final Pointer<Pointer<WLAN_INTERFACE_INFO_LIST>> ppIfList =
      calloc<Pointer<WLAN_INTERFACE_INFO_LIST>>();
  try {
    if (WlanEnumInterfaces(handle, nullptr, ppIfList) != _kErrorSuccess) {
      throw const WindowsJoinException(
        WindowsJoinFailure.noInterface,
        'Could not enumerate wireless interfaces.',
      );
    }
    final Pointer<WLAN_INTERFACE_INFO_LIST> list = ppIfList.value;
    try {
      if (list.ref.dwNumberOfItems == 0) {
        throw const WindowsJoinException(
          WindowsJoinFailure.noInterface,
          'No wireless interface present.',
        );
      }
      guidPtr.ref.setGUID(list.ref.InterfaceInfo[0].InterfaceGuid.toString());
    } finally {
      WlanFreeMemory(list.cast());
    }
  } finally {
    calloc.free(ppIfList);
  }
}

/// Issues the connect request. Returns as soon as Windows ACCEPTS it.
void _issueConnect(int handle, Pointer<GUID> guidPtr, String profileXml) {
  final Pointer<Utf16> profile = profileXml.toNativeUtf16();
  final Pointer<WLAN_CONNECTION_PARAMETERS> params =
      calloc<WLAN_CONNECTION_PARAMETERS>();
  try {
    params.ref
      ..wlanConnectionMode = wlan_connection_mode_temporary_profile
      // For a temporary profile this field carries the XML itself, not a name.
      ..strProfile = profile
      // Null: the profile already names the SSID, and supplying both is a way
      // to have them disagree.
      ..pDot11Ssid = nullptr
      ..pDesiredBssidList = nullptr
      ..dot11BssType = _kBssTypeInfrastructure
      ..dwFlags = 0;

    final int rc = WlanConnect(handle, guidPtr, params, nullptr);
    if (rc != _kErrorSuccess) {
      throw WindowsJoinException(
        WindowsJoinFailure.requestRejected,
        'Windows refused the connection request (error $rc).',
      );
    }
  } finally {
    calloc.free(params);
    calloc.free(profile);
  }
}

/// Polls the interface state until Windows reports connected, or gives up.
///
/// There is a notification API (`WlanRegisterNotification`) that would report
/// this without polling. It needs an FFI callback into Dart from a Windows
/// thread, which is a materially larger and more fragile piece of machinery
/// than a half-second poll over a twenty-five second window. Polling is chosen
/// deliberately, not by omission.
Future<void> _awaitConnected(
  int handle,
  Pointer<GUID> guidPtr,
  Duration timeout,
  Duration pollInterval,
  String ssid,
) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (_queryInterfaceState(handle, guidPtr) ==
        wlan_interface_state_connected) {
      return;
    }
    await Future<void>.delayed(pollInterval);
  }
  throw WindowsJoinException(
    WindowsJoinFailure.neverConnected,
    'Windows accepted the request but never associated with "$ssid". '
    'The usual cause is a wrong passphrase, which Windows does not report '
    'to an unprivileged caller as anything more specific than this.',
  );
}

/// One `wlan_intf_opcode_interface_state` query. Returns -1 when unreadable,
/// which is treated as "not connected yet" rather than as an error, because a
/// transient unreadable state during association is normal.
int _queryInterfaceState(int handle, Pointer<GUID> guidPtr) {
  final Pointer<Uint32> pSize = calloc<Uint32>();
  final Pointer<Pointer> ppData = calloc<Pointer>();
  try {
    final int rc = WlanQueryInterface(
      handle,
      guidPtr,
      wlan_intf_opcode_interface_state,
      nullptr,
      pSize,
      ppData,
      nullptr,
    );
    if (rc != _kErrorSuccess || ppData.value == nullptr) return -1;
    try {
      return ppData.value.cast<Int32>().value;
    } finally {
      WlanFreeMemory(ppData.value);
    }
  } finally {
    calloc.free(pSize);
    calloc.free(ppData);
  }
}

/// Leaves the current network on this machine's wireless interface.
///
/// `WlanDisconnect` is asynchronous in the same way `WlanConnect` is, so this
/// polls for the interface to leave the connected state rather than trusting
/// the return code. The asymmetry would otherwise be its own bug: careful about
/// proving a join and careless about proving a leave.
Future<void> disconnectWifiWindows({
  Duration timeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 400),
}) async {
  final Pointer<Uint32> pdwNegotiated = calloc<Uint32>();
  final Pointer<IntPtr> phClientHandle = calloc<IntPtr>();
  try {
    if (WlanOpenHandle(
          _kWlanClientVersion,
          nullptr,
          pdwNegotiated,
          phClientHandle,
        ) !=
        _kErrorSuccess) {
      throw const WindowsJoinException(
        WindowsJoinFailure.noInterface,
        'The Windows WLAN service did not open.',
      );
    }
    final int handle = phClientHandle.value;
    try {
      final Pointer<GUID> guidPtr = calloc<GUID>();
      try {
        _fillFirstWirelessInterfaceGuid(handle, guidPtr);
        final int rc = WlanDisconnect(handle, guidPtr, nullptr);
        if (rc != _kErrorSuccess) {
          throw WindowsJoinException(
            WindowsJoinFailure.requestRejected,
            'Windows refused the disconnect request (error $rc).',
          );
        }
        final DateTime deadline = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(deadline)) {
          if (_queryInterfaceState(handle, guidPtr) !=
              wlan_interface_state_connected) {
            return;
          }
          await Future<void>.delayed(pollInterval);
        }
        throw const WindowsJoinException(
          WindowsJoinFailure.neverConnected,
          'The radio was still associated after the disconnect timeout.',
        );
      } finally {
        calloc.free(guidPtr);
      }
    } finally {
      WlanCloseHandle(handle, nullptr);
    }
  } finally {
    calloc.free(pdwNegotiated);
    calloc.free(phClientHandle);
  }
}
