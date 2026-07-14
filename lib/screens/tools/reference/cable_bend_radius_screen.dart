// Cable Bend Radius & Pull Tension — read-only install-limits reference.
//
// The two load-bearing numbers an installer actually needs: installed UTP bends
// no tighter than 4x the cable outer diameter, and 4-pair UTP pulls at no more
// than 25 lbf (110 N). Both are TIA-568. Almost everything else on this topic
// (fiber multipliers, the 8x pull figure, cable-tie tension) is a defensible
// rule of thumb that the manufacturer's datasheet legally overrides. This page
// renders the TIA-anchored numbers as standards and the rules of thumb as
// guidance with a visible "manufacturer spec wins" caveat.
//
// It follows the reference template the Power & Cooling pages set: typed const
// datasets, a §8.16 AppCopyAction that emits the whole page as sectioned TSV,
// the LayoutBuilder / ConstrainedBox / SingleChildScrollView scaffold shared by
// every reference screen (iec_connectors_screen and fiber_optic_screen are the
// closest siblings), and a ToolHelpFooter keyed on the catalog id.
//
// Concept graphics: two LARGE graphics rendered through the shared LargeGraphic
// primitive and resolved by explicit asset name through BendDiagrams (the
// manifest-gated resolver, mirroring IecConnectorsDiagrams). The arc-vs-kink
// graphic sits in the bend-radius section; the pull-tension gauge sits in the
// pull-tension section. Each degrades to nothing when its SVG is not yet
// bundled, so the page ships fully working as text + tables now — the graphics
// are a parallel Charta pass.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-cable-bend-radius-reference/RESEARCH-BRIEF.md). The
// brief's confidence flags and CRITICAL honesty corrections are honored verbatim
// and pinned in the tests:
//   * 4x OD installed (UTP) and 25 lbf / 110 N pull (4-pair UTP) are TIA-568 —
//     cited as TIA. (High confidence.)
//   * The "8x OD during pull" copper figure is ISO 11801 / common practice, NOT
//     a confirmed TIA-568 copper clause. It is labeled "ISO 11801 / practice",
//     never attributed to TIA. (Medium confidence on attribution.)
//   * Fiber 10x installed / 20x under pull are RULES OF THUMB for the cable
//     assembly; G.657 bend-insensitive radii (10 mm / 7.5 mm / 5 mm / 2 mm) are
//     the BARE FIBER design radius — the two are not interchangeable.
//   * The manufacturer datasheet overrides every rule of thumb here, and can
//     override the TIA minimum in either direction. This caveat is VISIBLE, not
//     buried — it is the load-bearing fiber caveat.
//   * 0.5 in (13 mm) max untwist is TIA-568-B.1 §10.2.3 (standard); cable ties
//     "must not deform the sheath" is TIA-568-B.1 + BICSI (standard + practice).
//   * The 50/70/90 lbf failure thresholds are a single experimental source —
//     presented as illustrative, not a spec.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; each graphic carries its
// own absent-asset empty state (render nothing). GL-008 network/subprocess rules
// do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): conclusion-first; no em dashes (ASCII
// hyphen-minus only); "Wi-Fi" never "WiFi"; US spelling; the multiply glyph
// appears only where a value uses it ("4x OD" reads as the data value).

import 'package:flutter/material.dart';

import '../../../data/bend_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// How a numeric limit is anchored: a published standard, or a defensible rule
/// of thumb the datasheet overrides. Drives the standard-vs-practice badge so a
/// reader can tell the two registers apart at a glance.
enum LimitBasis {
  /// Anchored in a named standard (TIA-568, TIA-569). Rendered as the firm
  /// "standard" register.
  standard,

  /// A defensible rule of thumb / non-TIA standard (ISO 11801) / common
  /// practice. Rendered as the softer "practice" register, with the
  /// "datasheet wins" caveat visible nearby.
  practice,
}

/// One minimum-bend-radius row (copper or fiber). Field values are verified
/// against Pax's research brief; [basis] + [source] keep the standard-vs-practice
/// labeling honest per the brief's CRITICAL corrections.
@immutable
class BendLimit {
  const BendLimit({
    required this.condition,
    required this.limit,
    required this.basis,
    required this.source,
  });

  /// The install condition, e.g. `Installed, 4-pair UTP`.
  final String condition;

  /// The limit value, e.g. `>= 4x OD`. Rendered in DM Mono (numeric register).
  final String limit;

