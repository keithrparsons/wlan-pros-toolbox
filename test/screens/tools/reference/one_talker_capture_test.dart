// One Talker per Channel: screenshots for visual review, and the book figure
// for Wireless, Explained ("why Wi-Fi is slow with everyone home"), on the
// Guest Discovery capture pattern.
//
// Renders, always asserts, and writes PNGs ONLY when asked, per
// test/support/figure_write_gate.dart:
//   WRITE_FIGURES=1 ONE_TALKER_OUT=<dir> flutter test --tags capture \
//     test/screens/tools/reference/one_talker_capture_test.dart
// Output (default build/one-talker-screens, gitignored):
//   lesson-<theme>-<width>-<state>.png   the whole lesson, phone and desktop
//   present-<theme>-<w>x<h>.png          the presenter layout, fullest state
//   book-<scene>-<theme>.png             the stage alone at 720 px, 2x
@Tags(<String>['capture'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/theme/app_tokens.dart';

import '../../../support/figure_write_gate.dart';
import '../../../widgets/presenter/presenter_test_support.dart';

final String _outDir =
    Platform.environment['ONE_TALKER_OUT'] ?? 'build/one-talker-screens';
const double _tall = 6400;

Future<void> _write(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  double ratio = 1,
}) async {
  if (!kWriteFigures) return;
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void _fullest(OneTalkerController k) => k
  ..shiftClientsA(20)
  ..setSecondAp(SecondAp.sameChannel)
  ..shiftClientsB(20)
  ..setSlowTalker(true)
  ..nextTurn();

/// The book figure's scenes: the same room as it fills up, then the second
/// access point on the same channel and on another.
final Map<String, void Function(OneTalkerController)> _book =
    <String, void Function(OneTalkerController)>{
      '4-devices': (OneTalkerController k) {},
      '12-devices': (OneTalkerController k) => k.shiftClientsA(8),
      'same-channel': (OneTalkerController k) =>
          k.setSecondAp(SecondAp.sameChannel),
      'other-channel': (OneTalkerController k) =>
          k.setSecondAp(SecondAp.otherChannel),
      'slow-device': (OneTalkerController k) => k.setSlowTalker(true),
    };

void main() {
  for (final bool light in <bool>[false, true]) {
    final String theme = light ? 'light' : 'dark';
    for (final double width in <double>[360, 390, 1024]) {
      testWidgets('lesson $theme ${width.toInt()}', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, _tall));
        tester.view.physicalSize = Size(width, _tall);
        tester.view.devicePixelRatio = 1;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.reset);
        final GlobalKey key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              home: const OneTalkerScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Where these facts come from'), findsOneWidget);
        await _write(tester, key, 'lesson-$theme-${width.toInt()}-open');
        final OneTalkerController k = tester
            .widget<OneTalkerStage>(find.byType(OneTalkerStage))
            .controller;
        _fullest(k);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _write(tester, key, 'lesson-$theme-${width.toInt()}-fullest');
        k
          ..reset()
          ..setSecondAp(SecondAp.otherChannel)
          ..nextTurn();
        await tester.pumpAndSettle();
        await _write(
          tester,
          key,
          'lesson-$theme-${width.toInt()}-two-channels',
        );
      });
    }

    for (final Size window in const <Size>[Size(1920, 1080), Size(1470, 923)]) {
      testWidgets('present $theme ${window.width.toInt()}', (tester) async {
        await tester.binding.setSurfaceSize(window);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        setWindow(tester, window);
        installFakeWindow();
        final GlobalKey key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              home: const OneTalkerScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Present'));
        await tester.pumpAndSettle();
        final OneTalkerController k = tester
            .widget<OneTalkerStage>(find.byType(OneTalkerStage).last)
            .controller;
        final String size = '${window.width.toInt()}x${window.height.toInt()}';
        await _write(tester, key, 'present-$theme-$size-open');
        _fullest(k);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _write(tester, key, 'present-$theme-$size-fullest');
      });
    }

    for (final MapEntry<String, void Function(OneTalkerController)> scene
        in _book.entries) {
      testWidgets('book figure ${scene.key} $theme', (tester) async {
        const double w = 720;
        await tester.binding.setSurfaceSize(const Size(w, 1400));
        tester.view.physicalSize = const Size(w, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.reset);
        final OneTalkerController k = OneTalkerController();
        addTearDown(k.dispose);
        scene.value(k);
        final GlobalKey key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: light ? AppTheme.light() : AppTheme.dark(),
            home: Builder(
              builder: (BuildContext context) => ColoredBox(
                color: context.colors.surface0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: RepaintBoundary(
                    key: key,
                    child: Material(
                      color: context.colors.surface0,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: OneTalkerStage(controller: k),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _write(tester, key, 'book-${scene.key}-$theme', ratio: 2);
      });
    }
  }
}
