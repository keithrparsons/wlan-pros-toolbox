// FindMyExplainedScreen: the Guided Lesson rebuilt on the shared framework for 1.11.0.
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/find_my_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/find_my_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are unchanged from the first version', () {
    expect(kFindMyLesson.toolId, 'find-my-explained');
    expect(kFindMyLesson.route, AppRouter.findMyExplained);
  });

  runGuidedLessonSuite(
    lesson: kFindMyLesson,
    screen: const FindMyExplainedScreen(),
    figureCount: 11,
    keywords: <String>['find my', 'airtag'],
  );
}
