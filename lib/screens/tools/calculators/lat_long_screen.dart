// Lat/Long Conversion tool.
//
// Enter a coordinate as decimal degrees (DD) and read it back in three formats
// for both latitude and longitude:
//   DD  — decimal degrees
//   DDM — degrees + decimal minutes
//   DMS — degrees + minutes + decimal seconds
//
// Behavior matches the RF Tools PWA reference exactly (app.js calcLatLong →
// fmtCoord → ddToDmsParts, lines 156-180):
//   DD  = dd.toFixed(6)
//   DDM = "{deg}° {(min + sec/60).toFixed(4)}' {dir}"
//   DMS = "{deg}° {min}' {sec.toFixed(2)}" {dir}"
// where {dir} is the hemisphere letter (N/S for latitude, E/W for longitude)
// chosen from the sign: dd >= 0 → N/E, dd < 0 → S/W. Degrees/minutes/seconds
// are computed from the ABSOLUTE value (PWA ddToDmsParts), so the sign lives
// only in the direction letter.
//
// Input is decimal degrees, matching the PWA's two number fields. Live
// recompute on every keystroke.
//
// Edge cases (PWA calcLatLong guards):
// - Empty / partial / non-numeric input → blank the outputs, no crash.
// - |latitude|  > 90  → out of range; outputs blank.
// - |longitude| > 180 → out of range; outputs blank.
//
// Pure, no network, no platform APIs. Conversion math lives in static methods
// on the public LatLongScreen class so it is unit-testable against the PWA.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Which axis a coordinate is on. Selects the hemisphere letters (N/S vs E/W)
/// and the valid range (±90 vs ±180), mirroring the PWA `isLat` flag.
enum CoordAxis { latitude, longitude }

/// One coordinate rendered in all three formats. Strings are PWA-exact.
class CoordFormats {
  const CoordFormats({required this.dd, required this.ddm, required this.dms});

  /// Decimal degrees, e.g. "40.712800".
  final String dd;

  /// Degrees decimal minutes, e.g. "40° 42.7680' N".
  final String ddm;

  /// Degrees minutes seconds, e.g. "40° 42' 46.08\" N".
  final String dms;
}

class LatLongScreen extends StatefulWidget {
  const LatLongScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: ddToDmsParts, fmtCoord.

  /// Hemisphere letter for a signed decimal degree on [axis].
  /// PWA fmtCoord: lat → N (>=0) / S; lon → E (>=0) / W.
  static String direction(double dd, CoordAxis axis) {
    switch (axis) {
      case CoordAxis.latitude:
        return dd >= 0 ? 'N' : 'S';
      case CoordAxis.longitude:
        return dd >= 0 ? 'E' : 'W';
    }
  }

  /// Whole degrees from the absolute value (PWA ddToDmsParts.degrees).
  static int degreesPart(double dd) => dd.abs().floor();

  /// Whole minutes from the absolute value (PWA ddToDmsParts.minutes).
  static int minutesPart(double dd) {
    final double abs = dd.abs();
    final double minFull = (abs - abs.floorToDouble()) * 60;
    return minFull.floor();
  }

  /// Fractional seconds from the absolute value (PWA ddToDmsParts.seconds).
  static double secondsPart(double dd) {
    final double abs = dd.abs();
    final double minFull = (abs - abs.floorToDouble()) * 60;
    final int minutes = minFull.floor();
    return (minFull - minutes) * 60;
  }

  /// Decimal minutes for DDM = minutes + seconds/60 (PWA fmtCoord.dm value).
  static double decimalMinutesPart(double dd) {
    return minutesPart(dd) + secondsPart(dd) / 60;
  }

  /// All three PWA-exact format strings for [dd] on [axis]. Returns null when
  /// the value is non-finite or out of range (lat ±90, lon ±180) — the caller
  /// blanks the output, matching the PWA guard.
  static CoordFormats? format(double dd, CoordAxis axis) {
    if (!dd.isFinite) return null;
    final double limit = axis == CoordAxis.latitude ? 90 : 180;
    if (dd.abs() > limit) return null;

    final String dir = direction(dd, axis);
    final int deg = degreesPart(dd);
    final int min = minutesPart(dd);
    final double sec = secondsPart(dd);
    final double decMin = decimalMinutesPart(dd);

    return CoordFormats(
      dd: dd.toStringAsFixed(6),
      ddm: "$deg° ${decMin.toStringAsFixed(4)}' $dir",
      dms: "$deg° $min' ${sec.toStringAsFixed(2)}\" $dir",
    );
  }

  @override
  State<LatLongScreen> createState() => _LatLongScreenState();
}

class _LatLongScreenState extends State<LatLongScreen> {
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lonCtrl = TextEditingController();

  final FocusNode _latFocus = FocusNode();
  final FocusNode _lonFocus = FocusNode();

  // Computed format triples, or null when input is empty / invalid / range.
  CoordFormats? _lat;
  CoordFormats? _lon;

