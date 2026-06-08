// IEC Power Connectors — read-only reference for the two IEC connector families
// a field tech meets at a rack or PDU: the IEC 60320 appliance couplers (the
// C13/C14, C19/C20, "kettle" C15/C16, etc.) and the IEC 60309 industrial
// "pin-and-sleeve" connectors (color = voltage band, earth-pin clock position =
// keying).
//
// PAGE 3 of 6 in the "Power & Cooling" reference category. It follows the
// template the Power Phasing pilot set: typed const datasets, a §8.16
// AppCopyAction that emits the whole page as sectioned TSV, the LayoutBuilder /
// ConstrainedBox / SingleChildScrollView scaffold shared by every reference
// screen (power_phasing_screen and poe_reference_screen are the closest
// siblings), and a ToolHelpFooter keyed on the catalog id.
//
// Graphic slot: this page leaves ONE named diagram slot (connector-face
// diagrams — the C13/C14 vs C15/C16 keying notch, the IEC 60309 clock-position
// earth pin). It is resolved by explicit asset name through IecConnectorsDiagrams
// (the manifest-gated resolver, mirroring PowerPhasingDiagrams / ConnectorDiagrams)
// and rendered by the shared _DiagramBand, which reuses the §8.20.7 light-mode
// recolor path (ConceptGraphicBand.applyLightSwap) exactly as the Power Phasing
// waveform bands do. The band degrades to nothing when its SVG is not yet
// bundled, so the page ships fully working as tables now — the connector-face
// diagrams are a later graphics pass.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, Topic 3),
// sourced to IEC 60320 and IEC 60309 (named standards). Facts only. The brief's
// precision corrections are honored verbatim:
//   * The "kettle cord" nickname belongs to C15/C16 (the 120 degC hot-condition
//     coupler with the notch/ridge), NOT C13. C13/C14 is the "PC cord" and is the
//     cold-condition (70 degC) coupler.
//   * C13/C14 max temp is 70 degC; C15/C16 max temp is 120 degC.
//   * Odd number = the cord CONNECTOR (female); even number = the appliance
//     INLET (male), one greater than its mating connector. Stated as male/female
//     explicitly rather than relying on "plug/connector" loosely.
//   * IEC 60309 red spans 380-480V (not a single "415V"); both the color AND the
//     earth-pin clock position must match for two devices to mate.
//   * Clock positions vary by pole count/region: the common cases are rendered
//     and the rest labeled configuration-dependent (verify against IEC 60309-2).
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; the diagram band carries
// its own absent-asset empty state (render nothing). GL-008 network/subprocess
// rules do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): degrees spelled out in prose, "degC" symbol-free
// in the copy payload and the compact table cells; ASCII hyphen-minus only,
// never an em dash; US spelling; the math-approx glyph appears only where a
// table value uses it ("approx" written out in prose).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/iec_connectors_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One IEC 60320 appliance-coupler family (an odd/even mating pair, e.g.
/// C13/C14). Field values are verified against Pax's research brief (Topic 3).
@immutable
class IecCoupler {
  const IecCoupler({
    required this.pair,
    required this.current,
    required this.maxTemp,
    required this.nickname,
    required this.use,
  });

  /// The coupler pair, e.g. `C13 / C14`. The odd member is the cord connector
  /// (female); the even member is the appliance inlet (male).
  final String pair;

  /// Rated current for the coupler class, e.g. `10 A`. The standard's maximum;
  /// a specific cord may be rated lower.
  final String current;

  /// Maximum temperature rating, e.g. `70 degC`. C15/C16 is the 120 degC
  /// hot-condition coupler; everything else here is the 70 degC cold-condition.
  final String maxTemp;

  /// Common nickname, e.g. `"Cloverleaf"`. `'-'` (ASCII hyphen) when the family
  /// has no well-established colloquial name.
  final String nickname;

  /// Typical use.
  final String use;
}

