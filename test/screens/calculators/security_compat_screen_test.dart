// Widget and presenter tests for Why won't it associate? (spec 43), the
// security-compatibility mode of Association, Frame by Frame (join-ladder),
// and the shared failure marker (spec 42) as the Join ladder draws it.
//
// The verdicts are pinned in test/services/wifi_lab/security_compat_model_
// test.dart; these cover the screen contract: the mode select, the verdict
// band, the Client and Network cards, "associate" and never "join" in this
// mode, the X, the lost arrow and the Stopped band on the Join ladder, phone
// and desktop widths in both themes, and the presenter layout with C and
// Up/Down.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_failure.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/security_compat_controls.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/security_compat_model.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1280,
  double height = 900,
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
        child: const JoinLadderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EapLadderController _controller(WidgetTester tester) =>
    tester.widget<JoinRoamStage>(find.byType(JoinRoamStage).first).controller;

/// Sets up one pair and shows the whole ladder.
void _why(
  EapLadderController c, {
  required ScClientPreset client,
  required ScNetSecurity net,
  JrBand band = JrBand.g5,
  JrPmf pmf = JrPmf.optional,
  bool wifi7 = false,
}) {
  c.whyMode = true;
  c.jrConfig = c.jrConfig.copyWith(band: band, pmf: pmf);
  c.scPreset = client;
  c.scNetSecurity = net;
  c.apWifi7 = wifi7;
  c.showAll();
}

