// The shared failure marker (spec 42), drawn on the 802.1X and EAP Ladder
// stage from a hand-built sequence: the X on a failure message, the clock on
// a lost one, the "Stopped here" band held back until the last message, the
// caption lines, the worded screen-reader labels, and the status hue only on
// the marks. The faults themselves are tested in eap_ladder_break_it_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_failure.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<LadderMessage> _messages = <LadderMessage>[
  LadderMessage(
    from: LadderLane.client,
    to: LadderLane.ap,
    kind: LadderFrameKind.eapol,
    phase: LadderPhase.eapIdentity,
    label: 'EAP-Response / Identity',
    description: 'The client names itself.',
  ),
  LadderMessage(
    from: LadderLane.ap,
    to: LadderLane.radius,
    kind: LadderFrameKind.radius,
    phase: LadderPhase.eapIdentity,
    label: 'Access-Request',
    detail: 'no answer',
    description: 'Dropped by the server.',
    lost: true,
    waitMs: 3000,
  ),
  LadderMessage(
    from: LadderLane.ap,
    to: LadderLane.client,
    kind: LadderFrameKind.eapol,
    phase: LadderPhase.eapResult,
    label: 'EAP-Failure',
    description: 'The AP ends it.',
    failure: true,
  ),
];

Future<EapLadderController> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 844), disableAnimations: true),
        child: const EapLadderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final EapLadderController c = tester
      .widget<EapLadderStage>(find.byType(EapLadderStage))
      .controller;
  c.debugSequence = LadderSequence.forTest(
    const LadderConfig(),
    _messages,
    faultNote: 'The RADIUS server never answered.',
    helpDesk: 'Every user on this AP fails the same way.',
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    testWidgets('$name: marks appear only once their message is sent', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await _pump(tester, theme: theme());
      expect(find.byType(LadderFailureMark), findsNothing);
      expect(find.byType(LadderLostMark), findsNothing);
      // The band keeps its space but is not announced before it is reached.
      expect(find.bySemanticsLabel(RegExp('^Stopped here')), findsNothing);

      c.step();
      c.step();
      await tester.pumpAndSettle();
      expect(find.byType(LadderLostMark), findsOneWidget);
      expect(find.byType(LadderFailureMark), findsNothing);
      expect(find.textContaining('No answer: nothing comes back'), findsOne);
      expect(
        find.bySemanticsLabel(RegExp(r'Step 2 of 3.*No answer\.$')),
        findsOneWidget,
      );

      c.step();
      await tester.pumpAndSettle();
      expect(find.byType(LadderFailureMark), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Step 3 of 3.*Failure\.$')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Failure: this message refuses'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Stopped here. The RADIUS server never answered.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('What the help desk sees'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: status hue only on the marks, always with an icon', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await _pump(tester, theme: theme());
      c.showAll();
      await tester.pumpAndSettle();
      final Color danger = tester
          .element(find.byType(EapLadderStage))
          .colors
          .statusDanger;
      final Iterable<Icon> dangerIcons = tester
          .widgetList<Icon>(find.byType(Icon))
          .where((Icon i) => i.color == danger);
      expect(dangerIcons.map((Icon i) => i.icon).toSet(), <IconData>{
        kFailureIcon,
        kStoppedIcon,
      });
      final Iterable<Text> dangerText = tester
          .widgetList<Text>(find.byType(Text))
          .where((Text t) => t.style?.color == danger);
      expect(dangerText, isEmpty);
    });
  }

  testWidgets('phone width 360: no overflow with every mark on show', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _pump(
      tester,
      theme: AppTheme.dark(),
      width: 360,
    );
    c.showAll();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width 360, PEAP with no fault: the step gutter fits', (
    WidgetTester tester,
  ) async {
    // Regression: in v1.11.0 a lock and a two-digit step number overflowed
    // the gutter by a rounding hair at 360 px.
    tester.view.physicalSize = const Size(360 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(size: Size(360, 844), disableAnimations: true),
          child: EapLadderScreen(
            initial: LadderConfig(method: LadderMethod.peap),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<EapLadderStage>(find.byType(EapLadderStage))
        .controller
        .showAll();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
