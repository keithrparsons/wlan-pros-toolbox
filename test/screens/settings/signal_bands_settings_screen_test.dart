// Signal Bands settings screen: the user sets all four RSSI boundaries (five
// bands), with validation, Save, and Reset to Keith Parsons' defaults.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/settings/signal_bands_settings_screen.dart';
import 'package:wlan_pros_toolbox/services/network/rssi_scale.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Finder _field(int i) => find.byKey(ValueKey<String>('signal-band-field-$i'));

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(414, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: const SignalBandsSettingsScreen(),
    ),
  );
  await tester.pump();
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, SignalBandsSettingsScreen.kSaveLabel),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    RssiScaleStore.resetForTest();
  });
  tearDown(RssiScaleStore.resetForTest);

  testWidgets('opens on Keith Parsons\' defaults, with all five bands shown', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text(SignalBandsSettingsScreen.kTitle), findsOneWidget);
    expect(find.text(SignalBandsSettingsScreen.kIntro), findsOneWidget);
    for (int i = 0; i < 4; i++) {
      expect(
        tester.widget<TextField>(_field(i)).controller!.text,
        <String>['-66', '-72', '-78', '-84'][i],
      );
    }
    for (final String r in <String>[
      '-66 dBm and stronger',
      '-67 to -72',
      '-73 to -78',
      '-79 to -84',
      '-85 and weaker',
    ]) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.text('Unusable'), findsOneWidget);
    // Nothing changed yet, so Save is off.
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('saving new boundaries updates the store and the grades', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field(0), '-60');
    await tester.enterText(_field(1), '-65');
    await tester.enterText(_field(2), '-70');
    await tester.enterText(_field(3), '-80');
    await tester.pump();
    expect(find.text('-60 dBm and stronger'), findsOneWidget);
    expect(find.text('-81 and weaker'), findsOneWidget);

    await tester.tap(find.text(SignalBandsSettingsScreen.kSaveLabel));
    await tester.pumpAndSettle();
    expect(
      RssiScaleStore.instance.value,
      const RssiScale(
        excellentMinDbm: -60,
        goodMinDbm: -65,
        fairMinDbm: -70,
        poorMinDbm: -80,
      ),
    );
    expect(find.text(SignalBandsSettingsScreen.kSavedMessage), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(RssiScaleStore.prefsKey), isNotNull);
  });

  testWidgets('out-of-order input shows an error and blocks Save', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field(1), '-60'); // stronger than Excellent -66
    await tester.pump();
    expect(find.text('Must be weaker than -66'), findsOneWidget);
    expect(find.text('Fix the fields above to see the bands.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
    expect(RssiScaleStore.instance.value, RssiScale.defaults);
  });

  testWidgets('equal, empty or out-of-range input is rejected', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field(2), '-72'); // same as Good: empty band
    await tester.pump();
    expect(find.text('Must be weaker than -72'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(_field(2), '-78');
    await tester.enterText(_field(3), '-120');
    await tester.pump();
    expect(find.text('Enter -100 to -30 dBm'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(_field(3), '');
    await tester.pump();
    expect(find.text('Enter a whole number, for example -70'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('Reset restores Keith Parsons\' defaults and the fields', (
    WidgetTester tester,
  ) async {
    await RssiScaleStore.instance.save(
      const RssiScale(
        excellentMinDbm: -60,
        goodMinDbm: -65,
        fairMinDbm: -70,
        poorMinDbm: -80,
      ),
    );
    await _pump(tester);
    expect(tester.widget<TextField>(_field(0)).controller!.text, '-60');

    await tester.tap(find.text(SignalBandsSettingsScreen.kResetLabel));
    await tester.pumpAndSettle();
    expect(RssiScaleStore.instance.value, RssiScale.defaults);
    expect(tester.widget<TextField>(_field(0)).controller!.text, '-66');
    expect(tester.widget<TextField>(_field(3)).controller!.text, '-84');
    expect(find.text(SignalBandsSettingsScreen.kResetMessage), findsOneWidget);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(RssiScaleStore.prefsKey), isFalse);
  });

  testWidgets('renders without overflow at 320, 375, 768 and 1280 wide', (
    WidgetTester tester,
  ) async {
    for (final double w in <double>[320, 375, 768, 1280]) {
      await _pump(tester, size: Size(w, 1400));
      expect(tester.takeException(), isNull, reason: 'overflow at ${w}px');
    }
  });

  test('the route is registered', () {
    expect(AppRouter.routes.containsKey(AppRouter.signalBandsSettings), isTrue);
  });
}
