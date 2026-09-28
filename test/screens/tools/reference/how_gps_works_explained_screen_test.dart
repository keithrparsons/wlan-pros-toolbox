// HowGpsWorksExplainedScreen: the How GPS Works, Explained Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/how_gps_works_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/how_gps_works_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kHowGpsWorksLesson.toolId, 'how-gps-works-explained');
    expect(kHowGpsWorksLesson.route, AppRouter.howGpsWorksExplained);
  });

  runGuidedLessonSuite(
    lesson: kHowGpsWorksLesson,
    screen: const HowGpsWorksExplainedScreen(),
    figureCount: 14,
    keywords: <String>['gps', 'blue dot', 'satellite'],
  );
}
