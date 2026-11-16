import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_service.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_verdict.dart';
import 'package:wlan_pros_toolbox/services/network/tcp_probe_classifier.dart';

void main() {
  group('tcpOutcomeFor', () {
    test('a RST is blocked, NOT an answer (unlike Ping)', () {
      expect(
        tcpOutcomeFor(TcpFailureReason.refused),
        TargetOutcome.didNotGetOut,
      );
    });

    test('timed out, unreachable and unknown are blocked', () {
      for (final TcpFailureReason r in <TcpFailureReason>[
        TcpFailureReason.timedOut,
        TcpFailureReason.unreachable,
        TcpFailureReason.unknown,
      ]) {
        expect(tcpOutcomeFor(r), TargetOutcome.didNotGetOut, reason: '$r');
      }
    });

    test('a lookup failure is no verdict, never blocked', () {
      expect(
        tcpOutcomeFor(TcpFailureReason.lookupFailure),
        TargetOutcome.noVerdict,
      );
    });
  });

  group('connectTcp against this machine', () {
    test('a listening port gets out', () async {
      final ServerSocket server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      expect(
        await connectTcp('127.0.0.1', server.port, const Duration(seconds: 2)),
        TargetOutcome.gotOut,
      );
    });

    test('a closed port answers with a RST and counts as blocked', () async {
      final ServerSocket server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = server.port;
      await server.close();
      expect(
        await connectTcp('127.0.0.1', port, const Duration(seconds: 2)),
        TargetOutcome.didNotGetOut,
      );
    });
  });

  group('PortCheckService.run', () {
    test('probes every TCP target and returns each outcome', () async {
      final List<String> asked = <String>[];
      final PortCheckService service = PortCheckService(
        udp: (PortCheckTarget t) async => TargetOutcome.gotOut,
        tcp: (String host, int port, Duration timeout) async {
          asked.add('$host:$port');
          return port == 22 ? TargetOutcome.didNotGetOut : TargetOutcome.gotOut;
        },
      );
      final Map<PortCheckTarget, TargetOutcome> r = await service.run();
      final List<PortCheckTarget> tcpTargets = kPortCheckTargets
          .where((PortCheckTarget t) => t.transport == PortCheckTransport.tcp)
          .toList();
      expect(asked.length, tcpTargets.length);
      for (final PortCheckTarget t in tcpTargets) {
        expect(
          r[t],
          t.port == 22 ? TargetOutcome.didNotGetOut : TargetOutcome.gotOut,
        );
      }
    });

    test('probes every UDP target through the UDP prober', () async {
      final List<String> asked = <String>[];
      final PortCheckService service = PortCheckService(
        tcp: (String host, int port, Duration timeout) async =>
            TargetOutcome.gotOut,
        udp: (PortCheckTarget t) async {
          asked.add('${t.host}:${t.port}');
          return t.udp == UdpProbeKind.stun
              ? TargetOutcome.didNotGetOut
              : TargetOutcome.gotOut;
        },
      );
      final Map<PortCheckTarget, TargetOutcome> r = await service.run();
      final List<PortCheckTarget> udpTargets = kPortCheckTargets
          .where((PortCheckTarget t) => t.transport == PortCheckTransport.udp)
          .toList();
      expect(asked.length, udpTargets.length);
      expect(r.length, kPortCheckTargets.length);
      for (final PortCheckTarget t in udpTargets) {
        expect(
          r[t],
          t.udp == UdpProbeKind.stun
              ? TargetOutcome.didNotGetOut
              : TargetOutcome.gotOut,
        );
      }
    });

    test('probes run at once, not one after another', () async {
      final PortCheckService service = PortCheckService(
        tcp: (String host, int port, Duration timeout) async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return TargetOutcome.gotOut;
        },
        udp: (PortCheckTarget t) async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          return TargetOutcome.gotOut;
        },
      );
      final Stopwatch sw = Stopwatch()..start();
      await service.run();
      // 22 targets at 150 ms each would be 3.3 s one after another.
      expect(sw.elapsedMilliseconds, lessThan(600));
    });

    test('hands each probe the 3 second timeout', () async {
      Duration? seen;
      final PortCheckService service = PortCheckService(
        tcp: (String host, int port, Duration timeout) async {
          seen = timeout;
          return TargetOutcome.gotOut;
        },
        udp: (PortCheckTarget t) async => TargetOutcome.gotOut,
      );
      await service.run();
      expect(seen, kPortCheckTcpTimeout);
      expect(kPortCheckTcpTimeout, const Duration(seconds: 3));
    });
  });
}
