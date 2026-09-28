// WifiAndHealthExplainedScreen: screenshots for visual review. See
// test/widgets/lesson/lesson_capture.dart for what is written and when.
@Tags(<String>['capture'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_and_health_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/wifi_and_health_lesson.dart';

import '../../../widgets/lesson/lesson_capture.dart';

void main() => runGuidedLessonCapture(
  lesson: kWifiAndHealthLesson,
  screen: const WifiAndHealthExplainedScreen(),
  figureStep: 1,
);
