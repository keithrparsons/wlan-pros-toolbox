// ============================================================================
// CROSS-SCREEN PLATFORM-CAPABILITY CONSISTENCY HARNESS  (the "C-bug" net)
// ============================================================================
//
// WHAT THIS GUARDS. On 2026-06-30 we fixed three bugs of ONE class — a screen
// telling the user a datum is "not available / not reported / off on this
// platform" that the app can actually get on that platform:
//   * C1 — the Network-at-a-glance card said "Not reported on iOS" for SSID +
//          Signal while the Wi-Fi Information tool had a live reading cached.
//   * C2 — the same card said "Not reported on this platform" on Windows while
//          WindowsWifiInfoAdapter reads SSID/RSSI over FFI with no gate.
//   * C3 — the Roaming Log said "Live Wi-Fi monitoring is off on this device"
//          on Windows while WifiSignalSampler polls Windows like macOS/Android.
//
// ROOT CAUSE (all three). The screen carried its OWN inline platform list
// instead of delegating to the shared single-source-of-truth (SSOT) seams:
//   * [WifiInfoSourceResolver]  — which source backs Wi-Fi identity/snapshot;
//   * [WifiSignalSampler.isSupportedSource] — which platforms can live-sample;
//   * [CellularInfoSourceResolver] — which source backs cellular.
// The healthy tools (Wi-Fi Information, Test My Connection, Interface Info)
// delegate and stayed honest.
//
// THE INVARIANT THIS FILE ASSERTS, mechanically, on every `flutter test`:
//   For each of the platforms below, NO Wi-Fi/network/signal consumer may
//   render a "not available on <platform>" ceiling for a datum the shared
//   resolver marks OBTAINABLE on that platform — or that another consumer
//   renders on that platform. Conversely, on a platform where the SSOT marks a
//   datum genuinely unobtainable, the consumer MUST show its honest unavailable
//   state (never claim it elsewhere while denying it here).
//
// HOW CROSS-SCREEN AGREEMENT IS ENFORCED (and why it is not brittle). Every
// consumer case below derives its `obtainable` answer by CALLING THE ACTUAL
// SSOT seam — never a hand-typed per-screen platform list. Because all
// consumers are anchored to the same predicate, two screens cannot disagree
// about the same platform without at least one of them violating the predicate,
// which fails here. Part A first pins the SSOT itself (the resolvers agree with
// each other and with the documented matrix), so the anchor is validated, not
// assumed.
//
// ENUMERABLE BY DESIGN.
//   * Add a platform  → add one entry to `_platforms` (and the sixth "future
//     Linux adapter" sentinel shows how a new native source is caught).
//   * Add a consumer  → add one `_…Cases()` generator to `_allCases`.
//   * Add a Wi-Fi source enum value → Part A's exhaustive map assertion fails
//     until the new value is classified, forcing the harness (and the dev's
//     mental model) to be updated in the same change.
//
// ----------------------------------------------------------------------------
// WHAT THIS HARNESS CANNOT MECHANIZE (covered by a parallel MANUAL sweep):
//   1. Copy-vs-behavior nuance. This proves the false-ceiling STRING is gone;
//      it cannot judge whether the replacement copy is well-worded, or whether
//      "as of HH:MM" staleness wording reads honestly. Human review.
//   2. Stale HARDCODED data. A screen that shows a real-looking but outdated
//      constant (a pinned price, a frozen channel table) passes every check
//      here — the value is present and platform-appropriate. Only a human who
//      knows the correct current value catches drift.
//   3. Calc-vs-first-principles judgment. Whether a calculator's FORMULA is
//      right (not just internally consistent) is a domain call. The per-
//      calculator reference-value tests (eirp/fspl/link_budget/throughput/…)
//      guard the arithmetic; they cannot vouch that the chosen model matches
//      Keith's first-principles derivation.
//   4. Heavy live screens driven end-to-end. Wi-Fi Information, Test My
//      Connection, and Interface Info are anchored here via Part A (the exact
//      seams they delegate to) and by the source-scan delegation guard
//      (platform_gate_delegation_guard_test.dart), NOT by a full hermetic
//      widget drive — their iOS Shortcut / streaming machinery makes a 5-
//      platform pump brittle. A new inline platform gate in ANY of them is
//      still caught by the delegation guard; their per-field honesty is covered
//      by their own suites. This split is deliberate, not an omission.
// ----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/cellular_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_glance_card.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/roaming_log_screen.dart';
import 'package:wlan_pros_toolbox/services/help/tool_help_loader.dart';
import 'package:wlan_pros_toolbox/services/network/cellular_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap_cache.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/json_http_client.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/subnet_seed.dart';
import 'package:wlan_pros_toolbox/services/network/public_ip_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart'
    show LocationAuthStatus;
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// The canonical platform matrix. `wifi` / `cellular` are the SSOT SOURCES each
// platform resolves to; Part A verifies the real resolvers actually produce
// these, so the matrix is validated rather than trusted. The sixth entry is a
// FUTURE-ADAPTER SENTINEL: desktop Linux resolves to `unsupported` today, so a
// developer who wires a real Linux Wi-Fi adapter must change the resolver — at
// which point Part A's assertion `resolve(linux) == unsupported` fails, forcing
// the matrix + the sampler predicate to be updated together. That is the
// "a new Linux adapter is caught automatically" guarantee.
// ---------------------------------------------------------------------------
class _Platform {
  const _Platform(this.label, this.target, this.wifi, this.cellular);

