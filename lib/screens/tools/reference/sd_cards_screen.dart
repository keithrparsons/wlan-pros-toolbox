// SD and microSD Cards — read-only field reference for every mark on the card
// face. It belongs to the Toolbox's "decode the markings" family (Screw Drives,
// RJ Connectors, IEC / NEMA / International connectors) and follows that
// template rather than inventing one.
//
// The load-bearing content, and the reason the page exists:
//   1. ONLY ONE MARK MEASURES TWO THINGS. C, U, and V each set a minimum
//      sustained sequential WRITE floor and nothing else. A1 and A2 set that
//      same floor (10 MB/s, both) and add random 4 KB IOPS. A V90 card can be
//      poor at booting a Pi and an A2 card can drop frames.
//      CORRECTED 2026-07-27: this said "the two axes are orthogonal", refuted
//      against SD Physical Layer Simplified Spec v6.00 Sec 4.16.1.1/4.16.1.2 p.150.
//   2. A2 only delivers A2 if the HOST implements Command Queuing, and falls
//      back to A1 by design otherwise. This is why Raspberry Pi benchmarks keep
//      failing to show A2 beating A1. It is the most valuable single caveat on
//      the screen.
//   3. A1 and A2 cap sustained write at 10 MB/s, so an A2 card is no better than
//      V10 for video unless it separately carries a V mark.
//   4. The capacity mark is a FILESYSTEM contract, not just a size band. SDHC
//      means FAT32; SDXC and SDUC mean exFAT. That is what actually breaks
//      hosts.
//   5. V60 and V90 require UHS-II. A V60 card showing only a Roman I is marked
//      wrongly.
//
// Structure: typed const datasets in lib/data/sd_card_reference_data.dart (the
// screen only lays them out), a section-8.16 AppCopyAction that emits the whole
// page as sectioned TSV, the LayoutBuilder / ConstrainedBox /
// SingleChildScrollView scaffold every reference screen shares, named LARGE
// graphic slots rendered by the shared LargeGraphic primitive, and a
// ToolHelpFooter keyed on the catalog id.
//
// Graphic slots: resolved by explicit asset name through SdCardDiagrams (the
// manifest-gated resolver). Each degrades to nothing when its SVG is not yet
// bundled, so the page ships fully working as tables now; the hero card-face
// graphic is a later graphics pass. The callout numbers 1 to 7 in kSdCardMarks
// are the numbering that hero graphic uses, so the graphic and the list read as
// one object once it lands.
//
// Data provenance (GL-005): Pax's clean-room research brief,
// Deliverables/2026-07-25-battery-sd-reference/FINDINGS.md Part 2, which pulled
// every figure from the SD Physical Layer Simplified Specification v6.00 with
// section and page cited (the SD Association publishes its own class tables only
// as images). The brief's do-not-print item is honored: the SD Express maximum
// is printed as ~3.9 GB/s because the SD Association's web table and its own SD
// 9.1 white paper give two different numbers.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading / empty /
// error path because nothing is fetched or parsed at runtime; each graphic slot
// carries its own absent-asset empty state (render nothing). The counterfeit
// section NAMES external tools (h2testw, f3write, f3read, f3probe) as something
// the reader runs on a computer; the app never spawns them, so GL-008's
// no-subprocess rule is not engaged.
//
// Glyph / copy notes (GL-004): ASCII hyphen-minus only, never an em dash or an
// en dash; US spelling; "Wi-Fi" never "WiFi"; conclusion first; no marketing
// words.

import 'package:flutter/material.dart';

import '../../../data/sd_card_diagrams.dart';
import '../../../data/sd_card_reference_data.dart';
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

