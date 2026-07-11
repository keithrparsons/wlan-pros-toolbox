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

Widget _app() => MaterialApp(
      theme: AppTheme.dark(),
      home: PingSweepScreen(service: _deadService()),
    );

/// Collect the text of every rendered Text widget.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .join(' | ');

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
}
