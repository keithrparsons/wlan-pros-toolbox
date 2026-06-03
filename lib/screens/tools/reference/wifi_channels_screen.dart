// Wi-Fi Channels — read-only channel/frequency reference, offline.
//
// Ported verbatim from the rf-tools-pwa `channels` tool (www/app.js: CH24,
// CH5, PSC6/CH6) and its three-tab view (index.html #tool-channels: 2.4 / 5 /
// 6 GHz). Data is US (FCC) regulatory unless a row notes otherwise. No inputs,
// no network — a static reference table, so there is no loading / error /
// empty / network-unavailable surface; the dataset is compiled in.
//
// States (SOP-007 §5) for a read-only reference screen:
//  - success    → the selected band's channel rows render in a card.
//  - empty      → not reachable; every band has rows. (No fabricated row.)
//  - loading    → not reachable; data is a compile-time const, not an asset.
//  - error      → not reachable; nothing to parse at runtime.
//  - interactive→ the band toggle (2.4 / 5 / 6 GHz) is the only control.
//
// The dataset is exposed as public static const lists on WifiChannelsScreen so
// it is unit-testable without pumping the widget.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// Which band's table is shown. 2.4 / 5 / 6 GHz + sub-1 GHz HaLow — FOUR
/// options, so an `AppSelect`, not a segmented toggle (GL-003 §8.14: a Toggle
/// is for 2–3 short options; 4+ uses the Select).
enum WifiBand { ghz24, ghz5, ghz6, halow }

/// One 2.4 GHz channel row. US table is ch 1–11; 12–14 carry their regulatory
/// domain (EU adds 12–13, JP adds 14) per the PWA's own band footnote.
class Channel24 {
  const Channel24({
    required this.channel,
    required this.centerGhz,
    required this.rangeMhzLow,
    required this.rangeMhzHigh,
    required this.nonOverlap,
    required this.regulatory,
  });

  final int channel;
  final double centerGhz;
  final int rangeMhzLow;
  final int rangeMhzHigh;
  final bool nonOverlap;

  /// Regulatory note for non-US channels ('US' for 1–11, 'EU' for 12–13,
  /// 'JP' for 14). Surfaced as a chip so the table never implies 12–14 are
  /// usable in the US.
  final String regulatory;
}

/// One 5 GHz channel row. UNII sub-band + DFS flag, US (FCC).
class Channel5 {
  const Channel5({
    required this.channel,
    required this.centerGhz,
    required this.band,
    required this.dfs,
  });

  final int channel;
  final double centerGhz;

  /// UNII sub-band label: UNII-1 / UNII-2A / UNII-2C / UNII-3.
  final String band;

  /// Dynamic Frequency Selection required (radar avoidance).
  final bool dfs;
}

/// One 6 GHz channel row. The table shows the 15 Preferred Scanning Channels;
/// the full band is 59 × 20 MHz (ch 1–233), noted in the footnote.
class Channel6 {
  const Channel6({
    required this.channel,
    required this.centerGhz,
    required this.psc,
  });

  final int channel;
  final double centerGhz;

  /// Preferred Scanning Channel — clients scan these first.
  final bool psc;
}

/// One US (902-928 MHz) Wi-Fi HaLow 1 MHz channel row. Center frequency is
/// derived from the IEEE 802.11ah / List-of-WLAN-channels formula
/// center (MHz) = 902.5 + 0.5 x (channel - 1); the 1 MHz channels are the odd
/// numbers 1..51. HaLow has NO global numbering — this is the US reference
/// scheme (the only one verified at the per-channel level; other regions show
/// ranges only).
class ChannelHalow {
  const ChannelHalow({required this.channel, required this.centerMhz});

  final int channel;

  /// Center frequency in MHz (not GHz — sub-1 GHz reads more naturally in MHz).
  final double centerMhz;
}

/// One Wi-Fi HaLow channel-width block in the US scheme: how many channels of a
/// given width exist and how they are numbered.
class HalowWidthBlock {
  const HalowWidthBlock({
    required this.widthMhz,
    required this.count,
    required this.numbering,
  });

