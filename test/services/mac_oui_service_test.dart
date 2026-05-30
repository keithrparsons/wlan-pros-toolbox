// MacOuiService unit tests — multi-format MAC normalization, OUI extraction,
// most-specific-first registry matching (MA-L/MA-M/MA-S), U/L + I/G bit
// detection (locally-administered / multicast), unknown-OUI clean miss, and
// table parsing. The service is built from an in-memory table so no asset load
// is needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/mac_oui_service.dart';

void main() {
  final MacOuiService svc = MacOuiService.fromTable(<String, String>{
    'B827EB': 'Raspberry Pi Foundation', // MA-L /24
    '001A1E': 'Hewlett Packard Enterprise', // MA-L /24 (ex-Aruba block)
    'C85CE27': 'Synergy Systems', // MA-M /28
    '8C1F64AFA': 'Data Electronic Devices', // MA-S /36
  });

  group('normalizeMac', () {
    test('all common formats normalize to the same canonical form', () {
      const String want = 'b8:27:eb:01:23:45';
      expect(MacOuiService.normalizeMac('B8:27:EB:01:23:45'), want);
      expect(MacOuiService.normalizeMac('b8-27-eb-01-23-45'), want);
      expect(MacOuiService.normalizeMac('b827.eb01.2345'), want);
      expect(MacOuiService.normalizeMac('B827EB012345'), want);
      expect(MacOuiService.normalizeMac('  b8:27:eb:01:23:45  '), want);
    });

    test('rejects wrong length and non-hex', () {
      expect(MacOuiService.normalizeMac('b8:27:eb:01:23'), isNull);
      expect(MacOuiService.normalizeMac('b8:27:eb:01:23:45:67'), isNull);
      expect(MacOuiService.normalizeMac('gg:27:eb:01:23:45'), isNull);
      expect(MacOuiService.normalizeMac(''), isNull);
    });
  });

  group('ouiOf', () {
    test('returns the upper-case 24-bit OUI', () {
      expect(MacOuiService.ouiOf('b8:27:eb:01:23:45'), 'B827EB');
    });
    test('null on invalid input', () {
      expect(MacOuiService.ouiOf('nope'), isNull);
    });
  });

  group('lookup — valid vendor matches', () {
    test('known MA-L OUI resolves the vendor', () {
      final OuiResult r = svc.lookup('b8:27:eb:11:22:33');
      expect(r.isValid, isTrue);
      expect(r.matched, isTrue);
      expect(r.vendor, 'Raspberry Pi Foundation');
      expect(r.oui, 'B827EB');
      expect(r.registry, OuiRegistry.maL);
      expect(r.isLocal, isFalse);
      expect(r.isMulticast, isFalse);
    });

    test('all input formats resolve identically', () {
      expect(svc.lookup('B8-27-EB-11-22-33').vendor, 'Raspberry Pi Foundation');
      expect(svc.lookup('b827.eb11.2233').vendor, 'Raspberry Pi Foundation');
      expect(svc.lookup('b827eb112233').vendor, 'Raspberry Pi Foundation');
    });

    test('MA-M /28 match takes precedence over an absent /24', () {
      // C85CE27 is a /28 block; first octet C8 = 11001000 — U/L and I/G both 0.
      final OuiResult r = svc.lookup('c8:5c:e2:71:22:33');
      expect(r.matched, isTrue);
      expect(r.vendor, 'Synergy Systems');
      expect(r.registry, OuiRegistry.maM);
    });

    test('MA-S /36 match resolves the sub-assignee', () {
      // 8C1F64AFA is a /36 block; first octet 8C = 10001100 — U/L and I/G both 0.
      final OuiResult r = svc.lookup('8c:1f:64:af:a1:23');
      expect(r.matched, isTrue);
      expect(r.vendor, 'Data Electronic Devices');
      expect(r.registry, OuiRegistry.maS);
    });
  });

  group('lookup — locally-administered / multicast honesty', () {
    test('U/L bit set → locally administered, no vendor invented', () {
      final OuiResult r = svc.lookup('02:1a:2b:3c:4d:5e');
      expect(r.isValid, isTrue);
      expect(r.isLocal, isTrue);
      expect(r.matched, isFalse);
      expect(r.vendor, isNull);
    });

    test('randomized phone-style MACs flagged local', () {
      for (final String mac in <String>[
        'da:a1:19:00:11:22',
        '7e:00:00:00:00:01',
        'b6:ab:cd:ef:00:01',
      ]) {
        final OuiResult r = svc.lookup(mac);
        expect(r.isLocal, isTrue,
            reason: '\$mac should be locally administered');
        expect(r.matched, isFalse);
      }
    });

    test('I/G bit set → multicast, no vendor', () {
      final OuiResult r = svc.lookup('01:00:5e:00:00:fb');
      expect(r.isMulticast, isTrue);
      expect(r.matched, isFalse);
      expect(r.vendor, isNull);
    });

    test('globally-unique address (U/L clear) is not flagged local', () {
      final OuiResult r = svc.lookup('b8:27:eb:01:02:03');
      expect(r.isLocal, isFalse);
      expect(r.isMulticast, isFalse);
    });
  });

  group('lookup — clean miss and invalid input', () {
    test('unknown globally-unique OUI returns unmatched, not an error', () {
      final OuiResult r = svc.lookup('a0:00:00:00:00:01');
      expect(r.isValid, isTrue);
      expect(r.matched, isFalse);
      expect(r.vendor, isNull);
      expect(r.errorMessage, isNull);
    });

    test('malformed MAC is a validation error with a message', () {
      final OuiResult r = svc.lookup('not-a-mac');
      expect(r.isValid, isFalse);
      expect(r.matched, isFalse);
      expect(r.errorMessage, isNotNull);
      expect(r.errorMessage, contains('valid MAC'));
    });
  });

  group('parseTable', () {
    test('parses tab-separated rows, skips comments and blanks', () {
      const String raw = '# header comment\n'
          '\n'
          'B827EB\tRaspberry Pi Foundation\n'
          'C85CE27\tSynergy Systems\n'
          '8C1F64AFA\tData Electronic Devices\n'
          'BADLINE_NO_TAB\n'
          'XY\tToo short prefix\n';
      final Map<String, String> table = MacOuiService.parseTable(raw);
      expect(table['B827EB'], 'Raspberry Pi Foundation');
      expect(table['C85CE27'], 'Synergy Systems');
      expect(table['8C1F64AFA'], 'Data Electronic Devices');
      expect(table.containsKey('XY'), isFalse);
      expect(table.length, 3);
    });

    test('round-trips through a service built from the parsed table', () {
      const String raw = 'B827EB\tRaspberry Pi Foundation\n';
      final MacOuiService s =
          MacOuiService.fromTable(MacOuiService.parseTable(raw));
      expect(s.lookup('b8:27:eb:00:00:01').vendor, 'Raspberry Pi Foundation');
    });
  });
}
