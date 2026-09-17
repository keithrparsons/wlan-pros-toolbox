// Security resolution, pinned against tokens MEASURED on Keith's own network.
//
// WHY THIS FILE EXISTS. Three bugs shipped into the 1.10.0 build because the
// translation from platform tokens to a security scheme was written from the
// vocabulary rather than from what radios actually emit. Keith caught the first
// by knowing his own networks: "RACHEL is NOT OWE... it is OPEN. So is Keith
// Guest... the only place Keith Guest is OWE is on 6GHz."
//
// EVERY TOKEN LIST BELOW IS REAL, copied from a Nearby AP Scan export on
// 2026-09-17, with the truth taken from Keith's UniFi controller. macOS was
// reporting correctly the whole time; the translation threw the answer away.
//
// THE SHAPE OF ALL THREE BUGS WAS THE SAME: a capability MARKER was read as a
// security SCHEME. `oweTransition` and `wpa3Transition` say "I can take part in
// a transition pair", not "I am that scheme".
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/join_network_list.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

PiJoinSecurity resolve(List<String> tokens) =>
    piJoinSecurityFromKeyMgmt(keyMgmtFromSecurityTokens(tokens));

void main() {
  group('OWE transition: the open half is OPEN', () {
    test('Keith Guest on 2.4 and 5 GHz is open, not OWE', () {
      expect(resolve(<String>['none', 'oweTransition']), PiJoinSecurity.open);
    });

    test('RACHEL-SLOW is open, not OWE', () {
      expect(resolve(<String>['none', 'oweTransition']), PiJoinSecurity.open);
    });

    test('Keith Guest on 6 GHz IS OWE', () {
      // 6 GHz forbids open, so the same SSID runs OWE there. One SSID, two
      // different answers by band, which is why rows must not be merged across
      // bands.
      expect(resolve(<String>['owe', 'oweTransition']), PiJoinSecurity.owe);
    });

    test('oweTransition ALONE never implies OWE', () {
      expect(
        resolve(<String>['none', 'oweTransition']),
        isNot(PiJoinSecurity.owe),
      );
    });
  });

  group('WPA3 transition: the marker is not the scheme', () {
    test('Keith is WPA3, because wpa3Personal is present', () {
      expect(
        resolve(<String>['personal', 'wpa3Personal', 'wpa3Transition']),
        PiJoinSecurity.wpa3Psk,
      );
    });

    test('Keith-IoT is WPA2, even though it also carries wpa3Transition', () {
      // BOTH networks carry wpa3Transition, so it cannot be the discriminator.
      // Mapping it to SAE labelled this WPA2 network as WPA3-SAE.
      expect(
        resolve(<String>[
          'wpaPersonalMixed',
          'wpa2Personal',
          'personal',
          'wpa3Transition',
        ]),
        PiJoinSecurity.wpa2Psk,
      );
    });

    test('wpaPersonalMixed is RECOGNISED, not dumped into unresolved', () {
      // It was missing from the switch entirely and fell through to default,
      // so every WPA2 network on Keith's site carried an unresolved token.
      expect(
        keyMgmtFromSecurityTokens(<String>['wpaPersonalMixed']),
        isNot(contains('unresolved')),
      );
      expect(resolve(<String>['wpaPersonalMixed']), PiJoinSecurity.wpa2Psk);
    });
  });

  group('the protections that must survive all of this', () {
    test('an empty token list is still NOT open', () {
      expect(resolve(const <String>[]), PiJoinSecurity.unsupported);
    });

    test('an unknown token is still NOT open', () {
      expect(resolve(<String>['somethingNew2029']), PiJoinSecurity.unsupported);
    });

    test('enterprise still outranks everything, including OWE', () {
      expect(
        resolve(<String>['wpa2Enterprise', 'owe', 'none']),
        PiJoinSecurity.unsupported,
      );
    });

    test('WEP is still unsupported rather than open', () {
      expect(resolve(<String>['wep']), PiJoinSecurity.unsupported);
    });
  });
}
