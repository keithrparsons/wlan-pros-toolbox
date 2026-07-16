// Fiber Optic Cable Reference — read-only fiber-type reference card.
//
// One static table ported verbatim from the RF Tools PWA (app.js FIBER_DATA,
// view data-tool="fiber"): fiber type, core/cladding, modal bandwidth, jacket
// color code, and supported distance at 1G / 10G / 40G / 100G. Each row also
// carries the PWA's per-type notes line, shown beneath the distance row.
//
// Pure read-only reference — no inputs, no computation, no network. Works on
// every platform (no NetworkUnavailableView). The only state is "success":
// the bundled dataset always renders. No loading, empty, or error path because
// nothing is fetched or parsed at runtime.
//
// OVERFLOW-SAFE: the distance grid is 6 fixed-width columns (type, core, BW,
// @1G/@10G/@40G/@100G) wider than a phone — it lives in a horizontal
// SingleChildScrollView with an IntrinsicWidth body so the cells keep a fixed
// width and never RenderFlex-overflow at 320pt. Jacket color + notes render
// full-width below the scrollable grid so they wrap instead of widening it.
//
// Glyph note: em-dashes from the PWA source ("—" placeholder distances) are
// preserved as DATA glyphs (a real cell value meaning "not supported"), not as
// prose punctuation.

import 'package:flutter/material.dart';

import '../../../data/fiber_connectors_diagrams.dart';
import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'large_face_card.dart';
import 'reference_row_semantics.dart';

/// One fiber type, ported verbatim from PWA app.js FIBER_DATA.
class FiberType {
  const FiberType({
    required this.type,
    required this.core,
    required this.bandwidth,
    required this.jacketHex,
    required this.jacketName,
    required this.dist1G,
    required this.dist10G,
    required this.dist40G,
    required this.dist100G,
    required this.notes,
    required this.legacy,
  });

  /// OM/OS designation (e.g. "OM3", "OS2").
  final String type;

  /// Core/cladding diameter (e.g. "50/125 µm").
  final String core;

  /// Modal bandwidth in MHz·km, or "N/A" for singlemode.
  final String bandwidth;

  /// Jacket color code, hex from the PWA source (a data value, not a token).
  final int jacketHex;

  /// Jacket color name (e.g. "Aqua").
  final String jacketName;

  /// Supported distance at 1 GbE.
  final String dist1G;

  /// Supported distance at 10 GbE.
  final String dist10G;

  /// Supported distance at 40 GbE.
  final String dist40G;

  /// Supported distance at 100 GbE.
  final String dist100G;

  /// Deployment note line from the PWA.
  final String notes;

  /// OM1/OM2 render faded in the PWA (legacy). Drives the dimmed row.
  final bool legacy;
}

/// One fiber connector type. Verified from the 2026-06-08 fiber-connectors
/// research brief (IEC 61754 part numbers + mechanical specs).
@immutable
class FiberConnector {
  const FiberConnector({
    required this.name,
    required this.iec,
    required this.ferrule,
    required this.coupling,
    required this.formFactor,
    required this.use,
  });

  /// Connector designation (e.g. "LC", "MPO / MTP").
  final String name;

  /// IEC 61754 part number (e.g. "61754-20").
  final String iec;

  /// Ferrule size or fiber-count description (e.g. "1.25 mm", "2.5 mm").
  final String ferrule;

  /// Latch / coupling mechanism (e.g. "Bayonet twist-lock").
  final String coupling;

  /// Form factor (simplex, duplex, multi-fiber ribbon).
  final String formFactor;

  /// Typical deployment use.
  final String use;
}

/// One fiber polish / endface type. Verified from the 2026-06-08 research brief.
/// Return-loss figures are typical industry values, not datasheet guarantees.
@immutable
class FiberPolish {
  const FiberPolish({
    required this.name,
    required this.fullName,
    required this.endface,
    required this.returnLoss,
    required this.bodyName,
    required this.bodyHex,
  });

  /// Polish abbreviation (e.g. "APC").
  final String name;

  /// Spelled-out name (e.g. "Angled Physical Contact").
  final String fullName;

  /// Endface geometry description.
  final String endface;

  /// Typical return loss (e.g. "~ -60 dB (best)").
  final String returnLoss;

