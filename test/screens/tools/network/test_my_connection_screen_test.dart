// TestMyConnectionScreen — widget tests for the merged Wave 4 tool, updated for
// the v1.1 "show more" pass (2026-06-05, Keith) that walked back the
// over-simplified readability reshape toward MORE information.
//
// Drives the screen through its injection seams (a Wi-Fi source + fake
// adapter/bridge, a MockQualityClient with no network, live sampling disabled)
// so no real platform channel, socket, or poll timer is touched. Covers the
// v1.1 "show more" layout:
//   * (A) the VERDICT HERO renders the plain-language sentence (H1) + the two
//     side-by-side "Wi-Fi:" / "Internet:" status chips, each WORD + GLYPH;
//   * the state-driven VERDICT LINE names the limiter, and the DIRECT % comparison
//     sentence ("{N}% faster/slower" / "about the same speed") is always visible;
//   * the removed copy is gone: no "A few things to try", no "See the details"
//     disclosure, no "This won't change any of your settings.", no old "carrying
//     plenty" verdict line;
//   * the full detail (comparison bars, help-desk card, pro readout) is ALWAYS
//     rendered — no tap to reveal;
//   * "Couldn't check" carries the NEUTRAL help_outline glyph, never an error
//     glyph or status hue;
//   * the copy-able details text carries the two-axis line, internet down/up on
//     separate labeled lines, and the four Wi-Fi values (iOS payload → real
//     values; macOS Rx not exposed → "Wi-Fi Down: Unavailable", per GL-005);
//   * the "Run again" control (its own row beneath the verdict sentence)
//     re-runs the same check (moved off the AppBar 2026-06-14 so the full title
//     clears at iPhone widths — Vera; moved off the sentence row 2026-06-15 so
//     the verdict reads full-width at iPhone widths — Keith);
//   * a hung macOS link read can never hang the check.
//
// The copy text is intercepted at the Clipboard platform-channel boundary so the
// test asserts the EXACT payload the user would paste.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/dns_probe_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/network_details_service.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_security_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// macOS sample: Tx 866 present, Rx NOT exposed by public CoreWLAN, SNR 45.
ConnectedAp _macSample() => ConnectedAp.fromWifiInfo(
  WifiInfo(
    interfaceName: 'en0',
    ssid: 'KeithNet',
    bssid: 'a4:83:e7:00:11:22',
    rssiDbm: -50,
    noiseDbm: -95,
    snrDb: 45,
    txRateMbps: 866,
    phyMode: '802.11ax',
    channel: 36,
    channelWidthMhz: 80,
    band: '5 GHz',
    countryCode: 'US',
    hardwareAddress: 'a4:83:e7:aa:bb:cc',
    poweredOn: true,
    locationAuthorized: true,
  ),
);

/// macOS sample with the NAME gated off (Location not authorized).
ConnectedAp _macSampleNoName() => ConnectedAp.fromWifiInfo(
  WifiInfo(
    interfaceName: 'en0',
    ssid: null,
    bssid: null,
    rssiDbm: -50,
    noiseDbm: -95,
    snrDb: 45,
    txRateMbps: 866,
    phyMode: '802.11ax',
    channel: 36,
    channelWidthMhz: 80,
    band: '5 GHz',
    countryCode: 'US',
    hardwareAddress: 'a4:83:e7:aa:bb:cc',
    poweredOn: true,
    locationAuthorized: false,
  ),
);

/// macOS adapter whose Location is DENIED (not promptable). The screen must NOT
/// fire a system prompt for this state (no dialog can appear); it shows the
/// on-screen hint whose button DEEP-LINKS to System Settings.
class _NoNameMacAdapter implements WifiInfoAdapter {
  bool promptRequested = false;
  bool settingsOpened = false;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => _macSampleNoName();
  @override
  Future<bool> requestNamePermission() async {
    promptRequested = true;
    return true;
  }

  @override
  Future<bool> currentNameAuthorization() async => false;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.denied;
  @override
  Future<bool> openNamePermissionSettings() async {
    settingsOpened = true;
    return true;
  }
}

/// macOS adapter whose Location is NOT DETERMINED (promptable). The screen must
/// fire the native prompt EXACTLY ONCE at run start (Keith's auto-prompt
/// reversal). [grantOnPrompt] flips the post-prompt status to authorized so the
/// SSID/BSSID populate, mirroring a user who clicks Allow.
class _NotDeterminedMacAdapter implements WifiInfoAdapter {
  _NotDeterminedMacAdapter({this.grantOnPrompt = false});

  final bool grantOnPrompt;
  int requestCount = 0;
  bool _granted = false;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async =>
      _granted ? _macSample() : _macSampleNoName();
  @override
  Future<bool> requestNamePermission() async {
    requestCount++;
    if (grantOnPrompt) _granted = true;
    return _granted;
  }

  @override
  Future<bool> currentNameAuthorization() async => _granted;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => _granted
      ? LocationAuthStatus.authorized
      : LocationAuthStatus.notDetermined;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

class _FakeMacAdapter implements WifiInfoAdapter {
  bool promptRequested = false;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => _macSample();
  @override
  Future<bool> requestNamePermission() async {
    promptRequested = true;
    return true;
  }

  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// A macOS adapter whose SNAPSHOT READ never resolves — models the production
/// hang. The check must still complete with the link unread (ap = null →
/// "Couldn't check") and never hang. Location is already AUTHORIZED here so the
/// hang test isolates the snapshot stall (no prompt fires; the auto-prompt only
/// triggers on the promptable `notDetermined` state).
class _HangingMacAdapter implements WifiInfoAdapter {
  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() => Completer<ConnectedAp>().future;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// Android adapter recording the permission calls. [authorized] flips after a
/// granted runtime request, so a second read could see the name — but the test
/// asserts the REQUEST behavior on the consumer-check path (FIX 1): Android, unlike
/// macOS, MUST surface the runtime Location dialog from Test My Connection when the
/// permission is not already held, because Android redacts the entire WifiManager
/// snapshot without it. Fields mirror an Android link: Tx 433, no noise/SNR.
class _AndroidPermissionAdapter implements WifiInfoAdapter {
  _AndroidPermissionAdapter({this.alreadyAuthorized = false})
      : _authorized = alreadyAuthorized;

  final bool alreadyAuthorized;
  bool _authorized;

  int requestCount = 0;
  int currentAuthChecks = 0;

  ConnectedAp _sample() => ConnectedAp.fromAndroidWifiInfo(
        WifiInfo(
          interfaceName: 'wlan0',
          ssid: _authorized ? 'KeithNet' : null,
          bssid: _authorized ? 'a4:83:e7:00:11:22' : null,
          rssiDbm: -52,
          // Android exposes no noise floor → SNR null (the FIX 2 platform limit).
          noiseDbm: null,
          snrDb: null,
          txRateMbps: 433,
          phyMode: '802.11ax (Wi-Fi 6)',
          channel: 36,
          channelWidthMhz: null,
          band: '5 GHz',
          countryCode: null,
          hardwareAddress: null,
          poweredOn: true,
          locationAuthorized: _authorized,
        ),
      );

  @override
  String get platformLabel => 'Android';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => _sample();
  @override
  Future<bool> requestNamePermission() async {
    requestCount++;
    _authorized = true;
    return true;
  }

  @override
  Future<bool> currentNameAuthorization() async {
    currentAuthChecks++;
    return _authorized;
  }

  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async => _authorized
      ? LocationAuthStatus.authorized
      : LocationAuthStatus.notDetermined;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// iOS bridge delivering a full payload: rssi -58, noise -90 (→ SNR 32),
/// rxRate 780, txRate 866 — the platform that DOES expose Rx.
class _PayloadBridge implements WiFiDetailsBridge {
  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<WiFiDetails?> readLatest() async => const WiFiDetails(
    ssid: 'KeithNet',
    bssid: 'a4:83:e7:00:11:22',
    channel: 36,
    rssi: -58,
    noise: -90,
    standard: '802.11ax - Wi-Fi 6',
    rxRate: 780,
    txRate: 866,
  );
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// A [QualityClient] that counts how many times [measure] is subscribed.
class _CountingQualityClient implements QualityClient {
  _CountingQualityClient(this.scriptedResult);

  final QualityResult scriptedResult;
  QualityResult? _lastResult;

