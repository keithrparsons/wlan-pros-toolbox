// OBJECTIVE rotation probe — renders 3 representative cards through the EXACT
// same pdfx render call PdfReferenceScreen uses, decodes the resulting PNG, and
// prints the TRUE pixel dimensions of the raster. This is evidence, not
// reasoning: a correctly rotation-honored bubble-diagram must decode to a
// LANDSCAPE raster (wider than tall, ~792:612 ≈ 1.29:1).
//
// Run: flutter test integration_test/pdf_rotation_probe_test.dart -d macos
//
// For each card we report:
//   page.width / page.height        — pdfx MediaBox dims (Apple path ignores /Rotate)
//   PdfPageImage.width / .height     — what the plugin REPORTS for the raster
//   decoded PNG image.width/.height  — the ACTUAL raster pixels (ground truth)

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

  const List<({String label, String asset})> cards =
      <({String label, String asset})>[
    (label: 'ROTATED (/Rotate 90)', asset: 'assets/reference-cards/bubble-diagram.pdf'),
    (label: 'NATIVE-LANDSCAPE', asset: 'assets/reference-cards/channel-allocations-5ghz.pdf'),
    (label: 'PORTRAIT', asset: 'assets/reference-cards/top-20-checklist.pdf'),
  ];

  group('PDF rotation probe — true raster dimensions', () {
    for (final ({String label, String asset}) c in cards) {
      testWidgets('${c.label} — ${c.asset}', (_) async {
        final PdfDocument doc = await PdfDocument.openAsset(c.asset);
        final PdfPage page = await doc.getPage(1);

        // EXACT screen render path.
        final PdfPageImage? img = await renderReferencePage(page);
        expect(img, isNotNull, reason: 'render returned null for ${c.asset}');

        final ({int w, int h}) png = await _decodedPngSize(img!.bytes);

        debugPrint('PROBE | ${c.label} | ${c.asset}');
        debugPrint('PROBE |   page.width x page.height      = '
            '${page.width.toStringAsFixed(0)} x ${page.height.toStringAsFixed(0)}');
        debugPrint('PROBE |   PdfPageImage.width x .height   = '
            '${img.width} x ${img.height}');
        debugPrint('PROBE |   DECODED PNG width x height     = '
            '${png.w} x ${png.h}  '
            '(${png.w > png.h ? "LANDSCAPE" : png.w < png.h ? "PORTRAIT" : "SQUARE"}, '
            'aspect ${(png.w / png.h).toStringAsFixed(3)})');

        await page.close();
        await doc.close();
      });
    }
  });
}
