// MacRandomizationClassifier unit tests — the locally-administered-bit verdict
// and the honest "unreadable" handling for null/blank/iOS-sentinel inputs.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/mac_randomization.dart';

void main() {
  group('classify', () {
    test('clear U/L bit → universal (burned-in)', () {
      // 0xa4 = 1010 0100 — bit 0x02 clear.
      expect(
        MacRandomizationClassifier.classify('a4:83:e7:aa:bb:cc'),
        MacRandomization.universal,
      );
      // 0x00 first octet, classic vendor OUI.
      expect(
        MacRandomizationClassifier.classify('00:1b:63:84:45:e6'),
        MacRandomization.universal,
      );
    });

    test('set U/L bit → randomized (locally administered)', () {
      // 0x06 = 0000 0110 — bit 0x02 set.
      expect(
        MacRandomizationClassifier.classify('06:11:22:33:44:55'),
        MacRandomization.randomized,
      );
      // 0xda = 1101 1010 — bit 0x02 set (typical Apple randomized prefix).
      expect(
        MacRandomizationClassifier.classify('da:a1:19:00:11:22'),
        MacRandomization.randomized,
      );
    });

    test('null / blank → unreadable', () {
      expect(
        MacRandomizationClassifier.classify(null),
        MacRandomization.unreadable,
      );
      expect(
        MacRandomizationClassifier.classify('   '),
        MacRandomization.unreadable,
      );
    });

    test('iOS sentinel 02:00:00:00:00:00 → unreadable (not randomized)', () {
      // The sentinel has the U/L bit set, so a naive parse would call it
      // "randomized" — but it is the OS placeholder, so it must be unreadable.
      expect(
        MacRandomizationClassifier.classify('02:00:00:00:00:00'),
        MacRandomization.unreadable,
      );
      expect(
        MacRandomizationClassifier.classify('02:00:00:00:00:00'),
        isNot(MacRandomization.randomized),
      );
    });

    test('garbage / non-MAC → unreadable', () {
      expect(
        MacRandomizationClassifier.classify('not-a-mac'),
        MacRandomization.unreadable,
      );
      expect(
        MacRandomizationClassifier.classify('zz:zz'),
        MacRandomization.unreadable,
      );
    });

    test('accepts hyphen-separated and bare-hex forms', () {
      expect(
        MacRandomizationClassifier.classify('A4-83-E7-AA-BB-CC'),
        MacRandomization.universal,
      );
      expect(
        MacRandomizationClassifier.classify('0611223344 55'.replaceAll(' ', '')),
        MacRandomization.randomized,
      );
    });
  });

  group('label', () {
    test('universal label', () {
      expect(
        MacRandomizationClassifier.label('a4:83:e7:aa:bb:cc'),
        'Universal (burned-in)',
      );
    });

    test('randomized label', () {
      expect(
        MacRandomizationClassifier.label('06:11:22:33:44:55'),
        'Randomized (locally administered)',
      );
    });

    test('unreadable label names the Apple limitation', () {
      final String label =
          MacRandomizationClassifier.label('02:00:00:00:00:00');
      expect(label, contains('Apple does not expose'));
      expect(label, contains('Wi-Fi MAC'));
    });
  });
}
