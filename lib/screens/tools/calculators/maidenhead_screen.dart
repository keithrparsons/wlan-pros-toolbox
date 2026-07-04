// Maidenhead Grid Square (QTH locator) tool.
//
// Three modes (segmented toggle, GL-003 sec 8.14.1):
//   1. Grid        -> enter latitude + longitude (decimal degrees) and a
//                     precision (4 / 6 / 8 chars); get the Maidenhead locator
//                     plus the square's center and corner bounds.
//   2. Lat-Lon     -> enter a 4/6/8-char locator; get the center latitude /
//                     longitude and the south-west / north-east corners.
//   3. Distance    -> enter two locators; get the great-circle distance
//                     (km / mi) and initial bearing between their centers
//                     (useful for ham contacts AND Wi-Fi point-to-point planning).
//
// All math is the verified pure engine in data/maidenhead_data.dart. The locator
// algorithm is the IARU amateur-radio standard; the distance/bearing reuses the
// same spherical haversine the Distance & Bearing tool uses (R = 6371 km).
//
// THEME: chrome from context.colors (dark sec 8 / light sec 8.20). No new tokens.
// Locator strings + coordinates are fixed-width IDENTIFIERS -> Roboto Mono
// (mono.robotoMono) per GL-003 sec 8.5; the distance numerics are calculation
// outputs -> DM Mono (mono.output*). Glyph note: ASCII hyphen-minus and the
// degree sign only; no em dash (GL-004).
//
// States (SOP-007 sec 5):
//   - success     -> valid coordinate(s) / locator(s) yield a result
//   - empty       -> before any (valid) input: a prompt, copy disabled
//   - error       -> out-of-range coordinate or malformed locator: honest reject
//   - disabled    -> copy action disabled when there is nothing to copy
//   - interactive -> hover/focus/pressed on the toggles, fields, copy
//
// ICON: bespoke Tier-2 icon resolves by catalog id at
// assets/tool-icons/maidenhead-grid.svg when Charta ships it; until then the
// tile falls back to the category glyph (ToolAssets graceful degradation).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/maidenhead_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kMaidenheadToolId = 'maidenhead-grid';

enum _GridMode { toGrid, toLatLon, distance }

class MaidenheadScreen extends StatefulWidget {
  const MaidenheadScreen({super.key});

  @override
  State<MaidenheadScreen> createState() => _MaidenheadScreenState();
}

class _MaidenheadScreenState extends State<MaidenheadScreen> {
  _GridMode _mode = _GridMode.toGrid;

  // To Grid inputs.
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lonCtrl = TextEditingController();
  final FocusNode _latFocus = FocusNode();
  final FocusNode _lonFocus = FocusNode();
  int _precision = 6;

  // To Lat/Lon input.
  final TextEditingController _gridCtrl = TextEditingController();
  final FocusNode _gridFocus = FocusNode();

  // Distance inputs.
  final TextEditingController _gridACtrl = TextEditingController();
  final TextEditingController _gridBCtrl = TextEditingController();
  final FocusNode _gridAFocus = FocusNode();
  final FocusNode _gridBFocus = FocusNode();

