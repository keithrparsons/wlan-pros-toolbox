// Antenna Connectors — a data-driven, searchable, grouped reference of the
// antenna and RF connectors a Wi-Fi engineer meets in the field, fully offline
// (bundled JSON asset). RF Connectors merged into this single tool 2026-06-06
// (BF6-18); F-Type (75 ohm CATV) was folded in from the former RF Connectors
// card. Count is data-driven (connector_count in the JSON).
//
// Mirrors the app's bundled-JSON reference pattern (Wi-Fi Glossary / Well-Known
// Ports): bundled asset → AntennaConnectorService.fromJson → grouped list
// screen. The connectors render in their curated groups in file order (never
// alphabetized), each row showing the connector name, full name, an optional
// reverse-polarity chip, and its labeled fields (typical Wi-Fi use,
// indoor/outdoor, coupling, impedance, frequency, mating) plus field notes. A
// free-text search field filters the rendered rows live, matching the app's
// other list/reference search UX (case-insensitive substring across every field,
// SC 4.1.3 live count announcement).
//
// THREE EDITORIAL SECTIONS render below the table, verbatim from the dataset:
//   1. Enterprise Wi-Fi vendor trends (vendor → typical connector)
//   2. Size order, largest → smallest (+ its caveat note)
//   3. The top-6 connectors a Wi-Fi engineer actually meets (teaching list)
//
// DART: the dataset names DART as Cisco's descriptive "Cisco Smart Antenna
// Connector (DART)". Cisco does not publish an official expansion; the JSON
// `notes` field surfaces the commonly-cited "Digital Analog Radio Termination"
// but flags it "unverified by Cisco" (GL-005). This screen renders that copy
// verbatim and never asserts an expansion as fact. (Comment reconciled to the
// data in Wave-2 finding H: the dataset DOES cite the hedged expansion.)
//
// PER-CONNECTOR DIAGRAM SLOT: each connector renders an optional SVG line
// diagram (assets/connector-diagrams/<id>.svg) when one is bundled, resolved by
// ConnectorDiagrams against the asset manifest. Until Charta's diagrams land,
// the slot is omitted and the data screen ships fully working. The integration
// point is the _ConnectorDiagram widget — drop the SVGs in + uncomment the
// pubspec directory and they appear, no further wiring.
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner + AT announce.
//  - error   → the bundled asset failed to load/parse (should not happen in a
//    shipped build); an honest message card.
//  - success → groups with connector rows + the editorial sections, OR the
//    filtered subset.
//  - empty   → a query that matches nothing; an honest "no match" card.
//
// Copy affordance (§8.16): the AppBar carries AppCopyAction — copies the current
// view (filtered subset if searching, else the full reference) as plain text,
// grouped, with the editorial sections appended when unfiltered.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/connector_diagrams.dart';
import '../../../data/connector_photos.dart';
import '../../../data/connector_sections.dart';
import '../../../services/connectors/antenna_connector_service.dart';
import '../concept_graphic_band.dart' show ConceptGraphicBand;
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Asset path for the bundled Antenna Connectors reference. Overridable in tests
/// so a fixture string can stand in for the bundled asset.
const String kAntennaConnectorsAsset = 'assets/data/antenna_connectors.json';

class AntennaConnectorsScreen extends StatefulWidget {
  const AntennaConnectorsScreen({super.key, this.service});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final AntennaConnectorService? service;

  @override
  State<AntennaConnectorsScreen> createState() =>
      _AntennaConnectorsScreenState();
}

class _AntennaConnectorsScreenState extends State<AntennaConnectorsScreen> {
  final TextEditingController _queryCtrl = TextEditingController();