  /// Connector-body color name, or "Not color-keyed" for legacy PC.
  final String bodyName;

  /// Connector-body color as an ARGB int for the swatch, or null when the
  /// polish is not color-keyed (legacy PC). A data value, not a brand token.
  final int? bodyHex;
}

class FiberOpticScreen extends StatelessWidget {
  const FiberOpticScreen({super.key});

  /// Fiber types — ported verbatim from PWA app.js FIBER_DATA.
  /// Source row order: [type, core, bw, jacketHex, jacketName, d1G, d10G,
  /// d40G, d100G, notes]. OM1/OM2 are flagged legacy (faded in the PWA).
  // ignore: constant_identifier_names
  static const List<FiberType> FIBER_DATA = [
    FiberType(
      type: 'OM1',
      core: '62.5/125 µm',
      bandwidth: '200',
      jacketHex: 0xFFE65100,
      jacketName: 'Orange',
      dist1G: '275 m',
      dist10G: '33 m',
      dist40G: '—',
      dist100G: '—',
      notes: 'Legacy multimode. LED source. Pre-2000 installs.',
      legacy: true,
    ),
    FiberType(
      type: 'OM2',
      core: '50/125 µm',
      bandwidth: '500',
      jacketHex: 0xFFE65100,
      jacketName: 'Orange',
      dist1G: '550 m',
      dist10G: '82 m',
      dist40G: '—',
      dist100G: '—',
      notes: 'Improved multimode. LED/laser. Found in older buildings.',
      legacy: true,
    ),
    FiberType(
      type: 'OM3',
      core: '50/125 µm',
      bandwidth: '2,000',
      jacketHex: 0xFF0097A7,
      jacketName: 'Aqua',
      dist1G: '1 km',
      dist10G: '300 m',
      dist40G: '100 m',
      // 100G = 70 m: modern 100GBASE-SR4 (IEEE 802.3bm) on OM3. Was 100 m,
      // which is the legacy 100GBASE-SR10 (802.3ba, 10-lane) reach. Wave-2
      // finding B; confirmed by optical_transceivers.json (100G-SR4 70/100 m).
      dist100G: '70 m',
      notes:
          'Laser-optimized. Current 10G enterprise standard. '
          'Most common new install.',
      legacy: false,
    ),
    FiberType(
      type: 'OM4',
      core: '50/125 µm',
      bandwidth: '4,700',
      jacketHex: 0xFF0097A7,
      jacketName: 'Aqua',
      dist1G: '1 km',
      dist10G: '550 m',
      dist40G: '150 m',
      // 100G = 100 m: modern 100GBASE-SR4 (IEEE 802.3bm) on OM4. Was 150 m,
      // which is the legacy 100GBASE-SR10 reach (identical to 40G-SR4's OM4
      // number). Wave-2 finding B; confirmed by optical_transceivers.json.
      dist100G: '100 m',
      notes:
          'High-bandwidth. Data centers and dense campus runs. TIA-598-D '
          'assigns OM4 aqua, the same color as OM3; violet (Erika Violet) is a '
          'manufacturer differentiation convention, not the standard, so the '
          'printed jacket legend is the only reliable way to tell OM3 from OM4.',
      legacy: false,
    ),
    FiberType(
      type: 'OM5',
      core: '50/125 µm',
      bandwidth: '4,700',
      jacketHex: 0xFF7CB342,
      jacketName: 'Lime Green',
      dist1G: '1 km',
      dist10G: '550 m',
      dist40G: '150 m',
      // 100G = 100 m: modern 100GBASE-SR4 on OM5. OM5 shares OM4's 4,700
      // MHz·km EMB at 850 nm, so its SR4 reach matches OM4 (100 m); the old
      // 150 m was the legacy SR10 number. Wave-2 finding B (OM5 100G caveat =
      // same as OM4). Kept consistent with the OM4 row above.
      dist100G: '100 m',
      notes:
          'Wideband multimode (SWDM), 400G over 2 fibers. EMB 4,700 MHz·km '
          'at 850 nm (same as OM4); wideband window adds ~1,850-2,470 MHz·km '
          'near 953 nm. Emerging.',
      legacy: false,
    ),
    FiberType(
      type: 'OS1',
      core: '9/125 µm',
      bandwidth: 'N/A',
      jacketHex: 0xFFF9A825,
      jacketName: 'Yellow',
      dist1G: '10+ km',
      dist10G: '10+ km',
      dist40G: '10+ km',
      dist100G: '40+ km',
      notes: 'Singlemode tight-buffer. Indoor. IDF-to-MDF, campus backbone.',
      legacy: false,
    ),
    FiberType(
      type: 'OS2',
      core: '9/125 µm',
      bandwidth: 'N/A',
      jacketHex: 0xFFF9A825,
      jacketName: 'Yellow',
      dist1G: '40+ km',
      dist10G: '40+ km',
      dist40G: '40+ km',
      dist100G: '80+ km',
      notes: 'Singlemode loose-tube. Outdoor inter-building and long-haul.',
      legacy: false,
    ),
  ];

