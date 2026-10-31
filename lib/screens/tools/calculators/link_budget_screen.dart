// Link Budget calculator.
//
// Full point-to-point link budget. Mirrors the RF Tools PWA reference
// (app.js calcLinkBudget, line 404) field-for-field:
//   received(dBm) = TxPower + TxGain - TxLoss - PathLoss - RxLoss + RxGain - misc
//   linkMargin(dB) = received - RxSensitivity
//
// TX power accepts dBm (default), W, or mW. The PWA normalizes via wattsTodBm,
// matching the dBm/Watt converter: W → 10·log10(txp·1000); mW → 10·log10(txp).
// All other inputs are in dB / dBi / dBm directly. "Other losses" is the one
// optional field; the PWA treats a blank value as 0.
//
// Edge cases:
// - Any required field empty / invalid → blank both outputs (no crash). The
//   PWA blocks the whole calc unless every required field is finite; we do the
//   same so a half-filled form never shows a misleading partial number.
// - TX power in W/mW <= 0 → log10 undefined; treated as invalid → blank output.
//
// Path loss. FSPL is calculated from frequency (MHz) and distance (m or ft,
// following the app-wide UnitSystem) with FsplScreen.fsplDb, the same function
// the FSPL tool uses, after FsplScreen.freqToGHz / distToKm. A value typed into
// the FSPL field is a manual override: it wins, and the screen says so under
// the field and in the result. Leave it blank to calculate.
//
// EIRP = TX power (dBm) + TX antenna gain − TX cable loss, from
// EirpScreen.eirpDbm, the EIRP tool's function. It needs only the three
// transmitter fields.
//
// Margin health follows the PWA thresholds (>=10 healthy, >=0 marginal,
// <0 negative). The live margin is tinted with the GL-003 §8.13 semantic status
// palette: statusSuccess (>= 10 dB), statusWarning (0–10 dB), statusDanger
// (< 0 dB). Per §8.13 the calculator owns the dB thresholds; the colors come
// from AppColors. Success is the cool mint status green, not the lime brand
// primary — lime marks "computed value", success marks "passes" (§8.13).
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public class so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/field_unit_row.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/unit_system_switch.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'eirp_screen.dart';
import 'fspl_screen.dart';

/// TX power input units, mirroring the PWA lb-tx-unit select.
enum TxPowerUnit { dbm, w, mw }

/// Qualitative health of a link margin, matching the PWA color thresholds.
enum MarginHealth { healthy, marginal, negative }

class LinkBudgetScreen extends StatefulWidget {
  const LinkBudgetScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: wattsTodBm, calcLinkBudget.

  /// Watts → dBm (PWA wattsTodBm). 10·log10(w·1000).
  static double wattsTodBm(double w) => 10 * (math.log(w * 1000) / math.ln10);

  /// Normalize TX power to dBm, mirroring the PWA's unit branch:
  ///   W  → wattsTodBm(txp)
  ///   mW → wattsTodBm(txp / 1000)
  ///   dBm → txp unchanged
  static double txPowerToDbm(double value, TxPowerUnit unit) {
    switch (unit) {
      case TxPowerUnit.w:
        return wattsTodBm(value);
      case TxPowerUnit.mw:
        return wattsTodBm(value / 1000.0);
      case TxPowerUnit.dbm:
        return value;
    }
  }

  /// Received signal level in dBm.
  /// txPower + txGain - txLoss - pathLoss - rxLoss + rxGain - misc (PWA rx_dbm).
  /// txPowerDbm is the already-normalized TX power.
  static double receivedDbm({
    required double txPowerDbm,
    required double txGain,
    required double txLoss,
    required double pathLoss,
    required double rxLoss,
    required double rxGain,
    required double misc,
  }) {
    return txPowerDbm + txGain - txLoss - pathLoss - rxLoss + rxGain - misc;
  }

  /// Link margin in dB: received signal minus receiver sensitivity (PWA margin).
  static double linkMarginDb(double receivedDbm, double rxSensitivity) {
    return receivedDbm - rxSensitivity;
  }

  /// FSPL in dB from frequency in MHz and distance in metres, through the FSPL
  /// tool's own functions. Null when either input is not above 0.
  static double? fsplFromInputs({
    required double freqMhz,
    required double distanceMetres,
  }) {
    if (!(freqMhz > 0) || !(distanceMetres > 0)) return null;
    final double loss = FsplScreen.fsplDb(
      FsplScreen.freqToGHz(freqMhz, FreqUnit.mhz),
      FsplScreen.distToKm(distanceMetres, DistUnit.m),
    );
    return loss.isFinite ? loss : null;
  }

