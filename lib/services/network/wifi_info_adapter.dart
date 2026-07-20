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
//   * Android → [AndroidWifiInfoAdapter] over WifiManager (WifiInfoService).
//   * Windows → [WindowsWifiInfoAdapter] over the Win32 Native Wifi API
//             (wlanapi.dll), read straight from Dart FFI via the `win32`
//             package — NO C++ MethodChannel, NO Location-permission flow. A
//             pull-only snapshot, the same shape as macOS/Android.
//   * desktop Linux → [WifiInfoSource.unsupported]: clean seam, honest
//             "coming later" state.
//   * web → [WifiInfoSource.web]: download-the-app fallback.
//
// Keeping the iOS streaming stack as its own branch (rather than forcing it
// through a pull-only adapter) is deliberate: a snapshot adapter cannot express
// "install a Shortcut, then Start/Stop a live push stream" without leaking that
// shape into every platform. The seam's job is to pick the source honestly; the
// screen folds the iOS-only affordances behind the iOS source.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'ap_name_cache.dart';
import 'ap_name_decoder.dart';
import 'connected_ap.dart';
import 'wifi_info_service.dart';
import 'windows_wifi_reader.dart';

/// Which data source backs the Wi-Fi Information tool on the current platform.
enum WifiInfoSource {
  /// macOS CoreWLAN snapshot via [MacWifiInfoAdapter].
  macosCoreWlan,

  /// iOS companion-Shortcut stack (install flow + live streaming). The screen
  /// drives WiFiDetailsBridge / WifiMonitorController directly for this source.
  iosShortcuts,

  /// Android WifiManager + ConnectivityManager snapshot via
  /// [AndroidWifiInfoAdapter]. Pull-only snapshot + a Location-permission flow
  /// (ACCESS_FINE_LOCATION gates SSID/BSSID on Android 8.0+), the same shape as
  /// the macOS source.
  androidWifiManager,

  /// Windows Native Wifi (wlanapi.dll) snapshot via [WindowsWifiInfoAdapter].
  /// Pull-only snapshot, read straight from Dart FFI (NO C++ MethodChannel,
  /// NO Location-permission flow — Windows returns SSID/BSSID without a grant).
  /// Same shape as the macOS/Android snapshot sources.
  windowsNativeWifi,

  /// A native platform with no Wi-Fi adapter yet (desktop Linux).
  /// Honest "coming in a later update" state.
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
      TargetPlatform.android => WifiInfoSource.androidWifiManager,
      TargetPlatform.windows => WifiInfoSource.windowsNativeWifi,
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

