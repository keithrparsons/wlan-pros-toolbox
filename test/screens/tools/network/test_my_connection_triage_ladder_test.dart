// Triage ladder wiring on the REAL Test My Connection screen: the ladder sits
// between the verdict line and the Analyze button, names where the trouble looks
// like it sits, and reaches both Copy payloads and the Analyze screen.
//
// Harness copied from internet_unreachable_render_test.dart (same fakes).

// "WI-FI IS UP, THE INTERNET IS DOWN" — ON THE REAL SCREEN, NOT THE ENGINE.
//
// ============================================================================
// THE LAYER THAT WAS VERIFIED WAS NOT THE LAYER THAT RUNS (round 5 CRITICAL).
// ============================================================================
//
// The engine (`internet_unreachable_test.dart`) proved that `internetUnreachable`
// and `captivePortal` are CORRECT — by feeding `OnlineEvidence` LITERALS straight in.
// But the SCREEN could never PRODUCE that evidence:
//
//   * `OnlineEvidence.isOffline` / `.isCaptivePortal` both require
//     `publicIpObtained == false`.
//   * `publicIpObtained` was derived from `_ispInfo`.
//   * `_fetchIspInfo` stored the lookup ONLY on success — a FAILED lookup left
//     `_ispInfo` null, so `publicIpObtained` yielded `null` (UNANSWERED), NEVER
//     `false` (ANSWERED-NO).
//
// On a dead internet the ISP lookup FAILS. So `publicIpObtained` stayed null,
// `isOffline` stayed false, the engine fell back to `wifiUnknown`, and Keith's exact
// conference frame STILL rendered "Couldn't complete the check / Make sure you're
// connected to Wi-Fi" — with the Wi-Fi rate printing two inches below. BOTH new
// verdicts were unreachable in production.
//
// NO WIDGET TEST DROVE `_onlineEvidence` WITH A REAL FAILED LOOKUP. This file does.
// It drives the REAL screen, ON Wi-Fi, with a REAL working link (Keith's Tx 97 /
// Rx 77), a FAILING DnsProbeService, a FAILING IpGeoService, and an UNREACHABLE
// cloud-apps probe, and asserts THE RENDER — not the engine. It is RED against
// 34cb906 (the screen renders "Couldn't complete the check").
//
// The evidence lands through the LATE writer — the cloud-apps panel's `onResults` →
// `_recomputeVerdict` — which is the exact production path Keith hit, and the one the
// off-Wi-Fi suite proved is the real chokepoint. We assert the state AFTER it fires.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';
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

/// An iPhone genuinely ON Wi-Fi: the path monitor says the route runs over Wi-Fi,
/// and the interface holds an IPv4. `notOnWifi` is false; the working link renders.
class _OnWifiPath implements WifiPathProbe {
  const _OnWifiPath();
  @override
  Future<WifiPathFacts?> read() async => const WifiPathFacts(
    usesWifi: true,
    wifiSatisfied: true,
    wifiInterfacePresent: true,
  );
}

/// On Wi-Fi, so the address probe reads a real IPv4 (belt-and-braces with the path).
class _OnWifiNetworkInfo implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '10.0.20.14';
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Keith's ACTUAL conference link: Tx 97 / Rx 77 Mbps, a Ubiquiti AP, plainly
/// associated. avg(97,77)=87 -> 0.55*87 = 47.85 -> "48 Mbps" usable, "Moderate" tier.
/// A WORKING link. The whole point is that the app stopped blaming it.
class _WorkingLinkBridge implements WiFiDetailsBridge {
  int oneShotCalls = 0;
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
    ssid: 'Tom-Hildebrand-Science-Project',
    bssid: '94:2a:6f:a0:a5:5d',
    channel: 44,
    rssi: -58,
    noise: -95,
    standard: '802.11ax - Wi-Fi 6',
    rxRate: 77,
    txRate: 97,
  );

  @override
  Future<bool> isMonitoringActive() async => monitoringFlag;
  @override
  Future<void> setMonitoringActive(bool active) async =>
      monitoringFlag = active;
  @override
  Future<void> resetMonitoringColdStart() async => monitoringFlag = false;
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Future<bool> runShortcutOneShot(String name) async {
    oneShotCalls++;
    return true;
  }

  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// DNS resolution FAILS — a definitive "no" for the online-evidence axis.
class _FailingDns extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async => DnsProbeResult.unavailable();
}

/// DNS resolution SUCCEEDS — the captive-portal signature needs this "yes".
class _WorkingDns extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async =>
      DnsProbeResult.success(host: 'cloudflare.com', millis: 11);
}

