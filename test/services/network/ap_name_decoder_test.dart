// AP-name decoder — pure-function tests (ap_name_decoder.dart). No I/O, no
// platform symbols: every case is a plain Dart byte buffer, so they run on any
// CI. These lock the ONE pinned offset (Cisco Tag 133 value-offset 10), the
// Tag 221 OUI dispatch, and — most importantly — the HONEST-NULL contract: a
// recognized vendor whose name offset is unverified returns null, NOT a guessed
// substring, and no malformed / truncated / garbage input ever throws.
//
// Build: Felix 2026-07-17, per Pax's decode reference
// (Deliverables/2026-07-17-ap-name-beacon-vendor-decode/brief.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ap_name_decoder.dart';

/// Builds one non-extended IE element: `[id][len][...data]`.
List<int> _ie(int id, List<int> data) => <int>[id, data.length, ...data];

/// Builds a Cisco Aironet Extensions IE (Tag 133) value carrying [name] in the
/// 16-byte zero-padded field at value-offset 10: 10 leading bytes, the name
/// zero-padded to 16, then a client-count byte.
List<int> _aironetIe(String name, {int clientCount = 3}) {
  final List<int> nameField = List<int>.filled(16, 0x00);
  final List<int> chars = name.codeUnits;
  for (int i = 0; i < chars.length && i < 16; i++) {
    nameField[i] = chars[i];
  }
  return _ie(133, <int>[
    ...List<int>.filled(10, 0x00), // offset 0–9 (radio/load/version, opaque)
    ...nameField, // offset 10–25
    clientCount, // offset 26
  ]);
}

/// Builds a vendor-specific IE (Tag 221) with the 3-byte [oui], a vendor
/// type/subtype byte, and an ASCII [payloadName] following it.
List<int> _vendorIe(List<int> oui, {int vType = 0x00, String payloadName = 'GuessMe'}) =>
    _ie(221, <int>[...oui, vType, ...payloadName.codeUnits]);

const List<int> _ouiCiscoWl = <int>[0x00, 0x40, 0x96];
const List<int> _ouiAruba = <int>[0x00, 0x0B, 0x86];
const List<int> _ouiMist = <int>[0x5C, 0x5B, 0x35];
const List<int> _ouiRuckus = <int>[0x00, 0x13, 0x92];
const List<int> _ouiAerohive = <int>[0x00, 0x19, 0x77];
const List<int> _ouiExtreme = <int>[0x00, 0xE0, 0x2B];
const List<int> _ouiUbiquiti = <int>[0x00, 0x15, 0x6D];