  /// Reports the CURRENT name-gating authorization as a TRI-STATE, no prompt.
  ///
  /// The bool [currentNameAuthorization] cannot tell the promptable
  /// `notDetermined` from the deep-link-only `denied` / `restricted`. Callers
  /// that proactively surface the OS prompt (this screen, on a run) need that
  /// distinction so they fire the native prompt ONLY when it can actually
  /// appear, and offer the System Settings deep-link otherwise. Sources without
  /// a name gate report [LocationAuthStatus.authorized].
  Future<LocationAuthStatus> nameAuthorizationStatus();

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
    bool enrichApName = false,
    Duration apNameRescanFloor = const Duration(seconds: 30),
    DateTime Function()? now,
    ApNameCache? apNameCache,
  })  : _service = service ?? WifiInfoService(),
        // Kept in the initializer list alongside `_service` (which needs the
        // `?? WifiInfoService()` fallback) rather than split into formals.
        // ignore: prefer_initializing_formals
        _permissionTimeout = permissionTimeout,
        // ignore: prefer_initializing_formals
        _fetchTimeout = fetchTimeout,
        // ignore: prefer_initializing_formals
        _enrichApName = enrichApName,
        // ignore: prefer_initializing_formals
        _apNameRescanFloor = apNameRescanFloor,
        _now = now ?? DateTime.now,
        // Defaults to the app-wide shared cache so a name decoded on ANY screen
        // shows instantly on all. Injectable so a test can isolate a cache.
        _apNameCache = apNameCache ?? ApNameCache.instance;

  final WifiInfoService _service;
  final Duration _permissionTimeout;
  final Duration _fetchTimeout;

  /// Whether [fetch] also reads the connected AP's beacon IE bytes (a separate
  /// CoreWLAN scan) and decodes the vendor-advertised AP name onto the model.
  /// Opt-in (default false) so the display surfaces that show the name (the live
  /// sampler, the Wi-Fi Information screen) pay the scan while the consumer
  /// connection checks that never render it do not.
  ///
  /// When true, enrichment is FIRE-AND-FORGET: [fetch] never awaits the scan, so
  /// the RF snapshot and roam recording are never delayed by it. The scan runs
  /// in the background; its decoded name is CACHED per BSSID in the app-wide
  /// [ApNameCache] (AP names do not change), so a known AP returns its name with
  /// NO scan — even the FIRST time THIS screen sees it, if another screen already
  /// decoded it — and a scan fires only for a BSSID no screen has named yet, no
  /// more often than [_apNameRescanFloor] app-wide (so a run of unnamed samples,
  /// across any screens, cannot storm the radio — which also cuts the off-channel
  /// observer effect a scan causes). Honest-null until the async scan resolves.
  final bool _enrichApName;

  /// Minimum interval between scans for the SAME BSSID whose name is not yet
  /// cached. Throttles the radio; a cached BSSID is never re-scanned at all.
  final Duration _apNameRescanFloor;

  /// Injectable clock (for the throttle), so tests are deterministic.
  final DateTime Function() _now;

  /// The app-wide shared AP-name cache. Holds BOTH the decoded-name map AND the
  /// per-BSSID last-scan timestamp, so a name decoded on ANY screen shows
  /// instantly on all, and the scan throttle protects the radio app-wide (two
  /// adapters can't each scan the same not-yet-known BSSID). Defaults to
  /// [ApNameCache.instance]; injectable for test isolation.
  final ApNameCache _apNameCache;

  /// The in-flight background scan this adapter is waiting on, if any. At most
  /// one runs at a time (a second poll while a scan is pending does not launch
  /// another). It may be a scan this adapter STARTED, or one ADOPTED from
  /// another adapter that is already scanning the same BSSID — either way it is
  /// a real handle on real work, never null while a scan for the current BSSID
  /// is running somewhere in the app.
  Future<void>? _inFlightApNameScan;

  /// The current in-flight AP-name scan (or null). macOS is the only adapter that
  /// enriches AP names today, so this capability lives here rather than on the
  /// [WifiInfoAdapter] interface. A non-polling caller (Interface Info, via
  /// [InterfaceInfoService.pendingApNameScan]) awaits it to re-read once the
  /// fire-and-forget scan resolves, and tests await it to drive the scan
  /// deterministically.
  Future<void>? get pendingApNameScan => _inFlightApNameScan;

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
    final ConnectedAp ap = ConnectedAp.fromWifiInfo(info);
    if (!_enrichApName) return ap;
    final String? bssid = _normBssid(ap.bssid);
    if (bssid == null) return ap;

    // Shared-cache hit → attach it with NO scan. This is the cross-screen win:
    // if ANY other adapter (another screen) already decoded this BSSID's name,
    // it is served here instantly, cold-start scan skipped entirely.
    final String? cached = _apNameCache.nameFor(bssid);
    if (cached != null) return ap.withApName(cached);

    // Not cached. Fire-and-forget a throttled background scan ONLY when Location
    // is authorized (the IE bytes are nil without it). Crucially, do NOT await
    // it: the RF snapshot and the roam recording never wait on a scan, so the
    // main thread and the poll loop are never blocked (the beachball fix's Dart
    // half). The name fills in on a later poll once the scan caches it.
    if (info.locationAuthorized) _maybeScheduleApNameScan(bssid);
    return ap; // honest-null until the async scan resolves
  }

  /// Normalizes a BSSID to a stable cache key, or null when it carries no usable
  /// value. Delegates to [ApNameCache.normalizeBssid] rather than re-implementing
  /// the rule: the cache owns its key contract, and a second copy of this logic
  /// is free to drift from the one the cache actually keys on.
  static String? _normBssid(String? bssid) => ApNameCache.normalizeBssid(bssid);

  /// Schedules a single background AP-name scan for [bssid] when the throttle
  /// allows and none is already running. Never awaited by [fetch].
  void _maybeScheduleApNameScan(String bssid) {
    if (_inFlightApNameScan != null) return; // one scan at a time per adapter

    // A scan for this BSSID may already be running on ANOTHER adapter (another
    // screen). ADOPT it rather than reporting "nothing pending": the shared
    // throttle below would otherwise defer this adapter with no handle on the
    // winner's work, and a non-polling screen awaiting `pendingApNameScan` would
    // get null, re-read against the still-empty cache, and never re-read again.
    final Future<void>? running = _apNameCache.inFlightScanFor(bssid);
    if (running != null) {
      _holdApNameScan(running);
      return; // adopted, not started — still exactly one scan app-wide
    }

    // Shared throttle: the last-scan timestamp lives in the app-wide cache, so a
    // BSSID scanned recently by ANY adapter (any screen) is not re-scanned here.
    // Two adapters can no longer each scan the same not-yet-known BSSID inside
    // the floor — the second one to fetch sees the first's timestamp and defers.
    final DateTime? last = _apNameCache.lastScanAt(bssid);
    if (last != null && _now().difference(last) < _apNameRescanFloor) {
      return; // throttled: do not storm the radio for an unnamed BSSID
    }
    _apNameCache.markScanAttempt(bssid, _now());
    // The cache owns the dedupe and clears the in-flight entry when the scan
    // settles (success OR failure), so a failed scan never wedges the BSSID.
    _holdApNameScan(
      _apNameCache.beginScan(bssid, () => _scanAndCacheApName(bssid)),
    );
  }

  /// Holds [scan] as this adapter's pending scan and releases it when it
  /// settles. Identity-guarded so a settling scan never clears a newer one this
  /// adapter has since picked up (e.g. after a roam to a different BSSID).
  void _holdApNameScan(Future<void> scan) {
    _inFlightApNameScan = scan;
    scan.whenComplete(() {
      if (identical(_inFlightApNameScan, scan)) _inFlightApNameScan = null;
    });
  }

  /// Reads the connected AP's beacon IE bytes, decodes the name, and caches it.
  /// Total and best-effort: any failure, timeout, empty blob, or stale-scan
  /// BSSID mismatch leaves the cache untouched (honest-null), never a fabricated
  /// value, and never throws.
  Future<void> _scanAndCacheApName(String bssid) async {
    try {
      final ApIeBlob blob = await _service.connectedApIeBlob().timeout(
            _fetchTimeout,
            onTimeout: () => const ApIeBlob(
              ieBytes: null,
              bssid: null,
              locationAuthorized: false,
            ),
          );
      final Uint8List? bytes = blob.ieBytes;
      if (bytes == null || bytes.isEmpty) return;
      // Guard a stale-scan mismatch: only trust bytes whose scanned BSS matches
      // the BSSID we asked about.
      final String? scanned = _normBssid(blob.bssid);
      if (scanned != null && scanned != bssid) return;
      final String? name = decodeApName(bytes);
      // Write the decoded name to the SHARED cache so every other adapter (every
      // other screen) serves it instantly. Only a real decoded name is stored;
      // a null decode leaves the cache untouched (honest-null, GL-005).
      if (name != null) _apNameCache.cacheName(bssid, name);
    } catch (_) {
      // Honest-null; leave the cache empty. The throttle prevents a re-scan
      // storm for this BSSID until the floor elapses.
    }
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

  /// Reports the CURRENT macOS Location authorization as a TRI-STATE, no prompt.
  /// Backs onto the native no-prompt status token. Lets the screen fire the
  /// system prompt only when the status is `notDetermined` (promptable) and
  /// deep-link to System Settings when `denied` / `restricted`. Bounded by
  /// [fetchTimeout] as a hang-safety; on timeout it resolves to
  /// [LocationAuthStatus.notDetermined] (the safe, promptable default).
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() => _service
      .locationAuthorizationStatus()
      .timeout(_fetchTimeout, onTimeout: () => LocationAuthStatus.notDetermined);

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

/// Android WifiManager + ConnectivityManager adapter. Wraps the same
/// [WifiInfoService] the macOS adapter uses (shared `com.wlanpros.toolbox/
/// wifi_info` channel — MainActivity.kt provides the Android handler) and maps
/// its snapshot into the normalized [ConnectedAp].
///
/// Android, like macOS, gates the network NAME (SSID/BSSID) behind a Location
/// permission: ACCESS_FINE_LOCATION must be granted at RUNTIME on Android 8.0+
/// or WifiManager returns null/redacted SSID and BSSID. Unlike macOS, Android
/// CAN toggle the app's own permission via the standard runtime request dialog,
/// so [requestNamePermission] surfaces the real Android permission prompt
/// (handled natively in MainActivity.kt) and resolves with the grant result.
///
/// Fields Android cannot supply stay honestly null (GL-005 / GL-008): the
/// public Android API exposes no noise floor or SNR, so those rows render
/// "Unavailable" rather than an estimate — the same contract macOS uses for
/// the Rx rate. Channel width IS available on Android: the native side reads it
/// from the matching ScanResult.channelWidth (the connected WifiInfo does not
/// carry it) and maps it to MHz; when there is no scan match or no Location
/// grant, [ConnectedAp.channelWidthAvailable] rides false so the UI says
/// "Not reported" rather than guessing. The regulatory country comes from the
/// restricted WifiManager.getCountryCode(), which is limited on Android 11+ and
/// frequently returns nothing — null then drives an honest Android limit note.
class AndroidWifiInfoAdapter implements WifiInfoAdapter {
  /// [service] is injectable so tests drive a fake invoker + platform override
  /// without a real platform channel.
  ///
  /// [permissionTimeout] bounds the INTERACTIVE runtime-permission request. The
  /// Android dialog resolves on the user's tap; the ceiling (default 60s) is a
  /// hang-safety for the pathological case where no result callback arrives. On
  /// timeout the request resolves to `false` (treated as "not granted") and the
  /// network NAME degrades honestly while the RF fields, which never need
  /// Location, still render.
  ///
  /// [fetchTimeout] bounds the native WifiManager snapshot read for the same
  /// reason a stalled channel must never hang a caller; on timeout [fetch]
  /// throws a typed [WifiInfoUnavailable] (`channelError`).
  AndroidWifiInfoAdapter({
    WifiInfoService? service,
    Duration permissionTimeout = const Duration(seconds: 60),
    Duration fetchTimeout = const Duration(seconds: 5),
  })  : _service = service ?? WifiInfoService(),
        // ignore: prefer_initializing_formals
        _permissionTimeout = permissionTimeout,
        // ignore: prefer_initializing_formals
        _fetchTimeout = fetchTimeout;

  final WifiInfoService _service;
  final Duration _permissionTimeout;
  final Duration _fetchTimeout;

  @override
  String get platformLabel => 'Android';

  /// Android gates SSID/BSSID behind ACCESS_FINE_LOCATION at runtime.
  @override
  bool get gatesNameBehindPermission => true;

  /// Reads a fresh Android WifiManager snapshot with a hard upper bound. A
  /// native channel that never returns raises a typed [WifiInfoUnavailable]
  /// (`channelError`) after [fetchTimeout] rather than hanging the caller.
  @override
  Future<ConnectedAp> fetch() async {
    final WifiInfo info = await _service.fetch().timeout(
      _fetchTimeout,
      onTimeout: () => throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'Wi-Fi snapshot read timed out.',
      ),
    );
    return ConnectedAp.fromAndroidWifiInfo(info);
  }

  /// Requests ACCESS_FINE_LOCATION (INTERACTIVE — surfaces the Android runtime
  /// permission dialog and waits for the user) with a generous
  /// [permissionTimeout] ceiling. Returns whether location is granted after the
  /// dialog resolves. On the pathological no-callback hang, resolves to `false`.
  @override
  Future<bool> requestNamePermission() => _service
      .requestLocationPermission()
      .timeout(_permissionTimeout, onTimeout: () => false);

  /// Reports the CURRENT ACCESS_FINE_LOCATION grant WITHOUT surfacing a prompt.
  /// Bounded by [fetchTimeout] as a hang-safety; on timeout resolves to `false`.
  @override
  Future<bool> currentNameAuthorization() => _service
      .isLocationAuthorized()
      .timeout(_fetchTimeout, onTimeout: () => false);

  /// Reports the CURRENT Android Location grant as a TRI-STATE, no prompt.
  /// Backs onto the native status token (MainActivity maps a not-yet-granted,
  /// not-permanently-denied permission to `notDetermined` so the runtime dialog
  /// can still fire, and a permanently-denied one to `denied` so the UI
  /// deep-links to App Settings). Bounded by [fetchTimeout]; on timeout resolves
  /// to [LocationAuthStatus.notDetermined].
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() => _service
      .locationAuthorizationStatus()
      .timeout(_fetchTimeout, onTimeout: () => LocationAuthStatus.notDetermined);

  /// Opens the app's system Settings page so the user can enable Location
  /// manually after a permanent denial ("Don't ask again"). Android cannot
  /// re-prompt once permanently denied, so the deep-link is the honest path.
  /// Bounded by [fetchTimeout]; on timeout resolves to `false`.
  @override
  Future<bool> openNamePermissionSettings() => _service
      .openLocationSettings()
      .timeout(_fetchTimeout, onTimeout: () => false);
}

