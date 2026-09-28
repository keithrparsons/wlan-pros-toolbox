// TapTouchNearExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/tap_touch_near_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/tap_touch_near_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kTapTouchNearLesson.toolId, 'tap-touch-near-explained');
    expect(kTapTouchNearLesson.route, AppRouter.tapTouchNearExplained);
    expect(kTapTouchNearExplainedToolId, 'tap-touch-near-explained');
  });

  runGuidedLessonSuite(
    lesson: kTapTouchNearLesson,
    screen: const TapTouchNearExplainedScreen(),
    figureCount: 11,
    keywords: <String>['tap to pay', 'nfc'],
  );
}
