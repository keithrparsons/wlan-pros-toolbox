// Channel Map — read-only visual channel-bonding reference, offline.
//
// Ported verbatim from the rf-tools-pwa `chanmap` tool (www/app.js:
// buildChanMap + CM5_SLOTS/CM5_40/CM5_80/CM5_160, CM6_CHS/CM6_40/CM6_80/
// CM6_160/CM6_PSC5, and the CH24/CH5/CH6 datasets). This is the PWA's *visual
// bonding map* view (data-tool="chanmap"), distinct from the Wi-Fi Channels
// table (data-tool="channels"): it shows, per band, the 20/40/80/160/320 MHz
// bonded widths stacked as rows, each bonded block labelled with its primary
// (center) channel, with DFS markings carried over from the PWA.
//
// The PWA draws this as an SVG with literal hex fills. GL-003 forbids hardcoded
// color, so the DFS/PSC semantics are re-expressed with the §8.13 status
// palette (no-DFS → info blue, DFS → warning amber, mixed-160 → danger, PSC →
// lime primary) — same meaning, design-system tokens. The bonding tuples,
// channel sets, and notes are reproduced exactly; no data is invented.
//
// States (SOP-007 §5) for a read-only reference screen:
//  - success    → the selected band's bonding rows render in a card.
//  - empty      → not reachable; every band has rows. (No fabricated row.)
//  - loading    → not reachable; data is a compile-time const, not an asset.
//  - error      → not reachable; nothing to parse at runtime.
//  - interactive→ the band toggle (2.4 / 5 / 6 GHz) is the only control.
//
// OVERFLOW-SAFE: the 5/6 GHz maps are wider than a phone; each band map sits in
// a horizontal SingleChildScrollView with fixed-width slot cells (no Expanded
// inside the unbounded scroll width). The band toggle wraps each option in
// Expanded so it never overflows phone width. Matches the PWA, which itself
// asks the user to "scroll the 5 GHz and 6 GHz views horizontally".
//
// The datasets are exposed as public static const lists on ChannelMapScreen so
// they are unit-testable without pumping the widget.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';

/// Which band's bonding map is shown. 2.4 / 5 / 6 GHz — three short options, so
/// a segmented toggle, not an AppSelect (GL-003 §8.14).
enum ChanMapBand { ghz24, ghz5, ghz6 }

/// DFS / scanning semantics for a bonded block. Mirrors the PWA's color key:
///  - noDfs : blue  — no DFS required.
///  - dfs   : orange — DFS (radar detection) required.
///  - mixed : purple — a 160 MHz bond spanning a DFS and a non-DFS sub-band;
///            any DFS sub-channel makes the whole bond subject to DFS.
///  - psc   : the 20 MHz primary-scanning channels in 6 GHz (lime emphasis).
enum DfsClass { noDfs, dfs, mixed, psc }

/// One 2.4 GHz 20 MHz channel block in the map. ch 1–11 (US); 1/6/11 are the
/// only non-overlapping primaries (solid in the PWA), 2–5/7–10 overlap (faint).
class ChanMap24 {
  const ChanMap24({
    required this.channel,
    required this.freqMhz,
    required this.nonOverlap,
  });

  final int channel;
  final int freqMhz;
  final bool nonOverlap;
}

/// One bonded block in the 5 GHz or 6 GHz map: a width (20/40/80/160/320 MHz),
/// the primary/center channel number the PWA prints in the block, the two edge
/// channels that bound it, and its DFS/scanning class.
class BondedBlock {
  const BondedBlock({
    required this.widthMhz,
    required this.centerChannel,
    required this.lowChannel,
    required this.highChannel,
    required this.dfs,
    this.alt = false,
  });

  /// Bonded width in MHz: 20, 40, 80, 160, or 320.
  final int widthMhz;

  /// Primary (center) channel printed in the block — what the PWA labels.
  final int centerChannel;

  /// Lowest 20 MHz sub-channel in the bond (for span / testing).
  final int lowChannel;

  /// Highest 20 MHz sub-channel in the bond.
  final int highChannel;

  /// DFS / scanning class — drives the block tint and its paired text label.
  final DfsClass dfs;

  /// True for the 6 GHz ch 63 alternative 320 MHz block (dashed in the PWA):
  /// it overlaps ch 31 so only one is used at a time.
  final bool alt;

  /// Number of 20 MHz sub-channels spanned. 20→1, 40→2, 80→4, 160→8, 320→16.
  int get subChannels => widthMhz ~/ 20;
}

class ChannelMapScreen extends StatefulWidget {
  const ChannelMapScreen({super.key});

  // ── Datasets (public, const, unit-testable) ───────────────────────────────

