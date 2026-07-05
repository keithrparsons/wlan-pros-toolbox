// Wi-Fi HaLow (IEEE 802.11ah) — read-only reference (Tier-1, 2026-06-12).
//
// The channel-width plate (a Charta-rendered dark-baked raster comparing HaLow's
// 1-16 MHz channels against a 20 MHz Wi-Fi channel) is embedded at the top via
// the established DarkRasterDiagramCard (always-dark surface in both themes, tap
// to pinch-zoom, GL-003 §8). The screen leads with the REGION-LOCK caveat banner
// (warning tone, §8.13) because frequency and channel width are region-dependent
// and a device certified for one region cannot legally run in another -- the
// load-bearing fact a field tech must carry. Beneath, native tables carry every
// fact: what it is, bands by region, channel widths, the headline numbers, the
// single-stream MCS rate table (headline 86.7 Mbps -- NOT the contested 433),
// capacity, power, PHY/MAC, use cases, vs other IoT radios, and 2026 maturity.
//
// States (SOP-007 §5):
//  - success    → the tables always render (compile-time const data); the plate
//    card appears only when its PNG is bundled (ReferenceImages.isBundled),
//    otherwise it is omitted and the tables still read end-to-end.
//  - loading / empty / error → not reachable; nothing fetched or parsed.
//  - interactive→ the plate's tap-to-zoom + the AppBar §8.16 copy action.
//  - disabled   → copy is always enabled (const content always present).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). No new tokens.
// Glyph note: no em dash in prose; ASCII +/- and hyphen-minus throughout.

import 'package:flutter/material.dart';

import '../../../data/reference_images.dart';
import '../../../data/wifi_halow_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';

/// Stable catalog tool id — backs the route, the help entry, the bundled plate
/// PNG (assets/reference/wifi-halow.png), and the tests.
const String kWifiHalowToolId = 'wifi-halow';

class WifiHalowScreen extends StatelessWidget {
  const WifiHalowScreen({super.key});

  /// The channel-width plate's true aspect ratio (width / height), pinned so the
  /// inline card is the right shape with no measuring and no letterbox gutters.
  static const double _plateAspect = 3840 / 2700;

