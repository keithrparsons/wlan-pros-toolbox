// TestMyConnectionScreen — widget tests for the reworked results.
//
// Drives the screen through its injection seams (a Wi-Fi source + fake
// adapter/bridge, a MockQualityClient with no network) so no real platform
// channel or socket is touched. Covers:
//   * the removed "Likely cause" fact and the removed "call support" header no
//     longer render;
//   * the explanatory verdict conclusion sentence is gone — only the
//     "Wi-Fi:" / "Internet:" status chips carry the verdict;
//   * internet speed renders as two separate labeled rows ("Internet Down" /
//     "Internet Up"), never the old combined "332 Mbps down / 60 Mbps up"
//     string that wrapped mid-value;
//   * the new "Wi-Fi details" section renders RSSI / SNR, Wi-Fi Down, Wi-Fi Up;
//   * the copy-able details text carries internet down/up on separate labeled
//     lines and the four Wi-Fi values (iOS payload present → real values;
//     macOS Rx not exposed → "Wi-Fi Down: Unavailable", never fabricated, per
//     GL-005 / GL-008).
//
// The copy text is intercepted at the Clipboard platform-channel boundary
// (Clipboard.setData → SystemChannels.platform) so the test asserts the EXACT
// payload the user would paste, not a re-derivation of it.

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

/// macOS sample with the NAME gated off (Location not authorized): SSID/BSSID
/// null, RF metrics still present. Mirrors a real unauthorized snapshot.
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

/// A macOS adapter whose snapshot has no name (Location off) and whose
/// no-prompt status check reports unauthorized — used to assert TMC labels the
/// name honestly as "(Location access off)" WITHOUT ever prompting.
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
}

class _FakeMacAdapter implements WifiInfoAdapter {
  /// Set true if the screen ever calls the INTERACTIVE prompt path. A
  /// connection check must NEVER prompt, so the tests assert this stays false.
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
}

/// A macOS adapter whose SNAPSHOT READ never resolves — models the production
/// hang (stalled CoreWLAN channel that never returns). TMC no longer prompts
/// for Location (the no-prompt status check resolves immediately), so the path
/// that can still stall is the snapshot fetch. The real adapter bounds fetch at
/// the service layer; this fake bypasses that bound so the test exercises the
/// screen's own safety net (the 8s guard on the link future). The check must
/// still complete with the link unread (ap = null → "Couldn't check"), never
/// hang. It also asserts the interactive prompt is never called.
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

/// A [QualityClient] that counts how many times [measure] is subscribed,
/// proving the AppBar Refresh re-runs the SAME check (it re-invokes the screen's
/// one [_run] handler, which re-subscribes this client). Emits the same fixed
/// progress sequence as [MockQualityClient]; no network I/O.
class _CountingQualityClient implements QualityClient {
  _CountingQualityClient(this.scriptedResult);

  final QualityResult scriptedResult;
  QualityResult? _lastResult;

  /// Number of times the screen has started a run against this client.
  int measureCount = 0;

  @override
  bool get isAvailable => true;

  @override
  QualityResult? get lastResult => _lastResult;

  @override
  Stream<QualityProgress> measure() async* {
    measureCount++;
    // A small delay on the first event keeps the in-progress state observable
    // across a finite-duration pump (the production engine is not instant); the
    // bare MockQualityClient drains in one microtask, which would make the
    // running state un-catchable.
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

void main() {
  Widget host(Widget child, {Size? size}) => MaterialApp(
    theme: AppTheme.dark(),
    home: MediaQuery(
      data: MediaQueryData(size: size ?? const Size(390, 844)),
      child: child,
    ),
  );

  // Captures the last Clipboard.setData payload the screen writes.
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
    'result drops the "Likely cause" fact and the "call support" header',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      expect(find.text('Likely cause'), findsNothing);
      expect(
        find.text('If you need to call support, here’s what to tell them.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'verdict shows only the Wi-Fi / Internet status chips, no prose sentence',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The status chips remain — each axis still carries its own word.
      expect(find.text('Wi-Fi:'), findsOneWidget);
      expect(find.text('Internet:'), findsOneWidget);

      // The explanatory conclusion sentences are GONE for every outcome the
      // marginal-internet path can produce (A / mostly-Wi-Fi / internet).
      expect(
        find.textContaining('The slow part is between your device'),
        findsNothing,
      );
      expect(
        find.textContaining('Both your Wi-Fi and your internet are a little'),
        findsNothing,
      );
      expect(
        find.textContaining('the internet coming into your'),
        findsNothing,
      );
      expect(
        find.textContaining('both working well'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'internet speed renders as two separate "Internet Down" / "Internet Up" '
    'rows (no combined mid-value string)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // Two separate labeled rows, parallel to the Wi-Fi Down / Wi-Fi Up rows.
      expect(find.text('Internet Down'), findsOneWidget);
      expect(find.text('Internet Up'), findsOneWidget);
      // download 60, upload 20 from _marginalInternet().
      expect(find.text('60 Mbps'), findsOneWidget);
      expect(find.text('20 Mbps'), findsOneWidget);
      // The old combined string must be gone.
      expect(find.textContaining(' down / '), findsNothing);
      expect(find.text('Internet speed'), findsNothing);
    },
  );

  testWidgets('result renders the new "Wi-Fi details" section (iOS payload)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        TestMyConnectionScreen(
          sourceOverride: WifiInfoSource.iosShortcuts,
          iosBridge: _PayloadBridge(),
          qualityClient: MockQualityClient(scriptedResult: _marginalInternet()),
        ),
      ),
    );
    await runCheck(tester);

    expect(find.text('Wi-Fi details'), findsOneWidget);
    // RSSI / SNR row: rssi -58, snr = -58 − (-90) = 32.
    expect(find.text('-58 dBm / 32 dB'), findsOneWidget);
    // Wi-Fi Down (avg Rx) and Wi-Fi Up (avg Tx) labels + values.
    expect(find.text('Wi-Fi Down'), findsOneWidget);
    expect(find.text('Wi-Fi Up'), findsOneWidget);
    expect(find.text('780 Mbps'), findsOneWidget);
    expect(find.text('866 Mbps'), findsOneWidget);
  });

