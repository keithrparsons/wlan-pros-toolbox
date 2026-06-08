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
//   * the AppBar Refresh re-runs the same check;
//   * a hung macOS link read can never hang the check.
//
// The copy text is intercepted at the Clipboard platform-channel boundary so the
// test asserts the EXACT payload the user would paste.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/live_onboarding_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_signal_sampler.dart';
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

class _NoNameMacAdapter implements WifiInfoAdapter {
  bool promptRequested = false;

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
  Future<bool> openNamePermissionSettings() async => true;
}

/// A macOS adapter whose SNAPSHOT READ never resolves — models the production
/// hang. The check must still complete with the link unread (ap = null →
/// "Couldn't check"), never hang, and never call the interactive prompt.
class _HangingMacAdapter implements WifiInfoAdapter {
  @override
  String get platformLabel => 'macOS CoreWLAN';
  @override
  bool get gatesNameBehindPermission => true;
  @override
  Future<ConnectedAp> fetch() => Completer<ConnectedAp>().future;
  @override
  Future<bool> requestNamePermission() =>
      throw StateError('A connection check must never prompt for Location.');
  @override
  Future<bool> currentNameAuthorization() async => false;
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
    'the internet rate',
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

      // usable Wi-Fi (16.5) sits below measured internet (40) → Wi-Fi limits.
      expect(
        find.text('Your Wi-Fi is the weak link right now.'),
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
      // N = round(100 * (452.65 - 40) / 40) = 1032, faster.
      expect(
        find.text(
          'Your Wi-Fi link is 1032% faster than your internet connection.',
        ),
        findsOneWidget,
      );
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
      expect(copied, contains('Wi-Fi: '));
      expect(copied, contains('Internet: '));
      expect(copied, contains('Internet Down: 60 Mbps'));
      expect(copied, contains('Internet Up: 20 Mbps'));
      expect(copied, isNot(contains(' down / ')));
      expect(copied, contains('RSSI: -58 dBm'));
      expect(copied, contains('SNR: 32 dB'));
      expect(copied, contains('Wi-Fi Down: 780 Mbps'));
      expect(copied, contains('Wi-Fi Up: 866 Mbps'));

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
      expect(copied, contains('Wi-Fi Down: Unavailable'));
      expect(copied, contains('Wi-Fi Up: 866 Mbps'));

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS check NEVER prompts for Location — reads with current authorization',
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

      expect(adapter.promptRequested, isFalse);
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS missing name degrades GRACEFULLY — row omitted, no Location error',
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

      expect(adapter.promptRequested, isFalse);
      expect(find.textContaining('Location Services'), findsNothing);
      expect(find.textContaining('Location access'), findsNothing);
      expect(find.text('Wi-Fi network'), findsNothing);
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'AppBar Refresh re-runs the same check and is disabled while running',
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
      expect(find.byIcon(Icons.refresh), findsNothing);

      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      expect(quality.measureCount, 1);

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.bySemanticsLabel('Run the test again'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();
      expect(quality.measureCount, 2);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.text('Wi-Fi:'), findsOneWidget);
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
              'Your Wi-Fi link is 1032% faster than your internet connection.',
            ),
            findsOneWidget,
          );
          expect(find.text('Wi-Fi usable capacity'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
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
      'first run with a STALE monitoring flag shows the actionable Start '
      'control, not a stuck LIVE state',
      (tester) async {
        final bridge = _StaleFlagBridge();
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: bridge,
              sampler: sampler,
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);

        // The live card is in the result detail. It must present Start, never a
        // dead LIVE header with no data behind it.
        expect(find.text('Start'), findsOneWidget);
        expect(find.text('LIVE'), findsNothing);
        // No Shortcut fired yet (no auto-fire on load — the bounce gotcha).
        expect(bridge.runShortcutCalls, 0);
      },
    );

    testWidgets(
      'tapping Start fires the companion Shortcut and flips the card to LIVE',
      (tester) async {
        final bridge = _StaleFlagBridge();
        final sampler = WifiSignalSampler(
          source: WifiInfoSource.iosShortcuts,
          iosBridge: bridge,
        );
        await tester.pumpWidget(
          host(
            TestMyConnectionScreen(
              sourceOverride: WifiInfoSource.iosShortcuts,
              iosBridge: bridge,
              sampler: sampler,
              qualityClient: MockQualityClient(
                scriptedResult: _marginalInternet(),
              ),
            ),
          ),
        );
        await runCheck(tester);

        // The live card sits deep in the scroll view; bring Start into the
        // viewport before tapping so the gesture lands on the button.
        await tester.ensureVisible(find.text('Start'));
        await tester.pumpAndSettle();
        // Tap Start, then let the async start() chain (flag write → runShortcut →
        // notify) flush before asserting.
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        // The deliberate tap fired the Shortcut exactly once and the card is now
        // genuinely live.
        expect(bridge.runShortcutCalls, 1);
        expect(sampler.isStreaming, isTrue);
        expect(find.text('LIVE'), findsOneWidget);
        expect(find.text('Start'), findsNothing);
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
      'fires ONCE on first open of the front door and deep-links to Shortcuts '
      '(never-received payload, not seen before)',
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

        // The one-time setup sheet auto-presented BEFORE any check — the user
        // is led to enable live Wi-Fi, not left to hit a wall.
        expect(find.text('Set up live Wi-Fi'), findsOneWidget);
        expect(find.text('Tap Add the Shortcut below.'), findsOneWidget);
        // The no-Location trust signal is led, per the brief.
        expect(find.textContaining('No Location permission'), findsOneWidget);

        // Tapping "Add the Shortcut" deep-links into Shortcuts (openUrl), the
        // WiFiman install bounce.
        await tester.tap(find.text('Add the Shortcut'));
        await tester.pumpAndSettle();
        expect(bridge.openUrlCalls, 1);
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
}
