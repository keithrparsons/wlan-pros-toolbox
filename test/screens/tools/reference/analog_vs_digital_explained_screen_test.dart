// AnalogVsDigitalExplainedScreen: the Analog vs Digital, Explained Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/analog_vs_digital_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/analog_vs_digital_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kAnalogVsDigitalLesson.toolId, 'analog-vs-digital-explained');
    expect(kAnalogVsDigitalLesson.route, AppRouter.analogVsDigitalExplained);
  });

  runGuidedLessonSuite(
    lesson: kAnalogVsDigitalLesson,
    screen: const AnalogVsDigitalExplainedScreen(),
    figureCount: 12,
    keywords: <String>['analog', 'digital', 'modulation'],
  );
}
