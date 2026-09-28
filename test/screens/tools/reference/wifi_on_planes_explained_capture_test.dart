// WifiOnPlanesExplainedScreen: screenshots for visual review. See
// test/widgets/lesson/lesson_capture.dart for what is written and when.
@Tags(<String>['capture'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_on_planes_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/wifi_on_planes_lesson.dart';

import '../../../widgets/lesson/lesson_capture.dart';

void main() => runGuidedLessonCapture(
  lesson: kWifiOnPlanesLesson,
  screen: const WifiOnPlanesExplainedScreen(),
  figureStep: 1,
);
