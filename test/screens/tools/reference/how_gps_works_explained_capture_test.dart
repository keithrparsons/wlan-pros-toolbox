// HowGpsWorksExplainedScreen: screenshots for visual review. See
// test/widgets/lesson/lesson_capture.dart for what is written and when.
@Tags(<String>['capture'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/how_gps_works_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/how_gps_works_lesson.dart';

import '../../../widgets/lesson/lesson_capture.dart';

void main() => runGuidedLessonCapture(
  lesson: kHowGpsWorksLesson,
  screen: const HowGpsWorksExplainedScreen(),
  figureStep: 1,
);
