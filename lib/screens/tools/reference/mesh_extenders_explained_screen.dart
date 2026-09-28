// Mesh, Extenders and Wired Access Points, Explained: a Wireless Classroom Guided Lesson.
//
// Built for 1.11.0 on the shared Guided Lesson framework
// (lib/widgets/lesson/): the content is kMeshExtendersLesson in
// lessons/mesh_extenders_lesson.dart, generated word for word from the guide's final
// approved text by tool/guide_to_lesson.py, and the figures are the guide's
// own SVGs, extracted by tool/extract_lesson_figures.py into
// assets/lesson-figures/mesh-extenders/. GuidedLessonScreen renders it on a phone and
// in Present mode.

import 'package:flutter/material.dart';

import '../../../widgets/lesson/lesson.dart';
import 'lessons/mesh_extenders_lesson.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kMeshExtendersExplainedToolId = 'mesh-extenders-explained';

class MeshExtendersExplainedScreen extends StatelessWidget {
  const MeshExtendersExplainedScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const GuidedLessonScreen(lesson: kMeshExtendersLesson);
}
