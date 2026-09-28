// Widget tests for the Wi-Fi Classroom tool Why Two Devices Disagree
// (devices-disagree).
//
// The model is pinned in test/services/wifi_lab/devices_disagree_model_test
// .dart; these tests cover the screen contract: registration, the default
// readouts, predict then reveal, Apply offsets, the device picker, the
// stage/controls split, the illustrative labels, the no-vendor rule, and the
// layout at phone and desktop widths in both themes with no overflow.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/devices_disagree_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<DevicesDisagreeController> _pump(
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
      home: const DevicesDisagreeScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<DevicesDisagreeStage>(find.byType(DevicesDisagreeStage))
      .controller;
}

/// The source files whose strings reach the user.
const List<String> _sources = <String>[
  'lib/services/wifi_lab/devices_disagree_model.dart',
  'lib/screens/tools/calculators/devices_disagree_controller.dart',
  'lib/screens/tools/calculators/devices_disagree_controls.dart',
  'lib/screens/tools/calculators/devices_disagree_painters.dart',
  'lib/screens/tools/calculators/devices_disagree_parts.dart',
  'lib/screens/tools/calculators/devices_disagree_screen.dart',
  'lib/screens/tools/calculators/devices_disagree_stage.dart',
];

/// Vendor, chipset, operating system and product names that must never
/// appear in this tool's user-facing text. Matched as whole words, case
/// sensitive, so ordinary words ("surface" as a color token) do not trip it.
const List<String> _banned = <String>[
  'Apple',
  'iPhone',
  'iPad',
  'MacBook',
  'Mac',
  'macOS',
  'iOS',
  'Android',
  'Samsung',
  'Galaxy',
  'Google',
  'Pixel',
  'Microsoft',
  'Windows',
  'Surface',
  'Dell',
  'Lenovo',
  'HP',
  'Asus',
  'Acer',
  'Intel',
  'Broadcom',
  'Qualcomm',
  'MediaTek',
  'Realtek',
  'Cisco',
  'Aruba',
  'Juniper',
  'Mist',
  'Ubiquiti',
  'UniFi',
  'Ruckus',
  'Extreme',
  'Meraki',
  'Ekahau',
  'TamoGraph',
  'Tamosoft',
  'Hamina',
  'NetAlly',
  'AirMagnet',
  'NetSpot',
  'Fluke',
  'Metageek',
  'Chromebook',
  'Linux',
  'Netgear',
  'TP-Link',
  'Alfa',
  'Panda',
  'Comfast',
  'Edimax',
];

/// Every string literal in [src] (single or double quoted, one line), with
/// whole-line comments removed first.
Iterable<String> _literals(String src) sync* {
  final String code = src
      .split('\n')
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  for (final RegExp re in <RegExp>[
    RegExp(r"'((?:[^'\\\n]|\\.)*)'"),
    RegExp(r'"((?:[^"\\\n]|\\.)*)"'),
  ]) {
    for (final RegExpMatch m in re.allMatches(code)) {
      yield m.group(1)!;
    }
  }
}

List<String> _vendorHits(String text) => <String>[
  for (final String b in _banned)
    if (RegExp('(^|[^A-Za-z])${RegExp.escape(b)}(\$|[^A-Za-z])').hasMatch(text))
      b,
];

