// Widget tests for How to Measure Wall Attenuation (measure-wall).
//
// The math is pinned in test/services/wifi_lab/measure_wall_model_test.dart;
// these cover the screen: registration (catalog shelf, route, large-screen
// gate, help, keywords, icon), the live readout and its three parts, the
// locked channel, the illustrative label, dragging the laptop across the
// wall, the prediction, the units switch, and the layout at 390 x 844 and
// 1280 x 900 in both themes without overflow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_format.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_readouts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/measure_wall_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wall_slab_physics.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<MeasureWallController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
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
        home: const MeasureWallScreen(),
        routes: <String, WidgetBuilder>{
          AppRouter.wifiThroughAWall: (_) => const Scaffold(body: Text('WTW')),
          AppRouter.predictThenMeasure: (_) =>
              const Scaffold(body: Text('PTM')),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<MeasureWallStage>(find.byType(MeasureWallStage))
      .controller;
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kMeasureWallToolId]
        as Map<String, dynamic>;

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, RF and Propagation, live, routed, with '
        'an icon', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final ToolEntry e = cls.tools.firstWhere(
        (ToolEntry t) => t.id == kMeasureWallToolId,
      );
      expect(kMeasureWallToolId, 'measure-wall');
      expect(e.title, 'How to Measure Wall Attenuation');
      expect(e.subgroup, 'RF and Propagation');
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.measureWall);
      expect(AppRouter.routes[AppRouter.measureWall], isNotNull);
      final File icon = File('assets/tool-icons/measure-wall.svg');
      expect(icon.existsSync(), isTrue);
      expect(
        icon.readAsStringSync(),
        allOf(contains('viewBox="0 0 24 24"'), contains('currentColor')),
      );
    });

    testWidgets('the router puts the large-screen notice in front of it', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      final Widget w = AppRouter.routes[AppRouter.measureWall]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect(
        (w as LargeScreenGate).toolTitle,
        'How to Measure Wall Attenuation',
      );
    });

    test('keywords find it by what a student would type', () {
      expect(
        kToolKeywords[kMeasureWallToolId],
        containsAll(<String>[
          'wall attenuation',
          'measure wall',
          'wall loss',
          'free space path loss',
        ]),
      );
    });

    test('help: acronyms spelled out, Present and the keys, what it leaves '
        'out, the two linked tools, the spread illustrative', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wireless Classroom');
      final String all = <String>[
        h['purpose'] as String,
        h['whyHere'] as String,
        ...(h['howToUse'] as List<dynamic>).cast<String>(),
        h['algorithm'] as String,
        h['example'] as String,
        ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
        h['source'] as String,
      ].join('\n');
      for (final (String a, String spelled) in <(String, String)>[
        ('RF', 'radio frequency'),
        ('AP', 'access point'),
        ('FSPL', 'free-space path loss'),
      ]) {
        final int i = all.indexOf(RegExp('\\b$a\\b'));
        expect(i, greaterThanOrEqualTo(0), reason: a);
        // Spelled out right before or right after the first use.
        expect(
          all.substring(i < 40 ? 0 : i - 40, i + 40).toLowerCase(),
          contains(spelled),
          reason: '$a at first use',
        );
      }
      expect(all, contains('Present'));
      expect(all, contains('Esc exits'));
      expect(all, contains('Left out:'));
      expect(all, contains('Wi-Fi Through a Wall'));
      expect(all, contains('Predict, Then Measure'));
      expect(all, contains('illustrative'));
      expect(all, contains('20 log10(3 / 1) = 9.5 dB'));
      expect(all, isNot(contains('—')));
    });
  });

  group('screen', () {
    testWidgets('opens with the live measured value and its three parts, '
        'and the locked channel', (WidgetTester tester) async {
      final MeasureWallController k = await _pump(tester);
      final MwConfig c = k.config;
      expect(find.text(MwFormat.db(c.measuredDb!)), findsOneWidget);
      expect(find.text('True wall loss'), findsOneWidget);
      expect(find.text('Free-space error'), findsOneWidget);
      expect(find.text('Fading residual'), findsOneWidget);
      expect(find.text(MwFormat.signedDb(c.geometryErrorDb)), findsOneWidget);
      expect(find.text(mwChannelLine(c)), findsOneWidget);
      expect(find.textContaining('channel 100 (5500 MHz'), findsWidgets);
      await tester.scrollUntilVisible(find.text(MwLabels.readingsSection), 200);
      expect(find.text(MwLabels.readingsSection), findsOneWidget);
      expect(find.text(MwLabels.spread), findsOneWidget);
    });

    testWidgets('dragging the person across the wall moves the laptop to '
        'the far side and the number follows', (WidgetTester tester) async {
      final MeasureWallController k = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      expect(k.config.side, MwSide.near);
      final double before = k.config.measuredDb!;
      final Rect room = tester.getRect(
        find
            .descendant(
              of: find.byType(MeasureWallStage),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      // Tap near the right edge: behind the wall.
      await tester.tapAt(Offset(room.right - 20, room.center.dy));
      await tester.pumpAndSettle();
      expect(k.config.side, MwSide.far);
      expect(k.config.measuredDb, isNot(closeTo(before, 1e-9)));
      // Drag back to the left, in front of the wall.
      await tester.dragFrom(
        Offset(room.right - 20, room.center.dy),
        Offset(-(room.width * 0.5), 0),
      );
      await tester.pumpAndSettle();
      expect(k.config.side, MwSide.near);
    });

    testWidgets('Take new readings changes only the side the laptop is on', (
      WidgetTester tester,
    ) async {
      final MeasureWallController k = await _pump(tester);
      final List<double> near = k.config.nearSeries.samplesDbm;
      final List<double> far = k.config.farSeries.samplesDbm;
      await tester.tap(find.textContaining('Take new readings'));
      await tester.pumpAndSettle();
      expect(k.config.nearSeries.samplesDbm, isNot(near));
      expect(k.config.farSeries.samplesDbm, far);
    });

    testWidgets('the tight scene cuts the free-space error under 1 dB', (
      WidgetTester tester,
    ) async {
      final MeasureWallController k = await _pump(tester);
      expect(k.config.geometryErrorDb, greaterThan(4));
      final Finder tight = find.textContaining('Tight: source 4 m');
      await tester.scrollUntilVisible(tight, 200);
      await tester.tap(tight);
      await tester.pumpAndSettle();
      expect(k.activePreset, MwPreset.tight);
      expect(k.config.geometryErrorDb, lessThan(1));
    });

    testWidgets('predict, then reveal: the answer says too high by 9.5 dB '
        'and Show it puts the scene on the stage', (WidgetTester tester) async {
      final MeasureWallController k = await _pump(tester);
      final Finder reveal = find.text('Reveal the answer');
      await tester.scrollUntilVisible(reveal, 200);
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      expect(find.textContaining('Too high.'), findsOneWidget);
      expect(find.textContaining('= 9.5 dB'), findsOneWidget);
      await tester.tap(find.text('Show it'));
      await tester.pumpAndSettle();
      expect(k.config.sourceToWallM, 2);
      expect(k.config.nearGapM, 1);
      expect(k.config.farGapM, 1);
      expect(
        k.config.geometryErrorDb,
        closeTo(
          MwMath.geometryErrorDb(
            sourceToWallM: 2,
            nearGapM: 1,
            farGapM: 1,
            thicknessM: k.config.thicknessM,
          ),
          1e-9,
        ),
      );
    });

    testWidgets('a far side below the noise floor reads Cannot measure', (
      WidgetTester tester,
    ) async {
      final MeasureWallController k = await _pump(tester);
      k
        ..setMaterial(WallMaterial.metal)
        ..setThicknessM(0.01);
      await tester.pumpAndSettle();
      expect(find.text('Cannot measure'), findsOneWidget);
      // The metal slab's loss is capped as Wi-Fi Through a Wall caps it, and
      // no fading residual is claimed without a far reading.
      expect(find.text('more than 150 dB'), findsOneWidget);
      expect(find.text('none, no far reading'), findsOneWidget);
      expect(find.textContaining('below the noise floor'), findsWidgets);
    });

    testWidgets('imperial: the source distance and the scenes read in feet', (
      WidgetTester tester,
    ) async {
      await _pump(tester, units: UnitSystem.imperial);
      // 4 m is 13.1 ft; LengthFormat shows whole feet from 10 ft up.
      expect(find.textContaining('13 ft'), findsWidgets);
      expect(find.textContaining('Source to wall 4 m'), findsNothing);
    });

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size size in const <Size>[Size(390, 844), Size(1280, 900)]) {
        testWidgets('$name ${size.width.toInt()}x${size.height.toInt()}: no '
            'overflow in the default or the prediction scene', (
          WidgetTester tester,
        ) async {
          final MeasureWallController k = await _pump(
            tester,
            theme: theme(),
            size: size,
          );
          expect(tester.takeException(), isNull);
          k
            ..applyPreset(MwPreset.predict)
            ..setRevealed(true)
            ..setSide(MwSide.far);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          k.setSourceToWall(15);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
