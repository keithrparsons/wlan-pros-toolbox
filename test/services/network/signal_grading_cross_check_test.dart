// Cross-surface guard for RSSI signal grading (audit finding F2).
//
// THE MISSING TEST that let 1.7.1 ship. Two surfaces grade RSSI:
//   1. The VERDICT / Live engine — WifiGrading.gradeRssi (numeric, on
//      WifiGradingBands.kRssiBands minDbm bounds). This is what fires R-10/R-11/
//      R-12 and drives the Live grade word.
//   2. The Signal Thresholds REFERENCE SCREEN — the ranges it PRINTS in
//      SignalThresholdsScreen.kSignalBands, which the user reads off the table.
//
// In 1.7.1 these two disagreed (engine graded -73/-74 dBm "Poor / no plan will
// help", the reference table called the same reading "Fair / usable") because
// they were hand-maintained copies and NOTHING compared them. This test walks
// every dBm from -30 to -100 and FAILS THE BUILD the moment the graded grade
// and the printed grade disagree on a single reading.
//
// The reference-screen side is derived ONLY from the printed range STRINGS —
// deliberately independent of the numeric constants — so this genuinely
// compares the two user-facing representations, not a constant against itself
// ([[feedback_tests_that_cannot_fail]]). Expected grades in the boundary group
// are hand-typed from Keith's confirmed bands, never read back from the code.

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart' show QualityGrade;
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_grading.dart';

/// Maps a reference-table quality word to the grade it stands for.
QualityGrade _labelToGrade(String label) {
  switch (label) {
    case 'Excellent':
      return QualityGrade.excellent;
    case 'Good':
      return QualityGrade.good;
    case 'Fair':
      return QualityGrade.fair;
    case 'Poor':
      return QualityGrade.poor;
    default:
      fail('Unknown reference band label "$label".');
  }
}

/// True if [dbm] falls inside a reference-table range STRING, read the way a
/// user reads it. Parses the printed text ("> -60 dBm", "-60 to -67", "-73 or
/// weaker") into a predicate. Independent of WifiGradingBands numeric bounds on
/// purpose — this is the "what the screen shows" surface.
bool _rangeContains(String range, int dbm) {
  final List<int> nums = RegExp(r'-?\d+')
      .allMatches(range)
      .map((RegExpMatch m) => int.parse(m.group(0)!))
      .toList();
  expect(nums, isNotEmpty, reason: 'Unparseable reference range "$range".');
  if (range.contains('>')) return dbm > nums.first; // "> -60 dBm"
  if (range.contains('weaker')) return dbm <= nums.first; // "-73 or weaker"
  if (range.contains('<')) return dbm < nums.first; // "< -80 dBm" legacy form
  // "A to B", less-negative first, e.g. "-60 to -67": inclusive both ends.
  final int hi = nums.reduce((int a, int b) => a > b ? a : b);
  final int lo = nums.reduce((int a, int b) => a < b ? a : b);
  return dbm <= hi && dbm >= lo;
}

/// The grade a user would take off the REFERENCE SCREEN for [dbm]: the first
/// band (strongest-first, the way you read a table top to bottom) whose printed
/// range contains the reading.
QualityGrade _referenceScreenGrade(int dbm) {
  for (final SignalBand band in SignalThresholdsScreen.kSignalBands) {
    if (_rangeContains(band.range, dbm)) return _labelToGrade(band.label);
  }
  fail('No reference band covers $dbm dBm — the printed scale has a gap.');
}

void main() {
  group('RSSI grading — engine vs reference screen agree (F2 guard)', () {
    test(
        'the verdict engine and the reference screen assign the SAME grade at '
        'every dBm from -30 to -100', () {
      // This is the guard that would have caught 1.7.1. If either surface
      // drifts (a constant edited without the display, or vice versa), some
      // reading flips and this fails, naming the exact dBm.
      final List<String> disagreements = <String>[];
      for (int dbm = -30; dbm >= -100; dbm--) {
        final QualityGrade engine = WifiGrading.gradeRssi(dbm);
        final QualityGrade screen = _referenceScreenGrade(dbm);
        if (engine != screen) {
          disagreements.add('$dbm dBm: engine=${engine.name} '
              'screen=${screen.name}');
        }
      }
      expect(
        disagreements,
        isEmpty,
        reason: 'The verdict engine and the Signal Thresholds screen disagree '
            'on these readings — the exact class of drift that shipped in '
            '1.7.1:\n${disagreements.join('\n')}',
      );
    });

    test('the -73/-74 dBm regression: both surfaces now say Poor', () {
      // The 1.7.1 headline bug: the engine fired R-10 "Poor / no plan will
      // help" while the reference table called -73/-74 "Fair / usable". Pin it
      // shut on both surfaces.
      for (final int dbm in <int>[-73, -74]) {
        expect(WifiGrading.gradeRssi(dbm), QualityGrade.poor, reason: '$dbm');
        expect(_referenceScreenGrade(dbm), QualityGrade.poor, reason: '$dbm');
      }
    });

    test('four bands, no orphaned "Weak", labels strongest-first', () {
      expect(
        SignalThresholdsScreen.kSignalBands.map((SignalBand b) => b.label),
        <String>['Excellent', 'Good', 'Fair', 'Poor'],
      );
    });

    test('reference colour tier matches the graded quality', () {
      // Excellent/Good -> success, Fair -> warning, Poor -> danger. Guards the
      // QualityGrade -> SignalGrade presentation map.
      for (final SignalBand b in SignalThresholdsScreen.kSignalBands) {
        final QualityGrade q = _labelToGrade(b.label);
        final SignalGrade expected =
            (q == QualityGrade.excellent || q == QualityGrade.good)
                ? SignalGrade.good
                : q == QualityGrade.fair
                    ? SignalGrade.marginal
                    : SignalGrade.bad;
        expect(b.grade, expected, reason: b.label);
      }
    });
  });

  group('RSSI boundary grades — hand-derived from Keith\'s confirmed bands', () {
    // Expected values typed from Keith's bands (Excellent > -60, Good -60..-67,
    // Fair -67..-72, Poor -73 or weaker), NOT read back from WifiGradingBands.
    test('Excellent: rssi > -60 (so -59 in, -60 out)', () {
      expect(WifiGrading.gradeRssi(-30), QualityGrade.excellent);
      expect(WifiGrading.gradeRssi(-59), QualityGrade.excellent);
      expect(WifiGrading.gradeRssi(-60), isNot(QualityGrade.excellent));
    });
    test('Good: -60 down to -67 inclusive', () {
      expect(WifiGrading.gradeRssi(-60), QualityGrade.good);
      expect(WifiGrading.gradeRssi(-67), QualityGrade.good);
    });
    test('Fair: -68 down to -72 (-67 is Good, -73 is Poor)', () {
      expect(WifiGrading.gradeRssi(-68), QualityGrade.fair);
      expect(WifiGrading.gradeRssi(-72), QualityGrade.fair);
    });
    test('Poor: -73 and weaker', () {
      expect(WifiGrading.gradeRssi(-73), QualityGrade.poor);
      expect(WifiGrading.gradeRssi(-90), QualityGrade.poor);
    });
  });
}