  /// Channel width in MHz (1 / 2 / 4 / 8 / 16).
  final int widthMhz;

  /// Number of channels of this width in the US 902-928 MHz band.
  final int count;

  /// How the channels of this width are numbered, e.g. "1, 3, 5 ... 51".
  final String numbering;
}

/// One Wi-Fi HaLow regional operating range. HaLow's legal band, channel
/// numbering, and channel count are all region-dependent; only the operating
/// range is shown as the headline fact (counts are MEDIUM/LOW confidence per
/// the research brief and are labelled region-dependent).
class HalowRegion {
  const HalowRegion({
    required this.region,
    required this.rangeMhz,
    required this.note,
  });

  final String region;

  /// Operating range in MHz, e.g. "902-928".
  final String rangeMhz;

  /// Short region-dependent caveat for the count.
  final String note;
}

class WifiChannelsScreen extends StatefulWidget {
  const WifiChannelsScreen({super.key});

  // ── Dataset (public, const, unit-testable) ────────────────────────────────

  /// 2.4 GHz — ch 1–11 (US) at 2412 MHz + (ch-1)·5 MHz, ±11 MHz of occupied
  /// width; 1/6/11 are the only non-overlapping 20 MHz channels. Channels
  /// 12–14 added with their regulatory domain (EU 12–13, JP 14 at 2484 MHz —
  /// the special 12 MHz step above ch 13). Matches PWA CH24 plus its band
  /// footnote "Ch 1–11 (US) · Ch 1–13 (EU) · Ch 1–14 (JP)".
  static const List<Channel24> channels24 = [
    Channel24(
      channel: 1,
      centerGhz: 2.412,
      rangeMhzLow: 2401,
      rangeMhzHigh: 2423,
      nonOverlap: true,
      regulatory: 'US',
    ),
    Channel24(
      channel: 2,
      centerGhz: 2.417,
      rangeMhzLow: 2406,
      rangeMhzHigh: 2428,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 3,
      centerGhz: 2.422,
      rangeMhzLow: 2411,
      rangeMhzHigh: 2433,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 4,
      centerGhz: 2.427,
      rangeMhzLow: 2416,
      rangeMhzHigh: 2438,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 5,
      centerGhz: 2.432,
      rangeMhzLow: 2421,
      rangeMhzHigh: 2443,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 6,
      centerGhz: 2.437,
      rangeMhzLow: 2426,
      rangeMhzHigh: 2448,
      nonOverlap: true,
      regulatory: 'US',
    ),
    Channel24(
      channel: 7,
      centerGhz: 2.442,
      rangeMhzLow: 2431,
      rangeMhzHigh: 2453,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 8,
      centerGhz: 2.447,
      rangeMhzLow: 2436,
      rangeMhzHigh: 2458,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 9,
      centerGhz: 2.452,
      rangeMhzLow: 2441,
      rangeMhzHigh: 2463,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 10,
      centerGhz: 2.457,
      rangeMhzLow: 2446,
      rangeMhzHigh: 2468,
      nonOverlap: false,
      regulatory: 'US',
    ),
    Channel24(
      channel: 11,
      centerGhz: 2.462,
      rangeMhzLow: 2451,
      rangeMhzHigh: 2473,
      nonOverlap: true,
      regulatory: 'US',
    ),
    Channel24(
      channel: 12,
      centerGhz: 2.467,
      rangeMhzLow: 2456,
      rangeMhzHigh: 2478,
      nonOverlap: false,
      regulatory: 'EU',
    ),
    Channel24(
      channel: 13,
      centerGhz: 2.472,
      rangeMhzLow: 2461,
      rangeMhzHigh: 2483,
      nonOverlap: false,
      regulatory: 'EU',
    ),
    Channel24(
      channel: 14,
      centerGhz: 2.484,
      rangeMhzLow: 2473,
      rangeMhzHigh: 2495,
      nonOverlap: false,
      regulatory: 'JP',
    ),
  ];

