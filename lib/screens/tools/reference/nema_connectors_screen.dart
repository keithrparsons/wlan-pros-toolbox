// NEMA Connectors — read-only reference for the North American plug/receptacle
// system a field tech meets at a panel, PDU, generator, or wall outlet: how to
// decode the NEMA nomenclature (e.g. L21-30P), and a verified set of common
// device types with voltage / phase / amps / wire configuration, grouped by
// voltage class and flagged single-phase vs three-phase.
//
// Page 4 of 6 in the "Power & Cooling" reference category.
//
// BIG-graphic redesign (Keith, 2026-06-08): the page no longer carries one small
// recessed face plate. It now renders one LARGE per-connector FACE graphic per
// card — each = the big face graphic plus that connector's title/specs alongside
// (the reusable LargeFaceCard pattern the IEC page established). The nomenclature
// decoder stays a compact table card (it decodes a designation token-by-token; it
// is not a connector face). Every face degrades to nothing when its SVG is not
// yet bundled, so each card reads as title + specs + note alone until Charta's
// faces land. The face assets are resolved by explicit asset name through
// NemaConnectorDiagrams (the manifest-gated per-face resolver).
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, Topic 4),
// sourced to NEMA WD-6 + corroborating vendor spec sheets for the CS8364/65
// California Standard connectors. Facts only. The brief's corrections are
// honored verbatim:
//   * The 14-series (14-30/14-50, L14-20/30) is single-phase SPLIT (125/250V,
//     two hots 180 deg apart + neutral + ground), NOT three-phase. The 4th pin
//     is the neutral. This is the classic range / EV-charger receptacle.
//   * The L21 series IS three-phase wye (120/208V, 4-pole 5-wire).
//   * The leading number is a CODE for the voltage class + pole/wire + phase,
//     never a literal voltage — the decoder card states this.
//   * CS8364/65 are rated 250V 3-phase, not 208V (they run on 208V wye systems
//     but the connector nameplate is 250V).
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; each face card carries
// its own absent-asset empty state (renders no graphic). GL-008 network/subprocess
// rules do not apply (nothing fetched, nothing shelled out).
//
// Glyph / copy notes (GL-004): degrees spelled out in prose, "deg" symbol-free
// in copy payload; the phase descriptor is written "1-phase" / "3-phase" in copy
// and on screen; ASCII hyphen-minus only, never an em dash; US spelling.

import 'package:flutter/material.dart';

import '../../../data/nema_connector_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// One part of the NEMA nomenclature, decoded — the rows of the decoder card.
/// e.g. `L` prefix → locking (twist-lock). Verified against the research brief.
@immutable
class NemaDecodePart {
  const NemaDecodePart({
    required this.token,
    required this.meaning,
    required this.detail,
  });

  /// The token as it appears in a NEMA designation, e.g. `L`, `21`, `30`, `P`.
  final String token;

  /// Short label for what the token means, e.g. `Locking`.
  final String meaning;

  /// One-line expansion of the token's meaning.
  final String detail;
}

/// One NEMA device type — a verified row of the device table. Field values are
/// verified against Pax's research brief (Topic 4, device table).
@immutable
class NemaDevice {
  const NemaDevice({
    required this.type,
    required this.voltage,
    required this.phase,
    required this.wiring,
    required this.amps,
    this.locking = false,
    this.assetName,
  });

  /// The NEMA designation without the P/R sex suffix, e.g. `5-15`, `L21-30`.
  final String type;

  /// Nominal voltage, e.g. `125V`, `250V`, `125/250V`, `120/208V`.
  final String voltage;

  /// Phase descriptor: `1-phase`, `1-phase split`, or `3-phase wye`.
  final String phase;

  /// Pole / wire configuration, e.g. `2P / 3W (grounded)`, `4P / 5W`.
  final String wiring;

  /// Current rating in amps.
  final int amps;

  /// `true` for twist-lock (`L`-prefixed) types — drives the on-screen flag.
  final bool locking;

  /// The per-face SVG asset name for this device (one of the
  /// [NemaConnectorDiagrams] face consts), or null when no dedicated face is
  /// produced for this type (the less-common types read as text). Resolved
  /// through the manifest-gated resolver and degrades gracefully when absent.
  final String? assetName;

  /// `true` when this device is three-phase (drives the 1-phase vs 3-phase flag).
  bool get isThreePhase => phase.contains('3-phase');
}

