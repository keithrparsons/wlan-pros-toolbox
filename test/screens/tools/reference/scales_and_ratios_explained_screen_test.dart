// ScalesAndRatiosExplainedScreen: the Scales and Ratios, Explained Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/scales_and_ratios_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/scales_and_ratios_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kScalesAndRatiosLesson.toolId, 'scales-and-ratios-explained');
    expect(kScalesAndRatiosLesson.route, AppRouter.scalesAndRatiosExplained);
  });

  test(
    'the actual-size figure says so for the screen; the other keeps its caption',
    () {
      final List<LessonFigure> figs = lessonFigures(kScalesAndRatiosLesson);
      final LessonFigure f8 = figs.firstWhere(
        (LessonFigure f) => f.caption?.startsWith('**Figure 8.') ?? false,
      );
      expect(f8.caption, endsWith(' (actual size on the printed guide)'));
      final LessonFigure f1 = figs.firstWhere(
        (LessonFigure f) => f.caption?.startsWith('**Figure 1.') ?? false,
      );
      expect(f1.caption, endsWith('The drawing is not actual size.'));
      expect(
        figs.where(
          (LessonFigure f) =>
              f.caption?.contains('actual size on the printed guide') ?? false,
        ),
        hasLength(1),
      );
    },
  );

  runGuidedLessonSuite(
    lesson: kScalesAndRatiosLesson,
    screen: const ScalesAndRatiosExplainedScreen(),
    figureCount: 11,
    keywords: <String>['nanosecond', 'decibel', 'megabits'],
  );
}
