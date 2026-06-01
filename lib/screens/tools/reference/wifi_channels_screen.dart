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
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// Which band's table is shown. 2.4 / 5 / 6 GHz — three short options, so a
/// segmented toggle, not an AppSelect (GL-003 §8.14).
enum WifiBand { ghz24, ghz5, ghz6 }

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

  /// 6 GHz — the 15 Preferred Scanning Channels (US). Center = (5940 + ch·5)
  /// MHz. Verbatim from PWA PSC6 / CH6.filter(psc).
  static const List<Channel6> channels6 = [
    Channel6(channel: 5, centerGhz: 5.965, psc: true),
    Channel6(channel: 21, centerGhz: 6.045, psc: true),
    Channel6(channel: 37, centerGhz: 6.125, psc: true),
    Channel6(channel: 53, centerGhz: 6.205, psc: true),
    Channel6(channel: 69, centerGhz: 6.285, psc: true),
    Channel6(channel: 85, centerGhz: 6.365, psc: true),
    Channel6(channel: 101, centerGhz: 6.445, psc: true),
    Channel6(channel: 117, centerGhz: 6.525, psc: true),
    Channel6(channel: 133, centerGhz: 6.605, psc: true),
    Channel6(channel: 149, centerGhz: 6.685, psc: true),
    Channel6(channel: 165, centerGhz: 6.765, psc: true),
    Channel6(channel: 181, centerGhz: 6.845, psc: true),
    Channel6(channel: 197, centerGhz: 6.925, psc: true),
    Channel6(channel: 213, centerGhz: 7.005, psc: true),
    Channel6(channel: 229, centerGhz: 7.085, psc: true),
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
            'Band',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
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

  Widget _tableCard(BuildContext context, AppMonoText mono) {
    switch (_band) {
      case WifiBand.ghz24:
        return _Table24(mono: mono);
      case WifiBand.ghz5:
        return _Table5(mono: mono);
      case WifiBand.ghz6:
        return _Table6(mono: mono);
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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

/// Segmented band toggle (2.4 / 5 / 6 GHz). Mirrors the calculators' private
/// `_UnitToggle` idiom (§8.14: a Toggle is correct for 2–3 short options) so
/// this reference screen stays consistent with the rest of the app.
class _BandToggle extends StatelessWidget {
  const _BandToggle({required this.value, required this.onChanged});

  final WifiBand value;
  final ValueChanged<WifiBand> onChanged;

  static const List<(WifiBand, String)> _options = [
    (WifiBand.ghz24, '2.4 GHz'),
    (WifiBand.ghz5, '5 GHz'),
    (WifiBand.ghz6, '6 GHz'),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Row(
        children: _options.map((opt) {
          final bool selected = opt.$1 == value;
          // Each segment flexes to share the row width so the three band
          // chips never overflow a narrow phone surface (the toggle is
          // stretched full-width by the parent Column).
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
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    opt.$2,
                    style: text.labelLarge?.copyWith(
                      color: selected
                          ? AppColors.secondary
                          : AppColors.textSecondary,
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
