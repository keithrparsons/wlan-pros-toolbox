// The native-scan -> join-list adapter.
//
// The MUDI incident is the reason this adapter exists at all rather than a
// second grouping implementation, so the first test here is that same capture
// expressed in native tokens: one SSID, two bands, DIFFERENT SECURITY per band.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/join_network_list.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart'
    show PiJoinSecurity;

typedef Row = ({
  String? ssid,
  String bssid,
  int rssiDbm,
  int frequencyMhz,
  List<String> security
});

Row _row(String? ssid, String bssid, int rssi, int mhz, List<String> sec) =>
    (ssid: ssid, bssid: bssid, rssiDbm: rssi, frequencyMhz: mhz, security: sec);

void main() {
  group('token -> key_mgmt, so one resolver keeps the precedence rules', () {
    test('a transition BSS becomes what wpa_supplicant would have said', () {
      expect(
        keyMgmtFromSecurityTokens(<String>['wpa2Personal', 'wpa3Personal']),
        'wpa-psk sae',
      );
    });

    test('open becomes none', () {
      expect(keyMgmtFromSecurityTokens(<String>['none']), 'none');
    });

    test('EMPTY becomes unresolved, NOT open', () {
      // The load-bearing one. ScannedAp.security says empty means the platform
      // named nothing we could resolve, and must never read as open. An empty
      // string here would resolve to PiJoinSecurity.open and put a user one tap
      // from a join that cannot work.
      expect(keyMgmtFromSecurityTokens(const <String>[]), 'unresolved');
      expect(keyMgmtFromSecurityTokens(const <String>[]), isNot(''));
    });

    test('WEP does not become open', () {
      // There is no WEP case in PiJoinSecurity and there should not be: a WEP
      // join needs key material this path cannot accept.
      expect(keyMgmtFromSecurityTokens(<String>['wep']), 'wep');
    });

    test('an unknown token does not silently vanish into open', () {
      expect(keyMgmtFromSecurityTokens(<String>['someFutureScheme']),
          'unresolved');
    });

    test('none alongside a real scheme drops the none', () {
      // Contradictory source data. Offering an open join for a BSS that also
      // advertises encryption is the failure that matters, so the scheme wins.
      expect(keyMgmtFromSecurityTokens(<String>['none', 'wpa3Personal']), 'sae');
    });
  });

  group('the resolver still decides, and still decides correctly', () {
    PiJoinSecurity resolve(List<String> tokens) =>
        joinCandidatesFromNativeRows(<Row>[
          _row('N', 'aa:bb:cc:dd:ee:01', -40, 5745, tokens),
        ]).single.security;

    test('transition joins as WPA3, not WPA2', () {
      expect(resolve(<String>['wpa2Personal', 'wpa3Personal']),
          PiJoinSecurity.wpa3Psk);
    });

    test('enterprise is unsupported, never a passphrase box', () {
      expect(resolve(<String>['wpa2Enterprise']), PiJoinSecurity.unsupported);
    });

    test('OWE is JOINABLE through the native tokens too', () {
      expect(resolve(<String>['owe']), PiJoinSecurity.owe);
    });

    test('an OWE TRANSITION BSS keeps OWE rather than collapsing to open', () {
      // macOS answers yes to BOTH `none` and `owe` for a transition BSS, which
      // is how Keith's RACHEL-SLOW and Keith Guest were being mislabelled.
      expect(resolve(<String>['none', 'owe']), PiJoinSecurity.owe);
      expect(resolve(<String>['oweTransition']), PiJoinSecurity.owe);
    });

    test('an enterprise BSS with a PSK fallback is NOT downgraded', () {
      expect(resolve(<String>['wpa2Enterprise', 'wpa2Personal']),
          PiJoinSecurity.unsupported);
    });

    test('empty security resolves to unsupported, not open', () {
      expect(resolve(const <String>[]), PiJoinSecurity.unsupported);
    });

    test('WEP resolves to unsupported, not open', () {
      expect(resolve(<String>['wep']), PiJoinSecurity.unsupported);
    });

    test('an open BSS really does resolve to open', () {
      expect(resolve(<String>['none']), PiJoinSecurity.open);
    });
  });

  group('THE MUDI INCIDENT, in native tokens', () {
    test('one SSID on two bands with different security stays TWO rows', () {
      // Keith's travel router, 2026-08-31. The 2.4 GHz BSS is LOUDER, so any
      // grouping keyed on SSID alone drops the 5 GHz row and with it the fact
      // that the bands run different security.
      final List<JoinCandidate> out = joinCandidatesFromNativeRows(<Row>[
        _row('MUDI', '86:8f:31:56:df:b9', -35, 5745,
            <String>['wpa2Personal', 'wpa3Personal']),
        _row('MUDI', 'e6:4b:3c:67:80:89', -24, 2437, <String>['wpa2Personal']),
      ]);
      expect(out.length, 2);
      final JoinCandidate five =
          out.firstWhere((JoinCandidate c) => c.channel == 149);
      final JoinCandidate two =
          out.firstWhere((JoinCandidate c) => c.channel == 6);
      expect(five.security, PiJoinSecurity.wpa3Psk);
      expect(two.security, PiJoinSecurity.wpa2Psk);
    });

    test('two BSSs on ONE band collapse, and are counted', () {
      final List<JoinCandidate> out = joinCandidatesFromNativeRows(<Row>[
        _row('Office', 'aa:aa:aa:aa:aa:01', -70, 5745, <String>['wpa2Personal']),
        _row('Office', 'aa:aa:aa:aa:aa:02', -41, 5745, <String>['wpa2Personal']),
      ]);
      expect(out.length, 1);
      expect(out.single.bssCount, 2);
      // The strongest wins and is the one whose BSSID is shown.
      expect(out.single.bssid, 'aa:aa:aa:aa:aa:02');
      expect(out.single.signalDbm, -41);
    });

    test('hidden BSSs on the same band are NEVER merged', () {
      final List<JoinCandidate> out = joinCandidatesFromNativeRows(<Row>[
        _row(null, 'bb:bb:bb:bb:bb:01', -50, 5745, <String>['wpa2Personal']),
        _row(null, 'bb:bb:bb:bb:bb:02', -60, 5745, <String>['wpa2Personal']),
      ]);
      expect(out.length, 2, reason: 'folding them invents a relationship');
      expect(out.every((JoinCandidate c) => c.isHidden), isTrue);
    });
  });
}
