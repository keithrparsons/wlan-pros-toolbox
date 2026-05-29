// WakeOnLanService unit tests — MAC normalization across formats, magic-packet
// byte construction, broadcast/port validation, and the fire-and-forget send
// contract, all with a fake sender so no real UDP datagrams leave the host.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/wake_on_lan_service.dart';

void main() {
  group('normalizeMac', () {
    test('accepts colon-separated', () {
      expect(
        WakeOnLanService.normalizeMac('AA:BB:CC:DD:EE:FF'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('accepts hyphen-separated', () {
      expect(
        WakeOnLanService.normalizeMac('aa-bb-cc-dd-ee-ff'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('accepts no-separator', () {
      expect(
        WakeOnLanService.normalizeMac('AABBCCDDEEFF'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('accepts Cisco dotted form', () {
      expect(
        WakeOnLanService.normalizeMac('aabb.ccdd.eeff'),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(
        WakeOnLanService.normalizeMac('  aa:bb:cc:dd:ee:ff  '),
        'aa:bb:cc:dd:ee:ff',
      );
    });

    test('rejects too few bytes', () {
      expect(WakeOnLanService.normalizeMac('AA:BB:CC:DD:EE'), isNull);
    });

    test('rejects too many bytes', () {
      expect(WakeOnLanService.normalizeMac('AABBCCDDEEFF00'), isNull);
    });

    test('rejects non-hex characters', () {
      expect(WakeOnLanService.normalizeMac('GG:BB:CC:DD:EE:FF'), isNull);
    });

    test('rejects empty input', () {
      expect(WakeOnLanService.normalizeMac(''), isNull);
    });
  });

  group('buildMagicPacket', () {
    test('is exactly 102 bytes', () {
      final List<int> p =
          WakeOnLanService.buildMagicPacket('aa:bb:cc:dd:ee:ff');
      expect(p.length, 102);
    });

    test('starts with six 0xFF bytes', () {
      final List<int> p =
          WakeOnLanService.buildMagicPacket('01:02:03:04:05:06');
      expect(p.sublist(0, 6), <int>[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
    });

    test('repeats the MAC 16 times after the header', () {
      const List<int> mac = <int>[0x01, 0x02, 0x03, 0x04, 0x05, 0x06];
      final List<int> p =
          WakeOnLanService.buildMagicPacket('01:02:03:04:05:06');
      for (int rep = 0; rep < 16; rep++) {
        final int start = 6 + rep * 6;
        expect(p.sublist(start, start + 6), mac);
      }
    });

    test('accepts any MAC format and produces identical bytes', () {
      final List<int> a =
          WakeOnLanService.buildMagicPacket('AA-BB-CC-DD-EE-FF');
      final List<int> b = WakeOnLanService.buildMagicPacket('aabbccddeeff');
      expect(a, b);
    });

    test('throws on an invalid MAC', () {
      expect(
        () => WakeOnLanService.buildMagicPacket('nope'),
        throwsArgumentError,
      );
    });
  });

  group('packetHex', () {
    test('renders 204 hex chars (102 bytes) starting with twelve f', () {
      final List<int> p =
          WakeOnLanService.buildMagicPacket('aa:bb:cc:dd:ee:ff');
      final String hex = WakeOnLanService.packetHex(p);
      expect(hex.length, 204);
      expect(hex.startsWith('ffffffffffff'), isTrue);
    });
  });

  group('wake', () {
    test('sends to the default broadcast/port and reports bytes sent',
        () async {
      late InternetAddress dest;
      late int port;
      late int len;
      final WakeOnLanService svc = WakeOnLanService(
        sender: (List<int> packet, InternetAddress d, int p) async {
          dest = d;
          port = p;
          len = packet.length;
          return packet.length;
        },
      );
      final WakeOnLanResult r = await svc.wake(rawMac: 'AABBCCDDEEFF');
      expect(r.isError, isFalse);
      expect(r.normalizedMac, 'aa:bb:cc:dd:ee:ff');
      expect(r.broadcast, '255.255.255.255');
      expect(r.port, 9);
      expect(r.bytesSent, 102);
      expect(dest.address, '255.255.255.255');
      expect(port, 9);
      expect(len, 102);
    });

    test('honors a custom subnet broadcast and port 7', () async {
      final WakeOnLanService svc = WakeOnLanService(
        sender: (List<int> packet, InternetAddress d, int p) async =>
            packet.length,
      );
      final WakeOnLanResult r = await svc.wake(
        rawMac: 'aa:bb:cc:dd:ee:ff',
        rawBroadcast: '192.168.1.255',
        port: 7,
      );
      expect(r.isError, isFalse);
      expect(r.broadcast, '192.168.1.255');
      expect(r.port, 7);
    });

    test('invalid MAC is a clear validation error, no send', () async {
      bool sent = false;
      final WakeOnLanService svc = WakeOnLanService(
        sender: (List<int> packet, InternetAddress d, int p) async {
          sent = true;
          return packet.length;
        },
      );
      final WakeOnLanResult r = await svc.wake(rawMac: 'zz:zz');
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('valid MAC'));
      expect(sent, isFalse);
    });

    test('invalid broadcast address is rejected', () async {
      final WakeOnLanService svc = WakeOnLanService(
        sender: (List<int> packet, InternetAddress d, int p) async =>
            packet.length,
      );
      final WakeOnLanResult r = await svc.wake(
        rawMac: 'aa:bb:cc:dd:ee:ff',
        rawBroadcast: '999.1.1.1',
      );
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('Broadcast address'));
    });

    test('out-of-range port is rejected', () async {
      final WakeOnLanService svc = WakeOnLanService(
        sender: (List<int> packet, InternetAddress d, int p) async =>
            packet.length,
      );
      final WakeOnLanResult r = await svc.wake(
        rawMac: 'aa:bb:cc:dd:ee:ff',
        port: 70000,
      );
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('Port'));
    });

    test('zero bytes sent surfaces as a failure, not a fake success',
        () async {
      final WakeOnLanService svc = WakeOnLanService(
        sender: (List<int> packet, InternetAddress d, int p) async => 0,
      );
      final WakeOnLanResult r = await svc.wake(rawMac: 'aa:bb:cc:dd:ee:ff');
      expect(r.isError, isTrue);
      expect(r.errorMessage, contains('0 bytes'));
    });
  });
}
