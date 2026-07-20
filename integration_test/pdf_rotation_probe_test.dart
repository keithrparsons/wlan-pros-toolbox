// OBJECTIVE rotation probe — renders 3 representative cards through the EXACT
// same pdfx render call PdfReferenceScreen uses, decodes the resulting PNG, and
// checks the TRUE pixel dimensions of the raster. This is evidence, not
// reasoning.
//
// Run: flutter test integration_test/pdf_rotation_probe_test.dart -d macos
//
// MADE TO ASSERT 2026-07-20 (Vera gate). This file previously only
// `debugPrint`ed the dimensions; its single assertion was `expect(img,
// isNotNull)`. It was a test that could not fail — a squeezed card would have
// sailed through it green, which is precisely the regression it exists to catch.
// Two things follow from that, and both were true:
//
//   1. It never noticed that `bubble-diagram.pdf` was re-exported. The card is
//      no longer the "portrait MediaBox + /Rotate 90" asset the screen header
//      described: it now has `/MediaBox [0 0 1440 810]` and NO `/Rotate` key at
//      all. There is currently no rotated card in the bundle. Labels and
//      expected aspects below are re-measured, and the screen header is fixed.
//   2. Expected aspects are now DATA and are asserted, so a future re-export
//      that changes a card's shape fails here loudly instead of silently
//      invalidating the header's evidence again.
//
// For each card we report and assert:
//   page.width / page.height        — pdfx MediaBox dims (Apple path ignores /Rotate)
//   PdfPageImage.width / .height     — what the plugin REPORTS for the raster
//   decoded PNG image.width/.height  — the ACTUAL raster pixels (ground truth)
//
// The load-bearing invariant is the LAST one: PhotoView fit-contains the DECODED
// raster, so if the decoded aspect is right the card cannot paint squeezed.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';

Future<({int w, int h})> _decodedPngSize(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image img = frame.image;
  final size = (w: img.width, h: img.height);
  img.dispose();
  codec.dispose();
  return size;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Expected aspects re-measured 2026-07-20 against the shipped assets.
  const List<({String label, String asset, double aspect})> cards =
      <({String label, String asset, double aspect})>[
    (
      // Native landscape as of the 2026-07 re-export; NOT /Rotate any more.
      label: 'LANDSCAPE (1440x810 MediaBox, no /Rotate)',
      asset: 'assets/reference-cards/bubble-diagram.pdf',
      aspect: 1440 / 810, // 1.778
    ),
    (
      label: 'NATIVE-LANDSCAPE',
      asset: 'assets/reference-cards/channel-allocations-5ghz.pdf',
      aspect: 792 / 612, // 1.294
    ),
    (
      label: 'PORTRAIT',
      asset: 'assets/reference-cards/top-20-checklist.pdf',
      aspect: 612 / 792, // 0.773
    ),
  ];

  group('PDF rotation probe — true raster dimensions', () {
    for (final ({String label, String asset, double aspect}) c in cards) {
      testWidgets('${c.label} — ${c.asset}', (_) async {
        final PdfDocument doc = await PdfDocument.openAsset(c.asset);
        final PdfPage page = await doc.getPage(1);

        // EXACT screen render path.
        final PdfPageImage? img = await renderReferencePage(page);
        expect(img, isNotNull, reason: 'render returned null for ${c.asset}');

        final ({int w, int h}) png = await _decodedPngSize(img!.bytes);
        final double decodedAspect = png.w / png.h;

        debugPrint('PROBE | ${c.label} | ${c.asset}');
        debugPrint('PROBE |   page.width x page.height      = '
            '${page.width.toStringAsFixed(0)} x ${page.height.toStringAsFixed(0)}');
        debugPrint('PROBE |   PdfPageImage.width x .height   = '
            '${img.width} x ${img.height}');
        debugPrint('PROBE |   DECODED PNG width x height     = '
            '${png.w} x ${png.h}  '
            '(${png.w > png.h ? "LANDSCAPE" : png.w < png.h ? "PORTRAIT" : "SQUARE"}, '
            'aspect ${decodedAspect.toStringAsFixed(3)})');

        // THE assertion this file was missing. A squeeze is exactly an aspect
        // that does not match the page's true shape, so this is the check that
        // makes the probe capable of failing.
        expect(
          decodedAspect,
          closeTo(c.aspect, 0.01),
          reason: 'decoded raster for ${c.asset} is ${png.w}x${png.h} '
              '(aspect ${decodedAspect.toStringAsFixed(3)}) but the page shape '
              'implies ${c.aspect.toStringAsFixed(3)}. Either the card was '
              're-exported (update the expectation AND the pdf_reference_screen '
              'header evidence) or the render path is squeezing it.',
        );

        // Orientation stated independently of the ratio, so a reciprocal-shaped
        // bug (the classic rotation squeeze) cannot slip past on a near miss.
        expect(
          png.w > png.h,
          c.aspect > 1,
          reason: 'orientation flipped for ${c.asset}',
        );

        await page.close();
        await doc.close();
      });
    }
  });

  // Encodes the risk narrated in _PdfReferenceScreenState._pageBuilder: that
  // builder is a hand-copy of pdfx's PRIVATE default page builder, so a pdfx
  // upgrade can change the defaults underneath it without any signal. Rather
  // than trusting a "kept in sync" comment, ask pdfx what its defaults ARE.
  testWidgets('pdfx default page scales still match the screen constants', (
    _,
  ) async {
    final PdfDocument doc = await PdfDocument.openAsset(
      'assets/reference-cards/top-20-checklist.pdf',
    );
    final PdfPage page = await doc.getPage(1);
    final PdfPageImage? img = await renderReferencePage(page);
    expect(img, isNotNull);

    // pdfx's OWN default builder, via its public constructor default.
    const PdfViewBuilders<DefaultBuilderOptions> defaults =
        PdfViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    );
    final PhotoViewGalleryPageOptions pdfxDefault = defaults.pageBuilder(
      // ignore: use_build_context_synchronously — no BuildContext is touched by
      // pdfx's default page builder; it only assembles a value object.
      _NullBuildContext(),
      Future<PdfPageImage>.value(img!),
      0,
      doc,
    );

    expect(pdfxDefault.minScale, PhotoViewComputedScale.contained);
    expect((pdfxDefault.minScale! as PhotoViewComputedScale).multiplier,
        kPdfMinZoomFactor,
        reason: 'pdfx changed its default minScale; update _pageBuilder');
    expect(pdfxDefault.maxScale, PhotoViewComputedScale.contained);
    expect((pdfxDefault.maxScale! as PhotoViewComputedScale).multiplier,
        kPdfMaxZoomFactor,
        reason: 'pdfx changed its default maxScale; update _pageBuilder');
    expect(pdfxDefault.initialScale, PhotoViewComputedScale.contained);
    expect((pdfxDefault.initialScale! as PhotoViewComputedScale).multiplier, 1.0,
        reason: 'pdfx changed its default initialScale; update _pageBuilder');

    await page.close();
    await doc.close();
  });
}

/// pdfx's default page builder never dereferences its [BuildContext] — it only
/// assembles a [PhotoViewGalleryPageOptions] value. This stand-in lets the drift
/// guard call it without pumping a widget tree.
class _NullBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