  AntennaConnectorService? _service;
  String? _loadError;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _service = widget.service;
    } else {
      _loadAsset();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    try {
      final String raw = await rootBundle.loadString(kAntennaConnectorsAsset);
      final AntennaConnectorService svc =
          AntennaConnectorService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the connector reference: $e');
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final AntennaConnectorService? svc = _service;
    if (svc == null) return;
    // SC 4.1.3 — announce the live result count so AT users hear the list change
    // as they type, without focus leaving the field.
    final int n = svc.search(value).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching connectors' : '$n matching connector${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the current view (filtered subset if searching, else
  /// the full reference) as plain text, grouped by section. The three editorial
  /// sections are appended only on the unfiltered view. `null` until the service
  /// has loaded or when nothing matches the query, so copy renders disabled in
  /// those states (§8.16 empty/no-results rule).
  String? _buildCopyText() {
    final AntennaConnectorService? svc = _service;
    if (svc == null) return null;
    final List<AntennaConnector> filtered = svc.search(_query);
    if (filtered.isEmpty) return null;
    final bool unfiltered = _query.trim().isEmpty;

    final StringBuffer buf = StringBuffer()..writeln(svc.title);
    if (!unfiltered) buf.writeln('Filtered by "${_query.trim()}"');

    for (final AntennaConnectorGroup g in svc.grouped(filtered)) {
      buf
        ..writeln()
        ..writeln(g.group);
      for (final AntennaConnector c in g.connectors) {
        buf
          ..writeln('${c.connector} — ${c.fullName}')
          ..writeln('  Typical use: ${c.typicalWifiUse}')
          ..writeln('  Indoor/outdoor: ${c.indoorOutdoor}')
          ..writeln('  Coupling: ${c.coupling}')
          ..writeln('  Size: ${c.size}')
          ..writeln('  RF path: ${c.rfPath}')
          ..writeln('  Impedance: ${c.impedance}')
          ..writeln('  Frequency: ${c.frequency}')
          ..writeln('  Reverse-polarity: ${c.reversePolarity}')
          ..writeln('  Mating: ${c.mating}')
          ..writeln('  Notes: ${c.notes}');
      }
    }

    if (unfiltered) {
      if (svc.vendorTrends.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('Enterprise Wi-Fi vendor trends');
        for (final VendorTrend v in svc.vendorTrends) {
          buf.writeln('${v.vendor}: ${v.commonConnector}');
        }
      }
      if (svc.sizeOrder.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('Size order (largest to smallest)');
        buf.writeln(svc.sizeOrder.join(' > '));
        if (svc.sizeOrderNote.isNotEmpty) buf.writeln(svc.sizeOrderNote);
      }
      if (!svc.troubleshootingTop6.isEmpty) {
        buf
          ..writeln()
          ..writeln('Top 6 connectors in the field');
        if (svc.troubleshootingTop6.intro.isNotEmpty) {
          buf.writeln(svc.troubleshootingTop6.intro);
        }
        for (final TopConnector t in svc.troubleshootingTop6.connectors) {
          buf.writeln('${t.connector} — ${t.context}');
        }
        if (svc.troubleshootingTop6.coverageNote.isNotEmpty) {
          buf.writeln(svc.troubleshootingTop6.coverageNote);
        }
      }
    }

    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Antenna Connectors'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        if (_loadError != null) {
          return _PaddedMessage(
            edge: edge,
            icon: Icons.error_outline,
            title: 'Reference unavailable',
            body: _loadError!,
          );
        }

        final AntennaConnectorService? svc = _service;
        if (svc == null) {
          return Padding(
            padding: EdgeInsets.all(edge),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: Semantics(
                  label: 'Loading connector reference',
                  liveRegion: true,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.textAccent,
                  ),
                ),
              ),
            ),
          );
        }

        final AppMonoText mono =
            Theme.of(context).extension<AppMonoText>() ??
                AppMonoText.defaults();
        final List<AntennaConnector> filtered = svc.search(_query);
        final List<AntennaConnectorGroup> groups = svc.grouped(filtered);
        final bool unfiltered = _query.trim().isEmpty;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              children: <Widget>[
                _IntroCard(
                  total: svc.count,
                  groups: svc.groupCount,
                  intro: svc.intro,
                ),
                const SizedBox(height: AppSpacing.sm),
                _SearchField(
                  controller: _queryCtrl,
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (groups.isEmpty)
                  _NoMatch(query: _query.trim())
                else
                  ..._groupWidgets(groups, mono),
                // The three editorial sections render only on the unfiltered
                // view — they are reference context, not search hits.
                if (unfiltered && groups.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  // Polarity explained — the standard-vs-reverse-polarity
                  // teaching diagram (the single most-confused connector fact).
                  _PolaritySection(),
                  const SizedBox(height: AppSpacing.lg),
                  // At-a-glance comparison table: connector / size / RF path /
                  // typical use. Scrolls horizontally on phone, never clipped.
                  _ComparisonTableSection(connectors: svc.all),
                  const SizedBox(height: AppSpacing.lg),
                  _VendorTrendsSection(trends: svc.vendorTrends, mono: mono),
                  const SizedBox(height: AppSpacing.lg),
                  // Size order list + the to-scale size-comparison diagram.
                  _SizeOrderSection(
                    order: svc.sizeOrder,
                    note: svc.sizeOrderNote,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Top6Section(top6: svc.troubleshootingTop6),
                ],
                ToolHelpFooter(toolId: 'antenna-connectors'),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _groupWidgets(
    List<AntennaConnectorGroup> groups,
    AppMonoText mono,
  ) {
    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final AntennaConnectorGroup group = groups[g];
      out.add(_GroupHeader(group: group.group, count: group.count));
      out.add(const SizedBox(height: AppSpacing.xs));
      for (int i = 0; i < group.connectors.length; i++) {
        out.add(_ConnectorCard(connector: group.connectors[i], mono: mono));
        if (i < group.connectors.length - 1) {
          out.add(const SizedBox(height: AppSpacing.xs));
        }
      }
      if (g < groups.length - 1) {
        out.add(const SizedBox(height: AppSpacing.lg));
      }
    }
    return out;
  }
}

/// One-line reference intro + counts.
class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.total,
    required this.groups,
    required this.intro,
  });

  final int total;
  final int groups;
  final String intro;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String summary =
        '$total antenna and RF connectors across $groups groups. Search by '
        'name, vendor, coupling, frequency, or any word in a note.';
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
            summary,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          if (intro.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              intro,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// In-screen search field (§8.4 input spec).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      textField: true,
      label: 'Search antenna connectors by name, vendor, coupling, or notes',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        // 16px field text dodges iOS Safari auto-zoom (§8.4).
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: colors.textPrimary),
        cursorColor: colors.textAccent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: colors.textTertiary),
          hintText: 'Search connectors…',
        ),
      ),
    );
  }
}