  int measureCount = 0;

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  @override
  Stream<QualityProgress> measure() async* {
    measureCount++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    yield const QualityProgress(QualityPhase.latency, 0.25);
    yield const QualityProgress(QualityPhase.download, 0.5);
    yield const QualityProgress(QualityPhase.upload, 0.75);
    _lastResult = scriptedResult;
    yield const QualityProgress(QualityPhase.complete, 1.0);
  }
}

/// A net_quality result graded marginal so a finite link produces a localizing
/// verdict rather than the grade-gated "Both fine".
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

/// A net_quality result with NO available download/upload — the engine takes
/// its wifiUnknown path with a null internet figure (→ D2, both axes unknown).
QualityResult _emptyInternet() => QualityResult(
  source: QualitySource.mock,
  measuredAt: DateTime.utc(2026, 1, 1),
  metrics: const <QualityMetric>[
    QualityMetric(
      id: MetricIds.download,
      label: 'Download',
      value: null,
      unit: 'Mbps',
      grade: QualityGrade.unavailable,
    ),
    QualityMetric(
      id: MetricIds.upload,
      label: 'Upload',
      value: null,
      unit: 'Mbps',
      grade: QualityGrade.unavailable,
    ),
  ],
);

/// A net_quality result whose averaged throughput (down 600 / up 304 → avg 452)
/// sits within +/-10% of the iOS payload's usable Wi-Fi capacity (452.65 Mbps),
/// so the direct-comparison line reads "about the same speed". Graded good, so
/// the verdict is "Both fine".
QualityResult _aboutSameInternet() => QualityResult(
  source: QualitySource.mock,
  measuredAt: DateTime.utc(2026, 1, 1),
  metrics: const <QualityMetric>[
    QualityMetric(
      id: MetricIds.latency,
      label: 'Latency',
      value: 8,
      unit: 'ms',
      grade: QualityGrade.excellent,
    ),
    QualityMetric(
      id: MetricIds.loss,
      label: 'Loss',
      value: 0,
      unit: '%',
      grade: QualityGrade.excellent,
    ),
    QualityMetric(
      id: MetricIds.download,
      label: 'Download',
      value: 600,
      unit: 'Mbps',
      grade: QualityGrade.excellent,
    ),
    QualityMetric(
      id: MetricIds.upload,
      label: 'Upload',
      value: 304,
      unit: 'Mbps',
      grade: QualityGrade.excellent,
    ),
  ],
);

/// A macOS adapter at an arbitrary Tx rate (Rx not exposed on public CoreWLAN,
/// so usable Wi-Fi = 0.55 × Tx). Used by the same-tier hero tests to pin the
/// Wi-Fi axis onto a chosen absolute tier: Tx 720 → usable 396 (Strong),
/// Tx 360 → usable 198 (Moderate), Tx 120 → usable 66 (Weak).
class _TxLinkMacAdapter implements WifiInfoAdapter {
  _TxLinkMacAdapter(this.txRateMbps);
  final double txRateMbps;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => ConnectedAp.fromWifiInfo(
    WifiInfo(
      interfaceName: 'en0',
      ssid: 'KeithNet',
      bssid: 'a4:83:e7:00:11:22',
      rssiDbm: -55,
      noiseDbm: -92,
      snrDb: 37,
      txRateMbps: txRateMbps,
      phyMode: '802.11ax',
      channel: 36,
      channelWidthMhz: 80,
      band: '5 GHz',
      countryCode: 'US',
      hardwareAddress: 'a4:83:e7:aa:bb:cc',
      poweredOn: true,
      locationAuthorized: true,
    ),
  );
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// An internet result at a chosen down/up (avg sets the absolute tier). Grade
/// defaults to `fair` so the engine does NOT short-circuit to bothHealthy and
/// the rate-driven chip tiers are what the hero reads.
QualityResult _internetAt({
  required double down,
  required double up,
  QualityGrade grade = QualityGrade.fair,
}) => QualityResult(
  source: QualitySource.mock,
  measuredAt: DateTime.utc(2026, 1, 1),
  metrics: <QualityMetric>[
    const QualityMetric(
      id: MetricIds.latency,
      label: 'Latency',
      value: 18,
      unit: 'ms',
      grade: QualityGrade.good,
    ),
    const QualityMetric(
      id: MetricIds.loss,
      label: 'Loss',
      value: 0,
      unit: '%',
      grade: QualityGrade.good,
    ),
    QualityMetric(
      id: MetricIds.download,
      label: 'Download',
      value: down,
      unit: 'Mbps',
      grade: grade,
    ),
    QualityMetric(
      id: MetricIds.upload,
      label: 'Upload',
      value: up,
      unit: 'Mbps',
      grade: grade,
    ),
  ],
);

/// A macOS adapter whose link rate is LOW (Tx 30 Mbps) so usable Wi-Fi capacity
/// (16.5 Mbps) sits well below a marginal internet (avg 40), producing the
/// `wifiLimiter` verdict → outcome `wifi` and a "slower" % comparison.
ConnectedAp _macSampleSlowLink() => ConnectedAp.fromWifiInfo(
  WifiInfo(
    interfaceName: 'en0',
    ssid: 'KeithNet',
    bssid: 'a4:83:e7:00:11:22',
    rssiDbm: -78,
    noiseDbm: -92,
    snrDb: 14,
    txRateMbps: 30,
    phyMode: '802.11ax',
    channel: 36,
    channelWidthMhz: 80,
    band: '5 GHz',
    countryCode: 'US',
    hardwareAddress: 'a4:83:e7:aa:bb:cc',
    poweredOn: true,
    locationAuthorized: true,
  ),
);

class _SlowLinkMacAdapter implements WifiInfoAdapter {
  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => _macSampleSlowLink();
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}

/// iOS bridge modeling the FIRST-RUN stuck condition: a payload was received
/// before AND a STALE App Group monitoring flag is still set `true` (a prior
/// session's loop was killed without a clean Stop). No live producer exists. The
/// live card must still present the actionable Start, never a dead "LIVE".
class _StaleFlagBridge implements WiFiDetailsBridge {
  bool monitoringFlag = true;
  int runShortcutCalls = 0;
  String? lastRunShortcutName;

  @override
  Future<bool> hasEverReceivedPayload() async => true;
  @override
  Future<WiFiDetails?> readLatest() async => const WiFiDetails(
    ssid: 'KeithNet',
    bssid: 'a4:83:e7:00:11:22',
    channel: 36,
    rssi: -58,
    noise: -90,
    standard: '802.11ax - Wi-Fi 6',
    rxRate: 780,
    txRate: 866,
  );
  @override
  Future<bool> isMonitoringActive() async => monitoringFlag;
  @override
  Future<void> setMonitoringActive(bool active) async {
    monitoringFlag = active;
  }

  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    lastRunShortcutName = name;
    return true;
  }

  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// A brand-new iOS user's bridge: the app has NEVER received a Live payload, so
/// the honest install-state signal is `false` and the mandatory first-run
/// onboarding must fire. Records [openUrl] calls so a test can prove the sheet
/// deep-links into Shortcuts.
class _FreshBridge implements WiFiDetailsBridge {
  int openUrlCalls = 0;
  String? lastOpenedUrl;

  @override
  Future<bool> hasEverReceivedPayload() async => false;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => false;
  @override
  Future<void> setMonitoringActive(bool active) async {}
  @override
  Future<bool> openUrl(String url) async {
    openUrlCalls++;
    lastOpenedUrl = url;
    return true;
  }

  @override
  Future<bool> runShortcut(String name) async => true;
  @override
  Stream<WiFiDetails> get updates => const Stream<WiFiDetails>.empty();
}

/// A fake IP-info service for the comprehensive-copy tests (Keith ISP-ask + #6).
/// Extends the real [IpGeoService] (no network client is touched because
/// [lookup] is overridden). [result] is what [lookup] returns; pass an
/// [IpGeoResult.failure] (or set [throws]) to exercise the fail-open path where
/// the ISP copy section is omitted.
class _FakeIpGeoService extends IpGeoService {
  _FakeIpGeoService({this.result, this.throws = false});

  final IpGeoResult? result;
  final bool throws;

  @override
  Future<IpGeoResult> lookup({required String rawQuery}) async {
    if (throws) throw Exception('offline');
    return result ??
        IpGeoResult.failure(query: rawQuery, message: 'no result');
  }
}

/// A fake DNS resolution-time probe (Keith #3). Returns a deterministic 12 ms
/// success against cloudflare.com so the DNS report row is stable without a
/// live resolver.
class _FakeDnsProbe extends DnsProbeService {
  @override
  Future<DnsProbeResult> measure() async =>
      DnsProbeResult.success(host: 'cloudflare.com', millis: 12);
}

/// A fake local-addressing reader (Keith #5). Returns a deterministic home-LAN
/// snapshot so the Network report rows are stable without `network_info_plus`
/// or a live interface list.
class _FakeNetworkDetails extends NetworkDetailsService {
  @override
  Future<NetworkDetails> read() async => const NetworkDetails(
        localIp: '192.168.1.42',
        subnetMask: '255.255.255.0',
        gateway: '192.168.1.1',
      );
}

/// A fake iOS NEHotspotNetwork security reader. Returns a deterministic
/// unavailable result synchronously (no real method channel), so a live-card
/// test that leaves `enableLiveSampling` on does not touch the real native
/// channel and leak a pending async into the FakeAsync test clock. Pass an
/// [available] result to exercise the security/BSSID enrichment.
class _FakeSecurityService extends WifiSecurityService {
  _FakeSecurityService({this.info});

