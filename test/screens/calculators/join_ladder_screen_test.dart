// Widget and presenter tests for the Wi-Fi Classroom tool "Joining a
// Network, Frame by Frame" (join-ladder, spec 21b).
//
// The frames are pinned in test/services/wifi_lab/join_roam_test.dart; these
// cover the screen contract: catalog, route and help registration beside the
// untouched join-network tool, the fresh state, Step and the caption, tapping
// a message to inspect it, the channel strip, the not-found state, the PMF
// shield, the ACD and DNAv4 toggle, phone and desktop widths in both themes,
// and the presenter layout (spec 00) with Space, Right, R and Up/Down.
// The 6 GHz race (spec 40) has its own group at the end: the toggle and its
// disabled state, the four strips, Step between findings, the RNR toggle,
// reduced motion, copy, phone width, and the presenter with C.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_race.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 1280,
  double height = 900,
  bool reduceMotion = true,
  JrConfig? initial,
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
          disableAnimations: reduceMotion,
        ),
        child: JoinLadderScreen(initial: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EapLadderController _controller(WidgetTester tester) =>
    tester.widget<JoinRoamStage>(find.byType(JoinRoamStage).first).controller;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('catalog, route and help register join-ladder; join-network is '
      'untouched', () {
    final ToolCategory classroom = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final ToolEntry e = classroom.tools.firstWhere(
      (ToolEntry t) => t.id == kJoinLadderToolId,
    );
    expect(e.title, 'Association, Frame by Frame');
    expect(e.subgroup, 'Network Design and Security');
    expect(e.routeName, '/tools/join-ladder');
    expect(e.isLive, isTrue);
    expect(AppRouter.routes.containsKey('/tools/join-ladder'), isTrue);
    // The real join tool keeps its id, title, route and category.
    final ToolEntry real = kToolCategories
        .expand((ToolCategory c) => c.tools)
        .firstWhere((ToolEntry t) => t.id == 'join-network');
    expect(real.title, isNot(e.title));
    expect(real.routeName, '/tools/join-network');
    expect(
      classroom.tools.where((ToolEntry t) => t.id == 'join-network'),
      isEmpty,
    );
    // Ids are unique across the catalog.
    final List<String> ids = <String>[
      for (final ToolCategory c in kToolCategories)
        for (final ToolEntry t in c.tools) t.id,
    ];
    expect(ids.where((String id) => id == kJoinLadderToolId).length, 1);
  });

  testWidgets('fresh: Ready, lanes, channel strip, timeline, no mode toggle', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Association, Frame by Frame'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.byKey(JoinRoamStage.stripKey), findsOneWidget);
    expect(find.byKey(JoinRoamStage.timelineKey), findsOneWidget);
    expect(find.text('Client'), findsOneWidget);
    expect(find.text('AP'), findsOneWidget);
    expect(find.text('DHCP server'), findsOneWidget);
    // No RADIUS lane for WPA2-Personal.
    expect(find.text('RADIUS server'), findsNothing);
    // Join is its own tool: no Authenticate / Roam toggle.
    expect(find.text('Authenticate'), findsNothing);
    final EapLadderController c = _controller(tester);
    expect(c.mode, LadderMode.join);
    expect(c.shown, 0);
    expect(find.byType(EapLadderControls), findsOneWidget);
    // Address check toggle shows both options.
    expect(find.text('ACD'), findsOneWidget);
    expect(find.text('DNAv4'), findsOneWidget);
    expect(
      find.textContaining('Address Conflict Detection (ACD, RFC 5227)'),
      findsWidgets,
    );
  });

  testWidgets('Step sends frames; tapping a sent message shows what it '
      'carries', (WidgetTester tester) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    await _tap(tester, find.text('Step'));
    expect(find.textContaining('Step 1 of ${c.length}'), findsOneWidget);
    await _tap(tester, find.text('Show all'));
    expect(c.atEnd, isTrue);
    await _tap(tester, find.text('Association Request').first);
    expect(c.inspecting, isTrue);
    expect(c.captionJr!.label, 'Association Request');
    expect(find.text('What it carries'), findsOneWidget);
    expect(find.text('Listen interval'), findsOneWidget);
    expect(find.text('RSN element: PMF bits'), findsOneWidget);
    expect(find.textContaining('(tapped;'), findsOneWidget);
    // Step or Back returns the caption to the latest.
    c.back();
    await tester.pumpAndSettle();
    expect(c.inspecting, isFalse);
    // The 4-way handshake frames read as data frames in the caption.
    final int m1 = c.jr.messages.indexWhere(
      (JrMessage m) => m.label == 'EAPOL-Key',
    );
    c.inspect(m1);
    await tester.pumpAndSettle();
    expect(find.text('EAPOL-Key in an 802.11 data frame'), findsOneWidget);
  });

  testWidgets('a too-short passive dwell: not found, the ladder stops', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: const JrConfig(scanType: JrScanType.passive, passiveDwellMs: 40),
    );
    expect(find.textContaining('Not found on this pass'), findsOneWidget);
    final EapLadderController c = _controller(tester);
    expect(c.length, 1);
    await _tap(tester, find.text('Step'));
    expect(find.text('Not found: the join stops here.'), findsOneWidget);
    // Lengthen the dwell: found again.
    c.jrConfig = c.jrConfig.copyWith(passiveDwellMs: 111);
    await tester.pumpAndSettle();
    expect(find.textContaining('Not found on this pass'), findsNothing);
  });

  testWidgets('the PMF shield shows only with PMF in use', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    c.showAll();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_rounded), findsWidgets);
    c.jrConfig = c.jrConfig.copyWith(pmf: JrPmf.off);
    c.showAll();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_rounded), findsNothing);
    // Open: no keys, no lock, no shield.
    c.jrConfig = c.jrConfig.copyWith(security: JrSecurity.open);
    c.showAll();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_rounded), findsNothing);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
  });

  testWidgets('the address-check toggle switches ACD and DNAv4', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final EapLadderController c = _controller(tester);
    final double acd = c.jr.totalMs;
    await _tap(tester, find.text('DNAv4'));
    expect(c.jrConfig.addressCheck, JrAddressCheck.dnav4);
    expect(c.jr.totalMs, lessThan(acd));
    expect(
      find.textContaining('Detecting Network Attachment (DNAv4, RFC 4436)'),
      findsWidgets,
    );
  });

  testWidgets('802.1X adds the RADIUS lane; 6 GHz forces WPA3 and PMF', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: const JrConfig(security: JrSecurity.dot1x));
    expect(find.text('RADIUS server'), findsOneWidget);
    expect(find.text('EAP method'), findsOneWidget);
    final EapLadderController c = _controller(tester);
    c.jrConfig = c.jrConfig.copyWith(security: JrSecurity.psk, band: JrBand.g6);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('6 GHz requires WPA3 or OWE with PMF'),
      findsWidgets,
    );
    expect(c.jr.security, JrSecurity.sae);
  });

  test('copy text lists every frame and the phase times', () {
    final EapLadderController c = EapLadderController(mode: LadderMode.join);
    addTearDown(c.dispose);
    final String text = c.copyText();
    expect(text, startsWith('Association, Frame by Frame'));
    expect(text, contains('(management) Probe Request'));
    expect(text, contains('(data) EAPOL-Key'));
    expect(text, contains('via AP'));
    expect(text, contains('Address check: 5.50 s'));
    expect(text, contains('Total (illustrative inputs): 7.59 s'));
    expect(text, isNot(contains('—')));
    expect(text, isNot(contains('802.1x')));
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
      for (final JrConfig cfg in const <JrConfig>[
        JrConfig(),
        JrConfig(security: JrSecurity.dot1x),
        JrConfig(band: JrBand.g6, scanType: JrScanType.passive),
      ]) {
        testWidgets(
          '${cfg.security.name} ${cfg.band.name} at $w px, $themeName, '
          'no sideways scroll',
          (WidgetTester tester) async {
            await _pump(
              tester,
              width: w,
              height: 844,
              theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
              initial: cfg,
            );
            await _tap(tester, find.text('Show all'));
            expect(tester.takeException(), isNull);
            for (final Scrollable s in tester.widgetList<Scrollable>(
              find.byType(Scrollable),
            )) {
              expect(s.axisDirection, AxisDirection.down);
            }
            expect(find.textContaining('NaN'), findsNothing);
          },
        );
      }
    }
  }

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
        for (final JrSecurity sec in JrSecurity.values) {
          for (final JrBand band in const <JrBand>[JrBand.g5, JrBand.g6]) {
            testWidgets(
              '$name ${window.width.toInt()}x${window.height.toInt()} '
              '${sec.name} ${band.name}: fits with no overflow and no page '
              'scroll',
              (WidgetTester tester) async {
                final EapLadderController c = await present(
                  tester,
                  window: window,
                  theme: theme(),
                );
                // 6 GHz passive: the forced-security note and the longest scan.
                c.jrConfig = c.jrConfig.copyWith(
                  security: sec,
                  band: band,
                  scanType: band == JrBand.g6
                      ? JrScanType.passive
                      : JrScanType.active,
                );
                for (int i = 0; i < c.length * 2 ~/ 3; i++) {
                  c.step();
                }
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 400));
                expect(tester.takeException(), isNull);
                expect(pageScrollsBesidesLadder(tester), isEmpty);
                expect(controlsOverflow(tester), 0);
                expectOnScreen(
                  tester,
                  find.byKey(PresenterLayout.stageKey),
                  window,
                );
              },
            );
          }
        }
      }
    }

    testWidgets('Space plays and pauses, Right steps, R resets, Up and Down '
        'change the passive dwell', (WidgetTester tester) async {
      final EapLadderController c = await present(
        tester,
        window: const Size(1920, 1080),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(c.shown, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 2));
      expect(c.shown, greaterThan(3));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(c.playing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(c.shown, 0);
      final double dwell = c.jrConfig.passiveDwellMs;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.jrConfig.passiveDwellMs, dwell - 10);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(c.jrConfig.passiveDwellMs, dwell);
      expect(tester.takeException(), isNull);
    });
  });
  group('6 GHz race (spec 40)', () {
    Future<EapLadderController> race(
      WidgetTester tester, {
      double width = 1280,
      double height = 900,
      ThemeData? theme,
      bool reduceMotion = true,
    }) async {
      await _pump(
        tester,
        width: width,
        height: height,
        theme: theme,
        reduceMotion: reduceMotion,
        initial: const JrConfig(band: JrBand.g6, security: JrSecurity.sae),
      );
      await _tap(tester, find.text('Compare all four'));
      final EapLadderController c = _controller(tester);
      expect(c.raceActive, isTrue);
      return c;
    }

    testWidgets('Compare all four is disabled outside 6 GHz', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      final EapLadderController c = _controller(tester);
      expect(find.text('Compare all four'), findsOneWidget);
      expect(
        find.text(
          'Only for 6 GHz: the race compares four ways to find a 6 GHz AP.',
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Compare all four'));
      expect(c.raceActive, isFalse);
      expect(find.byKey(SixGhzRaceCard.raceKey), findsNothing);
      expect(find.byKey(JoinRoamStage.ladderScrollKey), findsOneWidget);
    });

    testWidgets('on: four strips replace the ladder; Show all names every '
        'finding and the first', (WidgetTester tester) async {
      final EapLadderController c = await race(tester);
      expect(find.byKey(SixGhzRaceCard.raceKey), findsOneWidget);
      expect(find.byKey(JoinRoamStage.ladderScrollKey), findsNothing);
      expect(find.byKey(JoinRoamStage.timelineKey), findsNothing);
      for (final SixGhzMethod m in SixGhzMethod.values) {
        expect(find.byKey(SixGhzRaceCard.laneKey(m)), findsOneWidget);
      }
      expect(find.textContaining('Ready. Press Play'), findsOneWidget);
      expect(find.text('ready'), findsNWidgets(4));
      // The single-method toggle has nothing to do in the race.
      expect(find.text('The race runs all four ways at once.'), findsOneWidget);
      await _tap(tester, find.text('Show all'));
      expect(c.atEnd, isTrue);
      expect(find.text('found at 1.01 s'), findsOneWidget); // passive, 59
      expect(find.text('found at 69 ms'), findsOneWidget); // PSC probe
      expect(find.text('found at 2.05 s'), findsOneWidget); // RNR + 5 GHz
      expect(find.text('found at 51 ms'), findsOneWidget); // FILS listen
      expect(find.text('first'), findsOneWidget);
      expect(
        find.textContaining('Listen 20 TU on each PSC found the AP first'),
        findsOneWidget,
      );
      expect(find.text('First to find it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the RNR toggle: leave the 5 GHz scan out and RNR wins', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await race(tester);
      expect(c.rnrCountsPriorScan, isTrue, reason: 'Keith: default on');
      await _tap(tester, find.text('Leave out'));
      expect(c.rnrCountsPriorScan, isFalse);
      c.showAll();
      await tester.pumpAndSettle();
      expect(find.text('found at 3 ms'), findsOneWidget);
      expect(c.race.winner!.method, SixGhzMethod.rnr);
      expect(find.textContaining('RNR goes straight to channel 37'), findsOne);
      await _tap(tester, find.text('Include'));
      expect(c.rnrCountsPriorScan, isTrue);
      // A finished race shows the new result whole.
      expect(c.atEnd, isTrue);
      expect(find.text('found at 2.05 s'), findsOneWidget);
    });

    testWidgets('Step jumps to each finding, Back returns, Reset clears', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await race(tester);
      final List<double> f = c.race.findings;
      for (final double t in f) {
        await _tap(tester, find.text('Step'));
        expect(c.raceMs, t);
      }
      expect(c.atEnd, isTrue);
      await _tap(tester, find.text('Back'));
      expect(c.raceMs, f[f.length - 2]);
      expect(find.textContaining('At '), findsOneWidget);
      await _tap(tester, find.text('Reset'));
      expect(c.raceMs, 0);
      expect(find.textContaining('Ready. Press Play'), findsOneWidget);
    });

    testWidgets('reduced motion: Play shows the whole race at once', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await race(tester);
      await _tap(tester, find.text('Play'));
      expect(c.playing, isFalse);
      expect(c.atEnd, isTrue);
      expect(
        find.textContaining('Play shows the whole race at once'),
        findsOneWidget,
      );
    });

    testWidgets('motion on: Play sweeps the cursor to the end', (
      WidgetTester tester,
    ) async {
      final EapLadderController c = await race(tester, reduceMotion: false);
      await tester.ensureVisible(find.text('Play'));
      await tester.pump();
      await tester.tap(find.text('Play'));
      await tester.pump();
      expect(c.playing, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(c.raceMs, greaterThan(0));
      expect(c.atEnd, isFalse);
      for (int i = 0; i < 80 && !c.atEnd; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(c.atEnd, isTrue);
      expect(c.playing, isFalse);
    });

    test('copy text lists the four times and the first', () {
      final EapLadderController c = EapLadderController(
        mode: LadderMode.join,
        initialJr: const JrConfig(band: JrBand.g6),
      );
      addTearDown(c.dispose);
      c.raceOn = true;
      final String text = c.copyText();
      expect(text, startsWith('Association, Frame by Frame: four ways'));
      expect(text, contains('Listen on all 59: found at 1.01 s'));
      expect(text, contains('Probe the 15 PSCs: found at 69 ms'));
      expect(text, contains('Known via RNR: found at 2.05 s'));
      expect(text, contains('Listen 20 TU on each PSC: found at 51 ms'));
      expect(text, contains('First to find the AP: Listen 20 TU on each PSC.'));
      expect(text, contains('dot11MinPSCProbeDelay'));
      expect(text, isNot(contains('—')));
      // Out of 6 GHz the race is off and copy is the ladder's again.
      c.jrConfig = c.jrConfig.copyWith(band: JrBand.g5);
      expect(c.raceActive, isFalse);
      expect(c.copyText(), startsWith('Association, Frame by Frame (WLAN'));
    });

    for (final String themeName in <String>['dark', 'light']) {
      for (final double w in <double>[390, 1280]) {
        testWidgets('race at $w px, $themeName, no sideways scroll', (
          WidgetTester tester,
        ) async {
          final EapLadderController c = await race(
            tester,
            width: w,
            height: 844,
            theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
          );
          await _tap(tester, find.text('Show all'));
          expect(c.atEnd, isTrue);
          expect(tester.takeException(), isNull);
          for (final Scrollable s in tester.widgetList<Scrollable>(
            find.byType(Scrollable),
          )) {
            expect(s.axisDirection, AxisDirection.down);
          }
          expect(find.textContaining('NaN'), findsNothing);
        });
      }
    }

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
          for (final bool prior in <bool>[true, false]) {
            testWidgets(
              '$name ${window.width.toInt()}x${window.height.toInt()} race '
              '${prior ? 'with' : 'without'} the 5 GHz scan: fits, no '
              'overflow, no page scroll',
              (WidgetTester tester) async {
                final EapLadderController c = await present(
                  tester,
                  window: window,
                  theme: theme(),
                );
                c.toggleRace();
                c.rnrCountsPriorScan = prior;
                c.showAll();
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 400));
                expect(c.raceActive, isTrue);
                expect(
                  find.descendant(
                    of: find.byKey(PresenterLayout.stageKey),
                    matching: find.byKey(SixGhzRaceCard.raceKey),
                  ),
                  findsOneWidget,
                );
                expect(find.byKey(JoinRoamStage.ladderScrollKey), findsNothing);
                expect(tester.takeException(), isNull);
                expect(pageScrollables(tester), isEmpty);
                expect(controlsOverflow(tester), 0);
                expectOnScreen(
                  tester,
                  find.byKey(PresenterLayout.stageKey),
                  window,
                );
              },
            );
          }
        }
      }

      // Keith, 2026-09-29: the race moves off C (security-compat keeps C
      // in this tool). R was asked for but is the shared Reset key, handled
      // before any extra key, so the race takes the next free letter, S.
      testWidgets('S turns the race on (moving to 6 GHz), Space runs it, '
          'Right steps to a finding, R resets, S turns it off; C does not '
          'touch the race', (
        WidgetTester tester,
      ) async {
        final EapLadderController c = await present(
          tester,
          window: const Size(1920, 1080),
        );
        expect(c.jrConfig.band, JrBand.g5);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await tester.pump();
        expect(c.raceActive, isFalse);
        expect(c.jrConfig.band, JrBand.g5);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pump();
        expect(c.jrConfig.band, JrBand.g6);
        expect(c.raceActive, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(c.raceMs, c.race.findings.first);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.pump();
        expect(c.raceMs, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(c.playing, isTrue);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));
        expect(c.raceMs, greaterThan(0));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(c.playing, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pump();
        expect(c.raceActive, isFalse);
        expect(find.byKey(JoinRoamStage.ladderScrollKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
