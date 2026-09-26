// Widget tests for the Wi-Fi Classroom "Heat Map Builder" screen.
//
// The math is pinned in test/services/wifi_lab/heat_map_builder_engine_test
// .dart; these cover the screen contract: catalog registration, the empty
// state (white floor, no data), placing a grid and tapping samples, the
// worked-example panel following power, domain and method, the three-dots
// lesson, the cell inspector, the spacing experiment, the stage and controls
// as separate widgets, the copy text, the help entry's cautions (one
// documented method, no vendor names, acronyms spelled out first), and phone
// and desktop widths in both themes laying out with no exception.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/heat_map_builder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/heat_map_builder_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/heat_map_builder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/heat_map_builder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/heat_map_builder_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<HeatMapBuilderController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1024,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  final HeatMapBuilderController c = HeatMapBuilderController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: HeatMapBuilderScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

String _valueOf(WidgetTester tester, String label) {
  final Finder row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  final List<Text> texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .toList();
  return texts.last.data ?? '';
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// The floor's paint area (the CustomPaint under the map card's gesture
/// detector).
Finder _floor() => find.descendant(
  of: find.byType(HeatMapBuilderStage),
  matching: find.byWidgetPredicate(
    (Widget w) => w is CustomPaint && w.painter.runtimeType.toString() == 'HmMapPainter',
  ),
);

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kHeatMapBuilderToolId]
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