class _FakeNetDetails extends NetworkDetailsService {
  @override
  Future<NetworkDetails> read() async => const NetworkDetails();
}

/// On Wi-Fi, so no native-SSID override is needed; the path probe carries it.
class _FakeSecurity extends WifiSecurityService {
  @override
  Future<WifiSecurityInfo> fetch() async => const WifiSecurityInfo.unavailable(
    'not needed in test',
    locationAuth: LocationAuthStatus.notDetermined,
  );
}

/// THE ISP LOOKUP FAILS. On 34cb906 this is DISCARDED and `publicIpObtained` stays
/// null forever — the exact bug. `IpGeoService` never throws; it returns a failure
/// result, so this is the `isError == true` path (the one `_fetchIspInfo` dropped).
class _FailingIpGeo extends IpGeoService {
  @override
  Future<IpGeoResult> lookup({required String rawQuery}) async =>
      IpGeoResult.failure(
        query: rawQuery,
        message: 'no public IP (dead internet)',
      );
}

/// A stalled speed test: the QualityResult exists (so `_recomputeVerdict` does not
/// early-return on `_internet == null`) but every metric is UNAVAILABLE, so the
/// engine's download figure is null — "we ran the test and got nothing", the dead
/// internet's own shape.
QualityResult _stalledInternet() => QualityResult(
  source: QualitySource.mock,
  measuredAt: DateTime.utc(2026, 1, 1),
  metrics: const <QualityMetric>[
    QualityMetric.unavailable(
      id: MetricIds.latency,
      label: 'Latency',
      unit: 'ms',
    ),
    QualityMetric.unavailable(id: MetricIds.loss, label: 'Loss', unit: '%'),
    QualityMetric.unavailable(
      id: MetricIds.download,
      label: 'Download',
      unit: 'Mbps',
    ),
    QualityMetric.unavailable(
      id: MetricIds.upload,
      label: 'Upload',
      unit: 'Mbps',
    ),
  ],
);

/// Cloud apps ALL UNREACHABLE (prober returns null) — a definitive "no" for the
/// online-evidence axis. Mounting the panel is what fires `onResults` →
/// `_recomputeVerdict`, the LATE writer that folds the evidence in for real.
ReachabilityProbe _unreachableCloudApps() => ReachabilityProbe(
  sites: kCloudApps,
  prober: (String host, int port, Duration timeout) async => null,
);

/// Cloud apps ALL REACHABLE — the captive-portal signature (the portal accepts the
/// TCP connection) needs this "yes".
ReachabilityProbe _reachableCloudApps() => ReachabilityProbe(
  sites: kCloudApps,
  prober: (String host, int port, Duration timeout) async =>
      const Duration(milliseconds: 22),
);

