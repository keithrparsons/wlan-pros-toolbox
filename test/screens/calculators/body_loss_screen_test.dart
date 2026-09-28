// Widget tests for the Wi-Fi Classroom Body Loss screen.
//
// The math is pinned in test/services/wifi_lab/body_loss_model_test.dart;
// these cover the screen contract (spec 34, "Done means"): registration
// (catalog, route, large-screen gate, help, keywords, icon), every loss
// setting on screen with "illustrative" in its label, the holder turning,
// empty vs occupied, scatter, the prediction, dragging on the floor, the
// stage/controls split, and the layout at 390 x 844 and 1280 wide in both
// themes without overflow or sideways scrolling.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_painter.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/body_loss_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<BodyLossController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const BodyLossScreen(),
      routes: <String, WidgetBuilder>{
        AppRouter.rfAttenuation: (_) => const Scaffold(body: Text('RFA')),
        AppRouter.wifiThroughAWall: (_) => const Scaffold(body: Text('WTW')),
      },
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<BodyLossStage>(find.byType(BodyLossStage)).controller;
}

void _expectNoSidewaysScroll(WidgetTester tester) {
  final Iterable<Scrollable> sideways = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (Scrollable s) =>
            s.axisDirection == AxisDirection.left ||
            s.axisDirection == AxisDirection.right,
      );
  expect(sideways, isEmpty, reason: 'nothing may scroll sideways');
}

void _expectTextInsideWidth(WidgetTester tester, double width) {
  for (final Element e in find.byType(Text).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final Offset tl = ro.localToGlobal(Offset.zero);
    expect(
      tl.dx + ro.size.width,
      lessThanOrEqualTo(width + 0.5),
      reason: 'text "${(e.widget as Text).data}" runs past $width px',
    );
    expect(tl.dx, greaterThanOrEqualTo(-0.5));
  }
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kBodyLossToolId]
        as Map<String, dynamic>;

String _helpText() {
  final Map<String, dynamic> h = _help();
  return <String>[
    h['purpose'] as String,
    h['whyHere'] as String,
    ...(h['howToUse'] as List<dynamic>).cast<String>(),
    ...(h['inputs'] as List<dynamic>).map(jsonEncode),
    h['algorithm'] as String,
    h['example'] as String,
    ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
    h['source'] as String,
  ].join('\n');
}

BlStagePainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(BodyLossStage),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((CustomPaint p) => p.painter)
    .whereType<BlStagePainter>()
    .single;

