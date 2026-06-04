// Widget tests for the PDF reference card screen's share/download action
// (Ticket 4).
//
// The pdfx PdfView body cannot render in the headless flutter_test environment
// (it needs native PDFKit), but the AppBar and its share action are in the
// widget tree independent of the document load state, so these tests assert the
// action's presence, semantics, and wiring without ever touching pdfx or the
// platform share channel. The share implementation is injected as a fake via
// the screen's `shareFn` seam.

import 'package:flutter/material.dart';
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
  });

  testWidgets('the share action exposes its tooltip/label to AT', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    // The IconButton's tooltip doubles as the accessible label.
    expect(find.byTooltip('Share or download'), findsOneWidget);
  });

  testWidgets('tapping the share action invokes the share seam with the '
      'card asset path and title', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.assetPath, 'assets/reference-cards/top-20-checklist.pdf');
    expect(calls.single.title, 'Top 20 Wi-Fi Checklist');
  });

  testWidgets('the share action is focusable (inherits the global ring path)', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    final FocusNode node = Focus.of(
      tester.element(find.byIcon(Icons.ios_share)),
    );
    // A live, enabled IconButton is reachable by keyboard focus traversal.
    expect(node.canRequestFocus, isTrue);
  });
}