/// One IEC 60309 industrial-connector voltage band, keyed by housing color.
/// Field values are verified against Pax's research brief (Topic 3).
@immutable
class IecIndustrial {
  const IecIndustrial({
    required this.color,
    required this.voltage,
    required this.use,
  });

  /// Housing color, which encodes the voltage band, e.g. `Blue`.
  final String color;

  /// Voltage range for the band, e.g. `200-250V`.
  final String voltage;

  /// Typical use.
  final String use;
}

class IecConnectorsScreen extends StatelessWidget {
  const IecConnectorsScreen({super.key});

  /// IEC 60320 appliance couplers, in render order. Verified against the
  /// research brief (Topic 3). Odd = cord connector (female); even = appliance
  /// inlet (male), one greater than its mate.
  static const List<IecCoupler> couplers = <IecCoupler>[
    IecCoupler(
      pair: 'C1 / C2',
      current: '0.2 A',
      maxTemp: '70 degC',
      nickname: '-',
      use: 'Electric shavers and other low-draw appliances',
    ),
    IecCoupler(
      pair: 'C5 / C6',
      current: '2.5 A',
      maxTemp: '70 degC',
      nickname: '"Cloverleaf" / "Mickey Mouse"',
      use: 'Laptop power bricks',
    ),
    IecCoupler(
      pair: 'C7 / C8',
      current: '2.5 A',
      maxTemp: '70 degC',
      nickname: '"Figure-8" / "Infinity"',
      use: 'AV gear and small electronics',
    ),
    IecCoupler(
      pair: 'C13 / C14',
      current: '10 A',
      maxTemp: '70 degC',
      nickname: '"PC cord"',
      use:
          'The ubiquitous PC, PDU, and server cord. Cold-condition (70 degC), '
          'NOT the kettle coupler.',
    ),
    IecCoupler(
      pair: 'C15 / C16',
      current: '10 A',
      maxTemp: '120 degC',
      nickname: '"Kettle cord" (true kettle coupler)',
      use:
          'Hot-condition coupler (120 degC), keyed by a notch. Kettles, hot '
          'appliances, networking gear in warm enclosures. A C15 cord fits a '
          'C14 inlet, but a C13 cord will not fit a C16 inlet (the notch blocks '
          'it).',
    ),
    IecCoupler(
      pair: 'C19 / C20',
      current: '16 A',
      maxTemp: '70 degC',
      nickname: '-',
      use:
          'High-draw servers, PDUs, and large UPS units. On a PDU the C19 '
          'outlets (female) feed device C20 inlets (male).',
    ),
  ];

  /// IEC 60309 industrial connectors, keyed by color = voltage band, in render
  /// order. Verified against the research brief (Topic 3).
  static const List<IecIndustrial> industrial = <IecIndustrial>[
    IecIndustrial(
      color: 'Violet',
      voltage: '20-25V',
      use: '24V circuits',
    ),
    IecIndustrial(
      color: 'White',
      voltage: '40-50V',
      use: 'Low-voltage single-phase',
    ),
    IecIndustrial(
      color: 'Yellow',
      voltage: '100-130V',
      use: 'Construction sites and isolated 110V supplies',
    ),
    IecIndustrial(
      color: 'Blue',
      voltage: '200-250V',
      use: 'Single-phase: caravans, marinas, events',
    ),
    IecIndustrial(
      color: 'Red',
      voltage: '380-480V',
      use: 'Three-phase power (covers 400V European and 480V US)',
    ),
    IecIndustrial(
      color: 'Black',
      voltage: '500-1000V',
      use: 'Marine and high-voltage',
    ),
  ];

