// Screw Drives & Driver Bits — read-only field reference for the drive types a
// network/AP installer meets on APs, enclosures, brackets, racks, and outdoor
// gear. Recognition plus the right bit: a dozen drive FACES and the matching
// bit, with two things that actually cost field time pulled out as the page's
// load-bearing content:
//   1. Pozidriv mistaken for Phillips — the wrong bit cams out and chews the
//      head. Tell them apart by the four 45-degree tick marks on Pozidriv.
//   2. Security / tamper drives on outdoor and public-space enclosures — each
//      needs its matching tamper bit, which a standard set does NOT include.
//      Pack the tamper bits before the job or you do not open the box.
//
// It follows the template the other reference screens set (iec_connectors_screen
// and fiber_optic_screen are the closest siblings): typed const datasets, a
// §8.16 AppCopyAction that emits the whole page as sectioned TSV, the
// LayoutBuilder / ConstrainedBox / SingleChildScrollView scaffold every
// reference screen shares, three LARGE concept graphics rendered by the shared
// LargeGraphic primitive, and a ToolHelpFooter keyed on the catalog id.
//
// Graphic slots: three named concept graphics, resolved by explicit asset name
// through ScrewDrivesDiagrams (the manifest-gated resolver). Each degrades to
// nothing when its SVG is not yet bundled, so the page ships fully working as
// tables now — Charta's drive-face silhouettes are a later graphics pass.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-screw-drives-reference/RESEARCH-BRIEF.md), sourced to
// ISO standards (named by number) plus multiple independent corroborations. The
// brief's honesty corrections are honored verbatim:
//   * The Phillips "designed to cam out" line is a DEBUNKED MYTH, not a fun
//     fact: the 1933 patent sought a recess with "no tendency to cam out." The
//     page states this as a one-line debunk, never repeats the myth as fact.
//   * Torx is named by its T-number (T10/T15/T20/T25), never "star bit" — the
//     lay term spans 6-point Torx, 5-point pentalobe, and the security variants.
//   * Robertson color coding (yellow #0, green #1, red #2, black #3) is a
//     genuine Robertson + trade-supplier convention, NOT an ISO standard. The
//     page labels it as a trade convention, not a standards-body fact.
//   * Pozidriv and Phillips are NOT interchangeable; the wrong bit cams out and
//     strips the head.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; each graphic carries its
// own absent-asset empty state (render nothing). GL-008 network/subprocess rules
// do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): ASCII hyphen-minus only, never an em dash; US
// spelling; "Wi-Fi" never "WiFi"; degrees spelled out in prose; conclusion
// first. No marketing words.

import 'package:flutter/material.dart';

import '../../../data/screw_drives_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// One common drive type an installer meets daily, with the matching bit and
/// where it shows up on network gear. Verified against the research brief
/// (Part 1 + Part 3).
@immutable
class ScrewDrive {
  const ScrewDrive({
    required this.name,
    required this.code,
    required this.bit,
    required this.where,
    required this.standard,
  });

  /// Drive name, e.g. `Phillips`.
  final String name;

  /// Size code an installer reads off the bit, e.g. `PH1, PH2`. `-` when the
  /// drive is sized by blade dimensions rather than a number series (slotted).
  final String code;

  /// The bit to grab, e.g. `PH1, PH2`.
  final String bit;

  /// Where it shows up on network gear, e.g. `Indoor AP covers, bracket screws`.
  final String where;

  /// Governing standard, e.g. `ISO 8764`. Robertson is flagged as a trade
  /// convention, not an ISO standard (brief correction).
  final String standard;
}

/// One security / tamper-resistant drive an installer meets on outdoor and
/// public-space enclosures, with what it looks like and the tool needed.
/// Verified against the research brief (Part 2).
@immutable
class SecurityDrive {
  const SecurityDrive({
    required this.name,
    required this.looksLike,
    required this.tool,
  });

  /// Drive name, e.g. `Security Torx (pin-in Torx)`.
  final String name;

  /// The distinguishing visual cue, e.g. `Torx star with a pin in the center`.
  final String looksLike;

