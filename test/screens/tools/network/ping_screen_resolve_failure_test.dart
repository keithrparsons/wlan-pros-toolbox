// TCP Ping screen — the honest resolve-failure path (parity with ICMP Ping).
//
// An unresolvable host must surface the "couldn't resolve" line and render NO
// packet-loss summary or replies card (no probe was sent, so _stats.sent == 0).
// The resolver is injected so no real DNS is touched, and the connector fails
// the test if it is ever called — a resolution failure must never reach a probe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_screen.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

/// A CurrentNetwork whose reader returns nothing (no gateway chip) immediately,
/// so the screen settles without touching a device.
CurrentNetwork _net() =>
    CurrentNetwork(reader: () async => (ip: null, mask: null, gateway: null));

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.dark(), home: child);

bool _anyTextContains(WidgetTester tester, String needle) => tester
    .widgetList<Text>(find.byType(Text))
    .any((Text t) => (t.data ?? '').contains(needle));

void main() {
  testWidgets(
    'an unresolvable host shows "couldn\'t resolve" and NO loss summary',
    (WidgetTester tester) async {
      final PingService svc = PingService(
        resolver: (String h) async => null, // cannot resolve any name
        connector: (host, port, {required Duration timeout}) async {
          fail('the connector must not be reached for an unresolvable name');
        },
      );

      await tester.pumpWidget(_wrap(PingScreen(service: svc, network: _net())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '192.168.1.b');
      await tester.tap(find.widgetWithText(FilledButton, 'Ping'));
      await tester.pumpAndSettle();

      // The honest resolve-failure line is shown.
      expect(_anyTextContains(tester, "Couldn't resolve"), isTrue);

      // No packet-loss summary and no replies card render (sent == 0). The
      // "% loss" token only ever appears in the Summary/stats card.
      expect(_anyTextContains(tester, '% loss'), isFalse);
      expect(find.text('Summary'), findsNothing);
      expect(find.text('Replies'), findsNothing);
    },
  );
}