  /// Plug-vs-connector convention note for the IEC 60320 table. Verified
  /// (research brief). States male/female explicitly per the brief's correction.
  static const String couplerNote =
      'Odd number = the cord connector (female), which slides onto the device. '
      'Even number = the appliance inlet (male), mounted on the equipment, '
      'numbered one greater than its mating connector. A C13 connector (female, '
      'on the cord) mates with a C14 inlet (male, on the back of the PC or PDU). '
      'Ratings shown are the coupler-class maxima per the standard; a specific '
      'cord may be rated lower.';

  /// Provenance footnote for the IEC 60320 table.
  static const String couplerFootnote =
      'IEC 60320 appliance couplers. The "kettle cord" nickname properly belongs '
      'to C15/C16 (the 120 degC hot-condition coupler with the keying notch), '
      'not C13/C14 (the 70 degC cold-condition "PC cord").';

  /// Clock-position keying note for the IEC 60309 table. Verified (research
  /// brief), including the configuration-dependent caveat.
  static const String industrialNote =
      'Color encodes the voltage band; the earth-pin clock position (in 30 '
      'degree steps) is mechanical keying so incompatible voltages cannot mate. '
      'Both the color AND the earth-pin hour must match for two devices to '
      'connect. Common positions: 6h for blue 230V single-phase and red 400V '
      'three-phase, 4h for yellow 110V, 9h for some blue split-phase. Pin counts '
      'are 2P+E (single-phase), 3P+E (three-phase, no neutral), and 3P+N+E (the '
      'common four-pole-plus-earth). Exact clock positions vary by pole count '
      'and region: verify against IEC 60309-2 for anything beyond the common '
      'cases.';

