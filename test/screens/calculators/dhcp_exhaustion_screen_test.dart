// Widget tests for the Wi-Fi Classroom "Conference Wi-Fi Runs Out of
// Addresses" screen (dhcp-exhaustion). The model has its own tests
// (test/services/wifi_lab/dhcp_exhaustion_model_test.dart); these check the
// screen: registration, the defaults, the main control moving the dry time,
// the rotation assumptions disabled until rotation is on, predict-then-
// reveal, playing the morning, acronyms spelled out, no vendor or product
// name on screen or in the help, the help's numbers against the model, and
// the layout at phone and desktop widths in both themes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dhcp_exhaustion_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dhcp_exhaustion_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dhcp_exhaustion_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dhcp_exhaustion_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../support/shipped_help_copy.dart';

final List<RegExp> _doNotPrint = <String>[
  'Apple',
  'iPhone',
  'iOS',
  'macOS',
  'Android',
  'Google',
  'Pixel',
  'Samsung',
  'Microsoft',
  'Windows',
  'Cisco',
  'Aruba',
  'Meraki',
  'Ubiquiti',
  'UniFi',
].map((String w) => RegExp('\\b$w\\b')).toList();

Future<DhcpExhaustionController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 6000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final DhcpExhaustionController c = DhcpExhaustionController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: DhcpExhaustionScreen(controller: c),
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
  test('catalog registers dhcp-exhaustion in the Wi-Fi Classroom, Network '
      'Design and Security, with its route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) =>
          c.tools.any((ToolEntry e) => e.id == 'dhcp-exhaustion'),
    );
    expect(cat.id, 'wifi-classroom');
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'dhcp-exhaustion',
    );
    expect(t.title, 'Conference Wi-Fi Runs Out of Addresses');
    expect(t.subgroup, 'Network Design and Security');
    expect(t.routeName, '/tools/dhcp-exhaustion');
    expect(AppRouter.dhcpExhaustion, t.routeName);
    expect(kDhcpExhaustionToolId, t.id);
  });

  test('keywords cover the brief', () {
    final List<String> kw = kToolKeywords['dhcp-exhaustion']!;
    for (final String k in <String>[
      'dhcp',
      'lease',
      'rfc 2131',
      'mac randomization',
      'conference wi-fi',
      'no internet',
    ]) {
      expect(kw, contains(k));
    }
  });

  testWidgets('opens on the defaults: a /24, a 1-day lease, dry at 10:18', (
    WidgetTester tester,
  ) async {
    final DhcpExhaustionController c = await _open(tester);
    expect(find.byType(DhcpExhaustionStage), findsOneWidget);
    expect(find.byType(DhcpExhaustionControls), findsOneWidget);
    expect(c.config, const DxConfig());
    expect(find.text('The pool ran dry at 10:18'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget);
    expect(
      find.text('254 usable addresses, 10 reserved: 244 in the pool.'),
      findsOneWidget,
    );
    expect(find.text('People over the morning (illustrative)'), findsOneWidget);
    expect(
      find.text('Share of devices that rotate (assumption)'),
      findsOneWidget,
    );
  });

  testWidgets('every acronym is spelled out before the answer', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final String intro = _screenText(
      tester,
    ).firstWhere((String s) => s.startsWith('Every device on the Wi-Fi'));
    for (final String s in <String>[
      'IP (Internet Protocol)',
      'DHCP (Dynamic Host Configuration Protocol)',
      'MAC (media access control)',
    ]) {
      expect(intro, contains(s));
    }
  });

  testWidgets('a 30-minute lease holds', (WidgetTester tester) async {
    final DhcpExhaustionController c = await _open(tester);
    c.leaseMinutes = 30;
    await tester.pump();
    expect(find.text('The pool held all morning'), findsOneWidget);
    expect(find.textContaining('covers everyone who arrived'), findsOneWidget);
  });

  testWidgets('the rotation assumptions are disabled until rotation is on', (
    WidgetTester tester,
  ) async {
    final DhcpExhaustionController c = await _open(tester);
    Slider share() => tester
        .widgetList<Slider>(find.byType(Slider))
        .firstWhere(
          (Slider s) => s.semanticFormatterCallback?.call(0.5) == '50 percent',
        );
    expect(share().onChanged, isNull);
    expect(find.text('Only used while rotation is on.'), findsOneWidget);
    await tester.ensureVisible(
      find.text('Devices rotate their private address on this open network'),
    );
    await tester.tap(
      find.text('Devices rotate their private address on this open network'),
    );
    await tester.pump();
    expect(c.config.rotation, isTrue);
    expect(share().onChanged, isNotNull);
    expect(find.text('The pool ran dry at 09:19'), findsOneWidget);
    expect(find.text('Held for old private addresses'), findsOneWidget);
  });

  testWidgets('the readouts at the dry minute', (WidgetTester tester) async {
    final DhcpExhaustionController c = await _open(tester);
    c.minute = c.morning.firstDryMinute!;
    await tester.pump();
    expect(find.text('At 10:18'), findsOneWidget);
    expect(find.text('113'), findsOneWidget);
    expect(find.text('132'), findsOneWidget);
    expect(find.text('0 of 244'), findsOneWidget);
    expect(find.text('1, no internet'), findsOneWidget);
  });

  testWidgets('predict, then reveal', (WidgetTester tester) async {
    final DhcpExhaustionController c = await _open(tester);
    c.leaseMinutes = 30;
    await tester.pump();
    await tester.ensureVisible(find.text('Ask the class'));
    await tester.tap(find.text('Ask the class'));
    await tester.pump();
    expect(c.question, DxQuestion.asking);
    expect(c.config, const DxConfig());
    expect(c.minute, c.morning.firstDryMinute);
    expect(
      find.text('Predict first: what would fix it? Then reveal.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Add more APs'));
    await tester.tap(find.text('Add more APs'));
    await tester.pump();
    await tester.ensureVisible(find.text('Reveal'));
    await tester.tap(find.text('Reveal'));
    await tester.pump();
    expect(find.text('A shorter lease or a bigger pool.'), findsOneWidget);
    expect(find.text('The class picked "Add more APs".'), findsOneWidget);
    expect(find.textContaining('at most 170 of 244'), findsOneWidget);
  });

  testWidgets('Play the morning runs to 13:00 and stops', (
    WidgetTester tester,
  ) async {
    final DhcpExhaustionController c = await _open(tester);
    await tester.ensureVisible(find.text('Play the morning'));
    await tester.tap(find.text('Play the morning'));
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kDxTick * 2);
    expect(c.minute, 10);
    await tester.pump(kDxTick * 80);
    expect(c.minute, kDxMinutes);
    expect(c.playing, isFalse);
  });

  testWidgets('copy text names the pool, the crowd and the result', (
    WidgetTester tester,
  ) async {
    final DhcpExhaustionController c = await _open(tester);
    final String t = c.copyText();
    expect(t, contains('254 usable minus 10 reserved = 244'));
    expect(t, contains('Ran dry at 10:18'));
    expect(t, contains('(illustrative)'));
  });

  testWidgets('no vendor, product or OS name on screen or in the help', (
    WidgetTester tester,
  ) async {
    final DhcpExhaustionController c = await _open(tester);
    c.rotation = true;
    await tester.pump();
    final List<String> all = <String>[
      ..._screenText(tester),
      ...shippedHelpProse('dhcp-exhaustion'),
    ];
    final List<String> hits = <String>[
      for (final String t in all)
        for (final RegExp r in _doNotPrint)
          if (r.hasMatch(t)) '${r.pattern} in "$t"',
    ];
    expect(hits, isEmpty);
  });

  test('the help example matches the model', () {
    final String ex = shippedHelpProse(
      'dhcp-exhaustion',
    ).firstWhere((String s) => s.startsWith('Defaults (/24'));
    final DxMorning d = DxMorning(const DxConfig());
    final DxMinute x = d.minutes[d.firstDryMinute!];
    expect(ex, contains('= ${d.poolSize} addresses'));
    expect(ex, contains('= ${const DxConfig().devices} devices'));
    expect(ex, contains('runs dry at ${dxClock(d.firstDryMinute!)}'));
    expect(ex, contains('only ${x.devicesHere} devices'));
    expect(ex, contains('${x.inUse} addresses are in use'));
    expect(ex, contains('${x.heldLeft} are still held'));
    expect(ex, contains('Up to ${d.peakWaiting} devices'));
    final DxMorning short = DxMorning(const DxConfig(leaseMinutes: 30));
    expect(ex, contains('at most ${short.peakBound} of 244'));
    final DxMorning two = DxMorning(const DxConfig(leaseMinutes: 120));
    expect(two.held, isTrue);
    expect(ex, contains('(peak ${two.peakBound})'));
    final DxMorning twoRot = DxMorning(
      const DxConfig(leaseMinutes: 120, rotation: true),
    );
    expect(ex, contains('runs dry at ${dxClock(twoRot.firstDryMinute!)}'));
    expect(DxMorning(const DxConfig(prefix: 23)).held, isTrue);
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double w in <double>[360, 390, 820, 1280]) {
      testWidgets('$name ${w.toInt()} px: no overflow', (
        WidgetTester tester,
      ) async {
        final DhcpExhaustionController c = await _open(
          tester,
          size: Size(w, 7000),
          theme: theme(),
        );
        for (final DxConfig cfg in <DxConfig>[
          const DxConfig(),
          const DxConfig(rotation: true, leaseMinutes: 5),
          const DxConfig(prefix: 19, people: 5000, devicesPerPerson: 3),
        ]) {
          c.leaseMinutes = cfg.leaseMinutes;
          c.rotation = cfg.rotation;
          c.prefix = cfg.prefix;
          c.people = cfg.people;
          c.devicesPerPerson = cfg.devicesPerPerson;
          c.minute = 200;
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        c.ask();
        await tester.pump();
        c.reveal();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
