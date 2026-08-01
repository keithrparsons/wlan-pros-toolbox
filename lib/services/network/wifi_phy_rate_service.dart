// WifiPhyRateService — Wi-Fi PHY-rate and estimated-real-throughput math.
//
// Pure Dart. No Flutter import, no network, no platform APIs, no state: every
// member is a compile-time constant table or a static function of its
// arguments, so this is unit-testable without a widget pump.
//
// ── PROVENANCE (carried verbatim from the calculator screen this was extracted
// from, 2026-07-31). These tables are a VALUE-FOR-VALUE port of the RF Tools
// PWA (`app.js`), specifically `calcThroughput` for the math and
// `updateTputOptions` for the dependent option sets. The PWA names map to the
// members here one-to-one:
//
//   PWA MCS_BPS       -> [WifiPhyRateService.mcsBps]
//   PWA MCS_MOD       -> [WifiPhyRateService.mcsMod]
//   PWA TPUT_NSD      -> [WifiPhyRateService.nsd]
//   PWA TPUT_SYM      -> [WifiPhyRateService.sym]
//   PWA TPUT_MAX_MCS  -> [WifiPhyRateService.maxMcs]
//   PWA TPUT_EFF      -> [WifiPhyRateService.eff]
//   PWA updateTputOptions bwOpts / giOpts / maxSS
//                     -> [bandwidths] / [giKeys] / [maxStreams]
//
// A constant whose origin is not written down is a constant nobody can check.
// If you change a number here, change the PWA reference too, or say why not.
//
// Formula (PWA calcThroughput):
//   phyRate(Mbps)  = (Nsd · bitsPerSymbol · streams) / symbolTime(µs)
//   realRate(Mbps) = phyRate · efficiency(std)
// where Nsd is data subcarriers (per standard per width), bitsPerSymbol is
// MCS_BPS[mcs] (Nbpsc·Rc), symbolTime is the OFDM symbol duration (per standard
// per guard interval), and efficiency is the per-standard real/PHY factor.
//
// EDGE CASES (both return null, the PWA showError paths):
//  - An invalid bandwidth / guard-interval combination for the standard. The
//    calculator's reclamp logic prevents this in normal use, but the pure math
//    guards it anyway so the function never divides by a missing Nsd or symbol
//    time.
//  - An MCS index above the standard's max (or below zero), zero/negative
//    spatial streams, or an MCS beyond the [mcsBps] table.
//
// HONESTY NOTE on [eff]: these are OPTIMISTIC real/PHY factors (HT 0.70 through
// EHT 0.80), at or above the practical best case usually cited. `realRateMbps`
// is therefore a FAVORABLE estimate of achievable throughput, and must never
// be presented as a target a user is failing to hit.
//
// HISTORY: extracted 2026-07-31 from
// `lib/screens/tools/calculators/throughput_calc_screen.dart`, where these
// members lived as statics on the `ThroughputCalcScreen` widget. Not one
// numeric value changed in the move. The screen's statics remain as thin
// delegates so existing call sites and tests keep working.

/// Wi-Fi standard, mirroring the PWA tput-std select (ht/vht/he/eht).
enum WifiStd { ht, vht, he, eht }

/// PHY-rate math for a Wi-Fi link, given standard, channel width, MCS index,
/// spatial streams, and guard interval.
///
/// Stateless: use the static members directly. The const constructor exists
/// only so the type can be referenced as a value where that reads better.
class WifiPhyRateService {
  const WifiPhyRateService();

  // ─── Constant tables (ports of app.js) ────────────────────────────────────

  /// Bits per symbol per MCS — Nbpsc · Rc (PWA MCS_BPS).
  static const List<double> mcsBps = <double>[
    0.5,
    1.0,
    1.5,
    2.0,
    3.0,
    4.0,
    4.5,
    5.0,
    6.0,
    6.6667,
    7.5,
    8.3333,
    9.0,
    10.0,
  ];

  /// Modulation label per MCS (PWA MCS_MOD).
  static const List<String> mcsMod = <String>[
    'BPSK ½',
    'QPSK ½',
    'QPSK ¾',
    '16-QAM ½',
    '16-QAM ¾',
    '64-QAM ⅔',
    '64-QAM ¾',
    '64-QAM ⅚',
    '256-QAM ¾',
    '256-QAM ⅚',
    '1024-QAM ¾',
    '1024-QAM ⅚',
    '4096-QAM ¾',
    '4096-QAM ⅚',
  ];

  /// Long MCS label (index — modulation) for the MCS select (PWA mcsLabels).
  static String mcsLabel(int mcs) => 'MCS $mcs: ${mcsMod[mcs]}';

