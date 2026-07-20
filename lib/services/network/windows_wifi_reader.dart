// Windows Wi-Fi Information reader — pure dart:ffi against wlanapi.dll via the
// `win32` package's Native Wifi bindings. NO C++ MethodChannel.
//
// feat/windows-port-prep (2026-06-11). This is the DECIDED primary approach from
// the 2026-06-08 Windows readiness report (§3): reuse the Android Dart seam and
// read the connected AP straight from the Win32 Native Wifi API in Dart, so the
// whole Windows Wi-Fi bridge is Dart (no native runner code, no extra build
// step). The reader produces the SAME [WifiInfo] shape the macOS/Android method
// channel produces, so [ConnectedAp.fromWindowsWifiInfo] maps it with the
// existing factory pattern and the screen renders it as a snapshot source.
//
// FFI call flow (matches the Microsoft Learn Native Wifi sample, retargeted to
// Dart pointers):
//   1. WlanOpenHandle            → a client handle to the WLAN service.
//   2. WlanEnumInterfaces        → the wireless interfaces (WLAN_INTERFACE_INFO).
//      Pick the first one in the `connected` state.
//   3. WlanQueryInterface(current_connection)
//                                → WLAN_CONNECTION_ATTRIBUTES: SSID, BSSID, PHY
//                                  type, signal quality (0–100), Rx rate, Tx
//                                  rate, plus WLAN_SECURITY_ATTRIBUTES (auth +
//                                  cipher algorithm) for the security type.
//   4. WlanGetNetworkBssList     → WLAN_BSS_ENTRY for the connected BSSID:
//                                  lRssi (REAL dBm, not 0–100), ulChCenterFreq
//                                  (→ channel + band), and the IE blob, which is
//                                  parsed for channel width (HT/VHT/HE/EHT
//                                  Operation elements). This is the one field
//                                  macOS supplies that signal-quality alone
//                                  cannot: a true dBm RSSI.
//   5. WlanFreeMemory on every buffer the API allocated, WlanCloseHandle at the
//      end. Pointer/free discipline is the only real hazard of the FFI path.
//
// HONESTY (GL-005 / GL-008): noise floor and SNR are NOT exposed by the public
// Native Wifi API, exactly like Android — so they stay null and are never
// derived. Channel WIDTH IS parsed from the connected AP's beacon IEs (HT/VHT/
// HE/EHT Operation elements) in windows_wifi_ffi.dart, so it resolves per
// network; it stays null only when that AP's beacon advertised no width element,
// the TLV was malformed, or the IE-blob offset still needs device verification
// (see the `TODO(windows-verify)` markers). Everything else
// (SSID/BSSID/RSSI-dBm/Tx+Rx rate/PHY/channel/band/security) the API supplies
// directly.
//
// PLATFORM GUARD: every entry point is gated on Platform.isWindows. On any other
// OS the reader throws [WifiInfoUnavailable] WITHOUT touching a win32 symbol, so
// `package:win32` is never loaded off Windows and this file is inert on
// iOS/macOS/Android. `dart:io` is import-guarded for web the same way the rest
// of the network layer guards it.
//
// VERIFICATION STATUS: written-not-executed. The FFI struct marshalling, the
// pointer/free discipline, and every field mapping below can only be confirmed
// against a real wlanapi.dll + a real wireless NIC. Each runtime-truth point is
// marked `// TODO(windows-verify):`. `dart:ffi` cannot run on macOS, so this
// module is `flutter analyze`-clean here but executed for the first time on the
// 26th.

// Guard dart:io for web exactly like wifi_info_service.dart does: Platform is
// only ever read on a native target, never on web.
import 'dart:io' if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'wifi_info_service.dart'
    show WifiInfo, WifiInfoUnavailable, WifiInfoUnavailableReason;
