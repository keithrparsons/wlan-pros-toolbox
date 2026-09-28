// Pins the teaching claims of Decibels in Your Head, the Rules of 3 and 10
// (db-rules), from the research brief's candidate 12:
//   - dB is a ratio: +3 dB doubles the power (1.995x exactly, "about
//     double"), +10 dB multiplies it by ten
//   - -67 dBm is twice -70 dBm
//   - the milliwatt math is the dBm/Watt Converter's formula
// and that the rules path always adds up to the difference it explains.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/db_rules_model.dart';

void main() {
  group('the rule of 3', () {
    test('+3 dB is 1.995x, said as about double', () {
      expect(DbRules.ratio(3), closeTo(1.9953, 1e-4));
      expect(DbRules.ratioWords(3), '1.995x, about double');
      expect(DbRules.ratioWords(-3), '0.501x, about half');
    });

    test('-67 dBm carries about twice the milliwatts of -70 dBm', () {
      final double r = DbRules.dbmToMw(-67) / DbRules.dbmToMw(-70);
      expect(r, closeTo(2, 0.01));
      expect(DbRules.dbmToPw(-70), closeTo(100, 1e-9));
      expect(DbRules.dbmToPw(-67), closeTo(199.5, 0.05));
    });

    test('every 3 dB up doubles the linear bar, near enough', () {
      for (int d = DbRules.minDbm; d + 3 <= DbRules.maxDbm; d++) {
        expect(
          DbRules.barShare(d + 3) / DbRules.barShare(d),
          closeTo(2, 0.01),
          reason: '$d',
        );
      }
    });
  });

  group('the rule of 10', () {
    test('+10 dB is exactly ten times, +20 dB a hundred', () {
      expect(DbRules.ratio(10), closeTo(10, 1e-12));
      expect(DbRules.ratio(20), closeTo(100, 1e-9));
      expect(DbRules.ratioWords(10), '10.0x, exactly ten times');
      expect(DbRules.ratioWords(-10), '0.100x, exactly a tenth');
    });

    test('the bar: -80, -70, -67, -60 dBm fill 1%, 10%, 20%, 100%', () {
      expect(DbRules.barShare(-80), closeTo(0.01, 1e-12));
      expect(DbRules.barShare(-70), closeTo(0.10, 1e-12));
      expect(DbRules.barShare(-67), closeTo(0.1995, 1e-4));
      expect(DbRules.barShare(-60), closeTo(1, 1e-12));
    });
  });

  test('the milliwatt formula is the dBm/Watt Converter one: 10^(dBm/10)', () {
    expect(DbRules.dbmToMw(0), 1);
    expect(DbRules.dbmToMw(20), closeTo(100, 1e-9));
    expect(DbRules.dbmToMw(-30), closeTo(0.001, 1e-15));
  });

  group('the rules path', () {
    test('adds up to every difference the slider can make', () {
      for (int db = -20; db <= 20; db++) {
        final DbRulePath p = DbRules.path(db);
        expect(p.db, db, reason: '$db');
        expect(
          p.steps.fold<int>(0, (int s, DbStep x) => s + x.db),
          db,
          reason: '$db',
        );
      }
    });

    test('lands within 4% of the exact ratio for every difference', () {
      for (int db = -20; db <= 20; db++) {
        final DbRulePath p = DbRules.path(db);
        expect(
          (p.ruleRatio / DbRules.ratio(db) - 1).abs(),
          lessThan(0.04),
          reason: '$db',
        );
      }
    });

    test('known paths: +1, +3, +7, +13, -1', () {
      DbRulePath p = DbRules.path(1);
      expect((p.tens, p.threes), (1, -3));
      expect(p.ruleRatio, closeTo(1.25, 1e-12));
      p = DbRules.path(3);
      expect((p.tens, p.threes), (0, 1));
      expect(p.ruleRatio, 2);
      p = DbRules.path(7);
      expect((p.tens, p.threes), (1, -1));
      expect(p.ruleRatio, 5);
      p = DbRules.path(13);
      expect((p.tens, p.threes), (1, 1));
      expect(p.ruleRatio, 20);
      p = DbRules.path(-1);
      expect((p.tens, p.threes), (-1, 3));
      expect(p.ruleRatio, closeTo(0.8, 1e-12));
      expect(DbRules.path(0).steps, isEmpty);
    });
  });

  test('the headline never doubles its noun', () {
    expect(DbRules.powerWords(0), '1x, the same power');
    expect(DbRules.powerWords(3), '1.995x, about double the power');
    for (int db = -20; db <= 20; db++) {
      expect(DbRules.powerWords(db), isNot(contains('power the power')));
    }
  });

  test('formatting', () {
    expect(DbFormat.dbDiff(3), '+3 dB');
    expect(DbFormat.dbDiff(0), '0 dB');
    expect(DbFormat.dbDiff(-7), '-7 dB');
    expect(DbFormat.pw(199.526), '199.5 pW');
    expect(DbFormat.rule(20), '20x');
    expect(DbFormat.rule(1.25), '1.25x');
    expect(DbFormat.rule(0.8), '0.800x');
  });
}
