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
//   4. Heavy live screens driven end-to-end. The Network-at-a-glance card,
//      Roaming Log, and — as of the 2026-06-30 pre-launch pass — Wi-Fi
//      Information ARE pumped hermetically in Part B across the native snapshot
//      sources (macOS/Windows/Android) plus the Linux unsupported sentinel, so
//      an enum-list false-ceiling that denies a datum on a capable native
//      platform fails HERE, not just in each screen's own suite. What is still
//      NOT pumped end-to-end: the iOS-Shortcut / streaming paths — iOS Wi-Fi
//      Information's onboarding-bridge state machine, Test My Connection's
//      live-quality streaming, and the iOS-obtainable Cellular case — plus
//      Interface Info, whose per-source branch selects a MAC-label reason, not a
//      data ceiling. Those are anchored via Part A (the exact seams they
//      delegate to) plus their own suites; a full 5-platform pump of their
//      Shortcut/streaming machinery is brittle, so that split is deliberate.
//      HONEST LIMIT (do not overread): the source-scan delegation guard
//      (platform_gate_delegation_guard_test.dart) catches only a RAW
//      `TargetPlatform.` / `Platform.isX` gate — it does NOT catch an inline
//      `WifiInfoSource` enum-list gate, which was the ACTUAL C1/C2/C3 shape. For
//      the un-pumped iOS/streaming paths above, that enum-list residual rests on
//      their own suites, NOT on this harness or the delegation guard.
// ----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/cellular_info_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_glance_card.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/network_unavailable_view.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/roaming_log_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/wifi_info_screen.dart';
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
///
/// CAUTION (keep INDEPENDENT): this is a hand-maintained EXPECTATION, deliberately
/// spelled out as its own boolean expression. Part A cross-checks it against the
/// live seam (`WifiSignalSampler.isSupportedSource`). Never refactor this to call
/// that seam (or the resolver) — doing so makes the check `seam == seam`, a
/// tautology, and the harness silently stops catching seam drift. Same rule for
/// `expectedSignalCapable` in Part A below.
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
            // ON WI-FI. This invariant is about PLATFORM CAPABILITY ("can this
            // platform obtain an SSID?"), not about connectivity. The card now
            // also consults the not-on-Wi-Fi probe, so the precondition has to be
            // stated — otherwise the two get conflated, and "the platform cannot
            // read it" and "there is no network to read" are exactly the two
            // kinds of null this whole effort exists to keep apart (GL-005).
            connectionService: WifiConnectionService(
              networkInfo: _OnWifiNetworkInfo(),
              platformOverride: p.target,
              // ...and on iOS the PRIMARY signal is now the native path monitor,
              // so the "on Wi-Fi" precondition has to be stated THERE too. Leaving
              // it to an unregistered method channel would make this invariant
              // depend on a test-harness accident rather than on the stated setup.
              pathProbe: _OnWifiPath(),
            ),
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

