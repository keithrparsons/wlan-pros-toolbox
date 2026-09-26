// Widget tests for the Wi-Fi Classroom Uplink vs Downlink screen.
//
// The math is pinned in test/services/wifi_lab/uplink_downlink_model_test.dart;
// these cover the screen contract (spec 28, "Done means"): registration
// (catalog, route, large-screen gate, help, keywords, icon), directions told
// apart by label, arrow and line pattern and not by color alone, the match
// button and its words, the preset disabling the client slider, the
// prediction, the stage/controls split, and the layout at 390 x 844 and 1280
// wide in both themes without overflow or sideways scrolling.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_painter.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<UplinkDownlinkController> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const UplinkDownlinkScreen(),
      routes: <String, WidgetBuilder>{
        AppRouter.linkBudget: (_) => const Scaffold(body: Text('LB')),
      },
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<UplinkDownlinkStage>(find.byType(UplinkDownlinkStage))
      .controller;
}

void _expectNoSidewaysScroll(WidgetTester tester) {
  final Iterable<Scrollable> sideways = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (Scrollable s) =>
            s.axisDirection == AxisDirection.left ||
            s.axisDirection == AxisDirection.right,
      );
  expect(sideways, isEmpty, reason: 'nothing may scroll sideways');
}

void _expectTextInsideWidth(WidgetTester tester, double width) {
  for (final Element e in find.byType(Text).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final Offset tl = ro.localToGlobal(Offset.zero);
    expect(
      tl.dx + ro.size.width,
      lessThanOrEqualTo(width + 0.5),
      reason: 'text "${(e.widget as Text).data}" runs past $width px',
    );
    expect(tl.dx, greaterThanOrEqualTo(-0.5));
  }
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kUplinkDownlinkToolId]
        as Map<String, dynamic>;

UdStagePainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(UplinkDownlinkStage),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((CustomPaint p) => p.painter)
    .whereType<UdStagePainter>()
    .single;

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, RF and Propagation, live, routed', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final ToolEntry e = cls.tools.firstWhere(
        (ToolEntry t) => t.id == kUplinkDownlinkToolId,
      );
      expect(kUplinkDownlinkToolId, 'uplink-downlink');
      expect(e.title, 'Uplink vs Downlink');
      expect(e.subgroup, 'RF and Propagation');
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.uplinkDownlink);
      expect(AppRouter.routes[AppRouter.uplinkDownlink], isNotNull);
      expect(File('assets/tool-icons/uplink-downlink.svg').existsSync(), isTrue);
    });

    testWidgets('the router puts the large-screen notice in front of it', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      );
      final Widget w = AppRouter.routes[AppRouter.uplinkDownlink]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect((w as LargeScreenGate).toolTitle, 'Uplink vs Downlink');
    });

    test('keywords carry spec 28\'s list', () {
      expect(
        kToolKeywords[kUplinkDownlinkToolId],
        containsAll(<String>[
          'uplink',
          'downlink',
          'asymmetric',
          'client power',
          'ap power',
          'link budget',
          '6 ghz client',
          'match power',
        ]),
      );
    });

    test('help: Present and the keys, the Link Budget pointer, and MCS, LPI '
        'and GVP spelled out where they first appear', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wi-Fi Classroom');
      final String all = <String>[
        h['purpose'] as String,
        h['whyHere'] as String,
        ...(h['howToUse'] as List<dynamic>).cast<String>(),
        ...(h['inputs'] as List<dynamic>).map(jsonEncode),
        h['algorithm'] as String,
        h['example'] as String,
        ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
        h['source'] as String,
      ].join('\n');
      expect(all, contains('Present opens'));
      for (final String key in <String>['Up and Down', 'R resets', 'Esc']) {
        expect(all, contains(key));
      }
      expect(all, contains('Link Budget'));
      for (final (String abbr, String expansion) in <(String, String)>[
        ('MCS', 'modulation and coding scheme'),
        ('LPI', 'low power indoor'),
        ('GVP', 'geofenced variable power'),
        ('SNR', 'signal-to-noise ratio'),
        ('EIRP', 'equivalent isotropically radiated power'),
      ]) {
        final int first = all.indexOf(abbr);
        expect(first, greaterThanOrEqualTo(0), reason: abbr);
        final String around = all
            .substring(
              (first - 60).clamp(0, all.length),
              (first + 60).clamp(0, all.length),
            )
            .toLowerCase();
        expect(around, contains(expansion), reason: 'first $abbr: $around');
      }
    });

    test('every direction hue clears 3:1 on the stage in both themes', () {
      for (final AppColorScheme s in <AppColorScheme>[
        AppColorScheme.dark(),
        AppColorScheme.light(),
      ]) {
        for (final UdDir d in UdDir.values) {
          expect(
            _contrast(UdPalette.of(d, s), s.surface2),
            greaterThanOrEqualTo(3),
            reason: '$d light=${s.isLight}',
          );
        }
        expect(
          UdPalette.of(UdDir.downlink, s),
          isNot(UdPalette.of(UdDir.uplink, s)),
        );
      }
    });
  });

  testWidgets('default screen: both directions, imbalance and zone', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Uplink vs Downlink'), findsOneWidget);
    expect(find.text('Downlink, AP to client'), findsOneWidget);
    expect(find.text('Uplink, client to AP'), findsOneWidget);
    expect(find.text('-64.3 dBm'), findsOneWidget);
    expect(find.text('-70.3 dBm'), findsOneWidget);
    expect(find.text('6.0 dB'), findsOneWidget);
    expect(find.text('29 m wide'), findsOneWidget);
    expect(find.text('Radios (illustrative values)'), findsOneWidget);
  });

  testWidgets('directions are told apart by words, arrows and line pattern', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    final UdStagePainter p = _painter(tester);
    expect(p.downLabel, startsWith('Downlink '));
    expect(p.upLabel, startsWith('Uplink '));
    expect(p.downRingLabel, 'Client decodes AP');
    expect(p.upRingLabel, 'AP decodes client');
    expect(p.zoneLabel, 'Only the client decodes');
    expect(find.textContaining('Solid: downlink'), findsOneWidget);
    expect(find.textContaining('Dashed: uplink'), findsOneWidget);
  });

  testWidgets('Turn AP down to match: downlink ring shrinks, uplink stays, '
      'and the words say so', (WidgetTester tester) async {
    final UplinkDownlinkController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    final double ul = k.config.uplink.rssiDbm;
    final double ring = k.config.downlinkRingM;
    await tester.ensureVisible(find.text('Turn AP down to match'));
    await tester.tap(find.text('Turn AP down to match'));
    await tester.pumpAndSettle();
    expect(k.config.apTxDbm, 14);
    expect(k.config.uplink.rssiDbm, closeTo(ul, 1e-9));
    expect(k.config.downlinkRingM, lessThan(ring));
    expect(find.textContaining('What did not change: the uplink'), findsWidgets);
    await tester.ensureVisible(find.text('Put the AP back to 20.0 dBm'));
    await tester.tap(find.text('Put the AP back to 20.0 dBm'));
    await tester.pumpAndSettle();
    expect(k.config.apTxDbm, 20);
  });

  testWidgets('the match button is disabled, with its reason, when the AP '
      'already transmits no more than the client', (tester) async {
    final UplinkDownlinkController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    k
      ..setApTx(10)
      ..setClientTx(18);
    await tester.pumpAndSettle();
    final OutlinedButton b = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Turn AP down to match'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(b.onPressed, isNull);
    expect(
      find.text('The AP already transmits no more than the client.'),
      findsOneWidget,
    );
  });

  testWidgets('a regulatory rule sets the client and disables its slider', (
    WidgetTester tester,
  ) async {
    final UplinkDownlinkController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    k.setPreset(UdPreset.usStandardPower);
    await tester.pumpAndSettle();
    expect(k.config.band, WifiBand.band6);
    expect(
      find.text('Client transmit power (set by the rule)'),
      findsOneWidget,
    );
    final Iterable<Slider> disabled = tester
        .widgetList<Slider>(find.byType(Slider))
        .where((Slider s) => s.onChanged == null);
    expect(disabled, hasLength(1));
    expect(find.textContaining('6 dB below its AP'), findsOneWidget);
    expect(find.textContaining('AP authorized power'), findsOneWidget);
  });

  testWidgets('predict, then reveal', (WidgetTester tester) async {
    final UplinkDownlinkController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    expect(
      find.text('The client shows four bars. Can the AP hear it?'),
      findsOneWidget,
    );
    expect(find.textContaining('Not necessarily'), findsNothing);
    await tester.ensureVisible(find.text('Reveal the answer'));
    await tester.tap(find.text('Reveal the answer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not necessarily'), findsOneWidget);
    await tester.ensureVisible(find.text('Put the client in the zone'));
    await tester.tap(find.text('Put the client in the zone'));
    await tester.pumpAndSettle();
    expect(k.config.clientInZone, isTrue);
    expect(k.config.uplink.mcs, isNull);
    expect(k.config.downlink.mcs, isNotNull);
    expect(find.textContaining('below MCS 0, so it cannot decode'), findsOne);
  });

  testWidgets('dragging on the floor moves the client', (
    WidgetTester tester,
  ) async {
    final UplinkDownlinkController k = await _pump(
      tester,
      size: const Size(1280, 900),
    );
    final Rect r = tester.getRect(
      find
          .descendant(
            of: find.byType(UplinkDownlinkStage),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await tester.tapAt(r.center + const Offset(2, 0));
    await tester.pumpAndSettle();
    expect(k.config.clientDistanceM, lessThan(5));
    await tester.dragFrom(
      r.center + const Offset(2, 0),
      Offset(0, r.height / 2 - 10),
    );
    await tester.pumpAndSettle();
    expect(k.config.clientDistanceM, greaterThan(50));
  });

  testWidgets('the explainer opens Link Budget', (WidgetTester tester) async {
    await _pump(tester, size: const Size(1280, 900));
    await tester.ensureVisible(find.text('Open Link Budget'));
    await tester.tap(find.text('Open Link Budget'));
    await tester.pumpAndSettle();
    expect(find.text('LB'), findsOneWidget);
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(UplinkDownlinkStage), findsOneWidget);
    expect(find.byType(UplinkDownlinkControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UplinkDownlinkStage),
        matching: find.byType(UplinkDownlinkControls),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(UplinkDownlinkControls),
        matching: find.byType(UplinkDownlinkStage),
      ),
      findsNothing,
    );
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1280, 900),
    ]) {
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly', (
        WidgetTester tester,
      ) async {
        final UplinkDownlinkController k = await _pump(
          tester,
          theme: theme(),
          size: size,
        );
        // Longest content: a long preset, 320 MHz, a match summary, the
        // answer revealed, the client at the edge and then at the AP.
        k
          ..setPreset(UdPreset.usGvp)
          ..setWidth(320)
          ..setApGain(0)
          ..setApTx(18)
          ..matchApToClient()
          ..setRevealed(true);
        for (final double d in <double>[1, 5000]) {
          k.setClientDistance(d);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          _expectNoSidewaysScroll(tester);
          _expectTextInsideWidth(tester, size.width);
        }
      });
    }
  }
}
