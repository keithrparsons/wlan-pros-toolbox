// Web stub for the dart:io conditional import used by wifi_info_service.dart.
//
// On web there is no dart:io Platform. This stub provides a matching Platform
// shape so the conditional import resolves, but it is never actually read at
// runtime: the service guards every access behind kIsWeb. The value is a
// harmless placeholder that keeps isSupportedPlatform false on web.

/// Minimal stand-in for dart:io Platform on web.
class Platform {
  Platform._();

  /// Always an empty string on web; the service treats this as unsupported.
  static String get operatingSystem => '';

  /// Always false on web (there is no host OS). The consumers that read this
  /// (the Windows Wi-Fi reader, the DTMF playback gate) guard on kIsWeb first,
  /// so this stub value is never the deciding factor — it only keeps the
  /// conditional import resolving on the web target.
  static bool get isWindows => false;
}