  /// The matching tamper bit, e.g. `Torx security bit, hole bored down the
  /// center to clear the pin (T10H-T40H)`.
  final String tool;
}

class ScrewDrivesScreen extends StatelessWidget {
  const ScrewDrivesScreen({super.key});

  /// Common drives an installer meets daily, in render order. Verified against
  /// the research brief (Part 1 + the Part 3 "which bit" table). PH1/PH2 and
  /// PZ1/PZ2 cover almost everything on network gear.
  static const List<ScrewDrive> commonDrives = <ScrewDrive>[
    ScrewDrive(
      name: 'Slotted (flat-blade)',
      code: '-',
      bit: 'Blade matched to slot width',
      where: 'Terminal blocks, grounding lugs, legacy brackets',
      standard: 'ISO 2380',
    ),
    ScrewDrive(
      name: 'Phillips',
      code: 'PH0-PH4',
      bit: 'PH1, PH2',
      where: 'Indoor AP covers, bracket screws, rack cage nuts',
      standard: 'ISO 8764',
    ),
    ScrewDrive(
      name: 'Pozidriv',
      code: 'PZ0-PZ5',
      bit: 'PZ1, PZ2',
      where: 'EU enclosures, DIN-rail gear, PDUs, EU mount kits',
      standard: 'ISO 8764 Type Z',
    ),
    ScrewDrive(
      name: 'Hex (Allen, metric)',
      code: '2.5-6 mm',
      bit: '2.5-6 mm hex key/bit',
      where: 'Antenna/pole mount set screws, bracket joints',
      standard: 'ISO 4762',
    ),
    ScrewDrive(
      name: 'Hex (Allen, imperial)',
      code: '3/32"-1/4"',
      bit: '3/32"-1/4" hex key/bit',
      where: 'US-sourced mounts, rack hardware',
      standard: 'ISO 4762',
    ),
    ScrewDrive(
      name: 'Torx',
      code: 'T1-T100',
      bit: 'T10, T15, T20, T25',
      where: 'Enclosures, rack ears, outdoor AP housings',
      standard: 'ISO 10664',
    ),
    ScrewDrive(
      name: 'Robertson (square)',
      code: '#0-#3',
      bit: '#1 (green), #2 (red)',
      where: 'Canadian sites/hardware, overhead ceiling work',
      standard: 'Trade convention (not ISO)',
    ),
  ];

  /// Security / tamper-resistant drives, in render order. Verified against the
  /// research brief (Part 2). Each needs its matching tamper bit, which a
  /// standard bit set does NOT include.
  static const List<SecurityDrive> securityDrives = <SecurityDrive>[
    SecurityDrive(
      name: 'Security Torx (pin-in Torx, TR)',
      looksLike: 'A normal Torx star with a small post (pin) in the center; a '
          'solid Torx bit will not seat.',
      tool: 'Torx security bit with a hole bored down the center to clear the '
          'pin (sized T10H-T40H). The most common tamper spec on commercial '
          'enclosures.',
    ),
    SecurityDrive(
      name: 'Pin-in hex (security hex)',
      looksLike: 'A normal Allen hex socket with a pin in the center.',
      tool: 'Hex security bit with a matching center hole. Common on panels and '
          'public enclosures.',
    ),
    SecurityDrive(
      name: 'One-way (clutch)',
      looksLike: 'A slotted-looking head with curved ramps; it turns to tighten '
          'and slips when you try to loosen.',
      tool: 'Installs with a flat blade; removal needs extraction (drill or '
          'specialty tool). A near-permanent fastener.',
    ),
    SecurityDrive(
      name: 'Tri-wing',
      looksLike: 'A three-bladed pinwheel / triangular recess.',
      tool: 'Tri-wing bit. Common on consumer electronics and commercial '
          'enclosures.',
    ),
    SecurityDrive(
      name: 'Spanner (snake-eye)',
      looksLike: 'Two round holes ("snake eyes") on the face.',
      tool: 'Spanner / pin-spanner bit with two matching pins. The lowest-'
          'security deterrent; serviceable by maintenance crews.',
    ),
  ];

