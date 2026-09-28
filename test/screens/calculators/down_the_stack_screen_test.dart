// Widget tests for the Wi-Fi Classroom tool Down the Stack, Across the Air,
// Up the Other Side (down-the-stack). The shared model has its own tests
// (test/services/wifi_lab/frame_journey_model_test.dart); these check the
// screen: registration, the defaults, the journey controls, the address
// explorer, predict-then-reveal, acronyms at first use, no vendor or
// operating-system names (screen and help), the help keys, and the layout at
// phone and desktop widths in both themes on every step.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/down_the_stack_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/down_the_stack_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/frame_journey_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../support/shipped_help_copy.dart';

final List<RegExp> _doNotPrint = <String>[
  'Apple',
  'iPhone',
  'iPad',
  'Mac',
  'macOS',
  'iOS',
  'Android',
  'Google',
  'Samsung',
  'Microsoft',
  'Windows',
  'Linux',
  'Cisco',
  'Aruba',
  'Juniper',
  'Ubiquiti',
  'Ruckus',
  'Meraki',
  'Intel',
  'Qualcomm',
  'Broadcom',
  'Wireshark',
].map((String w) => RegExp('\\b$w\\b')).toList();

Future<DownTheStackController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 5000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final DownTheStackController c = DownTheStackController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: DownTheStackScreen(controller: c),
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
  test('catalog registers down-the-stack on the Network Design and Security '
      'shelf, with its route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'down-the-stack',
    );
    expect(t.title, 'Down the Stack, Across the Air, Up the Other Side');
    expect(t.subgroup, 'Network Design and Security');
    expect(t.routeName, AppRouter.downTheStack);
    expect(kDownTheStackToolId, t.id);
    expect(kToolKeywords['down-the-stack'], contains('to ds'));
    expect(kToolKeywords['down-the-stack'], contains('encapsulation'));
  });

  testWidgets('opens on the laptop\'s application data, step 1', (
    WidgetTester tester,
  ) async {
    final DownTheStackController c = await _open(tester);
    expect(c.index, 0);
    expect(c.config, const FjConfig());
    expect(find.text('Laptop: application data'), findsOneWidget);
    expect(find.text('Data: 1460 bytes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Step reaches the air hop with the router in Address 3', (
    WidgetTester tester,
  ) async {
    final DownTheStackController c = await _open(tester);
    while (!c.step.onMedium) {
      await tester.ensureVisible(find.text('Step'));
      await tester.tap(find.text('Step'));
      await tester.pump();
    }
    expect(find.text('Across the air to the AP'), findsOneWidget);
    expect(find.textContaining(FjScene.routerLan.mac.text), findsWidgets);
    expect(find.text('802.11 header: To DS 1, From DS 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the address view shows all four cases, and the fourth '
      'address only with both bits set', (WidgetTester tester) async {
    final DownTheStackController c = await _open(tester);
    c.view = DtsView.addresses;
    for (final DsCase d in DsCase.values) {
      c.dsCase = d;
      await tester.pump();
      expect(find.byType(DtsAddressExplorer), findsOneWidget);
      expect(
        find.text('To DS ${d.toDsBit}, From DS ${d.fromDsBit}'),
        findsOneWidget,
      );
      if (d == DsCase.both) {
        expect(find.text('RA'), findsWidgets);
        expect(find.textContaining('Why a fourth address'), findsOneWidget);
      } else {
        expect(find.text('not present'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('predict, then reveal: the router\'s MAC', (
    WidgetTester tester,
  ) async {
    final DownTheStackController c = await _open(tester);
    c.server = FjServerLocation.sameSubnet;
    await tester.pump();
    await tester.ensureVisible(find.text('Ask the class'));
    await tester.tap(find.text('Ask the class'));
    await tester.pump();
    expect(c.config.server, FjServerLocation.otherSubnet);
    expect(c.question, DtsQuestion.asking);
    c.guess = DtsGuess.server;
    await tester.pump();
    await tester.ensureVisible(find.text('Reveal'));
    await tester.tap(find.text('Reveal'));
    await tester.pump();
    expect(find.text('The router\'s LAN MAC.'), findsOneWidget);
    final FjLink? l = c.step.link;
    expect(l, isA<FjWifiLink>());
    expect((l! as FjWifiLink).fields[2].mac, FjScene.routerLan.mac);
  });

  testWidgets('Play advances; reaching the end stops', (
    WidgetTester tester,
  ) async {
    final DownTheStackController c = await _open(tester);
    c.togglePlay();
    await tester.pump();
    await tester.pump(kDtsStepDuration * 3);
    expect(c.index, 3);
    await tester.pump(kDtsStepDuration * 40);
    expect(c.atEnd, isTrue);
    expect(c.playing, isFalse);
  });

  testWidgets('acronyms are spelled out at first use on the opening screen', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final String all = _screenText(tester).join('\n');
    for (final (String short, String long) in <(String, String)>[
      ('IP', 'Internet Protocol'),
      ('TTL', 'time to live'),
      ('MAC', 'media access control'),
      ('DS', 'DS: the distribution system'),
    ]) {
      final RegExpMatch m = RegExp('\\b$short\\b').firstMatch(all)!;
      final String after = all.substring(m.start, m.start + 60);
      expect(after, contains(long), reason: '$short first appears as "$after"');
    }
  });

  testWidgets('no vendor or operating-system name on screen, on any step, '
      'or in the help', (WidgetTester tester) async {
    final DownTheStackController c = await _open(tester);
    final Set<String> seen = <String>{};
    for (final FjDirection d in FjDirection.values) {
      for (final FjServerLocation s in FjServerLocation.values) {
        c.direction = d;
        c.server = s;
        for (int i = 0; i < c.stepCount; i++) {
          c.index = i;
          await tester.pump();
          seen.addAll(_screenText(tester));
        }
      }
    }
    c.view = DtsView.addresses;
    for (final DsCase d in DsCase.values) {
      c.dsCase = d;
      await tester.pump();
      seen.addAll(_screenText(tester));
    }
    final List<String> texts = <String>[
      ...seen,
      ...shippedHelpProse('down-the-stack'),
    ];
    final List<String> hits = <String>[
      for (final String t in texts)
        for (final RegExp r in _doNotPrint)
          if (r.hasMatch(t)) '${r.pattern} in "$t"',
    ];
    expect(hits, isEmpty);
  });

  test('the help mentions Present and every key, and what it leaves out', () {
    final String help = shippedHelpProse('down-the-stack').join('\n');
    for (final String k in <String>[
      'Present',
      'Space',
      'Right arrow',
      'R resets',
      'Up and Down',
      'D shows',
      'V switches',
      'Esc',
      'Left out',
      'NAT',
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
        final DownTheStackController c = await _open(
          tester,
          size: Size(w, 5000),
          theme: theme(),
        );
        for (final FjDirection d in FjDirection.values) {
          c.direction = d;
          for (int i = 0; i < c.stepCount; i++) {
            c.index = i;
            await tester.pump();
            expect(tester.takeException(), isNull, reason: 'step $i');
          }
        }
        c.view = DtsView.addresses;
        for (final DsCase d in DsCase.values) {
          c.dsCase = d;
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$d');
        }
      });
    }
  }
}
