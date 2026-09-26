// Widget tests for the Wi-Fi Classroom "Predict, Then Measure" screen
// (spec 32).
//
// The math is pinned in test/services/wifi_lab/predict_measure_engine_test
// .dart; these cover the screen contract: catalog, route and icon; the empty
// state (no walk, every wall untested, white maps); the preset walks; a drag
// on the floor drawing a leg; update model; the reveal and the Truth map; the
// stage and controls as separate widgets; the copy text; the help entry
// (illustrative wall losses, acronyms spelled out first, Present and its
// keys); the keywords; no string naming a vendor or product; and phone and
// desktop widths in both themes laying out with no exception.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/predict_measure_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/predict_measure_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<PredictMeasureController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1024,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final PredictMeasureController c = PredictMeasureController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: PredictMeasureScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _floor() => find.descendant(
  of: find.byType(PredictMeasureStage),
  matching: find.byWidgetPredicate(
    (Widget w) =>
        w is CustomPaint && w.painter.runtimeType.toString() == 'PmMapPainter',
  ),
);

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kPredictMeasureToolId]
        as Map<String, dynamic>;

/// Every string of the help entry, in the order the help sheet shows them.
String _helpText() {
  final Map<String, dynamic> h = _help();
  final StringBuffer b = StringBuffer()
    ..writeln(h['purpose'])
    ..writeln(h['whyHere']);
  for (final dynamic s in h['howToUse'] as List<dynamic>) {
    b.writeln(s);
  }
  for (final dynamic i in h['inputs'] as List<dynamic>) {
    final Map<String, dynamic> m = i as Map<String, dynamic>;
    b.writeln('${m['name']} ${m['unit']} ${m['range']}');
  }
  b
    ..writeln(h['algorithm'])
    ..writeln(h['example']);
  for (final dynamic s in h['fieldNotes'] as List<dynamic>) {
    b.writeln(s);
  }
  b.writeln(h['source']);
  return b.toString();
}

/// This tool's own source files, which carry every on-screen string.
List<File> _toolSources() => <File>[
  File('lib/services/wifi_lab/predict_measure_engine.dart'),
  for (final FileSystemEntity e
      in Directory('lib/screens/tools/calculators').listSync())
    if (e is File && e.path.contains('predict_measure_')) e,
];

String _keywordBlock() {
  final String src = File('lib/data/tool_keywords.dart').readAsStringSync();
  final int at = src.indexOf("'$kPredictMeasureToolId': <String>[");
  expect(at, greaterThan(0));
  return src.substring(at, src.indexOf('],', at));
}

