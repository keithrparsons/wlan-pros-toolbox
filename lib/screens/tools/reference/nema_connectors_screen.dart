// NEMA Connectors — read-only reference for the North American plug/receptacle
// system a field tech meets at a panel, PDU, generator, or wall outlet: how to
// decode the NEMA nomenclature (e.g. L21-30P), and a verified table of common
// device types with voltage / phase / amps / wire configuration, grouped by
// voltage class and flagged single-phase vs three-phase.
//
// Page 4 of 6 in the "Power & Cooling" reference category. It follows the
// template the pilot (power_phasing_screen) established: typed const datasets,
// a §8.16 AppCopyAction that emits the whole page as sectioned TSV, the
// LayoutBuilder / ConstrainedBox / SingleChildScrollView scaffold shared by
// every reference screen, a single manifest-gated face-diagram graphic slot that
// degrades gracefully (face diagrams are a later pass — Charta authors the plate
// and Larry wires it before merge), and a ToolHelpFooter keyed on the catalog id.
//
// What's the same as Power Phasing: one named graphic resolved by explicit asset
// name through NemaConnectorDiagrams (the manifest-gated resolver, mirroring
// PowerPhasingDiagrams / ConnectorDiagrams), rendered by a band that reuses the
// §8.20.7 light-mode recolor path (ConceptGraphicBand.applyLightSwap) and
// collapses to nothing when the SVG is not yet bundled — so the page ships fully
// working before the face plate lands.
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
// path because nothing is fetched or parsed at runtime; the face-diagram band
// carries its own absent-asset empty state (renders nothing). GL-008
// network/subprocess rules do not apply (nothing fetched, nothing shelled out).
//
// Glyph / copy notes (GL-004): degrees spelled out in prose, "deg" symbol-free
// in copy payload; the phase symbol is written "1-phase" / "3-phase" in copy and
// shown as the Greek phi glyph only in on-screen labels where it reads cleanly;
// ASCII hyphen-minus only, never an em dash; US spelling.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/nema_connector_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
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

  /// `true` when this device is three-phase (drives the 1-phase vs 3-phase flag).
  bool get isThreePhase => phase.contains('3-phase');
}

class NemaConnectorsScreen extends StatelessWidget {
  const NemaConnectorsScreen({super.key});

  /// The single face-diagram graphic slot, resolved by explicit asset name.
  static const String diagramAsset = NemaConnectorDiagrams.facePlate;

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
      'a configuration code, not a voltage — do no arithmetic on it.';

  // ---- Device groups -------------------------------------------------------