// ---------------------------------------------------------------------------
// Consumer 4 — Wi-Fi Information (the heavy identity tool). Added 2026-06-30 to
// close the enum-list gap called out in the skip-note above: it IS hermetically
// pumpable on the native snapshot sources via the injected adapter (the same
// pattern its own suite uses), so a source-level enum-list false-ceiling — a
// capable native source wrongly rendered as "coming soon / not available" (the
// C2 Windows family) — fails HERE, not only in the screen's own suite.
//
// iOS is deliberately NOT pumped here: its onboarding-bridge state machine makes
// a clean "reading present, no ceiling" pump brittle, so iOS Wi-Fi identity
// stays anchored via Part A + the screen's own iOS suite (documented in skip-
// note #4). Web is compile-time `kIsWeb` only, like the glance card.
// ---------------------------------------------------------------------------
List<_Case> _wifiInfoCases() {
  final List<_Case> cases = <_Case>[];
  for (final _Platform p in _platforms) {
    // Native snapshot sources + the Linux unsupported sentinel only.
    if (p.wifi == WifiInfoSource.iosShortcuts) continue; // documented skip
    if (p.isWeb) continue; // compile-time kIsWeb
    final bool obtainable = _wifiIdentityObtainable(p.wifi);
    cases.add(_Case(
      consumer: 'Wi-Fi Information (identity)',
      platform: p,
      obtainable: obtainable,
      build: () => _Built(
        // A snapshot source auto-reads via the injected adapter; the Linux
        // sentinel (unsupported) ignores the adapter and renders the honest
        // "coming in a later update" state, never a fabricated reading.
        WifiInfoScreen(
          sourceOverride: p.wifi,
          macAdapter: const _FakeSnapshotAdapter(),
        ),
        settle: true,
      ),
      verify: (WidgetTester tester, {required bool obtainable}) {
        const String comingSoon = 'Coming in a later update';
        if (obtainable) {
          // A capable native source MUST render the real identity and MUST NOT
          // fall to the platform-unavailable ceiling. An enum-list gate that
          // excluded this source (the C2 shape) would trip both expectations.
          expect(find.text('WLANPros'), findsWidgets,
              reason: 'Wi-Fi Information hides the real SSID on ${p.label} while '
                  'the resolver marks the identity obtainable');
          expect(find.text(comingSoon), findsNothing,
              reason: 'Wi-Fi Information shows a FALSE platform ceiling on '
                  '${p.label} (capable native source)');
        } else {
          // No adapter for this platform → honest unavailable state, no guess.
          expect(find.text('WLANPros'), findsNothing,
              reason: 'Wi-Fi Information fabricated a reading on ${p.label} '
                  '(no adapter)');
          expect(find.text(comingSoon), findsOneWidget,
              reason: 'Wi-Fi Information must state its honest unavailable state '
                  'on ${p.label}');
        }
      },
    ));
  }
  return cases;
}

List<_Case> get _allCases => <_Case>[
      ..._glanceCases(),
      ..._roamingCases(),
      ..._cellularCases(),
      ..._wifiInfoCases(),
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

/// iOS reports a Wi-Fi path: the device is associated.
class _OnWifiPath implements WifiPathProbe {
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
        usesWifi: true,
        wifiSatisfied: true,
        wifiInterfacePresent: true,
      );
}

/// The ANDROID TRANSPORT channel (round-4b, 2026-07-14).
///
/// WHY A CONSISTENCY TEST HAS TO STUB THIS. `RoamingLogScreen.initState` builds a
/// `WifiSignalSampler` and calls `load()`, which — for the `androidWifiManager`
/// source — now settles the honest Wi-Fi verdict through `WifiConnectionService`,
/// whose Android branch invokes this channel. A Flutter widget test runs as
/// `TargetPlatform.android` by DEFAULT, so this fires here even though these cases
/// are about capability honesty, not cellular consent.
///
/// Unstubbed, the probe's 3-second `.timeout()` deadline is left as a PENDING TIMER
/// when the test tears down, and the pending-timer invariant fails the case. (The
/// sibling iOS `WifiPathProbe` has the identical deadline and never tripped this —
/// only because it is gated on `_platform == iOS`, which a widget test never is.)
///
/// `available: false` is the honest "could not read the transport" payload → the
/// verdict resolves to `unknown`, which is exactly what these screens saw on Android
/// before the probe existed. Behavior is preserved; the device model is now stated.
const MethodChannel _networkTransportChannel =
    MethodChannel('com.wlanpros.toolbox/network_transport');

void main() {
  setUpAll(() async {
    // Roaming Log / Cellular screens mount a ToolHelpFooter.
    await ToolHelpLoader.ensureLoaded();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _networkTransportChannel,
      (MethodCall call) async => <String, Object?>{'available': false},
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_networkTransportChannel, null);
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
      // CAUTION (keep INDEPENDENT): these are hand-maintained expectations, not
      // a mirror of the seam. Never refactor this map to be built from
      // `WifiSignalSampler.isSupportedSource` — that turns the assertion below
      // into `seam == seam` and the harness stops catching drift.
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

/// A device that IS on Wi-Fi (the Wi-Fi interface has an IPv4). Keeps the
/// platform-capability invariant about the PLATFORM, not about whether this
/// particular test device happens to have a link.
class _OnWifiNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '192.168.1.50';
  @override
  Future<String?> getWifiIPv6() async => 'fe80::10b4:5ba5:5d42:a691%en0';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
