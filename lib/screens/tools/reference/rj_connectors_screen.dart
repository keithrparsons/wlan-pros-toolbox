// RJ Connector Types — read-only reference of the registered-jack connector
// form factors (RJ11, RJ14, RJ25, RJ45/8P8C, RJ48, RJ48C, RJ48X), each with its
// positions/conductors, the modular body it uses, and its typical use.
//
// This table is about the CONNECTOR FORM FACTOR — positions, conductors, and
// what each jack is for. It deliberately does NOT duplicate the T568A/T568B
// pin-to-pair-color wiring; that lives in the Ethernet Cable & Connector tool's
// RJ-45 pinout section, which this screen cross-links to (a tappable card that
// routes to /tools/ethernet-cable).
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success": the
// compile-time const dataset always renders. No loading/empty/error path
// because nothing is fetched or parsed at runtime, and the dataset is never
// empty.
//
// Pattern: matches standards_screen / osi_model_screen — Scaffold + AppBar
// (toolbarHeight 64), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView, cards from
// app_tokens, ValueRow data rows, AppCopyAction (§8.16), ToolHelpFooter
// (§8.16.1), ReferenceRowSemantics for one-node-per-row AT.
//
// EPISTEMIC HONESTY (GL-005 + Truthfulness Audit): "RJ45" is the colloquial name
// for the 8-position 8-conductor (8P8C) modular connector used for Ethernet —
// strictly, "RJ45" was a specific telephone wiring standard, and the data
// connector is properly the 8P8C modular jack. The intro states this accurately
// rather than asserting RJ45 IS 8P8C without qualification. The "PnCm" notation
// (e.g. 6P4C) means an n-position body populated with m conductors. Source:
// the registered-jack (USOC) interface standards and the modular-connector
// (8P8C / 6P*C) form-factor conventions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/connector_diagrams.dart';
import '../../../data/tool_assets.dart';
import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../network/value_row.dart';
import 'reference_row_semantics.dart';

/// One registered-jack / modular-connector reference entry.
@immutable
class RjConnectorEntry {
  const RjConnectorEntry({
    required this.name,
    required this.modular,
    required this.positions,
    required this.conductors,
    required this.typicalUse,
    required this.diagramId,
  });

  /// Connector designation, e.g. `RJ45`.
  final String name;

  /// Stable diagram asset id. Resolves the per-connector line drawing at
  /// `assets/connector-diagrams/<diagramId>.svg` via [ConnectorDiagrams],
  /// gated on the build-time asset manifest so a missing file degrades
  /// silently (matches the coax/antenna-connector diagram pattern).
  final String diagramId;

  /// Modular-body notation, e.g. `8P8C` (8 positions, 8 conductors) or
  /// `6P2C` (6-position body, 2 conductors populated).
  final String modular;

  /// Number of physical positions in the body.
  final int positions;

  /// Number of conductors (pins) actually populated.
  final int conductors;

  /// Plain-language typical use.
  final String typicalUse;
}

class RjConnectorsScreen extends StatelessWidget {
  const RjConnectorsScreen({super.key});