  // Signed decimal for coordinates; locator chars for grids (cap 8).
  static final List<TextInputFormatter> _signedDecimal = signedDecimalFormatters;
  static final List<TextInputFormatter> _locatorChars = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
    LengthLimitingTextInputFormatter(8),
  ];

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _latFocus.dispose();
    _lonFocus.dispose();
    _gridCtrl.dispose();
    _gridFocus.dispose();
    _gridACtrl.dispose();
    _gridBCtrl.dispose();
    _gridAFocus.dispose();
    _gridBFocus.dispose();
    super.dispose();
  }

  // ── Parsing helpers ─────────────────────────────────────────────────────────

  double? get _lat {
    final double? v = tryParseFlexibleDouble(_latCtrl.text);
    if (v == null || !v.isFinite || v < -90 || v > 90) return null;
    return v;
  }

  double? get _lon {
    final double? v = tryParseFlexibleDouble(_lonCtrl.text);
    if (v == null || !v.isFinite || v < -180 || v > 180) return null;
    return v;
  }

  /// The encoded locator for the current To Grid inputs, or null when either
  /// coordinate is blank/out of range.
  String? get _encoded {
    final double? lat = _lat;
    final double? lon = _lon;
    if (lat == null || lon == null) return null;
    return Maidenhead.encode(lat, lon, precision: _precision);
  }

  // ── Copy payload (sec 8.16) ─────────────────────────────────────────────────

  String? _buildCopyText() {
    switch (_mode) {
      case _GridMode.toGrid:
        final String? grid = _encoded;
        if (grid == null) return null;
        final MaidenheadCell cell = Maidenhead.decode(grid)!;
        return (StringBuffer()
              ..writeln('Maidenhead locator')
              ..writeln('Latitude: ${_fmtDeg(_lat!)}  '
                  'Longitude: ${_fmtDeg(_lon!)}')
              ..writeln('Locator ($_precision-char): $grid')
              ..writeln('Square center: ${_fmtDeg(cell.centerLat)}, '
                  '${_fmtDeg(cell.centerLon)}')
              ..writeln('SW corner: ${_fmtDeg(cell.swLat)}, '
                  '${_fmtDeg(cell.swLon)}')
              ..writeln('NE corner: ${_fmtDeg(cell.neLat)}, '
                  '${_fmtDeg(cell.neLon)}'))
            .toString()
            .trimRight();
      case _GridMode.toLatLon:
        final MaidenheadCell? cell = Maidenhead.decode(_gridCtrl.text);
        if (cell == null) return null;
        return (StringBuffer()
              ..writeln('Maidenhead locator -> position')
              ..writeln('Locator: ${_gridCtrl.text.trim().toUpperCase()}')
              ..writeln('Center: ${_fmtDeg(cell.centerLat)}, '
                  '${_fmtDeg(cell.centerLon)}')
              ..writeln('SW corner: ${_fmtDeg(cell.swLat)}, '
                  '${_fmtDeg(cell.swLon)}')
              ..writeln('NE corner: ${_fmtDeg(cell.neLat)}, '
                  '${_fmtDeg(cell.neLon)}')
              ..writeln('Size: ${_fmtDeg(cell.lonWidth)} lon x '
                  '${_fmtDeg(cell.latHeight)} lat'))
            .toString()
            .trimRight();
      case _GridMode.distance:
        final GridLeg? leg = Maidenhead.legBetween(
          _gridACtrl.text,
          _gridBCtrl.text,
        );
        if (leg == null) return null;
        return (StringBuffer()
              ..writeln('Maidenhead grid distance')
              ..writeln('From: ${_gridACtrl.text.trim().toUpperCase()}  '
                  'To: ${_gridBCtrl.text.trim().toUpperCase()}')
              ..writeln('Distance: ${leg.km.toStringAsFixed(1)} km '
                  '(${leg.miles.toStringAsFixed(1)} mi)')
              ..writeln('Initial bearing: '
                  '${leg.bearingDeg.toStringAsFixed(1)} deg '
                  '(${_cardinal(leg.bearingDeg)})'))
            .toString()
            .trimRight();
    }
  }

  static String _fmtDeg(double v) => v.toStringAsFixed(5);

  /// 16-point compass label for a bearing in degrees.
  static String _cardinal(double deg) {
    const List<String> points = <String>[
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final int idx = ((deg % 360) / 22.5).round() % 16;
    return points[idx];
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maidenhead Grid'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
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
                      _modeCard(),
                      const SizedBox(height: AppSpacing.md),
                      ..._modeBody(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _noteCard(text),
                      ToolHelpFooter(toolId: kMaidenheadToolId),
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

  Widget _modeCard() {
    return _card(
      child: AppToggle<_GridMode>(
        label: 'Mode',
        value: _mode,
        expand: true,
        semanticLabel: 'Conversion mode',
        items: const <AppToggleItem<_GridMode>>[
          (_GridMode.toGrid, 'Grid'),
          (_GridMode.toLatLon, 'Lat-Lon'),
          (_GridMode.distance, 'Distance'),
        ],
        onChanged: (_GridMode m) => setState(() => _mode = m),
      ),
    );
  }

  List<Widget> _modeBody(TextTheme text, AppMonoText mono) {
    switch (_mode) {
      case _GridMode.toGrid:
        return <Widget>[
          _toGridInputCard(text, mono),
          const SizedBox(height: AppSpacing.md),
          _toGridResultCard(text, mono),
        ];
      case _GridMode.toLatLon:
        return <Widget>[
          _toLatLonInputCard(text, mono),
          const SizedBox(height: AppSpacing.md),
          _toLatLonResultCard(text, mono),
        ];
      case _GridMode.distance:
        return <Widget>[
          _distanceInputCard(text, mono),
          const SizedBox(height: AppSpacing.md),
          _distanceResultCard(text, mono),
        ];
    }
  }

  // ── To Grid ──────────────────────────────────────────────────────────────────

  Widget _toGridInputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _coordField(
            label: 'Latitude',
            hint: '(-90 to 90)',
            semanticLabel: 'Latitude in decimal degrees, -90 to 90',
            controller: _latCtrl,
            focusNode: _latFocus,
            hintText: '37.75',
            mono: mono,
            colors: colors,
          ),
          const SizedBox(height: AppSpacing.sm),
          _coordField(
            label: 'Longitude',
            hint: '(-180 to 180)',
            semanticLabel: 'Longitude in decimal degrees, -180 to 180',
            controller: _lonCtrl,
            focusNode: _lonFocus,
            hintText: '-122.45',
            mono: mono,
            colors: colors,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<int>(
            label: 'Precision',
            value: _precision,
            expand: true,
            semanticLabel: 'Locator precision in characters',
            items: const <AppToggleItem<int>>[
              (4, '4 char'),
              (6, '6 char'),
              (8, '8 char'),
            ],
            onChanged: (int p) => setState(() => _precision = p),
          ),
        ],
      ),
    );
  }

  Widget _toGridResultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? lat = _lat;
    final double? lon = _lon;

    // EMPTY / ERROR — distinguish blank from out-of-range.
    if (lat == null || lon == null) {
      final bool latBlank = _latCtrl.text.trim().isEmpty;
      final bool lonBlank = _lonCtrl.text.trim().isEmpty;
      if (latBlank && lonBlank) {
        return _infoCard(
          icon: Icons.my_location,
          tint: colors.textTertiary,
          child: Text(
            'Enter a latitude and longitude in decimal degrees to get the '
            'Maidenhead grid square.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        );
      }
      return _errorCard(
        text,
        title: 'Coordinate out of range',
        message: 'Latitude must be -90 to 90 and longitude -180 to 180.',
      );
    }

    final String grid = Maidenhead.encode(lat, lon, precision: _precision);
    final MaidenheadCell cell = Maidenhead.decode(grid)!;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Maidenhead locator ($_precision-char)'),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            grid,
            style: mono.outputXL.copyWith(
              color: colors.textAccent,
              fontFamily: mono.robotoMono.fontFamily,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(text, mono,
              label: 'Square center',
              value: '${_fmtDeg(cell.centerLat)}, ${_fmtDeg(cell.centerLon)}',
              identifier: true),
          _row(text, mono,
              label: 'SW corner',
              value: '${_fmtDeg(cell.swLat)}, ${_fmtDeg(cell.swLon)}',
              identifier: true),
          _row(text, mono,
              label: 'NE corner',
              value: '${_fmtDeg(cell.neLat)}, ${_fmtDeg(cell.neLon)}',
              identifier: true),
        ],
      ),
    );
  }

  // ── To Lat/Lon ───────────────────────────────────────────────────────────────

  Widget _toLatLonInputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: _gridField(
        label: 'Locator',
        hint: '(4, 6, or 8 chars)',
        semanticLabel: 'Maidenhead locator',
        controller: _gridCtrl,
        focusNode: _gridFocus,
        hintText: 'JO62qm',
        mono: mono,
        colors: colors,
      ),
    );
  }

  Widget _toLatLonResultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final String raw = _gridCtrl.text.trim();
    if (raw.isEmpty) {
      return _infoCard(
        icon: Icons.travel_explore,
        tint: colors.textTertiary,
        child: Text(
          'Enter a 4, 6, or 8-character Maidenhead locator (e.g. JO62qm) to get '
          'its center latitude and longitude.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      );
    }
    final MaidenheadCell? cell = Maidenhead.decode(raw);
    if (cell == null) {
      return _errorCard(
        text,
        title: 'Not a valid locator',
        message:
            '"${raw.toUpperCase()}" is not a 4, 6, or 8-character Maidenhead '
            'locator. Field letters are A-R, subsquare letters A-X, the rest '
            'digits 0-9.',
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Square center'),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            '${_fmtDeg(cell.centerLat)}, ${_fmtDeg(cell.centerLon)}',
            style: mono.outputLarge.copyWith(
              color: colors.textAccent,
              fontFamily: mono.robotoMono.fontFamily,
              fontSize: AppTextSize.h3,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(text, mono,
              label: 'SW corner',
              value: '${_fmtDeg(cell.swLat)}, ${_fmtDeg(cell.swLon)}',
              identifier: true),
          _row(text, mono,
              label: 'NE corner',
              value: '${_fmtDeg(cell.neLat)}, ${_fmtDeg(cell.neLon)}',
              identifier: true),
          _row(text, mono,
              label: 'Cell size',
              value: '${_fmtDeg(cell.lonWidth)} lon x '
                  '${_fmtDeg(cell.latHeight)} lat',
              identifier: true),
        ],
      ),
    );
  }

  // ── Distance ─────────────────────────────────────────────────────────────────

  Widget _distanceInputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _gridField(
            label: 'From locator',
            hint: '(4, 6, or 8 chars)',
            semanticLabel: 'From Maidenhead locator',
            controller: _gridACtrl,
            focusNode: _gridAFocus,
            hintText: 'CM87',
            mono: mono,
            colors: colors,
          ),
          const SizedBox(height: AppSpacing.sm),
          _gridField(
            label: 'To locator',
            hint: '(4, 6, or 8 chars)',
            semanticLabel: 'To Maidenhead locator',
            controller: _gridBCtrl,
            focusNode: _gridBFocus,
            hintText: 'JO62',
            mono: mono,
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _distanceResultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final String a = _gridACtrl.text.trim();
    final String b = _gridBCtrl.text.trim();
    if (a.isEmpty || b.isEmpty) {
      return _infoCard(
        icon: Icons.straighten,
        tint: colors.textTertiary,
        child: Text(
          'Enter two Maidenhead locators to get the great-circle distance and '
          'initial bearing between their square centers.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      );
    }
    final GridLeg? leg = Maidenhead.legBetween(a, b);
    if (leg == null) {
      final List<String> bad = <String>[
        if (!Maidenhead.isValid(a)) a.toUpperCase(),
        if (!Maidenhead.isValid(b)) b.toUpperCase(),
      ];
      return _errorCard(
        text,
        title: 'Not a valid locator',
        message: '${bad.join(' and ')} '
            '${bad.length > 1 ? 'are' : 'is'} not a valid 4/6/8-char locator.',
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Great-circle distance'),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              SelectableText(
                leg.km.toStringAsFixed(1),
                style: mono.outputXL.copyWith(color: colors.textAccent),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'km',
                style: text.labelLarge?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(text, mono,
              label: 'Distance',
              value: '${leg.miles.toStringAsFixed(1)} mi'),
          _row(text, mono,
              label: 'Initial bearing',
              value: '${leg.bearingDeg.toStringAsFixed(1)} deg '
                  '(${_cardinal(leg.bearingDeg)})'),
        ],
      ),
    );
  }

  // ── Field builders ───────────────────────────────────────────────────────────

  Widget _coordField({
    required String label,
    required String hint,
    required String semanticLabel,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required AppMonoText mono,
    required AppColorScheme colors,
  }) {
    return LabeledField(
      label: label,
      hint: hint,
      semanticLabel: semanticLabel,
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: _signedDecimal,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        style: mono.outputLarge.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: colors.textAccent,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  Widget _gridField({
    required String label,
    required String hint,
    required String semanticLabel,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required AppMonoText mono,
    required AppColorScheme colors,
  }) {
    return LabeledField(
      label: label,
      hint: hint,
      semanticLabel: semanticLabel,
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        inputFormatters: _locatorChars,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        // Locator is a fixed-width identifier -> Roboto Mono (sec 8.5).
        style: mono.robotoMono.copyWith(
          fontSize: AppTextSize.fieldNumeric,
          letterSpacing: 1.0,
        ),
        cursorColor: colors.textAccent,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  // ── Shared pieces ────────────────────────────────────────────────────────────

  Widget _resultLabel(TextTheme text, String label) {
    final AppColorScheme colors = context.colors;
    return Text(
      label,
      style: text.labelMedium?.copyWith(
        color: colors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }

  Widget _row(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
    bool identifier = false,
  }) {
    final AppColorScheme colors = context.colors;
    final TextStyle valueStyle = identifier
        ? mono.robotoMono.copyWith(color: colors.textPrimary)
        : mono.inlineCode.copyWith(color: colors.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: SelectableText(value, style: valueStyle)),
        ],
      ),
    );
  }

  Widget _noteCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    return _infoCard(
      icon: Icons.info_outline,
      tint: colors.textTertiary,
      child: Text(
        'Maidenhead (QTH) locators name a rectangular grid square, not a point. '
        'A longer locator names a smaller square: 4-char ~ 1 deg x 2 deg, '
        '6-char ~ 2.5 x 5 minutes, 8-char finer still. Lookups return the '
        'square center.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }

  Widget _errorCard(
    TextTheme text, {
    required String title,
    required String message,
  }) {
    final AppColorScheme colors = context.colors;
    return _infoCard(
      icon: Icons.error_outline,
      tint: colors.statusWarning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: text.labelMedium?.copyWith(
              color: colors.statusWarning,
              fontWeight: colors.isLight ? FontWeight.w700 : FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            message,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }

  Widget _infoCard({
    required IconData icon,
    required Color tint,
    required Widget child,
  }) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: child),
        ],
      ),
    );
  }
}
