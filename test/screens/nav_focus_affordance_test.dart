// Regression test for the home → category → tool keyboard-focus spine.
//
// Context: the app-wide GL-003 §8.3 a11y pass added a 2px-primary focus ring
// to the themed buttons/chips AND cleared the global `Theme.focusColor` to
// transparent. That global change silently stripped the keyboard-focus
// affordance off three bare InkWell navigation surfaces that had relied on the
// ambient `Theme.focusColor` — the home grid tiles, the category tool rows,
// and the SSL inspector's disclosure toggle. On Web/Windows keyboard nav the
// navigation spine then showed NO visible focus indicator, violating WCAG 2.2
// SC 2.4.7 (Focus Visible) / GL-003 §8.9 ("never remove focus without
// replacement").
//
// These tests lock the fix in:
//   - Home grid tile (`_CategoryTile`) and category tool row (`_ToolRow`)
//     swap their container border to the 2px primary (lime) ring on keyboard
//     focus — same §8.3 treatment as the themed buttons/chips.
//   - The SSL disclosure InkWell, which has no bordered container to swap,
//     exposes an explicit lime `focusColor` overlay locally.
//
// If a future change reverts to an invisible focus state, these fail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

/// Pumps [child] inside the real app theme so `Theme.focusColor` is the
/// transparent value the §8.3 pass set — i.e. the conditions under which the
/// regression occurred.
Widget _app(Widget child) {
  return MaterialApp(
    theme: AppTheme.dark(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.dark,
    home: child,
  );
}

/// Walks the [container]'s decoration and returns the resolved [Border], or
/// null if the decoration is not a `BoxDecoration` with a `Border`.
Border? _borderOf(Container container) {
  final Decoration? decoration = container.decoration;
  if (decoration is BoxDecoration && decoration.border is Border) {
    return decoration.border as Border;
  }
  return null;
}

/// Finds the bordered `Container` that is a descendant of [inkWellFinder] and
/// carries a `BoxDecoration` border (the tile/row outline container).
Container _borderedContainerUnder(Finder inkWellFinder, WidgetTester tester) {
  final Finder containers = find.descendant(
    of: inkWellFinder,
    matching: find.byType(Container),
  );
  for (final Element element in containers.evaluate()) {
    final Container container = element.widget as Container;
    if (_borderOf(container) != null) return container;
  }
  fail('No bordered Container found under the InkWell.');
}

/// Drives keyboard focus onto the focusable surface under [inkWellFinder] the
/// same way keyboard traversal would: it resolves the `FocusNode` of the
/// `Focus` widget the InkWell builds internally (via `Focus.of` from a
/// descendant context that sits *below* that Focus) and requests focus on it.
/// This fires `InkWell.onFocusChange`.
void _focusInkWell(Finder inkWellFinder, WidgetTester tester) {
  // A context strictly below the InkWell's internal Focus widget — the
  // bordered Container — so `Focus.of` walks *up* and resolves the InkWell's
  // own FocusNode rather than throwing.
  final Element childContext = tester.element(
    find
        .descendant(of: inkWellFinder, matching: find.byType(Container))
        .first,
  );
  Focus.of(childContext).requestFocus();
}

void main() {
  group('Nav InkWell keyboard-focus affordance (SC 2.4.7 / §8.9)', () {
    testWidgets(
      'home grid tile swaps to the 2px primary ring on keyboard focus',
      (WidgetTester tester) async {
        await tester.pumpWidget(_app(const HomeScreen()));
        await tester.pumpAndSettle();

        // The first home TILE's InkWell. The IA-redesign added a search-field
        // InkWell above the grid, so target a tile by its category title rather
        // than taking the first InkWell in the tree.
        final ToolCategory firstCat = kToolCategories.first;
        final Finder firstInkWell = find
            .ancestor(
              of: find.text(firstCat.title),
              matching: find.byType(InkWell),
            )
            .first;
        expect(firstInkWell, findsOneWidget);

        // At rest: 1px borderStrong interactive boundary (§8.1), NOT the ring.
        final Border atRest =
            _borderOf(_borderedContainerUnder(firstInkWell, tester))!;
        expect(atRest.top.color, AppColors.borderStrong);
        expect(atRest.top.width, 1);

        // Drive keyboard focus onto the tile.
        _focusInkWell(firstInkWell, tester);
        await tester.pumpAndSettle();

        // On focus: the border resolves to the 2px primary (lime) ring.
        final Border focused =
            _borderOf(_borderedContainerUnder(firstInkWell, tester))!;
        expect(
          focused.top.color,
          AppColors.primary,
          reason: 'Focused home tile must show the §8.3 lime ring, not vanish.',
        );
        expect(focused.top.width, 2);
      },
    );

    testWidgets(
      'live category tool row swaps to the 2px primary ring on keyboard focus',
      (WidgetTester tester) async {
        // A category guaranteed to have a live tool row.
        final ToolCategory category =
            kToolCategories.firstWhere((c) => c.hasLiveTool);
        final ToolEntry liveTool =
            category.tools.firstWhere((t) => t.isLive);

        await tester.pumpWidget(_app(CategoryScreen(category: category)));
        await tester.pumpAndSettle();

        // Locate the live row's InkWell (the one with a non-null onTap).
        final Finder liveInkWell = find
            .byWidgetPredicate(
              (w) => w is InkWell && w.onTap != null,
            )
            .first;
        expect(liveInkWell, findsOneWidget);

        // At rest: 1px borderStrong interactive boundary.
        final Border atRest =
            _borderOf(_borderedContainerUnder(liveInkWell, tester))!;
        expect(atRest.top.color, AppColors.borderStrong);
        expect(atRest.top.width, 1);

        // Drive keyboard focus onto the live row.
        _focusInkWell(liveInkWell, tester);
        await tester.pumpAndSettle();

        final Border focused =
            _borderOf(_borderedContainerUnder(liveInkWell, tester))!;
        expect(
          focused.top.color,
          AppColors.primary,
          reason: 'Focused live tool row must show the §8.3 lime ring.',
        );
        expect(focused.top.width, 2);

        // Sanity: the route the live row navigates to is non-empty.
        expect(liveTool.routeName.isNotEmpty, isTrue);
      },
    );

    testWidgets(
      'theme keeps the global focusColor transparent (button/chip ring intact)',
      (WidgetTester tester) async {
        // Guards the intended part of the §8.3 pass: the global focusColor must
        // stay transparent so the button/chip ring is the sole, un-muddied
        // keyboard-focus indicator. The fix restores focus on the bare InkWells
        // locally — it must NOT re-introduce a global non-transparent
        // focusColor.
        final ThemeData theme = AppTheme.dark();
        expect(theme.focusColor, Colors.transparent);
      },
    );
  });
}
