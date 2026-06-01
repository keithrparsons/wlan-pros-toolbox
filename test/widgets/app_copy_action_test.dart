// Widget tests for AppCopyAction — the shared "Copy results" AppBar affordance
// (GL-003 §8.16).
//
// Covers the contract §8.16 promises:
//   - enabled (textBuilder returns non-null): copies the expected text to the
//     clipboard on tap;
//   - confirmation: the glyph swaps copy_outlined → check, the Semantics label
//     flips to "Results copied", then both revert after the 1.5s window;
//   - disabled (textBuilder returns null): no clipboard write, control is not
//     focusable, Semantics keeps the idle label with the disabled flag;
//   - Semantics: idle label is "Copy results", button role exposed.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String? Function() textBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Results'),
          actions: <Widget>[AppCopyAction(textBuilder: textBuilder)],
        ),
      ),
    ),
  );
}

void main() {
  group('AppCopyAction', () {
    // Capture clipboard writes without touching the real platform clipboard.
    final List<String> clipboardWrites = <String>[];

    setUp(() {
      clipboardWrites.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              final Map<dynamic, dynamic> args = call.arguments as Map;
              clipboardWrites.add(args['text'] as String);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('enabled: tap copies the builder text to the clipboard', (
      tester,
    ) async {
      await _pump(tester, textBuilder: () => 'IP\tName\n10.0.0.1\trouter');

      await tester.tap(find.byType(AppCopyAction));
      await tester.pump();

      expect(clipboardWrites, <String>['IP\tName\n10.0.0.1\trouter']);

      // Drain the 1.5s confirm timer so the test ends clean.
      await tester.pump(const Duration(milliseconds: 1500));
    });

    testWidgets(
      'confirmation: glyph swaps to check, label flips, then reverts',
      (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pump(tester, textBuilder: () => 'payload');

        // Idle state — copy glyph, "Copy results" label.
        expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
        expect(find.byIcon(Icons.check), findsNothing);
        SemanticsNode node = tester.getSemantics(find.byType(AppCopyAction));
        expect(node.label, 'Copy results');

        await tester.tap(find.byType(AppCopyAction));
        await tester.pump(); // process setState
        await tester.pump(const Duration(milliseconds: 150)); // settle the swap

        // Confirm window — check glyph, "Results copied" label.
        expect(find.byIcon(Icons.check), findsOneWidget);
        node = tester.getSemantics(find.byType(AppCopyAction));
        expect(node.label, 'Results copied');

        // After the 1.5s window it reverts to the idle glyph + label.
        await tester.pump(const Duration(milliseconds: 1500)); // fire revert timer
        await tester.pumpAndSettle(); // complete the cross-fade out
        expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
        expect(find.byIcon(Icons.check), findsNothing);
        node = tester.getSemantics(find.byType(AppCopyAction));
        expect(node.label, 'Copy results');

        handle.dispose();
      },
    );

    testWidgets('disabled: null builder copies nothing and is not focusable', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, textBuilder: () => null);

      // The glyph is present (disabled, not hidden — §8.16).
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);

      await tester.tap(find.byType(AppCopyAction));
      await tester.pump();

      // No clipboard write fired.
      expect(clipboardWrites, isEmpty);

      // Semantics keeps the idle label and is NOT marked enabled (disabled
      // flag set), and is not actionable as a tap target.
      expect(
        tester.getSemantics(find.byType(AppCopyAction)),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          label: 'Copy results',
        ),
        reason: 'disabled control keeps its label but is not enabled',
      );

      handle.dispose();
    });

    testWidgets('exposes the button role via Semantics', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, textBuilder: () => 'payload');

      expect(
        tester.getSemantics(find.byType(AppCopyAction)),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Copy results',
        ),
      );

      handle.dispose();
      await tester.pump(const Duration(milliseconds: 1500));
    });
  });
}
