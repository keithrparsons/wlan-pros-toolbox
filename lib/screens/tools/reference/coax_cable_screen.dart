// Coax Cable — read-only coaxial cable reference card.
//
// One static table ported verbatim from the RF Tools PWA (app.js COAX_DATA,
// view data-tool="coax"): cable type, impedance, velocity factor, outer
// diameter, max frequency, and typical use. Plus the PWA's footnote (VF
// meaning, 75Ω-mismatch caveat, pointer to the Cable Loss tool).
//
// This is a pure read-only reference — no inputs, no computation, no network.
// It works on every platform (no NetworkUnavailableView). The only state is
// "success": the bundled dataset always renders. There is no loading, empty,
// or error path because nothing is fetched or parsed at runtime.
//
// Overflow-safe: the PWA renders six columns in a horizontally-scrolled table.
// At phone width six columns do not fit, so each cable is one card-internal
// block — a mono spec line (impedance / VF / diameter / max GHz) with the
// cable name and typical use beneath. No horizontal scroll needed; nothing
// can RenderFlex-overflow. Matches the db_reference row idiom.
//
// Glyph note: the Ω (ohm) sign and the × in the footnote are preserved as data
// glyphs verbatim from the PWA. No em dashes; ASCII hyphen-minus only.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One row of the coax reference table. Field order mirrors the PWA
/// COAX_DATA tuple: [name, impedance, vf, diameterMm, maxGhz, use].
class CoaxCable {
  const CoaxCable({
    required this.name,
    required this.impedance,
    required this.vf,
    required this.diameterMm,
    required this.maxGhz,
    required this.use,
  });

  /// Cable type, e.g. "LMR-400".
  final String name;

  /// Characteristic impedance, e.g. "50Ω".
  final String impedance;

  /// Velocity factor as a percent, e.g. 85 means 85% of c.
  final int vf;

  /// Outer diameter in millimeters.
  final double diameterMm;

  /// Maximum usable frequency in GHz.
  final double maxGhz;

  /// Typical-use note.
  final String use;

  /// True for the 75Ω entry the PWA dims — impedance-mismatched for 50Ω
  /// Wi-Fi systems, shown for reference only.
  bool get isMismatched => impedance == '75Ω';
}

class CoaxCableScreen extends StatelessWidget {
  const CoaxCableScreen({super.key});

  /// Coax cable reference. Ported verbatim from PWA app.js COAX_DATA.
  static const List<CoaxCable> coaxData = [
    CoaxCable(
      name: 'RG-58',
      impedance: '50Ω',
      vf: 66,
      diameterMm: 5.0,
      maxGhz: 1.0,
      use: 'Short runs, legacy / test gear',
    ),
    CoaxCable(
      name: 'RG-8/U',
      impedance: '50Ω',
      vf: 66,
      diameterMm: 10.3,
      maxGhz: 1.0,
      use: 'General outdoor, amateur radio',
    ),
    CoaxCable(
      name: 'RG-213',
      impedance: '50Ω',
      vf: 66,
      diameterMm: 10.3,
      maxGhz: 1.0,
      use: 'Mil-spec jacket, same as RG-8',
    ),
    CoaxCable(
      name: 'RG-214',
      impedance: '50Ω',
      vf: 66,
      diameterMm: 10.8,
      maxGhz: 3.0,
      use: 'Double-shielded, low leakage',
    ),
    CoaxCable(
      name: 'LMR-100A',
      impedance: '50Ω',
      vf: 80,
      diameterMm: 3.5,
      maxGhz: 6.0,
      use: 'Pigtails, jumpers, tight bends',
    ),
    CoaxCable(
      name: 'LMR-200',
      impedance: '50Ω',
      vf: 83,
      diameterMm: 6.1,
      maxGhz: 6.0,
      use: 'Short outdoor runs (< 3 m)',
    ),
    CoaxCable(
      name: 'LMR-400',
      impedance: '50Ω',
      vf: 85,
      diameterMm: 10.8,
      maxGhz: 6.0,
      use: 'Standard Wi-Fi / cellular run',
    ),
    CoaxCable(
      name: 'LMR-600',
      impedance: '50Ω',
      vf: 87,
      diameterMm: 15.2,
      maxGhz: 6.0,
      use: 'Long runs, rooftop / tower',
    ),
    CoaxCable(
      name: 'LMR-900',
      impedance: '50Ω',
      vf: 87,
      diameterMm: 22.9,
      maxGhz: 6.0,
      use: 'Very long runs (> 30 m)',
    ),
    CoaxCable(
      name: 'LMR-1200',
      impedance: '50Ω',
      vf: 88,
      diameterMm: 30.0,
      maxGhz: 6.0,
      use: 'Tower base, high-power',
    ),
    CoaxCable(
      name: 'RG-6',
      impedance: '75Ω',
      vf: 82,
      diameterMm: 6.9,
      maxGhz: 1.0,
      use: 'CATV / satellite - NOT for Wi-Fi',
    ),
  ];