  // Signed decimal: degrees can be negative for S/W. No scientific notation —
  // coordinates are typed by hand, not pasted from instruments.
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
  ];

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _latFocus.dispose();
    _lonFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? lat = _tryParseDouble(_latCtrl.text);
    final double? lon = _tryParseDouble(_lonCtrl.text);
    setState(() {
      _lat = lat == null ? null : LatLongScreen.format(lat, CoordAxis.latitude);
      _lon = lon == null
          ? null
          : LatLongScreen.format(lon, CoordAxis.longitude);
    });
  }

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  /// §8.16 copy payload — the coordinate conversions as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) when neither coordinate is valid:
  /// before any entry, or when both are empty / non-numeric / out of range. A
  /// present coordinate copies all three formats (DD / DDM / DMS); a coordinate
  /// that is absent or out of range is simply omitted (honest blank, GL-005).
  String? _buildCopyText() {
    final CoordFormats? lat = _lat;
    final CoordFormats? lon = _lon;
    if (lat == null && lon == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('Lat / Long');
    if (lat != null) {
      buf
        ..writeln('Latitude DD: ${lat.dd}')
        ..writeln('Latitude DDM: ${lat.ddm}')
        ..writeln('Latitude DMS: ${lat.dms}');
    }
    if (lon != null) {
      buf
        ..writeln('Longitude DD: ${lon.dd}')
        ..writeln('Longitude DDM: ${lon.ddm}')
        ..writeln('Longitude DMS: ${lon.dms}');
    }
    return buf.toString().trimRight();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lat / Long'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until at least one
        // coordinate is valid and in range; copies each present coordinate in
        // all three formats (DD / DDM / DMS) as a labeled text block.
        actions: <Widget>[
          // §8.16 order: copy LEADS, help TRAILS.
          AppCopyAction(textBuilder: _buildCopyText),
          ToolHelpAction(toolId: 'lat-long'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 720;
            final double edge = isDesktop
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return Align(
              alignment: AppSpacing.calculatorVerticalAlignment(constraints),
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
                      // §8.6.2 concept-graphic header band — first child, above
                      // the input card. Self-collapses when no graphic is
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'lat-long',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('lat-long'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formatCard(text, mono),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Latitude',
            hint: '(decimal degrees)',
            semanticLabel: 'Latitude in decimal degrees',
            field: _ddField(
              controller: _latCtrl,
              focusNode: _latFocus,
              hintText: '40.7128',
              monoStyle: mono.outputLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Longitude',
            hint: '(decimal degrees)',
            semanticLabel: 'Longitude in decimal degrees',
            field: _ddField(
              controller: _lonCtrl,
              focusNode: _lonFocus,
              hintText: '-74.0060',
              monoStyle: mono.outputLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ddField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      inputFormatters: _signedDecimal,
      onChanged: (_) => _recompute(),
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(hintText: hintText),
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
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
          _resultBlock('Latitude', _lat, text, mono),
          const SizedBox(height: AppSpacing.md),
          _resultBlock('Longitude', _lon, text, mono),
        ],
      ),
    );
  }

  Widget _resultBlock(
    String heading,
    CoordFormats? f,
    TextTheme text,
    AppMonoText mono,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: text.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _formatRow(heading, 'DD', f?.dd, mono),
        const SizedBox(height: 4),
        _formatRow(heading, 'DDM', f?.ddm, mono),
        const SizedBox(height: 4),
        _formatRow(heading, 'DMS', f?.dms, mono),
      ],
    );
  }

  Widget _formatRow(
    String heading,
    String tag,
    String? value,
    AppMonoText mono,
  ) {
    final bool blank = value == null;
    // One SR node per row: "Latitude DD: 40.712800" (or "not calculated"),
    // instead of tag and value as separate fragments (Vera finding #6). The
    // heading rides along so the format is unambiguous when read aloud.
    return Semantics(
      label: '$heading $tag',
      value: blank ? 'not calculated' : value,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag column snaps to the 8px base unit (GL-003 §4); 56px holds "DDM".
          SizedBox(
            width: 56,
            child: Text(
              tag,
              style: mono.inlineCode.copyWith(color: AppColors.textTertiary),
            ),
          ),
          Expanded(
            child: SelectableText(
              blank ? '—' : value,
              style: mono.inlineCode.copyWith(
                color: blank ? AppColors.textTertiary : AppColors.primary,
                fontWeight: blank ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatCard(TextTheme text, AppMonoText mono) {
    // Legend examples use a reference coordinate (London, 51.5074°) that is
    // deliberately distinct from any coordinate the result card is likely to
    // be showing. The earlier examples reused the New York anchor (40.7128°),
    // so the static legend value rendered the SAME string as a live result —
    // two widgets carrying identical text. The reference coordinate keeps the
    // legend illustrative without colliding with computed output.
    final List<List<String>> rows = const [
      ['DD', 'Decimal degrees', '51.507400'],
      ['DDM', 'Degrees decimal minutes', "51° 30.4440' N"],
      ['DMS', 'Degrees minutes seconds', "51° 30' 26.64\" N"],
    ];

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
            'Formats',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row[1],
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(
                      row[2],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