  /// §8.16 plain-text payload — every section in order, so copying captures
  /// everything on-screen. Always non-null (static data).
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Wi-Fi HaLow (IEEE 802.11ah)')
      ..writeln()
      ..writeln(kHalowOneLiner)
      ..writeln()
      ..writeln('Region lock: $kHalowRegionLock')
      ..writeln(kHalowNotMainstreamBands)
      ..writeln()
      ..writeln('What it is');
    for (final HalowFact f in kHalowWhatItIs) {
      b.writeln('${f.label}\t${f.value}');
    }
    b
      ..writeln()
      ..writeln('Bands by region')
      ..writeln(<String>['Region', 'Band', 'Confidence'].join(tab));
    for (final HalowBand band in kHalowBands) {
      b.writeln(<String>[band.region, band.band, band.confidence].join(tab));
    }
    b
      ..writeln(kHalowBandsNote)
      ..writeln()
      ..writeln('Channel widths')
      ..writeln(<String>['Width', 'Use', 'Region availability'].join(tab));
    for (final HalowChannel c in kHalowChannels) {
      b.writeln(<String>[c.width, c.use, c.regions].join(tab));
    }
    b
      ..writeln(kHalowChannelsNote)
      ..writeln()
      ..writeln('Headline numbers');
    for (final HalowHeadline h in kHalowHeadlines) {
      b.writeln('${h.label}: ${h.value}. ${h.note}');
    }
    b
      ..writeln(kHalowRateHonesty)
      ..writeln()
      ..writeln('Single-stream data rates (Mbps, LGI / SGI)')
      ..writeln(
        <String>[
          'MCS',
          'Modulation',
          '1 MHz',
          '2 MHz',
          '4 MHz',
          '8 MHz',
          '16 MHz',
        ].join(tab),
      );
    for (final HalowMcs m in kHalowMcs) {
      b.writeln(
        <String>[
          'MCS ${m.mcs}',
          m.modulation,
          m.w1,
          m.w2,
          m.w4,
          m.w8,
          m.w16,
        ].join(tab),
      );
    }
    b
      ..writeln()
      ..writeln('Power efficiency');
    for (final HalowFact f in kHalowPower) {
      b.writeln('${f.label}\t${f.value}');
    }
    b
      ..writeln()
      ..writeln('PHY / MAC');
    for (final HalowFact f in kHalowPhy) {
      b.writeln('${f.label}\t${f.value}');
    }
    b
      ..writeln(kHalowPhyNote)
      ..writeln()
      ..writeln('Use cases');
    for (final String u in kHalowUseCases) {
      b.writeln('- $u');
    }
    b
      ..writeln()
      ..writeln('Vs other IoT radios')
      ..writeln(
        <String>['Tech', 'Band', 'Data rate', 'Range', 'IP-native'].join(tab),
      );
    for (final HalowVersus v in kHalowVersus) {
      b.writeln(
        <String>[v.tech, v.band, v.rate, v.range, v.ipNative].join(tab),
      );
    }
    b
      ..writeln(kHalowVersusVerdict)
      ..writeln()
      ..writeln('Maturity (2026)');
    for (final HalowFact f in kHalowMaturity) {
      b.writeln('${f.label}\t${f.value}');
    }
    b.writeln(kHalowMaturityNote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi HaLow'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
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
        final bool hasPlate = ReferenceImages.isBundled(kWifiHalowToolId);
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
                  if (hasPlate) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath: ReferenceImages.pathFor(kWifiHalowToolId),
                      aspectRatio: _plateAspect,
                      semanticLabel:
                          'HaLow channel widths versus a 20 MHz Wi-Fi channel',
                      caption:
                          'HaLow channels are 1 to 16 MHz wide; even the widest '
                          'is narrower than the minimum 20 MHz Wi-Fi channel.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  // Lead with the region-lock caveat: the load-bearing warning.
                  const _RegionLockBanner(),
                  const SizedBox(height: AppSpacing.md),
                  const _OneLinerCard(),
                  const SizedBox(height: AppSpacing.md),
                  _FactsCard(
                    title: 'What it is',
                    facts: kHalowWhatItIs,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _HeadlinesCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _BandsCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _ChannelsCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _McsCard(),
                  const SizedBox(height: AppSpacing.md),
                  _FactsCard(title: 'Power efficiency', facts: kHalowPower),
                  const SizedBox(height: AppSpacing.md),
                  _FactsCard(
                    title: 'PHY / MAC',
                    facts: kHalowPhy,
                    footnote: kHalowPhyNote,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _UseCasesCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _VersusCard(),
                  const SizedBox(height: AppSpacing.md),
                  _FactsCard(
                    title: 'Maturity (2026)',
                    facts: kHalowMaturity,
                    footnote: kHalowMaturityNote,
                  ),
                  ToolHelpFooter(toolId: kWifiHalowToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shared card chrome: a titled surface1 container with an optional footnote.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.footnote});

  final String title;
  final Widget child;
  final String? footnote;

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
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
          if (footnote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The region-lock caveat banner (warning tone, paired with the word).
class _RegionLockBanner extends StatelessWidget {
  const _RegionLockBanner();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.public, size: 16, color: colors.statusWarning),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Region lock',
                  style: text.labelMedium?.copyWith(
                    color: colors.statusWarning,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kHalowRegionLock,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kHalowNotMainstreamBands,
            style: text.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-line "what it is" summary.
class _OneLinerCard extends StatelessWidget {
  const _OneLinerCard();

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
      child: Text(
        kHalowOneLiner,
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

/// A label / value fact list inside the shared card chrome.
class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.title, required this.facts, this.footnote});

  final String title;
  final List<HalowFact> facts;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      title: title,
      footnote: footnote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final HalowFact f in facts)
            Semantics(
              container: true,
              excludeSemantics: true,
              label: '${f.label}: ${f.value}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 132,
                      child: Text(
                        f.label,
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        f.value,
                        style: text.bodySmall?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The headline numbers (range, rate, capacity, power) with the lime accent.
class _HeadlinesCard extends StatelessWidget {
  const _HeadlinesCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _Card(
      title: 'Headline numbers',
      footnote: kHalowRateHonesty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final HalowHeadline h in kHalowHeadlines)
            Semantics(
              container: true,
              excludeSemantics: true,
              label: '${h.label}: ${h.value}. ${h.note}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      h.label,
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      h.value,
                      style: mono.outputMedium.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      h.note,
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bands by region (frequency varies by regulator). High vs Medium confidence
/// shown as a tertiary tag so secondary-source figures are not over-claimed.
class _BandsCard extends StatelessWidget {
  const _BandsCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _Card(
      title: 'Bands by region (set by the local regulator)',
      footnote: kHalowBandsNote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final HalowBand band in kHalowBands)
            Semantics(
              container: true,
              excludeSemantics: true,
              label:
                  '${band.region}: ${band.band}, ${band.confidence} confidence',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 124,
                      child: Text(
                        band.region,
                        style: text.bodySmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        band.band,
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                        ),
                      ),
                    ),
                    if (band.confidence != 'High')
                      Text(
                        band.confidence,
                        style: text.labelMedium?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Channel widths (1-16 MHz) and their per-region availability.
class _ChannelsCard extends StatelessWidget {
  const _ChannelsCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _Card(
      title: 'Channel widths',
      footnote: kHalowChannelsNote,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final HalowChannel c in kHalowChannels)
            Semantics(
              container: true,
              excludeSemantics: true,
              label: '${c.width}: ${c.use}. ${c.regions}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        c.width,
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            c.use,
                            style: text.bodySmall?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            c.regions,
                            style: text.labelMedium?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single-stream MCS rate table. Wide, so it scrolls horizontally with a
/// visible affordance (HorizontalScrollTable) on desktop/web.
class _McsCard extends StatelessWidget {
  const _McsCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle cellStyle = mono.inlineCode.copyWith(
      color: colors.textSecondary,
    );
    return _Card(
      title: 'Single-stream data rates (Mbps, LGI / SGI)',
      child: HorizontalScrollTable(
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 48,
          columnSpacing: AppSpacing.md,
          horizontalMargin: 0,
          dividerThickness: 1,
          headingTextStyle: headStyle,
          columns: const <DataColumn>[
            DataColumn(label: Text('MCS')),
            DataColumn(label: Text('Mod')),
            DataColumn(label: Text('1 MHz')),
            DataColumn(label: Text('2 MHz')),
            DataColumn(label: Text('4 MHz')),
            DataColumn(label: Text('8 MHz')),
            DataColumn(label: Text('16 MHz')),
          ],
          rows: kHalowMcs.map((HalowMcs m) {
            // MCS 9 / 16 MHz / SGI carries the headline 86.7 Mbps -> lime accent.
            final bool isPeak = m.mcs == 9;
            final TextStyle peakStyle = mono.inlineCode.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
            );
            return DataRow(
              cells: <DataCell>[
                DataCell(
                  Text(
                    'MCS ${m.mcs}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    m.modulation,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                DataCell(Text(m.w1, style: cellStyle)),
                DataCell(Text(m.w2, style: cellStyle)),
                DataCell(Text(m.w4, style: cellStyle)),
                DataCell(Text(m.w8, style: cellStyle)),
                DataCell(Text(m.w16, style: isPeak ? peakStyle : cellStyle)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// The use-case bullet list.
class _UseCasesCard extends StatelessWidget {
  const _UseCasesCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      title: 'Use cases',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String u in kHalowUseCases)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '- ',
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                  Expanded(
                    child: Text(
                      u,
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
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

/// HaLow vs other IoT radios. Wide table, horizontally scrollable; the HaLow row
/// takes the lime accent.
class _VersusCard extends StatelessWidget {
  const _VersusCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    return _Card(
      title: 'Vs other IoT radios',
      footnote: kHalowVersusVerdict,
      child: HorizontalScrollTable(
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 56,
          columnSpacing: AppSpacing.md,
          horizontalMargin: 0,
          dividerThickness: 1,
          headingTextStyle: headStyle,
          columns: const <DataColumn>[
            DataColumn(label: Text('Tech')),
            DataColumn(label: Text('Band')),
            DataColumn(label: Text('Data rate')),
            DataColumn(label: Text('Range')),
            DataColumn(label: Text('IP-native')),
          ],
          rows: kHalowVersus.map((HalowVersus v) {
            final Color nameColor =
                v.isHalow ? colors.primary : colors.textPrimary;
            final FontWeight weight =
                v.isHalow ? FontWeight.w700 : FontWeight.w600;
            return DataRow(
              cells: <DataCell>[
                DataCell(
                  Text(
                    v.tech,
                    style: (text.bodySmall ?? const TextStyle()).copyWith(
                      color: nameColor,
                      fontWeight: weight,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    v.band,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    v.rate,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    v.range,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    v.ipNative,
                    style: text.bodySmall?.copyWith(
                      color: v.ipNative == 'Yes'
                          ? colors.primary
                          : colors.textSecondary,
                      fontWeight:
                          v.ipNative == 'Yes' ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
