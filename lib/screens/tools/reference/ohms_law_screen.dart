// Ohm's Law & Power Wheel — read-only reference for the V / I / R / P
// relationships every field tech reaches for, the 12-segment power wheel
// transcribed as a formula table, and the single-phase vs three-phase power
// formulas with the power-factor caveat.
//
// PAGE 2 of the "Power & Cooling" reference category. It follows the approved
// Power Phasing pilot template EXACTLY: typed const datasets, a §8.16
// AppCopyAction that emits the whole page as sectioned TSV, the LayoutBuilder /
// ConstrainedBox / SingleChildScrollView scaffold shared by every reference
// screen (power_phasing_screen / poe_reference_screen are the closest
// siblings), and a ToolHelpFooter keyed on the catalog id.
//
// Like the pilot, this page carries a NAMED reference graphic (the power
// wheel), resolved by explicit asset name through OhmsLawDiagrams (the
// manifest-gated resolver, mirroring PowerPhasingDiagrams) and rendered by the
// shared _WheelBand, which reuses the §8.20.7 light-mode recolor path
// (ConceptGraphicBand.applyLightSwap) exactly as the Power Phasing waveform
// bands do. The band degrades to nothing when its SVG is not yet bundled, so
// the page ships fully working before Charta's wheel SVG lands.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, Topic 1),
// sourced to the standard EE identity set (V = I x R, P = V x I, P = I^2 x R,
// P = V^2 / R), the 12-form Ohm's-law wheel, and the AC real/apparent/reactive
// power relationships with power factor. Facts only. The page deliberately
// renders the power-factor term (x PF) and states PF = 1 only for resistive /
// DC loads — the cheat-sheet error the brief flags is presenting P = V x I as
// universally giving watts in AC; this page does not.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; the wheel band carries
// its own absent-asset empty state (render nothing). GL-008 network/subprocess
// rules do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): ASCII hyphen-minus only, never an em dash; US
// spelling; the Greek phi in "cos phi" is spelled out in prose and rendered as
// the ASCII token "cos(phi)" in the copy payload so the pasted text stays
// plain-text safe; "sqrt(3)" written "the square root of 3" in prose and as the
// ASCII "sqrt(3)" token in formulas and copy; "I^2" / "V^2" use the caret ASCII
// notation (no superscript glyph) so the formulas copy cleanly.

import 'package:flutter/material.dart';

import '../../../data/ohms_law_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// One core electrical identity — the four relationships every field tech
/// reaches for. Verified against Pax's research brief (Topic 1).
@immutable
class OhmsRelation {
  const OhmsRelation({
    required this.name,
    required this.formula,
    required this.solvesFor,
  });

  /// What the relationship is called, e.g. `Ohm's law`.
  final String name;

  /// The formula in ASCII notation, e.g. `V = I x R`.
  final String formula;

  /// The quantity it solves for, e.g. `Voltage (V)`.
  final String solvesFor;
}

/// One row of the 12-segment power wheel — one of V, I, R, P expressed three
/// ways (in terms of any two of the others). Verified against the research
/// brief's 12-form wheel.
@immutable
class WheelRow {
  const WheelRow({
    required this.quantity,
    required this.formA,
    required this.formB,
    required this.formC,
  });

  /// The quantity being solved for, e.g. `V (volts)`.
  final String quantity;

  /// First algebraic form, e.g. `I x R`.
  final String formA;

  /// Second algebraic form, e.g. `P / I`.
  final String formB;

  /// Third algebraic form, e.g. `sqrt(P x R)`.
  final String formC;
}

/// One row of the single-phase vs three-phase power table. Verified against the
/// research brief's power table.
@immutable
class PowerFormula {
  const PowerFormula({
    required this.system,
    required this.apparent,
    required this.real,
  });

  /// The system, e.g. `Single-phase`.
  final String system;

  /// Apparent power (VA) formula, e.g. `S = V x I`.
  final String apparent;

  /// Real power (W) formula, e.g. `P = V x I x cos(phi)`.
  final String real;
}