  /// The path loss the budget uses: a manual value wins over the calculated
  /// one. Null when neither is available.
  static double? effectivePathLoss({double? manual, double? calculated}) =>
      manual ?? calculated;

  /// EIRP in dBm from normalized TX power, TX antenna gain and TX cable loss,
  /// through the EIRP tool's function. Null when not finite.
  static double? eirpDbm({
    required double txPowerDbm,
    required double txGain,
    required double txLoss,
  }) => EirpScreen.eirpDbm(
    power: txPowerDbm,
    unit: EirpPowerUnit.dBm,
    lossDb: txLoss,
    gainDbi: txGain,
  );

  /// Margin health, matching the PWA thresholds (>=10 / >=0 / <0).
  static MarginHealth marginHealth(double marginDb) {
    if (marginDb >= 10) return MarginHealth.healthy;
    if (marginDb >= 0) return MarginHealth.marginal;
    return MarginHealth.negative;
  }

  @override
  State<LinkBudgetScreen> createState() => _LinkBudgetScreenState();
}

class _LinkBudgetScreenState extends State<LinkBudgetScreen>
    with UnitSystemFollower<LinkBudgetScreen> {
  final TextEditingController _txPowerCtrl = TextEditingController();
  final TextEditingController _freqCtrl = TextEditingController();
  final TextEditingController _distCtrl = TextEditingController();
  final FocusNode _freqFocus = FocusNode();
  final FocusNode _distFocus = FocusNode();

  /// The app-wide length units, for the distance field.
  UnitSystem _units = UnitSystem.metric;
  final TextEditingController _txGainCtrl = TextEditingController();
  final TextEditingController _txLossCtrl = TextEditingController();
  final TextEditingController _pathLossCtrl = TextEditingController();
  final TextEditingController _miscCtrl = TextEditingController();
  final TextEditingController _rxLossCtrl = TextEditingController();
  final TextEditingController _rxGainCtrl = TextEditingController();
  final TextEditingController _rxSensCtrl = TextEditingController();

  final FocusNode _txPowerFocus = FocusNode();
  final FocusNode _txGainFocus = FocusNode();
  final FocusNode _txLossFocus = FocusNode();
  final FocusNode _pathLossFocus = FocusNode();
  final FocusNode _miscFocus = FocusNode();
  final FocusNode _rxLossFocus = FocusNode();
  final FocusNode _rxGainFocus = FocusNode();
  final FocusNode _rxSensFocus = FocusNode();

  TxPowerUnit _txPowerUnit = TxPowerUnit.dbm;

  // Computed outputs, or null when required input is empty / invalid.
  double? _receivedDbm;
  double? _marginDb;
  double? _eirpDbm; // needs only the transmitter fields
  double? _fsplCalculated; // from frequency and distance, when both are valid
  bool _fsplManual = false; // a value is typed in the FSPL field

  LengthFormat get _length => LengthFormat(_units);

  /// Follow the app-wide unit switch. A typed distance keeps its physical
  /// length: the number is converted into the new unit, so the FSPL does not
  /// jump when the units flip.
  @override
  void applyUnitSystem(UnitSystem system) {
    if (system == _units) return;
    final double? shown = tryParseFlexibleDouble(_distCtrl.text);
    final double? metres = shown == null ? null : _length.distToMetres(shown);
    _units = system;
    if (metres != null) {
      final double v = _length.distValue(metres);
      _distCtrl.text = _trimNumber(v);
    }
    _recompute();
  }

  /// Up to two decimals, no trailing zeros, for a converted distance.
  static String _trimNumber(double v) {
    String t = v.toStringAsFixed(2);
    if (t.contains('.')) t = t.replaceFirst(RegExp(r'\.?0+$'), '');
    return t;
  }

  // Gains, sensitivity, and TX power (dBm) can be negative, so these fields
  // accept a leading minus. Losses are non-negative in the PWA (min="0") but we
  // keep the formatter permissive and rely on the math; a stray sign just
  // shifts the budget, never crashes.
  static final List<TextInputFormatter> _signedDecimal =
      scientificDecimalFormatters;
  static final List<TextInputFormatter> _unsignedDecimal =
      unsignedDecimalFormatters;

  @override
  void dispose() {
    _txPowerCtrl.dispose();
    _freqCtrl.dispose();
    _distCtrl.dispose();
    _freqFocus.dispose();
    _distFocus.dispose();
    _txGainCtrl.dispose();
    _txLossCtrl.dispose();
    _pathLossCtrl.dispose();
    _miscCtrl.dispose();
    _rxLossCtrl.dispose();
    _rxGainCtrl.dispose();
    _rxSensCtrl.dispose();
    _txPowerFocus.dispose();
    _txGainFocus.dispose();
    _txLossFocus.dispose();
    _pathLossFocus.dispose();
    _miscFocus.dispose();
    _rxLossFocus.dispose();
    _rxGainFocus.dispose();
    _rxSensFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? txPower = tryParseFlexibleDouble(_txPowerCtrl.text);
    final double? txGain = tryParseFlexibleDouble(_txGainCtrl.text);
    final double? txLoss = tryParseFlexibleDouble(_txLossCtrl.text);
    final double? manualFspl = tryParseFlexibleDouble(_pathLossCtrl.text);
    final double? freq = tryParseFlexibleDouble(_freqCtrl.text);
    final double? dist = tryParseFlexibleDouble(_distCtrl.text);
    final double? calcFspl = (freq == null || dist == null)
        ? null
        : LinkBudgetScreen.fsplFromInputs(
            freqMhz: freq,
            distanceMetres: _length.distToMetres(dist),
          );
    final double? pathLoss = LinkBudgetScreen.effectivePathLoss(
      manual: manualFspl,
      calculated: calcFspl,
    );
    _fsplCalculated = calcFspl;
    _fsplManual = manualFspl != null;
    // EIRP needs only the transmitter, so it shows as soon as those are in.
    final double? txDbmForEirp = txPower == null
        ? null
        : LinkBudgetScreen.txPowerToDbm(txPower, _txPowerUnit);
    _eirpDbm =
        (txDbmForEirp == null ||
            !txDbmForEirp.isFinite ||
            txGain == null ||
            txLoss == null)
        ? null
        : LinkBudgetScreen.eirpDbm(
            txPowerDbm: txDbmForEirp,
            txGain: txGain,
            txLoss: txLoss,
          );
    final double? rxLoss = tryParseFlexibleDouble(_rxLossCtrl.text);
    final double? rxGain = tryParseFlexibleDouble(_rxGainCtrl.text);
    final double? rxSens = tryParseFlexibleDouble(_rxSensCtrl.text);
    // Misc is the only optional field; blank → 0, matching the PWA's
    // isFinite(num('lb-misc')) ? num : 0 guard.
    final double misc = tryParseFlexibleDouble(_miscCtrl.text) ?? 0;

    // PWA blocks the whole calc unless every required field is finite.
    if (txPower == null ||
        txGain == null ||
        txLoss == null ||
        pathLoss == null ||
        rxLoss == null ||
        rxGain == null ||
        rxSens == null) {
      setState(() {
        _receivedDbm = null;
        _marginDb = null;
      });
      return;
    }

    final double txPowerDbm = LinkBudgetScreen.txPowerToDbm(
      txPower,
      _txPowerUnit,
    );
    // W/mW <= 0 yields a non-finite dBm; treat as invalid rather than render it.
    if (!txPowerDbm.isFinite) {
      setState(() {
        _receivedDbm = null;
        _marginDb = null;
      });
      return;
    }

    final double rx = LinkBudgetScreen.receivedDbm(
      txPowerDbm: txPowerDbm,
      txGain: txGain,
      txLoss: txLoss,
      pathLoss: pathLoss,
      rxLoss: rxLoss,
      rxGain: rxGain,
      misc: misc,
    );
    final double margin = LinkBudgetScreen.linkMarginDb(rx, rxSens);
    setState(() {
      _receivedDbm = rx;
      _marginDb = margin;
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  /// PWA fmt(value, 1): fixed 1-decimal, "—" when not finite.
  static String _format(double? value) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(1);
  }

  /// Tint for the live margin value, using the §8.13 semantic status palette.
  /// The calculator owns the dB thresholds (§8.13 rule 4: margin ≥ 10 →
  /// success, 0–10 → warning, < 0 → danger); the colors come from AppColors.
  /// Success is the cool mint-green status token, NOT the lime brand primary —
  /// lime marks "computed value", not "passes" (§8.13). The empty/invalid state
  /// stays muted so a not-yet-computed readout never wears a verdict color.
  /// Verdict color is never the only signal — the value and its `dB` unit
  /// carry the number, and the §8.13-aligned Margin guide card spells out the
  /// bands in words (§8.13 rule 2, never color-only).
  Color _marginColor() {
    final AppColorScheme colors = context.colors;
    if (_marginDb == null || !_marginDb!.isFinite) {
      return colors.textTertiary;
    }
    switch (LinkBudgetScreen.marginHealth(_marginDb!)) {
      case MarginHealth.healthy:
        return colors.statusSuccess;
      case MarginHealth.marginal:
        return colors.statusWarning;
      case MarginHealth.negative:
        return colors.statusDanger;
    }
  }

  /// The margin verdict as a word, for the screen-reader value (§8.13 rule 2 —
  /// the verdict is never carried by color alone). Null when not computed.
  String? _marginVerdictWord() {
    if (_marginDb == null || !_marginDb!.isFinite) return null;
    switch (LinkBudgetScreen.marginHealth(_marginDb!)) {
      case MarginHealth.healthy:
        return 'healthy';
      case MarginHealth.marginal:
        return 'marginal';
      case MarginHealth.negative:
        return 'negative, link does not close';
    }
  }

  /// §8.16 copy payload — the link budget result as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) whenever there is no valid result:
  /// any required field empty/invalid, or a non-finite normalized TX power.
  /// Echoes the received signal, the link margin, and the margin VERDICT as a
  /// WORD (healthy / marginal / negative) — per §8.16 the on-screen status hue
  /// is the screen carrier, the word is the clipboard carrier.
  String? _buildCopyText() {
    final double? rx = _receivedDbm;
    final double? margin = _marginDb;
    if (rx == null || !rx.isFinite || margin == null || !margin.isFinite) {
      return null;
    }

    final String verdict = switch (LinkBudgetScreen.marginHealth(margin)) {
      MarginHealth.healthy => 'Healthy: link has fade headroom',
      MarginHealth.marginal => 'Marginal: vulnerable to fade',
      MarginHealth.negative => 'Negative: link does not close',
    };

    final StringBuffer b = StringBuffer()..writeln('Link Budget');
    final double? freq = tryParseFlexibleDouble(_freqCtrl.text);
    final double? dist = tryParseFlexibleDouble(_distCtrl.text);
    if (freq != null) b.writeln('Frequency: ${_trimNumber(freq)} MHz');
    if (dist != null) {
      b.writeln('Distance: ${_trimNumber(dist)} ${_length.distUnit}');
    }
    b
      ..writeln('Free space path loss: ${_fsplText()}')
      ..writeln('EIRP: ${_eirpText()}')
      ..writeln('Received signal: ${_format(rx)} dBm')
      ..writeln('Link margin: ${_format(margin)} dB')
      ..writeln('Verdict: $verdict');
    return b.toString().trimRight();
  }

  /// "94.0 dB (calculated)" / "120.0 dB (manual)" / "—".
  String _fsplText() {
    final double? manual = tryParseFlexibleDouble(_pathLossCtrl.text);
    if (manual != null) return '${_format(manual)} dB (manual)';
    if (_fsplCalculated != null) {
      return '${_format(_fsplCalculated)} dB (calculated)';
    }
    return '—';
  }

  /// "36.0 dBm (4.0 W)" or "—". Watts as the EIRP tool shows them: W with two
  /// decimals from 1 W up, else mW with one decimal.
  String _eirpText() {
    final double? e = _eirpDbm;
    if (e == null) return '—';
    return '${_format(e)} dBm (${_powerText(e)})';
  }

  static String _powerText(double dbm) {
    final double w = EirpScreen.eirpWatts(dbm);
    return w >= 1
        ? '${w.toStringAsFixed(2)} W'
        : '${(w * 1000).toStringAsFixed(1)} mW';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Budget'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until every
        // required field is finite; copies the received signal, the link
        // margin, and the margin VERDICT WORD (healthy/marginal/negative) so the
        // §8.13 status hue is never the only carrier of the verdict.
        // The app-wide metric / imperial switch comes first, as in every tool
        // that takes a length (here, the distance for FSPL).
        actions: <Widget>[
          const UnitSystemSwitch(),
          AppCopyAction(textBuilder: _buildCopyText),
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
                      // bundled (with the gap below it).
                      ConceptGraphicBand(
                        toolId: 'link-budget',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('link-budget'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'link-budget'),
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
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(text, 'Transmitter'),
          const SizedBox(height: AppSpacing.xs),
          // TX power is the one field with a unit toggle. FieldUnitRow reflows
          // the unit beneath the field below 440px so it never clips at phone
          // widths (Vera web-demo gate, 2026-06-02).
          FieldUnitRow(
            field: _field(
              label: 'TX Power',
              unitHint: _txPowerUnitLabel(_txPowerUnit),
              controller: _txPowerCtrl,
              focusNode: _txPowerFocus,
              hintText: '23',
              monoStyle: mono.outputLarge,
              signed: true,
            ),
            unit: _txPowerUnitSelector(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'TX Antenna Gain',
            unitHint: 'dBi',
            controller: _txGainCtrl,
            focusNode: _txGainFocus,
            hintText: '14',
            monoStyle: mono.outputLarge,
            signed: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'TX Cable Loss',
            unitHint: 'dB',
            controller: _txLossCtrl,
            focusNode: _txLossFocus,
            hintText: '1.5',
            monoStyle: mono.outputLarge,
            signed: false,
          ),
          const SizedBox(height: AppSpacing.md),
          _sectionTitle(text, 'Path'),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  label: 'Frequency',
                  unitHint: 'MHz',
                  controller: _freqCtrl,
                  focusNode: _freqFocus,
                  hintText: '5500',
                  monoStyle: mono.outputLarge,
                  signed: false,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _field(
                  label: 'Distance',
                  unitHint: _length.distUnit,
                  controller: _distCtrl,
                  focusNode: _distFocus,
                  hintText: _length.isMetric ? '1000' : '3280',
                  monoStyle: mono.outputLarge,
                  signed: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'Free Space Path Loss',
            unitHint: 'dB',
            controller: _pathLossCtrl,
            focusNode: _pathLossFocus,
            hintText: _fsplCalculated == null
                ? 'from frequency and distance'
                : _format(_fsplCalculated),
            monoStyle: mono.outputLarge,
            signed: false,
            helper: _fsplManual
                ? 'Manual value: it overrides frequency and distance. Clear '
                      'it to calculate.'
                : _fsplCalculated == null
                ? 'Calculated from frequency and distance, or type a value to '
                      'override.'
                : 'Calculated from frequency and distance. Type a value to '
                      'override.',
            helperColor: _fsplManual ? context.colors.statusWarning : null,
            text: text,
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'Other Losses (optional)',
            unitHint: 'dB',
            controller: _miscCtrl,
            focusNode: _miscFocus,
            hintText: '0',
            monoStyle: mono.outputLarge,
            signed: false,
            helper: 'Rain fade, foliage, interference, etc.',
            text: text,
          ),
          const SizedBox(height: AppSpacing.md),
          _sectionTitle(text, 'Receiver'),
          const SizedBox(height: AppSpacing.xs),
          _field(
            label: 'RX Cable Loss',
            unitHint: 'dB',
            controller: _rxLossCtrl,
            focusNode: _rxLossFocus,
            hintText: '1.5',
            monoStyle: mono.outputLarge,
            signed: false,
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'RX Antenna Gain',
            unitHint: 'dBi',
            controller: _rxGainCtrl,
            focusNode: _rxGainFocus,
            hintText: '14',
            monoStyle: mono.outputLarge,
            signed: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(
            label: 'RX Sensitivity',
            unitHint: 'dBm',
            controller: _rxSensCtrl,
            focusNode: _rxSensFocus,
            hintText: '-82',
            monoStyle: mono.outputLarge,
            signed: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(TextTheme text, String label) {
    final AppColorScheme colors = context.colors;
    return Text(
      label,
      style: text.labelMedium?.copyWith(
        color: colors.textSecondary,
        letterSpacing: 0.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// One labeled numeric field. `helper` renders a muted note under the field
  /// (used for the "Other losses" hint), `text` is required when helper is set.
  Widget _field({
    required String label,
    required String unitHint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
    required bool signed,
    String? helper,
    Color? helperColor,
    TextTheme? text,
  }) {
    final AppColorScheme colors = context.colors;
    final Widget input = LabeledField(
      label: label,
      hint: '($unitHint)',
      semanticLabel: '$label in $unitHint',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: signed,
        ),
        inputFormatters: signed ? _signedDecimal : _unsignedDecimal,
        onChanged: (_) => _recompute(),
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: AppTextSize.fieldNumeric),
        cursorColor: colors.textAccent,
        decoration: InputDecoration(hintText: hintText),
      ),
    );

    if (helper == null) return input;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        input,
        const SizedBox(height: AppSpacing.xs),
        Text(
          helper,
          style: text?.labelSmall?.copyWith(
            color: helperColor ?? colors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _txPowerUnitSelector() {
    return AppToggle<TxPowerUnit>(
      value: _txPowerUnit,
      items: const [
        (TxPowerUnit.dbm, 'dBm'),
        (TxPowerUnit.w, 'W'),
        (TxPowerUnit.mw, 'mW'),
      ],
      onChanged: (u) {
        setState(() => _txPowerUnit = u);
        _recompute();
      },
    );
  }

  static String _txPowerUnitLabel(TxPowerUnit u) {
    switch (u) {
      case TxPowerUnit.dbm:
        return 'dBm';
      case TxPowerUnit.w:
        return 'W';
      case TxPowerUnit.mw:
        return 'mW';
    }
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _resultRow(
            text: text,
            mono: mono,
            label: 'EIRP',
            value: _format(_eirpDbm),
            unit: _eirpDbm == null ? 'dBm' : 'dBm  (${_powerText(_eirpDbm!)})',
            valueColor: _eirpDbm == null
                ? colors.textTertiary
                : colors.textPrimary,
            blank: _eirpDbm == null,
          ),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(
            text: text,
            mono: mono,
            label: _fsplManual
                ? 'Free space path loss (manual)'
                : 'Free space path loss (calculated)',
            value: _format(
              LinkBudgetScreen.effectivePathLoss(
                manual: tryParseFlexibleDouble(_pathLossCtrl.text),
                calculated: _fsplCalculated,
              ),
            ),
            unit: 'dB',
            valueColor: colors.textPrimary,
            blank: !_fsplManual && _fsplCalculated == null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(
            text: text,
            mono: mono,
            label: 'Received signal',
            value: _format(_receivedDbm),
            unit: 'dBm',
            valueColor: _receivedDbm == null
                ? colors.textTertiary
                : colors.textPrimary,
            blank: _receivedDbm == null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: AppSpacing.sm),
          _resultRow(
            text: text,
            mono: mono,
            label: 'Link margin',
            value: _format(_marginDb),
            unit: 'dB',
            valueColor: _marginColor(),
            blank: _marginDb == null || !_marginDb!.isFinite,
            // Expose the pass/fail verdict word in the SR value so it does not
            // ride on color alone (colorblind + screen reader; §8.13 rule 2).
            verdictWord: _marginVerdictWord(),
          ),
        ],
      ),
    );
  }

  Widget _resultRow({
    required TextTheme text,
    required AppMonoText mono,
    required String label,
    required String value,
    required String unit,
    required Color valueColor,
    required bool blank,
    String? verdictWord,
  }) {
    final AppColorScheme colors = context.colors;
    // One SR node per readout: "Link margin: 12.0 dB, healthy" instead of the
    // value, unit, and verdict color announcing as separate fragments (finding
    // #6). The verdict word rides in the value so it never depends on color.
    final String semanticValue = blank
        ? 'not calculated'
        : verdictWord == null
        ? '$value $unit'
        : '$value $unit, $verdictWord';
    return Semantics(
      label: label,
      value: semanticValue,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                value,
                style: mono.outputXL.copyWith(color: valueColor),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                unit,
                style: text.labelLarge?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
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
            'Formula',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'RX = Tx + Gtx − Ltx − FSPL − Lrx + Grx − Lmisc',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'Margin = RX − Sensitivity',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'FSPL = 20·log10(f GHz) + 20·log10(d km) + 92.45',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          SelectableText(
            'EIRP = Tx + Gtx − Ltx',
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'All terms in dB except Tx (dBm or W/mW), EIRP and Sensitivity '
            '(dBm). FSPL is calculated from frequency and distance unless you '
            'type a value, which overrides it. '
            'A positive margin means the link closes; aim for 10 dB or more.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Margin-health bands matching the PWA color thresholds, with plain-language
    // guidance alongside the §8.13 status tint on the live readout (§8.13 rule 2
    // — the verdict is carried by words here, never color alone).
    final List<List<String>> refs = const [
      ['≥ 10 dB', 'Healthy, link has fade headroom'],
      ['0 to 10 dB', 'Marginal, vulnerable to fade'],
      ['< 0 dB', 'Link does not close'],
    ];

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
            'Margin guide',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...refs.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column width snaps to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
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