void main() {
  group('Tag 133 (Cisco Aironet / Meraki CCX)', () {
    test('decodes a known synthetic Aironet name at value-offset 10', () {
      expect(decodeApName(_aironetIe('AP-Lobby-01')), 'AP-Lobby-01');
    });

    test('strips trailing NUL padding and surrounding whitespace', () {
      // "  hall-3  " zero-padded — trailing NULs cut, spaces trimmed.
      expect(decodeApName(_aironetIe('  hall-3  ')), 'hall-3');
    });

    test('a full 15-char name (max) decodes intact', () {
      expect(decodeApName(_aironetIe('CampusAP-North2')), 'CampusAP-North2');
    });

    test('rejects a non-printable (garbage) name field rather than mojibake', () {
      // A control byte (0x01) in the name field → honest null, never mojibake.
      final List<int> ie = _ie(133, <int>[
        ...List<int>.filled(10, 0x00),
        0x41, 0x01, 0x42, ...List<int>.filled(13, 0x00), // "A\x01B..."
        0x02,
      ]);
      expect(decodeApName(ie), isNull);
    });

    test('a Tag 133 too short to hold the name field returns null (no throw)', () {
      final List<int> ie = _ie(133, <int>[0x00, 0x00, 0x00, 0x00, 0x00]);
      expect(() => decodeApName(ie), returnsNormally);
      expect(decodeApName(ie), isNull);
    });
  });

  group('Tag 221 OUI dispatch', () {
    test('each pinned OUI dispatches to the correct vendor', () {
      expect(tag221VendorForOui(_ouiCiscoWl), ApNameVendor.ciscoAironet);
      expect(tag221VendorForOui(_ouiAruba), ApNameVendor.aruba);
      expect(tag221VendorForOui(_ouiMist), ApNameVendor.mist);
      expect(tag221VendorForOui(_ouiRuckus), ApNameVendor.ruckus);
      expect(tag221VendorForOui(_ouiAerohive), ApNameVendor.aerohive);
      expect(tag221VendorForOui(_ouiExtreme), ApNameVendor.extreme);
      expect(tag221VendorForOui(_ouiUbiquiti), ApNameVendor.ubiquiti);
    });

    test('an unknown OUI dispatches to no vendor (null)', () {
      expect(tag221VendorForOui(<int>[0x12, 0x34, 0x56]), isNull);
    });
  });

  group('Tag 221 honest-null (unverified offsets are NOT guessed)', () {
    test('a recognized vendor with an unverified offset returns null, not a '
        'substring of the payload', () {
      // A well-formed Ruckus IE whose payload literally contains an ASCII name.
      // The offset is UNVERIFIED, so the decoder must NOT slice it out.
      final List<int> ie = _vendorIe(_ouiRuckus, payloadName: 'RuckusLab-AP7');
      expect(decodeApName(ie), isNull);
    });

    test('the still-unpinned Tag 221 vendors remain offset-unverified', () {
      // Guards the honest-null posture: if a future build pins one of these, this
      // fails loudly so the change is deliberate and reviewed — not silent.
      // UniFi is intentionally NOT in this list: its layout is dissector-pinned
      // (see the UniFi group below).
      for (final ApNameVendor v in <ApNameVendor>[
        ApNameVendor.ciscoAironet,
        ApNameVendor.aruba,
        ApNameVendor.mist,
        ApNameVendor.ruckus,
        ApNameVendor.aerohive,
        ApNameVendor.extreme,
      ]) {
        expect(tag221OffsetVerified(v), isFalse, reason: '$v offset should be unverified');
      }
    });

    test('an unknown-vendor Tag 221 (MikroTik-style) returns null', () {
      final List<int> ie = _vendorIe(<int>[0x4C, 0x5E, 0x0C], payloadName: 'x');
      expect(decodeApName(ie), isNull);
    });
  });

  group('Tag 221 UniFi (Ubiquiti) — dissector-pinned, offset 4, name-to-end', () {
    test('decodes an ASCII AP name that runs to the end of the element', () {
      // value = OUI 00:15:6D | type 0x01 | "UAP-Office-East" (to end).
      final List<int> ie = _vendorIe(_ouiUbiquiti, vType: 0x01, payloadName: 'UAP-Office-East');
      expect(decodeApName(ie), 'UAP-Office-East');
    });

    test('its offset is marked verified (dissector-pinned)', () {
      expect(tag221OffsetVerified(ApNameVendor.ubiquiti), isTrue);
    });

    test('a name longer than 32 chars is NOT capped (dissector sets no max)', () {
      const String long = 'this-unifi-ap-name-is-deliberately-well-past-32-characters';
      final List<int> ie = _vendorIe(_ouiUbiquiti, vType: 0x01, payloadName: long);
      expect(decodeApName(ie), long);
    });

    test('a different Ubiquiti vendor type (not 0x01) returns null, not a name', () {
      final List<int> ie = _vendorIe(_ouiUbiquiti, vType: 0x02, payloadName: 'NotAName');
      expect(decodeApName(ie), isNull);
    });

    test('an empty name field (element ends right after the type byte) → null', () {
      final List<int> ie = _ie(221, <int>[..._ouiUbiquiti, 0x01]); // length 4, no name
      expect(() => decodeApName(ie), returnsNormally);
      expect(decodeApName(ie), isNull);
    });

    test('strips trailing NUL padding on a UniFi name', () {
      final List<int> ie = _ie(221, <int>[
        ..._ouiUbiquiti, 0x01, ...'AP1'.codeUnits, 0x00, 0x00,
      ]);
      expect(decodeApName(ie), 'AP1');
    });

    test('rejects a non-printable UniFi name rather than mojibake', () {
      // A control byte (0x1F) inside the name → honest null, never mojibake.
      final List<int> ie = _ie(221, <int>[..._ouiUbiquiti, 0x01, 0x41, 0x1F, 0x42]);
      expect(decodeApName(ie), isNull);
    });
  });

  group('malformed / truncated / empty input never throws and returns null', () {
    test('empty IE bytes', () {
      expect(() => decodeApName(<int>[]), returnsNormally);
      expect(decodeApName(<int>[]), isNull);
    });

    test('a single stray byte (sub-header)', () {
      expect(() => decodeApName(<int>[0x85]), returnsNormally);
      expect(decodeApName(<int>[0x85]), isNull);
    });

    test('a length field that overruns the buffer', () {
      // Tag 133, len=30 declared but only 2 data bytes present.
      final List<int> ie = <int>[133, 30, 0x01, 0x02];
      expect(() => decodeApName(ie), returnsNormally);
      expect(decodeApName(ie), isNull);
    });

    test('a Tag 221 too short to hold OUI + type byte', () {
      final List<int> ie = <int>[221, 2, 0x00, 0x40];
      expect(() => decodeApName(ie), returnsNormally);
      expect(decodeApName(ie), isNull);
    });

    test('a non-Wi-Fi / random garbage blob', () {
      final List<int> garbage = <int>[0xDE, 0xAD, 0xBE, 0xEF, 0xFF, 0x00, 0x13];
      expect(() => decodeApName(garbage), returnsNormally);
      expect(decodeApName(garbage), isNull);
    });
  });

  group('a real name still wins when carried among other IEs', () {
    test('Tag 133 wins over a decodable Tag 221 in the same blob (priority)', () {
      final List<int> blob = <int>[
        ..._ie(0, 'MyNet'.codeUnits), // SSID element (id 0)
        ..._aironetIe('Edge-AP-42'),
        // A fully decodable UniFi name — Tag 133 still takes priority.
        ..._vendorIe(_ouiUbiquiti, vType: 0x01, payloadName: 'UniFi-Name'),
      ];
      expect(decodeApName(blob), 'Edge-AP-42');
    });
  });
}