  final WifiSecurityInfo? info;

  @override
  Future<WifiSecurityInfo> fetch() async =>
      info ?? const WifiSecurityInfo.unavailable('test: not available');
}

/// An onboarding service seeded "already seen", so a `_FreshBridge`-backed iOS
/// test (hasEverReceivedPayload == false) does NOT pop the one-time first-run
/// setup sheet mid-test. Backed by an in-memory SharedPreferences store.
LiveOnboardingService _seenOnboarding() {
  SharedPreferences.setMockInitialValues(<String, Object>{
    LiveOnboardingService.prefsKey: true,
  });
  return LiveOnboardingService(getStore: SharedPreferences.getInstance);
}

void main() {
  Widget hostTheme(Widget child, ThemeData theme, {Size? size}) => MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(size: size ?? const Size(390, 844)),
      child: child,
    ),
  );

  Widget host(Widget child, {Size? size}) =>
      hostTheme(child, AppTheme.dark(), size: size);

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

  /// In v1.1 the technical layer (comparison bars, help-desk card, pro readout)
  /// is ALWAYS rendered, so there is no disclosure to open. This just settles
  /// any pending frames before the detail assertions run.
  Future<void> settleDetails(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  testWidgets(
    '(A) verdict hero renders the plain-language sentence (H1) + the two '
    'side-by-side status chips, each WORD + GLYPH',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // _marginalInternet (down 60 / up 20) over the high iOS link rate →
      // ratio < 0.40 → engine `upstream` → outcome `internet` → the hero
      // sentence is "Your internet is the slow part."
      final Finder hero = find.text('Your internet is the slow part.');
      expect(hero, findsOneWidget);
      // It is the H1 hero — headlineLarge / 36px (§8.5.2 scope extension).
      final Text heroText = tester.widget<Text>(hero);
      expect(heroText.style?.fontSize, 36);

      // Both labeled axis chips remain, each carrying its own word + glyph.
      // REVISION 2: absolute 3-tier per axis. iOS link rxRate 780 / txRate 866 →
      // usable Wi-Fi 452.65 Mbps (> 250) → Wi-Fi: Strong (success/green). Internet
      // _marginalInternet down 60 / up 20 → avg 40 Mbps (< 100) → Internet: Weak
      // (danger/red). Each chip carries its WORD + the §8.13 glyph, never color-only.
      expect(find.text('Wi-Fi:'), findsOneWidget);
      expect(find.text('Internet:'), findsOneWidget);
      expect(find.text('Strong'), findsOneWidget);
      expect(find.text('Weak'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget); // Strong
      expect(find.byIcon(Icons.error_outline), findsOneWidget); // Weak
    },
  );

  testWidgets(
    'the state-driven VERDICT LINE names the limiter (internet limiter case)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // usable Wi-Fi (452.65) clearly exceeds measured internet (40) → internet
      // is the limiter. Present at first paint, no tap.
      expect(
        find.text('Your internet is the limit right now, not your Wi-Fi.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the VERDICT LINE names Wi-Fi as the weak link when usable Wi-Fi is below '
    'the internet rate AND the two axes are on different tiers',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _SlowLinkMacAdapter(),
            // usable Wi-Fi = 16.5 (< 100 → Weak); internet avg 200/100 = 150
            // (100-250 → Moderate). DIFFERENT tiers, so the limiter wording
            // stays — the chips do not contradict it.
            qualityClient: MockQualityClient(
              scriptedResult: _internetAt(down: 200, up: 100),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // usable Wi-Fi (16.5, Weak) sits below measured internet (150, Moderate)
      // → different tiers → Wi-Fi limits, the "weak link" wording is correct.
      expect(
        find.text('Your Wi-Fi is the weak link right now.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SAME-TIER: the VERDICT LINE and the reading line drop the "weak link" / '
    '"boost the Wi-Fi" wording and read by margin (Wi-Fi ahead, both Moderate)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            // Tx 360 → usable 198 (Moderate). internet 200/100 → avg 150
            // (Moderate). Same tier; usable is +32% → Wi-Fi has more headroom.
            macAdapter: _TxLinkMacAdapter(360),
            qualityClient: MockQualityClient(
              scriptedResult: _internetAt(down: 200, up: 100),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The hero reframes by margin (Wi-Fi slightly ahead).
      expect(
        find.text('Both sides are moderate. Your Wi-Fi is slightly ahead.'),
        findsOneWidget,
      );
      // The secondary verdict line NEVER names Wi-Fi the weak link in same-tier.
      expect(find.text('Your Wi-Fi is the weak link right now.'), findsNothing);
      expect(
        find.text(
          'Both your Wi-Fi and your internet are moderate; your Wi-Fi has a '
          'little more headroom right now.',
        ),
        findsOneWidget,
      );
      // The reading line NEVER says "boost the Wi-Fi" / "internet can carry
      // more" when both sides share a tier.
      expect(find.textContaining('Boost the Wi-Fi signal'), findsNothing);
      expect(
        find.textContaining('internet can carry more than your Wi-Fi'),
        findsNothing,
      );
      expect(
        find.text(
          'Your Wi-Fi link has a little more headroom, but both sides are in '
          'the same range right now.',
        ),
        findsOneWidget,
      );
      // The % comparison line still reads "32% faster" — all four agree.
      expect(
        find.text(
          'Your Wi-Fi link is 32% faster than your internet connection.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'SAME-TIER about-the-same: hero, verdict line, reading line and % line all '
    'agree (both Moderate, within +/-10%)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            // Tx 360 → usable 198 (Moderate). internet 240/160 → avg 200
            // (Moderate). |delta| = 1% → within the +/-10% band.
            macAdapter: _TxLinkMacAdapter(360),
            qualityClient: MockQualityClient(
              scriptedResult: _internetAt(down: 240, up: 160),
            ),
          ),
        ),
      );
      await runCheck(tester);

      expect(
        find.text('Both sides are moderate. They’re about the same speed.'),
        findsOneWidget,
      );
      expect(find.text('Your Wi-Fi is the weak link right now.'), findsNothing);
      expect(
        find.text(
          'Both your Wi-Fi and your internet are moderate, and running at about '
          'the same speed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Boost the Wi-Fi signal'), findsNothing);
      expect(
        find.text(
          'Your Wi-Fi link and your internet are carrying about the same. '
          'Neither side is clearly holding you back right now.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your Wi-Fi link and your internet connection are running at about '
          'the same speed.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the DIRECT % comparison line renders "faster" from real measured numbers',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // usable Wi-Fi = 0.55 * avg(866, 780) = 452.65; internet avg = 40.
      // Ratio 452.65 / 40 = 11.3x (> 10x), so the phrase is a CLEAN multiple
      // ("about 11x faster"), not a 1032% figure that reads as noise
      // (Keith 2026-06-17 ratio-phrasing fix).
      expect(
        find.text(
          'Your Wi-Fi link is about 11x faster than your internet connection.',
        ),
        findsOneWidget,
      );
      // The giant percentage must be gone.
      expect(find.textContaining('1032%'), findsNothing);
    },
  );

  testWidgets(
    'the DIRECT % comparison line renders "slower" when Wi-Fi is the weak link',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _SlowLinkMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // usable Wi-Fi = 0.55 * 30 = 16.5; internet avg = 40.
      // N = round(100 * (16.5 - 40) / 40) = 59, slower.
      expect(
        find.text(
          'Your Wi-Fi link is 59% slower than your internet connection.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the DIRECT % comparison line reads "about the same speed" within +/-10%',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _aboutSameInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // usable Wi-Fi 452.65 vs internet avg 452 → within +/-10% → "about the
      // same speed", and the percentage figure is NOT shown.
      expect(
        find.text(
          'Your Wi-Fi link and your internet connection are running at about '
          'the same speed.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('% faster'), findsNothing);
      expect(find.textContaining('% slower'), findsNothing);
    },
  );

  testWidgets(
    'the % comparison line is SUPPRESSED and the honest neutral verdict shows '
    'when the internet side could not be measured (D2)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _HangingMacAdapter(),
            qualityClient: MockQualityClient(scriptedResult: _emptyInternet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check My Connection'));
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      // No fabricated % when there is no internet figure to compare against.
      expect(find.textContaining('% faster'), findsNothing);
      expect(find.textContaining('% slower'), findsNothing);
      expect(find.textContaining('about the same speed'), findsNothing);
      // The honest neutral verdict line stands alone.
      expect(
        find.textContaining(
          'We could not read your Wi-Fi or your internet.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the removed copy is GONE: no "A few things to try", no "See the details" '
    'disclosure, no "This won\'t change any of your settings."',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      expect(find.text('A few things to try'), findsNothing);
      expect(find.text('See the details'), findsNothing);
      expect(
        find.text("This won't change any of your settings."),
        findsNothing,
      );
      // The old "Both fine" verdict line copy must be gone too.
      expect(find.textContaining('carrying plenty'), findsNothing);
      expect(find.textContaining('No bottleneck to chase'), findsNothing);
    },
  );

  testWidgets(
    'the full detail is ALWAYS rendered (no tap): comparison bars, help-desk '
    'card, and pro readout are present at first paint',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // No disclosure tap required — the technical layer is in the tree.
      expect(find.text('Wi-Fi usable capacity'), findsOneWidget);
      expect(find.text('Internet throughput'), findsOneWidget);
      expect(find.text('What to tell support'), findsOneWidget);
    },
  );

  testWidgets(
    '"Couldn\'t check" carries the NEUTRAL help_outline glyph (D2), never an '
    'error glyph',
    (tester) async {
      // D2: macOS link read hangs AND internet not measured → both axes unknown.
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _HangingMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _emptyInternet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check My Connection'));
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      // Both chips read "Couldn't check" with the neutral help_outline glyph.
      // (The always-shown help footer also uses help_outline, so the two chips
      // are a floor, not an exact count, now that details aren't behind a tap.)
      expect(find.text("Couldn't check"), findsNWidgets(2));
      expect(find.byIcon(Icons.help_outline), findsAtLeastNWidgets(2));
      // NOT a fault glyph and NOT the old remove_circle.
      expect(find.byIcon(Icons.error), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
      expect(find.byIcon(Icons.cancel), findsNothing);
    },
  );

  testWidgets(
    'opened details show Internet Down / Internet Up on separate rows',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);
      await settleDetails(tester);

      expect(find.text('What to tell support'), findsOneWidget);
      expect(find.text('Internet Down'), findsOneWidget);
      expect(find.text('Internet Up'), findsOneWidget);
      // download 60, upload 20 from _marginalInternet() (one each in facts).
      expect(find.text('60 Mbps'), findsOneWidget);
      expect(find.text('20 Mbps'), findsOneWidget);
      // The old combined string must be gone.
      expect(find.textContaining(' down / '), findsNothing);
    },
  );

  testWidgets(
    'copy text carries the two-axis line, internet down/up rows, and the four '
    'Wi-Fi values (iOS payload)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);
      await settleDetails(tester);

      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(clipboardWrites, isNotEmpty);
      final String copied = clipboardWrites.last;
      // Report header + two-axis summary line (Keith #4).
      expect(copied, contains('WLAN Pros Toolbox: Connection Report'));
      expect(copied, contains('Summary: Wi-Fi '));
      expect(copied, contains('Internet '));
      expect(copied, contains('Internet Down: 60 Mbps'));
      expect(copied, contains('Internet Up: 20 Mbps'));
      expect(copied, isNot(contains(' down / ')));
      expect(copied, contains('RSSI: -58 dBm'));
      expect(copied, contains('SNR: 32 dB'));
      // Comprehensive sectioned payload (Keith #6): Rx labeled "Wi-Fi Down",
      // Tx labeled "Wi-Fi Up".
      expect(copied, contains('Wi-Fi Down (Rx rate): 780 Mbps'));
      expect(copied, contains('Wi-Fi Up (Tx rate): 866 Mbps'));

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS Rx not exposed → "Wi-Fi Down: Unavailable" in the copy payload',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _FakeMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);
      await settleDetails(tester);

      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      final String copied = clipboardWrites.last;
      expect(copied, contains('RSSI: -50 dBm'));
      expect(copied, contains('SNR: 45 dB'));
      // macOS public CoreWLAN never exposes Rx → the empty state names it as a
      // KNOWN platform limit, not a glitch (honest-labeling, GL-005).
      expect(
        copied,
        contains('Wi-Fi Down (Rx rate): Unavailable (not exposed on macOS)'),
      );
      expect(copied, contains('Wi-Fi Up (Tx rate): 866 Mbps'));

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS check does NOT prompt when Location is already authorized — it reads '
    'the snapshot directly (no redundant TCC dialog)',
    (tester) async {
      final _FakeMacAdapter adapter = _FakeMacAdapter();
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // Already authorized → the auto-prompt does NOT fire (it only triggers on
      // the promptable notDetermined state), and the SSID/BSSID populate.
      expect(adapter.promptRequested, isFalse);
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS check AUTO-PROMPTS for Location when notDetermined (Keith reversal) — '
    'the native prompt fires from the run so the user need not dig into Settings',
    (tester) async {
      final _NotDeterminedMacAdapter adapter =
          _NotDeterminedMacAdapter(grantOnPrompt: true);
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The promptable state surfaced the native request exactly once at run
      // start; the verdict still resolves.
      expect(adapter.requestCount, 1);
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS auto-prompt fires AT MOST ONCE per mount — a re-run never re-prompts '
    '(Keith: "One request only")',
    (tester) async {
      // grantOnPrompt: false → the user dismisses; status stays notDetermined,
      // so a naive implementation would re-prompt on the second run. It must not.
      final _NotDeterminedMacAdapter adapter = _NotDeterminedMacAdapter();
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);
      expect(adapter.requestCount, 1);

      // Re-run from the verdict-hero row.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1600));

      // Still exactly one prompt across both runs.
      expect(adapter.requestCount, 1);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'Android check REQUESTS Location when not authorized (FIX 1) — the runtime '
    'prompt fires from Test My Connection so the user need not detour to Wi-Fi '
    'Information first',
    (tester) async {
      final _AndroidPermissionAdapter adapter = _AndroidPermissionAdapter();
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.androidWifiManager,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The check checked the CURRENT authorization (no prompt) and, finding it
      // unheld, surfaced the runtime request exactly once. The verdict still
      // resolves either way.
      expect(adapter.currentAuthChecks, greaterThanOrEqualTo(1));
      expect(adapter.requestCount, 1);
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'Android check does NOT re-prompt when Location is already authorized (FIX 1) '
    '— it reads the snapshot directly, no redundant dialog',
    (tester) async {
      final _AndroidPermissionAdapter adapter =
          _AndroidPermissionAdapter(alreadyAuthorized: true);
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.androidWifiManager,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      expect(adapter.currentAuthChecks, greaterThanOrEqualTo(1));
      expect(adapter.requestCount, 0);
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS DENIED Location shows the on-screen hint with an Open-settings action '
    '(no prompt — a denied state cannot raise a dialog)',
    (tester) async {
      final _NoNameMacAdapter adapter = _NoNameMacAdapter();
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);
      await settleDetails(tester);

      // Denied → no system prompt fires (it could never appear), but the
      // ON-SCREEN hint is now visible where the network name would sit.
      expect(adapter.promptRequested, isFalse);
      final Finder hint = find.text(
        'Wi-Fi network name hidden. Location access needed.',
      );
      await tester.ensureVisible(hint);
      expect(hint, findsOneWidget);

      // The denied state's action DEEP-LINKS to System Settings, not a prompt.
      final Finder settingsBtn = find.text('Open settings');
      expect(settingsBtn, findsOneWidget);
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();
      expect(adapter.settingsOpened, isTrue);
      expect(adapter.promptRequested, isFalse);

      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS notDetermined hint button re-fires the prompt (on-screen "Allow '
    'Location" path)',
    (tester) async {
      // Dismiss the auto-prompt (grantOnPrompt: false) so the hint stays and its
      // button is the promptable "Allow Location" variant.
      final _NotDeterminedMacAdapter adapter = _NotDeterminedMacAdapter();
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);
      await settleDetails(tester);

      // Auto-prompt fired once at run start.
      expect(adapter.requestCount, 1);

      final Finder allowBtn = find.text('Allow Location');
      await tester.ensureVisible(allowBtn);
      expect(allowBtn, findsOneWidget);
      await tester.tap(allowBtn);
      await tester.pumpAndSettle();

      // The hint button re-fired the prompt (user-initiated; the one-shot guard
      // governs only the AUTO prompt, not an explicit tap).
      expect(adapter.requestCount, 2);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'Re-run re-runs the same check and is hidden while running '
    '(re-run on its own row beneath the verdict sentence — Vera 2026-06-14 '
    'title fix; full-width sentence fix 2026-06-15)',
    (tester) async {
      final _CountingQualityClient quality =
          _CountingQualityClient(_marginalInternet());
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: quality,
          ),
        ),
      );

      await tester.pumpAndSettle();
      // No re-run affordance before a result exists.
      expect(find.byIcon(Icons.refresh), findsNothing);

      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      expect(quality.measureCount, 1);

      // The labeled "Run again" control is on its own row beneath the verdict
      // sentence, carrying the refresh glyph + the 'Run the test again'
      // semantics label + 44pt target.
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Run again'), findsOneWidget);
      expect(find.bySemanticsLabel('Run the test again'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      // While running, the hero card (and its re-run) is replaced by the
      // packet-flow progress card; no re-run affordance is shown.
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.text('Run again'), findsNothing);
      expect(
        find.text('Testing your Wi-Fi and your internet connection.'),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(quality.measureCount, 2);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Wi-Fi:'), findsOneWidget);
    },
  );

  testWidgets(
    'AppBar carries ONLY the copy action so the full title clears at 375px '
    '(Vera 2026-06-14 title-truncation fix)',
    (tester) async {
      await tester.pumpWidget(
        host(
          size: const Size(375, 812),
          TestMyConnectionScreen(
            enableLiveSampling: false,
            enableCloudApps: false,
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            ipGeoService: _FakeIpGeoService(throws: true),
            qualityClient: _CountingQualityClient(_marginalInternet()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();

      // The AppBar title renders the FULL string with no ellipsis, at 375px,
      // alongside the single §8.16 copy action (no second AppBar action).
      final Finder titleFinder = find.text('Test My Connection');
      expect(titleFinder, findsOneWidget);
      final RenderParagraph para = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: titleFinder,
          matching: find.byType(RichText),
          matchRoot: true,
        ),
      );
      expect(para.didExceedMaxLines, isFalse);
      expect(para.text.toPlainText(), 'Test My Connection');
    },
  );

  testWidgets(
    'check still completes (ap = null → "Couldn\'t check") when the macOS '
    'snapshot read never resolves — the link read can never hang the check',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            enableLiveSampling: false,
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _HangingMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check My Connection'));

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      expect(find.text('Wi-Fi:'), findsOneWidget);
      expect(find.text('Internet:'), findsOneWidget);
      // The Wi-Fi axis read "Couldn't check" (ap unread); the check completed.
      expect(find.text("Couldn't check"), findsWidgets);

      // The measured internet figure is in the always-shown detail.
      await settleDetails(tester);
      expect(find.text('Internet Down'), findsOneWidget);
      expect(find.text('60 Mbps'), findsOneWidget);
    },
  );

  // Render the full v1.1 result state in BOTH themes at mobile / tablet / desktop
  // widths — the always-shown detail must paint without overflow in light + dark.
  for (final (String themeName, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark()),
    ('light', AppTheme.light()),
  ]) {
    for (final (String sizeName, Size size) in <(String, Size)>[
      ('mobile', Size(360, 800)),
      ('tablet', Size(768, 1024)),
      ('desktop', Size(1200, 900)),
    ]) {
      testWidgets(
        'renders the full result with no overflow — $themeName / $sizeName',
        (tester) async {
          await tester.pumpWidget(
            hostTheme(
              TestMyConnectionScreen(
                enableLiveSampling: false,
                sourceOverride: WifiInfoSource.iosShortcuts,
                iosBridge: _PayloadBridge(),
                qualityClient: MockQualityClient(
                  scriptedResult: _marginalInternet(),
                ),
              ),
              theme,
              size: size,
            ),
          );
          await runCheck(tester);

          // The verdict line, the % comparison, and the always-shown detail are
          // all present and painted clean (no RenderFlex overflow).
          expect(
            find.text('Your internet is the limit right now, not your Wi-Fi.'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Your Wi-Fi link is about 11x faster than your internet '
              'connection.',
            ),
            findsOneWidget,
          );
          expect(find.text('Wi-Fi usable capacity'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  // The muted Copy-button helper line renders directly under "Copy these
  // details" in BOTH themes, and reads in the quiet textTertiary tone.
  for (final (String themeName, ThemeData theme) in <(String, ThemeData)>[
    ('dark', AppTheme.dark()),
    ('light', AppTheme.light()),
  ]) {
    testWidgets(
      'the Copy-button helper hint renders under the copy button ($themeName)',
      (tester) async {
        await tester.pumpWidget(
          hostTheme(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _PayloadBridge(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
            theme,
          ),
        );
        await runCheck(tester);

        const String hint =
            'Paste this into an email or text to your IT or support team.';
        final Finder hintFinder = find.text(hint);
        expect(hintFinder, findsOneWidget);

        // Quiet tone: it uses the muted textTertiary token (GL-003 §8.2), never
        // the primary text color, so it reads as a helper line, not body copy.
        final AppColorScheme colors = theme.extension<AppColorScheme>()!;
        final Text hintText = tester.widget<Text>(hintFinder);
        expect(hintText.style?.color, colors.textTertiary);

        // No em-dash or en-dash anywhere in the hint (hard ban), and the copy
        // never uses a bare "AP".
        expect(hint.contains('—'), isFalse); // em-dash
        expect(hint.contains('–'), isFalse); // en-dash
        expect(RegExp(r'\bAP\b').hasMatch(hint), isFalse);

        // It sits directly under the copy button (both in the help-desk card).
        expect(find.text('Copy these details'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // ---- iOS first-run live-card fix (2026-06-07) -------------------------------
  //
  // Reproduces Keith's beta 1.1.3 bug: the FIRST run rendered a "LIVE" header in
  // the Wi-Fi signal card with nothing behind it because a stale persisted
  // monitoring flag resumed the controller to `streaming` with no producer. The
  // fix makes the live state honest (in-session start required), so the card
  // shows the actionable Start, and tapping it fires the Shortcut.
  group('iOS first-run Wi-Fi signal card', () {
    testWidgets(
      'on MERE LOAD (no run yet) with a STALE monitoring flag the card shows the '
      'actionable Start control, not a stuck LIVE state, and never auto-fires',
      (tester) async {
        // The first-run protection (2026-06-07) is about SCREEN ENTRY: opening
        // the front door must NOT auto-fire the Shortcut (the bounce gotcha) and
        // must NOT render a dead "LIVE" from a stale persisted flag. The auto-
        // fire is tied to RUNNING a check (see the run-auto-fire test below), so
        // before any run this card stays on the honest idle Start state.
        final bridge = _StaleFlagBridge();
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        addTearDown(sampler.dispose);
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: bridge,
              sampler: sampler,
              securityService: _FakeSecurityService(),
              dnsProbeService: _FakeDnsProbe(),
              networkDetailsService: _FakeNetworkDetails(),
              enableCloudApps: false,
              onboardingService: _seenOnboarding(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        // Settle the load WITHOUT running a check.
        await tester.pumpAndSettle();

        // Mere screen entry never fires the Shortcut (no bounce). The live card
        // only renders once a check has produced a verdict, so here we just
        // assert the load did not auto-fire and did not resume a phantom stream.
        expect(bridge.runShortcutCalls, 0);
        expect(sampler.isStreaming, isFalse);
      },
    );

    testWidgets(
      'RUNNING a check auto-fires the companion Shortcut ONCE (one-shot) — no '
      'manual tap, and NO persistent live stream / banner (Keith #8 + 2026-06-23)',
      (tester) async {
        final bridge = _StaleFlagBridge();
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        addTearDown(sampler.dispose);
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: bridge,
              sampler: sampler,
              securityService: _FakeSecurityService(),
              dnsProbeService: _FakeDnsProbe(),
              networkDetailsService: _FakeNetworkDetails(),
              enableCloudApps: false,
              onboardingService: _seenOnboarding(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        // Advance past the one-shot settle + retry window so no fake-async timer
        // is left pending when the tree disposes. The _StaleFlagBridge's updates
        // stream is empty, so no sample lands and the one-shot retry fires — the
        // call count is therefore ≥1 (one auto-fire, plus the one empty-payload
        // retry), never zero and never an endless loop.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        // 2026-06-23 (Keith, friends-at-dinner): the run auto-fires the Shortcut
        // ONCE (one-shot) with NO manual tap, but it must NOT raise the persistent
        // monitoring loop — so there is no continuous stream and no persistent iOS
        // banner. The Shortcut was fired (>=1), the persistent monitoring flag was
        // never raised, and the sampler is NOT streaming.
        expect(bridge.runShortcutCalls, greaterThanOrEqualTo(1));
        // The one-shot CLEARS the (stale-true) monitoring flag and never re-raises
        // it, so the looping Shortcut stops after its single cycle (banner clears).
        expect(bridge.monitoringFlag, isFalse);
        expect(sampler.isStreaming, isFalse);
        expect(find.text('LIVE'), findsNothing);
      },
    );
  });

  // ==========================================================================
  // Mandatory one-time "enable live Wi-Fi" onboarding (WiFiman pattern).
  //
  // The front door is the FIRST live surface most users hit, so the unmissable
  // one-time setup must lead from HERE — a user can never run the comparison
  // check first and only afterward discover the companion Shortcut exists. The
  // gate is the honest composite (never-received-payload AND not-seen-before)
  // and it is iOS-only.
  // ==========================================================================
  group('TestMyConnectionScreen — mandatory first-run onboarding (iOS)', () {
    /// An onboarding service backed by an in-memory SharedPreferences store, so
    /// the gate is exercised end to end without touching a real platform
    /// channel. [seen] seeds the persisted "already shown" flag.
    LiveOnboardingService onboardingSvc({bool seen = false}) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        if (seen) LiveOnboardingService.prefsKey: true,
      });
      return LiveOnboardingService(getStore: SharedPreferences.getInstance);
    }

    testWidgets(
      'NATIVE-FIRST (2026-06-23): the front door does NOT auto-present the setup '
      'modal on first open — a casual user reaches the idle check with no modal',
      (tester) async {
        final bridge = _FreshBridge();
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: bridge,
              onboardingService: onboardingSvc(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The forced modal setup sheet must NOT auto-fire on open (the friends-
        // at-dinner friction). No modal, no Shortcuts deep-link bounce.
        expect(find.text('Set up live Wi-Fi'), findsNothing);
        expect(bridge.openUrlCalls, 0);
        // The normal front-door idle state renders instead, with zero taps.
        expect(find.text('Check My Connection'), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT fire when the app has EVER received a payload (already set up)',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _PayloadBridge(), // hasEverReceivedPayload == true
              onboardingService: onboardingSvc(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // A user who demonstrably has the Shortcut working is never nagged.
        expect(find.text('Set up live Wi-Fi'), findsNothing);
        // The normal front-door idle state is shown instead.
        expect(find.text('Check My Connection'), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT fire when the onboarding sheet was already shown once',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _FreshBridge(),
              onboardingService: onboardingSvc(seen: true),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // One-time: the persisted seen-flag suppresses the sheet on every later
        // open, even though the Shortcut is not yet demonstrably working.
        expect(find.text('Set up live Wi-Fi'), findsNothing);
        expect(find.text('Check My Connection'), findsOneWidget);
      },
    );

    testWidgets(
      'does NOT fire on macOS (CoreWLAN reads natively — iOS-only flow)',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              macAdapter: _FakeMacAdapter(),
              onboardingService: onboardingSvc(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Set up live Wi-Fi'), findsNothing);
        expect(find.text('Check My Connection'), findsOneWidget);
      },
    );
  });

  // ---- SAME-TIER HERO (2026-06-07, Vera gate / Keith) ----
  //
  // When BOTH absolute axis chips land on the SAME real tier, the hero is worded
  // by MARGIN (the same +/-10% band the comparison line uses) instead of naming a
  // "slow part / limit". The different-tier hero is unchanged.
  group('same-tier hero', () {
    testWidgets(
      'strong/strong within +/-10% reads "Both sides are strong. They’re about '
      'the same speed."',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 720 → usable Wi-Fi 396 (Strong). Internet 440/360 → avg 400
              // (Strong). margin = round(100*(396-400)/400) = -1% → about same.
              macAdapter: _TxLinkMacAdapter(720),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 440, up: 360),
              ),
            ),
          ),
        );
        await runCheck(tester);

        final Finder hero = find.text(
          'Both sides are strong. They’re about the same speed.',
        );
        expect(hero, findsOneWidget);
        // Still the H1 hero — headlineLarge / 36px.
        expect(tester.widget<Text>(hero).style?.fontSize, 36);
        // Both chips read Strong; no "slow part / limit" wording.
        expect(find.text('Strong'), findsNWidgets(2));
        expect(find.textContaining('slow part'), findsNothing);
      },
    );

    testWidgets(
      'moderate/moderate with Wi-Fi ahead reads "Both sides are moderate. Your '
      'Wi-Fi is slightly ahead."',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 360 → usable Wi-Fi 198 (Moderate). Internet 200/100 → avg 150
              // (Moderate). margin = round(100*(198-150)/150) = 32% → Wi-Fi ahead.
              macAdapter: _TxLinkMacAdapter(360),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 200, up: 100),
              ),
            ),
          ),
        );
        await runCheck(tester);

        expect(
          find.text('Both sides are moderate. Your Wi-Fi is slightly ahead.'),
          findsOneWidget,
        );
        expect(find.text('Moderate'), findsNWidgets(2));
        expect(find.textContaining('slow part'), findsNothing);
      },
    );

    testWidgets(
      'moderate/moderate with internet ahead names the internet side',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 240 → usable Wi-Fi 132 (Moderate). Internet 220/160 → avg 190
              // (Moderate). margin = round(100*(132-190)/190) = -31% → internet
              // ahead.
              macAdapter: _TxLinkMacAdapter(240),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 220, up: 160),
              ),
            ),
          ),
        );
        await runCheck(tester);

        expect(
          find.text(
            'Both sides are moderate. Your internet is slightly ahead.',
          ),
          findsOneWidget,
        );
        expect(find.text('Moderate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'moderate/moderate within +/-10% reads "about the same speed"',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 360 → usable Wi-Fi 198 (Moderate). Internet 240/160 → avg 200
              // (Moderate). margin = round(100*(198-200)/200) = -1% → about same.
              macAdapter: _TxLinkMacAdapter(360),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 240, up: 160),
              ),
            ),
          ),
        );
        await runCheck(tester);

        expect(
          find.text('Both sides are moderate. They’re about the same speed.'),
          findsOneWidget,
        );
        expect(find.text('Moderate'), findsNWidgets(2));
      },
    );

    testWidgets(
      'weak/weak within +/-10% reads "Both sides are weak. They’re about the '
      'same speed."',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 120 → usable Wi-Fi 66 (Weak). Internet 80/40 → avg 60 (Weak).
              // margin = round(100*(66-60)/60) = 10% → within band → about same.
              macAdapter: _TxLinkMacAdapter(120),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 80, up: 40),
              ),
            ),
          ),
        );
        await runCheck(tester);

        expect(
          find.text('Both sides are weak. They’re about the same speed.'),
          findsOneWidget,
        );
        expect(find.text('Weak'), findsNWidgets(2));
        // The HERO no longer names a slow part; the separate verdict LINE keeps
        // its existing "weak link" wording (unchanged by this fix).
        expect(find.textContaining('Your Wi-Fi is the slow part'), findsNothing);
      },
    );

    testWidgets(
      'weak/weak with Wi-Fi ahead names the Wi-Fi side',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 120 → usable Wi-Fi 66 (Weak). Internet 40/20 → avg 30 (Weak).
              // margin = round(100*(66-30)/30) = 120% → Wi-Fi ahead.
              macAdapter: _TxLinkMacAdapter(120),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 40, up: 20),
              ),
            ),
          ),
        );
        await runCheck(tester);

        expect(
          find.text('Both sides are weak. Your Wi-Fi is slightly ahead.'),
          findsOneWidget,
        );
        expect(find.text('Weak'), findsNWidgets(2));
      },
    );

