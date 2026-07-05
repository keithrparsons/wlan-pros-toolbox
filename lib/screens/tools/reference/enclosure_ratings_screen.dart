// Enclosure Ratings (IP and NEMA) — read-only field/trade reference (pilot of
// the Field Reference REFERENCE-screen set, 2026-07-05).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/01-enclosure-ratings.md)
// as native layout, with Vera's IP/NEMA decoder plate embedded at the top via
// the established DarkRasterDiagramCard (always-dark surface in both themes, tap
// to pinch-zoom). Every fact the plate depicts is ALSO in the native text below
// it, so the image is decorative for screen readers and never the sole carrier
// of meaning (GL-003 §8.6.2 a11y rule).
//
// States (SOP-007 §5): pure read-only reference — no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders (the always-present
//     state). The diagram card appears only when its PNG is bundled
//     (ReferenceImages.isBundled); otherwise it is omitted and every table and
//     paragraph still reads end-to-end (graceful degradation of the OPTIONAL art).
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the plate's tap-to-zoom, the AppBar §8.16 copy action, and
//     the §8.16.1 help footer (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The one-way NEMA->IP rule is a warning band (statusWarning glyph + word, never
// color-only meaning, §8.13); the recognize-and-defer footer is an info band
// (statusInfo). No new tokens.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; codes shown in DM Mono (AppMonoText.inlineCode).
//
// Pattern: matches diffie_hellman_screen / poe_reference_screen — Scaffold +
// AppBar (toolbarHeight 64) + §8.16 copy action, SafeArea(top: false),
// LayoutBuilder isDesktop @720, ConstrainedBox to calculatorMaxWidth,
// SingleChildScrollView of cards from app_tokens / app_typography.

import 'package:flutter/material.dart';

import '../../../data/enclosure_ratings_data.dart';
import '../../../data/reference_images.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';

class EnclosureRatingsScreen extends StatelessWidget {
  const EnclosureRatingsScreen({super.key});

