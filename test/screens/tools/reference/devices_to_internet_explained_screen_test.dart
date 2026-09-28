// DevicesToInternetExplainedScreen: a Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/devices_to_internet_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/devices_to_internet_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kDevicesToInternetLesson.toolId, 'devices-to-internet-explained');
    expect(
      kDevicesToInternetLesson.route,
      AppRouter.devicesToInternetExplained,
    );
  });

  test('each step that says Check My Connection opens Test My Connection', () {
    // The guide's button name is Check My Connection; the screen behind it
    // is Test My Connection, which has no catalog tile (the home hero is its
    // door), so the link carries its own route.
    for (final LessonStep s in kDevicesToInternetLesson.steps) {
      final bool names = s.blocks.any(
        (LessonBlock b) =>
            b is! LessonToolLink &&
            lessonStrings(
              GuidedLesson(
                toolId: 'x',
                route: 'x',
                title: 'x',
                guideTitle: 'x',
                promise: 'x',
                steps: <LessonStep>[
                  LessonStep(number: '1', title: 'x', blocks: <LessonBlock>[b]),
                ],
              ),
            ).any((String t) => t.contains('Check My Connection')),
      );
      final List<LessonToolLink> links = s.blocks
          .whereType<LessonToolLink>()
          .where((LessonToolLink l) => l.toolId == 'test-my-connection')
          .toList();
      expect(links.length, names ? 1 : 0, reason: s.title);
      for (final LessonToolLink l in links) {
        expect(l.route, AppRouter.testMyConnection);
        expect(l.title, 'Test My Connection');
      }
    }
  });

  runGuidedLessonSuite(
    lesson: kDevicesToInternetLesson,
    screen: const DevicesToInternetExplainedScreen(),
    figureCount: 10,
    keywords: <String>['slow internet', 'wi-fi or internet'],
  );
}
