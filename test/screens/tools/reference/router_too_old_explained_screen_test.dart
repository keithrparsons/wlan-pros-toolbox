// RouterTooOldExplainedScreen: a Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/router_too_old_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/router_too_old_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kRouterTooOldLesson.toolId, 'router-too-old-explained');
    expect(kRouterTooOldLesson.route, AppRouter.routerTooOldExplained);
  });

  runGuidedLessonSuite(
    lesson: kRouterTooOldLesson,
    screen: const RouterTooOldExplainedScreen(),
    figureCount: 11,
    keywords: <String>['router too old', 'firmware'],
  );
}