  /// 125V single-phase straight-blade devices (the 1-series and 5-series).
  static const List<NemaDevice> group125v = <NemaDevice>[
    NemaDevice(
      type: '1-15',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 2W (no ground)',
      amps: 15,
    ),
    NemaDevice(
      type: '5-15',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 15,
    ),
    NemaDevice(
      type: '5-20',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
    ),
    NemaDevice(
      type: '5-30',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
    ),
    NemaDevice(
      type: 'L5-15',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 15,
      locking: true,
    ),
    NemaDevice(
      type: 'L5-20',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
      locking: true,
    ),
    NemaDevice(
      type: 'L5-30',
      voltage: '125V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
      locking: true,
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
    ),
    NemaDevice(
      type: '6-20',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
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
    ),
    NemaDevice(
      type: 'L6-20',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 20,
      locking: true,
    ),
    NemaDevice(
      type: 'L6-30',
      voltage: '250V',
      phase: '1-phase',
      wiring: '2P / 3W (grounded)',
      amps: 30,
      locking: true,
    ),
    NemaDevice(
      type: '14-30',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 30,
    ),
    NemaDevice(
      type: '14-50',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 50,
    ),
    NemaDevice(
      type: 'L14-20',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 20,
      locking: true,
    ),
    NemaDevice(
      type: 'L14-30',
      voltage: '125/250V',
      phase: '1-phase split',
      wiring: '3P / 4W (2 hot + N + G)',
      amps: 30,
      locking: true,
    ),
    NemaDevice(
      type: 'L21-20',
      voltage: '120/208V',
      phase: '3-phase wye',
      wiring: '4P / 5W (3 hot + N + G)',
      amps: 20,
      locking: true,
    ),
    NemaDevice(
      type: 'L21-30',
      voltage: '120/208V',
      phase: '3-phase wye',
      wiring: '4P / 5W (3 hot + N + G)',
      amps: 30,
      locking: true,
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
                  // Face-diagram graphic slot — renders only when its SVG is
                  // bundled; otherwise collapses to nothing (graceful
                  // degradation). Face diagrams are a deferred pass.
                  _FaceDiagramBand(
                    assetName: diagramAsset,
                    isDesktop: isDesktop,
                  ),
                  if (NemaConnectorDiagrams.has(diagramAsset))
                    const SizedBox(height: AppSpacing.md),
                  // How to read a NEMA designation.
                  _decoderCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  // 125V single-phase devices.
                  _deviceCard(
                    title: '125V single-phase',
                    devices: group125v,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // 208 / 240 / 250V devices — with the split-vs-3-phase note.
                  _deviceCard(
                    title: '208 / 240 / 250V',
                    devices: group208v,
                    note: splitVsThreePhaseNote,
                    colors: colors,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // California Standard three-phase connectors.
                  _deviceCard(
                    title: 'California Standard 3-phase',
                    devices: groupCalifornia,
                    note: californiaNote,
                    footnote: footnote,
                    colors: colors,
                    text: text,
                    mono: mono,
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

  /// One device-group table: type, voltage, phase (1-phase vs 3-phase flagged),
  /// wiring, amps. The locking flag tints the twist-lock types; the three-phase
  /// flag tints the phase cell so the L21 / CS rows stand out from the
  /// single-phase majority.
  Widget _deviceCard({
    required String title,
    required List<NemaDevice> devices,
    required AppColorScheme colors,
    required TextTheme text,
    required AppMonoText mono,
    String? note,
    String? footnote,
  }) {
    return _TableCard(
      title: title,
      note: note,
      footnote: footnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Type', width: 80),
          _HeaderCell('Voltage', width: 96),
          _HeaderCell('Phase', width: 112),
          _HeaderCell('Wiring', width: 196),
          _HeaderCell('Amps', width: 56),
        ],
      ),
      rows: devices.map((NemaDevice d) {
        return ReferenceRowSemantics(
          label: rowLabel(d.type, <String?>[
            d.voltage,
            d.phase,
            d.wiring,
            '${d.amps} amps',
            if (d.locking) 'twist-lock',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 80,
                  child: Text(
                    d.type,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    d.voltage,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 112,
                  child: Text(
                    d.phase,
                    style: text.labelMedium?.copyWith(
                      // 3-phase flagged lime so it pops from the 1-phase
                      // majority — the page's load-bearing distinction.
                      color: d.isThreePhase
                          ? colors.textAccent
                          : colors.textTertiary,
                      fontWeight:
                          d.isThreePhase ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                SizedBox(
                  width: 196,
                  child: Text(
                    d.wiring,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${d.amps}A',
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
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

/// The face-diagram band for the NEMA Connectors plate. Renders the bundled SVG
/// (`assets/tool-graphics/nema-connectors.svg`) inside a recessed band when it
/// is bundled, and collapses to nothing (SizedBox.shrink) when it is not — so
/// the page ships fully working before the deferred face plate lands.
/// Decorative for screen readers: every fact the diagram depicts is also in the
/// tables' text (voltage, phase, amps, wiring) per GL-003 §8.6.2 a11y rule.
///
/// LIGHT/DARK (GL-003 §8.20.7): the plate is authored DARK-BAKED (scaffold/lime
/// hexes that read on #1A1A1A but fail contrast on white if drawn raw). So this
/// widget reuses the SAME §8.20.7 recolor path the §8.6.2 concept graphics and
/// the Power Phasing waveforms use, via [ConceptGraphicBand.applyLightSwap]:
///   * DARK: render the unmodified asset (byte-for-byte; dark goldens unaffected).
///   * LIGHT: load the SVG source, apply the §8.20.7 allow-list hex swap, then
///     render via SvgPicture.string. Cached so the replace runs once per build.
class _FaceDiagramBand extends StatelessWidget {
  const _FaceDiagramBand({required this.assetName, required this.isDesktop});

  final String assetName;
  final bool isDesktop;

  // §8.6.2 band-height token: 140dp mobile / 160dp tablet-desktop, matching the
  // Power Phasing waveform band.
  static const double _bandHeightMobile = 140;
  static const double _bandHeightDesktop = 160;

  // Per-asset cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per asset, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  /// Loads the face-plate SVG source and applies the §8.20.7 allow-list light
  /// swap, caching per asset name. Returns the recolored source string.
  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[assetName] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(NemaConnectorDiagrams.path(assetName));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[assetName] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled plate → render nothing, layout unchanged.
    if (!NemaConnectorDiagrams.has(assetName)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightFaceDiagramSvg(future: _loadSwappedSvg(), bandHeight: bandHeight)
        : SvgPicture.asset(
            NemaConnectorDiagrams.path(assetName),
            fit: BoxFit.contain,
            width: double.infinity,
            height: bandHeight,
            excludeFromSemantics: true,
            // A bundled-but-unparseable SVG collapses to nothing rather than
            // surfacing a broken-image box.
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: SizedBox(
          height: bandHeight,
          width: double.infinity,
          child: Center(child: svg),
        ),
      ),
    );
  }
}

/// Light-mode face-plate render: awaits the §8.20.7-swapped SVG source, then
/// draws it with `SvgPicture.string`. Collapses to nothing while loading or on
/// any parse failure — same graceful-degradation contract as the dark asset
/// path, so no broken-image box or layout jump ever appears. Mirrors
/// `_LightWaveformSvg` in power_phasing_screen.dart.
class _LightFaceDiagramSvg extends StatelessWidget {
  const _LightFaceDiagramSvg({required this.future, required this.bandHeight});

  final Future<String> future;
  final double bandHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) {
          // Loading or failed — render nothing (no broken box, no jump).
          return const SizedBox.shrink();
        }
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: double.infinity,
          height: bandHeight,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Card surface wrapping a wide table: title over an optional note, then a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// power_phasing_screen / poe_reference_screen overflow-safe idiom.
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