void main() {
  test('catalog registers heat-map-builder in the Wi-Fi Classroom', () {
    final ToolCategory cls = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry e = cls.tools.firstWhere(
      (ToolEntry t) => t.id == kHeatMapBuilderToolId,
    );
    expect(e.title, 'Heat Map Builder');
    expect(e.subgroup, 'Network Design and Security');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/heat-map-builder');
  });

  testWidgets('empty: the whole floor is white, readouts say no data', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    expect(find.text('Heat Map Builder'), findsOneWidget);
    expect(find.byType(HeatMapBuilderStage), findsOneWidget);
    expect(find.byType(HeatMapBuilderControls), findsOneWidget);
    expect(c.map.noDataShare, 1);
    expect(_valueOf(tester, 'Root mean square error (RMSE)'), 'no data');
    expect(_valueOf(tester, 'Floor with no data (white)'), '100%');
    expect(find.textContaining('No samples yet'), findsOneWidget);
    final IconButton undo = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.undo_rounded),
    );
    expect(undo.onPressed, isNull);
  });

  testWidgets('Grid places samples and the readouts fill in; Clear empties', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    await _tap(tester, find.text('Grid'));
    // A 3 m grid on 40 x 25 m: 13 across, 8 down.
    expect(c.points, hasLength(104));
    expect(_valueOf(tester, 'Samples'), '104');
    expect(
      _valueOf(tester, 'Root mean square error (RMSE)'),
      '${c.map.rmseDb!.toStringAsFixed(1)} dB',
    );
    await _tap(tester, find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
    expect(c.points, isEmpty);
    expect(c.map.noDataShare, 1);
  });

  testWidgets('a tap on the floor adds a sample; Undo removes it', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    await tester.ensureVisible(_floor());
    await tester.pumpAndSettle();
    await tester.tap(_floor());
    await tester.pumpAndSettle();
    expect(c.points, hasLength(1));
    expect(c.layout, HmLayout.custom);
    expect(c.map.noDataShare, lessThan(1));
    await _tap(tester, find.widgetWithIcon(IconButton, Icons.undo_rounded));
    expect(c.points, isEmpty);
  });

  testWidgets('inspecting a cell shows its samples, value and error', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    await _tap(tester, find.text('Grid'));
    await _tap(tester, find.text('Inspect a cell'));
    await tester.ensureVisible(_floor());
    await tester.pumpAndSettle();
    await tester.tap(_floor());
    await tester.pumpAndSettle();
    expect(c.points, hasLength(104), reason: 'inspect adds nothing');
    expect(c.inspection, isNotNull);
    expect(c.inspection!.contributions, hasLength(kHmIdwNeighbors));
    expect(find.textContaining('Cell at'), findsOneWidget);
    expect(find.textContaining('samples, weighted'), findsOneWidget);
  });

  testWidgets('the worked example follows power, domain and method', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    String estimate() => _valueOf(tester, 'Cell estimate (power 2, averaged in dB)');
    expect(estimate(), '-58.1 dBm');
    c.power = 1;
    await tester.pumpAndSettle();
    expect(
      _valueOf(tester, 'Cell estimate (power 1, averaged in dB)'),
      '-60.5 dBm',
    );
    c.power = 4;
    await tester.pumpAndSettle();
    expect(
      _valueOf(tester, 'Cell estimate (power 4, averaged in dB)'),
      '-55.8 dBm',
    );
    c.power = 2;
    await _tap(tester, find.text('Milliwatts (mW)'));
    expect(
      _valueOf(tester, 'Cell estimate (power 2, averaged in milliwatts)'),
      '-56.2 dBm',
    );
    await _tap(tester, find.text('Nearest neighbor'));
    expect(
      _valueOf(tester, 'Cell estimate (nearest neighbor)'),
      '-55.0 dBm',
    );
  });

  testWidgets('predict, then reveal: three dots, a wider range, the wall', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    await _tap(tester, find.text('Start: three dots'));
    expect(c.points, hasLength(3));
    expect(find.textContaining('Predict: three dots'), findsOneWidget);
    expect(c.map.noDataShare, greaterThan(0.8));
    await _tap(tester, find.text('Reveal: widen the guess range'));
    expect(c.map.noDataShare, 0);
    expect(find.textContaining('Reveal 1'), findsOneWidget);
    await _tap(tester, find.text('Reveal: the hidden wall'));
    expect(c.wallRevealed, isTrue);
    expect(c.view, HmView.error);
    expect(find.textContaining('Reveal 2: the hidden 12 dB wall'), findsOneWidget);
    await _tap(tester, find.text('End the lesson'));
    expect(c.lesson, HmLessonStep.off);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the spacing experiment plots and closes', (
    WidgetTester tester,
  ) async {
    final HeatMapBuilderController c = await _pump(tester);
    await _tap(tester, find.text('Spacing experiment'));
    expect(c.experiment, isNotNull);
    expect(
      find.text(
        'Spacing experiment: root mean square error (RMSE) by grid spacing',
      ),
      findsOneWidget,
    );
    expect(find.text('No noise'), findsOneWidget);
    // A setting change makes the result stale, so it goes away.
    c.guessRangeM = 8;
    await tester.pumpAndSettle();
    expect(c.experiment, isNull);
  });

  test('copy text says one documented method and spells out RMSE', () {
    final HeatMapBuilderController c = HeatMapBuilderController();
    addTearDown(c.dispose);
    c.useGrid();
    final String t = c.copyText();
    expect(t, contains('One documented method'));
    expect(t, contains('RMSE (root mean square error)'));
    expect(t, contains('IDW (inverse distance weighting)'));
    expect(t, contains('Samples: 104 (Grid, every 3 m)'));
  });

  group('help entry (spec 27)', () {
    test('mentions Present, the keys and the one-documented-method caution',
        () {
      final String t = _helpText();
      expect(t, contains('Present'));
      for (final String key in <String>['Space', 'Up and Down', 'Esc']) {
        expect(t, contains(key));
      }
      expect(t, contains('one documented method'));
    });

    test('names no survey vendor and not the retired term', () {
      final String t = _helpText().toLowerCase();
      for (final String banned in <String>[
        'ekahau',
        'hamina',
        'airmagnet',
        'tamograph',
        'netspot',
        'ibwave',
        'sidekick',
        'sido',
        'signal propagation assessment',
      ]) {
        expect(t, isNot(contains(banned)), reason: banned);
      }
    });

    test('every acronym is spelled out before its short form is used alone',
        () {
      final String t = _helpText();
      for (final (String short, String long) in <(String, String)>[
        ('IDW', 'inverse distance weighting (IDW)'),
        ('RMSE', 'root mean square error (RMSE)'),
        ('mW', 'milliwatts (mW)'),
        ('EIRP', 'effective isotropic radiated power (EIRP)'),
        ('FSPL', 'free-space path loss (FSPL)'),
        ('ACM', 'Association for Computing Machinery (ACM)'),
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
      // The spec's list, checked against the search keywords.
      const List<String> spec = <String>[
        'heat map',
        'interpolation',
        'extrapolation',
        'idw',
        'inverse distance',
        'kriging',
        'guess range',
        'accuracy distance',
        'interpolation distance',
        'sample spacing',
        'survey',
      ];
      final String src = File('lib/data/tool_keywords.dart').readAsStringSync();
      final int at = src.indexOf("'heat-map-builder': <String>[");
      expect(at, greaterThan(0));
      final String block = src.substring(at, src.indexOf('],', at));
      for (final String k in spec) {
        expect(block, contains("'$k'"), reason: k);
      }
      expect(block, isNot(contains('signal propagation')));
    });
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in const <Size>[Size(390, 844), Size(1280, 900)]) {
      testWidgets(
        '$name ${size.width.toInt()} wide: lays out with a map, error map '
        'and experiment, no exception',
        (WidgetTester tester) async {
          final HeatMapBuilderController c = await _pump(
            tester,
            theme: theme(),
            width: size.width,
            height: size.height,
          );
          c.useWalk();
          c.sigmaDb = 4;
          c.averaging = 4;
          c.inspect((x: 20, y: 5));
          c.wallRevealed = true;
          c.view = HmView.error;
          c.runExperiment();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(c.experiment, hasLength(3));
        },
      );
    }
  }
}
