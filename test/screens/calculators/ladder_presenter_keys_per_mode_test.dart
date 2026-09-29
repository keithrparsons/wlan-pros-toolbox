// The presenter keys of the two ladder tools, per mode, after the 1.12
// merge of security-compat (C, Why won't it associate?), eap-break-it (B,
// Authenticate) and six-ghz-race (S, the race in Join).
//
// The three branches each added one letter to the same controller and were
// tested alone. Merged, two seams showed:
//   1. The 802.1X and EAP Ladder's presenter did not rebuild with the
//      controller, so after switching to Roam the ? list still offered
//      B (Break it), which does nothing in Roam.
//   2. The race could be switched on inside Why won't it associate? with S,
//      where the stage then drew the race while the panel showed the client
//      and network, and nothing on the panel could turn the race off. The
//      race is a Join discovery view and the why view has no race control,
//      so the race is offered only in Play the association.
//
// Each test reads the ? list as the presenter shows it, not the actions list.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_race.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_jr_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/join_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/security_compat_controls.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

const String _breakIt = 'Break it: next fault';
const String _nextClient = 'Next client';
const String _race = 'Race the four ways to find a 6 GHz AP, on or off';

Future<void> _present(WidgetTester tester, Widget screen) async {
  setWindow(tester, const Size(1920, 1080));
  installFakeWindow();
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: screen));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
}

/// The descriptions in the ? list, opened and closed again.
Future<Set<String>> _sheet(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
  await tester.pumpAndSettle();
  final Finder sheet = find.byKey(PresenterLayout.shortcutsKey);
  expect(sheet, findsOneWidget);
  final Set<String> out = <String>{
    for (final Text t in tester.widgetList<Text>(
      find.descendant(of: sheet, matching: find.byType(Text)),
    ))
      if (t.data != null) t.data!,
  };
  await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
  await tester.pumpAndSettle();
  return out;
}

void main() {
  group('802.1X and EAP Ladder', () {
    EapLadderController ctl(WidgetTester tester) => tester
        .widget<EapLadderStage>(find.byType(EapLadderStage).last)
        .controller;

    testWidgets('B is listed in Authenticate and not in Roam', (
      WidgetTester tester,
    ) async {
      await _present(tester, const EapLadderScreen());
      final EapLadderController c = ctl(tester);
      expect(c.mode, LadderMode.authenticate);
      Set<String> keys = await _sheet(tester);
      expect(keys, contains(_breakIt));
      expect(keys, isNot(contains(_nextClient)));
      expect(keys, isNot(contains(_race)));

      c.mode = LadderMode.roam;
      await tester.pumpAndSettle();
      keys = await _sheet(tester);
      expect(keys, isNot(contains(_breakIt)));
      expect(keys, isNot(contains(_nextClient)));
      expect(keys, isNot(contains(_race)));

      c.mode = LadderMode.authenticate;
      await tester.pumpAndSettle();
      expect(await _sheet(tester), contains(_breakIt));
      expect(tester.takeException(), isNull);
    });
  });

  group('Association, Frame by Frame', () {
    EapLadderController ctl(WidgetTester tester) => tester
        .widget<JoinRoamStage>(find.byType(JoinRoamStage).last)
        .controller;

    testWidgets('Play the association lists S and not C; Why won\'t it '
        'associate? lists C and not S', (WidgetTester tester) async {
      await _present(tester, const JoinLadderScreen());
      final EapLadderController c = ctl(tester);
      Set<String> keys = await _sheet(tester);
      expect(keys, contains(_race));
      expect(keys, isNot(contains(_nextClient)));
      expect(keys, isNot(contains(_breakIt)));

      c.whyMode = true;
      await tester.pumpAndSettle();
      keys = await _sheet(tester);
      expect(keys, contains(_nextClient));
      expect(keys, isNot(contains(_race)));
      expect(keys, isNot(contains(_breakIt)));
      expect(keys, contains('Network security up'));
    });

    testWidgets('S does nothing in Why won\'t it associate?; the verdict '
        'and ladder stay on the stage', (WidgetTester tester) async {
      await _present(tester, const JoinLadderScreen());
      final EapLadderController c = ctl(tester);
      c.whyMode = true;
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(c.whyMode, isTrue);
      expect(c.raceActive, isFalse);
      expect(find.byKey(SixGhzRaceCard.raceKey), findsNothing);
      expect(find.byKey(ScVerdictBand.bandKey), findsOneWidget);

      // The controller refuses it too, not only the key list.
      c.toggleRace();
      c.raceOn = true;
      await tester.pumpAndSettle();
      expect(c.raceActive, isFalse);
      expect(find.byKey(SixGhzRaceCard.raceKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the race on, then Why won\'t it associate?: the race goes '
        'off and stays off on the way back', (WidgetTester tester) async {
      await _present(tester, const JoinLadderScreen());
      final EapLadderController c = ctl(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(c.raceActive, isTrue);
      expect(find.byKey(SixGhzRaceCard.raceKey), findsOneWidget);

      c.whyMode = true;
      await tester.pumpAndSettle();
      expect(c.raceActive, isFalse);
      expect(find.byKey(SixGhzRaceCard.raceKey), findsNothing);
      expect(find.byKey(ScVerdictBand.bandKey), findsOneWidget);

      c.whyMode = false;
      await tester.pumpAndSettle();
      expect(c.raceActive, isFalse);
      expect(c.jrConfig.band, JrBand.g6);
      expect(find.byKey(JoinRoamStage.ladderScrollKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Roam never offers the race', (WidgetTester tester) async {
      await _present(tester, const JoinLadderScreen());
      final EapLadderController c = ctl(tester);
      c.jrConfig = c.jrConfig.copyWith(band: JrBand.g6);
      c.raceOn = true;
      c.mode = LadderMode.roam;
      await tester.pumpAndSettle();
      expect(c.raceAvailable, isFalse);
      expect(c.raceActive, isFalse);
      final Set<String> keys = await _sheet(tester);
      expect(keys, isNot(contains(_race)));
      expect(find.text('6 GHz view'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
