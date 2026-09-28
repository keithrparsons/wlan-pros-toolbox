// CaptivePortalsExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/captive_portals_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/captive_portals_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kCaptivePortalsLesson.toolId, 'captive-portals-explained');
    expect(kCaptivePortalsLesson.route, AppRouter.captivePortalsExplained);
    expect(kCaptivePortalsExplainedToolId, 'captive-portals-explained');
  });

  runGuidedLessonSuite(
    lesson: kCaptivePortalsLesson,
    screen: const CaptivePortalsExplainedScreen(),
    figureCount: 15,
    keywords: <String>['captive portal', 'sign-in page'],
  );
}
