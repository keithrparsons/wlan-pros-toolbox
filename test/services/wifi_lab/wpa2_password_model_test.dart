// Teaching claims of "Why a Long Wi-Fi Password Matters More on WPA2"
// (wpa2-password), pinned against the model.
//
// Claims (research brief candidate 6; Wi-Fi Alliance, WPA3 Security
// Considerations, November 2019):
//   1. WPA2-Personal: guesses are checked offline, the AP never sees one.
//   2. WPA3-Personal (SAE): each guess is a live exchange the AP logs.
//   3. Transition mode: the same password is exposed offline, as on WPA2.
//   4. The number of possible passwords is characters ^ length, the same on
//      every security setting, and one more character multiplies it by the
//      number of characters.
//   5. The WFA example: 5,000 passwords, 50% after 2,500 live attempts.
//   6. No time or rate anywhere (brief section 5, anti-pattern 2).

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/wpa2_password_model.dart';

void main() {
  group('where a guess is checked', () {
    test('WPA2-Personal: offline, limited by the computer, AP sees none', () {
      const WpConfig c = WpConfig();
      expect(c.security, WpSecurity.wpa2);
      expect(c.guessPlace, WpGuessPlace.offline);
      expect(c.apSeesGuesses, isFalse);
      expect(c.apFailedAttempts(1000000), 0);
      expect(c.paceLabel, contains("attacker's computer"));
      expect(c.security.exposedOffline, isTrue);
      expect(c.recordedTraffic, startsWith('Readable'));
    });

    test('WPA3-Personal (SAE): only at the AP, one live exchange per guess, '
        'and every wrong guess is logged', () {
      final WpConfig c = const WpConfig().withSecurity(WpSecurity.wpa3);
      expect(c.guessPlace, WpGuessPlace.atAp);
      expect(c.apSeesGuesses, isTrue);
      for (final int g in <int>[0, 1, 7, 2500]) {
        expect(c.apFailedAttempts(g), g);
      }
      expect(c.paceLabel, contains('live exchange with the AP'));
      expect(c.security.exposedOffline, isFalse);
      expect(c.recordedTraffic, contains('forward secrecy'));
    });

    test('transition mode leaves the same password exposed offline, exactly '
        'as WPA2 does', () {
      const WpConfig wpa2 = WpConfig();
      final WpConfig tm = wpa2.withSecurity(WpSecurity.transition);
      expect(tm.security.exposedOffline, isTrue);
      expect(tm.guessPlace, wpa2.guessPlace);
      expect(tm.paceLabel, wpa2.paceLabel);
      expect(tm.apFailedAttempts(500), 0);
      // WPA3 devices on it keep forward secrecy (WFA 2019, p. 6).
      expect(tm.recordedTraffic, contains('WPA3 devices keep forward secrecy'));
    });
  });

  group('the number of possible passwords', () {
    test('characters ^ length, exactly', () {
      expect(const WpConfig().possiblePasswords, BigInt.from(208827064576));
      expect(
        const WpConfig(
          length: 8,
          charset: WpCharset.printable,
        ).possiblePasswords,
        BigInt.parse('6634204312890625'),
      );
      expect(
        const WpConfig(length: 20).possiblePasswords,
        BigInt.parse('19928148895209409152340197376'),
      );
    });

    test(
      'the same on every security setting: the password does not change',
      () {
        for (final WpCharset cs in WpCharset.values) {
          for (final int len in <int>[8, 12, 20, 63]) {
            final Set<BigInt> counts = <BigInt>{
              for (final WpSecurity s in WpSecurity.values)
                WpConfig(
                  security: s,
                  length: len,
                  charset: cs,
                ).possiblePasswords,
            };
            expect(counts, hasLength(1));
          }
        }
      },
    );

    test('one more character multiplies the count by the character count', () {
      for (final WpCharset cs in WpCharset.values) {
        for (int len = WpConfig.minLength; len < WpConfig.maxLength; len++) {
          final WpConfig a = WpConfig(length: len, charset: cs);
          final WpConfig b = a.withLength(len + 1);
          expect(
            b.possiblePasswords,
            a.possiblePasswords * BigInt.from(cs.size),
          );
          expect(a.perExtraCharacter, cs.size);
        }
      }
    });

    test('character sets are counts, not settings: 26, 36, 62, 95', () {
      expect(WpCharset.values.map((WpCharset c) => c.size), <int>[
        26,
        36,
        62,
        95,
      ]);
      for (final WpCharset c in WpCharset.values) {
        expect(c.label, contains('(${c.size})'));
      }
    });

    test(
      'length stays within the 8 to 63 characters a WPA password may be',
      () {
        expect(const WpConfig().withLength(3).length, 8);
        expect(const WpConfig().withLength(100).length, 63);
        expect(const WpConfig().withLength(15).length, 15);
        expect(WpConfig.defaultLength, WpConfig.minLength);
      },
    );
  });

  group('the Wi-Fi Alliance example', () {
    test('5,000 passwords: 50% after 2,500 live attempts, certain after '
        'all 5,000', () {
      final BigInt n = BigInt.from(WpWfaExample.passwords);
      expect(wpChanceFound(WpWfaExample.halfwayAttempts, n), 0.5);
      expect(wpChanceFound(5000, n), 1);
      expect(wpChanceFound(9999, n), 1);
      expect(wpChanceFound(0, n), 0);
      expect(WpFormat.chance(wpChanceFound(2500, n)), '50%');
    });
  });

  group('formatting', () {
    test('exact with separators up to 18 digits, then about m x 10^n', () {
      expect(WpFormat.count(BigInt.from(208827064576)), '208,827,064,576');
      expect(WpFormat.count(BigInt.from(999)), '999');
      expect(WpFormat.count(BigInt.from(1000)), '1,000');
      expect(
        WpFormat.count(BigInt.parse('19928148895209409152340197376')),
        'about 2.0 x 10^28',
      );
      // 9.96 rounds up to 10.0 and carries into the exponent.
      expect(
        WpFormat.count(BigInt.parse('9960000000000000000000')),
        'about 1.0 x 10^22',
      );
      expect(WpFormat.digits(BigInt.from(208827064576)), 12);
      expect(
        WpFormat.digits(
          const WpConfig(
            length: 63,
            charset: WpCharset.printable,
          ).possiblePasswords,
        ),
        125,
      );
    });

    test('chance says "less than 1%" rather than inventing precision', () {
      expect(WpFormat.chance(0.004), 'less than 1%');
      expect(WpFormat.chance(0), '0%');
      expect(WpFormat.chance(1), '100%');
    });
  });

  test('no time, rate or crack duration in any model string', () {
    final RegExp time = RegExp(
      r'\b(second|seconds|minute|minutes|hour|hours|day|days|year|years|'
      r'per second|/s|crack time|centur)',
      caseSensitive: false,
    );
    final List<String> strings = <String>[
      for (final WpSecurity s in WpSecurity.values) ...<String>[
        s.label,
        s.short,
        WpConfig(security: s).paceLabel,
        WpConfig(security: s).recordedTraffic,
      ],
      for (final WpGuessPlace p in WpGuessPlace.values) p.label,
      for (final WpCharset c in WpCharset.values) ...<String>[
        c.label,
        c.phrase,
      ],
    ];
    for (final String s in strings) {
      expect(time.hasMatch(s), isFalse, reason: s);
    }
  });
}
