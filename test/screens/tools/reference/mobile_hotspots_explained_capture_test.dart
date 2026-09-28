// MobileHotspotsExplainedScreen: screenshots for visual review. See
// test/widgets/lesson/lesson_capture.dart for what is written and when.
@Tags(<String>['capture'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/mobile_hotspots_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/mobile_hotspots_lesson.dart';

import '../../../widgets/lesson/lesson_capture.dart';

void main() => runGuidedLessonCapture(
  lesson: kMobileHotspotsLesson,
  screen: const MobileHotspotsExplainedScreen(),
  figureStep: 1,
);
