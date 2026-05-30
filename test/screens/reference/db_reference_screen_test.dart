// Tests for the dB Reference screen.
//
// The two datasets are ported verbatim from the RF Tools PWA (app.js
// DB_RATIOS + DBM_REFS). These tests assert the load-bearing anchor rows so a
// future edit cannot silently drift a value away from the PWA, plus one phone-
// viewport widget test (see test/widget_test.dart _withViewport) confirming the
// read-only screen renders without a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/db_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('dB power ratios — match PWA app.js DB_RATIOS', () {
    DbRatio rowFor(String db) =>
        DbReferenceScreen.dbRatios.firstWhere((DbRatio r) => r.db == db);

    test('+3 dB is about 2x power (the double-power rule)', () {
      expect(rowFor('+3 dB').powerRatio, '2x');
    });

    test('+10 dB is 10x power', () {
      expect(rowFor('+10 dB').powerRatio, '10x');
    });

    test('+20 dB is 100x power', () {
      expect(rowFor('+20 dB').powerRatio, '100x');
    });

    test('+6 dB is 4x power, 2x voltage', () {
      final DbRatio r = rowFor('+6 dB');
      expect(r.powerRatio, '4x');
      expect(r.voltageRatio, '2x');
    });

    test('-3 dB is half power', () {
      expect(rowFor('-3 dB').powerRatio, '1/2x');
    });

    test('nine ratio rows, all using ASCII hyphen-minus (no em dash)', () {
      expect(DbReferenceScreen.dbRatios.length, 9);
      for (final DbRatio r in DbReferenceScreen.dbRatios) {
        expect(r.db.contains('—'), isFalse, reason: 'no em dash');
        expect(r.db.contains('−'), isFalse, reason: 'no Unicode minus');
      }
    });
  });

  group('dBm reference points — match PWA app.js DBM_REFS', () {
    DbmRef refFor(String dbm) =>
        DbReferenceScreen.dbmRefs.firstWhere((DbmRef r) => r.dbm == dbm);

    test('0 dBm = 1 mW (the reference point)', () {
      expect(refFor('0 dBm').power, '1 mW');
    });

    test('+30 dBm = 1,000 mW (FCC 2.4 GHz conducted max)', () {
      expect(refFor('+30 dBm').power, '1,000 mW');
    });

    test('+20 dBm = 100 mW (common default AP Tx power)', () {
      expect(refFor('+20 dBm').power, '100 mW');
    });

    test('-70 dBm = 0.1 nW (minimum for enterprise data)', () {
      expect(refFor('-70 dBm').power, '0.1 nW');
    });

    test('thirteen dBm rows, all using ASCII hyphen-minus', () {
      expect(DbReferenceScreen.dbmRefs.length, 13);
      for (final DbmRef r in DbReferenceScreen.dbmRefs) {
        expect(r.dbm.contains('—'), isFalse, reason: 'no em dash');
        expect(r.dbm.contains('−'), isFalse, reason: 'no Unicode minus');
      }
    });
  });

  group('DbReferenceScreen widget', () {
    testWidgets('renders title and both table headings in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DbReferenceScreen(),
          ),
        );

        expect(find.text('dB Reference'), findsWidgets);
        expect(find.text('dB Power Ratios'), findsOneWidget);
        expect(find.text('Common dBm Reference Points'), findsOneWidget);
        // Anchor rows render their load-bearing values. '2x' legitimately
        // appears twice — as the +3 dB power ratio and the +6 dB voltage ratio
        // — so scope the assertion to the +3 dB row to prove the double-power
        // anchor renders in the power column specifically, not just somewhere.
        expect(find.text('2x'), findsNWidgets(2));
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('+3 dB'),
              matching: find.byType(Row),
            ),
            matching: find.text('2x'),
          ),
          findsOneWidget,
        );
        expect(find.text('1 mW'), findsOneWidget);
        // Read-only reference: no inputs.
        expect(find.byType(TextField), findsNothing);
      });
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
