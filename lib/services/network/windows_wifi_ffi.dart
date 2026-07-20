// Windows Native Wifi FFI implementation — the win32 calls behind
// [WindowsWifiReader]. Split into its own file so the win32 surface area lives
// in one place and [WindowsWifiReader] stays a thin platform-guarded wrapper.
//
// feat/windows-port-prep (2026-06-11). NO C++ MethodChannel — pure dart:ffi
// against wlanapi.dll via the `win32` package's pre-bound WLAN functions and
// structs (WlanOpenHandle / WlanEnumInterfaces / WlanQueryInterface /
// WlanGetNetworkBssList / WlanFreeMemory / WlanCloseHandle and the WLAN_* /
// DOT11_* structs). See windows_wifi_reader.dart for the call-flow narrative.
//
// EVERY runtime-truth claim here is `// TODO(windows-verify):` — this module
// compiles and `flutter analyze`-checks on macOS but is EXECUTED for the first
// time on a real Windows box with a real wireless NIC. dart:ffi does not run on
// macOS, so struct layout, pointer arithmetic, and free discipline are
// written-not-executed until the 26th.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32/win32.dart';

import '../../data/channel_frequency_data.dart'
    show WifiBand, WifiBandInfo, frequencyToChannel;
import 'ie_parser.dart' show findInformationElement;
import 'wifi_info_service.dart'
    show WifiInfo, WifiInfoUnavailable, WifiInfoUnavailableReason;

// Re-exported so this module's existing callers and tests keep resolving
// [findInformationElement] here after its extraction into the shared
// platform-neutral IE walker (ie_parser.dart).
export 'ie_parser.dart' show findInformationElement;

// ── Win32 constants (declared locally from the documented Native Wifi values
// rather than imported, so this module is robust to the win32 package's
// constant-export surface and self-documenting). Values are the canonical
// Microsoft Learn / wlanapi.h definitions. ─────────────────────────────────

/// `wlan_intf_opcode_current_connection` — the WlanQueryInterface opcode that
/// returns WLAN_CONNECTION_ATTRIBUTES for the live connection.
const int _kOpcodeCurrentConnection = 7;

/// `wlan_intf_opcode_channel_number` — returns the operating channel (ULONG) of
/// the connected interface. Authoritative for the primary link, and used to
/// disambiguate which affiliated per-link BSS to read on a Wi-Fi 7 MLO / MBSSID
/// connection where the current-connection BSSID is the AP MLD address.
const int _kOpcodeChannelNumber = 8;

/// `wlan_interface_state_connected` — the interface is associated to a network.
const int _kInterfaceStateConnected = 1;

/// `dot11_BSS_type_infrastructure` — a BSS served by an AP (vs ad-hoc). The
/// connected AP is always infrastructure for our purposes.
const int _kBssTypeInfrastructure = 1;

/// The WLAN client version we negotiate. 2 = Vista+ Native Wifi (what every
/// supported Windows ships). The negotiated version comes back in an out-param
/// we read but do not branch on.
const int _kWlanClientVersion = 2;

/// `ERROR_SUCCESS`.
const int _kErrorSuccess = 0;

/// `ERROR_BUFFER_OVERFLOW` — GetAdaptersAddresses returns this on the sizing
/// call (buffer too small / null), with the required byte count written back to
/// the size out-param. We then allocate and call again.
const int _kErrorBufferOverflow = 111;

/// `AF_UNSPEC` — return adapters for every address family. We only read the
/// link-layer MAC, so the family is immaterial; UNSPEC is the documented value
/// for "all".
const int _kAfUnspec = 0;

/// GetAdaptersAddresses flags — skip the unicast/anycast/multicast/DNS address
/// sub-lists we never read, so the driver fills the smallest possible buffer.
const int _kGaaFlagSkipUnicast = 0x0001;
const int _kGaaFlagSkipAnycast = 0x0002;
const int _kGaaFlagSkipMulticast = 0x0004;
const int _kGaaFlagSkipDnsServer = 0x0008;
const int _kGaaFlags = _kGaaFlagSkipUnicast |
    _kGaaFlagSkipAnycast |
    _kGaaFlagSkipMulticast |
    _kGaaFlagSkipDnsServer;

/// Byte offset of the variable-length `wlanBssEntries` array inside
/// WLAN_BSS_LIST: `dwTotalSize` (Uint32, 4) + `dwNumberOfItems` (Uint32, 4) = 8,
/// with no padding before the array (WLAN_BSS_ENTRY begins with a 4-byte-aligned
/// DOT11_SSID). Used to compute a real `Pointer<WLAN_BSS_ENTRY>` per row so the
/// IE blob can be read by pointer arithmetic (the win32 inline-array accessor
/// returns a struct view with no exposed backing address).
///
/// TODO(windows-verify): confirm the +8 base and `sizeOf<WLAN_BSS_ENTRY>()`
/// stride land each entry pointer on the same memory the (proven) array accessor
/// reads. A wrong offset corrupts ONLY the channel-width / country IE parse
/// (those fall back to null); the RSSI/channel/band path stays on the array
/// accessor and is unaffected.
const int _kBssEntriesOffset = 8;

// IE element IDs (IEEE 802.11 element-ID assignments) used by the operating-
// width + country parse. Extended elements share ID 255 and carry a 1-byte
// extension ID as their first data byte.
const int _kEidCountry = 7; // Country element.
const int _kEidHtOperation = 61; // HT Operation (20 vs 40 MHz).
const int _kEidVhtOperation = 192; // VHT Operation (80 / 160 / 80+80).
const int _kEidExtended = 255; // Element ID Extension marker.
const int _kExtHeOperation = 36; // HE Operation (6 GHz operation width).
const int _kExtEhtOperation = 106; // EHT Operation (Wi-Fi 7, up to 320 MHz).

// dot11_phy_type_* — the PHY generation the radio is using on this link.
const int _kPhyTypeDsss = 2; // 802.11b (DSSS)
const int _kPhyTypeOfdm = 4; // 802.11a (OFDM)
const int _kPhyTypeHrdsss = 5; // 802.11b (HR/DSSS)
const int _kPhyTypeErp = 6; // 802.11g (ERP)
const int _kPhyTypeHt = 7; // 802.11n (HT)
const int _kPhyTypeVht = 8; // 802.11ac (VHT)
const int _kPhyTypeHe = 10; // 802.11ax (HE)
const int _kPhyTypeEht = 11; // 802.11be (EHT)

