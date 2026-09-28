// TravelRoutersExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/travel_routers_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/travel_routers_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kTravelRoutersLesson.toolId, 'travel-routers-explained');
    expect(kTravelRoutersLesson.route, AppRouter.travelRoutersExplained);
    expect(kTravelRoutersExplainedToolId, 'travel-routers-explained');
  });

  runGuidedLessonSuite(
    lesson: kTravelRoutersLesson,
    screen: const TravelRoutersExplainedScreen(),
    figureCount: 20,
    keywords: <String>['travel router', 'hotel wi-fi'],
  );
}
