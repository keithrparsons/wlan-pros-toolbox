// Wave 2 prefill — the current-network suggestion wired into the networking
// tools. These widget tests pin the two things that make it HONEST rather than
// merely convenient:
//
//  1. The "Assumed /24" hint renders IFF the prefix was assumed (mask null) and
//     is ABSENT when the mask was measured. The label is the honesty contract —
//     an assumed /24 shown as measured is the small lie the 1.7.1 audit removed
//     ([[feedback_unsourced_is_not_invalid]]). Pinned both directions.
//  2. The prefill is a SUGGESTION, not a lock: a value the user has typed is
//     never overwritten by a late-arriving suggestion.
//
// The suggestion is injected via a stub CurrentNetwork reader, so nothing here
// touches network_info_plus or a real device.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_sweep_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/port_scan_screen.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';
import 'package:wlan_pros_toolbox/services/network/ping_sweep_service.dart';
import 'package:wlan_pros_toolbox/services/network/port_scan_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/gateway_target_chip.dart';

/// A CurrentNetwork whose reader returns a fixed ip/mask/gateway immediately.
CurrentNetwork _net({String? ip, String? mask, String? gateway}) =>
    CurrentNetwork(reader: () async => (ip: ip, mask: mask, gateway: gateway));

/// A CurrentNetwork whose reader resolves after a delay — used to prove a
/// late-arriving suggestion never clobbers a value the user already typed.
CurrentNetwork _slowNet({
  String? ip,
  String? mask,
  String? gateway,
  Duration delay = const Duration(milliseconds: 50),
}) =>
    CurrentNetwork(
      reader: () async {
        await Future<void>.delayed(delay);
        return (ip: ip, mask: mask, gateway: gateway);
      },
    );

/// A ping-sweep service whose probes all time out — so a sweep never opens a
/// socket. The prefill tests never run a sweep, but the screen needs a service.
PingSweepService _sweepService() => PingSweepService(
      connector: (String host, int port, {required Duration timeout}) async {
        throw const SocketException(
          'Connection timed out',
          osError: OSError('Connection timed out', 110),
        );
      },
    );

String _subnetText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

Widget _wrap(Widget screen) => MaterialApp(theme: AppTheme.dark(), home: screen);

bool _hasText(WidgetTester tester, String needle) => tester
    .widgetList<Text>(find.byType(Text))
    .any((Text t) => (t.data ?? '').contains(needle));

void main() {
  group('Ping Sweep — honest prefill of the real subnet', () {
    testWidgets('BEST: a real mask prefills the MEASURED CIDR with NO '
        '"assumed" hint', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingSweepScreen(
        service: _sweepService(),
        network: _net(ip: '172.19.0.37', mask: '255.255.255.0'),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '172.19.0.0/24',
          reason: 'the generic default is replaced by the real subnet');
      expect(_hasText(tester, 'Assumed /24'), isFalse,
          reason: 'a measured CIDR must NOT claim to be an assumption — but '
              'must also never wear the "assumed" label a guess would');
    });

    testWidgets('PARTIAL: mask null prefills an assumed /24 AND renders the '
        '"Assumed /24" hint', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingSweepScreen(
        service: _sweepService(),
        network: _net(ip: '172.19.5.8', mask: null),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '172.19.5.0/24');
      expect(_hasText(tester, 'Assumed /24'), isTrue,
          reason: 'the honesty contract: a guessed prefix says it is a guess');
    });

    testWidgets('NONE: no device network leaves the generic default and shows '
        'no hint', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingSweepScreen(
        service: _sweepService(),
        network: _net(ip: null, mask: null),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '192.168.1.0/24',
          reason: 'no measurement → keep the honest generic default');
      expect(_hasText(tester, 'Assumed /24'), isFalse);
    });

    testWidgets('the hint NEVER appears for a measured /23 (measured is '
        'measured, even when it is not a /24)', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingSweepScreen(
        service: _sweepService(),
        network: _net(ip: '10.5.7.8', mask: '255.255.254.0'),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '10.5.6.0/23');
      expect(_hasText(tester, 'Assumed /24'), isFalse);
    });

    testWidgets('SUGGESTION NOT A LOCK: a value the user typed is never '
        'overwritten by a late suggestion', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingSweepScreen(
        service: _sweepService(),
        network: _slowNet(ip: '172.19.0.37', mask: '255.255.255.0'),
      )));
      await tester.pump(); // initState fired; suggestion still pending.

      await tester.enterText(find.byType(TextField).first, '10.0.0.0/16');
      await tester.pump(const Duration(milliseconds: 100)); // suggestion lands.
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '10.0.0.0/16',
          reason: 'the user typed first — the prefill must yield');
    });
  });

  group('Port Scan — prefill the gateway, fall back to the device IP', () {
    testWidgets('prefills the gateway as the first scan target', (tester) async {
      await tester.pumpWidget(_wrap(PortScanScreen(
        service: PortScanService(),
        network: _net(
          ip: '192.168.1.50',
          mask: '255.255.255.0',
          gateway: '192.168.1.1',
        ),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '192.168.1.1');
    });

    testWidgets('falls back to the device IP when no gateway is known',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PortScanScreen(
        service: PortScanService(),
        network: _net(ip: '192.168.1.50', mask: '255.255.255.0'),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '192.168.1.50');
    });

    testWidgets('NONE leaves the host field empty (no fabrication)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PortScanScreen(
        service: PortScanService(),
        network: _net(ip: null, mask: null),
      )));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '');
    });

    testWidgets('a user-typed host is never overwritten by a late suggestion',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PortScanScreen(
        service: PortScanService(),
        network: _slowNet(ip: '192.168.1.50', gateway: '192.168.1.1'),
      )));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'example.com');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), 'example.com');
    });
  });

  group('Ping — offer the gateway as a one-tap target (chip, not a lock)', () {
    testWidgets('the gateway chip appears and fills the field when tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingScreen(
        service: PingService(),
        network: _net(
          ip: '192.168.1.50',
          mask: '255.255.255.0',
          gateway: '192.168.1.1',
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(GatewayTargetChip), findsOneWidget);
      expect(_hasText(tester, 'Gateway 192.168.1.1'), isTrue);

      await tester.tap(find.byType(GatewayTargetChip));
      await tester.pumpAndSettle();

      expect(_subnetText(tester), '192.168.1.1');
      expect(find.byType(GatewayTargetChip), findsNothing,
          reason: 'once the target is set, the offer withdraws');
    });

    testWidgets('no gateway → no chip (nothing to offer, nothing fabricated)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingScreen(
        service: PingService(),
        network: _net(ip: null, mask: null),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(GatewayTargetChip), findsNothing);
    });

    testWidgets('the chip withdraws once the user types their own target',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(PingScreen(
        service: PingService(),
        network: _slowNet(
          ip: '192.168.1.50',
          gateway: '192.168.1.1',
        ),
      )));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '1.1.1.1');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(GatewayTargetChip), findsNothing);
      expect(_subnetText(tester), '1.1.1.1');
    });
  });
}
