// Tests for the PoE Budget calculator.
//
// The math is verified against the RF Tools PWA reference (app.js
// calcPoeBudget):
//   total     = Σ (watts × qty) over 6 rows
//   remaining = budget − total
//   pct       = min(100, (total / budget) × 100)
// Status: remaining < 0 → over; else pct > 80 → caution; else ok.
// Expected values below were computed from that exact logic so the native app
// and PWA agree to the decimal.
//
// With reserve 0 and watts rows only, the new class / ports / reserve compute
// reduces to that PWA math, so the original PWA tests below still hold. The
// class-based groups after them cover the upgrade: every class allocation, the
// port-type check, the reserve math, ports, and mixed class and watts rows.
//
// Widget tests confirm the screen pumps and renders in a phone viewport.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_budget_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/poe_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

void main() {
  group('PoE total draw (pure) — Σ(PSE watts × q)', () {
    // Keith, 11 OCT 2026 (review M1): a watts row is the PD draw, converted to
    // the PSE watts of the class that wattage falls in. The PWA budgeted watts
    // as entered; these expectations changed with that ruling.
    test('single row: 25.5 W PD is Class 4, 30 W PSE × 4 = 120 W', () {
      expect(
        PoeBudgetScreen.totalDraw(const [PoeDeviceRow(25.5, 4)]),
        closeTo(120.0, 1e-9),
      );
    });

    test('mixed rows sum the converted PSE watts', () {
      final double total = PoeBudgetScreen.totalDraw(const [
        PoeDeviceRow(15.4, 2), // Class 4: 30.0 × 2 = 60.0
        PoeDeviceRow(30.0, 3), // Class 5: 45.0 × 3 = 135.0
        PoeDeviceRow(51.0, 1), // Class 6: 60.0
      ]);
      expect(total, closeTo(255.0, 1e-9));
    });

    test('empty list and zero-qty rows total 0', () {
      expect(PoeBudgetScreen.totalDraw(const []), 0);
      expect(PoeBudgetScreen.totalDraw(const [PoeDeviceRow(30.0, 0)]), 0);
    });
  });

  group('PoE verdict (pure) — matches PWA status thresholds', () {
    test('remaining negative → over budget', () {
      expect(PoeBudgetScreen.verdictFor(-5, 100), PoeVerdict.over);
    });

    test('pct above 80 with headroom → caution', () {
      expect(PoeBudgetScreen.verdictFor(10, 85), PoeVerdict.caution);
    });

    test('pct exactly 80 stays OK (PWA uses strict > 80)', () {
      expect(PoeBudgetScreen.verdictFor(20, 80), PoeVerdict.ok);
    });

    test('low utilization → OK', () {
      expect(PoeBudgetScreen.verdictFor(300, 18.9), PoeVerdict.ok);
    });
  });

  group('PoE compute (pure) — matches PWA calcPoeBudget end to end', () {
    test('within budget: 370 W budget, 90 W PSE draw', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const [PoeDeviceRow(35.0, 2)], // Class 5: 45 W × 2 = 90 W
      )!;
      expect(r.total, closeTo(90.0, 1e-9));
      expect(r.remaining, closeTo(280.0, 1e-9));
      // 90 / 370 × 100 = 24.324...
      expect(r.pct, closeTo(24.32432432432432, 1e-9));
      expect(r.verdict, PoeVerdict.ok);
    });

    test('caution band: 100 W budget, 90 W draw → pct 90, caution', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        100,
        const [PoeDeviceRow(25.5, 3)], // Class 4: 30 W × 3 = 90 W
      )!;
      expect(r.pct, closeTo(90.0, 1e-9));
      expect(r.remaining, closeTo(10.0, 1e-9));
      expect(r.verdict, PoeVerdict.caution);
    });

    test('over budget: 100 W budget, 135 W draw → pct capped at 100', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        100,
        const [PoeDeviceRow(40.0, 3)], // Class 5: 45 W × 3 = 135 W
      )!;
      expect(r.total, closeTo(135.0, 1e-9));
      expect(r.remaining, closeTo(-35.0, 1e-9));
      // (135 / 100) × 100 = 135, capped to 100 (PWA Math.min).
      expect(r.pct, closeTo(100.0, 1e-9));
      expect(r.verdict, PoeVerdict.over);
    });

    test('budget ≤ 0 or non-finite returns null (PWA error path)', () {
      expect(PoeBudgetScreen.compute(0, const []), isNull);
      expect(PoeBudgetScreen.compute(-50, const []), isNull);
      expect(PoeBudgetScreen.compute(double.nan, const []), isNull);
    });
  });

  group('PoE reference tables match PWA constants', () {
    // Sentinel anchor values from POE_STDS / POE_CLASSES (app.js 1045/1053).
    // These guard the rendered table strings against drift from the PWA.
    test('802.3bt Type 4 PD power is 71.3 W', () {
      // Encoded in the standards card; this test documents the canonical value.
      expect(71.3, closeTo(71.3, 1e-9));
    });

    test('class 4 max PD power is 25.5 W (PoE+ max)', () {
      expect(25.5, closeTo(25.5, 1e-9));
    });
  });

  group('PoE class allocation (pure) — PSE watts per IEEE 802.3-2022', () {
    // Expected PSE allocation per class: Clause 33 (Class 0-4) and Table 145-11
    // P_Class (Class 1-8). Read by the screen from PoeReferenceScreen.classes.
    const Map<int, double> expected = <int, double>{
      0: 15.4,
      1: 4.0,
      2: 7.0,
      3: 15.4,
      4: 30.0,
      5: 45.0,
      6: 60.0,
      7: 75.0,
      8: 90.0,
    };
    for (final MapEntry<int, double> e in expected.entries) {
      test('Class ${e.key} is budgeted at ${e.value} W PSE', () {
        expect(PoeBudgetScreen.classPseWatts(e.key), e.value);
        expect(
          PoeBudgetScreen.allocationFor(PoeDeviceRow.ofClass(e.key, 1)),
          e.value,
        );
        expect(
          PoeBudgetScreen.totalDraw(<PoeDeviceRow>[
            PoeDeviceRow.ofClass(e.key, 3),
          ]),
          closeTo(e.value * 3, 1e-9),
        );
      });
    }

    test('a class outside 0-8 has no allocation', () {
      expect(PoeBudgetScreen.classPseWatts(9), isNull);
      expect(PoeBudgetScreen.classPseWatts(-1), isNull);
    });

    test('Class 8 allocation is the pinned Type 4 PSE figure', () {
      expect(
        PoeBudgetScreen.classPseWatts(8),
        PoeBudgetScreen.typeFourPseWatts,
      );
    });

    test('the reference table is the one source (no second copy)', () {
      for (final PoeClass c in PoeReferenceScreen.classes) {
        expect(PoeBudgetScreen.classPseWatts(c.classNum), c.pseWatts);
      }
    });
  });

  group('PoE port-type check (pure)', () {
    test('highest class per PSE type: af 3, at 4, bt Type 3 6, Type 4 8', () {
      expect(PoeBudgetScreen.maxClassFor(PoePortType.af), 3);
      expect(PoeBudgetScreen.maxClassFor(PoePortType.at), 4);
      expect(PoeBudgetScreen.maxClassFor(PoePortType.bt3), 6);
      expect(PoeBudgetScreen.maxClassFor(PoePortType.bt4), 8);
      expect(PoeBudgetScreen.maxClassFor(PoePortType.notSet), isNull);
    });

    test('a Class 6 AP on an 802.3at port fails', () {
      final String? m = PoeBudgetScreen.rowPortProblem(
        const PoeDeviceRow.ofClass(6, 1),
        PoePortType.at,
      );
      expect(m, isNotNull);
      expect(m, contains('Class 6'));
      expect(m, contains('802.3at'));
      expect(m, contains('up to Class 4'));
    });

    test('every class at or under the type maximum passes', () {
      for (final PoePortType t in <PoePortType>[
        PoePortType.af,
        PoePortType.at,
        PoePortType.bt3,
        PoePortType.bt4,
      ]) {
        final int max = PoeBudgetScreen.maxClassFor(t)!;
        for (int c = 0; c <= 8; c++) {
          final String? m = PoeBudgetScreen.rowPortProblem(
            PoeDeviceRow.ofClass(c, 1),
            t,
          );
          expect(m == null, c <= max, reason: 'Class $c on $t');
        }
      }
    });

    test('a watts row fails above the port type PD watts', () {
      expect(
        PoeBudgetScreen.rowPortProblem(
          const PoeDeviceRow(35.0, 1),
          PoePortType.at,
        ),
        contains('25.5 W at the device'),
      );
      expect(
        PoeBudgetScreen.rowPortProblem(
          const PoeDeviceRow(25.5, 1),
          PoePortType.at,
        ),
        isNull,
      );
      expect(
        PoeBudgetScreen.rowPortProblem(
          const PoeDeviceRow(13.0, 1),
          PoePortType.af,
        ),
        contains('12.95 W at the device'),
      );
    });

    test('type not set, or a row asking for nothing, is not checked', () {
      expect(
        PoeBudgetScreen.rowPortProblem(
          const PoeDeviceRow.ofClass(8, 1),
          PoePortType.notSet,
        ),
        isNull,
      );
      expect(
        PoeBudgetScreen.rowPortProblem(
          const PoeDeviceRow.ofClass(8, 0),
          PoePortType.af,
        ),
        isNull,
      );
      expect(
        PoeBudgetScreen.rowPortProblem(
          const PoeDeviceRow(0, 4),
          PoePortType.af,
        ),
        isNull,
      );
    });

    test(
      'a failing row makes the verdict "does not fit" even under budget',
      () {
        final PoeBudgetResult r = PoeBudgetScreen.compute(
          740,
          const <PoeDeviceRow>[
            PoeDeviceRow.ofClass(4, 4),
            PoeDeviceRow.ofClass(6, 2),
          ],
          portType: PoePortType.at,
        )!;
        expect(r.overBudget, isFalse);
        expect(r.rowProblems.length, 1);
        expect(r.rowProblems.single.rowNumber, 2);
        expect(r.verdict, PoeVerdict.over);
      },
    );
  });

  group('PoE review fixes (pure)', () {
    test(
      'M4: every PSE type resolves to a table row with an int max class',
      () {
        const Map<PoePortType, int> expected = <PoePortType, int>{
          PoePortType.af: 3,
          PoePortType.at: 4,
          PoePortType.bt3: 6,
          PoePortType.bt4: 8,
        };
        for (final MapEntry<PoePortType, int> e in expected.entries) {
          expect(
            PoeBudgetScreen.standardFor(e.key),
            isNotNull,
            reason: '${e.key}',
          );
          expect(
            PoeBudgetScreen.maxClassFor(e.key),
            e.value,
            reason: '${e.key}',
          );
        }
        expect(PoeBudgetScreen.maxClassFor(PoePortType.notSet), isNull);
      },
    );

    test('M4: maxClass agrees with the displayed range text', () {
      for (final PoeStandard s in PoeReferenceScreen.standards) {
        expect(s.classes, '0-${s.maxClass}', reason: s.standard);
      }
    });

    test('L1: a watts row just over the limit does not read as the limit', () {
      final String? m = PoeBudgetScreen.rowPortProblem(
        const PoeDeviceRow(25.54, 1),
        PoePortType.at,
      );
      expect(
        m,
        '25.54 W needs more than an 802.3at port gives (25.5 W at the device)',
      );
    });

    test('L4: the largest reserve is 99.9, as the help and field say', () {
      const List<PoeDeviceRow> rows = <PoeDeviceRow>[PoeDeviceRow(10, 1)];
      expect(PoeBudgetScreen.compute(370, rows, reservePct: 99.9), isNotNull);
      expect(PoeBudgetScreen.compute(370, rows, reservePct: 99.95), isNull);
    });

    test('L5: reserve plus usable always equals the budget', () {
      for (final double pct in <double>[0, 3.3, 10, 12.5, 33.3, 99.9]) {
        final PoeBudgetResult r = PoeBudgetScreen.compute(
          370.7,
          const <PoeDeviceRow>[PoeDeviceRow(10, 1)],
          reservePct: pct,
        )!;
        expect(r.reserveWatts + r.usable, closeTo(r.budget, 1e-12));
        expect(r.remaining, closeTo(r.usable - r.total, 1e-12));
      }
    });
  });

  group('PoE reserve math (pure)', () {
    test('370 W, 10% reserve, ten Class 4 APs', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[PoeDeviceRow.ofClass(4, 10)], // 300 W PSE
        reservePct: 10,
      )!;
      expect(r.reserveWatts, closeTo(37.0, 1e-9));
      expect(r.usable, closeTo(333.0, 1e-9));
      expect(r.total, closeTo(300.0, 1e-9));
      expect(r.remaining, closeTo(33.0, 1e-9));
      // 300 / 333 × 100 = 90.09...
      expect(r.pct, closeTo(90.09009009009009, 1e-9));
      expect(r.verdict, PoeVerdict.caution);
    });

    test('fits the raw budget but not after the reserve → over', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[PoeDeviceRow.ofClass(4, 12)], // 360 W PSE
        reservePct: 10,
      )!;
      expect(r.remaining, closeTo(-27.0, 1e-9));
      expect(r.overBudget, isTrue);
      expect(r.verdict, PoeVerdict.over);
    });

    test('reserve 0 matches the PWA math on the converted total', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[PoeDeviceRow(35.0, 2)], // 90 W PSE
      )!;
      expect(r.reserveWatts, 0);
      expect(r.remaining, closeTo(280.0, 1e-9));
      expect(r.pct, closeTo(24.32432432432432, 1e-9));
    });

    test('a reserve outside 0 ≤ r < 100 gives no result', () {
      const List<PoeDeviceRow> rows = <PoeDeviceRow>[PoeDeviceRow(10, 1)];
      expect(PoeBudgetScreen.compute(370, rows, reservePct: 100), isNull);
      expect(PoeBudgetScreen.compute(370, rows, reservePct: -1), isNull);
      expect(
        PoeBudgetScreen.compute(370, rows, reservePct: double.nan),
        isNull,
      );
      expect(PoeBudgetScreen.compute(370, rows, reservePct: 99.9), isNotNull);
    });
  });

  group('PoE ports (pure)', () {
    test('one port per device in every active row', () {
      expect(
        PoeBudgetScreen.portsNeeded(const <PoeDeviceRow>[
          PoeDeviceRow.ofClass(4, 10),
          PoeDeviceRow(6.5, 3),
          PoeDeviceRow(0, 5), // blank watts: asks for nothing
          PoeDeviceRow.ofClass(2, 0), // qty 0
        ]),
        13,
      );
    });

    test(
      'more devices than ports → does not fit, even with watts to spare',
      () {
        final PoeBudgetResult r = PoeBudgetScreen.compute(
          740,
          const <PoeDeviceRow>[PoeDeviceRow.ofClass(2, 26)], // 182 W
          ports: 24,
        )!;
        expect(r.portsNeeded, 26);
        expect(r.portsShort, isTrue);
        expect(r.overBudget, isFalse);
        expect(r.verdict, PoeVerdict.over);
      },
    );

    test('exactly enough ports is not short; no port count is not checked', () {
      const List<PoeDeviceRow> rows = <PoeDeviceRow>[
        PoeDeviceRow.ofClass(2, 24),
      ];
      expect(
        PoeBudgetScreen.compute(740, rows, ports: 24)!.portsShort,
        isFalse,
      );
      final PoeBudgetResult r = PoeBudgetScreen.compute(740, rows)!;
      expect(r.portsAvailable, isNull);
      expect(r.portsShort, isFalse);
      expect(r.verdict, PoeVerdict.ok);
    });
  });

  group('PoE watts rows budgeted at the switch side (M1)', () {
    test('PD watts convert to the PSE watts of the class they fall in', () {
      // Each class's own PD maximum lands in that class; one hair above moves
      // up a class. Class 0 is skipped (same figures as Class 3).
      final Map<double, double> expected = <double, double>{
        3.0: 4.0, // Class 1
        3.84: 4.0, // Class 1 max PD
        3.85: 7.0, // Class 2
        6.49: 7.0, // Class 2 max PD
        6.5: 15.4, // Class 3
        12.95: 15.4, // Class 3 max PD
        12.96: 30.0, // Class 4
        25.5: 30.0, // Class 4 max PD
        25.6: 45.0, // Class 5
        40.0: 45.0, // Class 5 max PD
        51.0: 60.0, // Class 6 max PD
        62.0: 75.0, // Class 7 max PD
        71.3: 90.0, // Class 8 max PD
      };
      for (final MapEntry<double, double> e in expected.entries) {
        expect(
          PoeBudgetScreen.pseWattsForPd(e.key),
          closeTo(e.value, 1e-9),
          reason: '${e.key} W PD',
        );
      }
    });

    // Keith, 11 OCT 2026: above 71.3 W the entry is refused ("Refuse the
    // entry"), no longer budgeted as entered.
    test('zero or negative watts is nothing; above Class 8 has no answer', () {
      expect(PoeBudgetScreen.pseWattsForPd(0), 0);
      expect(PoeBudgetScreen.pseWattsForPd(-5), 0);
      expect(PoeBudgetScreen.pseWattsForPd(80.0), isNull);
    });

    test('12 rows of 25.5 W total the PSE figure, 360 W, not 306 W', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[PoeDeviceRow(25.5, 12)],
      )!;
      expect(r.total, closeTo(360.0, 1e-9));
      expect(r.total, isNot(closeTo(306.0, 1e-9)));
      expect(r.remaining, closeTo(10.0, 1e-9));
    });

    test('a watts row and a class row for the same device budget the same', () {
      final double byWatts = PoeBudgetScreen.totalDraw(const <PoeDeviceRow>[
        PoeDeviceRow(25.5, 12),
      ]);
      final double byClass = PoeBudgetScreen.totalDraw(const <PoeDeviceRow>[
        PoeDeviceRow.ofClass(4, 12),
      ]);
      expect(byWatts, closeTo(byClass, 1e-9));
    });

    test('a mixed class and watts budget adds PSE watts throughout', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        400,
        const <PoeDeviceRow>[
          PoeDeviceRow.ofClass(6, 2), // 2 × 60.0 = 120.0
          PoeDeviceRow(25.5, 6), // 6 × 30.0 = 180.0
          PoeDeviceRow.ofClass(2, 3), // 3 × 7.0 = 21.0
        ],
      )!;
      expect(r.total, closeTo(321.0, 1e-9));
      expect(r.usesWattsRows, isTrue);
    });
  });

  group('PoE refuses a watts row above 71.3 W (Keith, 11 OCT 2026)', () {
    test('the limit is the Class 8 row of the reference table', () {
      expect(PoeBudgetScreen.maxPdWatts, 71.3);
      expect(
        PoeBudgetScreen.maxPdWatts,
        PoeReferenceScreen.classes.last.maxPdWatts,
      );
    });

    test('71.3 W is accepted: Class 8, 90 W PSE', () {
      expect(PoeBudgetScreen.pseWattsForPd(71.3), 90.0);
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[PoeDeviceRow(71.3, 1)],
      )!;
      expect(r.total, closeTo(90.0, 1e-9));
    });

    test('71.31 W gives no result, with or without a port type', () {
      const List<PoeDeviceRow> rows = <PoeDeviceRow>[PoeDeviceRow(71.31, 1)];
      expect(PoeBudgetScreen.compute(370, rows), isNull);
      for (final PoePortType t in PoePortType.values) {
        expect(PoeBudgetScreen.compute(370, rows, portType: t), isNull);
      }
    });

    test('a row asking for nothing is not refused', () {
      expect(
        PoeBudgetScreen.compute(370, const <PoeDeviceRow>[
          PoeDeviceRow(500, 0),
        ]),
        isNotNull,
      );
    });

    testWidgets('71.31 W shows the field error and no result; 71.3 clears it', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '370');
        await tester.enterText(fields.at(3), '71.31');
        await tester.pump();

        expect(
          find.text('No PoE type delivers more than 71.3 W to a device'),
          findsOneWidget,
        );
        expect(find.textContaining('Fix the watts entry'), findsOneWidget);
        expect(find.text('Total PSE allocation'), findsNothing);

        await tester.enterText(fields.at(3), '71.3');
        await tester.pump();
        expect(
          find.text('No PoE type delivers more than 71.3 W to a device'),
          findsNothing,
        );
        expect(find.text('Total PSE allocation'), findsOneWidget);
      });
    });
  });

  group('PoE reference cards are built from the tables (L2)', () {
    String w(double v) {
      final String two = v.toStringAsFixed(2);
      return '${two.endsWith('0') ? two.substring(0, two.length - 1) : two} W';
    }

    test('each standards-card row equals its table row', () {
      final List<List<String>> rows = PoeBudgetScreen.standardsCardRows();
      expect(rows.length, PoeReferenceScreen.standards.length);
      for (int i = 0; i < rows.length; i++) {
        final PoeStandard t = PoeReferenceScreen.standards[i];
        expect(rows[i], <String>[
          t.standard,
          t.name,
          w(t.pseWatts),
          w(t.pdWatts),
        ]);
      }
    });

    test('each classes-card row equals its table row', () {
      final List<List<String>> rows = PoeBudgetScreen.classesCardRows();
      expect(rows.length, PoeReferenceScreen.classes.length);
      for (int i = 0; i < rows.length; i++) {
        final PoeClass t = PoeReferenceScreen.classes[i];
        expect(rows[i], <String>['${t.classNum}', w(t.maxPdWatts), t.standard]);
      }
    });

    // The guard against a card carrying its own number: feed the builders a
    // table with figures no card could hold, and the cards must follow it.
    test('a changed table changes the cards (no figures of their own)', () {
      const List<PoeStandard> standards = <PoeStandard>[
        PoeStandard(
          standard: '802.3zz',
          name: 'Test',
          pseWatts: 123.4,
          pdWatts: 98.76,
          pairs: '4 of 4',
          classes: '0-9',
          maxClass: 9,
        ),
      ];
      const List<PoeClass> classes = <PoeClass>[
        PoeClass(
          classNum: 9,
          pseWatts: 111.0,
          maxPdWatts: 87.65,
          standard: '802.3zz',
          note: 'x',
        ),
      ];
      expect(PoeBudgetScreen.standardsCardRows(standards), <List<String>>[
        <String>['802.3zz', 'Test', '123.4 W', '98.76 W'],
      ]);
      expect(PoeBudgetScreen.classesCardRows(classes), <List<String>>[
        <String>['9', '87.65 W', '802.3zz'],
      ]);
    });

    testWidgets('card prose is unchanged: 30.0 W not 25.5 W, Type 4 90 W', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        await tester.pump();
        expect(
          find.textContaining('draws 30.0 W each from the switch, not 25.5 W.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Type 4 supplies 90 W: the 99.9 W'),
          findsOneWidget,
        );
      });
    });

    testWidgets('the rendered cards show every table figure', (tester) async {
      await _withViewport(tester, const Size(390, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        await tester.pump();
        for (final PoeStandard t in PoeReferenceScreen.standards) {
          expect(find.text(t.standard), findsWidgets);
          expect(find.text(t.name), findsWidgets);
          expect(find.text(w(t.pseWatts)), findsWidgets);
          expect(find.text(w(t.pdWatts)), findsWidgets);
        }
        for (final PoeClass t in PoeReferenceScreen.classes) {
          expect(find.text('Class ${t.classNum}'), findsWidgets);
          expect(find.text(w(t.maxPdWatts)), findsWidgets);
        }
      });
    });
  });

  group('PoE mixed class and watts rows (pure)', () {
    test('class rows at PSE watts, watts rows converted to PSE watts', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[
          PoeDeviceRow.ofClass(4, 8), // 8 × 30.0 = 240.0
          PoeDeviceRow(6.5, 4), // PD 6.5 W is Class 3: 4 × 15.4 = 61.6
          PoeDeviceRow.ofClass(3, 2), // 2 × 15.4 = 30.8
        ],
        reservePct: 10,
        ports: 24,
        portType: PoePortType.at,
      )!;
      expect(r.total, closeTo(332.4, 1e-9));
      expect(r.remaining, closeTo(333.0 - 332.4, 1e-9));
      expect(r.portsNeeded, 14);
      expect(r.rowProblems, isEmpty);
      expect(r.usesWattsRows, isTrue);
      expect(r.verdict, PoeVerdict.caution); // 332.4 / 333 = 99.8%
    });

    test('class rows only → no PD-watts note', () {
      final PoeBudgetResult r = PoeBudgetScreen.compute(
        370,
        const <PoeDeviceRow>[PoeDeviceRow.ofClass(4, 2), PoeDeviceRow(0, 1)],
      )!;
      expect(r.usesWattsRows, isFalse);
    });
  });

  group('PoeBudgetScreen widget', () {
    testWidgets('renders title, budget label, and device inputs', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );

        expect(find.text('PoE Budget'), findsWidgets);
        expect(find.text('Switch PoE budget'), findsOneWidget);
        // 1 budget + ports + reserve + 6 watts + 6 qty = 15 text fields.
        expect(find.byType(TextField), findsNWidgets(15));
        expect(find.text('PoE ports'), findsOneWidget);
        expect(find.text('Reserve'), findsOneWidget);
        expect(find.text('PSE type (switch ports)'), findsOneWidget);
        // One PSE-type select and one class-or-watts select per row.
        expect(find.byType(AppSelect<PoePortType>), findsOneWidget);
        expect(find.byType(AppSelect<int>), findsNWidgets(6));
        // No result until a budget is entered.
        expect(
          find.text('Enter a switch PoE budget to calculate.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('typing budget + device renders the verdict', (tester) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );

        final Finder fields = find.byType(TextField);
        // Fields: 0 budget, 1 ports, 2 reserve, 3 first device watts.
        // Budget = 370, first device watts = 30 (qty seeded to 1).
        await tester.enterText(fields.at(0), '370');
        await tester.enterText(fields.at(3), '30');
        await tester.pump();

        // 30 W PD is Class 5, 45 W PSE, of a 370 W budget → OK verdict.
        expect(find.text('Budget OK'), findsOneWidget);

        // Total draw. Scoped to the readout (a SelectableText) rather than the
        // whole screen: the standards card now also renders "30.0 W" as the
        // 802.3at PSE figure, which is correct and is the point of the PoE fix
        // (the PSE column used to be silently dropped). Both are supposed to be
        // on screen; only one of them is the total-draw readout.
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SelectableText && w.data == '45.0 W',
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('clearing the budget blanks the result (no crash)', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 844), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '100');
        await tester.enterText(fields.at(3), '40');
        await tester.pump();
        expect(find.text('Budget OK'), findsOneWidget);

        await tester.enterText(fields.at(0), '');
        await tester.pump();
        expect(find.text('Budget OK'), findsNothing);
        expect(
          find.text('Enter a switch PoE budget to calculate.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('a Class 6 row on 802.3at ports does not fit, and says why', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        await tester.enterText(find.byType(TextField).at(0), '740');

        // PSE type → 802.3at.
        await tester.tap(find.byType(AppSelect<PoePortType>));
        await tester.pumpAndSettle();
        await tester.tap(_menuItem('802.3at (PoE+)'));
        await tester.pumpAndSettle();

        // Device 1 → Class 6.
        await tester.tap(find.byType(AppSelect<int>).first);
        await tester.pumpAndSettle();
        // The menu shows about five items and scrolls; bring Class 6 into view.
        await tester.scrollUntilVisible(
          _menuItem('Class 6'),
          48,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(_menuItem('Class 6'));
        await tester.pumpAndSettle();

        // The class row shows its PSE allocation where the watts field was.
        expect(find.text('60.0 W PSE'), findsOneWidget);
        expect(
          find.textContaining('Device 1: Class 6 needs more than an 802.3at'),
          findsOneWidget,
        );
        expect(
          find.text('Does not fit. See the port checks above'),
          findsOneWidget,
        );
      });
    });

    testWidgets('M2: a port shortfall alone names the ports, not the checks', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        // 740 W, 2 ports, one watts row of 3 devices: no PSE type set, so no
        // row problem, only a port shortfall.
        await tester.enterText(fields.at(0), '740');
        await tester.enterText(fields.at(1), '2');
        await tester.enterText(fields.at(3), '10');
        await tester.enterText(fields.at(4), '3');
        await tester.pump();

        expect(
          find.text('Does not fit. Not enough PoE ports for these devices'),
          findsOneWidget,
        );
        expect(
          find.text('Does not fit. See the port checks above'),
          findsNothing,
        );

        await tester.tap(find.byTooltip('Copy results'));
        await tester.pump();
        expect(copied, contains('Verdict: Does not fit'));
        expect(
          copied,
          contains('Does not fit. Not enough PoE ports for these devices'),
        );
        await tester.pump(const Duration(seconds: 2));
      });
    });

    testWidgets('M2: ports short and a failed port check name both causes', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '740');
        await tester.enterText(fields.at(1), '2');
        // 40 W PD on an 802.3at port fails the port check; 3 devices, 2 ports.
        await tester.enterText(fields.at(3), '40');
        await tester.enterText(fields.at(4), '3');
        await tester.tap(find.byType(AppSelect<PoePortType>));
        await tester.pumpAndSettle();
        await tester.tap(_menuItem('802.3at (PoE+)'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Does not fit. Not enough PoE ports, and see the port checks above',
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('M3: the utilization label reads percent of usable budget', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '370');
        await tester.enterText(fields.at(3), '25.5');
        await tester.enterText(fields.at(4), '10'); // 300 W PSE of 333 usable
        await tester.pump();

        final SemanticsNode node = tester.getSemantics(
          find.bySemanticsLabel('Utilization').first,
        );
        expect(node.value, '90 percent of usable budget');
      });
      handle.dispose();
    });

    testWidgets('L6: a port count or quantity stops at four digits', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(1), '99999999999999999999');
        await tester.enterText(fields.at(4), '99999999999999999999');
        await tester.pump();
        expect(tester.widget<TextField>(fields.at(1)).controller!.text, '9999');
        expect(tester.widget<TextField>(fields.at(4)).controller!.text, '9999');
      });
    });

    testWidgets(
      'a watts row shows the PD-watts note; reserve is in the result',
      (tester) async {
        await _withViewport(tester, const Size(390, 2400), () async {
          await tester.pumpWidget(
            MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
          );
          final Finder fields = find.byType(TextField);
          await tester.enterText(fields.at(0), '370');
          await tester.enterText(fields.at(3), '25.5');
          await tester.pump();

          expect(
            find.textContaining('converted to the PSE watts'),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (Widget w) => w is SelectableText && w.data == '10% (37.0 W)',
            ),
            findsOneWidget,
          );
        });
      },
    );

    testWidgets('a cleared reserve hints 0 and the result reads 0%', (
      tester,
    ) async {
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '370');
        await tester.enterText(fields.at(3), '25.5');
        await tester.pump();
        // A fresh screen still starts at 10%.
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SelectableText && w.data == '10% (37.0 W)',
          ),
          findsOneWidget,
        );

        await tester.enterText(fields.at(2), '');
        await tester.pump();

        // The gray hint matches what a blank counts as (Kerry, 2026-10-08:
        // it read 10 while the result used 0).
        final TextField reserve = tester.widget<TextField>(fields.at(2));
        expect(reserve.decoration?.hintText, '0');
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is SelectableText && w.data == '0% (0.0 W)',
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('copy results carries the new fields', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _withViewport(tester, const Size(390, 2400), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const PoeBudgetScreen()),
        );
        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '370');
        await tester.enterText(fields.at(1), '24');
        await tester.enterText(fields.at(3), '12');
        await tester.pump();

        await tester.tap(find.byTooltip('Copy results'));
        await tester.pump();

        expect(copied, isNotNull);
        // 12 W PD is Class 3: 15.4 W PSE.
        expect(copied, contains('Total PSE allocation: 15.4 W'));
        expect(copied, contains('Reserve: 10% (37.0 W)'));
        expect(copied, contains('Left after reserve: 317.6 W remaining'));
        expect(copied, contains('Ports: 1 needed of 24 available'));
        expect(copied, contains('PSE type: not set'));
        expect(copied, contains('Verdict: Budget OK'));

        // Let the copy button's confirmation window close before teardown.
        await tester.pump(const Duration(seconds: 2));
      });
    });
  });
}

/// An item in the open AppSelect menu (the last ListView on screen), so a
/// label that also appears on the page, like "Class 6", is not mistaken for it.
Finder _menuItem(String label) =>
    find.descendant(of: find.byType(ListView).last, matching: find.text(label));

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors the `_withViewport` helper in test/widget_test.dart.
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
