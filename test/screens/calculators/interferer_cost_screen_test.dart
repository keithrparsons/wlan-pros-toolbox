// Widget tests for the Wi-Fi Classroom tool What an Interferer Costs
// (interferer-cost).
//
// The model is pinned in test/services/wifi_lab/interferer_cost_model_test
// .dart; these cover the screen contract: catalog, route, help, icon and
// keywords; acronyms spelled out at first use in the help; the illustrative
// labels; the standard-minimum caveat and the links to the spectrum lessons;
// no vendor or product name in any string the tool ships; the fresh state;
// predict, then reveal; what each band offers; the absent state; stage and
// controls as separate widgets; the copy text; phone, tablet and desktop in
// both themes with no overflow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/interferer_cost_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/units/unit_system.dart';

Future<InterfererCostController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1024,
  double height = 1366,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: true,
        ),
        child: const InterfererCostScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<InterfererCostStage>(find.byType(InterfererCostStage))
      .controller;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kInterfererCostToolId]
        as Map<String, dynamic>;

/// The help in the order the help sheet shows it.
String _helpText() {
  final Map<String, dynamic> h = _help();
  return <String>[
    h['name'] as String,
    h['purpose'] as String,
    h['whyHere'] as String,
    ...(h['howToUse'] as List<dynamic>).cast<String>(),
    for (final dynamic i in h['inputs'] as List<dynamic>)
      '${(i as Map<String, dynamic>)['name']} ${i['range']}',
    h['algorithm'] as String,
    h['example'] as String,
    ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
    h['source'] as String,
  ].join('\n');
}

/// Vendor and product names the tool must never show (standing rule).
/// Citations keep their real sources (Airshark is a research system).
const List<String> _vendorNames = <String>[
  'cisco',
  'aruba',
  'hpe',
  'juniper',
  'mist',
  'ruckus',
  'ubiquiti',
  'unifi',
  'extreme networks',
  'meraki',
  'fortinet',
  'huawei',
  'netgear',
  'tp-link',
  'broadcom',
  'qualcomm',
  'intel',
  'mediatek',
  'apple',
  'iphone',
  'samsung',
  'android',
  'ekahau',
  'hamina',
  'atheros',
];

