// International Power Plugs — read-only reference mapping the IEC World Plugs
// letter system (Type A–O) to the national standards behind each plug, with
// country, voltage class, current rating, and type letter.
//
// Page 4 of 6 in the "Power & Cooling" reference category. It follows the
// template the pilot page (power_phasing_screen.dart) established and the closest
// table sibling (poe_reference_screen.dart): typed const datasets, a §8.16
// AppCopyAction that emits the whole page as sectioned TSV, the LayoutBuilder /
// ConstrainedBox / SingleChildScrollView scaffold shared by every reference
// screen, the wifi_channels overflow-safe HorizontalScrollTable + IntrinsicWidth
// table idiom, and a ToolHelpFooter keyed on the catalog id.
//
// Graphic slot: ONE concept graphic (`assets/tool-graphics/international-plugs`)
// resolved through the manifest-gated PowerPhasingDiagrams resolver — the same
// `assets/tool-graphics/<name>.svg` multi-graphic resolver the pilot uses,
// reused here by explicit asset name so this page adds no new resolver file. The
// band degrades to nothing (renders no SvgPicture) until Charta's face-diagram
// SVG lands in the bundle, so the data page ships fully working today. Face
// diagrams are a later pass; the tables carry every fact without them.
//
// SAFETY (the load-bearing distinction): the "interchangeable Type I cluster"
// (Australia/NZ, China, Argentina) shares the two-flat-blades-in-a-V + earth
// SHAPE but is NOT safely interchangeable — Argentina (IRAM 2073) reverses line
// and neutral relative to Australia/China, so an Australian plug used in
// Argentina energizes the wrong contact. That is rendered as a prominent
// StatusTone.warning callout, using the §8.13/§8.20.4 status-warning idiom the
// wpa/poe pages use (theme-aware statusToneColor border + tinted surface, never
// a baked Color).
//
// Data provenance (GL-005): Pax's verified research brief
// (Deliverables/2026-06-08-power-cooling-references/RESEARCH-BRIEF.md, Topic 5),
// sourced to the IEC World Plugs letter system and the named national standards
// (CEE 7, BS 1363, BS 546, AS/NZS 3112, GB 2099/CPCS-CCC, IRAM 2073, SEV 1011,
// CEI 23-50). The iec.ch World Plugs page returned HTTP 403 to automated fetch,
// so this page cites the underlying national standard numbers, not "per iec.ch".
// Facts only.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const datasets always render. No loading/empty/error path because
// nothing is fetched or parsed at runtime; the concept-graphic band carries its
// own absent-asset empty state (render nothing). GL-008 network/subprocess rules
// do not apply (nothing fetched, nothing shelled out to).
//
// Glyph / copy notes (GL-004): degrees spelled out in prose, no degree glyph in
// the copy payload; ASCII hyphen-minus only, never an em dash; US spelling;
// "Access Point" never "router". The '—' used in lineToLine columns is a
// rendered placeholder, never an em dash in prose.

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

/// One IEC World Plugs letter-type row — type letter mapped to the national
/// standard behind it, with voltage class, current rating, and example
/// countries. Field values are verified against Pax's research brief (Topic 5).
@immutable
class PlugType {
  const PlugType({
    required this.type,
    required this.standard,
    required this.voltageClass,
    required this.current,
    required this.countries,
  });

  /// IEC World Plugs type letter, e.g. `C`, `F`, `G`.
  final String type;

  /// The national standard behind the plug, e.g. `CEE 7/4 (Schuko)`.
  final String standard;

  /// Voltage class, e.g. `230V` or `120V`.
  final String voltageClass;

  /// Current rating, e.g. `16A`, `13A (fused)`, `2.5A`.
  final String current;

  /// Example countries, e.g. `Germany + most of continental Europe`.
  final String countries;
}

/// One CEE 7 family member — the European plug system needs its own breakout
/// because four CEE 7 plugs map to three IEC letters (C, E, F) plus the E/F
/// hybrid that has no distinct letter. Verified against the research brief.
@immutable
class Cee7Member {
  const Cee7Member({
    required this.designation,
    required this.type,
    required this.current,
    required this.note,
  });

  /// CEE 7 designation, e.g. `CEE 7/4`, `CEE 7/16`.
  final String designation;

  /// IEC type letter, or `E/F` for the hybrid that fits both sockets.
  final String type;

  /// Current rating, e.g. `16A`, `2.5A`.
  final String current;

  /// What it is / where it fits.
  final String note;
}

