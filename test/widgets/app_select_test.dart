// Widget tests for AppSelect<T> — the canonical App-Mode single-choice
// selector (GL-003 §8.14).
//
// Covers the states the component contract promises:
//   - renders the current selection's display label in the closed control;
//   - opening the menu surfaces every option;
//   - choosing an option fires onChanged with the chosen value (and not the
//     current value);
//   - disabled does not fire onChanged;
//   - error renders its message in the helper slot (never color-only — the
//     paired text is asserted here).
//
// Wrapped in a phone-sized viewport (mirrors test/widget_test.dart
// _withViewport) so the bordered control + menu never logs a RenderFlex
// overflow at phone width.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_select.dart';

enum _Sample { alpha, beta, gamma }

const List<AppSelectItem<_Sample>> _items = [
  (_Sample.alpha, 'Alpha'),
  (_Sample.beta, 'Beta'),
  (_Sample.gamma, 'Gamma'),
];

Future<void> _pump(
  WidgetTester tester, {
  required _Sample value,
  required ValueChanged<_Sample> onChanged,
  bool enabled = true,
  String? errorText,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: AppSelect<_Sample>(
            value: value,
            items: _items,
            enabled: enabled,
            errorText: errorText,
            semanticLabel: 'Sample',
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AppSelect<T>', () {
    testWidgets('renders the current selection label in the closed control',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await _pump(tester, value: _Sample.beta, onChanged: (_) {});
        // The selectedItemBuilder paints the closed value; "Beta" is visible.
        expect(find.text('Beta'), findsOneWidget);
      });
    });

    testWidgets('opening the menu surfaces every option', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await _pump(tester, value: _Sample.alpha, onChanged: (_) {});

        await tester.tap(find.byType(AppSelect<_Sample>));
        await tester.pumpAndSettle();

        // All three labels are present once the menu is open.
        expect(find.text('Alpha'), findsWidgets);
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Gamma'), findsOneWidget);
      });
    });

    testWidgets('selecting an option fires onChanged with the chosen value',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        _Sample? picked;
        await _pump(
          tester,
          value: _Sample.alpha,
          onChanged: (v) => picked = v,
        );

        await tester.tap(find.byType(AppSelect<_Sample>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gamma').last);
        await tester.pumpAndSettle();

        expect(picked, _Sample.gamma);
      });
    });

    testWidgets('disabled control does not fire onChanged', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        bool fired = false;
        await _pump(
          tester,
          value: _Sample.alpha,
          enabled: false,
          onChanged: (_) => fired = true,
        );

        await tester.tap(find.byType(AppSelect<_Sample>));
        await tester.pumpAndSettle();

        // No menu opens, nothing fires.
        expect(find.text('Gamma'), findsNothing);
        expect(fired, isFalse);
      });
    });

    testWidgets('error renders its message text in the helper slot',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await _pump(
          tester,
          value: _Sample.alpha,
          errorText: 'Pick one',
          onChanged: (_) {},
        );

        // §8.13 rule 2 — the verdict is carried by text, not color alone.
        expect(find.text('Pick one'), findsOneWidget);
      });
    });

    testWidgets('exposes the current selection via Semantics.value',
        (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pump(tester, value: _Sample.beta, onChanged: (_) {});

        // The control announces its label and current value for SR users.
        final SemanticsNode node = tester.getSemantics(
          find.byType(AppSelect<_Sample>),
        );
        expect(node.value, 'Beta');
        expect(node.label, contains('Sample'));

        handle.dispose();
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart _withViewport.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
