// The checks every Guided Lesson gets. A lesson's own test file calls
// runGuidedLessonSuite with its lesson, its screen and its figure count, then
// adds any checks only that lesson needs.
//
// What it covers:
//  - wiring: a live catalog entry on the Wireless Classroom's Guided Lessons
//    shelf, the route, keywords, and a help entry that names Present;
//  - figures: each asset is bundled, is flutter_svg-safe (no <marker>, <use>
//    or currentColor left, and it parses), and the captions run Figure 1..N
//    in lesson order;
//  - text rules: no printed page number survives; lengths are metric first
//    with imperial in parentheses; every informational box ("A word on",
//    "About", a Keith's note) is a Note or Quote, never Caution or Stop
//    (GL-003 §12.9 line 3);
//  - the phone screen in dark and light: every step reachable, a myth's fact
//    hidden until tapped;
//  - Present at 1920x1080 and 1440x900 in dark and light: every slide
//    renders with no page scroll, Right, Left, Space and R work.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lesson_parts.dart'
    show LessonSection, lessonPlain;
import 'package:wlan_pros_toolbox/services/help/tool_help.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../presenter/presenter_test_support.dart';

/// Every text field in [lesson], in order, with markup.
List<String> lessonStrings(GuidedLesson lesson) {
  final List<String> out = <String>[
    ?lesson.tagline,
    lesson.promise,
    ...lesson.byline,
  ];
  for (final LessonStep s in lesson.steps) {
    out.add(s.title);
    for (final LessonBlock b in s.blocks) {
      switch (b) {
        case LessonLede(:final String text):
        case LessonText(:final String text):
        case LessonHeading(:final String text):
          out.add(text);
        case LessonCallout c:
          out.addAll(<String>[
            ?c.speaker,
            ?c.title,
            c.body,
            ...c.steps,
            ?c.attribution,
          ]);
        case LessonFigure f:
          out.add(f.caption ?? '');
        case LessonMyth m:
          out.addAll(<String>[m.myth, m.fact]);
        case LessonSteps(:final List<String> items):
        case LessonBullets(:final List<String> items):
        case LessonSourceList(:final List<String> items):
          out.addAll(items);
        case LessonCards(:final List<LessonCardData> cards):
          for (final LessonCardData c in cards) {
            out.addAll(<String>[?c.title, c.body]);
          }
        case LessonTask t:
          out.addAll(<String>[t.title, ?t.why, ...t.steps, ?t.after]);
        case LessonToolLink():
          break;
      }
    }
  }
  return out;
}

/// Every figure in [lesson], cover first when it has one.
List<LessonFigure> lessonFigures(GuidedLesson lesson) => <LessonFigure>[
  ?lesson.cover,
  for (final LessonStep s in lesson.steps)
    for (final LessonBlock b in s.blocks)
      if (b is LessonFigure) b,
];

/// An imperial length written first: "300 miles (480 km)".
final RegExp imperialFirst = RegExp(
  r'\d[\d,.]*\s*(?:miles?|mi|feet|foot|ft|inch(?:es)?|in|yards?|yd)\b\s*\(',
);

