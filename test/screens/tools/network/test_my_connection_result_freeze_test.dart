// A COMPLETED CHECK IS A DATED REPORT, NOT A LIVE READOUT (cold-eyes F4).
//
// THE BUG THIS GUARDS (2026-07-13). Run a check at home ON Wi-Fi. Walk to the car.
// The app resumes, `didChangeAppLifecycleState` re-runs the connection probe, and
// the LIVE not-on-Wi-Fi flag flips true. Before this fix the result body read that
// live flag directly, so:
//
//   * every Wi-Fi row of the completed result vanished, and the copy report's
//     entire Wi-Fi block was replaced by a "tap Capture Wi-Fi details" note, while
//   * the verdict card — which `_onSamplerChanged` never recomputed — still read
//     "It's your Wi-Fi / the air link is the limiter."
//
// A legitimately-taken reading was discarded, and the screen contradicted itself.
//
// THE FIX, AND WHY THIS ONE. The completed result is FROZEN against the probe
// state of its own run (`_resultNotOnWifi` / `_resultAp`), stamped once in `onDone`.
// The alternative — recompute the verdict on resume — would replace a TRUE finding
// ("your Wi-Fi link was the limiter at 14:32") with a FALSE one ("there was no
// Wi-Fi to check"), which is the same class of lie the whole not-on-Wi-Fi effort
// exists to remove. The result is already stamped "Tested: <time>".
//
// The LIVE Wi-Fi-signal card keeps reading the live probe and honestly says
// "You are not on Wi-Fi right now" — so both truths sit on screen without
// contradicting each other: one is dated, one is live. That is asserted here too.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A phone that starts ON Wi-Fi and can be walked off it mid-test.
///
/// It models the device from BOTH views the probe now consults — the addresses
/// (`NetworkInfo`) and iOS's own network path (`WifiPathProbe`, round 4) — because
/// a real phone that leaves Wi-Fi loses both at once. Wiring only one of them would
/// let the test walk off Wi-Fi in one view while still holding a Wi-Fi link in the
/// other, which is not a state any device can be in.
class _MovableNetworkInfo implements NetworkInfo, WifiPathProbe {
  String? wifiIp = '192.168.1.42';
  String? wifiIpv6;

  /// What iOS's NWPathMonitor sees. Starts associated; `leaveWifi` drops it.
  bool _onWifi = true;

  void leaveWifi() {
    wifiIp = null;
    wifiIpv6 = null;
    _onWifi = false;
  }

  @override
  Future<WifiPathFacts?> read() async => WifiPathFacts(
        usesWifi: _onWifi,
        wifiSatisfied: _onWifi,
        wifiInterfacePresent: _onWifi,
      );

  @override
  Future<String?> getWifiIP() async => wifiIp;
  @override
  Future<String?> getWifiIPv6() async => wifiIpv6;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The App Group payload — a REAL reading, harvested while genuinely on Wi-Fi.
/// Tx 29 / Rx 13 against 60 Mbps of internet puts the engine on the `wifiLimiter`
/// branch, which is the exact verdict that was left stranded on screen after the
/// Wi-Fi rows beneath it were blanked.
class _HomeBridge implements WiFiDetailsBridge {
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;

