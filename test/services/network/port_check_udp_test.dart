import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_udp.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_verdict.dart';

Uint8List bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  group('DNS probe (RFC 1035)', () {
    final UdpProbeSpec spec = udpProbeFor(UdpProbeKind.dns);

    test('asks for the A record of google.com, recursion desired', () {
      final Uint8List p = spec.payload;
      expect(p[2], 0x01); // RD
      expect(p.sublist(4, 6), <int>[0, 1]); // one question
      expect(p.sublist(12), <int>[
        6,
        ...'google'.codeUnits,
        3,
        ...'com'.codeUnits,
        0,
        0,
        1,
        0,
        1,
      ]);
      expect(p.length, 28); // 12 header + 12 name + 4 type and class
    });

    test('accepts a response with our id, rejects another id or a query', () {
      final Uint8List reply = Uint8List.fromList(spec.payload)..[2] = 0x81;
      expect(spec.accepts(reply), isTrue);
      expect(spec.accepts(Uint8List.fromList(reply)..[0] ^= 0xff), isFalse);
      expect(spec.accepts(Uint8List.fromList(spec.payload)), isFalse);
      expect(spec.accepts(bytes(<int>[1, 2])), isFalse);
    });
  });

  group('NTP probe (RFC 4330)', () {
    final UdpProbeSpec spec = udpProbeFor(UdpProbeKind.ntp);

    test('sends the 48-byte client request', () {
      expect(spec.payload.length, 48);
      expect(spec.payload[0], 0x1B);
    });

    test('accepts a 48-byte server reply (mode 4), rejects the rest', () {
      expect(spec.accepts(Uint8List(48)..[0] = 0x24), isTrue);
      expect(spec.accepts(Uint8List(48)..[0] = 0x1B), isFalse);
      expect(spec.accepts(Uint8List(20)..[0] = 0x24), isFalse);
    });
  });

  group('STUN probe (RFC 5389)', () {
    final UdpProbeSpec spec = udpProbeFor(UdpProbeKind.stun);

    test('sends a 20-byte binding request with the magic cookie', () {
      final Uint8List p = spec.payload;
      expect(p.length, 20);
      expect(p.sublist(0, 4), <int>[0, 1, 0, 0]);
      expect(p.sublist(4, 8), <int>[0x21, 0x12, 0xA4, 0x42]);
    });

    test('accepts a reply that carries our transaction id', () {
      final Uint8List reply = Uint8List.fromList(spec.payload)..[1] = 0x01;
      reply[1] = 0x01;
      expect(spec.accepts(reply), isTrue);
      expect(spec.accepts(Uint8List.fromList(reply)..[19] ^= 0xff), isFalse);
      expect(spec.accepts(bytes(<int>[0, 1])), isFalse);
    });
  });

  group('QUIC probe (RFC 9000 and 8999)', () {
    final UdpProbeSpec spec = udpProbeFor(UdpProbeKind.quic);

    test('sends a 1200-byte long-header packet with a reserved version', () {
      final Uint8List p = spec.payload;
      expect(p.length, 1200);
      expect(p[0] & 0x80, 0x80);
      expect(p[1] & 0x0f, 0x0a); // 0x?a?a?a?a: reserved, forces negotiation
    });

    test('accepts a Version Negotiation reply, rejects other bytes', () {
      expect(
        spec.accepts(bytes(<int>[0xc7, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1])),
        isTrue,
      );
      expect(spec.accepts(bytes(<int>[0x47, 0, 0, 0, 0, 0, 0])), isFalse);
      expect(spec.accepts(bytes(<int>[0xc7, 0, 0, 0, 1, 0, 0])), isFalse);
    });
  });

  group('probeUdpAddress on loopback', () {
    late RawDatagramSocket server;
    final List<Uint8List> received = <Uint8List>[];

    Future<void> startServer({
      bool reply = false,
      int? replyFromOtherPort,
      Uint8List? replyBytes,
    }) async {
      server = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((RawSocketEvent e) {
        final Datagram? d = server.receive();
        if (d == null) return;
        received.add(d.data);
        final Uint8List out = replyBytes ?? d.data;
        if (reply) server.send(out, d.address, d.port);
        if (replyFromOtherPort != null) {
          RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0).then((
            RawDatagramSocket other,
          ) {
            other.send(out, d.address, d.port);
            Timer(const Duration(milliseconds: 50), other.close);
          });
        }
      });
    }

    setUp(received.clear);

    final UdpProbeSpec echoOk = UdpProbeSpec(
      Uint8List.fromList(<int>[1, 2, 3]),
      (Uint8List r) => r.length == 3,
    );
    const Duration resend = Duration(milliseconds: 100);
    const Duration window = Duration(milliseconds: 350);

    test(
      'a valid reply from the address and port we asked: gets out',
      () async {
        await startServer(reply: true);
        expect(
          await probeUdpAddress(
            InternetAddress.loopbackIPv4,
            server.port,
            echoOk,
            resendAfter: resend,
            window: window,
          ),
          TargetOutcome.gotOut,
        );
      },
    );

    test(
      'silence: the datagram is sent twice, then no verdict of out',
      () async {
        await startServer();
        expect(
          await probeUdpAddress(
            InternetAddress.loopbackIPv4,
            server.port,
            echoOk,
            resendAfter: resend,
            window: window,
          ),
          TargetOutcome.didNotGetOut,
        );
        expect(received.length, 2);
      },
    );

    test('a reply from a different port does not count', () async {
      await startServer(replyFromOtherPort: 1);
      expect(
        await probeUdpAddress(
          InternetAddress.loopbackIPv4,
          server.port,
          echoOk,
          resendAfter: resend,
          window: window,
        ),
        TargetOutcome.didNotGetOut,
      );
    });

    test('a reply the probe does not recognize does not count', () async {
      await startServer(reply: true, replyBytes: Uint8List(9));
      expect(
        await probeUdpAddress(
          InternetAddress.loopbackIPv4,
          server.port,
          echoOk,
          resendAfter: resend,
          window: window,
        ),
        TargetOutcome.didNotGetOut,
      );
    });
  });

  group('udpAddressFor', () {
    test('prefers an IPv4 address when there is one', () {
      expect(
        udpAddressFor(<InternetAddress>[
          InternetAddress('2606:4700::1111'),
          InternetAddress('1.1.1.1'),
        ])?.address,
        '1.1.1.1',
      );
    });

    test('falls back to IPv6 on an IPv6-only (NAT64) network', () {
      expect(
        udpAddressFor(<InternetAddress>[
          InternetAddress('64:ff9b::808:808'),
        ])?.address,
        '64:ff9b::808:808',
      );
    });

    test('nothing found is null', () {
      expect(udpAddressFor(<InternetAddress>[]), isNull);
    });
  });
}