  /// 5 GHz — US (FCC). UNII-1 / 2A / 2C / 3, 20 MHz centers, DFS per sub-band.
  /// Verbatim from PWA CH5.
  static const List<Channel5> channels5 = [
    Channel5(channel: 36, centerGhz: 5.180, band: 'UNII-1', dfs: false),
    Channel5(channel: 40, centerGhz: 5.200, band: 'UNII-1', dfs: false),
    Channel5(channel: 44, centerGhz: 5.220, band: 'UNII-1', dfs: false),
    Channel5(channel: 48, centerGhz: 5.240, band: 'UNII-1', dfs: false),
    Channel5(channel: 52, centerGhz: 5.260, band: 'UNII-2A', dfs: true),
    Channel5(channel: 56, centerGhz: 5.280, band: 'UNII-2A', dfs: true),
    Channel5(channel: 60, centerGhz: 5.300, band: 'UNII-2A', dfs: true),
    Channel5(channel: 64, centerGhz: 5.320, band: 'UNII-2A', dfs: true),
    Channel5(channel: 100, centerGhz: 5.500, band: 'UNII-2C', dfs: true),
    Channel5(channel: 104, centerGhz: 5.520, band: 'UNII-2C', dfs: true),
    Channel5(channel: 108, centerGhz: 5.540, band: 'UNII-2C', dfs: true),
    Channel5(channel: 112, centerGhz: 5.560, band: 'UNII-2C', dfs: true),
    Channel5(channel: 116, centerGhz: 5.580, band: 'UNII-2C', dfs: true),
    Channel5(channel: 120, centerGhz: 5.600, band: 'UNII-2C', dfs: true),
    Channel5(channel: 124, centerGhz: 5.620, band: 'UNII-2C', dfs: true),
    Channel5(channel: 128, centerGhz: 5.640, band: 'UNII-2C', dfs: true),
    Channel5(channel: 132, centerGhz: 5.660, band: 'UNII-2C', dfs: true),
    Channel5(channel: 136, centerGhz: 5.680, band: 'UNII-2C', dfs: true),
    Channel5(channel: 140, centerGhz: 5.700, band: 'UNII-2C', dfs: true),
    Channel5(channel: 144, centerGhz: 5.720, band: 'UNII-2C', dfs: true),
    Channel5(channel: 149, centerGhz: 5.745, band: 'UNII-3', dfs: false),
    Channel5(channel: 153, centerGhz: 5.765, band: 'UNII-3', dfs: false),
    Channel5(channel: 157, centerGhz: 5.785, band: 'UNII-3', dfs: false),
    Channel5(channel: 161, centerGhz: 5.805, band: 'UNII-3', dfs: false),
    Channel5(channel: 165, centerGhz: 5.825, band: 'UNII-3', dfs: false),
  ];

  /// 6 GHz — the 15 Preferred Scanning Channels (US). Center = (5950 + ch·5)
  /// MHz, per IEEE 802.11ax / List of WLAN channels (channel 1 = 5955 MHz).
  static const List<Channel6> channels6 = [
    Channel6(channel: 5, centerGhz: 5.975, psc: true),
    Channel6(channel: 21, centerGhz: 6.055, psc: true),
    Channel6(channel: 37, centerGhz: 6.135, psc: true),
    Channel6(channel: 53, centerGhz: 6.215, psc: true),
    Channel6(channel: 69, centerGhz: 6.295, psc: true),
    Channel6(channel: 85, centerGhz: 6.375, psc: true),
    Channel6(channel: 101, centerGhz: 6.455, psc: true),
    Channel6(channel: 117, centerGhz: 6.535, psc: true),
    Channel6(channel: 133, centerGhz: 6.615, psc: true),
    Channel6(channel: 149, centerGhz: 6.695, psc: true),
    Channel6(channel: 165, centerGhz: 6.775, psc: true),
    Channel6(channel: 181, centerGhz: 6.855, psc: true),
    Channel6(channel: 197, centerGhz: 6.935, psc: true),
    Channel6(channel: 213, centerGhz: 7.015, psc: true),
    Channel6(channel: 229, centerGhz: 7.095, psc: true),
  ];

