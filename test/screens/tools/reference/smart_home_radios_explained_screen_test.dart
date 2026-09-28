// SmartHomeRadiosExplainedScreen: a Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/smart_home_radios_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/smart_home_radios_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kSmartHomeRadiosLesson.toolId, 'smart-home-radios-explained');
    expect(kSmartHomeRadiosLesson.route, AppRouter.smartHomeRadiosExplained);
  });

  runGuidedLessonSuite(
    lesson: kSmartHomeRadiosLesson,
    screen: const SmartHomeRadiosExplainedScreen(),
    figureCount: 13,
    keywords: <String>['matter', 'thread', 'zigbee'],
  );
}
