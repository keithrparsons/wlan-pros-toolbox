// PortCheckScreen: "What This Network Lets Out". Taps run it, opening runs
// nothing, words come from the ladder, no color-only state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/port_check_screen.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_service.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_verdict.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

class _FakeService extends PortCheckService {
  _FakeService({this.blockPort});

  final int? blockPort;
  int runs = 0;

  @override
  Future<Map<PortCheckTarget, TargetOutcome>> run() async {
    runs++;
    return <PortCheckTarget, TargetOutcome>{
      for (final PortCheckTarget t in kPortCheckTargets)
        t: t.port == blockPort && t.transport == PortCheckTransport.tcp
            ? TargetOutcome.didNotGetOut
            : TargetOutcome.gotOut,
    };
  }
}

class _GatedService extends PortCheckService {
  _GatedService(this.result);

  final Future<Map<PortCheckTarget, TargetOutcome>> result;

  @override
  Future<Map<PortCheckTarget, TargetOutcome>> run() => result;
}

Widget _wrap(
  PortCheckService service, {
  double width = 400,
  double textScale = 1,
  bool signInNeeded = false,
}) => MaterialApp(
  theme: AppTheme.dark(),
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 900),
      textScaler: TextScaler.linear(textScale),
    ),
    child: PortCheckScreen(service: service, signInNeeded: signInNeeded),
  ),
);

void main() {
  testWidgets('opening the screen runs nothing', (WidgetTester tester) async {
    final _FakeService service = _FakeService();
    await tester.pumpWidget(_wrap(service));
    await tester.pumpAndSettle();
    expect(service.runs, 0);
    expect(find.text('Run the check'), findsOneWidget);
    expect(find.textContaining('Looks fine'), findsNothing);
  });

  testWidgets('says what it will open before running', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(_FakeService()));
    expect(find.textContaining('well-known mail, SSH, DNS'), findsOneWidget);
  });

  testWidgets('the intro never claims nothing is sent', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(_FakeService()));
    expect(find.textContaining('no data'), findsNothing);
    expect(find.textContaining('small test packets'), findsOneWidget);
  });

  testWidgets('says Checking while it runs, then why Run again waits', (
    WidgetTester tester,
  ) async {
    final Completer<Map<PortCheckTarget, TargetOutcome>> gate =
        Completer<Map<PortCheckTarget, TargetOutcome>>();
    await tester.pumpWidget(_wrap(_GatedService(gate.future)));
    await tester.tap(find.text('Run the check'));
    await tester.pump();
    expect(find.text('Checking…'), findsOneWidget);
    gate.complete(<PortCheckTarget, TargetOutcome>{
      for (final PortCheckTarget t in kPortCheckTargets)
        t: TargetOutcome.gotOut,
    });
    await tester.pump();
    expect(find.text('Checking…'), findsNothing);
    expect(find.textContaining('again in a few seconds'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('again in a few seconds'), findsNothing);
  });

  testWidgets('a tap runs it and shows each group with a word and a glyph', (
    WidgetTester tester,
  ) async {
    final _FakeService service = _FakeService(blockPort: 22);
    await tester.pumpWidget(_wrap(service));
    await tester.tap(find.text('Run the check'));
    await tester.pumpAndSettle();
    expect(service.runs, 1);
    expect(find.text('Remote login (SSH)'), findsOneWidget);
    expect(find.text('Looks off'), findsOneWidget);
    expect(find.text('Looks fine'), findsWidgets);
    expect(find.text('Not checked'), findsOneWidget); // the VPN row
    expect(find.byIcon(Icons.error), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('Run again is disabled while running and for 10 seconds', (
    WidgetTester tester,
  ) async {
    final _FakeService service = _FakeService();
    await tester.pumpWidget(_wrap(service));
    await tester.tap(find.text('Run the check'));
    await tester.pump(const Duration(seconds: 1));
    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(find.text('Run again'), findsOneWidget);
    expect(button().onPressed, isNull);
    await tester.pump(const Duration(seconds: 9));
    expect(button().onPressed, isNotNull);
    await tester.tap(find.text('Run again'));
    await tester.pump();
    expect(service.runs, 2);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a sign-in network is not probed and says to sign in', (
    WidgetTester tester,
  ) async {
    final _FakeService service = _FakeService();
    await tester.pumpWidget(_wrap(service, signInNeeded: true));
    await tester.tap(find.text('Run the check'));
    await tester.pumpAndSettle();
    expect(service.runs, 0);
    expect(find.textContaining('Sign in, then run this again'), findsWidgets);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('no overflow at 320 px with 2x text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_FakeService(blockPort: 22), width: 320, textScale: 2),
    );
    await tester.tap(find.text('Run the check'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('each row reads as group, word, detail', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_FakeService(blockPort: 22)));
    await tester.tap(find.text('Run the check'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^Remote login \(SSH\), Looks off\.')),
      findsOneWidget,
    );
    handle.dispose();
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('Copy is disabled before a run and carries words after', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(_FakeService(blockPort: 22)));
    expect(
      tester.widget<AppCopyAction>(find.byType(AppCopyAction)).textBuilder(),
      isNull,
    );
    await tester.tap(find.text('Run the check'));
    await tester.pumpAndSettle();
    final String? text = tester
        .widget<AppCopyAction>(find.byType(AppCopyAction))
        .textBuilder();
    expect(text, isNotNull);
    expect(text, contains('Remote login (SSH): Looks off'));
    expect(text, contains('Websites and apps: Looks fine'));
    expect(text, contains('Port 22 did not get out'));
    expect(text, isNot(contains('—')));
    await tester.pump(const Duration(seconds: 10));
  });
}