  /// Wi-Fi HaLow (802.11ah) — US 902-928 MHz 1 MHz channels. Odd channel
  /// numbers 1..51; center = 902.5 + 0.5 x (channel - 1) MHz (each successive
  /// odd channel is +1.0 MHz). Verified against IEEE 802.11ah and the Wikipedia
  /// List-of-WLAN-channels 802.11ah table; ch 51 = 927.5 MHz (a faulty
  /// 930.5 MHz source extraction was rejected by the band-edge check — see the
  /// research brief).
  static const List<ChannelHalow> halowUs1Mhz = [
    ChannelHalow(channel: 1, centerMhz: 902.5),
    ChannelHalow(channel: 3, centerMhz: 903.5),
    ChannelHalow(channel: 5, centerMhz: 904.5),
    ChannelHalow(channel: 7, centerMhz: 905.5),
    ChannelHalow(channel: 9, centerMhz: 906.5),
    ChannelHalow(channel: 11, centerMhz: 907.5),
    ChannelHalow(channel: 13, centerMhz: 908.5),
    ChannelHalow(channel: 15, centerMhz: 909.5),
    ChannelHalow(channel: 17, centerMhz: 910.5),
    ChannelHalow(channel: 19, centerMhz: 911.5),
    ChannelHalow(channel: 21, centerMhz: 912.5),
    ChannelHalow(channel: 23, centerMhz: 913.5),
    ChannelHalow(channel: 25, centerMhz: 914.5),
    ChannelHalow(channel: 27, centerMhz: 915.5),
    ChannelHalow(channel: 29, centerMhz: 916.5),
    ChannelHalow(channel: 31, centerMhz: 917.5),
    ChannelHalow(channel: 33, centerMhz: 918.5),
    ChannelHalow(channel: 35, centerMhz: 919.5),
    ChannelHalow(channel: 37, centerMhz: 920.5),
    ChannelHalow(channel: 39, centerMhz: 921.5),
    ChannelHalow(channel: 41, centerMhz: 922.5),
    ChannelHalow(channel: 43, centerMhz: 923.5),
    ChannelHalow(channel: 45, centerMhz: 924.5),
    ChannelHalow(channel: 47, centerMhz: 925.5),
    ChannelHalow(channel: 49, centerMhz: 926.5),
    ChannelHalow(channel: 51, centerMhz: 927.5),
  ];

  /// Wi-Fi HaLow US channel-width blocks (902-928 MHz). 1 and 2 MHz are
  /// mandatory; 1 MHz is the base unit, wider channels bond and take the centre
  /// number of their block. Verified against the brief (Wikipedia 802.11ah +
  /// everythingRF).
  static const List<HalowWidthBlock> halowUsWidths = [
    HalowWidthBlock(
      widthMhz: 1,
      count: 26,
      numbering: '1, 3, 5 ... 51 (odd)',
    ),
    HalowWidthBlock(
      widthMhz: 2,
      count: 13,
      numbering: '2, 6, 10 ... 50',
    ),
    HalowWidthBlock(
      widthMhz: 4,
      count: 6,
      numbering: '4, 12, 20, 28, 36, 44',
    ),
    HalowWidthBlock(
      widthMhz: 8,
      count: 3,
      numbering: '8, 24, 40',
    ),
    HalowWidthBlock(
      widthMhz: 16,
      count: 1,
      numbering: '16',
    ),
  ];

