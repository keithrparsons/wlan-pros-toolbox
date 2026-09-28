// CamerasDoorbellsExplainedScreen: a Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/cameras_doorbells_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/cameras_doorbells_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kCamerasDoorbellsLesson.toolId, 'cameras-doorbells-explained');
    expect(kCamerasDoorbellsLesson.route, AppRouter.camerasDoorbellsExplained);
  });

  runGuidedLessonSuite(
    lesson: kCamerasDoorbellsLesson,
    screen: const CamerasDoorbellsExplainedScreen(),
    figureCount: 11,
    keywords: <String>['doorbell camera', 'baby monitor', 'upload'],
  );
}
