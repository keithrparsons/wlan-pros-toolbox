// HomeInternetExplainedScreen: the Guided Lesson rebuilt on the shared framework for 1.11.0.
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/home_internet_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/home_internet_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are unchanged from the first version', () {
    expect(kHomeInternetLesson.toolId, 'home-internet-explained');
    expect(kHomeInternetLesson.route, AppRouter.homeInternetExplained);
  });

  runGuidedLessonSuite(
    lesson: kHomeInternetLesson,
    screen: const HomeInternetExplainedScreen(),
    figureCount: 18,
    keywords: <String>['home internet'],
  );
}