  /// Whether the limit is a standard or a rule of thumb.
  final LimitBasis basis;

  /// The cited basis, e.g. `TIA-568` or `ISO 11801 / practice`. Kept SEPARATE
  /// from the value so the 8x-during-pull figure can never read as "TIA".
  final String source;
}

/// One related install limit (untwist, cable-tie, fill, support spacing). The
/// [basis] + [source] carry the standard-vs-practice labeling the brief requires.
@immutable
class InstallLimit {
  const InstallLimit({
    required this.name,
    required this.value,
    required this.basis,
    required this.source,
  });

  /// The limit name, e.g. `Max pair untwist at termination`.
  final String name;

  /// The value, e.g. `<= 0.5 in (13 mm)`.
  final String value;

  /// Whether it is a standard or a rule of thumb.
  final LimitBasis basis;

  /// The cited basis, e.g. `TIA-568-B.1 §10.2.3`.
  final String source;
}

class CableBendRadiusScreen extends StatelessWidget {
  const CableBendRadiusScreen({super.key});

  // ---- Section (a) — minimum bend radius -----------------------------------

  /// Copper UTP minimum bend radius. Verified against the research brief
  /// (Section 1). The 4x installed figure is the TIA number to feature; the 8x
  /// during-pull figure is ISO 11801 / practice, NOT TIA — labeled accordingly.
  static const List<BendLimit> copperBend = <BendLimit>[
    BendLimit(
      condition: 'Installed, 4-pair UTP (horizontal)',
      limit: '>= 4x OD',
      basis: LimitBasis.standard,
      source: 'TIA-568',
    ),
    BendLimit(
      condition: 'During pull / under tension',
      limit: '>= 8x OD',
      basis: LimitBasis.practice,
      source: 'ISO 11801 / practice',
    ),
    BendLimit(
      condition: 'Multi-pair backbone copper (25+ pair)',
      limit: '>= 10x OD',
      basis: LimitBasis.practice,
      source: 'practice',
    ),
  ];

  /// Fiber minimum bend radius. Verified against the research brief (Section 2).
  /// The 10x / 20x figures are rules of thumb for the cable assembly; the G.657
  /// millimeter figures are the bare-fiber design radius. The two are not
  /// interchangeable — the datasheet caveat below makes that explicit.
  static const List<BendLimit> fiberBend = <BendLimit>[
    BendLimit(
      condition: 'Installed / no load (standard SM/MM cable)',
      limit: '>= 10x OD',
      basis: LimitBasis.practice,
      source: 'rule of thumb',
    ),
    BendLimit(
      condition: 'During pull / under tension',
      limit: '>= 20x OD',
      basis: LimitBasis.practice,
      source: 'rule of thumb',
    ),
    BendLimit(
      condition: 'Bend-insensitive SM (G.657.A1)',
      limit: '~10 mm',
      basis: LimitBasis.standard,
      source: 'ITU-T G.657',
    ),
    BendLimit(
      condition: 'Bend-insensitive SM (G.657.A2)',
      limit: '~7.5 mm',
      basis: LimitBasis.standard,
      source: 'ITU-T G.657',
    ),
    BendLimit(
      condition: 'Bend-insensitive SM (G.657.B2)',
      limit: '~5 mm',
      basis: LimitBasis.standard,
      source: 'ITU-T G.657 (vendor)',
    ),
    BendLimit(
      condition: 'Bend-insensitive SM (G.657.B3)',
      limit: '~2 mm',
      basis: LimitBasis.standard,
      source: 'ITU-T G.657 (vendor)',
    ),
  ];

  /// The "don't kink" mental model — the functional rule the 4x number protects.
  static const String kinkNote =
      'The functional rule is simple: do not kink it. A kink permanently changes '
      'the conductor spacing inside the jacket, which degrades return loss and '
      'crosstalk even after the cable is straightened. The damage does not spring '
      'back. The 4x figure exists to keep you safely away from the kink '
      'threshold, not because 3.9x fails and 4.0x passes. Compute the radius from '
      'the cable actual outer diameter: a ~0.25 in Cat6 needs about 1 in, while a '
      'fatter ~0.30 to 0.35 in Cat6A needs about 1.2 to 1.4 in. Never use a fixed '
      'inch value.';