class NemaConnectorsScreen extends StatelessWidget {
  const NemaConnectorsScreen({super.key});

  // ---- Nomenclature decoder ------------------------------------------------

  /// The decoder, walked left-to-right across a designation like `L21-30P`.
  /// Verified against the research brief nomenclature section.
  static const List<NemaDecodePart> decoder = <NemaDecodePart>[
    NemaDecodePart(
      token: 'L',
      meaning: 'Locking',
      detail:
          'Twist-lock with curved blades. No L prefix means straight blades '
          '(a standard non-locking plug).',
    ),
    NemaDecodePart(
      token: '21',
      meaning: 'Voltage / pole / phase class',
      detail:
          'A code, not a voltage. 21 = three-phase wye 120/208V, 4-pole '
          '5-wire. The leading number encodes the configuration; never read '
          'it as a literal voltage.',
    ),
    NemaDecodePart(
      token: '30',
      meaning: 'Current rating',
      detail: 'The number after the hyphen is the amp rating: 30 = 30A.',
    ),
    NemaDecodePart(
      token: 'P',
      meaning: 'Plug (male)',
      detail:
          'P = plug (male). R = receptacle (female). So L21-30P is the '
          '30A 3-phase twist-lock plug; L21-30R is its receptacle.',
    ),
  ];

  /// Worked-example note shown under the decoder.
  static const String decoderExample =
      'Worked example: L21-30P = L (twist-lock) + 21 (three-phase wye '
      '120/208V, 4-pole 5-wire) + 30 (30A) + P (plug). The leading number is '
      'a configuration code, not a voltage; do no arithmetic on it.';

  // ---- Device groups -------------------------------------------------------

  /// 125V single-phase straight-blade devices (the 1-series and 5-series).
  static const List<NemaDevice> group125v = <NemaDevice>[
    NemaDevice(
      type: '1-15',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 2W (no ground)',
      amps: 15,
      assetName: NemaConnectorDiagrams.n115,
    ),
    NemaDevice(
      type: '5-15',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 15,
      assetName: NemaConnectorDiagrams.n515,
    ),
    NemaDevice(
      type: '5-20',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
      assetName: NemaConnectorDiagrams.n520,
    ),
    NemaDevice(
      type: '5-30',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
      assetName: NemaConnectorDiagrams.n530,
    ),
    NemaDevice(
      type: 'L5-15',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 15,
      locking: true,
      assetName: NemaConnectorDiagrams.l515,
    ),
    NemaDevice(
      type: 'L5-20',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
      locking: true,
      assetName: NemaConnectorDiagrams.l520,
    ),
    NemaDevice(
      type: 'L5-30',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
      locking: true,
      assetName: NemaConnectorDiagrams.l530,
    ),
  ];

  /// 208/240/250V devices — 250V single-phase (6-series), 125/250V split-phase
  /// (14-series), and the 120/208V three-phase wye (L21-series). Flagged 1-phase
  /// vs 3-phase in the table: the 14-series is single-phase SPLIT (the 4th pin
  /// is neutral), NOT three-phase — only the L21-series is three-phase wye.
  static const List<NemaDevice> group208v = <NemaDevice>[
    NemaDevice(
      type: '6-15',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 15,
      assetName: NemaConnectorDiagrams.n615,
    ),
    NemaDevice(
      type: '6-20',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
      assetName: NemaConnectorDiagrams.n620,
    ),
    NemaDevice(
      type: '6-30',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
    ),
    NemaDevice(
      type: '6-50',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 50,
      assetName: NemaConnectorDiagrams.n650,
    ),
    NemaDevice(
      type: 'L6-20',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
      locking: true,
      assetName: NemaConnectorDiagrams.l620,
    ),
    NemaDevice(
      type: 'L6-30',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
      locking: true,
      assetName: NemaConnectorDiagrams.l630,
    ),
    NemaDevice(
      type: '14-30',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 30,
      assetName: NemaConnectorDiagrams.n1430,
    ),
    NemaDevice(
      type: '14-50',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 50,
      assetName: NemaConnectorDiagrams.n1450,
    ),
    NemaDevice(
      type: 'L14-20',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 20,
      locking: true,
      assetName: NemaConnectorDiagrams.l1420,
    ),
    NemaDevice(
      type: 'L14-30',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 30,
      locking: true,
      assetName: NemaConnectorDiagrams.l1430,
    ),
    NemaDevice(
      type: 'L21-20',
      voltage: '120/208V',
      phase: '3-phase wye',
      wiring: '4P / 5W (3 hot + N + G)',
      amps: 20,
      locking: true,
      assetName: NemaConnectorDiagrams.l2120,
    ),
    NemaDevice(
      type: 'L21-30',
      voltage: '120/208V',
      phase: '3-phase wye',
      wiring: '4P / 5W (3 hot + N + G)',
      amps: 30,
      locking: true,
      assetName: NemaConnectorDiagrams.l2130,
    ),
  ];

