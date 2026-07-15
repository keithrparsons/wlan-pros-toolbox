// Inline host/IP validation across the direct-connection tools — the fix for
// the 2026-07-14 user report: a typo used to be silently accepted and the tool
// "appeared broken". Now a malformed address shows an inline error and the run
// never starts; correcting it clears the error and the run proceeds.
//
// The screens are driven through their injected seams (CurrentNetwork reader +
// service / PingPlotController), so nothing here touches a real socket. RED
// before the wiring (a bad host proceeded with no error); GREEN after.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_plotter_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/port_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';
import 'package:wlan_pros_toolbox/services/network/ping_plot_controller.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';
import 'package:wlan_pros_toolbox/services/network/port_scan_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// The shared malformed message surfaced by NetworkTarget.validateHostOrIp.
const String _malformed = 'Not a valid host or IP address.';

/// A CurrentNetwork that measured nothing — no prefill, no gateway chip — so
/// the host field starts empty and the test controls the input.
CurrentNetwork _noNet() =>
    CurrentNetwork(reader: () async => (ip: null, mask: null, gateway: null));

Widget _wrap(Widget screen) =>
    MaterialApp(theme: AppTheme.dark(), home: screen);

({PingPlotController controller, StreamController<PingProgress> sink})
    _wirePlot() {
  final StreamController<PingProgress> sink =
      StreamController<PingProgress>.broadcast();
  final PingPlotController controller = PingPlotController(
    pingStreamFactory: ({
      required String host,
      required int port,
      required Duration interval,
      required Duration timeout,
      Future<void>? cancel,
    }) =>
        sink.stream,
  );
  return (controller: controller, sink: sink);
}

void main() {
  testWidgets('Ping: a malformed host shows the inline error and does not run',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      PingScreen(service: PingService(), network: _noNet()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '192.168.1.256');
    await tester.tap(find.widgetWithText(FilledButton, 'Ping'));
    await tester.pump();

    expect(find.text(_malformed), findsOneWidget);
    // Still idle: the run button is present (not swapped for the running
    // spinner), confirming the malformed host never started a ping.
    expect(find.widgetWithText(FilledButton, 'Ping'), findsOneWidget);
  });

  testWidgets('Port Scan: a malformed host shows the inline error, no scan',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      PortScanScreen(service: PortScanService(), network: _noNet()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'http://host');
    await tester.tap(find.text('Scan'));
    await tester.pump();

    expect(find.text(_malformed), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets(
      'Ping Plotter: a malformed host errors and does not run; correcting it '
      'clears the error and the run starts', (WidgetTester tester) async {
    final w = _wirePlot();
    addTearDown(w.sink.close);
    await tester
        .pumpWidget(_wrap(PingPlotterScreen(controller: w.controller)));
    await tester.pumpAndSettle();

    // Bad entry → inline error, no run.
    await tester.enterText(find.byType(TextField).first, '192.168..1');
    await tester.tap(find.text('Start plot'));
    await tester.pump();
    expect(find.text(_malformed), findsOneWidget);
    expect(w.controller.running, isFalse);

    // Correcting to a valid host clears the error and starts the plot.
    await tester.enterText(find.byType(TextField).first, '1.1.1.1');
    await tester.tap(find.text('Start plot'));
    await tester.pump();
    expect(find.text(_malformed), findsNothing);
    expect(w.controller.running, isTrue);
  });
}