  /// Wi-Fi HaLow operating ranges by region. Range is the headline fact; the
  /// channel count and numbering are region-dependent and (outside the US)
  /// MEDIUM/LOW confidence, so they are NOT presented as hard numbers. China is
  /// UNCERTAIN (conflicting band reports) — confirm with CMIIT. US is the only
  /// fully verified scheme (shown in full in the tables above).
  static const List<HalowRegion> halowRegions = [
    HalowRegion(
      region: 'United States',
      rangeMhz: '902-928',
      note: '26 x 1 MHz channels (full scheme above)',
    ),
    HalowRegion(
      region: 'Europe (EU)',
      rangeMhz: '863-868.6',
      note: 'Region-dependent; duty-cycle limited',
    ),
    HalowRegion(
      region: 'Japan',
      rangeMhz: '916.5-927.5',
      note: 'Region-dependent; grid shifted 0.5 MHz',
    ),
    HalowRegion(
      region: 'South Korea',
      rangeMhz: '917.5-923.5',
      note: 'Region-dependent',
    ),
    HalowRegion(
      region: 'Australia / NZ',
      rangeMhz: '915-928',
      note: 'Region-dependent',
    ),
    HalowRegion(
      region: 'Singapore',
      rangeMhz: '866-869 and 920-925',
      note: 'Two sub-bands; region-dependent',
    ),
    HalowRegion(
      region: 'India',
      rangeMhz: '865-867',
      note: 'Region-dependent; narrow allocation',
    ),
    HalowRegion(
      region: 'China',
      rangeMhz: 'varies (reported 755-787)',
      note: 'UNCERTAIN — confirm with CMIIT',
    ),
  ];

  @override
  State<WifiChannelsScreen> createState() => _WifiChannelsScreenState();
}

class _WifiChannelsScreenState extends State<WifiChannelsScreen> {
  WifiBand _band = WifiBand.ghz24;

