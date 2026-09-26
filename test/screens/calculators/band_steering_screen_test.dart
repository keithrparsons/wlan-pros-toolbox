// Widget tests for the Wi-Fi Classroom "Band Steering" screen
// (band-steering). The engine has its own tests (test/services/wifi_lab/
// band_steering_model_test.dart); these check the screen: registration, the
// defaults, that inputs move the readouts, the disabled tolerance slider,
// predict-then-reveal, the walk controls, acronyms spelled out at first use,
// no vendor, product or operating-system name in any shipped string (the
// DO-NOT-PRINT list below, swept over the help too), the help's numbers
// against the engine, and the layout at phone and desktop widths in both
// themes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/band_steering_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/band_steering_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/band_steering_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/band_steering_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../support/shipped_help_copy.dart';

/// DO-NOT-PRINT: vendor, product and operating-system names (Keith,
/// 2026-09-26: none anywhere in the tool). Case-sensitive, whole words, so
/// "MAC (media access control)" is not "Mac".
final List<RegExp> _doNotPrint = <String>[
  'Apple',
  'iPhone',
  'iPad',
  'Mac',
  'macOS',
  'iOS',
  'Android',
  'AOSP',
  'Google',
  'Pixel',
  'Samsung',
  'Microsoft',
  'Windows',
  'Linux',
  'hostapd',
  'OpenWrt',
  'Cisco',
  'Aruba',
  'Juniper',
  'Mist',
  'Ubiquiti',
  'UniFi',
  'Ruckus',
  'Meraki',
  'Intel',
  'Qualcomm',
  'Broadcom',
  'ChromeOS',
  'Chromebook',
].map((String w) => RegExp('\\b$w\\b')).toList();

List<String> _hits(Iterable<String> texts) => <String>[
  for (final String t in texts)
    for (final RegExp r in _doNotPrint)
      if (r.hasMatch(t)) '${r.pattern} in "$t"',
];

Future<BandSteeringController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 5000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final BandSteeringController c = BandSteeringController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: BandSteeringScreen(controller: c),
    ),
  );
  await tester.pump();
  return c;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

