// Widget tests for the Wi-Fi Classroom tool "Why a Long Wi-Fi Password
// Matters More on WPA2" (wpa2-password).
//
// The teaching claims are pinned in
// test/services/wifi_lab/wpa2_password_model_test.dart; these cover the
// screen contract: registration (catalog, route, large-screen gate, help,
// keywords, icon), the help text's guards (acronyms spelled out, Present and
// the keys, no crack times, no tool names), the security switch and the AP's
// count, the guess buttons, the prediction, the links into Association,
// Frame by Frame, and the layout at 390 x 844 and 1280 wide in both themes.
//
// Catalog neighbors and totals are NOT pinned here (BUILDER-RULES.md): the
// merge script owns the shared counts.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wpa2_password_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wpa2_password_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wpa2_password_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';

Future<Wpa2PasswordController> _pump(
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
      home: const Wpa2PasswordScreen(),
      routes: <String, WidgetBuilder>{
        AppRouter.wpaSecurity: (_) => const Scaffold(body: Text('WPA-SEC')),
      },
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<Wpa2PasswordStage>(find.byType(Wpa2PasswordStage))
      .controller;
}

Map<String, dynamic> _help() =>
    ((jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>)[kWpa2PasswordToolId]
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

void _expectNoSidewaysScroll(WidgetTester tester) {
  final Iterable<Scrollable> sideways = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (Scrollable s) =>
            s.axisDirection == AxisDirection.left ||
            s.axisDirection == AxisDirection.right,
      );
  expect(sideways, isEmpty);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('registration', () {
    test('catalog: Wi-Fi Classroom, Network Design and Security, live, '
        'routed, with an icon', () {
      final ToolCategory cls = kToolCategories.firstWhere(
        (ToolCategory c) => c.id == kWifiClassroomCategoryId,
      );
      final ToolEntry e = cls.tools.firstWhere(
        (ToolEntry t) => t.id == kWpa2PasswordToolId,
      );
      expect(kWpa2PasswordToolId, 'wpa2-password');
      expect(e.title, kWpa2PasswordTitle);
      expect(e.subgroup, 'Network Design and Security');
      expect(kWifiClassroomSimulatorSubgroups, contains(e.subgroup));
      expect(e.isLive, isTrue);
      expect(e.routeName, AppRouter.wpa2Password);
      expect(AppRouter.routes[AppRouter.wpa2Password], isNotNull);
      final File icon = File('assets/tool-icons/wpa2-password.svg');
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
      final Widget w = AppRouter.routes[AppRouter.wpa2Password]!(ctx);
      expect(w, isA<LargeScreenGate>());
      expect((w as LargeScreenGate).toolTitle, kWpa2PasswordTitle);
    });

    test('keywords', () {
      expect(
        kToolKeywords[kWpa2PasswordToolId],
        containsAll(<String>[
          'password',
          'wpa2',
          'wpa3',
          'sae',
          'transition mode',
          'wi-fi classroom',
        ]),
      );
    });

    test('help: acronyms spelled out at first use, Present and the keys, '
        'the WFA source, what it leaves out', () {
      final Map<String, dynamic> h = _help();
      expect(h['category'], 'Wireless Classroom');
      expect(h['name'], kWpa2PasswordTitle);
      final String all = _helpText();
      for (final (String acr, String long) in <(String, String)>[
        ('WPA', 'Wi-Fi Protected Access'),
        ('PSK', 'pre-shared key'),
        ('SAE', 'Simultaneous Authentication of Equals'),
        ('AP', 'access point'),
        ('SSID', 'service set identifier'),
      ]) {
        final int first = RegExp('\\b$acr').firstMatch(all)!.start;
        // Spelled out right before or right after its first use.
        expect(
          all.substring(first < 40 ? 0 : first - 40, first + 60).toLowerCase(),
          contains(long.toLowerCase()),
          reason: '$acr first used without "$long"',
        );
      }
      expect(all, contains('Present'));
      for (final String key in <String>['Space', 'Right arrow', 'Esc', 'P']) {
        expect(all, contains(key));
      }
      expect(
        h['source'],
        contains('Wi-Fi Alliance, WPA3 Security Considerations, November 2019'),
      );
      expect(all, contains('leaves out'));
      expect(all, contains('designed for tablets and computers'));
      expect(all, isNot(contains('—')), reason: 'no em dashes');
    });

    test('help and screen strings: no crack times and no attack tools or '
        'commands', () {
      final String all = _helpText().toLowerCase();
      for (final RegExp bad in <RegExp>[
        RegExp(r'\b\d+(\.\d+)?\s*(seconds?|minutes?|hours?|days?|years?)\b'),
        RegExp(r'guesses per second|per second'),
        RegExp(r'hashcat|aircrack|hcx|john the ripper|wireshark|deauth'),
        RegExp(r'\bsudo\b|\$ '),
      ]) {
        expect(bad.hasMatch(all), isFalse, reason: bad.pattern);
      }
    });
  });

  group('behavior', () {
    testWidgets('defaults: WPA2, 8 lowercase letters, nothing tried', (
      WidgetTester tester,
    ) async {
      final Wpa2PasswordController k = await _pump(tester);
      expect(k.config.security, WpSecurity.wpa2);
      expect(k.config.length, 8);
      expect(find.text('208,827,064,576'), findsOneWidget);
      expect(find.text("On the attacker's own computer"), findsOneWidget);
      expect(find.text("Only the attacker's computer"), findsOneWidget);
      expect(k.guesses, 0);
      expect(k.apFailedAttempts, 0);
    });

    testWidgets('one guess on WPA2 leaves the AP count at 0; on WPA3 the AP '
        'logs it; switching starts the count over', (
      WidgetTester tester,
    ) async {
      final Wpa2PasswordController k = await _pump(tester);
      await _tap(tester, find.text('Try one guess'));
      expect(k.guesses, 1);
      expect(k.apFailedAttempts, 0);

      await _tap(tester, find.text('WPA3'));
      expect(k.config.security, WpSecurity.wpa3);
      expect(k.guesses, 0, reason: 'a new setting is a new network');
      expect(find.text('Only at your AP, in a live exchange'), findsOneWidget);
      await _tap(tester, find.text('Try one guess'));
      await _tap(tester, find.text('Try one guess'));
      expect(k.guesses, 2);
      expect(k.apFailedAttempts, 2);

      await _tap(tester, find.text('Transition'));
      expect(k.config.security, WpSecurity.transition);
      await _tap(tester, find.text('Try one guess'));
      expect(k.apFailedAttempts, 0);
      expect(find.text("On the attacker's own computer"), findsOneWidget);
    });

    testWidgets('Keep guessing counts up by itself and stops', (
      WidgetTester tester,
    ) async {
      final Wpa2PasswordController k = await _pump(tester);
      await tester.ensureVisible(find.text('Keep guessing'));
      await tester.tap(find.text('Keep guessing'));
      await tester.pump();
      expect(k.playing, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(kWpOfflineGuessDrawn * 3);
      expect(k.guesses, greaterThanOrEqualTo(3));
      await tester.tap(find.text('Stop guessing'));
      await tester.pumpAndSettle();
      expect(k.playing, isFalse);
      final int g = k.guesses;
      await tester.pump(const Duration(seconds: 3));
      expect(k.guesses, g);
    });

    testWidgets('length and characters change the count, not the security', (
      WidgetTester tester,
    ) async {
      final Wpa2PasswordController k = await _pump(tester);
      k.setLength(12);
      await tester.pumpAndSettle();
      expect(find.text('95,428,956,661,682,176'), findsOneWidget);
      k.setCharset(WpCharset.printable);
      k.setLength(8);
      await tester.pumpAndSettle();
      expect(find.text('6,634,204,312,890,625'), findsOneWidget);
      expect(k.config.security, WpSecurity.wpa2);
    });

    testWidgets('predict, then reveal: the WFA example', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      expect(find.text(Wpa2PasswordPredict.question), findsOneWidget);
      expect(find.textContaining('WPA2: all 5,000'), findsNothing);
      await _tap(tester, find.text('Reveal the answer'));
      expect(find.textContaining('WPA2: all 5,000'), findsOneWidget);
      expect(find.textContaining('the chance is 50%'), findsOneWidget);
      expect(find.text(Wpa2PasswordPredict.credit), findsOneWidget);
    });

    testWidgets('the links open Association, Frame by Frame on the WPA2 and '
        'the WPA3 frames', (WidgetTester tester) async {
      await _pump(tester, size: const Size(1280, 900));
      await _tap(tester, find.text('The WPA3 SAE exchange'));
      final JoinLadderScreen sae = tester.widget<JoinLadderScreen>(
        find.byType(JoinLadderScreen),
      );
      expect(sae.initial?.security, JrSecurity.sae);
      Navigator.of(tester.element(find.byType(JoinLadderScreen))).pop();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('The WPA2 4-way handshake'));
      expect(
        tester
            .widget<JoinLadderScreen>(find.byType(JoinLadderScreen))
            .initial
            ?.security,
        JrSecurity.psk,
      );
      Navigator.of(tester.element(find.byType(JoinLadderScreen))).pop();
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Open WPA Security'));
      expect(find.text('WPA-SEC'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size size in const <Size>[Size(390, 844), Size(1280, 900)]) {
        testWidgets('$name ${size.width.toInt()} wide: every setting renders '
            'with no overflow and no sideways scroll', (
          WidgetTester tester,
        ) async {
          final Wpa2PasswordController k = await _pump(
            tester,
            theme: theme(),
            size: size,
          );
          for (final WpSecurity s in WpSecurity.values) {
            k
              ..setSecurity(s)
              ..setLength(63)
              ..setCharset(WpCharset.printable)
              ..setRevealed(true);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: s.label);
            _expectNoSidewaysScroll(tester);
          }
          expect(find.text('about 3.9 x 10^124'), findsOneWidget);
        });
      }
    }
  });
}