void main() {
  test('catalog, route, help, icon and keywords register interferer-cost on '
      'the Airtime and Access shelf', () {
    final ToolCategory c = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry e = c.tools.firstWhere(
      (ToolEntry t) => t.id == kInterfererCostToolId,
    );
    expect(e.title, 'What an Interferer Costs (and how a NIC hears the air)');
    expect(e.subgroup, 'Airtime and Access');
    expect(e.routeName, AppRouter.interfererCost);
    expect(AppRouter.routes.containsKey('/tools/interferer-cost'), isTrue);
    expect(File('assets/tool-icons/interferer-cost.svg').existsSync(), isTrue);
    expect(_help()['name'], e.title);

    final String how = (_help()['howToUse'] as List<dynamic>).join(' ');
    for (final String k in <String>[
      'Present',
      'Up and Down',
      'N picks the next source',
      'C the next channel',
      'R resets',
    ]) {
      expect(how, contains(k));
    }
    final List<String> kw = kToolKeywords[kInterfererCostToolId]!;
    for (final String k in <String>[
      'microwave',
      'bluetooth',
      'co-channel',
      'cca',
      'preamble detect',
      'energy detect',
      'deferral',
    ]) {
      expect(kw, contains(k));
    }
  });

  test('the help spells out NIC, AP, CCA, PPDU and FFT at first use', () {
    final String t = _helpText();
    for (final (String acronym, String spelled) in <(String, String)>[
      ('NIC', 'network interface card (NIC)'),
      ('AP', 'access point (AP)'),
      ('CCA', 'clear channel assessment (CCA)'),
      ('PPDU', 'physical layer protocol data unit (PPDU)'),
      ('FFT', 'fast Fourier transform (FFT)'),
    ]) {
      final String body = t.substring(t.indexOf('\n') + 1); // after the name
      final int first = RegExp('\\b$acronym\\b').firstMatch(body)!.start;
      final int spelledAt = body.indexOf(spelled);
      expect(spelledAt, isNonNegative, reason: spelled);
      expect(
        first,
        inInclusiveRange(spelledAt, spelledAt + spelled.length),
        reason: '$acronym first appears before it is spelled out',
      );
    }
  });

  test('the help carries the brief\'s caveats: standard minimums, the real '
      'chip near -91, one source past 20 MHz, no 320 MHz value, '
      'illustrative corruption, and links to the spectrum lessons', () {
    final String t = _helpText();
    expect(t, contains("standard's minimum requirements"));
    expect(t, contains('-91 dBm'));
    expect(t, contains('makes the real gap wider'));
    expect(t, contains('come from one source'));
    expect(t, contains('320 MHz is left out'));
    expect(t, contains('corrupted-frame shares are illustrative'));
    expect(t, contains('Spectrum Analysis'));
    expect(t, contains('Swept vs FFT race'));
    expect(t, contains("Keith's field observation"));
    expect(t, contains('The Wi-Fi Classroom is designed for tablets'));
    // Frame loss is not the headline: the why leads with waiting.
    expect(_help()['whyHere'] as String, startsWith('Many people assume'));
  });

  test('no vendor or product name in any string the tool ships', () {
    final List<String> sources = <String>[
      for (final String f in <String>[
        'interferer_cost_controller.dart',
        'interferer_cost_controls.dart',
        'interferer_cost_painters.dart',
        'interferer_cost_parts.dart',
        'interferer_cost_screen.dart',
        'interferer_cost_stage.dart',
      ])
        File('lib/screens/tools/calculators/$f').readAsStringSync(),
      File(
        'lib/services/wifi_lab/interferer_cost_model.dart',
      ).readAsStringSync(),
      jsonEncode(_help()),
      kToolKeywords[kInterfererCostToolId]!.join(' '),
    ];
    for (final String s in sources) {
      final String lower = s.toLowerCase();
      for (final String name in _vendorNames) {
        expect(
          RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(lower),
          isFalse,
          reason: 'found "$name"',
        );
      }
    }
  });

  testWidgets('fresh: the neighbor at -78 costs 30% waiting, the gap reads '
      '20 dB, and the question waits', (WidgetTester tester) async {
    final InterfererCostController c = await _pump(tester);
    expect(c.config.source, IcSource.wifiNeighbor);
    expect(find.text(kIcQuestion), findsOneWidget);
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.text('30%'), findsWidgets);
    expect(
      find.textContaining('Your radio waits: a Wi-Fi preamble at or above -82'),
      findsOneWidget,
    );
    expect(find.text('Airtime lost waiting'), findsOneWidget);
    expect(find.text('Airtime lost to corrupted frames'), findsOneWidget);
    expect(find.text(kIcIllustrativeCorruption), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'The gap is 20 dB, 100 times')),
      findsOneWidget,
    );
  });

  testWidgets('Reveal loads both at -70 and names the neighbor', (
    WidgetTester tester,
  ) async {
    final InterfererCostController c = await _pump(tester);
    await _tap(tester, find.text('The oven'));
    expect(c.prediction, IcPrediction.microwave);
    await _tap(tester, find.text('Reveal'));
    expect(c.revealed, isTrue);
    expect(c.config, kIcQuestionScene);
    expect(find.text("The neighbor's AP, by a wide margin."), findsOneWidget);
    expect(find.textContaining('12 dB above the -82 dBm'), findsOneWidget);
    expect(find.textContaining('8 dB below the -62 dBm'), findsOneWidget);
    // The answer stays with its scene when the student moves on.
    c.level = -90;
    await tester.pumpAndSettle();
    expect(find.textContaining('12 dB above the -82 dBm'), findsOneWidget);
    await _tap(tester, find.text('Ask again'));
    expect(c.revealed, isFalse);
    expect(c.prediction, isNull);
  });

  testWidgets('a right answer is called right', (WidgetTester tester) async {
    await _pump(tester);
    await _tap(tester, find.text("The neighbor's AP"));
    await _tap(tester, find.text('Reveal'));
    expect(find.text("Right: the neighbor's AP."), findsOneWidget);
  });

  testWidgets('widths only on 5 GHz; the mains toggle only for the oven; '
      'the oven on 5 GHz reads not on this band', (WidgetTester tester) async {
    final InterfererCostController c = await _pump(tester);
    expect(c.widths, <int>[20]);
    expect(find.text('Channel width (MHz)'), findsNothing);
    expect(find.text('Mains power'), findsNothing);
    c.channel = IcChannel.ch36;
    await tester.pumpAndSettle();
    expect(c.widths, kIcWidthsMHz);
    expect(find.text('Channel width (MHz)'), findsOneWidget);
    c.widthMHz = 160;
    await tester.pumpAndSettle();
    expect(c.result.preambleDetectDbm, -73);
    c.widthMHz = 320; // refused: no pinned threshold
    expect(c.config.widthMHz, 160);
    c.source = IcSource.microwave;
    await tester.pumpAndSettle();
    expect(find.text('Mains power'), findsOneWidget);
    expect(
      find.textContaining('Not on this band: nothing to wait for'),
      findsOneWidget,
    );
    // Back to 2.4 GHz snaps the width to 20.
    c.channel = IcChannel.ch1;
    await tester.pumpAndSettle();
    expect(c.config.widthMHz, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the video sender is not heard and ruins frames; the verdict '
      'says so in words', (WidgetTester tester) async {
    final InterfererCostController c = await _pump(tester);
    c.source = IcSource.videoSender;
    await tester.pumpAndSettle();
    expect(
      find.text('Not heard: under -62 dBm, your radio sends into it'),
      findsOneWidget,
    );
    expect(c.result.selected.corruptionShare, greaterThanOrEqualTo(0.8));
    expect(find.text('88%'), findsWidgets);
  });

  testWidgets('R resets; Reset to defaults does the same; N and C step', (
    WidgetTester tester,
  ) async {
    final InterfererCostController c = await _pump(tester);
    c
      ..level = -50
      ..channel = IcChannel.ch36;
    await tester.pumpAndSettle();
    c.presenterActions.reset!();
    expect(c.config, const IcConfig());
    c.nextSource();
    expect(c.config.source, IcSource.microwave);
    c.nextChannel();
    expect(c.config.channel, IcChannel.ch36);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Reset to defaults'));
    expect(c.config, const IcConfig());
  });

  testWidgets('stage and controls are separate widgets, and the copy text '
      'labels the corruption illustrative', (WidgetTester tester) async {
    final InterfererCostController c = await _pump(tester);
    expect(find.byType(InterfererCostStage), findsOneWidget);
    expect(find.byType(InterfererCostControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InterfererCostStage),
        matching: find.byType(InterfererCostControls),
      ),
      findsNothing,
    );
    final String copy = c.copyText();
    expect(copy, contains('a 20 dB gap, 100x the power'));
    expect(copy, contains('corrupted frames 88% (illustrative)'));
    expect(copy, contains('114 m'));
    expect(copy, contains('25 m'));
  });

  testWidgets('distances follow the units preference', (
    WidgetTester tester,
  ) async {
    final InterfererCostController c = await _pump(tester);
    c.setUnits(UnitSystem.imperial);
    expect(c.copyText(), contains('375 ft'));
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final (double w, double h) in <(double, double)>[
      (390, 844),
      (820, 1180),
      (1280, 800),
    ]) {
      testWidgets('$name ${w.toInt()}x${h.toInt()}: renders with no overflow '
          'across sources, channels and the reveal', (
        WidgetTester tester,
      ) async {
        final InterfererCostController c = await _pump(
          tester,
          theme: theme(),
          width: w,
          height: h,
        );
        for (final IcSource s in IcSource.values) {
          for (final IcChannel ch in IcChannel.values) {
            c
              ..source = s
              ..channel = ch;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$s $ch');
          }
        }
        c
          ..widthMHz = 160
          ..level = -30;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        c.reveal();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the width scaling is labeled the 5 GHz rule; no 6 GHz '
      'option is offered', (WidgetTester tester) async {
    final InterfererCostController c = await _pump(tester);
    expect(find.text('6 GHz'), findsNothing);
    expect(find.textContaining('This widening applies to 5 GHz'), findsNothing);
    c.channel = IcChannel.ch36;
    c.widthMHz = 40;
    await tester.pumpAndSettle();
    expect(c.result.gapDb, 17);
    expect(find.textContaining('This widening applies to 5 GHz'), findsWidgets);
    expect(c.copyText(), contains('This widening applies to 5 GHz'));
    c.channel = IcChannel.ch11;
    await tester.pumpAndSettle();
    expect(c.result.gapDb, 20);
    expect(c.copyText(), isNot(contains('This widening applies to 5 GHz')));
    expect(tester.takeException(), isNull);
  });
}