  /// The decoder plate's true aspect ratio (width / height), pinned so the
  /// inline card is the right shape with no measuring and no letterbox gutters.
  /// Master render is 3360 x 4150.
  static const double _diagramAspect = 3360 / 4150;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enclosure Ratings'),
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
            ReferenceImages.isBundled(kEnclosureRatingsToolId);
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
                          ReferenceImages.pathFor(kEnclosureRatingsToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'IP and NEMA enclosure-rating decoder diagram',
                      // The zoom affordance rides in a row BELOW the plate (see
                      // DarkRasterDiagramCard), so this caption stays a pure
                      // teaching line — no on-plate badge to collide with the
                      // baked logo / eyebrow / footer marks.
                      caption: 'Decode an IP code and bridge NEMA to IP.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _LeadCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _IpCodeCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _NemaCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _NemaToIpCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _PlacementCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _MythsCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCaresCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DeferBand(),
                  ToolHelpFooter(toolId: kEnclosureRatingsToolId),
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
      ..writeln('Enclosure Ratings (IP and NEMA)')
      ..writeln()
      ..writeln(kEnclosureLead)
      ..writeln()
      ..writeln('IP code (IEC 60529)')
      ..writeln(kIpCodeIntro)
      ..writeln(kIpCodeExample)
      ..writeln()
      ..writeln('First digit: solids and dust')
      ..writeln(<String>['Digit', 'Protection', 'Test gate'].join(tab));
    for (final IpDigit d in kIpSolidsDigits) {
      b.writeln(<String>[d.code, d.label, d.detail].join(tab));
    }
    b
      ..writeln(kIpSolidsNote)
      ..writeln()
      ..writeln('Second digit: water')
      ..writeln(<String>['Digit', 'Protection', 'Plain meaning'].join(tab));
    for (final IpDigit d in kIpWaterDigits) {
      b.writeln(<String>[d.code, d.label, d.detail].join(tab));
    }
    b
      ..writeln(kIpWaterNote)
      ..writeln()
      ..writeln('The X placeholder and the letters');
    for (final String note in kIpLetterNotes) {
      b.writeln('- $note');
    }
    b
      ..writeln()
      ..writeln('Common IP ratings you actually see')
      ..writeln(
        <String>['Rating', 'Plain meaning', 'Typical WLAN example'].join(tab),
      );
    for (final IpRating r in kCommonIpRatings) {
      b.writeln(<String>[r.rating, r.meaning, r.example].join(tab));
    }
    b
      ..writeln()
      ..writeln('NEMA (NEMA 250)')
      ..writeln(kNemaIntro)
      ..writeln(<String>['Type', 'Plain meaning'].join(tab));
    for (final NemaType n in kNemaTypes) {
      b.writeln(<String>[n.type, n.meaning].join(tab));
    }
    b
      ..writeln(kNemaFullListNote)
      ..writeln()
      ..writeln('NEMA to IP: a one-way relationship')
      ..writeln(kNemaToIpIntro)
      ..writeln(kNemaToIpRule)
      ..writeln(<String>['NEMA type', 'Minimum IP (commonly cited)'].join(tab));
    for (final NemaIpMapping m in kNemaToIp) {
      b.writeln(<String>[m.nemaType, m.minimumIp].join(tab));
    }
    b
      ..writeln(kNemaToIpNote)
      ..writeln()
      ..writeln('What rating for what placement')
      ..writeln(<String>['Placement', 'Reach for', 'Why'].join(tab));
    for (final PlacementGuidance p in kPlacementGuidance) {
      b.writeln(<String>[p.placement, p.reachFor, p.why].join(tab));
    }
    b
      ..writeln()
      ..writeln('Myths worth killing');
    for (final String myth in kEnclosureMyths) {
      b.writeln('- $myth');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares');
    for (final String p in kEnclosureWlanCares) {
      b.writeln(p);
    }
    b
      ..writeln()
      ..writeln(kEnclosureDeferNote);
    return b.toString().trimRight();
  }
}

// ─────────────────────────────── shared card shell ──────────────────────────

/// Surface-1 card with an optional section title (labelMedium, tracked). Matches
/// the diffie_hellman / poe reference card idiom.
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

/// A small bold subheading inside a card (e.g. "First digit: solids and dust").
class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
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
                child: Icon(
                  Icons.circle,
                  size: 6,
                  color: colors.textAccent,
                ),
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

/// A mono "code chip" (e.g. `6`, `IP66`, `4X`) with a fixed leading width so a
/// column of rows aligns. Accent-tinted, DM Mono per GL-003 identifier styling.
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code, {this.width = 44});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return SizedBox(
      width: width,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxs,
          horizontal: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Text(
          code,
          textAlign: TextAlign.center,
          style: mono.inlineCode.copyWith(
            color: colors.textAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One key/value reference row: a leading [code] chip, then a bold [label] with
/// an optional [detail] line beneath, and an optional muted [trailing] line
/// (e.g. the "typical WLAN example" / "why"). Whole row is one Semantics unit.
class _RefRow extends StatelessWidget {
  const _RefRow({
    required this.code,
    required this.label,
    this.detail,
    this.trailing,
    this.chipWidth = 44,
  });

  final String code;
  final String label;
  final String? detail;
  final String? trailing;
  final double chipWidth;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: <String?>[
        code,
        label,
        detail,
        trailing,
      ].whereType<String>().join('. '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CodeChip(code, width: chipWidth),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: (t.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: t.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (trailing != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    trailing!,
                    style: t.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertically-stacked list of [_RefRow]s with hairline dividers between them.
class _RefTable extends StatelessWidget {
  const _RefTable({required this.rows});

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

// ─────────────────────────────── section cards ──────────────────────────────

/// The italic lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kEnclosureLead));
  }
}

/// IP code (IEC 60529): intro + worked example + the two digit ladders + the
/// X/letters notes + the common-ratings table.
class _IpCodeCard extends StatelessWidget {
  const _IpCodeCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return _Card(
      title: 'IP code (IEC 60529)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kIpCodeIntro),
          const SizedBox(height: AppSpacing.sm),
          _ExampleBand(colors: colors),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading('First digit: solids and dust (0 to 6)'),
          const SizedBox(height: AppSpacing.sm),
          _RefTable(
            rows: <Widget>[
              for (final IpDigit d in kIpSolidsDigits)
                _RefRow(code: d.code, label: d.label, detail: d.detail),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kIpSolidsNote),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading('Second digit: water (0 to 9K)'),
          const SizedBox(height: AppSpacing.sm),
          _RefTable(
            rows: <Widget>[
              for (final IpDigit d in kIpWaterDigits)
                _RefRow(code: d.code, label: d.label, detail: d.detail),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kIpWaterNote),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading('The X placeholder and the letters'),
          const SizedBox(height: AppSpacing.sm),
          const _Bullets(kIpLetterNotes),
          const SizedBox(height: AppSpacing.md),
          const _SubHeading('Common IP ratings you actually see'),
          const SizedBox(height: AppSpacing.sm),
          _RefTable(
            rows: <Widget>[
              for (final IpRating r in kCommonIpRatings)
                _RefRow(
                  code: r.rating,
                  label: r.meaning,
                  trailing: r.example,
                  chipWidth: 60,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The worked "IP 6 7" example on a subtle inset band.
class _ExampleBand extends StatelessWidget {
  const _ExampleBand({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Text(
        kIpCodeExample,
        style: mono.inlineCode.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

/// NEMA (NEMA 250): intro + the four types + the full-list note.
class _NemaCard extends StatelessWidget {
  const _NemaCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'NEMA (NEMA 250)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kNemaIntro),
          const SizedBox(height: AppSpacing.md),
          _RefTable(
            rows: <Widget>[
              for (final NemaType n in kNemaTypes)
                _RefRow(code: n.type, label: n.meaning, chipWidth: 60),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kNemaFullListNote),
        ],
      ),
    );
  }
}

/// NEMA to IP: the one-way relationship. Intro + a warning band carrying the
/// rule + the minimum-equivalent table + the "approximate floors" note.
class _NemaToIpCard extends StatelessWidget {
  const _NemaToIpCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'NEMA to IP: a one-way relationship',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kNemaToIpIntro),
          const SizedBox(height: AppSpacing.md),
          const _RuleBand(),
          const SizedBox(height: AppSpacing.md),
          _RefTable(
            rows: <Widget>[
              for (final NemaIpMapping m in kNemaToIp)
                _RefRow(code: m.nemaType, label: m.minimumIp, chipWidth: 60),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kNemaToIpNote),
        ],
      ),
    );
  }
}

/// The one-way rule as a warning band (icon + word, never color-only, §8.13).
class _RuleBand extends StatelessWidget {
  const _RuleBand();

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
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              kNemaToIpRule,
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

/// What rating for what placement — the field decision table.
class _PlacementCard extends StatelessWidget {
  const _PlacementCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return _Card(
      title: 'What rating for what placement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < kPlacementGuidance.length; i++) ...<Widget>[
            if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
            Semantics(
              container: true,
              label:
                  '${kPlacementGuidance[i].placement}. Reach for '
                  '${kPlacementGuidance[i].reachFor}. '
                  '${kPlacementGuidance[i].why}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    kPlacementGuidance[i].placement,
                    style: (t.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kPlacementGuidance[i].reachFor,
                    style: t.bodyMedium?.copyWith(color: colors.textAccent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    kPlacementGuidance[i].why,
                    style: t.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Myths worth killing.
class _MythsCard extends StatelessWidget {
  const _MythsCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Myths worth killing',
      child: _Bullets(kEnclosureMyths),
    );
  }
}

/// Why a WLAN pro cares.
class _WlanCaresCard extends StatelessWidget {
  const _WlanCaresCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Why a WLAN pro cares',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < kEnclosureWlanCares.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _Body(kEnclosureWlanCares[i]),
          ],
        ],
      ),
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
              kEnclosureDeferNote,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
