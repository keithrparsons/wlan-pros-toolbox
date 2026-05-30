// Widget tests for the WLAN Pros Toolbox app shell.
//
// Coverage targets (post-Vera-regate fix pass 2, 2026-05-29):
// - Smoke: app mounts with the correct app-bar title.
// - Category grid: all 8 category titles render; item count equals catalog
//   length. (Vera F-11.)
// - Semantics: each tile exposes a single curated label; no duplicate
//   child-Text semantics leak through. (Vera F-04.)
// - Responsive: 375x900 phone viewport renders the home grid without
//   RenderFlex overflow. (Vera F-01.)
// - Focus hygiene: navigating Home → Category → Home leaves no tile with
//   primary focus. (Vera F-NEW-02.)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/main.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/noise_floor_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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
    'No tile retains focus after navigating Home → Category → Home',
    (tester) async {
      // Vera F-NEW-02 — the `initState` unfocus only fires on first build.
      // When the user pops back from a category, Flutter's focus traversal
      // can land on an unpredictable tile, painting the lime hover/focus
      // tint as if it were "selected". The fix chains an unfocus on the
      // Navigator.push().then(...) so home returns to its cold-start focus
      // state on every pop-back.
      await _withViewport(tester, const Size(800, 1200), () async {
        await _pumpApp(tester);

        // Force a tile into the focused state — this is the precondition
        // F-NEW-02 reproduces (a tile holds focus on the home tree, the
        // user navigates away and back, and focus persists on the tile).
        // We do it by walking the live Focus tree to the first Focus node
        // owned by a tile InkWell and requesting focus directly.
        final ToolCategory liveCat = kToolCategories.firstWhere(
          (ToolCategory c) => c.hasLiveTool,
        );

        FocusNode? tileFocusNode;
        void walk(FocusNode node) {
          if (tileFocusNode != null) return;
          final BuildContext? ctx = node.context;
          if (ctx != null &&
              ctx.findAncestorWidgetOfExactType<InkWell>() != null) {
            tileFocusNode = node;
            return;
          }
          for (final FocusNode child in node.children) {
            walk(child);
          }
        }

        walk(FocusManager.instance.rootScope);
        expect(
          tileFocusNode,
          isNotNull,
          reason: 'precondition: expected at least one tile-owned Focus node',
        );
        tileFocusNode!.requestFocus();
        await tester.pump();

        // Sanity check — primary focus is now inside a tile's InkWell.
        final FocusNode? pre = FocusManager.instance.primaryFocus;
        final BuildContext? preCtx = pre?.context;
        expect(
          preCtx != null &&
              preCtx.findAncestorWidgetOfExactType<InkWell>() != null,
          isTrue,
          reason: 'precondition: focus must be on a tile InkWell before nav',
        );

        // Navigate into the category by tapping the focused tile.
        await tester.tap(find.text(liveCat.title));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, liveCat.title), findsOneWidget);

        // Pop back to home.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        // Drain the Navigator.push().then(...) microtask.
        await tester.pumpAndSettle();

        // The defining symptom of F-NEW-02: a tile-level Focus node still
        // holds primary focus after pop-back, painting the lime tint on a
        // grid tile. After the fix, focus must have lifted off any tile.
        final FocusNode? primary = FocusManager.instance.primaryFocus;
        final BuildContext? focusedContext = primary?.context;
        final bool focusInsideTileInkWell = focusedContext != null &&
            focusedContext.findAncestorWidgetOfExactType<InkWell>() != null;
        expect(
          focusInsideTileInkWell,
          isFalse,
          reason:
              'After Home → Category → Home no grid tile should hold '
              'primary focus — found focus inside an InkWell: '
              '${primary?.debugLabel ?? primary?.toString() ?? "<none>"}',
        );
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
      await _expectNoOverflowAt(tester, const Size(375, 900));
    },
  );

  testWidgets(
    'Home grid fits within a 320x900 narrow-phone viewport without overflow',
    (tester) async {
      // Vera F-NEW-03 — iPhone SE 1st-gen at 320pt logical width previously
      // edge-overflowed by ~5px on tiles with 2-line summaries. The fix adds
      // a narrow-phone breakpoint that drops tile aspect to 0.75 below 360pt.
      await _expectNoOverflowAt(tester, const Size(320, 900));
    },
  );

  testWidgets(
    'Noise Floor screen renders in a 375x900 phone viewport',
    (tester) async {
      // Phone-viewport smoke for the calculator: it pumps, renders its result
      // rows, and shows the default 20 MHz thermal floor without overflow.
      await _withViewport(tester, const Size(375, 900), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const NoiseFloorScreen(),
          ),
        );
        await tester.pump();

        expect(find.text('Channel bandwidth'), findsOneWidget);
        expect(find.text('Rx noise floor'), findsOneWidget);
        // Default 20 MHz / NF 7 / 20°C → thermal -100.9 dBm.
        expect(find.text('-100.9'), findsOneWidget);
      });
    },
  );
}

/// Helper — pump the app at [size] and assert no `RenderFlex overflowed`
/// exception was logged. Shared by the 375pt and 320pt home-grid checks.
Future<void> _expectNoOverflowAt(WidgetTester tester, Size size) async {
  await _withViewport(tester, size, () async {
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
          'Home grid must not log a RenderFlex overflow at ${size.width.toInt()}'
          'x${size.height.toInt()} — '
          'got: ${overflowExceptions.map((Object e) => e.toString()).join("; ")}',
    );
  });
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
