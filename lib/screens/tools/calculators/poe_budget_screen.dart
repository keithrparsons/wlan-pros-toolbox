// PoE Budget calculator.
//
// Enter a switch PoE budget and up to six device rows (watts per device ×
// quantity); read total draw, remaining headroom, utilization, and a
// within-budget / caution / over-budget verdict.
//
// Math matches the RF Tools PWA reference (app.js calcPoeBudget, line 1147)
// VERBATIM:
//   total     = Σ (watts_i × qty_i) over the 6 rows
//   remaining = budget − total
//   pct       = min(100, (total / budget) × 100)
// The PWA guards budget > 0 (NaN / ≤ 0 → error, no result). Per-row blanks
// parse as 0 watts / 0 qty (PWA `parseFloat(...) || 0`).
//
// Status thresholds (PWA exactly): remaining < 0 → over budget (red);
// else pct > 80 → caution within 20% (orange/warning); else budget OK (green).
// Note the PWA's progress-bar tint uses a different cut (>90 red, >75 orange);
// this screen reproduces the bar tint too via `barColor` so both surfaces agree.
//
// Reference tables (POE_STDS, POE_CLASSES) mirror the PWA constants verbatim.
//
// Edge cases:
// - Budget empty / ≤ 0 / non-finite → blank the result block (no crash).
// - All device rows empty → total 0, full budget remaining, "Budget OK".
//
// Pure, no network, no platform APIs. Math lives in static functions so it is
// unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';

/// The verdict bucket for a computed budget, paired with words + a status color
/// so the result is never color-only (GL-003 §8.13 rule 2).
enum PoeVerdict { ok, caution, over }

/// A single device row: watts per device and quantity.
class PoeDeviceRow {
  const PoeDeviceRow(this.watts, this.qty);
  final double watts;
  final int qty;
}

/// The full computed budget outcome (PWA calcPoeBudget output).
class PoeBudgetResult {
  const PoeBudgetResult({
    required this.total,
    required this.budget,
    required this.remaining,
    required this.pct,
    required this.verdict,
  });

  final double total;
  final double budget;
  final double remaining; // budget − total; negative when over budget.
  final double pct; // capped at 100 for the utilization bar.
  final PoeVerdict verdict;
}

class PoeBudgetScreen extends StatefulWidget {
  const PoeBudgetScreen({super.key});

  /// Number of device rows, matching the PWA's poe-w1..6 / poe-q1..6 grid.
  static const int deviceRowCount = 6;

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js calcPoeBudget VERBATIM.

  /// Sum of watts × qty across [rows] (PWA: total += w * q).
  static double totalDraw(List<PoeDeviceRow> rows) {
    double total = 0;
    for (final PoeDeviceRow r in rows) {
      total += r.watts * r.qty;
    }
    return total;
  }

  /// The verdict bucket. PWA order: over (remaining < 0) → caution (pct > 80)
  /// → ok. The check is on the UNCAPPED total/budget ratio for `remaining`, and
  /// the capped pct for the caution band — but since remaining < 0 is handled
  /// first, the pct cap never masks an over-budget case.
  static PoeVerdict verdictFor(double remaining, double pct) {
    if (remaining < 0) return PoeVerdict.over;
    if (pct > 80) return PoeVerdict.caution;
    return PoeVerdict.ok;
  }

  /// Full compute. Returns null when [budget] is non-finite or ≤ 0 (PWA error
  /// path renders no result block).
  static PoeBudgetResult? compute(double budget, List<PoeDeviceRow> rows) {
    if (!budget.isFinite || budget <= 0) return null;
    final double total = totalDraw(rows);
    final double remaining = budget - total;
    final double pct = math.min(100, (total / budget) * 100);
    return PoeBudgetResult(
      total: total,
      budget: budget,
      remaining: remaining,
      pct: pct,
      verdict: verdictFor(remaining, pct),
    );
  }

  @override
  State<PoeBudgetScreen> createState() => _PoeBudgetScreenState();
}

class _PoeBudgetScreenState extends State<PoeBudgetScreen> {
  final TextEditingController _budgetCtrl = TextEditingController();

  // Per-row watts + qty controllers. PWA seeds qty with value="1".
  late final List<TextEditingController> _wattsCtrls;
  late final List<TextEditingController> _qtyCtrls;

  PoeBudgetResult? _result;

