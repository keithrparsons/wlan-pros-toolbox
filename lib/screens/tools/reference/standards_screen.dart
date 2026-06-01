// 802.11 Standards — read-only PHY-layer reference for every major 802.11
// amendment. Ported verbatim from the rf-tools-pwa `standards` tool view
// (data-tool="standards") and its `STANDARDS` const in www/app.js.
//
// Fully offline: the dataset is a bundled compile-time const, not fetched and
// not computed. No network, no OS-data calls — GL-008 network/subprocess rules
// do not apply here (nothing to fabricate; nothing to shell out to).
//
// States (SOP-007 §5):
//  - success → the standards rendered as cards (the default; data is always
//    present because it is a const).
//  - empty   → a band filter that matches nothing; an honest "no match" card,
//    never a fabricated row. (Unreachable with the current band set, but built
//    so a future filter value cannot ship a blank surface.)
//  - loading / error → none. There is no async load and nothing can fail to
//    parse, so a spinner or error card would be theatre. Omitted deliberately.
//
// Pattern: matches port_reference_screen — Scaffold + AppBar (toolbarHeight 64),
// SafeArea(top: false), LayoutBuilder isDesktop @720, ConstrainedBox to
// calculatorMaxWidth, SingleChildScrollView, cards built from app_tokens /
// app_typography. The optional band filter uses AppSelect (§8.14): the band
// dimension is a genuine filter for "which generations reach 6 GHz".

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import '../network/value_row.dart';
import 'reference_row_semantics.dart';

/// One row of the 802.11 PHY-layer comparison. Field names and values mirror
/// the PWA `STANDARDS` const exactly (std / gen / year / bands / rate / mimo /
/// chW / mod).
@immutable
class StandardEntry {
  const StandardEntry({
    required this.std,
    required this.generation,
    required this.year,
    required this.bands,
    required this.maxRate,
    required this.mimo,
    required this.channelWidth,
    required this.modulation,
  });

  /// IEEE designation, e.g. `802.11ax`.
  final String std;

  /// Marketing generation, e.g. `Wi-Fi 6`. The dash `—` for the original
  /// 802.11 (no marketing name).
  final String generation;

  /// Ratification year.
  final int year;

  /// Operating bands in GHz, e.g. `2.4 / 5 / 6`.
  final String bands;

  /// Theoretical max PHY rate, e.g. `9.6 Gbps`.
  final String maxRate;

  /// MIMO / spatial-stream ceiling, e.g. `8×8 MU-MIMO`. The dash `—` where the
  /// amendment predates MIMO.
  final String mimo;

  /// Channel width(s) in MHz, e.g. `20–320`.
  final String channelWidth;

  /// Modulation / access scheme, e.g. `1024-QAM OFDMA`.
  final String modulation;

  /// True when [bands] includes the 6 GHz band (Wi-Fi 6E and Wi-Fi 7).
  bool get hasBand6 => bands.contains('6');

  /// True when [bands] includes the 5 GHz band.
  bool get hasBand5 => bands.contains('5');

  /// True when [bands] includes the 2.4 GHz band.
  bool get hasBand24 => bands.contains('2.4');
}

/// 802.11 Standards reference screen (route `/tools/standards`).
class StandardsScreen extends StatefulWidget {
  const StandardsScreen({super.key});

  /// The 802.11 PHY-layer dataset — ported verbatim from the rf-tools-pwa
  /// `STANDARDS` const (www/app.js). Public + const so tests assert against the
  /// same single source the UI renders. Do not edit values here without
  /// reconciling the PWA source.
  static const List<StandardEntry> standards = <StandardEntry>[
    StandardEntry(
      std: '802.11',
      generation: '—',
      year: 1997,
      bands: '2.4',
      maxRate: '2 Mbps',
      mimo: '—',
      channelWidth: '22',
      modulation: 'DSSS/FHSS',
    ),
    StandardEntry(
      std: '802.11b',
      generation: 'Wi-Fi 1',
      year: 1999,
      bands: '2.4',
      maxRate: '11 Mbps',
      mimo: '—',
      channelWidth: '22',
      modulation: 'DSSS/CCK',
    ),
    StandardEntry(
      std: '802.11a',
      generation: 'Wi-Fi 2',
      year: 1999,
      bands: '5',
      maxRate: '54 Mbps',
      mimo: '—',
      channelWidth: '20',
      modulation: 'OFDM',
    ),
    StandardEntry(
      std: '802.11g',
      generation: 'Wi-Fi 3',
      year: 2003,
      bands: '2.4',
      maxRate: '54 Mbps',
      mimo: '—',
      channelWidth: '20',
      modulation: 'OFDM',
    ),
    StandardEntry(
      std: '802.11n',
      generation: 'Wi-Fi 4',
      year: 2009,
      bands: '2.4 / 5',
      maxRate: '600 Mbps',
      mimo: '4×4 MIMO',
      channelWidth: '20/40',
      modulation: 'OFDM',
    ),
    StandardEntry(
      std: '802.11ac',
      generation: 'Wi-Fi 5',
      year: 2013,
      bands: '5',
      maxRate: '6.9 Gbps',
      mimo: '8×8 MU-MIMO',
      channelWidth: '20–160',
      modulation: '256-QAM OFDM',
    ),
    StandardEntry(
      std: '802.11ax',
      generation: 'Wi-Fi 6',
      year: 2019,
      bands: '2.4 / 5',
      maxRate: '9.6 Gbps',
      mimo: '8×8 MU-MIMO',
      channelWidth: '20–160',
      modulation: '1024-QAM OFDMA',
    ),
    StandardEntry(
      std: '802.11ax',
      generation: 'Wi-Fi 6E',
      year: 2021,
      bands: '2.4 / 5 / 6',
      maxRate: '9.6 Gbps',
      mimo: '8×8 MU-MIMO',
      channelWidth: '20–160',
      modulation: '1024-QAM OFDMA',
    ),
    StandardEntry(
      std: '802.11be',
      generation: 'Wi-Fi 7',
      year: 2024,
      bands: '2.4 / 5 / 6',
      maxRate: '46 Gbps',
      mimo: '16×16 MLO',
      channelWidth: '20–320',
      modulation: '4K-QAM OFDMA',
    ),
  ];

