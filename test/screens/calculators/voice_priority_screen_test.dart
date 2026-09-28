// Widget tests for the Wi-Fi Classroom "Voice Priority, End to End" screen
// (voice-priority). The model has its own tests (test/services/wifi_lab/
// voice_priority_model_test.dart); these check the screen: registration,
// the defaults, that the main control moves the call between queues, the
// disabled frames-ahead slider with its reason, predict-then-reveal hiding
// the answer, the hop-by-hop trip, acronyms spelled out, no vendor or
// product name in any shipped string (help included), the help's numbers
// against the model, and the layout at phone and desktop widths in both
// themes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/voice_priority_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/voice_priority_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/voice_priority_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/voice_priority_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

import '../../support/shipped_help_copy.dart';

/// DO-NOT-PRINT: vendor, product and operating-system names (Keith,
/// 2026-09-26). Case-sensitive whole words.
final List<RegExp> _doNotPrint = <String>[
  'Apple',
  'iPhone',
  'Android',
  'Google',
  'Samsung',
  'Microsoft',
  'Windows',
  'Cisco',
  'Aruba',
  'Juniper',
  'Meraki',
  'Ubiquiti',
  'Zoom',
  'Teams',
  'WhatsApp',
  'FaceTime',
  'Skype',
].map((String w) => RegExp('\\b$w\\b')).toList();

