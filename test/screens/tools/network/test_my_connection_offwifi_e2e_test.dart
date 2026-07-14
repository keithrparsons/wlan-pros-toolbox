// TEST MY CONNECTION, OFF WI-FI — the end-to-end guard on the flagship screen.
//
// WHY THIS FILE EXISTS (cold-eyes review F1, 2026-07-13). The stale-Wi-Fi fix
// shipped with its regression tests pointed at [WifiMonitorController] and the
// Wi-Fi Information screen — NOT at Test My Connection, which is the screen Keith
// actually hit the bug on. Test My Connection's iOS link read calls
// `WiFiDetailsBridge.readLatest()` DIRECTLY (see `_readLink`), bypassing the
// controller, so every controller-level test can pass while the front door still
// renders a stale Wi-Fi rate. The reviewer proved it: deleting the screen's two
// gate lines left all 3,359 screen/service tests green while the screen rendered
// "It's your Wi-Fi", "Your Wi-Fi link 29 Mbps", and "Wi-Fi network KeithHome" on a
// phone with no Wi-Fi at all.
//
// So this test drives the REAL screen, with a REAL [WifiSignalSampler] and a REAL
// [WifiMonitorController] over an off-Wi-Fi probe and Keith's actual stale App
// Group payload, and asserts on what a user would SEE and COPY. It is the guard on
// the lines that actually fix the reported bug.
//
// It covers three findings at once, because they all live on this one screen:
//   F1 — no stale rate, no stale SSID, no Wi-Fi verdict, no "boost your Wi-Fi".
//   F2 — no companion-Shortcut capture offer (button, copy note, or offer card).
//        A Shortcut cannot read a link that does not exist; offering it is the
//        SAME wrong-kind-of-null failure in a new costume.
//   F5 — the Shortcut is not FIRED at all (the producer, not just the consumer).

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
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A cellular-only iPhone: BOTH Wi-Fi address families read clean and empty.
/// This is the only shape that may assert `notOnWifi` — an IPv4-null alone does
/// NOT (an IPv6-only SSID reads null there while associated). See the KNOWN LIMITS
/// note in [WifiConnectionService] and
/// `test/services/network/wifi_connection_service_test.dart`.
class _CellularOnlyNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => null;
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The App Group's LAST STORED payload — Keith's real stale reading, captured the
/// last time the phone WAS on Wi-Fi, and still sitting there on cellular.
/// `readLatest()` hands it back forever; nothing in the bridge knows the link is
/// gone. Counts one-shot fires so F5 is measured, not assumed.
class _StaleBridge implements WiFiDetailsBridge {
  int oneShotCalls = 0;
  int runShortcutCalls = 0;
  bool monitoringFlag = false;

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

  /// The user HAS the companion Shortcut set up — this is every established user,
  /// and it is exactly who the old `&& !hasEverReceived` gates hid the honest
  /// state from.
  @override
  Future<bool> hasEverReceivedPayload() async => true;

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
  Future<bool> isMonitoringActive() async => monitoringFlag;
  @override
  Future<void> setMonitoringActive(bool active) async => monitoringFlag = active;
  @override
  Future<void> resetMonitoringColdStart() async => monitoringFlag = false;
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    return true;
  }

  @override
  Future<bool> runShortcutOneShot(String name) async {
    oneShotCalls++;
    return true;
  }

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

/// Cellular: NEHotspotNetwork resolves nothing, so there is no native SSID to
/// override the probe with. (A resolved SSID IS a definitive on-Wi-Fi signal.)
class _FakeSecurity extends WifiSecurityService {
  @override
  Future<WifiSecurityInfo> fetch() async =>
      const WifiSecurityInfo.unavailable('cellular: no Wi-Fi');
}

/// Fails open, so no real HTTPS lookup runs and the ISP section is omitted.
class _FakeIpGeo extends IpGeoService {
  @override
  Future<IpGeoResult> lookup({required String rawQuery}) async =>
      IpGeoResult.failure(query: rawQuery, message: 'offline in test');
}