// DOT11_AUTH_ALGO_* — the authentication algorithm from
// WLAN_SECURITY_ATTRIBUTES.dot11AuthAlgorithm. Mapped to the same security
// TOKEN strings the macOS/iOS channels emit, so WifiSecurityClassifier (Dart,
// shared) classifies them with zero new code.
const int _kAuthOpen = 1; // DOT11_AUTH_ALGO_80211_OPEN
const int _kAuthSharedKey = 2; // DOT11_AUTH_ALGO_80211_SHARED_KEY (WEP)
const int _kAuthWpa = 3; // DOT11_AUTH_ALGO_WPA (WPA Enterprise)
const int _kAuthWpaPsk = 4; // DOT11_AUTH_ALGO_WPA_PSK (WPA Personal)
const int _kAuthRsna = 6; // DOT11_AUTH_ALGO_RSNA (WPA2 Enterprise)
const int _kAuthRsnaPsk = 7; // DOT11_AUTH_ALGO_RSNA_PSK (WPA2 Personal)
const int _kAuthWpa3 = 8; // DOT11_AUTH_ALGO_WPA3 (WPA3 Enterprise, 192-bit)
const int _kAuthWpa3Sae = 9; // DOT11_AUTH_ALGO_WPA3_SAE (WPA3 Personal)
const int _kAuthOwe = 10; // DOT11_AUTH_ALGO_OWE (Enhanced Open)
const int _kAuthWpa3Ent = 11; // DOT11_AUTH_ALGO_WPA3_ENT (WPA3 Enterprise)

/// Reads the connected AP via the Native Wifi API and returns it as a [WifiInfo].
///
/// Throws [WifiInfoUnavailable] ([WifiInfoUnavailableReason.channelError]) on any
/// Native Wifi error, when there is no wireless interface, or when none is
/// connected. Frees every API-allocated buffer and closes the client handle on
/// every exit path (success or throw).
///
/// MUST only be called on Windows — [WindowsWifiReader] guards this.
WifiInfo readConnectedApFromNativeWifi() {
  final Pointer<IntPtr> phClientHandle = calloc<IntPtr>();
  final Pointer<Uint32> pdwNegotiated = calloc<Uint32>();
  Pointer<WLAN_INTERFACE_INFO_LIST> pIfList = nullptr;

  try {
    // 1. Open a client handle.
    final int openResult = WlanOpenHandle(
      _kWlanClientVersion,
      nullptr,
      pdwNegotiated,
      phClientHandle,
    );
    if (openResult != _kErrorSuccess) {
      throw WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'WlanOpenHandle failed (error $openResult).',
      );
    }
    final int handle = phClientHandle.value;

    try {
      // 2. Enumerate wireless interfaces; pick the first connected one.
      final Pointer<Pointer<WLAN_INTERFACE_INFO_LIST>> ppIfList =
          calloc<Pointer<WLAN_INTERFACE_INFO_LIST>>();
      try {
        final int enumResult =
            WlanEnumInterfaces(handle, nullptr, ppIfList);
        if (enumResult != _kErrorSuccess) {
          throw WifiInfoUnavailable(
            WifiInfoUnavailableReason.channelError,
            'WlanEnumInterfaces failed (error $enumResult).',
          );
        }
        pIfList = ppIfList.value;
      } finally {
        calloc.free(ppIfList);
      }

      final int count = pIfList.ref.dwNumberOfItems;
      if (count == 0) {
        throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'No wireless interface present.',
        );
      }

      // Copy the GUID of the first connected interface into a buffer we own, so
      // it is unambiguously a Pointer<GUID> and outlives the list pointer, and
      // capture its friendly adapter description in the same pass.
      final _ConnectedInterface? iface = _connectedInterface(pIfList, count);
      if (iface == null) {
        throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'No connected wireless interface.',
        );
      }
      final Pointer<GUID> guidPtr = iface.guidPtr;

      try {
        // 3. Query the current connection attributes.
        final _ConnectionSnapshot conn =
            _queryCurrentConnection(handle, guidPtr);

        // 4. Read the BSS list to get the real dBm RSSI + center frequency for
        // the connected BSSID, plus the operating channel width + country code
        // parsed from that BSS entry's IE blob.
        final _BssSnapshot? bss = _queryConnectedBss(handle, guidPtr, conn);

        // 5. Read the device adapter MAC via GetAdaptersAddresses, matched to
        // this interface by GUID. Null (honest) when the match fails.
        final String? hardwareAddress = _queryHardwareAddress(guidPtr);

        return _composeWifiInfo(
          conn,
          bss,
          interfaceName: iface.description,
          hardwareAddress: hardwareAddress,
        );
      } finally {
        calloc.free(guidPtr);
      }
    } finally {
      if (pIfList != nullptr) {
        WlanFreeMemory(pIfList.cast());
      }
      WlanCloseHandle(handle, nullptr);
    }
  } finally {
    calloc.free(phClientHandle);
    calloc.free(pdwNegotiated);
  }
}

/// The connected interface's GUID (a caller-owned copy) plus its friendly
/// adapter description (e.g. "Intel(R) Wi-Fi 6E AX211 160MHz"). The caller owns
/// [guidPtr] and frees it with `calloc.free`.
class _ConnectedInterface {
  _ConnectedInterface(this.guidPtr, this.description);

  final Pointer<GUID> guidPtr;
  final String? description;
}

/// Returns the first connected interface's GUID (a freshly-allocated COPY) and
/// its `strInterfaceDescription`, or null when none is connected.
///
/// Copying the GUID (rather than taking the address of the inline-array element)
/// keeps it valid independent of the interface-list pointer's lifetime and makes
/// it unambiguously a `Pointer&lt;GUID&gt;` for WlanQueryInterface. The
/// description is the real friendly adapter name Native Wifi already holds, so
/// the Interface row shows it instead of an opaque GUID.
///
/// TODO(windows-verify): confirm the inline-array element read
/// `pIfList.ref.InterfaceInfo[i]` indexes correctly against the real
/// variable-length WLAN_INTERFACE_INFO_LIST layout, and that
/// `strInterfaceDescription` decodes to the expected adapter name.
_ConnectedInterface? _connectedInterface(
  Pointer<WLAN_INTERFACE_INFO_LIST> pIfList,
  int count,
) {
  for (int i = 0; i < count; i++) {
    final WLAN_INTERFACE_INFO info = pIfList.ref.InterfaceInfo[i];
    if (info.isState == _kInterfaceStateConnected) {
      // Copy the 16-byte GUID into a stable buffer we own, so it outlives any
      // reshuffle of the list pointer and is unambiguously a Pointer<GUID>.
      final Pointer<GUID> out = calloc<GUID>();
      // win32's GUID models Data4 as a single Uint64 (not an 8-byte array), so
      // the whole 16-byte GUID copies as four scalar field assignments.
      out.ref
        ..Data1 = info.InterfaceGuid.Data1
        ..Data2 = info.InterfaceGuid.Data2
        ..Data3 = info.InterfaceGuid.Data3
        ..Data4 = info.InterfaceGuid.Data4;
      // strInterfaceDescription is a fixed WCHAR[] the win32 binding decodes to
      // a Dart string; an empty value degrades honestly to null.
      final String desc = info.strInterfaceDescription.trim();
      return _ConnectedInterface(out, desc.isEmpty ? null : desc);
    }
  }
  return null;
}

