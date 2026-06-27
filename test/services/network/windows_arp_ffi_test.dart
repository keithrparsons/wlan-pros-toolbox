// Pure-logic tests for the Windows ARP FFI reader (windows_arp_ffi.dart) and
// the WindowsIpNetTableArpReader mapping (arp_reader.dart). These exercise only
// the pure Dart — IP/MAC formatting and the IP→MAC → ArpReadResult mapping — so
// they run on macOS CI even though the FFI body that reads iphlpapi.dll cannot.
// `DynamicLibrary.open('iphlpapi.dll')` is a lazy top-level final resolved only
// on the first real FFI read, which these tests never trigger (the reader is
// driven by an injected fake), so importing the module is safe off Windows.
//
// feat/windows-arp-enrichment. This locks the network-byte-order IPv4 decode,
// the lowercase-colon MAC formatting + all-zero/short honesty, and the
// available/unavailable framing of the reader, so a regression is caught here
// rather than only on a Windows box.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/arp_reader.dart';
import 'package:wlan_pros_toolbox/services/network/windows_arp_ffi.dart';

void main() {
  group('ipv4FromNetworkOrder — MIB_IPNETROW.dwAddr → dotted-quad', () {
    test('decodes a typical private address', () {
      // 192.168.1.10 stored network-order: 192 + 168<<8 + 1<<16 + 10<<24.
      const int dword = 192 + (168 << 8) + (1 << 16) + (10 << 24);
      expect(ipv4FromNetworkOrder(dword), '192.168.1.10');
    });

    test('decodes 10.0.0.1', () {
      const int dword = 10 + (0 << 8) + (0 << 16) + (1 << 24);
      expect(ipv4FromNetworkOrder(dword), '10.0.0.1');
    });

    test('decodes the all-zero and broadcast extremes', () {
      expect(ipv4FromNetworkOrder(0), '0.0.0.0');
      const int bcast = 255 + (255 << 8) + (255 << 16) + (255 << 24);
      expect(ipv4FromNetworkOrder(bcast), '255.255.255.255');
    });
  });

  group('formatPhysAddr — bPhysAddr[6] → lowercase colon-hex', () {
    test('formats a standard 6-byte MAC, lowercase, zero-padded', () {
      expect(
        formatPhysAddr(<int>[0xb8, 0x27, 0xeb, 0x01, 0x23, 0x45]),
        'b8:27:eb:01:23:45',
      );
    });

    test('zero-pads single-hex octets', () {
      expect(
        formatPhysAddr(<int>[0x00, 0x0a, 0x05, 0x09, 0x0f, 0x01]),
        '00:0a:05:09:0f:01',
      );
    });

    test('ignores trailing bytes beyond the first six (MAXLEN_PHYSADDR=8)', () {
      expect(
        formatPhysAddr(<int>[0xa4, 0x83, 0xe7, 0x00, 0x11, 0x22, 0xff, 0xff]),
        'a4:83:e7:00:11:22',
      );
    });

    test('returns null for the all-zero MAC (unresolved neighbor), never fakes',
        () {
      expect(formatPhysAddr(<int>[0, 0, 0, 0, 0, 0]), isNull);
    });

    test('returns null for a short physical address', () {
      expect(formatPhysAddr(<int>[0xb8, 0x27, 0xeb]), isNull);
    });

    test('masks bytes to a single octet defensively', () {
      expect(
        formatPhysAddr(<int>[0x1b8, 0x27, 0xeb, 0x01, 0x23, 0x45]),
        'b8:27:eb:01:23:45',
      );
    });
  });

  group('WindowsIpNetTableArpReader — IP→MAC list → ArpReadResult', () {
    test('maps a successful read to available entries, MACs lowercased', () async {
      final reader = WindowsIpNetTableArpReader(
        rawRead: () => <MapEntry<String, String>>[
          const MapEntry<String, String>('192.168.1.10', 'B8:27:EB:01:23:45'),
          const MapEntry<String, String>('192.168.1.20', 'a4:83:e7:00:11:22'),
        ],
      );

      final ArpReadResult result = await reader.read();

      expect(result.available, isTrue);
      expect(result.error, isNull);
      expect(result.byIp, <String, String>{
        '192.168.1.10': 'b8:27:eb:01:23:45',
        '192.168.1.20': 'a4:83:e7:00:11:22',
      });
    });

    test('a warm-but-empty cache is available with no entries (not a failure)',
        () async {
      final reader = WindowsIpNetTableArpReader(
        rawRead: () => <MapEntry<String, String>>[],
      );

      final ArpReadResult result = await reader.read();

      expect(result.available, isTrue);
      expect(result.entries, isEmpty);
      expect(result.error, isNull);
    });

    test('drops rows with an empty ip or mac (defensive)', () async {
      final reader = WindowsIpNetTableArpReader(
        rawRead: () => <MapEntry<String, String>>[
          const MapEntry<String, String>('', 'b8:27:eb:01:23:45'),
          const MapEntry<String, String>('192.168.1.10', ''),
          const MapEntry<String, String>('192.168.1.30', 'aa:bb:cc:dd:ee:ff'),
        ],
      );

      final ArpReadResult result = await reader.read();

      expect(result.available, isTrue);
      expect(result.byIp, <String, String>{
        '192.168.1.30': 'aa:bb:cc:dd:ee:ff',
      });
    });

    test('a GetIpNetTable failure becomes an honest unavailable result',
        () async {
      final reader = WindowsIpNetTableArpReader(
        rawRead: () =>
            throw const WindowsArpReadException('GetIpNetTable read call failed '
                '(error 5).'),
      );

      final ArpReadResult result = await reader.read();

      expect(result.available, isFalse);
      expect(result.entries, isEmpty);
      expect(result.error, contains('Windows ARP read failed'));
      expect(result.error, contains('error 5'));
    });

    test('any other thrown error also degrades to unavailable, never throws',
        () async {
      final reader = WindowsIpNetTableArpReader(
        rawRead: () => throw StateError('boom'),
      );

      final ArpReadResult result = await reader.read();

      expect(result.available, isFalse);
      expect(result.error, contains('Windows ARP read error'));
    });
  });
}
