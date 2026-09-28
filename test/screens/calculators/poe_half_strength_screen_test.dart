// Widget tests for the Wi-Fi Classroom tool "PoE: Why the New AP Runs at
// Half Strength" (poe-half-strength).
//
// The teaching claims are pinned in
// test/services/wifi_lab/poe_half_strength_model_test.dart; these cover the
// screen contract: registration (catalog, route, large-screen gate, help,
// keywords, icon), the help text's guards (acronyms spelled out, Present and
// the keys, the vendor sources in help only, "vendors differ", 802.3af
// illustrative), the port toggle, the 802.3at choice and its disabled state,
// the prediction, the links to PoE Budget and PoE Reference, and the layout
// at 390 x 844 and 1280 wide in both themes.
//
// Catalog neighbors and totals are NOT pinned here (BUILDER-RULES.md).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/poe_half_strength_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<PoeHalfStrengthController> _pump(
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
      home: const PoeHalfStrengthScreen(),
      routes: <String, WidgetBuilder>{
        AppRouter.poeBudget: (_) => const Scaffold(body: Text('BUDGET')),
        AppRouter.poeReference: (_) => const Scaffold(body: Text('REF')),
      },
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<PoeHalfStrengthStage>(find.byType(PoeHalfStrengthStage))
      .controller;
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kPoeHalfStrengthToolId]
        as Map<String, dynamic>;

