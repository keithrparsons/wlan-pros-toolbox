// MCS Index reference — a read-only data table of 802.11 MCS rates, offline.
//
// FOUR standards, not three: 802.11n (HT), 802.11ac (VHT), 802.11ax (HE), and
// 802.11be (EHT / Wi-Fi 7 — 320 MHz, MCS 12-13, 4096-QAM). Each table lists,
// per MCS index, the modulation, the coding rate, and the per-spatial-stream
// data rate for each channel-width column. A spatial-streams selector scales
// every rate.
//
// ─── SOURCE OF TRUTH ────────────────────────────────────────────────────────
// Keith Parsons' MCS Index Chart, and mcsindex.net (by @VergesFrancois,
// © SemFio Networks), which Keith explicitly endorsed:
//   https://docs.google.com/spreadsheets/d/e/2PACX-1vQXoEYLGWrR1aGyGaTXOOaDQSPLfeC4rv70KRFuRP6eZ5fL-Ku_YI6DgS6zZMNyIhQpQmnKQ1O7abij/pub?output=csv
// Every value here is transcribed from that table, never from running the code.
// The full source table is pinned cell-by-cell in
// test/screens/reference/mcs_index_source_table_test.dart — that file is the
// oracle, this file is the implementation, and they are kept independent on
// purpose.
//
// ─── THIS SCREEN HAS BEEN WRONG THREE TIMES. READ BEFORE EDITING. ───────────
// 1. A hand-written comment, "// MCS9 invalid at 20 and 40 MHz (1 SS)", nulled
//    VHT MCS 9 at BOTH widths. A human knew the real 20 MHz exclusion and
//    over-generalized it one column to the right. MCS 9 @ 40 MHz is a working
//    rate (200 Mbps SGI at 1 SS).
// 2. The fix for (1) OVER-CORRECTED. Keith's chart covers 1-3 SS, so the pass
//    concluded "there is no exclusion above 3 SS" and the app began returning
//    385.2 Mbps for VHT MCS 9 @ 20 MHz at 4 SS. The source says N/A. An inverse
//    over-generalization is exactly as wrong as the original one.
// 3. Rates above 1 SS were computed as round(base, 1) * ss, while the source
//    publishes round(exact * ss, 1). That drifted ~110 cells by 0.1-0.2 Mbps
//    (e.g. VHT MCS 9 @ 160 MHz, 2 SS: the app said 1733.4, the source 1733.3).
//    [exactRatesPerSs] therefore stores the UNROUNDED per-stream rate and
//    [rate] rounds the product. Do not "tidy" those constants back to 1 dp.
//
// The lesson each time: the table is not derivable, only readable. A tempting
// rule — "a cell is valid iff N_SD x N_BPSCS x R x N_SS is a whole number of
// bits" — reproduces VHT MCS 9 @ 20 MHz perfectly and then calls VHT MCS 6 @
// 80 MHz and MCS 9 @ 160 MHz valid at 3 SS, where the source says N/A. It is
// wrong. There is no shortcut. Read the source or ship the hole.
//
// ─── THE N/A CELLS ARE DATA, NOT GAPS ───────────────────────────────────────
// An N/A cell is a fact the standard asserts, and it is as load-bearing as any
// rate. Never fill one to make the table look complete.
//
// ─── ABOVE 4 SPATIAL STREAMS WE PUBLISH NOTHING ─────────────────────────────
// The source tables stop at 4 SS. 802.11ac/ax/be define up to 8 streams, but no
// source on hand publishes their rates or — critically — their exclusions up
// there. So above [maxSourcedStreams] the screen shows an honest "not sourced"
// state and [rate] returns null. That is NOT the same claim as "N/A": N/A means
// the standard excludes the combination; unsourced means we do not know. The
// two must never render alike, because marking a valid cell invalid is precisely
// defect (1) in a new costume.
//
// GUARD INTERVALS: HT and VHT have 0.8 us and 0.4 us. HE and EHT have
// 0.8 / 1.6 / 3.2 us ONLY. A 400 ns column for HE or EHT would be fabricated —
// do not add one. (Pinned in test/audit/audit_wave_2_test.dart.)
//
// States (SOP-007 §5):
//  - success  → the chosen standard's MCS rows render, rates scaled by SS.
//  - empty    → not reachable: the datasets are bundled consts, never empty.
//  - "no data" → the genuinely-invalid cells (VHT MCS 9 @ 20 MHz at 1, 2 and
//    4 SS; MCS 6 @ 80 MHz and MCS 9 @ 160 MHz at 3 SS) render an honest "N/A",
//    never a faked number.
//  - unsourced → above 4 SS, an explicit notice instead of the rate table.
//  - loading / error → not applicable: no asset load, no network, no parse. The
//    data is compile-time const, so there is no failure surface to render.
//
// Pure data, no network, no platform APIs. The dataset and lookups are public
// statics so they unit-test against the source chart.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// 802.11 standard shown in the MCS table: n (HT), ac (VHT), ax (HE), and
/// be (EHT / Wi-Fi 7 — 320 MHz and 4096-QAM at MCS 12-13). All four ship.
enum McsStd { n, ac, ax, be }