  // Unsigned-decimal for watts/budget; unsigned-integer for quantity.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];
  static final List<TextInputFormatter> _unsignedInteger = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  @override
  void initState() {
    super.initState();
    _wattsCtrls = List.generate(
      PoeBudgetScreen.deviceRowCount,
      (_) => TextEditingController(),
    );
    // PWA quantity inputs default to "1".
    _qtyCtrls = List.generate(
      PoeBudgetScreen.deviceRowCount,
      (_) => TextEditingController(text: '1'),
    );
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    for (final TextEditingController c in _wattsCtrls) {
      c.dispose();
    }
    for (final TextEditingController c in _qtyCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double? budget = _tryParseDouble(_budgetCtrl.text);
    if (budget == null) {
      setState(() => _result = null);
      return;
    }
    final List<PoeDeviceRow> rows = [
      for (int i = 0; i < PoeBudgetScreen.deviceRowCount; i++)
        PoeDeviceRow(
          // PWA: parseFloat(...) || 0 — blank / invalid → 0.
          _tryParseDouble(_wattsCtrls[i].text) ?? 0,
          _tryParseInt(_qtyCtrls[i].text) ?? 0,
        ),
    ];
    setState(() => _result = PoeBudgetScreen.compute(budget, rows));
  }

  // ─── Parsing ──────────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  static int? _tryParseInt(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  /// PWA fmt(n, d): fixed-decimal, "—" when not finite.
  static String _fmt(double? n, int decimals) {
    if (n == null || !n.isFinite) return '—';
    return n.toStringAsFixed(decimals);
  }

  /// PWA poe-remain string: `<abs> W remaining` or `−<abs> W over`.
  static String _remainingLabel(double remaining) {
    final bool over = remaining < 0;
    final String sign = over ? '−' : '';
    return '$sign${_fmt(remaining.abs(), 1)} W ${over ? 'over' : 'remaining'}';
  }

  static String _verdictText(PoeVerdict v) {
    switch (v) {
      case PoeVerdict.over:
        return 'Over budget — reduce devices or upgrade switch';
      case PoeVerdict.caution:
        return 'Caution — within 20% of budget limit';
      case PoeVerdict.ok:
        return 'Budget OK';
    }
  }

  /// Status-word color (GL-003 §8.13 palette). PWA: red / orange / green.
  static Color _verdictColor(PoeVerdict v) {
    switch (v) {
      case PoeVerdict.over:
        return AppColors.statusDanger;
      case PoeVerdict.caution:
        return AppColors.statusWarning;
      case PoeVerdict.ok:
        return AppColors.statusSuccess;
    }
  }

  /// Utilization-bar tint. PWA uses a different cut than the status word:
  /// pct > 90 red, > 75 orange, else green.
  static Color _barColor(double pct) {
    if (pct > 90) return AppColors.statusDanger;
    if (pct > 75) return AppColors.statusWarning;
    return AppColors.statusSuccess;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(title: const Text('PoE Budget'), toolbarHeight: 64),
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
                      // §8.6.2 concept-graphic header band — first child, above
                      // the input card. Self-collapses when no graphic is
                      // bundled, so the 24px gap below it disappears too.
                      ConceptGraphicBand(
                        toolId: 'poe-budget',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('poe-budget'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _standardsCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _classesCard(text, mono),
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
            label: 'Switch PoE budget',
            hint: '(W)',
            semanticLabel: 'Switch PoE budget in watts',
            field: TextField(
              controller: _budgetCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '370'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Connected devices',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _deviceHeader(text),
          for (int i = 0; i < PoeBudgetScreen.deviceRowCount; i++) ...[
            const SizedBox(height: AppSpacing.xs),
            _deviceRow(i, mono),
          ],
        ],
      ),
    );
  }

  Widget _deviceHeader(TextTheme text) {
    final TextStyle? style = text.labelSmall?.copyWith(
      color: AppColors.textTertiary,
    );
    return Row(
      children: [
        Expanded(flex: 3, child: Text('Watts / device', style: style)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(flex: 2, child: Text('Quantity', style: style)),
      ],
    );
  }

  Widget _deviceRow(int i, AppMonoText mono) {
    final int rowNum = i + 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Semantics(
            label: 'Device $rowNum watts per device',
            textField: true,
            child: TextField(
              controller: _wattsCtrls[i],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _unsignedDecimal,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: 'W'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: Semantics(
            label: 'Device $rowNum quantity',
            textField: true,
            child: TextField(
              controller: _qtyCtrls[i],
              keyboardType: TextInputType.number,
              inputFormatters: _unsignedInteger,
              onChanged: (_) => _recompute(),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              style: mono.outputLarge.copyWith(
                fontSize: AppTextSize.fieldNumeric,
              ),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: 'Qty'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final PoeBudgetResult? r = _result;

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
          Text(
            'Result',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (r == null)
            // Empty / invalid budget → blank, no crash.
            Text(
              'Enter a switch PoE budget to calculate.',
              style: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
            )
          else ...[
            _utilizationBar(r, text, mono),
            const SizedBox(height: AppSpacing.md),
            _resultRow(text, mono, 'Total draw', '${_fmt(r.total, 1)} W'),
            _resultRow(text, mono, 'Switch budget', '${_fmt(r.budget, 0)} W'),
            _resultRow(
              text,
              mono,
              'Remaining',
              _remainingLabel(r.remaining),
              valueColor: _verdictColor(r.verdict),
            ),
            _resultRow(
              text,
              mono,
              'Utilization',
              '${r.pct.toStringAsFixed(0)}%',
            ),
            const SizedBox(height: AppSpacing.sm),
            _statusLine(r.verdict, text),
          ],
        ],
      ),
    );
  }

  Widget _utilizationBar(PoeBudgetResult r, TextTheme text, AppMonoText mono) {
    final Color fill = _barColor(r.pct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Utilization',
          value: '${r.pct.toStringAsFixed(0)} percent of budget',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Stack(
              children: [
                Container(height: AppSpacing.sm, color: AppColors.inputFill),
                FractionallySizedBox(
                  // pct is capped at 100, so the fraction never exceeds 1.
                  widthFactor: (r.pct / 100).clamp(0.0, 1.0),
                  child: Container(height: AppSpacing.sm, color: fill),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono,
    String label,
    String value, {
    Color? valueColor,
  }) {
    // One SR node per row: "Total draw: 142.0 W", instead of label and value as
    // separate fragments (Vera finding #6). The "Remaining" row's verdict color
    // is never the only signal — the worded verdict lives in the status line
    // below (§8.13 rule 2).
    return Semantics(
      label: label,
      value: value,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SelectableText(
              value,
              style: mono.inlineCode.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The §8.13 status verdict — colored word never standing on color alone.
  Widget _statusLine(PoeVerdict verdict, TextTheme text) {
    final Color color = _verdictColor(verdict);
    final IconData icon;
    switch (verdict) {
      case PoeVerdict.over:
        icon = Icons.error_outline;
      case PoeVerdict.caution:
        icon = Icons.warning_amber_outlined;
      case PoeVerdict.ok:
        icon = Icons.check_circle_outline;
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.md, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              _verdictText(verdict),
              style: text.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _standardsCard(TextTheme text, AppMonoText mono) {
    // POE_STDS mirror: [standard, name, PSE W, PD W].
    final List<List<String>> rows = const [
      ['802.3af', 'PoE', '15.4 W', '12.95 W'],
      ['802.3at', 'PoE+', '30.0 W', '25.5 W'],
      ['802.3bt Type 3', 'PoE++ / 4PPoE', '60.0 W', '51.0 W'],
      ['802.3bt Type 4', 'PoE++ Hi', '100.0 W', '71.3 W'],
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
            'PoE standards',
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
                    width: 120,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      row[3],
                      textAlign: TextAlign.right,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'PD W is the power available at the device (after cable loss).',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _classesCard(TextTheme text, AppMonoText mono) {
    // POE_CLASSES mirror: [class, max PD W, standard].
    final List<List<String>> rows = const [
      ['0', '12.95 W', '802.3af'],
      ['1', '3.84 W', '802.3af'],
      ['2', '6.49 W', '802.3af'],
      ['3', '12.95 W', '802.3af'],
      ['4', '25.5 W', '802.3at'],
      ['5', '40.0 W', '802.3bt'],
      ['6', '51.0 W', '802.3bt'],
      ['7', '62.0 W', '802.3bt'],
      ['8', '71.3 W', '802.3bt'],
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
            'PD power classes',
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
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      'Class ${row[0]}',
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
                  SizedBox(
                    width: 72,
                    child: Text(
                      row[1],
                      textAlign: TextAlign.right,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
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