  final String label;

  /// The `TargetPlatform` override; null models the web build (which the
  /// resolvers detect via compile-time `kIsWeb`, not an override).
  final TargetPlatform? target;
  final WifiInfoSource wifi;
  final CellularInfoSource cellular;

  bool get isWeb => target == null;
}

const List<_Platform> _platforms = <_Platform>[
  _Platform('iOS', TargetPlatform.iOS, WifiInfoSource.iosShortcuts,
      CellularInfoSource.iosShortcuts),
  _Platform('macOS', TargetPlatform.macOS, WifiInfoSource.macosCoreWlan,
      CellularInfoSource.unsupported),
  _Platform('Windows', TargetPlatform.windows, WifiInfoSource.windowsNativeWifi,
      CellularInfoSource.unsupported),
  _Platform('Android', TargetPlatform.android, WifiInfoSource.androidWifiManager,
      CellularInfoSource.unsupported),
  _Platform('web', null, WifiInfoSource.web, CellularInfoSource.web),
  // Future-adapter sentinel — NOT one of the shipping five. See the note above.
  _Platform('desktop Linux (no adapter yet)', TargetPlatform.linux,
      WifiInfoSource.unsupported, CellularInfoSource.unsupported),
];

/// SSOT-derived: is the Wi-Fi IDENTITY/snapshot datum (SSID/RSSI) obtainable on
/// a platform backed by [source]? True for every source that has a working
/// reader (the four native adapters) or an app-readable cache (iOS Shortcut).
/// False only for a native platform with no adapter and the web build. Derived
/// from the resolver's own source enum — never a hand-listed platform set.
bool _wifiIdentityObtainable(WifiInfoSource source) =>
    source != WifiInfoSource.unsupported && source != WifiInfoSource.web;

// ---------------------------------------------------------------------------
// Test host + fakes.
// ---------------------------------------------------------------------------
Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.dark(), home: child);

/// A hermetic snapshot adapter standing in for a native FFI/CoreWLAN reader, so
/// the macOS/Android/Windows sampler + glance paths run with no platform
/// channel. Returns a real reading (SSID + RSSI present).
class _FakeSnapshotAdapter implements WifiInfoAdapter {
  const _FakeSnapshotAdapter();

  @override
  Future<ConnectedAp> fetch() async => const ConnectedAp(
        ssid: 'WLANPros',
        bssid: 'a4:83:e7:00:11:22',
        rssiDbm: -52,
      );

  @override
  bool get gatesNameBehindPermission => false;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => false;
  @override
  String get platformLabel => 'fake';
}

/// In-memory [WiFiDetailsBridge] so the iOS sampler path (roaming log) runs
/// with no Shortcut/App-Group channel. Models "installed, never streaming this
/// session" — the honest capable-but-awaiting-Start state, NOT a false ceiling.
class _FakeBridge extends WiFiDetailsBridge {
  _FakeBridge();

  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
}

SubnetSeedDeriver _seed() => SubnetSeedDeriver(
      reader: () async => (
        ip: '192.168.1.50',
        mask: '255.255.255.0',
        gateway: '192.168.1.1',
      ),
    );

PublicIpService _publicIp() => PublicIpService(
      fetcher: (String url, Duration timeout) async => '203.0.113.7',
    );