/// Windows Native Wifi adapter. Reads the connected AP straight from
/// `wlanapi.dll` via Dart FFI ([WindowsWifiReader]) — NO C++ MethodChannel and
/// NO method-channel `WifiInfoService` at all; the win32 package binds
/// WlanOpenHandle / WlanEnumInterfaces / WlanQueryInterface /
/// WlanGetNetworkBssList directly, so the whole bridge is Dart. It maps the
/// resulting snapshot into the normalized [ConnectedAp] via
/// [ConnectedAp.fromWindowsWifiInfo].
///
/// Unlike macOS and Android, Windows does NOT gate the network name behind a
/// Location permission — Native Wifi returns SSID/BSSID with no runtime grant.
/// So [gatesNameBehindPermission] is false and every permission method is the
/// no-op the [WifiInfoAdapter] contract specifies for ungated sources.
///
/// Fields Windows cannot supply stay honestly null (GL-005 / GL-008): the public
/// Native Wifi API exposes no noise floor, so noise + SNR are null and never
/// derived (the same two Android omits). Channel WIDTH is parsed from the
/// connected AP's beacon IEs, so it resolves per network and rides null only when
/// that AP advertised no width element. Windows supplies MORE than macOS, though:
/// a real dBm RSSI (`lRssi`) AND the Rx rate — so
/// [ConnectedAp.fromWindowsWifiInfo] sets `rxRateAvailable: true`.
class WindowsWifiInfoAdapter implements WifiInfoAdapter {
  /// [reader] is injectable so tests drive a fake/Windows-override without a
  /// real platform or a real wlanapi.dll.
  ///
  /// [fetchTimeout] bounds the FFI read as a hang-safety; on timeout [fetch]
  /// throws a typed [WifiInfoUnavailable] (`channelError`), matching every other
  /// adapter so callers degrade honestly with no per-screen change.
  WindowsWifiInfoAdapter({
    WindowsWifiReader? reader,
    Duration fetchTimeout = const Duration(seconds: 5),
  })  : _reader = reader ?? WindowsWifiReader(),
        // ignore: prefer_initializing_formals
        _fetchTimeout = fetchTimeout;

