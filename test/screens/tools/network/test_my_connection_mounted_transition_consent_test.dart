// THE MOUNTED TRANSITION — walking out of Wi-Fi range with the screen open.
// (Round-4 cold review, F-2. Keith, 2026-07-14.)
//
// The cellular-data consent gate had a hole big enough to spend 500 MB through,
// and it was open on the app's PRIMARY ENTRY POINT.
//
// Every existing consent test mounts the screen in its FINAL connectivity state:
// already on cellular, or already on Wi-Fi. Nothing covered the state CHANGING
// while the screen is mounted — which is not an exotic scenario, it is what
// happens when you walk out of Wi-Fi range holding your phone.
//
// THE BYPASS. `_run` computed `spendData` from `_notOnWifi`, but the only probe
// that refreshed `_notOnWifi` inside a run was a FIRE-AND-FORGET
// `_sampler?.load()` fired AFTER that decision. So:
//
//   1. mount on Wi-Fi          -> _notOnWifi = false
//   2. walk out of range       -> nothing re-probes; the screen never rebuilds
//   3. the cellular warning never renders, the button keeps its on-Wi-Fi label,
//      and the consent tap (`_throughputConsented = true`) therefore NEVER FIRES
//   4. tap Run                 -> spendData reads the STALE false -> TRUE
//   5. the full-rate download runs (~30 s, 50-500 MB of the user's cellular data)
//   6. the probe lands, and the RESULT renders "you're not connected to Wi-Fi"
//
// The app spent the data AND THEN TOLD YOU IT KNEW. `_autoStart` awaited the
// probe, which is exactly why the auto-run path was safe and why the auto-run
// path was the one that got tested. The button and "Run again" did not.
//
// These tests drive the transition itself. They go RED against the unfixed code.

import 'package:flutter/material.dart';
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

/// The native NWPathMonitor stays silent, so the verdict is driven through the
/// ADDRESS probe below — the seam this test can actually move at runtime. The
/// native path has its own coverage elsewhere.
class _NativeSilent implements WifiPathProbe {
  const _NativeSilent();
  @override
  Future<WifiPathFacts?> read() async => null;
}

/// THE WHOLE POINT OF THIS FILE: a link that CHANGES under the mounted screen.
///
/// Flip [onWifi] to false to model the user walking out of Wi-Fi range. On Wi-Fi
/// the interface carries an IPv4; on cellular it carries no address of either
/// family (the only shape permitted to assert `notOnWifi`).
class _FlippingNetworkInfo implements NetworkInfo {
  _FlippingNetworkInfo({this.onWifi = true});

  bool onWifi;

  @override
  Future<String?> getWifiIP() async => onWifi ? '192.168.1.20' : null;

