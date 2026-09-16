// Tests for the RSN / WPA IE security decoder.
//
// The byte strings below are built the way a real beacon builds them, from the
// element id and the declared lengths outward, rather than pasted as opaque
// hex. A test whose fixture nobody can read cannot be checked against the
// standard, and this decoder reads attacker-adjacent bytes.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ie_parser.dart';
import 'package:wlan_pros_toolbox/services/network/rsn_security_parser.dart';

/// Builds one `[id][len][body]` element.
Uint8List _ie(int id, List<int> body) =>
    Uint8List.fromList(<int>[id, body.length, ...body]);

/// Builds an RSN element body: version 1, CCMP group, one CCMP pairwise, then
/// the given AKM suite types under the RSN OUI.
List<int> _rsnBody(List<int> akmTypes, {List<int> oui = kRsnOui}) => <int>[
      0x01, 0x00, // version 1
      ...kRsnOui, 0x04, // group cipher CCMP
      0x01, 0x00, // pairwise count 1
      ...kRsnOui, 0x04, // pairwise CCMP
      akmTypes.length, 0x00, // AKM count
      for (final int t in akmTypes) ...<int>[...oui, t],
      0x00, 0x00, // RSN capabilities
    ];

/// Builds the WPA1 vendor element body: OUI 00-50-F2, type 1, then RSN layout
/// with the Microsoft selector OUI.
List<int> _wpaBody(List<int> akmTypes) => <int>[
      ...kMsOui, kWpaVendorType,
      0x01, 0x00, // version 1
      ...kMsOui, 0x02, // group cipher TKIP
      0x01, 0x00, // pairwise count 1
      ...kMsOui, 0x02, // pairwise TKIP
      akmTypes.length, 0x00,
      for (final int t in akmTypes) ...<int>[...kMsOui, t],
    ];

