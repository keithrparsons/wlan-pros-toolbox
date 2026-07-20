// Widget tests for [PdfViewerControlBar] — the enabled/disabled CONTRACT of the
// PDF viewer's page and zoom controls.
//
// WHY THIS FILE EXISTS (second Vera gate, 2026-07-20).
//
// The screen these controls live on cannot be exercised by `flutter test`: pdfx
// renders through native PDFKit, which is a no-op in the headless test engine,
// so the pager only exists under an integration test on a real device. Every
// assertion about these controls therefore lived in
// `integration_test/pdf_desktop_navigation_test.dart` — and that is precisely
// how the bug shipped.
//
// The finding: mutating `_canGoForward` to `=> true` left all 18 navigation
// tests GREEN. The one test named for the bound — "previous is DISABLED on page
// 1, next on the last page" — pumps the 64-page book, asserts on page 1, taps
// Next once, and asserts on page 2. It never visits page 64. The second half of
// its own name was never executed. (See [[feedback_tests_that_cannot_fail]].)
//
// A test that must first win a race against a native document load in order to
// check a pure boolean is the wrong instrument. The bar is now a public widget
// taking a [PdfViewerControlState], so every (page, count, state) combination
// is pumpable directly — no document, no engine, no race, and the last page is
// reachable by typing the number 64.
//
// WHAT IS ASSERTED, and why it is the semantics node and not just the callback:
// the defect is an ACCESSIBILITY defect. A disabled-looking grey glyph that
// still reports `enabled: true` to assistive tech is the actual harm — the
// screen-reader user is told the button works, presses it, and gets silence.
// So each case below asserts BOTH the `IconButton.onPressed` wiring AND the
// enabled state the platform accessibility tree actually publishes.

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  // Semantics are off by default in flutter_test. Every assertion in this file
  // is about what the accessibility tree publishes, so the tree has to be built.
  late SemanticsHandle semantics;
  setUp(() => semantics = SemanticsBinding.instance.ensureSemantics());
  tearDown(() => semantics.dispose());

  /// Pumps the bar in isolation.
  ///
  /// Defaults describe a LOADED, mid-document, fully interactive desktop
  /// viewer, so each test overrides only the one axis it is about.
  Future<void> pumpBar(
    WidgetTester tester, {
    int currentPage = 5,
    int pageCount = 64,
    bool showPageControls = true,
    bool showZoomControls = true,
    bool canPrevious = true,
    bool canNext = true,
    bool canZoom = true,
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.dark(),
        home: Scaffold(
          body: PdfViewerControlBar(
            currentPage: currentPage,
            pageCount: pageCount,
            showPageControls: showPageControls,
            showZoomControls: showZoomControls,
            state: PdfViewerControlState(
              canPrevious: canPrevious,
              canNext: canNext,
              canZoom: canZoom,
            ),
            onPrevious: () {},
            onNext: () {},
            onZoomIn: () {},
            onZoomOut: () {},
            onZoomReset: () {},
          ),
        ),
      ),
    );
  }

  /// The [IconButton] behind the control labelled [tooltip].
  IconButton button(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );

  /// The semantics node a screen reader actually announces for a control.
  ///
  /// Each control produces a PAIR of nodes: an outer node from the explicit
  /// `Semantics(button:, enabled:, label:)` wrapper, which carries the NAME and
  /// the enabled state, and an inner node from the [IconButton] itself, which
  /// carries the tap action and is unlabelled. `find.byTooltip` resolves to the
  /// inner one, so it is the wrong handle for a naming assertion — it returns
  /// `label: ""` for every control, enabled or not. Finding by label pins the
  /// outer node, which is the unit AT reads out ("Zoom in, button, dimmed").
  SemanticsNode announcedNode(WidgetTester tester, String label) =>
      tester.getSemantics(find.bySemanticsLabel(label));

  /// What assistive tech is told about the enabled state of the control named
  /// [label].
  ///
  /// Reads the composed accessibility tree, not the widget's constructor
  /// arguments, so it fails if the `enabled:` flag is dropped, defaulted, or
  /// contradicted anywhere between the widget and what the platform publishes.
  ///
  /// A TRISTATE, deliberately. [Tristate.none] means the node never declared an
  /// enabled state at all, which AT reports as an unknown/disabled control — the
  /// exact trap the share button fell into in 68d9b93. Distinguishing "unset"
  /// from "explicitly false" is what stops a disabled-expectation being
  /// satisfied by a node that simply forgot to say anything.
  Tristate announcedEnabled(WidgetTester tester, String label) =>
      announcedNode(tester, label).getSemanticsData().flagsCollection.isEnabled;

  /// Asserts the wiring and the announcement AGREE, and equal [expected].
  ///
  /// The bug being guarded is precisely a disagreement between these two: an
  /// inert control that announces itself as enabled. Checking them together in
  /// one place is what makes that state unrepresentable in a passing test.
  void expectControl(
    WidgetTester tester,
    String tooltip, {
    required bool expected,
  }) {
    expect(
      button(tester, tooltip).onPressed,
      expected ? isNotNull : isNull,
      reason: '"$tooltip" onPressed should be '
          '${expected ? "wired" : "null"}',
    );
    expect(
      announcedEnabled(tester, tooltip),
      expected ? Tristate.isTrue : Tristate.isFalse,
      reason: '"$tooltip" must ANNOUNCE enabled=$expected to assistive tech, '
          'and must DECLARE the state rather than leaving it Tristate.none. '
          'A control that is inert but announced enabled is the defect this '
          'file exists to prevent.',
    );
  }

  const List<String> zoomControls = <String>[
    'Zoom in',
    'Zoom out',
    'Fit page to window',
  ];

  // ── The document bounds, including the end the integration test never saw ──
  group('page controls at the document bounds', () {
    testWidgets('on page 1 of 64, Previous is disabled and Next is live', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester, currentPage: 1, canPrevious: false);
      expectControl(tester, 'Previous page', expected: false);
      expectControl(tester, 'Next page', expected: true);
    });

    testWidgets('on the LAST page, Next is disabled and Previous is live', (
      WidgetTester tester,
    ) async {
      // THE CASE THAT WAS NEVER RUN. The integration test carrying this
      // sentence in its name stops at page 2. Mutating the forward bound to
      // `true` left it green; it turns this red.
      await pumpBar(tester, currentPage: 64, canNext: false);
      expectControl(tester, 'Next page', expected: false);
      expectControl(tester, 'Previous page', expected: true);
    });

    testWidgets('mid-document both controls are live', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester, currentPage: 30);
      expectControl(tester, 'Previous page', expected: true);
      expectControl(tester, 'Next page', expected: true);
    });

    testWidgets('§8.16 disabled, not hidden — the control stays in the bar', (
      WidgetTester tester,
    ) async {
      // The bar must not reflow as you page, and AT must meet a labelled
      // disabled control rather than a control that vanishes.
      await pumpBar(tester, currentPage: 64, canNext: false);
      expect(find.byTooltip('Next page'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  // ── The zoom defect ──────────────────────────────────────────────────────
  group('zoom controls', () {
    testWidgets('are DISABLED and announced disabled when nothing can zoom', (
      WidgetTester tester,
    ) async {
      // The loading and error states: `_baseScaleFor` is null, so `_zoomBy`
      // early-returns. Before the fix these three took non-nullable callbacks,
      // so `enabled` was a constant true and all three announced themselves as
      // working while doing nothing.
      await pumpBar(tester, canZoom: false);
      for (final String tooltip in zoomControls) {
        expectControl(tester, tooltip, expected: false);
      }
    });

    testWidgets('are live once the page and viewport are measured', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester);
      for (final String tooltip in zoomControls) {
        expectControl(tester, tooltip, expected: true);
      }
    });

    testWidgets('stay VISIBLE while disabled (§8.16 disabled, not hidden)', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester, canZoom: false);
      for (final String tooltip in zoomControls) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
    });

    testWidgets('every zoom control keeps an accessible NAME while disabled', (
      WidgetTester tester,
    ) async {
      // Disabling must not cost the label: a disabled unlabelled button is
      // still an unnamed button to a screen reader (WCAG 2.2 SC 4.1.2).
      await pumpBar(tester, canZoom: false);
      for (final String tooltip in zoomControls) {
        final SemanticsNode node = announcedNode(tester, tooltip);
        expect(node.label, tooltip);
        expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      }
    });
  });

  // ── Disabled controls must also leave the focus order ────────────────────
  group('keyboard traversal', () {
    // Focusability and the tap action live on the INNER (IconButton) node; the
    // outer labelled wrapper carries neither. So these read `find.byTooltip`,
    // unlike the naming assertions above. Focusability is asserted as the
    // presence of [SemanticsAction.focus], which is how the accessibility tree
    // actually expresses "AT can move focus here" (measured: an enabled control
    // publishes `actions: [focus, tap]`, a disabled one publishes none).
    testWidgets('a disabled control is not focusable and offers no tap', (
      WidgetTester tester,
    ) async {
      // Null `onPressed` drops an IconButton from traversal, which is what
      // stops a keyboard user landing on a dead control and pressing Enter into
      // silence.
      await pumpBar(tester, canZoom: false, currentPage: 1, canPrevious: false);
      for (final String tooltip in <String>['Previous page', ...zoomControls]) {
        final SemanticsData data =
            tester.getSemantics(find.byTooltip(tooltip)).getSemanticsData();
        expect(
          data.hasAction(SemanticsAction.focus),
          isFalse,
          reason: '"$tooltip" is disabled and must not take keyboard focus',
        );
        expect(
          data.hasAction(SemanticsAction.tap),
          isFalse,
          reason: '"$tooltip" is disabled and must expose no tap action',
        );
      }
    });

    testWidgets('an enabled control IS focusable and offers a tap', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester);
      final SemanticsData data =
          tester.getSemantics(find.byTooltip('Next page')).getSemanticsData();
      expect(data.hasAction(SemanticsAction.focus), isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
    });
  });

  // ── Visibility rules (unchanged behaviour, pinned so the fix cannot move) ─
  group('bar visibility', () {
    testWidgets('a single-page card on a touch platform draws no bar', (
      WidgetTester tester,
    ) async {
      await pumpBar(
        tester,
        currentPage: 1,
        pageCount: 1,
        showPageControls: false,
        showZoomControls: false,
      );
      expect(find.byType(IconButton), findsNothing);
      expect(find.textContaining('/'), findsNothing);
    });

    testWidgets('a multi-page card shows the indicator on a touch platform', (
      WidgetTester tester,
    ) async {
      // Knowing you are on 12 of 64 is useful whether or not you can click.
      await pumpBar(
        tester,
        currentPage: 12,
        showPageControls: false,
        showZoomControls: false,
      );
      expect(find.text('12 / 64'), findsOneWidget);
      expect(find.byTooltip('Next page'), findsNothing);
    });

    testWidgets('the page indicator reads as a sentence to AT', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester, currentPage: 12);
      // "Page 12 of 64", not "12 slash 64".
      expect(find.bySemanticsLabel('Page 12 of 64'), findsOneWidget);
    });
  });

  // ── Both themes ──────────────────────────────────────────────────────────
  group('light theme', () {
    testWidgets('the disabled contract holds in light mode too', (
      WidgetTester tester,
    ) async {
      await pumpBar(tester, theme: AppTheme.light(), canZoom: false);
      for (final String tooltip in zoomControls) {
        expectControl(tester, tooltip, expected: false);
      }
    });
  });
}