IpGeoService _geo() => IpGeoService(
      client: JsonHttpClient(
        fetcher: (Uri url, Duration timeout) async => <String, dynamic>{
          'ip': '203.0.113.7',
          'loc': '37.75,-122.4',
          'org': 'AS396325 Comcast',
        },
      ),
    );

// ---------------------------------------------------------------------------
// A single table row: one (consumer × platform) invariant check.
// ---------------------------------------------------------------------------
class _Built {
  const _Built(this.widget, {this.dispose, this.settle = false});

  final Widget widget;

  /// Disposes any injected resource (a live sampler's poll timer). Called after
  /// the widget is unmounted so the pending-timer invariant stays green.
  final void Function()? dispose;

  /// True when the widget resolves async lanes with no periodic timer (safe to
  /// `pumpAndSettle`); false for live-sampling screens (fixed pumps only).
  final bool settle;
}

class _Case {
  const _Case({
    required this.consumer,
    required this.platform,
    required this.obtainable,
    required this.build,
    required this.verify,
  });

  final String consumer;
  final _Platform platform;

  /// Derived from the SSOT seam — never a per-platform literal.
  final bool obtainable;

  final _Built Function() build;

  /// Asserts the invariant given whether the datum is obtainable here.
  final void Function(WidgetTester tester, {required bool obtainable}) verify;
}

// ---------------------------------------------------------------------------
// Consumer 1 — Network-at-a-glance card (SSID + Signal). The C1 + C2 net.
// Fully hermetic on all four native platforms and the Linux sentinel; the web
// build is excluded because the resolver only returns `web` under compile-time
// `kIsWeb`, which a host test cannot toggle (web honesty is covered by the
// card's own suite + Part A pinning WifiInfoSource.web as unobtainable).
// ---------------------------------------------------------------------------
List<_Case> _glanceCases() {
  final List<_Case> cases = <_Case>[];
  for (final _Platform p in _platforms) {
    if (p.isWeb) continue; // see note above
    final bool obtainable = _wifiIdentityObtainable(p.wifi);
    cases.add(_Case(
      consumer: 'Network-at-a-glance card (SSID/Signal)',
      platform: p,
      obtainable: obtainable,
      build: () {
        // iOS reads the shared cache; the native snapshot sources auto-read via
        // the injected fetcher; the Linux sentinel (unsupported) reads nothing
        // and MUST fall to the honest "Not reported on this platform".
        final ConnectedApCache cache = ConnectedApCache();
        if (p.wifi == WifiInfoSource.iosShortcuts) {
          cache.update(const ConnectedAp(ssid: 'WLANPros', rssiDbm: -47));
        }
        return _Built(
          NetworkGlanceCard(
            platformOverride: p.target,
            apCache: cache,
            // On iOS these MUST NOT be consulted (the reading is cached); on the
            // native sources the fetcher IS the read.
            wifiFetcher: p.wifi == WifiInfoSource.iosShortcuts
                ? () async => throw StateError('iOS must not auto-fetch')
                : () async =>
                    const ConnectedAp(ssid: 'WLANPros', rssiDbm: -52),
            liveReadingRequester: () async =>
                throw StateError('must not fire on mount'),
            seedDeriver: _seed(),
            publicIpService: _publicIp(),
            ipGeoService: _geo(),
          ),
          settle: true,
        );
      },
      verify: (WidgetTester tester, {required bool obtainable}) {
        // "Not reported on <platform>" is the EXACT false-ceiling string the
        // Wi-Fi lane emits (`Not reported on $_platformLabel`). It must be
        // ABSENT wherever the datum is obtainable (C1/C2 would fail here) and
        // PRESENT where it genuinely is not (honest ceiling, e.g. Linux).
        final Finder ceiling = find.textContaining('Not reported on ');
        if (obtainable) {
          expect(ceiling, findsNothing,
              reason: 'glance card claims a FALSE Wi-Fi ceiling on '
                  '${p.label} while the resolver marks SSID/Signal obtainable');
          expect(find.text('WLANPros'), findsOneWidget,
              reason: 'the real SSID must render on ${p.label}');
        } else {
          expect(ceiling, findsWidgets,
              reason: 'glance card must state the honest Wi-Fi ceiling on '
                  '${p.label} (no adapter), never a blank or a guess');
        }
      },
    ));
  }
  return cases;
}