    testWidgets(
      'DIFFERENT-tier hero is UNCHANGED: strong Wi-Fi + weak internet still '
      'names the internet as the slow part (no "Both sides are")',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // Tx 720 → usable Wi-Fi 396 (Strong). Internet 60/20 → avg 40
              // (Weak). Different tiers → existing "slow part" wording stands.
              macAdapter: _TxLinkMacAdapter(720),
              qualityClient: MockQualityClient(
                scriptedResult: _internetAt(down: 60, up: 20),
              ),
            ),
          ),
        );
        await runCheck(tester);

        expect(
          find.text('Your internet is the slow part.'),
          findsOneWidget,
        );
        expect(find.textContaining('Both sides are'), findsNothing);
        expect(find.text('Strong'), findsOneWidget);
        expect(find.text('Weak'), findsOneWidget);
      },
    );
  });

  // ==========================================================================
  // Comprehensive copy payload + ISP (Keith ISP-ask + #6) and the AppBar
  // "Run again" affordance (Keith #8). The cloud panel is disabled in the copy
  // tests so no real reachability socket opens; the ISP service is injected.
  // ==========================================================================
  group('TestMyConnectionScreen — comprehensive copy + ISP + run-again', () {
    IpGeoResult ispSuccess() => IpGeoResult.success(
          query: '(my IP)',
          provider: IpGeoProvider.ipinfo,
          ip: '203.0.113.7',
          country: 'US',
          region: 'Utah',
          city: 'Lehi',
          isp: 'Fusion Networks',
          org: 'Fusion Networks',
          asn: 'AS396325',
        );

    testWidgets(
      'copy payload is sectioned (Wi-Fi / Internet / ISP / Verdict) and carries '
      'all available Wi-Fi + internet fields plus the ISP block',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _PayloadBridge(),
              ipGeoService: _FakeIpGeoService(result: ispSuccess()),
              dnsProbeService: _FakeDnsProbe(),
              networkDetailsService: _FakeNetworkDetails(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);
        // Let the injected ISP / DNS / addressing lookups land before copying.
        await tester.pumpAndSettle();

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        // Polished report header + section headers (Keith #4).
        expect(copied, contains('WLAN Pros Toolbox: Connection Report'));
        expect(copied, contains('WI-FI'));
        expect(copied, contains('INTERNET'));
        expect(copied, contains('DNS'));
        expect(copied, contains('NETWORK'));
        expect(copied, contains('ISP'));
        expect(copied, contains('VERDICT'));
        // Verdict words still lead, in the summary line.
        expect(copied, contains('Summary: Wi-Fi '));
        // Full Wi-Fi block (iOS payload exposes everything).
        expect(copied, contains('Network (SSID): KeithNet'));
        expect(copied, contains('BSSID: a4:83:e7:00:11:22'));
        expect(copied, contains('RSSI: -58 dBm'));
        expect(copied, contains('SNR: 32 dB'));
        expect(copied, contains('Wi-Fi Down (Rx rate): 780 Mbps'));
        expect(copied, contains('Wi-Fi Up (Tx rate): 866 Mbps'));
        expect(copied, contains('Channel: 36'));
        expect(copied, contains('Standard (PHY): 802.11ax - Wi-Fi 6'));
        // Full internet block, including jitter/responsiveness (down/up retained).
        expect(copied, contains('Internet Down: 60 Mbps'));
        expect(copied, contains('Internet Up: 20 Mbps'));
        expect(copied, contains('Latency: 60 ms'));
        expect(copied, contains('Loss: 1%'));
        // DNS section carries a REAL resolution-time row (Keith #3) — the
        // injected probe resolved in a known time.
        expect(copied, contains('Resolution time: 12 ms'));
        // Network section carries the local addressing + the honest unavailable
        // DHCP / DNS-server / VLAN rows (Keith #5).
        expect(copied, contains('Local IP address: 192.168.1.42'));
        expect(copied, contains('Subnet mask: 255.255.255.0'));
        expect(copied, contains('Default gateway: 192.168.1.1'));
        expect(copied, contains('VLAN tag: Not visible to endpoint devices'));
        // ISP block from the injected lookup.
        expect(copied, contains('Public IP: 203.0.113.7'));
        expect(copied, contains('ISP / org: Fusion Networks'));
        expect(copied, contains('ASN: AS396325'));

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'ISP lookup fails open: an offline/failed lookup omits the ISP section but '
      'the copy + verdict still complete (GL-005 / GL-008)',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _PayloadBridge(),
              ipGeoService: _FakeIpGeoService(throws: true),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);
        await tester.pumpAndSettle();

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        // The check still produced a full payload…
        expect(copied, contains('WI-FI'));
        expect(copied, contains('INTERNET'));
        expect(copied, contains('VERDICT'));
        // …but the ISP section is cleanly omitted (no header, no fabricated IP).
        expect(copied, isNot(contains('ISP')));
        expect(copied, isNot(contains('Public IP:')));

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'macOS link still copies its available Wi-Fi fields and marks Rx '
      'unavailable in the sectioned payload',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              macAdapter: _FakeMacAdapter(),
              ipGeoService: _FakeIpGeoService(throws: true),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        expect(copied, contains('RSSI: -50 dBm'));
        expect(copied, contains('SNR: 45 dB'));
        expect(copied, contains('Noise: -95 dBm'));
        expect(copied, contains('Channel width: 80 MHz'));
        expect(copied, contains('Band: 5 GHz'));
        // macOS public CoreWLAN exposes no Rx → honest, KNOWN-platform-limit label.
        expect(
          copied,
          contains('Wi-Fi Down (Rx rate): Unavailable (not exposed on macOS)'),
        );
        expect(copied, contains('Wi-Fi Up (Tx rate): 866 Mbps'));

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'Verdict-card "Run again" shows the label + refresh icon and re-runs the '
      'whole test (Keith #8; re-run moved off the AppBar — Vera 2026-06-14; '
      'own row beneath the verdict sentence — Keith 2026-06-15)',
      (tester) async {
        final _CountingQualityClient quality =
            _CountingQualityClient(_marginalInternet());
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _PayloadBridge(),
              ipGeoService: _FakeIpGeoService(throws: true),
              qualityClient: quality,
            ),
          ),
        );

        await tester.pumpAndSettle();
        // No affordance before a result.
        expect(find.text('Run again'), findsNothing);

        await tester.tap(find.text('Check My Connection'));
        await tester.pumpAndSettle();
        expect(quality.measureCount, 1);

        // The affordance is now an unmistakable labeled action, not a bare glyph.
        expect(find.text('Run again'), findsOneWidget);
        expect(find.byIcon(Icons.refresh), findsOneWidget);
        expect(find.bySemanticsLabel('Run the test again'), findsOneWidget);

        await tester.tap(find.text('Run again'));
        await tester.pumpAndSettle();
        expect(quality.measureCount, 2);
      },
    );

    testWidgets(
      'loader shows the duration hint (Keith #9)',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _PayloadBridge(),
              ipGeoService: _FakeIpGeoService(throws: true),
              qualityClient: _CountingQualityClient(_marginalInternet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check My Connection'));
        // Pump a frame mid-run (the counting client delays 100ms before yielding).
        await tester.pump(const Duration(milliseconds: 40));

        expect(
          find.text('This usually takes about half a minute.'),
          findsOneWidget,
        );

        await tester.pumpAndSettle();
      },
    );
  });

  // =========================================================================
  // Wi-Fi RF availability + honest labeling (Felix, 2026-06-15).
  // =========================================================================
  group('Wi-Fi RF availability + honest labeling', () {
    /// macOS adapter whose snapshot carries an INVALID channel 0 — the
    /// "no/unknown channel" sentinel some stacks return. It must NEVER display
    /// as "0"; the honest "Unavailable" treatment shows instead (GL-005).
    ConnectedAp macSampleChannelZero() => ConnectedAp.fromWifiInfo(
          WifiInfo(
            interfaceName: 'en0',
            ssid: 'KeithNet',
            bssid: 'a4:83:e7:00:11:22',
            rssiDbm: -50,
            noiseDbm: -95,
            snrDb: 45,
            txRateMbps: 866,
            phyMode: '802.11ax',
            channel: 0,
            channelWidthMhz: 80,
            band: '5 GHz',
            countryCode: 'US',
            hardwareAddress: 'a4:83:e7:aa:bb:cc',
            poweredOn: true,
            locationAuthorized: true,
          ),
        );

    testWidgets(
      'channel 0 is never shown — the copy report marks Channel Unavailable',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              macAdapter: _StaticMacAdapter(macSampleChannelZero()),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        expect(copied, contains('Channel: Unavailable'));
        expect(copied, isNot(contains('Channel: 0')));

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'macOS without Location authorization labels SSID/BSSID with the grant '
      'hint in the copy report (not a bare Unavailable)',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              sourceOverride: WifiInfoSource.macosCoreWlan,
              // _NoNameMacAdapter: snapshot has SSID/BSSID null and
              // currentNameAuthorization() == false (Location not granted).
              macAdapter: _NoNameMacAdapter(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        expect(
          copied,
          contains(
            'Network (SSID): Unavailable (grant Location access to show the '
            'network name)',
          ),
        );
        expect(
          copied,
          contains(
            'BSSID: Unavailable (grant Location access to show the network '
            'name)',
          ),
        );

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'iOS with NO captured RF shows the "Capture Wi-Fi details" affordance, '
      'not a silent grid of Unavailable',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableLiveSampling: false,
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              // _FreshBridge.readLatest() == null → no RF captured.
              iosBridge: _FreshBridge(),
              securityService: _FakeSecurityService(),
              onboardingService: _seenOnboarding(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);

        // The Wi-Fi link sub-card leads with the capture affordance.
        expect(find.text('Capture Wi-Fi details'), findsOneWidget);

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        // The copy report names the capture step rather than silently listing
        // every RF row as a plain Unavailable.
        final String copied = clipboardWrites.last;
        expect(copied, contains('Wi-Fi signal details not captured'));

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'iOS enriches Security + BSSID natively (NEHotspotNetwork) even with no '
      'captured RF',
      (tester) async {
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              // enableLiveSampling on so the injected security fake is consulted.
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: _FreshBridge(),
              onboardingService: _seenOnboarding(),
              securityService: _FakeSecurityService(
                info: const WifiSecurityInfo(
                  available: true,
                  securityToken: 'personal',
                  bssid: 'b8:27:eb:11:22:33',
                  ssid: 'KeithNet',
                  locationAuthorized: true,
                ),
              ),
              dnsProbeService: _FakeDnsProbe(),
              networkDetailsService: _FakeNetworkDetails(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        await settleDetails(tester);
        await tester.pumpAndSettle();

        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        // Security + BSSID populated from the native read despite no Shortcut RF.
        expect(copied, contains('BSSID: b8:27:eb:11:22:33'));
        expect(copied, isNot(contains('Security: Unavailable')));

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'iOS copy serializes the LIVE-streamed RF when the one-shot read had none '
      '(copy == what is on screen)',
      (tester) async {
        // The exact bug Keith hit on device: the one-shot bridge readLatest()
        // returns null (no RF in the one-shot read), but the LIVE companion-
        // Shortcut stream delivers a rich payload — the same source the on-screen
        // sparklines bind to. Before the fix, the copy read only the one-shot
        // _ap and listed every RF row as "Unavailable" while the sparklines
        // showed live data. After the fix, [_effectiveAp] folds the live sampler
        // onto the one-shot read, so the copy serializes the live RF.
        final _StreamingBridge bridge = _StreamingBridge();
        final WifiSignalSampler sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        addTearDown(sampler.dispose);

        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              // One-shot read returns null → _ap carries NO RF on its own.
              iosBridge: bridge,
              // The live sampler over the SAME streaming bridge → the on-screen
              // sparkline source. Injected so the copy/technical reads unify on it.
              sampler: sampler,
              // Native NEHotspotNetwork security/BSSID — so the one-shot read
              // yields a minimal link (a real, non-D1 verdict) carrying identity
              // but NO RF. The RF must then come from the live source.
              securityService: _FakeSecurityService(
                info: const WifiSecurityInfo(
                  available: true,
                  securityToken: 'personal',
                  bssid: 'a4:83:e7:00:11:22',
                  ssid: 'KeithNet',
                  locationAuthorized: true,
                ),
              ),
              onboardingService: _seenOnboarding(),
              dnsProbeService: _FakeDnsProbe(),
              networkDetailsService: _FakeNetworkDetails(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Bring the live stream up and deliver a rich RF sample BEFORE the run
        // completes — this is the source the on-screen sparklines bind to (the
        // mock quality client completes synchronously, so seeding the live
        // reading here mirrors the device case where the stream is already
        // delivering by the time the ~30s measurement finishes).
        await sampler.start();
        bridge.emit(const WiFiDetails(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          channel: 36,
          rssi: -58,
          noise: -90,
          standard: '802.11ax - Wi-Fi 6',
          rxRate: 780,
          txRate: 866,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Check My Connection'));
        await tester.pumpAndSettle();
        await settleDetails(tester);

        // The one-shot read carried only the native security/BSSID identity, NO
        // RF. So the copied report's RF rows (RSSI, channel, Rx/Tx, SNR) can ONLY
        // come from the live sampler the sparklines bind to — proving copy ==
        // what is on screen. Copied via the inline help-desk button.
        final Finder copyBtn = find.text('Copy these details');
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();

        final String copied = clipboardWrites.last;
        // The live RF is now in the copy — NOT "Unavailable".
        expect(copied, contains('RSSI: -58 dBm'));
        expect(copied, contains('Channel: 36'));
        expect(copied, contains('Wi-Fi Down (Rx rate): 780 Mbps'));
        expect(copied, contains('Wi-Fi Up (Tx rate): 866 Mbps'));
        // SNR derived from the live rssi/noise (-58 − -90 = 32).
        expect(copied, contains('SNR: 32 dB'));
        // And the "not captured" fallback note is gone — RF WAS captured (live).
        expect(copied, isNot(contains('Wi-Fi signal details not captured')));
        // The capture affordance is not shown either (RF is present on screen).
        expect(find.text('Capture Wi-Fi details'), findsNothing);

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );

    testWidgets(
      'iOS auto-fires the companion Shortcut ONCE on a run (no manual tap) — RF '
      'is captured automatically with NO persistent banner (Keith #8 + 2026-06-23)',
      (tester) async {
        // Keith #8 + 2026-06-23: running the test must auto-capture Wi-Fi RF with
        // zero taps, but as a ONE-SHOT — the Shortcut fires once and no persistent
        // monitoring loop / iOS banner is left running. The bridge records
        // runShortcut() calls; we then deliver a sample (the single Shortcut cycle
        // delivering) and confirm RF lands with no Start / Capture tap and no
        // persistent stream.
        final _StreamingBridge bridge = _StreamingBridge();
        final WifiSignalSampler sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        addTearDown(sampler.dispose);

        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              enableCloudApps: false,
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: bridge,
              sampler: sampler,
              // Inject so the link read does not touch the real NEHotspotNetwork
              // channel (which hangs the run in a widget test).
              securityService: _FakeSecurityService(),
              onboardingService: _seenOnboarding(),
              dnsProbeService: _FakeDnsProbe(),
              networkDetailsService: _FakeNetworkDetails(),
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);
        // Advance past the one-shot settle + retry window so no fake-async timer
        // is left pending.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        // The companion Shortcut was fired AUTOMATICALLY by the run — no manual
        // Start / Capture tap from the test. This is the core of Keith #8.
        expect(bridge.runShortcutCalls, greaterThanOrEqualTo(1));
        // 2026-06-23: the auto-capture is a ONE-SHOT, so it must NOT raise the
        // persistent monitoring flag and must NOT leave a continuous stream up.
        expect(bridge.monitoringActive, isFalse);
        expect(sampler.isStreaming, isFalse);

        // The single Shortcut cycle then delivers a sample — the one-shot's
        // transient capture folds it into the latest reading (so it shows on
        // screen and in the copy), with no manual Start / Capture tap and without
        // promoting the screen into a persistent live stream.
        bridge.emit(const WiFiDetails(
          ssid: 'KeithNet',
          bssid: 'a4:83:e7:00:11:22',
          channel: 36,
          rssi: -58,
          noise: -90,
          standard: '802.11ax - Wi-Fi 6',
          rxRate: 780,
          txRate: 866,
        ));
        await tester.pumpAndSettle();
        expect(sampler.latest?.rssiDbm, -58);
        // Still no persistent stream after the sample lands (one-shot, not loop).
        expect(sampler.isStreaming, isFalse);

        await tester.pump(const Duration(milliseconds: 1600));
      },
    );
  });
}

/// An iOS bridge whose one-shot [readLatest] is EMPTY (null) but whose live
/// [updates] stream can be driven with [emit]. Models the device condition Keith
/// hit: the live companion-Shortcut stream feeds the on-screen sparklines while
/// the one-shot App-Group read has not (yet) captured RF. [runShortcut] is
/// recorded so the auto-fire test can prove the run fired it with no manual tap.
class _StreamingBridge implements WiFiDetailsBridge {
  final StreamController<WiFiDetails> _events =
      StreamController<WiFiDetails>.broadcast();
  bool _monitoring = false;
  int runShortcutCalls = 0;

  /// Exposes the persisted monitoring flag so a test can assert a one-shot read
  /// never raises it (2026-06-23).
  bool get monitoringActive => _monitoring;

  void emit(WiFiDetails d) => _events.add(d);

  @override
  Future<bool> hasEverReceivedPayload() async => false;
  @override
  Future<WiFiDetails?> readLatest() async => null;
  @override
  Future<bool> isMonitoringActive() async => _monitoring;
  @override
  Future<void> setMonitoringActive(bool active) async {
    _monitoring = active;
  }

  @override
  Future<bool> openUrl(String url) async => true;
  @override
  Future<bool> runShortcut(String name) async {
    runShortcutCalls++;
    return true;
  }

  @override
  Stream<WiFiDetails> get updates => _events.stream;
}

/// A macOS adapter that returns a caller-supplied [ConnectedAp]. Used to drive
/// edge-case snapshots (e.g. an invalid channel 0) through the screen.
class _StaticMacAdapter implements WifiInfoAdapter {
  _StaticMacAdapter(this._ap);

  final ConnectedAp _ap;

  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() async => _ap;
  @override
  Future<bool> requestNamePermission() async => true;
  @override
  Future<bool> currentNameAuthorization() async => true;
  @override
  Future<LocationAuthStatus> nameAuthorizationStatus() async =>
      LocationAuthStatus.authorized;
  @override
  Future<bool> openNamePermissionSettings() async => true;
}