/// One MCS index row: index, modulation, coding rate, and the per-column
/// EXACT single-spatial-stream data rates in Mbps.
class McsRow {
  const McsRow({
    required this.mcs,
    required this.modulation,
    required this.codeRate,
    required this.exactRatesPerSs,
  });

  /// MCS index (0-based).
  final int mcs;

  /// Modulation label, e.g. "64-QAM".
  final String modulation;

  /// Coding rate label, e.g. "5/6".
  final String codeRate;

  /// EXACT (unrounded) single-spatial-stream rate per channel-width column, in
  /// Mbps, in the same order as the standard's [McsStdData.columns].
  ///
  /// These are deliberately NOT rounded to the 1 decimal place the UI shows.
  /// The source publishes round(exact * streams, 1); rounding the base first
  /// and then multiplying drifts by up to 0.2 Mbps (VHT MCS 9 @ 160 MHz at
  /// 2 SS: 866.7 * 2 = 1733.4, but the source says 1733.3). [rate] rounds the
  /// product, which is what the source does. Do not "tidy" these to 1 dp.
  ///
  /// A null entry would be an unconditionally-invalid cell. There are none: in
  /// this dataset every exclusion is stream-count-dependent, so they live in
  /// [vhtStreamExclusions] instead.
  final List<double?> exactRatesPerSs;
}

/// A standard's full MCS table: the column headers and the per-MCS rows.
class McsStdData {
  const McsStdData({required this.columns, required this.rows});

  /// Column headers in display order, e.g. ['20 LGI', '20 SGI', ...].
  final List<String> columns;

  /// MCS rows, MCS 0 first.
  final List<McsRow> rows;
}

class McsIndexScreen extends StatefulWidget {
  const McsIndexScreen({super.key});

  // ─── Sourced coverage limits ────────────────────────────────────────────────

  /// The highest spatial-stream count the source tables publish.
  ///
  /// Keith's MCS chart and mcsindex.net both stop at 4 SS. Above this the app
  /// computes nothing — see the header note. This is a data-coverage limit, not
  /// a claim about the standard: 802.11ac/ax/be all define up to 8 streams.
  static const int maxSourcedStreams = 4;

  /// Max spatial streams each standard DEFINES. 802.11n tops out at 4 (MCS 0-31
  /// is 8 indices x 4 streams); ac/ax/be reach 8.
  ///
  /// Kept in step with `ThroughputCalcScreen.maxStreams` by a test — one app,
  /// one number. Offering 8 streams of 802.11n (as this screen used to) is a
  /// self-contradiction the app answers elsewhere.
  static const Map<McsStd, int> maxStreamsPerStd = <McsStd, int>{
    McsStd.n: 4,
    McsStd.ac: 8,
    McsStd.ax: 8,
    McsStd.be: 8,
  };

  /// True when the source tables actually cover [spatialStreams].
  static bool isSourcedStreamCount(int spatialStreams) =>
      spatialStreams >= 1 && spatialStreams <= maxSourcedStreams;

  // ─── Dataset ────────────────────────────────────────────────────────────────
  // Values are the EXACT PHY rates (N_SD x N_BPSCS x R / T_sym), which reproduce
  // every published cell of the source table for 1-4 SS after rounding the
  // product to 1 dp. Verified cell-by-cell in mcs_index_source_table_test.dart.

