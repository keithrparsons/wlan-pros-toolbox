// Cross-surface guard for RSSI signal grading (audit finding F2).
//
// THE MISSING TEST that let 1.7.1 ship. Two surfaces grade RSSI:
//   1. The VERDICT / Live engine: WifiGrading.gradeRssi (numeric, on the
//      RssiScaleStore band minDbm bounds). This is what fires R-10/R-11/R-12
//      and drives the Live grade word.
//   2. The Signal Thresholds REFERENCE SCREEN: the ranges it PRINTS in
//      SignalThresholdsScreen.signalBands(), which the user reads off the
//      table.
//
// Since 19 Nov 2026 the bands are user-settable (Keith Parsons' defaults plus
// the user's overrides), so the agreement walk runs on the defaults AND on
// custom scales.
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
import 'package:shared_preferences/shared_preferences.dart';
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
    case 'Unusable':
      return QualityGrade.unusable;
    default:
      fail('Unknown reference band label "$label".');
  }
}

/// True if [dbm] falls inside a reference-table range STRING, read the way a
/// user reads it. Parses the printed text ("-66 dBm and stronger", "-67 to -72", "-85 and
/// weaker") into a predicate. Independent of WifiGradingBands numeric bounds on
/// purpose — this is the "what the screen shows" surface.
bool _rangeContains(String range, int dbm) {
  final List<int> nums = RegExp(r'-?\d+')
      .allMatches(range)
      .map((RegExpMatch m) => int.parse(m.group(0)!))
      .toList();
  expect(nums, isNotEmpty, reason: 'Unparseable reference range "$range".');
  if (range.contains('stronger')) return dbm >= nums.first; // "-66 dBm and stronger"
  if (range.contains('weaker')) return dbm <= nums.first; // "-85 and weaker"
  if (range.contains('>')) return dbm > nums.first; // "> -60 dBm" legacy form
  if (range.contains('<')) return dbm < nums.first; // "< -80 dBm" legacy form
  if (nums.length == 1) return dbm == nums.first; // a 1 dB band, e.g. "-71"
  // "A to B", less-negative first, e.g. "-67 to -72": inclusive both ends.
  final int hi = nums.reduce((int a, int b) => a > b ? a : b);
  final int lo = nums.reduce((int a, int b) => a < b ? a : b);
  return dbm <= hi && dbm >= lo;
}

/// The grade a user would take off the REFERENCE SCREEN for [dbm]: the first
/// band (strongest-first, the way you read a table top to bottom) whose printed
/// range contains the reading.
QualityGrade _referenceScreenGrade(int dbm) {
  for (final SignalBand band in SignalThresholdsScreen.signalBands()) {
    if (_rangeContains(band.range, dbm)) return _labelToGrade(band.label);
  }
  fail('No reference band covers $dbm dBm — the printed scale has a gap.');
}

/// Custom scales the agreement walk also runs on, including a 1 dB band.
const List<RssiScale> _customScales = <RssiScale>[
  RssiScale(excellentMinDbm: -60, goodMinDbm: -67, fairMinDbm: -72, poorMinDbm: -80),
  RssiScale(excellentMinDbm: -70, goodMinDbm: -71, fairMinDbm: -72, poorMinDbm: -73),
  RssiScale(excellentMinDbm: -30, goodMinDbm: -50, fairMinDbm: -90, poorMinDbm: -100),
];

List<String> _disagreements() {
  final List<String> out = <String>[];
  for (int dbm = -30; dbm >= -110; dbm--) {
    final QualityGrade engine = WifiGrading.gradeRssi(dbm);
    final QualityGrade screen = _referenceScreenGrade(dbm);
    if (engine != screen) {
      out.add('$dbm dBm: engine=${engine.name} screen=${screen.name}');
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  setUp(RssiScaleStore.resetForTest);
  tearDown(RssiScaleStore.resetForTest);

  group('RSSI grading: engine vs reference screen agree (F2 guard)', () {
    test(
        'the verdict engine and the reference screen assign the SAME grade at '
        'every dBm from -30 to -110 (defaults)', () {
      final List<String> d = _disagreements();
      expect(
        d,
        isEmpty,
        reason: 'The verdict engine and the Signal Thresholds screen disagree '
            'on these readings, the exact class of drift that shipped in '
            '1.7.1:\n${d.join('\n')}',
      );
    });

    test('they still agree after the user sets their own bands', () async {
      for (final RssiScale scale in _customScales) {
        await RssiScaleStore.instance.save(scale);
        final List<String> d = _disagreements();
        expect(d, isEmpty, reason: '$scale:\n${d.join('\n')}');
      }
    });

    test('no reading falls inside two printed ranges, or none', () async {
      for (final RssiScale scale in <RssiScale>[
        RssiScale.defaults,
        ..._customScales,
      ]) {
        await RssiScaleStore.instance.save(scale);
        final List<String> overlaps = <String>[];
        for (int dbm = -30; dbm >= -110; dbm--) {
          final List<String> hits = <String>[
            for (final SignalBand b in SignalThresholdsScreen.signalBands())
              if (_rangeContains(b.range, dbm)) b.label,
          ];
          if (hits.length != 1) overlaps.add('$dbm dBm: ${hits.join(', ')}');
        }
        expect(overlaps, isEmpty, reason: '$scale\n${overlaps.join('\n')}');
      }
    });

    test('five bands, labels strongest-first', () {
      expect(
        SignalThresholdsScreen.signalBands().map((SignalBand b) => b.label),
        <String>['Excellent', 'Good', 'Fair', 'Poor', 'Unusable'],
      );
    });

    test('reference color tier matches the graded quality', () {
      // Excellent/Good -> success, Fair -> warning, Poor/Unusable -> danger.
      for (final SignalBand b in SignalThresholdsScreen.signalBands()) {
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

  group('RSSI boundary grades, hand-typed from Keith\'s master scale', () {
    // Expected values typed from Keith's 19 Nov 2026 defaults (Excellent -66
    // and stronger, Good -67 to -72, Fair -73 to -78, Poor -79 to -84,
    // Unusable -85 and weaker), NOT read back from RssiScale.defaults.
    const Map<int, QualityGrade> expected = <int, QualityGrade>{
      -30: QualityGrade.excellent,
      -66: QualityGrade.excellent,
      -67: QualityGrade.good,
      -72: QualityGrade.good,
      -73: QualityGrade.fair,
      -78: QualityGrade.fair,
      -79: QualityGrade.poor,
      -84: QualityGrade.poor,
      -85: QualityGrade.unusable,
      -100: QualityGrade.unusable,
    };
    for (final MapEntry<int, QualityGrade> e in expected.entries) {
      test('${e.key} dBm is ${e.value.name} on both surfaces', () {
        expect(WifiGrading.gradeRssi(e.key), e.value);
        expect(_referenceScreenGrade(e.key), e.value);
      });
    }
  });
}
