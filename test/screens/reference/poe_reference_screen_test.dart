// Tests for the PoE Reference screen.
//
// The two datasets are ported verbatim from the RF Tools PWA (app.js POE_STDS +
// POE_CLASSES, view data-tool="poe"). These tests assert the load-bearing
// anchor rows so a future edit cannot silently drift a value away from the PWA,
// plus one phone-viewport widget test (mirrors test/widget_test.dart
// _withViewport) confirming the read-only screen renders without a RenderFlex
// overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('PoE standards — match PWA app.js POE_STDS', () {
    PoeStandard stdFor(String s) =>
        PoeReferenceScreen.standards.firstWhere((PoeStandard p) => p.standard == s);

    test('802.3af = 15.4 W PSE / 12.95 W PD', () {
      final PoeStandard p = stdFor('802.3af');
      expect(p.name, 'PoE');
      expect(p.pseWatts, 15.4);
      expect(p.pdWatts, 12.95);
      expect(p.pairs, '2 of 4');
      expect(p.classes, '0-3');
    });

    test('802.3at (PoE+) = 30 W PSE / 25.5 W PD', () {
      final PoeStandard p = stdFor('802.3at');
      expect(p.name, 'PoE+');
      expect(p.pseWatts, 30.0);
      expect(p.pdWatts, 25.5);
    });

    test('802.3bt Type 3 = 60 W PSE / 51 W PD / 4 of 4 pairs', () {
      final PoeStandard p = stdFor('802.3bt Type 3');
      expect(p.pseWatts, 60.0);
      expect(p.pdWatts, 51.0);
      expect(p.pairs, '4 of 4');
    });

    test('802.3bt Type 4 = 100 W PSE / 71.3 W PD (the 90-100 W tier)', () {
      final PoeStandard p = stdFor('802.3bt Type 4');
      expect(p.pseWatts, 100.0);
      expect(p.pdWatts, 71.3);
      expect(p.classes, '0-8');
    });

    test('four standards, all 802.3 (never 802.3x), no em dash', () {
      expect(PoeReferenceScreen.standards.length, 4);
      for (final PoeStandard p in PoeReferenceScreen.standards) {
        expect(p.standard.startsWith('802.3'), isTrue);
        expect(p.standard.contains('802.3x'), isFalse);
        expect(p.classes.contains('—'), isFalse, reason: 'no em dash');
        expect(p.classes.contains('-'), isTrue, reason: 'ASCII hyphen ranges');
      }
    });
  });

  group('PD power classes — match PWA app.js POE_CLASSES', () {
    PoeClass classFor(int n) =>
        PoeReferenceScreen.classes.firstWhere((PoeClass c) => c.classNum == n);

    test('class 0 = 12.95 W (default / unclassified)', () {
      final PoeClass c = classFor(0);
      expect(c.maxPdWatts, 12.95);
      expect(c.standard, '802.3af');
    });

    test('class 4 = 25.5 W (PoE+ max, 802.3at)', () {
      final PoeClass c = classFor(4);
      expect(c.maxPdWatts, 25.5);
      expect(c.standard, '802.3at');
    });

    test('class 8 = 71.3 W (Type 4 max, 802.3bt)', () {
      final PoeClass c = classFor(8);
      expect(c.maxPdWatts, 71.3);
      expect(c.standard, '802.3bt');
      expect(c.note, 'Type 4 max');
    });

    test('nine classes (0-8), all 802.3 standards', () {
      expect(PoeReferenceScreen.classes.length, 9);
      expect(
        PoeReferenceScreen.classes.map((PoeClass c) => c.classNum).toList(),
        <int>[0, 1, 2, 3, 4, 5, 6, 7, 8],
      );
      for (final PoeClass c in PoeReferenceScreen.classes) {
        expect(c.standard.startsWith('802.3'), isTrue);
        expect(c.standard.contains('802.3x'), isFalse);
      }
    });
  });

  group('PoeReferenceScreen widget', () {
    testWidgets('renders title and both table headings in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const PoeReferenceScreen(),
          ),
        );

        expect(find.text('PoE Reference'), findsWidgets);
        expect(find.text('PoE standards'), findsOneWidget);
        expect(find.text('PD power classes'), findsOneWidget);
        // An anchor row renders its load-bearing values. '802.3af' appears in
        // both tables (standards row + class 0-3 'Standard' cells), so scope the
        // finder to the standards-card label that is unique to that row.
        expect(find.text('802.3af'), findsWidgets);
        expect(find.text('PoE++ Hi'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1200), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const PoeReferenceScreen(),
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
/// Mirrors test/widget_test.dart _withViewport so the read-only reference
/// renders at phone width without a RenderFlex overflow.
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