Future<VoicePriorityController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 5000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final VoicePriorityController c = VoicePriorityController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: VoicePriorityScreen(controller: c),
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
  test('catalog registers voice-priority in the Wi-Fi Classroom, Airtime and '
      'Access, with its route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) =>
          c.tools.any((ToolEntry e) => e.id == 'voice-priority'),
    );
    expect(cat.id, 'wifi-classroom');
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'voice-priority',
    );
    expect(t.title, 'Voice Priority, End to End');
    expect(t.subgroup, 'Airtime and Access');
    expect(t.routeName, '/tools/voice-priority');
    expect(AppRouter.voicePriority, t.routeName);
    expect(kVoicePriorityToolId, t.id);
  });

  test('keywords cover the brief', () {
    final List<String> kw = kToolKeywords['voice-priority']!;
    for (final String k in <String>[
      'dscp',
      'wmm',
      'qos',
      'rfc 8325',
      'expedited forwarding',
      'user priority',
      'best effort',
      'tunnel',
    ]) {
      expect(kw, contains(k));
    }
  });

  testWidgets('opens on the defaults: the call in Voice, EF at every hop', (
    WidgetTester tester,
  ) async {
    final VoicePriorityController c = await _open(tester);
    expect(find.byType(VoicePriorityStage), findsOneWidget);
    expect(find.byType(VoicePriorityControls), findsOneWidget);
    expect(c.config, const VpConfig());
    expect(find.text('Voice (AC_VO)'), findsOneWidget);
    expect(find.text('EF (46)'), findsNWidgets(7));
    expect(find.text('Marking lost here'), findsNothing);
    expect(find.text('Marking lost here'), findsNothing);
    expect(find.text('Packet here'), findsOneWidget);
    expect(find.text('0.48 ms'), findsOneWidget);
    // Illustrative values are labeled so.
    expect(
      find.text('Download frames ahead in Best effort (illustrative)'),
      findsOneWidget,
    );
    expect(find.textContaining('every 20 ms (illustrative)'), findsOneWidget);
  });

  testWidgets('every acronym is spelled out before the answer', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final String intro = _screenText(tester).firstWhere(
      (String s) => s.startsWith('The caller'),
    );
    for (final String s in <String>[
      'EF (Expedited Forwarding)',
      'DSCP (Differentiated Services Code Point)',
      'access point (AP)',
      'user priority (UP)',
      'WMM (Wi-Fi Multimedia)',
      'access categories (AC)',
      'RFC (Request for Comments)',
    ]) {
      expect(intro, contains(s));
    }
  });

  testWidgets('losing the mark at the provider drops the call to Best '
      'effort, and its wait grows', (WidgetTester tester) async {
    final VoicePriorityController c = await _open(tester);
    await tester.ensureVisible(find.text('Provider'));
    await tester.tap(find.text('Provider'));
    await tester.pump();
    expect(c.config.loss, MarkLoss.isp);
    expect(find.text('Best effort (AC_BE)'), findsOneWidget);
    expect(find.text('Marking lost here'), findsOneWidget);
    expect(find.text('Best effort: the call'), findsOneWidget);
    expect(find.text('25.9 ms'), findsOneWidget);
  });

  testWidgets('the tunnel note says it depends on the device', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    expect(find.textContaining('depends on the device'), findsWidgets);
  });

  testWidgets('top three bits: Video, not Voice', (WidgetTester tester) async {
    final VoicePriorityController c = await _open(tester);
    c.mapping = ApMapping.topThreeBits;
    await tester.pump();
    expect(find.text('Video (AC_VI)'), findsOneWidget);
    expect(find.textContaining('Video, not Voice'), findsOneWidget);
  });

  testWidgets('the frames-ahead slider is disabled unless the call is in Best '
      'effort with a download, with the reason in words', (
    WidgetTester tester,
  ) async {
    final VoicePriorityController c = await _open(tester);
    Slider s() => tester.widget<Slider>(find.byType(Slider));
    expect(s().onChanged, isNull);
    expect(
      find.text('Only used when the call lands in Best effort.'),
      findsOneWidget,
    );
    c.loss = MarkLoss.tunnel;
    await tester.pump();
    expect(s().onChanged, isNotNull);
    c.downloadRunning = false;
    await tester.pump();
    expect(s().onChanged, isNull);
    expect(find.text('Only used while a download runs.'), findsOneWidget);
  });

  testWidgets('predict, then reveal hides the answer until Reveal', (
    WidgetTester tester,
  ) async {
    final VoicePriorityController c = await _open(tester);
    await tester.ensureVisible(find.text('Ask the class'));
    await tester.tap(find.text('Ask the class'));
    await tester.pump();
    expect(c.question, VpQuestion.asking);
    expect(c.config.loss, MarkLoss.isp);
    expect(find.text('?'), findsWidgets);
    expect(find.text('Best effort (AC_BE)'), findsNothing);
    expect(find.text('Best effort: the call'), findsNothing);
    await tester.ensureVisible(find.text('Voice').last);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Voice'));
    await tester.pump();
    await tester.ensureVisible(find.text('Reveal'));
    await tester.tap(find.text('Reveal'));
    await tester.pump();
    expect(c.question, VpQuestion.revealed);
    expect(find.text('Best effort (AC_BE)'), findsOneWidget);
    expect(find.text('Best effort.'), findsOneWidget);
    expect(find.text('The class picked "Voice".'), findsOneWidget);
    expect(c.hop, VpHopId.air.index);
  });

  testWidgets('Send the packet moves it hop by hop and stops at the phone', (
    WidgetTester tester,
  ) async {
    final VoicePriorityController c = await _open(tester);
    await tester.ensureVisible(find.text('Send the packet'));
    await tester.tap(find.text('Send the packet'));
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kVpHopDuration * 2);
    expect(c.hop, 2);
    await tester.pump(kVpHopDuration * 10);
    expect(c.hop, VpHopId.phone.index);
    expect(c.playing, isFalse);
    final OutlinedButton next = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Next hop'),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('copy text names the queue and the illustrative values', (
    WidgetTester tester,
  ) async {
    final VoicePriorityController c = await _open(tester);
    c.loss = MarkLoss.tunnel;
    final String t = c.copyText();
    expect(t, contains('Best effort (AC_BE, UP 0)'));
    expect(t, contains('(marking lost here)'));
    expect(t, contains('(illustrative)'));
  });

  testWidgets('no vendor, product or OS name on screen or in the help', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final List<String> all = <String>[
      ..._screenText(tester),
      ...shippedHelpProse('voice-priority'),
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
      'voice-priority',
    ).firstWhere((String s) => s.startsWith('Defaults (nothing lost'));
    final VpTrip d = VpTrip(const VpConfig());
    final VpTrip isp = VpTrip(const VpConfig(loss: MarkLoss.isp));
    final VpTrip top = VpTrip(const VpConfig(mapping: ApMapping.topThreeBits));
    expect(ex, contains('waits ${vpMs(d.waitUs)}'));
    expect(ex, contains('= ${vpMs(isp.waitUs)}'));
    expect(ex, contains('${(isp.waitUs / d.waitUs).round()} times'));
    expect(ex, contains('waits ${vpMs(top.waitUs)}'));
    expect(
      ex,
      contains(
        '0.398 ms',
      ),
    );
    expect(
      (VpAirTable.bestEffortServiceUs / 1000).toStringAsFixed(3),
      '0.398',
    );
    final Map<AccessCategory, double> off = VpTrip(
      const VpConfig(downloadRunning: false),
    ).waitsByQueue;
    expect(
      ex,
      contains(
        '${vpMs(off[AccessCategory.voice]!).replaceAll(' ms', '')}, '
        '${vpMs(off[AccessCategory.video]!).replaceAll(' ms', '')} and '
        '${vpMs(off[AccessCategory.bestEffort]!)}',
      ),
    );
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double w in <double>[360, 390, 820, 1280]) {
      testWidgets('$name ${w.toInt()} px: no overflow in any loss state', (
        WidgetTester tester,
      ) async {
        final VoicePriorityController c = await _open(
          tester,
          size: Size(w, 6000),
          theme: theme(),
        );
        for (final MarkLoss l in MarkLoss.values) {
          c.loss = l;
          c.framesAhead = 256;
          await tester.pump();
          expect(tester.takeException(), isNull, reason: l.name);
        }
        c.ask();
        await tester.pump();
        expect(tester.takeException(), isNull);
        c.reveal();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
