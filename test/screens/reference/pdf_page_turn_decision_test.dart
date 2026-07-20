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
            currentPage: 1,
            pageCount: 0,
            forward: true,
          ),
          isFalse,
        );
      });
    });
  });
}