  final WindowsWifiReader _reader;
  final Duration _fetchTimeout;

  @override
  String get platformLabel => 'Windows';

  /// Windows Native Wifi returns SSID/BSSID with NO Location grant.
  @override
  bool get gatesNameBehindPermission => false;

  /// Reads a fresh Native Wifi snapshot with a hard upper bound. An FFI read
  /// that never returns raises a typed [WifiInfoUnavailable] (`channelError`)
  /// after [fetchTimeout] rather than hanging the caller.
  @override
  Future<ConnectedAp> fetch() async {
    final WifiInfo info = await _reader.fetch().timeout(
      _fetchTimeout,
      onTimeout: () => throw const WifiInfoUnavailable(
        WifiInfoUnavailableReason.channelError,
        'Wi-Fi snapshot read timed out.',
      ),
    );
    return ConnectedAp.fromWindowsWifiInfo(info);
  }

  /// No name-gating permission on Windows — always authorized.
  @override
  Future<bool> requestNamePermission() async => true;

  /// No name-gating permission on Windows — always authorized.
  @override
  Future<bool> currentNameAuthorization() async => true;

  /// Windows Native Wifi has no name gate, so it reports the tri-state as
  /// [LocationAuthStatus.authorized] (per the interface contract: sources
  /// without a name gate are always authorized).
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;

  /// No name-gating settings pane to deep-link to on Windows.
  @override
  Future<bool> openNamePermissionSettings() async => false;
}