/// Mounts the real screen ON Wi-Fi with a working link and the given probes, runs
/// one check, lets the cloud panel resolve, and settles.
Future<void> _runCheck(
  WidgetTester tester, {
  required DnsProbeService dns,
  required ReachabilityProbe cloud,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  final _WorkingLinkBridge bridge = _WorkingLinkBridge();
  final WifiSignalSampler sampler = WifiSignalSampler(
    source: WifiInfoSource.iosShortcuts,
    iosBridge: bridge,
    connectionService: WifiConnectionService(
      networkInfo: _OnWifiNetworkInfo(),
      platformOverride: TargetPlatform.iOS,
      pathProbe: const _OnWifiPath(),
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
        ipGeoService: _FailingIpGeo(),
        enableCloudApps: true,
        cloudAppsProbe: cloud,
        onboardingService: LiveOnboardingService(
          getStore: SharedPreferences.getInstance,
        ),
        qualityClient: MockQualityClient(scriptedResult: _stalledInternet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // On Wi-Fi the link is proven free, so the button carries no data cost.
  await tester.tap(find.byKey(TestMyConnectionScreen.runButtonKey));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  // Let the cloud-apps panel's probe resolve and fire onResults -> _recomputeVerdict.
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
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

class _ThrowingCloudProbe extends ReachabilityProbe {
  _ThrowingCloudProbe()
    : super(
        sites: kCloudApps,
        prober: (String host, int port, Duration timeout) async => null,
      );

  @override
  Future<List<SiteReachability>> measure() async => throw StateError('boom');
}

ReachabilityProbe _gatedCloudProbe(Completer<void> gate) => ReachabilityProbe(
  sites: kCloudApps,
  prober: (String host, int port, Duration timeout) async {
    await gate.future;
    return const Duration(milliseconds: 20);
  },
);

void main() {
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

  group('triage ladder on Check My Connection', () {
    testWidgets('dead internet: ladder shows, names the internet, and sits '
        'between the verdict line and the Analyze button', (
      WidgetTester tester,
    ) async {
      await _runCheck(
        tester,
        dns: _FailingDns(),
        cloud: _unreachableCloudApps(),
      );
      final String screen = _visibleText(tester);
      expect(screen, contains('Where it looks off'));
      for (final String name in <String>[
        'Wi-Fi link',
        'Name lookup (DNS)',
        'The internet',
        'Services',
      ]) {
        expect(screen, contains(name));
      }
      expect(screen, contains('Looks off'));
      // DNS failed, so the first rung outward that looks off is name lookup.
      expect(
        screen,
        contains('It looks like the trouble sits at name lookup (DNS).'),
      );
      // One line per rung on this screen: reasons belong to Analyze.
      expect(screen, isNot(contains('Website names did not resolve.')));

      final double ladderY = tester
          .getTopLeft(find.text('Where it looks off'))
          .dy;
      final double analyzeY = tester
          .getTopLeft(find.text('Analyze my results'))
          .dy;
      expect(ladderY, lessThan(analyzeY));
      expect(
        ladderY,
        greaterThan(
          tester.getTopLeft(find.textContaining('Your Wi-Fi is fine').first).dy,
        ),
        reason: 'the ladder comes after the headline',
      );
    });

    testWidgets('captive portal: the sign-in sentence leads the ladder', (
      WidgetTester tester,
    ) async {
      await _runCheck(tester, dns: _WorkingDns(), cloud: _reachableCloudApps());
      expect(
        _visibleText(tester),
        contains('It looks like this network wants a sign-in.'),
      );
    });

    testWidgets('the TMC Copy report carries the ladder as words', (
      WidgetTester tester,
    ) async {
      await _runCheck(
        tester,
        dns: _FailingDns(),
        cloud: _unreachableCloudApps(),
      );
      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();
      final String report = clipboardWrites.last;
      expect(report, contains('Where it looks off'));
      expect(report, contains('Name lookup (DNS): Looks off'));
      expect(report, contains('Website names did not resolve.'));
      expect(report, isNot(contains('\u2014')));
      // Let the "Copied" confirmation's 1.5 s reset timer finish.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Analyze opens with the ladder first, reasons shown, and its '
        'Copy carries the ladder', (WidgetTester tester) async {
      await _runCheck(tester, dns: _WorkingDns(), cloud: _reachableCloudApps());
      final Finder analyze = find.text('Analyze my results');
      await tester.ensureVisible(analyze);
      await tester.pumpAndSettle();
      await tester.tap(analyze);
      await tester.pumpAndSettle();

      final String report = _visibleText(tester);
      expect(report, contains('Analyze Results'), reason: 'sanity: on Analyze');
      expect(report, contains('This network wants a sign-in.'));
      expect(
        tester.getTopLeft(find.text('Where it looks off')).dy,
        lessThan(
          tester
              .getTopLeft(find.textContaining('Here\'s what your connection'))
              .dy,
        ),
      );

      await tester.tap(find.byType(AppCopyAction));
      await tester.pumpAndSettle();
      final String copied = clipboardWrites.last;
      expect(copied, contains('Where it looks off'));
      expect(copied, contains('The internet: Looks off'));
      expect(copied, contains('This network wants a sign-in.'));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Analyze Copy matches the ladder the screen showed, even if '
        'an answer lands after it opened', (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      await _runCheck(
        tester,
        dns: _WorkingDns(),
        cloud: _gatedCloudProbe(gate),
      );
      final Finder analyze = find.text('Analyze my results');
      await tester.ensureVisible(analyze);
      await tester.pumpAndSettle();
      await tester.tap(analyze);
      await tester.pumpAndSettle();
      expect(
        _visibleText(tester),
        contains('No answer yet when this was captured.'),
      );

      // The cloud panel on the screen underneath now answers.
      gate.complete();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(AppCopyAction));
      await tester.pumpAndSettle();
      expect(
        clipboardWrites.last,
        contains('No answer yet when this was captured.'),
        reason: 'the copy must be the page the user was looking at',
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a cloud panel that errored reads Not checked in the Copy '
        'report, not Checking', (WidgetTester tester) async {
      await _runCheck(tester, dns: _WorkingDns(), cloud: _ThrowingCloudProbe());
      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();
      final String report = clipboardWrites.last;
      expect(report, contains('Services: Not checked'));
      expect(report, contains('The services check did not complete.'));
      expect(report, isNot(contains('No answer yet when this was captured.')));
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
