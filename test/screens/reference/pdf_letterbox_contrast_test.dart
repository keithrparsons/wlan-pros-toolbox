// Contrast + rendered evidence for the PDF viewer's LETTERBOX — the matte the
// fit-contained page sits in.
//
// THE DEFECT (found by a Vera gate, 2026-07-20, pre-existing). The letterbox was
// `surface1` in both themes. In light mode `surface1` is #FFFFFF, which is the
// SAME white the pages are rendered on (`renderReferencePage` passes
// `backgroundColor: '#ffffff'`). Measured page-edge contrast: 1.00:1. A PDF page
// had no visible boundary in light mode at all — the user could not see where
// the page ended and the viewer began.
//
// WHY A NUMERIC TEST AND NOT ONLY A GOLDEN. A golden proves "these pixels are
// what they were last time"; it cannot say whether the edge is VISIBLE, and a
// baseline regenerated on a broken build enshrines the bug (see
// [[feedback_tests_that_enshrine_the_bug]]). The contrast ratio is the actual
// requirement, so it is asserted as a number, against the real shipped tokens
// read out of `AppColorScheme`, not against copies. The goldens below are
// supporting visual evidence, not the gate.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';

/// WCAG 2.2 relative luminance (SC 1.4.3 / 1.4.11 definition).
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final AppColorScheme light = AppColorScheme.light();
  final AppColorScheme dark = AppColorScheme.dark();

  group('page-edge contrast against the letterbox', () {
    test('LIGHT mode: the page edge is perceivable', () {
      final Color matte = pdfLetterboxColor(light);
      final double ratio = _contrast(kPdfPageStock, matte);
      // 3:1 is SC 1.4.11 (non-text contrast) — the floor for the boundary of a
      // component the user can target. The page pans and zooms, so it is one.
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason: 'the page edge must be visible in light mode; measured '
            '${ratio.toStringAsFixed(2)}:1 against '
            '#${matte.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      );
    });

    test('LIGHT mode: the regression itself cannot come back', () {
      // The precise shape of the bug: matte == page stock. Pinned separately
      // from the ratio assertion so the failure message names the cause.
      expect(
        pdfLetterboxColor(light),
        isNot(kPdfPageStock),
        reason: 'the letterbox must not be the same white as the page stock — '
            'that is the 1.00:1 defect this test exists for',
      );
      expect(
        pdfLetterboxColor(light),
        isNot(light.surface1),
        reason: 'light surface1 IS #FFFFFF; using it here reintroduces the bug',
      );
    });

    test('DARK mode is unharmed — byte-identical to what shipped', () {
      // Dark was never broken (15.91:1). The fix must not touch it, so this
      // asserts the exact token rather than only a ratio: a change that kept
      // dark above 3:1 while altering its appearance would still be a
      // regression in App Mode.
      expect(
        pdfLetterboxColor(dark),
        dark.surface1,
        reason: 'dark mode must keep the surface1 letterbox it always had',
      );
      expect(
        _contrast(kPdfPageStock, pdfLetterboxColor(dark)),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('the measured ratios are the ones documented in the source', () {
      // Pins the numbers written into pdfLetterboxColor's doc comment, so the
      // comment cannot quietly drift from the tokens it claims to describe.
      expect(
        _contrast(kPdfPageStock, pdfLetterboxColor(light)),
        closeTo(5.74, 0.01),
      );
      expect(
        _contrast(kPdfPageStock, pdfLetterboxColor(dark)),
        closeTo(15.91, 0.01),
      );
      // And the rejected candidates, so the "no light surface token works"
      // claim in that doc stays checkable rather than asserted.
      expect(_contrast(kPdfPageStock, light.surface0), closeTo(1.08, 0.01));
      expect(_contrast(kPdfPageStock, light.surface1), closeTo(1.00, 0.01));
      expect(_contrast(kPdfPageStock, light.border), closeTo(1.30, 0.01));
    });
  });

  // ── Rendered evidence ────────────────────────────────────────────────────
  //
  // HONEST SCOPE, so nobody reads more into these than they carry: the page
  // rectangle here is a STAND-IN, not a PDFKit raster. pdfx cannot render in the
  // headless engine, so a real page cannot appear in a widget test at all. What
  // IS true-to-ship is every color: the matte comes from `pdfLetterboxColor` and
  // the page fill from `kPdfPageStock`, the same two values the running viewer
  // uses. These capture the page-edge relationship, which is the whole defect.
  group('rendered letterbox goldens', () {
    Widget harness({required AppColorScheme colors, required Size page}) {
      return MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: pdfLetterboxColor(colors),
            child: Center(
              child: SizedBox(
                width: page.width,
                height: page.height,
                child: const ColoredBox(color: kPdfPageStock),
              ),
            ),
          ),
        ),
      );
    }

    // A landscape card in a portrait-ish window — the worst case, where the
    // matte is most of the screen and an invisible edge is most obvious.
    for (final (String name, AppColorScheme colors) in <(String, AppColorScheme)>[
      ('light', AppColorScheme.light()),
      ('dark', AppColorScheme.dark()),
    ]) {
      testWidgets('letterbox @ $name', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          harness(colors: colors, page: const Size(520, 293)),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(ColoredBox).first,
          matchesGoldenFile('goldens/pdf_letterbox_$name.png'),
        );
      });
    }
  });

  // Sanity check on the harness itself: if the two goldens were identical the
  // captures would be worthless as light/dark evidence.
  test('the two themes really do produce different mattes', () {
    expect(pdfLetterboxColor(light), isNot(pdfLetterboxColor(dark)));
  });

  test('kPdfPageStock matches the renderer argument', () {
    // renderReferencePage passes the literal string '#ffffff' to pdfx. If that
    // ever changes, this constant — and every ratio above — is measuring the
    // wrong thing.
    expect(kPdfPageStock, const Color(0xFFFFFFFF));
    expect(ui.Color(0xFFFFFFFF), kPdfPageStock);
  });
}