  // Scene-teardown restore seam. Default = NO pending run, so every pre-existing
  // test keeps asserting the app does NOT drag the user into a tool. They are the
  // counterweight net for the restore.
  @override
  Future<void> armLiveRun(String route) async {}
  @override
  Future<PendingLiveRun?> pendingLiveRun() async => null;
  @override
  Future<void> clearLiveRun() async {}
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<DateTime?> payloadReceivedAt() async => null;
  @override
  Future<WiFiDetails?> readLatest() async => const WiFiDetails(
        ssid: 'KeithHome',
        bssid: '94:2a:6f:a0:a5:5d',
        channel: 44,
        rssi: -61,
        noise: -95,
        standard: '802.11ax - Wi-Fi 6',
        rxRate: 13,
        txRate: 29,
      );
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<void> resetMonitoringColdStart() async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// ON Wi-Fi, but the link RATES were never read.
///
/// This is a REAL and common iOS shape, not a contrivance: the Shortcut payload
/// carries SSID / BSSID / RSSI / channel, and the negotiated Tx/Rx rates can be
/// absent. It matters here because it is the ONLY shape in which the engine's
/// `notOnWifi` flag actually CHANGES the verdict: with no rate there is no
/// `WifiRateBasis`, so the engine takes its `wifiUnknown` branch — and that branch
/// is the one that reads `notOnWifi` to choose between
///
///   "the Wi-Fi link rate could not be read"   (true: we were on Wi-Fi)
///   "this device is not on Wi-Fi"             (FALSE: we were on Wi-Fi)
///
/// With rates present the engine reports `wifiLimiter` and never consults the
/// flag — which is exactly why my first attempt at this test passed against the
/// mutated line and proved nothing. Recorded because it is the same trap as
/// [[feedback_tests_that_cannot_fail]]: a test that cannot fail is not a test.
class _HomeBridgeNoRates extends _HomeBridge {
  @override
  Future<WiFiDetails?> readLatest() async => const WiFiDetails(
        ssid: 'KeithHome',
        bssid: '94:2a:6f:a0:a5:5d',
        channel: 44,
        rssi: -61,
        noise: -95,
        standard: '802.11ax - Wi-Fi 6',
        // No rxRate / txRate: the link is real, its rates were not read.
      );
}

class _FakeDns extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async =>
      DnsProbeResult.success(host: 'cloudflare.com', millis: 12);
}

/// A DNS probe that does not answer until the test says so.
///
/// This is the seam for the SECOND half of F4. The three "you're online" evidence
/// signals (DNS, public IP, cloud reachability) land ASYNC and each one calls
/// `_recomputeVerdict()` as it arrives — which re-derives the verdict from a
/// notOnWifi flag. If that recompute reads the LIVE probe instead of the flag
/// STAMPED on the run, a signal that lands after the user has walked off Wi-Fi
/// silently rewrites a completed, honest on-Wi-Fi result into "there is no Wi-Fi
/// link" — while the frozen `_resultAp` keeps rendering the Wi-Fi rows right
/// beside it. Holding the DNS answer open lets the test land that evidence at the
/// exact moment the phone is off Wi-Fi.
class _LateDns extends DnsProbeService {
  final Completer<DnsProbeResult> _gate = Completer<DnsProbeResult>();

  /// Deliver the DNS evidence NOW (fires `_recomputeVerdict`).
  void land() =>
      _gate.complete(DnsProbeResult.success(host: 'cloudflare.com', millis: 12));

  @override
  Future<DnsProbeResult> measure() => _gate.future;
}

class _FakeNetDetails extends NetworkDetailsService {
  @override
  Future<NetworkDetails> read() async => const NetworkDetails();
}

class _FakeSecurity extends WifiSecurityService {
  @override
  Future<WifiSecurityInfo> fetch() async =>
      const WifiSecurityInfo.unavailable('no native read in test');
}

class _FakeIpGeo extends IpGeoService {
  @override
  Future<IpGeoResult> lookup({required String rawQuery}) async =>
      IpGeoResult.failure(query: rawQuery, message: 'offline in test');
}

QualityResult _internet60() => QualityResult(
      source: QualitySource.mock,
      measuredAt: DateTime.utc(2026, 1, 1),
      metrics: const <QualityMetric>[
        QualityMetric(
          id: MetricIds.latency,
          label: 'Latency',
          value: 60,
          unit: 'ms',
          grade: QualityGrade.fair,
        ),
        QualityMetric(
          id: MetricIds.loss,
          label: 'Loss',
          value: 1,
          unit: '%',
          grade: QualityGrade.fair,
        ),
        QualityMetric(
          id: MetricIds.download,
          label: 'Download',
          value: 60,
          unit: 'Mbps',
          grade: QualityGrade.fair,
        ),
        QualityMetric(
          id: MetricIds.upload,
          label: 'Upload',
          value: 20,
          unit: 'Mbps',
          grade: QualityGrade.fair,
        ),
      ],
    );

String _visibleText(WidgetTester tester) {
  final StringBuffer buf = StringBuffer();
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    if (t.data != null) buf.writeln(t.data);
  }
  return buf.toString();
}

