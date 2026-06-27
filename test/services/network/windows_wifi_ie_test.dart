// Pure-function tests for the Windows Native Wifi IE parse + MAC formatting
// helpers (windows_wifi_ffi.dart). Like windows_wifi_mapping_test.dart, none of
// these touch a win32 symbol — they operate on plain Dart byte buffers — so they
// run on macOS CI even though the FFI body that reads wlanapi.dll cannot.
//
// feat/windows-wifi-fields (2026-06-27). Locks the TLV walk, the HT/VHT/HE/EHT
// operating-width decode, the Country-element parse, and the device-MAC byte
// formatting that turn raw IE blobs + adapter MAC bytes into the shared WifiInfo
// fields, so a regression in the bit math is caught here rather than only on the
// Windows box.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/windows_wifi_ffi.dart';

/// Builds a non-extended IE element: [id][len][...data].
Uint8List _ie(int id, List<int> data) =>
    Uint8List.fromList(<int>[id, data.length, ...data]);

/// Builds an extended IE element (id 255): [255][len][extId][...data].
Uint8List _extIe(int extId, List<int> data) =>
    Uint8List.fromList(<int>[255, data.length + 1, extId, ...data]);

Uint8List _concat(List<Uint8List> parts) =>
    Uint8List.fromList(<int>[for (final Uint8List p in parts) ...p]);