  /// 802.11n (HT) — columns are [20 LGI, 20 SGI, 40 LGI, 40 SGI].
  /// N_SD: 52 (20 MHz), 108 (40 MHz). T_sym: 4.0 us (LGI), 3.6 us (SGI).
  static const McsStdData ht = McsStdData(
    columns: ['20 LGI', '20 SGI', '40 LGI', '40 SGI'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        exactRatesPerSs: [6.5, 7.222222222222222, 13.5, 15.0],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        exactRatesPerSs: [13.0, 14.444444444444445, 27.0, 30.0],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        exactRatesPerSs: [19.5, 21.666666666666668, 40.5, 45.0],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        exactRatesPerSs: [26.0, 28.88888888888889, 54.0, 60.0],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [39.0, 43.333333333333336, 81.0, 90.0],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        exactRatesPerSs: [52.0, 57.77777777777778, 108.0, 120.0],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [58.5, 65.0, 121.5, 135.0],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [65.0, 72.22222222222223, 135.0, 150.0],
      ),
    ],
  );

  /// 802.11ac (VHT) — columns are SGI (0.4 us) rates per width [20, 40, 80,
  /// 160]. N_SD: 52 / 108 / 234 / 468. T_sym: 3.6 us.
  ///
  /// The three stream-dependent exclusions live in [vhtStreamExclusions]; the
  /// base rate stays in the row and the mask decides which stream counts may
  /// show it. A flat null could not express "N/A at 1, 2 and 4 SS, valid at 3".
  static const McsStdData vht = McsStdData(
    columns: ['20 SGI', '40 SGI', '80 SGI', '160 SGI'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        exactRatesPerSs: [7.222222222222222, 15.0, 32.5, 65.0],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        exactRatesPerSs: [14.444444444444445, 30.0, 65.0, 130.0],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        exactRatesPerSs: [21.666666666666668, 45.0, 97.5, 195.0],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        exactRatesPerSs: [28.88888888888889, 60.0, 130.0, 260.0],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [43.333333333333336, 90.0, 195.0, 390.0],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        exactRatesPerSs: [57.77777777777778, 120.0, 260.0, 520.0],
      ),
      McsRow(
        // MCS 6 @ 80 MHz is N/A at 3 SS — see [vhtStreamExclusions].
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [65.0, 135.0, 292.5, 585.0],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [72.22222222222223, 150.0, 325.0, 650.0],
      ),
      McsRow(
        mcs: 8,
        modulation: '256-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [86.66666666666667, 180.0, 390.0, 780.0],
      ),
      McsRow(
        // The row this screen keeps getting wrong.
        //  - 20 MHz : N/A at 1, 2 and 4 SS. VALID at 3 SS (260 LGI / 288.9 SGI).
        //  - 40 MHz : VALID everywhere. The app once nulled it. It is 200 Mbps.
        //  - 160 MHz: N/A at 3 SS.
        // The rates below are real; the MASK decides which stream counts show
        // them. See [vhtStreamExclusions].
        mcs: 9,
        modulation: '256-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          96.29629629629629,
          200.0,
          433.3333333333333,
          866.6666666666666,
        ],
      ),
    ],
  );

  /// VHT cells whose validity depends on the SPATIAL-STREAM COUNT, not just on
  /// the MCS index and channel width. Keyed `'<mcs>:<columnIndex>'`, valued with
  /// the stream counts for which the source marks the cell N/A.
  ///
  /// SOURCE (mcsindex.net, 1-4 SS blocks — every one of the five N/A cells in
  /// the app's column set):
  ///   - MCS 9 @ 20 MHz  — N/A at 1, 2 and 4 SS; VALID at 3 SS (260 / 288.9).
  ///   - MCS 6 @ 80 MHz  — N/A at 3 SS.
  ///   - MCS 9 @ 160 MHz — N/A at 3 SS.
  ///
  /// DO NOT EXTEND THIS MAP ABOVE 4 SS. The source stops there. An exclusion at
  /// 5-8 SS would be invented, and inventing one is the mirror image of the bug
  /// this map exists to fix. Above 4 SS the screen shows nothing at all rather
  /// than guess — see [maxSourcedStreams].
  ///
  /// DO NOT "SIMPLIFY" IT EITHER. The 4 SS entry looks like an outlier next to
  /// the 1 and 2. It is not. It is in the source, and a previous pass deleted it
  /// on the theory that exclusions stop at 3 SS.
  static const Map<String, Set<int>> vhtStreamExclusions = <String, Set<int>>{
    '9:0': <int>{1, 2, 4}, // MCS 9 @ 20 MHz  — valid at 3 SS only.
    '6:2': <int>{3}, //       MCS 6 @ 80 MHz
    '9:3': <int>{3}, //       MCS 9 @ 160 MHz
  };

  /// 802.11ax (HE) — columns are 800 ns GI rates per width [20, 40, 80, 160].
  /// N_SD (RU): 234 / 468 / 980 / 1960. T_sym: 12.8 + 0.8 = 13.6 us.
  static const McsStdData he = McsStdData(
    columns: ['20 MHz', '40 MHz', '80 MHz', '160 MHz'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        exactRatesPerSs: [
          8.602941176470589,
          17.205882352941178,
          36.029411764705884,
          72.05882352941177,
        ],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        exactRatesPerSs: [
          17.205882352941178,
          34.411764705882355,
          72.05882352941177,
          144.11764705882354,
        ],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        exactRatesPerSs: [
          25.808823529411764,
          51.61764705882353,
          108.08823529411765,
          216.1764705882353,
        ],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        exactRatesPerSs: [
          34.411764705882355,
          68.82352941176471,
          144.11764705882354,
          288.2352941176471,
        ],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          51.61764705882353,
          103.23529411764706,
          216.1764705882353,
          432.3529411764706,
        ],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        exactRatesPerSs: [
          68.82352941176471,
          137.64705882352942,
          288.2352941176471,
          576.4705882352941,
        ],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          77.42647058823529,
          154.85294117647058,
          324.2647058823529,
          648.5294117647059,
        ],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          86.02941176470588,
          172.05882352941177,
          360.29411764705884,
          720.5882352941177,
        ],
      ),
      McsRow(
        mcs: 8,
        modulation: '256-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          103.23529411764706,
          206.47058823529412,
          432.3529411764706,
          864.7058823529412,
        ],
      ),
      McsRow(
        mcs: 9,
        modulation: '256-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          114.70588235294117,
          229.41176470588235,
          480.3921568627451,
          960.7843137254902,
        ],
      ),
      McsRow(
        mcs: 10,
        modulation: '1024-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          129.0441176470588,
          258.0882352941176,
          540.4411764705883,
          1080.8823529411766,
        ],
      ),
      McsRow(
        // 600.5 / 1201.0, not 600.4 / 1200.9 — the old figures TRUNCATED where
        // they should have rounded (true values 600.49 and 1200.98).
        mcs: 11,
        modulation: '1024-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          143.38235294117646,
          286.7647058823529,
          600.4901960784314,
          1200.9803921568628,
        ],
      ),
    ],
  );

  /// 802.11be (EHT / Wi-Fi 7) — columns are 800 ns GI rates per width
  /// [20, 40, 80, 160, 320]. MCS 0-11 share HE's modulation/rates; EHT adds the
  /// 320 MHz column (N_SD 3920) and two 4096-QAM indices (MCS 12-13).
  static const McsStdData eht = McsStdData(
    columns: ['20 MHz', '40 MHz', '80 MHz', '160 MHz', '320 MHz'],
    rows: [
      McsRow(
        mcs: 0,
        modulation: 'BPSK',
        codeRate: '1/2',
        exactRatesPerSs: [
          8.602941176470589,
          17.205882352941178,
          36.029411764705884,
          72.05882352941177,
          144.11764705882354,
        ],
      ),
      McsRow(
        mcs: 1,
        modulation: 'QPSK',
        codeRate: '1/2',
        exactRatesPerSs: [
          17.205882352941178,
          34.411764705882355,
          72.05882352941177,
          144.11764705882354,
          288.2352941176471,
        ],
      ),
      McsRow(
        mcs: 2,
        modulation: 'QPSK',
        codeRate: '3/4',
        exactRatesPerSs: [
          25.808823529411764,
          51.61764705882353,
          108.08823529411765,
          216.1764705882353,
          432.3529411764706,
        ],
      ),
      McsRow(
        mcs: 3,
        modulation: '16-QAM',
        codeRate: '1/2',
        exactRatesPerSs: [
          34.411764705882355,
          68.82352941176471,
          144.11764705882354,
          288.2352941176471,
          576.4705882352941,
        ],
      ),
      McsRow(
        mcs: 4,
        modulation: '16-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          51.61764705882353,
          103.23529411764706,
          216.1764705882353,
          432.3529411764706,
          864.7058823529412,
        ],
      ),
      McsRow(
        mcs: 5,
        modulation: '64-QAM',
        codeRate: '2/3',
        exactRatesPerSs: [
          68.82352941176471,
          137.64705882352942,
          288.2352941176471,
          576.4705882352941,
          1152.9411764705883,
        ],
      ),
      McsRow(
        mcs: 6,
        modulation: '64-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          77.42647058823529,
          154.85294117647058,
          324.2647058823529,
          648.5294117647059,
          1297.0588235294117,
        ],
      ),
      McsRow(
        mcs: 7,
        modulation: '64-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          86.02941176470588,
          172.05882352941177,
          360.29411764705884,
          720.5882352941177,
          1441.1764705882354,
        ],
      ),
      McsRow(
        mcs: 8,
        modulation: '256-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          103.23529411764706,
          206.47058823529412,
          432.3529411764706,
          864.7058823529412,
          1729.4117647058824,
        ],
      ),
      McsRow(
        mcs: 9,
        modulation: '256-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          114.70588235294117,
          229.41176470588235,
          480.3921568627451,
          960.7843137254902,
          1921.5686274509803,
        ],
      ),
      McsRow(
        mcs: 10,
        modulation: '1024-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          129.0441176470588,
          258.0882352941176,
          540.4411764705883,
          1080.8823529411766,
          2161.764705882353,
        ],
      ),
      McsRow(
        mcs: 11,
        modulation: '1024-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          143.38235294117646,
          286.7647058823529,
          600.4901960784314,
          1200.9803921568628,
          2401.9607843137255,
        ],
      ),
      McsRow(
        mcs: 12,
        modulation: '4096-QAM',
        codeRate: '3/4',
        exactRatesPerSs: [
          154.85294117647058,
          309.70588235294116,
          648.5294117647059,
          1297.0588235294117,
          2594.1176470588234,
        ],
      ),
      McsRow(
        mcs: 13,
        modulation: '4096-QAM',
        codeRate: '5/6',
        exactRatesPerSs: [
          172.05882352941177,
          344.11764705882354,
          720.5882352941177,
          1441.1764705882354,
          2882.3529411764707,
        ],
      ),
    ],
  );

  /// Lookup table keyed by standard.
  static const Map<McsStd, McsStdData> dataset = {
    McsStd.n: ht,
    McsStd.ac: vht,
    McsStd.ax: he,
    McsStd.be: eht,
  };

  /// The on-screen notes text. Public + const so guard tests can pin it: the
  /// notes card used to assert "802.11ac MCS 9 is invalid at 20 and 40 MHz for a
  /// single stream" — false at 40 MHz, and the prose half of the same defect the
  /// data carried.
  static const String notesText =
      'Rates scale with the spatial-stream count selected above. '
      '802.11n: LGI = 800 ns long guard interval, SGI = 400 ns short. '
      '802.11ac: short guard interval. 802.11ax and 802.11be: 800 ns guard '
      'interval (HE and EHT define 0.8, 1.6, and 3.2 us guard intervals only - '
      'there is no 400 ns short GI above 802.11ac). 802.11be (Wi-Fi 7 / EHT) '
      'adds the 320 MHz channel width and 4096-QAM (MCS 12 and 13). '
      '802.11ac carries three stream-dependent exclusions: MCS 9 at 20 MHz is '
      'valid ONLY at 3 spatial streams (N/A at 1, 2 and 4); MCS 6 at 80 MHz and '
      'MCS 9 at 160 MHz are N/A at 3 streams. MCS 9 at 40 MHz is valid at every '
      'stream count. Cells shown as N/A are genuinely invalid combinations - '
      'never zero, never made up. '
      'The source tables (Keith Parsons\' MCS chart and mcsindex.net) publish 1 '
      'to 4 spatial streams. Above 4 spatial streams no rate is shown: the '
      'exclusions up there are unpublished, and this app does not compute a rate '
      'it cannot source. '
      'Actual throughput is typically 50 to 65 percent of the PHY rate.';

  /// Shown in place of the rate table above [maxSourcedStreams].
  ///
  /// It must never say "N/A". N/A is a claim the standard makes (this
  /// combination is invalid); this is a claim about OUR DATA (we have no
  /// published figure). Conflating them would mark valid cells invalid — which
  /// is the original bug wearing a different hat.
  static const String unsourcedStreamsNotice =
      'The source tables stop at 4 spatial streams. Keith Parsons\' MCS chart '
      'and mcsindex.net publish 1 to 4 streams only, so no rate is shown beyond '
      'that. This is a gap in the published data, not an invalid configuration: '
      '802.11ac, ax and be all define up to 8 spatial streams. The per-stream '
      'exclusions above 4 streams are unpublished and are not derivable from the '
      'ones below it, so rather than compute a rate we cannot source, we show '
      'none.';

  // ─── Lookups (pure, testable) ───────────────────────────────────────────────

  /// The MCS table for [std].
  static McsStdData dataFor(McsStd std) => dataset[std]!;

  /// Round to the 1 decimal place the source publishes.
  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  /// True when [std] / [mcs] / [columnIndex] is invalid **at this specific
  /// stream count** — the exclusions a flat null cell cannot express. See
  /// [vhtStreamExclusions].
  ///
  /// This answers "does the standard exclude this combination?", NOT "do we have
  /// a number for it?". Above [maxSourcedStreams] it returns false, because we
  /// do not know — and claiming an exclusion we cannot source is exactly the bug
  /// this whole file warns about. [rate] returns null there for the other reason.
  static bool isExcludedAt({
    required McsStd std,
    required int mcs,
    required int columnIndex,
    required int spatialStreams,
  }) {
    if (std != McsStd.ac) return false;
    final Set<int>? excluded = vhtStreamExclusions['$mcs:$columnIndex'];
    return excluded != null && excluded.contains(spatialStreams);
  }

  /// The data rate in Mbps at the source's published precision (1 dp), or null
  /// when there is no rate to report.
  ///
  /// Null means one of four things, and the screen distinguishes the first two:
  ///   1. the standard EXCLUDES the combination ([isExcludedAt]) → renders "N/A";
  ///   2. the stream count is beyond [maxSourcedStreams] → renders the
  ///      "not sourced" notice, never "N/A";
  ///   3. the MCS index or column is out of range;
  ///   4. spatialStreams < 1.
  ///
  /// The product is rounded, NOT the base — the source publishes
  /// round(exact * streams, 1), and rounding first drifts up to 0.2 Mbps.
  static double? rate({
    required McsStd std,
    required int mcs,
    required int columnIndex,
    required int spatialStreams,
  }) {
    // Above the source's coverage we do not guess — for VHT this would also
    // silently assert that the stream-dependent exclusions stop at 4 SS.
    if (!isSourcedStreamCount(spatialStreams)) return null;

    final McsStdData data = dataset[std]!;
    McsRow? row;
    for (final McsRow r in data.rows) {
      if (r.mcs == mcs) {
        row = r;
        break;
      }
    }
    if (row == null) return null;
    if (columnIndex < 0 || columnIndex >= row.exactRatesPerSs.length) {
      return null;
    }
    if (isExcludedAt(
      std: std,
      mcs: mcs,
      columnIndex: columnIndex,
      spatialStreams: spatialStreams,
    )) {
      return null;
    }
    final double? base = row.exactRatesPerSs[columnIndex];
    if (base == null) return null;
    return _round1(base * spatialStreams);
  }

  @override
  State<McsIndexScreen> createState() => _McsIndexScreenState();
}