/// The fields we lift out of WLAN_CONNECTION_ATTRIBUTES (+ its security attrs).
class _ConnectionSnapshot {
  const _ConnectionSnapshot({
    required this.ssid,
    required this.bssid,
    required this.phyType,
    required this.signalQuality,
    required this.rxRateKbps,
    required this.txRateKbps,
    required this.securityToken,
  });

  final String? ssid;
  final String? bssid;
  final int phyType;
  final int signalQuality; // 0–100
  final int rxRateKbps; // ulRxRate is in Kbps
  final int txRateKbps; // ulTxRate is in Kbps
  final String? securityToken;
}

/// Queries WLAN_CONNECTION_ATTRIBUTES for the connected interface.
_ConnectionSnapshot _queryCurrentConnection(
  int handle,
  Pointer<GUID> guidPtr,
) {
  final Pointer<Uint32> pDataSize = calloc<Uint32>();
  final Pointer<Pointer> ppData = calloc<Pointer>();
  Pointer<WLAN_CONNECTION_ATTRIBUTES> pConn = nullptr;
  try {
    final int qResult = WlanQueryInterface(
      handle,
      guidPtr,
      _kOpcodeCurrentConnection,
      nullptr,
      pDataSize,
      ppData,
      nullptr,
    );
    if (qResult != _kErrorSuccess) {
      throw WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'WlanQueryInterface(current_connection) failed (error $qResult).',
      );
    }
    pConn = ppData.value.cast<WLAN_CONNECTION_ATTRIBUTES>();
    final WLAN_ASSOCIATION_ATTRIBUTES assoc = pConn.ref.wlanAssociationAttributes;

    // SSID: DOT11_SSID is a length-prefixed (NOT null-terminated) byte array.
    final String? ssid = _decodeSsid(assoc.dot11Ssid);
    // BSSID: 6 raw bytes → colon-hex.
    final String? bssid = _decodeBssid(assoc.dot11Bssid);

    final WLAN_SECURITY_ATTRIBUTES sec = pConn.ref.wlanSecurityAttributes;
    final String? token = sec.bSecurityEnabled == 0
        ? 'open'
        : _securityToken(sec.dot11AuthAlgorithm);

    return _ConnectionSnapshot(
      ssid: ssid,
      bssid: bssid,
      phyType: assoc.dot11PhyType,
      signalQuality: assoc.wlanSignalQuality,
      rxRateKbps: assoc.ulRxRate,
      txRateKbps: assoc.ulTxRate,
      securityToken: token,
    );
  } finally {
    if (pConn != nullptr) {
      WlanFreeMemory(pConn.cast());
    }
    calloc.free(pDataSize);
    calloc.free(ppData);
  }
}

/// The fields we lift out of the connected WLAN_BSS_ENTRY (real dBm + frequency,
/// plus the operating width + country parsed from its IE blob).
class _BssSnapshot {
  const _BssSnapshot({
    required this.rssiDbm,
    required this.centerFreqKhz,
    this.channelWidthMhz,
    this.countryCode,
  });

  final int rssiDbm; // lRssi — a true negative dBm
  final int centerFreqKhz; // ulChCenterFrequency, in kHz
  final int? channelWidthMhz; // {20,40,80,160,320} from HT/VHT/HE/EHT op IEs
  final String? countryCode; // 2-char AP-advertised country, or null
}

/// A decoded BSS-list entry we may select the connected link from.
///
/// A plain Dart value object (no win32 struct), so the link-selection logic that
/// consumes it ([selectConnectedLink]) is unit-testable off Windows.
/// [_queryConnectedBss] builds these from WLAN_BSS_ENTRY rows.
@visibleForTesting
class WifiBssCandidate {
  const WifiBssCandidate({
    required this.bssid,
    required this.ssid,
    required this.rssiDbm,
    required this.centerFreqKhz,
    this.informationElements,
  });

  final String bssid; // lowercase colon-hex
  final String? ssid;
  final int rssiDbm;
  final int centerFreqKhz;

  /// The raw IE blob copied out of this entry's WLAN_BSS_ENTRY (Beacon/Probe
  /// Response elements), or null when the entry carries none. Parsed for the
  /// operating channel width + country only on the SELECTED link, so the walk
  /// runs once, not per candidate.
  final Uint8List? informationElements;
}

/// Maps decoded BSS-list entries to the `com.wlanpros.toolbox/ap_scan` payload
/// rows — the SAME row shape the Android and macOS channels return, so the
/// existing `ScannedAp` model would consume them unchanged.
///
/// DARK PATH. This mapper and [enumerateNearbyBssFromNativeWifi] complete the
/// Windows nearby-AP enumeration, but Windows is deliberately NOT a supported
/// platform in `ApScanService.isSupportedPlatform` and the Nearby AP Scan tool
/// is dropped from the Windows catalog. Nothing calls this at runtime. The
/// module header's `TODO(windows-verify)` applies in full: it has never been
/// executed against a real wlanapi.dll and a real wireless NIC, and unverified
/// code does not ship live.
///
/// Pure and unit-testable off Windows: it takes plain [WifiBssCandidate] values,
/// not win32 structs. Channel and band are resolved through the proven
/// [frequencyToChannel] table rather than a second hand-rolled channel plan; a
/// BSS whose frequency does not land on the channel plan is DROPPED rather than
/// filed under a guessed channel, matching the Android and macOS mappers. Note
/// that WLAN_BSS_ENTRY reports the center frequency in kHz, not MHz.
///
/// No noise and no SNR: the Native Wifi BSS list carries no per-BSS noise floor,
/// so there is nothing to report and nothing is derived (GL-005 / GL-008).
@visibleForTesting
List<Map<String, Object?>> scannedApRowsFromBssCandidates(
  List<WifiBssCandidate> candidates,
) {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
  final Set<String> seen = <String>{};
  for (final WifiBssCandidate c in candidates) {
    if (!seen.add(c.bssid)) continue;
    final double mhz = c.centerFreqKhz / 1000.0;
    final ({WifiBand band, int channel})? match = frequencyToChannel(mhz);
    if (match == null) continue;
    rows.add(<String, Object?>{
      // A hidden network's empty SSID is passed as null so the UI renders
      // "(hidden network)" rather than a blank or a fabricated name.
      'ssid': (c.ssid == null || c.ssid!.isEmpty) ? null : c.ssid,
      'bssid': c.bssid,
      'rssiDbm': c.rssiDbm,
      'channel': match.channel,
      'band': match.band.label,
      'frequencyMhz': mhz.round(),
    });
  }
  return rows;
}

