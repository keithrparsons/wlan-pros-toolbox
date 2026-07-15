// TestMyConnectionScreen — stale-SSID regression (client-site bug, 2026-07-14).
//
// THE BUG (user on iPhone, at a client site): "What to tell support" showed the
// user's HOME Wi-Fi SSID in the "Wi-Fi network" row instead of the network the
// phone was actually joined to — under a CURRENT "Tested" timestamp, so the
// wrong name looked authoritative. Same shape as the 1.7.3 stale-Wi-Fi-on-
// cellular fix: a STALE VALUE under a FRESH stamp.
//
// ROOT CAUSE: on iOS the RF comes from the companion Shortcut's LAST-STORED App
// Group payload (WiFiDetailsBridge.readLatest / the live sampler). That payload
// survives the phone moving between networks, so at a client site it still
// carried the HOME SSID (and home RF) captured last time the Shortcut ran at
// home. _enrichIosSecurity let that Shortcut SSID be authoritative; the live
// native NEHotspotNetwork read (which DOES reflect the currently-joined network)
// was only a fallback. The result body read the stale name.
//
// THE CONTRACT THESE TESTS PIN:
//  1. The live native NEHotspotNetwork SSID is the AUTHORITY for the network
//     NAME on iOS. When it disagrees with the Shortcut payload, the native name
//     wins.
//  2. On that disagreement the Shortcut payload belongs to a DIFFERENT network,
//     so its ENTIRE RF block is stale for the current network and must drop to
//     the honest "not captured" state — never shown under a fresh timestamp.
//  3. This holds through BOTH iOS Shortcut-sourced paths: the one-shot
//     readLatest() AND the live sampler's latest reading.
//
// GL-007: the reported network came from a client site. NO real client SSID /
// BSSID appears here — only the synthetic "HomeNet" (stale) and "ClientNet"
// (current) placeholders.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_connection_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_path_probe.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// The STALE home payload the companion Shortcut stored last time it ran at home.
/// Carries a BSSID, so the pre-fix _enrichIosSecurity takes its "Shortcut BSSID
/// present" branch and returns this reading verbatim — SSID and all.
const WiFiDetails _homeStalePayload = WiFiDetails(
  ssid: 'HomeNet',
  bssid: 'aa:bb:cc:00:00:01',
  channel: 36,
  rssi: -58,
  noise: -90,
  standard: '802.11ax - Wi-Fi 6',
  rxRate: 780,
  txRate: 866,
);

/// An iOS bridge whose stored payload is the STALE HOME reading. Models the
/// client-site phone: the Shortcut has not re-run on the new network, so
/// readLatest() still returns the home capture.
class _StaleHomeBridge implements WiFiDetailsBridge {
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
  Future<WiFiDetails?> readLatest() async => _homeStalePayload;
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

/// An iOS bridge with NO stored Shortcut payload (readLatest → null). Used by the
/// sampler-path test: the one-shot read is empty, so the identity comes from the
/// native read alone and any stale RF/name can ONLY arrive via the live sampler.
class _EmptyBridge extends _StaleHomeBridge {
  @override
  Future<WiFiDetails?> readLatest() async => null;
}

/// A fake NEHotspotNetwork security reader. Returns an AVAILABLE read for the
/// CURRENT network ("ClientNet") — the live, authoritative identity at the
/// client site. This is what the phone is actually joined to right now.
class _ClientNativeSecurity extends WifiSecurityService {
  @override
  Future<WifiSecurityInfo> fetch() async => const WifiSecurityInfo(
        available: true,
        securityToken: 'personal',
        ssid: 'ClientNet',
        bssid: 'dd:ee:ff:00:00:02',
        locationAuthorized: true,
      );
}

/// A sampler whose live `latest` is the STALE HOME reading — models the live
/// companion-Shortcut stream still handing out the last home payload after the
/// phone moved networks. Every feed-driving method is a no-op so the widget test
/// touches no real method channel; only [latest] is scripted.
class _StaleLatestSampler extends WifiSignalSampler {
  _StaleLatestSampler({required super.iosBridge})
      : super(
          source: WifiInfoSource.iosShortcuts,
          connectionService: _onWifiConnection(),
        );