/// A measured internet result over cellular: 60 Mbps down. Marginal, so the
/// engine does NOT take the grade gate and must reason about the Wi-Fi link —
/// which is precisely the path that produced "It's your Wi-Fi" from a stale rate.
QualityResult _cellularInternet() => QualityResult(
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

/// Mounts the real screen with a real iOS sampler + controller over the fakes,
/// runs one check, and settles.
Future<_StaleBridge> _runOffWifiCheck(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final _StaleBridge bridge = _StaleBridge();
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.iosShortcuts,
    iosBridge: bridge,
    connectionService: WifiConnectionService(
      networkInfo: _CellularOnlyNetworkInfo(),
      platformOverride: TargetPlatform.iOS,
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
        qualityClient: MockQualityClient(scriptedResult: _cellularInternet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Check My Connection'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  return bridge;
}

/// Every `Text` currently on screen, joined — the copy a user actually reads.
String _visibleText(WidgetTester tester) {
  final StringBuffer buf = StringBuffer();
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    if (t.data != null) buf.writeln(t.data);
  }
  return buf.toString();
}

void main() {
  group('Test My Connection, cellular-only iPhone with a stale App Group payload',
      () {
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
    testWidgets('F1: renders no stale Wi-Fi reading and no Wi-Fi verdict',
        (WidgetTester tester) async {
      await _runOffWifiCheck(tester);
      final String screen = _visibleText(tester);

      // The stale RF must not render ANYWHERE — not as a rate, not as an SSID.
      expect(screen, isNot(contains('KeithHome')),
          reason: 'the stale SSID must never render as the current network');
      expect(screen, isNot(contains('29')),
          reason: 'the stale 29 Mbps Tx rate must not appear on screen');
      expect(screen, isNot(contains('94:2a:6f')),
          reason: 'the stale BSSID must not render as the current AP');
      expect(screen, isNot(contains('-61')),
          reason: 'the stale RSSI must not render as a live signal');

      // The false verdict and the false advice must be gone.
      expect(screen, isNot(contains("It's your Wi-Fi")));
      expect(screen, isNot(contains('the air link is the limiter')));
      expect(screen, isNot(contains('Boost the Wi-Fi signal')));
      expect(screen.toLowerCase(), isNot(contains('looks like your wi-fi')));

      // The honest state must be NAMED. This is the other half of the fix: not
      // just "say less", but "say the true thing" (GL-005 — two kinds of null).
      expect(screen.toLowerCase(), contains('not connected to wi-fi'));
    });

    testWidgets(
        'F2: offers no companion-Shortcut capture — no Shortcut can read a link '
        'that does not exist', (WidgetTester tester) async {
      await _runOffWifiCheck(tester);
      final String screen = _visibleText(tester);

      // Surface 1 — the "Your Wi-Fi link" capture affordance (_WifiLinkSection).
      expect(screen, isNot(contains('Capture Wi-Fi details')),
          reason: 'there is no Wi-Fi link to capture on a cellular-only phone');
      expect(screen, isNot(contains('need a quick capture on iOS')));
      expect(find.widgetWithText(FilledButton, 'Capture Wi-Fi details'),
          findsNothing);

      // Surface 2 — the post-verdict Shortcut offer card (_ShortcutOfferCard).
      expect(screen, isNot(contains('Want a deeper Wi-Fi check?')));
      expect(screen, isNot(contains('Add the companion Shortcut')));
      expect(screen, isNot(contains('Set up live Wi-Fi to read your signal')));

      // Nothing on screen may send this user to the Shortcut at all.
      expect(screen.toLowerCase(), isNot(contains('companion shortcut')),
          reason: 'the Shortcut is not the missing piece; a Wi-Fi network is');
    });

    testWidgets('F2: the copy report names the real state and never the Shortcut',
        (WidgetTester tester) async {
      await _runOffWifiCheck(tester);

      // The help-desk card's copy action serializes exactly what the screen shows.
      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(clipboardWrites, isNotEmpty,
          reason: 'the copy report must be produced');
      final String report = clipboardWrites.last;

      expect(report.toLowerCase(), isNot(contains('shortcut')),
          reason: 'the report must not tell a help desk to run a Shortcut for a '
              'Wi-Fi link that does not exist');
      expect(report, isNot(contains('Capture Wi-Fi details')));
      expect(report, isNot(contains('KeithHome')));
      expect(report, isNot(contains('29 Mbps')));

      // The WI-FI section's own note must name the real state. Asserted on the
      // note's exact wording, NOT on a loose "not connected to Wi-Fi" — that
      // phrase also appears in the VERDICT section, so a loose match stayed green
      // with the note deleted (caught by mutating the note's guard to `false`).
      expect(
        report,
        contains('was not connected to Wi-Fi when the check ran'),
        reason: 'the WI-FI section must say WHY its rows are empty: there was no '
            'link, not a failed read (GL-005 — the two kinds of null)',
      );
      // The internet side is untouched: it WAS measured, over cellular.
      expect(report, contains('Internet Down'));

      // Drain the copy button's 1.5s "Copied" confirmation timer.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('F5: the companion Shortcut is never FIRED off Wi-Fi',
        (WidgetTester tester) async {
      final _StaleBridge bridge = await _runOffWifiCheck(tester);

      // The reviewer measured TWO fires per off-Wi-Fi check (the auto-capture plus
      // its no-reading retry). Each is an app-switch to Shortcuts for a read that
      // cannot succeed, and each starves the concurrent throughput measurement.
      expect(bridge.oneShotCalls, 0,
          reason: 'a cellular-only check must not bounce the user into the '
              'Shortcuts app to harvest a Wi-Fi link that does not exist');
      expect(bridge.runShortcutCalls, 0,
          reason: 'nor may it start the continuous monitoring loop');
    });
  });
}
