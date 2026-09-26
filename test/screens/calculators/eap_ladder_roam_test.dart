// Widget and presenter tests for the Roam mode of the 802.1X and EAP Ladder
// (spec 21b). The original spec 21 tests are unchanged in
// eap_ladder_screen_test.dart and eap_ladder_presenter_test.dart; these add
// the Mode toggle, the four lanes, the roam methods, the timeline bar, and
// the presenter layout for every roam method.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1280,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: true,
        ),
        child: const EapLadderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EapLadderController _controller(WidgetTester tester) =>
    tester.widget<EapLadderStage>(find.byType(EapLadderStage)).controller;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Mode toggle switches to Roam and back', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    expect(c.mode, LadderMode.authenticate);
    expect(find.text('Authenticate'), findsOneWidget);
    // No Join option: joining is its own tool.
    expect(find.text('Join'), findsNothing);
    await _tap(tester, find.text('Roam'));
    expect(c.mode, LadderMode.roam);
    expect(find.byType(JoinRoamStage), findsOneWidget);
    expect(find.text('Current AP'), findsOneWidget);
    expect(find.text('Target AP'), findsOneWidget);
    expect(find.text('RADIUS server'), findsOneWidget);
    expect(find.byKey(JoinRoamStage.timelineKey), findsOneWidget);
    // Roam has no channel strip; that belongs to joining.
    expect(find.byKey(JoinRoamStage.stripKey), findsNothing);
    // Back to the original ladder, fresh.
    await _tap(tester, find.text('Authenticate'));
    expect(c.mode, LadderMode.authenticate);
    expect(find.byType(JoinRoamStage), findsNothing);
    await _tap(tester, find.text('Step'));
    expect(find.text('Step 1 of 27'), findsOneWidget);
  });

  testWidgets('roam methods: FT over the DS shows the wire hop between APs; '
      'caching drops the RADIUS lane', (WidgetTester tester) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    c.mode = LadderMode.roam;
    c.jrConfig = c.jrConfig.copyWith(roamMethod: JrRoamMethod.ftOverDs);
    c.showAll();
    await tester.pumpAndSettle();
    expect(find.text('FT Action: Request'), findsOneWidget);
    expect(find.text('FT Request, forwarded'), findsOneWidget);
    // PMF optional by default: the FT Action frames carry the shield.
    expect(find.byIcon(Icons.shield_rounded), findsWidgets);
    expect(find.text('RADIUS server'), findsNothing);
    expect(find.textContaining('single capture'), findsOneWidget);
    c.jrConfig = c.jrConfig.copyWith(roamMethod: JrRoamMethod.okc);
    await tester.pumpAndSettle();
    expect(find.textContaining('vendor extension, not IEEE'), findsWidgets);
    // The skipped list says the scan is the same for every method.
    expect(find.textContaining('Not the scan'), findsOneWidget);
  });

  testWidgets('tapping the Reassociation Request shows the current AP', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    c.mode = LadderMode.roam;
    c.showAll();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Reassociation Request').first);
    expect(c.captionJr!.label, 'Reassociation Request');
    expect(find.text('Current AP address'), findsOneWidget);
  });

  test('copy text in Roam mode', () {
    final EapLadderController c = EapLadderController(
      mode: LadderMode.roam,
      initialJr: const JrConfig(roamMethod: JrRoamMethod.ftOverAir),
    );
    addTearDown(c.dispose);
    final String text = c.copyText();
    expect(text, startsWith('802.1X and EAP Ladder, Roam'));
    expect(text, contains('Target AP'));
    expect(text, contains('Key handshake:'));
    expect(text, contains('Skipped versus full 802.1X'));
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
      testWidgets('Roam at $w px, $themeName, no sideways scroll', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          width: w,
          height: 844,
          theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
        );
        final EapLadderController c = _controller(tester);
        for (final JrRoamMethod r in JrRoamMethod.values) {
          c.mode = LadderMode.roam;
          c.jrConfig = c.jrConfig.copyWith(roamMethod: r);
          c.showAll();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$r');
          for (final Scrollable s in tester.widgetList<Scrollable>(
            find.byType(Scrollable),
          )) {
            expect(s.axisDirection, AxisDirection.down);
          }
        }
      });
    }
  }

  group('presenter', () {
    Future<EapLadderController> present(
      WidgetTester tester, {
      required Size window,
      ThemeData? theme,
    }) async {
      setWindow(tester, window);
      installFakeWindow();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.dark(),
          home: const EapLadderScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      expect(find.byType(PresenterLayout), findsOneWidget);
      return tester
          .widget<EapLadderStage>(find.byType(EapLadderStage).last)
          .controller;
    }

    List<ScrollableState> pageScrollsBesidesLadder(WidgetTester tester) {
      final Set<ScrollableState> ladder = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byKey(JoinRoamStage.ladderScrollKey),
              matching: find.byType(Scrollable),
            ),
          )
          .toSet();
      return pageScrollables(
        tester,
      ).where((ScrollableState s) => !ladder.contains(s)).toList();
    }

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size window in const <Size>[
        Size(1920, 1080),
        Size(1440, 900),
        Size(1470, 923),
      ]) {
        for (final JrRoamMethod r in JrRoamMethod.values) {
          testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
              'Roam ${r.name}: fits with no overflow and no page scroll', (
            WidgetTester tester,
          ) async {
            final EapLadderController c = await present(
              tester,
              window: window,
              theme: theme(),
            );
            c.mode = LadderMode.roam;
            c.jrConfig = c.jrConfig.copyWith(roamMethod: r);
            for (int i = 0; i < c.length * 2 ~/ 3; i++) {
              c.step();
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
            expect(pageScrollsBesidesLadder(tester), isEmpty);
            expect(controlsOverflow(tester), 0);
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
          });
        }
      }
    }

    testWidgets('Roam: Space plays, Right steps, R resets, Up and Down change '
        'the certificate size', (WidgetTester tester) async {
      final EapLadderController c = await present(
        tester,
        window: const Size(1920, 1080),
      );
      c.mode = LadderMode.roam;
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(c.shown, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      expect(c.shown, greaterThan(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(c.shown, 0);
      final int frags = c.jrConfig.certFragments;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.jrConfig.certFragments, frags + 1);
      // FT sends no certificate: the size keys do nothing.
      c.jrConfig = c.jrConfig.copyWith(roamMethod: JrRoamMethod.ftOverAir);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.jrConfig.certFragments, frags + 1);
      expect(tester.takeException(), isNull);
    });
  });
}
