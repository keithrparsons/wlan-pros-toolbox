// Unit tests for [canTurnPdfPage] — the page-turn gate in PdfReferenceScreen.
//
// WHY these exist (Vera gate, 2026-07-20). The `pagerAttached` half of this gate
// prevents a real CRASH: turning a page before the `PageController` has a
// position trips PageView's `positions.isNotEmpty` assertion. That bug was found
// during the desktop-navigation build and then shipped guarded but UNCOVERED —
// deleting the guard left all 18 integration tests green, because the race it
// guards is sub-frame and pumpBook settles past it.
//
// Racing a sub-frame window is not a test strategy. Extracting the decision into
// a pure function is, and the condition is now asserted directly. Each case below
// is chosen so that removing the corresponding line from `canTurnPdfPage` turns
// at least one of these red.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';

void main() {
  group('canTurnPdfPage', () {
    group('the pagerAttached crash guard', () {
      test('refuses to turn forward before the pager attaches', () {
        // The exact shape of the crash: the document HAS loaded (64 pages known,
        // so the bounds check would happily pass) but the PageController has no
        // position yet. This is the case that must not reach animateToPage.
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: false,
            documentReady: true,
            currentPage: 1,
            pageCount: 64,
            forward: true,
          ),
          isFalse,
        );
      });

      test('refuses to turn back before the pager attaches', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: false,
            documentReady: true,
            currentPage: 12,
            pageCount: 64,
            forward: false,
          ),
          isFalse,
        );
      });

      test('mid-document is still refused while unattached', () {
        // Guards against a "bounds are fine, let it through" simplification.
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: false,
            documentReady: true,
            currentPage: 30,
            pageCount: 64,
            forward: true,
          ),
          isFalse,
        );
      });

      test('the SAME call is allowed once attached', () {
        // The contrast case: identical inputs, attached. If this and the first
        // test do not disagree, the guard is not doing anything.
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 1,
            pageCount: 64,
            forward: true,
          ),
          isTrue,
        );
      });
    });

    group('the in-flight guard', () {
      test('drops input while a turn is already animating', () {
        // A wheel flick emits many ticks; without this a single flick queues a
        // dozen page turns.
        expect(
          canTurnPdfPage(
            turning: true,
            pagerAttached: true,
            documentReady: true,
            currentPage: 5,
            pageCount: 64,
            forward: true,
          ),
          isFalse,
        );
      });

      test('accepts input once the turn has settled', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 5,
            pageCount: 64,
            forward: true,
          ),
          isTrue,
        );
      });
    });

    group('document bounds', () {
      test('cannot go back from page 1', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 1,
            pageCount: 64,
            forward: false,
          ),
          isFalse,
        );
      });

      test('cannot go forward from the last page', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 64,
            pageCount: 64,
            forward: true,
          ),
          isFalse,
        );
      });

      test('can go back from page 2', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 2,
            pageCount: 64,
            forward: false,
          ),
          isTrue,
        );
      });

      test('can go forward from the second-to-last page', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 63,
            pageCount: 64,
            forward: true,
          ),
          isTrue,
        );
      });

      test('a single-page document cannot turn in either direction', () {
        // Ten of the 13 bundled documents are one page.
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 1,
            pageCount: 1,
            forward: true,
          ),
          isFalse,
        );
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 1,
            pageCount: 1,
            forward: false,
          ),
          isFalse,
        );
      });

      test('a not-yet-loaded document (0 pages) cannot turn forward', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 1,
            pageCount: 0,
            forward: true,
          ),
          isFalse,
        );
      });
    });

    // ── documentReady (added 2026-07-20, second Vera gate) ────────────────
    //
    // These are the cases the widget could not previously express at all. The
    // control bar carried its own bounds rule (`_currentPage < _pageCount`)
    // that knew nothing about the load state, so a control could announce
    // itself ENABLED over a spinner or an error panel. Every case below pairs
    // a not-ready call with an otherwise-identical ready call, so a mutation
    // that drops the `documentReady` line makes the pair contradict itself.
    group('the load-state guard', () {
      test('refuses to turn forward while the document is still loading', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: false,
            currentPage: 1,
            pageCount: 64,
            forward: true,
          ),
          isFalse,
        );
      });

      test('refuses to turn back while the document is still loading', () {
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: false,
            currentPage: 12,
            pageCount: 64,
            forward: false,
          ),
          isFalse,
        );
      });

      test('refuses to turn in the ERROR state even with a known page count',
          () {
        // The specific shape: `onDocumentLoaded` fired (so pageCount is 64 and
        // the bounds check passes) and `onDocumentError` fired afterwards. The
        // pager is still mounted under the error overlay, so this WOULD turn a
        // page the user cannot see, while the screen reads "could not be
        // opened".
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: false,
            currentPage: 30,
            pageCount: 64,
            forward: true,
          ),
          isFalse,
        );
      });

      test('the SAME call is allowed once the document is ready', () {
        // The contrast case. If this and the test above do not disagree, the
        // documentReady line is doing nothing.
        expect(
          canTurnPdfPage(
            turning: false,
            pagerAttached: true,
            documentReady: true,
            currentPage: 30,
            pageCount: 64,
            forward: true,
          ),
          isTrue,
        );
      });
    });
  });

  // ── canZoomPdfPage ──────────────────────────────────────────────────────
  //
  // WHY (Vera gate, 2026-07-20). The three zoom controls took NON-nullable
  // callbacks, so `_ControlButton`'s `enabled = onPressed != null` was a
  // constant true and every one of them published `Semantics(enabled: true)` in
  // the loading and error states — where `_zoomBy` bails immediately because
  // `_baseScaleFor` is null. A screen-reader user was told the button worked,
  // pressed it, and got silence. Same family as the share-button `enabled:` bug
  // in 68d9b93.
  group('canZoomPdfPage', () {
    test('no zoom while the document is loading, even if a scale is known', () {
      // A stale raster from a previously-open document must not re-enable the
      // controls over a spinner.
      expect(
        canZoomPdfPage(documentReady: false, baseScale: 0.42),
        isFalse,
      );
    });

    test('no zoom in the error state', () {
      expect(
        canZoomPdfPage(documentReady: false, baseScale: 1.0),
        isFalse,
      );
    });

    test('no zoom before the page raster and viewport are measured', () {
      // `_baseScaleFor` returns null until BOTH the decoded raster size and the
      // viewer's box are known. This is the state the loading spinner sits in,
      // and it is exactly what `_zoomBy` early-returns on.
      expect(
        canZoomPdfPage(documentReady: true, baseScale: null),
        isFalse,
      );
    });

    test('no zoom on a degenerate zero scale', () {
      // A zero-area raster or viewport yields a 0 base scale; multiplying it by
      // the zoom step is still 0, so the control would be inert.
      expect(
        canZoomPdfPage(documentReady: true, baseScale: 0),
        isFalse,
      );
    });

    test('zoom IS available once ready and measured', () {
      // The contrast case for all four refusals above.
      expect(
        canZoomPdfPage(documentReady: true, baseScale: 0.42),
        isTrue,
      );
    });
  });

  // ── PdfViewerControlState.from ──────────────────────────────────────────
  //
  // WHY these exist, specifically. With the enabled state computed inline in
  // the screen's `build`, a mutation run on 2026-07-20 found two SURVIVORS:
  // making the prev/next callbacks unconditional, and hard-coding
  // `documentReady: true`. Neither could be killed from a `flutter test`,
  // because the only state the headless engine reaches is "loading, 0 pages, no
  // raster" — where `pageCount == 0` already hides the pager and
  // `baseScale == null` already blocks zoom, so a broken guard and a working one
  // build identical trees. The states that WOULD distinguish them live behind
  // native PDFKit, which is the same wall that let the original bug ship.
  //
  // Pulling the derivation into a pure factory makes every one of those states
  // constructible by writing the numbers down. The cases below are the ones the
  // widget layer physically cannot reach.
  group('PdfViewerControlState.from', () {
    /// A loaded, attached, mid-document, fully measured viewer. Each test
    /// overrides only the axis it is about.
    PdfViewerControlState state({
      bool documentReady = true,
      bool pagerAttached = true,
      int currentPage = 30,
      int pageCount = 64,
      double? baseScale = 0.42,
    }) =>
        PdfViewerControlState.from(
          documentReady: documentReady,
          pagerAttached: pagerAttached,
          currentPage: currentPage,
          pageCount: pageCount,
          baseScale: baseScale,
        );

    test('mid-document, loaded and measured: everything is live', () {
      final PdfViewerControlState s = state();
      expect(s.canPrevious, isTrue);
      expect(s.canNext, isTrue);
      expect(s.canZoom, isTrue);
    });

    test('on the FIRST page, only Previous is dead', () {
      final PdfViewerControlState s = state(currentPage: 1);
      expect(s.canPrevious, isFalse);
      expect(s.canNext, isTrue);
      expect(s.canZoom, isTrue);
    });

    test('on the LAST page, only Next is dead', () {
      // Unreachable from a headless widget test: it needs a 64-page document
      // that PDFKit actually opened. Here it is just a number.
      final PdfViewerControlState s = state(currentPage: 64);
      expect(s.canPrevious, isTrue);
      expect(s.canNext, isFalse);
      expect(s.canZoom, isTrue);
    });

    test('while LOADING, nothing is live', () {
      expect(
        state(documentReady: false, pageCount: 0, baseScale: null),
        PdfViewerControlState.inert,
      );
    });

    test('a document that loaded and THEN errored kills every control', () {
      // The case that hard-coding `documentReady: true` would break, and the
      // one no headless widget test can build: page count and raster are both
      // known — so the bounds and zoom checks would each pass on their own —
      // but the viewer is showing an error panel. Every control must be dead.
      expect(
        state(documentReady: false, currentPage: 30, baseScale: 0.42),
        PdfViewerControlState.inert,
      );
    });

    test('before the pager attaches, paging is dead but zoom is not', () {
      // These two are independent: the crash guard is about the PageController,
      // and has nothing to do with whether the page can be scaled.
      final PdfViewerControlState s = state(pagerAttached: false);
      expect(s.canPrevious, isFalse);
      expect(s.canNext, isFalse);
      expect(s.canZoom, isTrue);
    });

    test('an unmeasured page kills zoom but not paging', () {
      // The other half of the same independence: pdfx renders lazily, so a
      // freshly turned-to page has no raster yet while the pager is fine.
      final PdfViewerControlState s = state(baseScale: null);
      expect(s.canPrevious, isTrue);
      expect(s.canNext, isTrue);
      expect(s.canZoom, isFalse);
    });

    test('a single-page card: no paging, but zoom still works', () {
      // Ten of the 13 bundled documents are one page. Zoom is the whole point
      // of the viewer for those, so it must NOT be collateral damage.
      final PdfViewerControlState s = state(currentPage: 1, pageCount: 1);
      expect(s.canPrevious, isFalse);
      expect(s.canNext, isFalse);
      expect(s.canZoom, isTrue);
    });

    test('the inert constant really is all-false', () {
      // Guards the constant itself, since two tests above assert equality
      // against it and would both pass if it silently became all-true.
      expect(PdfViewerControlState.inert.canPrevious, isFalse);
      expect(PdfViewerControlState.inert.canNext, isFalse);
      expect(PdfViewerControlState.inert.canZoom, isFalse);
    });

    test('value equality distinguishes each field', () {
      // The equality operator is load-bearing for the two `inert` comparisons
      // above; a `==` that ignored a field would make them vacuous.
      const PdfViewerControlState all = PdfViewerControlState(
        canPrevious: true,
        canNext: true,
        canZoom: true,
      );
      expect(all, isNot(PdfViewerControlState.inert));
      expect(
        all,
        isNot(const PdfViewerControlState(
          canPrevious: false,
          canNext: true,
          canZoom: true,
        )),
      );
      expect(
        all,
        isNot(const PdfViewerControlState(
          canPrevious: true,
          canNext: false,
          canZoom: true,
        )),
      );
      expect(
        all,
        isNot(const PdfViewerControlState(
          canPrevious: true,
          canNext: true,
          canZoom: false,
        )),
      );
      expect(
        all,
        const PdfViewerControlState(
          canPrevious: true,
          canNext: true,
          canZoom: true,
        ),
      );
    });
  });
}
