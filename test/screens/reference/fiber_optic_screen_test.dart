// Tests for the Fiber Optic Cable Reference screen.
//
// The dataset is ported verbatim from the RF Tools PWA (app.js FIBER_DATA,
// view data-tool="fiber"). These tests assert the load-bearing anchor rows so
// a future edit cannot silently drift a value away from the PWA, plus one
// phone-viewport widget test (see test/widget_test.dart _withViewport)
// confirming the read-only screen renders without a RenderFlex overflow at
// 375pt — the distance grid is wider than a phone and scrolls horizontally.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/fiber_optic_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('fiber types — match PWA app.js FIBER_DATA', () {
    FiberType rowFor(String type) =>
        FiberOpticScreen.FIBER_DATA.firstWhere((FiberType f) => f.type == type);

    test('seven fiber types, in PWA order', () {
      expect(
        FiberOpticScreen.FIBER_DATA.map((FiberType f) => f.type).toList(),
        <String>['OM1', 'OM2', 'OM3', 'OM4', 'OM5', 'OS1', 'OS2'],
      );
    });

    test('OM1 — 62.5/125 µm, 200 MHz·km, Orange, 275 m @ 1G', () {
      final FiberType f = rowFor('OM1');
      expect(f.core, '62.5/125 µm');
      expect(f.bandwidth, '200');
      expect(f.jacketName, 'Orange');
      expect(f.dist1G, '275 m');
      expect(f.dist10G, '33 m');
      expect(f.dist40G, '—'); // not-supported data glyph, verbatim from PWA
      expect(f.dist100G, '—');
      expect(f.legacy, isTrue);
    });

    test('OM3 — 50/125 µm, 2,000 MHz·km, Aqua, current 10G standard', () {
      final FiberType f = rowFor('OM3');
      expect(f.core, '50/125 µm');
      expect(f.bandwidth, '2,000');
      expect(f.jacketName, 'Aqua');
      expect(f.dist1G, '1 km');
      expect(f.dist10G, '300 m');
      expect(f.dist40G, '100 m');
      expect(f.dist100G, '100 m');
      expect(f.legacy, isFalse);
    });

    test('OM4 — 4,700 MHz·km, Violet/Aqua jacket', () {
      final FiberType f = rowFor('OM4');
      expect(f.bandwidth, '4,700');
      expect(f.jacketName, 'Violet/Aqua');
      expect(f.dist10G, '550 m');
    });

    test('OM5 — wideband multimode, 28,000 MHz·km, Lime Green', () {
      final FiberType f = rowFor('OM5');
      expect(f.bandwidth, '28,000');
      expect(f.jacketName, 'Lime Green');
      expect(f.dist40G, '150 m');
    });

    test('OS1 — singlemode 9/125 µm, Yellow, no modal bandwidth', () {
      final FiberType f = rowFor('OS1');
      expect(f.core, '9/125 µm');
      expect(f.bandwidth, 'N/A');
      expect(f.jacketName, 'Yellow');
      expect(f.dist1G, '10+ km');
      expect(f.dist100G, '40+ km');
      expect(f.legacy, isFalse);
    });

    test('OS2 — singlemode long-haul, 80+ km @ 100G', () {
      final FiberType f = rowFor('OS2');
      expect(f.core, '9/125 µm');
      expect(f.bandwidth, 'N/A');
      expect(f.dist1G, '40+ km');
      expect(f.dist100G, '80+ km');
    });

    test('only OM1 and OM2 are legacy (faded rows)', () {
      final List<String> legacy = FiberOpticScreen.FIBER_DATA
          .where((FiberType f) => f.legacy)
          .map((FiberType f) => f.type)
          .toList();
      expect(legacy, <String>['OM1', 'OM2']);
    });

    test('jacket hex values match the PWA color codes', () {
      expect(rowFor('OM1').jacketHex, 0xFFE65100); // Orange
      expect(rowFor('OM3').jacketHex, 0xFF0097A7); // Aqua
      expect(rowFor('OM5').jacketHex, 0xFF7CB342); // Lime Green
      expect(rowFor('OS2').jacketHex, 0xFFF9A825); // Yellow
    });

    test('footnote cites TIA-568 / ISO 11801, no em-dash punctuation', () {
      expect(FiberOpticScreen.footnote.contains('TIA-568'), isTrue);
      expect(FiberOpticScreen.footnote.contains('ISO 11801'), isTrue);
      // The footnote prose must not use an em dash (—) as punctuation.
      expect(FiberOpticScreen.footnote.contains('—'), isFalse);
    });
  });

  group('widget — phone viewport', () {
    testWidgets(
      'Fiber Optic screen renders in a 375x900 phone viewport without overflow',
      (tester) async {
        // Phone-viewport smoke: pump, render the section headings and a known
        // PWA cell (OM3 row), and confirm no RenderFlex overflow even though
        // the distance grid is wider than the phone (it scrolls horizontally).
        await _withViewport(tester, const Size(375, 900), () async {
          final List<Object> overflow = <Object>[];
          final FlutterExceptionHandler? previous = FlutterError.onError;
          FlutterError.onError = (FlutterErrorDetails details) {
            if (details.exception.toString().contains('RenderFlex overflowed') ||
                details.exception.toString().contains('overflowed by')) {
              overflow.add(details.exception);
            }
          };
          addTearDown(() => FlutterError.onError = previous);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const FiberOpticScreen(),
            ),
          );
          await tester.pump();

          expect(find.text('Fiber Optic'), findsOneWidget);
          expect(find.text('Distance by data rate'), findsOneWidget);
          expect(find.text('Jacket color code & notes'), findsOneWidget);
          // OM3 appears in both the distance grid and the jacket card.
          expect(find.text('OM3'), findsWidgets);
          // A known PWA jacket color name.
          expect(find.text('Aqua'), findsOneWidget);

          expect(
            overflow,
            isEmpty,
            reason:
                'Fiber Optic screen must not log a RenderFlex overflow at '
                '375x900 — got: '
                '${overflow.map((Object e) => e.toString()).join("; ")}',
          );
        });
      },
    );

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const FiberOpticScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport`.
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
