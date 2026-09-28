// StarlinkExplainedScreen: the Guided Lesson rebuilt on the shared framework for 1.11.0.
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/starlink_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/starlink_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are unchanged from the first version', () {
    expect(kStarlinkLesson.toolId, 'starlink-explained');
    expect(kStarlinkLesson.route, AppRouter.starlinkExplained);
  });

  runGuidedLessonSuite(
    lesson: kStarlinkLesson,
    screen: const StarlinkExplainedScreen(),
    figureCount: 13,
    keywords: <String>['starlink'],
  );
}
