// Hazardous (Classified) Locations — read-only field/trade reference (#3 of the
// Field Reference REFERENCE-screen set, 2026-07-05). Clones the Enclosure
// Ratings pilot pattern verbatim.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/02-hazardous-
// locations.md) as native layout, with Vera's Class/Division/Zone decoder plate
// embedded at the top via DarkRasterDiagramCard (always-dark surface in both
// themes, tap to pinch-zoom). Every fact the plate depicts is ALSO in the native
// text below it, so the image is decorative for screen readers and never the
// sole carrier of meaning (GL-003 §8.6.2 a11y rule).
//
// RECOGNIZE-AND-DEFER: this screen names the hazard (Class / Division / Zone),
// the protection concepts, and the field read, then STOPS. It carries the
// load-bearing safety takeaway ("a commercial AP is a genuine ignition source")
// in a warning band and the AHJ / licensed-electrician defer line in an info
// band. It never adds procedure or a "how to comply" step.
//
// States (SOP-007 §5): pure read-only reference — no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders. The diagram card
//     appears only when its PNG is bundled (ReferenceImages.isBundled);
//     otherwise it is omitted and every table and paragraph still reads
//     end-to-end (graceful degradation of the OPTIONAL art).
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the plate's tap-to-zoom, the §8.16 copy action, and the
//     §8.16.1 help footer (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// Warning bands use Icons.warning_amber_rounded (the fixed convention); info
// bands use Icons.info_outline. Never color-only meaning (§8.13). No new tokens.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.
//
// Pattern: matches enclosure_ratings_screen — Scaffold + AppBar (toolbarHeight
// 64) + §8.16 copy action, SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView of cards.

import 'package:flutter/material.dart';

import '../../../data/hazardous_locations_data.dart';
import '../../../data/reference_images.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';

class HazardousLocationsScreen extends StatelessWidget {
  const HazardousLocationsScreen({super.key});

  /// The decoder plate's true aspect ratio (width / height). Master render is
  /// 3360 x 3236.
  static const double _diagramAspect = 3360 / 3236;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hazardous Locations'),
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
        final bool hasDiagram =
            ReferenceImages.isBundled(kHazardousLocationsToolId);
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
                  if (hasDiagram) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath:
                          ReferenceImages.pathFor(kHazardousLocationsToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Class, Division, and Zone hazardous-location decoder '
                          'diagram',
                      caption: 'Decode Class, Division, and the IEC Zone system.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _LeadCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _ClassCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DivisionCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _ZoneCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WhyNotCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _Div2BuysCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _FieldReadCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCaresCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DeferBand(),
                  ToolHelpFooter(toolId: kHazardousLocationsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// §8.16 plain-text payload — the full reference as tab-separated sections so
  /// it pastes cleanly into notes or a spec review. Always non-null (static).
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Hazardous (Classified) Locations')
      ..writeln()
      ..writeln(kHazLead)
      ..writeln()
      ..writeln('Class: what the hazard is made of')
      ..writeln(<String>['Class', 'Hazard', 'Real environments'].join(tab));
    for (final HazClass c in kHazClasses) {
      b.writeln(<String>[c.cls, c.hazard, c.environments].join(tab));
    }
    b
      ..writeln()
      ..writeln('Division: how often the hazard is present');
    for (final String d in kHazDivisions) {
      b.writeln('- $d');
    }
    b
      ..writeln(kHazDivisionNote)
      ..writeln()
      ..writeln('Zone: the international system')
      ..writeln(kHazZoneIntro)
      ..writeln(<String>['Hazard', 'Zones', 'Meaning'].join(tab));
    for (final HazZone z in kHazZones) {
      b.writeln(<String>[z.hazard, z.zones, z.meaning].join(tab));
    }
    b.writeln(kHazZoneMappingIntro);
    for (final String m in kHazZoneMapping) {
      b.writeln('- $m');
    }
    b
      ..writeln(kHazZoneNote)
      ..writeln()
      ..writeln('Why a commercial AP cannot go there')
      ..writeln(kHazApBody)
      ..writeln(kHazApWarning)
      ..writeln(kHazProtectionIntro)
      ..writeln(<String>['Concept', 'How it protects', 'Where'].join(tab));
    for (final HazConcept c in kHazConcepts) {
      b.writeln(<String>[c.concept, c.how, c.where].join(tab));
    }
    b
      ..writeln(kHazListingNote)
      ..writeln()
      ..writeln('What "Class I Div 2 rated" actually buys you');
    for (final String p in kHazDiv2Buys) {
      b.writeln(p);
    }
    b
      ..writeln()
      ..writeln('The field read');
    for (final String p in kHazFieldRead) {
      b.writeln('- $p');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kHazWlanCares)
      ..writeln()
      ..writeln(kHazDeferNote);
    return b.toString().trimRight();
  }
}

// ─────────────────────────────── shared card shell ──────────────────────────

/// Surface-1 card with an optional section title (labelMedium, tracked).
class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});

  final String? title;
  final Widget child;

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
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// A body paragraph in the standard secondary color.
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textSecondary,
      ),
    );
  }
}

