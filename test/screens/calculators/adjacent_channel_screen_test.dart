// Widget tests for the Wi-Fi Classroom "Adjacent Channels and AP Stacking"
// screen (spec 29).
//
// The model is pinned in test/services/wifi_lab/adjacent_channel_model_test
// .dart; these cover the screen contract: catalog, route, help, icon and
// keywords; acronyms spelled out at first use in the help; every rejection
// value labeled illustrative; no vendor or product name in any string the tool
// ships; the fresh state and its verdicts; predict, then reveal; the controls
// offer only what the band allows; stage and controls as separate widgets;
// the copy text; phone and desktop widths in both themes with no overflow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/adjacent_channel_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<AdjacentChannelController> _pump(
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
        child: const AdjacentChannelScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<AdjacentChannelStage>(find.byType(AdjacentChannelStage))
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
            as Map<String, dynamic>)[kAdjacentChannelToolId]
        as Map<String, dynamic>;

/// The help in the order the help sheet shows it.
String _helpText() {
  final Map<String, dynamic> h = _help();
  return <String>[
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

/// Vendor and product names the tool must never show (standing rule). Word
/// boundaries, so "Extremely High Throughput" (the IEEE name) is not a hit.
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
  'cambium',
  'huawei',
  'netgear',
  'tp-link',
  'rohde',
  'schwarz',
  'keysight',
  'tektronix',
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
];

void main() {
  test('catalog, route, help, icon and keywords register adjacent-channel '
      'next to Channel Planner', () {
    final ToolCategory c = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final List<String> ids = c.tools.map((ToolEntry t) => t.id).toList();
    expect(
      ids.indexOf(kAdjacentChannelToolId),
      ids.indexOf('channel-planner') + 1,
    );
    final ToolEntry e = c.tools.firstWhere(
      (ToolEntry t) => t.id == kAdjacentChannelToolId,
    );
    expect(e.title, 'Adjacent Channels and AP Stacking');
    expect(e.subgroup, 'Network Design and Security');
    expect(e.routeName, AppRouter.adjacentChannel);
    expect(AppRouter.routes.containsKey('/tools/adjacent-channel'), isTrue);
    expect(File('assets/tool-icons/adjacent-channel.svg').existsSync(), isTrue);

    final String how = (_help()['howToUse'] as List<dynamic>).join(' ');
    for (final String k in <String>['Present', 'Up and Down', 'R resets']) {
      expect(how, contains(k));
    }
    expect(_helpText(), contains('Channel Planner'));

    final List<String> kw = kToolKeywords[kAdjacentChannelToolId]!;
    for (final String k in <String>[
      'adjacent channel',
      'aci',
      'spectral mask',
      'ap stacking',
      'co-located aps',
      'desense',
      'rejection',
    ]) {
      expect(kw, contains(k));
    }
  });

  test('the help spells out ACR, SINR, SIR, CCA, MCS, OFDM and dBr at first '
      'use, and says the rejection values are illustrative', () {
    final String t = _helpText();
    for (final (String acronym, String spelled) in <(String, String)>[
      ('ACR', 'adjacent-channel rejection (ACR)'),
      ('SINR', 'SINR (signal to interference plus noise ratio)'),
      ('SIR', 'SIR (signal to interference ratio)'),
      ('CCA', 'CCA (clear channel assessment)'),
      ('MCS', 'MCS (modulation and coding scheme)'),
      ('OFDM', 'OFDM (orthogonal frequency-division multiplexing'),
      ('dBr', 'dBr (decibels relative'),
    ]) {
      final int first = RegExp('\\b$acronym\\b').firstMatch(t)!.start;
      final int spelledAt = t.indexOf(spelled);
      expect(spelledAt, isNonNegative, reason: spelled);
      expect(
        first,
        inInclusiveRange(spelledAt, spelledAt + spelled.length),
        reason: '$acronym first appears before it is spelled out',
      );
    }
    expect(t, contains('illustrative'));
    expect(t, contains('no primary per-rate table was read'));
  });

  test('no vendor or product name in any string the tool ships', () {
    final List<String> sources = <String>[
      for (final String f in <String>[
        'adjacent_channel_controller.dart',
        'adjacent_channel_controls.dart',
        'adjacent_channel_painters.dart',
        'adjacent_channel_parts.dart',
        'adjacent_channel_screen.dart',
        'adjacent_channel_stage.dart',
      ])
        File('lib/screens/tools/calculators/$f').readAsStringSync(),
      File(
        'lib/services/wifi_lab/adjacent_channel_model.dart',
      ).readAsStringSync(),
      jsonEncode(_help()),
      kToolKeywords[kAdjacentChannelToolId]!.join(' '),
      kToolCategories
          .expand((ToolCategory c) => c.tools)
          .firstWhere((ToolEntry t) => t.id == kAdjacentChannelToolId)
          .description,
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

  testWidgets('fresh: 36 and 44 at 3 m, MCS 8 falls to MCS 4, energy detect '
      'clear, and the question waits', (WidgetTester tester) async {
    final AdjacentChannelController c = await _pump(tester);
    expect(c.plan.neighborChannel, 36);
    expect(c.plan.receiverChannel, 44);
    expect(find.text(kAciQuestion), findsOneWidget);
    expect(find.text('Reveal'), findsOneWidget);
    expect(find.text('MCS 8 to MCS 4'), findsOneWidget);
    expect(find.text('Down 4 MCS steps'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(
      find.text('Highest MCS (modulation and coding scheme)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('SINR (signal to interference plus noise ratio)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('clear channel assessment (CCA)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Adjacent-channel rejection (ACR)'),
      findsOneWidget,
    );
  });

  testWidgets('every rejection value is labeled illustrative', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text(kAciIllustrativeNote), findsOneWidget);
    for (final AciRateGroup g in AciRateGroup.values) {
      expect(find.text('${g.label} (illustrative)'), findsOneWidget);
    }
    expect(find.textContaining(': illustrative.'), findsOneWidget);
  });

  testWidgets('Reveal loads the 36 and 44 at 30 cm scene and answers from it', (
    WidgetTester tester,
  ) async {
    final AdjacentChannelController c = await _pump(tester);
    await _tap(tester, find.text('Yes, a problem'));
    expect(c.prediction, AciPrediction.problem);
    await _tap(tester, find.text('Reveal'));
    expect(c.revealed, isTrue);
    expect(c.config.neighborDistanceM, 0.3);
    expect(c.result.ccaBusy, isTrue);
    expect(
      find.text('Right: they do not overlap, and it still hurts.'),
      findsOneWidget,
    );
    expect(find.textContaining('above the -62 dBm'), findsOneWidget);
    expect(find.text('Link lost'), findsOneWidget);
    expect(find.text('Busy: your radio waits'), findsOneWidget);
    // The answer stays with its scene when the student moves on.
    c.neighborDistanceM = 20;
    await tester.pumpAndSettle();
    expect(find.textContaining('above the -62 dBm'), findsOneWidget);
    await _tap(tester, find.text('Ask again'));
    expect(c.revealed, isFalse);
    expect(c.prediction, isNull);
  });

  testWidgets('the controls offer only what the band allows', (
    WidgetTester tester,
  ) async {
    final AdjacentChannelController c = await _pump(tester);
    c.band = WifiBand.band24;
    await tester.pumpAndSettle();
    expect(c.widths, <int>[20]);
    expect(c.separations, AciSeparation.forBand(WifiBand.band24));
    expect(c.config.separation, AciSeparation.ch1and6);
    expect(find.text('Neighbor width (MHz)'), findsNothing);
    c.band = WifiBand.band6;
    await tester.pumpAndSettle();
    expect(c.families, <AciMaskFamily>[AciMaskFamily.heEht]);
    expect(c.widths, <int>[20, 40, 80, 160, 320]);
    c.neighborWidthMHz = 320;
    c.family = AciMaskFamily.ofdm; // refused: no OFDM mask at 320 MHz
    await tester.pumpAndSettle();
    expect(c.config.family, AciMaskFamily.heEht);
    c.band = WifiBand.band5;
    await tester.pumpAndSettle();
    expect(c.config.neighborWidthMHz, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R resets; Reset to defaults does the same', (
    WidgetTester tester,
  ) async {
    final AdjacentChannelController c = await _pump(tester);
    c
      ..neighborDistanceM = 0.5
      ..neighborPowerDbm = 5
      ..setRejection(AciRateGroup.low, 30);
    await tester.pumpAndSettle();
    c.presenterActions.reset!();
    expect(c.config.neighborDistanceM, const AciConfig().neighborDistanceM);
    c.neighborPowerDbm = 5;
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Reset to defaults'));
    expect(c.config.neighborPowerDbm, const AciConfig().neighborPowerDbm);
  });

  testWidgets('stage and controls are separate widgets, and the copy text '
      'says the rejection is illustrative', (WidgetTester tester) async {
    final AdjacentChannelController c = await _pump(tester);
    expect(find.byType(AdjacentChannelStage), findsOneWidget);
    expect(find.byType(AdjacentChannelControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AdjacentChannelStage),
        matching: find.byType(AdjacentChannelControls),
      ),
      findsNothing,
    );
    final String copy = c.copyText();
    expect(copy, contains('Rejection dB (illustrative)'));
    expect(copy, contains('worst case the mask allows'));
    expect(copy, contains('ch 36'));
    expect(copy, contains('ch 44'));
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
          'across bands and the reveal', (WidgetTester tester) async {
        final AdjacentChannelController c = await _pump(
          tester,
          theme: theme(),
          width: w,
          height: h,
        );
        for (final WifiBand b in WifiBand.values) {
          c.band = b;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: b.label);
        }
        c.neighborWidthMHz = 320;
        c.neighborDistanceM = 0.3;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        c.reveal();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
