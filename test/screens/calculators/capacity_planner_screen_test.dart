// Tests for the Capacity Planner screen.
//
// The screen is no longer a calculator. Keith retired the AP-count math (a
// single formula can't honestly model real capacity — GL-005 / the truthfulness
// audit) and replaced it with a read-only informational disclaimer. The tile and
// the /tools/capacity-planner route are kept so it still resolves where users
// expect, but there are NO inputs and NO computed result.
//
// These tests verify the disclaimer renders (heading + the three approved body
// paragraphs) and that the screen exposes no calculator inputs. Both Light and
// Dark themes pump cleanly (App Mode now ships both). Copy is asserted verbatim
// against the approved draft.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/capacity_planner_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

// The approved copy, verbatim — the screen must render this and not reword it.
const String _heading =
    'Capacity planning is a design problem, not a calculation.';
const String _para1Start =
    'Real Wi-Fi capacity depends on too many moving parts for any single '
    'formula:';
const String _para2Start =
    'A tool that squeezed all of that into a few input boxes would hand you a '
    'confident number that\'s wrong, which is worse than no number at all.';
const String _para3Start =
    'If you need a capacity plan you can trust, bring in a Wi-Fi professional';

void main() {
  group('CapacityPlannerScreen — informational disclaimer', () {
    testWidgets('renders the AppBar title, heading, and all three paragraphs', (
      tester,
    ) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // AppBar title preserved so the tile resolves where users expect.
        expect(find.text('Capacity Planner'), findsWidgets);

        // Heading rendered verbatim.
        expect(find.text(_heading), findsOneWidget);

        // The three approved body paragraphs. textContaining matches the full
        // paragraph by its opening clause (paragraphs render as single strings).
        expect(find.textContaining(_para1Start), findsOneWidget);
        expect(find.text(_para2Start), findsOneWidget);
        expect(find.textContaining(_para3Start), findsOneWidget);
      });
    });

    testWidgets('exposes NO calculator inputs (no text fields)', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // The calculator is gone: no input fields, and none of its former
        // field labels or result headline remain.
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Total users'), findsNothing);
        expect(find.text('Concurrent usage'), findsNothing);
        expect(find.text('AP max throughput'), findsNothing);
        expect(find.text('Recommended access points'), findsNothing);
      });
    });

    testWidgets('the heading is exposed as a semantic header', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // The heading must carry Semantics(header: true) for WCAG 2.2 SC 1.3.1.
        // The card's text merges into one semantics node (label spans the whole
        // card), so assert the isHeader flag directly rather than exact-matching
        // the label.
        final SemanticsNode node = tester.getSemantics(find.text(_heading));
        expect(
          node.getSemanticsData().flagsCollection.isHeader,
          isTrue,
          reason: 'Heading must carry Semantics(header: true) for SC 1.3.1.',
        );
      });
    });

    testWidgets('renders cleanly under the Light theme too', (tester) async {
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: const CapacityPlannerScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(_heading), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      });
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
/// Mirrors test/widget_test.dart `_withViewport`.
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