class OhmsLawScreen extends StatelessWidget {
  const OhmsLawScreen({super.key});

  /// The four core identities, all derivable from V = I x R and P = V x I.
  /// Verified against the research brief (Topic 1).
  static const List<OhmsRelation> relations = <OhmsRelation>[
    OhmsRelation(
      name: "Ohm's law",
      formula: 'V = I x R',
      solvesFor: 'Voltage (V)',
    ),
    OhmsRelation(
      name: 'Power (base)',
      formula: 'P = V x I',
      solvesFor: 'Power (W)',
    ),
    OhmsRelation(
      name: 'Power from current and resistance',
      formula: 'P = I^2 x R',
      solvesFor: 'Power (W)',
    ),
    OhmsRelation(
      name: 'Power from voltage and resistance',
      formula: 'P = V^2 / R',
      solvesFor: 'Power (W)',
    ),
  ];

  /// The 12-segment wheel: each of V, I, R, P in terms of any two of the others.
  /// Verified against the research brief's 12-form wheel.
  static const List<WheelRow> wheel = <WheelRow>[
    WheelRow(
      quantity: 'V (volts)',
      formA: 'I x R',
      formB: 'P / I',
      formC: 'sqrt(P x R)',
    ),
    WheelRow(
      quantity: 'I (amps)',
      formA: 'V / R',
      formB: 'P / V',
      formC: 'sqrt(P / R)',
    ),
    WheelRow(
      quantity: 'R (ohms)',
      formA: 'V / I',
      formB: 'V^2 / P',
      formC: 'P / I^2',
    ),
    WheelRow(
      quantity: 'P (watts)',
      formA: 'V x I',
      formB: 'I^2 x R',
      formC: 'V^2 / R',
    ),
  ];

  /// Single-phase vs three-phase power. Verified against the research brief.
  static const List<PowerFormula> powerFormulas = <PowerFormula>[
    PowerFormula(
      system: 'Single-phase',
      apparent: 'S = V x I',
      real: 'P = V x I x cos(phi)',
    ),
    PowerFormula(
      system: 'Three-phase (balanced)',
      apparent: 'S = sqrt(3) x V_LL x I_L',
      real: 'P = sqrt(3) x V_LL x I_L x cos(phi)',
    ),
  ];

  /// The power-factor note — the load-bearing AC caveat the brief flags. Facts
  /// only (research brief, Topic 1).
  static const String powerFactorNote =
      'Power factor (cos phi) is 1 for purely resistive loads and for DC, where '
      'P = V x I is exact. Power factor is less than 1 whenever the load is '
      'reactive (inductive motors and compressors, or switch-mode power '
      'supplies); there V x I gives apparent power in VA, not real power in '
      'watts. That gap is exactly why UPS and PDU equipment is rated in both VA '
      'and W. Do not read P = V x I as giving watts on an AC reactive load.';

  /// Provenance footnote on the relationships card.
  static const String relationsFootnote =
      'All four identities derive from V = I x R and P = V x I. For three-phase '
      'balanced loads the line-to-line voltage is the square root of 3 times '
      'the line-to-neutral voltage.';

