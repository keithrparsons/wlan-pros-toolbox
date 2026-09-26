// Render-proof capture of the Wi-Fi Classroom home section (NOT a golden, NOT
// a gate). The `_render.dart` suffix keeps it out of the default run:
//
//   CLASSROOM_RENDER_OUT=/some/dir \
//     flutter test test/screens/render/classroom_section_render.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_assets.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/services/educational/educational_resources_service.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/screens/search_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/educational/educational_resources_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

final String _outDir =
    Platform.environment['CLASSROOM_RENDER_OUT'] ?? '/tmp/classroom-render';

ToolCategory get _classroom =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == 'wifi-classroom');

Future<void> _shoot(
  WidgetTester tester,
  String slug,
  Size size,
  bool light,
  Widget home, {
  Future<void> Function()? before,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The app loads the icon manifest in main(); do the same so rows show their
  // real per-tool icons rather than the fallback bolt.
  await tester.runAsync(ToolAssets.ensureLoaded);
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        routes: <String, WidgetBuilder>{...AppRouter.routes}
          ..remove(AppRouter.home),
        home: home,
      ),
    ),
  );
  // Assets load on real I/O; give them a moment, then settle with a bounded
  // pump (the directory's loading spinner never settles on its own).
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (before != null) await before();
  expect(tester.takeException(), isNull);
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File out = File('$_outDir/$slug.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';
    for (final Size size in const <Size>[Size(390, 2000), Size(1280, 1400)]) {
      final String w = '${size.width.toInt()}';
      testWidgets('home-$w-$mode', (WidgetTester tester) async {
        await _shoot(tester, 'home-$w-$mode', size, light, const HomeScreen());
      });
      testWidgets('section-$w-$mode', (WidgetTester tester) async {
        await _shoot(
          tester,
          'section-$w-$mode',
          Size(size.width, size.width < 600 ? 8400 : 5600),
          light,
          CategoryScreen(category: _classroom),
        );
      });
      testWidgets('edu-$w-$mode', (WidgetTester tester) async {
        await _shoot(
          tester,
          'educational-resources-$w-$mode',
          Size(size.width, 1400),
          light,
          EducationalResourcesScreen(
            service: EducationalResourcesService.fromJson(
              File(kEducationalResourcesAsset).readAsStringSync(),
            ),
          ),
        );
      });
      testWidgets('search-$w-$mode', (WidgetTester tester) async {
        await _shoot(
          tester,
          'search-checklist-$w-$mode',
          Size(size.width, 1400),
          light,
          const SearchScreen(initialQuery: 'checklist'),
        );
      });
    }
  }
}