  @override
  ConnectedAp? get latest => ConnectedAp.fromWifiDetails(_homeStalePayload);

  @override
  bool get notOnWifi => false;

  @override
  MeteredRisk get meteredRisk => MeteredRisk.none;

  @override
  bool get meteredRiskResolved => true;

  @override
  Future<void> start() async {}
  @override
  Future<void> load({String? nativeSsid}) async {}
  @override
  Future<bool> getReadingOnce() async => true;
  @override
  Future<void> pollLatestAfterOneShot() async {}
  @override
  Future<void> stop() async {}
  @override
  void resumeMac() {}
  @override
  void pauseMac() {}
}

/// A marginal internet result so the check produces a full result body (verdict,
/// help-desk facts, pro readout) rather than a grade-gated short circuit.
QualityResult _marginalInternet() => QualityResult(
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

class _SilentPath implements WifiPathProbe {
  const _SilentPath();
  @override
  Future<WifiPathFacts?> read() async => null;
}

class _OnWifiNet implements NetworkInfo {
  @override
  Future<String?> getWifiIP() async => '10.0.0.20';
  @override
  Future<String?> getWifiIPv6() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WifiConnectionService _onWifiConnection() => WifiConnectionService(
      networkInfo: _OnWifiNet(),
      platformOverride: TargetPlatform.iOS,
      pathProbe: const _SilentPath(),
    );

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: child,
        ),
      );

  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> runCheck(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check My Connection'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ONE-SHOT PATH: the live native SSID (ClientNet) wins over the stale '
    'Shortcut SSID (HomeNet) in "What to tell support", and the stale RF is NOT '
    'shown under a fresh timestamp',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            connectionService: _onWifiConnection(),
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _StaleHomeBridge(),
            securityService: _ClientNativeSecurity(),
            qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
          ),
        ),
      );
      await runCheck(tester);

      // The "What to tell support" card is rendered.
      expect(find.text('What to tell support'), findsOneWidget);

      // The Wi-Fi network row names the network we are ACTUALLY on (native
      // NEHotspotNetwork), never the stale home carryover.
      expect(find.text('ClientNet'), findsWidgets);
      expect(find.text('HomeNet'), findsNothing);

      // The stale home RF (RSSI -58, rates 780/866 captured at home) must NOT be
      // presented as the current network's reading. On the SSID disagreement the
      // whole RF block is stale, so none of it may appear on screen or in copy.
      expect(find.textContaining('-58'), findsNothing);
      expect(find.textContaining('780'), findsNothing);
      expect(find.textContaining('866'), findsNothing);

      // And the copied report carries the same authoritative name, never HomeNet.
      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(clipboardWrites, isNotEmpty);
      final String copied = clipboardWrites.last;
      expect(copied, contains('ClientNet'));
      expect(copied, isNot(contains('HomeNet')));
      expect(copied, isNot(contains('-58 dBm')));
      expect(copied, isNot(contains('780')));
      expect(copied, isNot(contains('866')));

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'SAMPLER PATH: a stale HomeNet reading arriving only via the live sampler '
    'never overrides the native ClientNet name, and its RF never surfaces',
    (tester) async {
      final _StaleLatestSampler sampler =
          _StaleLatestSampler(iosBridge: _EmptyBridge());
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: true,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _EmptyBridge(),
            securityService: _ClientNativeSecurity(),
            sampler: sampler,
            qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
          ),
        ),
      );
      await runCheck(tester);

      expect(find.text('What to tell support'), findsOneWidget);
      // Native identity is authoritative even though the ONLY RF-bearing reading
      // (the sampler's latest) is the stale home payload.
      expect(find.text('ClientNet'), findsWidgets);
      expect(find.text('HomeNet'), findsNothing);
      // The sampler's stale RF must not leak into the current-network reading.
      expect(find.textContaining('-58'), findsNothing);
      expect(find.textContaining('780'), findsNothing);
      expect(find.textContaining('866'), findsNothing);
    },
  );
}