/// A group header with a count chip (matches the reference section-header
/// register: H3 title + neutral count pill).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.count});

  final String group;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: '$group, $count connector${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                group,
                style: text.headlineSmall?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$count',
                style: text.labelLarge?.copyWith(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One connector card: name + full name + optional RP chip on the title line, an
/// optional diagram slot, then the labeled fields and field notes. Read-only —
/// no tap target, so no focus ring; announced as one coherent screen-reader node
/// via ReferenceRowSemantics.
class _ConnectorCard extends StatelessWidget {
  const _ConnectorCard({required this.connector, required this.mono});

  final AntennaConnector connector;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // Screen-reader summary: name, full name, then the key fields read in order.
    final String srLabel = rowLabel(connector.connector, <String?>[
      connector.fullName,
      if (connector.isReversePolarity) 'reverse polarity',
      'typical use ${connector.typicalWifiUse}',
      connector.indoorOutdoor,
      'coupling ${connector.coupling}',
      if (connector.size.isNotEmpty) 'size ${connector.size}',
      if (connector.rfPath.isNotEmpty) 'RF path ${connector.rfPath}',
      'impedance ${connector.impedance}',
      'frequency ${connector.frequency}',
      'mating ${connector.mating}',
      connector.notes,
    ]);

    return ReferenceRowSemantics(
      label: srLabel,
      merge: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Title line: connector name + optional RP chip.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    connector.connector,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (connector.isReversePolarity) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  const _RpChip(),
                ],
              ],
            ),
            if (connector.fullName.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                connector.fullName,
                style: text.labelMedium?.copyWith(color: colors.textTertiary),
              ),
            ],
            // Optional real, freely-licensed connector PHOTO. Renders only for
            // the connectors with a vetted CC0/PD photo; omitted (zero cost)
            // for the rest — N-Type, TNC and RP-TNC keep their line diagram and
            // get no photo (GL-005: only show a photo we actually have).
            _ConnectorPhoto(connectorId: connector.id),
            // Optional per-connector line diagram. Renders only when bundled;
            // omitted (zero layout cost) otherwise.
            _ConnectorDiagram(connectorId: connector.id),
            const SizedBox(height: AppSpacing.xs),
            // Labeled fields.
            _Field(label: 'Typical use', value: connector.typicalWifiUse),
            _Field(label: 'Indoor/out', value: connector.indoorOutdoor),
            _Field(label: 'Coupling', value: connector.coupling, mono: mono),
            _Field(label: 'Size', value: connector.size, mono: mono),
            _Field(label: 'RF path', value: connector.rfPath),
            _Field(label: 'Impedance', value: connector.impedance, mono: mono),
            _Field(label: 'Frequency', value: connector.frequency, mono: mono),
            _Field(label: 'Mating', value: connector.mating),
            if (connector.notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                connector.notes,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The reverse-polarity chip. A short neutral pill that flags an RP variant;
/// carries its own text label, so the cue is never color-only (GL-003 §8.13).
class _RpChip extends StatelessWidget {
  const _RpChip();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Reverse polarity variant',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          'RP',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// The per-connector diagram integration point. Renders the bundled SVG line
/// diagram (`assets/connector-diagrams/<id>.svg`) inside a card-styled band when
/// one exists, and collapses to nothing (SizedBox.shrink) when it does not — so
/// the data screen ships fully working before Charta's diagrams land. Decorative
/// for screen readers: every fact a diagram depicts is already in the card's
/// text fields (GL-003 §8.6.2 a11y rule).
///
/// LIGHT/DARK (GL-003 §8.20.7): the diagrams are authored DARK-BAKED — they use
/// the concept-graphic scaffold/lime hexes (#E5E5E5 / #9C9C9C / #A2CC3A), which
/// read correctly on the #1A1A1A dark surface but FAIL contrast on a light
/// surface if drawn raw (a lime stroke on white is ~1.65:1). So this widget
/// reuses the SAME §8.20.7 recolor path the §8.6.2 concept graphics use, via the
/// single-source-of-truth swap [ConceptGraphicBand.debugApplyLightSwap]:
///   * DARK: render the unmodified asset (byte-for-byte, dark goldens unaffected).
///   * LIGHT: load the SVG source, apply the §8.20.7 allow-list hex swap
///     (#A2CC3A → #5A7A1C darkened lime, scaffold/muted neutrals → text-safe
///     light values), then render via SvgPicture.string. The swapped string is
///     cached per connector id so the replace runs once, not on every rebuild.
class _ConnectorDiagram extends StatelessWidget {
  const _ConnectorDiagram({required this.connectorId});

  /// 200dp diagram band — wide enough for a side-by-side cutaway, capped so a
  /// long card stays scannable. Scales to width, never crops.
  static const double _bandHeight = 200;

  // Per-id cache of the already-swapped light SVG source, so the §8.20.7 string
  // replace runs once per connector, not on every rebuild. Keyed on connector
  // id (each diagram is its own asset, unlike the per-tool concept-graphic
  // cache).
  static final Map<String, String> _lightSvgCache = <String, String>{};

  final String connectorId;

  /// Loads the diagram SVG source and applies the §8.20.7 allow-list light swap,
  /// caching per connector id. Returns the recolored source string.
  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[connectorId] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(ConnectorDiagrams.path(connectorId));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[connectorId] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    if (!ConnectorDiagrams.has(connectorId)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;

    // DARK: unmodified asset (dark render unchanged). LIGHT: load + §8.20.7 swap
    // + render via string so no raw lime stroke ever hits a light surface.
    final Widget svg = colors.isLight
        ? _LightConnectorSvg(
            future: _loadSwappedSvg(),
            bandHeight: _bandHeight,
          )
        : SvgPicture.asset(
            ConnectorDiagrams.path(connectorId),
            fit: BoxFit.contain,
            width: double.infinity,
            height: _bandHeight,
            excludeFromSemantics: true,
            // A bundled-but-unparseable SVG collapses to nothing rather than
            // surfacing a broken-image box.
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: SizedBox(
            height: _bandHeight,
            width: double.infinity,
            child: Center(child: svg),
          ),
        ),
      ),
    );
  }
}

