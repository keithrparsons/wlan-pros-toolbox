// Wi-Fi Live per-dimension grading (TICKET-01, Live mode).
//
// Live mode grades the streamed RF fields one dimension at a time, in the
// house grade-gate style established by `net_quality` and the
// `wifi-vs-internet` tool: we reuse [QualityGrade] (Excellent / Good / Fair /
// Poor / Unusable / Unavailable) and we deliberately do NOT collapse the per-dimension
// grades into a single composite "score". Each metric stands alone, the grade
// WORD always carries the meaning (the color only reinforces it), and an
// unmeasurable field grades [QualityGrade.unavailable] — never a fabricated
// value.
//
// What is graded vs. what only trends:
//   * RSSI (dBm) and SNR (dB) get a hard grade against the app's bands. The
//     RSSI bands are Keith Parsons' defaults, which the user can change in
//     settings (there is no industry consensus on RSSI bands).
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
// ── RSSI BANDS: KEITH'S DEFAULTS, USER-SETTABLE ──────────────────────────────
// The RSSI bands are NOT defined here any more. They live in ONE place,
// [RssiScaleStore.instance] (rssi_scale.dart): Keith Parsons' default scale
// (master scale, 19 Nov 2026: Excellent -66 dBm and stronger, Good -67 to -72,
// Fair -73 to -78, Poor -79 to -84, Unusable -85 and weaker) plus any
// boundaries the user set in the Signal Bands settings screen. There is no
// industry consensus on RSSI bands, so none of this is presented as a standard.
//
// SINGLE SOURCE OF TRUTH. The grading engine ([WifiGrading.gradeRssi], used by
// Live mode, Wi-Fi Info, Check My Connection, the Analyze verdict engine and the
// triage ladder) and the Signal Thresholds reference screen all read the same
// store, so the number the app GRADES on can never drift from the number it
// SHOWS the user. Toolbox 1.7.1 shipped THREE divergent RSSI scales because the
// engine and the reference screen were hand-maintained copies (audit findings
// F1/F2). Do not re-introduce a second copy.

import 'package:net_quality/net_quality.dart' show QualityGrade;

import 'rssi_scale.dart';

export 'rssi_scale.dart' show RssiBand, RssiScale, RssiScaleStore;

/// Tunable grade bands for the Live-mode RF dimensions.
///
/// RSSI comes from the user-settable [RssiScaleStore] (Keith's defaults until
/// the user changes them). SNR thresholds are Keith-reviewed constants. All
/// thresholds are the inclusive lower bound of each band, evaluated top-down,
/// so each integer reading falls into exactly one band.
class WifiGradingBands {
  WifiGradingBands._();

  /// The RSSI bands in force right now, strongest first: Keith's defaults or
  /// the user's own boundaries. Read fresh on every call; never cache it.
  static List<RssiBand> get rssiBands => RssiScaleStore.instance.value.bands;

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

  /// Grades an RSSI reading (dBm) against the RSSI scale in force: [scale]
  /// when given, otherwise [RssiScaleStore.instance] (Keith's defaults or the
  /// user's own boundaries), the SAME source the Signal Thresholds screen
  /// renders. A null reading is honestly [QualityGrade.unavailable], never a
  /// guessed grade. Five bands: Excellent, Good, Fair, Poor, Unusable.
  static QualityGrade gradeRssi(int? rssiDbm, {RssiScale? scale}) =>
      (scale ?? RssiScaleStore.instance.value).grade(rssiDbm);

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
    final List<double> present = window.whereType<double>().toList(
      growable: false,
    );
    if (present.length < 2) return WifiRateTrend.unavailable;
    final double delta = present.last - present.first;
    if (delta.abs() <= WifiGradingBands.rateSteadyEpsilonMbps) {
      return WifiRateTrend.steady;
    }
    return delta > 0 ? WifiRateTrend.rising : WifiRateTrend.falling;
  }
}
