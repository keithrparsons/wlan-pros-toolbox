// Web stub for windows_arp_ffi.dart.
//
// windows_arp_ffi.dart imports dart:ffi + package:ffi, neither of which exists
// on the web target — compiling it for web fails with "dart:ffi unsupported
// without --enable-experimental-ffi". The Windows ARP reader is only ever
// reached after a Platform.isWindows guard (see arp_reader.dart's
// platformArpReader()), and the Network Discovery engine never runs on web at
// all (the debug screen is kIsWeb-gated). This stub exists purely to satisfy
// the conditional import and keep `flutter build web` compiling, mirroring the
// existing windows_wifi_ffi_web_stub.dart in this same layer.
//
// GUARD NOTE: selected via `if (dart.library.io)` in arp_reader.dart — the real
// FFI file is imported only when dart:io (and therefore dart:ffi) is available,
// i.e. on native targets. `dart.library.html` is NOT used: it evaluates false
// on the Flutter 3.44 / Dart 3.12 web target (dart:html is deprecated in favor
// of dart:js_interop), which would silently fall a `dart.library.html` guard
// through to the FFI default and break the web build.

/// Web-target stand-in for [WindowsArpReadException] from windows_arp_ffi.dart.
/// Never thrown on web (the reader is unreachable there); present only so the
/// conditional import resolves and arp_reader.dart's catch clause type-checks.
class WindowsArpReadException implements Exception {
  const WindowsArpReadException(this.message);

  final String message;

  @override
  String toString() => 'WindowsArpReadException: $message';
}

/// Web-target stand-in for the Windows iphlpapi GetIpNetTable FFI read. Never
/// called on web (the caller guards on Platform.isWindows first, and the engine
/// is kIsWeb-gated); if it ever were reached it throws the same exception the
/// real reader throws on a genuine failure, so arp_reader.dart maps it to an
/// honest unavailable result rather than a fabricated MAC — behavior identical.
List<MapEntry<String, String>> readArpTableViaIpHlpApi() {
  throw const WindowsArpReadException(
    'Windows ARP table is not available on the web platform.',
  );
}
