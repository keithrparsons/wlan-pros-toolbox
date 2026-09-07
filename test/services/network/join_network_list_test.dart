// Join list grouping - the (SSID, band) key, proven against a live capture.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/services/network/join_network_list.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';

PiScanNet net(String? ssid, String bssid, int signal, int freq, String? km) =>
    PiScanNet(
      ssid: ssid,
      bssid: bssid,
      signalDbm: signal,
      freqMhz: freq,
      keyMgmt: km,
    );

void main() {
  group('piJoinSecurityFromKeyMgmt', () {
    test('open when key_mgmt is absent or empty', () {
      expect(piJoinSecurityFromKeyMgmt(null), PiJoinSecurity.open);
      expect(piJoinSecurityFromKeyMgmt(''), PiJoinSecurity.open);
      expect(piJoinSecurityFromKeyMgmt('none'), PiJoinSecurity.open);
    });

    test('wpa-psk and its sha256 variant are WPA2-PSK', () {
      expect(piJoinSecurityFromKeyMgmt('wpa-psk'), PiJoinSecurity.wpa2Psk);
      expect(piJoinSecurityFromKeyMgmt('wpa-psk/wpa-psk-sha256'),
          PiJoinSecurity.wpa2Psk);
    });

    test('transition mode resolves to WPA3, not WPA2', () {
      // wpa-psk/sae advertises both. Joining as WPA3 is correct; joining as
      // WPA2 is merely tolerated, so sae must be tested first.
      expect(piJoinSecurityFromKeyMgmt('wpa-psk/sae'), PiJoinSecurity.wpa3Psk);
      expect(piJoinSecurityFromKeyMgmt('sae'), PiJoinSecurity.wpa3Psk);
    });

    test('enterprise and OWE are unsupported, not open', () {
      expect(piJoinSecurityFromKeyMgmt('wpa-eap'), PiJoinSecurity.unsupported);
      expect(piJoinSecurityFromKeyMgmt('wpa-eap-suite-b-192'),
          PiJoinSecurity.unsupported);
      expect(piJoinSecurityFromKeyMgmt('owe'), PiJoinSecurity.unsupported);
    });

    test('an unrecognised key_mgmt is unsupported, never open', () {
      // GL-005: guessing "open" would put a user one tap from a join that
      // silently cannot work.
      expect(piJoinSecurityFromKeyMgmt('something-new-2029'),
          PiJoinSecurity.unsupported);
    });

    test('no wire value exists for an unsupported network', () {
      expect(piJoinSecurityWireValue(PiJoinSecurity.unsupported), isNull);
      expect(piJoinSecurityWireValue(PiJoinSecurity.open), 'OPEN');
      expect(piJoinSecurityWireValue(PiJoinSecurity.wpa2Psk), 'WPA2-PSK');
      expect(piJoinSecurityWireValue(PiJoinSecurity.wpa3Psk), 'WPA3-PSK');
    });
  });

  group('buildJoinCandidates', () {
    test('THE REGRESSION: one SSID on two bands stays two rows', () {
      // Verbatim from the R4's own scan of Keith's travel router, 2026-08-31.
      // Keyed on SSID alone the louder 2.4 GHz row wins and the 5 GHz WPA3 BSS
      // vanishes, taking a different security type with it.
      final List<JoinCandidate> rows = buildJoinCandidates(<PiScanNet>[
        net('MUDI', '86:8f:31:56:df:b9', -35, 5745, 'wpa-psk/sae'),
        net('MUDI', 'e6:4b:3c:67:80:89', -24, 2437, 'wpa-psk'),
      ]);

      expect(rows.length, 2, reason: 'both bands must survive');
      expect(rows.first.signalDbm, -24, reason: 'strongest first');
      expect(rows.first.band, WifiBand.band24);
      expect(rows.first.security, PiJoinSecurity.wpa2Psk);
      expect(rows.last.band, WifiBand.band5);
      expect(rows.last.security, PiJoinSecurity.wpa3Psk,
          reason: 'the 5 GHz BSS runs SAE and must not inherit the 2.4 GHz type');
    });

    test('several BSSs of one SSID on ONE band collapse to a single row', () {
      final List<JoinCandidate> rows = buildJoinCandidates(<PiScanNet>[
        net('waves.', '7a:49:82:3e:41:60', -63, 5180, 'wpa-eap'),
        net('waves.', '7a:49:82:3e:32:30', -68, 5180, 'wpa-eap'),
        net('waves.', '7a:49:82:3e:44:10', -71, 5180, 'wpa-eap'),
      ]);

      expect(rows.length, 1);
      expect(rows.single.bssCount, 3);
      expect(rows.single.signalDbm, -63, reason: 'strongest BSS represents it');
      expect(rows.single.bssid, '7a:49:82:3e:41:60');
    });

    test('hidden BSSs are never merged with each other', () {
      final List<JoinCandidate> rows = buildJoinCandidates(<PiScanNet>[
        net(null, '68:49:92:3e:34:30', -50, 2437, 'wpa-eap'),
        net(null, '56:49:82:3e:41:60', -64, 5180, 'wpa-psk'),
        net(null, '6a:49:82:3e:41:60', -64, 5180, 'wpa-eap'),
      ]);

      expect(rows.length, 3, reason: 'three hidden BSSs are three networks');
      expect(rows.every((JoinCandidate c) => c.isHidden), isTrue);
      expect(rows.every((JoinCandidate c) => c.bssCount == 1), isTrue);
    });

    test('a group takes the security that demands the MOST, not the loudest', () {
      // A mixed group should never be reported as open because the nearest BSS
      // was open. The quiet downgrade is the failure mode.
      final List<JoinCandidate> rows = buildJoinCandidates(<PiScanNet>[
        net('Mixed', 'aa:aa:aa:aa:aa:01', -30, 2437, null),
        net('Mixed', 'aa:aa:aa:aa:aa:02', -70, 2437, 'wpa-psk'),
      ]);

      expect(rows.single.security, PiJoinSecurity.wpa2Psk);
      expect(rows.single.signalDbm, -30, reason: 'signal still comes from the strongest');
    });

    test('an unrecognised frequency still produces a row', () {
      final List<JoinCandidate> rows =
          buildJoinCandidates(<PiScanNet>[net('Odd', 'bb:bb:bb:bb:bb:01', -55, 4000, 'wpa-psk')]);

      expect(rows.length, 1);
      expect(rows.single.band, isNull);
      expect(rows.single.channel, isNull);
      expect(rows.single.bandLabel, '4000 MHz',
          reason: 'falls back to the raw frequency rather than hiding the BSS');
    });

    test('ordering is stable across identical signal values', () {
      final List<PiScanNet> raw = <PiScanNet>[
        net('Bravo', 'cc:00:00:00:00:01', -60, 2437, 'wpa-psk'),
        net('Alpha', 'cc:00:00:00:00:02', -60, 2437, 'wpa-psk'),
      ];
      expect(
        buildJoinCandidates(raw).map((JoinCandidate c) => c.ssid).toList(),
        buildJoinCandidates(raw.reversed.toList())
            .map((JoinCandidate c) => c.ssid)
            .toList(),
        reason: 'a list that reshuffles under the finger is its own defect',
      );
    });

    test('empty scan yields an empty list, not a crash', () {
      expect(buildJoinCandidates(const <PiScanNet>[]), isEmpty);
    });
  });

  group('absentPassphraseReason', () {
    test('every non-PSK case explains itself', () {
      // The requirement Keith earned on the prototype: he saw a correctly
      // absent passphrase box on an open network and read the page as broken.
      expect(absentPassphraseReason(PiJoinSecurity.open), isNotEmpty);
      expect(absentPassphraseReason(PiJoinSecurity.unsupported), isNotEmpty);
      expect(absentPassphraseReason(PiJoinSecurity.open),
          contains('no passphrase'));
      expect(absentPassphraseReason(PiJoinSecurity.unsupported),
          contains('802.1X'));
    });

    test('PSK networks have no absence to explain', () {
      expect(absentPassphraseReason(PiJoinSecurity.wpa2Psk), isEmpty);
      expect(absentPassphraseReason(PiJoinSecurity.wpa3Psk), isEmpty);
    });
  });
}
