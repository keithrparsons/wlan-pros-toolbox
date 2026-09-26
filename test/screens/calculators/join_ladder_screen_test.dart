// Widget and presenter tests for the Wi-Fi Classroom tool "Joining a
// Network, Frame by Frame" (join-ladder, spec 21b).
//
// The frames are pinned in test/services/wifi_lab/join_roam_test.dart; these
// cover the screen contract: catalog, route and help registration beside the
// untouched join-network tool, the fresh state, Step and the caption, tapping
// a message to inspect it, the channel strip, the not-found state, the PMF
// shield, the ACD and DNAv4 toggle, phone and desktop widths in both themes,
// and the presenter layout (spec 00) with Space, Right, R and Up/Down.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controls.dart';
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
    expect(e.title, 'Joining a Network, Frame by Frame');
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
    expect(find.text('Joining a Network, Frame by Frame'), findsOneWidget);
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
    expect(text, startsWith('Joining a Network, Frame by Frame'));
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
}
