// Widget tests for AppToggle<T> — the canonical App-Mode 2–3 option segmented
// selector (GL-003 §8.14.1). Mirrors app_select_test.dart.
//
// Covers the contract the component promises:
//   - renders its label and every segment label;
//   - tapping an unselected segment fires onChanged with that value (and never
//     re-fires the already-selected value);
//   - the selected segment exposes Semantics.selected (never color-only —
//     §8.14.1 / §8.13 rule 2);
//   - a disabled control does not fire onChanged.
//
// Wrapped in a phone-sized viewport (mirrors test/widgets/app_select_test.dart
// _withViewport) so the bordered track never logs a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_toggle.dart';

enum _Unit { ft, m }

const List<AppToggleItem<_Unit>> _items = [(_Unit.ft, 'ft'), (_Unit.m, 'm')];

Future<void> _pump(
  WidgetTester tester, {
  required _Unit value,
  required ValueChanged<_Unit> onChanged,
  bool enabled = true,
  String? label = 'Unit',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: AppToggle<_Unit>(
            value: value,
            items: _items,
            enabled: enabled,
            label: label,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AppToggle<T>', () {
    testWidgets('renders the label and every segment label', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await _pump(tester, value: _Unit.ft, onChanged: (_) {});
        expect(find.text('Unit'), findsOneWidget);
        expect(find.text('ft'), findsOneWidget);
        expect(find.text('m'), findsOneWidget);
      });
    });

    testWidgets(
      'tapping an unselected segment fires onChanged with its value',
      (tester) async {
        await _withViewport(tester, const Size(375, 900), () async {
          _Unit? picked;
          await _pump(tester, value: _Unit.ft, onChanged: (v) => picked = v);

          await tester.tap(find.text('m'));
          await tester.pumpAndSettle();

          expect(picked, _Unit.m);
        });
      },
    );

    testWidgets(
      'tapping the already-selected segment does not fire onChanged',
      (tester) async {
        await _withViewport(tester, const Size(375, 900), () async {
          bool fired = false;
          await _pump(tester, value: _Unit.ft, onChanged: (_) => fired = true);

          await tester.tap(find.text('ft'));
          await tester.pumpAndSettle();

          expect(fired, isFalse);
        });
      },
    );

    testWidgets('exposes the selected segment via Semantics.selected', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await _pump(tester, value: _Unit.m, onChanged: (_) {});

        // §8.14.1: selection is exposed via Semantics.selected and each segment
        // is announced in a mutually-exclusive group. isSemantics is the lenient
        // non-deprecated matcher (checks only the properties named here).
        expect(
          tester.getSemantics(find.bySemanticsLabel('m')),
          isSemantics(
            isSelected: true,
            isButton: true,
            isInMutuallyExclusiveGroup: true,
            hasEnabledState: true,
            isEnabled: true,
            label: 'm',
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('ft')),
          isSemantics(
            isSelected: false,
            isButton: true,
            isInMutuallyExclusiveGroup: true,
            hasEnabledState: true,
            isEnabled: true,
            label: 'ft',
          ),
        );

        handle.dispose();
      });
    });

    testWidgets('disabled control does not fire onChanged', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        bool fired = false;
        await _pump(
          tester,
          value: _Unit.ft,
          enabled: false,
          onChanged: (_) => fired = true,
        );

        await tester.tap(find.text('m'));
        await tester.pumpAndSettle();

        expect(fired, isFalse);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widgets/app_select_test.dart _withViewport.
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
