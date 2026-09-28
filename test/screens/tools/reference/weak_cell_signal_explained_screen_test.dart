// WeakCellSignalExplainedScreen: the Weak Cell Signal at Home, Explained Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/weak_cell_signal_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/weak_cell_signal_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kWeakCellSignalLesson.toolId, 'weak-cell-signal-explained');
    expect(kWeakCellSignalLesson.route, AppRouter.weakCellSignalExplained);
  });

  runGuidedLessonSuite(
    lesson: kWeakCellSignalLesson,
    screen: const WeakCellSignalExplainedScreen(),
    figureCount: 13,
    keywords: <String>[
      'weak cell signal',
      'signal booster',
      'network extender',
    ],
  );
}
