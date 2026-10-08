// PoE Budget calculator.
//
// Enter a switch PoE budget, its PoE port count, its PSE type and a reserve %,
// then up to six device rows. Each row is either a PoE class (0-8), budgeted at
// that class's PSE allocation, or watts per device, budgeted as entered (PD
// watts, nothing added for cable loss). Read the total PSE allocation, the
// watts left after the reserve, ports needed vs available, a per-row port-type
// check, and a fits / caution / does-not-fit verdict.
//
// Class PSE allocations and per-type class ranges are NOT duplicated here: they
// are read from PoeReferenceScreen.classes / .standards (IEEE Std 802.3-2022,
// Clause 33 and Table 145-11), so the two screens cannot disagree.
//
// Math. With reserve 0 and every row in watts, this is the RF Tools PWA
// reference (app.js calcPoeBudget, line 1147) VERBATIM:
//   total     = Σ (allocation_i × qty_i) over the 6 rows
//   usable    = budget × (1 − reserve% / 100)
//   remaining = usable − total
//   pct       = min(100, (total / usable) × 100)
// The PWA guards budget > 0 (NaN / ≤ 0 → error, no result); reserve must be
// 0 ≤ r < 100. Per-row blanks parse as 0 watts / 0 qty (PWA
// `parseFloat(...) || 0`).
//
// Status thresholds (PWA exactly, applied to the usable budget): remaining < 0
// → over budget (red); else pct > 80 → caution within 20% (orange/warning);
// else budget OK (green). Ports short, or any row failing the port-type check,
// also make the verdict "does not fit" (red).
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
import '../../../widgets/app_select.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import '../reference/poe_reference_screen.dart';

/// The verdict bucket for a computed budget, paired with words + a status color
/// so the result is never color-only (GL-003 §8.13 rule 2).
enum PoeVerdict { ok, caution, over }

/// The PSE type of the switch's PoE ports. [notSet] skips the per-row check.
enum PoePortType { notSet, af, at, bt3, bt4 }

/// A single device row: either a PoE class or watts per device, and a quantity.
class PoeDeviceRow {
  /// A watts row: [watts] is the device's PD draw, budgeted as entered.
  const PoeDeviceRow(this.watts, this.qty) : poeClass = null;

  /// A class row: budgeted at the PSE allocation for [poeClass] (0-8).
  const PoeDeviceRow.ofClass(int this.poeClass, this.qty) : watts = 0;

  final double watts;
  final int? poeClass;
  final int qty;

  bool get isClass => poeClass != null;

  /// A row that asks for power: a class row, or a watts row above 0, with qty.
  bool get isActive => qty > 0 && (isClass || watts > 0);
}

/// One row that fails the port-type check, for display and copy.
class PoeRowProblem {
  const PoeRowProblem(this.rowNumber, this.message);
  final int rowNumber; // 1-based, as shown on screen.
  final String message;
}

/// The full computed budget outcome.
class PoeBudgetResult {
  const PoeBudgetResult({
    required this.total,
    required this.budget,
    required this.reservePct,
    required this.remaining,
    required this.pct,
    required this.verdict,
    this.portsNeeded = 0,
    this.portsAvailable,
    this.portType = PoePortType.notSet,
    this.rowProblems = const <PoeRowProblem>[],
    this.usesWattsRows = false,
  });

  final double total; // Σ PSE allocation (class rows) + PD watts (watts rows).
  final double budget;
  final double reservePct;
  final double remaining; // usable − total; negative when over budget.
  final double pct; // of the usable budget, capped at 100 for the bar.
  final PoeVerdict verdict;
  final int portsNeeded;
  final int? portsAvailable; // null when the port count was not entered.
  final PoePortType portType;
  final List<PoeRowProblem> rowProblems;
  final bool usesWattsRows; // any active watts row: PD watts, no cable loss.

  double get reserveWatts => budget * reservePct / 100;
  double get usable => budget - reserveWatts;
  bool get overBudget => remaining < 0;
  bool get portsShort =>
      portsAvailable != null && portsNeeded > portsAvailable!;
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
  // With reserve 0 and watts rows only, mirrors app.js calcPoeBudget VERBATIM.