/// A muted one-line caption / footnote (tertiary).
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.bodySmall?.copyWith(color: colors.textTertiary),
    );
  }
}

/// A bulleted list of prose strings, each a real semantic line.
class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                child: Icon(Icons.circle, size: 6, color: colors.textAccent),
              ),
              Expanded(
                child: Text(
                  items[i],
                  style: t.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One three-line labeled row: a bold [head], an accent [mid] line, and a muted
/// [foot] line. Handles arbitrary-length leading text (Class/Zone/Concept names)
/// without a fixed-width code chip. Whole row is one Semantics unit.
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.head, required this.mid, required this.foot});

  final String head;
  final String mid;
  final String foot;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$head. $mid. $foot',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            head,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(mid, style: t.bodyMedium?.copyWith(color: colors.textAccent)),
          const SizedBox(height: 2),
          Text(foot, style: t.bodySmall?.copyWith(color: colors.textTertiary)),
        ],
      ),
    );
  }
}

/// A vertically-stacked list of rows with hairline dividers between them.
class _DividedTable extends StatelessWidget {
  const _DividedTable({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
          rows[i],
        ],
      ],
    );
  }
}

/// A warning band (icon + text, never color-only, §8.13). Fixed convention:
/// Icons.warning_amber_rounded.
class _WarningBand extends StatelessWidget {
  const _WarningBand(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.statusWarning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── section cards ──────────────────────────────

/// The lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kHazLead));
  }
}

/// Class: what the hazard is made of.
class _ClassCard extends StatelessWidget {
  const _ClassCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Class: what the hazard is made of',
      child: _DividedTable(
        rows: <Widget>[
          for (final HazClass c in kHazClasses)
            _LabeledRow(head: c.cls, mid: c.hazard, foot: c.environments),
        ],
      ),
    );
  }
}

/// Division: how often the hazard is present.
class _DivisionCard extends StatelessWidget {
  const _DivisionCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Division: how often the hazard is present',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Bullets(kHazDivisions),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kHazDivisionNote),
        ],
      ),
    );
  }
}

/// Zone: the international (IEC) system.
class _ZoneCard extends StatelessWidget {
  const _ZoneCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Zone: the international system',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kHazZoneIntro),
          const SizedBox(height: AppSpacing.md),
          _DividedTable(
            rows: <Widget>[
              for (final HazZone z in kHazZones)
                _LabeledRow(head: z.zones, mid: z.meaning, foot: z.hazard),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _Body(kHazZoneMappingIntro),
          const SizedBox(height: AppSpacing.sm),
          const _Bullets(kHazZoneMapping),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kHazZoneNote),
        ],
      ),
    );
  }
}

/// Why a commercial AP cannot go there — body + the load-bearing warning band +
/// the protection-concept table.
class _WhyNotCard extends StatelessWidget {
  const _WhyNotCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Why a commercial AP cannot go there',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kHazApBody),
          const SizedBox(height: AppSpacing.md),
          const _WarningBand(kHazApWarning),
          const SizedBox(height: AppSpacing.md),
          const _Body(kHazProtectionIntro),
          const SizedBox(height: AppSpacing.md),
          _DividedTable(
            rows: <Widget>[
              for (final HazConcept c in kHazConcepts)
                _LabeledRow(head: c.concept, mid: c.how, foot: c.where),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kHazListingNote),
        ],
      ),
    );
  }
}

/// What "Class I Div 2 rated" actually buys you.
class _Div2BuysCard extends StatelessWidget {
  const _Div2BuysCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'What "Class I Div 2 rated" actually buys you',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < kHazDiv2Buys.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _Body(kHazDiv2Buys[i]),
          ],
        ],
      ),
    );
  }
}

/// The field read.
class _FieldReadCard extends StatelessWidget {
  const _FieldReadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'The field read',
      child: _Bullets(kHazFieldRead),
    );
  }
}

/// Why a WLAN pro cares.
class _WlanCaresCard extends StatelessWidget {
  const _WlanCaresCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Why a WLAN pro cares',
      child: _Body(kHazWlanCares),
    );
  }
}

/// The recognize-and-defer footer as an info band (icon + text, §8.13).
class _DeferBand extends StatelessWidget {
  const _DeferBand();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusInfoFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusInfo, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: colors.statusInfo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              kHazDeferNote,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
