// Web stub for windows_wifi_ffi.dart.
//
// windows_wifi_ffi.dart imports dart:ffi + package:win32, neither of which
// exists on the web target — compiling it for web fails with "Only JS interop
// members may be 'external'". The Native Wifi reader is only ever called after a
// Platform.isWindows guard (see windows_wifi_reader.dart), so on web this symbol
// is never reached at runtime. This stub exists purely to satisfy the
// conditional import and keep `flutter build web` compiling, mirroring the
// existing wifi_info_service_web_stub.dart pattern used in this same layer.

import 'wifi_info_service.dart'
    show WifiInfo, WifiInfoUnavailable, WifiInfoUnavailableReason;

/// Web-target stand-in for the Windows Native Wifi reader. Never called on web
/// (the caller guards on Platform.isWindows first); if it ever were reached it
/// throws the same unsupported-platform signal the real reader throws off
/// Windows, so behavior is identical.
WifiInfo readConnectedApFromNativeWifi() {
  throw const WifiInfoUnavailable(
    WifiInfoUnavailableReason.unsupportedPlatform,
  );
}
