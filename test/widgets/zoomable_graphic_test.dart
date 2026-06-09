// Widget tests for ZoomableGraphic — the reusable tap-to-zoom wrapper that
// makes a tool concept graphic open a full-screen pinch-zoom + pan view.
//
// Covers the contract from Keith's 2026-06-08 request:
//   - the in-page child renders, plus a subtle magnifier affordance over it;
//   - the whole graphic is ONE labeled, operable button (a11y: VoiceOver lands
//     on a "Zoom graphic" control, not a decorative image);
//   - a tap opens a full-screen InteractiveViewer (minScale 1, maxScale 5) that
//     re-renders the graphic large via the call site's svgBuilder;
//   - the zoom view has a labeled close button and dismisses (X / back) so the
//     route pops and the in-page graphic is restored.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/zoomable_graphic.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host({String label = 'Zoom graphic'}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: Center(
        child: ZoomableGraphic(
          semanticLabel: label,
          svgBuilder: (BuildContext context, Size canvas) => SizedBox(
            key: const Key('zoom-canvas-child'),
            width: canvas.width,
            height: canvas.height,
            child: const ColoredBox(color: Color(0xFF222222)),
          ),
          child: const SizedBox(
            key: Key('in-page-child'),
            width: 320,
            height: 160,
            child: ColoredBox(color: Color(0xFF222222)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ZoomableGraphic', () {
    testWidgets('renders the in-page child and a magnifier affordance',
        (tester) async {
      await tester.pumpWidget(_host());

      expect(find.byKey(const Key('in-page-child')), findsOneWidget);
      // The subtle corner magnifier glyph.
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    });

    testWidgets('exposes one labeled, operable zoom button (a11y)',
        (tester) async {
      await tester.pumpWidget(_host(label: 'Zoom iec c13'));

      // The graphic is announced as a button with the call site's label.
      expect(
        find.bySemanticsLabel('Zoom iec c13'),
        findsOneWidget,
      );
    });

    testWidgets('tap opens a full-screen InteractiveViewer (1x..5x) that '
        're-renders the graphic large', (tester) async {
      await tester.pumpWidget(_host());

      await tester.tap(find.bySemanticsLabel('Zoom graphic'));
      await tester.pumpAndSettle();

      final InteractiveViewer viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.minScale, 1);
      expect(viewer.maxScale, 5);
      // The zoom view re-rendered the graphic via svgBuilder.
      expect(find.byKey(const Key('zoom-canvas-child')), findsOneWidget);
      // And a labeled close button is present.
      expect(find.bySemanticsLabel('Close zoom'), findsOneWidget);
    });

    testWidgets('close button dismisses the zoom view and restores the page',
        (tester) async {
      await tester.pumpWidget(_host());

      await tester.tap(find.bySemanticsLabel('Zoom graphic'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Close zoom'));
      await tester.pumpAndSettle();

      // Zoom view gone; the in-page graphic is back.
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byKey(const Key('in-page-child')), findsOneWidget);
    });
  });
}
