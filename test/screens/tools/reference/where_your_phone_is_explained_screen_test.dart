// WhereYourPhoneIsExplainedScreen: the How Your Phone Knows Where It Is, Explained Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/where_your_phone_is_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/where_your_phone_is_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kWhereYourPhoneIsLesson.toolId, 'where-your-phone-is-explained');
    expect(kWhereYourPhoneIsLesson.route, AppRouter.whereYourPhoneIsExplained);
  });

  test('FLP is credited to David Coleman, word for word', () {
    final String all = lessonStrings(kWhereYourPhoneIsLesson).join(' ');
    expect(
      all,
      contains(
        'David Coleman calls this blending **Fused Location Positioning**.',
      ),
    );
    expect(all, contains('Two-step idea after David Coleman.'));
  });

  runGuidedLessonSuite(
    lesson: kWhereYourPhoneIsLesson,
    screen: const WhereYourPhoneIsExplainedScreen(),
    figureCount: 11,
    keywords: <String>['location', 'wi-fi positioning', 'nomap'],
  );
}
