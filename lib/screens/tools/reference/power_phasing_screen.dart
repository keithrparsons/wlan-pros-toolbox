// Power Phasing — read-only reference for the three power topologies a field
// tech meets in IT spaces, and the 208-vs-240 distinction installers confuse.
//
// PILOT page for the "Power & Cooling" reference category (page 1 of 6). It
// establishes the template the other five pages follow: typed const datasets,
// a §8.16 AppCopyAction that emits the whole page as sectioned TSV, the
// LayoutBuilder / ConstrainedBox / SingleChildScrollView scaffold shared by
// every reference screen (poe_reference_screen is the closest sibling), and a
// ToolHelpFooter keyed on the catalog id.
//
// What's different from a single-graphic reference: this page carries THREE
// named waveform graphics (one per topology), not one per-tool concept graphic.
// They are resolved by explicit asset name through PowerPhasingDiagrams (the
// manifest-gated resolver, mirroring ConnectorDiagrams) and rendered by the
// shared _WaveformBand, which reuses the §8.20.7 light-mode recolor path
// (ConceptGraphicBand.applyLightSwap) exactly as the Antenna Connectors diagram
// slot does. Each band degrades to nothing when its SVG is not yet bundled, so
// the page ships fully working before Charta's SVGs land.
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, Topic 2),
// sourced to NEC Article 100/210 nominal voltages, split-phase and three-phase
// EE references, and the V_LL = sqrt(3) x V_LN relationship. Facts only.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. There is no loading/empty/error
// path because nothing is fetched or parsed at runtime; the waveform bands carry
// their own absent-asset empty state (render nothing). GL-008 network/subprocess
// rules do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): "Access Point" never "router"; degrees spelled
// out in prose, "degrees" symbol-free in copy payload; ASCII hyphen-minus only,
// never an em dash; US spelling; sqrt(3) written "the square root of 3" in prose
// and "≈ 208" with the math-approx glyph in the comparison table.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/power_phasing_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One power-topology entry — the three systems a tech meets at a panel.
/// Field values are verified against Pax's research brief (Topic 2).
@immutable
class PowerTopology {
  const PowerTopology({
    required this.name,
    required this.assetName,
    required this.hots,
    required this.lineToNeutral,
    required this.lineToLine,
    required this.phaseAngle,
    required this.where,
    required this.notes,
  });

  /// Display name, e.g. `Split-phase 120/240V`.
  final String name;

  /// The waveform SVG asset name for this topology (one of
  /// [PowerPhasingDiagrams.all]). Resolved through the manifest-gated resolver.
  final String assetName;

  /// Number of hot legs, e.g. `One`, `Two`, `Three`.
  final String hots;

  /// Line-to-neutral (hot-to-neutral) voltage, e.g. `120V`.
  final String lineToNeutral;

  /// Line-to-line (hot-to-hot) voltage, e.g. `240V`. `'—'` when there is only
  /// one hot (single-phase 120V has no hot-to-hot pair).
  final String lineToLine;

  /// Phase angle between hots, e.g. `180 deg`. `'—'` when there is one hot.
  final String phaseAngle;

  /// Where it is typically seen.
  final String where;

  /// Short clarifying note rendered under the topology card.
  final String notes;
}

/// One row of the 208-vs-240 comparison — the page's load-bearing distinction.
@immutable
class PhasingComparison {
  const PhasingComparison({
    required this.attribute,
    required this.split240,
    required this.wye208,
  });

  /// What is being compared, e.g. `Hot-to-hot voltage`.
  final String attribute;

  /// The split-phase 240V value.
  final String split240;

  /// The three-phase wye 208V value.
  final String wye208;
}

class PowerPhasingScreen extends StatelessWidget {
  const PowerPhasingScreen({super.key});

  /// The three topologies, in render order. Verified against the research brief.
  static const List<PowerTopology> topologies = <PowerTopology>[
    PowerTopology(
      name: 'Single-phase 120V',
      assetName: PowerPhasingDiagrams.single120v,
      hots: 'One',
      lineToNeutral: '120V',
      lineToLine: '—',
      phaseAngle: '—',
      where: 'Standard receptacle circuits',
      notes:
          'One hot plus a neutral, nominal 120V. The everyday wall outlet '
          'circuit feeding most Access Points and edge gear.',
    ),
    PowerTopology(
      name: 'Split-phase 120/240V',
      assetName: PowerPhasingDiagrams.split240v,
      hots: 'Two',
      lineToNeutral: '120V',
      lineToLine: '240V',
      phaseAngle: '180 deg',
      where: 'North American residential and light-commercial service',
      notes:
          'A center-tapped transformer secondary: two hot legs 180 degrees '
          'apart relative to the shared neutral. 240V hot-to-hot, 120V '
          'hot-to-neutral on each leg. This is still single-phase, not '
          'two-phase, and the center conductor is a current-carrying neutral, '
          'not the equipment ground.',
    ),
    PowerTopology(
      name: 'Three-phase wye 208V',
      assetName: PowerPhasingDiagrams.three208v,
      hots: 'Three',
      lineToNeutral: '120V',
      lineToLine: '208V',
      phaseAngle: '120 deg',
      where: 'Commercial buildings and data centers (208V/120V wye panels)',
      notes:
          'Three hots 120 degrees apart. 120V line-to-neutral, 208V '
          'line-to-line. The line-to-line voltage is the square root of 3 '
          'times the line-to-neutral voltage: 120 x 1.732 ≈ 208V.',
    ),
  ];

