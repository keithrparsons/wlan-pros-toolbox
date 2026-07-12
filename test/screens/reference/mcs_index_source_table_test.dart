// MCS Index — the SOURCE TABLE as an independent oracle.
//
// Every expected value in this file is transcribed from mcsindex.net, the chart
// Keith explicitly endorsed:
//   https://docs.google.com/spreadsheets/d/e/2PACX-1vQXoEYLGWrR1aGyGaTXOOaDQSPLfeC4rv70KRFuRP6eZ5fL-Ku_YI6DgS6zZMNyIhQpQmnKQ1O7abij/pub?output=csv
//   (by @VergesFrancois, © SemFio Networks)
//
// NOT ONE VALUE IN THIS FILE CAME FROM RUNNING THE CODE. That is the whole
// point: the screen computes, this file remembers what the source published, and
// the two are compared. An expectation is never "corrected" to make a test pass
// — if they disagree, the SCREEN is wrong.
//
// WHY THIS FILE EXISTS. The MCS screen has now been wrong in three different
// directions, each time because someone reasoned about the table instead of
// reading it:
//   1. A hand-written comment "// MCS9 invalid at 20 and 40 MHz (1 SS)" — a
//      human knew the real 20 MHz exclusion and over-generalized it to 40 MHz.
//   2. The fix for (1) over-corrected the other way: it asserted there is no
//      exclusion above 3 SS, and the app began returning a rate for VHT MCS 9
//      @ 20 MHz at 4 SS. The source says N/A. An inverse over-generalization is
//      exactly as wrong as the original.
//   3. Rates above 1 SS were computed as round(base, 1) * ss, but the source
//      publishes round(exact * ss, 1). That drifted ~110 cells by 0.1-0.2 Mbps.
//
// The N/A CELLS ARE AS LOAD-BEARING AS THE RATES. Both get assertions here, so
// nobody can "helpfully" fill a hole later.
//
// THE SOURCE COVERS 1-4 SPATIAL STREAMS ONLY. Above 4 SS it publishes nothing,
// so the app publishes nothing — see the honest-null group at the bottom. Do NOT
// extrapolate the exclusion pattern in either direction to fill that gap. A
// tempting equation ("a cell is valid iff N_SD x N_BPSCS x R x N_SS is a whole
// number of bits") reproduces VHT MCS 9 @ 20 MHz exactly — and then FAILS on
// VHT MCS 6 @ 80 MHz and VHT MCS 9 @ 160 MHz, which it calls valid at 3 SS while
// the source says N/A. There is no derivable rule. Get the source or ship the
// hole.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mcs_index_screen.dart';

/// One transcribed source row: the rate per width column at a given stream
/// count. `null` is an N/A cell in the source — a genuine exclusion, not a gap
/// in our transcription.
typedef SrcRow = ({int mcs, int ss, List<double?> rates});