/// First 5 octets of a colon-hex BSSID (`94:2a:6f:a0:a5`), lowercased. Groups
/// the transmitted + non-transmitted BSSIDs of one AP radio (MBSSID), and
/// bridges a Wi-Fi 7 AP MLD address to its affiliated per-link APs, which share
/// the OUI + first device octets and differ only in the last byte. Lowercasing
/// makes the prefix match case-insensitive; the real call path already feeds it
/// lowercase BSSIDs, so this is behavior-preserving.
@visibleForTesting
String bssidRadioPrefix(String bssid) {
  final String lower = bssid.toLowerCase();
  final List<String> parts = lower.split(':');
  return parts.length >= 6 ? parts.sublist(0, 5).join(':') : lower;
}

/// Picks the candidate on [operatingChannel] when known, else the strongest
/// (least-negative dBm). Returns null for an empty list.
WifiBssCandidate? _selectLink(
  List<WifiBssCandidate> list,
  int? operatingChannel,
) {
  if (list.isEmpty) return null;
  if (operatingChannel != null) {
    for (final WifiBssCandidate c in list) {
      if (_frequencyKhzToChannel(c.centerFreqKhz) == operatingChannel) return c;
    }
  }
  final List<WifiBssCandidate> sorted = List<WifiBssCandidate>.of(list)
    ..sort((WifiBssCandidate a, WifiBssCandidate b) =>
        b.rssiDbm.compareTo(a.rssiDbm));
  return sorted.first;
}

/// The pure connected-link selection: given the decoded BSS candidates and the
/// current-connection identifiers, returns the candidate that represents the
/// connected link, or null when nothing advertises the connection.
///
/// Precedence (exact → broad), identical to the win32 path it was extracted
/// from, so the common single-link case is unchanged:
///   1. Exact BSSID match (non-MLO APs).
///   2. Same AP radio (shared first-5-octet prefix) — the Wi-Fi 7 MLO / MBSSID
///      case where [connBssid] is the AP MLD address that never beacons;
///      selects the affiliated link on [operatingChannel], else the strongest.
///   3. Same SSID — last resort; same selection rule.
///
/// [connBssid] is matched case-insensitively against the (lowercase)
/// candidate BSSIDs.
@visibleForTesting
WifiBssCandidate? selectConnectedLink(
  List<WifiBssCandidate> candidates, {
  required String? connBssid,
  required String? connSsid,
  required int? operatingChannel,
}) {
  if (candidates.isEmpty) return null;

  final String? lowerBssid = connBssid?.toLowerCase();

  // 1. Exact BSSID match — the normal single-link case.
  if (lowerBssid != null) {
    for (final WifiBssCandidate c in candidates) {
      if (c.bssid == lowerBssid) return c;
    }
    // 2. Same AP radio (Wi-Fi 7 MLO / MBSSID): the connection BSSID is the AP
    // MLD address; read the affiliated per-link AP on the operating channel.
    final String prefix = bssidRadioPrefix(lowerBssid);
    final List<WifiBssCandidate> sameRadio = candidates
        .where((WifiBssCandidate c) => bssidRadioPrefix(c.bssid) == prefix)
        .toList();
    final WifiBssCandidate? link = _selectLink(sameRadio, operatingChannel);
    if (link != null) return link;
  }

  // 3. Same SSID — last resort.
  if (connSsid != null) {
    final List<WifiBssCandidate> sameSsid = candidates
        .where((WifiBssCandidate c) => c.ssid != null && c.ssid == connSsid)
        .toList();
    final WifiBssCandidate? link = _selectLink(sameSsid, operatingChannel);
    if (link != null) return link;
  }

  return null;
}

/// Queries `wlan_intf_opcode_channel_number` for the connected interface's
/// operating channel. Returns null on any error or a 0 channel.
int? _queryOperatingChannel(int handle, Pointer<GUID> guidPtr) {
  final Pointer<Uint32> pDataSize = calloc<Uint32>();
  final Pointer<Pointer> ppData = calloc<Pointer>();
  try {
    final int r = WlanQueryInterface(
      handle,
      guidPtr,
      _kOpcodeChannelNumber,
      nullptr,
      pDataSize,
      ppData,
      nullptr,
    );
    if (r != _kErrorSuccess || ppData.value == nullptr) return null;
    final int ch = ppData.value.cast<Uint32>().value;
    WlanFreeMemory(ppData.value);
    return ch == 0 ? null : ch;
  } finally {
    calloc.free(pDataSize);
    calloc.free(ppData);
  }
}