// Default to the web stub; pull in the real dart:ffi/win32 reader only when
// dart:io (hence dart:ffi) is available — i.e. on native targets. The previous
// `if (dart.library.html)` key evaluated false on the Flutter 3.44 / Dart 3.12
// web build (dart:html is deprecated for dart:js_interop), so it silently fell
// through to the windows_wifi_ffi.dart default and dragged dart:ffi into the
// web target, breaking `flutter build web`. `if (dart.library.io)` selects the
// stub on web and the FFI file on every native platform.
import 'windows_wifi_ffi_web_stub.dart'
    if (dart.library.io) 'windows_wifi_ffi.dart'
    show readConnectedApFromNativeWifi, enumerateNearbyBssFromNativeWifi;

// The win32 surface lives entirely in windows_wifi_ffi.dart. This wrapper is the
// platform guard: readConnectedApFromNativeWifi() is only ever called once the
// Platform.isWindows check has passed, so no win32 symbol is touched — and the
// wlanapi.dll is never loaded — off Windows. The reader is therefore inert and
// `flutter analyze`-clean on iOS / macOS / Android / web.

/// Reads the connected Wi-Fi access point on Windows via the Native Wifi API.
///
/// Returns a [WifiInfo] with the same field contract the macOS/Android channel
/// returns, so [ConnectedAp.fromWindowsWifiInfo] maps it unchanged.
///
/// Throws [WifiInfoUnavailable]:
///   * [WifiInfoUnavailableReason.unsupportedPlatform] off Windows (no win32
///     symbol is touched), or
///   * [WifiInfoUnavailableReason.channelError] when the Native Wifi API returns
///     an error, no wireless interface is present, or none is connected.
///
/// Never fabricates a reading.
class WindowsWifiReader {
  /// [isWindowsOverride] lets tests assert the off-Windows guard without a real
  /// platform. Defaults to the host OS check.
  WindowsWifiReader({bool? isWindowsOverride})
      : _isWindows = isWindowsOverride ?? _hostIsWindows();

  final bool _isWindows;

  static bool _hostIsWindows() {
    if (kIsWeb) return false;
    return platform_io.Platform.isWindows;
  }

  /// True when this reader can run on the current platform.
  bool get isSupported => _isWindows;

  /// Reads a fresh connected-AP snapshot.
  Future<WifiInfo> fetch() async {
    if (!_isWindows) {
      throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.unsupportedPlatform,
        'Windows Native Wifi is only available on Windows.',
      );
    }
    // TODO(windows-verify): first real execution of the FFI path. Confirm the
    // handle opens, an interface enumerates, the connected-connection query and
    // the BSS-list read both succeed against a real wlanapi.dll + wireless NIC,
    // and that WlanFreeMemory/WlanCloseHandle leave no leak (run under the
    // win32 ffi_leak_tracker if a leak is suspected).
    return readConnectedApFromNativeWifi();
  }

  /// Enumerates EVERY nearby BSS as `com.wlanpros.toolbox/ap_scan` payload rows
  /// — the same row shape the Android and macOS channels return, so the shared
  /// `ScannedAp` model would consume them unchanged.
  ///
  /// DARK PATH — NOT LIVE, by explicit decision. Windows is excluded from
  /// `ApScanService.isSupportedPlatform` and from `kNativeScanPlatforms`, so the
  /// Nearby AP Scan tool does not appear on Windows and nothing calls this. It
  /// is written and reviewable, waiting on real-hardware verification.
  ///
  /// TODO(windows-verify): see [enumerateNearbyBssFromNativeWifi] for the exact
  /// list of claims that have never been executed, including whether the driver
  /// BSS list is stale without a preceding `WlanScan`. Do NOT add Windows to
  /// the supported platforms until those are confirmed on real hardware
  /// ([[feedback_gate_until_clean]]).
  Future<List<Map<String, Object?>>> scanNearbyBss() async {
    if (!_isWindows) {
      throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.unsupportedPlatform,
        'Windows Native Wifi is only available on Windows.',
      );
    }
    return enumerateNearbyBssFromNativeWifi();
  }
}
