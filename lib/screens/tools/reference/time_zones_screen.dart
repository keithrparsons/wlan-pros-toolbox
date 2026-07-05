// Time Zones — read-only UTC reference (Tier-1, Pass 2b 2026-06-12; maps
// rebuilt in the integration batch 2026-06-12).
//
// Two map plates (schematic UTC-offset orientation maps) are the VISUAL the
// staged DATA could not reproduce as text, so they are embedded at the top via
// the established DarkRasterDiagramCard (always-dark surface in both themes, tap
// to pinch-zoom; the plates are dark-baked, GL-003 §8):
//   1. The brand-rebuilt WORLD time-zones map (assets/reference/time-zones-
//      world.png), which replaces the old crude "blobs" world map.
//   2. The new US time-zones map (assets/reference/time-zones-us.png).
// Beneath them, two NATIVE tables carry every fact in text (the maps are
// decorative for screen readers, never the sole carrier of meaning):
//   A. World UTC offset rail (anchor cities per one-hour band).
//   B. United States time zones (standard / daylight abbreviations + notes).
//
// All offsets are STANDARD TIME; the DST framing note is carried on-screen.
//
// States (SOP-007 §5):
//  - success    → the tables always render (compile-time const data); the map
//    card appears only when its PNG is bundled (ReferenceImages.isBundled),
//    otherwise it is omitted and the tables still read end-to-end.
//  - loading / empty / error → not reachable; nothing fetched or parsed.
//  - interactive→ the map's tap-to-zoom + the AppBar §8.16 copy action.
//  - disabled   → copy is always enabled (const content always present).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). No new tokens.
// Glyph note: no em dash in prose; offsets use ASCII +/-.

import 'package:flutter/material.dart';

import '../../../data/reference_images.dart';
import '../../../data/time_zones_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
/// (NEVER renamed — backs the route, catalog entry, and help id.)
const String kTimeZonesToolId = 'time-zone-maps';

/// Resolver key for the brand-rebuilt WORLD time-zones map plate
/// (assets/reference/time-zones-world.png). Separate from [kTimeZonesToolId] so
/// the catalog id stays stable while the map assets are addressed independently.
const String kTimeZonesWorldMapId = 'time-zones-world';

/// Resolver key for the new US time-zones map plate
/// (assets/reference/time-zones-us.png).
const String kTimeZonesUsMapId = 'time-zones-us';

class TimeZonesScreen extends StatelessWidget {
  const TimeZonesScreen({super.key});

  /// The world-map plate's true aspect ratio (width / height), pinned so the
  /// inline card is the right shape with no measuring and no letterbox gutters.
  static const double _worldMapAspect = 5367 / 2910;

  /// The US-map plate's true aspect ratio (width / height).
  static const double _usMapAspect = 3714 / 2868;

  /// §8.16 plain-text payload — the map's facts live in these tables, so copying
  /// them captures everything on-screen. Always non-null (static data).
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Time Zones (standard time)')
      ..writeln()
      ..writeln('World UTC offset rail')
      ..writeln(<String>['Offset', 'Anchor cities'].join(tab));
    for (final UtcOffset o in kUtcOffsets) {
      b.writeln(<String>[o.offset, o.cities].join(tab));
    }
    b
      ..writeln(kUtcOffsetsNote)
      ..writeln()
      ..writeln('United States time zones')
      ..writeln(
        <String>[
          'Zone',
          'Abbr',
          'Offset (STD)',
          'Daylight saving',
          'Cities',
        ].join(tab),
      );
    for (final UsTimeZone z in kUsTimeZones) {
      b.writeln(
        <String>[z.zone, z.abbr, z.offset, z.daylight, z.cities].join(tab),
      );
    }
    b.writeln(kTimeZonesDstNote);
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Zones'),
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
        final bool hasWorldMap =
            ReferenceImages.isBundled(kTimeZonesWorldMapId);
        final bool hasUsMap = ReferenceImages.isBundled(kTimeZonesUsMapId);
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
                  if (hasWorldMap) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath: ReferenceImages.pathFor(kTimeZonesWorldMapId),
                      aspectRatio: _worldMapAspect,
                      semanticLabel: 'world UTC time-zone map',
                      caption:
                          'Vertical bands are one-hour UTC offsets; the prime '
                          'meridian (UTC 0) runs through Greenwich.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (hasUsMap) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath: ReferenceImages.pathFor(kTimeZonesUsMapId),
                      aspectRatio: _usMapAspect,
                      semanticLabel: 'United States time-zone map',
                      caption:
                          'The continental US spans four zones, plus Alaska and '
                          'Hawaii-Aleutian.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _OffsetRailCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _UsZonesCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DstNoteCard(),
                  ToolHelpFooter(toolId: kTimeZonesToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The world UTC offset rail (offset -> anchor cities).
class _OffsetRailCard extends StatelessWidget {
  const _OffsetRailCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
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
            'World UTC offset rail',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final UtcOffset o in kUtcOffsets)
            Semantics(
              container: true,
              excludeSemantics: true,
              label: '${o.offset}: ${o.cities}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      // Wide enough that the longest offset label ("UTC +5:30",
                      // "UTC +9:30") stays on one line in DM Mono; at 84 it wrapped
                      // "UTC" / "+5:30" to two lines (no-wrap column audit, 2026-06-12).
                      width: 100,
                      child: Text(
                        o.offset,
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        o.cities,
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kUtcOffsetsNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The United States time-zone table.
class _UsZonesCard extends StatelessWidget {
  const _UsZonesCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);
    final TextStyle smallStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textSecondary);
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
            'United States time zones',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              columnSpacing: AppSpacing.md,
              horizontalMargin: 0,
              dividerThickness: 1,
              headingTextStyle: headStyle,
              columns: const <DataColumn>[
                DataColumn(label: Text('Zone')),
                DataColumn(label: Text('Abbr')),
                DataColumn(label: Text('Offset')),
                DataColumn(label: Text('Cities')),
              ],
              rows: kUsTimeZones.map((UsTimeZone z) {
                final String summary = rowLabel(z.zone, <String?>[
                  z.abbr,
                  'offset ${z.offset}',
                  'daylight saving ${z.daylight}',
                  z.cities,
                ]);
                return DataRow(
                  cells: <DataCell>[
                    DataCell(
                      Semantics(
                        label: summary,
                        container: true,
                        child: ExcludeSemantics(
                          child: Text(
                            z.zone,
                            style: (text.bodyMedium ?? const TextStyle())
                                .copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          z.abbr,
                          style: mono.inlineCode.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(
                          z.offset,
                          style: mono.inlineCode.copyWith(
                            color: colors.textAccent,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      ExcludeSemantics(
                        child: Text(z.cities, style: smallStyle),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The daylight-saving column is dropped from the scroll table to keep
          // rows legible; surface it here so no data is lost.
          for (final UsTimeZone z in kUsTimeZones)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RichText(
                text: TextSpan(
                  style: text.labelMedium?.copyWith(color: colors.textTertiary),
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${z.zone}: ',
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: z.daylight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The standard-time / DST framing note.
class _DstNoteCard extends StatelessWidget {
  const _DstNoteCard();

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
              kTimeZonesDstNote,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
