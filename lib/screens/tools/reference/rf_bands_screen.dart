// RF Bands at a Glance — read-only frequency reference (Tier-1, 2026-06-12).
//
// The log-scale spectrum bar plate (a Charta-rendered dark-baked raster that no
// native table can reproduce) is embedded at the top via the established
// DarkRasterDiagramCard (always-dark surface in both themes, tap to pinch-zoom,
// GL-003 §8). Beneath it, five NATIVE grouped tables carry every fact in text
// (the plate is decorative for screen readers, never the sole carrier), one per
// spectrum neighborhood low -> high, with the Wi-Fi rows given the single lime
// accent (§8.15 case-3). A region-variance list (warning tone, §8.13) closes the
// screen: the rows where "what operates where" genuinely changes by regulator.
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
import '../../../data/rf_bands_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';

/// Stable catalog tool id — backs the route, the help entry, the bundled plate
/// PNG (assets/reference/rf-bands.png), and the tests.
const String kRfBandsToolId = 'rf-bands';

class RfBandsScreen extends StatelessWidget {
  const RfBandsScreen({super.key});

  /// The spectrum-bar plate's true aspect ratio (width / height), pinned so the
  /// inline card is the right shape with no measuring and no letterbox gutters.
  static const double _plateAspect = 5040 / 3360;

  /// §8.16 plain-text payload — every band row and region flag in order, so
  /// copying captures everything on-screen. Always non-null (static data).
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('RF Bands at a Glance (frequency map, not a channel plan)');
    for (final RfBandGroup g in kRfBandGroups) {
      b
        ..writeln()
        ..writeln('${g.title} -- ${g.subtitle}')
        ..writeln(
          <String>['Band', 'Technology', 'Use', 'Note'].join(tab),
        );
      for (final RfBandRow r in g.rows) {
        b.writeln(<String>[r.band, r.tech, r.use, r.note].join(tab));
      }
      b.writeln(g.takeaway);
    }
    b
      ..writeln()
      ..writeln('Region variance (US FCC vs EU ETSI and others)');
    for (final RfRegionFlag f in kRfRegionFlags) {
      b.writeln('${f.topic}: ${f.detail}');
    }
    b
      ..writeln()
      ..writeln(kRfBandsNote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RF Bands'),
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
        final bool hasPlate = ReferenceImages.isBundled(kRfBandsToolId);
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
                      assetPath: ReferenceImages.pathFor(kRfBandsToolId),
                      aspectRatio: _plateAspect,
                      semanticLabel: 'RF spectrum bar, low to high frequency',
                      caption:
                          'Where the common wireless technologies live in the '
                          'spectrum, low to high frequency (log scale). Tap to '
                          'zoom.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  for (final RfBandGroup g in kRfBandGroups) ...<Widget>[
                    _BandGroupCard(group: g),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _RegionFlagsCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _NoteCard(),
                  ToolHelpFooter(toolId: kRfBandsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One spectrum neighborhood: a titled card with the subtitle, its band rows,
/// and the closing takeaway.
class _BandGroupCard extends StatelessWidget {
  const _BandGroupCard({required this.group});

  final RfBandGroup group;

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
            group.title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            group.subtitle,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final RfBandRow r in group.rows) _BandRowTile(row: r),
          const SizedBox(height: AppSpacing.xs),
          Text(
            group.takeaway,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One band row: the frequency as a DM Mono chip, the technology and use as
/// body text, and the note as a tertiary footnote. Wi-Fi rows take the lime
/// accent so the reader's home turf stands out inside each crowded band.
class _BandRowTile extends StatelessWidget {
  const _BandRowTile({required this.row});

  final RfBandRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color freqColor = row.isWiFi ? colors.primary : colors.textAccent;
    final Color techColor = row.isWiFi ? colors.primary : colors.textPrimary;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${row.band}: ${row.tech}. ${row.use}. ${row.note}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 150,
                  child: Text(
                    row.band,
                    style: mono.inlineCode.copyWith(
                      color: freqColor,
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
                        row.tech,
                        style: (text.bodyMedium ?? const TextStyle()).copyWith(
                          color: techColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        row.use,
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 158, top: 1),
              child: Text(
                row.note,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The region-variance list: the rows where "what operates where" genuinely
/// changes by regulator, given the warning tone (§8.13) paired with the word.
class _RegionFlagsCard extends StatelessWidget {
  const _RegionFlagsCard();

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
              Icon(
                Icons.public,
                size: 16,
                color: colors.statusWarning,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Region variance (US FCC vs EU ETSI and others)',
                  style: text.labelMedium?.copyWith(
                    color: colors.statusWarning,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final RfRegionFlag f in kRfRegionFlags)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: RichText(
                text: TextSpan(
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${f.topic}: ',
                      style: text.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: f.detail),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The nominal-allocations framing note.
class _NoteCard extends StatelessWidget {
  const _NoteCard();

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              kRfBandsNote,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