  /// The load-bearing fiber caveat — manufacturer datasheet wins. This MUST be
  /// visible, not buried (research brief, Section 2 honesty note).
  static const String fiberDatasheetNote =
      'Always defer to the cable assembly datasheet. The 10x / 20x figures are '
      'rules of thumb for the jacketed assembly; the G.657 millimeter radii are '
      'the bare fiber design radius, and the two are not interchangeable. '
      'Bend-insensitive glass does not license a tight bend on a cable whose '
      'jacket says otherwise. The datasheet is the binding number; the rule of '
      'thumb is the fallback when no datasheet is at hand.';

  // ---- Section (b) — maximum pull tension ----------------------------------

  /// Maximum pull tension. Verified against the research brief (Section 3). The
  /// 25 lbf / 110 N figure for 4-pair UTP is TIA-568 (section 10.6.3.2).
  static const List<InstallLimit> pullTension = <InstallLimit>[
    InstallLimit(
      name: '4-pair UTP (24 AWG horizontal)',
      value: '25 lbf (110 N)',
      basis: LimitBasis.standard,
      source: 'TIA-568 §10.6.3.2',
    ),
    InstallLimit(
      name: 'Fiber and multi-fiber cable',
      value: 'Per datasheet',
      basis: LimitBasis.practice,
      source: 'strength-member dependent',
    ),
    InstallLimit(
      name: 'Multi-cable bundle pull',
      value: 'Derate per cable',
      basis: LimitBasis.practice,
      source: 'total is not the sum',
    ),
  ];

  /// Why 25 lbf, the three consequences of over-pulling, and the illustrative
  /// failure thresholds (single experimental source — flagged as illustrative).
  static const String pullNote =
      'The 25 lbf limit is engineered, not arbitrary: per Paul Kish (former chair '
      'of the TIA copper-cabling working group), 4-pair 24 AWG copper tolerates '
      'about 10,000 psi over its ~0.0025 sq in cross-section, which works out to '
      'about 25 lbf. Over-pull and three things happen: the conductors stretch '
      'and thin, attenuation (insertion loss) rises because a thinner conductor '
      'has more resistance, and NEXT and return loss degrade because stretching '
      'disturbs the twist geometry the cable depends on for balance. As an '
      'illustration (single experimental source, not a spec): below about 50 lbf '
      'there is little change, around 70 lbf shows visible copper stretch, and at '
      'about 90 to 110 lbf the cable breaks. The 25 lbf limit is deliberately '
      'conservative, so failures do not start at 26 lbf, but past it you have '
      'left the engineered safety margin.';

  /// Fiber / bundle pull caveat — do not publish a single fiber tension number.
  static const String pullFiberNote =
      'Fiber and multi-fiber tension limits are strength-member dependent and '
      'differ entirely from copper, so follow the cable datasheet rather than a '
      'single published number. For a multi-cable pull the safe per-cable tension '
      'drops with friction and uneven loading, and the bundle total is not the '
      'simple sum of the individual ratings. Derate, and follow the datasheet.';

  // ---- Section (c) — related install limits --------------------------------

  /// Related install limits, with honest standard-vs-practice labeling. Verified
  /// against the research brief (Section 4).
  static const List<InstallLimit> installLimits = <InstallLimit>[
    InstallLimit(
      name: 'Max pair untwist at termination',
      value: '<= 0.5 in (13 mm)',
      basis: LimitBasis.standard,
      source: 'TIA-568-B.1 §10.2.3',
    ),
    InstallLimit(
      name: 'Cable-tie tension',
      value: 'No sheath deformation',
      basis: LimitBasis.standard,
      source: 'TIA-568-B.1 + BICSI',
    ),
    InstallLimit(
      name: 'Pathway fill',
      value: '<= 40% conduit, <= 50% tray',
      basis: LimitBasis.practice,
      source: 'TIA-569 (verify revision)',
    ),
    InstallLimit(
      name: 'Horizontal support spacing',
      value: '<= 5 ft (~1.5 m)',
      basis: LimitBasis.practice,
      source: 'TIA-569 + BICSI',
    ),
  ];

  /// Untwist + cable-tie field tests. Both numbers here are genuine standards
  /// (TIA + BICSI), not rules of thumb.
  static const String installNote =
      'Two of these are genuine TIA requirements, not rules of thumb. Keep pair '
      'twists maintained to within 0.5 in (13 mm) of the termination point '
      '(TIA-568-B.1 §10.2.3, Cat5e through Cat8); untwisting further introduces '
      'NEXT, and Cat6A and higher want tighter than 0.5 in. For cable ties, the '
      'field test is that you should be able to slide or rotate the tie around '
      'the bundle after tying it. If it cannot move, it is too tight: '
      'overtightening crushes the pair geometry and causes return loss, NEXT, and '
      'intermittent faults. Hook-and-loop (Velcro) over zip ties for data bundles '
      'is sound practice consistent with the "must slide" rule, but it is '
      'convention, not a TIA mandate. Pathway fill and support spacing vary by '
      'pathway and cable type, so treat them as commonly specified and verify '
      'against the current TIA-569 and local code.';