void main() {
  group('registration', () {
    test('catalog entry on the Network Design and Security shelf of the '
        'Wi-Fi Classroom, with a route and an icon', () {
      final ToolCategory classroom = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final ToolEntry t = classroom.tools.firstWhere(
        (ToolEntry t) => t.id == kPredictMeasureToolId,
      );
      expect(t.title, 'Predict, Then Measure');
      expect(t.isLive, isTrue);
      expect(t.subgroup, 'Network Design and Security');
      expect(t.routeName, AppRouter.predictThenMeasure);
      expect(AppRouter.routes[AppRouter.predictThenMeasure], isNotNull);
      expect(
        File('assets/tool-icons/$kPredictMeasureToolId.svg').existsSync(),
        isTrue,
      );
    });
  });

  testWidgets('empty state: no walk, every wall untested, Measured map is no '
      'data, Undo, Clear and Update model disabled', (
    WidgetTester tester,
  ) async {
    final PredictMeasureController c = await _pump(tester);
    expect(c.hasWalk, isFalse);
    expect(c.testedCount, 0);
    expect(c.maps.measuredShare, 0);
    expect(find.textContaining('No walk yet'), findsOneWidget);
    expect(find.textContaining('untested'), findsWidgets);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.undo_rounded),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Update model'),
              matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('the design shows green everywhere'), findsOneWidget);
  });

  testWidgets('One side only tests nothing; Both sides tests every wall and '
      'enables Update model', (WidgetTester tester) async {
    final PredictMeasureController c = await _pump(tester);
    await _tap(tester, find.text('One side only'));
    expect(c.hasWalk, isTrue);
    expect(c.testedCount, 0);
    expect(c.canUpdateModel, isFalse);
    await _tap(tester, find.text('Both sides of every wall'));
    expect(c.testedCount, c.walls.length);
    expect(c.canUpdateModel, isTrue);
    await _tap(tester, find.text('Update model'));
    expect(c.updatedWalls, hasLength(c.walls.length));
    for (final PmWall w in c.walls) {
      expect(w.predictedLossDb, closeTo(w.trueLossDb, 1e-6));
    }
    expect(c.canUpdateModel, isFalse);
  });

  testWidgets('a drag on the floor draws one walk leg with samples', (
    WidgetTester tester,
  ) async {
    final PredictMeasureController c = await _pump(tester);
    final Finder floor = _floor();
    await tester.ensureVisible(floor);
    await tester.pumpAndSettle();
    final Rect r = tester.getRect(floor);
    final TestGesture g = await tester.startGesture(r.center);
    for (int i = 0; i < 6; i++) {
      await g.moveBy(Offset(r.width * 0.05, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(c.legs, hasLength(1));
    expect(c.sampleCount, greaterThan(3));
    expect(c.drawing, isFalse);
    expect(c.maps.measuredShare, greaterThan(0));
  });

  testWidgets('Move the AP: a tap on the floor moves the AP', (
    WidgetTester tester,
  ) async {
    final PredictMeasureController c = await _pump(tester);
    await _tap(tester, find.text('Move the AP'));
    final Finder floor = _floor();
    await tester.ensureVisible(floor);
    await tester.pumpAndSettle();
    final Rect r = tester.getRect(floor);
    final ({double x, double y}) before = c.ap;
    await tester.tapAt(r.topLeft + Offset(r.width * 0.2, r.height * 0.3));
    await tester.pumpAndSettle();
    expect(c.ap, isNot(before));
    expect(c.legs, isEmpty);
  });

  testWidgets('Reveal the truth adds the Truth map and the reveal prompt', (
    WidgetTester tester,
  ) async {
    final PredictMeasureController c = await _pump(tester);
    expect(c.availableViews, isNot(contains(PmMapView.truth)));
    await _tap(tester, find.text('Reveal the truth'));
    expect(c.revealed, isTrue);
    expect(c.view, PmMapView.truth);
    expect(c.availableViews, contains(PmMapView.truth));
    expect(find.textContaining('Reveal: the building differs'), findsOneWidget);
    expect(find.textContaining('true '), findsWidgets);
    await _tap(tester, find.text('Hide the truth'));
    expect(c.revealed, isFalse);
    expect(c.view, PmMapView.predicted);
  });

  testWidgets('stage and controls are separate widgets over one controller', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.byType(PredictMeasureStage), findsOneWidget);
    expect(find.byType(PredictMeasureControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PredictMeasureStage),
        matching: find.byType(PredictMeasureControls),
      ),
      findsNothing,
    );
  });

  test('controller: design edits, instructor truth, new truth, reset', () {
    final PredictMeasureController c = PredictMeasureController();
    addTearDown(c.dispose);
    c.selectedWall = 2;
    c.predictedLossDb = 12;
    expect(c.walls[2].predictedLossDb, 12);
    c.useMaterialDefault();
    expect(c.walls[2].predictedLossDb, c.walls[2].material.defaultLossDb);
    c.trueLossDb = 30;
    expect(c.walls[2].trueLossDb, 30);
    c.useBothSidesWalk();
    c.reset();
    expect(c.walls[2].trueLossDb, 30, reason: 'reset keeps the truth');
    expect(c.hasWalk, isFalse);
    final int seed = c.seed;
    c.newHiddenTruth();
    expect(c.seed, seed + 1);
    c.preset = PmPreset.warehouse;
    expect(c.walls, hasLength(kPmWarehouse.walls.length));
    expect(c.seed, kPmWarehouse.defaultSeed);
  });

  test('M cycles only the maps on offer', () {
    final PredictMeasureController c = PredictMeasureController();
    addTearDown(c.dispose);
    final List<PmMapView> seen = <PmMapView>[];
    for (int i = 0; i < 4; i++) {
      seen.add(c.view);
      c.nextView();
    }
    expect(seen, <PmMapView>[
      PmMapView.predicted,
      PmMapView.measured,
      PmMapView.difference,
      PmMapView.predicted,
    ]);
    c.revealed = true;
    c.view = PmMapView.difference;
    c.nextView();
    expect(c.view, PmMapView.truth);
  });

  test('copy text labels the illustrative values and lists every wall', () {
    final PredictMeasureController c = PredictMeasureController();
    addTearDown(c.dispose);
    c.useBothSidesWalk();
    final String t = c.copyText();
    expect(t, contains('Walls (losses illustrative)'));
    expect(t, contains('noise 0.0 dB (illustrative)'));
    expect(t, contains('effective isotropic radiated power (EIRP)'));
    expect(t, contains('design target (illustrative)'));
    expect(t, contains('Walls tested: ${c.walls.length}, untested: 0'));
    expect(t, isNot(contains(', true ')));
    c.revealed = true;
    expect(c.copyText(), contains(', true '));
  });

  group('help entry (spec 32)', () {
    test('says wall losses are illustrative and mentions Present and its '
        'keys', () {
      final String t = _helpText();
      expect(t, contains('illustrative'));
      expect(t, contains('wall losses here'));
      expect(t, contains('Present'));
      for (final String key in <String>['Space', 'M steps', 'R resets', 'Esc']) {
        expect(t, contains(key));
      }
      expect(
        t,
        contains('The Wi-Fi Classroom is designed for tablets and computers'),
      );
    });

    test('every acronym is spelled out before its short form is used alone',
        () {
      final String t = _helpText();
      for (final (String short, String long) in <(String, String)>[
        ('APoS', 'AP on a stick (APoS)'),
        ('IDW', 'inverse distance weighting (IDW)'),
        ('EIRP', 'effective isotropic radiated power (EIRP)'),
        ('FSPL', 'free-space path loss (FSPL)'),
      ]) {
        final int first = RegExp('\\b$short\\b').firstMatch(t)!.start;
        final int spelled = t.toLowerCase().indexOf(long.toLowerCase());
        expect(spelled, greaterThanOrEqualTo(0), reason: long);
        expect(
          first,
          spelled + long.length - short.length - 1,
          reason: '$short is used before it is spelled out',
        );
      }
    });

    test('keywords from the spec are all there', () {
      const List<String> spec = <String>[
        'predictive design',
        'ap on a stick',
        'apos',
        'validation',
        'wall loss',
        'survey',
        'model vs reality',
      ];
      final String block = _keywordBlock();
      for (final String k in spec) {
        expect(block, contains("'$k'"), reason: k);
      }
    });
  });

  test('no string names a vendor or product', () {
    final StringBuffer all = StringBuffer()
      ..writeln(_helpText())
      ..writeln(_keywordBlock());
    for (final File f in _toolSources()) {
      all.writeln(f.readAsStringSync());
    }
    expect(_toolSources().length, 6);
    final String t = all.toString().toLowerCase();
    for (final String banned in <String>[
      'ekahau',
      'hamina',
      'tamograph',
      'tamosoft',
      'airmagnet',
      'ibwave',
      'netspot',
      'sidekick',
      'cisco',
      'meraki',
      'aruba',
      'ubiquiti',
      'unifi',
      'ruckus',
      'fortinet',
      'juniper',
      'cost 231',
      'cost-231',
    ]) {
      expect(t, isNot(contains(banned)), reason: banned);
    }
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in const <Size>[Size(390, 844), Size(1280, 900)]) {
      for (final PmPreset p in PmPreset.values) {
        testWidgets(
          '$name ${size.width.toInt()} wide, ${p.label}: lays out with a '
          'walk, the difference map and the reveal, no exception',
          (WidgetTester tester) async {
            final PredictMeasureController c = await _pump(
              tester,
              theme: theme(),
              width: size.width,
              height: size.height,
            );
            c.preset = p;
            c.useBothSidesWalk();
            c.sigmaDb = 3;
            c.view = PmMapView.difference;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            c.revealed = true;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
