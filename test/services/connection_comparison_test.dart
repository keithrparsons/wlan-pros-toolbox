// ConnectionComparison.phrase — pure ratio-phrasing unit tests.
//
// Covers the wording bands: about-the-same (+/-10%), small-ratio percentage,
// the clean "Nx" multiple above ~10x (the fix for the "3913% faster" bug), and
// the "far faster/slower" plain wording past ~100x. No Flutter, no I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/connection_comparison.dart';

void main() {
  group('ConnectionComparison.phrase', () {
    test('within +/-10% reads as "about the same speed"', () {
      expect(
        ConnectionComparison.phrase(105, 100),
        'Your Wi-Fi link and your internet connection are running at about '
        'the same speed.',
      );
      // Symmetric within the band the other direction.
      expect(
        ConnectionComparison.phrase(92, 100),
        contains('about the same speed'),
      );
    });

    test('small ratio keeps the percentage wording (faster)', () {
      // usable 150, internet 100 → +50% faster, ratio 1.5x (<= 10x).
      expect(
        ConnectionComparison.phrase(150, 100),
        'Your Wi-Fi link is 50% faster than your internet connection.',
      );
    });

    test('small ratio keeps the percentage wording (slower)', () {
      // usable 50, internet 100 → -50%, internet 2x the Wi-Fi.
      expect(
        ConnectionComparison.phrase(50, 100),
        'Your Wi-Fi link is 50% slower than your internet connection.',
      );
    });

    test('the 3913% bug: ~40x is expressed as a clean multiple, not a %', () {
      // The motivating case: usable 470, internet ~11.7 → ~3913% → ~40x.
      final s = ConnectionComparison.phrase(470, 11.7);
      expect(s, 'Your Wi-Fi link is about 40x faster than your internet '
          'connection.');
      // The giant percentage must be gone.
      expect(s, isNot(contains('%')));
      expect(s, isNot(contains('3913')));
    });

    test('just above 10x switches from % to the "about Nx" multiple', () {
      // usable 1200, internet 100 → 12x.
      final s = ConnectionComparison.phrase(1200, 100);
      expect(s, 'Your Wi-Fi link is about 12x faster than your internet '
          'connection.');
    });

    test('at/below ~10x still uses the percentage (boundary stays small-ratio)',
        () {
      // Exactly 10x → keeps the percentage (900% faster), not yet a multiple.
      final s = ConnectionComparison.phrase(1000, 100);
      expect(s, 'Your Wi-Fi link is 900% faster than your internet connection.');
    });

    test('past ~100x reads as plain "far faster"', () {
      // usable 20000, internet 100 → 200x.
      expect(
        ConnectionComparison.phrase(20000, 100),
        'Your Wi-Fi link is far faster than your internet connection.',
      );
    });

    test('a huge ratio the other way reads as "far slower"', () {
      // internet 200x the usable Wi-Fi.
      expect(
        ConnectionComparison.phrase(100, 20000),
        'Your Wi-Fi link is far slower than your internet connection.',
      );
    });

    test('the clean-multiple phrasing carries NO em-dash and no giant %', () {
      for (final ratio in <double>[15, 40, 99]) {
        final s = ConnectionComparison.phrase(100 * ratio, 100);
        expect(s, isNot(contains('—')));
        expect(s, contains('x faster'));
      }
    });
  });
}
