// Widget tests for the Wi-Fi Classroom "802.1X and EAP Ladder" screen.
//
// The sequences are pinned in test/services/wifi_lab/eap_ladder_test.dart;
// these cover the screen contract: catalog and route registration beside the
// untouched 'eap-types' and 'frame-exchange' tools, the fresh state, Step,
// Back and the caption, Play and Pause, the milestones appearing, PSK with no
// RADIUS, disabled settings, the stage and controls as separate widgets, the
// copy text, and phone and desktop widths in both themes for EAP-TLS, PEAP
// and SAE with no sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  bool reduceMotion = true,
  LadderConfig? initial,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: reduceMotion,
        ),
        child: EapLadderScreen(initial: initial),
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

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );

void main() {
  test('catalog and route register eap-ladder in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kEapLadderToolId,
    );
    expect(e.title, '802.1X and EAP Ladder');
    expect(e.subgroup, 'Wi-Fi Classroom');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/eap-ladder');
    expect(AppRouter.routes.containsKey('/tools/eap-ladder'), isTrue);
    // The existing references are separate, untouched entries.
    for (final String id in <String>['eap-types', 'frame-exchange']) {
      expect(
        kToolCategories.any(
          (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == id),
        ),
        isTrue,
        reason: id,
      );
    }
  });

  testWidgets('fresh: nothing sent, Ready caption, Back and Reset disabled', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('802.1X and EAP Ladder'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    expect(_button(tester, 'Back').onPressed, isNull);
    expect(_button(tester, 'Reset').onPressed, isNull);
    expect(_controller(tester).shown, 0);
    // Stage and controls are separate widgets over one controller.
    expect(find.byType(EapLadderStage), findsOneWidget);
    expect(find.byType(EapLadderControls), findsOneWidget);
    expect(
      identical(
        _controller(tester),
        tester
            .widget<EapLadderControls>(find.byType(EapLadderControls))
            .controller,
      ),
      isTrue,
    );
    // Lanes and the reference wording from the EAP Types tool.
    expect(find.text('supplicant'), findsOneWidget);
    expect(find.text('authenticator'), findsOneWidget);
    expect(find.text('X.509 certs (both sides)'), findsOneWidget);
    expect(find.text('Keys available'), findsOneWidget); // legend only
  });

  testWidgets('Step sends messages, the caption follows, Back undoes', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder step = find.text('Step');
    await _tap(tester, step);
    expect(find.text('Step 1 of 27'), findsOneWidget);
    expect(find.text('Probe Request'), findsWidgets);
    expect(_controller(tester).current!.leg, LadderLeg.air);
    // The caption's leg chip, beside the readout row of the same name.
    expect(find.text('Over the air'), findsNWidgets(2));
    for (int i = 0; i < 7; i++) {
      await _tap(tester, step);
    }
    // Message 7 is the AP's EAP-Request/Identity... message 8 its response.
    expect(find.text('Step 8 of 27'), findsOneWidget);
    expect(_controller(tester).current!.label, 'EAP-Response / Identity');
    await _tap(tester, step);
    expect(_controller(tester).current!.label, 'Access-Request');
    expect(_controller(tester).current!.leg, LadderLeg.wire);
    expect(find.text('On the wire'), findsNWidgets(2));
    await _tap(tester, find.text('Back'));
    expect(find.text('Step 8 of 27'), findsOneWidget);
    await _tap(tester, find.text('Reset'));
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('milestone bands appear only once reached', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    final int keys = c.sequence.indexOfMilestone(LadderMilestone.keysAvailable);
    final String keyText = c.sequence.messages[keys].milestoneText!;
    // Held back: laid out for size, so the ladder does not jump, but hidden
    // and out of the semantics tree.
    expect(find.text(keyText), findsOneWidget);
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(
              of: find.text(keyText),
              matching: find.byType(Visibility),
            ),
          )
          .visible,
      isFalse,
    );
    expect(find.bySemanticsLabel(keyText), findsNothing);
    for (int i = 0; i <= keys; i++) {
      c.step();
    }
    await tester.pumpAndSettle();
    expect(c.current!.label, 'Access-Accept');
    // In the ladder band and in the caption.
    expect(find.text(keyText), findsNWidgets(2));
    expect(find.bySemanticsLabel(keyText), findsWidgets);
    await _tap(tester, find.text('Show all'));
    expect(c.atEnd, isTrue);
    expect(find.text('Play again'), findsOneWidget);
    expect(_button(tester, 'Step').onPressed, isNull);
    expect(
      find.textContaining('Traffic protected: data frames'),
      findsNWidgets(2),
    );
  });

  testWidgets('Play sends one message per beat and Pause stops', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: false);
    final EapLadderController c = _controller(tester);
    await tester.ensureVisible(find.text('Play'));
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(c.shown, 1);
    expect(c.playing, isTrue);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 950));
    expect(c.shown, greaterThanOrEqualTo(2));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    final int at = c.shown;
    await tester.pump(const Duration(seconds: 3));
    expect(c.shown, at);
    expect(c.playing, isFalse);
    await tester.pumpAndSettle();
  });

  testWidgets('PSK: no RADIUS lane, RADIUS settings disabled with a reason', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: const LadderConfig(method: LadderMethod.psk));
    expect(find.text('not used here'), findsOneWidget);
    expect(find.text('none (no RADIUS)'), findsOneWidget);
    expect(find.text('No RADIUS messages in this method.'), findsOneWidget);
    expect(find.text('No certificate is sent in this method.'), findsOneWidget);
    final List<Slider> sliders = tester
        .widgetList<Slider>(find.byType(Slider))
        .toList();
    expect(sliders.every((Slider s) => s.onChanged == null), isTrue);
    expect(find.textContaining('Only EAP-TTLS'), findsOneWidget);
  });

  testWidgets('changing method with the whole ladder shown keeps it shown', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    c.showAll();
    c.method = LadderMethod.peap;
    await tester.pumpAndSettle();
    expect(c.atEnd, isTrue);
    expect(c.sequence.length, 43);
    // Part way through, a new method starts again from the top.
    c.reset();
    c.step();
    c.method = LadderMethod.sae;
    await tester.pumpAndSettle();
    expect(c.shown, 0);
    // A timing change keeps the place.
    c.method = LadderMethod.eapTls;
    c.step();
    c.step();
    c.radiusRttMs = 80;
    expect(c.shown, 2);
  });

  test('copy text lists every message and the readouts', () {
    final EapLadderController c = EapLadderController(
      vsync: const TestVSync(),
      initial: const LadderConfig(method: LadderMethod.peap),
    );
    addTearDown(c.dispose);
    final String text = c.copyText();
    expect(text, contains('PEAP (MSCHAPv2), Full authentication'));
    expect(text, contains('1. Client -> AP (air) Probe Request'));
    expect(text, contains('(wire) Access-Accept'));
    expect(text, contains('RADIUS round trips: 8'));
    expect(text, contains('Keys available: the RADIUS server sent the PMK'));
    expect(text, isNot(contains('—')));
    expect(text, isNot(contains('802.1x')));
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
      for (final LadderConfig cfg in <LadderConfig>[
        const LadderConfig(certFragments: 3),
        const LadderConfig(method: LadderMethod.peap),
        const LadderConfig(method: LadderMethod.sae),
      ]) {
        testWidgets(
          '${cfg.method.label} at $w px, $themeName, no sideways scroll',
          (WidgetTester tester) async {
            await _pump(
              tester,
              width: w,
              theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
              initial: cfg,
            );
            await _tap(tester, find.text('Show all'));
            expect(tester.takeException(), isNull);
            for (final Scrollable s in tester.widgetList<Scrollable>(
              find.byType(Scrollable),
            )) {
              expect(s.axisDirection, AxisDirection.down);
            }
            expect(find.textContaining('NaN'), findsNothing);
          },
        );
      }
    }
  }
}