String _helpText() {
  final Map<String, dynamic> h = _help();
  return <String>[
    h['purpose'] as String,
    h['whyHere'] as String,
    ...(h['howToUse'] as List<dynamic>).cast<String>(),
    ...(h['inputs'] as List<dynamic>).map(jsonEncode),
    h['algorithm'] as String,
    h['example'] as String,
    ...(h['fieldNotes'] as List<dynamic>).cast<String>(),
    h['source'] as String,
  ].join('\n');
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Every Text on screen, joined.
String _screenText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, Network Design and Security, live, '
        'routed, with an icon', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final ToolEntry e = cls.tools.firstWhere(
        (ToolEntry t) => t.id == kPoeHalfStrengthToolId,
      );
      expect(kPoeHalfStrengthToolId, 'poe-half-strength');
      expect(e.title, kPoeHalfStrengthTitle);
      expect(e.subgroup, 'Network Design and Security');
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.poeHalfStrength);
      expect(AppRouter.routes[AppRouter.poeHalfStrength], isNotNull);
      final File icon = File('assets/tool-icons/poe-half-strength.svg');
      expect(icon.existsSync(), isTrue);
      expect(
        icon.readAsStringSync(),
        allOf(contains('viewBox="0 0 24 24"'), contains('currentColor')),
      );
      expect(icon.readAsStringSync(), isNot(contains('#')));
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
      final Widget w = AppRouter.routes[AppRouter.poeHalfStrength]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect((w as LargeScreenGate).toolTitle, kPoeHalfStrengthTitle);
    });

    test('keywords', () {
      expect(
        kToolKeywords[kPoeHalfStrengthToolId],
        containsAll(<String>[
          'poe',
          '802.3at',
          '802.3bt',
          'power over ethernet',
          'wi-fi classroom',
        ]),
      );
    });

    test('help: acronyms spelled out, Present and the keys, both vendor '
        'guides cited, vendors differ, 802.3af illustrative', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wireless Classroom');
      expect(h['name'], kPoeHalfStrengthTitle);
      final String all = _helpText();
      for (final (String acr, String long) in <(String, String)>[
        ('AP', 'access point'),
        ('PoE', 'Power over Ethernet'),
        ('IoT', 'Internet of Things'),
      ]) {
        final int first = RegExp('\\b$acr').firstMatch(all)!.start;
        expect(
          all.substring(first < 40 ? 0 : first - 40, first + 60).toLowerCase(),
          contains(long.toLowerCase()),
          reason: '$acr first used without "$long"',
        );
      }
      for (final String key in <String>['Present', 'Space', 'Esc', 'P']) {
        expect(all, contains(key));
      }
      expect(h['source'], contains('Juniper Mist'));
      expect(h['source'], contains('Cisco Meraki'));
      expect(h['source'], contains('802.3af case is illustrative'));
      expect(all, contains('vendors differ; this is one example'));
      expect(all, isNot(contains('every Wi-Fi radio off')));
      expect(all, contains('Vendors cut different things'));
      expect(all, contains('leaves that out'));
      expect(all, contains('designed for tablets and computers'));
      expect(all, isNot(contains('—')), reason: 'no em dashes');
    });

    testWidgets('no vendor or product name as a device on screen (citations '
        'live in help)', (WidgetTester tester) async {
      final PoeHalfStrengthController k = await _pump(
        tester,
        size: const Size(1280, 900),
      );
      for (final PhPort p in PhPort.values) {
        k.setPort(p);
        k.setRevealed(true);
        await tester.pumpAndSettle();
        final String s = _screenText(tester);
        for (final String name in <String>[
          'Juniper',
          'Mist',
          'Cisco',
          'Meraki',
          'AP47',
        ]) {
          expect(s, isNot(contains(name)), reason: '${p.standard}: $name');
        }
      }
    });
  });

  group('behavior', () {
    testWidgets('default: 802.3at, half strength, the light on', (
      WidgetTester tester,
    ) async {
      final PoeHalfStrengthController k = await _pump(tester);
      expect(k.config.port, PhPort.at);
      expect(find.text('6 of 12'), findsOneWidget);
      expect(find.textContaining('(50%)'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets('the port toggle changes the streams; the 802.3at choice is '
        'disabled off 802.3at, with the reason', (WidgetTester tester) async {
      final PoeHalfStrengthController k = await _pump(tester);
      await _tap(tester, find.text('802.3bt').first);
      expect(k.config.port, PhPort.bt);
      expect(find.text('12 of 12'), findsOneWidget);
      expect(find.textContaining('Applies only on an 802.3at port'), findsOne);
      await _tap(tester, find.text('Two at 4x4'));
      expect(k.config.atMode, PhAtMode.allAt2x2, reason: 'disabled');

      await _tap(tester, find.text('802.3at').first);
      await _tap(tester, find.text('Two at 4x4'));
      expect(k.config.atMode, PhAtMode.twoAt4x4);
      expect(find.text('8 of 12'), findsOneWidget);

      await _tap(tester, find.text('802.3af').first);
      expect(find.text('3 of 12'), findsOneWidget);
      expect(find.text(PhLabels.afIllustrative), findsOneWidget);
      expect(find.textContaining('no Wi-Fi radio'), findsNothing);
      expect(find.textContaining('USB port off'), findsWidgets);
      expect(k.copyText(), contains('USB port off'));
      expect(k.copyText(), contains('this is one example'));
    });

    testWidgets('predict, then reveal', (WidgetTester tester) async {
      final PoeHalfStrengthController k = await _pump(tester);
      k.setPort(PhPort.bt);
      await tester.pumpAndSettle();
      expect(find.text(PoeHalfStrengthPredict.question), findsOneWidget);
      await _tap(tester, find.text('Reveal the answer'));
      expect(
        find.text(PoeHalfStrengthPredict.answer(PhAtMode.allAt2x2)),
        findsOneWidget,
      );
      expect(
        PoeHalfStrengthPredict.answer(PhAtMode.allAt2x2),
        contains('6 of 12'),
      );
      await _tap(tester, find.text('Show it on 802.3at'));
      expect(k.config.port, PhPort.at);
    });

    testWidgets('links open PoE Budget and PoE Reference', (
      WidgetTester tester,
    ) async {
      await _pump(tester, size: const Size(1280, 900));
      await _tap(tester, find.text('Open PoE Budget'));
      expect(find.text('BUDGET'), findsOneWidget);
      Navigator.of(tester.element(find.text('BUDGET'))).pop();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Open PoE Reference'));
      expect(find.text('REF'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size size in const <Size>[Size(390, 844), Size(1280, 900)]) {
        testWidgets('$name ${size.width.toInt()} wide: every port renders '
            'with no overflow', (WidgetTester tester) async {
          final PoeHalfStrengthController k = await _pump(
            tester,
            theme: theme(),
            size: size,
          );
          for (final PhPort p in PhPort.values) {
            for (final PhAtMode m in PhAtMode.values) {
              k
                ..setPort(p)
                ..setAtMode(m)
                ..setRevealed(true);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: p.standard);
            }
          }
        });
      }
    }
  });
}