  testWidgets(
    'copy text includes the four Wi-Fi values and drops "Likely cause" (iOS)',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      final Finder copyBtn = find.text('Copy these details');
      await tester.ensureVisible(copyBtn);
      await tester.pumpAndSettle();
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(clipboardWrites, isNotEmpty);
      final String copied = clipboardWrites.last;
      // Internet down/up on their own labeled lines — one value per line.
      expect(copied, contains('Internet Down: 60 Mbps'));
      expect(copied, contains('Internet Up: 20 Mbps'));
      expect(copied, isNot(contains(' down / ')));
      expect(copied, contains('RSSI: -58 dBm'));
      expect(copied, contains('SNR: 32 dB'));
      expect(copied, contains('Wi-Fi Down: 780 Mbps'));
      expect(copied, contains('Wi-Fi Up: 866 Mbps'));
      expect(copied, isNot(contains('Likely cause')));

      // Let the 1.5s "Copied" revert timer fire so none is left pending.
      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS Rx not exposed → "Wi-Fi Down: Unavailable" on screen and in copy',
    (tester) async {
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: _FakeMacAdapter(),
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // On screen: Rx is "Unavailable", Tx (866) and RSSI/SNR are real.
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('-50 dBm / 45 dB'), findsOneWidget);
      expect(find.text('866 Mbps'), findsOneWidget);

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

      // Let the 1.5s "Copied" revert timer fire so none is left pending.
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
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // The interactive prompt path was never invoked during the check.
      expect(adapter.promptRequested, isFalse);
      // The check still produced a real Wi-Fi verdict from the link rate.
      expect(find.text('Wi-Fi:'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1600));
    },
  );

  testWidgets(
    'macOS name honestly "(Location access off)" when not authorized, no prompt',
    (tester) async {
      final _NoNameMacAdapter adapter = _NoNameMacAdapter();
      await tester.pumpWidget(
        host(
          TestMyConnectionScreen(
            sourceOverride: WifiInfoSource.macosCoreWlan,
            macAdapter: adapter,
            qualityClient: MockQualityClient(
              scriptedResult: _marginalInternet(),
            ),
          ),
        ),
      );
      await runCheck(tester);

      // No prompt was surfaced, and the missing name is labeled honestly —
      // never a fabricated SSID, never a bare "Not measured".
      expect(adapter.promptRequested, isFalse);
      expect(
        find.text('Name unavailable (Location access off)'),
        findsOneWidget,
      );

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
            sourceOverride: WifiInfoSource.iosShortcuts,
            iosBridge: _PayloadBridge(),
            qualityClient: quality,
          ),
        ),
      );

      // No Refresh before the first result — the big button is the affordance.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh), findsNothing);

      // First run via the big button.
      await tester.tap(find.text('Check My Connection'));
      await tester.pumpAndSettle();
      expect(quality.measureCount, 1);

      // Refresh now appears in the AppBar with the §a11y label.
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.bySemanticsLabel('Run the test again'), findsOneWidget);

      // Tap Refresh: a single pump lands on the in-progress state — the
      // refresh IconButton is gone (swapped for the spinner) so the test can
      // not be double-fired, and the second run has begun.
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // The re-run settles back to a result and the Refresh control restores.
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

      // The internet measurement drains, onDone fires, and the link future is
      // still pending (the snapshot read never resolves). Advance fake time
      // past the screen's 8s safety net so `await linkFuture.timeout(8s)` yields
      // null and the verdict computes on the internet-only path.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      // The verdict landed — the check did NOT hang.
      expect(find.text('Wi-Fi:'), findsOneWidget);
      expect(find.text('Internet:'), findsOneWidget);
      // Link unread → the Wi-Fi axis honestly reports "Couldn't check".
      expect(find.text("Couldn't check"), findsWidgets);
      // The internet result it DID measure is still shown.
      expect(find.text('Internet Down'), findsOneWidget);
      expect(find.text('60 Mbps'), findsOneWidget);
    },
  );
}