void main() {
  group('formatMacBytes', () {
    test('formats the first six octets as lowercase colon-hex', () {
      expect(
        formatMacBytes(<int>[0xA4, 0x83, 0xE7, 0x00, 0x11, 0x22]),
        'a4:83:e7:00:11:22',
      );
    });

    test('zero-pads single-hex-digit octets', () {
      expect(
        formatMacBytes(<int>[0x00, 0x0a, 0x0b, 0x01, 0x02, 0x03]),
        '00:0a:0b:01:02:03',
      );
    });

    test('reads only the first six octets when more are supplied', () {
      expect(
        formatMacBytes(<int>[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0xFF, 0xFF]),
        '01:02:03:04:05:06',
      );
    });

    test('masks values to a byte', () {
      expect(
        formatMacBytes(<int>[0x1A4, 0x83, 0xE7, 0x00, 0x11, 0x22]),
        'a4:83:e7:00:11:22',
      );
    });

    test('a short buffer → null (never a fabricated MAC)', () {
      expect(formatMacBytes(<int>[0x01, 0x02, 0x03]), isNull);
    });

    test('the all-zero MAC → null', () {
      expect(formatMacBytes(<int>[0, 0, 0, 0, 0, 0]), isNull);
    });
  });

  group('findInformationElement', () {
    test('returns the data bytes of a matching non-extended element', () {
      final Uint8List ies = _concat(<Uint8List>[
        _ie(0, <int>[0x41, 0x42]), // SSID "AB"
        _ie(61, <int>[0x24, 0x05]), // HT Operation
      ]);
      expect(findInformationElement(ies, 61), Uint8List.fromList(<int>[0x24, 0x05]));
    });

    test('extended element match excludes the extension-id byte', () {
      final Uint8List ies = _extIe(36, <int>[0xAA, 0xBB, 0xCC]);
      expect(
        findInformationElement(ies, 255, extId: 36),
        Uint8List.fromList(<int>[0xAA, 0xBB, 0xCC]),
      );
    });

    test('skips a 255 element with a different extension id', () {
      final Uint8List ies = _concat(<Uint8List>[
        _extIe(36, <int>[0x01]), // HE
        _extIe(106, <int>[0x02, 0x03]), // EHT
      ]);
      expect(
        findInformationElement(ies, 255, extId: 106),
        Uint8List.fromList(<int>[0x02, 0x03]),
      );
    });

    test('an absent element → null', () {
      final Uint8List ies = _ie(7, <int>[0x55, 0x53, 0x20]);
      expect(findInformationElement(ies, 192), isNull);
    });

    test('a truncated element terminates the walk without throwing', () {
      // Claims length 10 but only 2 data bytes follow.
      final Uint8List ies = Uint8List.fromList(<int>[61, 10, 0x00, 0x04]);
      expect(findInformationElement(ies, 61), isNull);
    });

    test('an empty blob → null', () {
      expect(findInformationElement(Uint8List(0), 61), isNull);
    });
  });

  group('channelWidthFromIes — HT Operation (20/40)', () {
    test('STA channel-width bit clear → 20 MHz', () {
      final Uint8List ies = _ie(61, <int>[0x24, 0x00]);
      expect(channelWidthFromIes(ies), 20);
    });

    test('STA channel-width bit set → 40 MHz', () {
      final Uint8List ies = _ie(61, <int>[0x24, 0x04]);
      expect(channelWidthFromIes(ies), 40);
    });
  });

  group('channelWidthFromIes — VHT Operation (80/160)', () {
    test('width field 1 with a single segment → 80 MHz', () {
      // [width=1][seg0=42][seg1=0]
      final Uint8List ies = _ie(192, <int>[1, 42, 0]);
      expect(channelWidthFromIes(ies), 80);
    });

    test('width field 1 with two segments → 160 MHz span', () {
      // [width=1][seg0=50][seg1=58]
      final Uint8List ies = _ie(192, <int>[1, 50, 58]);
      expect(channelWidthFromIes(ies), 160);
    });

    test('width field 2 → 160 MHz (deprecated explicit)', () {
      final Uint8List ies = _ie(192, <int>[2, 50, 0]);
      expect(channelWidthFromIes(ies), 160);
    });

    test('VHT width field 0 falls back to the HT Operation element', () {
      final Uint8List ies = _concat(<Uint8List>[
        _ie(61, <int>[0x24, 0x04]), // HT → 40
        _ie(192, <int>[0, 0, 0]), // VHT width 0 → defer to HT
      ]);
      expect(channelWidthFromIes(ies), 40);
    });
  });

  group('channelWidthFromIes — HE Operation (6 GHz)', () {
    test('6 GHz Operation Information present, control width 2 → 80 MHz', () {
      // HE params (3 bytes) with bit 17 (6 GHz present) set: 1<<17 = 0x020000.
      // Byte layout little-endian: [0x00, 0x00, 0x02].
      // Then BSS color (1) + Basic HE-MCS/Nss (2) + 6 GHz Op Info
      // [primary][control][seg0][seg1][minrate]; control low 2 bits = width.
      final Uint8List he = _extIe(36, <int>[
        0x00, 0x00, 0x02, // HE Operation Parameters, 6 GHz present
        0x00, // BSS Color
        0x00, 0x00, // Basic HE-MCS And Nss Set
        37, // primary channel
        0x02, // control: width = 2 (80 MHz)
        37, 0, 0, // seg0, seg1, min rate
      ]);
      expect(channelWidthFromIes(he), 80);
    });

    test('6 GHz Operation Information present, control width 3 → 160 MHz', () {
      final Uint8List he = _extIe(36, <int>[
        0x00, 0x00, 0x02, // 6 GHz present
        0x00,
        0x00, 0x00,
        37,
        0x03, // width = 3 (160 span)
        37, 45, 0,
      ]);
      expect(channelWidthFromIes(he), 160);
    });
  });

  group('channelWidthFromIes — EHT Operation (Wi-Fi 7, 320)', () {
    test('EHT Operation Information present, control width 4 → 320 MHz', () {
      // [params: bit0 = info present][4 bytes basic mcs/nss][control][...]
      final Uint8List eht = _extIe(106, <int>[
        0x01, // EHT Operation Parameters: Information Present
        0x00, 0x00, 0x00, 0x00, // Basic EHT-MCS And Nss Set
        0x04, // Control: channel width = 4 (320 MHz)
        0, 0, // CCFS0, CCFS1
      ]);
      expect(channelWidthFromIes(eht), 320);
    });

    test('EHT control width 3 → 160 MHz', () {
      final Uint8List eht = _extIe(106, <int>[
        0x01,
        0x00, 0x00, 0x00, 0x00,
        0x03, // width = 3 (160)
        0, 0,
      ]);
      expect(channelWidthFromIes(eht), 160);
    });

    test('EHT Operation Information NOT present → falls through (null here)', () {
      final Uint8List eht = _extIe(106, <int>[
        0x00, // info NOT present
        0x00, 0x00, 0x00, 0x00,
      ]);
      expect(channelWidthFromIes(eht), isNull);
    });

    test('EHT takes priority over a co-present VHT element', () {
      final Uint8List ies = _concat(<Uint8List>[
        _ie(192, <int>[1, 42, 0]), // VHT → 80
        _extIe(106, <int>[0x01, 0, 0, 0, 0, 0x04, 0, 0]), // EHT → 320
      ]);
      expect(channelWidthFromIes(ies), 320);
    });
  });

  group('channelWidthFromIes — no operation element', () {
    test('a blob with no HT/VHT/HE/EHT element → null', () {
      final Uint8List ies = _ie(7, <int>[0x55, 0x53, 0x20]); // Country only
      expect(channelWidthFromIes(ies), isNull);
    });
  });

  group('countryCodeFromIes', () {
    test('parses the two ASCII country bytes, uppercased', () {
      // "us" + regulatory-class indicator byte.
      final Uint8List ies = _ie(7, <int>[0x75, 0x73, 0x20]);
      expect(countryCodeFromIes(ies), 'US');
    });

    test('finds the Country element among other elements', () {
      final Uint8List ies = _concat(<Uint8List>[
        _ie(61, <int>[0x24, 0x04]),
        _ie(7, <int>[0x44, 0x45, 0x20]), // "DE"
      ]);
      expect(countryCodeFromIes(ies), 'DE');
    });

    test('no Country element → null', () {
      final Uint8List ies = _ie(61, <int>[0x24, 0x04]);
      expect(countryCodeFromIes(ies), isNull);
    });

    test('non-alphabetic country bytes → null (never a garbage code)', () {
      final Uint8List ies = _ie(7, <int>[0x01, 0x02, 0x20]);
      expect(countryCodeFromIes(ies), isNull);
    });

    test('a too-short Country element → null', () {
      final Uint8List ies = _ie(7, <int>[0x55]);
      expect(countryCodeFromIes(ies), isNull);
    });
  });
}
