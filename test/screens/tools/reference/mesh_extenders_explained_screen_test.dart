// MeshExtendersExplainedScreen: a Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mesh_extenders_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/mesh_extenders_lesson.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route', () {
    expect(kMeshExtendersLesson.toolId, 'mesh-extenders-explained');
    expect(kMeshExtendersLesson.route, AppRouter.meshExtendersExplained);
  });

  test('every step that cites the Classroom model opens Repeaters and Mesh '
      'Backhaul', () {
    final List<String> citing = <String>[];
    final List<String> linked = <String>[];
    for (final LessonStep s in kMeshExtendersLesson.steps) {
      final String words = lessonStrings(
        GuidedLesson(
          toolId: 'x',
          route: 'x',
          title: 'x',
          guideTitle: 'x',
          promise: 'x',
          steps: <LessonStep>[s],
        ),
      ).join(' ');
      if (words.contains('Classroom')) citing.add(s.number);
      if (s.blocks.any(
        (LessonBlock b) => b is LessonToolLink && b.toolId == 'repeater-mesh',
      )) {
        linked.add(s.number);
      }
    }
    expect(citing, <String>['4', '6', '→']);
    expect(linked, citing);
  });

  runGuidedLessonSuite(
    lesson: kMeshExtendersLesson,
    screen: const MeshExtendersExplainedScreen(),
    figureCount: 11,
    keywords: <String>['mesh', 'extender', 'backhaul'],
  );
}
