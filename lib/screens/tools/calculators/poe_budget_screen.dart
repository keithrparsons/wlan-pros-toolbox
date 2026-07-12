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
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../utils/decimal_input.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
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

  // ─── 802.3bt Type 4 PSE — settled from the standard ───────────────────────
  //
  // 90 W. Per IEEE Std 802.3-2022, Table 145-11, the Class 8 P_Class value —
  // the PSE's minimum output power for that class — is 90 W.
  //
  // ⚠️ WHERE THE WRONG NUMBER CAME FROM, SO IT DOES NOT COME BACK ⚠️
  //
  // This screen used to hold 100.0 W (hidden — the PSE column was never
  // rendered, see [_standardsCard], which is why the contradiction with
  // poe_reference_screen.dart's 90.0 W went unnoticed for so long).
  //
  // 100 is Table 145-16 item 13 — P_Type for a Type 4 PSE, given as
  // min 75 W / MAX 99.9 W — rounded up. That is the PSE's power-RATING BAND.
  // It is NOT the per-class output power. Two different quantities in two
  // different tables, and reading across from one to the other is exactly the
  // mistake that shipped.
  //
  // If you are here because 90 "looks low" next to a 99.9 W figure you found:
  // you have found P_Type. You want P_Class. Table 145-11.
  //
  // These two constants are asserted TOGETHER in test/audit/audit_wave_1_test
  // ("the on-screen IEEE citation is pinned to the value it cites"). A citation
  // that is not checked against the source is worse than no citation — this app
  // has already shipped a screen that rendered a real IEEE reference above a
  // table of wrong rows. Do not separate the number from its proof.

  /// PSE output power for an 802.3bt Type 4 (Class 8) port, in watts.
  static const double typeFourPseWatts = 90.0;

  /// The exact clause this figure is read from. Pinned by test alongside
  /// [typeFourPseWatts]; never change one without the other.
  static const String typeFourPseCitation =
      'IEEE 802.3-2022, Table 145-11 (P_Class)';

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
  static final List<TextInputFormatter> _unsignedDecimal = unsignedDecimalFormatters;
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
    final double? budget = tryParseFlexibleDouble(_budgetCtrl.text);
    if (budget == null) {
      setState(() => _result = null);
      return;
    }
    final List<PoeDeviceRow> rows = [
      for (int i = 0; i < PoeBudgetScreen.deviceRowCount; i++)
        PoeDeviceRow(
          // PWA: parseFloat(...) || 0 — blank / invalid → 0.
          tryParseFlexibleDouble(_wattsCtrls[i].text) ?? 0,
          _tryParseInt(_qtyCtrls[i].text) ?? 0,
        ),
    ];
    setState(() => _result = PoeBudgetScreen.compute(budget, rows));
  }

  // ─── Parsing ──────────────────────────────────────────────────────────────

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
  static Color _verdictColor(PoeVerdict v, AppColorScheme colors) {
    switch (v) {
      case PoeVerdict.over:
        return colors.statusDanger;
      case PoeVerdict.caution:
        return colors.statusWarning;
      case PoeVerdict.ok:
        return colors.statusSuccess;
    }
  }

  /// Utilization-bar tint. PWA uses a different cut than the status word:
  /// pct > 90 red, > 75 orange, else green.
  static Color _barColor(double pct, AppColorScheme colors) {
    if (pct > 90) return colors.statusDanger;
    if (pct > 75) return colors.statusWarning;
    return colors.statusSuccess;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PoE Budget'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled while the switch
        // budget is empty/invalid (no result block); copies the budget summary
        // as a labeled text block, carrying the §8.13 verdict WORD. Copy leads;
        // no help icon here.
        actions: <Widget>[
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
                      ToolHelpFooter(toolId: 'poe-budget'),
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

  /// Short verdict word for the clipboard headline (§8.16 / §8.13 rule 2 — the
  /// color is the on-screen carrier, the word is the clipboard carrier). The
  /// full advisory sentence rides along beneath it.
  static String _verdictWord(PoeVerdict v) {
    switch (v) {
      case PoeVerdict.over:
        return 'Over budget';
      case PoeVerdict.caution:
        return 'Caution';
      case PoeVerdict.ok:
        return 'Budget OK';
    }
  }

  /// §8.16 copy payload — the PoE budget summary as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) while the switch budget is empty,
  /// non-finite, or ≤ 0 (no result block). The verdict line carries the §8.13
  /// status WORD plus the full advisory; values match the on-screen result card.
  String? _buildCopyText() {
    final PoeBudgetResult? r = _result;
    if (r == null) return null;

    return (StringBuffer()
          ..writeln('PoE Budget')
          ..writeln('Switch budget: ${_fmt(r.budget, 0)} W')
          ..writeln('Total draw: ${_fmt(r.total, 1)} W')
          ..writeln('Remaining: ${_remainingLabel(r.remaining)}')
          ..writeln('Utilization: ${r.pct.toStringAsFixed(0)}%')
          ..writeln('Verdict: ${_verdictWord(r.verdict)}')
          ..writeln(_verdictText(r.verdict)))
        .toString()
        .trimRight();
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
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '370'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Connected devices',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
    final AppColorScheme colors = context.colors;
    final TextStyle? style = text.labelSmall?.copyWith(
      color: colors.textTertiary,
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
    final AppColorScheme colors = context.colors;
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
              cursorColor: colors.textAccent,
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
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: 'Qty'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final PoeBudgetResult? r = _result;

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
          Text(
            'Result',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (r == null)
            // Empty / invalid budget → blank, no crash.
            Text(
              'Enter a switch PoE budget to calculate.',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
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
              valueColor: _verdictColor(r.verdict, colors),
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
    final AppColorScheme colors = context.colors;
    final Color fill = _barColor(r.pct, colors);
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
                Container(height: AppSpacing.sm, color: colors.inputFill),
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
    final AppColorScheme colors = context.colors;
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
                  color: colors.textSecondary,
                ),
              ),
            ),
            SelectableText(
              value,
              style: mono.inlineCode.copyWith(
                color: valueColor ?? colors.textPrimary,
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
    final AppColorScheme colors = context.colors;
    final Color color = _verdictColor(verdict, colors);
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
        color: colors.inputFill,
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

  /// Width of each watt column in the standards card. 72px fits "12.95 W" in
  /// the mono face without clipping, and snaps to the 8px base unit (GL-003 §4).
  static const double _poeColW = 72;

  Widget _standardsCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // [standard, name, PSE W, PD W].
    //
    // THE BUG THIS FIXES: this list has always held four columns, but the render
    // below emitted row[0], row[1], row[3] — silently dropping row[2], the PSE
    // watts. That is the number that matters most: a switch budget is spent in
    // PSE watts, not PD watts. Twelve Class-4 APs read 306 W of PD against a
    // 370 W switch and look comfortable; the switch actually delivers 360 W and
    // is nearly exhausted. Both columns now render, labeled.
    //
    final List<List<String>> rows = <List<String>>[
      const <String>['802.3af', 'PoE', '15.4 W', '12.95 W'],
      const <String>['802.3at', 'PoE+', '30.0 W', '25.5 W'],
      const <String>['802.3bt Type 3', 'PoE++ / 4PPoE', '60.0 W', '51.0 W'],
      <String>[
        '802.3bt Type 4',
        'PoE++ Hi',
        '${PoeBudgetScreen.typeFourPseWatts.toStringAsFixed(1)} W',
        '71.3 W',
      ],
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
            'PoE standards',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Column header — without it, two bare watt figures per row are
          // ambiguous, and PSE-vs-PD is exactly the distinction that matters.
          //
          // LAYOUT: the standard and its friendly name are STACKED in one
          // flexible cell, so the two watt columns keep their full width even at
          // 375px. Laying standard / name / PSE / PD out as four side-by-side
          // columns squeezed the name cell to ~55px on a phone, wrapping
          // "802.3bt Type 3" across three lines and butting the two watt values
          // together ("15.4 W12.95 W").
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                SizedBox(
                  width: _poeColW,
                  child: Text(
                    'PSE',
                    textAlign: TextAlign.right,
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: _poeColW,
                  child: Text(
                    'PD',
                    textAlign: TextAlign.right,
                    style: text.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...rows.map((row) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Standard + friendly name, stacked.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          row[0],
                          style: mono.inlineCode.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        Text(
                          row[1],
                          style: text.labelSmall?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // PSE — accented, because this is the number a switch budget
                  // is actually spent in.
                  SizedBox(
                    width: _poeColW,
                    child: Text(
                      row[2],
                      textAlign: TextAlign.right,
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // PD — secondary: what actually lands at the device.
                  SizedBox(
                    width: _poeColW,
                    child: Text(
                      row[3],
                      textAlign: TextAlign.right,
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'PSE W is what the switch port must supply. This is the number a '
            'switch budget is spent in. PD W is what reaches the device after '
            'cable loss. Budget in PSE watts: a rack of Class-4 APs draws '
            '30.0 W each from the switch, not 25.5 W.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          // The citation, rendered. It is pinned to the value by test, so this
          // line cannot drift away from the number it justifies.
          Text(
            'PSE figures per ${PoeBudgetScreen.typeFourPseCitation}. Type 4 '
            'supplies 90 W: the 99.9 W figure sometimes quoted is the PSE '
            'power rating band (P_Type), not the per-class output power.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _classesCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
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
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PD power classes',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[2],
                      style: text.labelMedium?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      row[1],
                      textAlign: TextAlign.right,
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
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
