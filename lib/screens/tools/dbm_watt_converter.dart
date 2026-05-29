// dBm / Watt Converter — first live tool.
//
// Bidirectional across three units (dBm, Watts, mW). Typing in any one field
// updates the other two in real time, including from a cold start. Formulas
// match the RF Tools PWA reference implementation:
//   Watts = 10^(dBm/10) / 1000     dBm   = 10 * log10(Watts * 1000)
//   mW    = 10^(dBm/10)            dBm   = 10 * log10(mW)
//
// Behavior matches PWA app.js convertDbmToW / convertWToDbm / convertMwToDbm.
// Watts uses scientific notation (toStringAsExponential) because real Wi-Fi
// receive values land at 0.0000000001 W — fixed notation is unreadable.
// mW uses fixed notation with 4 decimals.
//
// Edge cases:
// - Empty input → blank the other fields (no crash).
// - Invalid keystroke → blocked by input formatters.
// - Watts <= 0 or mW <= 0 → log10 undefined; show "—" in dBm field.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';

class DbmWattConverterScreen extends StatefulWidget {
  const DbmWattConverterScreen({super.key});

  @override
  State<DbmWattConverterScreen> createState() => _DbmWattConverterScreenState();
}

class _DbmWattConverterScreenState extends State<DbmWattConverterScreen> {
  final TextEditingController _dbmCtrl = TextEditingController();
  final TextEditingController _wattsCtrl = TextEditingController();
  final TextEditingController _mwCtrl = TextEditingController();

  final FocusNode _dbmFocus = FocusNode();
  final FocusNode _wattsFocus = FocusNode();
  final FocusNode _mwFocus = FocusNode();

