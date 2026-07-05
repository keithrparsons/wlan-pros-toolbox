// Tests for ReferencePdfDownloadCard — the "Download PDF" (save/share) control
// on every Field & Trade Reference plate screen (2026-07-05).
//
// Coverage:
//   * the control renders its "Download PDF" label + the download glyph, in both
//     the dark and light themes, with no overflow;
//   * tapping it invokes the share/save seam with the RIGHT bundled asset path
//     and the clean, title-derived filename (WLAN-Pros-<slug>.pdf) — the wiring
//     contract that guarantees the correct plate downloads;
//   * a failing share channel degrades HONESTLY — no crash, no thrown exception
//     surfaced to the framework (GL-005).
//
// The share seam is injected as a fake so the tests never touch a real asset
// bundle or a platform share channel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/pdf_download.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/reference_pdf_download.dart';

void main() {
  late List<({String assetPath, String title})> calls;

  Future<void> fakeShare({
    required String assetPath,
    required String title,
    ShareOrigin? shareOrigin,
  }) async {
    calls.add((assetPath: assetPath, title: title));
  }

  setUp(() => calls = <({String assetPath, String title})>[]);

  Widget harness({
    Brightness brightness = Brightness.dark,
    PdfShareFn? shareFn,
    String assetPath = 'assets/reference-pdf/enclosure-ratings.pdf',
    String title = 'Enclosure Ratings',
  }) =>
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(
          body: ReferencePdfDownloadCard(
            assetPath: assetPath,
            title: title,
            shareFn: shareFn ?? fakeShare,
          ),
        ),
      );

  testWidgets('renders the "Download PDF" label + the download glyph', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
  });

  testWidgets(
      'tapping invokes the seam with the RIGHT asset path + clean filename',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Download PDF'));
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.assetPath, 'assets/reference-pdf/enclosure-ratings.pdf');
    // The title is what the seam slugifies into WLAN-Pros-<slug>.pdf.
    expect(calls.single.title, 'Enclosure Ratings');
    expect(
      pdfDownloadFilename(calls.single.title),
      'WLAN-Pros-Enclosure-Ratings.pdf',
    );
  });

  testWidgets('passes the exact per-plate asset + title it is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        assetPath: 'assets/reference-pdf/led-master-comparison.pdf',
        title: 'LED Decoder',
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Download PDF'));
    await tester.pump();

    expect(
      calls.single.assetPath,
      'assets/reference-pdf/led-master-comparison.pdf',
    );
    expect(pdfDownloadFilename(calls.single.title), 'WLAN-Pros-LED-Decoder.pdf');
  });

  testWidgets('a failing share channel degrades honestly (no crash)', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        shareFn: ({
          required String assetPath,
          required String title,
          ShareOrigin? shareOrigin,
        }) async =>
            throw Exception('share channel unavailable'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Download PDF'));
    await tester.pump();

    // The honest failure is a screen-reader announcement, not a thrown error.
    expect(tester.takeException(), isNull);
  });

  testWidgets('builds in the light theme with no overflow', (tester) async {
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(harness(brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      expect(find.text('Download PDF'), findsOneWidget);
    }
  });
}
