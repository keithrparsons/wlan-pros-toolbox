// Captive Portals, Explained: a Wi-Fi Classroom Guided Lesson.
//
// Built for 1.11.0 on the shared Guided Lesson framework
// (lib/widgets/lesson/): the content is kCaptivePortalsLesson in
// lessons/captive_portals_lesson.dart, generated word for word from the guide's final
// approved text by tool/guide_to_lesson.py, and the figures are the guide's
// own SVGs, extracted by tool/extract_lesson_figures.py into
// assets/lesson-figures/captive-portals/. GuidedLessonScreen renders it on a phone and
// in Present mode.

import 'package:flutter/material.dart';

import '../../../widgets/lesson/lesson.dart';
import 'lessons/captive_portals_lesson.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kCaptivePortalsExplainedToolId = 'captive-portals-explained';

class CaptivePortalsExplainedScreen extends StatelessWidget {
  const CaptivePortalsExplainedScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const GuidedLessonScreen(lesson: kCaptivePortalsLesson);
}
