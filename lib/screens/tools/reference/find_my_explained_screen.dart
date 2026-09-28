// Find My, Explained: a Wi-Fi Classroom Guided Lesson.
//
// Rebuilt for 1.11.0 on the shared Guided Lesson framework
// (lib/widgets/lesson/): the content is kFindMyLesson in
// lessons/find_my_lesson.dart, generated word for word from the guide's final
// approved text by tool/guide_to_lesson.py, and the figures are the guide's
// own SVGs, extracted by tool/extract_lesson_figures.py into
// assets/lesson-figures/find-my/. GuidedLessonScreen renders it on a phone and
// in Present mode.
//
// The tool id, route and this class name are unchanged from the first
// version of the lesson (2026-09-27), so the catalog, router, help entry and
// Field Manual still point here.

import 'package:flutter/material.dart';

import '../../../widgets/lesson/lesson.dart';
import 'lessons/find_my_lesson.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kFindMyExplainedToolId = 'find-my-explained';

class FindMyExplainedScreen extends StatelessWidget {
  const FindMyExplainedScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const GuidedLessonScreen(lesson: kFindMyLesson);
}