  /// Provenance footnote for the IEC 60309 table.
  static const String industrialFootnote =
      'IEC 60309 industrial connectors. Red spans 380-480V (it is not a single '
      '"415V"): it covers 400V European and 480V US three-phase.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IEC Power Connectors'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the IEC 60320 couplers,
        // then the IEC 60309 industrial bands. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as two TSV sections. Section 1 is the
  /// IEC 60320 coupler table (pair, current, max temp, nickname, use); section 2
  /// is the IEC 60309 industrial table (color, voltage, use). The "degC" suffix
  /// and ASCII ranges carry straight through so the pasted text stays plain-text
  /// safe (no degree glyph). Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('IEC Power Connectors')
      ..writeln()
      ..writeln('IEC 60320 appliance couplers')
      ..writeln(
        <String>[
          'Coupler',
          'Current',
          'Max temp',
          'Nickname',
          'Common use',
        ].join(tab),
      );
    for (final IecCoupler c in couplers) {
      buf.writeln(
        <String>[
          c.pair,
          c.current,
          c.maxTemp,
          c.nickname,
          c.use,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(couplerNote)
      ..writeln()
      ..writeln(couplerFootnote)
      ..writeln()
      ..writeln('IEC 60309 industrial connectors')
      ..writeln(
        <String>['Color', 'Voltage', 'Typical use'].join(tab),
      );
    for (final IecIndustrial i in industrial) {
      buf.writeln(
        <String>[i.color, i.voltage, i.use].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(industrialNote)
      ..writeln()
      ..writeln(industrialFootnote);
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
                  // The connector-face diagram slot — renders only when the SVG
                  // is bundled; otherwise the page reads fully on the tables
                  // below (graceful degradation). A later graphics pass fills it.
                  _DiagramBand(
                    assetName: IecConnectorsDiagrams.connectors,
                    isDesktop: isDesktop,
                  ),
                  if (IecConnectorsDiagrams.has(IecConnectorsDiagrams.connectors))
                    const SizedBox(height: AppSpacing.md),
                  _couplersCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _industrialCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'iec-connectors'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _couplersCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'IEC 60320 appliance couplers',
      note: couplerNote,
      footnote: couplerFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Coupler', width: 96),
          _HeaderCell('Current', width: 72),
          _HeaderCell('Max temp', width: 80),
          _HeaderCell('Nickname', width: 168),
          _HeaderCell('Common use', width: 280),
        ],
      ),
      rows: couplers.map((IecCoupler c) {
        return ReferenceRowSemantics(
          label: rowLabel(c.pair, <String?>[
            c.current,
            'max ${c.maxTemp}',
            c.nickname,
            c.use,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    c.pair,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    c.current,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    c.maxTemp,
                    style: mono.inlineCode.copyWith(
                      // The 120 degC hot-condition coupler is the one people
                      // misremember; tint it accent to draw the eye.
                      color: c.maxTemp == '120 degC'
                          ? colors.textAccent
                          : colors.textSecondary,
                      fontWeight: c.maxTemp == '120 degC'
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    c.nickname,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: Text(
                    c.use,
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

  Widget _industrialCard(
      AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'IEC 60309 industrial connectors',
      note: industrialNote,
      footnote: industrialFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Color', width: 88),
          _HeaderCell('Voltage', width: 104),
          _HeaderCell('Typical use', width: 304),
        ],
      ),
      rows: industrial.map((IecIndustrial i) {
        return ReferenceRowSemantics(
          label: rowLabel(i.color, <String?>[i.voltage, i.use]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 88,
                  child: Text(
                    i.color,
                    style: text.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Text(
                    i.voltage,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 304,
                  child: Text(
                    i.use,
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

/// The connector-face diagram band. Renders the bundled SVG
/// (`assets/tool-graphics/iec-connectors.svg`) inside a recessed band when it is
/// bundled, and collapses to nothing (SizedBox.shrink) when it is not — so the
/// page ships fully working as tables before the connector-face graphics pass
/// lands. Decorative for screen readers: every fact a diagram depicts (the
/// keying notch, the clock position) is also in the tables and the notes per
/// GL-003 §8.6.2 a11y rule.
///
/// LIGHT/DARK (GL-003 §8.20.7): diagrams are authored DARK-BAKED (scaffold/lime
/// hexes that read on #1A1A1A but fail contrast on white if drawn raw). So this
/// widget reuses the SAME §8.20.7 recolor path the §8.6.2 concept graphics and
/// the Power Phasing waveforms use, via the single-source swap
/// [ConceptGraphicBand.applyLightSwap]:
///   * DARK: render the unmodified asset (byte-for-byte; dark goldens unaffected).
///   * LIGHT: load the SVG source, apply the §8.20.7 allow-list hex swap, then
///     render via SvgPicture.string. Cached per asset name so the replace runs
///     once, not on every rebuild.
class _DiagramBand extends StatelessWidget {
  const _DiagramBand({required this.assetName, required this.isDesktop});

  final String assetName;
  final bool isDesktop;

  // §8.6.2 band-height token: 140dp mobile / 160dp tablet-desktop.
  static const double _bandHeightMobile = 140;
  static const double _bandHeightDesktop = 160;

  // Per-asset cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per diagram, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  /// Loads the diagram SVG source and applies the §8.20.7 allow-list light swap,
  /// caching per asset name. Returns the recolored source string.
  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[assetName] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(IecConnectorsDiagrams.path(assetName));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[assetName] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled diagram → render nothing, layout unchanged.
    if (!IecConnectorsDiagrams.has(assetName)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightDiagramSvg(future: _loadSwappedSvg(), bandHeight: bandHeight)
        : SvgPicture.asset(
            IecConnectorsDiagrams.path(assetName),
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

/// Light-mode diagram render: awaits the §8.20.7-swapped SVG source, then draws
/// it with `SvgPicture.string`. Collapses to nothing while loading or on any
/// parse failure — same graceful-degradation contract as the dark asset path, so
/// no broken-image box or layout jump ever appears. Mirrors `_LightWaveformSvg`
/// in power_phasing_screen.dart and `_LightConceptSvg` in concept_graphic_band.dart.
class _LightDiagramSvg extends StatelessWidget {
  const _LightDiagramSvg({required this.future, required this.bandHeight});

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
