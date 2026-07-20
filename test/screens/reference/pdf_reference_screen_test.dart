// Widget tests for the PDF reference card screen's share/download action
// (Ticket 4).
//
// The pdfx PdfView body cannot render in the headless flutter_test environment
// (it needs native PDFKit), but the AppBar and its share action are in the
// widget tree independent of the document load state, so these tests assert the
// action's presence, semantics, and wiring without ever touching pdfx or the
// platform share channel. The share implementation is injected as a fake via
// the screen's `shareFn` seam.

import 'dart:io' show Platform;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/pdf_download.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  // Captures the args the screen passes to the share seam so the test can
  // assert the wiring without a platform channel.
  late List<({String assetPath, String title})> calls;

  Future<void> fakeShare({
    required String assetPath,
    required String title,
    ShareOrigin? shareOrigin,
  }) async {
    calls.add((assetPath: assetPath, title: title));
  }

  setUp(() => calls = <({String assetPath, String title})>[]);

  Widget harness() => MaterialApp(
        theme: AppTheme.dark(),
        home: PdfReferenceScreen(
          title: 'Top 20 Wi-Fi Checklist',
          assetPath: 'assets/reference-cards/top-20-checklist.pdf',
          toolId: 'top-20-checklist',
          shareFn: fakeShare,
        ),
      );

  // PdfReferenceScreen wires share_plus/pdfx, neither of which has a Linux
  // plugin implementation; these share-action tests touch that native seam, so
  // skip them only on the Linux CI runner. They pass on macOS/iOS/local.
  testWidgets('a share action is present in the AppBar', (tester) async {
    await tester.pumpWidget(harness());
    // One IconButton in the AppBar carrying the share glyph.
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      ),
      findsOneWidget,
    );
  }, skip: Platform.isLinux);

  testWidgets('the share action exposes its tooltip/label to AT', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    // The IconButton's tooltip doubles as the accessible label.
    expect(find.byTooltip('Share or download'), findsOneWidget);
  }, skip: Platform.isLinux);

  testWidgets('tapping the share action invokes the share seam with the '
      'card asset path and title', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.assetPath, 'assets/reference-cards/top-20-checklist.pdf');
    expect(calls.single.title, 'Top 20 Wi-Fi Checklist');
  }, skip: Platform.isLinux);

  testWidgets('the share action is focusable (inherits the global ring path)', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    final FocusNode node = Focus.of(
      tester.element(find.byIcon(Icons.ios_share)),
    );
    // A live, enabled IconButton is reachable by keyboard focus traversal.
    expect(node.canRequestFocus, isTrue);
  }, skip: Platform.isLinux);

  // ── The LOADING state, end to end through the real screen ────────────────
  //
  // Added 2026-07-20 (second Vera gate). [PdfViewerControlBar]'s own tests pin
  // the bar's enabled/disabled CONTRACT; these pin the SCREEN'S WIRING to it,
  // which is the other half and was previously reachable only from an
  // integration test on a real device — which is how the bug shipped.
  //
  // MEASURED, not assumed: pdfx opens the document through native PDFKit, which
  // does not exist in the headless test engine, so the document future never
  // completes and the screen sits in `_PdfLoadState.loading` indefinitely. It
  // does NOT reach the error state (verified: no error copy in the tree, no
  // exception on the binding). That makes `flutter test` a perfect fixture for
  // the loading half of this defect — the spinner is up, and on a pointer
  // platform the control bar renders all three zoom controls over it.
  //
  // This is the exact scenario a real user meets on a cold launch of a large
  // card: controls painted, document not yet open, nothing to zoom.
  group('loading state', () {
    // The zoom controls only render on a pointer platform. Without forcing one
    // the bar omits them entirely and every assertion below passes vacuously.
    //
    // Uses [TargetPlatformVariant] rather than setting
    // `debugDefaultTargetPlatformOverride` in setUp/tearDown: flutter_test
    // verifies that no foundation debug variable is still set when the test
    // BODY ends, which is before `tearDown` runs, so the setUp/tearDown form
    // fails the invariant check. The variant sets and clears it around that
    // check correctly.
    final TargetPlatformVariant onDesktop =
        TargetPlatformVariant.only(TargetPlatform.macOS);

    // Semantics are off by default in flutter_test, and the handle must be
    // disposed at GROUP level: flutter_test's end-of-body verification runs
    // before `addTearDown` callbacks, so disposing from inside a test body
    // fails with "A SemanticsHandle was active at the end of the test".
    late SemanticsHandle semantics;
    setUp(() => semantics = SemanticsBinding.instance.ensureSemantics());
    tearDown(() => semantics.dispose());

    const List<String> zoomControls = <String>[
      'Zoom in',
      'Zoom out',
      'Fit page to window',
    ];

    /// Pumps the screen and holds it in the loading state.
    Future<void> pumpLoading(WidgetTester tester) async {
      await tester.pumpWidget(harness());
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // Precondition: if this ever starts reaching a resolved state, these
      // tests are no longer testing loading and must be rewritten rather than
      // silently passing against a different state.
      expect(
        find.text('This reference card could not be opened.'),
        findsNothing,
        reason: 'this group asserts the LOADING state; the screen resolved',
      );
    }

    testWidgets('the zoom controls are DISABLED while the document loads', (
      tester,
    ) async {
      // THE DEFECT, at the screen level. The three zoom callbacks used to be
      // unconditional, so all three rendered live over the loading spinner: a
      // screen-reader user was told "Zoom in, button" on a card that had not
      // opened, pressed it, and got silence — `_zoomBy` bails because
      // `_baseScaleFor` is null with no page raster measured.
      await pumpLoading(tester);
      for (final String label in zoomControls) {
        final IconButton control = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(label),
            matching: find.byType(IconButton),
          ),
        );
        expect(
          control.onPressed,
          isNull,
          reason: '"$label" must be disabled during load — _zoomBy has no '
              'measured page to scale against and drops the press',
        );
      }
    }, skip: Platform.isLinux, variant: onDesktop);

    testWidgets('the zoom controls announce enabled=false to AT', (
      tester,
    ) async {
      // The accessibility half, which is the harm: a grey glyph that still
      // reports itself as enabled is what makes the press-into-silence happen.
      await pumpLoading(tester);
      for (final String label in zoomControls) {
        final SemanticsData data = tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData();
        expect(
          data.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason: '"$label" is inert during load and must announce enabled=false'
              ' — and must DECLARE the state, not leave it Tristate.none, which'
              ' AT reads as an unknown control',
        );
      }
    }, skip: Platform.isLinux, variant: onDesktop);

    testWidgets('the zoom controls are still SHOWN and named (§8.16)', (
      tester,
    ) async {
      // Disabled, not hidden — and disabling must not cost the accessible name.
      await pumpLoading(tester);
      for (final String label in zoomControls) {
        expect(find.byTooltip(label), findsOneWidget);
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
    }, skip: Platform.isLinux, variant: onDesktop);

    testWidgets('no pager is drawn for a document that has reported no pages', (
      tester,
    ) async {
      // `_pageCount` is still 0, so there is nothing to page through and the
      // prev/next controls must not appear at all.
      await pumpLoading(tester);
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.byTooltip('Previous page'), findsNothing);
    }, skip: Platform.isLinux, variant: onDesktop);
  });
}
