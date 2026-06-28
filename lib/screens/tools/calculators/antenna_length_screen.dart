// Antenna Length — frequency / wavelength / antenna-element calculator.
//
// Distinct from the existing Wavelength tool (id `wavelength`), which is a quick
// five-unit lambda readout using the rounded c = 300 constant. THIS tool adds
// the amateur-radio antenna dimension: the half-wave dipole and quarter-wave
// vertical physical lengths (velocity-factor adjusted) shown beside the classic
// 468/f and 234/f rules of thumb, plus the inverse (wavelength -> frequency).
// It uses the EXACT speed of light c = 299.792458 (MHz*m form), not 300.
//
// CORE PHYSICS:
//   lambda(m) = 299.792458 / f(MHz)        f(MHz) = 299.792458 / lambda(m)
//   half-wave dipole  physical L = (lambda / 2) * VF   rule: L(ft) ~ 468 / f(MHz)
//   quarter-wave vert physical L = (lambda / 4) * VF   rule: L(ft) ~ 234 / f(MHz)
//   PHYSICAL length = ELECTRICAL length * velocity factor (VF). VF defaults to
//   0.95 (thin bare wire). The rule-of-thumb 468/234 figures already fold in a
//   typical end-effect shortening, so they read a touch shorter than the pure
//   physics half/quarter wavelength; both are shown so the user sees the spread.
//
// SANITY CHECKS (see antenna_length_screen_test.dart):
//   14.2 MHz  -> lambda ~ 21.11 m; half-wave dipole ~ 33 ft (VF 0.95) / 468-rule
//   146 MHz   -> quarter-wave vertical ~ 19-20 in
//   2400 MHz  -> quarter-wave vertical ~ 3 cm
//
// THEME: chrome from context.colors (dark sec 8 / light sec 8.20). No new tokens.
// Numerics in DM Mono (mono.output*) per GL-003 sec 8.5; no identifiers here so
// no Roboto Mono. Glyph note: ASCII hyphen-minus throughout; no em dash (GL-004).
//
// States (SOP-007 sec 5):
//   - success     -> a valid frequency (or wavelength) + valid VF yields lengths
//   - empty       -> no/blank input: a prompt, copy disabled, rows blank to "-"
//   - error       -> input <= 0 / non-finite, or VF outside (0, 1]: honest note
//   - disabled    -> copy action disabled when there is nothing to copy
//   - interactive -> hover/focus/pressed on the toggles, fields, copy
//
// ICON: bespoke Tier-2 icon resolves by catalog id at
// assets/tool-icons/antenna-length.svg when Charta ships it; until then the
// tile falls back to the category glyph (ToolAssets graceful degradation).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kAntennaLengthToolId = 'antenna-length';

/// Whether the user is entering a frequency or a wavelength.
enum _InputMode { frequency, wavelength }

/// Frequency unit for the frequency-input mode.
enum AntennaFreqUnit { mhz, ghz }

class AntennaLengthScreen extends StatefulWidget {
  const AntennaLengthScreen({super.key});

  // ─── Math (pure, static so it is unit-testable without a widget) ───────────

  /// Exact speed of light in the MHz*meter form: lambda(m) = c / f(MHz).
  static const double cMHzMeters = 299.792458;

  /// Free-space wavelength (m) from frequency (MHz).
  static double wavelengthMeters(double freqMHz) => cMHzMeters / freqMHz;

  /// Frequency (MHz) from free-space wavelength (m) — the inverse.
  static double frequencyMHz(double wavelengthM) => cMHzMeters / wavelengthM;

  /// Half-wave dipole PHYSICAL length (m): (lambda / 2) * VF.
  static double halfWaveDipoleMeters(double wavelengthM, double vf) =>
      (wavelengthM / 2.0) * vf;

  /// Quarter-wave vertical PHYSICAL length (m): (lambda / 4) * VF.
  static double quarterWaveMeters(double wavelengthM, double vf) =>
      (wavelengthM / 4.0) * vf;

  /// Half-wave dipole rule-of-thumb length in FEET: 468 / f(MHz).
  static double dipoleRuleOfThumbFeet(double freqMHz) => 468.0 / freqMHz;