class InternationalPlugsScreen extends StatelessWidget {
  const InternationalPlugsScreen({super.key});

  /// The single concept-graphic asset name for this page, resolved through the
  /// `assets/tool-graphics/<name>.svg` manifest-gated resolver. Face diagrams
  /// land later; until then the band renders nothing (graceful degradation).
  static const String graphicAsset = 'international-plugs';

  /// The IEC World Plugs letter system, in letter order. Verified against the
  /// research brief (Topic 5). Public-static for testing.
  static const List<PlugType> plugTypes = <PlugType>[
    PlugType(
      type: 'A',
      standard: 'NEMA 1-15 (ungrounded)',
      voltageClass: '120V',
      current: '15A',
      countries: 'US, Canada, Japan, Mexico',
    ),
    PlugType(
      type: 'B',
      standard: 'NEMA 5-15 (grounded)',
      voltageClass: '120V',
      current: '15A',
      countries: 'US, Canada',
    ),
    PlugType(
      type: 'C',
      standard: 'CEE 7/16 (Europlug)',
      voltageClass: '230V',
      current: '2.5A',
      countries: 'Europe (widespread, unearthed)',
    ),
    PlugType(
      type: 'D',
      standard: 'BS 546 (5A)',
      voltageClass: '230V',
      current: '5A',
      countries: 'India, around 40 countries',
    ),
    PlugType(
      type: 'E',
      standard: 'CEE 7/5 (French)',
      voltageClass: '230V',
      current: '16A',
      countries: 'France, Belgium, Poland, Czechia',
    ),
    PlugType(
      type: 'F',
      standard: 'CEE 7/4 (Schuko)',
      voltageClass: '230V',
      current: '16A',
      countries: 'Germany + most of continental Europe',
    ),
    PlugType(
      type: 'G',
      standard: 'BS 1363',
      voltageClass: '230V',
      current: '13A (fused)',
      countries: 'UK, Ireland, around 50 countries',
    ),
    PlugType(
      type: 'I',
      standard: 'AS/NZS 3112',
      voltageClass: '230V',
      current: '10A',
      countries: 'Australia, New Zealand',
    ),
    PlugType(
      type: 'I',
      standard: 'CPCS-CCC (GB 2099, China)',
      voltageClass: '230V',
      current: '10A',
      countries: 'China',
    ),
    PlugType(
      type: 'I',
      standard: 'IRAM 2073 (Argentina)',
      voltageClass: '230V',
      current: '10A',
      countries: 'Argentina (line/neutral reversed — see warning)',
    ),
    PlugType(
      type: 'J',
      standard: 'SEV 1011 / SN 441011',
      voltageClass: '230V',
      current: '10A',
      countries: 'Switzerland, Liechtenstein',
    ),
    PlugType(
      type: 'L',
      standard: 'CEI 23-50',
      voltageClass: '230V',
      current: '10 / 16A',
      countries: 'Italy, Chile',
    ),
    PlugType(
      type: 'M',
      standard: 'BS 546 (15A)',
      voltageClass: '230V',
      current: '15A',
      countries: 'South Africa',
    ),
  ];

  /// The CEE 7 European family breakout — four plugs, three letters plus the
  /// E/F hybrid. Verified against the research brief.
  static const List<Cee7Member> cee7Family = <Cee7Member>[
    Cee7Member(
      designation: 'CEE 7/16',
      type: 'C',
      current: '2.5A',
      note: 'Europlug — unearthed, fits most 230V sockets across Europe',
    ),
    Cee7Member(
      designation: 'CEE 7/4',
      type: 'F',
      current: '16A',
      note: 'Schuko — earthed, Germany and most of continental Europe',
    ),
    Cee7Member(
      designation: 'CEE 7/5',
      type: 'E',
      current: '16A',
      note: 'French — earthed, France, Belgium, Poland, Czechia',
    ),
    Cee7Member(
      designation: 'CEE 7/7',
      type: 'E/F',
      current: '16A',
      note: 'Hybrid plug designed to fit both French (E) and Schuko (F) sockets',
    ),
  ];

  /// The Type I safety warning — the load-bearing caveat. Verified (Topic 5).
  /// Rendered in a prominent StatusTone.warning callout, not buried in a row.
  static const String typeIWarningTitle =
      'Type I plugs are not safely interchangeable';

