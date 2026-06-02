// Wi-Fi Live per-dimension grading (TICKET-01, Live mode).
//
// Live mode grades the streamed RF fields one dimension at a time, in the
// house grade-gate style established by `net_quality` and the
// `wifi-vs-internet` tool: we reuse [QualityGrade] (Excellent / Good / Fair /
// Poor / Unavailable) and we deliberately do NOT collapse the per-dimension
// grades into a single composite "score". Each metric stands alone, the grade
// WORD always carries the meaning (the color only reinforces it), and an
// unmeasurable field grades [QualityGrade.unavailable] — never a fabricated
// value.
//
// What is graded vs. what only trends:
//   * RSSI (dBm) and SNR (dB) get a hard grade against standard bands.
//   * Tx rate and Rx rate get a TREND (rising / falling / steady) over the
//     rolling window, NOT a hard grade — a "good" data rate is entirely
//     relative to band, width, MCS, and the negotiated PHY, so a fixed Mbps
//     threshold would be dishonest. The value + its direction is the honest
//     signal.
//   * Congestion / CCA is intentionally absent: iOS does not expose channel
//     utilization or clear-channel-assessment, and we do not derive a busy
//     percentage from RSSI/SNR/rate (that would be a fabricated number). The
//     Live UI omits it rather than fake it (TICKET-01 §scope-5, GL-005).
//
// ── BANDS ARE KEITH-REVIEWED THRESHOLDS (2026-06-01) ───────────────────────
// The dBm / dB cut points below are Keith's reviewed thresholds, ratified
// 2026-06-01 (no longer starting values pending tuning). They live as named
// constants in ONE place so the exact thresholds stay reviewable in one spot
// without touching the UI or the grading logic. Do not scatter literals into
// the screen — change them HERE.

import 'package:net_quality/net_quality.dart' show QualityGrade;

/// Tunable grade bands for the Live-mode RF dimensions.
///
/// Keith-reviewed thresholds (2026-06-01). All thresholds are expressed as the
/// inclusive lower bound of each band, evaluated top-down. The bands are
/// contiguous and unambiguous: each integer reading falls into exactly one band.
class WifiGradingBands {
  WifiGradingBands._();

  // ── RSSI (received signal strength, dBm; less-negative is stronger) ──────
  // Keith-reviewed thresholds (2026-06-01).
  //   rssi >  -60          Excellent
  //   -67 <= rssi <= -60   Good   (-60 Good, -67 Good)
  //   -72 <= rssi <  -67   Fair   (-72 Fair)
  //   rssi <  -72          Poor

  /// RSSI at or above this (dBm) grades Excellent. Equivalent to rssi > -60 for
  /// integer readings. Keith-reviewed threshold (2026-06-01).
  static const int rssiExcellentDbm = -59;

  /// RSSI at or above this (dBm), below [rssiExcellentDbm], grades Good. So -60
  /// and -67 are both Good. Keith-reviewed threshold (2026-06-01).
  static const int rssiGoodDbm = -67;

  /// RSSI at or above this (dBm), below [rssiGoodDbm], grades Fair. So -72 is
  /// Fair; below it grades Poor. Keith-reviewed threshold (2026-06-01).
  static const int rssiFairDbm = -72;

  // ── SNR (signal-to-noise ratio, dB; higher is better) ────────────────────
  // Keith-reviewed thresholds (2026-06-01).
  //   snr >  35          Excellent
  //   25 <= snr <= 35    Good   (35 Good, 25 Good)
  //   15 <= snr <  25    Fair   (15 Fair)
  //   snr <  15          Poor

  /// SNR at or above this (dB) grades Excellent. Equivalent to snr > 35 for
  /// integer readings. Keith-reviewed threshold (2026-06-01).
  static const int snrExcellentDb = 36;

  /// SNR at or above this (dB), below [snrExcellentDb], grades Good. So 35 and
  /// 25 are both Good. Keith-reviewed threshold (2026-06-01).
  static const int snrGoodDb = 25;

  /// SNR at or above this (dB), below [snrGoodDb], grades Fair. So 15 is Fair;
  /// below it grades Poor. Keith-reviewed threshold (2026-06-01).
  static const int snrFairDb = 15;

  /// Sample-to-sample change (in the field's own unit) at or below which a
  /// rate is reported "Steady" rather than Rising / Falling. Compared against
  /// the difference between the first and last samples of the rolling window.
  /// Starting value: pending tuning.
  static const double rateSteadyEpsilonMbps = 12;
}

/// Direction a streamed rate is moving across the rolling window. Rates are
/// NOT hard-graded (see file header); the trend is the honest signal.
enum WifiRateTrend {
  rising,
  falling,
  steady,

  /// Not enough samples (or no samples) to determine a direction.
  unavailable,
}

/// Human-readable labels for [WifiRateTrend].
extension WifiRateTrendLabel on WifiRateTrend {
  String get label {
    switch (this) {
      case WifiRateTrend.rising:
        return 'Rising';
      case WifiRateTrend.falling:
        return 'Falling';
      case WifiRateTrend.steady:
        return 'Steady';
      case WifiRateTrend.unavailable:
        return 'Unavailable';
    }
  }
}

/// Pure grading functions for Live mode. Stateless; the rolling window lives in
/// the screen, the bands live in [WifiGradingBands], the math lives here.
class WifiGrading {
  WifiGrading._();

  /// Grades an RSSI reading (dBm) against [WifiGradingBands]. A null reading is
  /// honestly [QualityGrade.unavailable] — never a guessed grade.
  static QualityGrade gradeRssi(int? rssiDbm) {
    if (rssiDbm == null) return QualityGrade.unavailable;
    if (rssiDbm >= WifiGradingBands.rssiExcellentDbm) {
      return QualityGrade.excellent;
    }
    if (rssiDbm >= WifiGradingBands.rssiGoodDbm) return QualityGrade.good;
    if (rssiDbm >= WifiGradingBands.rssiFairDbm) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Grades an SNR reading (dB) against [WifiGradingBands]. A null reading is
  /// honestly [QualityGrade.unavailable].
  static QualityGrade gradeSnr(int? snrDb) {
    if (snrDb == null) return QualityGrade.unavailable;
    if (snrDb >= WifiGradingBands.snrExcellentDb) return QualityGrade.excellent;
    if (snrDb >= WifiGradingBands.snrGoodDb) return QualityGrade.good;
    if (snrDb >= WifiGradingBands.snrFairDb) return QualityGrade.fair;
    return QualityGrade.poor;
  }

  /// Reports the trend of a rate across an ordered (oldest→newest) window of
  /// samples. Compares the first and last present samples; a change within
  /// [WifiGradingBands.rateSteadyEpsilonMbps] is Steady. Fewer than two present
  /// samples is [WifiRateTrend.unavailable].
  static WifiRateTrend rateTrend(List<double?> window) {
    final List<double> present =
        window.whereType<double>().toList(growable: false);
    if (present.length < 2) return WifiRateTrend.unavailable;
    final double delta = present.last - present.first;
    if (delta.abs() <= WifiGradingBands.rateSteadyEpsilonMbps) {
      return WifiRateTrend.steady;
    }
    return delta > 0 ? WifiRateTrend.rising : WifiRateTrend.falling;
  }
}