  /// Quarter-wave vertical rule-of-thumb length in FEET: 234 / f(MHz).
  static double quarterRuleOfThumbFeet(double freqMHz) => 234.0 / freqMHz;

  /// Meters -> feet.
  static double metersToFeet(double m) => m * 3.28084;

  /// Meters -> inches.
  static double metersToInches(double m) => m * 3.28084 * 12.0;

  /// Feet -> meters.
  static double feetToMeters(double ft) => ft / 3.28084;

  @override
  State<AntennaLengthScreen> createState() => _AntennaLengthScreenState();
}

class _AntennaLengthScreenState extends State<AntennaLengthScreen> {
  _InputMode _mode = _InputMode.frequency;
  AntennaFreqUnit _freqUnit = AntennaFreqUnit.mhz;

  final TextEditingController _valueCtrl = TextEditingController();
  final FocusNode _valueFocus = FocusNode();
  // VF seeded to the thin-wire default; user-editable.
  final TextEditingController _vfCtrl = TextEditingController(text: '0.95');
  final FocusNode _vfFocus = FocusNode();

  static final List<TextInputFormatter> _unsignedDecimal =
      <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _valueCtrl.dispose();
    _valueFocus.dispose();
    _vfCtrl.dispose();
    _vfFocus.dispose();
    super.dispose();
  }

  // ── Derived state ───────────────────────────────────────────────────────────

  /// Effective frequency in MHz from whichever input mode is active, or null
  /// when the input is empty / unparseable / non-positive.
  double? get _freqMHz {
    final double? v = _tryParse(_valueCtrl.text);
    if (v == null || v <= 0) return null;
    switch (_mode) {
      case _InputMode.frequency:
        final double mhz =
            _freqUnit == AntennaFreqUnit.ghz ? v * 1000.0 : v;
        return mhz > 0 ? mhz : null;
      case _InputMode.wavelength:
        // v is wavelength in meters; invert to frequency.
        return AntennaLengthScreen.frequencyMHz(v);
    }
  }

  /// Free-space wavelength in meters, or null when the frequency is unresolved.
  double? get _wavelengthM {
    final double? f = _freqMHz;
    if (f == null) return null;
    return AntennaLengthScreen.wavelengthMeters(f);
  }

  /// Velocity factor in (0, 1], or null when the VF field is invalid.
  double? get _vf {
    final double? v = _tryParse(_vfCtrl.text);
    if (v == null || v <= 0 || v > 1.0) return null;
    return v;
  }

  static double? _tryParse(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  // ── Copy payload (sec 8.16) ─────────────────────────────────────────────────

  String? _buildCopyText() {
    final double? f = _freqMHz;
    final double? lambda = _wavelengthM;
    if (f == null || lambda == null) return null;
    final double? vf = _vf;

    final StringBuffer b = StringBuffer()
      ..writeln('Antenna Length')
      ..writeln('Frequency: ${_fmt(f, 4)} MHz')
      ..writeln('Wavelength (lambda): ${_fmt(lambda, 4)} m '
          '(${_fmt(AntennaLengthScreen.metersToFeet(lambda), 3)} ft)');

    if (vf == null) {
      b.writeln('Velocity factor: invalid (must be > 0 and <= 1)');
      return b.toString().trimRight();
    }

    final double dipoleM = AntennaLengthScreen.halfWaveDipoleMeters(lambda, vf);
    final double dipoleRuleFt = AntennaLengthScreen.dipoleRuleOfThumbFeet(f);
    final double vertM = AntennaLengthScreen.quarterWaveMeters(lambda, vf);
    final double vertRuleFt = AntennaLengthScreen.quarterRuleOfThumbFeet(f);

    b
      ..writeln('Velocity factor (VF): ${_fmt(vf, 3)} '
          '(physical = electrical x VF)')
      ..writeln('Half-wave dipole (1/2 lambda):')
      ..writeln('  Physical: ${_fmt(dipoleM, 4)} m / '
          '${_fmt(AntennaLengthScreen.metersToFeet(dipoleM), 3)} ft / '
          '${_fmt(AntennaLengthScreen.metersToInches(dipoleM), 2)} in')
      ..writeln('  Rule of thumb 468/f: ${_fmt(dipoleRuleFt, 3)} ft '
          '(${_fmt(AntennaLengthScreen.feetToMeters(dipoleRuleFt), 4)} m)')
      ..writeln('Quarter-wave vertical (1/4 lambda):')
      ..writeln('  Physical: ${_fmt(vertM, 4)} m / '
          '${_fmt(AntennaLengthScreen.metersToFeet(vertM), 3)} ft / '
          '${_fmt(AntennaLengthScreen.metersToInches(vertM), 2)} in')
      ..writeln('  Rule of thumb 234/f: ${_fmt(vertRuleFt, 3)} ft '
          '(${_fmt(AntennaLengthScreen.feetToMeters(vertRuleFt), 4)} m)')
      ..writeln()
      ..writeln('c = 299.792458 (exact). Physical length = electrical '
          'length x velocity factor.');
    return b.toString().trimRight();
  }

  static String _fmt(double? value, int decimals) {
    if (value == null || !value.isFinite) return '-';
    return value.toStringAsFixed(decimals);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Antenna Length'),
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
                      ConceptGraphicBand(
                        toolId: kAntennaLengthToolId,
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic(kAntennaLengthToolId))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      ..._resultCards(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      ToolHelpFooter(toolId: kAntennaLengthToolId),
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
    final AppColorScheme colors = context.colors;
    final bool freqMode = _mode == _InputMode.frequency;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<_InputMode>(
            label: 'Enter',
            value: _mode,
            expand: true,
            semanticLabel: 'Input type',
            items: const <AppToggleItem<_InputMode>>[
              (_InputMode.frequency, 'Frequency'),
              (_InputMode.wavelength, 'Wavelength'),
            ],
            onChanged: (_InputMode m) => setState(() => _mode = m),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (freqMode)
            FieldUnitRow(
              field: _numberField(
                label: 'Frequency',
                hint: _freqUnit == AntennaFreqUnit.mhz ? '(MHz)' : '(GHz)',
                semanticLabel: _freqUnit == AntennaFreqUnit.mhz
                    ? 'Frequency in MHz'
                    : 'Frequency in GHz',
                controller: _valueCtrl,
                focusNode: _valueFocus,
                hintText: '14.2',
                mono: mono,
                colors: colors,
              ),
              unit: AppToggle<AntennaFreqUnit>(
                value: _freqUnit,
                semanticLabel: 'Frequency unit',
                items: const <AppToggleItem<AntennaFreqUnit>>[
                  (AntennaFreqUnit.mhz, 'MHz'),
                  (AntennaFreqUnit.ghz, 'GHz'),
                ],
                onChanged: (AntennaFreqUnit u) =>
                    setState(() => _freqUnit = u),
              ),
            )
          else
            _numberField(
              label: 'Wavelength',
              hint: '(m)',
              semanticLabel: 'Wavelength in meters',
              controller: _valueCtrl,
              focusNode: _valueFocus,
              hintText: '21.1',
              mono: mono,
              colors: colors,
            ),
          const SizedBox(height: AppSpacing.sm),
          _numberField(
            label: 'Velocity factor',
            hint: '(0 to 1, e.g. 0.95)',
            semanticLabel: 'Velocity factor, 0 to 1',
            controller: _vfCtrl,
            focusNode: _vfFocus,
            hintText: '0.95',
            mono: mono,
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _numberField({
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
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _unsignedDecimal,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        style: mono.outputLarge.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: colors.textAccent,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  List<Widget> _resultCards(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final double? f = _freqMHz;
    final double? lambda = _wavelengthM;

    // EMPTY — nothing valid entered yet.
    if (f == null || lambda == null) {
      return <Widget>[
        _infoCard(
          icon: Icons.straighten,
          tint: colors.textTertiary,
          child: Text(
            _mode == _InputMode.frequency
                ? 'Enter a frequency to get the wavelength and the half-wave '
                    'and quarter-wave antenna lengths.'
                : 'Enter a wavelength in meters to get the frequency and the '
                    'half-wave and quarter-wave antenna lengths.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ),
      ];
    }

    final double? vf = _vf;
    return <Widget>[
      _wavelengthCard(text, mono, f, lambda),
      const SizedBox(height: AppSpacing.md),
      if (vf == null)
        _infoCard(
          icon: Icons.error_outline,
          tint: colors.statusWarning,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Velocity factor out of range',
                style: text.labelMedium?.copyWith(
                  color: colors.statusWarning,
                  fontWeight:
                      colors.isLight ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Enter a velocity factor greater than 0 and at most 1 '
                '(0.95 for thin bare wire) to size the antenna elements.',
                style:
                    text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        )
      else ...<Widget>[
        _antennaCard(
          text,
          mono,
          title: 'Half-wave dipole',
          fraction: '1/2 lambda',
          physicalM:
              AntennaLengthScreen.halfWaveDipoleMeters(lambda, vf),
          ruleFeet: AntennaLengthScreen.dipoleRuleOfThumbFeet(f),
          ruleLabel: '468 / f',
          vf: vf,
        ),
        const SizedBox(height: AppSpacing.md),
        _antennaCard(
          text,
          mono,
          title: 'Quarter-wave vertical',
          fraction: '1/4 lambda',
          physicalM: AntennaLengthScreen.quarterWaveMeters(lambda, vf),
          ruleFeet: AntennaLengthScreen.quarterRuleOfThumbFeet(f),
          ruleLabel: '234 / f',
          vf: vf,
        ),
      ],
    ];
  }

  Widget _wavelengthCard(
    TextTheme text,
    AppMonoText mono,
    double freqMHz,
    double lambdaM,
  ) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Full wavelength (lambda)'),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label: 'Full wavelength',
            value: '${_fmt(lambdaM, 4)} meters',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                SelectableText(
                  _fmt(lambdaM, 4),
                  style: mono.outputXL.copyWith(color: colors.textAccent),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'm',
                  style: text.labelLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(text, mono,
              label: 'Wavelength',
              value: '${_fmt(AntennaLengthScreen.metersToFeet(lambdaM), 3)} ft'),
          _row(text, mono,
              label: 'Frequency', value: '${_fmt(freqMHz, 4)} MHz'),
        ],
      ),
    );
  }

  Widget _antennaCard(
    TextTheme text,
    AppMonoText mono, {
    required String title,
    required String fraction,
    required double physicalM,
    required double ruleFeet,
    required String ruleLabel,
    required double vf,
  }) {
    final AppColorScheme colors = context.colors;
    final double physFt = AntennaLengthScreen.metersToFeet(physicalM);
    final double physIn = AntennaLengthScreen.metersToInches(physicalM);
    final double ruleM = AntennaLengthScreen.feetToMeters(ruleFeet);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: text.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                fraction,
                style: mono.inlineCode.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultLabel(text, 'Physical length (VF ${_fmt(vf, 3)})'),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label: '$title physical length',
            value: '${_fmt(physicalM, 4)} meters, '
                '${_fmt(physFt, 3)} feet, ${_fmt(physIn, 2)} inches',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    SelectableText(
                      _fmt(physicalM, 4),
                      style:
                          mono.outputLarge.copyWith(color: colors.textAccent),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'm',
                      style: text.labelLarge?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${_fmt(physFt, 3)} ft  /  ${_fmt(physIn, 2)} in',
                  style: mono.inlineCode.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(
            text,
            mono,
            label: 'Rule of thumb',
            value: '${_fmt(ruleFeet, 3)} ft  /  ${_fmt(ruleM, 4)} m',
          ),
          _row(text, mono, label: ' ', value: '($ruleLabel, MHz)'),
        ],
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _resultLabel(text, 'Formula'),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'lambda(m) = 299.792458 / f(MHz)',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            'physical L = electrical L x VF',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Half-wave dipole physical length = (lambda / 2) x VF; the 468 / f '
            'rule of thumb gives feet directly and already folds in a typical '
            'end-effect shortening, so it reads a little shorter than the pure '
            'half wavelength. Quarter-wave vertical = (lambda / 4) x VF; rule of '
            'thumb 234 / f. VF defaults to 0.95 for thin bare wire; insulated '
            'wire and tubing run lower. c is the exact 299.792458, not 300.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── Small shared pieces ─────────────────────────────────────────────────────

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
  }) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              value,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
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