void main() {
  group('RSN AKM suites map to the shared token vocabulary', () {
    test('PSK is wpa2Personal', () {
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[2]))),
          <String>['wpa2Personal']);
    });

    test('802.1X is wpa2Enterprise', () {
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[1]))),
          <String>['wpa2Enterprise']);
    });

    test('SAE is wpa3Personal', () {
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[8]))),
          <String>['wpa3Personal']);
    });

    test('Suite-B 192 is wpa3Enterprise', () {
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[12]))),
          <String>['wpa3Enterprise']);
    });

    test('OWE is owe, not open', () {
      // Enhanced Open is ENCRYPTED. Reporting it as open would be the exact
      // false statement this decoder exists to avoid.
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[18]))),
          <String>['owe']);
    });

    test('FT variants fold into their base scheme, not a separate token', () {
      // Fast transition is a roaming mechanism, not a different security
      // scheme to someone choosing a network.
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[4]))),
          <String>['wpa2Personal']);
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[9]))),
          <String>['wpa3Personal']);
    });
  });

  group('THE CASE THE FEATURE EXISTS FOR: more than one scheme at once', () {
    test('a WPA2/WPA3 transition BSS reports BOTH tokens', () {
      // PSK + SAE in one RSN element. Collapsing this to a single token would
      // put back, one layer down, the defect per-BSS security exists to stop.
      final List<String> got =
          securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[2, 8])));
      expect(got, <String>['wpa2Personal', 'wpa3Personal']);
    });

    test('order is canonical, not the order the AKMs happened to appear', () {
      // Same two AKMs, reversed in the beacon. The output must not move, or
      // two identical APs would diff against each other.
      final List<String> forward =
          securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[2, 8])));
      final List<String> reversed =
          securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[8, 2])));
      expect(forward, reversed);
    });

    test('a WPA1 + RSN mixed BSS reports both generations', () {
      final Uint8List ies = Uint8List.fromList(<int>[
        ..._ie(kEidVendorSpecific, _wpaBody(<int>[2])),
        ..._ie(kEidRsn, _rsnBody(<int>[2])),
      ]);
      expect(securityTokensFromIes(ies), <String>['wpaPersonal', 'wpa2Personal']);
    });

    test('a duplicate AKM does not produce a duplicate token', () {
      expect(securityTokensFromIes(_ie(kEidRsn, _rsnBody(<int>[2, 2, 4]))),
          <String>['wpa2Personal']);
    });
  });

  group('WPA1 vendor element', () {
    test('PSK is wpaPersonal', () {
      expect(securityTokensFromIes(_ie(kEidVendorSpecific, _wpaBody(<int>[2]))),
          <String>['wpaPersonal']);
    });

    test('a NON-WPA vendor element is ignored entirely', () {
      // Element 221 is shared by every vendor. A WMM or a vendor name element
      // must not be read as a security claim.
      final Uint8List wmm = _ie(kEidVendorSpecific,
          <int>[0x00, 0x50, 0xf2, 0x02, 0x01, 0x01, 0x00, 0x00]);
      expect(securityTokensFromIes(wmm), isEmpty);
    });

    test('a different vendor OUI is ignored', () {
      final Uint8List other = _ie(kEidVendorSpecific,
          <int>[0x00, 0x03, 0x7f, 0x01, 0x01, 0x00]);
      expect(securityTokensFromIes(other), isEmpty);
    });
  });

  group('OPEN versus WEP, which the IEs alone cannot separate', () {
    test('no security element and Privacy CLEAR is none (open)', () {
      expect(
        securityTokensFromIes(Uint8List(0), capabilityInformation: 0x0401),
        <String>['none'],
      );
    });

    test('no security element and Privacy SET is wep', () {
      // WEP advertises neither an RSN nor a WPA element. The Privacy bit is the
      // only thing that distinguishes it from an open network.
      expect(
        securityTokensFromIes(Uint8List(0),
            capabilityInformation: 0x0401 | kCapabilityPrivacyBit),
        <String>['wep'],
      );
    });

    test('NO capability field means EMPTY, and empty is not open', () {
      // The contract on ScannedAp.security: empty means the platform named no
      // scheme we could resolve, and it must never be read as open. Open has
      // its own token.
      expect(securityTokensFromIes(Uint8List(0)), isEmpty);
      expect(securityTokensFromIes(Uint8List(0)), isNot(contains('none')));
    });

    test('an RSN element WINS over the Privacy bit', () {
      // Privacy is set on every encrypted network, WEP or not. A BSS with an
      // RSN element must never be reported as WEP.
      final List<String> got = securityTokensFromIes(
        _ie(kEidRsn, _rsnBody(<int>[8])),
        capabilityInformation: 0x0401 | kCapabilityPrivacyBit,
      );
      expect(got, <String>['wpa3Personal']);
      expect(got, isNot(contains('wep')));
    });
  });

  group('Malformed input fails safe, and never throws', () {
    test('an empty blob yields nothing', () {
      expect(securityTokensFromIes(Uint8List(0)), isEmpty);
    });

    test('an RSN element truncated mid-AKM keeps what it decoded', () {
      // Two AKMs declared, one and a half supplied.
      final List<int> body = <int>[
        0x01, 0x00,
        ...kRsnOui, 0x04,
        0x01, 0x00,
        ...kRsnOui, 0x04,
        0x02, 0x00, // claims 2 AKMs
        ...kRsnOui, 0x02, // first is PSK
        0x00, 0x0f, // second is cut off
      ];
      expect(securityTokensFromIes(_ie(kEidRsn, body)), <String>['wpa2Personal']);
    });

    test('an ABSURD AKM count does not over-read or throw', () {
      // A 65535-entry claim with no data behind it. This is the hostile case:
      // the count is attacker-controlled.
      final List<int> body = <int>[
        0x01, 0x00,
        ...kRsnOui, 0x04,
        0x01, 0x00,
        ...kRsnOui, 0x04,
        0xff, 0xff, // 65535 AKMs claimed
      ];
      expect(() => securityTokensFromIes(_ie(kEidRsn, body)), returnsNormally);
      expect(securityTokensFromIes(_ie(kEidRsn, body)), isEmpty);
    });

    test('an ABSURD pairwise count does not throw', () {
      final List<int> body = <int>[
        0x01, 0x00,
        ...kRsnOui, 0x04,
        0xff, 0xff, // 65535 pairwise ciphers claimed
      ];
      expect(() => securityTokensFromIes(_ie(kEidRsn, body)), returnsNormally);
      expect(securityTokensFromIes(_ie(kEidRsn, body)), isEmpty);
    });

    test('a header-only RSN element yields nothing rather than a guess', () {
      expect(securityTokensFromIes(_ie(kEidRsn, <int>[0x01, 0x00])), isEmpty);
    });

    test('an UNKNOWN AKM type yields nothing, and NOT open', () {
      // A future scheme we do not classify. Saying "open" about it would be a
      // false statement about someone's network; saying nothing is merely
      // incomplete. Crucially the Privacy fallback must NOT fire here, because
      // a security element WAS present.
      final List<String> got = securityTokensFromIes(
        _ie(kEidRsn, _rsnBody(<int>[99])),
        capabilityInformation: 0x0401 | kCapabilityPrivacyBit,
      );
      expect(got, isEmpty);
      expect(got, isNot(contains('none')));
      expect(got, isNot(contains('wep')));
    });

    test('a truncated tail in the surrounding blob stops the walk cleanly', () {
      final Uint8List ies = Uint8List.fromList(<int>[
        ..._ie(kEidRsn, _rsnBody(<int>[2])),
        0x30, 0x40, 0x01, // element 48 claiming 64 bytes, supplying 1
      ]);
      expect(securityTokensFromIes(ies), <String>['wpa2Personal']);
    });
  });
}