  /// The 208-vs-240 comparison — the single most-confused power fact for
  /// installers. Verified against the research brief comparison table.
  static const List<PhasingComparison> comparison = <PhasingComparison>[
    PhasingComparison(
      attribute: 'Phase angle between hots',
      split240: '180 deg',
      wye208: '120 deg',
    ),
    PhasingComparison(
      attribute: 'Hot-to-hot voltage',
      split240: '240V',
      wye208: '208V',
    ),
    PhasingComparison(
      attribute: 'Hot-to-neutral',
      split240: '120V',
      wye208: '120V',
    ),
    PhasingComparison(
      attribute: 'Source',
      split240: 'Single-phase, center-tapped',
      wye208: 'Two legs of a 3-phase wye',
    ),
    PhasingComparison(
      attribute: 'Math',
      split240: '2 x 120 (anti-phase)',
      wye208: 'sqrt(3) x 120 ≈ 208',
    ),
  ];

  /// The why-it-matters note beneath the comparison. Verified (research brief).
  static const String comparisonNote =
      '208V and 240V are not interchangeable. Two legs of a 208V wye system '
      'are 120 degrees apart, so hot-to-hot is the square root of 3 times 120, '
      'which is about 208V, not 240V. Equipment nameplated for 240V '
      'single-phase runs at roughly 13 percent lower voltage on 208V; heaters '
      'and motors run at reduced output, and some gear may trip.';

