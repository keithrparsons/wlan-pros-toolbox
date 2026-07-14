// THE CELLULAR-DATA CONSENT GATE (Keith, 2026-07-13).
//
// WHY THIS EXISTS. The speed test is NOT byte-bounded. Both data-hungry stages
// download for a fixed WINDOW at whatever rate the link achieves:
//
//   * ThroughputProbe.maxDuration = 15 s, and `_downloadOnce` LOOPS sized requests
//     back-to-back until that window closes. Five concurrent streams.
//   * The responsiveness (RPM) probe's load generator is ANOTHER full-window
//     single-flow download (`runResilientRpmLoad`) — a second ~15 s at rate.
//   * Only the upload is capped (uploadBytes = 10 MB).
//
// So the app downloads at full speed for ~30 s, and the bytes scale with the link:
// ~48 MB at 10 Mbps, ~385 MB at 100 Mbps, ~1.1 GB at 300 Mbps. Keith travels
// constantly and is about to run a conference gig; a Wi-Fi professional abroad on
// an expensive roaming plan must never have an app silently burn that.
//
// THE CONTRACT UNDER TEST:
//   1. On CELLULAR (a POSITIVE not-on-Wi-Fi probe): warn, and require an explicit
//      tap before any throughput byte moves.
//   2. On WI-FI: nothing changes. No warning, no new tap.
//   3. On UNKNOWN (an ambiguous probe, a wired Mac, any non-iOS platform): nothing
//      changes either. An ambiguous read must never nag a user on Wi-Fi — that is
//      the same over-claiming this whole release exists to remove.
//   4. Declining still produces a USEFUL result: latency, loss, DNS, reachability
//      and the honest not-on-Wi-Fi state all still run. Only the data-hungry
//      stages are withheld, and they read "Not measured", never "Couldn't check" —
//      nothing failed.

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

/// Cellular-only: the Wi-Fi interface carries no address of either family. The
/// only shape that may assert `notOnWifi` (see WifiConnectionService KNOWN LIMITS).
/// "iOS did not answer." These tests are about the CELLULAR-DATA CONSENT GATE, not
/// about the Wi-Fi-detection mechanism, and they drive it through the ADDRESS probe
/// (the `NetworkInfo` fakes below). Round 4 made the native NWPathMonitor the
/// PRIMARY signal on iOS, so the address probe is now only reached when the native
/// path is silent — and that precondition has to be STATED here, not left to an
/// unregistered method channel in the test harness.
///
/// The native path has its own dedicated coverage in
/// `test/services/network/wifi_connection_service_test.dart` and the off-Wi-Fi E2E.
class _NativeSilent implements WifiPathProbe {
  const _NativeSilent();
  @override
  Future<WifiPathFacts?> read() async => null;
}

class _CellularOnly implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// On Wi-Fi: a Wi-Fi IPv4 is a definitive on-Wi-Fi signal.
class _OnWifi implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '192.168.1.42';
  @override
  Future<String?> getWifiIPv6() async => 'fe80::10b4:5ba5:5d42:a691%en0';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The AMBIGUOUS probe: the read THROWS, so the verdict is `unknown`. The user may