  // Formatters. dBm and Watts both accept `e/E/+` alongside digits, dot, and
  // minus so a paste like "1e2" either parses as 100 or fails cleanly — the
  // pre-fix formatter silently stripped the `e` and coerced `1e2` to `12`
  // (Vera F-07). mW stays unsigned-decimal — no scientific notation, no sign,
  // because mW values are entered by humans, not pasted from instruments.
  static final List<TextInputFormatter> _signedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.eE+\-]')),
  ];
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _dbmCtrl.dispose();
    _wattsCtrl.dispose();
    _mwCtrl.dispose();
    _dbmFocus.dispose();
    _wattsFocus.dispose();
    _mwFocus.dispose();
    super.dispose();
  }

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js: dBmToWatts, wattsTodBm, dBmToMilliwatts.

  static double _dbmToWatts(double dbm) => math.pow(10, dbm / 10).toDouble() / 1000.0;
  static double _wattsTodBm(double w) => 10 * (math.log(w * 1000) / math.ln10);
  static double _dbmToMilliwatts(double dbm) => math.pow(10, dbm / 10).toDouble();

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _onDbmChanged(String raw) {
    final double? dbm = _tryParseDouble(raw);
    if (dbm == null) {
      _wattsCtrl.text = '';
      _mwCtrl.text = '';
      setState(() {});
      return;
    }
    final double watts = _dbmToWatts(dbm);
    final double mw = _dbmToMilliwatts(dbm);
    _wattsCtrl.text = _formatWatts(watts);
    _mwCtrl.text = _formatFixed(mw, 4);
    setState(() {});
  }

  void _onWattsChanged(String raw) {
    final double? w = _tryParseDouble(raw);
    if (w == null || w <= 0) {
      // Vera F-06 — write the zero case as a fixed 4-decimal "0.0000" so the
      // mirror field reads consistently with normal mW formatting, instead of
      // a literal "0" that mismatches every other rendered value.
      _dbmCtrl.text = w == null ? '' : '—';
      _mwCtrl.text = w == null ? '' : _formatFixed(0, 4);
      setState(() {});
      return;
    }
    _dbmCtrl.text = _formatFixed(_wattsTodBm(w), 2);
    _mwCtrl.text = _formatFixed(w * 1000, 4);
    setState(() {});
  }

  void _onMwChanged(String raw) {
    final double? mw = _tryParseDouble(raw);
    if (mw == null || mw <= 0) {
      // Vera F-06 (mirror) — same fix on the mW→Watts side. Watts uses
      // scientific format normally; show "0.0000" in the zero case so the
      // field reads as "a real result" rather than a parsing artifact.
      _dbmCtrl.text = mw == null ? '' : '—';
      _wattsCtrl.text = mw == null ? '' : _formatFixed(0, 4);
      setState(() {});
      return;
    }
    _dbmCtrl.text = _formatFixed(_wattsTodBm(mw / 1000), 2);
    _wattsCtrl.text = _formatWatts(mw / 1000);
    setState(() {});
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    return double.tryParse(s);
  }

  /// Mirrors the PWA: Watts > 0 → 4-sig scientific notation, with explicit
  /// "1.2345e-10" form so the magnitude is obvious. The PWA used
  /// `toExponential(4)` (4 digits after the decimal, so 5 sig figs total).
  static String _formatWatts(double w) {
    if (!w.isFinite) return '';
    if (w == 0) return '0';
    return w.toStringAsExponential(4);
  }

  static String _formatFixed(double n, int decimals) {
    if (!n.isFinite) return '—';
    return n.toStringAsFixed(decimals);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('dBm / Watt'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
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
                      _converterCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
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

  Widget _converterCard(TextTheme text, AppMonoText mono) {
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
          _ConverterField(
            label: 'dBm',
            unitHint: 'decibel-milliwatts',
            controller: _dbmCtrl,
            focusNode: _dbmFocus,
            formatters: _signedDecimal,
            onChanged: _onDbmChanged,
            monoStyle: mono.outputLarge,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ConverterField(
            label: 'Watts',
            unitHint: 'W',
            controller: _wattsCtrl,
            focusNode: _wattsFocus,
            // _signedDecimal already accepts e/E/+ (Vera F-07 fix), so the
            // Watts field gets scientific-notation input out of the box.
            formatters: _signedDecimal,
            onChanged: _onWattsChanged,
            monoStyle: mono.outputLarge,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _ConverterField(
            label: 'Milliwatts',
            unitHint: 'mW',
            controller: _mwCtrl,
            focusNode: _mwFocus,
            formatters: _unsignedDecimal,
            onChanged: _onMwChanged,
            monoStyle: mono.outputLarge,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulaCard(TextTheme text, AppMonoText mono) {
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
            'Formula',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'dBm = 10 · log₁₀(mW)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          SelectableText(
            'W   = 10^(dBm/10) / 1000',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Compact, high-signal anchor values pulled from the PWA DBM_REFS list.
    // Kept short here — the full table belongs in a dedicated Reference tool.
    // Vera F-08 — standardize on ASCII hyphen-minus (U+002D) here so the
    // reference card glyph matches the live `toStringAsFixed` output in the
    // dBm field. The pre-fix rows used Unicode minus (U+2212), which is
    // visually wider than the ASCII the converter writes.
    final List<List<String>> refs = const [
      ['+30 dBm', '1,000 mW', '1 W, FCC 2.4 GHz max conducted'],
      ['+20 dBm', '100 mW', 'Common default AP Tx power'],
      ['0 dBm', '1 mW', 'Reference point, 1 milliwatt'],
      ['-70 dBm', '0.1 nW', 'Minimum for enterprise data'],
      ['-80 dBm', '10 pW', 'Typical Wi-Fi receiver sensitivity'],
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
            'Reference points',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...refs.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vera F-10 — column widths snap to the 8px base unit
                  // (GL-003 §4). 88px was off-grid; 96px holds every
                  // reference value without truncating "1,000 mW".
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[1],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[2],
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
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

/// Single label + input row. Pulled out so the three fields stay consistent.
class _ConverterField extends StatelessWidget {
  const _ConverterField({
    required this.label,
    required this.unitHint,
    required this.controller,
    required this.focusNode,
    required this.formatters,
    required this.onChanged,
    required this.monoStyle,
    required this.keyboardType,
  });

  final String label;
  final String unitHint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onChanged;
  final TextStyle monoStyle;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: text.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($unitHint)',
              style: text.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          inputFormatters: formatters,
          onChanged: onChanged,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          style: monoStyle.copyWith(fontSize: 20),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: _hintFor(label),
          ),
        ),
      ],
    );
  }

  String _hintFor(String label) {
    switch (label) {
      case 'dBm':
        return '0';
      case 'Watts':
        return '0.001';
      case 'Milliwatts':
        return '1';
      default:
        return '';
    }
  }
}