  static const String typeIWarningBody =
      'Australia and New Zealand (AS/NZS 3112), China (CPCS-CCC / GB 2099), and '
      'Argentina (IRAM 2073) all share the Type I two-flat-blades-in-a-V plus '
      'earth shape, but they are not freely interchangeable. Argentina is wired '
      'with the live and neutral contacts reversed relative to Australia and '
      'China, so an Australian plug used in Argentina energizes the wrong '
      'contact. Argentina\'s 10A and 20A variants also differ in pin spacing '
      'and do not intermate, and the Chinese variant has dimensional '
      'differences from the Australasian one. Same family, different polarity '
      'and spacing — do not assume cross-compatibility.';

  /// Provenance + clarifying footnotes shown beneath the main table.
  static const String tableFootnote =
      'Voltage is around 230V across virtually all of Europe, Asia, Oceania, '
      'and South America; A and B are the 120V North American types. BS 546 '
      'appears twice on purpose: Type D is the 5A plug (India), Type M is the '
      '15A plug (South Africa) — same family, different sizes, not '
      'intermateable. Standards per the named national standards behind the IEC '
      'World Plugs letter system.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('International Power Plugs'),
        toolbarHeight: 64,
        // §8.16 — copy the whole page as sectioned TSV: the IEC type table, the
        // CEE 7 European family, then the Type I safety warning. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the full page as TSV sections. Section 1 is the IEC
  /// type table (type, standard, voltage, current, countries); section 2 is the
  /// CEE 7 family (designation, type, current, note); then the Type I safety
  /// warning and the footnote as prose. No degree or em-dash glyph is emitted.
  /// Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('International Power Plugs')
      ..writeln()
      ..writeln('IEC World Plugs letter system')
      ..writeln(
        <String>[
          'Type',
          'Standard',
          'Voltage',
          'Current',
          'Example countries',
        ].join(tab),
      );
    for (final PlugType p in plugTypes) {
      buf.writeln(
        <String>[
          p.type,
          p.standard,
          p.voltageClass,
          p.current,
          p.countries,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('CEE 7 European family')
      ..writeln(
        <String>['Designation', 'Type', 'Current', 'Note'].join(tab),
      );
    for (final Cee7Member m in cee7Family) {
      buf.writeln(
        <String>[m.designation, m.type, m.current, m.note].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('WARNING: $typeIWarningTitle')
      ..writeln(typeIWarningBody)
      ..writeln()
      ..writeln(tableFootnote);
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
                  // Single concept graphic (face diagrams), resolved by explicit
                  // asset name through the tool-graphics resolver. Renders only
                  // when bundled; otherwise collapses to nothing. Face diagrams
                  // are a later pass — the tables carry every fact without them.
                  _PlugGraphicBand(
                    assetName: graphicAsset,
                    isDesktop: isDesktop,
                  ),
                  if (PowerPhasingDiagrams.has(graphicAsset))
                    const SizedBox(height: AppSpacing.md),
                  // The Type I safety warning rides at the top, above the table,
                  // so a tech sees it before scanning the Type I rows.
                  _WarningCallout(
                    title: typeIWarningTitle,
                    body: typeIWarningBody,
                    colors: colors,
                    text: text,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _plugTypeCard(colors, text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _cee7Card(colors, text, mono),
                  ToolHelpFooter(toolId: 'international-plugs'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _plugTypeCard(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'IEC World Plugs letter system',
      footnote: tableFootnote,
      header: const Row(
        children: <Widget>[
          _HeaderCell('Type', width: 48),
          _HeaderCell('Standard', width: 188),
          _HeaderCell('Voltage', width: 72),
          _HeaderCell('Current', width: 88),
          _HeaderCell('Example countries', width: 260),
        ],
      ),
      rows: plugTypes.map((PlugType p) {
        return ReferenceRowSemantics(
          label: rowLabel('Type ${p.type}', <String?>[
            'standard ${p.standard}',
            'voltage ${p.voltageClass}',
            'current ${p.current}',
            p.countries,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 48,
                  child: Text(
                    p.type,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 188,
                  child: Text(
                    p.standard,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    p.voltageClass,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 88,
                  child: Text(
                    p.current,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: Text(
                    p.countries,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
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

  Widget _cee7Card(AppColorScheme colors, TextTheme text, AppMonoText mono) {
    return _TableCard(
      title: 'CEE 7 European family',
      header: const Row(
        children: <Widget>[
          _HeaderCell('Designation', width: 96),
          _HeaderCell('Type', width: 56),
          _HeaderCell('Current', width: 72),
          _HeaderCell('Note', width: 300),
        ],
      ),
      rows: cee7Family.map((Cee7Member m) {
        return ReferenceRowSemantics(
          label: rowLabel(m.designation, <String?>[
            'type ${m.type}',
            'current ${m.current}',
            m.note,
          ]),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 96,
                  child: Text(
                    m.designation,
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    m.type,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    m.current,
                    style: mono.inlineCode.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: Text(
                    m.note,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
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

/// The Type I safety warning, rendered as a prominent callout using the
/// §8.13/§8.20.4 status-warning idiom the wpa/poe pages use: a surface1 card
/// with a 1px [StatusTone.warning] border (resolved at render via
/// [statusToneColor], never a baked Color, so it tracks light/dark), a warning
/// icon tinted to the same status token, and the warning title + body. The
/// status border clears SC 1.4.11 (3:1 non-text) on surface1; all warning text
/// is full-strength textPrimary/textSecondary so contrast does not depend on the
/// status hue.
class _WarningCallout extends StatelessWidget {
  const _WarningCallout({
    required this.title,
    required this.body,
    required this.colors,
    required this.text,
  });

  final String title;
  final String body;
  final AppColorScheme colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final Color warning = colors.statusToneColor(StatusTone.warning);
    return Semantics(
      container: true,
      // Spoken as a single block so the warning is heard before the tables.
      label: 'Warning. $title. $body',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: warning, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: warning, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      body,
                      style: text.bodyMedium?.copyWith(
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
    );
  }
}

/// The single concept-graphic band for this page (plug face diagrams). Renders
/// the bundled SVG (`assets/tool-graphics/<asset-name>.svg`) inside a recessed
/// band when it is bundled, and collapses to nothing (SizedBox.shrink) when it
/// is not — so the page ships fully working before Charta's face diagrams land.
/// Decorative for screen readers: every fact a diagram would depict (type,
/// standard, voltage, current, country) is already in the table text per the
/// GL-003 §8.6.2 a11y rule.
///
/// LIGHT/DARK (GL-003 §8.20.7): the diagram is authored DARK-BAKED, so this
/// widget reuses the SAME §8.20.7 recolor path the §8.6.2 concept graphics and
/// the power-phasing waveforms use, via the single-source swap
/// [ConceptGraphicBand.applyLightSwap]:
///   * DARK: render the unmodified asset (byte-for-byte; dark goldens unaffected).
///   * LIGHT: load the SVG source, apply the §8.20.7 allow-list hex swap, then
///     render via SvgPicture.string. Cached so the replace runs once per build.
///
/// Mirrors `_WaveformBand` in power_phasing_screen.dart exactly, narrowed to one
/// asset.
class _PlugGraphicBand extends StatelessWidget {
  const _PlugGraphicBand({required this.assetName, required this.isDesktop});

  final String assetName;
  final bool isDesktop;

  // §8.6.2 band-height token: 140dp mobile / 160dp tablet-desktop, matching the
  // shared concept-graphic band so the diagram never crops.
  static const double _bandHeightMobile = 140;
  static const double _bandHeightDesktop = 160;

  // Per-asset cache of the already-swapped light SVG source, so the §8.20.7
  // string replace runs once per asset, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  /// Loads the diagram SVG source and applies the §8.20.7 allow-list light swap,
  /// caching per asset name. Returns the recolored source string.
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
    // Graceful fallback: no bundled diagram → render nothing, layout unchanged.
    if (!PowerPhasingDiagrams.has(assetName)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final double bandHeight =
        isDesktop ? _bandHeightDesktop : _bandHeightMobile;

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightPlugSvg(future: _loadSwappedSvg(), bandHeight: bandHeight)
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

/// Light-mode diagram render: awaits the §8.20.7-swapped SVG source, then draws
/// it with `SvgPicture.string`. Collapses to nothing while loading or on any
/// parse failure — same graceful-degradation contract as the dark asset path.
/// Mirrors `_LightWaveformSvg` in power_phasing_screen.dart.
class _LightPlugSvg extends StatelessWidget {
  const _LightPlugSvg({required this.future, required this.bandHeight});

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

/// Card surface wrapping a wide table: title over the grid, a
/// horizontally-scrolling IntrinsicWidth grid (header + rows share one width so
/// columns align), with an optional full-width footnote beneath. Matches the
/// poe_reference_screen / power_phasing_screen / wifi_channels_screen
/// overflow-safe idiom. This page's cards carry footnotes only (no in-card
/// note), so the note slot the pilot uses is dropped here.
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.title,
    required this.header,
    required this.rows,
    this.footnote,
  });

  final String title;
  final Widget header;
  final List<Widget> rows;
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
