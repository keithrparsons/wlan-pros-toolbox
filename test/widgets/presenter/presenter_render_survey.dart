// Render-proof capture of the Survey Walk (spec 26): presenter layout at
// 1470x923 and 1920x1080, both themes, in three states (1 NIC mid-walk with
// the door pause, 3 NICs priority with the signal layer, active with its
// limits), plus the phone-width stack. NOT a golden, NOT a gate; the
// `_render.dart` name keeps it out of the default `flutter test` run. Own
// file so parallel worktrees do not edit one list.
//
//   PRESENTER_RENDER_OUT=/some/dir \
//     flutter test test/widgets/presenter/presenter_render_survey.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/survey_walk_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/survey_walk_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import 'presenter_test_support.dart';

final String _outDir =
    Platform.environment['PRESENTER_RENDER_OUT'] ?? '/tmp/presenter-render';

Future<void> _shot(
  WidgetTester tester, {
  required bool light,
  required Size size,
  required String slug,
  required void Function(SurveyWalkController c) setup,
  bool present = true,
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
        home: const SurveyWalkScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pump(const Duration(milliseconds: 500));
  }
  setup(
    tester
        .widget<SurveyWalkStage>(find.byType(SurveyWalkStage).last)
        .controller,
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 500));
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
  if (present) {
    // ignore: avoid_print
    print('$slug controls overflow ${controlsOverflow(tester)}');
  }
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  final Map<String, void Function(SurveyWalkController)> states =
      <String, void Function(SurveyWalkController)>{
        'one-nic-door': (SurveyWalkController c) {
          c.doorPause = true;
          c.seek(c.result.durationS);
        },
        'priority-signal': (SurveyWalkController c) {
          c.radios = 3;
          c.algorithm = HoppingAlgorithm.priority;
          c.showSignal = true;
          c.seek(c.result.durationS * 0.7);
        },
        'active': (SurveyWalkController c) {
          c.surveyType = SurveyType.active;
          c.seek(24);
        },
        'all-channels-percycle': (SurveyWalkController c) {
          c.shownChannel = null;
          c.timestamp = TimestampMode.perCycle;
          c.seek(c.result.durationS * 0.8);
        },
      };

  testWidgets('survey walk', (WidgetTester tester) async {
    for (final bool light in <bool>[false, true]) {
      final String theme = light ? 'light' : 'dark';
      for (final Size s in const <Size>[Size(1470, 923), Size(1920, 1080)]) {
        for (final MapEntry<String, void Function(SurveyWalkController)> e
            in states.entries) {
          await _shot(
            tester,
            light: light,
            size: s,
            slug:
                'survey-walk-$theme-${s.width.toInt()}x${s.height.toInt()}-'
                '${e.key}',
            setup: e.value,
          );
        }
      }
      await _shot(
        tester,
        light: light,
        size: const Size(1024, 2400),
        slug: 'survey-walk-$theme-1024-phone-stack',
        present: false,
        setup: (SurveyWalkController c) {
          c.doorPause = true;
          c.showSignal = true;
          c.seek(c.result.durationS);
        },
      );
    }
  });
}