  @override
  State<StandardsScreen> createState() => _StandardsScreenState();
}

/// Band filter options. `all` shows every amendment; the rest narrow to a band.
enum _BandFilter { all, band24, band5, band6 }

class _StandardsScreenState extends State<StandardsScreen> {
  _BandFilter _filter = _BandFilter.all;

  static const List<AppSelectItem<_BandFilter>> _filterItems =
      <AppSelectItem<_BandFilter>>[
        (_BandFilter.all, 'All bands'),
        (_BandFilter.band24, '2.4 GHz'),
        (_BandFilter.band5, '5 GHz'),
        (_BandFilter.band6, '6 GHz'),
      ];

  List<StandardEntry> get _visible {
    switch (_filter) {
      case _BandFilter.all:
        return StandardsScreen.standards;
      case _BandFilter.band24:
        return StandardsScreen.standards
            .where((StandardEntry e) => e.hasBand24)
            .toList();
      case _BandFilter.band5:
        return StandardsScreen.standards
            .where((StandardEntry e) => e.hasBand5)
            .toList();
      case _BandFilter.band6:
        return StandardsScreen.standards
            .where((StandardEntry e) => e.hasBand6)
            .toList();
    }
  }

  void _onFilterChanged(_BandFilter next) {
    setState(() => _filter = next);
    // WCAG 4.1.3 — announce the live result count when the filter changes.
    final int n = _visible.length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0
          ? 'No standards in this band'
          : '$n standard${n == 1 ? '' : 's'} shown',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the full 802.11 amendment table as TSV. Static data,
  /// so always enabled, and it copies the COMPLETE amendment set regardless of
  /// the on-screen band filter (the filter narrows the view, not the
  /// reference). One section: a header row, then one tab-separated row per
  /// amendment. The source `—` placeholders for the original 802.11's
  /// generation/MIMO are kept verbatim.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('802.11 Standards')
      ..writeln(
        <String>[
          'Standard',
          'Wi-Fi gen',
          'Year',
          'Bands (GHz)',
          'Max PHY rate',
          'MIMO',
          'Ch width (MHz)',
          'Modulation',
        ].join(tab),
      );
    for (final StandardEntry e in StandardsScreen.standards) {
      buf.writeln(
        <String>[
          e.std,
          e.generation,
          '${e.year}',
          e.bands,
          e.maxRate,
          e.mimo,
          e.channelWidth,
          e.modulation,
        ].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('802.11 Standards'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        final List<StandardEntry> rows = _visible;
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
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: '80211-standards',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('80211-standards'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _filterCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  if (rows.isEmpty)
                    _emptyCard(context)
                  else
                    ...rows.map(
                      (StandardEntry e) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _StandardCard(entry: e),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Text(
        'PHY-layer comparison of all major 802.11 amendments. Max PHY rate is '
        'the theoretical aggregate ceiling. Real-world throughput is typically '
        '50 to 60 percent of the PHY rate.',
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }

  Widget _filterCard(BuildContext context) {
    return _Card(
      child: LabeledField(
        label: 'Band',
        semanticLabel: 'Filter standards by band',
        field: AppSelect<_BandFilter>(
          value: _filter,
          items: _filterItems,
          onChanged: _onFilterChanged,
          semanticLabel: 'Band filter',
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.search_off, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No match',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No 802.11 standard operates in this band.',
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One amendment card: a header (IEEE designation + Wi-Fi generation badge +
/// year) over the PHY spec rows.
class _StandardCard extends StatelessWidget {
  const _StandardCard({required this.entry});

  final StandardEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceRowSemantics(
      // merge:false — the card holds SelectableText ValueRows; keep them
      // individually navigable/selectable while the card reads as one
      // container labelled by the IEEE designation. (Vera F-02.)
      merge: false,
      label: rowLabel(entry.std, <String?>[
        entry.generation == '—' ? null : entry.generation,
        '${entry.year}',
        'bands ${entry.bands} gigahertz',
        'max rate ${entry.maxRate}',
        'MIMO ${entry.mimo}',
        'channel width ${entry.channelWidth} megahertz',
        'modulation ${entry.modulation}',
      ]),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    entry.std,
                    style: text.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (entry.generation != '—') ...<Widget>[
                  _GenerationBadge(label: entry.generation),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  '${entry.year}',
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Divider(color: AppColors.border, height: 1),
            ValueRow(label: 'Bands (GHz)', value: entry.bands),
            ValueRow(
              label: 'Max PHY rate',
              value: entry.maxRate,
              emphasize: true,
            ),
            ValueRow(label: 'MIMO', value: entry.mimo),
            ValueRow(label: 'Ch width (MHz)', value: entry.channelWidth),
            ValueRow(label: 'Modulation', value: entry.modulation),
          ],
        ),
      ),
    );
  }
}

/// Lime pill carrying the Wi-Fi marketing generation (e.g. "Wi-Fi 6E").
class _GenerationBadge extends StatelessWidget {
  const _GenerationBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Text(
        label,
        style: mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Shared surface-1 card with the standard border, radius, and padding.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