  /// Footnote on the wheel card.
  static const String wheelFootnote =
      'Each of V, I, R, and P can be written in terms of any two of the others, '
      'giving the twelve forms of the power wheel.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ohm's Law & Power Wheel"),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: core relationships, the
        // 12-form wheel, then single-phase vs three-phase power. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as three TSV sections. Section 1 is the
  /// core relationships (name, formula, solves for); section 2 is the 12-form
  /// wheel (quantity, three forms); section 3 is single-phase vs three-phase
  /// power (system, apparent, real). ASCII tokens ("sqrt(3)", "cos(phi)",
  /// "I^2") carry straight through so the pasted text stays plain-text safe (no
  /// root, phi, or superscript glyph). Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln("Ohm's Law & Power Wheel")
      ..writeln()
      ..writeln('Core relationships')
      ..writeln(
        <String>['Relationship', 'Formula', 'Solves for'].join(tab),
      );
    for (final OhmsRelation r in relations) {
      buf.writeln(<String>[r.name, r.formula, r.solvesFor].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Power wheel (12 forms)')
      ..writeln(
        <String>['Quantity', 'Form 1', 'Form 2', 'Form 3'].join(tab),
      );
    for (final WheelRow w in wheel) {
      buf.writeln(
        <String>[w.quantity, w.formA, w.formB, w.formC].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Single-phase vs three-phase power')
      ..writeln(
        <String>['System', 'Apparent power (VA)', 'Real power (W)'].join(tab),
      );
    for (final PowerFormula p in powerFormulas) {
      buf.writeln(<String>[p.system, p.apparent, p.real].join(tab));
    }
    buf
      ..writeln()
      ..writeln(powerFactorNote)
      ..writeln()
      ..writeln(relationsFootnote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

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
                  // The power wheel as the LARGE hero of the page (Keith,
                  // 2026-06-08): it fills the content width and a large share of
                  // screen height so the wheel dominates, above the formula
                  // tables — replacing the small recessed ConceptGraphicBand.
                  // Renders only when the SVG is bundled; otherwise the page
                  // reads fully on the wheel table below (graceful degradation).
                  // The wheel is roughly square, so it takes a slightly taller
                  // height fraction than a wide connector face.
                  LargeGraphic(
                    assetName: OhmsLawDiagrams.wheel,
                    path: OhmsLawDiagrams.path,
                    has: OhmsLawDiagrams.has,
                    heightFraction: 0.46,
                    maxHeight: 520,
                  ),
                  if (OhmsLawDiagrams.has(OhmsLawDiagrams.wheel))
                    const SizedBox(height: AppSpacing.md),
                  _relationsCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _wheelCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _powerCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'ohms-law'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _relationsCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Core relationships',
      footnote: relationsFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Relationship', width: 240),
          _HeaderCell('Formula', width: 120),
          _HeaderCell('Solves for', width: 120),
        ],
      ),
      rows: relations.map((OhmsRelation r) {
        return ReferenceRowSemantics(
          label: rowLabel(r.name, <String?>[
            'formula ${r.formula}',
            'solves for ${r.solvesFor}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 240,
                  child: Text(
                    r.name,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    r.formula,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    r.solvesFor,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
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

  Widget _wheelCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Power wheel (12 forms)',
      footnote: wheelFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Quantity', width: 96),
          _HeaderCell('Form 1', width: 104),
          _HeaderCell('Form 2', width: 104),
          _HeaderCell('Form 3', width: 120),
        ],
      ),
      rows: wheel.map((WheelRow w) {
        return ReferenceRowSemantics(
          label: rowLabel(w.quantity, <String?>[
            w.formA,
            w.formB,
            w.formC,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    w.quantity,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Text(
                    w.formA,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Text(
                    w.formB,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    w.formC,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
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

  Widget _powerCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Single-phase vs three-phase power',
      note: powerFactorNote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('System', width: 168),
          _HeaderCell('Apparent power (VA)', width: 184),
          _HeaderCell('Real power (W)', width: 240),
        ],
      ),
      rows: powerFormulas.map((PowerFormula p) {
        return ReferenceRowSemantics(
          label: rowLabel(p.system, <String?>[
            'apparent power ${p.apparent}',
            'real power ${p.real}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 168,
                  child: Text(
                    p.system,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 184,
                  child: Text(
                    p.apparent,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: Text(
                    p.real,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
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

/// Card surface wrapping a wide table: title over an optional note, then a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// power_phasing_screen / poe_reference_screen / wifi_channels_screen
/// overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.note,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? note;
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
          const SizedBox(height: AppSpacing.xs),
          HorizontalScrollTable(
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  header,
                  Divider(color: colors.border, height: AppSpacing.sm),
                  ...rows,
                ],
              ),
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note!,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
          if (footnote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              footnote!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// One column-header label, caption-styled to align with the data cells.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: colors.textTertiary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
