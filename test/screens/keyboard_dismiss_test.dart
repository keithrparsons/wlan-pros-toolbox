// Tests for the app-wide keyboard-dismiss affordance (live-device bug,
// 2026-05-30).
//
// The iOS number pad (TextInputType.number / numberWithOptions without
// `signed`) renders no return/Done key, so `textInputAction: TextInputAction.done`
// on the RF calculators is inert and there was no other way to drop the
// keyboard — it covered the results on EIRP / Link Budget / Fresnel etc.
//
// The fix wraps the whole app (MaterialApp.builder in main.dart) in a
// translucent GestureDetector that unfocuses on any tap outside a text field.
// These tests reproduce that exact builder and assert:
//   1. a focused field loses focus when the user taps outside it, and
//   2. `HitTestBehavior.translucent` does NOT swallow the tap — a button beneath
//      the gesture region still fires (no regression to interactive widgets).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// Mirrors the `builder` wired into MaterialApp in `main.dart`. Kept here so the
/// test exercises the real dismissal idiom; if the builder in main.dart changes
/// shape, this test should be updated to match.
Widget _dismissOnTapOutside(BuildContext context, Widget? child) {
  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child,
  );
}

void main() {
  group('App-wide keyboard dismiss (2026-05-30 live-device bug)', () {
    testWidgets('tapping outside a focused field unfocuses it',
        (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      final FocusNode focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: _dismissOnTapOutside,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // A number-pad field: the keyboard type from the affected RF
                  // calculators, which renders no Done key on iOS.
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 200),
                  const Text('empty space below the field'),
                ],
              ),
            ),
          ),
        ),
      );

      // Focus the field — keyboard would be up on a real device.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue,
          reason: 'field should be focused after tapping it');

      // Tap the empty space well below the field.
      await tester.tap(find.text('empty space below the field'));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse,
          reason:
              'tapping outside the field must dismiss focus (and the keyboard)');
    });

    testWidgets(
        'translucent gesture does not swallow taps on widgets beneath it',
        (WidgetTester tester) async {
      bool buttonTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: _dismissOnTapOutside,
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => buttonTapped = true,
                child: const Text('Calculate'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Calculate'));
      await tester.pump();

      expect(buttonTapped, isTrue,
          reason:
              'HitTestBehavior.translucent must let the tap reach the button; '
              'the dismiss wrapper only adds unfocus, it does not block taps');
    });
  });
}