  /// 2.4 GHz — ch 1–11 (US), freq = 2412 + (ch-1)·5 MHz; non-overlap = {1,6,11}.
  /// Verbatim from PWA `CH24` (Array.from length 11) used by buildChanMap's
  /// 2.4 GHz block.
  static const List<ChanMap24> map24 = [
    ChanMap24(channel: 1, freqMhz: 2412, nonOverlap: true),
    ChanMap24(channel: 2, freqMhz: 2417, nonOverlap: false),
    ChanMap24(channel: 3, freqMhz: 2422, nonOverlap: false),
    ChanMap24(channel: 4, freqMhz: 2427, nonOverlap: false),
    ChanMap24(channel: 5, freqMhz: 2432, nonOverlap: false),
    ChanMap24(channel: 6, freqMhz: 2437, nonOverlap: true),
    ChanMap24(channel: 7, freqMhz: 2442, nonOverlap: false),
    ChanMap24(channel: 8, freqMhz: 2447, nonOverlap: false),
    ChanMap24(channel: 9, freqMhz: 2452, nonOverlap: false),
    ChanMap24(channel: 10, freqMhz: 2457, nonOverlap: false),
    ChanMap24(channel: 11, freqMhz: 2462, nonOverlap: true),
  ];

  // ── 5 GHz bonding map (US, FCC) ────────────────────────────────────────────
  //
  // DFS class per PWA `cm5DFSType`, computed on the CM5_SLOTS index:
  //   slot ≤ 3            → UNII-1            → noDfs
  //   slot ≥ 20           → UNII-3            → noDfs
  //   slot 4–19 (both)    → UNII-2A/2C        → dfs
  //   straddles a boundary→ mixed (160 MHz across UNII-1+2A)
  // Center channel per PWA: round((c1+c2)/2). Slot order from CM5_SLOTS.

