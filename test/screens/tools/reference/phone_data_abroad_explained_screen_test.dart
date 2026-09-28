// PhoneDataAbroadExplainedScreen: a Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/phone_data_abroad_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/phone_data_abroad_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kPhoneDataAbroadLesson.toolId, 'phone-data-abroad-explained');
    expect(kPhoneDataAbroadLesson.route, AppRouter.phoneDataAbroadExplained);
  });

  runGuidedLessonSuite(
    lesson: kPhoneDataAbroadLesson,
    screen: const PhoneDataAbroadExplainedScreen(),
    figureCount: 13,
    keywords: <String>['esim', 'roaming'],
  );
}