// ---------------------------------------------------------------------------
// Consumer 2 — Roaming Log (live signal via WifiSignalSampler). The C3 net.
// Drivable on all six: the four native sources + iOS via injected fakes, and
// web/Linux via the real no-sampler path (honest NetworkUnavailableView).
// ---------------------------------------------------------------------------
List<_Case> _roamingCases() {
  final List<_Case> cases = <_Case>[];
  for (final _Platform p in _platforms) {
    final bool obtainable = WifiSignalSampler.isSupportedSource(p.wifi);
    cases.add(_Case(
      consumer: 'Roaming Log (live signal)',
      platform: p,
      obtainable: obtainable,
      build: () {
        if (!obtainable) {
          // web / unsupported: real path, no sampler → honest unavailable view.
          return _Built(
            RoamingLogScreen(sourceOverride: p.wifi, enableSampling: false),
          );
        }
        // Capable platforms: inject a hermetic sampler so the LIVE card renders
        // (never the disabled "off on this device" string). iOS uses the fake
        // bridge (awaiting-Start state); the snapshot sources use the fake
        // adapter (auto-poll).
        final WifiSignalSampler sampler = p.wifi ==
                WifiInfoSource.iosShortcuts
            ? WifiSignalSampler(source: p.wifi, iosBridge: _FakeBridge())
            : WifiSignalSampler(
                source: p.wifi, macAdapter: const _FakeSnapshotAdapter());
        return _Built(
          RoamingLogScreen(sourceOverride: p.wifi, sampler: sampler),
          dispose: sampler.dispose,
        );
      },
      verify: (WidgetTester tester, {required bool obtainable}) {
        const String offCeiling = 'Live Wi-Fi monitoring is off on this device.';
        if (obtainable) {
          // C3: a capable platform must NOT be darkened — neither the disabled
          // string nor the whole "unavailable" view may appear.
          expect(find.text(offCeiling), findsNothing,
              reason: 'roaming log darkens ${p.label} with the false '
                  '"monitoring off" ceiling while the sampler supports it');
          expect(find.byType(NetworkUnavailableView), findsNothing,
              reason: 'roaming log must not show the unavailable view on '
                  'sampler-capable ${p.label}');
        } else {
          expect(find.byType(NetworkUnavailableView), findsOneWidget,
              reason: 'roaming log must show the honest unavailable view on '
                  '${p.label} (sampler cannot run there)');
        }
      },
    ));
  }
  return cases;
}

// ---------------------------------------------------------------------------
// Consumer 3 — Cellular Information. Cellular is obtainable on iOS ONLY; every
// other consumer agrees cellular is unavailable off iOS, so this asserts the
// honest-ceiling direction (no screen may claim cellular where the resolver
// denies it). The iOS obtainable case needs the Shortcut/monitor stack, so it
// is anchored via Part A rather than a hermetic pump (documented skip).
// ---------------------------------------------------------------------------
List<_Case> _cellularCases() {
  final List<_Case> cases = <_Case>[];
  for (final _Platform p in _platforms) {
    final bool obtainable = p.cellular == CellularInfoSource.iosShortcuts;
    if (obtainable) continue; // iOS Shortcut stack — anchored via Part A
    cases.add(_Case(
      consumer: 'Cellular Information',
      platform: p,
      obtainable: obtainable,
      build: () => _Built(
        CellularInfoScreen(sourceOverride: p.cellular),
      ),
      verify: (WidgetTester tester, {required bool obtainable}) {
        expect(find.byType(NetworkUnavailableView), findsOneWidget,
            reason: 'cellular must show the honest unavailable view on '
                '${p.label}, never imply it is reachable there');
      },
    ));
  }
  return cases;
}

List<_Case> get _allCases => <_Case>[
      ..._glanceCases(),
      ..._roamingCases(),
      ..._cellularCases(),
    ];

