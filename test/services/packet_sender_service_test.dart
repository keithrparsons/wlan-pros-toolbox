// PacketSenderService unit tests — payload parsing (text + hex escapes), and
// TCP/UDP round-trips against in-process echo servers on 127.0.0.1, plus the
// refused/timeout/DNS-failure typed-error paths. No external network is touched.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/packet_sender_service.dart';

void main() {
  group('parsePayload', () {
    test('plain text to its UTF-8 bytes', () {
      expect(PacketSenderService.parsePayload('AB'), <int>[0x41, 0x42]);
    });

    test('hex escapes', () {
      expect(PacketSenderService.parsePayload(r'\x00\xff\x41'),
          <int>[0x00, 0xFF, 0x41]);
    });

    test('common escapes r n t 0 backslash', () {
      expect(PacketSenderService.parsePayload(r'\r\n\t\0\\'),
          <int>[0x0D, 0x0A, 0x09, 0x00, 0x5C]);
    });

    test('mixed text + hex (an HTTP request line)', () {
      expect(PacketSenderService.parsePayload(r'GET /\r\n'),
          'GET /'.codeUnits + <int>[0x0D, 0x0A]);
    });

    test('bad hex escape is rejected with null', () {
      expect(PacketSenderService.parsePayload(r'\xZZ'), isNull);
      expect(PacketSenderService.parsePayload(r'\x0'), isNull);
    });

    test('empty payload is an empty byte list, not null', () {
      expect(PacketSenderService.parsePayload(''), <int>[]);
    });
  });

  group('toHex / decodeText', () {
    test('hex dump is two digits per byte', () {
      expect(PacketSenderService.toHex(<int>[0x0D, 0x0A, 0xFF]), '0d0aff');
    });
    test('decode tolerates malformed bytes', () {
      expect(PacketSenderService.decodeText(<int>[0x41, 0xFF]), startsWith('A'));
    });
  });

  group('TCP round-trip', () {
    late ServerSocket server;
    late int port;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((Socket socket) {
        socket.listen(
          (data) {
            socket.add(data);
            socket.flush().then((_) => socket.destroy());
          },
          onError: (_) => socket.destroy(),
        );
      });
    });

    tearDown(() async {
      await server.close();
    });

    test('payload is echoed back over TCP', () async {
      final PacketSenderService svc = PacketSenderService();
      final PacketResult r = await svc.send(
        transport: PacketTransport.tcp,
        host: '127.0.0.1',
        port: port,
        payload: 'ping'.codeUnits,
        timeout: const Duration(seconds: 2),
      );
      expect(r.isError, isFalse);
      expect(r.bytesSent, 4);
      expect(PacketSenderService.decodeText(r.received), 'ping');
    });
  });

  group('TCP error paths', () {
    test('connection refused to typed refused error', () async {
      final ServerSocket s =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int deadPort = s.port;
      await s.close();

      final PacketSenderService svc = PacketSenderService();
      final PacketResult r = await svc.send(
        transport: PacketTransport.tcp,
        host: '127.0.0.1',
        port: deadPort,
        payload: 'x'.codeUnits,
        timeout: const Duration(milliseconds: 500),
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, PacketErrorKind.refused);
    });

    // THE case that matters: Dart's own connect-timeout carries a NON-null
    // osError with the synthetic errno 110. This fake used to throw
    // `SocketException('timed out')` with a NULL osError — a shape no platform
    // produces. It passed via the message fallback, so it was green AND
    // vacuous: it exercised a branch real hardware never takes, and gave zero
    // coverage of the one errno that caused the whole class defect.
    test('connect timeout (Connection timed out, errno 110) → typed timeout',
        () async {
      final PacketSenderService svc = PacketSenderService(
        tcpConnector: (host, port, {required timeout}) async {
          await Future<void>.delayed(timeout);
          throw const SocketException(
            'Connection timed out',
            osError: OSError('Connection timed out', 110),
          );
        },
      );
      final PacketResult r = await svc.send(
        transport: PacketTransport.tcp,
        host: '10.255.255.1',
        port: 9,
        payload: 'x'.codeUnits,
        timeout: const Duration(milliseconds: 80),
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, PacketErrorKind.timeout,
          reason: 'errno 110 is a TIMEOUT, not a generic "other" error. Before '
              'the classifier, the timeout branch was gated on '
              '`os == null && elapsed >= timeout - 50ms` and could NEVER fire.');
      expect(r.timedOut, isTrue);
    });

    test('a dead host never reports as refused (110 is not 61)', () async {
      // The inverse guard: a timeout must not be promoted into "refused",
      // which would imply the host answered.
      final PacketSenderService svc = PacketSenderService(
        tcpConnector: (host, port, {required timeout}) async {
          throw const SocketException(
            'Connection timed out',
            osError: OSError('Connection timed out', 110),
          );
        },
      );
      final PacketResult r = await svc.send(
        transport: PacketTransport.tcp,
        host: '10.255.255.1',
        port: 9,
        payload: 'x'.codeUnits,
        timeout: const Duration(milliseconds: 80),
      );
      expect(r.errorKind, isNot(PacketErrorKind.refused));
      expect(r.errorKind, PacketErrorKind.timeout);
    });

    test('unreachable and lookup failures get their own typed kinds', () async {
      Future<PacketResult> sendWith(SocketException e) {
        final PacketSenderService svc = PacketSenderService(
          tcpConnector: (host, port, {required timeout}) async => throw e,
        );
        return svc.send(
          transport: PacketTransport.tcp,
          host: 'target.invalid',
          port: 9,
          payload: 'x'.codeUnits,
          timeout: const Duration(milliseconds: 80),
        );
      }

      final PacketResult unreachable = await sendWith(const SocketException(
        'No route to host',
        osError: OSError('No route to host', 65),
      ));
      expect(unreachable.errorKind, PacketErrorKind.unreachable);

      final PacketResult dns = await sendWith(
        const SocketException('Failed host lookup: target.invalid'),
      );
      expect(dns.errorKind, PacketErrorKind.dnsFailure);
    });
  });

  group('UDP round-trip + no-reply', () {
    late RawDatagramSocket echo;
    late int port;
    StreamSubscription<RawSocketEvent>? echoSub;

    setUp(() async {
      echo = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = echo.port;
      echoSub = echo.listen((RawSocketEvent ev) {
        if (ev == RawSocketEvent.read) {
          final Datagram? dg = echo.receive();
          if (dg != null) {
            echo.send(dg.data, dg.address, dg.port);
          }
        }
      });
    });

    tearDown(() async {
      await echoSub?.cancel();
      echo.close();
    });

    test('datagram is echoed back over UDP', () async {
      final PacketSenderService svc = PacketSenderService();
      final PacketResult r = await svc.send(
        transport: PacketTransport.udp,
        host: '127.0.0.1',
        port: port,
        payload: <int>[1, 2, 3, 4],
        timeout: const Duration(seconds: 2),
      );
      expect(r.isError, isFalse);
      expect(r.bytesSent, 4);
      expect(r.received, <int>[1, 2, 3, 4]);
      expect(r.isNoReply, isFalse);
    });

    test('no listener to UDP no-reply is a clean non-error outcome', () async {
      await echoSub?.cancel();
      echo.close();

      final PacketSenderService svc = PacketSenderService();
      final PacketResult r = await svc.send(
        transport: PacketTransport.udp,
        host: '127.0.0.1',
        port: port,
        payload: <int>[9],
        timeout: const Duration(milliseconds: 300),
      );
      expect(r.isError, isFalse);
      expect(r.received, isEmpty);
      expect(r.timedOut, isTrue);
      expect(r.isNoReply, isTrue);
    });
  });

  group('input validation', () {
    test('empty host is rejected before any I/O', () async {
      final PacketSenderService svc = PacketSenderService();
      final PacketResult r = await svc.send(
        transport: PacketTransport.tcp,
        host: '   ',
        port: 80,
        payload: const <int>[],
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, PacketErrorKind.invalidInput);
    });

    test('out-of-range port is rejected', () async {
      final PacketSenderService svc = PacketSenderService();
      final PacketResult r = await svc.send(
        transport: PacketTransport.udp,
        host: '127.0.0.1',
        port: 70000,
        payload: const <int>[],
      );
      expect(r.isError, isTrue);
      expect(r.errorKind, PacketErrorKind.invalidInput);
    });
  });
}