/// Light-mode connector-diagram render: awaits the §8.20.7-swapped SVG source,
/// then draws it with `SvgPicture.string`. Collapses to nothing while loading or
/// on any parse failure — same graceful-degradation contract as the dark asset
/// path, so no broken-image box or layout jump ever appears. Mirrors
/// `_LightConceptSvg` in concept_graphic_band.dart.
class _LightConnectorSvg extends StatelessWidget {
  const _LightConnectorSvg({required this.future, required this.bandHeight});

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

/// The per-connector PHOTO slot. Renders a real, freely-licensed photo
/// (`assets/connector-photos/<id>.jpg`) inside a card-styled band when one is
/// bundled AND vetted (ConnectorPhotos.has), and collapses to nothing otherwise
/// — so connectors with no CC0/PD photo (N-Type, TNC, RP-TNC) show no photo and
/// no placeholder. A quiet courtesy-credit line sits beneath the photo.
///
/// A11y (GL-003 §8.13): unlike the decorative line diagrams, a photo is
/// informative, so it carries real `Semantics(image: true, label: alt)` from the
/// vetted metadata — never an unlabeled image node. The credit line is read as
/// ordinary text after the image.
///
/// LIGHT/DARK: a photo is a fixed raster; it is not recolored. It renders the
/// same bytes in both modes inside the theme-driven card surface (the card
/// border/fill follow context.colors). The shipped photos are clean, light
/// studio-style shots that read on both surfaces.
class _ConnectorPhoto extends StatelessWidget {
  const _ConnectorPhoto({required this.connectorId});