/// Every string drawn on screen.
List<String> _texts(WidgetTester tester) => <String>[
  for (final Text t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
  for (final RichText t in tester.widgetList<RichText>(find.byType(RichText)))
    t.text.toPlainText(),
];

/// The pairs that reach every outcome.
const List<(ScClientPreset, ScNetSecurity, JrBand, JrPmf, bool)> _cases =
    <(ScClientPreset, ScNetSecurity, JrBand, JrPmf, bool)>[
      (
        ScClientPreset.olderLaptop,
        ScNetSecurity.wpa3Personal,
        JrBand.g5,
        JrPmf.optional,
        false,
      ),
      (
        ScClientPreset.printer,
        ScNetSecurity.wpa2Personal,
        JrBand.g24,
        JrPmf.required,
        false,
      ),
      (
        ScClientPreset.newLaptop,
        ScNetSecurity.wpa2Personal,
        JrBand.g6,
        JrPmf.optional,
        false,
      ),
      (
        ScClientPreset.phoneWpa3,
        ScNetSecurity.wpa3Personal,
        JrBand.g6,
        JrPmf.optional,
        false,
      ),
      (
        ScClientPreset.phoneWifi7,
        ScNetSecurity.wpa3Personal,
        JrBand.g5,
        JrPmf.optional,
        true,
      ),
      (
        ScClientPreset.phoneWifi7,
        ScNetSecurity.wpa2Enterprise,
        JrBand.g5,
        JrPmf.optional,
        true,
      ),
    ];

void main() {
  group('screen', () {
    testWidgets('the mode select starts on Play the association, and the '
        'ordinary Join is on show', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byKey(AssociationModeSelect.selectKey), findsOneWidget);
      expect(find.text(kPlayAssociationLabel), findsOneWidget);
      final EapLadderController c = _controller(tester);
      expect(c.whyMode, isFalse);
      expect(c.verdict, isNull);
      expect(find.byKey(ScVerdictBand.bandKey), findsNothing);
      expect(find.byType(ScClientCard), findsNothing);
      // The existing mode keeps its PMF control; its title says associate
      // too (Keith, 2026-09-29).
      expect(
        find.textContaining('Association: WPA2-Personal (PSK).'),
        findsOneWidget,
      );
    });

    testWidgets('choosing Why won\'t it associate? from the select', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byKey(AssociationModeSelect.selectKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kWhyWontItAssociateLabel).last);
      await tester.pumpAndSettle();
      final EapLadderController c = _controller(tester);
      expect(c.whyMode, isTrue);
      expect(find.byKey(ScVerdictBand.bandKey), findsOneWidget);
      expect(find.byType(ScClientCard), findsOneWidget);
      expect(find.byType(ScNetworkCard), findsOneWidget);
      // The default pair: an older WPA2 laptop and a WPA3-only network.
      expect(
        find.text('Never tries to associate: no key management in common'),
        findsOneWidget,
      );
      expect(c.shown, 0);
    });

    testWidgets('associate, never join, on every outcome', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 4000);
      final EapLadderController c = _controller(tester);
      for (final (
            ScClientPreset p,
            ScNetSecurity n,
            JrBand b,
            JrPmf pmf,
            bool w,
          )
          in _cases) {
        _why(c, client: p, net: n, band: b, pmf: pmf, wifi7: w);
        await tester.pumpAndSettle();
        final List<String> joins = <String>[
          for (final String t in _texts(tester))
            if (t.toLowerCase().contains('join')) t,
        ];
        expect(joins, isEmpty, reason: '${p.name} ${n.name}');
      }
    });

    // Keith, 2026-09-29: "associate", not "join", everywhere on screen in
    // this tool, the ordinary Play the association mode included. Route ids
    // and code identifiers (join-ladder, JrConfig) are not on screen.
    testWidgets('associate, never join, anywhere in the tool: Play the '
        'association in every band, scan and security, not found, each '
        'message inspected, the copy text and the help entry', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 4000);
      final EapLadderController c = _controller(tester);
      expect(c.whyMode, isFalse);
      final List<JrConfig> configs = <JrConfig>[
        for (final JrBand b in JrBand.values)
          for (final JrScanType t in JrScanType.values)
            for (final JrSecurity sec in JrSecurity.values)
              JrConfig(band: b, scanType: t, security: sec),
        // Too short a passive dwell: the scan misses the beacon.
        const JrConfig(scanType: JrScanType.passive, passiveDwellMs: 40),
      ];
      List<String> joins(Iterable<String> texts) => <String>[
        for (final String t in texts)
          if (t.toLowerCase().contains('join')) t,
      ];
      List<String> semantics() => <String>[
        for (final Semantics w in tester.widgetList<Semantics>(
          find.byType(Semantics),
        ))
          w.properties.label ?? '',
      ];
      for (final JrConfig cfg in configs) {
        c.jrConfig = cfg;
        c.reset();
        c.step();
        await tester.pumpAndSettle();
        final String name =
            '${cfg.band.name} ${cfg.scanType.name} ${cfg.security.name}';
        expect(joins(_texts(tester)), isEmpty, reason: '$name, first step');
        c.showAll();
        await tester.pumpAndSettle();
        expect(joins(_texts(tester)), isEmpty, reason: name);
        expect(joins(semantics()), isEmpty, reason: '$name semantics');
        expect(joins(<String>[c.copyText()]), isEmpty, reason: '$name copy');
        for (int i = 0; i < c.jr.length; i++) {
          c.inspect(i);
          await tester.pump();
          expect(joins(_texts(tester)), isEmpty, reason: '$name inspect $i');
        }
      }
      // The not-found case really reached the not-found line.
      expect(find.text('Not found: the association stops here.'), findsOne);

      final Map<String, dynamic> help =
          (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                  as Map<String, dynamic>)['tools']['join-ladder']
              as Map<String, dynamic>;
      final List<String> helpStrings = <String>[];
      void walk(Object? o) {
        if (o is String) helpStrings.add(o);
        if (o is List) o.forEach(walk);
        if (o is Map) o.values.forEach(walk);
      }

      walk(help);
      // "Join a Network" is the name of a different tool, the one that
      // really connects this device; naming it is not this tool saying join.
      expect(
        joins(helpStrings.map((String t) => t.replaceAll('Join a Network', ''))),
        isEmpty,
      );
    });

    testWidgets('refused: X on the Association Response, the Stopped band held '
        'back until the end, and the help desk line', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 4000);
      final EapLadderController c = _controller(tester);
      _why(
        c,
        client: ScClientPreset.printer,
        net: ScNetSecurity.wpa2Personal,
        pmf: JrPmf.required,
      );
      c.reset();
      await tester.pumpAndSettle();
      // Held back (space kept, not announced) before the end.
      expect(find.bySemanticsLabel(RegExp('^Stopped here')), findsNothing);
      c.showAll();
      await tester.pumpAndSettle();
      expect(find.byKey(LadderStoppedBand.bandKey), findsOneWidget);
      expect(find.byType(LadderFailureMark), findsOneWidget);
      expect(find.byType(LadderLostMark), findsNothing);
      expect(
        find.text('Refused: status 31 at the Association Response'),
        findsOneWidget,
      );
      expect(find.textContaining('What the help desk sees'), findsOneWidget);
      expect(find.text('This is where it fails.'), findsOneWidget);
      // The status hue is on the X only, never on the ladder's text.
      final AppColorScheme colors = AppColorScheme.dark();
      final Icon x = tester.widget<Icon>(
        find.descendant(
          of: find.byType(LadderFailureMark),
          matching: find.byType(Icon),
        ),
      );
      expect(x.color, colors.statusDanger);
      // The row says it in words for a screen reader.
      expect(
        find.bySemanticsLabel(RegExp('failed here.*Association Response')),
        findsOneWidget,
      );
    });

    testWidgets('not offered in 6 GHz: a lost probe with the clock, no channel '
        'strip, no swap to SAE', (WidgetTester tester) async {
      await _pump(tester, height: 3000);
      final EapLadderController c = _controller(tester);
      _why(
        c,
        client: ScClientPreset.newLaptop,
        net: ScNetSecurity.wpa2Personal,
        band: JrBand.g6,
      );
      await tester.pumpAndSettle();
      expect(find.byType(LadderLostMark), findsOneWidget);
      expect(find.byKey(JoinRoamStage.stripKey), findsNothing);
      expect(find.byKey(LadderStoppedBand.bandKey), findsOneWidget);
      expect(
        find.text('Not offered: 6 GHz does not allow WPA2-Personal'),
        findsOneWidget,
      );
      expect(find.textContaining('SAE Commit'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('no answer.*Probe Request')),
        findsOneWidget,
      );
    });

    testWidgets('no 6 GHz radio: the beacon is never heard', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 3000);
      final EapLadderController c = _controller(tester);
      _why(
        c,
        client: ScClientPreset.phoneWpa3,
        net: ScNetSecurity.wpa3Personal,
        band: JrBand.g6,
      );
      await tester.pumpAndSettle();
      expect(find.text('Beacon (never heard)'), findsWidgets);
      expect(find.byType(LadderFailureMark), findsOneWidget);
      expect(
        find.text('Never heard: the client never starts to associate.'),
        findsOneWidget,
      );
      // No time to draw: no timeline.
      expect(find.byKey(JoinRoamStage.timelineKey), findsNothing);
    });

    testWidgets('a Wi-Fi 7 connection associates to the end with no marker', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 4000);
      final EapLadderController c = _controller(tester);
      _why(
        c,
        client: ScClientPreset.phoneWifi7,
        net: ScNetSecurity.wpa3Personal,
        wifi7: true,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Associates: a Wi-Fi 7 connection with SAE (24), GCMP-256, PMF on',
        ),
        findsOneWidget,
      );
      expect(find.byType(LadderFailureMark), findsNothing);
      expect(find.byKey(LadderStoppedBand.bandKey), findsNothing);
    });

    testWidgets('editing a capability makes the client Custom', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 4000);
      final EapLadderController c = _controller(tester);
      c.whyMode = true;
      await tester.pumpAndSettle();
      final Finder fold = find.text(
        'Client capabilities (AKM, ciphers, PMF, bands)',
      );
      await tester.ensureVisible(fold);
      await tester.tap(fold);
      await tester.pumpAndSettle();
      final Finder sae = find.text(ScAkm.sae.label);
      await tester.ensureVisible(sae);
      await tester.tap(sae);
      await tester.pumpAndSettle();
      expect(c.scPreset, isNull);
      expect(find.text('Custom'), findsWidgets);
      // With SAE (8) added, the PMF-capable laptop now associates with the
      // WPA3-Personal only network.
      expect(c.verdict!.outcome, ScOutcome.associates);
    });

    testWidgets('PMF is disabled with a reason outside WPA2', (
      WidgetTester tester,
    ) async {
      await _pump(tester, height: 4000);
      final EapLadderController c = _controller(tester);
      c.whyMode = true;
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Required: WPA3-Personal only sets MFPC 1, MFPR 1 (required).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('switching back to Play the association restores the '
        'ordinary Join, the 6 GHz swap included', (WidgetTester tester) async {
      await _pump(tester);
      final EapLadderController c = _controller(tester);
      c.jrConfig = c.jrConfig.copyWith(band: JrBand.g6);
      c.whyMode = true;
      c.scNetSecurity = ScNetSecurity.wpa2Personal;
      expect(c.jr.failed, isTrue);
      c.whyMode = false;
      await tester.pumpAndSettle();
      expect(c.jr.failed, isFalse);
      expect(c.jr.security, JrSecurity.sae);
      expect(c.jr.messages.map((JrMessage m) => m.label), isNot(contains('')));
      final JrSequence plain = buildJoin(c.jrConfig);
      expect(c.jr.length, plain.length);
    });

    testWidgets('copy text names the pair, the verdict and where it stopped', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      final EapLadderController c = _controller(tester);
      _why(
        c,
        client: ScClientPreset.printer,
        net: ScNetSecurity.wpa2Personal,
        pmf: JrPmf.required,
      );
      final String t = c.copyText();
      expect(t, contains('Why won\'t it associate?'));
      expect(t, contains('Client: Printer, no PMF'));
      expect(t, contains('Refused: status 31 at the Association Response'));
      expect(t, contains('[stops here]'));
      expect(t, contains('Stopped here.'));
      expect(t.toLowerCase(), isNot(contains('join')));
    });

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final double width in <double>[360, 390, 1280]) {
        testWidgets(
          '$name $width px: every outcome lays out with no overflow',
          (WidgetTester tester) async {
            await _pump(tester, theme: theme(), width: width, height: 1200);
            final EapLadderController c = _controller(tester);
            for (final (
                  ScClientPreset p,
                  ScNetSecurity n,
                  JrBand b,
                  JrPmf pmf,
                  bool w,
                )
                in _cases) {
              _why(c, client: p, net: n, band: b, pmf: pmf, wifi7: w);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: '${p.name} $n');
            }
            // The capabilities fold open, too.
            final Finder fold = find.text(
              'Client capabilities (AKM, ciphers, PMF, bands)',
            );
            await tester.ensureVisible(fold);
            await tester.tap(fold);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('presenter', () {
    Future<EapLadderController> present(
      WidgetTester tester, {
      required Size window,
      ThemeData? theme,
    }) async {
      setWindow(tester, window);
      installFakeWindow();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? AppTheme.dark(),
          home: const JoinLadderScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      expect(find.byType(PresenterLayout), findsOneWidget);
      return tester
          .widget<JoinRoamStage>(find.byType(JoinRoamStage).last)
          .controller;
    }

    List<ScrollableState> pageScrollsBesidesLadder(WidgetTester tester) {
      final Set<ScrollableState> ladder = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byKey(JoinRoamStage.ladderScrollKey),
              matching: find.byType(Scrollable),
            ),
          )
          .toSet();
      return pageScrollables(
        tester,
      ).where((ScrollableState s) => !ladder.contains(s)).toList();
    }

    for (final (String name, ThemeData Function() theme)
        in <(String, ThemeData Function())>[
          ('dark', AppTheme.dark),
          ('light', AppTheme.light),
        ]) {
      for (final Size window in const <Size>[
        Size(1920, 1080),
        Size(1440, 900),
        Size(1470, 923),
      ]) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
            'every outcome fits with no overflow and no page scroll', (
          WidgetTester tester,
        ) async {
          final EapLadderController c = await present(
            tester,
            window: window,
            theme: theme(),
          );
          for (final (
                ScClientPreset p,
                ScNetSecurity n,
                JrBand b,
                JrPmf pmf,
                bool w,
              )
              in _cases) {
            _why(c, client: p, net: n, band: b, pmf: pmf, wifi7: w);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            final String why = '${p.name} ${n.name}';
            expect(tester.takeException(), isNull, reason: why);
            expect(pageScrollsBesidesLadder(tester), isEmpty, reason: why);
            expect(controlsOverflow(tester), 0, reason: why);
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
            expect(find.byKey(ScVerdictBand.bandKey), findsOneWidget);
          }
        });
      }
    }

    testWidgets('the verdict is at headline size', (WidgetTester tester) async {
      final EapLadderController c = await present(
        tester,
        window: const Size(1920, 1080),
      );
      _why(
        c,
        client: ScClientPreset.printer,
        net: ScNetSecurity.wpa2Personal,
        pmf: JrPmf.required,
      );
      await tester.pumpAndSettle();
      final Text headline = tester.widget<Text>(
        find.text('Refused: status 31 at the Association Response'),
      );
      final Text caption = tester.widget<Text>(
        find.descendant(
          of: find.byKey(ScVerdictBand.bandKey),
          matching: find.textContaining('This client is older than PMF'),
        ),
      );
      expect(headline.style!.fontSize!, greaterThan(caption.style!.fontSize!));
      expect(headline.style!.fontSize!, greaterThanOrEqualTo(28));
    });

    testWidgets('C cycles the client presets; Up and Down step the network '
        'security; Play mode keeps the passive dwell', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await present(
        tester,
        window: const Size(1920, 1080),
      );
      // Play the association: Up changes the passive dwell, C does nothing.
      final double dwell = c.jrConfig.passiveDwellMs;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.jrConfig.passiveDwellMs, dwell + 10);
      expect(c.presenterActions.sliderLabel, 'Passive dwell');
      expect(
        c.presenterActions.extra.map((PresenterExtraKey k) => k.keyLabel),
        isNot(contains('C')),
      );
      c.whyMode = true;
      await tester.pumpAndSettle();
      expect(c.presenterActions.sliderLabel, 'Network security');
      expect(c.scPreset, ScClientPreset.olderLaptop);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(c.scPreset, ScClientPreset.printer);
      for (int i = 0; i < ScClientPreset.values.length - 1; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.pump();
      }
      expect(c.scPreset, ScClientPreset.olderLaptop);
      final ScNetSecurity before = c.scNetwork.security;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.scNetwork.security.index, (before.index + 1) % 9);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.scNetwork.security, before);
      // The passive dwell did not move while Up and Down stepped the network.
      expect(c.jrConfig.passiveDwellMs, dwell + 10);
    });
  });
}