  /// The Phillips-vs-Pozidriv distinguisher — the highest field-value rule on
  /// the page. Conclusion first (GL-004). Verified against the research brief.
  static const String distinguisher =
      'Pozidriv is easily mistaken for Phillips, and the wrong bit cams out and '
      'strips the head. They are NOT interchangeable. Tell them apart by the '
      'face: a Pozidriv head has four shallow tick marks set at 45 degrees '
      'between the cross arms (the "starburst"); see those extra lines, reach '
      'for a PZ bit. A Phillips head is a clean cross with no tick marks; use a '
      'PH bit. Pozidriv is the European "electrician\'s screw" standard, so it '
      'turns up on EU-sourced enclosures, DIN-rail hardware, and PDUs; grabbing '
      'a Phillips bit out of habit is the number-one head-stripping mistake.';

  /// The "pack your tamper bits" takeaway for the security section. Conclusion
  /// first (GL-004). Verified against the research brief (Part 2 anti-pattern).
  static const String tamperTakeaway =
      'Pack the tamper bits before any outdoor or public-space job. Security '
      'drives exist specifically so a standard bit will not work, so "I will '
      'grab one at the site" is not a plan; if you did not bring the matching '
      'bit, you do not open the enclosure. A consolidated security set (security '
      'Torx T10H-T40H, pin-hex, tri-wing, and spanner) covers the vast majority '
      'of specs you hit on outdoor AP enclosures, ceiling cages, and locked NEMA '
      'boxes.';

  /// The one-line myth debunk (GL-005 + the domain-proof-over-consensus standing
  /// rule). The page states the truth and does NOT repeat the myth as fact.
  static const String mythDebunk =
      'Myth, debunked: Phillips was NOT designed to cam out. The original 1933 '
      'patent explicitly sought a recess with "no tendency of the driver to cam '
      'out." Cam-out is a byproduct of the tapered walls, not a design goal; '
      'most online sources still repeat the myth, so getting this right is worth '
      'it.';