Rect _floorRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(BodyLossStage),
        matching: find.byType(GestureDetector),
      )
      .first,
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, RF and Propagation, live, routed, '
        'after Uplink vs Downlink', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final List<String> ids = cls.tools.map((ToolEntry t) => t.id).toList();
      final ToolEntry e = cls.tools.firstWhere(
        (ToolEntry t) => t.id == kBodyLossToolId,
      );
      expect(kBodyLossToolId, 'body-loss');
      expect(e.title, 'Body Loss');
      expect(e.subgroup, 'RF and Propagation');
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.bodyLoss);
      expect(ids.indexOf('body-loss'), ids.indexOf('uplink-downlink') + 1);
      expect(AppRouter.routes[AppRouter.bodyLoss], isNotNull);
      expect(File('assets/tool-icons/body-loss.svg').existsSync(), isTrue);
      expect(
        File('assets/tool-icons/body-loss.svg').readAsStringSync(),
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
      final Widget w = AppRouter.routes[AppRouter.bodyLoss]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect((w as LargeScreenGate).toolTitle, 'Body Loss');
    });

    test('keywords carry spec 34\'s list', () {
      expect(
        kToolKeywords[kBodyLossToolId],
        containsAll(<String>[
          'body loss',
          'human body',
          'crowd',
          'occupancy',
          'attenuation',
          'orientation',
          'holding the phone',
        ]),
      );
    });

    test('help: MCS spelled out at first use, the losses illustrative and '
        'not measured, Present and the keys', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wireless Classroom');
      final String all = _helpText();
      final int first = all.indexOf('MCS');
      expect(first, greaterThanOrEqualTo(0));
      expect(
        all.substring(first, first + 40).toLowerCase(),
        contains('modulation and coding scheme'),
      );
      expect(all, contains('illustrative setting, not a measurement'));
      expect(h['source'] as String, contains('No primary source was read'));
      for (final Map<String, dynamic> input
          in (h['inputs'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final String name = input['name'] as String;
        if (name.contains('loss') || name.contains('multiplier')) {
          expect(input['range'], contains('illustrative'), reason: name);
        }
      }
      expect(all, contains('Present opens'));
      for (final String key in <String>[
        'Left and Right',
        'Space',
        'R resets',
        'Esc',
      ]) {
        expect(all, contains(key));
      }
      expect(
        (h['fieldNotes'] as List<dynamic>).cast<String>(),
        contains(
          'The Wireless Classroom is designed for tablets and computers, and on '
          'a phone some views are cramped.',
        ),
      );
    });

    test('what the stage draws clears 3:1 in both themes: the crowd, the '
        'ink, the thin in-path ring on the surface, and the ink outline '
        'around every lime fill', () {
      for (final AppColorScheme s in <AppColorScheme>[
        AppColorScheme.dark(),
        AppColorScheme.light(),
      ]) {
        for (final Color c in <Color>[
          s.textTertiary,
          s.textPrimary,
          s.textAccent,
        ]) {
          expect(
            _contrast(c, s.surface2),
            greaterThanOrEqualTo(3),
            reason: '$c light=${s.isLight}',
          );
        }
        // A lime-filled mark is bounded by its ink outline. On dark the lime
        // fill itself stands off the surface; on light (GL-003 §8.20.2, lime
        // is a fill only) the ink outline does, checked above as textPrimary.
        if (!s.isLight) {
          expect(_contrast(s.primary, s.surface2), greaterThanOrEqualTo(3));
        }
        // The badge number sits on the lime fill.
        expect(_contrast(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      }
    });
  });

  testWidgets('default screen: level, MCS, losses, empty vs occupied', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.text('Body Loss'), findsOneWidget);
    expect(find.text('-71.4 dBm'), findsWidgets);
    expect(find.text('MCS 3'), findsWidgets);
    expect(find.text('Loss from the holder  '), findsOneWidget);
    expect(find.text('Loss from the crowd  '), findsOneWidget);
    expect(find.text('Empty vs occupied  '), findsOneWidget);
    expect(find.text('9.6 dB'), findsNWidgets(2));
    expect(
      find.textContaining('Empty -61.8 dBm, MCS 7; occupied -71.4 dBm, MCS 3'),
      findsOneWidget,
    );
  });

  testWidgets('every loss setting is on screen and labeled illustrative', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    for (final String l in <String>[
      BlLabels.holderLoss,
      BlLabels.perPersonLoss,
      BlLabels.multiplier5,
      BlLabels.multiplier6,
      BlLabels.lossesSection,
      BlLabels.bandTrend,
    ]) {
      expect(find.text(l), findsOneWidget, reason: l);
      expect(l.toLowerCase(), contains('illustrative'));
    }
    expect(find.textContaining(BlLabels.turnRamp), findsOneWidget);
  });

  testWidgets('Back to the AP applies the full holder loss; Face the AP '
      'removes it', (WidgetTester tester) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    await _tap(tester, find.text('Back to the AP'));
    expect(k.config.holderLossAppliedDb, closeTo(9.6, 1e-9));
    expect(
      find.textContaining('The holder\'s back is to the AP'),
      findsOneWidget,
    );
    expect(_painter(tester).holderLabel, 'Holder, body in the path: 9.6 dB');
    await _tap(tester, find.text('Face the AP'));
    expect(k.config.holderLossAppliedDb, 0);
    expect(_painter(tester).holderLabel, 'Holder');
  });

  testWidgets('Empty removes only the crowd loss and disables the crowd '
      'controls, with the reason', (WidgetTester tester) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    final double holder = k.config.holderLossAppliedDb;
    await _tap(tester, find.text('Empty'));
    expect(k.config.occupied, isFalse);
    expect(k.config.crowdLossDb, 0);
    expect(k.config.holderLossAppliedDb, holder);
    expect(
      find.text(
        'The building is empty. Choose Occupied to bring the crowd back.',
      ),
      findsOneWidget,
    );
    expect(_painter(tester).emptyLabel, 'Empty building');
    final OutlinedButton scatter = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Scatter the crowd'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(scatter.onPressed, isNull);
    final Iterable<Slider> disabled = tester
        .widgetList<Slider>(find.byType(Slider))
        .where((Slider s) => s.onChanged == null);
    expect(disabled, hasLength(1));
    await _tap(tester, find.text('Occupied'));
    expect(k.config.crowdLossDb, closeTo(9.6, 1e-9));
  });

  testWidgets('Scatter places the crowd again from the next seed', (
    WidgetTester tester,
  ) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    final List<BlPoint> before = k.config.people;
    await _tap(tester, find.text('Scatter the crowd'));
    expect(k.config.seed, BlConfig.defaultSeed + 1);
    expect(k.config.people, isNot(before));
  });

  testWidgets('band changes the losses through the multipliers', (
    WidgetTester tester,
  ) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    await _tap(tester, find.text('2.4 GHz'));
    expect(k.config.band, WifiBand.band24);
    expect(k.config.crowdLossDb, closeTo(8, 1e-9));
    await _tap(tester, find.text('6 GHz'));
    expect(k.config.crowdLossDb, closeTo(4 * 1.3 * 2, 1e-9));
  });

  testWidgets('predict, then reveal', (WidgetTester tester) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    expect(
      find.text(
        'You surveyed the auditorium empty on Saturday. What happens Monday '
        'at 9 a.m.?',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('The level drops'), findsNothing);
    await _tap(tester, find.text('Reveal the answer'));
    expect(
      find.textContaining(
        'The level drops 9.6 dB: from -61.8 dBm (MCS 7) in the empty room to '
        '-71.4 dBm (MCS 3)',
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Show Saturday, empty'));
    expect(k.config.occupied, isFalse);
    expect(find.text('Show Monday, occupied'), findsOneWidget);
  });

  testWidgets('with nobody on the line the answer says nothing changes', (
    WidgetTester tester,
  ) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    k
      ..setCrowdSize(0)
      ..setRevealed(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Here, nothing changes'), findsOneWidget);
    expect(find.text('No one else is in the room.'), findsOneWidget);
  });

  testWidgets('drag the holder to move them, drag a person to place them, '
      'tap elsewhere to turn the holder', (WidgetTester tester) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    final Rect r = _floorRect(tester);
    final BlFloorGeometry g = BlFloorGeometry(r.size);
    Offset at(BlPoint p) => r.topLeft + g.toPx(p);

    // Tap a spot straight above the holder with nobody near it: the holder
    // turns to face it and does not move.
    final BlPoint h = k.config.holder;
    final BlPoint spot =
        <BlPoint>[
          for (double y = 0.6; y < h.y - 2; y += 0.2) BlPoint(h.x, y),
        ].firstWhere(
          (BlPoint p) =>
              k.config.people.every((BlPoint q) => q.distanceTo(p) > 1),
        );
    await tester.tapAt(at(spot));
    await tester.pumpAndSettle();
    expect(k.config.facingDeg, closeTo(0, 1));
    expect(k.config.holder, h);

    // Drag the holder toward the AP.
    await tester.dragFrom(at(h), Offset(-4 * g.pxPerM, 0));
    await tester.pumpAndSettle();
    expect(k.config.holder.x, lessThan(h.x - 2));

    // Drag person 0 onto the line.
    final BlPoint p0 = k.config.people[0];
    final BlPoint target = BlPoint(
      (BlConfig.ap.x + k.config.device.x) / 2,
      (BlConfig.ap.y + k.config.device.y) / 2,
    );
    await tester.dragFrom(at(p0), at(target) - at(p0));
    await tester.pumpAndSettle();
    expect(k.config.people[0].distanceTo(target), lessThan(0.3));
    expect(k.config.crossingIndexes, contains(0));
  });

  testWidgets('the explainer opens RF Attenuation and Wi-Fi Through a Wall', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    await _tap(tester, find.text('Open RF Attenuation'));
    expect(find.text('RFA'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Open Wi-Fi Through a Wall'));
    expect(find.text('WTW'), findsOneWidget);
  });

  testWidgets('the copy payload names the losses as illustrative', (
    WidgetTester tester,
  ) async {
    final BodyLossController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    final String t = k.copyText();
    expect(t, startsWith('Body Loss\n'));
    expect(t, contains('Illustrative losses: holder 8.0 dB at 2.4 GHz'));
    expect(t, contains('Received -71.4 dBm, MCS 3'));
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(BodyLossStage), findsOneWidget);
    expect(find.byType(BodyLossControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BodyLossStage),
        matching: find.byType(BodyLossControls),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(BodyLossControls),
        matching: find.byType(BodyLossStage),
      ),
      findsNothing,
    );
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1280, 900),
    ]) {
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly', (
        WidgetTester tester,
      ) async {
        final BodyLossController k = await _pump(
          tester,
          theme: theme(),
          size: size,
        );
        // Fullest content: 6 GHz, the whole crowd, back to the AP at the
        // back wall and then at the front, the answer revealed, then empty.
        k
          ..setBand(WifiBand.band6)
          ..setCrowdSize(50)
          ..setHolderLoss(20)
          ..setPerPersonLoss(10)
          ..setRevealed(true);
        for (final double x in <double>[BlConfig.floorWidthM, 0]) {
          k
            ..setHolderX(x)
            ..backToAp();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          _expectNoSidewaysScroll(tester);
          _expectTextInsideWidth(tester, size.width);
        }
        k.setOccupied(false);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectTextInsideWidth(tester, size.width);
      });
    }
  }
}
