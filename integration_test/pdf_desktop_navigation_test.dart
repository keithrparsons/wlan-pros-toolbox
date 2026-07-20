// Integration test — proves a DESKTOP MOUSE can navigate a multi-page bundled
// PDF in [PdfReferenceScreen] on the real macOS embedder.
//
// WHY this is an integration test, not a widget test: the surface under test is
// pdfx's `PdfView`, which only builds its `PhotoViewGallery`/`PageView` once the
// document has actually opened through the platform PDF engine (Apple PDFKit on
// iOS + macOS). That engine is a no-op in the headless flutter_test
// environment, so a plain widget test never gets a `PageView` to drag at all.
// IntegrationTestWidgetsFlutterBinding runs this against the live macOS binding
// where PDFKit is available and the pager really exists.
//
// Run:  flutter test integration_test/pdf_desktop_navigation_test.dart -d macos
//
// THE BUG THIS GUARDS (customer report, Peter, Windows, 2026-07-19): "Fix Your
// Own Wi-Fi ... just shows the title image and then you can't scroll / access
// the rest of the content."
//
// Root cause: `PdfView` pages horizontally through a `PageView`, which is a
// `Scrollable`. Flutter's default `ScrollBehavior.dragDevices` is
// `_kTouchLikeDeviceTypes` (widgets/scroll_configuration.dart) — touch, stylus,
// invertedStylus, trackpad, unknown. `PointerDeviceKind.mouse` is deliberately
// NOT in that set, because on desktop Flutter expects a scrollbar or a wheel to
// do the scrolling. A `PageView` offers neither, so a mouse user cannot turn the
// page by any means and is pinned to page 1 forever.
//
// Note `trackpad` IS in the default set. That is exactly why this shipped: on a
// MacBook trackpad the viewer pages fine, so the defect is invisible to anyone
// testing on a laptop without plugging in a mouse.
//
// THREE of the 13 bundled documents are multi-page and therefore affected:
// fix-your-own-wifi (64), ham-radio-general-exam-study-notes (15) and
// general-license-frequency-chart (6). Counts per `mdls -name
// kMDItemNumberOfPages`; an earlier revision of this comment also listed
// mcs-index-card as 2 pages, but it is `/Count 1`, one page.
//
// Each check drives a genuine `PointerDeviceKind.mouse` gesture or a real
// `PointerScrollEvent`, so it fails red on the unfixed screen.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The consumer book — 64 pages, the document the customer actually hit.
const String _bookTitle = 'Fix Your Own Wi-Fi';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps the screen and waits for native PDFKit to open the document and
  /// build the pager. Returns once a [PageView] exists in the tree.
  ///
  /// `pumpAndSettle` can hang here (PhotoView runs a continuous ticker), so we
  /// poll the tree rather than settle it — same approach as pdf_render_test.
  Future<void> pumpBook(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const PdfReferenceScreen(
          title: _bookTitle,
          assetPath: kFixYourOwnWifiBookAsset,
          toolId: 'fix-your-own-wifi-book',
        ),
      ),
    );

    const Duration budget = Duration(seconds: 30);
    final Stopwatch sw = Stopwatch()..start();
    bool found = false;
    while (sw.elapsed < budget) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(PageView).evaluate().isNotEmpty) {
        found = true;
        break;
      }
      if (find
          .text('This reference card could not be opened.')
          .evaluate()
          .isNotEmpty) {
        fail('The book asset failed to open on this device.');
      }
    }
    if (!found) fail('PDF pager never appeared within ${budget.inSeconds}s.');

    // The PageView existing is not the same as the first page being decoded and
    // laid out. pdfx cross-fades the loader out via an AnimatedSwitcher and the
    // page raster arrives asynchronously, so a gesture sent the instant the
    // PageView appears can land before the pager has a usable scroll position.
    // Settle a few more frames so the drag tests measure navigation, not a race.
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// Current 0-based page of the viewer's underlying pager.
  double currentPage(WidgetTester tester) {
    final PageView view = tester.widget<PageView>(find.byType(PageView));
    return view.controller?.page ?? 0;
  }

  /// Lets the page-turn animation run without settling the PhotoView ticker.
  Future<void> letAnimationRun(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the pager accepts MOUSE drags', (WidgetTester tester) async {
    await pumpBook(tester);

    // Structural guard on the actual cause. Flutter's default behavior omits
    // PointerDeviceKind.mouse here, which is what pinned the document to page 1.
    final ScrollBehavior behavior = ScrollConfiguration.of(
      tester.element(find.byType(PageView)),
    );
    expect(
      behavior.dragDevices,
      contains(PointerDeviceKind.mouse),
      reason: 'The pager must accept mouse drags.',
    );
    // Trackpad must survive too: it is in Flutter's default set, and dropping it
    // would break paging for every laptop user.
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
    expect(behavior.dragDevices, contains(PointerDeviceKind.touch));
  });

  testWidgets('a MOUSE drag turns the page', (WidgetTester tester) async {
    await pumpBook(tester);
    expect(
      currentPage(tester),
      closeTo(0, 0.01),
      reason: 'should start on page 1',
    );

    // A fling carries velocity, so it pages regardless of how wide the test
    // window happens to be. A fixed-distance drag is viewport-dependent: on an
    // 860px-wide window a 400px drag sits under PageView's 50% snap threshold
    // and springs back, which looks like a navigation failure but is not one.
    await tester.fling(
      find.byType(PageView),
      const Offset(-500, 0),
      3000,
      deviceKind: PointerDeviceKind.mouse,
    );
    await letAnimationRun(tester);

    expect(
      currentPage(tester),
      greaterThan(0.5),
      reason:
          'A mouse drag must turn the page. If this fails, either '
          'ScrollBehavior.dragDevices is missing PointerDeviceKind.mouse, or '
          'PhotoView is claiming the drag (see _pageOwnsDragGesture).',
    );
  });

  testWidgets('a TOUCH drag still turns the page (no mobile regression)', (
    WidgetTester tester,
  ) async {
    await pumpBook(tester);

    await tester.fling(
      find.byType(PageView),
      const Offset(-500, 0),
      3000,
      deviceKind: PointerDeviceKind.touch,
    );
    await letAnimationRun(tester);

    expect(
      currentPage(tester),
      greaterThan(0.5),
      reason: 'Touch paging must be unaffected by the desktop fix.',
    );
  });

  testWidgets('the mouse WHEEL turns the page', (WidgetTester tester) async {
    await pumpBook(tester);
    expect(currentPage(tester), closeTo(0, 0.01));

    final Offset centre = tester.getCenter(find.byType(PageView));
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(centre);
    // A notched wheel tick scrolls in the vertical axis; the viewer maps that
    // onto its horizontal pager.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await letAnimationRun(tester);

    expect(
      currentPage(tester),
      greaterThan(0.5),
      reason: 'A mouse wheel tick must advance one page.',
    );
  });

  testWidgets('the next/previous page controls turn the page', (
    WidgetTester tester,
  ) async {
    // Semantics is off by default in an integration test, so turn it on BEFORE
    // pumping, otherwise the nodes are not built when we assert on them.
    // Disposed inline rather than via addTearDown: flutter_test verifies that
    // no handle is live at the END OF THE TEST BODY, which runs before tearDowns.
    final SemanticsHandle semantics = tester.ensureSemantics();

    await pumpBook(tester);

    // The page indicator reports human-facing 1-based numbering.
    expect(find.text('1 / 64'), findsOneWidget);
    expect(find.bySemanticsLabel('Page 1 of 64'), findsOneWidget);
    expect(find.bySemanticsLabel('Next page'), findsOneWidget);
    expect(find.bySemanticsLabel('Previous page'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom out'), findsOneWidget);
    expect(find.bySemanticsLabel('Fit page to window'), findsOneWidget);
    // Every icon-only control on this screen needs an accessible NAME, not just
    // a tooltip (WCAG 2.2 AA SC 4.1.2). The share action shipped without one:
    // Flutter's `tooltip:` is a separate field that macOS maps to AXHelp, so a
    // semantics dump read `label="" button=true`. This is the guard for that.
    expect(find.bySemanticsLabel('Share or download'), findsOneWidget);
    // ...and it must be exposed as an ENABLED button. A Semantics node with
    // `button: true` but no `enabled:` leaves isEnabled unset, which AT reads as
    // a disabled control; a live dump caught exactly that when the label was
    // first added. Share is always available (the asset is bundled).
    expect(
      tester.getSemantics(find.bySemanticsLabel('Share or download')),
      // isSemantics (the non-deprecated successor to containsSemantics), not
      // matchesSemantics: we assert the properties that matter rather than an
      // exhaustive node shape that would break on any unrelated framework flag
      // change.
      isSemantics(
        label: 'Share or download',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
      ),
    );

    // Tap by tooltip, the repo's existing convention for AppBar/icon actions.
    await tester.tap(find.byTooltip('Next page'));
    await letAnimationRun(tester);
    expect(currentPage(tester), greaterThan(0.5));
    expect(find.text('2 / 64'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous page'));
    await letAnimationRun(tester);
    expect(currentPage(tester), closeTo(0, 0.01));
    expect(find.text('1 / 64'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('previous is DISABLED on page 1, next on the last page', (
    WidgetTester tester,
  ) async {
    await pumpBook(tester);

    // `find.byTooltip` matches the Tooltip widget; the IconButton is its
    // ancestor, and the IconButton is what carries the enabled/disabled state.
    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

    // §8.16 "disabled, not hidden": the control stays in the bar so the layout
    // does not reflow and AT still meets a labelled control.
    expect(
      button('Previous page').onPressed,
      isNull,
      reason: 'Previous must be disabled on page 1.',
    );
    expect(
      button('Next page').onPressed,
      isNotNull,
      reason: 'Next must be live on page 1 of 64.',
    );

    await tester.tap(find.byTooltip('Next page'));
    await letAnimationRun(tester);
    expect(
      button('Previous page').onPressed,
      isNotNull,
      reason: 'Previous must become live once off page 1.',
    );
  });

  testWidgets('zoom controls change the page scale for a mouse user', (
    WidgetTester tester,
  ) async {
    await pumpBook(tester);

    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Fit page to window'), findsOneWidget);

    // photo_view leaves controller.scale NULL while the page sits at its
    // computed fit scale, and only populates it once something sets a scale.
    // So "null" is the fitted state, not a missing value.
    double? scale() => tester
        .widget<PhotoView>(find.byType(PhotoView).first)
        .controller
        ?.scale;

    await tester.tap(find.byTooltip('Zoom in'));
    await letAnimationRun(tester);
    final double? zoomedOnce = scale();
    expect(
      zoomedOnce,
      isNotNull,
      reason: 'Zoom in must set a scale, not silently no-op.',
    );

    await tester.tap(find.byTooltip('Zoom in'));
    await letAnimationRun(tester);
    expect(
      scale(),
      greaterThan(zoomedOnce!),
      reason: 'A second Zoom in must magnify further.',
    );

    await tester.tap(find.byTooltip('Fit page to window'));
    await letAnimationRun(tester);
    expect(
      scale(),
      lessThan(zoomedOnce),
      reason: 'Fit must return the page below the zoomed scale.',
    );
  });

  // ---------------------------------------------------------------------------
  // TOUCH PLATFORMS (`_isPointerPlatform == false`)
  //
  // Everything above runs as macOS, which only exercises the desktop branch.
  // These drive the branch iOS and Android users actually get. Touch is not
  // merely "unaffected" by this change: a multi-page document now gains a page
  // indicator on mobile too, so the mobile surface really did change and needs
  // asserting rather than assuming.
  // ---------------------------------------------------------------------------
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    // The override is set and cleared INSIDE each test body, not via
    // setUp/tearDown: flutter_test asserts that no foundation debug variable is
    // still set at the end of the test BODY, and tearDown runs after that check.
    // try/finally so a failing expect still restores the platform for the next
    // test rather than poisoning the rest of the run.
    Future<void> asPlatform(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    group('on $platform', () {
      testWidgets('multi-page shows the indicator but NO desktop controls', (
        WidgetTester tester,
      ) async {
        await asPlatform(() async {
          await pumpBook(tester);

          // The indicator is useful on every platform: knowing you are on 12 of 64
          // does not require a mouse.
          expect(find.text('1 / 64'), findsOneWidget);

          // Pager buttons would duplicate swipe, and zoom buttons would duplicate
          // pinch. Neither should appear where the gesture already exists.
          expect(find.byTooltip('Next page'), findsNothing);
          expect(find.byTooltip('Previous page'), findsNothing);
          expect(find.byTooltip('Zoom in'), findsNothing);
          expect(find.byTooltip('Zoom out'), findsNothing);
          expect(find.byTooltip('Fit page to window'), findsNothing);
        });
      });

      testWidgets('a touch swipe still turns the page', (
        WidgetTester tester,
      ) async {
        await asPlatform(() async {
          await pumpBook(tester);
          await tester.fling(
            find.byType(PageView),
            const Offset(-500, 0),
            3000,
            deviceKind: PointerDeviceKind.touch,
          );
          await letAnimationRun(tester);
          expect(
            currentPage(tester),
            greaterThan(0.5),
            reason:
                'swipe-to-page must survive the desktop fix; '
                '_pageOwnsDragGesture must not disable PhotoView on touch',
          );
        });
      });

      testWidgets('the Semantics label names PINCH, not the desktop controls', (
        WidgetTester tester,
      ) async {
        await asPlatform(() async {
          final SemanticsHandle semantics = tester.ensureSemantics();
          await pumpBook(tester);

          // The original bug in this label: it said "Pinch to zoom" on every
          // platform. The fix must not invert that mistake by naming keyboard and
          // on-screen controls to a touch user who has neither.
          expect(
            find.bySemanticsLabel(RegExp('Pinch to zoom')),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel(RegExp('arrow keys')), findsNothing);
          expect(
            find.bySemanticsLabel(RegExp('Command|Control')),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(RegExp('Swipe to change page')),
            findsOneWidget,
          );

          semantics.dispose();
        });
      });

      testWidgets('a SINGLE-page card shows no control bar at all', (
        WidgetTester tester,
      ) async {
        await asPlatform(() async {
          // The degenerate case: nothing to page, and pinch already zooms, so the
          // bar should take no vertical space from the viewer.
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const PdfReferenceScreen(
                title: 'Top 20 Wi-Fi Checklist',
                assetPath: 'assets/reference-cards/top-20-checklist.pdf',
                toolId: 'top-20-checklist',
              ),
            ),
          );
          final Stopwatch sw = Stopwatch()..start();
          while (sw.elapsed < const Duration(seconds: 30)) {
            await tester.pump(const Duration(milliseconds: 250));
            if (find.byType(PageView).evaluate().isNotEmpty) break;
          }
          for (int i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 150));
          }

          expect(find.byTooltip('Zoom in'), findsNothing);
          expect(find.byTooltip('Next page'), findsNothing);
          expect(find.text('1 / 1'), findsNothing);
        });
      });
    });
  }

  testWidgets('navigation input during LOADING never crashes', (
    WidgetTester tester,
  ) async {
    // Guards `_turnPage`'s `!_pagerAttached` check (set from
    // ScrollMetricsNotification). Without it, a navigation intent raised before
    // the PageController has a position reaches PdfController.animateToPage and
    // trips PageView's `positions.isNotEmpty` assertion — a crash, not a no-op.
    //
    // This deliberately does NOT use pumpBook: pumpBook settles 8 frames and so
    // closes the exact race the guard exists for, which is why deleting the
    // guard left the rest of this suite green.
    //
    // It also does not try to pin "the one pre-attach frame". On a warm process
    // the document can open within two frames, so that window is not reliably
    // observable. Instead we drive every navigation entry point on EVERY frame
    // from the first one onwards, which necessarily covers whatever pre-attach
    // frames exist on this run, and assert the framework swallowed nothing.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const PdfReferenceScreen(
          title: _bookTitle,
          assetPath: kFixYourOwnWifiBookAsset,
          toolId: 'fix-your-own-wifi-book',
        ),
      ),
    );

    for (int frame = 0; frame < 40; frame++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);

      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(tester.getCenter(find.byType(PdfReferenceScreen)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));

      // takeException() returns anything the framework caught this frame. A
      // clean null on every frame of the load is the whole assertion.
      expect(
        tester.takeException(),
        isNull,
        reason: 'navigation input on frame $frame (during document load) must '
            'be a no-op, not a PageController assertion failure',
      );

      await tester.pump(const Duration(milliseconds: 16));
    }

    // The screen must still be alive and able to finish loading afterwards.
    final Stopwatch sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(PageView).evaluate().isNotEmpty) break;
    }
    expect(find.byType(PageView), findsOneWidget,
        reason: 'the document should still load normally after early input');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a SINGLE-page card shows zoom controls but no pager', (
    WidgetTester tester,
  ) async {
    // Nine of the 13 bundled documents are one page. A pager and a "1 / 1"
    // indicator there would be controls that do nothing, so the bar shows only
    // what is actionable. Zoom still applies: a mouse has no pinch, and these
    // dense print cards are exactly what the customer said was hard to read.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const PdfReferenceScreen(
          title: 'Top 20 Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/top-20-checklist.pdf',
          toolId: 'top-20-checklist',
        ),
      ),
    );
    final Stopwatch sw = Stopwatch()..start();
    while (sw.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.byType(PageView).evaluate().isNotEmpty) break;
    }
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.byTooltip('Next page'), findsNothing);
    expect(find.byTooltip('Previous page'), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Fit page to window'), findsOneWidget);
  });

  testWidgets('arrow keys and PageUp/PageDown turn the page', (
    WidgetTester tester,
  ) async {
    await pumpBook(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await letAnimationRun(tester);
    expect(
      currentPage(tester),
      greaterThan(0.5),
      reason: 'Right arrow must advance a page.',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await letAnimationRun(tester);
    expect(
      currentPage(tester),
      closeTo(0, 0.01),
      reason: 'Left arrow must go back a page.',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await letAnimationRun(tester);
    expect(
      currentPage(tester),
      greaterThan(0.5),
      reason: 'PageDown must advance a page.',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await letAnimationRun(tester);
    expect(
      currentPage(tester),
      closeTo(0, 0.01),
      reason: 'PageUp must go back a page.',
    );
  });
}
