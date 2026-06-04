// Widget smoke tests for the Batch 4 standalone utilities.
//
// Each test pumps the screen in a phone-sized viewport (mirrors
// test/widget_test.dart _withViewport) so the input + selector layout does not
// log a RenderFlex overflow, then asserts the screen renders its key surfaces.
// The math is covered separately (unit_conversion_test / dtmf_test); these are
// render/wire-up guards.
//
// The DTMF screen constructs a DtmfPlayer (AudioPlayer) in initState; we never
// TAP a key in these tests, so no platform audio channel is exercised — the
// widget tree builds without a real audio backend.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:wlan_pros_toolbox/data/unit_conversion.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dtmf_generator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/qr_generator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/unit_converter_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}

void main() {
  group('UnitConverterScreen', () {
    testWidgets('renders the category + value + result surfaces', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const UnitConverterScreen(),
          ),
        );
        expect(find.text('Unit Converter'), findsWidgets);
        expect(find.text('Category'), findsOneWidget);
        expect(find.text('Value'), findsOneWidget);
        expect(find.text('Result'), findsOneWidget);
        // Category select + from-unit + to-unit selects.
        expect(find.byType(AppSelect<UnitCategory>), findsOneWidget);
        expect(find.byType(AppSelect<Unit>), findsNWidgets(2));
      });
    });

    testWidgets('typing a value produces a finite result', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const UnitConverterScreen(),
          ),
        );
        // Default category is data rate; default from→to is bps→kbps.
        // 1000 bps = 1 kbps.
        await tester.enterText(find.byType(TextField), '1000');
        await tester.pump();
        expect(find.text('1'), findsWidgets);
        // Em-free dash is only shown for an empty/invalid input.
        expect(find.text('—'), findsNothing);
      });
    });

    testWidgets('clearing the value blanks the result to an em-free dash', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const UnitConverterScreen(),
          ),
        );
        await tester.enterText(find.byType(TextField), '1000');
        await tester.pump();
        await tester.enterText(find.byType(TextField), '');
        await tester.pump();
        expect(find.text('—'), findsOneWidget);
      });
    });
  });

  group('QrGeneratorScreen', () {
    testWidgets('shows the empty state until text is entered', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const QrGeneratorScreen(),
          ),
        );
        expect(find.text('QR Code Generator'), findsWidgets);
        expect(find.text('Text or URL'), findsOneWidget);
        // No QR until there is data.
        expect(find.byType(PrettyQrView), findsNothing);
      });
    });

    testWidgets('entering a URL renders the QR + Share button', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const QrGeneratorScreen(),
          ),
        );
        await tester.enterText(
          find.byType(TextField),
          'https://wlanpros.com',
        );
        await tester.pump();
        expect(find.byType(PrettyQrView), findsOneWidget);
        expect(find.text('Share / Save'), findsOneWidget);
      });
    });
  });

  group('DtmfGeneratorScreen', () {
    testWidgets('renders the 16-key keypad and the Play toggle', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DtmfGeneratorScreen(),
          ),
        );
        expect(find.text('DTMF Generator'), findsWidgets);
        // 16 outline keypad buttons.
        expect(find.byType(OutlinedButton), findsNWidgets(16));
        // The primary Play toggle (defaults to key 5).
        expect(find.textContaining('Play (5)'), findsOneWidget);
      });
    });

    testWidgets('each key carries an explicit "DTMF key N" Semantics label', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DtmfGeneratorScreen(),
          ),
        );
        // Spot-check a few keys' SR labels (§8.9).
        expect(
          find.bySemanticsLabel('DTMF key 5'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('DTMF key #'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('DTMF key A'),
          findsOneWidget,
        );
      });
    });
  });
}