  /// California Standard three-phase connectors. A separate lineup from the
  /// NEMA WD-6 straight/locking devices, common on 50A 3-phase generators and
  /// large PDUs. Rated 250V (not 208V), per the research brief correction.
  static const List<NemaDevice> groupCalifornia = <NemaDevice>[
    NemaDevice(
      type: 'CS8364',
      voltage: '250V',
      phase: '3-phase',
      wiring: '4W (3 hot + G), connector (female)',
      amps: 50,
    ),
    NemaDevice(
      type: 'CS8365',
      voltage: '250V',
      phase: '3-phase',
      wiring: '4W (3 hot + G), plug (male)',
      amps: 50,
    ),
  ];

  // ---- Notes / footnotes ---------------------------------------------------

  /// The load-bearing correction beneath the 208/240V group.
  static const String splitVsThreePhaseNote =
      'Watch the 14-series. NEMA 14-30 and 14-50 are single-phase SPLIT '
      '(125/250V): two hot legs 180 degrees apart, plus a neutral and a '
      'ground. The 4th pin is the NEUTRAL, not a third hot. They are the '
      'classic range and EV-charger receptacles and are NOT three-phase. Only '
      'the L21 series is three-phase wye (120/208V, three hots 120 degrees '
      'apart, 4-pole 5-wire).';

  /// Footnote for the California Standard table.
  static const String californiaNote =
      'CS8365 (plug) mates with CS8364 (connector) and CS8369 (receptacle). '
      'The nameplate rating is 250V three-phase; they run on 208V wye systems '
      'but are rated 250V, so size to the 250V figure.';