  /// The RJ / modular-connector dataset. Public + static const so tests assert
  /// against the same single source the UI renders. Ordered by ascending body
  /// size / family. Form-factor data only — NO T568A/B pin colors (those live
  /// in the Ethernet Cable & Connector pinout section).
  static const List<RjConnectorEntry> connectors = <RjConnectorEntry>[
    RjConnectorEntry(
      name: 'RJ11',
      modular: '6P2C',
      positions: 6,
      conductors: 2,
      typicalUse: 'Single analog phone line (one pair). The common home '
          'telephone / DSL jack.',
      diagramId: 'rj11',
    ),
    RjConnectorEntry(
      name: 'RJ14',
      modular: '6P4C',
      positions: 6,
      conductors: 4,
      typicalUse: 'Two phone lines (two pairs) in the same 6-position body as '
          'RJ11.',
      diagramId: 'rj14',
    ),
    RjConnectorEntry(
      name: 'RJ25',
      modular: '6P6C',
      positions: 6,
      conductors: 6,
      typicalUse: 'Three phone lines (three pairs), fully populated '
          '6-position body. Sometimes loosely called RJ12.',
      diagramId: 'rj25',
    ),
    RjConnectorEntry(
      name: 'RJ45 (8P8C)',
      modular: '8P8C',
      positions: 8,
      conductors: 8,
      typicalUse: 'Ethernet (10/100/1000/2.5G/5G/10GBASE-T) over twisted pair. '
          '"RJ45" is the colloquial name for the 8P8C modular connector.',
      diagramId: 'rj45-8p8c',
    ),
    RjConnectorEntry(
      name: 'RJ48',
      modular: '8P8C',
      positions: 8,
      conductors: 8,
      typicalUse: 'T1 / E1 / ISDN / DDS over twisted pair. Same 8P8C body as '
          'RJ45 but a different pin assignment (and often shielded).',
      diagramId: 'rj48',
    ),
    RjConnectorEntry(
      name: 'RJ48C',
      modular: '8P8C',
      positions: 8,
      conductors: 8,
      typicalUse: 'T1 on a standard wall jack; the most common RJ48 variant. '
          'Uses pins 1/2 (Rx) and 4/5 (Tx).',
      diagramId: 'rj48c',
    ),
    RjConnectorEntry(
      name: 'RJ48X',
      modular: '8P8C',
      positions: 8,
      conductors: 8,
      typicalUse: 'T1 with a shorting bar that loops the line when the plug is '
          'removed, for loopback testing.',
      diagramId: 'rj48x',
    ),
    RjConnectorEntry(
      name: 'RJ9 / RJ22',
      modular: '4P4C',
      positions: 4,
      conductors: 4,
      typicalUse: 'Telephone handset-to-base coil cord (4P4C). Not a wall jack.',
      diagramId: 'rj9-rj22',
    ),
  ];

  static const String intro =
      'Registered-jack connector form factors: positions, conductors, and '
      'typical use. "RJ45" is the colloquial name for the 8-position '
      '8-conductor (8P8C) modular connector used for Ethernet. The "PnCm" '
      'notation means an n-position body with m conductors populated.';

  static const String footnote =
      'This table covers the connector body, not the wiring. For T568A / T568B '
      'pin-to-pair-color wiring on the 8P8C (RJ45) connector, see the Ethernet '
      'Cable & Connector tool.';

  /// §8.16 copy payload — the connectors as TSV (name, modular, positions,
  /// conductors, use). One header row; one tab-separated row per connector.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('RJ Connector Types')
      ..writeln(
        <String>[
          'Connector',
          'Modular',
          'Positions',
          'Conductors',
          'Typical use',
        ].join(tab),
      );
    for (final RjConnectorEntry c in connectors) {
      buf.writeln(
        <String>[
          c.name,
          c.modular,
          '${c.positions}',
          '${c.conductors}',
          c.typicalUse,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(footnote);
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RJ Connectors'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
                  ConceptGraphicBand(
                    toolId: 'rj-connectors',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('rj-connectors'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(colors, context),
                  const SizedBox(height: AppSpacing.sm),
                  ...connectors.map(
                    (RjConnectorEntry c) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _ConnectorCard(entry: c),
                    ),
                  ),
                  _pinoutLinkCard(colors, context),
                  ToolHelpFooter(toolId: 'rj-connectors'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(AppColorScheme colors, BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Text(
        intro,
        style: text.labelMedium?.copyWith(color: colors.textTertiary),
      ),
    );
  }

  /// Cross-link to the Ethernet Cable & Connector tool's RJ-45 pinout — the
  /// T568A/B wiring content this table deliberately does not duplicate. A
  /// focusable, tappable card.
  Widget _pinoutLinkCard(AppColorScheme colors, BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: 'Open Ethernet Cable and Connector tool for T568A and T568B '
            'wiring',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(context)
              .pushNamed(AppRouter.ethernetCable),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface1,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: colors.borderStrong, width: 1),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.cable_outlined,
                  size: 20,
                  color: colors.textAccent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Need the wiring?',
                        style: text.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Open Ethernet Cable & Connector for T568A / T568B '
                        'pin-to-pair-color wiring.',
                        style: text.labelMedium?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One connector card: a header (name + modular badge) over the spec rows.
class _ConnectorCard extends StatelessWidget {
  const _ConnectorCard({required this.entry});

  final RjConnectorEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceRowSemantics(
      // merge:false — the card holds SelectableText ValueRows; keep them
      // individually selectable while the card reads as one labelled container.
      merge: false,
      label: rowLabel(entry.name, <String?>[
        '${entry.modular} modular',
        '${entry.positions} positions',
        '${entry.conductors} conductors',
        entry.typicalUse,
      ]),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    entry.name,
                    style: text.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                _ModularBadge(label: entry.modular),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Divider(color: colors.border, height: 1),
            // Per-connector line drawing (front mating-face view: positions,
            // loaded conductors, latch). Renders only when the SVG is bundled;
            // collapses to nothing otherwise so the data screen ships working
            // even before the drawings land. Decorative for AT (every fact it
            // shows is in the rows + the merged card label) — GL-003 §8.6.2.
            _RjConnectorDiagram(diagramId: entry.diagramId),
            ValueRow(
              label: 'Positions',
              value: '${entry.positions}',
              mono: true,
            ),
            ValueRow(
              label: 'Conductors',
              value: '${entry.conductors}',
              mono: true,
            ),
            ValueRow(label: 'Typical use', value: entry.typicalUse),
          ],
        ),
      ),
    );
  }
}

/// Lime pill carrying the modular-body notation (e.g. "8P8C").
class _ModularBadge extends StatelessWidget {
  const _ModularBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
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
          color: colors.textAccent,
        ),
      ),
    );
  }
}

