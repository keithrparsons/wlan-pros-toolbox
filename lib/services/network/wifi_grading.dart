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
// ── BANDS ARE KEITH-REVIEWED THRESHOLDS ──
// The dBm / dB cut points below are Keith's reviewed thresholds. The RSSI scale
// is Keith Parsons field cutoffs, 1 Nov 2026 (Excellent -67 or better, Good
// -68 to -72, Fair -73 to -75, Poor -76 or worse). These replace the earlier
// scale (Excellent > -60, Good -60..-67, Fair -68..-72, Poor -73 or weaker).
//
// SINGLE SOURCE OF TRUTH. These live as named constants — and, for RSSI, as the
// [WifiGradingBands.kRssiBands] list — in ONE place. BOTH the grading engine
// ([WifiGrading.gradeRssi], used by Live mode AND the Analyze verdict engine)
// and the Signal Thresholds reference screen read from this one list, so the
// number the app GRADES on can never drift from the number it SHOWS the user.
// Toolbox 1.7.1 shipped THREE divergent RSSI scales because the engine and the
// reference screen were hand-maintained copies with nothing comparing them
// (audit findings F1/F2). Do not re-introduce a second copy — change the bands
// HERE only.

import 'package:net_quality/net_quality.dart' show QualityGrade;

/// One canonical RSSI grade band — the SINGLE SOURCE OF TRUTH for signal
/// grading. Both the grading engine ([WifiGrading.gradeRssi], driving Live mode
/// and the Analyze verdict engine) and the Signal Thresholds reference screen
/// render from [WifiGradingBands.kRssiBands], so the graded number and the
/// displayed number cannot drift apart again (1.7.1 shipped three divergent
/// RSSI scales; audit findings F1/F2).
class RssiBand {
  const RssiBand({
    required this.grade,
    required this.label,
    required this.minDbm,
    required this.displayRange,
  });

  /// The quality grade a reading in this band receives.
  final QualityGrade grade;

  /// Human label for the reference table ("Excellent", "Good", "Fair", "Poor").
  final String label;

  /// Inclusive lower bound of the band in dBm, evaluated strongest-first. The
  /// weakest band (Poor) uses [WifiGradingBands.rssiNoFloor] — nothing grades
  /// weaker than Poor.
  final int minDbm;

  /// The range exactly as the reference table prints it, e.g. "-67 dBm or better",
  /// "-68 to -72". Human-readable; the numeric grading uses [minDbm]. A
  /// cross-check test fails the build if this string ever disagrees with the
  /// grade [WifiGrading.gradeRssi] computes.
  final String displayRange;
}

/// Tunable grade bands for the Live-mode RF dimensions.
///
/// Keith-reviewed thresholds; the RSSI scale is Keith Parsons field cutoffs,
/// 1 Nov 2026. All thresholds are expressed as the inclusive lower bound of each
/// band, evaluated top-down. The bands are contiguous and unambiguous: each
/// integer reading falls into exactly one band.
class WifiGradingBands {
  WifiGradingBands._();

  // ── RSSI (received signal strength, dBm; less-negative is stronger) ──────
  // Source: Keith Parsons field cutoffs, 1 Nov 2026.
  //   rssi >= -67          Excellent (-67 Excellent)
  //   -72 <= rssi <= -68   Good      (-68 Good, -72 Good)
  //   -75 <= rssi <= -73   Fair      (-73 Fair, -75 Fair)
  //   rssi <= -76          Poor

  /// RSSI at or above this (dBm) grades Excellent, so -67 is Excellent.
  /// Source: Keith Parsons field cutoffs, 1 Nov 2026.
  static const int rssiExcellentDbm = -67;

  /// RSSI at or above this (dBm), below [rssiExcellentDbm], grades Good. So -68
  /// and -72 are both Good. Source: Keith Parsons field cutoffs, 1 Nov 2026.
  static const int rssiGoodDbm = -72;

  /// RSSI at or above this (dBm), below [rssiGoodDbm], grades Fair. So -73 and
  /// -75 are Fair; -76 and weaker grade Poor. Source: Keith Parsons field
  /// cutoffs, 1 Nov 2026.
  static const int rssiFairDbm = -75;

  /// Sentinel lower bound for the weakest band: no reading is below Poor. Used
  /// as the Poor band's [RssiBand.minDbm] so the strongest-first scan always
  /// terminates on a match.
  static const int rssiNoFloor = -1000;

  /// Keith's RSSI grade scale (four grades; Keith Parsons field cutoffs,
  /// 1 Nov 2026). THE single source of truth: [WifiGrading.gradeRssi] derives
  /// its grade from this list, and SignalThresholdsScreen renders its RSSI
  /// quality scale from it. Do not hand-copy these numbers into a screen —
  /// extend or edit them HERE only. Keith's note: these bands are a convention,
  /// not physics ("I've had great connectivity at -75 dBm"), so the verdict
  /// copy hedges rather than stating a band as a hard fact.
  static const List<RssiBand> kRssiBands = <RssiBand>[
    RssiBand(
      grade: QualityGrade.excellent,
      label: 'Excellent',
      minDbm: rssiExcellentDbm, // -67 or better
      displayRange: '-67 dBm or better',
    ),
    RssiBand(
      grade: QualityGrade.good,
      label: 'Good',
      minDbm: rssiGoodDbm, // -68 to -72
      displayRange: '-68 to -72',
    ),
    RssiBand(
      grade: QualityGrade.fair,
      label: 'Fair',
      minDbm: rssiFairDbm, // -73 to -75
      displayRange: '-73 to -75',
    ),
    RssiBand(
      grade: QualityGrade.poor,
      label: 'Poor',
      minDbm: rssiNoFloor, // -76 or worse
      displayRange: '-76 or worse',
    ),
  ];

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

  /// Grades an RSSI reading (dBm) against the canonical
  /// [WifiGradingBands.kRssiBands] — the SAME list the Signal Thresholds
  /// reference screen renders, so the graded grade and the displayed band never
  /// disagree. A null reading is honestly [QualityGrade.unavailable] — never a
  /// guessed grade. Bands are scanned strongest-first; each band's [minDbm] is
  /// its inclusive lower bound.
  static QualityGrade gradeRssi(int? rssiDbm) {
    if (rssiDbm == null) return QualityGrade.unavailable;
    for (final RssiBand band in WifiGradingBands.kRssiBands) {
      if (rssiDbm >= band.minDbm) return band.grade;
    }
    return QualityGrade.poor; // unreachable: the Poor band has no floor.
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
