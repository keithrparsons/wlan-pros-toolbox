// Render-proof capture for the "where you test throughput along the path
// changes the result" reference card on the Speed Test Services screen (NOT a
// golden test). Writes PNG snapshots to the myPKA Deliverables folder so Vera
// (and Keith) can eyeball the embedded dark-baked diagram card in BOTH themes
// without a device build.
//
// The point of capturing BOTH themes: the diagram is a pre-rendered raster, so
// it cannot take the §8.20.7 light-mode per-mark swap. It is mounted on an
// ALWAYS-DARK surface card (AppColorScheme.dark surface1, #222222) in both
// themes, so the dark capture and the light capture should show the SAME dark
// card — only the surrounding screen canvas and the caption text change. These
// two PNGs prove the card never reads inverted on a light canvas.
//
// This is a capture utility, not a regression gate. Run it explicitly:
//   flutter test test/screens/tools/reference/throughput_where_card_render.dart
// Renders use the production theme + the bundled typefaces loaded by
// flutter_test_config.dart, so the PNGs reflect shipping pixels. The real
// bundled PNG is precached on the live event loop (runAsync) so it decodes and
// paints rather than rendering as an empty box.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/speedtest_logos.dart';
import 'package:wlan_pros_toolbox/data/throughput_where_diagram.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/speedtest_services_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _outDir =
    '/Users/keithparsons/Documents/myPKA/Deliverables/'
    '2026-06-10-throughput-testing-where/in-app-renders';

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String filename,
) async {
  final RenderRepaintBoundary boundary = boundaryKey.currentContext!
      .findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? bytes =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final File out = File('$_outDir/$filename');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _renderCard(
  WidgetTester tester,
  ThemeData theme,
  String themeName,
) async {
  // The card resolver gates on the manifest; mark the asset bundled so the card
  // renders. (The capture run has the real asset in the test bundle.)
  ThroughputWhereDiagram.debugSetBundled(<String>{
    ThroughputWhereDiagram.assetPath,
  });
  SpeedtestLogos.debugSetBundledAssets(<String>{});
  addTearDown(() {
    ThroughputWhereDiagram.debugReset();
    SpeedtestLogos.debugReset();
  });

  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final GlobalKey boundaryKey = GlobalKey();
  final Widget app = RepaintBoundary(
    key: boundaryKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const Material(child: _CardHost()),
    ),
  );

  // Precache the real bundled PNG on the live event loop so it decodes and the
  // Image.asset paints actual pixels (not an empty box) in the capture.
  await tester.runAsync(() async {
    await tester.pumpWidget(app);
    final BuildContext context = tester.element(find.byType(_CardHost));
    await precacheImage(
      const AssetImage(
          'assets/tool-diagrams/throughput-testing-where/'
          'throughput-testing-where-dark.png'),
      context,
    );
  });
  await tester.pumpAndSettle();

  await _capture(tester, boundaryKey, 'throughput-where-card_$themeName.png');
}

/// Mounts the production [ThroughputWhereDiagramCard] on the live screen
/// surface, padded the way the screen pads its scroll body, so the capture
/// shows exactly the embedded card + caption a user sees.
class _CardHost extends StatelessWidget {
  const _CardHost();

  @override
  Widget build(BuildContext context) {
    final Color canvas = Theme.of(context).scaffoldBackgroundColor;
    return Container(
      color: canvas,
      padding: const EdgeInsets.all(16),
      child: const Align(
        alignment: Alignment.topCenter,
        child: ThroughputWhereDiagramCard(),
      ),
    );
  }
}

void main() {
  testWidgets('render dark', (tester) async {
    await _renderCard(tester, AppTheme.dark(), 'dark');
  });
  testWidgets('render light', (tester) async {
    await _renderCard(tester, AppTheme.light(), 'light');
  });
}
