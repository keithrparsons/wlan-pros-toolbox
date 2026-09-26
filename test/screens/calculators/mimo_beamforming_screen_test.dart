// Widget tests for the MIMO and Beamforming screen (Wi-Fi Classroom spec 06).
//
// The model has its own tests (test/services/wifi_lab/mimo_beamforming_model
// _test.dart); these check the screen drives it: the stage and controls are
// separate widgets on one controller, ideal gains are labeled as ideal upper
// bounds, the capture figure is labeled as our measurement, Swap gives the
// vice versa case, the sniffer verdict follows its chain count, beamforming
// off removes the sounding cost, and the layout holds at phone width in both
// themes without the page scrolling sideways.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mimo_beamforming_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host({
  ThemeData? theme,
  int ap = 4,
  int client = 2,
  LinkDirection direction = LinkDirection.downlink,
}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: MimoBeamformingScreen(
    initialApChains: ap,
    initialClientChains: client,
    initialDirection: direction,
  ),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('opens on a 4x4 AP and a 2x2 client with computed results', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('MIMO and Beamforming'), findsOneWidget);
    expect(find.text('Streams and spare chains'), findsOneWidget);
    expect(find.text('Beam pattern, seen from above'), findsOneWidget);
    expect(find.text('What beamforming costs: sounding'), findsOneWidget);
    expect(find.text('Both directions side by side'), findsOneWidget);
    expect(
      find.text('4x4 AP, 2x2 client: 2 streams each way.'),
      findsOneWidget,
    );
    // Stage and controls are separate widgets on one controller.
    expect(find.byType(MimoStage), findsOneWidget);
    expect(find.byType(MimoControls), findsNWidgets(2));
  });

  testWidgets('ideal gains are labeled as ideal upper bounds', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(
      find.text('Transmit beamforming, ideal upper bound'),
      findsOneWidget,
    );
    expect(find.text('Receive combining, ideal upper bound'), findsOneWidget);
    expect(
      find.textContaining('up to +3.0 dB, an ideal upper bound'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Transmit beamforming, ideal upper bound: downlink +3.0 dB, '
        'uplink none',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the capture figure is labeled as our measurement', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Our measurement, not a model output'), findsOneWidget);
    expect(find.text('50.8%'), findsOneWidget);
    expect(find.text('5.1%'), findsOneWidget);
  });

  testWidgets('uplink: the AP spare receive chains combine', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.tap(find.text('Uplink').first);
    await tester.pump();

    expect(
      find.textContaining('AP: 2 spare chains listen too and combine'),
      findsOneWidget,
    );
    expect(find.textContaining('Uplink: the client transmits'), findsWidgets);
  });

  testWidgets('Swap gives the vice versa case', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.tap(find.text('Swap'));
    await tester.pump();

    expect(
      find.text('2x2 AP, 4x4 client: 2 streams each way.'),
      findsOneWidget,
    );
    // Downlink now: the client has the spare receive chains.
    expect(
      find.textContaining('Client: 2 spare chains listen too and combine'),
      findsOneWidget,
    );
  });

  testWidgets('the sniffer verdict follows its chain count', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.text('No: 1 chain for 2 streams'), findsOneWidget);

    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    expect(find.text('Yes: 2 chains for 2 streams'), findsOneWidget);
  });

  testWidgets('beamforming off: nothing steered, no sounding cost', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.text('Sounding, estimated'), findsOneWidget);

    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(find.text('Sounding, estimated'), findsNothing);
    expect(
      find.textContaining('the AP never sounds the client'),
      findsOneWidget,
    );
    expect(find.text('0.0 dB, not steered'), findsOneWidget);
  });

  testWidgets('dragging the pattern moves the nearer marker', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 5000));
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.text('20 deg right'), findsOneWidget);

    final Finder pattern = find.bySemanticsLabel(
      RegExp('^Beam pattern seen from above'),
    );
    final Rect r = tester.getRect(pattern);
    // Straight ahead of the AP: nearer the client (20) than the sniffer (-35).
    await tester.tapAt(Offset(r.center.dx, r.top + 30));
    await tester.pump();
    expect(find.text('20 deg right'), findsNothing);
    expect(find.text('0 deg'), findsOneWidget);
  });

  testWidgets('the copy payload carries the link and the measurement', (
    WidgetTester tester,
  ) async {
    final MimoController c = MimoController();
    addTearDown(c.dispose);
    expect(c.copyText(), contains('Streams: 2 downlink, 2 uplink'));
    expect(c.copyText(), contains('(ideal upper bound): up to +3.0 dB'));
    expect(c.copyText(), contains('Our measurement'));
    c.beamforming = false;
    expect(c.copyText(), contains('Sounding: none'));
  });

  for (final (String name, ThemeData Function() theme) t
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final (int, int) chains in <(int, int)>[(4, 2), (8, 4), (1, 1)]) {
      testWidgets('390 px, ${t.$1}, ${chains.$1}x${chains.$2}: no overflow, '
          'no sideways scroll', (WidgetTester tester) async {
        await _setSize(tester, const Size(390, 900));
        await tester.pumpWidget(
          _host(theme: t.$2(), ap: chains.$1, client: chains.$2),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final Scrollable s in tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        )) {
          expect(s.axisDirection, anyOf(AxisDirection.down, AxisDirection.up));
        }
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -8000),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
