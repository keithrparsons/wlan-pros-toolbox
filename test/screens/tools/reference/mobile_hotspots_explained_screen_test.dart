// MobileHotspotsExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mobile_hotspots_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/mobile_hotspots_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kMobileHotspotsLesson.toolId, 'mobile-hotspots-explained');
    expect(kMobileHotspotsLesson.route, AppRouter.mobileHotspotsExplained);
    expect(kMobileHotspotsExplainedToolId, 'mobile-hotspots-explained');
  });

  runGuidedLessonSuite(
    lesson: kMobileHotspotsLesson,
    screen: const MobileHotspotsExplainedScreen(),
    figureCount: 22,
    keywords: <String>['mobile hotspot', 'tethering'],
  );
}
