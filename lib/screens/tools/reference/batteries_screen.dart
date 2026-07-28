// Batteries — read-only field reference for the cell types, sizes, chemistries,
// and codes a Wi-Fi engineer meets on sensors, testers, controllers, and gear.
// It belongs to the Toolbox's "decode the markings" family (Screw Drives, RJ
// Connectors, IEC / NEMA / International connectors) and follows that template
// rather than inventing one.
//
// The load-bearing content, and the reason the page exists:
//   1. The round-cell code DECODES and the button-cell catalog number DOES NOT,
//      and both conventions live in the same IEC 60086-2:2021 Clause 7 block.
//      CR2032 genuinely is 20.00 mm by 3.20 mm. LR44 is catalog entry 44.
//      Everyone teaches only the first half.
//   2. The diameter group is a FLOOR (whole millimeters, truncated) and the
//      height group is EXACT (tenths of a millimeter). Two digits of height
//      means a coin; three means a cylinder. The code truncates; the part does
//      not, which is why a code and a datasheet can disagree on diameter and
//      both be right. Four retracted claims were removed from this page on
//      2026-07-25; see the retraction block in battery_reference_data.dart.
//   3. The doubled letter means SMALLER. The ladder ran N, AAAA, AAA, AA, A, B,
//      C, D, so AA is smaller than A. A and B left retail; they did not vanish.
//   4. LR44 against SR44: same 11.60 mm by 5.40 mm can, 1.5 V sloping against
//      1.55 V flat. Silver oxide substitutes into an alkaline slot safely; the
//      reverse drifts a precision instrument as it sags.
//   5. The 1.5 V against 1.2 V gotcha, framed correctly: the real problem is
//      that a voltage-based fuel gauge cannot read a flat NiMH curve, not that
//      the device will not run.
//
// Structure: typed const datasets in lib/data/battery_reference_data.dart (the
// screen only lays them out), a section-8.16 AppCopyAction that emits the whole
// page as sectioned TSV, the LayoutBuilder / ConstrainedBox /
// SingleChildScrollView scaffold every reference screen shares, named LARGE
// graphic slots rendered by the shared LargeGraphic primitive, and a
// ToolHelpFooter keyed on the catalog id.
//
// Graphic slots: resolved by explicit asset name through BatteryDiagrams (the
// manifest-gated resolver). Each degrades to nothing when its SVG is not yet
// bundled, so the page ships fully working as tables now; the hero exploded-code
// graphic is a later graphics pass.
//
// Data provenance (GL-005): Pax's clean-room research brief,
// Deliverables/2026-07-25-battery-sd-reference/FINDINGS.md Part 1. The brief's
// do-not-print list is honored in the data file and repeated here so a future
// edit does not quietly reintroduce any of it:
//   * AA 1907 / AAA 1911 introduction dates: UNVERIFIED. Absent.
//   * "B was skipped to avoid the radio B battery": FOLKLORE. Absent. The
//     distinction between the two senses of "B battery" is solid and IS shown.
//   * 1.5 V USB-C rechargeable Li-ion AA: no standards designation, no usable
//     datasheet. Prose caution with NO numbers.
//   * No bare capacity number. Capacity is load-dependent and is labeled so.
//
// Safety copy: the button-cell ingestion mechanism is stated as electrolysis
// generating hydroxide and causing liquefactive necrosis, with a new fully
// charged cell the most dangerous. It is NOT described as a leak and NOT as
// choking. That wording is load-bearing and is asserted by the widget test.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading / empty /
// error path because nothing is fetched or parsed at runtime; each graphic slot
// carries its own absent-asset empty state (render nothing). GL-008 network and
// subprocess rules do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): ASCII hyphen-minus only, never an em dash or an
// en dash; US spelling; "Wi-Fi" never "WiFi"; conclusion first; no marketing
// words.

import 'package:flutter/material.dart';

import '../../../data/battery_diagrams.dart';
import '../../../data/battery_reference_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_callout.dart';
import 'reference_row_semantics.dart';
import 'reference_section.dart';

