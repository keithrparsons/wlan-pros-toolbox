// WifiOnPlanesExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lesson_parts.dart'
    show LessonSources;
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_on_planes_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/wifi_on_planes_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kWifiOnPlanesLesson.toolId, 'wifi-on-planes-explained');
    expect(kWifiOnPlanesLesson.route, AppRouter.wifiOnPlanesExplained);
    expect(kWifiOnPlanesExplainedToolId, 'wifi-on-planes-explained');
  });

  testWidgets('a source that names a document in italics shows no markup', (
    tester,
  ) async {
    // This guide's sources cite Apple pages by title in italics
    // (__Choose iPhone settings for travel__); the list once showed the
    // underscores.
    final List<String> items = <String>[
      for (final LessonStep s in kWifiOnPlanesLesson.steps)
        for (final LessonBlock b in s.blocks)
          if (b is LessonSourceList) ...b.items,
    ];
    expect(items.any((String i) => i.contains('__')), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: LessonSources(items)),
        ),
      ),
    );
    expect(find.textContaining('__', findRichText: true), findsNothing);
    expect(
      find.textContaining(
        'Choose iPhone settings for travel',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  runGuidedLessonSuite(
    lesson: kWifiOnPlanesLesson,
    screen: const WifiOnPlanesExplainedScreen(),
    figureCount: 11,
    keywords: <String>['airplane mode', 'in-flight wi-fi'],
  );
}
