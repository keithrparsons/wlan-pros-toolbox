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

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/horizontal_scroll_table.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
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
      dist100G: '100 m',
      notes:
          'Laser-optimized. Current 10G enterprise standard. '
          'Most common new install.',
      legacy: false,
    ),
    FiberType(
      type: 'OM4',
      core: '50/125 µm',
      bandwidth: '4,700',
      jacketHex: 0xFF7B1FA2,
      jacketName: 'Violet/Aqua',
      dist1G: '1 km',
      dist10G: '550 m',
      dist40G: '150 m',
      dist100G: '150 m',
      notes: 'High-bandwidth. Data centers and dense campus runs.',
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
      dist100G: '150 m',
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
      notes: 'Singlemode tight-buffer. Indoor — IDF-to-MDF, campus backbone.',
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
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
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
                  _footnoteCard(text),
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

  Widget _footnoteCard(TextTheme text) {
    return _Card(
      heading: 'Notes',
      headingText: text,
      child: Text(
        footnote,
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: headingText.labelMedium?.copyWith(
              color: AppColors.textSecondary,
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
    final TextStyle? style = text.labelMedium?.copyWith(
      color: AppColors.textTertiary,
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
    // Legacy rows fade to tertiary; current types read at primary text.
    final Color cellColor = fiber.legacy
        ? AppColors.textTertiary
        : AppColors.textSecondary;
    final Color typeColor = fiber.legacy
        ? AppColors.textTertiary
        : AppColors.primary;
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
    final Color typeColor = fiber.legacy
        ? AppColors.textTertiary
        : AppColors.primary;
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
                    border: Border.all(color: AppColors.border, width: 1),
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
                      color: AppColors.textPrimary,
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
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