  /// Connector types — verified from the 2026-06-08 fiber-connectors research
  /// brief (IEC 61754 part numbers + mechanical specs, S4/S7). Form factor,
  /// ferrule size, latch/coupling, and typical use per row.
  // ignore: constant_identifier_names
  static const List<FiberConnector> CONNECTOR_DATA = [
    FiberConnector(
      name: 'LC',
      iec: '61754-20',
      ferrule: '1.25 mm',
      coupling: 'Push-pull latch (RJ-style clip)',
      formFactor: 'Simplex + duplex',
      use:
          'Data center and enterprise; SFP/SFP+ transceivers. Dominant today. '
          'The 1.25 mm ferrule gives it the density advantage in the data '
          'center.',
    ),
    FiberConnector(
      name: 'SC',
      iec: '61754-4',
      ferrule: '2.5 mm',
      coupling: 'Push-pull snap',
      formFactor: 'Simplex + duplex',
      use: 'FTTH, telecom, and enterprise patching. Second most common.',
    ),
    FiberConnector(
      name: 'ST',
      iec: '61754-2',
      ferrule: '2.5 mm',
      coupling: 'Bayonet twist-lock',
      formFactor: 'Simplex only',
      use: 'Legacy campus and multimode LANs.',
    ),
    FiberConnector(
      name: 'FC',
      iec: '61754-13',
      ferrule: '2.5 mm',
      coupling: 'Threaded screw nut',
      formFactor: 'Simplex only',
      use: 'Test equipment, precision, and high-vibration installs.',
    ),
    FiberConnector(
      name: 'MPO / MTP',
      iec: '61754-7',
      ferrule: 'Multi-fiber (8 / 12 / 24)',
      coupling: 'Push-pull, keyed (pinned or pin-less)',
      formFactor: 'Multi-fiber ribbon',
      use:
          '40G/100G/400G parallel optics and data-center trunks. MTP is US '
          'Conec\'s branded, tighter-tolerance MPO, mechanically '
          'intermateable with MPO, not a separate standard.',
    ),
  ];

  /// Polish / endface types — verified from the 2026-06-08 research brief
  /// (S1/S2 color + standard, S8 angle/return-loss/mating rule). Return-loss
  /// figures are typical industry values, not per-datasheet guarantees.
  // ignore: constant_identifier_names
  static const List<FiberPolish> POLISH_DATA = [
    FiberPolish(
      name: 'PC',
      fullName: 'Physical Contact',
      endface: 'Slight dome, flat-ish',
      returnLoss: '~ -40 dB',
      bodyName: 'Not color-keyed',
      bodyHex: null,
    ),
    FiberPolish(
      name: 'UPC',
      fullName: 'Ultra Physical Contact',
      endface: 'Finer dome, no angle',
      returnLoss: '~ -50 dB',
      bodyName: 'Blue',
      bodyHex: 0xFF1565C0,
    ),
    FiberPolish(
      name: 'APC',
      fullName: 'Angled Physical Contact',
      endface: '8° angled ferrule',
      returnLoss: '~ -60 dB (best)',
      bodyName: 'Green',
      bodyHex: 0xFF2E7D32,
    ),
  ];

  /// The hard field rule: APC and UPC never mate. Stated as a safety/quality
  /// rule per the research brief (the #1 field error).
  static const String polishRule =
      'APC and UPC never mate. The 8° angled ferrule against a flat ferrule '
      'causes very high insertion loss and can physically damage both '
      'endfaces. APC (green) mates only to APC.';

