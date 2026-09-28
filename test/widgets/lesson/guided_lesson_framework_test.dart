// The Guided Lesson framework itself (lib/widgets/lesson/), on a small
// made-up lesson: the controller's slide and reveal rules, the GL-003 §12.10
// tokens on each callout kind and on the myth pair, the figure's always-light
// card and its keyboard-operable zoom, and the {{UI name}} markup.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/lesson_parts.dart'
    show LessonRich, LessonSources, lessonPlain;
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/lesson/lesson.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter_actions.dart';

const LessonFigure _fig = LessonFigure(
  asset: 'assets/lesson-figures/find-my/fig-01.svg',
  width: 760,
  height: 300,
  caption: '**Figure 1. The Find My network.** The tag whispers.',
);

const GuidedLesson _lesson = GuidedLesson(
  toolId: 'test-lesson',
  route: '/tools/test-lesson',
  title: 'Test, Explained',
  guideTitle: 'Test, Explained',
  promise: 'A promise.',
  steps: <LessonStep>[
    LessonStep(
      number: '1',
      title: 'Figures and words',
      blocks: <LessonBlock>[
        LessonLede('A lede.'),
        LessonText('A paragraph that stays in the panel.'),
        _fig,
        LessonCallout.note(title: 'A word on the words', body: 'Note body.'),
      ],
    ),
    LessonStep(
      number: '2',
      title: 'Myths',
      blocks: <LessonBlock>[
        LessonText('Each myth is followed by what is true.'),
        LessonMyth(myth: 'Myth one.', fact: 'Fact one.'),
        LessonMyth(myth: 'Myth two.', fact: 'Fact two.'),
      ],
    ),
    LessonStep(
      number: 'A',
      spoken: 'Appendix',
      title: 'Tasks',
      blocks: <LessonBlock>[
        LessonText('The › symbol means "then tap".', small: true),
        LessonHeading('Group one'),
        LessonTask(title: '1. Do a thing', steps: <String>['Tap {{Done}}.']),
        LessonHeading('Group two'),
        LessonTask(title: '2. Do another', steps: <String>['Tap {{More}}.']),
        LessonTask(title: '3. And another', steps: <String>['Tap {{Add}}.']),
        LessonTask(title: '4. And one more', steps: <String>['Tap {{Save}}.']),
      ],
    ),
  ],
);