  /// Provenance footnote shown at the foot of the comparison card.
  static const String footnote =
      'Nominal voltages per NEC Article 100/210. Split-phase legs are 180 '
      'degrees apart; three-phase wye legs are 120 degrees apart.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Power Phasing'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the three topologies,
        // then the 208-vs-240 comparison. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as two TSV sections. Section 1 is the
  /// topology table (system, hots, line-to-neutral, line-to-line, phase angle,
  /// where); section 2 is the 208-vs-240 comparison (attribute, split-phase
  /// 240V, three-phase wye 208V). The "deg" suffix and ASCII "sqrt(3)" carry
  /// straight through so the pasted text stays plain-text safe (no degree or
  /// root glyph). Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Power Phasing')
      ..writeln()
      ..writeln('Power topologies')
      ..writeln(
        <String>[
          'System',
          'Hots',
          'Line-to-neutral',
          'Line-to-line',
          'Phase angle',
          'Where',
        ].join(tab),
      );
    for (final PowerTopology t in topologies) {
      buf.writeln(
        <String>[
          t.name,
          t.hots,
          t.lineToNeutral,
          t.lineToLine,
          t.phaseAngle,
          t.where,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('208V vs 240V')
      ..writeln(
        <String>[
          'Attribute',
          'Split-phase 240V',
          'Three-phase wye 208V',
        ].join(tab),
      );
    for (final PhasingComparison c in comparison) {
      buf.writeln(
        <String>[c.attribute, c.split240, c.wye208].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(comparisonNote)
      ..writeln()
      ..writeln(footnote);
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
                  // One card per topology: its waveform graphic, the key
                  // voltages, and a clarifying note.
                  for (final PowerTopology t in topologies) ...<Widget>[
                    _TopologyCard(
                      topology: t,
                      isDesktop: isDesktop,
                      colors: colors,
                      text: text,
                      mono: mono,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  // The 208-vs-240 comparison — the load-bearing distinction.
                  _comparisonCard(colors, text, mono),
                  ToolHelpFooter(toolId: 'power-phasing'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _comparisonCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: '208V vs 240V',
      footnote: footnote,
      note: comparisonNote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('', width: 168),
          _HeaderCell('Split-phase 240V', width: 168),
          _HeaderCell('Three-phase wye 208V', width: 192),
        ],
      ),
      rows: comparison.map((PhasingComparison c) {
        return ReferenceRowSemantics(
          label: rowLabel(c.attribute, <String?>[
            'split-phase 240V ${c.split240}',
            'three-phase wye 208V ${c.wye208}',
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 168,
                  child: Text(
                    c.attribute,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 168,
                  child: Text(
                    c.split240,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 192,
                  child: Text(
                    c.wye208,
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

/// One topology card: the waveform band (graceful when absent), the system name,
/// a compact line of key voltages, and a clarifying note. Card surface matches
/// every other reference card (surface1 / 12px radius / 1px hairline / 16px
/// padding).
class _TopologyCard extends StatelessWidget {
  const _TopologyCard({
    required this.topology,
    required this.isDesktop,
    required this.colors,
    required this.text,
    required this.mono,
  });

  final PowerTopology topology;
  final bool isDesktop;
  final AppColorScheme colors;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
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
            topology.name,
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Waveform graphic — renders only when its SVG is bundled; otherwise
          // the card reads fine on the text below (graceful degradation).
          _WaveformBand(assetName: topology.assetName, isDesktop: isDesktop),
          if (PowerPhasingDiagrams.has(topology.assetName))
            const SizedBox(height: AppSpacing.sm),
          // Key voltages in a wrap so they never overflow a phone-width card.
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _Spec(label: 'Hots', value: topology.hots, colors: colors,
                  text: text, mono: mono),
              _Spec(label: 'L-N', value: topology.lineToNeutral, colors: colors,
                  text: text, mono: mono),
              if (topology.lineToLine != '—')
                _Spec(label: 'L-L', value: topology.lineToLine, colors: colors,
                    text: text, mono: mono, accent: true),
              if (topology.phaseAngle != '—')
                _Spec(label: 'Phase', value: topology.phaseAngle, colors: colors,
                    text: text, mono: mono),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            topology.where,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            topology.notes,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A label-over-value spec chip (e.g. "L-L / 240V"). The value is DM Mono so
/// voltages align with the rest of the app's numeric register; the optional
/// [accent] flag tints the hot-to-hot value lime to draw the eye to the
/// 208-vs-240 number.
class _Spec extends StatelessWidget {
  const _Spec({
    required this.label,
    required this.value,
    required this.colors,
    required this.text,
    required this.mono,
    this.accent = false,
  });

  final String label;
  final String value;
  final AppColorScheme colors;
  final TextTheme text;
  final AppMonoText mono;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: mono.inlineCode.copyWith(
            color: accent ? colors.textAccent : colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// The waveform-diagram band for one topology. Renders the bundled SVG
/// (`assets/tool-graphics/<asset-name>.svg`) inside a recessed band when it is
/// bundled, and collapses to nothing (SizedBox.shrink) when it is not — so the
/// page ships fully working before Charta's waveforms land. Decorative for
/// screen readers: every fact a waveform depicts is also in the card's text
/// (voltages, phase angle, note) per GL-003 §8.6.2 a11y rule.
///
/// LIGHT/DARK (GL-003 §8.20.7): the waveforms are authored DARK-BAKED (the
/// scaffold/lime hexes that read on #1A1A1A but fail contrast on white if drawn
/// raw). So this widget reuses the SAME §8.20.7 recolor path the §8.6.2 concept
/// graphics and the Antenna Connectors diagrams use, via the single-source swap
/// [ConceptGraphicBand.applyLightSwap]:
///   * DARK: render the unmodified asset (byte-for-byte; dark goldens unaffected).
///   * LIGHT: load the SVG source, apply the §8.20.7 allow-list hex swap, then
///     render via SvgPicture.string. Cached per asset name so the replace runs
///     once, not on every rebuild.
class _WaveformBand extends StatelessWidget {
  const _WaveformBand({required this.assetName, required this.isDesktop});

  final String assetName;
  final bool isDesktop;

  // §8.6.2 band-height token: 140dp mobile / 160dp tablet-desktop. A waveform
  // is wider than tall, so it sits comfortably inside the concept-graphic band
  // height and never crops.
  static const double _bandHeightMobile = 140;
  static const double _bandHeightDesktop = 160;

  // Per-asset cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per waveform, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  /// Loads the waveform SVG source and applies the §8.20.7 allow-list light
  /// swap, caching per asset name. Returns the recolored source string.
  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[assetName] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(PowerPhasingDiagrams.path(assetName));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[assetName] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    // Graceful fallback: no bundled waveform → render nothing, layout unchanged.
    if (!PowerPhasingDiagrams.has(assetName)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightWaveformSvg(future: _loadSwappedSvg(), bandHeight: bandHeight)
        : SvgPicture.asset(
            PowerPhasingDiagrams.path(assetName),
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

/// Light-mode waveform render: awaits the §8.20.7-swapped SVG source, then draws
/// it with `SvgPicture.string`. Collapses to nothing while loading or on any
/// parse failure — same graceful-degradation contract as the dark asset path, so
/// no broken-image box or layout jump ever appears. Mirrors `_LightConceptSvg`
/// in concept_graphic_band.dart.
class _LightWaveformSvg extends StatelessWidget {
  const _LightWaveformSvg({required this.future, required this.bandHeight});

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
/// poe_reference_screen / wifi_channels_screen overflow-safe idiom.
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