/// Reads the BSS list and returns the connected link's RSSI + center frequency.
///
/// Match order, exact → broad, so the common single-link case is unchanged:
///   1. Exact BSSID match (non-MLO APs).
///   2. Same AP radio (shared first-5-octet prefix) — the Wi-Fi 7 MLO / MBSSID
///      case where the current-connection BSSID is the AP MLD address that never
///      beacons; selects the affiliated link on the operating channel.
///   3. Same SSID — last resort; selects the link on the operating channel, else
///      the strongest.
/// Returns null only when nothing advertises the connection at all (then
/// RSSI-dBm/channel/band stay null and the signal-quality % still shows).
/// Enumerates EVERY nearby BSS the first wireless interface can see, as the
/// `com.wlanpros.toolbox/ap_scan` payload the shared `ApScanSnapshot` consumes.
///
/// DARK PATH — NOT LIVE. Windows is deliberately excluded from
/// `ApScanService.isSupportedPlatform` and from `kNativeScanPlatforms`, so the
/// Nearby AP Scan tool does not appear on Windows and nothing calls this at
/// runtime. It exists so the enumeration is written and reviewable, ready to be
/// switched on AFTER it is executed against real hardware.
///
/// TODO(windows-verify): never executed. Confirm against a real wlanapi.dll and
/// a real wireless NIC that: the handle opens; an interface enumerates even when
/// NOT connected (this path deliberately does not require a connected
/// interface, unlike [readConnectedApFromNativeWifi]); WlanGetNetworkBssList
/// returns every visible BSS rather than only the connected network's;
/// `ulChCenterFrequency` really is kHz on 6 GHz radios as well as 2.4/5 GHz;
/// and WlanFreeMemory/WlanCloseHandle leave no leak.
///
/// UNRESOLVED BEFORE THIS COULD GO LIVE: Windows may return a STALE driver BSS
/// list unless a scan is requested first (`WlanScan`, which completes
/// asynchronously via a notification callback). This function does NOT call
/// `WlanScan`, so the list it returns is whatever the driver last cached. Wiring
/// it live without settling that would risk presenting stale results as fresh,
/// which is exactly the kind of unmeasured verdict this app must not state.
///
/// Throws [WifiInfoUnavailable] rather than fabricating a list.
List<Map<String, Object?>> enumerateNearbyBssFromNativeWifi() {
  final Pointer<Uint32> pdwNegotiated = calloc<Uint32>();
  final Pointer<IntPtr> phClientHandle = calloc<IntPtr>();
  Pointer<WLAN_INTERFACE_INFO_LIST> pIfList = nullptr;
  try {
    final int openResult = WlanOpenHandle(
      _kWlanClientVersion,
      nullptr,
      pdwNegotiated,
      phClientHandle,
    );
    if (openResult != _kErrorSuccess) {
      throw WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'WlanOpenHandle failed (error $openResult).',
      );
    }
    final int handle = phClientHandle.value;
    try {
      final Pointer<Pointer<WLAN_INTERFACE_INFO_LIST>> ppIfList =
          calloc<Pointer<WLAN_INTERFACE_INFO_LIST>>();
      try {
        final int enumResult = WlanEnumInterfaces(handle, nullptr, ppIfList);
        if (enumResult != _kErrorSuccess) {
          throw WifiInfoUnavailable(
            WifiInfoUnavailableReason.channelError,
            'WlanEnumInterfaces failed (error $enumResult).',
          );
        }
        pIfList = ppIfList.value;
      } finally {
        calloc.free(ppIfList);
      }

      if (pIfList.ref.dwNumberOfItems == 0) {
        throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'No wireless interface present.',
        );
      }

      // Scanning does NOT require a connected interface, so this takes the first
      // wireless interface rather than the first CONNECTED one.
      final Pointer<GUID> guidPtr = calloc<GUID>();
      try {
        guidPtr.ref.setGUID(pIfList.ref.InterfaceInfo[0].InterfaceGuid.toString());

        final Pointer<Pointer<WLAN_BSS_LIST>> ppBssList =
            calloc<Pointer<WLAN_BSS_LIST>>();
        Pointer<WLAN_BSS_LIST> pBssList = nullptr;
        try {
          final int bResult = WlanGetNetworkBssList(
            handle,
            guidPtr,
            nullptr,
            _kBssTypeInfrastructure,
            0,
            nullptr,
            ppBssList,
          );
          if (bResult != _kErrorSuccess) {
            throw WifiInfoUnavailable(
              WifiInfoUnavailableReason.channelError,
              'WlanGetNetworkBssList failed (error $bResult).',
            );
          }
          pBssList = ppBssList.value;
          final int n = pBssList.ref.dwNumberOfItems;
          final Pointer<WLAN_BSS_ENTRY> entriesBase =
              Pointer<WLAN_BSS_ENTRY>.fromAddress(
            pBssList.address + _kBssEntriesOffset,
          );
          return scannedApRowsFromBssCandidates(
            _decodeBssCandidates(pBssList, n, entriesBase),
          );
        } finally {
          if (pBssList != nullptr) {
            WlanFreeMemory(pBssList.cast());
          }
          calloc.free(ppBssList);
        }
      } finally {
        calloc.free(guidPtr);
      }
    } finally {
      if (pIfList != nullptr) {
        WlanFreeMemory(pIfList.cast());
      }
      WlanCloseHandle(handle, nullptr);
    }
  } finally {
    calloc.free(phClientHandle);
    calloc.free(pdwNegotiated);
  }
}

/// Decodes every WLAN_BSS_ENTRY row in a BSS list into plain Dart values.
///
/// Extracted so the connected-link path ([_queryConnectedBss]) and the nearby-AP
/// enumeration path ([enumerateNearbyBssFromNativeWifi]) read the list exactly
/// once, the same way. Rows whose BSSID cannot be decoded are dropped — there is
/// no honest identity for them.
List<WifiBssCandidate> _decodeBssCandidates(
  Pointer<WLAN_BSS_LIST> pBssList,
  int count,
  Pointer<WLAN_BSS_ENTRY> entriesBase,
) {
  final List<WifiBssCandidate> candidates = <WifiBssCandidate>[];
  for (int i = 0; i < count; i++) {
    final WLAN_BSS_ENTRY entry = pBssList.ref.wlanBssEntries[i];
    final String? bssid = _decodeBssid(entry.dot11Bssid);
    if (bssid == null) continue;
    candidates.add(WifiBssCandidate(
      bssid: bssid.toLowerCase(),
      ssid: _decodeSsid(entry.dot11Ssid),
      rssiDbm: entry.lRssi,
      centerFreqKhz: entry.ulChCenterFrequency,
      informationElements: _readIeBlob(entriesBase + i),
    ));
  }
  return candidates;
}

_BssSnapshot? _queryConnectedBss(
  int handle,
  Pointer<GUID> guidPtr,
  _ConnectionSnapshot conn,
) {
  final Pointer<Pointer<WLAN_BSS_LIST>> ppBssList =
      calloc<Pointer<WLAN_BSS_LIST>>();
  Pointer<WLAN_BSS_LIST> pBssList = nullptr;
  try {
    // Passing a null DOT11_SSID + infrastructure BSS type returns all BSS
    // entries the driver currently has; we then match the connected link.
    final int bResult = WlanGetNetworkBssList(
      handle,
      guidPtr,
      nullptr,
      _kBssTypeInfrastructure,
      0,
      nullptr,
      ppBssList,
    );
    if (bResult != _kErrorSuccess) {
      // The BSS list is an ENRICHMENT (real dBm + channel); its absence is not
      // fatal. Degrade honestly to signal-quality only.
      return null;
    }
    pBssList = ppBssList.value;
    final int n = pBssList.ref.dwNumberOfItems;

    // A real Pointer<WLAN_BSS_ENTRY> to entry 0, used ONLY to read each entry's
    // IE blob by pointer arithmetic (the RSSI/channel/band fields keep reading
    // through the proven win32 inline-array accessor below, so a wrong IE offset
    // cannot regress them). See [_kBssEntriesOffset].
    final Pointer<WLAN_BSS_ENTRY> entriesBase =
        Pointer<WLAN_BSS_ENTRY>.fromAddress(
      pBssList.address + _kBssEntriesOffset,
    );

    final List<WifiBssCandidate> candidates =
        _decodeBssCandidates(pBssList, n, entriesBase);
    if (candidates.isEmpty) return null;

    final int? operatingChannel = _queryOperatingChannel(handle, guidPtr);

    // Pure precedence (exact → same-radio → same-SSID), extracted so it is
    // unit-testable off Windows. See [selectConnectedLink].
    final WifiBssCandidate? link = selectConnectedLink(
      candidates,
      connBssid: conn.bssid,
      connSsid: conn.ssid,
      operatingChannel: operatingChannel,
    );
    if (link != null) {
      // Parse the operating channel width + AP-advertised country from the
      // SELECTED link's IE blob (pure TLV walk; null when absent or malformed).
      final Uint8List? ies = link.informationElements;
      return _BssSnapshot(
        rssiDbm: link.rssiDbm,
        centerFreqKhz: link.centerFreqKhz,
        channelWidthMhz: ies == null ? null : channelWidthFromIes(ies),
        countryCode: ies == null ? null : countryCodeFromIes(ies),
      );
    }

    return null;
  } finally {
    if (pBssList != nullptr) {
      WlanFreeMemory(pBssList.cast());
    }
    calloc.free(ppBssList);
  }
}

