// Widget tests for the WLAN Pros Toolbox app shell.
//
// Coverage targets (post-Vera-gate fix pass, 2026-05-29):
// - Smoke: app mounts with the correct app-bar title.
// - Category grid: all 8 category titles render; item count equals catalog
//   length. (Vera F-11.)
// - Semantics: each tile exposes a single curated label; no duplicate
//   child-Text semantics leak through. (Vera F-04.)
// - Responsive: 375x900 phone viewport renders the home grid without
//   RenderFlex overflow. (Vera F-01.)

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/main.dart';

void main() {
  testWidgets('Home screen mounts with app title', (tester) async {
    await _pumpApp(tester);

    expect(find.text('WLAN Pros Toolbox'), findsOneWidget);
  });

  testWidgets('Home grid renders every category from the catalog', (
    tester,
  ) async {
    await _pumpApp(tester);

    // All 8 titles render, one tile each. (Vera F-11.)
    for (final ToolCategory cat in kToolCategories) {
      expect(
        find.text(cat.title),
        findsOneWidget,
        reason: 'expected one tile for "${cat.title}"',
      );
    }

    // Item count matches catalog length — guards against the grid silently
    // dropping or duplicating tiles after a layout change. (Vera F-11.)
    final Finder grid = find.byType(GridView);
    expect(grid, findsOneWidget);
    final GridView view = tester.widget<GridView>(grid);
    final SliverChildDelegate delegate = view.childrenDelegate;
    expect(delegate, isA<SliverChildBuilderDelegate>());
    expect(
      (delegate as SliverChildBuilderDelegate).childCount,
      kToolCategories.length,
    );
  });

  testWidgets(
    'Home tiles expose the curated semantic label only (no duplicates)',
    (tester) async {
      // Vera F-04 — the outer Semantics on each tile must be marked
      // `excludeSemantics: true` so child Text widgets do NOT add a second
      // (and third) reading of the same content.
      await _withViewport(tester, const Size(800, 1200), () async {
        final SemanticsHandle handle = tester.ensureSemantics();

        await _pumpApp(tester);

        for (final ToolCategory cat in kToolCategories) {
          final String expected =
              '${cat.title}. '
              '${cat.hasLiveTool ? "" : "Coming soon. "}'
              '${cat.summary}';

          // The curated label must appear exactly once across the semantic
          // tree — once per tile, with no second copy bleeding from the
          // child Texts.
          expect(
            find.bySemanticsLabel(expected),
            findsOneWidget,
            reason: 'tile "${cat.title}" must expose a single curated label',
          );

          // Confirm the raw child Texts no longer surface as their own
          // semantic nodes — `bySemanticsLabel` would find them if they did.
          expect(
            find.bySemanticsLabel(cat.title),
            findsNothing,
            reason:
                'child Text "${cat.title}" should be excluded from semantics',
          );
          expect(
            find.bySemanticsLabel(cat.summary),
            findsNothing,
            reason:
                'child Text "${cat.summary}" should be excluded from semantics',
          );
        }

        handle.dispose();
      });
    },
  );

  testWidgets(
    'Home grid fits within a 375x900 iPhone viewport without overflow',
    (tester) async {
      // Vera F-01 — at 375pt iPhone width the 2-up grid previously overflowed
      // every tile with a 2-line summary. The fix drops childAspectRatio to
      // 0.85 below the phone breakpoint, restoring vertical room for the
      // icon row + 2-line H3 title + 2-line caption.
      await _withViewport(tester, const Size(375, 900), () async {
        final List<Object> overflowExceptions = <Object>[];
        final FlutterExceptionHandler? previous = FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exception.toString().contains('RenderFlex overflowed') ||
              details.exception.toString().contains('overflowed by')) {
            overflowExceptions.add(details.exception);
          }
        };
        addTearDown(() => FlutterError.onError = previous);

        await _pumpApp(tester);

        expect(
          overflowExceptions,
          isEmpty,
          reason:
              'Home grid must not log a RenderFlex overflow at 375x900 — '
              'got: ${overflowExceptions.map((Object e) => e.toString()).join("; ")}',
        );
      });
    },
  );
}

/// Helper — pump the real `ToolboxApp` and let async font loads settle.
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ToolboxApp());
  await tester.pumpAndSettle();
}

/// Helper — run [body] with the test view sized to [size], then restore.
///
/// Uses the post-multi-window API (`tester.view.physicalSize` /
/// `resetPhysicalSize`) introduced after Flutter 3.9, instead of the
/// deprecated `tester.binding.window` accessors.
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
