// PingPlotterScreen — widget tests for the live latency-trend tool.
//
// Drives the screen through its injected PingPlotController seam (a
// caller-driven synthetic ping stream), so no socket, no timer, and no real
// PingService run. Covers:
//   * idle → form only, no chart/readout;
//   * a run → readout (current/min/avg/max/jitter) + the fl_chart canvas render;
//   * honest dropped-packet path → loss% shown, no fabricated 0;
//   * blank-host inline validation;
//   * Copy payload carries the summary + a per-sample TSV with an honest loss row;
//   * no overflow across the standard widths;
//   * dispose tears down cleanly (no setState-after-unmount, no leak).

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_plotter_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ping_plot_controller.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

PingProgress _progress(int seq, double? rttMs, {String? error}) {
  final bool success = rttMs != null;
  return PingProgress(
    reply: PingReply(
      sequence: seq,
      success: success,
      rtt: success ? Duration(microseconds: (rttMs * 1000).round()) : null,
      errorLabel: success ? null : (error ?? 'timeout'),
    ),
    stats: PingStats.empty,
  );
}

({PingPlotController controller, StreamController<PingProgress> sink})
    _wire() {
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

Widget _host(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    );

void main() {
  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('idle: form only, no chart or readout yet', (tester) async {
    final w = _wire();
    addTearDown(w.sink.close);
    await tester.pumpWidget(_host(PingPlotterScreen(controller: w.controller)));

    expect(find.text('Ping Plotter'), findsOneWidget);
    expect(find.text('Start plot'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.text('Latency trend'), findsNothing);
  });

  testWidgets('a run renders the readout metrics and the chart',
      (tester) async {
    final w = _wire();
    addTearDown(w.sink.close);
    await tester.pumpWidget(_host(PingPlotterScreen(controller: w.controller)));

    await tester.enterText(find.byType(TextField), '1.1.1.1');
    await tester.tap(find.text('Start plot'));
    await tester.pump();

    w.sink.add(_progress(1, 12));
    w.sink.add(_progress(2, 18));
    w.sink.add(_progress(3, 15));
    await tester.pump();

    // Readout labels present.
    expect(find.text('current'), findsOneWidget);
    expect(find.text('min'), findsOneWidget);
    expect(find.text('avg'), findsOneWidget);
    expect(find.text('max'), findsOneWidget);
    expect(find.text('jitter'), findsOneWidget);
    // Chart canvas rendered.
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Latency trend'), findsOneWidget);
    // Running control swapped to Stop.
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('honest dropped-packet: loss shown, no fabricated 0',
      (tester) async {
    final w = _wire();
    addTearDown(w.sink.close);
    await tester.pumpWidget(_host(PingPlotterScreen(controller: w.controller)));

    await tester.enterText(find.byType(TextField), 'host');
    await tester.tap(find.text('Start plot'));
    await tester.pump();

    w.sink.add(_progress(1, 10));
    w.sink.add(_progress(2, null, error: 'unreachable'));
    await tester.pump();

    // 1 of 2 replies, 50% loss — surfaced in the summary header.
    expect(find.textContaining('1 / 2'), findsOneWidget);
    expect(find.textContaining('50% loss'), findsOneWidget);
  });

  testWidgets('blank host shows inline validation, no run', (tester) async {
    final w = _wire();
    addTearDown(w.sink.close);
    await tester.pumpWidget(_host(PingPlotterScreen(controller: w.controller)));

    await tester.tap(find.text('Start plot'));
    await tester.pump();

    expect(find.text('Enter a host or IP to plot.'), findsOneWidget);
    expect(w.controller.running, isFalse);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('copy payload carries the summary + an honest loss row',
      (tester) async {
    final w = _wire();
    addTearDown(w.sink.close);
    await tester.pumpWidget(_host(PingPlotterScreen(controller: w.controller)));

    await tester.enterText(find.byType(TextField), '1.1.1.1');
    await tester.tap(find.text('Start plot'));
    await tester.pump();
    w.sink.add(_progress(1, 12));
    w.sink.add(_progress(2, null, error: 'timeout'));
    await tester.pump();

    await tester.tap(find.byType(AppCopyAction));
    await tester.pump();
    // AppCopyAction shows a transient "copied" confirmation on a ~1.5s timer;
    // let it elapse so no timer is pending when the widget tree disposes.
    await tester.pump(const Duration(seconds: 2));

    expect(clipboardWrites, isNotEmpty);
    final String text = clipboardWrites.single;
    expect(text, contains('Ping Plotter'));
    expect(text, contains('1.1.1.1'));
    expect(text, contains('1/2 replies'));
    expect(text, contains('50% loss'));
    // The lost sample row carries its honest reason word and an EMPTY RTT
    // column (the row ends right after "timeout"), never a fabricated 0 ms.
    expect(text, contains('timeout'));
    expect(text.trimRight().endsWith('timeout'), isTrue,
        reason: 'lost row ends with the reason word, no RTT value appended');
    // The landed row carries its real RTT; the lost row does not get one.
    expect(text, contains('reply\t12.0'));
    expect(text, isNot(contains('timeout\t')));
  });

  testWidgets('no overflow across standard widths', (tester) async {
    for (final double width in <double>[320, 390, 768, 1024]) {
      final w = _wire();
      await tester.pumpWidget(
        _host(
          // A fresh key per width forces a new State so the screen starts idle
          // each iteration (rather than reusing the prior running State).
          PingPlotterScreen(
            key: ValueKey<double>(width),
            controller: w.controller,
          ),
          size: Size(width, 900),
        ),
      );
      await tester.enterText(find.byType(TextField), 'host');
      await tester.tap(find.text('Start plot'));
      await tester.pump();
      w.sink.add(_progress(1, 12));
      w.sink.add(_progress(2, null));
      w.sink.add(_progress(3, 240));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
      await w.sink.close();
    }
  });

  testWidgets('dispose tears down with no exception', (tester) async {
    final w = _wire();
    addTearDown(w.sink.close);
    await tester.pumpWidget(_host(PingPlotterScreen(controller: w.controller)));
    await tester.enterText(find.byType(TextField), 'host');
    await tester.tap(find.text('Start plot'));
    await tester.pump();
    w.sink.add(_progress(1, 12));
    await tester.pump();

    // Navigate away → screen disposes → controller disposed.
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    // A late emission from the source must not blow up a disposed screen.
    w.sink.add(_progress(2, 20));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
