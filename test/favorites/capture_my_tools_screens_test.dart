// Screenshot harness for the My Tools feature. Tagged `capture`, so CI skips
// it (dart_test.yaml). Writes PNGs only with WRITE_FIGURES=1, into
// MY_TOOLS_SHOTS_DIR (default build/my_tools_shots):
//
//   WRITE_FIGURES=1 MY_TOOLS_SHOTS_DIR=/abs/path \
//     flutter test --tags capture test/favorites/capture_my_tools_screens_test.dart
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/data/tool_assets.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_controller.dart';
import 'package:wlan_pros_toolbox/favorites/my_tools_item.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/screens/home_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

import '../support/figure_write_gate.dart';

const List<String> _picks = <String>[
  'net-quality',
  'wifi-info',
  'ping',
  'dns-lookup',
  'fspl',
  'eirp',
  'link-budget',
  'subnet-planner',
  'cable-loss',
  'fresnel',
];

final GlobalKey _boundary = GlobalKey();

String get _outDir =>
    Platform.environment['MY_TOOLS_SHOTS_DIR'] ?? 'build/my_tools_shots';

Future<MyToolsController> _controller(int n) async {
  final MyToolsController c = MyToolsController();
  for (final String id in _picks.take(n)) {
    expect(await c.add(id), MyToolsAddResult.added, reason: id);
  }
  return c;
}

Future<void> _shoot(
  WidgetTester tester, {
  required String name,
  required Size size,
  required MyToolsController controller,
  required Widget home,
  ThemeData? theme,
  Future<void> Function(WidgetTester)? drive,
}) async {
  const double ratio = 2;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MyToolsScope(
        controller: controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? AppTheme.dark(),
          home: home,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (drive != null) {
    await drive(tester);
    await tester.pumpAndSettle();
  }
  // Let SVG tool icons decode.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();

  final RenderRepaintBoundary b =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await b.toImage(pixelRatio: ratio);
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (kWriteFigures) {
      Directory(_outDir).createSync(recursive: true);
      File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    // ignore: avoid_print
    print('WROTE $name.png ${image.width}x${image.height}');
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ToolAssets.ensureLoaded();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('01 home, phone, dark, ten tools', (WidgetTester tester) async {
    await _shoot(
      tester,
      name: '01-home-phone-dark-my-tools',
      size: const Size(390, 844),
      controller: await _controller(10),
      home: const HomeScreen(),
    );
  });

  testWidgets('02 list-is-full dialog from a long-press', (
    WidgetTester tester,
  ) async {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    await _shoot(
      tester,
      name: '02-list-full-dialog-phone-dark',
      size: const Size(390, 844),
      controller: await _controller(10),
      home: CategoryScreen(category: cat),
      drive: (WidgetTester t) async {
        // The first built row that is not already in My Tools.
        final ToolRow row = t
            .widgetList<ToolRow>(find.byType(ToolRow))
            .firstWhere((ToolRow r) => !_picks.contains(r.tool.id));
        await t.longPress(find.byWidget(row));
      },
    );
  });

  testWidgets('03 home edit mode, phone, light', (WidgetTester tester) async {
    await _shoot(
      tester,
      name: '03-home-edit-mode-phone-light',
      size: const Size(390, 844),
      controller: await _controller(4),
      home: const HomeScreen(),
      theme: AppTheme.light(),
      drive: (WidgetTester t) =>
          t.tap(find.byKey(const ValueKey<String>('my-tools-edit'))),
    );
  });

  testWidgets('04 home, desktop, dark, ten tools', (WidgetTester tester) async {
    await _shoot(
      tester,
      name: '04-home-desktop-dark-ten-tools',
      size: const Size(1280, 900),
      controller: await _controller(10),
      home: const HomeScreen(),
    );
  });

  testWidgets('05 home, 320 wide, dark, ten long names', (
    WidgetTester tester,
  ) async {
    final MyToolsController c = MyToolsController();
    for (final String id in <String>[
      'interferer-cost',
      'mesh-extenders-explained',
      'down-the-stack',
      'guest-discovery',
      'box-vs-hand',
      'location-rssi-ftm',
      'cameras-doorbells-explained',
      'devices-to-internet-explained',
      'wpa2-password',
      'db-rules',
    ]) {
      expect(await c.add(id), MyToolsAddResult.added, reason: id);
    }
    await _shoot(
      tester,
      name: '05-home-320-long-names-dark',
      size: const Size(320, 760),
      controller: c,
      home: const HomeScreen(),
    );
  });

  // One tool and one Educational Resources entry (2026-10-09). The resource
  // list loads from the bundled asset, as main.dart does.
  Future<MyToolsController> toolAndResource() async {
    await MyToolsResources.instance.load();
    expect(MyToolsResources.instance.isLoaded, isTrue);
    final MyToolsController c = MyToolsController();
    expect(await c.add('net-quality'), MyToolsAddResult.added);
    expect(await c.add(myToolsResourceId('wlan-pi')), MyToolsAddResult.added);
    return c;
  }

  testWidgets('06 home, phone, dark, one tool and one resource', (
    WidgetTester tester,
  ) async {
    await _shoot(
      tester,
      name: '06-home-phone-dark-tool-and-resource',
      size: const Size(390, 844),
      controller: await tester.runAsync(toolAndResource) as MyToolsController,
      home: const HomeScreen(),
    );
  });

  testWidgets('07 home, desktop, dark, one tool and one resource', (
    WidgetTester tester,
  ) async {
    await _shoot(
      tester,
      name: '07-home-desktop-dark-tool-and-resource',
      size: const Size(1280, 800),
      controller: await tester.runAsync(toolAndResource) as MyToolsController,
      home: const HomeScreen(),
    );
  });
}