  void _onBandChanged(WifiBand next) {
    if (next == _band) return;
    setState(() => _band = next);
    // WCAG 4.1.3 — announce which band's table is now shown.
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${_bandLabel(next)} channels',
      TextDirection.ltr,
    );
  }

  static String _bandLabel(WifiBand b) {
    switch (b) {
      case WifiBand.ghz24:
        return '2.4 GHz';
      case WifiBand.ghz5:
        return '5 GHz';
      case WifiBand.ghz6:
        return '6 GHz';
      case WifiBand.halow:
        return 'HaLow';
    }
  }

  /// §8.16 copy payload — all three band tables as TSV. Static data, so always
  /// enabled, and it copies EVERY band (not just the selected one) so the
  /// clipboard carries the complete channel reference. Each band is its own
  /// section with its own column shape: 2.4 GHz (channel + range + note),
  /// 5 GHz (channel + UNII sub-band + DFS), 6 GHz (channel + PSC). The on-screen
  /// chips (non-overlap / regulatory domain / DFS / PSC) are carried as worded
  /// cells so the meaning survives the copy.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()..writeln('Wi-Fi Channels');

    buf
      ..writeln()
      ..writeln('2.4 GHz (${WifiChannelsScreen.channels24.length} channels)')
      ..writeln(<String>['Ch', 'Center GHz', 'Range MHz', 'Note'].join(tab));
    for (final Channel24 c in WifiChannelsScreen.channels24) {
      final String note = c.nonOverlap
          ? 'Non-overlapping'
          : (c.regulatory != 'US' ? '${c.regulatory} only' : '');
      buf.writeln(
        <String>[
          '${c.channel}',
          c.centerGhz.toStringAsFixed(3),
          '${c.rangeMhzLow}-${c.rangeMhzHigh}',
          note,
        ].join(tab),
      );
    }

    buf
      ..writeln()
      ..writeln('5 GHz (${WifiChannelsScreen.channels5.length} channels, US)')
      ..writeln(<String>['Ch', 'GHz', 'Band', 'DFS'].join(tab));
    for (final Channel5 c in WifiChannelsScreen.channels5) {
      buf.writeln(
        <String>[
          '${c.channel}',
          c.centerGhz.toStringAsFixed(3),
          c.band,
          c.dfs ? 'DFS required' : 'No DFS',
        ].join(tab),
      );
    }

    buf
      ..writeln()
      ..writeln('6 GHz (${WifiChannelsScreen.channels6.length} PSC channels)')
      ..writeln(<String>['Ch', 'GHz', 'Type'].join(tab));
    for (final Channel6 c in WifiChannelsScreen.channels6) {
      buf.writeln(
        <String>[
          '${c.channel}',
          c.centerGhz.toStringAsFixed(3),
          c.psc ? 'PSC' : '',
        ].join(tab),
      );
    }

    // Wi-Fi HaLow (802.11ah, sub-1 GHz) — three sections: US 1 MHz channels,
    // US width blocks, and per-region operating ranges. No global numbering, so
    // the copy carries the same region-dependent framing the screen shows.
    buf
      ..writeln()
      ..writeln('Wi-Fi HaLow / 802.11ah (sub-1 GHz, US 902-928 MHz)')
      ..writeln(
        <String>[
          'Ch (1 MHz)',
          'Center MHz',
        ].join(tab),
      );
    for (final ChannelHalow c in WifiChannelsScreen.halowUs1Mhz) {
      buf.writeln(
        <String>['${c.channel}', c.centerMhz.toStringAsFixed(1)].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('HaLow US channel widths')
      ..writeln(<String>['Width MHz', 'Count', 'Numbering'].join(tab));
    for (final HalowWidthBlock w in WifiChannelsScreen.halowUsWidths) {
      buf.writeln(
        <String>['${w.widthMhz}', '${w.count}', w.numbering].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('HaLow operating ranges by region (counts region-dependent)')
      ..writeln(<String>['Region', 'Range MHz', 'Note'].join(tab));
    for (final HalowRegion r in WifiChannelsScreen.halowRegions) {
      buf.writeln(<String>[r.region, r.rangeMhz, r.note].join(tab));
    }

    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Channels'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
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
                    toolId: 'wifi-channels',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('wifi-channels'))
                    const SizedBox(height: AppSpacing.md),
                  _bandCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _tableCard(context, mono),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bandCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      // 2.4 / 5 / 6 GHz + HaLow — FOUR options, so an AppSelect, not a
      // segmented toggle (§8.14: Toggle is 2–3 short options only; 4+ → Select).
      // The HaLow addition pushed this past the 3-option Toggle ceiling, where
      // the fourth segment wrapped and "HaLow" broke mid-word at 320px.
      child: LabeledField(
        label: 'Band',
        field: AppSelect<WifiBand>(
          value: _band,
          semanticLabel: 'Band',
          items: WifiBand.values
              .map((WifiBand b) => (b, _bandLabel(b)))
              .toList(),
          onChanged: _onBandChanged,
        ),
      ),
    );
  }

  Widget _tableCard(BuildContext context, AppMonoText mono) {
    switch (_band) {
      case WifiBand.ghz24:
        return _Table24(mono: mono);
      case WifiBand.ghz5:
        return _Table5(mono: mono);
      case WifiBand.ghz6:
        return _Table6(mono: mono);
      case WifiBand.halow:
        return _TableHalow(mono: mono);
    }
  }
}

