// OFDMA vs MU-MIMO screen (spec 47): every scenario renders at phone and
// desktop widths in both themes without overflow; the verdict, the pair
// badges and the refusal agree; the move buttons and the drag move a client;
// Copy carries the verdict.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_painters.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_vs_mumimo_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mu_mimo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<OfdmaVsMumimoController> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 3000),
  ThemeData? theme,
  MuPreset preset = MuPreset.spreadBig,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final OfdmaVsMumimoController c = OfdmaVsMumimoController(preset: preset);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: OfdmaVsMumimoScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double w in <double>[360, 390, 820, 1280]) {
      testWidgets('$name ${w.toInt()}: every scenario renders cleanly', (
        WidgetTester tester,
      ) async {
        final OfdmaVsMumimoController c = await _pump(
          tester,
          size: Size(w, 4000),
          theme: theme(),
        );
        for (final MuPreset p in MuPreset.values) {
          c.applyPreset(p);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: p.label);
          expect(find.text('Which wins here'), findsOneWidget);
        }
        c.toggleWorking();
        c.setReflection(true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('verdicts per scenario', (WidgetTester tester) async {
    final OfdmaVsMumimoController c = await _pump(tester);
    expect(find.textContaining('MU-MIMO, by'), findsOneWidget);
    c.applyPreset(MuPreset.bunched);
    await tester.pumpAndSettle();
    expect(find.textContaining('too much to decode'), findsWidgets);
    expect(find.textContaining('not separable'), findsWidgets);
    c.applyPreset(MuPreset.tinyFrames);
    await tester.pumpAndSettle();
    expect(find.textContaining('OFDMA, by'), findsOneWidget);
  });

  testWidgets('more clients than antennas: no pair reads separable', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _pump(tester);
    c.setAntennas(3);
    await tester.pumpAndSettle();
    expect(c.result.block, MuBlock.tooManyClients);
    expect(find.textContaining('at least 4 AP antennas'), findsWidgets);
    expect(find.textContaining(': separable'), findsNothing);
    expect(find.textContaining('not separable as a group'), findsOneWidget);
  });

  testWidgets('an edit leaves the preset; picking one restores it', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _pump(tester);
    expect(find.text('Spread out, big frames'), findsWidgets);
    c.setPayload(500);
    await tester.pumpAndSettle();
    expect(c.preset, isNull);
    expect(find.text('Your own layout'), findsOneWidget);
    c.nextPreset();
    expect(c.preset, MuPreset.spreadBig);
  });

  testWidgets('the move buttons turn and step the selected client', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _pump(tester);
    final double a0 = c.clients[0].angleDeg;
    final double d0 = c.clients[0].distanceM;
    await tester.ensureVisible(find.text('Turn right'));
    await tester.tap(find.text('Turn right'));
    await tester.tap(find.text('Farther'));
    await tester.pumpAndSettle();
    expect(c.clients[0].angleDeg, a0 + kMuTurnStepDeg);
    expect(c.clients[0].distanceM, d0 + kMuDistanceStepM);
    // At the edge the button is disabled.
    c.moveClient(0, const MuClient(angleDeg: -90, distanceM: 8));
    await tester.pumpAndSettle();
    final OutlinedButton left = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Turn left'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(left.onPressed, isNull);
  });

  testWidgets('dragging a client moves it and holds the scale', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _pump(tester);
    final double view = c.viewRadiusM;
    final Finder room = find.byKey(OfdmaVsMumimoStage.roomKey);
    final Rect r = tester.getRect(room);
    // Client D sits right of the AP; drag from its dot toward the far left.
    final MuClient d = c.clients[3];
    final Offset from =
        r.topLeft + MuRoomGeometry(r.size, viewRadiusM: view).toPx(d);
    final TestGesture g = await tester.startGesture(from);
    await g.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(c.viewRadiusM, view);
    await g.up();
    await tester.pumpAndSettle();
    expect(c.selected, 3);
    expect(c.clients[3].angleDeg, lessThan(d.angleDeg));
  });

  testWidgets('Copy text names the verdict and each client', (
    WidgetTester tester,
  ) async {
    final OfdmaVsMumimoController c = await _pump(tester);
    final String t = c.copyText();
    expect(t, contains('Which wins here: MU-MIMO'));
    expect(t, contains('A: 50 deg left, 8 m'));
    expect(t, contains('sounding 533.6 µs'));
    expect(t, isNot(contains('—')));
  });

  test('the help entry exists, credits no outside lab tool, no em dash', () {
    final Map<String, dynamic> tools =
        (jsonDecode(File('assets/help/tool_help.json').readAsStringSync())
                as Map<String, dynamic>)['tools']
            as Map<String, dynamic>;
    final Map<String, dynamic> e =
        tools[kOfdmaVsMumimoToolId] as Map<String, dynamic>;
    for (final String k in <String>[
      'name',
      'purpose',
      'howToUse',
      'inputs',
      'algorithm',
      'example',
      'fieldNotes',
      'source',
    ]) {
      expect(e.containsKey(k), isTrue, reason: k);
    }
    final String all = jsonEncode(e).toLowerCase();
    // Keith, 2026-09-29: no credit to Ed or SIAM Wireless anywhere.
    expect(all, isNot(contains('siam')));
    expect(all, isNot(contains('semfio')));
    expect(all, isNot(contains('\u2014')));
    expect(all, isNot(contains('—')));
  });
}