void main() {
  /// Assert one standard's whole table, cell by cell, against the source.
  void pinTable(String label, McsStd std, List<SrcRow> table) {
    group('$label — every cell matches mcsindex.net', () {
      for (final SrcRow r in table) {
        test('MCS ${r.mcs} @ ${r.ss} SS', () {
          for (int c = 0; c < r.rates.length; c++) {
            final double? expected = r.rates[c];
            final double? actual = McsIndexScreen.rate(
              std: std,
              mcs: r.mcs,
              columnIndex: c,
              spatialStreams: r.ss,
            );
            final String col = McsIndexScreen.dataFor(std).columns[c];
            if (expected == null) {
              expect(
                actual,
                isNull,
                reason: '$label MCS ${r.mcs} @ $col, ${r.ss} SS: the source '
                    'prints N/A. The app returned $actual. An N/A cell is a '
                    'fact, not a hole to fill.',
              );
            } else {
              expect(
                actual,
                expected,
                reason: '$label MCS ${r.mcs} @ $col, ${r.ss} SS: the source '
                    'prints $expected. The app returned $actual.',
              );
            }
          }
        });
      }
    });
  }

  // ── 802.11n (HT) ─ columns [20 LGI, 20 SGI, 40 LGI, 40 SGI] ────────────────
  // The source encodes streams in the HT index (MCS 8-15 = 2 SS, 16-23 = 3 SS,
  // 24-31 = 4 SS); the app models MCS 0-7 with a stream selector. Same table.
  pinTable('802.11n', McsStd.n, const <SrcRow>[
    (mcs: 0, ss: 1, rates: [6.5, 7.2, 13.5, 15.0]),
    (mcs: 1, ss: 1, rates: [13.0, 14.4, 27.0, 30.0]),
    (mcs: 2, ss: 1, rates: [19.5, 21.7, 40.5, 45.0]),
    (mcs: 3, ss: 1, rates: [26.0, 28.9, 54.0, 60.0]),
    (mcs: 4, ss: 1, rates: [39.0, 43.3, 81.0, 90.0]),
    (mcs: 5, ss: 1, rates: [52.0, 57.8, 108.0, 120.0]),
    (mcs: 6, ss: 1, rates: [58.5, 65.0, 121.5, 135.0]),
    (mcs: 7, ss: 1, rates: [65.0, 72.2, 135.0, 150.0]),
    // HT MCS 8-15 (2 SS)
    (mcs: 0, ss: 2, rates: [13.0, 14.4, 27.0, 30.0]),
    (mcs: 1, ss: 2, rates: [26.0, 28.9, 54.0, 60.0]),
    (mcs: 2, ss: 2, rates: [39.0, 43.3, 81.0, 90.0]),
    (mcs: 3, ss: 2, rates: [52.0, 57.8, 108.0, 120.0]),
    (mcs: 4, ss: 2, rates: [78.0, 86.7, 162.0, 180.0]),
    (mcs: 5, ss: 2, rates: [104.0, 115.6, 216.0, 240.0]),
    (mcs: 6, ss: 2, rates: [117.0, 130.0, 243.0, 270.0]),
    (mcs: 7, ss: 2, rates: [130.0, 144.4, 270.0, 300.0]),
    // HT MCS 16-23 (3 SS)
    (mcs: 0, ss: 3, rates: [19.5, 21.7, 40.5, 45.0]),
    (mcs: 1, ss: 3, rates: [39.0, 43.3, 81.0, 90.0]),
    (mcs: 2, ss: 3, rates: [58.5, 65.0, 121.5, 135.0]),
    (mcs: 3, ss: 3, rates: [78.0, 86.7, 162.0, 180.0]),
    (mcs: 4, ss: 3, rates: [117.0, 130.0, 243.0, 270.0]),
    (mcs: 5, ss: 3, rates: [156.0, 173.3, 324.0, 360.0]),
    (mcs: 6, ss: 3, rates: [175.5, 195.0, 364.5, 405.0]),
    (mcs: 7, ss: 3, rates: [195.0, 216.7, 405.0, 450.0]),
    // HT MCS 24-31 (4 SS)
    (mcs: 0, ss: 4, rates: [26.0, 28.9, 54.0, 60.0]),
    (mcs: 1, ss: 4, rates: [52.0, 57.8, 108.0, 120.0]),
    (mcs: 2, ss: 4, rates: [78.0, 86.7, 162.0, 180.0]),
    (mcs: 3, ss: 4, rates: [104.0, 115.6, 216.0, 240.0]),
    (mcs: 4, ss: 4, rates: [156.0, 173.3, 324.0, 360.0]),
    (mcs: 5, ss: 4, rates: [208.0, 231.1, 432.0, 480.0]),
    (mcs: 6, ss: 4, rates: [234.0, 260.0, 486.0, 540.0]),
    (mcs: 7, ss: 4, rates: [260.0, 288.9, 540.0, 600.0]),
  ]);

  // ── 802.11ac (VHT) ─ columns [20, 40, 80, 160] all SGI (0.4 us) ────────────
  // THE FIVE N/A CELLS LIVE HERE. Every one is transcribed, not inferred.
  pinTable('802.11ac', McsStd.ac, const <SrcRow>[
    (mcs: 0, ss: 1, rates: [7.2, 15.0, 32.5, 65.0]),
    (mcs: 1, ss: 1, rates: [14.4, 30.0, 65.0, 130.0]),
    (mcs: 2, ss: 1, rates: [21.7, 45.0, 97.5, 195.0]),
    (mcs: 3, ss: 1, rates: [28.9, 60.0, 130.0, 260.0]),
    (mcs: 4, ss: 1, rates: [43.3, 90.0, 195.0, 390.0]),
    (mcs: 5, ss: 1, rates: [57.8, 120.0, 260.0, 520.0]),
    (mcs: 6, ss: 1, rates: [65.0, 135.0, 292.5, 585.0]),
    (mcs: 7, ss: 1, rates: [72.2, 150.0, 325.0, 650.0]),
    (mcs: 8, ss: 1, rates: [86.7, 180.0, 390.0, 780.0]),
    // N/A @ 20 MHz. VALID at 40 — 200 Mbps. The original bug nulled 40 too.
    (mcs: 9, ss: 1, rates: [null, 200.0, 433.3, 866.7]),

    (mcs: 0, ss: 2, rates: [14.4, 30.0, 65.0, 130.0]),
    (mcs: 1, ss: 2, rates: [28.9, 60.0, 130.0, 260.0]),
    (mcs: 2, ss: 2, rates: [43.3, 90.0, 195.0, 390.0]),
    (mcs: 3, ss: 2, rates: [57.8, 120.0, 260.0, 520.0]),
    (mcs: 4, ss: 2, rates: [86.7, 180.0, 390.0, 780.0]),
    (mcs: 5, ss: 2, rates: [115.6, 240.0, 520.0, 1040.0]),
    (mcs: 6, ss: 2, rates: [130.0, 270.0, 585.0, 1170.0]),
    (mcs: 7, ss: 2, rates: [144.4, 300.0, 650.0, 1300.0]),
    (mcs: 8, ss: 2, rates: [173.3, 360.0, 780.0, 1560.0]),
    // N/A @ 20 MHz. Note 160 MHz = 1733.3, NOT 1733.4 (866.7 * 2). The source
    // rounds the exact product; it does not multiply a rounded base.
    (mcs: 9, ss: 2, rates: [null, 400.0, 866.7, 1733.3]),

    (mcs: 0, ss: 3, rates: [21.7, 45.0, 97.5, 195.0]),
    (mcs: 1, ss: 3, rates: [43.3, 90.0, 195.0, 390.0]),
    (mcs: 2, ss: 3, rates: [65.0, 135.0, 292.5, 585.0]),
    (mcs: 3, ss: 3, rates: [86.7, 180.0, 390.0, 780.0]),
    (mcs: 4, ss: 3, rates: [130.0, 270.0, 585.0, 1170.0]),
    (mcs: 5, ss: 3, rates: [173.3, 360.0, 780.0, 1560.0]),
    // MCS 6 @ 80 MHz — N/A at 3 SS.
    (mcs: 6, ss: 3, rates: [195.0, 405.0, null, 1755.0]),
    (mcs: 7, ss: 3, rates: [216.7, 450.0, 975.0, 1950.0]),
    (mcs: 8, ss: 3, rates: [260.0, 540.0, 1170.0, 2340.0]),
    // MCS 9 @ 20 MHz — THE ONE VALID CELL in that column: 288.9 at 3 SS.
    // MCS 9 @ 160 MHz — N/A at 3 SS.
    (mcs: 9, ss: 3, rates: [288.9, 600.0, 1300.0, null]),

    (mcs: 0, ss: 4, rates: [28.9, 60.0, 130.0, 260.0]),
    (mcs: 1, ss: 4, rates: [57.8, 120.0, 260.0, 520.0]),
    (mcs: 2, ss: 4, rates: [86.7, 180.0, 390.0, 780.0]),
    (mcs: 3, ss: 4, rates: [115.6, 240.0, 520.0, 1040.0]),
    (mcs: 4, ss: 4, rates: [173.3, 360.0, 780.0, 1560.0]),
    (mcs: 5, ss: 4, rates: [231.1, 480.0, 1040.0, 2080.0]),
    (mcs: 6, ss: 4, rates: [260.0, 540.0, 1170.0, 2340.0]),
    (mcs: 7, ss: 4, rates: [288.9, 600.0, 1300.0, 2600.0]),
    (mcs: 8, ss: 4, rates: [346.7, 720.0, 1560.0, 3120.0]),
    // ── THE REGRESSION THIS FILE WAS WRITTEN FOR ──────────────────────────
    // MCS 9 @ 20 MHz is N/A at 4 SS. The previous pass concluded "no exclusion
    // above 3 SS" because Keith's chart stops at 3, and the app started
    // returning 385.2 here. The source says N/A. It is N/A.
    (mcs: 9, ss: 4, rates: [null, 800.0, 1733.3, 3466.7]),
  ]);

  // ── 802.11ax (HE) ─ columns [20, 40, 80, 160] @ 0.8 us GI ──────────────────
  pinTable('802.11ax', McsStd.ax, const <SrcRow>[
    (mcs: 0, ss: 1, rates: [8.6, 17.2, 36.0, 72.1]),
    (mcs: 1, ss: 1, rates: [17.2, 34.4, 72.1, 144.1]),
    (mcs: 2, ss: 1, rates: [25.8, 51.6, 108.1, 216.2]),
    (mcs: 3, ss: 1, rates: [34.4, 68.8, 144.1, 288.2]),
    (mcs: 4, ss: 1, rates: [51.6, 103.2, 216.2, 432.4]),
    (mcs: 5, ss: 1, rates: [68.8, 137.6, 288.2, 576.5]),
    (mcs: 6, ss: 1, rates: [77.4, 154.9, 324.3, 648.5]),
    (mcs: 7, ss: 1, rates: [86.0, 172.1, 360.3, 720.6]),
    (mcs: 8, ss: 1, rates: [103.2, 206.5, 432.4, 864.7]),
    (mcs: 9, ss: 1, rates: [114.7, 229.4, 480.4, 960.8]),
    (mcs: 10, ss: 1, rates: [129.0, 258.1, 540.4, 1080.9]),
    (mcs: 11, ss: 1, rates: [143.4, 286.8, 600.5, 1201.0]),

    (mcs: 0, ss: 2, rates: [17.2, 34.4, 72.1, 144.1]),
    (mcs: 1, ss: 2, rates: [34.4, 68.8, 144.1, 288.2]),
    (mcs: 2, ss: 2, rates: [51.6, 103.2, 216.2, 432.4]),
    (mcs: 3, ss: 2, rates: [68.8, 137.6, 288.2, 576.5]),
    (mcs: 4, ss: 2, rates: [103.2, 206.5, 432.4, 864.7]),
    (mcs: 5, ss: 2, rates: [137.6, 275.3, 576.5, 1152.9]),
    (mcs: 6, ss: 2, rates: [154.9, 309.7, 648.5, 1297.1]),
    (mcs: 7, ss: 2, rates: [172.1, 344.1, 720.6, 1441.2]),
    (mcs: 8, ss: 2, rates: [206.5, 412.9, 864.7, 1729.4]),
    (mcs: 9, ss: 2, rates: [229.4, 458.8, 960.8, 1921.6]),
    (mcs: 10, ss: 2, rates: [258.1, 516.2, 1080.9, 2161.8]),
    (mcs: 11, ss: 2, rates: [286.8, 573.5, 1201.0, 2402.0]),

    (mcs: 0, ss: 3, rates: [25.8, 51.6, 108.1, 216.2]),
    (mcs: 1, ss: 3, rates: [51.6, 103.2, 216.2, 432.4]),
    (mcs: 2, ss: 3, rates: [77.4, 154.9, 324.3, 648.5]),
    (mcs: 3, ss: 3, rates: [103.2, 206.5, 432.4, 864.7]),
    (mcs: 4, ss: 3, rates: [154.9, 309.7, 648.5, 1297.1]),
    (mcs: 5, ss: 3, rates: [206.5, 412.9, 864.7, 1729.4]),
    (mcs: 6, ss: 3, rates: [232.3, 464.6, 972.8, 1945.6]),
    (mcs: 7, ss: 3, rates: [258.1, 516.2, 1080.9, 2161.8]),
    (mcs: 8, ss: 3, rates: [309.7, 619.4, 1297.1, 2594.1]),
    (mcs: 9, ss: 3, rates: [344.1, 688.2, 1441.2, 2882.4]),
    (mcs: 10, ss: 3, rates: [387.1, 774.3, 1621.3, 3242.6]),
    (mcs: 11, ss: 3, rates: [430.1, 860.3, 1801.5, 3602.9]),

    (mcs: 0, ss: 4, rates: [34.4, 68.8, 144.1, 288.2]),
    (mcs: 1, ss: 4, rates: [68.8, 137.6, 288.2, 576.5]),
    (mcs: 2, ss: 4, rates: [103.2, 206.5, 432.4, 864.7]),
    (mcs: 3, ss: 4, rates: [137.6, 275.3, 576.5, 1152.9]),
    (mcs: 4, ss: 4, rates: [206.5, 412.9, 864.7, 1729.4]),
    (mcs: 5, ss: 4, rates: [275.3, 550.6, 1152.9, 2305.9]),
    (mcs: 6, ss: 4, rates: [309.7, 619.4, 1297.1, 2594.1]),
    (mcs: 7, ss: 4, rates: [344.1, 688.2, 1441.2, 2882.4]),
    (mcs: 8, ss: 4, rates: [412.9, 825.9, 1729.4, 3458.8]),
    (mcs: 9, ss: 4, rates: [458.8, 917.6, 1921.6, 3843.1]),
    (mcs: 10, ss: 4, rates: [516.2, 1032.4, 2161.8, 4323.5]),
    (mcs: 11, ss: 4, rates: [573.5, 1147.1, 2402.0, 4803.9]),
  ]);

  // ── 802.11be (EHT) ─ columns [20, 40, 80, 160, 320] @ 0.8 us GI ────────────
  pinTable('802.11be', McsStd.be, const <SrcRow>[
    (mcs: 0, ss: 1, rates: [8.6, 17.2, 36.0, 72.1, 144.1]),
    (mcs: 1, ss: 1, rates: [17.2, 34.4, 72.1, 144.1, 288.2]),
    (mcs: 2, ss: 1, rates: [25.8, 51.6, 108.1, 216.2, 432.4]),
    (mcs: 3, ss: 1, rates: [34.4, 68.8, 144.1, 288.2, 576.5]),
    (mcs: 4, ss: 1, rates: [51.6, 103.2, 216.2, 432.4, 864.7]),
    (mcs: 5, ss: 1, rates: [68.8, 137.6, 288.2, 576.5, 1152.9]),
    (mcs: 6, ss: 1, rates: [77.4, 154.9, 324.3, 648.5, 1297.1]),
    (mcs: 7, ss: 1, rates: [86.0, 172.1, 360.3, 720.6, 1441.2]),
    (mcs: 8, ss: 1, rates: [103.2, 206.5, 432.4, 864.7, 1729.4]),
    (mcs: 9, ss: 1, rates: [114.7, 229.4, 480.4, 960.8, 1921.6]),
    (mcs: 10, ss: 1, rates: [129.0, 258.1, 540.4, 1080.9, 2161.8]),
    (mcs: 11, ss: 1, rates: [143.4, 286.8, 600.5, 1201.0, 2402.0]),
    (mcs: 12, ss: 1, rates: [154.9, 309.7, 648.5, 1297.1, 2594.1]),
    (mcs: 13, ss: 1, rates: [172.1, 344.1, 720.6, 1441.2, 2882.4]),

    (mcs: 0, ss: 2, rates: [17.2, 34.4, 72.1, 144.1, 288.2]),
    (mcs: 1, ss: 2, rates: [34.4, 68.8, 144.1, 288.2, 576.5]),
    (mcs: 2, ss: 2, rates: [51.6, 103.2, 216.2, 432.4, 864.7]),
    (mcs: 3, ss: 2, rates: [68.8, 137.6, 288.2, 576.5, 1152.9]),
    (mcs: 4, ss: 2, rates: [103.2, 206.5, 432.4, 864.7, 1729.4]),
    (mcs: 5, ss: 2, rates: [137.6, 275.3, 576.5, 1152.9, 2305.9]),
    (mcs: 6, ss: 2, rates: [154.9, 309.7, 648.5, 1297.1, 2594.1]),
    (mcs: 7, ss: 2, rates: [172.1, 344.1, 720.6, 1441.2, 2882.4]),
    (mcs: 8, ss: 2, rates: [206.5, 412.9, 864.7, 1729.4, 3458.8]),
    (mcs: 9, ss: 2, rates: [229.4, 458.8, 960.8, 1921.6, 3843.1]),
    (mcs: 10, ss: 2, rates: [258.1, 516.2, 1080.9, 2161.8, 4323.5]),
    (mcs: 11, ss: 2, rates: [286.8, 573.5, 1201.0, 2402.0, 4803.9]),
    (mcs: 12, ss: 2, rates: [309.7, 619.4, 1297.1, 2594.1, 5188.2]),
    (mcs: 13, ss: 2, rates: [344.1, 688.2, 1441.2, 2882.4, 5764.7]),

    (mcs: 0, ss: 3, rates: [25.8, 51.6, 108.1, 216.2, 432.4]),
    (mcs: 1, ss: 3, rates: [51.6, 103.2, 216.2, 432.4, 864.7]),
    (mcs: 2, ss: 3, rates: [77.4, 154.9, 324.3, 648.5, 1297.1]),
    (mcs: 3, ss: 3, rates: [103.2, 206.5, 432.4, 864.7, 1729.4]),
    (mcs: 4, ss: 3, rates: [154.9, 309.7, 648.5, 1297.1, 2594.1]),
    (mcs: 5, ss: 3, rates: [206.5, 412.9, 864.7, 1729.4, 3458.8]),
    (mcs: 6, ss: 3, rates: [232.3, 464.6, 972.8, 1945.6, 3891.2]),
    (mcs: 7, ss: 3, rates: [258.1, 516.2, 1080.9, 2161.8, 4323.5]),
    (mcs: 8, ss: 3, rates: [309.7, 619.4, 1297.1, 2594.1, 5188.2]),
    (mcs: 9, ss: 3, rates: [344.1, 688.2, 1441.2, 2882.4, 5764.7]),
    (mcs: 10, ss: 3, rates: [387.1, 774.3, 1621.3, 3242.6, 6485.3]),
    (mcs: 11, ss: 3, rates: [430.1, 860.3, 1801.5, 3602.9, 7205.9]),
    (mcs: 12, ss: 3, rates: [464.6, 929.1, 1945.6, 3891.2, 7782.4]),
    (mcs: 13, ss: 3, rates: [516.2, 1032.4, 2161.8, 4323.5, 8647.1]),

    (mcs: 0, ss: 4, rates: [34.4, 68.8, 144.1, 288.2, 576.5]),
    (mcs: 1, ss: 4, rates: [68.8, 137.6, 288.2, 576.5, 1152.9]),
    (mcs: 2, ss: 4, rates: [103.2, 206.5, 432.4, 864.7, 1729.4]),
    (mcs: 3, ss: 4, rates: [137.6, 275.3, 576.5, 1152.9, 2305.9]),
    (mcs: 4, ss: 4, rates: [206.5, 412.9, 864.7, 1729.4, 3458.8]),
    (mcs: 5, ss: 4, rates: [275.3, 550.6, 1152.9, 2305.9, 4611.8]),
    (mcs: 6, ss: 4, rates: [309.7, 619.4, 1297.1, 2594.1, 5188.2]),
    (mcs: 7, ss: 4, rates: [344.1, 688.2, 1441.2, 2882.4, 5764.7]),
    (mcs: 8, ss: 4, rates: [412.9, 825.9, 1729.4, 3458.8, 6917.6]),
    (mcs: 9, ss: 4, rates: [458.8, 917.6, 1921.6, 3843.1, 7686.3]),
    (mcs: 10, ss: 4, rates: [516.2, 1032.4, 2161.8, 4323.5, 8647.1]),
    (mcs: 11, ss: 4, rates: [573.5, 1147.1, 2402.0, 4803.9, 9607.8]),
    (mcs: 12, ss: 4, rates: [619.4, 1238.8, 2594.1, 5188.2, 10376.5]),
    (mcs: 13, ss: 4, rates: [688.2, 1376.5, 2882.4, 5764.7, 11529.4]),
  ]);

  // ═══════════════════════════════════════════════════════════════════════════
  // THE EXCLUSIONS, PINNED INDIVIDUALLY.
  //
  // The table above already covers these, but they get their own named tests so
  // that a future reader who breaks one sees WHY it exists, not just "row 37".
  // ═══════════════════════════════════════════════════════════════════════════
  group('VHT stream-dependent exclusions — the N/A cells are facts', () {
    const int c20 = 0;
    const int c40 = 1;
    const int c80 = 2;
    const int c160 = 3;

    double? vht(int mcs, int col, int ss) => McsIndexScreen.rate(
          std: McsStd.ac,
          mcs: mcs,
          columnIndex: col,
          spatialStreams: ss,
        );

    test('MCS 9 @ 20 MHz: N/A at 1, 2 and 4 SS — VALID at 3 SS only', () {
      expect(vht(9, c20, 1), isNull, reason: 'source: N/A');
      expect(vht(9, c20, 2), isNull, reason: 'source: N/A');
      expect(vht(9, c20, 3), 288.9, reason: 'source: 260 LGI / 288.9 SGI');
      // THE REGRESSION. A previous fix concluded "no exclusion above 3 SS"
      // because Keith's chart stops at 3 SS, and the app returned 385.2 here.
      expect(
        vht(9, c20, 4),
        isNull,
        reason: 'source: N/A at 4 SS. The inverse over-generalization ("there '
            'is no exclusion above 3 SS") is exactly as wrong as the original '
            'over-generalization it replaced. Do not fill this hole.',
      );
    });

    test('MCS 9 @ 40 MHz: VALID at every sourced stream count', () {
      // The ORIGINAL bug: the app nulled this column. It is a working rate.
      expect(vht(9, c40, 1), 200.0);
      expect(vht(9, c40, 2), 400.0);
      expect(vht(9, c40, 3), 600.0);
      expect(vht(9, c40, 4), 800.0);
    });

    test('MCS 6 @ 80 MHz: N/A at 3 SS only', () {
      expect(vht(6, c80, 1), 292.5);
      expect(vht(6, c80, 2), 585.0);
      expect(vht(6, c80, 3), isNull, reason: 'source: N/A');
      expect(vht(6, c80, 4), 1170.0);
    });

    test('MCS 9 @ 160 MHz: N/A at 3 SS only', () {
      expect(vht(9, c160, 1), 866.7);
      // 1733.3, NOT 1733.4. The source rounds the exact product.
      expect(vht(9, c160, 2), 1733.3);
      expect(vht(9, c160, 3), isNull, reason: 'source: N/A');
      expect(vht(9, c160, 4), 3466.7);
    });

    test('the exclusion map covers exactly the five sourced N/A cells', () {
      // Keyed '<mcs>:<columnIndex>'. If someone adds a key, this fails and they
      // have to justify it against the source.
      expect(McsIndexScreen.vhtStreamExclusions, <String, Set<int>>{
        '9:0': <int>{1, 2, 4},
        '6:2': <int>{3},
        '9:3': <int>{3},
      });
    });

    test('no exclusion is claimed at a stream count the source never covers',
        () {
      // The map may only speak about 1-4 SS. Above that the source is silent,
      // and silence is handled by the honest-null rule, not by the mask.
      for (final MapEntry<String, Set<int>> e
          in McsIndexScreen.vhtStreamExclusions.entries) {
        for (final int ss in e.value) {
          expect(
            ss,
            inInclusiveRange(1, McsIndexScreen.maxSourcedStreams),
            reason: 'Exclusion "${e.key}" claims something at $ss SS. The '
                'source table stops at ${McsIndexScreen.maxSourcedStreams} SS. '
                'An exclusion beyond it would be invented.',
          );
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // ABOVE 4 SS — THE HONEST HOLE.
  //
  // Neither Keith's chart nor mcsindex publishes 5-8 spatial streams. We do not
  // know which cells are excluded up there, and the exclusions are NOT
  // derivable (see the header note). So the app computes nothing.
  //
  // A hole we know about beats an invention we don't.
  // ═══════════════════════════════════════════════════════════════════════════
  group('above 4 SS the app refuses to invent a rate', () {
    test('the sourced ceiling is 4 spatial streams', () {
      expect(McsIndexScreen.maxSourcedStreams, 4);
    });

    test('every standard returns null for 5-8 SS', () {
      for (final McsStd std in McsStd.values) {
        final McsStdData data = McsIndexScreen.dataFor(std);
        for (int ss = 5; ss <= 8; ss++) {
          for (final McsRow row in data.rows) {
            for (int c = 0; c < data.columns.length; c++) {
              expect(
                McsIndexScreen.rate(
                  std: std,
                  mcs: row.mcs,
                  columnIndex: c,
                  spatialStreams: ss,
                ),
                isNull,
                reason: '$std MCS ${row.mcs} col $c at $ss SS: the source stops '
                    'at 4 SS. Computing a rate here would be an invention — and '
                    'for VHT it would silently assert the exclusions vanish.',
              );
            }
          }
        }
      }
    });

    test('isSourcedStreamCount draws the line at 4', () {
      expect(McsIndexScreen.isSourcedStreamCount(0), isFalse);
      for (int ss = 1; ss <= 4; ss++) {
        expect(McsIndexScreen.isSourcedStreamCount(ss), isTrue);
      }
      for (int ss = 5; ss <= 8; ss++) {
        expect(McsIndexScreen.isSourcedStreamCount(ss), isFalse);
      }
    });

    test('"unsourced" is NOT the same claim as "invalid"', () {
      // This is the whole point of the distinction. VHT MCS 9 @ 40 MHz is a
      // VALID combination at 8 SS as far as 802.11ac is concerned — we simply
      // have no published rate for it. Rendering it as "N/A" in the same style
      // as a genuine exclusion would repeat the original bug in a new costume:
      // marking a working cell invalid. The screen must say "not sourced",
      // never "N/A", above 4 SS.
      expect(McsIndexScreen.notesText, contains('4 spatial streams'));
      expect(McsIndexScreen.unsourcedStreamsNotice, contains('4 spatial'));
      expect(
        McsIndexScreen.unsourcedStreamsNotice.toUpperCase(),
        isNot(contains('N/A')),
        reason: 'Unsourced is not invalid. Do not label it N/A.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // THE ROUNDING CONTRACT.
  // ═══════════════════════════════════════════════════════════════════════════
  group('rates round the exact product, not a rounded base', () {
    test('VHT MCS 9 @ 160 MHz, 2 SS = 1733.3 (not 866.7 x 2 = 1733.4)', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.ac, mcs: 9, columnIndex: 3, spatialStreams: 2),
        1733.3,
      );
    });

    test('HE MCS 11 @ 160 MHz, 4 SS = 4803.9 (not 1201.0 x 4 = 4804.0)', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.ax, mcs: 11, columnIndex: 3, spatialStreams: 4),
        4803.9,
      );
    });

    test('HT MCS 0 @ 20 SGI, 3 SS = 21.7 (not 7.2 x 3 = 21.6)', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.n, mcs: 0, columnIndex: 1, spatialStreams: 3),
        21.7,
      );
    });
  });
}
