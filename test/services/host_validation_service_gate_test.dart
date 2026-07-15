// Host/IP format validation at the SERVICE boundary — SSL Inspect, NTP, and
// Packet Sender each now reject a malformed host BEFORE opening a socket, so a
// typo produces an honest "not a valid host or IP" message instead of a
// confusing connection failure (the 2026-07-14 user report).
//
// Each service exposes an injectable transport seam. The tests assert the seam
// is NEVER touched for a malformed host — proving validation short-circuits the
// I/O, with no real network. RED before the wiring (the service passed the
// empty-only check and dialed out); GREEN after.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ntp_service.dart';
import 'package:wlan_pros_toolbox/services/network/packet_sender_service.dart';
import 'package:wlan_pros_toolbox/services/network/ssl_inspect_service.dart';

void main() {
  group('SslInspectService.inspect — malformed host, no connect', () {
    test('an out-of-range octet is rejected before any connect', () async {
      bool connected = false;
      final SslInspectService svc = SslInspectService(
        connector: (host, port, {required timeout}) async {
          connected = true;
          throw StateError('should not connect');
        },
      );
      final SslInspectResult r = await svc.inspect(rawHost: '192.168.1.256');
      expect(r.isError, isTrue);
      expect(connected, isFalse, reason: 'validation must precede the socket');
    });

    test('a double-dot host is rejected before any connect', () async {
      bool connected = false;
      final SslInspectService svc = SslInspectService(
        connector: (host, port, {required timeout}) async {
          connected = true;
          throw StateError('should not connect');
        },
      );
      final SslInspectResult r = await svc.inspect(rawHost: '192.168..1');
      expect(r.isError, isTrue);
      expect(connected, isFalse);
    });

    test('a well-formed host still reaches the connector', () async {
      bool connected = false;
      final SslInspectService svc = SslInspectService(
        connector: (host, port, {required timeout}) async {
          connected = true;
          throw StateError('reached connector'); // stop before real TLS
        },
      );
      await svc.inspect(rawHost: 'example.com');
      expect(connected, isTrue, reason: 'legitimate input must not be blocked');
    });
  });

  group('NtpService.query — malformed server, no exchange', () {
    test('a pasted URL scheme is rejected before the SNTP exchange', () async {
      bool exchanged = false;
      final NtpService svc = NtpService(
        exchange: (host, port, timeout) async {
          exchanged = true;
          throw StateError('should not exchange');
        },
      );
      final NtpResult r = await svc.query(server: 'http://host');
      expect(r.isError, isTrue);
      expect(exchanged, isFalse);
    });

    test('an out-of-range octet is rejected before the exchange', () async {
      bool exchanged = false;
      final NtpService svc = NtpService(
        exchange: (host, port, timeout) async {
          exchanged = true;
          throw StateError('should not exchange');
        },
      );
      final NtpResult r = await svc.query(server: '10.0.0.256');
      expect(r.isError, isTrue);
      expect(exchanged, isFalse);
    });

    test('a well-formed server still reaches the exchange', () async {
      bool exchanged = false;
      final NtpService svc = NtpService(
        exchange: (host, port, timeout) async {
          exchanged = true;
          throw StateError('reached exchange');
        },
      );
      await svc.query(server: 'time.apple.com');
      expect(exchanged, isTrue);
    });
  });

  group('PacketSenderService.send — malformed host, no connect', () {
    test('an out-of-range octet is rejected before the TCP connect', () async {
      bool connected = false;
      final PacketSenderService svc = PacketSenderService(
        tcpConnector: (host, port, {required timeout}) async {
          connected = true;
          throw const SocketException('should not connect');
        },
      );
      final PacketResult r = await svc.send(
        transport: PacketTransport.tcp,
        host: '192.168.1.256',
        port: 80,
        payload: const <int>[0],
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, PacketErrorKind.invalidInput);
      expect(connected, isFalse);
    });

    test('a well-formed host still reaches the connector', () async {
      bool connected = false;
      final PacketSenderService svc = PacketSenderService(
        tcpConnector: (host, port, {required timeout}) async {
          connected = true;
          throw const SocketException('reached connector');
        },
      );
      await svc.send(
        transport: PacketTransport.tcp,
        host: '192.168.1.1',
        port: 80,
        payload: const <int>[0],
      );
      expect(connected, isTrue);
    });
  });
}