  /// PSE allocation for PoE class [poeClass], in watts, read from the
  /// reference screen's class table (IEEE 802.3-2022). Null outside 0-8.
  static double? classPseWatts(int poeClass) {
    for (final PoeClass c in PoeReferenceScreen.classes) {
      if (c.classNum == poeClass) return c.pseWatts;
    }
    return null;
  }

  /// What one device in [row] is budgeted at: its class's PSE allocation, or
  /// the watts entered (PD watts, nothing added for cable loss).
  static double allocationFor(PoeDeviceRow row) =>
      row.isClass ? (classPseWatts(row.poeClass!) ?? 0) : row.watts;

  /// Sum of allocation × qty across [rows] (PWA: total += w * q).
  static double totalDraw(List<PoeDeviceRow> rows) {
    double total = 0;
    for (final PoeDeviceRow r in rows) {
      total += allocationFor(r) * r.qty;
    }
    return total;
  }

  /// Ports the rows need: one per device in every active row.
  static int portsNeeded(List<PoeDeviceRow> rows) {
    int n = 0;
    for (final PoeDeviceRow r in rows) {
      if (r.isActive) n += r.qty;
    }
    return n;
  }

  /// The reference-table row for a port type, or null for [PoePortType.notSet].
  static PoeStandard? standardFor(PoePortType type) {
    final String? name = switch (type) {
      PoePortType.notSet => null,
      PoePortType.af => '802.3af',
      PoePortType.at => '802.3at',
      PoePortType.bt3 => '802.3bt Type 3',
      PoePortType.bt4 => '802.3bt Type 4',
    };
    if (name == null) return null;
    return PoeReferenceScreen.standards.firstWhere(
      (PoeStandard s) => s.standard == name,
    );
  }

  /// Highest class a port of [type] supports, from the table's "0-4" range.
  static int? maxClassFor(PoePortType type) {
    final PoeStandard? s = standardFor(type);
    if (s == null) return null;
    return int.parse(s.classes.split('-').last);
  }

  /// Why one device in [row] cannot run from a port of [type], or null if it
  /// can (or if the type is not set, or the row asks for nothing). A class row
  /// fails above the type's highest class; a watts row fails above the type's
  /// PD watts (what reaches the device).
  static String? rowPortProblem(PoeDeviceRow row, PoePortType type) {
    final PoeStandard? s = standardFor(type);
    if (s == null || !row.isActive) return null;
    if (row.isClass) {
      final int max = maxClassFor(type)!;
      if (row.poeClass! <= max) return null;
      return 'Class ${row.poeClass} needs more than an ${s.standard} port '
          'gives (up to Class $max)';
    }
    if (row.watts <= s.pdWatts) return null;
    return '${row.watts.toStringAsFixed(1)} W needs more than an '
        '${s.standard} port gives (${_trim(s.pdWatts)} W at the device)';
  }

  static String _trim(double w) =>
      w == w.roundToDouble() ? w.toStringAsFixed(1) : w.toString();

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
  /// path renders no result block), or when [reservePct] is not 0 ≤ r < 100.
  /// [ports] null means the port count was not entered, so it is not checked.
  static PoeBudgetResult? compute(
    double budget,
    List<PoeDeviceRow> rows, {
    double reservePct = 0,
    int? ports,
    PoePortType portType = PoePortType.notSet,
  }) {
    if (!budget.isFinite || budget <= 0) return null;
    if (!reservePct.isFinite || reservePct < 0 || reservePct >= 100) {
      return null;
    }
    final double total = totalDraw(rows);
    final double usable = budget * (1 - reservePct / 100);
    final double remaining = usable - total;
    final double pct = math.min(100, (total / usable) * 100);
    final List<PoeRowProblem> problems = <PoeRowProblem>[
      for (int i = 0; i < rows.length; i++)
        if (rowPortProblem(rows[i], portType) case final String m)
          PoeRowProblem(i + 1, m),
    ];
    final int needed = portsNeeded(rows);
    final bool portsShort = ports != null && needed > ports;
    final PoeVerdict watts = verdictFor(remaining, pct);
    return PoeBudgetResult(
      total: total,
      budget: budget,
      reservePct: reservePct,
      remaining: remaining,
      pct: pct,
      verdict: (portsShort || problems.isNotEmpty) ? PoeVerdict.over : watts,
      portsNeeded: needed,
      portsAvailable: ports,
      portType: portType,
      rowProblems: problems,
      usesWattsRows: rows.any((PoeDeviceRow r) => r.isActive && !r.isClass),
    );
  }