/// Shared card chrome for a band table: title, optional column header row,
/// data rows, optional footnote.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The grid (header + rows) sizes to its own intrinsic content width
          // and scrolls horizontally when that exceeds the card's content
          // width. Children of a horizontal SingleChildScrollView get
          // unbounded width, so IntrinsicWidth lets every Row shrink-wrap its
          // fixed-width cells while sharing one common width — columns align
          // and nothing is pinned to a guessed (too-small) value that would
          // overflow. Title and footnote stay full-width and wrap.
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const Divider(color: AppColors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, mono-caption styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// A small affordance chip — tinted fill + bordered, label always present so it
/// is never color-only (§8.13). When `neutral` is set the chip renders on the
/// §8.1/§8.2 neutral stack (surface2 fill + decorative border + tertiary text)
/// instead of tinting a status hue — used for category chips that carry no
/// verdict (§8.15 case-3, e.g. the EU/JP regulatory-domain chip).
class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.color, this.neutral = false});

  final String label;
  final Color color;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: neutral ? AppColors.surface2 : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: neutral ? AppColors.border : color, width: 1),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: neutral ? AppColors.textTertiary : color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Table24 extends StatelessWidget {
  const _Table24({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _TableCard(
      title: '2.4 GHz — ${WifiChannelsScreen.channels24.length} channels',
      header: const Row(
        children: [
          _HeaderCell('Ch', width: 40),
          _HeaderCell('Center', width: 64),
          _HeaderCell('Range MHz', width: 96),
          _HeaderCell('Note', width: 120),
        ],
      ),
      footnote:
          'Center is the GHz carrier; range is the ±11 MHz of occupied 20 MHz '
          'width. Only 1, 6, 11 are non-overlapping in the US. Ch 12–13 are EU, '
          'ch 14 is JP only.',
      rows: WifiChannelsScreen.channels24.map((c) {
        return ReferenceRowSemantics(
          label: rowLabel('Channel ${c.channel}', <String?>[
            'center ${c.centerGhz.toStringAsFixed(3)} gigahertz',
            'range ${c.rangeMhzLow} to ${c.rangeMhzHigh} megahertz',
            c.nonOverlap
                ? 'non-overlapping'
                : (c.regulatory != 'US' ? '${c.regulatory} only' : null),
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${c.channel}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    c.centerGhz.toStringAsFixed(3),
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '${c.rangeMhzLow}-${c.rangeMhzHigh}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: c.nonOverlap
                        ? const _Chip('Non-overlap', color: AppColors.primary)
                        : (c.regulatory != 'US'
                              // §8.15 R-02: EU/JP is a regulatory-domain *category*,
                              // not a caution verdict — no status hue. Neutral chip.
                              ? _Chip(
                                  c.regulatory,
                                  color: AppColors.textTertiary,
                                  neutral: true,
                                )
                              : Text('', style: text.labelSmall)),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Table5 extends StatelessWidget {
  const _Table5({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    String lastBand = '';
    final List<Widget> rows = [];
    for (final c in WifiChannelsScreen.channels5) {
      // PWA draws a 2px rule at each UNII sub-band boundary; mirror with a
      // thin divider above the first row of a new band.
      if (c.band != lastBand && lastBand.isNotEmpty) {
        rows.add(const Divider(color: AppColors.border, height: AppSpacing.sm));
      }
      lastBand = c.band;
      rows.add(_row5(c));
    }
    return _TableCard(
      title: '5 GHz — ${WifiChannelsScreen.channels5.length} channels (US)',
      header: const Row(
        children: [
          _HeaderCell('Ch', width: 48),
          _HeaderCell('GHz', width: 72),
          _HeaderCell('Band', width: 88),
          _HeaderCell('DFS', width: 56),
        ],
      ),
      footnote:
          'DFS channels require radar detection. UNII-2A/2C require DFS in the '
          'US. Verify UNII-4 (ch 169–177) local rules before use.',
      rows: rows,
    );
  }

  Widget _row5(Channel5 c) {
    return ReferenceRowSemantics(
      label: rowLabel('Channel ${c.channel}', <String?>[
        '${c.centerGhz.toStringAsFixed(3)} gigahertz',
        'band ${c.band}',
        c.dfs ? 'DFS required' : null,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              child: Text(
                '${c.channel}',
                style: mono.inlineCode.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                c.centerGhz.toStringAsFixed(3),
                style: mono.inlineCode.copyWith(color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Chip(c.band, color: AppColors.statusInfo),
              ),
            ),
            SizedBox(
              width: 56,
              child: c.dfs
                  ? const _Chip('DFS', color: AppColors.statusWarning)
                  : Builder(
                      builder: (context) => Text(
                        '—',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Table6 extends StatelessWidget {
  const _Table6({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return _TableCard(
      title: '6 GHz — ${WifiChannelsScreen.channels6.length} PSC channels',
      header: const Row(
        children: [
          _HeaderCell('Ch', width: 56),
          _HeaderCell('GHz', width: 88),
          _HeaderCell('Type', width: 88),
        ],
      ),
      footnote:
          'Showing 15 Preferred Scanning Channels (PSC). Full band: 59 × 20 MHz '
          'channels (ch 1–233). Indoor/LPI: no AFC required. Outdoor/Standard '
          'Power: AFC authorization required. Wi-Fi 7 supports 320 MHz channels '
          'in 6 GHz.',
      rows: WifiChannelsScreen.channels6.map((c) {
        return ReferenceRowSemantics(
          label: rowLabel('Channel ${c.channel}', <String?>[
            '${c.centerGhz.toStringAsFixed(3)} gigahertz',
            'Preferred Scanning Channel',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    '${c.channel}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    c.centerGhz.toStringAsFixed(3),
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 88,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _Chip('PSC', color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Wi-Fi HaLow (802.11ah, sub-1 GHz) tables. Three stacked cards: the US 1 MHz
/// channel→frequency list (the only per-channel-verified scheme), the US
/// channel-width blocks (1/2/4/8/16 MHz numbering), and the per-region operating
/// ranges with region-dependent counts. HaLow has no global numbering, so the
/// US scheme is the reference and other regions show ranges only.
class _TableHalow extends StatelessWidget {
  const _TableHalow({required this.mono});

  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _usChannelsCard(context),
        const SizedBox(height: AppSpacing.sm),
        _widthsCard(context),
        const SizedBox(height: AppSpacing.sm),
        _regionsCard(context),
      ],
    );
  }

  Widget _usChannelsCard(BuildContext context) {
    return _TableCard(
      title: 'HaLow — US 902-928 MHz, 26 × 1 MHz channels',
      header: const Row(
        children: [
          _HeaderCell('Ch', width: 56),
          _HeaderCell('Center MHz', width: 96),
        ],
      ),
      footnote:
          'Wi-Fi HaLow (802.11ah), sub-1 GHz IoT. Center = 902.5 + 0.5 × '
          '(ch − 1) MHz. 1 MHz channels are odd-numbered 1–51; 1 and 2 MHz '
          'widths are mandatory. US numbering shown — HaLow has no global '
          'channel scheme.',
      rows: WifiChannelsScreen.halowUs1Mhz.map((ChannelHalow c) {
        return ReferenceRowSemantics(
          label: rowLabel('Channel ${c.channel}', <String?>[
            'center ${c.centerMhz.toStringAsFixed(1)} megahertz',
            '1 megahertz width',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    '${c.channel}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    c.centerMhz.toStringAsFixed(1),
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _widthsCard(BuildContext context) {
    return _TableCard(
      title: 'HaLow — US channel widths',
      header: const Row(
        children: [
          _HeaderCell('Width', width: 64),
          _HeaderCell('Count', width: 56),
          _HeaderCell('Numbering', width: 168),
        ],
      ),
      footnote:
          'Wider channels bond 1 MHz units and take the center number of the '
          'block. Counts are the US 902-928 MHz scheme.',
      rows: WifiChannelsScreen.halowUsWidths.map((HalowWidthBlock w) {
        return ReferenceRowSemantics(
          label: rowLabel('${w.widthMhz} megahertz width', <String?>[
            '${w.count} channels',
            'numbered ${w.numbering}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    '${w.widthMhz} MHz',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${w.count}',
                    style: mono.inlineCode.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    w.numbering,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _regionsCard(BuildContext context) {
    return _TableCard(
      title: 'HaLow — operating ranges by region',
      header: const Row(
        children: [
          _HeaderCell('Region', width: 128),
          _HeaderCell('Range MHz', width: 144),
          _HeaderCell('Note', width: 220),
        ],
      ),
      footnote:
          'Channel numbering and count are region-dependent and subject to the '
          'local regulator; only the US scheme is verified per-channel. China '
          'is uncertain — confirm with CMIIT.',
      rows: WifiChannelsScreen.halowRegions.map((HalowRegion r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.region, <String?>[
            'range ${r.rangeMhz} megahertz',
            r.note,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 128,
                  child: Builder(
                    builder: (context) => Text(
                      r.region,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 144,
                  child: Text(
                    r.rangeMhz,
                    style: mono.inlineCode.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: Builder(
                    builder: (context) => Text(
                      r.note,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