/// SD and microSD card reference. Route `/tools/sd-cards`, catalog id
/// [kSdCardsToolId].
class SdCardsScreen extends StatelessWidget {
  const SdCardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SD & microSD Cards'),
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
      ..writeln('SD & microSD Cards (field reference)')
      ..writeln()
      ..writeln(kSdLead)
      ..writeln()
      ..writeln('The seven marks')
      ..writeln(<String>['#', 'Mark', 'What it measures'].join(tab));
    for (final SdCardMark m in kSdCardMarks) {
      buf.writeln(<String>['${m.number}', m.mark, m.measures].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kMarketingReadCaution)
      ..writeln()
      ..writeln('Capacity standard and the filesystem it specifies')
      ..writeln(<String>['Mark', 'Capacity', 'Filesystem'].join(tab));
    for (final SdCapacityStandard c in kSdCapacityStandards) {
      buf.writeln(<String>[c.mark, c.capacity, c.filesystem].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kFilesystemContract)
      ..writeln()
      ..writeln('Bus interface')
      ..writeln(<String>['Mark', 'Bus', 'Ceiling'].join(tab));
    for (final SdBusInterface b in kSdBusInterfaces) {
      buf.writeln(<String>[b.mark, b.name, b.ceiling].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kSdExpressCaution)
      ..writeln(kSecondPinRow)
      ..writeln(kUhsIiInUhsISlot)
      ..writeln(kV60RequiresUhsIi)
      ..writeln()
      ..writeln('Sustained sequential write classes')
      ..writeln(<String>['Mark', 'Minimum sustained write', 'Note'].join(tab));
    for (final SdSpeedClass s in kSdSpeedClasses) {
      buf.writeln(<String>[s.mark, s.floor, s.note].join(tab));
    }
    buf
      ..writeln()
      ..writeln(kVNumberReadsDirectly)
      ..writeln(kRedundantMarks)
      ..writeln(kClassesAreOptional)
      ..writeln()
      ..writeln('Application Performance Class (random 4 KB IOPS)')
      ..writeln(
        <String>[
          'Mark',
          'Random read',
          'Random write',
          'Sustained write',
        ].join(tab),
      );
    for (final SdAppPerformanceClass a in kSdAppClasses) {
      buf.writeln(
        <String>[a.mark, a.randomRead, a.randomWrite, a.sustainedWrite]
            .join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(kA2NeedsCommandQueuing)
      ..writeln(kA2IsNotAVideoCard)
      ..writeln()
      ..writeln('Reading order for a buyer');
    for (final SdReadingStep s in kSdReadingOrder) {
      buf.writeln('${s.step}: ${s.what}');
    }
    buf
      ..writeln()
      ..writeln('Selection by job')
      ..writeln(
        <String>['Job', 'What governs it', 'Read', 'Ignore'].join(tab),
      );
    for (final SdJobSelection j in kSdJobSelections) {
      buf.writeln(
        <String>[j.job, j.governs, j.read, j.ignore].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Endurance')
      ..writeln(kEnduranceProblem)
      ..writeln(kEnduranceTbw)
      ..writeln()
      ..writeln('Counterfeits')
      ..writeln(kCounterfeitMechanism);
    for (final CounterfeitBehavior c in kCounterfeitBehaviors) {
      buf.writeln('${c.name}: ${c.what}');
    }
    buf
      ..writeln(kCounterfeitAntiPattern)
      ..writeln(kCounterfeitTest)
      ..writeln()
      ..writeln('The write-protect notch')
      ..writeln(kWriteProtectNotch);
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
                  ReferenceLead(text: kSdLead),
                  const SizedBox(height: AppSpacing.lg),

                  // (a) The card face — hero graphic slot plus the seven marks.
                  const ReferenceSectionHeading(label: 'The seven marks'),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: SdCardDiagrams.cardFace,
                    path: SdCardDiagrams.path,
                    has: SdCardDiagrams.has,
                  ),
                  if (SdCardDiagrams.has(SdCardDiagrams.cardFace))
                    const SizedBox(height: AppSpacing.md),
                  _MarksCard(),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'The headline MB/s is not a class',
                    body: kMarketingReadCaution,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (b) Capacity standard = filesystem contract.
                  const ReferenceSectionHeading(
                    label: 'Capacity standard',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _CapacityCard(),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'It fails on exFAT, not on capacity',
                    body: kFilesystemContract,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (c) Bus interface, the ceiling.
                  const ReferenceSectionHeading(label: 'Bus interface'),
                  const SizedBox(height: AppSpacing.sm),
                  _BusCard(),
                  const SizedBox(height: AppSpacing.xs),
                  _Footnote(text: kSdExpressCaution),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: SdCardDiagrams.contactRows,
                    path: SdCardDiagrams.path,
                    has: SdCardDiagrams.has,
                  ),
                  if (SdCardDiagrams.has(SdCardDiagrams.contactRows))
                    const SizedBox(height: AppSpacing.md),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'What the second row of pins is',
                    body: kSecondPinRow,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'A UHS-II card in a UHS-I slot runs UHS-I',
                    body: kUhsIiInUhsISlot,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'V60 and V90 require UHS-II',
                    body: kV60RequiresUhsIi,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (d) The two axes: sustained write, then IOPS.
                  const ReferenceSectionHeading(
                    label: 'Sustained write classes',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SpeedClassCard(),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'The V number is the MB/s floor',
                    body: kVNumberReadsDirectly,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _Footnote(text: kRedundantMarks),
                  const SizedBox(height: AppSpacing.xs),
                  _Footnote(text: kClassesAreOptional),
                  const SizedBox(height: AppSpacing.lg),

                  const ReferenceSectionHeading(
                    label: 'Application Performance Class',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: SdCardDiagrams.twoAxis,
                    path: SdCardDiagrams.path,
                    has: SdCardDiagrams.has,
                  ),
                  if (SdCardDiagrams.has(SdCardDiagrams.twoAxis))
                    const SizedBox(height: AppSpacing.md),
                  _AppClassCard(),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.danger,
                    heading: 'A2 needs Command Queuing in the host',
                    body: kA2NeedsCommandQueuing,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'An A2 card is not a video card',
                    body: kA2IsNotAVideoCard,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (e) Reading order and selection by job.
                  const ReferenceSectionHeading(
                    label: 'Reading order for a buyer',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ReadingOrderCard(),
                  const SizedBox(height: AppSpacing.sm),
                  _JobSelectionCard(),
                  const SizedBox(height: AppSpacing.lg),

                  // (f) Endurance.
                  const ReferenceSectionHeading(label: 'Endurance'),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.warning,
                    heading: 'Hours at an unstated bitrate',
                    body: kEnduranceProblem,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'TBW is the comparable number',
                    body: kEnduranceTbw,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (g) Counterfeits.
                  const ReferenceSectionHeading(label: 'Counterfeits'),
                  const SizedBox(height: AppSpacing.sm),
                  _CounterfeitCard(),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.danger,
                    heading: 'A counterfeit passes every quick test',
                    body: kCounterfeitAntiPattern,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'Fill it and read every byte back',
                    body: kCounterfeitTest,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (h) The write-protect notch.
                  const ReferenceCallout(
                    tone: ReferenceCalloutTone.info,
                    heading: 'The card cannot see the write-protect switch',
                    body: kWriteProtectNotch,
                  ),
                  ToolHelpFooter(toolId: kSdCardsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────────── the seven marks ──────────────────────────────

/// The seven marks, numbered to match the hero card-face graphic callouts.
class _MarksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ReferenceCard(
      heading: 'What each mark on the face measures',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final SdCardMark m in kSdCardMarks)
            ReferenceRowSemantics(
              label: rowLabel('Mark ${m.number}, ${m.mark}', <String?>[
                m.measures,
              ]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: AppSpacing.md,
                      child: Text(
                        '${m.number}',
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            m.mark,
                            style: text.bodyLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            m.measures,
                            style: text.labelMedium?.copyWith(
                              color: colors.textSecondary,
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

// ──────────────────────────── capacity standard ─────────────────────────────

const double _kCapMarkW = 120;
const double _kCapSizeW = 148;
const double _kCapFsW = 168;

/// The capacity ladder with the filesystem the standard specifies.
class _CapacityCard extends StatelessWidget {
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
      heading: 'The filesystem column is the one that bites',
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
                      width: _kCapMarkW,
                      child: Text('Mark', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kCapSizeW,
                      child: Text('Capacity', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kCapFsW,
                      child: Text('Filesystem', style: header),
                    ),
                  ],
                ),
              ),
              for (final SdCapacityStandard c in kSdCapacityStandards)
                ReferenceRowSemantics(
                  label: rowLabel(c.mark, <String?>[
                    c.capacity,
                    'filesystem ${c.filesystem}',
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kCapMarkW,
                          child: Text(
                            c.mark,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kCapSizeW,
                          child: Text(
                            c.capacity,
                            style: text.labelMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kCapFsW,
                          child: Text(
                            c.filesystem,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
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

// ────────────────────────────── bus interface ───────────────────────────────

const double _kBusMarkW = 72;
const double _kBusNameW = 132;
const double _kBusCeilW = 260;

/// The bus ladder.
class _BusCard extends StatelessWidget {
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
      heading: 'The ceiling. No class can exceed it',
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
                      width: _kBusMarkW,
                      child: Text('Face', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kBusNameW,
                      child: Text('Bus', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kBusCeilW,
                      child: Text('Ceiling', style: header),
                    ),
                  ],
                ),
              ),
              for (final SdBusInterface b in kSdBusInterfaces)
                ReferenceRowSemantics(
                  label: rowLabel(b.name, <String?>[
                    'marked ${b.mark}',
                    'ceiling ${b.ceiling}',
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kBusMarkW,
                          child: Text(
                            b.mark,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kBusNameW,
                          child: Text(
                            b.name,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kBusCeilW,
                          child: Text(
                            b.ceiling,
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

// ─────────────────────────── sustained-write classes ────────────────────────

const double _kClassMarkW = 190;
const double _kClassFloorW = 168;
const double _kClassNoteW = 340;

/// The three sustained-write families in one table.
class _SpeedClassCard extends StatelessWidget {
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
      heading: 'All three measure minimum sustained sequential write',
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
                      width: _kClassMarkW,
                      child: Text('Mark', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kClassFloorW,
                      child: Text('Floor', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kClassNoteW,
                      child: Text('Note', style: header),
                    ),
                  ],
                ),
              ),
              for (final SdSpeedClass s in kSdSpeedClasses)
                ReferenceRowSemantics(
                  label: rowLabel(s.mark, <String?>[
                    'minimum sustained write ${s.floor}',
                    s.note,
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kClassMarkW,
                          child: Text(
                            s.mark,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kClassFloorW,
                          child: Text(
                            s.floor,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kClassNoteW,
                          child: Text(
                            s.note,
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

// ─────────────────────── application performance class ──────────────────────

const double _kAppMarkW = 72;
const double _kAppColW = 148;

/// The A1 / A2 table, quoted from the spec.
class _AppClassCard extends StatelessWidget {
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
      heading: 'Random 4 KB IOPS, on top of the same write floor',
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
                      width: _kAppMarkW,
                      child: Text('Mark', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kAppColW,
                      child: Text('Random read', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kAppColW,
                      child: Text('Random write', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kAppColW,
                      child: Text('Sustained write', style: header),
                    ),
                  ],
                ),
              ),
              for (final SdAppPerformanceClass a in kSdAppClasses)
                ReferenceRowSemantics(
                  label: rowLabel(a.mark, <String?>[
                    'random read ${a.randomRead}',
                    'random write ${a.randomWrite}',
                    'sustained write ${a.sustainedWrite}',
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kAppMarkW,
                          child: Text(
                            a.mark,
                            style: mono.inlineCode.copyWith(
                              color: colors.textAccent,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kAppColW,
                          child: Text(
                            a.randomRead,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kAppColW,
                          child: Text(
                            a.randomWrite,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kAppColW,
                          child: Text(
                            a.sustainedWrite,
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

// ───────────────────────── reading order + job table ────────────────────────

/// The four-step buying read.
class _ReadingOrderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceCard(
      heading: 'In this order',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final SdReadingStep s in kSdReadingOrder)
            ReferenceRowSemantics(
              label: '${s.step}. ${s.what}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.step,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      s.what,
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
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

const double _kJobW = 200;
const double _kGovernsW = 300;
const double _kReadW = 300;
const double _kIgnoreW = 168;

/// Selection by job, with the reasoning rather than only the answer.
class _JobSelectionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? header = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return ReferenceCard(
      heading: 'Selection by job',
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: <Widget>[
                    ReferenceTableCell(width: _kJobW, child: Text('Job', style: header)),
                    ReferenceTableCell(
                      width: _kGovernsW,
                      child: Text('What governs it', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kReadW,
                      child: Text('Read', style: header),
                    ),
                    ReferenceTableCell(
                      width: _kIgnoreW,
                      child: Text('Ignore', style: header),
                    ),
                  ],
                ),
              ),
              for (final SdJobSelection j in kSdJobSelections)
                ReferenceRowSemantics(
                  label: rowLabel(j.job, <String?>[
                    j.governs,
                    'read ${j.read}',
                    'ignore ${j.ignore}',
                  ]),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceTableCell(
                          width: _kJobW,
                          child: Text(
                            j.job,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kGovernsW,
                          child: Text(
                            j.governs,
                            style: text.labelMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kReadW,
                          child: Text(
                            j.read,
                            style: text.labelMedium?.copyWith(
                              color: colors.textAccent,
                            ),
                          ),
                        ),
                        ReferenceTableCell(
                          width: _kIgnoreW,
                          child: Text(
                            j.ignore,
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

// ───────────────────────────── counterfeit card ─────────────────────────────

/// How a fake is built and the two ways it fails past the real capacity.
class _CounterfeitCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceCard(
      heading: 'What a counterfeit card is',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            kCounterfeitMechanism,
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final CounterfeitBehavior c in kCounterfeitBehaviors)
            ReferenceRowSemantics(
              label: '${c.name}. ${c.what}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      c.name,
                      style: text.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      c.what,
                      style: text.labelMedium?.copyWith(
                        color: colors.textSecondary,
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

// ───────────────────────────── small helpers ────────────────────────────────

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
