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
  ///
  /// This is the INTERACTIVE path: it surfaces the OS prompt and waits for the
  /// user to respond, so it carries a generous timeout ceiling. Callers that
  /// must not pop a prompt (e.g. a connection check) read with the CURRENT
  /// authorization via [currentNameAuthorization] instead.
  Future<bool> requestNamePermission();

  /// Reports the CURRENT name-gating authorization WITHOUT surfacing any prompt.
  /// Returns true for sources without such a gate. Used by callers (a connection
  /// check) that must read with the existing authorization and never interrupt
  /// the user with a system prompt mid-task.
  Future<bool> currentNameAuthorization();

  /// Deep-links the user to the OS settings pane where they can grant the
  /// name-gating permission manually.
  ///
  /// Some platforms (macOS) cannot toggle their own Location permission in code
  /// (TCC protection), and the in-app prompt is unreliable in notarized builds,
  /// so the honest fallback is to open the exact settings pane and tell the user
  /// what to flip. Returns whether the settings pane opened. A no-op returning
  /// false for sources without such a deep-link.
  Future<bool> openNamePermissionSettings();

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
  /// [permissionTimeout] bounds the INTERACTIVE native Location-authorization
  /// request. It is a GENEROUS ceiling (default 30s) — long enough for a user
  /// to read and respond to the system prompt before the delegate callback
  /// fires, while still being a hang-safety for the pathological case where the
  /// prompt never surfaces and no callback ever arrives (common in notarized
  /// non-App-Store builds). On timeout the request resolves to `false` —
  /// treated as "not authorized" — and the network NAME degrades honestly while
  /// the rate-derived verdict, which never needs Location, proceeds.
  ///
  /// NOTE: this timeout governs the interactive [requestNamePermission] only.
  /// The no-prompt [currentNameAuthorization] never surfaces a prompt, so it is
  /// not bounded by this ceiling.
  ///
  /// [fetchTimeout] bounds the native CoreWLAN snapshot read for the same
  /// reason: a stalled channel (the native side never returns) must never hang
  /// a caller. On timeout [fetch] throws a typed [WifiInfoUnavailable]
  /// (`channelError`), so EVERY caller is protected in one place — the pro
  /// Wi-Fi Information tool surfaces its honest "No Wi-Fi reading" card, while
  /// Test My Connection and Wi-Fi vs Internet degrade to their internet-only
  /// verdict. Mirrors how [requestNamePermission] is bounded.
  MacWifiInfoAdapter({
    WifiInfoService? service,
    Duration permissionTimeout = const Duration(seconds: 30),
    Duration fetchTimeout = const Duration(seconds: 5),
  })  : _service = service ?? WifiInfoService(),
        // Kept in the initializer list alongside `_service` (which needs the
        // `?? WifiInfoService()` fallback) rather than split into formals.
        // ignore: prefer_initializing_formals
        _permissionTimeout = permissionTimeout,
        // ignore: prefer_initializing_formals
        _fetchTimeout = fetchTimeout;

  final WifiInfoService _service;
  final Duration _permissionTimeout;
  final Duration _fetchTimeout;

  @override
  String get platformLabel => 'macOS CoreWLAN';

  /// macOS gates SSID/BSSID behind Location Services authorization.
  @override
  bool get gatesNameBehindPermission => true;

  /// Reads a fresh macOS CoreWLAN snapshot with a hard upper bound. A native
  /// channel that never returns (CoreWLAN read stalls) raises a typed
  /// [WifiInfoUnavailable] (`channelError`) after [fetchTimeout] rather than
  /// hanging the caller. This protects EVERY caller — the pro Wi-Fi Information
  /// tool and the two consumer checks (Test My Connection, Wi-Fi vs Internet) —
  /// in one place, so no screen has to wrap the call itself. The thrown type
  /// matches the existing channel-error path, so callers' current `catch`
  /// handling degrades honestly with no per-screen change.
  @override
  Future<ConnectedAp> fetch() async {
    final WifiInfo info = await _service.fetch().timeout(
      _fetchTimeout,
      onTimeout: () => throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'Wi-Fi snapshot read timed out.',
      ),
    );
    return ConnectedAp.fromWifiInfo(info);
  }

  /// Requests Location authorization (INTERACTIVE — surfaces the OS prompt and
  /// waits for the user) with a generous [permissionTimeout] ceiling (30s by
  /// default). The ceiling is long enough for a real user to respond to the
  /// system prompt — the delegate fires on their response well within it — so
  /// the interactive grant in the pro Wi-Fi Information tool resolves AUTHORIZED
  /// after the user clicks Allow, and the subsequent re-read populates SSID and
  /// BSSID. It still guards the pathological hang where no prompt surfaces and
  /// no callback ever arrives: on timeout the request resolves to `false`.
  @override
  Future<bool> requestNamePermission() => _service
      .requestLocationPermission()
      .timeout(_permissionTimeout, onTimeout: () => false);

  /// Reports the CURRENT Location authorization WITHOUT surfacing any prompt.
  /// Backs onto the native no-prompt status check. Used by a connection check
  /// so it can label the network name honestly (authorized vs not) without ever
  /// interrupting the user with a system prompt. Bounded by [fetchTimeout] as a
  /// hang-safety; on timeout it resolves to `false` (treated as not authorized).
  @override
  Future<bool> currentNameAuthorization() => _service
      .isLocationAuthorized()
      .timeout(_fetchTimeout, onTimeout: () => false);

  /// Opens the macOS Location Services privacy pane so the user can enable this
  /// app's Location access manually. macOS cannot toggle its own Location
  /// permission in code (TCC), so this deep-link plus on-screen steps is the
  /// honest path when the in-app prompt does not surface. Bounded by
  /// [fetchTimeout] as a hang-safety; on timeout it resolves to `false`.
  @override
  Future<bool> openNamePermissionSettings() => _service
      .openLocationSettings()
      .timeout(_fetchTimeout, onTimeout: () => false);
}
