// Render-proof capture of the RF presenter tools (NOT a golden, NOT a gate):
// FSPL Simulator, Rate vs Range, 6 GHz Power and PSD, Wi-Fi Through a Wall
// and Multipath Simulator. Same pattern as presenter_render.dart, kept in its
// own file so sibling tool conversions do not collide in one test body. The
// `_render.dart` suffix keeps it out of the default `flutter test` run:
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_rf.dart
//
// Widget tests prove nothing overflows; these frames are for looking at the
// projector layout at 1470x923 (a MacBook Air in full screen) in both themes.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/six_ghz_psd_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wifi_through_a_wall_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/six_ghz_psd_math.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

/// Optional filter: only tools whose slug contains this.
final String _only = Platform.environment['PRESENTER_RENDER_ONLY'] ?? '';

const List<Size> _sizes = <Size>[Size(1470, 923)];

Future<void> _shot(
  WidgetTester tester, {
  required Widget screen,
  required bool light,
  required Size size,
  required String slug,
  Future<void> Function()? setup,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  installFakeWindow();
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: screen,
      ),
    ),
  );
  Future<void> wait() async {
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  await wait();
  await tester.tap(find.text('Present'));
  await wait();
  await setup?.call();
  await wait();
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File out = File('$_outDir/$slug.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('$slug controls overflow ${controlsOverflow(tester)}');
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
}

String _slug(String tool, bool light, Size s, [String extra = '']) =>
    '$tool-${light ? 'light' : 'dark'}-${s.width.toInt()}x${s.height.toInt()}'
    '${extra.isEmpty ? '' : '-$extra'}';

void main() {
  testWidgets('fspl', (WidgetTester tester) async {
    if (!'fspl'.contains(_only)) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const FsplSimulatorScreen(),
          light: light,
          size: s,
          slug: _slug('fspl', light, s),
          setup: () async {
            final FsplSimModel m = tester
                .widget<FsplStage>(find.byType(FsplStage).last)
                .model;
            m
              ..setIndoor(true)
              ..setMeasuredText(rssi: '-71', dist: '40')
              ..setCursor(20);
          },
        );
      }
    }
  });

  testWidgets('rate vs range', (WidgetTester tester) async {
    if (!'rate-vs-range'.contains(_only)) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const RateVsRangeScreen(),
          light: light,
          size: s,
          slug: _slug('rate-vs-range', light, s),
          setup: () async {
            final RateVsRangeModel m = tester
                .widget<RateVsRangeStage>(find.byType(RateVsRangeStage).last)
                .model;
            m.setClientDistance(18);
          },
        );
      }
    }
  });

  testWidgets('six ghz psd', (WidgetTester tester) async {
    if (!'six-ghz-psd'.contains(_only)) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        for (final (bool all, PsdView view) in <(bool, PsdView)>[
          (false, PsdView.eirp),
          (true, PsdView.eirp),
          (false, PsdView.spectrum),
        ]) {
          await _shot(
            tester,
            screen: const SixGhzPsdScreen(),
            light: light,
            size: s,
            slug: _slug(
              'six-ghz-psd',
              light,
              s,
              all
                  ? 'all-classes'
                  : view == PsdView.spectrum
                  ? 'spectrum'
                  : '',
            ),
            setup: () async {
              final SixGhzPsdModel m = tester
                  .widget<SixGhzPsdStage>(find.byType(SixGhzPsdStage).last)
                  .model;
              if (all) {
                for (final PowerClass c in m.regionClasses) {
                  m.setShown(c, true);
                }
              }
              m
                ..setWidthIndex(3)
                ..setView(view);
            },
          );
        }
      }
    }
  });

  testWidgets('wifi through a wall', (WidgetTester tester) async {
    if (!'wall'.contains(_only)) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        await _shot(
          tester,
          screen: const MediaQuery(
            data: MediaQueryData(
              size: Size(1470, 923),
              disableAnimations: true,
            ),
            child: WifiThroughAWallScreen(),
          ),
          light: light,
          size: s,
          slug: _slug('wifi-through-a-wall', light, s),
        );
      }
    }
  });

  testWidgets('multipath', (WidgetTester tester) async {
    if (!'multipath'.contains(_only)) return;
    for (final bool light in <bool>[false, true]) {
      for (final Size s in _sizes) {
        for (final MultipathMode mode in MultipathMode.values) {
          await _shot(
            tester,
            screen: MultipathSimulatorScreen(initialMode: mode),
            light: light,
            size: s,
            slug: _slug('multipath', light, s, mode.name),
          );
        }
      }
    }
  });
}
