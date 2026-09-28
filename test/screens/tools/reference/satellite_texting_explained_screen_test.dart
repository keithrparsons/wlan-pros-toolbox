// SatelliteTextingExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/satellite_texting_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/satellite_texting_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kSatelliteTextingLesson.toolId, 'satellite-texting-explained');
    expect(kSatelliteTextingLesson.route, AppRouter.satelliteTextingExplained);
    expect(kSatelliteTextingExplainedToolId, 'satellite-texting-explained');
  });

  runGuidedLessonSuite(
    lesson: kSatelliteTextingLesson,
    screen: const SatelliteTextingExplainedScreen(),
    figureCount: 8,
    keywords: <String>['satellite texting', 'sos'],
  );
}