  @override
  Future<String?> getWifiIPv6() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bridge implements WiFiDetailsBridge {
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<DateTime?> payloadReceivedAt() async => null;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<void> resetMonitoringColdStart() async {}
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async => true;
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> consumeShortcutMissing() async => false;
  @override
  Future<bool> hasInitiatedSetup() async => false;
  @override
  Future<void> markSetupInitiated() async {}
  @override
  Future<bool> isShortcutsAppInstalled() async => true;
  @override
  Future<void> setLiveOriginRoute(String route) async {}
  @override
  Future<String?> consumeLiveErrorNav() async => null;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDns extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async =>
      DnsProbeResult.success(host: 'cloudflare.com', millis: 12);
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

QualityResult _internet() => QualityResult(
      source: QualitySource.mock,
      measuredAt: DateTime.utc(2026, 1, 1),
      metrics: const <QualityMetric>[
        QualityMetric(
          id: MetricIds.latency,
          label: 'Latency',
          value: 42,
          unit: 'ms',
          grade: QualityGrade.fair,
        ),
        QualityMetric(
          id: MetricIds.download,
          label: 'Download',
          value: 60,
          unit: 'Mbps',
          grade: QualityGrade.fair,
        ),
      ],
    );

void main() {
  testWidgets(
    'WALK OUT OF WI-FI RANGE WITH THE SCREEN OPEN: the re-run must not spend '
    'cellular data the user was never asked about',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });

      // 1. MOUNT ON WI-FI. The screen auto-runs the full check, throughput and
      //    all — correct, and free.
      final _FlippingNetworkInfo net = _FlippingNetworkInfo(onWifi: true);
      final _Bridge bridge = _Bridge();
      final MockQualityClient quality =
          MockQualityClient(scriptedResult: _internet());
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: net,
          platformOverride: TargetPlatform.iOS,
          pathProbe: const _NativeSilent(),
        ),
      );
      addTearDown(sampler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            // The ROUTER mounts this screen with autoStart: true
            // (app_router.dart). A test that omits it is not testing the
            // screen the user actually gets.
            autoStart: true,
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
            qualityClient: quality,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: the on-Wi-Fi auto-run happened and DID spend throughput. If this
      // ever fails, the test is no longer exercising what it claims to.
      expect(quality.measureCalls, 1,
          reason: 'the on-Wi-Fi auto-run should have run once');
      expect(quality.lastIncludeThroughput, isTrue,
          reason: 'on Wi-Fi the full check runs, as it always has');

      // 2. THE USER WALKS OUT OF WI-FI RANGE. Nothing re-probes; the screen does
      //    not rebuild; the cellular warning is NOT on screen and the consent tap
      //    has NOT been made. This is the ordinary, un-exotic thing.
      net.onWifi = false;

      // 3. THE USER TAPS "Run again" on the result.
      final Finder runAgain = find.text('Run again');
      expect(runAgain, findsOneWidget);
      await tester.tap(runAgain);
      await tester.pumpAndSettle();
      // Drain the iOS RF auto-capture timer so the run completes cleanly.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // THE ASSERTION. The link is cellular and the user has consented to
      // nothing, so not one throughput byte may move.
      expect(quality.measureCalls, 2,
          reason: 'the re-run must still RUN — the cheap probes are free');
      expect(
        quality.lastIncludeThroughput,
        isFalse,
        reason: 'THE BYPASS: the run read a STALE not-on-Wi-Fi flag, refreshed '
            'only by a fire-and-forget probe fired AFTER the decision, and spent '
            'up to 500 MB of cellular data the user was never asked about — then '
            'told them it knew they were off Wi-Fi.',
      );
    },
  );

  testWidgets(
    'the downgraded re-run is still HONEST: it reports "Not measured", never '
    '"Couldn\'t check" — nothing failed, we simply did not spend the data',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LiveOnboardingService.prefsKey: true,
      });

      final _FlippingNetworkInfo net = _FlippingNetworkInfo(onWifi: true);
      final _Bridge bridge = _Bridge();
      final MockQualityClient quality =
          MockQualityClient(scriptedResult: _internet());
      final WifiSignalSampler sampler = WifiSignalSampler(
        source: WifiInfoSource.iosShortcuts,
        iosBridge: bridge,
        connectionService: WifiConnectionService(
          networkInfo: net,
          platformOverride: TargetPlatform.iOS,
          pathProbe: const _NativeSilent(),
        ),
      );
      addTearDown(sampler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: TestMyConnectionScreen(
            autoStart: true,
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
            qualityClient: quality,
          ),
        ),
      );
      await tester.pumpAndSettle();

      net.onWifi = false;
      await tester.tap(find.text('Run again'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      final StringBuffer buf = StringBuffer();
      for (final Element e in find.byType(Text).evaluate()) {
        final Text t = e.widget as Text;
        if (t.data != null) buf.writeln(t.data);
      }
      final String screen = buf.toString();

      // Zero throughput bytes moved.
      expect(quality.lastIncludeThroughput, isFalse);

      // And the result does not claim a failure that did not happen. The speed
      // test did not fail; it was never run. (GL-005, the two kinds of null.)
      expect(screen, contains('Not measured'));
      expect(screen, isNot(contains("Couldn't check")),
          reason: 'the speed test did not fail — we declined to spend the data');
    },
  );
}
