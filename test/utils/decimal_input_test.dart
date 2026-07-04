// Unit tests for the locale-flexible decimal parser.
//
// Guards the EU decimal-separator fix: comma-decimal locales type `0,95` where
// en-US types `0.95`. Before the fix, `double.tryParse('0,95')` returned null
// and the calculators silently produced a wrong answer (or none). These tests
// pin the additive behavior — every period-locale input that parsed before
// still parses to the same value, and comma inputs now parse correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/utils/decimal_input.dart';

void main() {
  group('tryParseFlexibleDouble — comma-decimal locales', () {
    test('0,95 -> 0.95', () {
      expect(tryParseFlexibleDouble('0,95'), 0.95);
    });
    test('14,2 -> 14.2', () {
      expect(tryParseFlexibleDouble('14,2'), 14.2);
    });
    test('scientific 1,5e3 -> 1500.0', () {
      expect(tryParseFlexibleDouble('1,5e3'), 1500.0);
    });
    test('signed -3,5 -> -3.5', () {
      expect(tryParseFlexibleDouble('-3,5'), -3.5);
    });
  });

  group('tryParseFlexibleDouble — period locales unchanged (no regression)', () {
    test('1.5 -> 1.5', () {
      expect(tryParseFlexibleDouble('1.5'), 1.5);
    });
    test('integer 42 -> 42.0', () {
      expect(tryParseFlexibleDouble('42'), 42.0);
    });
    test('scientific 1.5e3 -> 1500.0', () {
      expect(tryParseFlexibleDouble('1.5e3'), 1500.0);
    });
    test('signed -3.5 -> -3.5', () {
      expect(tryParseFlexibleDouble('-3.5'), -3.5);
    });
  });

  group('tryParseFlexibleDouble — ambiguity guard rejects grouped/garbled', () {
    test('1.2.3 -> null', () {
      expect(tryParseFlexibleDouble('1.2.3'), isNull);
    });
    test('1,2,3 -> null', () {
      expect(tryParseFlexibleDouble('1,2,3'), isNull);
    });
    test('mixed grouping 1,234,5 -> null', () {
      expect(tryParseFlexibleDouble('1,234,5'), isNull);
    });
  });

  group('tryParseFlexibleDouble — empty / non-numeric / lone separators', () {
    test('empty -> null', () {
      expect(tryParseFlexibleDouble(''), isNull);
    });
    test('whitespace only -> null', () {
      expect(tryParseFlexibleDouble('   '), isNull);
    });
    test('non-numeric -> null', () {
      expect(tryParseFlexibleDouble('abc'), isNull);
    });
    test('lone period -> null', () {
      expect(tryParseFlexibleDouble('.'), isNull);
    });
    test('lone comma -> null', () {
      expect(tryParseFlexibleDouble(','), isNull);
    });
    test('lone minus -> null', () {
      expect(tryParseFlexibleDouble('-'), isNull);
    });
    test('trims surrounding whitespace', () {
      expect(tryParseFlexibleDouble('  14,2  '), 14.2);
    });
  });
}
