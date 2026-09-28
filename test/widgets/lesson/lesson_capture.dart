// Screenshots of a Guided Lesson for visual review. Always renders and
// asserts; writes PNGs only when asked (test/support/figure_write_gate.dart):
//   WRITE_FIGURES=1 flutter test --tags capture \
//     test/screens/tools/reference/<slug>_explained_capture_test.dart
// Output: build/lesson-screens/<tool id>/ (gitignored):
//   step-<n>-dark.png / -light.png  one step with a figure, at a phone's
//                                   width, in each theme;
//   phone-dark.png / -light.png     the whole lesson at 390 wide;
//   present-<mode>-NN.png           every Present slide at 1920x1080.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../support/figure_write_gate.dart';
import '../presenter/presenter_test_support.dart';

final GlobalKey _key = GlobalKey();

Future<void> _write(String dir, String name, {double ratio = 2}) async {
  final RenderRepaintBoundary b =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await b.toImage(pixelRatio: ratio);
  final ByteData? bytes = await image.toByteData(
    format: ui.ImageByteFormat.png,
  );
  Directory(dir).createSync(recursive: true);
  File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// [figureStep] is the index of a step that carries a figure, for the
/// single-step review shot.
void runGuidedLessonCapture({
  required GuidedLesson lesson,
  required Widget screen,
  required int figureStep,
}) {
  final String dir = 'build/lesson-screens/${lesson.toolId}';

  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';

    testWidgets('${lesson.toolId}: step ${figureStep + 1} with its figure '
        '($mode)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.light() : AppTheme.dark(),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: _key,
                  child: Container(
                    color: context.colors.surface0,
                    padding: const EdgeInsets.all(16),
                    child: GuidedLessonScope(
                      controller: GuidedLessonController(lesson),
                      child: LessonStepView(lesson: lesson, step: figureStep),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LessonFigureView), findsWidgets);
      expect(tester.takeException(), isNull);
      if (kWriteFigures) {
        await tester.runAsync(
          () => _write(dir, 'step-${figureStep + 1}-$mode'),
        );
      }
    });

    testWidgets('${lesson.toolId}: the whole phone lesson ($mode)', (
      tester,
    ) async {
      const double tall = 30000;
      await tester.binding.setSurfaceSize(const Size(390, tall));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        RepaintBoundary(
          key: _key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: light ? AppTheme.light() : AppTheme.dark(),
            home: screen,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (kWriteFigures) {
        await tester.runAsync(() => _write(dir, 'phone-$mode', ratio: 1));
      }
    });

    testWidgets('${lesson.toolId}: every Present slide ($mode)', (
      tester,
    ) async {
      installFakeWindow();
      setWindow(tester, const Size(1920, 1080));
      await tester.pumpWidget(
        RepaintBoundary(
          key: _key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: light ? AppTheme.light() : AppTheme.dark(),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      final GuidedLessonController probe = GuidedLessonController(lesson);
      final int slides = probe.slides.length;
      probe.dispose();
      for (int i = 1; i <= slides; i++) {
        // Reveal one fact on each myth slide so the pair shows in review.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'slide $i');
        if (kWriteFigures) {
          await tester.runAsync(
            () => _write(
              dir,
              'present-$mode-${i.toString().padLeft(2, '0')}',
              ratio: 1,
            ),
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
    });
  }
}
