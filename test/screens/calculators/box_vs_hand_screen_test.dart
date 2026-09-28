// Screen tests for The Number on the Box vs the Number in Your Hand
// (box-vs-hand): registration (catalog, route, large-screen gate, help,
// keywords, icon), the three steps, the client control, the distance step,
// the tools it points to, and clean rendering on phone and desktop in both
// themes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/box_vs_hand_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<BoxVsHandController> _pump(
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
      home: const BoxVsHandScreen(),
      routes: <String, WidgetBuilder>{
        AppRouter.throughputCalc: (_) => const Scaffold(body: Text('TPUT')),
        AppRouter.mcsIndex: (_) => const Scaffold(body: Text('MCSI')),
        AppRouter.rateVsRange: (_) => const Scaffold(body: Text('RVR')),
      },
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<BoxVsHandStage>(find.byType(BoxVsHandStage)).controller;
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kBoxVsHandToolId]
        as Map<String, dynamic>;

String _helpText() {
  final Map<String, dynamic> h = _help();
  return <String>[
    h['name'] as String,
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

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Every rendered text in the tool (stage, controls, explainer, title).
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, Signals and PHY, live, routed, with an '
        'icon', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final ToolEntry e = cls.tools.firstWhere(
        (ToolEntry t) => t.id == kBoxVsHandToolId,
      );
      expect(kBoxVsHandToolId, 'box-vs-hand');
      expect(e.title, kBoxVsHandTitle);
      expect(e.subgroup, 'Signals and PHY');
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.boxVsHand);
      expect(AppRouter.routes[AppRouter.boxVsHand], isNotNull);
      final File icon = File('assets/tool-icons/box-vs-hand.svg');
      expect(icon.existsSync(), isTrue);
      expect(
        icon.readAsStringSync(),
        allOf(
          contains('viewBox="0 0 24 24"'),
          contains('currentColor'),
          isNot(contains('#')),
        ),
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
      final Widget w = AppRouter.routes[AppRouter.boxVsHand]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect((w as LargeScreenGate).toolTitle, kBoxVsHandTitle);
    });

    test('keywords carry the words a student types', () {
      expect(
        kToolKeywords[kBoxVsHandToolId],
        containsAll(<String>[
          'be19000',
          'spatial streams',
          '2x2',
          'phy rate',
          'wi-fi classroom',
        ]),
      );
    });

    test('help: acronyms spelled out at first use, the defaults said to be '
        'illustrative, the estimate favorable, Present and the keys, and no '
        'vendor or phone model', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wireless Classroom');
      final String all = _helpText();
      for (final (String short, String long) in <(String, String)>[
        ('Mbps', 'megabits per second'),
        ('MCS', 'modulation and coding scheme'),
        ('PHY', 'physical layer'),
        ('EIRP', 'effective isotropic radiated power'),
        ('MIMO', 'multiple input, multiple output'),
        ('QAM', 'quadrature amplitude modulation'),
      ]) {
        final int first = all.indexOf(short);
        expect(first, greaterThanOrEqualTo(0), reason: short);
        expect(
          all.substring(first, first + short.length + 45).toLowerCase(),
          contains(long),
          reason: short,
        );
      }
      expect(all, contains('illustrative'));
      expect(all, contains('favorable'));
      expect(all, contains('Present opens'));
      for (final String key in <String>[
        'Right shows the next step',
        'Left the one before',
        'Space',
        'Up and Down',
        'R resets',
        'Esc',
      ]) {
        expect(all, contains(key));
      }
      expect(
        all,
        isNot(
          matches(
            RegExp('TP-Link|Archer|iPhone|Pixel|Apple|Google|Samsung|Galaxy'),
          ),
        ),
      );
      expect(
        (h['fieldNotes'] as List<dynamic>).cast<String>(),
        contains(
          'The Wireless Classroom is designed for tablets and computers, and on '
          'a phone some views are cramped.',
        ),
      );
    });
  });

  testWidgets('opens on the box: 18,656 Mbps, the next two steps waiting', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(tester);
    expect(k.step, BvhStep.box);
    expect(k.client, BvhClient.phone2x2);
    expect(find.text(BvhLabels.boxRow()), findsOneWidget);
    expect(find.text('On the box: a BE19000-class router'), findsOneWidget);
    expect(
      find.text('18,656 Mbps', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Step 2 of 3'), findsOneWidget);
    expect(find.textContaining('Step 3 of 3'), findsOneWidget);
    expect(find.textContaining('5,765 Mbps', findRichText: true), findsNothing);
  });

  testWidgets('Show the next step walks box, best case, distance; Back a '
      'step returns', (WidgetTester tester) async {
    final BoxVsHandController k = await _pump(tester);
    await _tap(tester, find.text(BvhLabels.nextStep));
    expect(k.step, BvhStep.bestCase);
    expect(find.text('Best case: a 2x2 phone'), findsOneWidget);
    expect(
      find.textContaining('5,765 Mbps  31% of the box', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining(BvhLabels.sameCeiling), findsOneWidget);

    await _tap(tester, find.text(BvhLabels.nextStep));
    expect(k.step, BvhStep.atDistance);
    expect(find.text('At 5 m on a 320 MHz channel'), findsOneWidget);
    expect(
      find.textContaining('2,306 Mbps  12% of the box', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('MCS 7'), findsWidgets);
    expect(find.textContaining('favorable estimate'), findsOneWidget);
    final FilledButton next = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(BvhLabels.nextStep),
        matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
      ),
    );
    expect(next.onPressed, isNull, reason: 'disabled on the last step');

    await _tap(tester, find.text(BvhLabels.previous));
    expect(k.step, BvhStep.bestCase);
    await _tap(tester, find.text(BvhLabels.previous));
    expect(k.step, BvhStep.box);
    final TextButton back = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(BvhLabels.previous),
        matching: find.byWidgetPredicate((Widget w) => w is TextButton),
      ),
    );
    expect(back.onPressed, isNull, reason: 'disabled on the first step');
  });

  testWidgets('the client control: laptop matches the phone, the 4-stream '
      'reference still stops at one link', (WidgetTester tester) async {
    final BoxVsHandController k = await _pump(tester);
    k.setStep(BvhStep.bestCase);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Laptop'));
    expect(k.client, BvhClient.laptop2x2);
    expect(find.text('Best case: a 2x2 laptop'), findsOneWidget);
    expect(
      find.textContaining('5,765 Mbps  31% of the box', findRichText: true),
      findsOneWidget,
    );
    await _tap(tester, find.text('4-stream'));
    expect(
      find.textContaining('11,529 Mbps  62% of the box', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining(BvhLabels.sameCeiling), findsNothing);
  });

  testWidgets('far away on a wide channel says No link in words', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(tester);
    k
      ..setStep(BvhStep.atDistance)
      ..setDistance(60);
    await tester.pumpAndSettle();
    expect(find.textContaining('No link', findRichText: true), findsOneWidget);
    expect(find.textContaining('below MCS 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 20 m a 160 MHz channel beats 320 MHz', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(tester);
    k
      ..setStep(BvhStep.atDistance)
      ..setDistance(20);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('231 Mbps  1% of the box', findRichText: true),
      findsOneWidget,
    );
    await _tap(tester, find.text('160'));
    expect(k.widthMHz, 160);
    expect(
      find.textContaining('346 Mbps  2% of the box', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('imperial units follow the app setting', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(tester);
    k
      ..setStep(BvhStep.atDistance)
      ..setUnits(UnitSystem.imperial);
    await tester.pumpAndSettle();
    expect(find.text('At 16 ft on a 320 MHz channel'), findsOneWidget);
  });

  testWidgets('reduced motion: a new bar jumps to its length', (
    WidgetTester tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final BoxVsHandController k = await _pump(tester);
    k.nextStep();
    await tester.pump();
    final Iterable<TweenAnimationBuilder<double>> tweens = tester
        .widgetList<TweenAnimationBuilder<double>>(
          find.byType(TweenAnimationBuilder<double>),
        );
    expect(tweens, isNotEmpty);
    for (final TweenAnimationBuilder<double> t in tweens) {
      expect(t.duration, Duration.zero);
    }
  });

  testWidgets('with motion on, a new bar shrinks from the bar above it', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(tester);
    k.nextStep();
    await tester.pump();
    final TweenAnimationBuilder<double> t = tester
        .widget<TweenAnimationBuilder<double>>(
          find.byType(TweenAnimationBuilder<double>),
        );
    expect(t.duration, kBvhShrinkDuration);
    expect(t.tween.begin, 1);
    expect(t.tween.end, closeTo(5764.7 / 18656, 1e-4));
    await tester.pumpAndSettle();
  });

  testWidgets('the explainer opens the three tools whose math it reuses', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    for (final (String label, String page) in <(String, String)>[
      ('Open Throughput Calculator', 'TPUT'),
      ('Open MCS Index', 'MCSI'),
      ('Open Rate vs Range', 'RVR'),
    ]) {
      await _tap(tester, find.text(label));
      expect(find.text(page), findsOneWidget);
      Navigator.of(tester.element(find.text(page))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('no product names anywhere on screen', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    k.setStep(BvhStep.atDistance);
    await tester.pumpAndSettle();
    expect(
      _allText(tester),
      isNot(matches(RegExp('TP-Link|Archer|iPhone|Pixel|Apple|Google|Galaxy'))),
    );
  });

  testWidgets('the copy payload carries all three numbers', (
    WidgetTester tester,
  ) async {
    final BoxVsHandController k = await _pump(tester);
    final String t = k.copyText();
    expect(t, contains('18,656 Mbps'));
    expect(t, contains('5,765 Mbps'));
    expect(t, contains('2,306 Mbps'));
    expect(t, contains('favorable estimate'));
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(BoxVsHandStage), findsOneWidget);
    expect(find.byType(BoxVsHandControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BoxVsHandStage),
        matching: find.byType(BoxVsHandControls),
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
      const Size(768, 1024),
      const Size(1280, 900),
    ]) {
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly '
          'at every step and client', (WidgetTester tester) async {
        final BoxVsHandController k = await _pump(
          tester,
          theme: theme(),
          size: size,
        );
        for (final BvhStep s in BvhStep.values) {
          for (final BvhClient c in BvhClient.values) {
            k
              ..setStep(s)
              ..setClient(c);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$s $c');
          }
        }
      });
    }
  }
}