/// Copies the IE blob out of one WLAN_BSS_ENTRY into a Dart-owned [Uint8List].
///
/// `ulIeOffset` is the byte offset of the IE data FROM THE START OF THE ENTRY,
/// and `ulIeSize` its length, so the blob is `entryPtr + ulIeOffset` for
/// `ulIeSize` bytes (per the Microsoft Native Wifi sample). Copying detaches the
/// bytes from native memory so they survive WlanFreeMemory and parse purely.
/// Returns null for an empty/absent blob.
///
/// TODO(windows-verify): confirm `ulIeOffset` is entry-relative (not list-
/// relative) on the real struct and that the copied bytes begin at a valid
/// TLV (id,len,...). A wrong base only nulls width/country, never RSSI.
Uint8List? _readIeBlob(Pointer<WLAN_BSS_ENTRY> entryPtr) {
  final int offset = entryPtr.ref.ulIeOffset;
  final int size = entryPtr.ref.ulIeSize;
  if (offset <= 0 || size <= 0) return null;
  final Pointer<Uint8> iePtr = entryPtr.cast<Uint8>() + offset;
  final Uint8List out = Uint8List(size);
  for (int j = 0; j < size; j++) {
    out[j] = iePtr[j];
  }
  return out;
}

/// Reads the device adapter MAC for the connected interface via
/// GetAdaptersAddresses (iphlpapi), matched to [guidPtr] by GUID.
///
/// The WLAN interface GUID equals the adapter's `AdapterName` string (the GUID
/// in `{...}` form) that GetAdaptersAddresses returns, so we match on it
/// case-insensitively. Returns the burned-in/active device MAC as lowercase
/// colon-hex, or null when the adapter list cannot be read or no GUID matches
/// (honest — never the AP BSSID, never a fabricated address).
///
/// Frees every buffer it allocates on every exit path.
///
/// TODO(windows-verify): confirm `AdapterName` matches `GUID.toString()`'s
/// `{...}` form (case aside) and that `PhysicalAddress[0..5]` is the Wi-Fi MAC.
String? _queryHardwareAddress(Pointer<GUID> guidPtr) {
  final String targetGuid = guidPtr.ref.toString().toLowerCase();

  final Pointer<Uint32> pSize = calloc<Uint32>();
  Pointer<IP_ADAPTER_ADDRESSES_LH> buf = nullptr;
  try {
    // Sizing call: a null buffer returns ERROR_BUFFER_OVERFLOW with the byte
    // count written to pSize.
    int result = GetAdaptersAddresses(
      _kAfUnspec,
      _kGaaFlags,
      nullptr,
      nullptr,
      pSize,
    );
    if (result != _kErrorBufferOverflow && result != _kErrorSuccess) {
      return null;
    }
    if (pSize.value == 0) return null;

    buf = calloc<Uint8>(pSize.value).cast<IP_ADAPTER_ADDRESSES_LH>();
    result = GetAdaptersAddresses(
      _kAfUnspec,
      _kGaaFlags,
      nullptr,
      buf,
      pSize,
    );
    if (result != _kErrorSuccess) return null;

    for (
      Pointer<IP_ADAPTER_ADDRESSES_LH> cur = buf;
      cur != nullptr;
      cur = cur.ref.Next
    ) {
      final Pointer<Utf8> namePtr = cur.ref.AdapterName;
      if (namePtr == nullptr) continue;
      final String name = namePtr.toDartString().toLowerCase();
      if (name != targetGuid) continue;

      final int len = cur.ref.PhysicalAddressLength;
      if (len < 6) return null; // not an Ethernet/Wi-Fi MAC
      final List<int> bytes = <int>[
        for (int i = 0; i < 6; i++) cur.ref.PhysicalAddress[i],
      ];
      return formatMacBytes(bytes);
    }
    return null;
  } finally {
    if (buf != nullptr) calloc.free(buf);
    calloc.free(pSize);
  }
}

