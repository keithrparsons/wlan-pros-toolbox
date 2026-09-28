// WifiAndHealthExplainedScreen: the Guided Lesson on the shared framework (1.11.0).
// The shared checks (wiring, figures, text rules, phone and Present) live in
// test/widgets/lesson/lesson_suite.dart; this file adds what only this
// lesson needs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_and_health_explained_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lessons/wifi_and_health_lesson.dart';

import '../../../widgets/lesson/lesson_suite.dart';

void main() {
  test('the tool id and route are the permanent ones', () {
    expect(kWifiAndHealthLesson.toolId, 'wifi-and-health-explained');
    expect(kWifiAndHealthLesson.route, AppRouter.wifiAndHealthExplained);
    expect(kWifiAndHealthExplainedToolId, 'wifi-and-health-explained');
  });

  // Keith's ruling on the Wi-Fi and Health guide (2026-09-28): the guide
  // talks about Wi-Fi only and never says the words that make a reader stop
  // reading. The list is the one the guide was checked against, myPKA
  // Deliverables/2026-09-28-wifi-and-health-guide/VERDICTS.md, "Banned-word
  // check": whole word, any case.
  const List<String> banned = <String>[
    'cancer',
    'carcinogen',
    'carcinogenic',
    'tumor',
    'tumour',
    'glioma',
    'leukemia',
    'neuroma',
    'schwannoma',
    'IARC',
    'NTP',
    'rat',
    'rats',
    'mice',
  ];
  final RegExp bannedWord = RegExp(
    '\\b(?:${banned.join('|')})\\b',
    caseSensitive: false,
  );

  group('Keith\'s banned words appear nowhere a reader can see', () {
    test('the check itself catches a banned word, in any case', () {
      expect(bannedWord.hasMatch('Is Wi-Fi linked to Cancer?'), isTrue);
      expect(bannedWord.hasMatch('studies in RATS'), isTrue);
      // Whole words only: these are fine.
      expect(bannedWord.hasMatch('rate, ratio, accurate, pirate'), isFalse);
    });

    test('the lesson text', () {
      for (final String s in lessonStrings(kWifiAndHealthLesson)) {
        expect(bannedWord.firstMatch(s)?.group(0), isNull, reason: s);
      }
    });

    test('every figure: its labels, caption and alt text', () {
      final Directory dir = Directory('assets/lesson-figures/wifi-and-health');
      final List<File> files = dir
          .listSync()
          .whereType<File>()
          .where(
            (File f) => f.path.endsWith('.svg') || f.path.endsWith('.json'),
          )
          .toList();
      expect(files.length, greaterThan(10));
      for (final File f in files) {
        final String text = f.readAsStringSync();
        expect(bannedWord.firstMatch(text)?.group(0), isNull, reason: f.path);
      }
    });

    test('the help entry, the Field Manual entry and the search keywords', () {
      final Map<String, dynamic> help =
          (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                  as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      final String entry = jsonEncode(help[kWifiAndHealthLesson.toolId]);
      expect(entry, contains('Wi-Fi and Your Health'));
      expect(bannedWord.firstMatch(entry)?.group(0), isNull);

      final String manual = File(
        'assets/guides/field-manual.md',
      ).readAsStringSync();
      final int start = manual.indexOf('### Wi-Fi and Your Health, Explained');
      expect(start, isNot(-1));
      final int end = manual.indexOf('\n### ', start + 4);
      final String section = manual.substring(start, end);
      expect(bannedWord.firstMatch(section)?.group(0), isNull);

      for (final String k in kToolKeywords[kWifiAndHealthLesson.toolId]!) {
        expect(bannedWord.hasMatch(k), isFalse, reason: k);
      }
    });
  });

  runGuidedLessonSuite(
    lesson: kWifiAndHealthLesson,
    screen: const WifiAndHealthExplainedScreen(),
    figureCount: 10,
    keywords: <String>['wi-fi and health', 'radiation'],
  );
}
