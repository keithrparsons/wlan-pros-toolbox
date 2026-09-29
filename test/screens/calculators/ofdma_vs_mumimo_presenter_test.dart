// Presenter-mode test for OFDMA vs MU-MIMO (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, for every scenario and the fullest states (four clients on eight
// antennas with the reflection and the readouts open; MU-MIMO refused), and
// the keys it has: Right steps the scenario, Up and Down change the client
// count, R resets. Drag on the stage moves a client.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_painters.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mu_mimo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<OfdmaVsMumimoController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final OfdmaVsMumimoController c = OfdmaVsMumimoController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: OfdmaVsMumimoScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return c;
}

void _expectFits(WidgetTester tester, Size window, String why) {
  expect(tester.takeException(), isNull, reason: why);
  expect(pageScrollables(tester), isEmpty, reason: why);
  expect(controlsOverflow(tester), 0, reason: why);
  expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
}

void main() {
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
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size: every scenario fits', (
        WidgetTester tester,
      ) async {
        final OfdmaVsMumimoController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final MuPreset p in MuPreset.values) {
          c.applyPreset(p);
          await tester.pumpAndSettle();
          _expectFits(tester, window, p.label);
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text('Which wins here'),
            ),
            findsOneWidget,
          );
        }
      });

      testWidgets('$name $size: fullest state, readouts open', (
        WidgetTester tester,
      ) async {
        final OfdmaVsMumimoController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c
          ..setAntennas(8)
          ..setClientCount(4)
          ..setReflection(true)
          ..setExchanges(1);
        await tester.pumpAndSettle();
        await tester.tap(find.text('All readouts'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
      });

      testWidgets('$name $size: MU-MIMO refused', (WidgetTester tester) async {
        final OfdmaVsMumimoController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.setAntennas(2);
        await tester.pumpAndSettle();
        expect(c.result.block, MuBlock.tooManyClients);
        _expectFits(tester, window, 'refused');
      });
    }
  }

  testWidgets('Right steps the scenario, Up and Down the clients, R resets', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.preset, MuPreset.spreadBig);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.preset, MuPreset.bunched);
    final int n = c.clientCount;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.clientCount, n + 1);
    expect(c.preset, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.preset, MuPreset.spreadBig);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.clientCount, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging on the presenter stage moves a client', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    final Finder room = find.descendant(
      of: find.byKey(PresenterLayout.stageKey),
      matching: find.byKey(OfdmaVsMumimoStage.roomKey),
    );
    final RenderBox box = tester.renderObject<RenderBox>(room);
    final PresenterScale ps = PresenterScale.forWindow(const Size(1920, 1080));
    final Offset local = MuRoomGeometry(
      box.size,
      marker: ps.marker,
      viewRadiusM: c.viewRadiusM,
    ).toPx(c.clients[1]);
    final double a = c.clients[1].angleDeg;
    final TestGesture g = await tester.startGesture(box.localToGlobal(local));
    await g.moveBy(const Offset(120, 0));
    await g.up();
    await tester.pumpAndSettle();
    expect(c.selected, 1);
    expect(c.clients[1].angleDeg, greaterThan(a));
  });
}
