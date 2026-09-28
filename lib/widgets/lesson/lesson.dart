// Guided Lessons: one import for a lesson screen.
//
// HOW TO BUILD A LESSON FROM AN EXPLAINER GUIDE
//
//  1. Figures:  python3 tool/extract_lesson_figures.py GUIDE.html <slug>
//     writes assets/lesson-figures/<slug>/fig-NN.svg, cover.svg and
//     figures.json. Add `- assets/lesson-figures/<slug>/` to pubspec.yaml.
//     It warns on any figure label that names a printed page; fix each with
//     --replace "(page 6)=(step 5)" and report it.
//  2. Content:  python3 tool/guide_to_lesson.py GUIDE.html <slug> ...
//     writes lib/screens/tools/reference/lessons/<slug>_lesson.dart, a const
//     GuidedLesson with the guide's text word for word. Read what it prints:
//     every change it made to the text (a printed page number turned into a
//     step number) is listed there for the report.
//  3. Screen:   a StatelessWidget whose build returns
//     `GuidedLessonScreen(lesson: k<Name>Lesson)`, plus the catalog entry,
//     route, keywords, help entry (mention Present and its keys) and Field
//     Manual entry, wired as find-my-explained is.
//  4. Test:     copy test/screens/tools/reference/find_my_explained_screen_
//     test.dart; the shared checks in test/widgets/lesson/ cover the rest.
//
// See guided_lesson.dart for the data format.

export 'guided_lesson.dart';
export 'guided_lesson_controller.dart';
export 'guided_lesson_screen.dart';
export 'lesson_blocks.dart';
export 'lesson_figure_view.dart';
