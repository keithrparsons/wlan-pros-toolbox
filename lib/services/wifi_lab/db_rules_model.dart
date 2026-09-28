// Decibels in Your Head, the Rules of 3 and 10: the pure model for the Wi-Fi
// Classroom tool (db-rules).
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 12
// (section 3) and the section 5 anti-patterns. Pure Dart, no Flutter imports,
// pinned by test/services/wifi_lab/db_rules_model_test.dart.
//
// THE LESSON (brief candidate 12; CWNA-109 objective 1.2.7, "dBm to mW
// conversion rules of 10 and 3"): dB is a ratio. +3 dB doubles the power and
// +10 dB multiplies it by ten, so -67 dBm is twice -70 dBm. The exact factor
// for +3 dB is 10^0.3 = 1.995, so the tool says "about double".
//
// THE MATH is the dBm / Watt Converter's own formula, mW = 10^(dBm / 10)
// (lib/screens/tools/dbm_watt_converter.dart header), and the power ratio of
// a dB difference is 10^(dB / 10). Nothing here is measured or illustrative;
// it is arithmetic.
//
// THE RULES PATH. Any whole number of dB can be written as tens and threes:
// dB = 10 a + 3 b, because 10 and 3 share no factor. The rule estimate is
// 10^a x 2^b. [DbRules.path] picks the a and b with the fewest steps, so +1
// dB is +10 -3 -3 -3 (x10 / 8 = 1.25x, exact 1.26x) and +13 dB is +10 +3
// (x20, exact 19.95x). The estimate and the exact ratio are always shown
// side by side, so the rule never stands in for the arithmetic.
//
// THE SCALE. The slider runs -80 to -60 dBm against a fixed -70 dBm
// reference. The linear milliwatt bar's full length is the top of the
// slider, -60 dBm, so -80, -70, -67 and -60 dBm sit at 1%, 10%, 20% and 100%
// of it: both rules are visible on one linear bar and nothing shrinks below
// what a screen can draw.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kDbRulesToolId = 'db-rules';

/// One rule step: +10, -10, +3 or -3 dB.
enum DbStep {
  plusTen(10, 'x10'),
  minusTen(-10, '/10'),
  plusThree(3, 'x2'),
  minusThree(-3, '/2');

  const DbStep(this.db, this.effect);

  /// The step in dB.
  final int db;

  /// What the rule says it does to the power.
  final String effect;

  String get label => db > 0 ? '+$db' : '$db';
}

/// How a whole number of dB breaks into rule steps.
class DbRulePath {
  const DbRulePath({required this.tens, required this.threes});

  /// Signed count of 10 dB steps.
  final int tens;

  /// Signed count of 3 dB steps.
  final int threes;

  int get db => 10 * tens + 3 * threes;

  /// The rule's estimate of the power ratio: 10^tens x 2^threes.
  double get ruleRatio =>
      math.pow(10, tens).toDouble() * math.pow(2, threes).toDouble();

  /// The steps in order: tens first, then threes.
  List<DbStep> get steps => <DbStep>[
    for (int i = 0; i < tens.abs(); i++)
      tens > 0 ? DbStep.plusTen : DbStep.minusTen,
    for (int i = 0; i < threes.abs(); i++)
      threes > 0 ? DbStep.plusThree : DbStep.minusThree,
  ];
}

abstract final class DbRules {
  /// Slider range and default, dBm.
  static const int minDbm = -80;
  static const int maxDbm = -60;
  static const int referenceDbm = -70;
  static const int defaultDbm = -70;

  /// The prediction's level.
  static const int predictDbm = -67;

  /// The dBm / Watt Converter's formula: mW = 10^(dBm / 10).
  static double dbmToMw(num dbm) => math.pow(10, dbm / 10).toDouble();

  /// Picowatts (trillionths of a watt): 1 mW is 10^9 pW.
  static double dbmToPw(num dbm) => dbmToMw(dbm) * 1e9;

  /// Power ratio of a difference of [db] decibels: 10^(dB / 10).
  static double ratio(num db) => math.pow(10, db / 10).toDouble();

  /// Share of the linear bar's full length (-60 dBm) that [dbm] fills.
  static double barShare(num dbm) => dbmToMw(dbm) / dbmToMw(maxDbm);

  /// The fewest rule steps (tens and threes) that add to [db].
  static DbRulePath path(int db) {
    DbRulePath? best;
    for (int tens = -12; tens <= 12; tens++) {
      final int rest = db - 10 * tens;
      if (rest % 3 != 0) continue;
      final DbRulePath p = DbRulePath(tens: tens, threes: rest ~/ 3);
      final int cost = p.tens.abs() + p.threes.abs();
      if (best == null ||
          cost < best.tens.abs() + best.threes.abs() ||
          (cost == best.tens.abs() + best.threes.abs() &&
              p.threes.abs() < best.threes.abs())) {
        best = p;
      }
    }
    return best!;
  }

  /// The headline: "1.995x, about double the power", or "1x, the same
  /// power" when there is no difference.
  static String powerWords(int db) =>
      db == 0 ? ratioWords(0) : '${ratioWords(db)} the power';

  /// The ratio in words for a whole number of dB, with the nearest plain
  /// phrase: "1.995x, about double" for +3 dB.
  static String ratioWords(int db) {
    if (db == 0) return '1x, the same power';
    final double r = ratio(db);
    final String exact = DbFormat.ratio(r);
    final String? plain = switch (db) {
      3 => 'about double',
      -3 => 'about half',
      6 => 'about four times',
      -6 => 'about a quarter',
      9 => 'about eight times',
      -9 => 'about an eighth',
      10 => 'exactly ten times',
      -10 => 'exactly a tenth',
      20 => 'exactly a hundred times',
      -20 => 'exactly a hundredth',
      _ => null,
    };
    return plain == null ? exact : '$exact, $plain';
  }
}

/// Number formatting shared by stage, controls and copy text.
abstract final class DbFormat {
  /// "1.995x" for ratios near 1 to 10, fewer decimals above; fractions of
  /// one as "0.501x".
  static String ratio(double r) {
    if (r >= 100) return '${r.toStringAsFixed(0)}x';
    if (r >= 10) return '${r.toStringAsFixed(1)}x';
    return '${r.toStringAsFixed(3)}x';
  }

  /// Rule estimate: whole numbers bare, fractions to two decimals.
  static String rule(double r) {
    if ((r - r.roundToDouble()).abs() < 1e-9 && r >= 1) {
      return '${r.round()}x';
    }
    return '${r >= 1 ? r.toStringAsFixed(2) : r.toStringAsFixed(3)}x';
  }

  /// Picowatts, one decimal: "199.5 pW".
  static String pw(double pw) => '${pw.toStringAsFixed(1)} pW';

  /// A signed dB difference: "+3 dB", "0 dB", "-7 dB".
  static String dbDiff(int db) => db > 0 ? '+$db dB' : '$db dB';

  static String dbm(int dbm) => '$dbm dBm';
}
