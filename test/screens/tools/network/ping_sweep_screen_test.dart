// PingSweepScreen — copy honesty + responsive render.
//
// The copy assertion is the point. The blurb used to say "a host is listed when
// it answers a TCP handshake on port N". A RST is NOT a handshake, yet we DO
// (correctly) list refused hosts — a refusal proves the host answered. The old
// wording described behaviour the tool does not have, and it silently implied
// the opposite of the bug we just fixed (silent hosts were being listed too).
//
// The screen must now say plainly: the host is listed when it ANSWERS, by
// completing the handshake or by actively refusing; silence is not an answer.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_sweep_screen.dart';
import 'package:wlan_pros_toolbox/services/network/ping_sweep_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// Every probe times out — the DEAD case, in the shape the platform really
/// throws it (non-null osError, synthetic errno 110).
PingSweepService _deadService() => PingSweepService(
      connector: (String host, int port, {required Duration timeout}) async {
        throw const SocketException(
          'Connection timed out',
          osError: OSError('Connection timed out', 110),
        );
      },
    );

/// Every probe is REFUSED — the middlebox case. A host that RSTs is genuinely
/// alive and is correctly counted as answered, but the user must be able to see
/// that it answered with a refusal, not a listening service.
PingSweepService _refusingService() => PingSweepService(
      connector: (String host, int port, {required Duration timeout}) async {
        throw const SocketException(
          'Connection refused',
          osError: OSError('Connection refused', 61),
        );
      },
    );

Widget _app([PingSweepService? service]) => MaterialApp(
      theme: AppTheme.dark(),
      home: PingSweepScreen(service: service ?? _deadService()),
    );

/// Collect the text of every rendered Text widget.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .join(' | ');

/// Drive a real sweep over a small range and return the copy-report payload —
/// the thing that actually gets pasted into a ticket or an email.
Future<String> _runSweepAndCopy(
  WidgetTester tester,
  PingSweepService service, {
  String range = '10.99.99.1-4',
}) async {
  await tester.pumpWidget(_app(service));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, range);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Sweep'));
  await tester.pumpAndSettle();

  // The payload AppCopyAction would put on the clipboard — the permanent record.
  final AppCopyAction action =
      tester.widgetList<AppCopyAction>(find.byType(AppCopyAction)).single;
  return action.textBuilder() ?? '';
}

void main() {
  group('method blurb describes what the tool ACTUALLY does', () {
    testWidgets('says the host is listed when it ANSWERS, not "handshake"',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final String copy = _allText(tester);

      expect(copy, contains('ANSWERS'),
          reason: 'the listing criterion is an ANSWER, not a handshake');
      expect(copy, contains('actively'),
          reason: 'an active refusal is an answer and IS listed — say so');
      expect(copy, contains('Silence does not'),
          reason: 'silence is not an answer: a silent host is never listed');
      expect(copy, contains('not ICMP liveness'),
          reason: 'the honesty bar (GL-005) must survive the rewrite');

      expect(
        copy.contains('answers a TCP handshake on port'),
        isFalse,
        reason: 'the old wording claimed a handshake is the only listing '
            'criterion. A RST is not a handshake, and we list those hosts.',
      );
    });
  });

  group('responsive render — no overflow at any viewport', () {
    // The blurb got longer with the honest wording. Prove it wraps rather than
    // overflowing on the narrowest phone we support and on a desktop window.
    final Map<String, Size> viewports = <String, Size>{
      'mobile (iPhone SE)': const Size(320, 568),
      'tablet (iPad portrait)': const Size(768, 1024),
      'desktop': const Size(1440, 900),
    };

    viewports.forEach((String label, Size size) {
      testWidgets('renders clean at $label', (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_app());
        await tester.pumpAndSettle();

        // A RenderFlex overflow throws into the test's exception channel.
        expect(tester.takeException(), isNull, reason: '$label overflowed');
        expect(find.byType(PingSweepScreen), findsOneWidget);
      });
    });
  });

  group('copy report — the permanent record must define its own terms', () {
    // VERA'S KICKER. A middlebox that RSTs on behalf of every address in the
    // range yields a pasted report reading "254 of 254 hosts responded" — the
    // exact string that started this whole investigation — unless the report
    // says HOW they answered. The person reading a pasted report never saw the
    // screen. It has to stand on its own.
    testWidgets('all-refused does NOT paste as an undifferentiated "responded"',
        (WidgetTester tester) async {
      final String report =
          await _runSweepAndCopy(tester, _refusingService());

      expect(report, contains('4 of 4 hosts answered'));
      expect(
        report,
        contains('0 by completing the handshake, 4 by actively refusing'),
        reason: 'a wall of RSTs must be visible AS a wall of RSTs, not as four '
            'indistinguishable live hosts',
      );
      expect(report, contains('answered (refused)'),
          reason: 'the State column must name HOW the host answered');
      expect(report, isNot(contains('answered (handshake)')));

      // The Method line defines the term the summary uses.
      expect(report, contains('Method:'));
      expect(report, contains('an active refusal (RST) count'));
      expect(report, contains('Silence is not an answer'));
    });

    testWidgets('a dead range copies a tally of zero, and lists no hosts',
        (WidgetTester tester) async {
      final String report = await _runSweepAndCopy(tester, _deadService());

      expect(report, contains('0 of 4 hosts answered'));
      expect(report, isNot(contains('answered (refused)')));
      expect(report, isNot(contains('answered (handshake)')));
      expect(report, contains('Method:'));
    });

    testWidgets('the report still carries the ICMP-liveness caveat (GL-005)',
        (WidgetTester tester) async {
      final String report =
          await _runSweepAndCopy(tester, _refusingService());
      expect(report, contains('not ICMP liveness'));
      expect(report, contains('may still be up'));
    });
  });

  group('on-screen rows match the copied report (screenshot-text rule)', () {
    testWidgets('a refused host renders as "refused", not a bare green tick',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_refusingService()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '10.99.99.1-2');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Sweep'));
      await tester.pumpAndSettle();

      final String onScreen = _allText(tester);
      expect(onScreen, contains('refused'),
          reason: 'the screen must say the same thing the clipboard does');
      expect(find.byIcon(Icons.block), findsWidgets,
          reason: 'WCAG 1.4.1 — a distinct SHAPE per outcome, not a color swap');
    });
  });
}