// ---------------------------------------------------------------------------
Future<void> _render(WidgetTester tester, _Built built) async {
  await tester.binding.setSurfaceSize(const Size(560, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(built.widget));
  if (built.settle) {
    await tester.pumpAndSettle();
  } else {
    // Live-sampling screens carry a periodic poll timer; settle would spin
    // forever. Two bounded pumps flush the seed read + first notify.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    // Roaming Log / Cellular screens mount a ToolHelpFooter.
    await ToolHelpLoader.ensureLoaded();
  });

  // =======================================================================
  // PART A — pin the SSOT itself. The anchor every consumer case relies on.
  // =======================================================================
  group('Part A — the SSOT seams agree (anchor)', () {
    test('WifiInfoSourceResolver resolves each platform to the matrix source',
        () {
      for (final _Platform p in _platforms) {
        if (p.isWeb) continue; // web is compile-time kIsWeb, not overridable
        expect(
          WifiInfoSourceResolver.resolve(platformOverride: p.target),
          p.wifi,
          reason: 'the Wi-Fi source matrix drifted for ${p.label}',
        );
      }
    });

    test('CellularInfoSourceResolver resolves each platform to the matrix source',
        () {
      for (final _Platform p in _platforms) {
        if (p.isWeb) continue;
        expect(
          CellularInfoSourceResolver.resolve(platformOverride: p.target),
          p.cellular,
          reason: 'the cellular source matrix drifted for ${p.label}',
        );
      }
    });

    test(
        'every WifiInfoSource is classified — a NEW enum value fails here until '
        'the harness is updated (forces the sampler predicate to be revisited)',
        () {
      // Expected live-feed capability for EVERY source. A source added to the
      // enum without an entry here trips the coverage assertion below.
      const Map<WifiInfoSource, bool> expectedSignalCapable =
          <WifiInfoSource, bool>{
        WifiInfoSource.macosCoreWlan: true,
        WifiInfoSource.androidWifiManager: true,
        WifiInfoSource.windowsNativeWifi: true,
        WifiInfoSource.iosShortcuts: true,
        WifiInfoSource.unsupported: false,
        WifiInfoSource.web: false,
      };
      expect(
        expectedSignalCapable.keys.toSet(),
        WifiInfoSource.values.toSet(),
        reason: 'a WifiInfoSource enum value is unclassified — add it to the '
            'harness AND to WifiSignalSampler.isSupportedSource',
      );
      for (final WifiInfoSource s in WifiInfoSource.values) {
        expect(WifiSignalSampler.isSupportedSource(s), expectedSignalCapable[s],
            reason: 'sampler capability drifted for $s');
      }
    });

    test(
        'the two Wi-Fi seams agree: identity-readable ⇔ live-sample-capable, '
        'for every source (no seam may think the radio is reachable while the '
        'other thinks it is not)', () {
      for (final WifiInfoSource s in WifiInfoSource.values) {
        expect(
          _wifiIdentityObtainable(s),
          WifiSignalSampler.isSupportedSource(s),
          reason: 'WifiInfoSourceResolver and WifiSignalSampler disagree about '
              'whether the Wi-Fi radio is reachable for $s',
        );
      }
    });

    test('the instance getter delegates to the static SSOT predicate', () {
      // Guards the Vera LOW-finding refactor: isSupported must not re-implement
      // the list. Constructed with hermetic fakes so no channel is touched.
      for (final WifiInfoSource s in <WifiInfoSource>[
        WifiInfoSource.macosCoreWlan,
        WifiInfoSource.androidWifiManager,
        WifiInfoSource.windowsNativeWifi,
        WifiInfoSource.unsupported,
        WifiInfoSource.web,
      ]) {
        final WifiSignalSampler sampler =
            WifiSignalSampler(source: s, macAdapter: const _FakeSnapshotAdapter());
        expect(sampler.isSupported, WifiSignalSampler.isSupportedSource(s),
            reason: 'instance isSupported diverged from the static predicate '
                'for $s');
        sampler.dispose();
      }
    });
  });

  // =======================================================================
  // PART B — the cross-screen invariant, table-driven over every case.
  // =======================================================================
  group('Part B — no consumer contradicts the SSOT', () {
    for (final _Case c in _allCases) {
      final String state = c.obtainable ? 'obtainable' : 'unavailable';
      testWidgets(
        '${c.consumer} on ${c.platform.label} ($state) stays honest',
        (WidgetTester tester) async {
          final _Built built = c.build();
          await _render(tester, built);
          c.verify(tester, obtainable: c.obtainable);
          // Unmount, THEN dispose the injected sampler inside the test body so
          // its live poll timer is cancelled before the framework's pending-
          // timer invariant runs (the screen never disposes an injected
          // sampler). Doing this in addTearDown would run too late.
          await tester.pumpWidget(const SizedBox());
          built.dispose?.call();
        },
      );
    }
  });
}