  /// Provenance footnote.
  static const String footnote =
      'Ratings per NEMA WD-6 plus vendor spec sheets for the CS8364/65 '
      'California Standard connectors. The leading number is a configuration '
      'code, not a voltage. P = plug (male); R = receptacle (female).';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEMA Connectors'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the decoder, then the
        // three device tables. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as TSV sections: the nomenclature
  /// decoder, then the three device tables (125V 1-phase, 208/240V, California
  /// Standard 3-phase). The "deg" suffix and "1-phase" / "3-phase" carry through
  /// so the pasted text stays plain-text safe (no degree or phi glyph). Always
  /// non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('NEMA Connectors')
      ..writeln()
      ..writeln('Nomenclature (example: L21-30P)')
      ..writeln(<String>['Token', 'Meaning', 'Detail'].join(tab));
    for (final NemaDecodePart p in decoder) {
      buf.writeln(<String>[p.token, p.meaning, p.detail].join(tab));
    }
    buf
      ..writeln()
      ..writeln(decoderExample)
      ..writeln();
    _writeDeviceSection(buf, '125V single-phase', group125v, tab);
    buf.writeln();
    _writeDeviceSection(buf, '208 / 240 / 250V', group208v, tab);
    buf
      ..writeln()
      ..writeln(splitVsThreePhaseNote)
      ..writeln();
    _writeDeviceSection(
        buf, 'California Standard 3-phase', groupCalifornia, tab);
    buf
      ..writeln()
      ..writeln(californiaNote)
      ..writeln()
      ..writeln(footnote);
    return buf.toString().trimRight();
  }

  /// Writes one device table as a TSV section (subtitle + header + one row each).
  static void _writeDeviceSection(
    StringBuffer buf,
    String title,
    List<NemaDevice> devices,
    String tab,
  ) {
    buf
      ..writeln(title)
      ..writeln(
        <String>['Type', 'Voltage', 'Phase', 'Wiring', 'Amps'].join(tab),
      );
    for (final NemaDevice d in devices) {
      buf.writeln(
        <String>[d.type, d.voltage, d.phase, d.wiring, '${d.amps}A'].join(tab),
      );
    }
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
                  // How to read a NEMA designation — a compact decoder table
                  // card (this decodes a designation token-by-token; it is not a
                  // connector face, so it stays a table, not a LargeFaceCard).
                  _decoderCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.lg),
                  // BIG-graphic redesign (Keith, 2026-06-08): one LARGE face-card
                  // per common device type, stacked vertically — each = the big
                  // face graphic plus that device's title/specs alongside (the
                  // reusable LargeFaceCard pattern the IEC page established).
                  // Every face degrades to nothing when its SVG is not yet
                  // bundled, so each card reads as title + specs + note alone
                  // until Charta's faces land.
                  _SectionHeading(label: '125V single-phase'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._faceCards(group125v, isDesktop),
                  const SizedBox(height: AppSpacing.sm),
                  _SectionHeading(label: '208 / 240 / 250V'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._faceCards(group208v, isDesktop),
                  // The load-bearing 14-50 split / L21 wye callout, kept
                  // prominent beneath the 208/240V cards.
                  Text(
                    splitVsThreePhaseNote,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SectionHeading(label: 'California Standard 3-phase'),
                  const SizedBox(height: AppSpacing.sm),
                  ..._faceCards(groupCalifornia, isDesktop),
                  Text(
                    californiaNote,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    footnote,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                  ToolHelpFooter(toolId: 'nema-connectors'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the stacked [LargeFaceCard] list for one device group, one big card
  /// per device, with an `AppSpacing.md` gap between them. Each card carries the
  /// device's type as the title, the nickname/phase as a subtitle, the
  /// voltage/amps/wiring as specs, and its per-face SVG (degrading gracefully).
  List<Widget> _faceCards(List<NemaDevice> devices, bool isDesktop) {
    final List<Widget> cards = <Widget>[];
    for (final NemaDevice d in devices) {
      cards
        ..add(
          LargeFaceCard(
            title: d.type,
            subtitle: _subtitleFor(d),
            specs: <FaceSpec>[
              FaceSpec(label: 'Voltage', value: d.voltage),
              FaceSpec(label: 'Amps', value: '${d.amps}A', accent: true),
              FaceSpec(
                label: 'Phase',
                value: d.phase,
                accent: d.isThreePhase,
              ),
              FaceSpec(label: 'Wiring', value: d.wiring),
            ],
            assetName: d.assetName ?? '',
            path: NemaConnectorDiagrams.path,
            has: (String name) =>
                name.isNotEmpty && NemaConnectorDiagrams.has(name),
            isDesktop: isDesktop,
          ),
        )
        ..add(const SizedBox(height: AppSpacing.md));
    }
    return cards;
  }

  /// A one-line subtitle for a device card: the twist-lock flag and/or the
  /// load-bearing phase distinction, kept short. Null when neither applies.
  static String? _subtitleFor(NemaDevice d) {
    final List<String> parts = <String>[
      if (d.locking) 'Twist-lock',
      if (d.phase == '1-phase split') 'Split-phase (4th pin = neutral)',
      if (d.isThreePhase) 'Three-phase',
    ];
    return parts.isEmpty ? null : parts.join(' - ');
  }

  /// The nomenclature decoder — a labeled walk through `L21-30P`. Each row is a
  /// token, its meaning, and a one-line expansion.
  Widget _decoderCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'Reading a NEMA designation',
      note: decoderExample,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Token', width: 64),
          _HeaderCell('Meaning', width: 168),
          _HeaderCell('Detail', width: 280),
        ],
      ),
      rows: decoder.map((NemaDecodePart p) {
        return ReferenceRowSemantics(
          label: rowLabel(p.token, <String?>[p.meaning, p.detail]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 64,
                  child: Text(
                    p.token,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    p.meaning,
                    style: text.labelMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: Text(
                    p.detail,
                    style: text.bodyMedium?.copyWith(
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
}

/// A section heading inside the NEMA reference (e.g. "125V single-phase").
/// Title-styled, secondary ink, matching the register the IEC page uses for its
/// section labels — standing on the page background above a stack of
/// [LargeFaceCard]s rather than inside one card.
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

/// Card surface wrapping a wide table: title over an optional note, then a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align). Used only for the nomenclature decoder card now. Matches the
/// power_phasing_screen / poe_reference_screen overflow-safe idiom.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.note,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
  final String? note;

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
