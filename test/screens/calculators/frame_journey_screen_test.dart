// Widget tests for the Wi-Fi Classroom tool A Frame's Journey
// (frame-journey). The shared model has its own tests (test/services/
// wifi_lab/frame_journey_model_test.dart); these check the screen:
// registration, the defaults, corrupt-a-bit through to the retry, the
// radiotap switch, the units preference, predict-then-reveal, acronyms at
// first use, no vendor names, the help keys, and the layout on every step.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/frame_journey_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/frame_journey_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/frame_journey_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';

import '../../support/shipped_help_copy.dart';

final List<RegExp> _doNotPrint = <String>[
  'Apple',
  'iPhone',
  'Mac',
  'macOS',
  'iOS',
  'Android',
  'Google',
  'Microsoft',
  'Windows',
  'Linux',
  'Cisco',
  'Intel',
  'Qualcomm',
  'Broadcom',
  'Wireshark',
  'tcpdump',
].map((String w) => RegExp('\\b$w\\b')).toList();

Future<FrameJourneyController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 5000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final FrameJourneyController c = FrameJourneyController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: FrameJourneyScreen(controller: c),
    ),
  );
  await tester.pump();
  return c;
}

List<String> _screenText(WidgetTester tester) => <String>[
  for (final Element e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
];

void main() {
  test('catalog registers frame-journey on the Signals and PHY shelf', () {
    final ToolEntry t = kToolCategories
        .firstWhere((ToolCategory c) => c.id == 'wifi-classroom')
        .tools
        .firstWhere((ToolEntry e) => e.id == 'frame-journey');
    expect(t.title, 'A Frame\'s Journey');
    expect(t.subgroup, 'Signals and PHY');
    expect(t.routeName, AppRouter.frameJourney);
    expect(kFrameJourneyToolId, t.id);
  });

  testWidgets('opens clean: one attempt, FCS pass, then the ACK', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = await _open(tester);
    expect(c.config.corrupt, isFalse);
    expect(c.hop.every((FhStep s) => s.attempt == 1), isTrue);
    c.index = c.hop.indexWhere((FhStep s) => s.stage == FjHopStage.fcs);
    await tester.pump();
    expect(find.byType(FhVerdict), findsOneWidget);
    expect(find.text('FCS pass'), findsOneWidget);
    c.index = c.hop.indexWhere((FhStep s) => s.stage == FjHopStage.sifs);
    await tester.pump();
    expect(find.textContaining('16 µs'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt a bit: FCS fail, no ACK, then the retry gets through', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = await _open(tester);
    await tester.ensureVisible(
      find.text('Corrupt one bit on the first attempt'),
    );
    await tester.tap(find.text('Corrupt one bit on the first attempt'));
    await tester.pump();
    expect(c.config.corrupt, isTrue);
    expect(find.textContaining('In Address 3'), findsOneWidget);
    c.index = c.hop.indexWhere((FhStep s) => s.stage == FjHopStage.fcs);
    await tester.pump();
    expect(find.text('FCS fail'), findsOneWidget);
    expect(find.textContaining('flipped'), findsWidgets);
    c.index = c.hop.indexWhere((FhStep s) => s.stage == FjHopStage.noAck);
    await tester.pump();
    expect(find.text('No ACK comes back'), findsOneWidget);
    c.index = c.stepCount - 1;
    await tester.pump();
    expect(find.text('Delivered on the retry'), findsOneWidget);
    expect(find.text('FCS pass'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bit slider is disabled until Corrupt is on', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final Slider bit = tester.widget<Slider>(
      find.descendant(
        of: find.bySemanticsLabel('Which bit'),
        matching: find.byType(Slider),
      ),
    );
    expect(bit.onChanged, isNull);
  });

  testWidgets('radiotap appears only when the receiver captures', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = await _open(tester);
    c.index = c.hop.indexWhere((FhStep s) => s.stage == FjHopStage.radiotap);
    await tester.pump();
    expect(find.text('radiotap: added here, never sent'), findsOneWidget);
    c.capturing = false;
    await tester.pump();
    c.index = c.stepCount - 1;
    await tester.pump();
    expect(find.text('radiotap: added here, never sent'), findsNothing);
    expect(
      find.text('This receiver is not capturing, so nothing is added.'),
      findsOneWidget,
    );
  });

  testWidgets('distance follows the units preference', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = await _open(tester);
    expect(find.text('8 m'), findsWidgets);
    c.setUnits(UnitSystem.imperial);
    await tester.pump();
    expect(find.text('26 ft'), findsWidgets);
  });

  testWidgets('predict, then reveal: nothing comes back', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = await _open(tester);
    await tester.ensureVisible(find.text('Ask the class'));
    await tester.tap(find.text('Ask the class'));
    await tester.pump();
    expect(c.config.corrupt, isTrue);
    c.guess = FhGuess.resend;
    await tester.pump();
    await tester.ensureVisible(find.text('Reveal'));
    await tester.tap(find.text('Reveal'));
    await tester.pump();
    expect(find.text('Nothing.'), findsOneWidget);
    expect(c.step.stage, FjHopStage.noAck);
  });

  testWidgets('acronyms are spelled out at first use on the opening screen', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final String all = _screenText(tester).join('\n');
    for (final (String short, String long) in <(String, String)>[
      ('NIC', 'network interface card'),
      ('FCS', 'frame check sequence'),
      ('CRC', '32-bit cyclic redundancy check'),
      ('SIFS', 'short interframe space'),
    ]) {
      final RegExpMatch m = RegExp('\\b$short\\b').firstMatch(all)!;
      final String after = all.substring(m.start, m.start + 60);
      expect(after, contains(long), reason: '$short first appears as "$after"');
    }
  });

  testWidgets('no vendor or operating-system name on screen or in the help', (
    WidgetTester tester,
  ) async {
    final FrameJourneyController c = await _open(tester);
    c.corrupt = true;
    final Set<String> seen = <String>{};
    for (final FjBand b in FjBand.values) {
      c.band = b;
      for (int i = 0; i < c.stepCount; i++) {
        c.index = i;
        await tester.pump();
        seen.addAll(_screenText(tester));
      }
    }
    final List<String> hits = <String>[
      for (final String t in <String>[
        ...seen,
        ...shippedHelpProse('frame-journey'),
      ])
        for (final RegExp r in _doNotPrint)
          if (r.hasMatch(t)) '${r.pattern} in "$t"',
    ];
    expect(hits, isEmpty);
  });

  test('the help mentions Present and every key, and what it leaves out', () {
    final String help = shippedHelpProse('frame-journey').join('\n');
    for (final String k in <String>[
      'Present',
      'Space',
      'Right arrow',
      'R resets',
      'Up and Down',
      'C corrupts',
      'B picks',
      'Esc',
      'Not modeled',
    ]) {
      expect(help, contains(k), reason: k);
    }
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double w in <double>[390, 820, 1280]) {
      testWidgets('$name at ${w.toInt()} px: no overflow on any step', (
        WidgetTester tester,
      ) async {
        final FrameJourneyController c = await _open(
          tester,
          size: Size(w, 5000),
          theme: theme(),
        );
        for (final bool corrupt in <bool>[false, true]) {
          c.corrupt = corrupt;
          for (final FjBand b in FjBand.values) {
            c.band = b;
            for (int i = 0; i < c.stepCount; i++) {
              c.index = i;
              await tester.pump();
              expect(tester.takeException(), isNull, reason: '$b step $i');
            }
          }
        }
      });
    }
  }
}