/// A metric length with no imperial beside it, in running text:
/// "480 km up" with no "(... miles)".
final RegExp _metricLength = RegExp(r'\b\d[\d,.]*\s*(?:km|m|cm|mm)\b(?!\s*\()');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void runGuidedLessonSuite({
  required GuidedLesson lesson,
  required Widget screen,
  required int figureCount,
  required List<String> keywords,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(bool light) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: light ? AppTheme.light() : AppTheme.dark(),
    home: screen,
  );

  group('${lesson.toolId}: wiring', () {
    test('a live Guided Lesson on the Wireless Classroom shelf', () {
      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == lesson.toolId),
      );
      final ToolEntry e = cat.tools.firstWhere(
        (ToolEntry t) => t.id == lesson.toolId,
      );
      expect(cat.id, 'wifi-classroom');
      expect(e.subgroup, 'Guided Lessons');
      expect(e.isLive, isTrue);
      expect(e.title, lesson.title);
      expect(e.routeName, lesson.route);
      expect(lesson.route, '/tools/${lesson.toolId}');
      expect(AppRouter.routes.containsKey(lesson.route), isTrue);
    });

    test('search keywords are registered', () {
      expect(kToolKeywords[lesson.toolId], containsAll(keywords));
    });

    test('the help entry exists and names Present and its keys', () async {
      final ToolHelpStore store = ToolHelpStore.fromJson(
        await rootBundle.loadString('assets/help/tool_help.json'),
      );
      final ToolHelp? h = store.forId(lesson.toolId);
      expect(h?.name, lesson.title);
      final String how = h!.howToUse.join(' ');
      expect(how, contains('Present'));
      expect(how, contains('Space reveals the next fact'));
      expect(h.purpose, contains('$figureCount figures'));
    });
  });

  group('${lesson.toolId}: figures', () {
    final List<LessonFigure> figs = lessonFigures(lesson);

    test('captions run Figure 1 to $figureCount in lesson order', () {
      final List<int> numbers = <int>[
        for (final LessonFigure f in figs)
          if (f.caption != null)
            int.parse(
              RegExp(r'^\*\*Figure (\d+)\.').firstMatch(f.caption!)!.group(1)!,
            ),
      ];
      expect(numbers, List<int>.generate(figureCount, (int i) => i + 1));
    });

    for (final LessonFigure f in figs) {
      test('${f.asset} is bundled and flutter_svg-safe', () async {
        final String svg = await rootBundle.loadString(f.asset);
        expect(svg, isNot(contains('<marker')), reason: 'arrowheads drop');
        expect(svg, isNot(contains('<use')));
        expect(svg, isNot(contains('currentColor')));
        // The lesson reserves width x height before the SVG loads; the
        // viewBox origin may be negative (a 2-unit bleed on some figures).
        expect(
          RegExp(
            r'viewBox="\S+ \S+ (\S+) (\S+)"',
          ).firstMatch(svg)?.groups(<int>[1, 2]),
          <String>[_g(f.width), _g(f.height)],
        );
        expect(
          svg,
          isNot(contains(', sans-serif')),
          reason: 'font-family must be a single bundled family',
        );
      });
    }

    testWidgets('every figure parses in flutter_svg', (tester) async {
      for (final LessonFigure f in figs) {
        final String svg = File(f.asset).readAsStringSync();
        Object? caught;
        await tester.pumpWidget(
          MaterialApp(
            home: SvgPicture.string(
              svg,
              width: 320,
              errorBuilder: (BuildContext c, Object e, StackTrace? s) {
                caught = e;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(caught, isNull, reason: f.asset);
      }
    });
  });

  group('${lesson.toolId}: text rules', () {
    final List<String> text = lessonStrings(lesson).map(lessonPlain).toList();

    test('no printed page number survives, in the text or a figure', () {
      final List<String> labels = <String>[
        for (final LessonFigure f in lessonFigures(lesson))
          ...RegExp(r'<text[^>]*>([^<]*)</text>')
              .allMatches(File(f.asset).readAsStringSync())
              .map((RegExpMatch m) => '${f.asset}: ${m.group(1)}'),
      ];
      for (final String s in <String>[...text, ...labels]) {
        expect(s, isNot(matches(RegExp(r'\bpages? \d'))), reason: s);
      }
    });

    test('lengths are metric first, imperial in parentheses', () {
      final List<String> all = <String>[
        ...text,
        for (final LessonFigure f in lessonFigures(lesson))
          ...RegExp(r'<text[^>]*>([^<]*)</text>')
              .allMatches(File(f.asset).readAsStringSync())
              .map((RegExpMatch m) => m.group(1)!),
      ];
      for (final String s in all) {
        expect(s, isNot(matches(imperialFirst)), reason: s);
      }
      // Every metric length in running prose carries its imperial. Sources
      // list figures as "(370 to 460 km, 230 to 290 miles)", which the
      // pattern above already allows.
      for (final String s in text) {
        for (final RegExpMatch m in _metricLength.allMatches(s)) {
          final String before = s.substring(0, m.start);
          final String after = s.substring(m.end);
          // A speed (km/s) or an operand in arithmetic (4 × 35,786 km ÷ ...)
          // is not a length to convert.
          if (after.startsWith('/') ||
              RegExp(r'[×÷]\s*$').hasMatch(before) ||
              RegExp(r'^\s*[×÷]').hasMatch(after)) {
            continue;
          }
          final bool imperialFollows = RegExp(
            r'^[^.;]{0,40}(?:miles?|feet|foot|inch|ft\b)',
          ).hasMatch(after);
          expect(
            imperialFollows,
            isTrue,
            reason: 'metric length with no imperial: "${m.group(0)}" in $s',
          );
        }
      }
    });

    test('informational boxes are Notes or Quotes, never warm', () {
      for (final LessonStep s in lesson.steps) {
        for (final LessonBlock b in s.blocks) {
          if (b is! LessonCallout || b.title == null) continue;
          final String t = lessonPlain(b.title!);
          if (t.startsWith('A word on') ||
              t.startsWith('About') ||
              t.startsWith('Companion') ||
              b.speaker == "Keith's note") {
            expect(
              b.kind,
              anyOf(LessonCalloutKind.note, LessonCalloutKind.quote),
              reason: t,
            );
          }
        }
      }
    });
  });

  for (final bool light in <bool>[false, true]) {
    final String mode = light ? 'light' : 'dark';
    group('${lesson.toolId}: phone screen ($mode)', () {
      testWidgets('every step is reachable, and the closing row follows', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(app(light));
        await _settle(tester);
        expect(find.text(lesson.title), findsWidgets);
        for (final LessonStep s in lesson.steps) {
          await tester.scrollUntilVisible(
            find.byWidgetPredicate(
              (Widget w) => w is LessonSection && w.title == s.title,
            ),
            400,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.scrollUntilVisible(
          find.byKey(LessonTakeaway.rowKey),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining(lesson.guideTitle), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('${lesson.toolId}: a myth hides its fact until tapped', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(false));
    await _settle(tester);
    late LessonBlockRef ref;
    late LessonMyth myth;
    outer:
    for (int s = 0; s < lesson.steps.length; s++) {
      for (int b = 0; b < lesson.steps[s].blocks.length; b++) {
        final LessonBlock block = lesson.steps[s].blocks[b];
        if (block is LessonMyth) {
          ref = LessonBlockRef(s, b);
          myth = block;
          break outer;
        }
      }
    }
    final Finder button = find.byKey(lessonMythKey(ref));
    await tester.scrollUntilVisible(
      button,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final Finder fact = find.textContaining(lessonPlain(myth.fact));
    expect(fact, findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fact, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fact, findsNothing);
  });

  for (final bool light in <bool>[false, true]) {
    for (final Size window in const <Size>[Size(1920, 1080), Size(1440, 900)]) {
      final String label =
          '${light ? 'light' : 'dark'} '
          '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('${lesson.toolId}: Present, every slide fits ($label)', (
        tester,
      ) async {
        installFakeWindow();
        setWindow(tester, window);
        await tester.pumpWidget(app(light));
        await _settle(tester);
        await tester.tap(find.text('Present'));
        await _settle(tester);
        expect(find.byType(PresenterLayout), findsOneWidget);
        final GuidedLessonController c = GuidedLessonController(lesson);
        final int slides = c.slides.length;
        c.dispose();
        for (int i = 0; i < slides; i++) {
          expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
          expect(pageScrollables(tester), isEmpty, reason: 'slide ${i + 1}');
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _settle(tester);
        }
        expect(find.byKey(GuidedLessonScreen.counterKey), findsOneWidget);
      });
    }
  }

  testWidgets('${lesson.toolId}: Present keys: Right, Left, Space, R', (
    tester,
  ) async {
    installFakeWindow();
    setWindow(tester, const Size(1920, 1080));
    await tester.pumpWidget(app(false));
    await _settle(tester);
    await tester.tap(find.text('Present'));
    await _settle(tester);
    String counter() =>
        tester.widget<Text>(find.byKey(GuidedLessonScreen.counterKey)).data!;
    expect(counter(), startsWith('Step 1 of ${lesson.steps.length}'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(counter(), startsWith('Step 2 of'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(counter(), startsWith('Step 1 of'));

    // Walk to the first slide with a myth on its stage; Space reveals its
    // first fact on the stage, and R returns to step 1 with it hidden.
    final GuidedLessonController probe = GuidedLessonController(lesson);
    int target = 0;
    while (probe.slide < probe.slides.length - 1) {
      if (probe.mythsOnSlide.isNotEmpty) break;
      probe.next();
      target++;
    }
    final LessonBlockRef first = probe.mythsOnSlide.first;
    final LessonMyth myth =
        lesson.steps[first.step].blocks[first.block] as LessonMyth;
    probe.dispose();
    for (int i = 0; i < target; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
    }
    final Finder fact = find.descendant(
      of: find.byKey(PresenterLayout.stageKey),
      matching: find.textContaining(lessonPlain(myth.fact)),
    );
    expect(fact, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(fact, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await _settle(tester);
    expect(counter(), startsWith('Step 1 of'));
    expect(tester.takeException(), isNull);
  });
}

String _g(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