/// Folds the connection + BSS snapshots into the shared [WifiInfo] contract.
///
/// Field availability mirrors Android's honest posture, plus Windows extras:
///   * RSSI dBm  — from the BSS entry (real dBm); null when no BSS match.
///   * Tx + Rx rate — from the association attrs (Windows supplies BOTH, unlike
///     macOS which has no Rx). Kbps → Mbps.
///   * channel + band — derived from the BSS center frequency.
///   * noise / SNR — NOT exposed by Native Wifi → null, never derived (GL-005).
///   * channelWidthMhz — parsed from the BSS IE blob (HT/VHT/HE/EHT Operation);
///     null when no operation element advertises a width.
///   * interfaceName — the friendly adapter description from WLAN_INTERFACE_INFO.
///   * hardwareAddress — the device adapter MAC from GetAdaptersAddresses.
///   * countryCode — the AP-advertised Country element, when present.
WifiInfo _composeWifiInfo(
  _ConnectionSnapshot conn,
  _BssSnapshot? bss, {
  required String? interfaceName,
  required String? hardwareAddress,
}) {
  final int? channel =
      bss == null ? null : _frequencyKhzToChannel(bss.centerFreqKhz);
  final String? band =
      bss == null ? null : _frequencyKhzToBand(bss.centerFreqKhz);

  // ulTxRate / ulRxRate are in units of Kbps. Mbps = Kbps / 1000. A 0 value
  // means "not reported" → null, never a fabricated 0 Mbps.
  final double? txMbps =
      conn.txRateKbps > 0 ? conn.txRateKbps / 1000.0 : null;
  final double? rxMbps =
      conn.rxRateKbps > 0 ? conn.rxRateKbps / 1000.0 : null;

  return WifiInfo(
    // The friendly adapter description from WLAN_INTERFACE_INFO (e.g. "Intel(R)
    // Wi-Fi 6E AX211 160MHz"), not an opaque GUID.
    interfaceName: interfaceName,
    ssid: conn.ssid,
    bssid: conn.bssid,
    rssiDbm: bss?.rssiDbm, // real dBm from the BSS entry, or null.
    // Native Wifi exposes no noise floor → SNR cannot be computed (GL-005).
    noiseDbm: null,
    snrDb: null,
    txRateMbps: txMbps,
    rxRateMbps: rxMbps, // Windows DOES supply Rx (macOS does not).
    phyMode: _phyTypeToStandard(conn.phyType),
    channel: channel,
    // Operating width from the BSS HT/VHT/HE/EHT Operation IEs; null when none
    // advertises one.
    channelWidthMhz: bss?.channelWidthMhz,
    band: band,
    // AP-advertised Country element (element ID 7); null when the AP omits it.
    countryCode: bss?.countryCode,
    // The device adapter MAC from GetAdaptersAddresses (NOT the AP BSSID); null
    // when the GUID match fails.
    hardwareAddress: hardwareAddress,
    securityToken: conn.securityToken,
    poweredOn: true, // a current-connection read implies the radio is on.
    locationAuthorized: true, // Windows Native Wifi needs no Location grant.
  );
}

// ── Decoders + mappers (pure, would be unit-testable if not for the win32
// struct inputs; the value→token/standard/band helpers below ARE pure and are
// exercised by windows_wifi_mapping_test.dart). ────────────────────────────

/// DOT11_SSID is length-prefixed: `uSSIDLength` valid bytes in `ucSSID[32]`.
/// Decoded as UTF-8 (the common case); an empty/oversize length → null.
String? _decodeSsid(DOT11_SSID ssid) {
  final int len = ssid.uSSIDLength;
  if (len <= 0 || len > 32) return null;
  final List<int> bytes = <int>[for (int i = 0; i < len; i++) ssid.ucSSID[i]];
  try {
    return _utf8OrLatin1(bytes);
  } catch (_) {
    return null;
  }
}

/// 6 raw BSSID bytes → lowercase colon-separated hex (`a4:83:e7:00:11:22`).
String? _decodeBssid(Array<Uint8> mac) {
  final List<String> parts = <String>[
    for (int i = 0; i < 6; i++) mac[i].toRadixString(16).padLeft(2, '0'),
  ];
  final String joined = parts.join(':');
  return joined == '00:00:00:00:00:00' ? null : joined;
}

/// Maps a dot11 PHY type to the 802.11 designation the [WifiInfo] model carries.
/// ConnectedAp._macStandardLabel folds in the Wi-Fi N marketing name from this.
String? phyTypeToStandard(int phyType) => _phyTypeToStandard(phyType);

String? _phyTypeToStandard(int phyType) {
  return switch (phyType) {
    _kPhyTypeDsss || _kPhyTypeHrdsss => '802.11b',
    _kPhyTypeOfdm => '802.11a',
    _kPhyTypeErp => '802.11g',
    _kPhyTypeHt => '802.11n',
    _kPhyTypeVht => '802.11ac',
    _kPhyTypeHe => '802.11ax',
    _kPhyTypeEht => '802.11be',
    _ => null,
  };
}

/// Maps a DOT11_AUTH_ALGO_* value to the security TOKEN the shared
/// [WifiSecurityClassifier] understands. Windows exposes the FINE auth algorithm
/// (WPA2 vs WPA3, Personal vs Enterprise) — richer than iOS's coarse view, on a
/// par with macOS. Cipher could refine WEP-vs-open further but the auth algo is
/// sufficient for the model's label set.
String? securityTokenForAuthAlgo(int authAlgo) => _securityToken(authAlgo);

String? _securityToken(int authAlgo) {
  return switch (authAlgo) {
    _kAuthOpen => 'open',
    _kAuthSharedKey => 'wep',
    _kAuthWpa => 'wpaEnterprise',
    _kAuthWpaPsk => 'wpaPersonal',
    _kAuthRsna => 'wpa2Enterprise',
    _kAuthRsnaPsk => 'wpa2Personal',
    _kAuthWpa3 || _kAuthWpa3Ent => 'wpa3Enterprise',
    _kAuthWpa3Sae => 'wpa3Personal',
    _kAuthOwe => 'owe',
    _ => 'unknown',
  };
}

/// Center frequency (kHz) → 802.11 channel number. Covers 2.4 / 5 / 6 GHz.
/// Pure; unit-tested. Returns null for a frequency outside the known plans.
int? frequencyKhzToChannel(int freqKhz) => _frequencyKhzToChannel(freqKhz);

int? _frequencyKhzToChannel(int freqKhz) {
  final int mhz = (freqKhz / 1000).round();
  // 2.4 GHz: ch1=2412 … ch13=2472, ch14=2484.
  if (mhz == 2484) return 14;
  if (mhz >= 2412 && mhz <= 2472) return ((mhz - 2412) ~/ 5) + 1;
  // 5 GHz: ch = (MHz − 5000) / 5.
  if (mhz >= 5160 && mhz <= 5885) return (mhz - 5000) ~/ 5;
  // 6 GHz (Wi-Fi 6E/7): ch = (MHz − 5950) / 5, ch1=5955 … .
  if (mhz >= 5955 && mhz <= 7115) return (mhz - 5950) ~/ 5;
  return null;
}

/// Center frequency (kHz) → human band label, matching the model's set.
String? frequencyKhzToBand(int freqKhz) => _frequencyKhzToBand(freqKhz);

String? _frequencyKhzToBand(int freqKhz) {
  final int mhz = (freqKhz / 1000).round();
  if (mhz >= 2400 && mhz < 2500) return '2.4 GHz';
  if (mhz >= 4900 && mhz < 5900) return '5 GHz';
  if (mhz >= 5925 && mhz <= 7125) return '6 GHz';
  return null;
}

/// Decode bytes as UTF-8, falling back to Latin-1 for a non-UTF-8 SSID. Kept
/// tiny and dependency-free.
String _utf8OrLatin1(List<int> bytes) {
  try {
    return const Utf8Decoder(allowMalformed: false).convert(bytes);
  } catch (_) {
    return const Latin1Decoder().convert(bytes);
  }
}