  /// The two-color-systems caveat: jacket color (TIA-598-D) and connector-body
  /// color (TIA-568/598 convention) are separate systems, and green and aqua
  /// each mean two different things depending on which you are reading.
  static const String twoColorSystemsNote =
      'Two separate color systems exist. Cable jacket color (TIA-598-D) marks '
      'the fiber type: orange for OM1/OM2, aqua for OM3/OM4, lime green for '
      'OM5, yellow for single-mode. Connector body color (TIA-568/598 '
      'convention) marks the polish and mode: blue for single-mode UPC, green '
      'for single-mode APC. Green collides across the two systems: lime-green '
      'jacket means OM5 multimode, while a green connector body means an '
      'angled single-mode APC. Aqua collides the same way (OM3/OM4 jacket and '
      'OM3/OM4 connector body). Always note which system a color belongs to.';

  /// Footnote, ported verbatim from the PWA buildFiberTable() caption.
  static const String footnote =
      'Distances are per TIA-568 / ISO 11801. Actual limits depend on '
      'transceiver, splice count, and connector loss. OM3/OM4 are the current '
      'deployment standards; OM1/OM2 are legacy (faded rows).';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiber Optic'),
        toolbarHeight: 64,
        // §8.16 — copy both sub-tables as TSV (distance-by-rate + jacket color
        // & notes), each its own section. Static data, always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — both fiber sub-tables as a two-section TSV. Section 1
  /// is the distance-by-rate matrix (type, core, BW, @1G/@10G/@40G/@100G);
  /// section 2 is jacket color code + deployment notes. Each section gets a
  /// subtitle + header + one row per fiber type. Always non-null (static data).
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Fiber Optic Reference')
      ..writeln()
      ..writeln('Distance by data rate')
      ..writeln(
        <String>[
          'Type',
          'Core',
          'BW (MHz·km)',
          '@ 1G',
          '@ 10G',
          '@ 40G',
          '@ 100G',
        ].join(tab),
      );
    for (final FiberType f in FIBER_DATA) {
      buf.writeln(
        <String>[
          f.type,
          f.core,
          f.bandwidth,
          f.dist1G,
          f.dist10G,
          f.dist40G,
          f.dist100G,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Jacket color code & notes')
      ..writeln(<String>['Type', 'Jacket color', 'Notes'].join(tab));
    for (final FiberType f in FIBER_DATA) {
      buf.writeln(<String>[f.type, f.jacketName, f.notes].join(tab));
    }
    buf
      ..writeln()
      ..writeln('Connectors')
      ..writeln(
        <String>[
          'Connector',
          'IEC 61754',
          'Ferrule',
          'Coupling',
          'Form factor',
          'Typical use',
        ].join(tab),
      );
    for (final FiberConnector c in CONNECTOR_DATA) {
      buf.writeln(
        <String>[
          c.name,
          c.iec,
          c.ferrule,
          c.coupling,
          c.formFactor,
          c.use,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Polish & endface')
      ..writeln(
        <String>[
          'Polish',
          'Name',
          'Endface',
          'Return loss (typical)',
          'Connector body color',
        ].join(tab),
      );
    for (final FiberPolish p in POLISH_DATA) {
      buf.writeln(
        <String>[
          p.name,
          p.fullName,
          p.endface,
          p.returnLoss,
          p.bodyName,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln(polishRule)
      ..writeln()
      ..writeln(twoColorSystemsNote);
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return LayoutBuilder(
      builder: (context, constraints) {
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
                children: [
                  ConceptGraphicBand(
                    toolId: 'fiber-optic',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('fiber-optic'))
                    const SizedBox(height: AppSpacing.md),
                  _distanceCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _jacketCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  // CONNECTORS + POLISH half (2026-06-08 extension). The three
                  // concept graphics resolve through FiberConnectorsDiagrams,
                  // which is NOT in main.dart's startup ensureLoaded() chain
                  // (central file, off-limits), so this section self-loads the
                  // manifest and rebuilds when it resolves. Tables render
                  // immediately; a graphic folds in only once bundled.
                  _ConnectorsAndPolish(
                    isDesktop: isDesktop,
                    text: text,
                    mono: mono,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(colors, text),
                  ToolHelpFooter(toolId: 'fiber-optic'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Distance-by-rate matrix — wider than a phone, so it scrolls horizontally
  /// with fixed-width cells (overflow-safe). Notes line wraps full-width below.
  Widget _distanceCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'Distance by data rate',
      headingText: text,
      child: HorizontalScrollTable(
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DistanceHeaderRow(text: text),
              const SizedBox(height: AppSpacing.xs),
              for (final FiberType f in FIBER_DATA)
                _DistanceRow(fiber: f, text: text, mono: mono),
            ],
          ),
        ),
      ),
    );
  }

  /// Jacket color code + per-type notes — full-width so they wrap instead of
  /// widening the scrollable distance grid.
  Widget _jacketCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'Jacket color code & notes',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final FiberType f in FIBER_DATA)
            _JacketRow(fiber: f, text: text, mono: mono),
        ],
      ),
    );
  }

  Widget _footnoteCard(AppColorScheme colors, TextTheme text) {
    return _Card(
      heading: 'Notes',
      headingText: text,
      child: Text(
        footnote,
        style: text.labelMedium?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// Shared card surface — matches the dB / port reference idiom.
class _Card extends StatelessWidget {
  const _Card({
    required this.heading,
    required this.headingText,
    required this.child,
  });

  final String heading;
  final TextTheme headingText;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: headingText.labelMedium?.copyWith(
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

// Fixed cell widths for the horizontally-scrolled distance grid. Constant so
// the header and every data row align column-for-column.
const double _kTypeW = 56;
const double _kCoreW = 96;
const double _kBwW = 72;
const double _kRateW = 64;

/// Column header for the distance matrix.
class _DistanceHeaderRow extends StatelessWidget {
  const _DistanceHeaderRow({required this.text});

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
        children: [
          SizedBox(
            width: _kTypeW,
            child: Text('Type', style: style),
          ),
          SizedBox(
            width: _kCoreW,
            child: Text('Core', style: style),
          ),
          SizedBox(
            width: _kBwW,
            child: Text('BW', style: style),
          ),
          SizedBox(
            width: _kRateW,
            child: Text('@ 1G', style: style),
          ),
          SizedBox(
            width: _kRateW,
            child: Text('@ 10G', style: style),
          ),
          SizedBox(
            width: _kRateW,
            child: Text('@ 40G', style: style),
          ),
          SizedBox(
            width: _kRateW,
            child: Text('@ 100G', style: style),
          ),
        ],
      ),
    );
  }
}

/// One fiber row in the distance matrix. Legacy (OM1/OM2) rows render dimmed
/// to mirror the PWA's faded styling.
class _DistanceRow extends StatelessWidget {
  const _DistanceRow({
    required this.fiber,
    required this.text,
    required this.mono,
  });

  final FiberType fiber;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // Legacy rows fade to tertiary; current types read at primary text.
    final Color cellColor = fiber.legacy
        ? colors.textTertiary
        : colors.textSecondary;
    final Color typeColor = fiber.legacy
        ? colors.textTertiary
        : colors.textAccent;
    return ReferenceRowSemantics(
      label: rowLabel(fiber.type, <String?>[
        'core ${fiber.core}',
        'bandwidth ${fiber.bandwidth}',
        'at 1 gigabit ${fiber.dist1G}',
        'at 10 gigabit ${fiber.dist10G}',
        'at 40 gigabit ${fiber.dist40G}',
        'at 100 gigabit ${fiber.dist100G}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _kTypeW,
              child: Text(
                fiber.type,
                style: mono.inlineCode.copyWith(
                  color: typeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: _kCoreW,
              child: Text(
                fiber.core,
                style: mono.inlineCode.copyWith(
                  color: cellColor,
                  fontSize: AppTextSize.caption,
                ),
              ),
            ),
            SizedBox(
              width: _kBwW,
              child: Text(
                fiber.bandwidth,
                style: mono.inlineCode.copyWith(color: cellColor),
              ),
            ),
            _rateCell(fiber.dist1G, cellColor),
            _rateCell(fiber.dist10G, cellColor),
            _rateCell(fiber.dist40G, cellColor),
            _rateCell(fiber.dist100G, cellColor),
          ],
        ),
      ),
    );
  }

  Widget _rateCell(String value, Color color) {
    return SizedBox(
      width: _kRateW,
      child: Text(value, style: mono.inlineCode.copyWith(color: color)),
    );
  }
}

/// One jacket-color row: a color swatch + type + color name on the top line,
/// the deployment note beneath. Full-width so the note wraps.
class _JacketRow extends StatelessWidget {
  const _JacketRow({
    required this.fiber,
    required this.text,
    required this.mono,
  });

  final FiberType fiber;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color typeColor = fiber.legacy
        ? colors.textTertiary
        : colors.textAccent;
    return ReferenceRowSemantics(
      label: rowLabel(fiber.type, <String?>[
        'jacket ${fiber.jacketName}',
        fiber.notes,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Jacket swatch — color is verbatim PWA data, not a brand token.
                // Decorative; the color name beside it carries the meaning for
                // colorblind / AT users (never color-only).
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Color(fiber.jacketHex),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: colors.border, width: 1),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: _kTypeW,
                  child: Text(
                    fiber.type,
                    style: mono.inlineCode.copyWith(
                      color: typeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    fiber.jacketName,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                fiber.notes,
                style: text.labelMedium?.copyWith(
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

/// The CONNECTORS + POLISH half of the page (2026-06-08 extension).
///
/// Renders three sections: a Connectors card (one row per LC/SC/ST/FC/MPO with
/// the connector-faces graphic above), a Polish & endface card (one row per
/// PC/UPC/APC with the APC-8° graphic plus the hard never-mate rule), and a
/// Two color systems card (the jacket-vs-body split graphic plus the green/aqua
/// collision note).
///
/// SELF-LOADING: [FiberConnectorsDiagrams] is not in main.dart's startup
/// ensureLoaded() chain (central file, off-limits for this extension), so this
/// widget kicks off the one-shot manifest load itself and rebuilds when it
/// resolves. The tables render on the first frame regardless; each graphic folds
/// in only after the load completes AND the asset is bundled — identical
/// graceful degradation to the manifest-gated bands elsewhere in the app.
class _ConnectorsAndPolish extends StatefulWidget {
  const _ConnectorsAndPolish({
    required this.isDesktop,
    required this.text,
    required this.mono,
  });

  final bool isDesktop;
  final TextTheme text;
  final AppMonoText mono;

  @override
  State<_ConnectorsAndPolish> createState() => _ConnectorsAndPolishState();
}

class _ConnectorsAndPolishState extends State<_ConnectorsAndPolish> {
  @override
  Widget build(BuildContext context) {
    // No self-loading FutureBuilder: FiberConnectorsDiagrams is now in main.dart's
    // startup ensureLoaded() chain, so has() is populated before this builds. The
    // old self-load FutureBuilder hung pumpAndSettle in widget tests. Tables
    // always render; each graphic folds in when its asset is bundled (has()).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _connectorsCard(),
        const SizedBox(height: AppSpacing.md),
        _polishCard(),
        const SizedBox(height: AppSpacing.md),
        _twoColorSystemsCard(),
      ],
    );
  }

  Widget _connectorsCard() {
    return _Card(
      heading: 'Connectors',
      headingText: widget.text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (FiberConnectorsDiagrams.has(
            FiberConnectorsDiagrams.connectorFaces,
          )) ...<Widget>[
            LargeGraphic(
              assetName: FiberConnectorsDiagrams.connectorFaces,
              path: FiberConnectorsDiagrams.path,
              has: FiberConnectorsDiagrams.has,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final FiberConnector c
              in FiberOpticScreen.CONNECTOR_DATA)
            _ConnectorRow(
              connector: c,
              text: widget.text,
              mono: widget.mono,
            ),
        ],
      ),
    );
  }

  Widget _polishCard() {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Polish & endface',
      headingText: widget.text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (FiberConnectorsDiagrams.has(
            FiberConnectorsDiagrams.apcEndface,
          )) ...<Widget>[
            LargeGraphic(
              assetName: FiberConnectorsDiagrams.apcEndface,
              path: FiberConnectorsDiagrams.path,
              has: FiberConnectorsDiagrams.has,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final FiberPolish p in FiberOpticScreen.POLISH_DATA)
            _PolishRow(polish: p, text: widget.text, mono: widget.mono),
          const SizedBox(height: AppSpacing.sm),
          // The hard never-mate rule, set apart so it reads as a warning, not a
          // table row. Accent border + secondary text — no color-only meaning.
          _RuleCallout(text: FiberOpticScreen.polishRule, colors: colors),
        ],
      ),
    );
  }

  Widget _twoColorSystemsCard() {
    final AppColorScheme colors = context.colors;
    return _Card(
      heading: 'Two color systems',
      headingText: widget.text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (FiberConnectorsDiagrams.has(
            FiberConnectorsDiagrams.twoColorSystems,
          )) ...<Widget>[
            LargeGraphic(
              assetName: FiberConnectorsDiagrams.twoColorSystems,
              path: FiberConnectorsDiagrams.path,
              has: FiberConnectorsDiagrams.has,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            FiberOpticScreen.twoColorSystemsNote,
            style: widget.text.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One connector row: name + IEC part on the top line, then ferrule / form
/// factor / coupling as compact label-value pairs, then the typical-use line.
/// Full-width so the use line wraps. Identifiers (name, IEC, ferrule) are DM
/// Mono; the use prose is sans.
class _ConnectorRow extends StatelessWidget {
  const _ConnectorRow({
    required this.connector,
    required this.text,
    required this.mono,
  });

  final FiberConnector connector;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(connector.name, <String?>[
        'IEC ${connector.iec}',
        'ferrule ${connector.ferrule}',
        'form factor ${connector.formFactor}',
        'coupling ${connector.coupling}',
        connector.use,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  connector.name,
                  style: mono.inlineCode.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'IEC ${connector.iec}',
                    style: mono.inlineCode.copyWith(
                      color: colors.textTertiary,
                      fontSize: AppTextSize.caption,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            _MetaLine(
              label: 'Ferrule',
              value: connector.ferrule,
              text: text,
              mono: mono,
            ),
            _MetaLine(
              label: 'Form factor',
              value: connector.formFactor,
              text: text,
              mono: mono,
            ),
            _MetaLine(
              label: 'Coupling',
              value: connector.coupling,
              text: text,
              mono: mono,
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                connector.use,
                style: text.labelMedium?.copyWith(
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

/// One polish row: a connector-body color swatch + abbreviation + full name on
/// the top line, then endface + return loss as label-value pairs. The swatch is
/// omitted for legacy PC (not color-keyed); the body-color name always shows so
/// meaning never rests on color alone.
class _PolishRow extends StatelessWidget {
  const _PolishRow({
    required this.polish,
    required this.text,
    required this.mono,
  });

  final FiberPolish polish;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return ReferenceRowSemantics(
      label: rowLabel(polish.name, <String?>[
        polish.fullName,
        'endface ${polish.endface}',
        'return loss ${polish.returnLoss}',
        'connector body color ${polish.bodyName}',
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Connector-body color swatch — verbatim convention data, not a
                // brand token. Decorative; the body-color name carries meaning.
                if (polish.bodyHex != null) ...<Widget>[
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Color(polish.bodyHex!),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: colors.border, width: 1),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  polish.name,
                  style: mono.inlineCode.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    polish.fullName,
                    style: text.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            _MetaLine(
              label: 'Endface',
              value: polish.endface,
              text: text,
              mono: mono,
            ),
            _MetaLine(
              label: 'Return loss',
              value: polish.returnLoss,
              text: text,
              mono: mono,
            ),
            _MetaLine(
              label: 'Body color',
              value: polish.bodyName,
              text: text,
              mono: mono,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact label-value line shared by the connector and polish rows: a small
/// sans label, then a DM Mono value (identifiers/specs align in the mono
/// register per GL-003 §8.5).
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.label,
    required this.value,
    required this.text,
    required this.mono,
  });

  final String label;
  final String value;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: text.labelSmall?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: mono.inlineCode.copyWith(
                color: colors.textSecondary,
                fontSize: AppTextSize.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bordered callout for the hard never-mate rule. Reads as a warning, not a
/// table row — accent left border, secondary text. No color-only meaning: the
/// text states the rule in full.
class _RuleCallout extends StatelessWidget {
  const _RuleCallout({required this.text, required this.colors});

  final String text;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final TextTheme theme = Theme.of(context).textTheme;
    return Semantics(
      label: text,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border(
            left: BorderSide(color: colors.textAccent, width: 3),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          text,
          style: theme.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