void main() {
  setUp(resetLargeScreenNoticeForTest);

  group('registration', () {
    test('catalog: Wi-Fi Classroom, RF and Propagation, after Multipath', () {
      final ToolCategory c = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == 'wifi-classroom',
      );
      final List<String> ids = c.tools.map((ToolEntry t) => t.id).toList();
      final int i = ids.indexOf(kDevicesDisagreeToolId);
      expect(i, greaterThan(0));
      expect(ids[i - 1], 'multipath-simulator');
      final ToolEntry t = c.tools[i];
      expect(t.title, kDevicesDisagreeTitle);
      expect(t.subgroup, 'RF and Propagation');
      expect(t.routeName, AppRouter.devicesDisagree);
      expect(t.isLive, isTrue);
    });

    test('route is registered and gated as a Classroom simulator', () {
      expect(AppRouter.routes.containsKey(AppRouter.devicesDisagree), isTrue);
      expect(
        wifiLabTools().map((ToolEntry t) => t.id),
        contains(kDevicesDisagreeToolId),
      );
    });

    test('icon exists', () {
      expect(
        File('assets/tool-icons/$kDevicesDisagreeToolId.svg').existsSync(),
        isTrue,
      );
    });

    test('keywords carry the spec terms', () {
      final List<String> k = kToolKeywords[kDevicesDisagreeToolId]!;
      for (final String w in <String>[
        'rssi',
        'rcpi',
        'signal strength',
        'offset',
        'calibration',
        'adapter offset',
        'different readings',
        'survey adapter',
      ]) {
        expect(k, contains(w));
      }
    });

    test('help: spells out RSSI and RCPI at first use, says offsets are '
        'illustrative, names Present and the keys', () {
      final Map<String, dynamic> help =
          (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                  as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      final Map<String, dynamic> e =
          help[kDevicesDisagreeToolId] as Map<String, dynamic>;
      final String all = <String>[
        e['purpose'] as String,
        e['whyHere'] as String,
        ...(e['howToUse'] as List<dynamic>).cast<String>(),
        e['algorithm'] as String,
        e['example'] as String,
        ...(e['fieldNotes'] as List<dynamic>).cast<String>(),
        e['source'] as String,
      ].join('\n');
      expect(e['category'], 'Wireless Classroom');
      int first(String s) => all.indexOf(s);
      expect(first('RSSI (received signal strength indicator)'), first('RSSI'));
      expect(first('RCPI (received channel power indicator)'), first('RCPI'));
      expect(
        first('effective isotropic radiated power (EIRP)'),
        lessThan(first('EIRP')),
      );
      expect(all, contains('illustrative'));
      expect(all, contains('Present'));
      expect(all, contains('Space re-samples'));
      expect(all, contains('R resets'));
    });
  });

  group('no vendor or product is named', () {
    test('in the source strings', () {
      for (final String path in _sources) {
        for (final String lit in _literals(File(path).readAsStringSync())) {
          expect(_vendorHits(lit), isEmpty, reason: '$path: "$lit"');
        }
      }
    });

    test('in the help entry, catalog entry and keywords', () {
      final Map<String, dynamic> help =
          (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                  as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      expect(_vendorHits(jsonEncode(help[kDevicesDisagreeToolId])), isEmpty);
      final ToolEntry t = kToolCategories
          .expand((ToolCategory c) => c.tools)
          .firstWhere((ToolEntry t) => t.id == kDevicesDisagreeToolId);
      expect(_vendorHits('${t.title} ${t.description}'), isEmpty);
      expect(
        _vendorHits(kToolKeywords[kDevicesDisagreeToolId]!.join(' ')),
        isEmpty,
      );
    });

    testWidgets('on screen', (WidgetTester tester) async {
      await _pump(tester, size: const Size(1280, 900));
      for (final Element e in find.byType(Text).evaluate()) {
        final Text t = e.widget as Text;
        final String s = t.data ?? t.textSpan?.toPlainText() ?? '';
        expect(_vendorHits(s), isEmpty, reason: s);
      }
    });

    test('the scanner itself catches a vendor name', () {
      expect(_vendorHits('Laptop from Apple'), <String>['Apple']);
      expect(_vendorHits('colors.surface1'), isEmpty);
    });
  });

  group('screen', () {
    testWidgets('default: four devices, true power, spreads, illustrative '
        'note', (WidgetTester tester) async {
      final DevicesDisagreeController c = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      Finder onStage(String s) => find.descendant(
        of: find.byType(DevicesDisagreeStage),
        matching: find.text(s),
      );
      for (final String kind in <String>[
        'Laptop',
        'Phone',
        'Tablet',
        'Survey adapter',
      ]) {
        expect(onStage(kind), findsOneWidget);
      }
      expect(find.text('True power'), findsOneWidget);
      expect(find.text(DdFormat.dbmPrecise(c.result.trueDbm)), findsOneWidget);
      expect(c.result.trueDbm, closeTo(-60.35, 0.01));
      expect(find.text('Spread now'), findsOneWidget);
      expect(find.text('After offsets'), findsOneWidget);
      expect(find.text(kDdIllustrativeNote), findsOneWidget);
      expect(find.textContaining('(illustrative)'), findsWidgets);
      expect(find.text('Present'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('predict, then reveal', (WidgetTester tester) async {
      final DevicesDisagreeController c = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      expect(find.text(kDdPredictPrompt), findsOneWidget);
      expect(find.textContaining('Neither one'), findsNothing);
      await tester.tap(find.text('Reveal'));
      await tester.pumpAndSettle();
      expect(c.revealed, isTrue);
      expect(find.textContaining('Neither one'), findsOneWidget);
      expect(find.text('Reveal'), findsNothing);
      c.reset();
      await tester.pumpAndSettle();
      expect(find.text('Reveal'), findsOneWidget);
    });

    testWidgets('Apply offsets changes what the cards show', (
      WidgetTester tester,
    ) async {
      final DevicesDisagreeController c = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      c.fadingOn = false;
      await tester.pumpAndSettle();
      final DeviceTrace phone = c.result.traces[1];
      expect(find.text(DdFormat.dbm(phone.latest)), findsWidgets);
      await tester.tap(find.text('Apply offsets'));
      await tester.pumpAndSettle();
      expect(c.applyOffsets, isTrue);
      expect(c.shownNow(1), phone.latest + 4);
      expect(find.text('offset -4 dB removed'), findsOneWidget);
    });

    testWidgets('the device picker edits the picked device only', (
      WidgetTester tester,
    ) async {
      final DevicesDisagreeController c = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      await tester.tap(find.text('Device C'));
      await tester.pumpAndSettle();
      expect(c.selected, 2);
      expect(find.text('Device C offset (illustrative)'), findsOneWidget);
      c.editDevice((DeviceSettings d) => d.copyWith(offsetDb: 7));
      await tester.pumpAndSettle();
      expect(c.config.devices[2].offsetDb, 7);
      expect(c.config.devices[0].offsetDb, 0);
      expect(find.text('+7 dB'), findsWidgets);
    });

    testWidgets('fewer devices: cards and picker follow', (
      WidgetTester tester,
    ) async {
      final DevicesDisagreeController c = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      c.selectDevice(3);
      c.deviceCount = 2;
      await tester.pumpAndSettle();
      expect(c.selected, 1);
      expect(
        find.descendant(
          of: find.byType(DevicesDisagreeStage),
          matching: find.text('Tablet'),
        ),
        findsNothing,
      );
      expect(find.text('Device C'), findsNothing);
      expect(c.result.traces, hasLength(2));
    });

    testWidgets('Re-sample takes a new sample set; Reset restores it', (
      WidgetTester tester,
    ) async {
      final DevicesDisagreeController c = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      final List<double> before = c.result.traces.first.reportedDbm;
      await tester.tap(find.text('Re-sample'));
      await tester.pumpAndSettle();
      expect(c.sampleSet, 2);
      expect(find.text('Sample set 2'), findsOneWidget);
      expect(c.result.traces.first.reportedDbm, isNot(before));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(c.sampleSet, 1);
      expect(c.result.traces.first.reportedDbm, before);
    });

    testWidgets('stage and controls are separate widgets', (
      WidgetTester tester,
    ) async {
      await _pump(tester, size: const Size(1280, 900));
      expect(find.byType(DevicesDisagreeStage), findsOneWidget);
      expect(find.byType(DevicesDisagreeControls), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DevicesDisagreeStage),
          matching: find.byType(DevicesDisagreeControls),
        ),
        findsNothing,
      );
    });

    testWidgets('copy text names every device generically', (
      WidgetTester tester,
    ) async {
      final DevicesDisagreeController c = await _pump(tester);
      final String text = c.copyText();
      expect(text, contains('Device A (laptop)'));
      expect(text, contains('Device D (survey adapter)'));
      expect(text, contains('illustrative'));
      expect(_vendorHits(text), isEmpty);
    });
  });

  group('layout', () {
    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size size in const <Size>[
        Size(390, 844),
        Size(768, 1024),
        Size(1280, 800),
      ]) {
        testWidgets('$name ${size.width.toInt()}x${size.height.toInt()}: no '
            'overflow, reveal and offsets on', (WidgetTester tester) async {
          final DevicesDisagreeController c = await _pump(
            tester,
            theme: theme(),
            size: size,
          );
          c
            ..reveal()
            ..applyOffsets = true;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          c.deviceCount = 2;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