  /// Provenance footnote for the common-drives table.
  static const String commonFootnote =
      'Bit forms are governed by the ISO standards named above (ISO 2380 '
      'slotted, ISO 8764 cross-recess / Pozidriv Type Z, ISO 4762 hex socket, '
      'ISO 10664 hexalobular / Torx). Robertson color coding is a genuine '
      'Robertson and trade-supplier convention, not an ISO standard. PH1/PH2 and '
      'PZ1/PZ2 cover almost everything on network gear.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Screw Drives'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the common-drive "which
        // bit" table, the Phillips-vs-Pozidriv rule, then the security drives.
        // Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as sectioned TSV. Section 1 is the
  /// common-drive "which bit / where on network gear" table; section 2 is the
  /// Phillips-vs-Pozidriv distinguisher; section 3 is the security-drive table
  /// plus the pack-your-tamper-bits takeaway; then the one-line myth debunk.
  /// Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Screw Drives & Driver Bits (installer field reference)')
      ..writeln()
      ..writeln('Common drives: which bit / where on network gear')
      ..writeln(
        <String>[
          'Drive',
          'Size code',
          'Bit',
          'Where on network gear',
          'Standard',
        ].join(tab),
      );
    for (final ScrewDrive d in commonDrives) {
      buf.writeln(
        <String>[d.name, d.code, d.bit, d.where, d.standard].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(commonFootnote)
      ..writeln()
      ..writeln('Phillips vs Pozidriv: not interchangeable')
      ..writeln(distinguisher)
      ..writeln()
      ..writeln('Security / tamper drives (outdoor AP enclosures)')
      ..writeln(<String>['Drive', 'What it looks like', 'Tool needed'].join(tab));
    for (final SecurityDrive s in securityDrives) {
      buf.writeln(
        <String>[s.name, s.looksLike, s.tool].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(tamperTakeaway)
      ..writeln()
      ..writeln(mythDebunk);
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
                  // (a) Common drives — the recognition chart + the "which bit /
                  // where on network gear" table.
                  const _SectionHeading(label: 'Common drives'),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: ScrewDrivesDiagrams.faces,
                    path: ScrewDrivesDiagrams.path,
                    has: ScrewDrivesDiagrams.has,
                  ),
                  if (ScrewDrivesDiagrams.has(ScrewDrivesDiagrams.faces))
                    const SizedBox(height: AppSpacing.md),
                  _CommonDrivesCard(isDesktop: isDesktop),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    commonFootnote,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (b) Phillips vs Pozidriv — the distinguisher graphic + the
                  // "not interchangeable" warning.
                  const _SectionHeading(
                    label: 'Phillips vs Pozidriv',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: ScrewDrivesDiagrams.phillipsVsPozidriv,
                    path: ScrewDrivesDiagrams.path,
                    has: ScrewDrivesDiagrams.has,
                  ),
                  if (ScrewDrivesDiagrams.has(
                    ScrewDrivesDiagrams.phillipsVsPozidriv,
                  ))
                    const SizedBox(height: AppSpacing.md),
                  _CalloutCard(
                    tone: _CalloutTone.warning,
                    heading: 'Not interchangeable',
                    body: distinguisher,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (c) Security / tamper drives — the security faces graphic +
                  // the table + the "pack the tamper bits" takeaway.
                  const _SectionHeading(
                    label: 'Security / tamper drives',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LargeGraphic(
                    assetName: ScrewDrivesDiagrams.security,
                    path: ScrewDrivesDiagrams.path,
                    has: ScrewDrivesDiagrams.has,
                  ),
                  if (ScrewDrivesDiagrams.has(ScrewDrivesDiagrams.security))
                    const SizedBox(height: AppSpacing.md),
                  _SecurityDrivesCard(),
                  const SizedBox(height: AppSpacing.sm),
                  _CalloutCard(
                    tone: _CalloutTone.info,
                    heading: 'Pack the tamper bits',
                    body: tamperTakeaway,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // (d) The one-line myth debunk.
                  _CalloutCard(
                    tone: _CalloutTone.info,
                    heading: 'Phillips cam-out myth',
                    body: mythDebunk,
                  ),
                  ToolHelpFooter(toolId: 'screw-drives'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A section heading standing on the page background above a card or graphic.
/// Mirrors the IEC reference's `_SectionHeading` register.
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

/// Shared card surface — matches the dB / fiber / IEC reference idiom.
class _Card extends StatelessWidget {
  const _Card({required this.heading, required this.child});

  final String heading;
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
          Text(
            heading,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

// Fixed cell widths for the horizontally-scrolled common-drive "which bit" grid.
// Constant so the header and every data row align column-for-column, and so the
// grid never RenderFlex-overflows at 320pt (it scrolls horizontally instead).
const double _kDriveW = 168;
const double _kCodeW = 92;
const double _kBitW = 132;
const double _kWhereW = 240;
const double _kStdW = 168;

/// The common-drive "which bit / where on network gear" table. Wider than a
/// phone, so it scrolls horizontally with fixed-width cells (overflow-safe),
/// matching the fiber distance-grid idiom.
class _CommonDrivesCard extends StatelessWidget {
  const _CommonDrivesCard({required this.isDesktop});

  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _Card(
      heading: 'Which bit / where on network gear',
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CommonHeaderRow(text: text),
              const SizedBox(height: AppSpacing.xs),
              for (final ScrewDrive d in ScrewDrivesScreen.commonDrives)
                _CommonRow(drive: d, text: text, mono: mono),
            ],
          ),
        ),
      ),
    );
  }
}

/// Column header for the common-drive grid.
class _CommonHeaderRow extends StatelessWidget {
  const _CommonHeaderRow({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? style = text.labelMedium?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: <Widget>[
          SizedBox(width: _kDriveW, child: Text('Drive', style: style)),
          SizedBox(width: _kCodeW, child: Text('Size', style: style)),
          SizedBox(width: _kBitW, child: Text('Bit', style: style)),
          SizedBox(width: _kWhereW, child: Text('Where on gear', style: style)),
          SizedBox(width: _kStdW, child: Text('Standard', style: style)),
        ],
      ),
    );
  }
}

/// One drive row in the common-drive grid.
class _CommonRow extends StatelessWidget {
  const _CommonRow({
    required this.drive,
    required this.text,
    required this.mono,
  });

  final ScrewDrive drive;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(drive.name, <String?>[
        drive.code == '-' ? null : 'size ${drive.code}',
        'bit ${drive.bit}',
        'on gear ${drive.where}',
        'standard ${drive.standard}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: _kDriveW,
              child: Text(
                drive.name,
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: _kCodeW,
              child: Text(
                drive.code,
                style: mono.inlineCode.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(
              width: _kBitW,
              child: Text(
                drive.bit,
                style: mono.inlineCode.copyWith(color: colors.textAccent),
              ),
            ),
            SizedBox(
              width: _kWhereW,
              child: Text(
                drive.where,
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            SizedBox(
              width: _kStdW,
              child: Text(
                drive.standard,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The security / tamper-drive table. Full-width rows (looks-like + tool wrap),
/// so no horizontal scroll is needed — the content is sentences, not a numeric
/// matrix.
class _SecurityDrivesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      heading: 'What it looks like / tool needed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final SecurityDrive s in ScrewDrivesScreen.securityDrives)
            _SecurityRow(drive: s, text: text),
        ],
      ),
    );
  }
}

/// One security-drive row: the drive name on the top line, then the
/// "looks like" and "tool needed" clauses beneath. Full-width so they wrap.
class _SecurityRow extends StatelessWidget {
  const _SecurityRow({required this.drive, required this.text});

  final SecurityDrive drive;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(drive.name, <String?>[
        'looks like ${drive.looksLike}',
        'tool ${drive.tool}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              drive.name,
              style: text.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            _LabeledLine(label: 'Looks like', value: drive.looksLike),
            const SizedBox(height: AppSpacing.xxs),
            _LabeledLine(label: 'Tool', value: drive.tool),
          ],
        ),
      ),
    );
  }
}

/// A short label followed by its wrapping value, used inside the security rows.
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return RichText(
      text: TextSpan(
        style: text.labelMedium?.copyWith(color: colors.textSecondary),
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: text.labelMedium?.copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

/// Tone of a [_CalloutCard]: a warning (the not-interchangeable / strips-the-
/// head rule) or a neutral info note (the takeaway, the myth debunk). Uses the
/// §8.13 status palette (paired with a heading WORD — never color alone).
enum _CalloutTone { warning, info }

/// A bordered callout that pulls one load-bearing rule out of the body text. The
/// left edge and the heading take a §8.13 status hue; the body reads at primary
/// ink so it stays full-contrast. Never color alone — the heading carries the
/// meaning for colorblind / AT users.
class _CalloutCard extends StatelessWidget {
  const _CalloutCard({
    required this.tone,
    required this.heading,
    required this.body,
  });

  final _CalloutTone tone;
  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color toneColor = switch (tone) {
      _CalloutTone.warning => colors.statusWarning,
      _CalloutTone.info => colors.statusInfo,
    };
    return Semantics(
      container: true,
      label: '$heading. $body',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
          // The left accent edge carries the tone; pairs with the heading word.
          // A thicker left border than the 1px hairline reads as a status rail.
        ),
        // IntrinsicHeight bounds the Row's height so the stretch-rail child gets
        // a finite height. Without it, the Row sits in a SingleChildScrollView
        // Column with unbounded vertical constraints, and the zero-intrinsic-
        // height accent rail cannot stretch to Infinity — that is what threw the
        // "RenderBox was not laid out: hasSize" failure at 320pt (and cascaded
        // into the missing-SvgPicture failure on the same page).
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: AppSpacing.xxs,
                decoration: BoxDecoration(
                  color: toneColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.card),
                    bottomLeft: Radius.circular(AppRadius.card),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        heading,
                        style: text.labelLarge?.copyWith(
                          color: toneColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        body,
                        style: text.bodyMedium?.copyWith(
                          color: colors.textPrimary,
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
