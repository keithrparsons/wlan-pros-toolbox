// Tests for the Signal Thresholds reference screen.
//
// Dataset tests assert the load-bearing thresholds: the RSSI quality-scale
// bands default to KEITH PARSONS' master scale (19 Nov 2026: Excellent -66 dBm
// and stronger, Good -67 to -72, Fair -73 to -78, Poor -79 to -84, Unusable -85
// and weaker), and follow the user's own bands from RssiScaleStore. The values
// below are hand-typed from Keith's scale (NOT read back from the code under
// test), so a drift on either side breaks this. The per-application
// RSSI/SNR targets and the SNR/MCS floor are ported from the rf-tools-pwa
// `rssi` tool.
//
// The widget-viewport smoke test lives in test/widget_test.dart (uses the
// shared private `_withViewport` phone-viewport helper there). A multi-width
// overflow regression below pumps the screen at 320/375/768/1280 widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/settings/signal_bands_settings_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/services/network/rssi_scale.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  setUp(RssiScaleStore.resetForTest);
  tearDown(RssiScaleStore.resetForTest);

  group('Signal Thresholds dataset', () {
    AppThreshold byApp(String name) => SignalThresholdsScreen.kAppThresholds
        .firstWhere((AppThreshold t) => t.application == name);

    test('VoIP target is -67 dBm / 25 dB SNR', () {
      final AppThreshold voip = byApp('VoIP / Real-time');
      expect(voip.minRssi, '-67 dBm');
      expect(voip.minSnr, '25 dB');
    });

    test('HD video target is -70 dBm / 20 dB SNR', () {
      final AppThreshold video = byApp('Video streaming (HD)');
      expect(video.minRssi, '-70 dBm');
      expect(video.minSnr, '20 dB');
    });

    test('General browsing data target is -70 dBm / 15 dB SNR', () {
      final AppThreshold data = byApp('General browsing');
      expect(data.minRssi, '-70 dBm');
      expect(data.minSnr, '15 dB');
    });

    test('Location / RTLS target is -75 dBm / 15 dB SNR', () {
      final AppThreshold loc = byApp('Location / RTLS');
      expect(loc.minRssi, '-75 dBm');
      expect(loc.minSnr, '15 dB');
    });

    test('Email / basic connectivity target is -75 dBm / 10 dB SNR', () {
      final AppThreshold email = byApp('Email / basic data');
      expect(email.minRssi, '-75 dBm');
      expect(email.minSnr, '10 dB');
    });

    test('all six PWA application rows are present', () {
      expect(SignalThresholdsScreen.kAppThresholds.length, 6);
    });

    test("Keith's default RSSI bands carry his master-scale ranges", () {
      String range(String label) => SignalThresholdsScreen.signalBands()
          .firstWhere((SignalBand b) => b.label == label)
          .range;
      expect(range('Excellent'), '-66 dBm and stronger');
      expect(range('Good'), '-67 to -72');
      expect(range('Fair'), '-73 to -78');
      expect(range('Poor'), '-79 to -84');
      expect(range('Unusable'), '-85 and weaker');
    });

    test('five RSSI quality bands are present, strongest first', () {
      expect(
        SignalThresholdsScreen.signalBands().map((SignalBand b) => b.label),
        <String>['Excellent', 'Good', 'Fair', 'Poor', 'Unusable'],
      );
    });

    test('Excellent/Good pass, Fair marginal, Poor and Unusable bad', () {
      SignalGrade grade(String label) => SignalThresholdsScreen.signalBands()
          .firstWhere((SignalBand b) => b.label == label)
          .grade;
      expect(grade('Excellent'), SignalGrade.good);
      expect(grade('Good'), SignalGrade.good);
      expect(grade('Fair'), SignalGrade.marginal);
      expect(grade('Poor'), SignalGrade.bad);
      expect(grade('Unusable'), SignalGrade.bad);
    });

    test('the table follows the user\'s own bands', () async {
      await RssiScaleStore.instance.save(
        const RssiScale(
          excellentMinDbm: -60,
          goodMinDbm: -65,
          fairMinDbm: -70,
          poorMinDbm: -80,
        ),
      );
      expect(
        SignalThresholdsScreen.signalBands().map((SignalBand b) => b.range),
        <String>[
          '-60 dBm and stronger',
          '-61 to -65',
          '-66 to -70',
          '-71 to -80',
          '-81 and weaker',
        ],
      );
    });

    test('SNR/MCS table runs MCS 0 at 5 dB up to MCS 11 at 35 dB', () {
      final List<SnrMcsRow> rows = SignalThresholdsScreen.kSnrMcsRows;
      expect(rows.length, 12);
      expect(rows.first.minSnr, '5 dB');
      expect(rows.first.mcs, 'MCS 0 - BPSK 1/2');
      expect(rows.last.minSnr, '35 dB');
      expect(rows.last.mcs, 'MCS 11 - 1024-QAM 5/6');
    });
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths',
      (tester) async {
    // Multi-width overflow regression: the threshold tables must not RenderFlex
    // overflow at small phone (320), phone (375), tablet (768), or desktop
    // (1280). Tall height so vertical scroll content never false-triggers.
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const SignalThresholdsScreen(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });

  testWidgets('Change signal bands opens Signal Bands settings and the table '
      'updates after a save', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(414, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const SignalThresholdsScreen(),
        routes: <String, WidgetBuilder>{
          AppRouter.signalBandsSettings: (_) =>
              const SignalBandsSettingsScreen(),
        },
      ),
    );
    expect(find.text('-66 dBm and stronger'), findsOneWidget);
    expect(find.text('-85 and weaker'), findsOneWidget);

    await tester.tap(find.text(SignalThresholdsScreen.kChangeBandsLabel));
    await tester.pumpAndSettle();
    expect(find.text(SignalBandsSettingsScreen.kTitle), findsOneWidget);

    await RssiScaleStore.instance.save(
      const RssiScale(
        excellentMinDbm: -60,
        goodMinDbm: -65,
        fairMinDbm: -70,
        poorMinDbm: -80,
      ),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('-60 dBm and stronger'), findsOneWidget);
    expect(find.text('-66 dBm and stronger'), findsNothing);
  });
}