Widget _host(Widget child, {bool light = false}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('GuidedLessonController', () {
    test('default slides: stage kinds on the stage; a task-only step splits '
        'at its subheadings', () {
      final GuidedLessonController c = GuidedLessonController(_lesson);
      addTearDown(c.dispose);
      expect(
        c.slides.map((LessonSlide s) => '${s.step}:${s.stage}').toList(),
        <String>[
          '0:[0, 2, 3]',
          '1:[1, 2]',
          // Prelude with the first group; a heading keeps its tasks; at
          // most two task cards a slide.
          '2:[0, 1, 2]',
          '2:[3, 4, 5]',
          '2:[6]',
        ],
      );
    });

    test(
      'an appendix that opens with a lede still splits into task slides',
      () {
        // Cameras, Doorbells: "Do this now" opens with a lede, then three tasks
        // with an Open button after the first. The lede must not take the
        // stage alone and leave every task in the side panel.
        const LessonStep step = LessonStep(
          number: 'A',
          title: 'Do this now',
          blocks: <LessonBlock>[
            LessonLede('Half an hour, one camera at a time.'),
            LessonTask(title: 'One', steps: <String>['Tap {{A}}.']),
            LessonToolLink('net-quality'),
            LessonTask(title: 'Two', steps: <String>['Tap {{B}}.']),
            LessonTask(title: 'Three', steps: <String>['Tap {{C}}.']),
          ],
        );
        expect(GuidedLessonController.slidesFor(step), <List<int>>[
          <int>[0, 1, 2, 3],
          <int>[4],
        ]);
        // A lede beside a figure is an ordinary step: one slide, stage kinds.
        const LessonStep withFigure = LessonStep(
          number: '1',
          title: 'Figure',
          blocks: <LessonBlock>[
            LessonLede('A lede.'),
            _fig,
            LessonTask(title: 'One'),
          ],
        );
        expect(GuidedLessonController.slidesFor(withFigure), <List<int>>[
          <int>[0, 1],
        ]);
      },
    );

    test('Space reveals the next fact, then hides them all; R resets', () {
      final GuidedLessonController c = GuidedLessonController(_lesson);
      addTearDown(c.dispose);
      c.revealNext(); // step 1 has no myth: nothing happens
      c.next();
      const LessonBlockRef m1 = LessonBlockRef(1, 1);
      const LessonBlockRef m2 = LessonBlockRef(1, 2);
      c.revealNext();
      expect(<bool>[c.isRevealed(m1), c.isRevealed(m2)], <bool>[true, false]);
      c.revealNext();
      expect(<bool>[c.isRevealed(m1), c.isRevealed(m2)], <bool>[true, true]);
      c.revealNext();
      expect(<bool>[c.isRevealed(m1), c.isRevealed(m2)], <bool>[false, false]);
      c
        ..revealNext()
        ..next()
        ..reset();
      expect(c.slide, 0);
      expect(c.isRevealed(m1), isFalse);
    });

    test('the Present keys: Space, Right, R, and Left as an extra key', () {
      final GuidedLessonController c = GuidedLessonController(_lesson);
      addTearDown(c.dispose);
      final PresenterActions a = c.presenterActions;
      expect(a.playPause, isNotNull);
      expect(a.step, isNotNull);
      expect(a.reset, isNotNull);
      expect(a.hasSlider, isFalse, reason: 'Up and Down are not used');
      expect(
        a.extra.single.key,
        LogicalKeyboardKey.arrowLeft,
        reason: 'Left is the previous step',
      );
      a.step!();
      expect(c.slide, 1);
      a.extra.single.onPressed();
      expect(c.slide, 0);
    });
  });

  group('callouts follow GL-003 §12.10', () {
    for (final bool light in <bool>[false, true]) {
      testWidgets('Note and Quote are statusInfo; Caution and Stop carry '
          'their word and mark (light: $light)', (tester) async {
        final AppColorScheme colors = light
            ? AppColorScheme.light()
            : AppColorScheme.dark();
        await tester.pumpWidget(
          _host(
            const Column(
              children: <Widget>[
                LessonCalloutView(
                  LessonCallout.note(title: 'A word on the words', body: 'b'),
                ),
                LessonCalloutView(
                  LessonCallout.quote(
                    speaker: "Keith's note",
                    title: 'The drop',
                    body: 'q',
                    attribution: 'Keith Parsons, 2026-09-27',
                  ),
                ),
                LessonCalloutView(
                  LessonCallout.caution(title: 'Costs money', body: 'c'),
                ),
                LessonCalloutView(
                  LessonCallout.stop(
                    title: 'Be safe',
                    body: 's',
                    steps: <String>['One.', 'Two.'],
                  ),
                ),
              ],
            ),
            light: light,
          ),
        );
        await tester.pumpAndSettle();
        Color barOf(String title) {
          final Finder callout = find.ancestor(
            of: find.text(title),
            matching: find.byType(LessonCalloutView),
          );
          final Container bar = tester
              .widgetList<Container>(
                find.descendant(of: callout, matching: find.byType(Container)),
              )
              .firstWhere((Container c) => c.constraints?.maxWidth == 6);
          return bar.color!;
        }

        expect(barOf('A word on the words'), colors.statusInfo);
        expect(barOf('The drop'), colors.statusInfo);
        expect(barOf('Costs money'), colors.statusWarning);
        expect(barOf('Be safe'), colors.statusDanger);
        expect(find.text("KEITH'S NOTE"), findsOneWidget);
        expect(find.text('CAUTION'), findsOneWidget);
        expect(find.text('STOP'), findsOneWidget);
        expect(find.byType(SvgPicture), findsNWidgets(2));
        expect(find.textContaining('One.'), findsOneWidget);
      });
    }
  });

  testWidgets('myth and fact: stacked, textAccent fact, never statusSuccess', (
    tester,
  ) async {
    final AppColorScheme colors = AppColorScheme.dark();
    await tester.pumpWidget(
      _host(
        const LessonMythView(
          myth: LessonMyth(myth: 'A myth.', fact: 'A fact.'),
          ref: LessonBlockRef(0, 0),
        ),
      ),
    );
    expect(find.text('A fact.'), findsNothing);
    await tester.tap(find.byKey(lessonMythKey(const LessonBlockRef(0, 0))));
    await tester.pumpAndSettle();
    expect(find.text('A fact.'), findsOneWidget);
    final Text factLabel = tester.widget<Text>(find.text('FACT'));
    expect(factLabel.style!.color, colors.textAccent);
    expect(factLabel.style!.color, isNot(colors.statusSuccess));
    expect(
      tester.widget<Text>(find.text('MYTH')).style!.color,
      colors.textTertiary,
    );
  });

  group('figures', () {
    testWidgets('sit on the light card in dark mode, and the caption is the '
        'alt text', (tester) async {
      await tester.pumpWidget(_host(const LessonFigureView(_fig)));
      await tester.pumpAndSettle();
      final Container card = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(lessonFigureKey(_fig.asset)),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (card.decoration! as BoxDecoration).color,
        AppColorScheme.light().surface1,
      );
      expect(find.bySemanticsLabel(lessonPlain(_fig.caption!)), findsOneWidget);
    });

    testWidgets('Tab reaches the zoom and Enter opens it; Esc closes it', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LessonFigureView(_fig)));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(LessonFigureZoom), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LessonFigureZoom), findsNothing);
    });

    testWidgets('a tap opens the zoom and the close button closes it', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const LessonFigureView(_fig), light: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(lessonFigureKey(_fig.asset)));
      await tester.pumpAndSettle();
      expect(find.byType(LessonFigureZoom), findsOneWidget);
      await tester.tap(find.byKey(LessonFigureZoom.closeKey));
      await tester.pumpAndSettle();
      expect(find.byType(LessonFigureZoom), findsNothing);
    });

    testWidgets('a figure that cannot load says so, and keeps its caption', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const LessonFigureView(
            LessonFigure(
              asset: 'assets/lesson-figures/none/fig-99.svg',
              width: 100,
              height: 50,
              caption: '**Figure 9. Missing.** Still reads.',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be shown'), findsOneWidget);
      expect(find.textContaining('Still reads.'), findsOneWidget);
    });
  });

  testWidgets('{{UI name}} draws a chip and reads as the plain name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const LessonRich(
          'Open {{Settings}} › {{Find My}}.',
          style: TextStyle(),
        ),
      ),
    );
    expect(
      lessonPlain('Open {{Settings}} › {{Find My}}.'),
      'Open Settings › Find My.',
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Find My'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Settings › Find My.'), findsOneWidget);
  });

  testWidgets('a Quote whose label names its source: no attribution line, the '
      'title in italics, read as plain words', (tester) async {
    // Bluetooth and Weak Cell Signal (2026-09-28) put the book in the label:
    // "Keith's note, from <i>Fix Your Own Wi-Fi</i>", with no source line.
    await tester.pumpWidget(
      _host(
        const LessonCalloutView(
          LessonCallout.quote(
            speaker: "Keith's note, from __Fix Your Own Wi-Fi__",
            body: '"Water and metal surprise people."',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('__'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp("^Keith's note, from Fix Your Own Wi-Fi")),
      findsWidgets,
    );
  });

  testWidgets('a source line shows a book title in italics, not its markers', (
    tester,
  ) async {
    // Bluetooth, Explained cites "Keith Parsons, <i>Fix Your Own Wi-Fi</i>".
    await tester.pumpWidget(
      _host(
        const LessonSources(<String>[
          'Keith Parsons, __Fix Your Own Wi-Fi__ (in preparation, 2026)',
        ]),
      ),
    );
    expect(find.textContaining('__'), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Keith Parsons, Fix Your Own Wi-Fi (in preparation, 2026)',
      ),
      findsOneWidget,
    );
  });
}