// ── Pure helpers exercised by windows_wifi_ie_test.dart. None touches a win32
// symbol, so they run on any host. ──────────────────────────────────────────

/// Formats the first 6 octets of a device MAC as lowercase colon-hex
/// (`a4:83:e7:00:11:22`). Returns null for a short input or the all-zero MAC
/// (which Native Wifi/iphlpapi can hand back for a down adapter) — never a
/// fabricated address.
String? formatMacBytes(List<int> bytes) {
  if (bytes.length < 6) return null;
  final List<String> parts = <String>[
    for (int i = 0; i < 6; i++) (bytes[i] & 0xff).toRadixString(16).padLeft(2, '0'),
  ];
  final String joined = parts.join(':');
  return joined == '00:00:00:00:00:00' ? null : joined;
}

/// Resolves the operating channel width in MHz ({20,40,80,160,320}) from the
/// operation IEs in [ies], or null when none advertises one.
///
/// Priority newest → oldest, since the most advanced operation element reflects
/// the actual operating width: EHT Operation (Wi-Fi 7, ≤320) → HE Operation
/// (6 GHz width) → VHT Operation (80/160/80+80) → HT Operation (20/40).
int? channelWidthFromIes(Uint8List ies) {
  final Uint8List? eht = findInformationElement(
    ies,
    _kEidExtended,
    extId: _kExtEhtOperation,
  );
  if (eht != null) {
    final int? w = _ehtWidth(eht);
    if (w != null) return w;
  }

  final Uint8List? he = findInformationElement(
    ies,
    _kEidExtended,
    extId: _kExtHeOperation,
  );
  if (he != null) {
    final int? w = _heWidth(he);
    if (w != null) return w;
  }

  final Uint8List? vht = findInformationElement(ies, _kEidVhtOperation);
  if (vht != null) {
    final int? w = _vhtWidth(vht);
    if (w != null) return w;
  }

  final Uint8List? ht = findInformationElement(ies, _kEidHtOperation);
  if (ht != null) {
    return _htWidth(ht);
  }

  return null;
}

/// HT Operation (element 61): the STA Channel Width bit (0x04) of HT Operation
/// Information subset 1 (data byte 1) distinguishes 40 from 20 MHz.
int? _htWidth(Uint8List d) {
  if (d.length < 2) return null;
  return (d[1] & 0x04) != 0 ? 40 : 20;
}

/// VHT Operation (element 192): byte 0 is the Channel Width field; bytes 1–2 are
/// the center-frequency segment-0 / segment-1 indices used to tell 160 from
/// 80+80 when the width field is the (legacy) value 1.
int? _vhtWidth(Uint8List d) {
  if (d.isEmpty) return null;
  switch (d[0]) {
    case 0:
      return null; // 20/40 — defer to the HT Operation element.
    case 1:
      // 80, 160, or 80+80: a zero segment-1 index (data byte 2) means a single
      // 80 MHz segment; a non-zero one means a 160 MHz span (contiguous or
      // 80+80).
      if (d.length >= 3) {
        return d[2] == 0 ? 80 : 160;
      }
      return 80;
    case 2:
      return 160; // deprecated explicit 160.
    case 3:
      return 160; // 80+80.
    default:
      return null;
  }
}

/// HE Operation (extended element 36, ext-id stripped): the operating width for
/// a 6 GHz BSS lives in the optional 6 GHz Operation Information field, gated by
/// presence bits in the 3-byte HE Operation Parameters. A 5 GHz HE BSS instead
/// carries an optional VHT Operation Information field, decoded via [_vhtWidth].
int? _heWidth(Uint8List d) {
  if (d.length < 6) return null;
  final int params = d[0] | (d[1] << 8) | (d[2] << 16);
  final bool vhtPresent = (params & (1 << 14)) != 0;
  final bool coHosted = (params & (1 << 15)) != 0;
  final bool sixGhzPresent = (params & (1 << 17)) != 0;

  // Fixed prefix: HE Operation Parameters (3) + BSS Color (1) + Basic HE-MCS
  // And Nss Set (2) = 6 bytes.
  int offset = 6;
  Uint8List? vhtInfo;
  if (vhtPresent) {
    if (offset + 3 <= d.length) {
      vhtInfo = Uint8List.sublistView(d, offset, offset + 3);
    }
    offset += 3;
  }
  if (coHosted) offset += 1;

  if (sixGhzPresent && offset + 2 <= d.length) {
    // 6 GHz Operation Information: [primary][control][seg0][seg1][min-rate].
    // The Control field (byte 1) carries the Channel Width.
    return _sixGhzWidth(d[offset + 1]);
  }
  if (vhtInfo != null) return _vhtWidth(vhtInfo);
  return null;
}

/// HE/EHT 6 GHz Operation Information Control field → width. The Channel Width
/// subfield is bits 0–1: 0=20, 1=40, 2=80, 3=160/80+80 (both a 160 MHz span).
int? _sixGhzWidth(int control) {
  switch (control & 0x03) {
    case 0:
      return 20;
    case 1:
      return 40;
    case 2:
      return 80;
    case 3:
      return 160;
    default:
      return null;
  }
}

/// EHT Operation (extended element 106, ext-id stripped): when the EHT Operation
/// Information field is present (Parameters bit 0), its Control field carries the
/// Channel Width (bits 0–2): 0=20, 1=40, 2=80, 3=160, 4=320.
int? _ehtWidth(Uint8List d) {
  if (d.isEmpty) return null;
  final bool infoPresent = (d[0] & 0x01) != 0;
  if (!infoPresent) return null;
  // EHT Operation Parameters (1) + Basic EHT-MCS And Nss Set (4) = 5.
  const int infoStart = 5;
  if (infoStart >= d.length) return null;
  switch (d[infoStart] & 0x07) {
    case 0:
      return 20;
    case 1:
      return 40;
    case 2:
      return 80;
    case 3:
      return 160;
    case 4:
      return 320;
    default:
      return null;
  }
}

/// Country element (element 7): the first two bytes are the ASCII country code
/// (the third byte is a regulatory class indicator we ignore). Returns the
/// uppercase 2-letter code, or null when absent/non-alphabetic.
String? countryCodeFromIes(Uint8List ies) {
  final Uint8List? country = findInformationElement(ies, _kEidCountry);
  if (country == null || country.length < 2) return null;
  bool isAlpha(int c) =>
      (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
  if (!isAlpha(country[0]) || !isAlpha(country[1])) return null;
  return String.fromCharCodes(<int>[country[0], country[1]]).toUpperCase();
}