  /// The page-level mental model, stated conclusion-first up top.
  static const String leadNote =
      'Four habits cover almost all of cable-handling damage: do not kink, do not '
      'over-pull, do not over-tighten the ties, and when a datasheet is at hand, '
      'the datasheet wins. The numbers below give the floors. TIA standards set '
      'minimum performance floors; a specific cable datasheet can be more '
      'permissive (bend-insensitive fiber) or more restrictive (large-OD Cat6A, '
      'shielded constructions), and it is the binding number when you have it.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bend Radius & Pull Tension'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: bend radius (copper +
        // fiber), pull tension, and related install limits. Static data, always
        // enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as TSV sections. Standard-vs-practice is
  /// preserved as a "Basis" column so the pasted text never loses the honesty
  /// labeling (the 8x figure carries "ISO 11801 / practice", never "TIA").
  /// Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Cable Bend Radius & Pull Tension')
      ..writeln()
      ..writeln(leadNote)
      ..writeln()
      ..writeln('Minimum bend radius: copper UTP')
      ..writeln(
        <String>['Condition', 'Limit', 'Basis'].join(tab),
      );
    for (final BendLimit b in copperBend) {
      buf.writeln(<String>[b.condition, b.limit, b.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kinkNote)
      ..writeln()
      ..writeln('Minimum bend radius: fiber')
      ..writeln(
        <String>['Condition', 'Limit', 'Basis'].join(tab),
      );
    for (final BendLimit b in fiberBend) {
      buf.writeln(<String>[b.condition, b.limit, b.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln(fiberDatasheetNote)
      ..writeln()
      ..writeln('Maximum pull tension')
      ..writeln(
        <String>['Cable', 'Max pull tension', 'Basis'].join(tab),
      );
    for (final InstallLimit l in pullTension) {
      buf.writeln(<String>[l.name, l.value, l.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln(pullNote)
      ..writeln()
      ..writeln(pullFiberNote)
      ..writeln()
      ..writeln('Related install limits')
      ..writeln(
        <String>['Limit', 'Value', 'Basis'].join(tab),
      );
    for (final InstallLimit l in installLimits) {
      buf.writeln(<String>[l.name, l.value, l.source].join(tab));
    }
    buf
      ..writeln()
      ..writeln(installNote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
                children: <Widget>[
                  // Conclusion-first lead: the four-habit mental model before the
                  // numbers (research brief recommendation).
                  Text(
                    leadNote,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ---- Section (a) — minimum bend radius -------------------
                  _SectionHeading(label: 'Minimum bend radius'),
                  const SizedBox(height: AppSpacing.sm),
                  // The arc-vs-kink concept graphic leads the bend section — the
                  // single most useful visual on the page. Degrades to nothing
                  // when its SVG is not yet bundled.
                  LargeGraphic(
                    assetName: BendDiagrams.arcVsKink,
                    path: BendDiagrams.path,
                    has: BendDiagrams.has,
                  ),
                  if (BendDiagrams.has(BendDiagrams.arcVsKink))
                    const SizedBox(height: AppSpacing.md),
                  _LimitCard(
                    heading: 'Copper UTP',
                    rows: <Widget>[
                      for (final BendLimit b in copperBend)
                        _BendRow(limit: b),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _NoteText(kinkNote),
                  const SizedBox(height: AppSpacing.md),
                  _LimitCard(
                    heading: 'Fiber',
                    rows: <Widget>[
                      for (final BendLimit b in fiberBend) _BendRow(limit: b),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // The datasheet-wins caveat, visible (not buried) per the brief.
                  _CaveatText(fiberDatasheetNote),
                  const SizedBox(height: AppSpacing.lg),

                  // ---- Section (b) — maximum pull tension ------------------
                  _SectionHeading(label: 'Maximum pull tension'),
                  const SizedBox(height: AppSpacing.sm),
                  // The pull-tension gauge concept graphic sits in its own
                  // section. Degrades to nothing when its SVG is not yet bundled.
                  LargeGraphic(
                    assetName: BendDiagrams.pullTensionGauge,
                    path: BendDiagrams.path,
                    has: BendDiagrams.has,
                  ),
                  if (BendDiagrams.has(BendDiagrams.pullTensionGauge))
                    const SizedBox(height: AppSpacing.md),
                  _LimitCard(
                    heading: 'Max pull tension',
                    rows: <Widget>[
                      for (final InstallLimit l in pullTension)
                        _InstallRow(limit: l),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _NoteText(pullNote),
                  const SizedBox(height: AppSpacing.xs),
                  _CaveatText(pullFiberNote),
                  const SizedBox(height: AppSpacing.lg),

                  // ---- Section (c) — related install limits ----------------
                  _SectionHeading(label: 'Related install limits'),
                  const SizedBox(height: AppSpacing.sm),
                  _LimitCard(
                    heading: 'Termination, ties, pathways',
                    rows: <Widget>[
                      for (final InstallLimit l in installLimits)
                        _InstallRow(limit: l),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _NoteText(installNote),

                  ToolHelpFooter(toolId: 'cable-bend-radius'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A section heading standing on the page background above a stack of cards.
/// Mirrors the IEC reference `_SectionHeading` register.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      label,
      style: text.titleSmall?.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// Shared card surface for a labelled limit table — matches the fiber / dB / port
/// reference idiom (surface1 fill, hairline border, card radius).
class _LimitCard extends StatelessWidget {
  const _LimitCard({required this.heading, required this.rows});

  final String heading;
  final List<Widget> rows;

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
            heading,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows,
        ],
      ),
    );
  }
}

/// A small badge that distinguishes a published standard from a rule of thumb.
/// Color is never the only signal — the badge carries the word "Standard" or
/// "Practice" so it reads for colorblind / AT users.
class _BasisBadge extends StatelessWidget {
  const _BasisBadge({required this.basis});

  final LimitBasis basis;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isStandard = basis == LimitBasis.standard;
    // Standard reads at accent (the firm register); practice reads at tertiary
    // ink on a plain surface (the softer guidance register). Both carry a word,
    // so meaning never rests on color alone.
    final Color fg = isStandard ? colors.textAccent : colors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Text(
        isStandard ? 'Standard' : 'Practice',
        style: text.labelSmall?.copyWith(
          color: fg,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One minimum-bend-radius row: condition (wraps), value (DM Mono, accent), the
/// cited basis, and the standard-vs-practice badge. Full-width so the condition
/// and source wrap instead of overflowing at phone width.
class _BendRow extends StatelessWidget {
  const _BendRow({required this.limit});

  final BendLimit limit;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceRowSemantics(
      label: rowLabel(limit.condition, <String?>[
        limit.limit,
        '${limit.basis == LimitBasis.standard ? 'standard' : 'practice'}: '
            '${limit.source}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    limit.condition,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    limit.limit,
                    textAlign: TextAlign.end,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: <Widget>[
                  _BasisBadge(basis: limit.basis),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      limit.source,
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One related-install-limit / pull-tension row: name (wraps), value (DM Mono),
/// the cited basis, and the standard-vs-practice badge. Full-width so it wraps
/// at phone width instead of overflowing.
class _InstallRow extends StatelessWidget {
  const _InstallRow({required this.limit});

  final InstallLimit limit;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool isStandard = limit.basis == LimitBasis.standard;
    return ReferenceRowSemantics(
      label: rowLabel(limit.name, <String?>[
        limit.value,
        '${isStandard ? 'standard' : 'practice'}: ${limit.source}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    limit.name,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    limit.value,
                    textAlign: TextAlign.end,
                    style: mono.inlineCode.copyWith(
                      // The TIA pull-tension number is the page's headline value;
                      // accent it. Practice rows read at primary ink so the accent
                      // stays reserved for the standards.
                      color: isStandard ? colors.textAccent : colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: <Widget>[
                  _BasisBadge(basis: limit.basis),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      limit.source,
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A standard secondary-ink note paragraph beneath a card.
class _NoteText extends StatelessWidget {
  const _NoteText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.bodyMedium?.copyWith(color: colors.textSecondary),
    );
  }
}

/// A caveat paragraph rendered in an accent-bordered well so the load-bearing
/// "datasheet wins" rule is visible and not buried (research brief requirement).
class _CaveatText extends StatelessWidget {
  const _CaveatText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.textAccent, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 24,
            color: colors.textAccent,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: t.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
