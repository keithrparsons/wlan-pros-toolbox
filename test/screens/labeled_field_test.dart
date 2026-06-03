// Tests for the shared LabeledField SR-association primitive (Vera FIX 1) and
// the GL-003 §8.3 keyboard focus ring at the theme level (Vera FIX 2).
//
// FIX 1 — every tool input must announce its purpose to VoiceOver / TalkBack.
//   GL-003 §8.4 puts the label ABOVE the field (no in-field labelText), so the
//   field's purpose is carried by a Semantics(label:, textField: true) wrapper.
//   This test asserts a representative field exposes that label in the
//   semantics tree and is flagged as a text field, AND that the visible label
//   is NOT double-announced as standalone text.
//
// FIX 2 — the FilledButton / ChoiceChip keyboard-focus border resolves to the
//   §8.3 treatment: 2px solid primary (lime), not Material's focusColor overlay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/labeled_field.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

void main() {
  group('LabeledField — SR association (FIX 1)', () {
    testWidgets('field is announced with its label and as a text field',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: LabeledField(
              label: 'Host or IP',
              field: TextField(controller: controller),
            ),
          ),
        ),
      );

      // The field is reachable by its programmatic label and carries the
      // textField semantics flag — exactly what VoiceOver / TalkBack announce
      // on focus.
      final Finder byLabel = find.bySemanticsLabel('Host or IP');

      // Exactly ONE node carries the label — the field. The visible §8.4 label
      // line is wrapped in ExcludeSemantics, so it must NOT contribute a second
      // 'Host or IP' node (no double-announcement to VoiceOver / TalkBack).
      expect(byLabel, findsOneWidget);

      // And that one node is announced as a text field, exactly what a screen
      // reader speaks on focus: "Host or IP, text field".
      expect(
        tester.getSemantics(byLabel),
        matchesSemantics(label: 'Host or IP', isTextField: true),
      );

      handle.dispose();
    });

    testWidgets('semanticLabel overrides the visible label for SR',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: LabeledField(
              label: 'dBm',
              hint: '(dBm)',
              semanticLabel: 'dBm in dBm',
              field: TextField(controller: controller),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('dBm in dBm'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('visible label text is rendered (no visual regression)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: LabeledField(
              label: 'Subnet or range',
              field: TextField(controller: TextEditingController()),
            ),
          ),
        ),
      );

      // The §8.4 label line still shows on screen.
      expect(find.text('Subnet or range'), findsOneWidget);
    });
  });

  group('§8.3 focus ring at theme level (FIX 2)', () {
    final ThemeData theme = AppTheme.dark();

    test('FilledButton resolves a 2px solid primary border on focus', () {
      final ButtonStyle? style = theme.filledButtonTheme.style;
      expect(style, isNotNull);

      final BorderSide? focused = style!.side
          ?.resolve(<WidgetState>{WidgetState.focused});
      expect(focused, isNotNull, reason: 'focused state must carry a ring');
      expect(focused!.color, AppColors.primary);
      expect(focused.width, 2);

      // Idle (unfocused) filled button carries no border — the fill is the
      // affordance.
      final BorderSide? idle = style.side?.resolve(<WidgetState>{});
      expect(idle, anyOf(isNull, equals(BorderSide.none)));
    });

    test('OutlinedButton thickens to the 2px primary ring on focus', () {
      final ButtonStyle? style = theme.outlinedButtonTheme.style;
      final BorderSide? focused = style!.side
          ?.resolve(<WidgetState>{WidgetState.focused});
      expect(focused!.color, AppColors.primary);
      expect(focused.width, 2);

      // Idle outline is the 1.5px lime, so focus is distinguishable.
      final BorderSide? idle = style.side?.resolve(<WidgetState>{});
      expect(idle!.color, AppColors.primary);
      expect(idle.width, 1.5);
    });

    test('TextButton resolves a 2px solid primary border on focus', () {
      final ButtonStyle? style = theme.textButtonTheme.style;
      final BorderSide? focused = style!.side
          ?.resolve(<WidgetState>{WidgetState.focused});
      expect(focused!.color, AppColors.primary);
      expect(focused.width, 2);
    });

    test('chipSide() resolves the 2px primary ring on focus', () {
      final WidgetStateBorderSide side = AppTheme.chipSide();

      final BorderSide? focused =
          side.resolve(<WidgetState>{WidgetState.focused});
      expect(focused!.color, AppColors.primary);
      expect(focused.width, 2);

      // Focus must win even when the chip is also selected.
      final BorderSide? focusedSelected = side.resolve(
        <WidgetState>{WidgetState.focused, WidgetState.selected},
      );
      expect(focusedSelected!.color, AppColors.primary);
      expect(focusedSelected.width, 2);

      // Unfocused-selected = 1px primary; unfocused-idle = 1px borderStrong.
      final BorderSide? selected =
          side.resolve(<WidgetState>{WidgetState.selected});
      expect(selected!.color, AppColors.primary);
      expect(selected.width, 1);

      final BorderSide? idle = side.resolve(<WidgetState>{});
      expect(idle!.color, AppColors.borderStrong);
      expect(idle.width, 1);
    });

    test('input focusedBorder already uses the matching 2px lime border', () {
      // Sanity: buttons/chips now match the input focus treatment (§8.4).
      final InputBorder? focused =
          theme.inputDecorationTheme.focusedBorder;
      expect(focused, isA<OutlineInputBorder>());
      expect(focused!.borderSide.color, AppColors.primary);
      expect(focused.borderSide.width, 2);
    });

    test('global focusColor overlay is cleared so the ring leads', () {
      expect(theme.focusColor, Colors.transparent);
    });
  });
}
