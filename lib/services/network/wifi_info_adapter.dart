// Wi-Fi Information platform-adapter seam (TICKET-04).
//
// One Wi-Fi tool, one normalized [ConnectedAp] model, and a platform-selected
// data source behind THIS seam. The screen never imports a platform's service
// directly — it asks [WifiInfoAdapter.forPlatform] for the right adapter and
// renders whatever capabilities that adapter declares.
//
// Two adapters are wired today; the other platforms are an honest seam only:
//
//   * macOS → [MacWifiInfoAdapter]  over CoreWLAN (WifiInfoService).
//             Pull-only snapshot + a Location-permission flow. No streaming.
//   * iOS   → handled by the Shortcuts stack (WiFiDetailsBridge +
//             WifiMonitorController) which the screen drives directly because it
//             carries an install flow + live streaming the snapshot seam does
//             not model. The adapter for iOS therefore reports
//             [WifiInfoSource.iosShortcuts] so the screen routes to that stack.
//   * Android / Windows → [WifiInfoSource.unsupported]: clean seam, honest
//             "coming later" state. NOT built in this ticket.
//   * web → [WifiInfoSource.web]: download-the-app fallback.
//
// Keeping the iOS streaming stack as its own branch (rather than forcing it
// through a pull-only adapter) is deliberate: a snapshot adapter cannot express
// "install a Shortcut, then Start/Stop a live push stream" without leaking that
// shape into every platform. The seam's job is to pick the source honestly; the
// screen folds the iOS-only affordances behind the iOS source.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'connected_ap.dart';
import 'wifi_info_service.dart';

/// Which data source backs the Wi-Fi Information tool on the current platform.
enum WifiInfoSource {
  /// macOS CoreWLAN snapshot via [MacWifiInfoAdapter].
  macosCoreWlan,

  /// iOS companion-Shortcut stack (install flow + live streaming). The screen
  /// drives WiFiDetailsBridge / WifiMonitorController directly for this source.
  iosShortcuts,

  /// A native platform with no Wi-Fi adapter yet (Android, Windows, desktop
  /// Linux). Honest "coming in a later update" state.
  unsupported,

  /// Running in a browser — download-the-app fallback.
  web,
}

/// Resolves the per-platform Wi-Fi data source. `defaultTargetPlatform` is
/// web-safe (it does not import `dart:io`), so this is readable in `build`.
class WifiInfoSourceResolver {
  WifiInfoSourceResolver._();

  /// The data source for the current platform.
  ///
  /// [platformOverride] lets tests assert each branch without a real platform.
  static WifiInfoSource resolve({TargetPlatform? platformOverride}) {
    if (kIsWeb) return WifiInfoSource.web;
    final TargetPlatform platform = platformOverride ?? defaultTargetPlatform;
    return switch (platform) {
      TargetPlatform.macOS => WifiInfoSource.macosCoreWlan,
      TargetPlatform.iOS => WifiInfoSource.iosShortcuts,
      _ => WifiInfoSource.unsupported,
    };
  }
}

/// A snapshot-style Wi-Fi data source: pull a [ConnectedAp], optionally gate a
/// field behind a permission. macOS is the only implementer today; the iOS
/// streaming path does not use this interface (see the file header).
abstract class WifiInfoAdapter {
  /// Reads a fresh snapshot of the connected access point.
  ///
  /// Throws [WifiInfoUnavailable] when the snapshot cannot be read (no Wi-Fi
  /// interface, channel error). Never fabricates a reading.
  Future<ConnectedAp> fetch();

  /// Whether this source gates the network name (SSID/BSSID) behind an OS
  /// permission the user can grant in-app (macOS Location Services). False for
  /// sources with no such gate.
  bool get gatesNameBehindPermission;

  /// Requests the name-gating permission, then reports whether it is authorized.
  /// A no-op returning true for sources without such a gate.
  Future<bool> requestNamePermission();

  /// Human label for the source platform, used in honest per-field
  /// "not exposed by `<platform>`" copy.
  String get platformLabel;
}

/// macOS CoreWLAN adapter. Wraps the retained, device-tested [WifiInfoService]
/// (native channel `com.wlanpros.toolbox/wifi_info` → WifiInfoChannel.swift) and
/// maps its snapshot into the normalized [ConnectedAp].
class MacWifiInfoAdapter implements WifiInfoAdapter {
  /// [service] is injectable so widget tests drive a fake invoker + platform
  /// override without a real platform channel.
  ///
  /// [permissionTimeout] bounds the native Location-authorization request so a
  /// stalled CLLocationManager prompt (common in notarized non-App-Store builds
  /// where the system prompt never surfaces or the delegate callback never
  /// fires) can never hang a caller. On timeout the request resolves to `false`
  /// — treated as "not authorized" — and the network NAME degrades honestly
  /// while the rate-derived verdict, which never needs Location, proceeds.
  MacWifiInfoAdapter({
    WifiInfoService? service,
    Duration permissionTimeout = const Duration(seconds: 3),
  })  : _service = service ?? WifiInfoService(),
        // Kept in the initializer list alongside `_service` (which needs the
        // `?? WifiInfoService()` fallback) rather than split into a formal.
        // ignore: prefer_initializing_formals
        _permissionTimeout = permissionTimeout;

  final WifiInfoService _service;
  final Duration _permissionTimeout;

  @override
  String get platformLabel => 'macOS CoreWLAN';

  /// macOS gates SSID/BSSID behind Location Services authorization.
  @override
  bool get gatesNameBehindPermission => true;

  @override
  Future<ConnectedAp> fetch() async {
    final WifiInfo info = await _service.fetch();
    return ConnectedAp.fromWifiInfo(info);
  }

  /// Requests Location authorization with a hard upper bound. A native side
  /// that never answers (no prompt surfaced, delegate callback never fires)
  /// resolves to `false` after [permissionTimeout] instead of hanging the
  /// caller. This protects EVERY caller — Test My Connection and the pro Wi-Fi
  /// Information tool alike — without either needing to wrap the call itself.
  @override
  Future<bool> requestNamePermission() => _service
      .requestLocationPermission()
      .timeout(_permissionTimeout, onTimeout: () => false);
}
