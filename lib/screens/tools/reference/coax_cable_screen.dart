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
import '../../../theme/app_color_scheme.dart';
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

  /// Maximum usable frequency in GHz — the TE11 higher-order-mode cutoff
  /// (the physics ceiling above which the coax stops being single-mode).
  /// This is NOT the distributor "max operating frequency" catalog cap
  /// (which the PWA copied and which errs dangerously for LMR-1200).
  /// Cutoff = c / (pi * (D+d)/2 * sqrt(er)); scales inversely with diameter.
  /// Per Wave-2 finding E (Pax, 2026-07-12): values below are L-com
  /// published cutoff-frequency spec rows where available, else computed
  /// with the method validated 3x against L-com's published LMR-200/600/1200
  /// cutoffs.
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
      // VF 66% per Times Microwave / Pasternack LMR-100A-FR datasheet
      // (was 80%; wrong). maxGhz = TE11 cutoff ~62 GHz, computed via the
      // validated method (dielectric dims estimated). Wave-2 finding E §2.3/§2.5.
      impedance: '50Ω',
      vf: 66,
      diameterMm: 3.5,
      maxGhz: 62.0,
      use: 'Pigtails, jumpers, tight bends',
    ),
    CoaxCable(
      name: 'LMR-200',
      // maxGhz = 39 GHz TE11 cutoff (L-com LMR-200 datasheet, published
      // "Cutoff Frequency = 39 GHz"). Wave-2 finding E §2.3.
      impedance: '50Ω',
      vf: 83,
      diameterMm: 6.1,
      maxGhz: 39.0,
      use: 'Short outdoor runs (< 3 m)',
    ),
    CoaxCable(
      name: 'LMR-400',
      // maxGhz = 16.2 GHz TE11 cutoff (L-com LMR-400 datasheet, published
      // "Cutoff Frequency = 16.2 GHz"; validated method computes 16.3).
      // Wave-2 finding E §2.2/§2.3. (NB: the fix-list item #12's "13.6"
      // does not match finding E's published 16.2 — deferring to finding E,
      // the primary-sourced authority, per the task's "confirm against
      // finding E" instruction.)
      impedance: '50Ω',
      vf: 85,
      diameterMm: 10.8,
      maxGhz: 16.2,
      use: 'Standard Wi-Fi / cellular run',
    ),
    CoaxCable(
      name: 'LMR-600',
      // maxGhz = 10.3 GHz TE11 cutoff (L-com LMR-600 datasheet, published
      // "Cutoff Frequency = 10.3 GHz"; validated method computes 10.4).
      // Wave-2 finding E §2.2/§2.3.
      impedance: '50Ω',
      vf: 87,
      diameterMm: 15.2,
      maxGhz: 10.3,
      use: 'Long runs, rooftop / tower',
    ),
    CoaxCable(
      name: 'LMR-900',
      // maxGhz = ~7.0 GHz TE11 cutoff (computed via the validated method
      // from datasheet dimensions; L-com does not publish LMR-900 cutoff).
      // Wave-2 finding E §2.3, High confidence.
      impedance: '50Ω',
      vf: 87,
      diameterMm: 22.9,
      maxGhz: 7.0,
      use: 'Very long runs (> 30 m)',
    ),
    CoaxCable(
      name: 'LMR-1200',
      // maxGhz = 5.2 GHz TE11 cutoff (distributor-published + validated
      // method computes 5.21). THE safety fix: the PWA's 6.0 GHz overstated
      // this — LMR-1200 goes multimode at 5.2 GHz (below 6 GHz Wi-Fi), and
      // Times' own attenuation table stops at 2.5 GHz. Wave-2 finding E §2.3/§2.4.
      impedance: '50Ω',
      vf: 88,
      diameterMm: 30.0,
      maxGhz: 5.2,
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

  /// Footnote. VF text ported from the PWA; the Max GHz clarification is
  /// added in Wave-2 (the column now carries the TE11 mode cutoff, not the
  /// distributor application cap the PWA had copied).
  static const String footnote =
      'VF = velocity factor. Higher VF = slightly lower propagation delay and '
      'loss. Max GHz is the single-mode (TE11) cutoff - above it the cable '
      'goes multimode and loss becomes undefined; note LMR-1200 tops out at '
      '5.2 GHz, below the 6 GHz Wi-Fi band. 75Ω cables (RG-6) are '
      'impedance-mismatched for 50Ω Wi-Fi systems - shown for reference '
      'only. Use the Cable Loss tool for exact attenuation calculations.';

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
                    toolId: 'coax-cable',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('coax-cable'))
                    const SizedBox(height: AppSpacing.md),
                  _tableCard(text, mono),
                  const SizedBox(height: AppSpacing.md),
                  _footnoteCard(colors, text),
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

/// Column header for the spec line: Imp / VF% / Dia mm / Max GHz. The cable
/// name and typical use drop to their own lines per row, so these four numeric
/// columns fit phone width without a horizontal scroll.
class _ColumnHeaderRow extends StatelessWidget {
  const _ColumnHeaderRow({required this.text});

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
    final AppColorScheme colors = context.colors;
    // 75Ω is impedance-mismatched for 50Ω Wi-Fi; the PWA dims it. Reuse the
    // muted text tier so it reads as "reference only" without a new token.
    final bool muted = cable.isMismatched;
    final Color nameColor = muted
        ? colors.textTertiary
        : colors.textPrimary;
    final Color specColor = muted
        ? colors.textTertiary
        : colors.textSecondary;

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
                    // Ω (U+03A9) is absent from DM Mono (inlineCode) and would
                    // render as tofu; the bundled Roboto Mono has it, so the
                    // impedance value routes through that GL-003 mono token.
                    style: mono.robotoMono.copyWith(
                      color: muted ? colors.textTertiary : colors.textAccent,
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
                  color: colors.textTertiary,
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
