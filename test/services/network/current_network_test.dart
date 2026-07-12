// CurrentNetwork.suggestFrom — the pure ip+mask → CIDR derivation behind the
// Wave 2 "prefill current network" feature.
//
// 🔴 Every expected value here is HAND-COMPUTED from the ip/mask, NOT read back
// from running the app ([[feedback_tests_that_cannot_fail]]). A test whose
// expectation came from the code can only prove the code agrees with itself.
//
// The load-bearing assertion is the honest-null contract
// ([[feedback_unsourced_is_not_invalid]]): a REAL mask yields a measured CIDR
// (maskWasReal true, no "assumed" hint); a MISSING/unparseable mask yields an
// assumed /24 (maskWasReal false, hint shown); NO usable IP yields nothing
// (cidr null, fabricate nothing). All three paths — not just the happy one —
// are pinned below.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/current_network.dart';

void main() {
  group('BEST — real IP + real mask → the TRUE, MEASURED CIDR', () {
    test('the common /24 case: 192.168.1.50 /24 → 192.168.1.0/24, measured', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.1.50',
        mask: '255.255.255.0',
      );
      expect(s.cidr, '192.168.1.0/24');
      expect(s.maskWasReal, isTrue);
      expect(s.isAssumedPrefix, isFalse,
          reason: 'a measured mask must NOT show the "assumed" hint');
      expect(s.deviceIp, '192.168.1.50');
    });

    test('a non-192.168 network is surfaced verbatim: 172.19.0.37 /24 → '
        '172.19.0.0/24 (the whole point — no more generic default)', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '172.19.0.37',
        mask: '255.255.255.0',
      );
      expect(s.cidr, '172.19.0.0/24');
      expect(s.maskWasReal, isTrue);
    });

    test('🔴 a /23 is shown as /23, NOT /24 — and the network base is the even '
        'boundary the device does not sit in (10.5.7.8 /23 → 10.5.6.0/23)', () {
      // Hand math: 255.255.254.0 = /23. 10.5.7.8 & 255.255.254.0:
      //   third octet 7 (00000111) & 254 (11111110) = 6 (00000110) → 10.5.6.0.
      // Showing 10.5.7.0/24 here would be the exact small lie the 1.7.1 audit
      // removed: wrong prefix AND wrong network base.
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '10.5.7.8',
        mask: '255.255.254.0',
      );
      expect(s.cidr, '10.5.6.0/23');
      expect(s.maskWasReal, isTrue);
    });

    test('🔴 a wide mask is NOT clamped to /24 — the /24 clamp is a scan-scope '
        'guard, not an honest description (192.168.7.42 /16 → 192.168.0.0/16)',
        () {
      // subnet_seed clamps a /16 scan to the device /24; the PREFILL must still
      // tell the truth about the network the device is actually on.
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.7.42',
        mask: '255.255.0.0',
      );
      expect(s.cidr, '192.168.0.0/16');
      expect(s.maskWasReal, isTrue);
    });

    test('a sub-/24 mask is honored: 192.168.1.200 /25 → 192.168.1.128/25', () {
      // 255.255.255.128 = /25. 200 (11001000) & 128 (10000000) = 128.
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.1.200',
        mask: '255.255.255.128',
      );
      expect(s.cidr, '192.168.1.128/25');
      expect(s.maskWasReal, isTrue);
    });

    test('a /32 host mask is a valid measured claim: 203.0.113.5 → '
        '203.0.113.5/32', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '203.0.113.5',
        mask: '255.255.255.255',
      );
      expect(s.cidr, '203.0.113.5/32');
      expect(s.maskWasReal, isTrue);
    });

    test('a real gateway is passed through with the measured CIDR', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.1.50',
        mask: '255.255.255.0',
        gateway: '192.168.1.1',
      );
      expect(s.gatewayIp, '192.168.1.1');
      expect(s.deviceIp, '192.168.1.50');
      expect(s.cidr, '192.168.1.0/24');
    });
  });

  group('PARTIAL — IP but no real mask → an ASSUMED /24, flagged as such', () {
    test('mask null → /24 derived from the IP, maskWasReal FALSE, hint on', () {
      // 172.19.5.8 & 255.255.255.0 = 172.19.5.0. It is a GUESS, not a
      // measurement — the flag says so.
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '172.19.5.8',
        mask: null,
      );
      expect(s.cidr, '172.19.5.0/24');
      expect(s.maskWasReal, isFalse);
      expect(s.isAssumedPrefix, isTrue,
          reason: 'an assumed /24 MUST advertise itself as assumed');
    });

    test('mask 0.0.0.0 is treated as "no mask", not a real /0', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '10.0.0.5',
        mask: '0.0.0.0',
      );
      expect(s.cidr, '10.0.0.0/24');
      expect(s.maskWasReal, isFalse);
    });

    test('a non-contiguous mask is not trusted → assumed /24, not mis-derived',
        () {
      // 255.0.255.0 is not a valid contiguous mask; deriving a prefix from it
      // would be nonsense. Fall back to the honest assumed /24.
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.5.20',
        mask: '255.0.255.0',
      );
      expect(s.cidr, '192.168.5.0/24');
      expect(s.maskWasReal, isFalse);
    });
  });

  group('NONE — no usable device IPv4 → derive nothing, fabricate nothing', () {
    test('null ip + null mask → cidr null, everything null', () {
      final NetworkSuggestion s =
          CurrentNetwork.suggestFrom(ip: null, mask: null);
      expect(s.cidr, isNull);
      expect(s.hasCidr, isFalse);
      expect(s.deviceIp, isNull);
      expect(s.gatewayIp, isNull);
      expect(s.maskWasReal, isFalse);
      expect(s.isAssumedPrefix, isFalse);
    });

    test('a mask WITHOUT an IP is still NONE — a mask alone derives no network',
        () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: 'not.an.ip',
        mask: '255.255.255.0',
      );
      expect(s.cidr, isNull);
      expect(s.deviceIp, isNull);
    });

    test('an empty ip string is NONE', () {
      expect(CurrentNetwork.suggestFrom(ip: '', mask: null).cidr, isNull);
    });

    test('a VPN that exposes only a gateway still passes the gateway through '
        '(cidr null, but the gateway is a real target)', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: null,
        mask: null,
        gateway: '10.8.0.1',
      );
      expect(s.cidr, isNull);
      expect(s.gatewayIp, '10.8.0.1');
    });
  });

  group('gateway sanitation — never offer a dead target', () {
    test('0.0.0.0 (the "no gateway" sentinel) becomes null', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.1.50',
        mask: '255.255.255.0',
        gateway: '0.0.0.0',
      );
      expect(s.gatewayIp, isNull);
      expect(s.cidr, '192.168.1.0/24'); // the CIDR is unaffected
    });

    test('an unparseable gateway becomes null, never passed on', () {
      final NetworkSuggestion s = CurrentNetwork.suggestFrom(
        ip: '192.168.1.50',
        mask: '255.255.255.0',
        gateway: 'garbage',
      );
      expect(s.gatewayIp, isNull);
    });
  });

  group('the async reader seam wires straight to the pure core', () {
    test('suggest() derives from the injected reader with no device', () async {
      final CurrentNetwork net = CurrentNetwork(
        reader: () async =>
            (ip: '172.19.0.37', mask: '255.255.255.0', gateway: '172.19.0.1'),
      );
      final NetworkSuggestion s = await net.suggest();
      expect(s.cidr, '172.19.0.0/24');
      expect(s.gatewayIp, '172.19.0.1');
      expect(s.maskWasReal, isTrue);
    });

    test('a reader that returns all-null yields the honest NONE suggestion',
        () async {
      final CurrentNetwork net = CurrentNetwork(
        reader: () async => (ip: null, mask: null, gateway: null),
      );
      expect((await net.suggest()).cidr, isNull);
    });
  });
}