void main() {
  group('a completed ON-Wi-Fi result survives the phone leaving Wi-Fi', () {
    late List<String> clipboardWrites;

    setUp(() {
      clipboardWrites = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          clipboardWrites.add(args['text'] as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
        'the reading and the verdict stay, and stay consistent, after a resume '
        'off Wi-Fi', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final _MovableNetworkInfo net = _MovableNetworkInfo();
      final _HomeBridge bridge = _HomeBridge();
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: net,
          platformOverride: TargetPlatform.iOS,
          pathProbe: net,
        ),
      );
      addTearDown(sampler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: bridge,
            sampler: sampler,
            securityService: _FakeSecurity(),
            dnsProbeService: _FakeDns(),
            networkDetailsService: _FakeNetDetails(),
            ipGeoService: _FakeIpGeo(),
            enableCloudApps: false,
            onboardingService:
                LiveOnboardingService(getStore: SharedPreferences.getInstance),
            qualityClient: MockQualityClient(scriptedResult: _internet60()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ---- AT HOME, ON WI-FI: run the check. ----
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final String onWifi = _visibleText(tester);
      expect(onWifi, contains('29'),
          reason: 'sanity: the on-Wi-Fi run must render its Wi-Fi Up rate');
      expect(onWifi, contains("It's your Wi-Fi"),
          reason: 'sanity: Tx 29 / Rx 13 vs 60 Mbps is the wifiLimiter branch');

      // ---- WALK TO THE CAR. The phone drops to cellular; the app resumes. ----
      net.leaveWifi();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final String afterResume = _visibleText(tester);

      // 1. The probe DID move — the LIVE card tells the truth about right now.
      //    (If this fails, the test is not exercising the resume at all.)
      expect(sampler.notOnWifi, isTrue,
          reason: 'sanity: the resume must have re-run the probe');
      expect(afterResume, contains("You're not connected to Wi-Fi"),
          reason: 'the live signal card must report the CURRENT state honestly');

      // 2. The dated reading is NOT discarded. It was taken on Wi-Fi and it is
      //    still true of the moment it was taken.
      expect(afterResume, contains('29'),
          reason: 'a legitimately-taken Wi-Fi reading must not be deleted '
              'because the phone later left the network');

      // 3. The verdict that reading produced is still there — so the screen does
      //    not read "It\'s your Wi-Fi" over a blanked Wi-Fi block.
      expect(afterResume, contains("It's your Wi-Fi"));

      // 4. NO capture prompt: the result HAS its RF, and there is nothing to fix.
      expect(afterResume, isNot(contains('Capture Wi-Fi details')));

      // 5. The copy report matches the screen — the same frozen snapshot.
      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();
      final String report = clipboardWrites.last;
      expect(report, contains('Wi-Fi Up (Tx rate): 29 Mbps'),
          reason: 'the report must still carry the Wi-Fi block it measured');
      expect(report, contains('KeithHome'));
      expect(report.toLowerCase(), isNot(contains('shortcut')),
          reason: 'the completed report has its RF; nothing to capture');
      expect(report, isNot(contains('was not connected to Wi-Fi when the check '
          'ran')),
          reason: 'the check DID run on Wi-Fi; the report must not claim it did '
              'not');

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets(
        'late DNS evidence landing AFTER the phone leaves Wi-Fi does not rewrite '
        'the completed verdict', (WidgetTester tester) async {
      // THE HOLE ROUND 2 LEFT (cold-eyes HIGH-2, 2026-07-13). The test above walks
      // the phone off Wi-Fi but never lands any late evidence, so it never calls
      // `_recomputeVerdict()` — and the `notOnWifi:` argument inside it went
      // UNCOVERED. Flipping that one line from the run's stamped `_resultNotOnWifi`
      // to the live `_notOnWifi` left the entire 4,133-test suite green.
      //
      // What that mutation does to a user: check your connection at home on Wi-Fi,
      // walk out to the car, and a DNS/ISP/cloud signal that was still in flight
      // lands on cellular. The verdict card rewrites itself to "there is no Wi-Fi
      // link" — while the frozen Wi-Fi rows (SSID, 29 Mbps, -61 dBm) are still
      // rendered directly beneath it. The screen contradicts itself, and the
      // half that changed is the half that is now WRONG: the check DID run on
      // Wi-Fi.
      //
      // This test lands that evidence at exactly that moment.
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });
      final _MovableNetworkInfo net = _MovableNetworkInfo();
      // Rate-less ON-Wi-Fi payload: the shape in which `notOnWifi` actually steers
      // the verdict. See [_HomeBridgeNoRates].
      final _HomeBridge bridge = _HomeBridgeNoRates();
      final _LateDns dns = _LateDns();
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: net,
          platformOverride: TargetPlatform.iOS,
          pathProbe: net,
        ),
      );
      addTearDown(sampler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: bridge,
            sampler: sampler,
            securityService: _FakeSecurity(),
            dnsProbeService: dns,
            networkDetailsService: _FakeNetDetails(),
            ipGeoService: _FakeIpGeo(),
            enableCloudApps: false,
            onboardingService:
                LiveOnboardingService(getStore: SharedPreferences.getInstance),
            qualityClient: MockQualityClient(scriptedResult: _internet60()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ---- AT HOME, ON WI-FI: run the check. DNS is still in flight. ----
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // SANITY, and it is load-bearing. The completed run must be on the engine's
      // `wifiUnknown` branch (no rate → no basis) with `notOnWifi: FALSE`, because
      // that is the only branch where the line under test can change anything. If
      // this assertion ever stops holding, the test below silently stops testing.
      final String onWifi = _visibleText(tester);
      expect(onWifi, contains('Wi-Fi link not measured'),
          reason: 'sanity: a rate-less ON-Wi-Fi run must read "could not be '
              'read", which is TRUE — we were on Wi-Fi');
      expect(onWifi, isNot(contains('Not connected to Wi-Fi')),
          reason: 'sanity: the run was ON Wi-Fi');

      // ---- WALK TO THE CAR. Cellular now. ----
      net.leaveWifi();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(sampler.notOnWifi, isTrue,
          reason: 'sanity: the resume must have flipped the LIVE probe, or this '
              'test is not exercising the race at all');

      // ---- THE IN-FLIGHT DNS LOOKUP NOW LANDS, ON CELLULAR. ----
      // This is the line that calls `_recomputeVerdict()`.
      dns.land();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final String after = _visibleText(tester);

      // 1. THE LINE UNDER TEST. The verdict is the one the CHECK earned, derived
      //    from the probe state of ITS OWN RUN. The Wi-Fi rate could not be read —
      //    that is true, and it stays true. Rewriting it to "this device is not on
      //    Wi-Fi" would be a FALSE statement about a check that ran on Wi-Fi.
      expect(after, contains('Wi-Fi link not measured'),
          reason: 'a late evidence signal must re-derive the verdict for the '
              'check that was TAKEN — it must never rewrite a completed '
              'on-Wi-Fi result into "there is no Wi-Fi link" because the phone '
              'has since moved');
      expect(after, contains('We checked your internet, but not your Wi-Fi.'),
          reason: 'and the consumer headline must not flip to the not-on-Wi-Fi '
              'wording either: the check DID have Wi-Fi');

      // 2. The screen does not contradict itself: the link the verdict is ABOUT
      //    is still rendered alongside it, not blanked into "there is no Wi-Fi
      //    link to report".
      expect(after, contains('KeithHome'),
          reason: 'the verdict and the reading it was derived from must survive '
              'together or not at all');
      expect(after, isNot(contains('there is no Wi-Fi link to report')),
          reason: 'there WAS a Wi-Fi link. Saying otherwise discards a real '
              'reading and contradicts the SSID still on screen.');

      // 3. The result must never claim the check ran off Wi-Fi. It did not.
      expect(
        after.toLowerCase(),
        isNot(contains('was not connected to wi-fi when the check ran')),
      );

      // 4. The LIVE card still tells the truth about RIGHT NOW — both truths
      //    coexist, one dated and one live, which is the whole point of F4.
      expect(after, contains("You're not connected to Wi-Fi"));
    });
  });
}
