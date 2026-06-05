// TestMyConnectionScreen — widget tests for the merged Wave 4 tool, updated for
// the v1.1 result-readability reshape (2026-06-05, Iris spec).
//
// Drives the screen through its injection seams (a Wi-Fi source + fake
// adapter/bridge, a MockQualityClient with no network, live sampling disabled)
// so no real platform channel, socket, or poll timer is touched. Covers the
// v1.1 readability layout:
//   * (A) the VERDICT HERO renders the plain-language sentence (H1) + the two
//     side-by-side "Wi-Fi:" / "Internet:" status chips, each WORD + GLYPH;
//   * (B) the "what this means" line is always visible (not behind a disclosure);
//   * (C) the "A few things to try" 2–4 numbered steps render;
//   * (D) the "See the details" disclosure is COLLAPSED on first paint — the
//     Mbps / bars / help-desk / pro readout appear only after it is opened;
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
import 'package:wlan_pros_toolbox/screens/tools/network/test_my_connection_screen.dart';
import 'package:wlan_pros_toolbox/services/network/connected_ap.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_details_bridge.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_adapter.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
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

void main() {
  Widget host(Widget child, {Size? size}) => MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(size: size ?? const Size(390, 844)),
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

  /// Opens the (D) "See the details" disclosure so the technical layer (the
  /// comparison bars, the help-desk card, the pro readout) is in the tree.
  Future<void> openDetails(WidgetTester tester) async {
    final Finder row = find.text('See the details');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
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
      // internet outcome → Wi-Fi: Fine, Internet: Slow.
      expect(find.text('Wi-Fi:'), findsOneWidget);
      expect(find.text('Internet:'), findsOneWidget);
      expect(find.text('Fine'), findsOneWidget);
      expect(find.text('Slow'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget); // Fine
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget); // Slow
    },
  );

  testWidgets(
    '(B) the "what this means" line is visible without opening any disclosure',
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

      // internet outcome "what this means" — present at first paint, no tap.
      expect(
        find.textContaining(
          'Your Wi-Fi has room to spare. The internet coming into your home',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '(C) the "A few things to try" numbered steps render',
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

      // The section heading + the easiest-first internet steps (internet
      // outcome → internet self-help list).
      expect(find.text('A few things to try'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(
        find.text('Check if your provider has an outage in your area.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '(D) "See the details" is COLLAPSED on first paint — the bars and the '
    'help-desk card appear only after it is opened',
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

      // The disclosure row exists; its technical content does NOT, collapsed.
      expect(find.text('See the details'), findsOneWidget);
      expect(find.text('Wi-Fi usable capacity'), findsNothing);
      expect(find.text('What to tell support'), findsNothing);
      expect(find.text('Wi-Fi vs Internet'), findsNothing);

      // Open it — now the technical layer is in the tree.
      await openDetails(tester);
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
      expect(find.text("Couldn't check"), findsNWidgets(2));
      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
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
      await openDetails(tester);

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
      await openDetails(tester);

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
      await openDetails(tester);

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

      // The measured internet figure lives behind the details disclosure now.
      await openDetails(tester);
      expect(find.text('Internet Down'), findsOneWidget);
      expect(find.text('60 Mbps'), findsOneWidget);
    },
  );
}
