// The router hint in Ping (TCP), Ping (ICMP) and Ping Plotter: when the target
// is the device's gateway and every ping goes unanswered, a plain note says
// many routers ignore pings sent to themselves and points at Traceroute.
// Services and the gateway reader are faked, so no network is touched.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/icmp_ping_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_plotter_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/ping_screen.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';
import 'package:wlan_pros_toolbox/services/network/icmp_service.dart';
import 'package:wlan_pros_toolbox/services/network/ping_plot_controller.dart';
import 'package:wlan_pros_toolbox/services/network/ping_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/router_note.dart';

const String _gateway = '192.168.1.1';

CurrentNetwork _net() => CurrentNetwork(
  reader: () async =>
      (ip: '192.168.1.42', mask: '255.255.255.0', gateway: _gateway),
);

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

/// Every TCP connect times out: the target never answers.
PingService _silentTcp() => PingService(
  connector: (host, port, {required Duration timeout}) async =>
      throw TimeoutException('no answer', timeout),
);

/// ICMP backend where every echo times out.
class _SilentIcmpBackend implements IcmpBackend {
  const _SilentIcmpBackend();

  @override
  Stream<IcmpReply> echo({
    required String host,
    required int count,
    required Duration interval,
    required Duration timeout,
    int? ttl,
    Future<void>? cancel,
  }) => Stream<IcmpReply>.fromIterable(<IcmpReply>[
    for (int i = 1; i <= count; i++)
      IcmpReply(sequence: i, success: false, errorLabel: 'timeout'),
  ]);
}

void main() {
  group('Ping (TCP)', () {
    Future<void> ping(WidgetTester tester, String target) async {
      await tester.pumpWidget(
        _wrap(PingScreen(service: _silentTcp(), network: _net())),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, target);
      await tester.tap(find.widgetWithText(FilledButton, 'Ping'));
      await tester.pumpAndSettle();
    }

    testWidgets('router that never answers: shows the router note', (
      tester,
    ) async {
      await ping(tester, _gateway);
      expect(find.text(routerIgnoresPingNote), findsOneWidget);
    });

    testWidgets('another host that never answers: no router note', (
      tester,
    ) async {
      await ping(tester, '203.0.113.9');
      expect(find.text(routerIgnoresPingNote), findsNothing);
    });
  });

  group('Ping (ICMP)', () {
    Future<void> ping(WidgetTester tester, String target) async {
      await tester.pumpWidget(
        _wrap(
          IcmpPingScreen(
            service: IcmpService(
              platformOverride: 'android',
              isWebOverride: false,
              backend: const _SilentIcmpBackend(),
            ),
            network: _net(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, target);
      await tester.tap(find.widgetWithText(FilledButton, 'Ping'));
      await tester.pumpAndSettle();
    }

    testWidgets('router that never answers: shows the router note', (
      tester,
    ) async {
      await ping(tester, _gateway);
      expect(find.text(routerIgnoresPingNote), findsOneWidget);
    });

    testWidgets('another host that never answers: no router note', (
      tester,
    ) async {
      await ping(tester, '203.0.113.9');
      expect(find.text(routerIgnoresPingNote), findsNothing);
    });
  });

  group('Ping Plotter', () {
    Future<void> plot(WidgetTester tester, String target) async {
      final StreamController<PingProgress> sink =
          StreamController<PingProgress>.broadcast();
      final PingPlotController controller = PingPlotController(
        pingStreamFactory:
            ({
              required String host,
              required int port,
              required Duration interval,
              required Duration timeout,
              Future<void>? cancel,
            }) => sink.stream,
      );
      await tester.pumpWidget(
        _wrap(PingPlotterScreen(controller: controller, network: _net())),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), target);
      await tester.tap(find.text('Start plot'));
      await tester.pump();
      for (int i = 1; i <= 3; i++) {
        sink.add(
          PingProgress(
            reply: PingReply(
              sequence: i,
              success: false,
              errorLabel: 'timeout',
            ),
            stats: PingStats.empty,
          ),
        );
      }
      await tester.pump();
      await tester.pump();
    }

    testWidgets('router that never answers: shows the router note', (
      tester,
    ) async {
      await plot(tester, _gateway);
      expect(find.text(routerIgnoresPingNote), findsOneWidget);
    });

    testWidgets('another host that never answers: no router note', (
      tester,
    ) async {
      await plot(tester, '203.0.113.9');
      expect(find.text(routerIgnoresPingNote), findsNothing);
    });
  });
}
