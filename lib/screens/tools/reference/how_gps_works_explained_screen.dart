// How GPS Works, Explained: a Wireless Classroom Guided Lesson.
//
// Built for 1.11.0 on the shared Guided Lesson framework (lib/widgets/lesson/):
// the content is kHowGpsWorksLesson in lessons/how_gps_works_lesson.dart, generated word for
// word from the guide's final approved text by tool/guide_to_lesson.py, and
// the figures are the guide's own SVGs, extracted by
// tool/extract_lesson_figures.py into assets/lesson-figures/how-gps-works/.
// GuidedLessonScreen renders it on a phone and in Present mode.

import 'package:flutter/material.dart';

import '../../../widgets/lesson/lesson.dart';
import 'lessons/how_gps_works_lesson.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kHowGpsWorksExplainedToolId = 'how-gps-works-explained';

class HowGpsWorksExplainedScreen extends StatelessWidget {
  const HowGpsWorksExplainedScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const GuidedLessonScreen(lesson: kHowGpsWorksLesson);
}