  /// Data subcarriers per standard per channel width MHz (PWA TPUT_NSD).
  static const Map<WifiStd, Map<int, int>> nsd = <WifiStd, Map<int, int>>{
    WifiStd.ht: <int, int>{20: 52, 40: 108},
    WifiStd.vht: <int, int>{20: 52, 40: 108, 80: 234, 160: 468},
    WifiStd.he: <int, int>{20: 234, 40: 468, 80: 980, 160: 1960},
    WifiStd.eht: <int, int>{20: 234, 40: 468, 80: 980, 160: 1960, 320: 3920},
  };

  /// OFDM symbol duration µs per standard per guard interval key (PWA
  /// TPUT_SYM).
  static const Map<WifiStd, Map<String, double>> sym =
      <WifiStd, Map<String, double>>{
    WifiStd.ht: <String, double>{'0.4': 3.6, '0.8': 4.0},
    WifiStd.vht: <String, double>{'0.4': 3.6, '0.8': 4.0},
    WifiStd.he: <String, double>{'0.8': 13.6, '1.6': 14.4, '3.2': 16.0},
    WifiStd.eht: <String, double>{'0.8': 13.6, '1.6': 14.4, '3.2': 16.0},
  };

  /// Highest valid MCS index per standard (PWA TPUT_MAX_MCS).
  static const Map<WifiStd, int> maxMcs = <WifiStd, int>{
    WifiStd.ht: 7,
    WifiStd.vht: 9,
    WifiStd.he: 11,
    WifiStd.eht: 13,
  };

  /// Real-throughput efficiency vs PHY rate per standard (PWA TPUT_EFF).
  ///
  /// Optimistic by design — see the HONESTY NOTE in the file header.
  static const Map<WifiStd, double> eff = <WifiStd, double>{
    WifiStd.ht: 0.70,
    WifiStd.vht: 0.72,
    WifiStd.he: 0.76,
    WifiStd.eht: 0.80,
  };

  /// Bandwidth options MHz per standard (PWA updateTputOptions bwOpts).
  static const Map<WifiStd, List<int>> bandwidths = <WifiStd, List<int>>{
    WifiStd.ht: <int>[20, 40],
    WifiStd.vht: <int>[20, 40, 80, 160],
    WifiStd.he: <int>[20, 40, 80, 160],
    WifiStd.eht: <int>[20, 40, 80, 160, 320],
  };

  /// Guard-interval option keys per standard, in display order. Keys index into
  /// [sym] (PWA updateTputOptions giOpts).
  static const Map<WifiStd, List<String>> giKeys = <WifiStd, List<String>>{
    WifiStd.ht: <String>['0.4', '0.8'],
    WifiStd.vht: <String>['0.4', '0.8'],
    WifiStd.he: <String>['0.8', '1.6', '3.2'],
    WifiStd.eht: <String>['0.8', '1.6', '3.2'],
  };

  /// Max spatial streams per standard, capped at 8 (PWA updateTputOptions
  /// maxSS).
  static const Map<WifiStd, int> maxStreams = <WifiStd, int>{
    WifiStd.ht: 4,
    WifiStd.vht: 8,
    WifiStd.he: 8,
    WifiStd.eht: 8,
  };

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js calcThroughput.

  /// PHY rate in Mbps, or null when the bandwidth / guard-interval combination
  /// is invalid for the standard or the MCS exceeds the standard's max — the
  /// PWA showError paths. (nsd · MCS_BPS[mcs] · ss) / sym.
  static double? phyRateMbps({
    required WifiStd std,
    required int bandwidthMHz,
    required int mcs,
    required int streams,
    required String giKey,
  }) {
    final int? n = nsd[std]?[bandwidthMHz];
    final double? s = sym[std]?[giKey];
    final int? max = maxMcs[std];
    if (n == null || s == null || s <= 0) return null;
    if (max == null || mcs < 0 || mcs > max) return null;
    if (mcs >= mcsBps.length) return null;
    if (streams <= 0) return null;
    return (n * mcsBps[mcs] * streams) / s;
  }

  /// Estimated real throughput in Mbps — phyRate · efficiency(std). Null when
  /// the PHY rate is null (same invalid-combination guard).
  static double? realRateMbps({
    required WifiStd std,
    required int bandwidthMHz,
    required int mcs,
    required int streams,
    required String giKey,
  }) {
    final double? phy = phyRateMbps(
      std: std,
      bandwidthMHz: bandwidthMHz,
      mcs: mcs,
      streams: streams,
      giKey: giKey,
    );
    final double? e = eff[std];
    if (phy == null || e == null) return null;
    return phy * e;
  }
}
