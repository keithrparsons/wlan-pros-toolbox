// The Windows join profile is built from attacker-controlled text and consumed
// by a parser we do not own, so the failures worth testing are the ones where a
// bad document reads to a user as a bad NETWORK.
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart'
    show PiJoinSecurity;
import 'package:wlan_pros_toolbox/services/network/windows_join_profile.dart';

void main() {
  group('escapeXml', () {
    test('escapes all five predefined entities', () {
      expect(escapeXml('''a&b<c>d"e'f'''), 'a&amp;b&lt;c&gt;d&quot;e&apos;f');
    });

    test('leaves ordinary SSID text alone', () {
      expect(escapeXml('Express 7 Test'), 'Express 7 Test');
    });

    test('an ampersand SSID does not produce malformed XML', () {
      final String xml = buildWindowsJoinProfileXml(
        ssid: 'Bob & Alice',
        security: PiJoinSecurity.wpa2Psk,
        passphrase: 'correcthorse',
      );
      expect(xml, contains('<name>Bob &amp; Alice</name>'));
      expect(xml, isNot(contains('<name>Bob & Alice</name>')));
    });

    test(
      'an apostrophe SSID survives, which is the common real-world case',
      () {
        final String xml = buildWindowsJoinProfileXml(
          ssid: "Keith's Lab",
          security: PiJoinSecurity.open,
        );
        expect(xml, contains('Keith&apos;s Lab'));
      },
    );

    test('a passphrase containing XML metacharacters is escaped too', () {
      final String xml = buildWindowsJoinProfileXml(
        ssid: 'Lab',
        security: PiJoinSecurity.wpa2Psk,
        passphrase: 'pass<&>word',
      );
      expect(xml, contains('<keyMaterial>pass&lt;&amp;&gt;word</keyMaterial>'));
    });
  });

  group('security mapping', () {
    test('open carries no sharedKey block at all', () {
      final String xml = buildWindowsJoinProfileXml(
        ssid: 'Guest',
        security: PiJoinSecurity.open,
      );
      expect(xml, contains('<authentication>open</authentication>'));
      expect(xml, contains('<encryption>none</encryption>'));
      expect(xml, isNot(contains('sharedKey')));
      expect(xml, isNot(contains('keyMaterial')));
    });

    test('WPA2-PSK maps to WPA2PSK and AES', () {
      final String xml = buildWindowsJoinProfileXml(
        ssid: 'Lab',
        security: PiJoinSecurity.wpa2Psk,
        passphrase: 'correcthorse',
      );
      expect(xml, contains('<authentication>WPA2PSK</authentication>'));
      expect(xml, contains('<encryption>AES</encryption>'));
      expect(xml, contains('<keyType>passPhrase</keyType>'));
    });

    test('WPA3-SAE maps to WPA3SAE and is NEVER silently downgraded', () {
      final String xml = buildWindowsJoinProfileXml(
        ssid: 'Lab6',
        security: PiJoinSecurity.wpa3Psk,
        passphrase: 'correcthorse',
      );
      expect(xml, contains('<authentication>WPA3SAE</authentication>'));
      // The silent-downgrade defect this guards: a transition-mode AP would
      // accept WPA2PSK, so a fallback would work and would weaken the user's
      // own connection without telling them.
      expect(xml, isNot(contains('WPA2PSK')));
    });

    test('unsupported refuses rather than guessing open', () {
      expect(
        () => buildWindowsJoinProfileXml(
          ssid: 'Corp',
          security: PiJoinSecurity.unsupported,
          passphrase: 'correcthorse',
        ),
        throwsA(isA<JoinProfileUnsupported>()),
      );
    });
  });

  group('inputs that must be refused before Windows sees them', () {
    test('a hidden network has no SSID to build from', () {
      expect(
        () =>
            buildWindowsJoinProfileXml(ssid: '', security: PiJoinSecurity.open),
        throwsA(isA<JoinProfileUnsupported>()),
      );
    });

    test('a secured network with no passphrase is refused', () {
      expect(
        () => buildWindowsJoinProfileXml(
          ssid: 'Lab',
          security: PiJoinSecurity.wpa2Psk,
        ),
        throwsA(isA<JoinProfileUnsupported>()),
      );
    });

    test('a passphrase under 8 characters is refused HERE, not by Windows', () {
      expect(
        () => buildWindowsJoinProfileXml(
          ssid: 'Lab',
          security: PiJoinSecurity.wpa2Psk,
          passphrase: 'short',
        ),
        throwsA(isA<JoinProfileUnsupported>()),
      );
    });

    test('a passphrase over 63 characters is refused', () {
      expect(
        () => buildWindowsJoinProfileXml(
          ssid: 'Lab',
          security: PiJoinSecurity.wpa2Psk,
          passphrase: 'x' * 64,
        ),
        throwsA(isA<JoinProfileUnsupported>()),
      );
    });

    test('exactly 8 and exactly 63 are both accepted, the boundaries', () {
      expect(
        () => buildWindowsJoinProfileXml(
          ssid: 'Lab',
          security: PiJoinSecurity.wpa2Psk,
          passphrase: 'x' * 8,
        ),
        returnsNormally,
      );
      expect(
        () => buildWindowsJoinProfileXml(
          ssid: 'Lab',
          security: PiJoinSecurity.wpa2Psk,
          passphrase: 'x' * 63,
        ),
        returnsNormally,
      );
    });
  });

  group('profile shape', () {
    test(
      'connectionMode is manual so Windows does not auto-reconnect later',
      () {
        final String xml = buildWindowsJoinProfileXml(
          ssid: 'Lab',
          security: PiJoinSecurity.open,
        );
        expect(xml, contains('<connectionMode>manual</connectionMode>'));
      },
    );

    test('the SSID appears in both the name and the SSIDConfig block', () {
      final String xml = buildWindowsJoinProfileXml(
        ssid: 'Express 7 Test',
        security: PiJoinSecurity.open,
      );
      expect('<name>Express 7 Test</name>'.allMatches(xml).length, 2);
    });
  });
}