  @override
  State<PoeBudgetScreen> createState() => _PoeBudgetScreenState();
}

class _PoeBudgetScreenState extends State<PoeBudgetScreen> {
  final TextEditingController _budgetCtrl = TextEditingController();
  final TextEditingController _portsCtrl = TextEditingController();
  // Reserve defaults to 10% of the budget, held back for growth and inrush.
  final TextEditingController _reserveCtrl = TextEditingController(text: '10');
  PoePortType _portType = PoePortType.notSet;

  /// Per-row kind: [_wattsKind] for a watts row, or the PoE class 0-8.
  static const int _wattsKind = -1;
  late final List<int> _rowKinds;

  // Per-row watts + qty controllers. PWA seeds qty with value="1".
  late final List<TextEditingController> _wattsCtrls;
  late final List<TextEditingController> _qtyCtrls;

  PoeBudgetResult? _result;

  // Unsigned-decimal for watts/budget; unsigned-integer for quantity.
  static final List<TextInputFormatter> _unsignedDecimal =
      unsignedDecimalFormatters;
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
    // Rows start as watts rows, so a blank row asks for nothing.
    _rowKinds = List<int>.filled(PoeBudgetScreen.deviceRowCount, _wattsKind);
    // PWA quantity inputs default to "1".
    _qtyCtrls = List.generate(
      PoeBudgetScreen.deviceRowCount,
      (_) => TextEditingController(text: '1'),
    );
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    _portsCtrl.dispose();
    _reserveCtrl.dispose();
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
        if (_rowKinds[i] == _wattsKind)
          PoeDeviceRow(
            // PWA: parseFloat(...) || 0 — blank / invalid → 0.
            tryParseFlexibleDouble(_wattsCtrls[i].text) ?? 0,
            _tryParseInt(_qtyCtrls[i].text) ?? 0,
          )
        else
          PoeDeviceRow.ofClass(
            _rowKinds[i],
            _tryParseInt(_qtyCtrls[i].text) ?? 0,
          ),
    ];
    // A blank reserve counts as 0%; an out-of-range one blanks the result.
    final double reserve = _reserveCtrl.text.trim().isEmpty
        ? 0
        : (tryParseFlexibleDouble(_reserveCtrl.text) ?? double.nan);
    setState(
      () => _result = PoeBudgetScreen.compute(
        budget,
        rows,
        reservePct: reserve,
        ports: _tryParseInt(_portsCtrl.text),
        portType: _portType,
      ),
    );
  }

  /// True when the reserve field holds something compute() rejects.
  bool get _reserveInvalid {
    if (_reserveCtrl.text.trim().isEmpty) return false;
    final double? r = tryParseFlexibleDouble(_reserveCtrl.text);
    return r == null || r < 0 || r >= 100;
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

  static String _verdictText(PoeBudgetResult r) {
    switch (r.verdict) {
      case PoeVerdict.over:
        if (!r.overBudget) {
          return 'Does not fit. See the port checks above';
        }
        return 'Over budget. Reduce devices or upgrade switch';
      case PoeVerdict.caution:
        return 'Caution: within 20% of budget limit';
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

  static const String _wattsRowNote =
      'Watts rows are budgeted at the PD watts entered, with nothing added '
      'for cable loss. Pick the device\'s class to budget PSE watts.';

  static String _portTypeLabel(PoePortType t) =>
      PoeBudgetScreen.standardFor(t)?.standard ?? 'not set';

  static String _reserveLabel(PoeBudgetResult r) =>
      '${_fmt(r.reservePct, r.reservePct == r.reservePct.roundToDouble() ? 0 : 1)}%'
      ' (${_fmt(r.reserveWatts, 1)} W)';

  static String _portsLabel(PoeBudgetResult r) => r.portsAvailable == null
      ? '${r.portsNeeded} needed (enter the port count to check)'
      : '${r.portsNeeded} needed of ${r.portsAvailable} available'
            '${r.portsShort ? ', ${r.portsNeeded - r.portsAvailable!} short' : ''}';

  /// One line per port-type finding; a single line when everything fits.
  static List<String> _portCheckLines(PoeBudgetResult r) {
    if (r.portType == PoePortType.notSet) {
      return const <String>['PSE type not set, so devices were not checked'];
    }
    if (r.rowProblems.isEmpty) {
      return <String>[
        'every device fits an ${_portTypeLabel(r.portType)} port',
      ];
    }
    return <String>[
      for (final PoeRowProblem p in r.rowProblems)
        'Device ${p.rowNumber}: ${p.message}',
    ];
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
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
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
  static String _verdictWord(PoeBudgetResult r) {
    switch (r.verdict) {
      case PoeVerdict.over:
        return r.overBudget ? 'Over budget' : 'Does not fit';
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

    final StringBuffer b = StringBuffer()
      ..writeln('PoE Budget')
      ..writeln('Switch budget: ${_fmt(r.budget, 0)} W')
      ..writeln('PSE type: ${_portTypeLabel(r.portType)}')
      ..writeln('Reserve: ${_reserveLabel(r)}')
      ..writeln('Total PSE allocation: ${_fmt(r.total, 1)} W')
      ..writeln('Left after reserve: ${_remainingLabel(r.remaining)}')
      ..writeln('Utilization: ${r.pct.toStringAsFixed(0)}% of usable budget')
      ..writeln('Ports: ${_portsLabel(r)}');
    for (final String line in _portCheckLines(r)) {
      b.writeln('Port check: $line');
    }
    if (r.usesWattsRows) b.writeln(_wattsRowNote);
    b
      ..writeln('Verdict: ${_verdictWord(r)}')
      ..writeln(_verdictText(r));
    return b.toString().trimRight();
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
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'PoE ports',
                  semanticLabel: 'Number of PoE ports on the switch',
                  field: _numberField(
                    _portsCtrl,
                    mono,
                    hint: '24',
                    decimal: false,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LabeledField(
                  label: 'Reserve',
                  hint: '(%)',
                  semanticLabel: 'Reserve, percent of the budget held back',
                  field: _numberField(
                    _reserveCtrl,
                    mono,
                    hint: '10',
                    decimal: true,
                    errorText: _reserveInvalid ? '0 to 99.9' : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'PSE type (switch ports)',
            semanticLabel: 'PSE type of the switch ports',
            field: AppSelect<PoePortType>(
              value: _portType,
              semanticLabel: 'PSE type of the switch ports',
              items: const <AppSelectItem<PoePortType>>[
                (PoePortType.notSet, 'Not set'),
                (PoePortType.af, '802.3af (PoE)'),
                (PoePortType.at, '802.3at (PoE+)'),
                (PoePortType.bt3, '802.3bt Type 3'),
                (PoePortType.bt4, '802.3bt Type 4'),
              ],
              onChanged: (PoePortType t) {
                _portType = t;
                _recompute();
              },
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
        Expanded(flex: 3, child: Text('Class or watts', style: style)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(flex: 3, child: Text('Per device', style: style)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(flex: 2, child: Text('Quantity', style: style)),
      ],
    );
  }

  Widget _deviceRow(int i, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final int rowNum = i + 1;
    final int kind = _rowKinds[i];
    final Widget perDevice;
    if (kind == _wattsKind) {
      perDevice = Semantics(
        label: 'Device $rowNum watts per device',
        textField: true,
        child: TextField(
          controller: _wattsCtrls[i],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: _unsignedDecimal,
          onChanged: (_) => _recompute(),
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          style: mono.outputLarge.copyWith(fontSize: AppTextSize.fieldNumeric),
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: 'W (PD)'),
        ),
      );
    } else {
      // A class row is budgeted at its PSE allocation: show that figure, read
      // from the reference table, where the watts field would be.
      final String pse =
          '${_fmt(PoeBudgetScreen.classPseWatts(kind), 1)} W PSE';
      perDevice = Semantics(
        label: 'Device $rowNum budgeted per device',
        value: pse,
        excludeSemantics: true,
        child: Text(
          pse,
          style: mono.inlineCode.copyWith(
            color: colors.textAccent,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: AppSelect<int>(
            value: kind,
            semanticLabel: 'Device $rowNum class or watts',
            items: <AppSelectItem<int>>[
              (_wattsKind, 'Watts'),
              for (int c = 0; c <= 8; c++) (c, 'Class $c'),
            ],
            onChanged: (int k) {
              _rowKinds[i] = k;
              _recompute();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(flex: 3, child: perDevice),
        const SizedBox(width: AppSpacing.xs),
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

  /// A numeric field for the switch inputs (ports, reserve).
  Widget _numberField(
    TextEditingController ctrl,
    AppMonoText mono, {
    required String hint,
    required bool decimal,
    String? errorText,
  }) {
    final AppColorScheme colors = context.colors;
    return TextField(
      controller: ctrl,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: decimal ? _unsignedDecimal : _unsignedInteger,
      onChanged: (_) => _recompute(),
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      style: mono.outputLarge.copyWith(fontSize: AppTextSize.fieldNumeric),
      cursorColor: colors.textAccent,
      decoration: InputDecoration(hintText: hint, errorText: errorText),
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
            // Empty / invalid budget or reserve → blank, no crash.
            Text(
              _reserveInvalid
                  ? 'Enter a reserve from 0 to 99.9% to calculate.'
                  : 'Enter a switch PoE budget to calculate.',
              style: text.bodyMedium?.copyWith(color: colors.textTertiary),
            )
          else ...[
            _utilizationBar(r, text, mono),
            const SizedBox(height: AppSpacing.md),
            _resultRow(
              text,
              mono,
              'Total PSE allocation',
              '${_fmt(r.total, 1)} W',
            ),
            _resultRow(text, mono, 'Switch budget', '${_fmt(r.budget, 0)} W'),
            _resultRow(text, mono, 'Reserve', _reserveLabel(r)),
            _resultRow(
              text,
              mono,
              'Left after reserve',
              _remainingLabel(r.remaining),
              valueColor: r.overBudget
                  ? colors.statusDanger
                  : _verdictColor(
                      PoeBudgetScreen.verdictFor(r.remaining, r.pct),
                      colors,
                    ),
            ),
            _resultRow(
              text,
              mono,
              'Utilization',
              '${r.pct.toStringAsFixed(0)}% of usable',
            ),
            _resultRow(
              text,
              mono,
              'Ports',
              _portsLabel(r),
              valueColor: r.portsShort ? colors.statusDanger : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final String line in _portCheckLines(r))
              _noteLine(
                'Port check: $line',
                text,
                color: r.rowProblems.isEmpty
                    ? colors.textTertiary
                    : colors.statusDanger,
              ),
            if (r.usesWattsRows) _noteLine(_wattsRowNote, text),
            const SizedBox(height: AppSpacing.sm),
            _statusLine(r, text),
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
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // Flexible + right-aligned so a long value ("14 needed of 24
            // available") wraps under itself at phone width instead of
            // overflowing the row.
            Flexible(
              child: SelectableText(
                value,
                textAlign: TextAlign.right,
                style: mono.inlineCode.copyWith(
                  color: valueColor ?? colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A small line of explanation under the result rows.
  Widget _noteLine(String line, TextTheme text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text(
        line,
        style: text.labelSmall?.copyWith(
          color: color ?? context.colors.textTertiary,
        ),
      ),
    );
  }

  /// The §8.13 status verdict — colored word never standing on color alone.
  Widget _statusLine(PoeBudgetResult r, TextTheme text) {
    final AppColorScheme colors = context.colors;
    final Color color = _verdictColor(r.verdict, colors);
    final IconData icon;
    switch (r.verdict) {
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
              _verdictText(r),
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