/// The per-connector RJ diagram slot. Renders the bundled SVG line drawing
/// (`assets/connector-diagrams/<diagramId>.svg`) inside a card-styled band when
/// one exists, and collapses to nothing when it does not — so the data screen
/// ships fully working even before the drawings land. Decorative for screen
/// readers (every fact it depicts is already in the card's rows + the merged
/// `ReferenceRowSemantics` label), per GL-003 §8.6.2.
///
/// LIGHT/DARK (GL-003 §8.20.7): the drawings are authored DARK-BAKED on the
/// concept-graphic swap-list hexes (#E5E5E5 / #9C9C9C / #A2CC3A) plus the
/// domain-canonical gold (#C9A227) for the gold contacts, which passes the swap
/// unchanged because the color IS the data. On a light surface a raw lime stroke
/// is ~1.65:1, so this reuses the single-source §8.20.7 recolor path
/// ([ConceptGraphicBand.applyLightSwap]) — identical treatment to the antenna /
/// coax connector diagrams:
///   * DARK: render the unmodified asset (dark goldens unaffected).
///   * LIGHT: load the source, apply the §8.20.7 allow-list hex swap, render via
///     `SvgPicture.string`. The swapped string is cached per diagram id.
class _RjConnectorDiagram extends StatelessWidget {
  const _RjConnectorDiagram({required this.diagramId});

  /// 120dp band — the drawings are a 400×200 (2:1) front-face view; capped so a
  /// card stays scannable. Scales to width, never crops.
  static const double _bandHeight = 120;

  // Per-id cache of the already-swapped light SVG source so the §8.20.7 string
  // replace runs once per diagram, not on every rebuild.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  final String diagramId;

  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[diagramId] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(ConnectorDiagrams.path(diagramId));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[diagramId] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    if (!ConnectorDiagrams.has(diagramId)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;

    final Widget svg = colors.isLight
        ? _LightRjSvg(future: _loadSwappedSvg(), bandHeight: _bandHeight)
        : SvgPicture.asset(
            ConnectorDiagrams.path(diagramId),
            fit: BoxFit.contain,
            width: double.infinity,
            height: _bandHeight,
            excludeFromSemantics: true,
            // A bundled-but-unparseable SVG collapses to nothing rather than
            // surfacing a broken-image box.
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: ExcludeSemantics(
        child: SizedBox(
          height: _bandHeight,
          width: double.infinity,
          child: Center(child: svg),
        ),
      ),
    );
  }
}

/// Light-mode RJ-diagram render: awaits the §8.20.7-swapped SVG source, then
/// draws it with `SvgPicture.string`. Collapses to nothing while loading or on
/// any parse failure — same graceful-degradation contract as the dark asset
/// path, so no broken-image box or layout jump ever appears.
class _LightRjSvg extends StatelessWidget {
  const _LightRjSvg({required this.future, required this.bandHeight});

  final Future<String> future;
  final double bandHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) {
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

/// Shared surface-1 card with the standard border, radius, and padding.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