  /// 5 GHz 20 MHz primaries — verbatim from PWA `CH5` (ch + DFS). noDfs for
  /// UNII-1 (36–48) and UNII-3 (149–165); dfs for UNII-2A (52–64) and UNII-2C
  /// (100–144).
  static const List<BondedBlock> map5_20 = [
    BondedBlock(
      widthMhz: 20,
      centerChannel: 36,
      lowChannel: 36,
      highChannel: 36,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 40,
      lowChannel: 40,
      highChannel: 40,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 44,
      lowChannel: 44,
      highChannel: 44,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 48,
      lowChannel: 48,
      highChannel: 48,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 52,
      lowChannel: 52,
      highChannel: 52,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 56,
      lowChannel: 56,
      highChannel: 56,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 60,
      lowChannel: 60,
      highChannel: 60,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 64,
      lowChannel: 64,
      highChannel: 64,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 100,
      lowChannel: 100,
      highChannel: 100,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 104,
      lowChannel: 104,
      highChannel: 104,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 108,
      lowChannel: 108,
      highChannel: 108,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 112,
      lowChannel: 112,
      highChannel: 112,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 116,
      lowChannel: 116,
      highChannel: 116,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 120,
      lowChannel: 120,
      highChannel: 120,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 124,
      lowChannel: 124,
      highChannel: 124,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 128,
      lowChannel: 128,
      highChannel: 128,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 132,
      lowChannel: 132,
      highChannel: 132,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 136,
      lowChannel: 136,
      highChannel: 136,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 140,
      lowChannel: 140,
      highChannel: 140,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 144,
      lowChannel: 144,
      highChannel: 144,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 149,
      lowChannel: 149,
      highChannel: 149,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 153,
      lowChannel: 153,
      highChannel: 153,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 157,
      lowChannel: 157,
      highChannel: 157,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 161,
      lowChannel: 161,
      highChannel: 161,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 165,
      lowChannel: 165,
      highChannel: 165,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 5 GHz 40 MHz bonds — verbatim from PWA `CM5_40`. Center = round((c1+c2)/2).
  static const List<BondedBlock> map5_40 = [
    BondedBlock(
      widthMhz: 40,
      centerChannel: 38,
      lowChannel: 36,
      highChannel: 40,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 46,
      lowChannel: 44,
      highChannel: 48,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 54,
      lowChannel: 52,
      highChannel: 56,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 62,
      lowChannel: 60,
      highChannel: 64,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 102,
      lowChannel: 100,
      highChannel: 104,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 110,
      lowChannel: 108,
      highChannel: 112,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 118,
      lowChannel: 116,
      highChannel: 120,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 126,
      lowChannel: 124,
      highChannel: 128,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 134,
      lowChannel: 132,
      highChannel: 136,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 142,
      lowChannel: 140,
      highChannel: 144,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 151,
      lowChannel: 149,
      highChannel: 153,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 159,
      lowChannel: 157,
      highChannel: 161,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 5 GHz 80 MHz bonds — verbatim from PWA `CM5_80`. Center = round((c1+c2)/2).
  static const List<BondedBlock> map5_80 = [
    BondedBlock(
      widthMhz: 80,
      centerChannel: 42,
      lowChannel: 36,
      highChannel: 48,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 58,
      lowChannel: 52,
      highChannel: 64,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 106,
      lowChannel: 100,
      highChannel: 112,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 122,
      lowChannel: 116,
      highChannel: 128,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 138,
      lowChannel: 132,
      highChannel: 144,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 155,
      lowChannel: 149,
      highChannel: 161,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 5 GHz 160 MHz bonds — verbatim from PWA `CM5_160`. Center = round((c1+c2)/2).
  /// ch 50 (36–64) spans UNII-1 + UNII-2A → mixed: a non-DFS + DFS span, so the
  /// whole bond is subject to DFS (the PWA's purple block).
  static const List<BondedBlock> map5_160 = [
    BondedBlock(
      widthMhz: 160,
      centerChannel: 50,
      lowChannel: 36,
      highChannel: 64,
      dfs: DfsClass.mixed,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 114,
      lowChannel: 100,
      highChannel: 128,
      dfs: DfsClass.dfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 130,
      lowChannel: 116,
      highChannel: 144,
      dfs: DfsClass.dfs,
    ),
  ];

  // ── 6 GHz bonding map (full US band, UNII-5 through UNII-8) ─────────────────
  //
  // The PWA's chanmap *view* drew only UNII-5 (ch 1–93); but the PWA's own data
  // tables (www/app.js: "Full band: 59 × 20 MHz channels (ch 1–233)" and
  // "59 × 20 MHz · 29 × 40 MHz · 14 × 80 MHz · 7 × 160 MHz · 3 × 320 MHz") state
  // the complete US 6 GHz plan. v1.1.1 restores the full band per Ferney's beta
  // report (the map was truncated at ch 93). Canonical US 6 GHz plan, 5925–7125
  // MHz: 20 MHz channels 1,5,9,…,233 (59 channels). PSC = every 4th 20 MHz
  // channel from 5: {5,21,37,…,229} (15 channels). Center labels per PWA rule:
  // 40→c1+2, 80→c1+6, 160→c1+14, 320→c1+30. 320 MHz has a primary set (centers
  // 31,95,159) and an overlapping alternative set (centers 63,127,191).

  /// 6 GHz 20 MHz primaries — full US band ch 1,5,9,…,233 (UNII-5 through
  /// UNII-8). PSC channels (5,21,37,…,229) are the preferred scanning channels
  /// Wi-Fi 6E/7 clients scan first.
  static const List<BondedBlock> map6_20 = [
    BondedBlock(
      widthMhz: 20,
      centerChannel: 1,
      lowChannel: 1,
      highChannel: 1,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 5,
      lowChannel: 5,
      highChannel: 5,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 9,
      lowChannel: 9,
      highChannel: 9,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 13,
      lowChannel: 13,
      highChannel: 13,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 17,
      lowChannel: 17,
      highChannel: 17,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 21,
      lowChannel: 21,
      highChannel: 21,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 25,
      lowChannel: 25,
      highChannel: 25,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 29,
      lowChannel: 29,
      highChannel: 29,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 33,
      lowChannel: 33,
      highChannel: 33,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 37,
      lowChannel: 37,
      highChannel: 37,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 41,
      lowChannel: 41,
      highChannel: 41,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 45,
      lowChannel: 45,
      highChannel: 45,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 49,
      lowChannel: 49,
      highChannel: 49,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 53,
      lowChannel: 53,
      highChannel: 53,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 57,
      lowChannel: 57,
      highChannel: 57,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 61,
      lowChannel: 61,
      highChannel: 61,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 65,
      lowChannel: 65,
      highChannel: 65,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 69,
      lowChannel: 69,
      highChannel: 69,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 73,
      lowChannel: 73,
      highChannel: 73,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 77,
      lowChannel: 77,
      highChannel: 77,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 81,
      lowChannel: 81,
      highChannel: 81,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 85,
      lowChannel: 85,
      highChannel: 85,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 89,
      lowChannel: 89,
      highChannel: 89,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 93,
      lowChannel: 93,
      highChannel: 93,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 97,
      lowChannel: 97,
      highChannel: 97,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 101,
      lowChannel: 101,
      highChannel: 101,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 105,
      lowChannel: 105,
      highChannel: 105,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 109,
      lowChannel: 109,
      highChannel: 109,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 113,
      lowChannel: 113,
      highChannel: 113,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 117,
      lowChannel: 117,
      highChannel: 117,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 121,
      lowChannel: 121,
      highChannel: 121,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 125,
      lowChannel: 125,
      highChannel: 125,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 129,
      lowChannel: 129,
      highChannel: 129,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 133,
      lowChannel: 133,
      highChannel: 133,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 137,
      lowChannel: 137,
      highChannel: 137,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 141,
      lowChannel: 141,
      highChannel: 141,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 145,
      lowChannel: 145,
      highChannel: 145,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 149,
      lowChannel: 149,
      highChannel: 149,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 153,
      lowChannel: 153,
      highChannel: 153,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 157,
      lowChannel: 157,
      highChannel: 157,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 161,
      lowChannel: 161,
      highChannel: 161,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 165,
      lowChannel: 165,
      highChannel: 165,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 169,
      lowChannel: 169,
      highChannel: 169,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 173,
      lowChannel: 173,
      highChannel: 173,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 177,
      lowChannel: 177,
      highChannel: 177,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 181,
      lowChannel: 181,
      highChannel: 181,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 185,
      lowChannel: 185,
      highChannel: 185,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 189,
      lowChannel: 189,
      highChannel: 189,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 193,
      lowChannel: 193,
      highChannel: 193,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 197,
      lowChannel: 197,
      highChannel: 197,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 201,
      lowChannel: 201,
      highChannel: 201,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 205,
      lowChannel: 205,
      highChannel: 205,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 209,
      lowChannel: 209,
      highChannel: 209,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 213,
      lowChannel: 213,
      highChannel: 213,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 217,
      lowChannel: 217,
      highChannel: 217,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 221,
      lowChannel: 221,
      highChannel: 221,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 225,
      lowChannel: 225,
      highChannel: 225,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 229,
      lowChannel: 229,
      highChannel: 229,
      dfs: DfsClass.psc,
    ),
    BondedBlock(
      widthMhz: 20,
      centerChannel: 233,
      lowChannel: 233,
      highChannel: 233,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 6 GHz 40 MHz bonds — full band. Center label = c1+2 (PWA CM6_40 rule).
  static const List<BondedBlock> map6_40 = [
    BondedBlock(
      widthMhz: 40,
      centerChannel: 3,
      lowChannel: 1,
      highChannel: 5,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 11,
      lowChannel: 9,
      highChannel: 13,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 19,
      lowChannel: 17,
      highChannel: 21,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 27,
      lowChannel: 25,
      highChannel: 29,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 35,
      lowChannel: 33,
      highChannel: 37,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 43,
      lowChannel: 41,
      highChannel: 45,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 51,
      lowChannel: 49,
      highChannel: 53,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 59,
      lowChannel: 57,
      highChannel: 61,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 67,
      lowChannel: 65,
      highChannel: 69,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 75,
      lowChannel: 73,
      highChannel: 77,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 83,
      lowChannel: 81,
      highChannel: 85,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 91,
      lowChannel: 89,
      highChannel: 93,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 99,
      lowChannel: 97,
      highChannel: 101,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 107,
      lowChannel: 105,
      highChannel: 109,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 115,
      lowChannel: 113,
      highChannel: 117,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 123,
      lowChannel: 121,
      highChannel: 125,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 131,
      lowChannel: 129,
      highChannel: 133,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 139,
      lowChannel: 137,
      highChannel: 141,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 147,
      lowChannel: 145,
      highChannel: 149,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 155,
      lowChannel: 153,
      highChannel: 157,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 163,
      lowChannel: 161,
      highChannel: 165,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 171,
      lowChannel: 169,
      highChannel: 173,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 179,
      lowChannel: 177,
      highChannel: 181,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 187,
      lowChannel: 185,
      highChannel: 189,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 195,
      lowChannel: 193,
      highChannel: 197,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 203,
      lowChannel: 201,
      highChannel: 205,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 211,
      lowChannel: 209,
      highChannel: 213,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 219,
      lowChannel: 217,
      highChannel: 221,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 40,
      centerChannel: 227,
      lowChannel: 225,
      highChannel: 229,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 6 GHz 80 MHz bonds — full band. Center label = c1+6 (PWA CM6_80 rule).
  static const List<BondedBlock> map6_80 = [
    BondedBlock(
      widthMhz: 80,
      centerChannel: 7,
      lowChannel: 1,
      highChannel: 13,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 23,
      lowChannel: 17,
      highChannel: 29,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 39,
      lowChannel: 33,
      highChannel: 45,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 55,
      lowChannel: 49,
      highChannel: 61,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 71,
      lowChannel: 65,
      highChannel: 77,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 87,
      lowChannel: 81,
      highChannel: 93,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 103,
      lowChannel: 97,
      highChannel: 109,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 119,
      lowChannel: 113,
      highChannel: 125,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 135,
      lowChannel: 129,
      highChannel: 141,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 151,
      lowChannel: 145,
      highChannel: 157,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 167,
      lowChannel: 161,
      highChannel: 173,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 183,
      lowChannel: 177,
      highChannel: 189,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 199,
      lowChannel: 193,
      highChannel: 205,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 80,
      centerChannel: 215,
      lowChannel: 209,
      highChannel: 221,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 6 GHz 160 MHz bonds — full band. Center label = c1+14 (PWA CM6_160 rule).
  static const List<BondedBlock> map6_160 = [
    BondedBlock(
      widthMhz: 160,
      centerChannel: 15,
      lowChannel: 1,
      highChannel: 29,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 47,
      lowChannel: 33,
      highChannel: 61,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 79,
      lowChannel: 65,
      highChannel: 93,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 111,
      lowChannel: 97,
      highChannel: 125,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 143,
      lowChannel: 129,
      highChannel: 157,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 175,
      lowChannel: 161,
      highChannel: 189,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 160,
      centerChannel: 207,
      lowChannel: 193,
      highChannel: 221,
      dfs: DfsClass.noDfs,
    ),
  ];

  /// 6 GHz 320 MHz bonds — full band. Center label = c1+30. The primary set
  /// (320-1) centers on 31, 95, 159; the alternative set (320-2) centers on
  /// 63, 127, 191 and overlaps the primary set, so a primary and its alternate
  /// are not used at the same time. `alt` marks the 320-2 blocks (the PWA drew
  /// ch 63 dashed for exactly this reason).
  static const List<BondedBlock> map6_320 = [
    BondedBlock(
      widthMhz: 320,
      centerChannel: 31,
      lowChannel: 1,
      highChannel: 61,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 320,
      centerChannel: 95,
      lowChannel: 65,
      highChannel: 125,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 320,
      centerChannel: 159,
      lowChannel: 129,
      highChannel: 189,
      dfs: DfsClass.noDfs,
    ),
    BondedBlock(
      widthMhz: 320,
      centerChannel: 63,
      lowChannel: 33,
      highChannel: 93,
      dfs: DfsClass.noDfs,
      alt: true,
    ),
    BondedBlock(
      widthMhz: 320,
      centerChannel: 127,
      lowChannel: 97,
      highChannel: 157,
      dfs: DfsClass.noDfs,
      alt: true,
    ),
    BondedBlock(
      widthMhz: 320,
      centerChannel: 191,
      lowChannel: 161,
      highChannel: 221,
      dfs: DfsClass.noDfs,
      alt: true,
    ),
  ];

  @override
  State<ChannelMapScreen> createState() => _ChannelMapScreenState();
}

class _ChannelMapScreenState extends State<ChannelMapScreen> {
  ChanMapBand _band = ChanMapBand.ghz24;

  void _onBandChanged(ChanMapBand next) {
    if (next == _band) return;
    setState(() => _band = next);
    // WCAG 4.1.3 — announce which band's map is now shown.
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_bandLabel(next)} channel map',
      TextDirection.ltr,
    );
  }

  static String _bandLabel(ChanMapBand b) {
    switch (b) {
      case ChanMapBand.ghz24:
        return '2.4 GHz';
      case ChanMapBand.ghz5:
        return '5 GHz';
      case ChanMapBand.ghz6:
        return '6 GHz';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channel Map'),
        toolbarHeight: 64,
        // §8.16 — copy all three band maps as TSV. The maps are static const
        // data (the band toggle only picks which one renders, all are present),
        // so the affordance is always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — every band's channel map as TSV, regardless of which
  /// band is currently toggled on screen (the data is all present; the toggle
  /// only chooses what renders). Three sections:
  ///   - 2.4 GHz: Channel / Frequency (MHz) / Overlap.
  ///   - 5 GHz and 6 GHz: each bonded width as its own sub-section with
  ///     Width (MHz) / Center channel / Low channel / High channel / Class —
  ///     where Class is the worded DFS/PSC label (§8.13: the color carries the
  ///     class on screen; the word carries it to the clipboard).
  /// Always non-null: the datasets are static, so copy is never disabled.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer();

    // ── 2.4 GHz ──
    buf
      ..writeln('2.4 GHz — 20 MHz channels (US)')
      ..writeln(<String>['Channel', 'Frequency (MHz)', 'Overlap'].join(tab));
    for (final ChanMap24 c in ChannelMapScreen.map24) {
      buf.writeln(
        <String>[
          '${c.channel}',
          '${c.freqMhz}',
          c.nonOverlap ? 'Non-overlapping' : 'Overlapping',
        ].join(tab),
      );
    }

    // ── 5 GHz bonded widths ──
    buf
      ..writeln()
      ..writeln('5 GHz — bonded widths (US, FCC)');
    _writeBonded(buf, tab, '20 MHz', ChannelMapScreen.map5_20);
    _writeBonded(buf, tab, '40 MHz', ChannelMapScreen.map5_40);
    _writeBonded(buf, tab, '80 MHz', ChannelMapScreen.map5_80);
    _writeBonded(buf, tab, '160 MHz', ChannelMapScreen.map5_160);

    // ── 6 GHz bonded widths ──
    buf
      ..writeln()
      ..writeln('6 GHz — full US band, ch 1–233 (UNII-5 to UNII-8)');
    _writeBonded(buf, tab, '20 MHz', ChannelMapScreen.map6_20);
    _writeBonded(buf, tab, '40 MHz', ChannelMapScreen.map6_40);
    _writeBonded(buf, tab, '80 MHz', ChannelMapScreen.map6_80);
    _writeBonded(buf, tab, '160 MHz', ChannelMapScreen.map6_160);
    _writeBonded(buf, tab, '320 MHz', ChannelMapScreen.map6_320);

    return buf.toString().trimRight();
  }

  /// One bonded-width sub-section: a subtitle, a header, then one row per block.
  void _writeBonded(
    StringBuffer buf,
    String tab,
    String widthLabel,
    List<BondedBlock> blocks,
  ) {
    buf
      ..writeln(widthLabel)
      ..writeln(
        <String>[
          'Width (MHz)',
          'Center channel',
          'Low channel',
          'High channel',
          'Class',
        ].join(tab),
      );
    for (final BondedBlock b in blocks) {
      buf.writeln(
        <String>[
          '${b.widthMhz}',
          b.alt ? '${b.centerChannel} (alt)' : '${b.centerChannel}',
          '${b.lowChannel}',
          '${b.highChannel}',
          _dfsLabel(b.dfs),
        ].join(tab),
      );
    }
  }

  Widget _body() {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return LayoutBuilder(
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
                    toolId: 'channel-map',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('channel-map'))
                    const SizedBox(height: AppSpacing.md),
                  _intro(context),
                  const SizedBox(height: AppSpacing.sm),
                  _bandCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _mapCard(context, mono),
                  ToolHelpFooter(toolId: 'channel-map'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _intro(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      'Visual channel bonding map: center channels, bonded widths, and '
      'non-overlapping groupings for 2.4, 5, and 6 GHz. Scroll the 5 GHz and '
      '6 GHz maps horizontally.',
      style: text.labelMedium?.copyWith(color: colors.textTertiary),
    );
  }

  Widget _bandCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
            'Band',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 2.4 / 5 / 6 GHz — three short options, segmented toggle (§8.14).
          _BandToggle(value: _band, onChanged: _onBandChanged),
        ],
      ),
    );
  }

  Widget _mapCard(BuildContext context, AppMonoText mono) {
    switch (_band) {
      case ChanMapBand.ghz24:
        return _Map24(mono: mono);
      case ChanMapBand.ghz5:
        return _Map5(mono: mono);
      case ChanMapBand.ghz6:
        return _Map6(mono: mono);
    }
  }
}

// ── DFS / scanning class → status token + label ──────────────────────────────

/// Tint and paired label for a DfsClass. `color` carries the verdict/affordance
/// hue; the label keeps it from being color-only (§8.13 rule 2). `neutral` flips
/// the rendering to the §8.1/§8.2 neutral stack (surface tint + decorative
/// border + tertiary text) for classes that are a plain *attribute*, not a
/// verdict — per §8.15 case-3, an attribute gets no status hue.
class _DfsStyle {
  const _DfsStyle(this.color, this.label, {this.neutral = false});
  final Color color;
  final String label;
  final bool neutral;
}

// Theme-independent label lookup (used by the copy/share text buffer, which has
// no color or BuildContext in scope).
String _dfsLabel(DfsClass d) {
  switch (d) {
    case DfsClass.noDfs:
      return 'No DFS';
    case DfsClass.dfs:
      return 'DFS';
    case DfsClass.mixed:
      return 'Mixed / DFS';
    case DfsClass.psc:
      return 'PSC';
  }
}

_DfsStyle _dfsStyle(DfsClass d, AppColorScheme colors) {
  switch (d) {
    case DfsClass.noDfs:
      // §8.15 R-03: "No DFS" is an attribute (the absence of a regulatory
      // requirement), not an info verdict. It gets no status hue — render it
      // neutral (surface tint + decorative border + tertiary text). It stays
      // distinguishable from DFS (amber) and Mixed (danger) by being the only
      // un-tinted, neutral class.
      return _DfsStyle(colors.textTertiary, _dfsLabel(d), neutral: true);
    case DfsClass.dfs:
      return _DfsStyle(colors.statusWarning, _dfsLabel(d));
    case DfsClass.mixed:
      return _DfsStyle(colors.statusDanger, _dfsLabel(d));
    case DfsClass.psc:
      // PSC is the lime-marked "preferred scanning channel" class. The color is
      // a FOREGROUND marker (chip text + border), so it uses textAccent — lime
      // in dark, darkened-lime in light (§8.20.2 lime split).
      return _DfsStyle(colors.textAccent, _dfsLabel(d));
  }
}

// ── Shared map chrome ─────────────────────────────────────────────────────────

/// Card chrome for a band map: title, the horizontally-scrolling bonding grid,
/// a color legend, and a footnote. The grid is the only horizontally-scrolled
/// region; title/legend/footnote stay full-width and wrap.
class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.title,
    required this.grid,
    required this.legend,
    required this.footnote,
  });

  final String title;
  final Widget grid;
  final List<DfsClass> legend;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Only the bonding grid scrolls horizontally; its children take their
          // intrinsic (fixed) width, so nothing is pinned to a guessed value
          // that would overflow a phone. Matches wifi_channels_screen.dart and
          // the PWA's own "scroll horizontally" treatment for 5/6 GHz.
          HorizontalScrollTable(child: grid),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: legend.map((d) {
              final _DfsStyle st = _dfsStyle(d, colors);
              return _Chip(st.label, color: st.color, neutral: st.neutral);
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            footnote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Width of one 20 MHz slot column in the bonding grid. Fixed so bonded blocks
/// can be sized as integer multiples and columns align across rows.
///
/// v1.1.1: widened 30→40 so a 3-digit center-channel label (100–177 in the
/// 5 GHz map; 100–233 in the full 6 GHz map) fits inside a 20 MHz cell at the
/// uniform DM Mono body size (16px) without clipping/ellipsis — Ferney's beta
/// finding. The maps already live in a horizontal SingleChildScrollView, so a
/// wider slot only lengthens the scroll content; phone width is unaffected.
const double _kSlot = 40;

/// Horizontal gap between adjacent slot columns; a bonded block of N sub-
/// channels is N·_kSlot + (N-1)·_kGap wide so it visually spans its primaries.
const double _kGap = 4;

/// Height of one bonding-row block.
const double _kBlockH = 40;

/// Vertical gap between bonding rows (20 / 40 / 80 / …).
const double _kRowGap = 8;

/// Width of the left-hand row-label gutter ("20", "40", "80", "160", "320").
const double _kGutter = 44;

double _blockWidth(int subChannels) =>
    subChannels * _kSlot + (subChannels - 1) * _kGap;

/// One bonded block rendered as a tinted, bordered cell labelled with its
/// primary/center channel. Sized to span its sub-channels so the bonding is
/// visually obvious across rows.
class _Block extends StatelessWidget {
  const _Block({required this.block, required this.mono});

  final BondedBlock block;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final _DfsStyle st = _dfsStyle(block.dfs, colors);
    // Neutral (No DFS) blocks use the §8.1/§8.2 neutral stack — a faint surface
    // tint + decorative border — matching the 2.4 GHz overlapping-channel idiom
    // already in this file. Verdict classes keep their status-hue tint.
    final Color blockFill = st.neutral
        ? colors.textTertiary.withValues(alpha: 0.06)
        : st.color.withValues(alpha: 0.18);
    final Color blockBorder = st.neutral ? colors.border : st.color;
    final String label = block.alt
        ? '${block.centerChannel} alt'
        : '${block.centerChannel}';
    return Semantics(
      label:
          '${block.widthMhz} megahertz, primary channel ${block.centerChannel}'
          '${block.alt ? ' alternate' : ''}, ${st.label}',
      child: Container(
        width: _blockWidth(block.subChannels),
        height: _kBlockH,
        margin: const EdgeInsets.only(right: _kGap),
        alignment: Alignment.center,
        // Small horizontal inset so the label never butts the rounded border.
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: blockFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: blockBorder,
            width: 1,
            // Dashed look isn't a Border feature; the "alt" block is instead
            // marked by its label suffix and a lighter fill. (PWA dashed = alt.)
          ),
        ),
        // BF6-7: a 3-digit center channel (100–233) in the narrow single-slot
        // (20 MHz) bonded cell was clipping/ellipsizing at the uniform 16px DM
        // Mono size. FittedBox scaleDown guarantees the full label fits any
        // cell width — it only shrinks when the text would otherwise overflow
        // (3-digit labels in a 40px slot), leaving wider bonded blocks
        // unaffected — so no channel number is ever truncated, light or dark.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: mono.inlineCode.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// One bonding row: a fixed-width gutter label ("40") + the row's blocks laid
/// out left-to-right. Used by the 5/6 GHz maps inside the horizontal scroll.
class _BondRow extends StatelessWidget {
  const _BondRow({
    required this.widthLabel,
    required this.blocks,
    required this.mono,
  });

  final String widthLabel;
  final List<BondedBlock> blocks;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: _kRowGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _kGutter,
            child: Text(
              widthLabel,
              style: text.labelSmall?.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          ...blocks.map((b) => _Block(block: b, mono: mono)),
        ],
      ),
    );
  }
}

// ── 2.4 GHz map ───────────────────────────────────────────────────────────────

class _Map24 extends StatelessWidget {
  const _Map24({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    // 11 channels, each a 20 MHz block. Non-overlapping 1/6/11 emphasized in
    // lime; overlapping 2–5/7–10 rendered faint (decorative border tint).
    final List<Widget> blocks = ChannelMapScreen.map24.map((c) {
      final bool primary = c.nonOverlap;
      // Lime emphasis is a thin border line + low-alpha tint fill. Per §8.20.2
      // lime is forbidden as a thin foreground on light, so this reads from
      // textAccent (lime in dark, darkened-lime in light).
      final Color tint = primary ? colors.textAccent : colors.textTertiary;
      return Semantics(
        label: c.nonOverlap
            ? 'Channel ${c.channel}, ${c.freqMhz} megahertz, non-overlapping'
            : 'Channel ${c.channel}, ${c.freqMhz} megahertz, overlapping',
        child: Container(
          width: _kSlot * 2,
          margin: const EdgeInsets.only(right: _kGap),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: primary ? 0.18 : 0.06),
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: primary ? colors.textAccent : colors.border,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${c.channel}',
                style: mono.inlineCode.copyWith(
                  color: primary
                      ? colors.textPrimary
                      : colors.textTertiary,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              Text(
                '${c.freqMhz}',
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return _MapCard(
      title: '2.4 GHz — 20 MHz channels (US)',
      grid: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(children: blocks),
      ),
      legend: const [DfsClass.noDfs],
      footnote:
          'Solid lime: channels 1, 6, 11 — the only non-overlapping 20 MHz '
          'channels. Faint: channels 2–5, 7–10 all overlap with at least one '
          'preferred channel. Never use them as primary channels.',
    );
  }
}

// ── 5 GHz map ─────────────────────────────────────────────────────────────────

class _Map5 extends StatelessWidget {
  const _Map5({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return _MapCard(
      title: '5 GHz — bonded widths (US, FCC)',
      grid: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BondRow(
            widthLabel: '20',
            blocks: ChannelMapScreen.map5_20,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '40',
            blocks: ChannelMapScreen.map5_40,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '80',
            blocks: ChannelMapScreen.map5_80,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '160',
            blocks: ChannelMapScreen.map5_160,
            mono: mono,
          ),
        ],
      ),
      legend: const [DfsClass.noDfs, DfsClass.dfs, DfsClass.mixed],
      footnote:
          'No DFS = UNII-1 (36–48) and UNII-3 (149–165). DFS required = '
          'UNII-2A/2C. Ch 50 (160 MHz) spans UNII-1 + UNII-2A — any DFS '
          'sub-channel makes the whole bond subject to DFS. Numbers are the '
          'primary (center) channel for each bonded width.',
    );
  }
}

// ── 6 GHz map ─────────────────────────────────────────────────────────────────

class _Map6 extends StatelessWidget {
  const _Map6({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return _MapCard(
      title: '6 GHz — full US band, ch 1–233 (UNII-5 to UNII-8)',
      grid: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BondRow(
            widthLabel: '20',
            blocks: ChannelMapScreen.map6_20,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '40',
            blocks: ChannelMapScreen.map6_40,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '80',
            blocks: ChannelMapScreen.map6_80,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '160',
            blocks: ChannelMapScreen.map6_160,
            mono: mono,
          ),
          _BondRow(
            widthLabel: '320',
            blocks: ChannelMapScreen.map6_320,
            mono: mono,
          ),
        ],
      ),
      legend: const [DfsClass.noDfs, DfsClass.psc],
      footnote:
          'Full US 6 GHz band, 5.925–7.125 GHz: 59 × 20 MHz channels (ch '
          '1–233) across UNII-5/6/7/8 — no DFS, no AFC required indoors (LPI). '
          'PSC = Preferred Scanning Channel — Wi-Fi 6E/7 clients scan these '
          'first. 320 MHz has a primary set (centers 31, 95, 159) and an '
          'overlapping alternative set (centers 63, 127, 191, marked "alt") — a '
          'primary and its alternate are not used at the same time. Numbers are '
          'the primary (center) channel for each bonded width.',
    );
  }
}

// ── Chips and toggle ──────────────────────────────────────────────────────────

/// Small affordance chip — tinted fill + bordered, label always present so it
/// is never color-only (§8.13 rule 2). When `neutral` is set, the chip renders
/// on the §8.1/§8.2 neutral stack (surface2 fill + decorative border + tertiary
/// text) instead of tinting a status hue — used for attribute chips that carry
/// no verdict (§8.15 case-3, e.g. "No DFS").
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.color, this.neutral = false});

  final String label;
  final Color color;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: neutral ? colors.surface2 : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: neutral ? colors.border : color, width: 1),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: neutral ? colors.textTertiary : color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Segmented band toggle (2.4 / 5 / 6 GHz). Mirrors wifi_channels_screen.dart's
/// `_BandToggle` so the two reference screens stay consistent (§8.14: a Toggle
/// is correct for 2–3 short options). Each segment is Expanded so the row never
/// overflows phone width.
class _BandToggle extends StatelessWidget {
  const _BandToggle({required this.value, required this.onChanged});

  final ChanMapBand value;
  final ValueChanged<ChanMapBand> onChanged;

  static const List<(ChanMapBand, String)> _options = [
    (ChanMapBand.ghz24, '2.4 GHz'),
    (ChanMapBand.ghz5, '5 GHz'),
    (ChanMapBand.ghz6, '6 GHz'),
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Row(
        children: _options.map((opt) {
          final bool selected = opt.$1 == value;
          // Each segment flexes to share the row width so the three band chips
          // never overflow a narrow phone surface.
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: opt.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.control),
                onTap: () => onChanged(opt.$1),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AppSpacing.minTouchTarget,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected ? colors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    style: text.labelLarge?.copyWith(
                      color: selected
                          ? colors.onPrimary
                          : colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
