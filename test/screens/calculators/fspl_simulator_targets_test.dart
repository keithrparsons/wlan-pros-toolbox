// User-editable design targets in the FSPL Simulator (Keith, 2026-09-27):
// the model (edit, validate, add, remove, cap, reset), persistence through
// shared_preferences, the label layout for close values, and the rendering
// on the chart, in the legend, in the controls, on a phone and in presenter
// mode.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_chart.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_panels.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

List<String> _labels(FsplSimModel m) => <String>[
  for (final FsplRefLine r in m.refLines()) r.label,
];

Future<FsplSimModel> _loadedModel() async {
  final FsplTargetStore store = FsplTargetStore();
  await store.load();
  return FsplSimModel(store: store);
}

FsplChartPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((CustomPaint c) => c.painter)
    .whereType<FsplChartPainter>()
    .first;

Future<FsplSimModel> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  ThemeData? theme,
  UnitSystem units = UnitSystem.metric,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UnitSystemScope(
      controller: UnitSystemController(initial: units),
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: const FsplSimulatorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<FsplStage>(find.byType(FsplStage).first).model;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FsplTargetStore.resetForTest();
  });

  group('model', () {
    test('defaults are exactly -67 voice and -70 HD video', () async {
      final FsplSimModel m = await _loadedModel();
      expect(_labels(m), <String>['-67 dBm voice', '-70 dBm HD video']);
      expect(m.targetsAreDefault, isTrue);
      expect(m.resetTargetsLabel, 'Reset to -67 voice / -70 HD video');
      expect(m.canAddTarget, isTrue);
    });

    test('a value and a label edit the line', () async {
      final FsplSimModel m = await _loadedModel();
      final int id = m.targetRows.first.id;
      m
        ..setTargetValueText(id, '-72')
        ..setTargetLabel(id, 'data');
      expect(_labels(m), <String>['-72 dBm data', '-70 dBm HD video']);
      expect(m.targetsAreDefault, isFalse);
    });

    test('an empty label falls back to the value', () async {
      final FsplSimModel m = await _loadedModel();
      m.setTargetLabel(m.targetRows.first.id, '   ');
      expect(_labels(m).first, '-67 dBm');
    });

    test('out of range or not a number: error in the field, no line', () async {
      final FsplSimModel m = await _loadedModel();
      final int id = m.targetRows.first.id;
      for (final String bad in <String>['-101', '-29', '0', 'abc', '-']) {
        m.setTargetValueText(id, bad);
        expect(m.targetError(id), kFsplTargetError, reason: bad);
        expect(_labels(m), <String>['-70 dBm HD video'], reason: bad);
      }
      for (final String ok in <String>['-100', '-30']) {
        m.setTargetValueText(id, ok);
        expect(m.targetError(id), isNull, reason: ok);
      }
    });

    test('an empty value is waiting, not an error', () async {
      final FsplSimModel m = await _loadedModel();
      final int id = m.targetRows.first.id;
      m.setTargetValueText(id, '');
      expect(m.targetError(id), isNull);
      expect(m.targets, hasLength(1));
    });

    test(
      'a decimal value keeps one place; comma and Unicode minus parse',
      () async {
        final FsplSimModel m = await _loadedModel();
        final int id = m.targetRows.first.id;
        m.setTargetValueText(id, '−67,54');
        expect(m.targets.first.dbm, -67.5);
        expect(_labels(m).first, '-67.5 dBm voice');
      },
    );

    test('labels are clipped to the maximum length', () async {
      final FsplSimModel m = await _loadedModel();
      m.setTargetLabel(m.targetRows.first.id, 'x' * 40);
      expect(m.targetRows.first.label, hasLength(kFsplTargetLabelMax));
    });

    test('add up to the cap, remove, then reset', () async {
      final FsplSimModel m = await _loadedModel();
      final int? a = m.addTarget();
      final int? b = m.addTarget();
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(m.targetRows, hasLength(kFsplMaxTargets));
      expect(m.canAddTarget, isFalse);
      expect(m.addTarget(), isNull);
      // Empty new rows draw nothing until a value is typed.
      expect(m.targets, hasLength(2));
      m.setTargetValueText(a!, '-75');
      expect(_labels(m).last, '-75 dBm');

      m.removeTarget(m.targetRows.first.id);
      expect(m.targetRows, hasLength(3));
      expect(m.canAddTarget, isTrue);

      m.resetTargets();
      expect(_labels(m), <String>['-67 dBm voice', '-70 dBm HD video']);
      expect(m.targetsAreDefault, isTrue);
    });

    test('removing every line leaves no reference lines', () async {
      final FsplSimModel m = await _loadedModel();
      for (final FsplTargetRow r in m.targetRows) {
        m.removeTarget(r.id);
      }
      expect(m.refLines(), isEmpty);
      expect(m.targetsAreDefault, isFalse);
    });

    test('path loss view draws no targets', () async {
      final FsplSimModel m = await _loadedModel();
      m.setView(FsplView.pathLoss);
      expect(m.refLines(), isEmpty);
    });

    test('the y axis stretches to a far target', () async {
      final FsplSimModel m = await _loadedModel();
      m.setTargetValueText(m.targetRows.first.id, '-100');
      final ({double min, double max, double step}) yr = m.yRange(m.series());
      expect(yr.min, lessThanOrEqualTo(-100));
    });
  });

  group('persistence', () {
    test('an edit is saved and a fresh store loads it', () async {
      final FsplSimModel m = await _loadedModel();
      final int id = m.targetRows.first.id;
      m
        ..setTargetValueText(id, '-65')
        ..setTargetLabel(id, 'voice (strict)');
      await pumpEventQueue();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FsplTargetStore.prefsKey), isNotNull);

      final FsplSimModel next = await _loadedModel();
      expect(_labels(next), <String>[
        '-65 dBm voice (strict)',
        '-70 dBm HD video',
      ]);
    });

    test('an invalid row is not saved', () async {
      final FsplSimModel m = await _loadedModel();
      m.setTargetValueText(m.targetRows.first.id, '-5');
      await pumpEventQueue();
      final FsplSimModel next = await _loadedModel();
      expect(_labels(next), <String>['-70 dBm HD video']);
    });

    test('no lines is a saved choice, not a return to defaults', () async {
      final FsplSimModel m = await _loadedModel();
      for (final FsplTargetRow r in m.targetRows) {
        m.removeTarget(r.id);
      }
      await pumpEventQueue();
      final FsplSimModel next = await _loadedModel();
      expect(next.refLines(), isEmpty);
    });

    test('reset forgets the saved lines', () async {
      final FsplSimModel m = await _loadedModel();
      m.setTargetValueText(m.targetRows.first.id, '-60');
      await pumpEventQueue();
      m.resetTargets();
      await pumpEventQueue();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(FsplTargetStore.prefsKey), isFalse);
    });

    test('editing back to the defaults also forgets them', () async {
      final FsplSimModel m = await _loadedModel();
      final int id = m.targetRows.first.id;
      m.setTargetValueText(id, '-60');
      await pumpEventQueue();
      m.setTargetValueText(id, '-67');
      await pumpEventQueue();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(FsplTargetStore.prefsKey), isFalse);
    });

    test('garbage falls back to defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        FsplTargetStore.prefsKey: 'not json',
      });
      final FsplSimModel m = await _loadedModel();
      expect(m.targetsAreDefault, isTrue);
    });

    test('bad entries are dropped and at most four are kept', () {
      final List<FsplDesignTarget>? t = FsplTargetStore.decode(
        '[{"dbm":-67,"label":"a"},{"dbm":-200,"label":"b"},'
        '{"dbm":"x","label":"c"},{"dbm":-68,"label":"d"},'
        '{"dbm":-69,"label":"e"},{"dbm":-70,"label":"f"},'
        '{"dbm":-71,"label":"g"}]',
      );
      expect(t!.map((FsplDesignTarget x) => x.label), <String>[
        'a',
        'd',
        'e',
        'f',
      ]);
    });

    test('a model built before the load follows it, unless edited', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        FsplTargetStore.prefsKey: '[{"dbm":-75,"label":"data"}]',
      });
      final FsplSimModel a = FsplSimModel(store: FsplTargetStore());
      expect(_labels(a), <String>['-67 dBm voice', '-70 dBm HD video']);
      await pumpEventQueue();
      expect(_labels(a), <String>['-75 dBm data']);

      final FsplSimModel b = FsplSimModel(store: FsplTargetStore());
      b.setTargetLabel(b.targetRows.first.id, 'mine');
      await pumpEventQueue();
      expect(_labels(b).first, '-67 dBm mine');
    });
  });

  group('label layout', () {
    List<double> lay(List<double> ys, {double bottom = 300}) =>
        FsplChartPainter.layoutRefLabels(
          lineYs: ys,
          heights: List<double>.filled(ys.length, 15),
          top: 0,
          bottom: bottom,
        );

    void expectNoOverlap(List<double> tops) {
      final List<double> s = <double>[...tops]..sort();
      for (int i = 1; i < s.length; i++) {
        expect(s[i] - s[i - 1], greaterThanOrEqualTo(15), reason: '$tops');
      }
    }

    test('far-apart lines each get their label over the line', () {
      expect(lay(<double>[100, 200]), <double>[83, 183]);
    });

    test('the default pair on a normal chart: -67 over, -70 under', () {
      // 5 px per dB: -67 at 100, -70 at 115.
      final List<double> t = lay(<double>[100, 115]);
      expect(t[0], 83); // over -67
      expect(t[1], 117); // under -70
    });

    test('four lines 1 dB apart stack in order without overlap', () {
      final List<double> t = lay(<double>[100, 105, 110, 115]);
      expectNoOverlap(t);
      expect(t, orderedEquals(<double>[...t]..sort()));
    });

    test('two lines at the same value do not overlap', () {
      expectNoOverlap(lay(<double>[120, 120]));
    });

    test('a stack at the bottom edge is pushed back inside', () {
      final List<double> t = lay(<double>[290, 292, 294, 296], bottom: 300);
      expectNoOverlap(t);
      for (final double top in t) {
        expect(top + 15, lessThanOrEqualTo(300));
      }
    });

    test('input order is kept in the output', () {
      final List<double> t = lay(<double>[200, 100]);
      expect(t[0], greaterThan(t[1]));
    });
  });

  group('rendering', () {
    testWidgets(
      'defaults: two rows, Reset disabled, legend and chart labelled',
      (WidgetTester tester) async {
        await _pump(tester);
        expect(find.text('Design targets'), findsOneWidget);
        expect(find.byType(FsplTargetEditor), findsOneWidget);
        expect(
          find.text('Design targets: -67 dBm voice, -70 dBm HD video'),
          findsOneWidget,
        );
        expect(
          _painter(tester).refLines.map((FsplRefLine r) => r.label),
          <String>['-67 dBm voice', '-70 dBm HD video'],
        );
        final TextButton reset = tester.widget<TextButton>(
          find.ancestor(
            of: find.text('Reset to -67 voice / -70 HD video'),
            matching: find.byWidgetPredicate((Widget w) => w is TextButton),
          ),
        );
        expect(reset.onPressed, isNull);
      },
    );

    testWidgets('typing a label and value updates chart and legend', (
      WidgetTester tester,
    ) async {
      final FsplSimModel m = await _pump(tester);
      final int id = m.targetRows.first.id;
      await tester.enterText(
        find.byKey(ValueKey<String>('fspl-target-value-$id')),
        '-65',
      );
      await tester.enterText(
        find.byKey(ValueKey<String>('fspl-target-label-$id')),
        'Voice, strict',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Design targets: -65 dBm Voice, strict, -70 dBm HD video'),
        findsOneWidget,
      );
      expect(_painter(tester).refLines.first.label, '-65 dBm Voice, strict');

      await tester.ensureVisible(
        find.text('Reset to -67 voice / -70 HD video'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset to -67 voice / -70 HD video'));
      await tester.pumpAndSettle();
      expect(
        find.text('Design targets: -67 dBm voice, -70 dBm HD video'),
        findsOneWidget,
      );
      final EditableText value = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(
            ValueKey<String>('fspl-target-value-${m.targetRows.first.id}'),
          ),
          matching: find.byType(EditableText),
        ),
      );
      expect(value.controller.text, '-67');
    });

    testWidgets('an out-of-range value shows the error in the field', (
      WidgetTester tester,
    ) async {
      final FsplSimModel m = await _pump(tester);
      await tester.enterText(
        find.byKey(
          ValueKey<String>('fspl-target-value-${m.targetRows.first.id}'),
        ),
        '-20',
      );
      await tester.pumpAndSettle();
      expect(find.text(kFsplTargetError), findsOneWidget);
      expect(_painter(tester).refLines, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Add fills to four, then disables with a reason', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      for (int i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('Add line'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add line'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byTooltip('Remove design target 4'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove design target 4'), findsOneWidget);
      final TextButton add = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Add line'),
          matching: find.byWidgetPredicate((Widget w) => w is TextButton),
        ),
      );
      expect(add.onPressed, isNull);
      expect(find.textContaining('Up to 4 lines'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove design target 4'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove design target 4'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no lines: a note, and the legend drops the item', (
      WidgetTester tester,
    ) async {
      final FsplSimModel m = await _pump(tester);
      for (final FsplTargetRow r in m.targetRows) {
        m.removeTarget(r.id);
      }
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No design targets on the chart'),
        findsOneWidget,
      );
      expect(find.textContaining('Design targets:'), findsNothing);
      expect(find.textContaining('Design target:'), findsNothing);
    });

    testWidgets('a saved pick shows on open, in imperial and on linear too', (
      WidgetTester tester,
    ) async {
      await FsplTargetStore.instance.save(const <FsplDesignTarget>[
        FsplDesignTarget(-67, 'voice'),
        FsplDesignTarget(-68, 'video'),
      ]);
      final FsplSimModel m = await _pump(tester, units: UnitSystem.imperial);
      expect(m.units, UnitSystem.imperial);
      m.setLogScale(false);
      await tester.pumpAndSettle();
      expect(
        _painter(tester).refLines.map((FsplRefLine r) => r.label),
        <String>['-67 dBm voice', '-68 dBm video'],
      );
      expect(tester.takeException(), isNull);
    });

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      testWidgets('$name phone 390x844: four lines with long labels fit', (
        WidgetTester tester,
      ) async {
        final FsplSimModel m = await _pump(
          tester,
          size: const Size(390, 844),
          theme: theme(),
        );
        m
          ..addTarget()
          ..addTarget();
        final List<FsplTargetRow> rows = m.targetRows;
        for (int i = 0; i < rows.length; i++) {
          m
            ..setTargetValueText(rows[i].id, '${-67 - i}')
            ..setTargetLabel(rows[i].id, 'a long label here $i');
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Show controls'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Add line'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Remove design target 4'), findsOneWidget);
      });
    }

    testWidgets('presenter: a Design targets fold, and four lines still fit', (
      WidgetTester tester,
    ) async {
      setWindow(tester, const Size(1440, 900));
      installFakeWindow();
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark(), home: const FsplSimulatorScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      expect(find.byType(PresenterLayout), findsOneWidget);
      final FsplSimModel m = tester
          .widget<FsplStage>(find.byType(FsplStage).last)
          .model;
      m
        ..addTarget()
        ..addTarget();
      final List<FsplTargetRow> rows = m.targetRows;
      for (int i = 0; i < rows.length; i++) {
        m.setTargetValueText(rows[i].id, '${-67 - i}');
      }
      // Folded, the panel still fits with no scroll.
      expect(controlsOverflow(tester), 0);
      // Open, four lines scroll the panel like the Channels fold does; the
      // last row and the Add / Reset actions stay reachable.
      await tester.tap(find.text('Design targets'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add line'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove design target 4'), findsOneWidget);
      expectOnScreen(tester, find.text('Add line'), const Size(1440, 900));
      expect(tester.takeException(), isNull);
    });
  });
}
