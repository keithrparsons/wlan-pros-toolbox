// Cellular Information platform-source seam (TICKET-02).
//
// Mirrors [WifiInfoSourceResolver]: one tool, one normalized [CellularInfo]
// model, and a platform-selected data source behind THIS seam. The screen asks
// the resolver which source backs the current platform and renders accordingly.
//
// Unlike Wi-Fi, cellular has exactly ONE live source:
//
//   * iOS   → [CellularInfoSource.iosShortcuts]: the companion-Shortcut stack
//             (the stock "Get Network Details" action, cellular branch, handed
//             over the App Group bridge). The only source that yields data.
//   * macOS → [CellularInfoSource.unsupported]: Macs ship with no cellular
//             radio, so the tile shows an honest "not available on macOS" state.
//   * Android / Windows → [CellularInfoSource.unsupported]: no bridge built; a
//             native path would need CoreTelephony-equivalent permissions and is
//             out of scope for this iOS-parallel tool.
//   * web → [CellularInfoSource.web]: download-the-app fallback.
//
// There is intentionally NO native CoreTelephony adapter: CTCarrier is
// deprecated and returns junk, and signal strength is private-API-only. Data
// comes only via the Shortcuts bridge (see [CellularInfo]).

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Which data source backs the Cellular Information tool on the current
/// platform.
enum CellularInfoSource {
  /// iOS companion-Shortcut stack (install flow + one-shot read). The only
  /// source that delivers a [CellularInfo].
  iosShortcuts,

  /// A native platform with no cellular data path: macOS (no radio), Android,
  /// Windows, desktop Linux. Honest "not available on this platform" state.
  unsupported,

  /// Running in a browser — download-the-app fallback.
  web,
}

/// Resolves the per-platform Cellular Information data source.
/// `defaultTargetPlatform` is web-safe (no `dart:io`), so this is readable in
/// `build`.
class CellularInfoSourceResolver {
  CellularInfoSourceResolver._();

  /// The data source for the current platform.
  ///
  /// [platformOverride] lets tests assert each branch without a real platform.
  static CellularInfoSource resolve({TargetPlatform? platformOverride}) {
    if (kIsWeb) return CellularInfoSource.web;
    final TargetPlatform platform = platformOverride ?? defaultTargetPlatform;
    return switch (platform) {
      TargetPlatform.iOS => CellularInfoSource.iosShortcuts,
      // Everything else — macOS included — has no cellular data path.
      _ => CellularInfoSource.unsupported,
    };
  }
}