/// Batteries reference. Route `/tools/batteries`, catalog id
/// [kBatteriesToolId].
class BatteriesScreen extends StatelessWidget {
  const BatteriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Batteries'),
        toolbarHeight: 64,
        // Section 8.16 — copy the whole page as sectioned TSV. Static data, so
        // the action is always enabled and the builder is always non-null.
        actions: <Widget>[
          AppCopyAction(textBuilder: buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// Section 8.16 copy payload — the full page as sectioned TSV. Public so the
  /// widget test asserts the same string the copy button emits.
  @visibleForTesting
  static String buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Batteries (field reference)')
      ..writeln()
      ..writeln(kBatteryLead)
      ..writeln()
      ..writeln('Reading the code')
      ..writeln(kCoinCodeRule)
      ..writeln(kCodeRoundsPartDoesNot)
      ..writeln(kHeightGroupRule)
      ..writeln(kButtonCodeRule)
      ..writeln()
      ..writeln(<String>[
        'Code',
        'Reads as',
        'What the code says',
        'What the part measures',
        'Dimensional?',
      ].join(tab));
    for (final CellCode c in kCellCodes) {
      buf.writeln(
        <String>[
          c.code,
          c.reads,
          c.meaning,
          c.datasheet,
          c.dimensional ? 'Yes' : 'No, catalog number',
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('The size ladder')
      ..writeln(kSizeLadderRule)
      ..writeln()
      ..writeln(<String>['Size', 'Dimensions', 'Where you meet it', 'Source']
          .join(tab));
    for (final BatterySizeRung r in kBatterySizeRungs) {
      buf.writeln(
        <String>[
          r.size,
          r.dimensions ?? kNoDatasheetDimension,
          r.status,
          r.pin,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('IEC 60086-2:2021 Clause 7, round single cells:')
      ..writeln(kIecRoundSingleCellList)
      ..writeln(kIecMissingSizes)
      ..writeln(kTwoSensesOfB)
      ..writeln()
      ..writeln('The two naming systems')
      ..writeln(<String>['System', 'Shape of the code', 'AA alkaline'].join(tab));
    for (final NamingSystem n in kNamingSystems) {
      buf.writeln(<String>[n.system, n.shape, n.aaAlkaline].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kOneCodePerSizeIsWrong)
      ..writeln(kNineVoltNote)
      ..writeln()
      ..writeln('Chemistry letters (IEC 60086-1:2021, 4.1.4 Table 1)')
      ..writeln(
        <String>['Letter', 'System', 'Nominal', 'Max OCV'].join(tab),
      );
    for (final ChemistryLetter c in kChemistryLetters) {
      buf.writeln(
        <String>[c.letter, c.system, c.nominal, c.maxOcv].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Rechargeables (IEC 61951 / 61960)');
    for (final ChemistryLetter c in kRechargeableLetters) {
      buf.writeln(
        <String>[c.letter, c.system, c.nominal, c.maxOcv].join(tab),
      );
    }
    buf
      ..writeln(kRechargeableNote)
      ..writeln()
      ..writeln('LR44 against SR44')
      ..writeln(<String>['Property', 'LR44 (alkaline)', 'SR44 (silver oxide)']
          .join(tab));
    for (final SubstitutionRow s in kLr44VsSr44) {
      buf.writeln(<String>[s.property, s.alkaline, s.silver].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Same can, alkaline: $kLr44CrossReference')
      ..writeln('Same can, silver oxide: $kSr44CrossReference')
      ..writeln(kAg13Caveat)
      ..writeln(k357Vs303)
      ..writeln(kMercuryTrap)
      ..writeln()
      ..writeln('1.5 V against 1.2 V')
      ..writeln(kVoltageGotchaLead);
    for (final VoltageGotcha g in kVoltageGotchas) {
      buf.writeln('${g.heading}: ${g.detail}');
    }
    buf
      ..writeln(kLithiumOverVoltage)
      ..writeln()
      ..writeln('Button cell ingestion')
      ..writeln(kIngestionMechanism)
      ..writeln(kIngestionFreshCellIsWorst)
      ..writeln(kIngestionTiming)
      ..writeln(kIngestionHotline)
      ..writeln(kReesesLaw)
      ..writeln()
      ..writeln('Air travel')
      ..writeln(kAirTravelRule)
      ..writeln(kAirTravelTerminals)
      ..writeln()
      ..writeln('Where a Wi-Fi engineer meets these')
      ..writeln(<String>['Where', 'Cell', 'Why'].join(tab));
    for (final BatteryFieldUse f in kBatteryFieldUses) {
      buf.writeln(<String>[f.where, f.cell, f.why].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kCapacityCaution)
      ..writeln(kUsbCRechargeableCaution);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
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
                  ReferenceLead(text: kBatteryLead),
                  const SizedBox(height: AppSpacing.lg),

                  // (a) Reading the code — the hero graphic slot, the split
                  // convention, and the worked examples.
                  const ReferenceSectionHeading(label: 'Reading the code'),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: BatteryDiagrams.codeExploded,
                    path: BatteryDiagrams.path,
                    has: BatteryDiagrams.has,
                  ),
                  if (BatteryDiagrams.has(BatteryDiagrams.codeExploded))
                    const SizedBox(height: AppSpacing.md),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'Round-cell codes decode',
                    body: kCoinCodeRule,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'The code truncates; the part does not',
                    body: kCodeRoundsPartDoesNot,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'Two digits of height is a coin, three is a cylinder',
                    body: kHeightGroupRule,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'Button cells do not decode',
                    body: kButtonCodeRule,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _CellCodeCard(),
                  const SizedBox(height: AppSpacing.lg),

                  // (b) The size ladder.
                  const ReferenceSectionHeading(label: 'The size ladder'),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: BatteryDiagrams.sizeLadder,
                    path: BatteryDiagrams.path,
                    has: BatteryDiagrams.has,
                  ),
                  if (BatteryDiagrams.has(BatteryDiagrams.sizeLadder))
                    const SizedBox(height: AppSpacing.md),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'AA is smaller than A',
                    body: kSizeLadderRule,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _SizeRungCard(),
                  const SizedBox(height: AppSpacing.sm),
                  ReferenceCard(
                    heading: 'What the standard lists',
                    child: _StandardListBlock(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'Two unrelated things called a B battery',
                    body: kTwoSensesOfB,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (c) The two naming systems.
                  const ReferenceSectionHeading(label: 'Naming systems'),
                  const SizedBox(height: AppSpacing.sm),
                  _NamingSystemCard(),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'One code per size is wrong',
                    body: kOneCodePerSizeIsWrong,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'Reading the 9 V block',
                    body: kNineVoltNote,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (d) Chemistry letters.
                  const ReferenceSectionHeading(label: 'Chemistry letters'),
                  const SizedBox(height: AppSpacing.sm),
                  _ChemistryCard(
                    heading: 'Primary cells (IEC 60086-1:2021, 4.1.4 Table 1)',
                    rows: kChemistryLetters,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ChemistryCard(
                    heading: 'Rechargeables (IEC 61951 / 61960)',
                    rows: kRechargeableLetters,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _Footnote(text: kRechargeableNote),
                  const SizedBox(height: AppSpacing.lg),

                  // (e) LR44 against SR44 — the equivalence trap.
                  const ReferenceSectionHeading(
                    label: 'LR44 against SR44',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _SubstitutionCard(),
                  const SizedBox(height: AppSpacing.sm),
                  ReferenceCard(
                    heading: 'Same can, many names',
                    child: _CrossReferenceBlock(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'AG13 is not a specification',
                    body: kAg13Caveat,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: '357 and 303 split on drain rate',
                    body: k357Vs303,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'The mercury trap',
                    body: kMercuryTrap,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (f) The 1.5 V against 1.2 V gotcha.
                  const ReferenceSectionHeading(
                    label: '1.5 V against 1.2 V',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: BatteryDiagrams.dischargeCurves,
                    path: BatteryDiagrams.path,
                    has: BatteryDiagrams.has,
                  ),
                  if (BatteryDiagrams.has(BatteryDiagrams.dischargeCurves))
                    const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    heading: 'Where the shortfall bites',
                    child: _VoltageGotchaBlock(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'The opposite trap: lithium runs high',
                    body: kLithiumOverVoltage,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (g) Safety. Danger tone: this is the one section on the page
                  // where getting the mechanism wrong would be a defect.
                  const ReferenceSectionHeading(label: 'Button cell safety'),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.danger,
                    heading: 'How a swallowed cell injures',
                    body: kIngestionMechanism,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.danger,
                    heading: 'A new cell is the dangerous one',
                    body: kIngestionFreshCellIsWorst,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ReferenceCard(
                    heading: 'What to do, and how fast',
                    child: _SafetyBlock(),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (h) Air travel.
                  const ReferenceSectionHeading(label: 'Air travel'),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'Spare lithium cells fly in the cabin',
                    body: kAirTravelRule,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'The hazard is a short circuit',
                    body: kAirTravelTerminals,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (i) The field slant.
                  const ReferenceSectionHeading(
                    label: 'Where a Wi-Fi engineer meets these',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _FieldUseCard(),
                  const SizedBox(height: AppSpacing.lg),

                  // (j) The two standing cautions.
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'Capacity is load-dependent',
                    body: kCapacityCaution,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'The USB-C rechargeable AA',
                    body: kUsbCRechargeableCaution,
                  ),
                  ToolHelpFooter(toolId: kBatteriesToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── code examples table ──────────────────────────────

/// The worked code examples. Full-width rows: the meaning column is a sentence,
/// so it wraps rather than scrolling horizontally.
class _CellCodeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ReferenceCard(
      heading: 'Worked examples',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final CellCode c in kCellCodes) _CellCodeRow(code: c),
        ],
      ),
    );
  }
}

/// One worked code row: the code in mono, a dimensional / catalog badge, then
/// the split and the meaning beneath.
class _CellCodeRow extends StatelessWidget {
  const _CellCodeRow({required this.code});

  final CellCode code;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceRowSemantics(
      label: rowLabel(code.code, <String?>[
        code.dimensional ? 'dimensional code' : 'catalog number, not dimensions',
        'reads as ${code.reads}',
        'the code says ${code.meaning}',
        'the part measures: ${code.datasheet}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    code.code,
                    style: mono.outputMedium.copyWith(
                      color: colors.textAccent,
                    ),
                  ),
                ),
                _Badge(
                  label: code.dimensional ? 'Dimensional' : 'Catalog number',
                  tone: code.dimensional
                      ? ReferenceCalloutTone.info
                      : ReferenceCalloutTone.warning,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Reads as ${code.reads}',
              style: mono.inlineCode.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            // What the CODE says. Labeled, because the line beneath it is a
            // different quantity and an unlabeled pair reads as a contradiction.
            _QuantityLine(
              label: 'The code says',
              value: code.meaning,
              emphasis: true,
            ),
            const SizedBox(height: AppSpacing.xxs),
            // What the PART measures. The two disagree on diameter by design.
            _QuantityLine(label: 'The part measures', value: code.datasheet),
          ],
        ),
      ),
    );
  }
}

/// A tertiary-ink label over a value, used where two adjacent numbers are
/// different KINDS of number and the reader has to be told which is which.
class _QuantityLine extends StatelessWidget {
  const _QuantityLine({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          value,
          style: emphasis
              ? text.bodyMedium?.copyWith(color: colors.textPrimary)
              : text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ─────────────────────────── size ladder table ──────────────────────────────

// Fixed cell widths for the horizontally-scrolled size grid. Constant so the
// header and every data row align column-for-column, and so the grid never
// RenderFlex-overflows at 320pt (it scrolls horizontally instead).
const double _kSizeW = 72;
const double _kDimW = 176;
// The source line sits UNDER the status text rather than in a fourth column.
// A fourth column pushed the table to 828pt, which is wider than the clamp at
// every breakpoint, so the pin would have been the one cell that is always off
// the right edge behind a horizontal scroll. A citation nobody can see without
// discovering a scroll gesture is not a citation.
const double _kStatusW = 320;

/// The size rungs that have a sourced dimension.
class _SizeRungCard extends StatelessWidget {
  const _SizeRungCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle? header = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return ReferenceCard(
      heading: 'The rungs with a sourced dimension',
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    ReferenceTableCell(width: _kSizeW, child: Text('Size', style: header)),
                    ReferenceTableCell(
                      width: _kDimW,
                      child: Text('Dimensions', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kStatusW,
                      child: Text('Where you meet it, and the source', style: header),
                    ),
                  ],
                ),
              ),
              for (final BatterySizeRung r in kBatterySizeRungs)
                ReferenceRowSemantics(
                  label: rowLabel(r.size, <String?>[
                    r.dimensions ?? 'dimension unavailable, no datasheet',
                    r.status,
                    r.pin,
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kSizeW,
                          child: Text(
                            r.size,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kDimW,
                          // The honest-unavailable state. A null dimension is
                          // rendered as words in muted ink, never as a number
                          // and never as a blank cell: a blank reads as an
                          // oversight, and this absence is the finding.
                          child: r.dimensions == null
                              ? Text(
                                  kNoDatasheetDimension,
                                  style: text.labelMedium?.copyWith(
                                    color: colors.textTertiary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Text(
                                  r.dimensions!,
                                  style: mono.inlineCode.copyWith(
                                    color: colors.textAccent,
                                  ),
                                ),
                        ),
                        ReferenceTableCell(
                          width: _kStatusW,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                r.status,
                                style: text.labelMedium?.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                r.pin,
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
        ),
      ),
    );
  }
}

/// The verbatim standard list plus what is missing from it.
class _StandardListBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Round single cells, IEC 60086-2:2021 Clause 7:',
          style: text.labelMedium?.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          kIecRoundSingleCellList,
          style: mono.inlineCode.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          kIecMissingSizes,
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

// ────────────────────────── naming systems table ────────────────────────────

/// The ANSI / NEDA against IEC 60086 comparison.
class _NamingSystemCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceCard(
      heading: 'Two systems, which disagree by design',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final NamingSystem n in kNamingSystems)
            ReferenceRowSemantics(
              label: rowLabel(n.system, <String?>[
                n.shape,
                'an alkaline AA is ${n.aaAlkaline}',
              ]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            n.system,
                            style: text.bodyLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          n.aaAlkaline,
                          style: mono.inlineCode.copyWith(
                            color: colors.textAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      n.shape,
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The right column is what an alkaline AA is called in each system.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────── chemistry letters table ───────────────────────────

// Fixed cell widths for the horizontally-scrolled chemistry grid.
const double _kLetterW = 72;
const double _kSystemW = 260;
const double _kNominalW = 108;
const double _kOcvW = 132;

/// One chemistry table (primaries or rechargeables).
class _ChemistryCard extends StatelessWidget {
  const _ChemistryCard({required this.heading, required this.rows});

  final String heading;
  final List<ChemistryLetter> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle? header = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return ReferenceCard(
      heading: heading,
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    ReferenceTableCell(
                      width: _kLetterW,
                      child: Text('Letter', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kSystemW,
                      child: Text('System', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kNominalW,
                      child: Text('Nominal', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kOcvW,
                      child: Text('Max OCV', style: header),
                    ),
                  ],
                ),
              ),
              for (final ChemistryLetter c in rows)
                ReferenceRowSemantics(
                  label: rowLabel(c.letter, <String?>[
                    c.system,
                    'nominal ${c.nominal}',
                    'maximum open circuit ${c.maxOcv}',
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kLetterW,
                          child: Text(
                            c.letter,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kSystemW,
                          child: Text(
                            c.system,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kNominalW,
                          child: Text(
                            c.nominal,
                            style: mono.inlineCode.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kOcvW,
                          child: Text(
                            c.maxOcv,
                            style: text.labelMedium?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────── LR44 against SR44 table ───────────────────────────

const double _kPropW = 148;
const double _kCellColW = 240;

/// The property-by-property comparison of the two cells that share a can.
class _SubstitutionCard extends StatelessWidget {
  const _SubstitutionCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? header = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return ReferenceCard(
      heading: 'Same 11.60 mm by 5.40 mm can, different battery',
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    ReferenceTableCell(width: _kPropW, child: Text('', style: header)),
                    ReferenceTableCell(
                      width: _kCellColW,
                      child: Text('LR44 (alkaline)', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kCellColW,
                      child: Text('SR44 (silver oxide)', style: header),
                    ),
                  ],
                ),
              ),
              for (final SubstitutionRow s in kLr44VsSr44)
                ReferenceRowSemantics(
                  label: rowLabel(s.property, <String?>[
                    'LR44 alkaline ${s.alkaline}',
                    'SR44 silver oxide ${s.silver}',
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kPropW,
                          child: Text(
                            s.property,
                            style: text.labelMedium?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kCellColW,
                          child: Text(
                            s.alkaline,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kCellColW,
                          child: Text(
                            s.silver,
                            style: text.bodyMedium?.copyWith(
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
        ),
      ),
    );
  }
}

/// The two cross-reference lists.
class _CrossReferenceBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const <Widget>[
        _LabeledMonoLine(
          label: 'Alkaline (LR44 family)',
          value: kLr44CrossReference,
        ),
        SizedBox(height: AppSpacing.xs),
        _LabeledMonoLine(
          label: 'Silver oxide (SR44 family)',
          value: kSr44CrossReference,
        ),
      ],
    );
  }
}

/// A tertiary label over a mono value list.
class _LabeledMonoLine extends StatelessWidget {
  const _LabeledMonoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: mono.inlineCode.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── voltage gotcha block ─────────────────────────────

/// The lead plus the four consequences.
class _VoltageGotchaBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          kVoltageGotchaLead,
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final VoltageGotcha g in kVoltageGotchas)
          ReferenceRowSemantics(
            label: '${g.heading}. ${g.detail}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    g.heading,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    g.detail,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ────────────────────────────── safety block ────────────────────────────────

/// The timing, the hotline, and the rule that changed the hardware.
class _SafetyBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          kIngestionTiming,
          style: text.bodyMedium?.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          container: true,
          label: kIngestionHotline,
          excludeSemantics: true,
          child: Text(
            kIngestionHotline,
            style: mono.inlineCode.copyWith(
              color: colors.statusDanger,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          kReesesLaw,
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ──────────────────────────── field use table ───────────────────────────────

const double _kWhereW = 260;
const double _kCellW = 200;
const double _kWhyW = 340;

/// Where a Wi-Fi engineer actually meets each cell.
class _FieldUseCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle? header = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return ReferenceCard(
      heading: 'Cell, and why that cell',
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    ReferenceTableCell(
                      width: _kWhereW,
                      child: Text('Where', style: header),
                    ),
                    ReferenceTableCell(width: _kCellW, child: Text('Cell', style: header)),
                    ReferenceTableCell(width: _kWhyW, child: Text('Why', style: header)),
                  ],
                ),
              ),
              for (final BatteryFieldUse f in kBatteryFieldUses)
                ReferenceRowSemantics(
                  label: rowLabel(f.where, <String?>[f.cell, f.why]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kWhereW,
                          child: Text(
                            f.where,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kCellW,
                          child: Text(
                            f.cell,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kWhyW,
                          child: Text(
                            f.why,
                            style: text.labelMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── small helpers ────────────────────────────────

/// A small pill badge carrying a one-word classification, tinted by tone. Never
/// color alone: the badge WORD carries the meaning.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final ReferenceCalloutTone tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Text(
        label,
        style: mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: tone.color(colors),
        ),
      ),
    );
  }
}

/// A tertiary-ink footnote beneath a card.
class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.labelMedium?.copyWith(color: colors.textTertiary),
    );
  }
}
