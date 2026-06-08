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

    test('unreadable label names the Apple limitation (iOS default)', () {
      final String label =
          MacRandomizationClassifier.label('02:00:00:00:00:00');
      expect(label, contains('Apple does not expose'));
      expect(label, contains('Wi-Fi MAC'));
    });

    test('unreadable label is PLATFORM-CORRECT — Android names the Android '
        'limit, never Apple (S24 leak fix)', () {
      final String label = MacRandomizationClassifier.label(
        '02:00:00:00:00:00',
        platform: MacAddressPlatform.android,
      );
      // The Android note must name the real Android reason, and must NOT leak
      // the iOS "Apple" wording onto Android.
      expect(label, contains('Android returns a randomized placeholder MAC'));
      expect(label, contains('hidden from apps'));
      expect(label, isNot(contains('Apple')));
    });

    test('explicit iOS platform names the Apple limit', () {
      final String label = MacRandomizationClassifier.label(
        '02:00:00:00:00:00',
        platform: MacAddressPlatform.ios,
      );
      expect(label, contains('Apple does not expose'));
    });

    test('other platform gives a generic, non-Apple, non-Android note', () {
      final String label = MacRandomizationClassifier.label(
        '02:00:00:00:00:00',
        platform: MacAddressPlatform.other,
      );
      expect(label, isNot(contains('Apple')));
      expect(label, isNot(contains('Android')));
      expect(label, contains('does not expose'));
    });

    test('readable verdicts are platform-independent', () {
      for (final MacAddressPlatform p in MacAddressPlatform.values) {
        expect(
          MacRandomizationClassifier.label('a4:83:e7:aa:bb:cc', platform: p),
          'Universal (burned-in)',
        );
        expect(
          MacRandomizationClassifier.label('06:11:22:33:44:55', platform: p),
          'Randomized (locally administered)',
        );
      }
    });
  });

  group('unreadableReason', () {
    test('iOS reason names Apple', () {
      expect(
        MacRandomizationClassifier.unreadableReason(MacAddressPlatform.ios),
        contains('Apple does not expose'),
      );
    });

    test('Android reason names the randomized placeholder, not Apple', () {
      final String reason =
          MacRandomizationClassifier.unreadableReason(MacAddressPlatform.android);
      expect(reason, contains('randomized placeholder MAC'));
      expect(reason, isNot(contains('Apple')));
    });
  });
}
