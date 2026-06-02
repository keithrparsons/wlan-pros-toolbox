// Wi-Fi Live grading — unit tests (TICKET-01).
//
// Exercises the named band boundaries in [WifiGradingBands] exactly at and just
// across each cut point, plus the honest-unavailable path and the rate-trend
// logic (which is NOT a hard grade).

import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart' show QualityGrade;
import 'package:wlan_pros_toolbox/services/network/wifi_grading.dart';

void main() {
  group('WifiGrading.gradeRssi — band boundaries (Keith-reviewed 2026-06-01)',
      () {
    test('null is honestly Unavailable, never guessed', () {
      expect(WifiGrading.gradeRssi(null), QualityGrade.unavailable);
    });

    test('rssi > -60 is Excellent', () {
      expect(WifiGrading.gradeRssi(-59), QualityGrade.excellent); // just over
      expect(WifiGrading.gradeRssi(-40), QualityGrade.excellent);
      expect(WifiGrading.gradeRssi(-30), QualityGrade.excellent);
    });

    test('-67 <= rssi <= -60 is Good (edges -60 and -67 both Good)', () {
      expect(WifiGrading.gradeRssi(-60), QualityGrade.good); // upper edge
      expect(WifiGrading.gradeRssi(-63), QualityGrade.good);
      expect(WifiGrading.gradeRssi(-67), QualityGrade.good); // lower edge
    });

    test('-72 <= rssi < -67 is Fair (-67 is Good not Fair; -72 is Fair)', () {
      expect(WifiGrading.gradeRssi(-68), QualityGrade.fair); // just below Good
      expect(WifiGrading.gradeRssi(-72), QualityGrade.fair); // lower edge
    });

    test('rssi < -72 is Poor (-73 is Poor)', () {
      expect(WifiGrading.gradeRssi(-73), QualityGrade.poor); // just below Fair
      expect(WifiGrading.gradeRssi(-90), QualityGrade.poor);
    });
  });

  group('WifiGrading.gradeSnr — band boundaries (Keith-reviewed 2026-06-01)',
      () {
    test('null is honestly Unavailable', () {
      expect(WifiGrading.gradeSnr(null), QualityGrade.unavailable);
    });

    test('snr > 35 is Excellent', () {
      expect(WifiGrading.gradeSnr(36), QualityGrade.excellent); // just over
      expect(WifiGrading.gradeSnr(45), QualityGrade.excellent);
      expect(WifiGrading.gradeSnr(60), QualityGrade.excellent);
    });

    test('25 <= snr <= 35 is Good (edges 35 and 25 both Good)', () {
      expect(WifiGrading.gradeSnr(35), QualityGrade.good); // upper edge
      expect(WifiGrading.gradeSnr(30), QualityGrade.good);
      expect(WifiGrading.gradeSnr(25), QualityGrade.good); // lower edge
    });

    test('15 <= snr < 25 is Fair (25 is Good not Fair; 15 is Fair)', () {
      expect(WifiGrading.gradeSnr(24), QualityGrade.fair); // just below Good
      expect(WifiGrading.gradeSnr(15), QualityGrade.fair); // lower edge
    });

    test('snr < 15 is Poor (14 is Poor)', () {
      expect(WifiGrading.gradeSnr(14), QualityGrade.poor); // just below Fair
      expect(WifiGrading.gradeSnr(0), QualityGrade.poor);
    });
  });

  group('WifiGrading.rateTrend — direction, not a hard grade', () {
    test('fewer than two present samples is Unavailable', () {
      expect(WifiGrading.rateTrend(<double?>[]), WifiRateTrend.unavailable);
      expect(WifiGrading.rateTrend(<double?>[100]), WifiRateTrend.unavailable);
      expect(WifiGrading.rateTrend(<double?>[null, null]),
          WifiRateTrend.unavailable);
    });

    test('a rise beyond the epsilon is Rising', () {
      // 200 - 100 = 100 > epsilon (12).
      expect(WifiGrading.rateTrend(<double?>[100, 150, 200]),
          WifiRateTrend.rising);
    });

    test('a fall beyond the epsilon is Falling', () {
      expect(WifiGrading.rateTrend(<double?>[400, 300, 200]),
          WifiRateTrend.falling);
    });

    test('change within the epsilon is Steady', () {
      // 100 -> 108 is within the 12 Mbps steady band.
      expect(WifiGrading.rateTrend(<double?>[100, 105, 108]),
          WifiRateTrend.steady);
    });

    test('nulls (gaps) are skipped; first/last PRESENT samples decide', () {
      // present = [100, 300] -> rising.
      expect(WifiGrading.rateTrend(<double?>[100, null, null, 300]),
          WifiRateTrend.rising);
    });
  });
}