/// well be on Wi-Fi, so they must not be warned about cellular data.
class _AmbiguousNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => throw Exception('denied');
  @override
  Future<String?> getWifiIPv6() async => throw Exception('denied');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Bridge implements WiFiDetailsBridge {
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
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<WiFiDetails?> readLatest() async => null;
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

/// 60 Mbps down / 20 up, plus latency + loss — the cheap samples that survive a
/// declined speed test.
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

/// Mounts the real screen over the given connectivity shape and settles to the
/// PRE-RUN state (nothing tapped yet). Returns the quality client so the test can
/// assert what the screen ASKED FOR.
Future<MockQualityClient> _pumpPreRun(
  WidgetTester tester,
  NetworkInfo net, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final _Bridge bridge = _Bridge();
  final MockQualityClient quality =
      MockQualityClient(scriptedResult: _internet());
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.iosShortcuts,
    iosBridge: bridge,
    connectionService: WifiConnectionService(
      networkInfo: net,
      platformOverride: platform,
      pathProbe: const _NativeSilent(),
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
        qualityClient: quality,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return quality;
}

void main() {
  group('cellular: warn before spending the data', () {
    testWidgets('the PRE-RUN screen states the data cost and offers a way out',
        (WidgetTester tester) async {
      await _pumpPreRun(tester, _CellularOnly());
      final String screen = _visibleText(tester);

      // The cost, stated honestly as a RANGE and by MECHANISM, because it genuinely
      // depends on link speed and we cannot know it before the test runs (GL-005 —
      // no invented figure).
      expect(screen, contains("You're on cellular."));
      expect(screen, contains('downloads at full speed for about 30 seconds'));
      expect(screen, contains('roughly 50 MB'));
      expect(screen, contains('500 MB or more on fast 5G'));

      // The consent tap is labeled with its cost, and the decline path exists.
      expect(find.text('Check My Connection (uses data)'), findsOneWidget);
      expect(find.text('Check without the speed test'), findsOneWidget);
    });

    testWidgets('NO throughput byte moves until the user consents',
        (WidgetTester tester) async {
      // The gate is only real if the data-hungry stages are never even REQUESTED.
      final MockQualityClient quality =
          await _pumpPreRun(tester, _CellularOnly());

      await tester.tap(find.text('Check without the speed test'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(quality.lastIncludeThroughput, isFalse,
          reason: 'declining must not run the speed test at all — not a smaller '
              'one, not a shorter one. No bytes.');
    });

    testWidgets('consenting DOES run the speed test',
        (WidgetTester tester) async {
      final MockQualityClient quality =
          await _pumpPreRun(tester, _CellularOnly());

      await tester.tap(find.text('Check My Connection (uses data)'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(quality.lastIncludeThroughput, isTrue,
          reason: 'an explicit tap on the labeled button IS the consent');
      expect(_visibleText(tester), contains('60'),
          reason: 'and the measured speed is reported');
    });

    testWidgets(
        'declining still produces a USEFUL result, and says "Not measured" — '
        'never "Couldn\'t check"', (WidgetTester tester) async {
      await _pumpPreRun(tester, _CellularOnly());

      await tester.tap(find.text('Check without the speed test'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final String screen = _visibleText(tester);

      // The cheap probes still ran, and their real values are reported. "It must
      // not say Couldn't check for things we did check."
      expect(screen, contains('42'), reason: 'latency was measured and reported');
      expect(screen, contains('12 ms (cloudflare.com)'),
          reason: 'the DNS probe still ran');

      // The honest not-on-Wi-Fi state still works.
      expect(screen.toLowerCase(), contains('not connected to wi-fi'));

      // THE WORD. Nothing failed: the user chose not to measure. "Couldn't check"
      // would be a false claim of incapacity — the same lie as the Wi-Fi chip,
      // arrived at from the opposite direction.
      expect(screen, contains('Not measured'),
          reason: 'a measurement we chose not to take is not one we failed to '
              'take (AxisStatus.notMeasured)');
      expect(screen, isNot(contains("Couldn't check")),
          reason: 'the speed test did not fail. It was never run.');

      // And the copy must not invite them to spend the data they just declined.
      expect(screen, isNot(contains('did not complete')),
          reason: 'a test that never ran did not "fail to complete"');
      expect(screen, isNot(contains('Try again in a moment')));
    });
  });

  group('on Wi-Fi and on an AMBIGUOUS probe: nothing changes', () {
    testWidgets('ON WI-FI there is no warning and no extra tap',
        (WidgetTester tester) async {
      final MockQualityClient quality = await _pumpPreRun(tester, _OnWifi());
      final String screen = _visibleText(tester);

      expect(screen, isNot(contains("You're on cellular.")));
      expect(screen, isNot(contains('roughly 50 MB')));
      expect(find.text('Check without the speed test'), findsNothing);
      // The original, unchanged affordance.
      expect(find.text('Check My Connection'), findsOneWidget);

      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(quality.lastIncludeThroughput, isTrue,
          reason: 'on Wi-Fi the speed test runs exactly as before, one tap');
    });

    testWidgets(
        'an AMBIGUOUS probe (unknown) must NOT nag — it is not proof of cellular',
        (WidgetTester tester) async {
      // The read THROWS -> WifiConnectionStatus.unknown. The user may well be on
      // Wi-Fi. Warning them about cellular data on an ambiguous read would be a
      // false claim, and would nag every wired desktop forever. `unknown` means
      // "assert nothing" — including this.
      final MockQualityClient quality =
          await _pumpPreRun(tester, _AmbiguousNetworkInfo());
      final String screen = _visibleText(tester);

      expect(screen, isNot(contains("You're on cellular.")),
          reason: 'an ambiguous probe is not a positive cellular signal');
      expect(find.text('Check without the speed test'), findsNothing);
      expect(find.text('Check My Connection'), findsOneWidget);

      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(quality.lastIncludeThroughput, isTrue);
    });

    testWidgets('a wired MAC (non-iOS -> unknown) is untouched',
        (WidgetTester tester) async {
      await _pumpPreRun(
        tester,
        _CellularOnly(), // no Wi-Fi IP, but macOS -> ambiguous, never notOnWifi
        platform: TargetPlatform.macOS,
      );
      expect(_visibleText(tester), isNot(contains("You're on cellular.")));
      expect(find.text('Check without the speed test'), findsNothing);
    });
  });
}