  /// Footnote, ported verbatim from the PWA coax view.
  static const String footnote =
      'VF = velocity factor. Higher VF = slightly lower propagation delay and '
      'loss. 75Ω cables (RG-6) are impedance-mismatched for 50Ω Wi-Fi systems '
      '- shown for reference only. Use the Cable Loss tool for exact '
      'attenuation calculations.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coax Cable'),
        toolbarHeight: 64,
        // §8.16 — copy the coax table as TSV. Static data, so always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the coax reference as TSV: a title, the six-column
  /// header, one tab-separated row per cable (every column the card shows,
  /// including the typical-use note), then the footnote section. Always
  /// non-null: the dataset is static, so copy is never disabled.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Coax Cable Types')
      ..writeln(
        <String>[
          'Cable',
          'Impedance',
          'VF %',
          'Diameter (mm)',
          'Max GHz',
          'Typical use',
        ].join(tab),
      );
    for (final CoaxCable c in coaxData) {
      buf.writeln(
        <String>[
          c.name,
          c.impedance,
          '${c.vf}',
          _CoaxRow._fmt(c.diameterMm),
          _CoaxRow._fmt(c.maxGhz),
          c.use,
        ].join(tab),
      );
    }
    buf
      ..writeln()
      ..writeln('Notes')
      ..writeln(footnote);
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
                    toolId: 'coax-cable',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('coax-cable'))
                    const SizedBox(height: AppSpacing.md),
                  _tableCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(text),
                  ToolHelpFooter(toolId: 'coax-cable'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tableCard(TextTheme text, AppMonoText mono) {
    return _Card(
      heading: 'Coax Cable Types',
      headingText: text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ColumnHeaderRow(text: text),
          const SizedBox(height: AppSpacing.xs),
          for (final CoaxCable c in coaxData)
            _CoaxRow(cable: c, text: text, mono: mono),
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

/// Shared card surface — matches the reference-card idiom in db_reference.
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

/// Column header for the spec line: Imp / VF% / Dia mm / Max GHz. The cable
/// name and typical use drop to their own lines per row, so these four numeric
/// columns fit phone width without a horizontal scroll.
class _ColumnHeaderRow extends StatelessWidget {
  const _ColumnHeaderRow({required this.text});

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
          SizedBox(width: 56, child: Text('Imp', style: style)),
          SizedBox(width: 48, child: Text('VF%', style: style)),
          SizedBox(width: 72, child: Text('Dia mm', style: style)),
          Expanded(child: Text('Max GHz', style: style)),
        ],
      ),
    );
  }
}

/// One coax entry: the cable name, then a mono spec line
/// (impedance / VF / diameter / max GHz), then the typical-use note beneath.
/// The 75Ω entry tints muted to mirror the PWA's dimmed reference-only row.
class _CoaxRow extends StatelessWidget {
  const _CoaxRow({required this.cable, required this.text, required this.mono});

  final CoaxCable cable;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    // 75Ω is impedance-mismatched for 50Ω Wi-Fi; the PWA dims it. Reuse the
    // muted text tier so it reads as "reference only" without a new token.
    final bool muted = cable.isMismatched;
    final Color nameColor = muted
        ? AppColors.textTertiary
        : AppColors.textPrimary;
    final Color specColor = muted
        ? AppColors.textTertiary
        : AppColors.textSecondary;

    return ReferenceRowSemantics(
      label: rowLabel(cable.name, <String?>[
        '${cable.impedance} impedance',
        'velocity factor ${cable.vf} percent',
        'diameter ${_fmt(cable.diameterMm)} millimeters',
        'max ${_fmt(cable.maxGhz)} gigahertz',
        cable.use,
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cable.name,
              style: text.bodyLarge?.copyWith(
                color: nameColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    cable.impedance,
                    style: mono.inlineCode.copyWith(
                      color: muted ? AppColors.textTertiary : AppColors.primary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${cable.vf}',
                    style: mono.inlineCode.copyWith(color: specColor),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    _fmt(cable.diameterMm),
                    style: mono.inlineCode.copyWith(color: specColor),
                  ),
                ),
                Expanded(
                  child: Text(
                    _fmt(cable.maxGhz),
                    style: mono.inlineCode.copyWith(color: specColor),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                cable.use,
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

  /// Render whole values without a trailing ".0" so the spec line reads like
  /// the PWA (e.g. "66", "1") while fractional values keep one decimal.
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