class _McsIndexScreenState extends State<McsIndexScreen> {
  McsStd _std = McsStd.n; // Default tab (802.11n active).
  int _ss = 1; // Default spatial streams (1 SS).

  /// True when the current selection is beyond what the source publishes.
  bool get _unsourced => !McsIndexScreen.isSourcedStreamCount(_ss);

  static String _stdLabel(McsStd std) {
    switch (std) {
      case McsStd.n:
        return '802.11n — Wi-Fi 4 (HT)';
      case McsStd.ac:
        return '802.11ac — Wi-Fi 5 (VHT)';
      case McsStd.ax:
        return '802.11ax — Wi-Fi 6 (HE)';
      case McsStd.be:
        return '802.11be — Wi-Fi 7 (EHT)';
    }
  }

  /// Rates render at fixed 1 decimal; genuinely-invalid cells render "N/A".
  static String _formatRate(double? n) {
    if (n == null) return 'N/A';
    return n.toStringAsFixed(1);
  }

  /// §8.16 copy payload — the live MCS rate table as TSV. The title records the
  /// selected standard and spatial-stream count because the rates are scaled by
  /// SS. Invalid cells copy as "N/A" (never fabricated).
  ///
  /// Above the sourced stream ceiling there is no table to copy, so the payload
  /// is the honest notice rather than a grid of "N/A" — pasting a wall of N/A
  /// into a design doc would assert those combinations are invalid, which is a
  /// claim we are not making.
  String _buildCopyText() {
    const String tab = '\t';
    if (_unsourced) {
      return 'MCS Index — ${_stdLabel(_std)} · $_ss SS\n'
          '${McsIndexScreen.unsourcedStreamsNotice}';
    }
    final McsStdData data = McsIndexScreen.dataFor(_std);
    final StringBuffer buf = StringBuffer()
      ..writeln('MCS Index — ${_stdLabel(_std)} · $_ss SS (Mbps)')
      ..writeln(
        <String>['MCS', 'Modulation', 'Code', ...data.columns].join(tab),
      );
    for (final McsRow row in data.rows) {
      final List<String> cells = <String>[
        '${row.mcs}',
        row.modulation,
        row.codeRate,
      ];
      for (int i = 0; i < data.columns.length; i++) {
        final double? scaled = McsIndexScreen.rate(
          std: _std,
          mcs: row.mcs,
          columnIndex: i,
          spatialStreams: _ss,
        );
        cells.add(_formatRate(scaled));
      }
      buf.writeln(cells.join(tab));
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCS Index'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.calculatorMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConceptGraphicBand(
                        toolId: 'mcs-index',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('mcs-index'))
                        const SizedBox(height: AppSpacing.md),
                      _controlsCard(),
                      const SizedBox(height: AppSpacing.md),
                      // Above the sourced ceiling the rate table is replaced by
                      // an honest notice — NOT by a grid of "N/A", which would
                      // assert those combinations are invalid.
                      if (_unsourced)
                        _unsourcedCard(text)
                      else
                        _tableCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _notesCard(text),
                      ToolHelpFooter(toolId: 'mcs-index'),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _controlsCard() {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stdSelector(),
          const SizedBox(height: AppSpacing.sm),
          _ssSelector(),
        ],
      ),
    );
  }

  Widget _stdSelector() {
    return LabeledField(
      label: '802.11 standard',
      field: AppSelect<McsStd>(
        value: _std,
        semanticLabel: '802.11 standard',
        items: McsStd.values.map((McsStd s) => (s, _stdLabel(s))).toList(),
        onChanged: (McsStd s) => setState(() {
          _std = s;
          // 802.11n defines 4 spatial streams, not 8. Clamp rather than leave a
          // stale 8 SS selection that the standard does not define at all.
          final int max = McsIndexScreen.maxStreamsPerStd[s]!;
          if (_ss > max) _ss = max;
        }),
      ),
    );
  }

  Widget _ssSelector() {
    // Offer only the stream counts the SELECTED standard actually defines.
    // 802.11n tops out at 4 (MCS 0-31 = 8 indices x 4 streams); ac/ax/be reach
    // 8. This screen used to offer 8 streams of 802.11n, which the standard has
    // no mode for — and the app's own throughput calculator already said 4.
    final int max = McsIndexScreen.maxStreamsPerStd[_std]!;
    final List<AppSelectItem<int>> items = [
      for (int i = 1; i <= max; i++) (i, '$i SS'),
    ];
    return LabeledField(
      label: 'Spatial streams',
      field: AppSelect<int>(
        value: _ss,
        semanticLabel: 'Spatial streams',
        items: items,
        onChanged: (int s) => setState(() => _ss = s),
      ),
    );
  }

  /// The honest "we have no source for this" state (above 4 SS).
  ///
  /// Deliberately NOT a table of "N/A": N/A means the standard excludes the
  /// combination, and 8-stream 802.11be is perfectly valid — we simply have no
  /// published rate for it. Saying "N/A" here would mark a working cell invalid,
  /// which is the exact defect this screen was fixed for.
  Widget _unsourcedCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      label: 'Rates not available above '
          '${McsIndexScreen.maxSourcedStreams} spatial streams. '
          '${McsIndexScreen.unsourcedStreamsNotice}',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.statusInfoFill,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.statusInfo, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: AppTextSize.body,
                color: colors.statusInfo,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No sourced rates above '
                      '${McsIndexScreen.maxSourcedStreams} spatial streams',
                      style: text.labelMedium?.copyWith(
                        color: colors.textPrimary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      McsIndexScreen.unsourcedStreamsNotice,
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final McsStdData data = McsIndexScreen.dataFor(_std);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${data.rows.length} MCS indices  ·  ×$_ss SS (Mbps)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Horizontal scroll: the per-width rate columns can exceed phone
          // width, so the data table scrolls sideways inside the fixed card.
          HorizontalScrollTable(child: _dataTable(data, text, mono)),
        ],
      ),
    );
  }

  Widget _dataTable(McsStdData data, TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);

    return DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 48,
      columnSpacing: AppSpacing.md,
      horizontalMargin: 0,
      dividerThickness: 1,
      headingTextStyle: headStyle,
      columns: [
        const DataColumn(label: Text('MCS')),
        const DataColumn(label: Text('Modulation')),
        const DataColumn(label: Text('Code')),
        for (final String c in data.columns)
          DataColumn(label: Text(c), numeric: true),
      ],
      rows: data.rows.map((McsRow row) {
        // DataTable renders each cell as its own column node; without grouping
        // a screen reader reads "0", "BPSK", "1/2", "8.6"… as disconnected
        // nodes and can't tell which rates belong to which MCS. Label the first
        // (MCS) cell with the full row summary and exclude the rest. (Vera
        // F-02.) An excluded cell is announced as invalid rather than skipped —
        // silence would read as "no data", and N/A is a fact worth hearing.
        final List<String?> rateClauses = <String?>[];
        for (int i = 0; i < data.columns.length; i++) {
          final double? scaled = McsIndexScreen.rate(
            std: _std,
            mcs: row.mcs,
            columnIndex: i,
            spatialStreams: _ss,
          );
          rateClauses.add(
            scaled == null
                ? '${data.columns[i]} not valid at $_ss spatial streams'
                : '${data.columns[i]} ${_formatRate(scaled)} megabits',
          );
        }
        final String summary = rowLabel('MCS ${row.mcs}', <String?>[
          row.modulation,
          'code rate ${row.codeRate}',
          ...rateClauses,
        ]);
        return DataRow(
          cells: [
            DataCell(
              Semantics(
                label: summary,
                container: true,
                child: ExcludeSemantics(
                  child: Text(
                    '${row.mcs}',
                    style: mono.outputMedium.copyWith(color: colors.textAccent),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  row.modulation,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  row.codeRate,
                  style: mono.inlineCode.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            for (int i = 0; i < data.columns.length; i++)
              _rateCell(row, i, mono),
          ],
        );
      }).toList(),
    );
  }

  DataCell _rateCell(McsRow row, int columnIndex, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? scaled = McsIndexScreen.rate(
      std: _std,
      mcs: row.mcs,
      columnIndex: columnIndex,
      spatialStreams: _ss,
    );
    final bool na = scaled == null;
    return DataCell(
      ExcludeSemantics(
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            _formatRate(scaled),
            style: mono.outputMedium.copyWith(
              color: na ? colors.textTertiary : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _notesCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            McsIndexScreen.notesText,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
