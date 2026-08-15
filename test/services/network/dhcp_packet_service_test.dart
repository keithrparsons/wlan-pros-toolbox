// Tests for DhcpPacketService.
//
// The primary fixture is REAL output captured from `ipconfig getpacket en0` on
// a macOS machine on 2026-08-15, not a hand-written approximation. If Apple
// changes the format, this test is what notices.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/dhcp_packet_service.dart';

/// Verbatim capture, macOS, 2026-08-15.
const String kRealPacket = '''
op = BOOTREPLY
htype = 1
flags = 0x0
hlen = 6
hops = 0
xid = 0x420b6590
secs = 0
ciaddr = 192.168.20.52
yiaddr = 192.168.20.52
siaddr = 0.0.0.0
giaddr = 0.0.0.0
chaddr = 66:22:dd:41:a9:d5
sname =
file =
options:
Options count is 7
dhcp_message_type (uint8): ACK 0x5
server_identifier (ip): 192.168.20.1
lease_time (uint32): 0x1fa40
subnet_mask (ip): 255.255.252.0
router (ip_mult): {192.168.20.1}
domain_name_server (ip_mult): {4.2.2.1}
end (none):
''';

void main() {
  group('parsePacket — real macOS capture', () {
    late final packet = DhcpPacketService.parsePacket(
      kRealPacket,
      interfaceName: 'en0',
    );

    test('parses and finds every option', () {
      expect(packet, isNotNull);
      // 7 printed, minus the `end` sentinel which is not an option.
      expect(packet!.options.length, 6);
      expect(packet.hasOptions, isTrue);
    });

    test('reads the header fields it needs', () {
      expect(packet!.yiaddr, '192.168.20.52');
      expect(packet.chaddr, '66:22:dd:41:a9:d5');
      expect(packet.interfaceName, 'en0');
    });

    test('maps names to the right RFC codes', () {
      expect(packet!.byCode(53)?.rawName, 'dhcp_message_type');
      expect(packet.byCode(54)?.rawValue, '192.168.20.1');
      expect(packet.byCode(1)?.rawValue, '255.255.252.0');
      expect(packet.byCode(3)?.rawValue, '{192.168.20.1}');
      expect(packet.byCode(6)?.rawValue, '{4.2.2.1}');
    });

    test('keeps the raw type token', () {
      expect(packet!.byCode(51)?.rawType, 'uint32');
      expect(packet.byCode(3)?.rawType, 'ip_mult');
    });

    test('decodes the hex lease time', () {
      // 0x1fa40 == 129600 == 1 day 12 hours, which is what NetViews shows.
      expect(packet!.leaseSeconds, 129600);
      expect(
        DhcpPacketService.formatLeaseDuration(packet.leaseSeconds),
        '129600 s (1 d 12 h)',
      );
    });

    test('supplies a display name for mapped codes', () {
      expect(packet!.byCode(51)?.displayName, 'IP Address Lease Time');
      expect(packet.byCode(51)?.isMapped, isTrue);
    });

    test('does not drop the end sentinel into the option list', () {
      expect(
        packet!.options.where((o) => o.rawName == 'end'),
        isEmpty,
      );
    });
  });

  group('parsePacket — honesty on unknown options', () {
    test('an unmapped name keeps its name and gets NO code', () {
      const String txt = '''
options:
Options count is 2
some_future_apple_option (uint8): 42
lease_time (uint32): 0xa8c0
end (none):
''';
      final packet = DhcpPacketService.parsePacket(txt, interfaceName: 'en0');
      expect(packet, isNotNull);
      final unknown = packet!.options.first;
      expect(unknown.rawName, 'some_future_apple_option');
      expect(unknown.code, isNull, reason: 'never guess an option number');
      expect(unknown.displayName, isNull);
      expect(unknown.isMapped, isFalse);
      expect(unknown.rawValue, '42');
    });
  });

  group('parsePacket — malformed input', () {
    test('returns null when there is no options block', () {
      expect(
        DhcpPacketService.parsePacket('op = BOOTREPLY\n', interfaceName: 'en0'),
        isNull,
      );
    });

    test('returns null on empty input', () {
      expect(DhcpPacketService.parsePacket('', interfaceName: 'en0'), isNull);
    });

    test('an options block with no options parses to an empty list', () {
      final packet = DhcpPacketService.parsePacket(
        'options:\nend (none):\n',
        interfaceName: 'en0',
      );
      expect(packet, isNotNull);
      expect(packet!.options, isEmpty);
      expect(packet.hasOptions, isFalse);
      expect(packet.leaseSeconds, isNull);
    });
  });

  group('leaseSeconds', () {
    test('is null when option 51 is absent', () {
      final packet = DhcpPacketService.parsePacket(
        'options:\nrouter (ip_mult): {10.0.0.1}\nend (none):\n',
        interfaceName: 'en0',
      );
      expect(packet!.leaseSeconds, isNull);
    });

    test('is null for a zero lease, never 0', () {
      final packet = DhcpPacketService.parsePacket(
        'options:\nlease_time (uint32): 0x0\nend (none):\n',
        interfaceName: 'en0',
      );
      expect(packet!.leaseSeconds, isNull);
    });

    test('accepts a decimal value as well as hex', () {
      final packet = DhcpPacketService.parsePacket(
        'options:\nlease_time (uint32): 3600\nend (none):\n',
        interfaceName: 'en0',
      );
      expect(packet!.leaseSeconds, 3600);
    });
  });

  group('formatLeaseDuration', () {
    test('null and non-positive yield null, never "0 s"', () {
      expect(DhcpPacketService.formatLeaseDuration(null), isNull);
      expect(DhcpPacketService.formatLeaseDuration(0), isNull);
      expect(DhcpPacketService.formatLeaseDuration(-1), isNull);
    });

    test('formats the common durations', () {
      expect(DhcpPacketService.formatLeaseDuration(45), '45 s (45 s)');
      expect(DhcpPacketService.formatLeaseDuration(3600), '3600 s (1 h)');
      expect(DhcpPacketService.formatLeaseDuration(86400), '86400 s (1 d)');
      expect(
        DhcpPacketService.formatLeaseDuration(129600),
        '129600 s (1 d 12 h)',
      );
      expect(
        DhcpPacketService.formatLeaseDuration(90061),
        '90061 s (1 d 1 h 1 m)',
      );
    });
  });

  group('platform gating', () {
    test('non-macOS reports unsupportedPlatform and never spawns', () async {
      var spawned = false;
      final svc = DhcpPacketService(
        isMacOsOverride: false,
        runProcess: (_, _) async {
          spawned = true;
          throw StateError('must not spawn');
        },
      );
      expect(svc.isSupportedPlatform, isFalse);
      expect(await svc.isAvailable(), isFalse);
      final r = await svc.read();
      expect(r.isSuccess, isFalse);
      expect(r.unavailable, DhcpPacketUnavailable.unsupportedPlatform);
      expect(spawned, isFalse);
    });

    test('a sandbox denial is reported as sandboxed, not as no lease', () async {
      final svc = DhcpPacketService(
        isMacOsOverride: true,
        runProcess: (String bin, List<String> args) async {
          if (args.isNotEmpty && args.first == 'getpacket') {
            throw const ProcessException('ipconfig', <String>[], 'denied', 1);
          }
          return ProcessResult(0, 0, 'interface: en0\n', '');
        },
      );
      final r = await svc.read(interfaceName: 'en0');
      expect(r.unavailable, DhcpPacketUnavailable.sandboxed);
    });

    test('empty output is reported as noLease', () async {
      final svc = DhcpPacketService(
        isMacOsOverride: true,
        runProcess: (_, _) async => ProcessResult(0, 1, '', ''),
      );
      final r = await svc.read(interfaceName: 'en0');
      expect(r.unavailable, DhcpPacketUnavailable.noLease);
    });

    test('unreadable output is unparseable, distinct from noLease', () async {
      final svc = DhcpPacketService(
        isMacOsOverride: true,
        runProcess: (_, _) async =>
            ProcessResult(0, 0, 'something entirely different\n', ''),
      );
      final r = await svc.read(interfaceName: 'en0');
      expect(r.unavailable, DhcpPacketUnavailable.unparseable);
    });

    test('a real packet round-trips through read()', () async {
      final svc = DhcpPacketService(
        isMacOsOverride: true,
        runProcess: (String bin, List<String> args) async {
          if (args.isNotEmpty && args.first == 'getpacket') {
            return ProcessResult(0, 0, kRealPacket, '');
          }
          return ProcessResult(0, 0, 'interface: en0\n', '');
        },
      );
      final r = await svc.read();
      expect(r.isSuccess, isTrue);
      expect(r.packet!.leaseSeconds, 129600);
      expect(r.packet!.interfaceName, 'en0');
    });
  });
}