  /// 180dp photo band — tall enough to recognize the connector, capped so a card
  /// stays scannable. The image scales to fit (BoxFit.contain), never crops.
  static const double _bandHeight = 180;

  final String connectorId;

  @override
  Widget build(BuildContext context) {
    if (!ConnectorPhotos.has(connectorId)) {
      return const SizedBox.shrink();
    }
    final ConnectorPhotoMeta? meta = ConnectorPhotos.meta(connectorId);
    if (meta == null) return const SizedBox.shrink();

    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The photo carries its own image semantics (alt text) — informative,
            // not decorative.
            Semantics(
              image: true,
              label: meta.alt,
              child: SizedBox(
                height: _bandHeight,
                width: double.infinity,
                child: Image.asset(
                  ConnectorPhotos.path(connectorId),
                  fit: BoxFit.contain,
                  // A decode failure collapses to nothing rather than a broken
                  // box — same graceful contract as the diagram slot.
                  errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Quiet courtesy credit. The shipped set is CC0/PD/free-use so this
            // is not legally required, but it is good practice and reads as
            // ordinary caption text after the image.
            Text(
              'Photo: ${meta.credit}',
              style: text.labelMedium?.copyWith(
                color: colors.textTertiary,
                fontSize: AppTextSize.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labeled field row inside a connector card: a fixed-width caption and the
/// value. The value uses Expanded so long text wraps instead of overflowing at
/// narrow width. A `mono` value renders in the identifier mono token (coupling /
/// impedance / frequency read as scanned data).
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.mono});

  final String label;
  final String value;
  final AppMonoText? mono;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? valueStyle = mono != null
        ? mono!.inlineCode.copyWith(color: colors.textSecondary)
        : text.labelMedium?.copyWith(color: colors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }
}

/// Editorial section: enterprise Wi-Fi vendor trends (vendor → typical
/// connector), rendered as labeled rows inside a section card.
class _VendorTrendsSection extends StatelessWidget {
  const _VendorTrendsSection({required this.trends, required this.mono});

  final List<VendorTrend> trends;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _SectionCard(
      heading: 'Enterprise Wi-Fi vendor trends',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < trends.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            ReferenceRowSemantics(
              label: '${trends[i].vendor}: ${trends[i].commonConnector}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    trends[i].vendor,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    trends[i].commonConnector,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Editorial section: size order, largest → smallest, as a numbered ladder with
/// the dataset's caveat note beneath.
class _SizeOrderSection extends StatelessWidget {
  const _SizeOrderSection({required this.order, required this.note});

  final List<String> order;
  final String note;

  @override
  Widget build(BuildContext context) {
    if (order.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _SectionCard(
      heading: 'Size order, largest to smallest',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // To-scale size-comparison diagram (Charta), recolored for light.
          const _SectionDiagram(sectionKey: ConnectorSections.sizeComparison),
          for (int i = 0; i < order.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}.',
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      order[i],
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (note.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              note,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Editorial section: the top-6 connectors a Wi-Fi engineer actually meets, as a
/// teaching list (intro + connector → context rows + coverage note).
class _Top6Section extends StatelessWidget {
  const _Top6Section({required this.top6});

  final TroubleshootingTop6 top6;

  @override
  Widget build(BuildContext context) {
    if (top6.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _SectionCard(
      heading: 'Top 6 connectors in the field',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (top6.intro.isNotEmpty) ...<Widget>[
            Text(
              top6.intro,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (int i = 0; i < top6.connectors.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.xxs),
            ReferenceRowSemantics(
              label:
                  '${top6.connectors[i].connector}: ${top6.connectors[i].context}',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    top6.connectors[i].connector,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (top6.connectors[i].context.isNotEmpty)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Text(
                          top6.connectors[i].context,
                          style: text.labelMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (top6.coverageNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              top6.coverageNote,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Editorial section: "Polarity explained" — Charta's standard-vs-reverse-
/// polarity teaching diagram, the single most-confused connector fact. The
/// diagram is decorative for screen readers (every fact it shows is also in the
/// caption + the RP chips + each card's mating field), so it carries the same
/// caption text beneath for AT. Renders nothing if the diagram is not bundled.
class _PolaritySection extends StatelessWidget {
  const _PolaritySection();

  @override
  Widget build(BuildContext context) {
    if (!ConnectorSections.has(ConnectorSections.polarityExplained)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _SectionCard(
      heading: 'Polarity explained',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionDiagram(
            sectionKey: ConnectorSections.polarityExplained,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Reverse polarity (RP) swaps the gender of the center contact, not '
            'the outer thread. An RP connector threads onto its standard '
            'counterpart but the center contacts do not connect electrically.',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Editorial section: an at-a-glance comparison TABLE — connector / size / RF
/// path / typical use, populated from the dataset (size + rf_path fields). It
/// scrolls horizontally on phone via [HorizontalScrollTable] (always-visible
/// scrollbar, Vera web-demo gate) so the columns are never clipped at narrow
/// width. Each row's first cell carries the full row summary for screen readers
/// and the rest are excluded, so AT reads one coherent node per connector
/// (mirrors the MCS Index table's DataTable a11y treatment).
class _ComparisonTableSection extends StatelessWidget {
  const _ComparisonTableSection({required this.connectors});

  final List<AntennaConnector> connectors;

  @override
  Widget build(BuildContext context) {
    if (connectors.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle headStyle = (text.labelMedium ?? const TextStyle())
        .copyWith(color: colors.textTertiary, letterSpacing: 0.4);

    final DataTable table = DataTable(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 56,
      columnSpacing: AppSpacing.md,
      horizontalMargin: 0,
      dividerThickness: 1,
      headingTextStyle: headStyle,
      columns: const <DataColumn>[
        DataColumn(label: Text('Connector')),
        DataColumn(label: Text('Size')),
        DataColumn(label: Text('RF path')),
        DataColumn(label: Text('Typical use')),
      ],
      rows: connectors.map((AntennaConnector c) {
        final String summary = rowLabel(c.connector, <String?>[
          if (c.size.isNotEmpty) 'size ${c.size}',
          if (c.rfPath.isNotEmpty) 'RF path ${c.rfPath}',
          if (c.typicalWifiUse.isNotEmpty) 'typical use ${c.typicalWifiUse}',
        ]);
        return DataRow(
          cells: <DataCell>[
            DataCell(
              Semantics(
                label: summary,
                container: true,
                child: ExcludeSemantics(
                  child: Text(
                    c.connector,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  c.size.isEmpty ? '—' : c.size,
                  style: mono.inlineCode.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: Text(
                  c.rfPath.isEmpty ? '—' : c.rfPath,
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
            DataCell(
              ExcludeSemantics(
                child: ConstrainedBox(
                  // Cap the free-text column so a long use line wraps to two
                  // rows instead of pushing the table absurdly wide.
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    c.typicalWifiUse.isEmpty ? '—' : c.typicalWifiUse,
                    style:
                        text.bodyMedium?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );

    return _SectionCard(
      heading: 'Compare at a glance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Size is the connector body width (across-flats for threaded parts, '
            'outer diameter for board-level parts), an approximate recognition '
            'aid. Scroll sideways to see every column.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          HorizontalScrollTable(child: table),
        ],
      ),
    );
  }
}

/// Shared render for an editorial SECTION diagram (Charta's full-width teaching
/// SVGs). Mirrors the per-connector diagram slot's light/dark treatment: DARK
/// renders the unmodified asset; LIGHT loads the source and applies the §8.20.7
/// allow-list swap (via the single-source-of-truth [ConceptGraphicBand.
/// applyLightSwap]) so no raw lime stroke ever hits a light surface. Decorative
/// for screen readers — every fact each diagram depicts is also in the section's
/// caption text. Collapses to nothing while loading, on parse failure, or when
/// the section's SVG is not bundled (no broken box, no layout jump).
class _SectionDiagram extends StatelessWidget {
  const _SectionDiagram({required this.sectionKey});

  /// Section-diagram band — taller than a per-connector diagram because these
  /// are denser two-row / multi-connector teaching figures. Scales to width,
  /// never crops.
  static const double _bandHeight = 240;

  // Per-key cache of the already-swapped light SVG source.
  static final Map<String, String> _lightSvgCache = <String, String>{};

  final String sectionKey;

  Future<String> _loadSwappedSvg() async {
    final String cached = _lightSvgCache[sectionKey] ?? '';
    if (cached.isNotEmpty) return cached;
    final String raw =
        await rootBundle.loadString(ConnectorSections.path(sectionKey));
    final String swapped = ConceptGraphicBand.applyLightSwap(raw);
    _lightSvgCache[sectionKey] = swapped;
    return swapped;
  }

  @override
  Widget build(BuildContext context) {
    if (!ConnectorSections.has(sectionKey)) {
      return const SizedBox.shrink();
    }
    final AppColorScheme colors = context.colors;

    final Widget svg = colors.isLight
        ? _LightConnectorSvg(
            future: _loadSwappedSvg(),
            bandHeight: _bandHeight,
          )
        : SvgPicture.asset(
            ConnectorSections.path(sectionKey),
            fit: BoxFit.contain,
            width: double.infinity,
            height: _bandHeight,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => const SizedBox.shrink(),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: colors.border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: SizedBox(
            height: _bandHeight,
            width: double.infinity,
            child: Center(child: svg),
          ),
        ),
      ),
    );
  }
}

/// Shared section-card surface for the three editorial blocks — matches the
/// reference card idiom (surface1 fill, card radius, hairline border, a quiet
/// uppercase-register heading).
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.heading, required this.child});

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
          Semantics(
            header: true,
            child: Text(
              heading,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// In-screen no-results state when the live filter matches nothing.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isEmpty
                ? 'No connectors loaded.'
                : 'No connectors match "$query".',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// An error / message card with leading icon (mirrors the reference message-card
/// register).
class _PaddedMessage extends StatelessWidget {
  const _PaddedMessage({
    required this.edge,
    required this.icon,
    required this.title,
    required this.body,
  });

  final double edge;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(edge),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    body,
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
    );
  }
}