/// Every Text and RichText string on screen, in tree order.
List<String> _screenText(WidgetTester tester) => <String>[
  for (final Element e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
];

void main() {
  test('catalog registers band-steering in the Wi-Fi Classroom beside '
      'Roaming Walk, with its route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) => c.tools.any((ToolEntry e) => e.id == 'band-steering'),
    );
    expect(cat.id, 'wifi-classroom');
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'band-steering',
    );
    expect(t.title, 'Band Steering');
    expect(t.subgroup, 'Network Design and Security');
    expect(t.routeName, '/tools/band-steering');
    expect(AppRouter.bandSteering, t.routeName);
    expect(kBandSteeringToolId, t.id);
  });

  test('keywords cover the spec list', () {
    final List<String> kw = kToolKeywords['band-steering']!;
    for (final String k in <String>[
      'band steering',
      '2.4 ghz',
      '5 ghz',
      'sticky client',
      'probe suppression',
      '802.11v',
      'bss transition',
      'mac randomization',
      'band select',
    ]) {
      expect(kw, contains(k));
    }
  });

  testWidgets('opens on the defaults: Client A at the edge, on 2.4 GHz', (
    WidgetTester tester,
  ) async {
    final BandSteeringController c = await _open(tester);
    expect(find.text('Band Steering'), findsOneWidget);
    expect(find.byType(BandSteeringStage), findsOneWidget);
    expect(find.byType(BandSteeringControls), findsOneWidget);
    expect(c.config, const BsConfig());
    expect(find.text('Client A is on'), findsOneWidget);
    expect(find.text('55 m from the AP'), findsOneWidget);
    expect(find.textContaining('can hear only 2.4 GHz'), findsWidgets);
    // Illustrative and provisional values are labeled so.
    expect(find.text('Extra 5 GHz wall loss (illustrative)'), findsOneWidget);
    expect(
      find.text('Refusals a client tolerates (illustrative)'),
      findsOneWidget,
    );
    expect(find.textContaining('Provisional, pending review'), findsOneWidget);
    expect(find.textContaining('-82 dBm, illustrative'), findsOneWidget);
    expect(
      find.textContaining('Not modeled: forcing a client off'),
      findsOneWidget,
    );
  });

  testWidgets('the refusal tolerance slider is disabled outside '
      'authentication refusal', (WidgetTester tester) async {
    final BandSteeringController c = await _open(tester);
    Slider tol() => tester
        .widgetList<Slider>(find.byType(Slider))
        .firstWhere(
          (Slider s) => s.semanticFormatterCallback?.call(3) == '3 refusals',
        );
    expect(tol().onChanged, isNull);
    expect(find.text('Only used with authentication refusal.'), findsOneWidget);
    c.mode = SteeringMode.authRefusal;
    await tester.pump();
    expect(tol().onChanged, isNotNull);
  });

  testWidgets('a transition request to Client B at the edge is declined in '
      'words', (WidgetTester tester) async {
    final BandSteeringController c = await _open(tester);
    c.profile = ClientProfile.b;
    c.mode = SteeringMode.transitionRequest;
    await tester.pump();
    expect(
      find.text('Declined: no suitable candidates (status 7)'),
      findsOneWidget,
    );
    expect(find.textContaining('so it declined: no suitable'), findsWidgets);
  });

  testWidgets('the random-address switch stops authentication refusal', (
    WidgetTester tester,
  ) async {
    final BandSteeringController c = await _open(tester);
    c.mode = SteeringMode.authRefusal;
    c.path = WalkPath.apToEdge;
    c.index = c.stepCount - 1;
    await tester.pump();
    expect(find.textContaining('3 (the AP gives in after 3)'), findsOneWidget);
    await _tap(
      tester,
      find.text('Client uses a random address while scanning'),
    );
    expect(c.config.randomScanAddress, isTrue);
    expect(find.textContaining('0 (the AP gives in after 3)'), findsOneWidget);
  });

  testWidgets('Step, Reset and Walk move the client', (
    WidgetTester tester,
  ) async {
    final BandSteeringController c = await _open(tester);
    await _tap(tester, find.text('Step 1 m'));
    expect(c.index, 1);
    expect(find.text('54 m from the AP'), findsOneWidget);
    await _tap(tester, find.text('Reset'));
    expect(c.index, 0);
    await _tap(tester, find.text('Walk'));
    expect(c.playing, isTrue);
    await tester.pump(kBsStepDuration * 3);
    expect(c.index, 3);
    await _tap(tester, find.text('Pause'));
    expect(c.playing, isFalse);
    // The walk ends at the AP.
    await _tap(tester, find.text('Walk'));
    await tester.pump(kBsStepDuration * 60);
    expect(c.atEnd, isTrue);
    expect(c.playing, isFalse);
    expect(find.text('2 m from the AP'), findsOneWidget);
  });

  testWidgets('predict, then reveal: the client stays on 2.4 GHz', (
    WidgetTester tester,
  ) async {
    final BandSteeringController c = await _open(tester);
    c.profile = ClientProfile.c;
    c.mode = SteeringMode.transitionRequest;
    await tester.pump();
    await _tap(tester, find.text('Ask the class'));
    expect(c.question, BsQuestion.asking);
    // The question's walk: steering off, edge to AP, Client A.
    expect(c.config.mode, SteeringMode.off);
    expect(c.config.path, WalkPath.edgeToAp);
    expect(c.config.profile, ClientProfile.a);
    expect(c.index, 0);
    expect(find.text(kBsQuestionText), findsOneWidget);
    await _tap(tester, find.text(BsGuess.no.label));
    await _tap(tester, find.text('Reveal'));
    expect(
      find.textContaining(
        "No. Under Client A's and Client B's published rules, it stays on "
        '2.4 GHz',
      ),
      findsOneWidget,
    );
    expect(find.textContaining(': right.'), findsOneWidget);
    await tester.pump(kBsStepDuration * 60);
    expect(c.atEnd, isTrue);
    expect(c.step.band, BsBand.ghz24);
    expect(c.questionAnswer, (a: BsBand.ghz24, b: BsBand.ghz24));
  });

  testWidgets('acronyms are spelled out at first use on screen', (
    WidgetTester tester,
  ) async {
    final BandSteeringController c = await _open(tester);
    c.mode = SteeringMode.transitionRequest;
    await tester.pump();
    final String all = _screenText(tester).join('\n');
    for (final (String short, String long) in <(String, String)>[
      ('MAC', 'media access control'),
      ('BSS', 'basic service set'),
    ]) {
      final int at = RegExp('\\b$short\\b').firstMatch(all)!.start;
      expect(
        all.substring(at, at + short.length + long.length + 3),
        '$short ($long)',
        reason: short,
      );
    }
  });

  testWidgets('no vendor, product or operating-system name on screen, in any '
      'profile and mode', (WidgetTester tester) async {
    final BandSteeringController c = await _open(tester);
    for (final ClientProfile p in ClientProfile.values) {
      for (final SteeringMode m in SteeringMode.values) {
        c.profile = p;
        c.mode = m;
        c.index = 20;
        await tester.pump();
        expect(_hits(_screenText(tester)), isEmpty, reason: '$p $m');
      }
    }
  });

  test('no vendor, product or operating-system name in the model strings, '
      'catalog, keywords or help', () {
    final List<String> texts = <String>[];
    for (final ClientProfile p in ClientProfile.values) {
      for (final SteeringMode m in SteeringMode.values) {
        for (final WalkPath path in WalkPath.values) {
          for (final bool random in <bool>[false, true]) {
            final BsWalk w = simulateWalk(
              BsConfig(
                profile: p,
                mode: m,
                path: path,
                randomScanAddress: random,
                driverSupportsBtm: p != ClientProfile.c || !random,
              ),
            );
            for (final BsStep s in w.steps) {
              texts.add(s.why);
              texts.addAll(s.frames.map((BsFrame f) => f.text));
              if (s.btm != null) texts.add(s.btm!.label);
            }
          }
        }
        texts.add(bsModeNote(m));
      }
      texts.add(bsProfileNote(p));
    }
    final ToolEntry t = kToolCategories
        .expand((ToolCategory c) => c.tools)
        .firstWhere((ToolEntry e) => e.id == 'band-steering');
    texts.addAll(<String>[t.title, t.description]);
    texts.addAll(shippedHelpProse('band-steering'));
    expect(_hits(texts), isEmpty);
    // Keywords are lower case; "mac" there is the address, so it is skipped.
    final List<String> kw = kToolKeywords['band-steering']!;
    for (final String k in kw) {
      for (final String banned in <String>[
        'apple',
        'iphone',
        'android',
        'microsoft',
        'windows',
        'hostapd',
      ]) {
        expect(k.contains(banned), isFalse, reason: k);
      }
    }
  });

  test('the help mentions Present and its keys, and the deauthentication '
      'exclusion; its example numbers match the engine', () {
    final List<String> help = shippedHelpProse('band-steering');
    final String all = help.join('\n');
    expect(all, contains('Present opens this simulator'));
    for (final String k in <String>[
      'Space',
      'Right arrow',
      'R resets',
      'Up and Down',
    ]) {
      expect(all, contains(k));
    }
    expect(
      all,
      contains(
        'Not modeled: an AP forcing a client off with a '
        'deauthentication frame',
      ),
    );
    expect(
      all,
      contains('The Wi-Fi Classroom is designed for tablets and computers'),
    );

    // "at 55 m 2.4 GHz arrives at -78.4 dBm and 5 GHz at -88.5 dBm"
    final BsWalk w = simulateWalk(const BsConfig());
    expect(bsDbm(w.steps.first.rssi24), '-78.4 dBm');
    expect(bsDbm(w.steps.first.rssi5), '-88.5 dBm');
    expect(all, contains('-78.4 dBm and 5 GHz at -88.5 dBm'));
    // "2.4 GHz rises above -70 dBm at about 29 m"
    expect(bsRangeM(BsBand.ghz24, -70), closeTo(29, 0.5));
    // "at 2 m it is still on 2.4 GHz at -35.2 dBm, with 5 GHz at -45.3 dBm"
    expect(w.last.band, BsBand.ghz24);
    expect(bsDbm(w.last.rssi24), '-35.2 dBm');
    expect(bsDbm(w.last.rssi5), '-45.3 dBm');
    expect(all, contains('-35.2 dBm, with 5 GHz at -45.3 dBm'));
    // "Client B ... accepts and moves at 20 m"
    final BsWalk b = simulateWalk(
      const BsConfig(
        profile: ClientProfile.b,
        mode: SteeringMode.transitionRequest,
      ),
    );
    expect(
      b.steps.firstWhere((BsStep s) => s.band == BsBand.ghz5).distanceM,
      20,
    );
    expect(all, contains('moves at 20 m'));
    // "7.1 dB"
    expect(bsFreeSpaceGapDb.toStringAsFixed(1), '7.1');
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double w in <double>[390, 820, 1280]) {
      testWidgets('$name at ${w.toInt()} px: no overflow in any mode', (
        WidgetTester tester,
      ) async {
        final BandSteeringController c = await _open(
          tester,
          size: Size(w, 5000),
          theme: theme(),
        );
        for (final SteeringMode m in SteeringMode.values) {
          c.mode = m;
          c.profile = ClientProfile.c;
          c.path = WalkPath.apToEdge;
          c.index = 33;
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$m');
        }
      });
    }
  }
}
