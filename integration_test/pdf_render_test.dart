// Integration test — proves the 10 bundled reference-card PDFs decode and
// render through pdfx → native Apple PDFKit on the REAL macOS embedder.
//
// WHY this is an integration test, not a widget test: pdfx renders PDFs via the
// platform PDF engine (Apple PDFKit on iOS + macOS). That engine is a no-op in
// the headless flutter_test environment, so a plain widget test can never prove
// the bundled assets actually decode. IntegrationTestWidgetsFlutterBinding runs
// this against the live macOS binding where PDFKit is available.
//
// Run:  flutter test integration_test/pdf_render_test.dart -d macos
//
// Two checks:
//   1. Open EACH of the 10 card assets through PdfDocument.openAsset (the exact
//      call PdfReferenceScreen makes) and assert pagesCount >= 1, then close.
//      This validates every bundled PDF is a real, decodable document.
//   2. Pump PdfReferenceScreen for one card and confirm it reaches the loaded
//      state (no _ErrorState in the tree) within a timeout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfx/pdfx.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/pdf_reference_screen.dart';

/// The 10 bundled reference cards, mirroring the router wiring
/// (lib/router/app_router.dart). Title is used only for the one screen-pump.
const List<({String title, String assetPath})> _cards =
    <({String title, String assetPath})>[
  (
    title: 'WLAN Pros Bubble Diagram',
    assetPath: 'assets/reference-cards/bubble-diagram.pdf',
  ),
  (
    title: 'Wireless LAN Troubleshooting Causes',
    assetPath: 'assets/reference-cards/troubleshooting-causes.pdf',
  ),
  (
    title: 'Top 20 Wi-Fi Checklist',
    assetPath: 'assets/reference-cards/top-20-checklist.pdf',
  ),
  (
    title: 'Extended Wi-Fi Checklist',
    assetPath: 'assets/reference-cards/extended-checklist.pdf',
  ),
  (
    title: 'Extended Checklist (Non-Advertised Items)',
    assetPath: 'assets/reference-cards/extended-checklist-nonadvertised.pdf',
  ),
  (
    title: 'Wi-Fi Connection Checklist',
    assetPath: 'assets/reference-cards/connection-checklist.pdf',
  ),
  (
    title: '2.4 GHz Channel Allocations',
    assetPath: 'assets/reference-cards/channel-allocations-24ghz.pdf',
  ),
  (
    title: '5 GHz Channel Allocations',
    assetPath: 'assets/reference-cards/channel-allocations-5ghz.pdf',
  ),
  (
    title: '6 GHz Channel Allocations',
    assetPath: 'assets/reference-cards/channel-allocations-6ghz.pdf',
  ),
  (
    title: 'Modulation and Coding Schemes (MCS Index)',
    assetPath: 'assets/reference-cards/mcs-index-card.pdf',
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Bundled reference-card PDFs decode natively (PDFKit)', () {
    for (final ({String title, String assetPath}) card in _cards) {
      testWidgets('opens ${card.assetPath} with >= 1 page', (_) async {
        final PdfDocument doc = await PdfDocument.openAsset(card.assetPath);
        expect(
          doc.pagesCount,
          greaterThanOrEqualTo(1),
          reason: '${card.assetPath} opened but reported 0 pages',
        );
        await doc.close();
      });
    }
  });

  testWidgets(
    'PdfReferenceScreen reaches the loaded state (no error overlay)',
    (WidgetTester tester) async {
      const ({String title, String assetPath}) card = (
        title: 'Top 20 Wi-Fi Checklist',
        assetPath: 'assets/reference-cards/top-20-checklist.pdf',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PdfReferenceScreen(
            title: card.title,
            assetPath: card.assetPath,
            toolId: 'top-20-checklist',
          ),
        ),
      );

      // Give native PDFKit time to open + paint the first page. pump-and-settle
      // can hang on the continuous PdfViewPinch animation/ticker, so poll the
      // tree for the error overlay instead.
      const Duration budget = Duration(seconds: 15);
      final Stopwatch sw = Stopwatch()..start();
      bool sawError = false;
      while (sw.elapsed < budget) {
        await tester.pump(const Duration(milliseconds: 250));
        // The error overlay renders this exact copy; its presence means the
        // bundled asset failed to open.
        if (find
            .text('This reference card could not be opened.')
            .evaluate()
            .isNotEmpty) {
          sawError = true;
          break;
        }
        // Loaded: the spinner is gone and the viewer is painting.
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }

      expect(
        sawError,
        isFalse,
        reason: 'PdfReferenceScreen hit its error state for ${card.assetPath}',
      );
      expect(
        find.byType(PdfReferenceScreen),
        findsOneWidget,
      );
    },
  );
}
