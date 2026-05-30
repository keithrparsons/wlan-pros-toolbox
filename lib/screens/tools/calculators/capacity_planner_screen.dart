// Wi-Fi Capacity Planner calculator.
//
// Estimates how many access points a deployment needs from a capacity-first
// model: concurrent users → aggregate throughput demand → APs to serve it,
// cross-checked against an optional per-AP client-count ceiling.
//
// Formula matches the RF Tools PWA reference (app.js calcCapacity, line 1305):
//   concurrent  = ceil(users * conc% / 100)
//   totalBW     = concurrent * perUser            (Mbps)
//   effectiveAP = apMax * util% / 100             (usable Mbps per AP)
//   apsByTput   = ceil(totalBW / effectiveAP)
//   apsByDens   = (maxCli > 0) ? ceil(concurrent / maxCli) : 0
//   recommended = max(apsByTput, apsByDens, 1)
//
// Inputs are plain counts / Mbps / percentages — no unit selectors. Five fields
// are required (users, conc%, perUser, apMax, util%); max clients/AP is optional
// and only contributes the density check when present. Output rounding mirrors
// the PWA: integer AP counts, totalBW with fmt(...,0).
//
// Edge cases (mirror the PWA guards):
// - Any required field empty / non-positive → all outputs blank (no crash).
// - Optional max-clients empty or <= 0 → density row shows the dash, recommended
//   falls back to the throughput count.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget so it is unit-testable against the PWA values.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../labeled_field.dart';

/// Result of a capacity computation. Null is used at the call site when any
/// required input is missing or non-positive, so this struct is always fully
/// populated when present.
class CapacityResult {
  const CapacityResult({
    required this.concurrent,
    required this.totalBwMbps,
    required this.apsByThroughput,
    required this.apsByDensity,
    required this.recommended,
  });

  /// ceil(users * conc% / 100).
  final int concurrent;

  /// concurrent * perUser, in Mbps.
  final double totalBwMbps;

  /// APs needed to serve the aggregate throughput.
  final int apsByThroughput;

  /// APs needed for the client-count ceiling, or 0 when no ceiling was given.
  final int apsByDensity;

  /// max(apsByThroughput, apsByDensity, 1).
  final int recommended;
}

class CapacityPlannerScreen extends StatefulWidget {
  const CapacityPlannerScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────
  // Mirrors app.js calcCapacity.

  /// Compute the capacity plan. Returns null when any required input is missing
  /// or non-positive (matches the PWA showError early-returns). [maxClients] is
  /// optional: null or <= 0 disables the density check (PWA apsByDens = 0).
  static CapacityResult? compute({
    required double? users,
    required double? concurrentPct,
    required double? perUserMbps,
    required double? apMaxMbps,
    required double? targetUtilPct,
    double? maxClients,
  }) {
    if (users == null || users <= 0) return null;
    if (concurrentPct == null || concurrentPct <= 0) return null;
    if (perUserMbps == null || perUserMbps <= 0) return null;
    if (apMaxMbps == null || apMaxMbps <= 0) return null;
    if (targetUtilPct == null || targetUtilPct <= 0) return null;

    final int concurrent = (users * (concurrentPct / 100)).ceil();
    final double totalBw = concurrent * perUserMbps;
    final double effectiveAp = apMaxMbps * (targetUtilPct / 100);
    final int apsByTput = (totalBw / effectiveAp).ceil();
    final int apsByDens = (maxClients != null && maxClients > 0)
        ? (concurrent / maxClients).ceil()
        : 0;
    final int recommended = math.max(math.max(apsByTput, apsByDens), 1);

    return CapacityResult(
      concurrent: concurrent,
      totalBwMbps: totalBw,
      apsByThroughput: apsByTput,
      apsByDensity: apsByDens,
      recommended: recommended,
    );
  }

  @override
  State<CapacityPlannerScreen> createState() => _CapacityPlannerScreenState();
}

class _CapacityPlannerScreenState extends State<CapacityPlannerScreen> {
  final TextEditingController _usersCtrl = TextEditingController();
  final TextEditingController _concCtrl = TextEditingController();
  final TextEditingController _perUserCtrl = TextEditingController();
  final TextEditingController _apMaxCtrl = TextEditingController();
  final TextEditingController _utilCtrl = TextEditingController();
  final TextEditingController _maxCliCtrl = TextEditingController();

  final FocusNode _usersFocus = FocusNode();
  final FocusNode _concFocus = FocusNode();
  final FocusNode _perUserFocus = FocusNode();
  final FocusNode _apMaxFocus = FocusNode();
  final FocusNode _utilFocus = FocusNode();
  final FocusNode _maxCliFocus = FocusNode();

  // Computed plan, or null while required input is incomplete / invalid.
  CapacityResult? _result;

  // Unsigned-decimal only. Counts, percentages, and Mbps are all positive
  // hand-typed values — no sign, no scientific notation.
  static final List<TextInputFormatter> _unsignedDecimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
  ];

  @override
  void dispose() {
    _usersCtrl.dispose();
    _concCtrl.dispose();
    _perUserCtrl.dispose();
    _apMaxCtrl.dispose();
    _utilCtrl.dispose();
    _maxCliCtrl.dispose();
    _usersFocus.dispose();
    _concFocus.dispose();
    _perUserFocus.dispose();
    _apMaxFocus.dispose();
    _utilFocus.dispose();
    _maxCliFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    setState(() {
      _result = CapacityPlannerScreen.compute(
        users: _tryParseDouble(_usersCtrl.text),
        concurrentPct: _tryParseDouble(_concCtrl.text),
        perUserMbps: _tryParseDouble(_perUserCtrl.text),
        apMaxMbps: _tryParseDouble(_apMaxCtrl.text),
        targetUtilPct: _tryParseDouble(_utilCtrl.text),
        maxClients: _tryParseDouble(_maxCliCtrl.text),
      );
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static double? _tryParseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capacity Planner'),
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
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _resultsCard(text, mono),
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
          _inputField(
            label: 'Total users',
            unitHint: 'count',
            controller: _usersCtrl,
            focusNode: _usersFocus,
            hintText: '200',
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputField(
            label: 'Concurrent usage',
            unitHint: '%',
            controller: _concCtrl,
            focusNode: _concFocus,
            hintText: '70',
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputField(
            label: 'Per-user throughput',
            unitHint: 'Mbps',
            controller: _perUserCtrl,
            focusNode: _perUserFocus,
            hintText: '5',
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputField(
            label: 'AP max throughput',
            unitHint: 'Mbps',
            controller: _apMaxCtrl,
            focusNode: _apMaxFocus,
            hintText: '600',
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputField(
            label: 'Target channel utilization',
            unitHint: '%',
            controller: _utilCtrl,
            focusNode: _utilFocus,
            hintText: '50',
            monoStyle: mono.outputLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          _inputField(
            label: 'Max clients per AP',
            unitHint: 'optional',
            controller: _maxCliCtrl,
            focusNode: _maxCliFocus,
            hintText: '50',
            monoStyle: mono.outputLarge,
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required String label,
    required String unitHint,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required TextStyle monoStyle,
  }) {
    return LabeledField(
      label: label,
      hint: '($unitHint)',
      semanticLabel: '$label in $unitHint',
      field: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _unsignedDecimal,
        onChanged: (_) => _recompute(),
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        style: monoStyle.copyWith(fontSize: 20),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(hintText: hintText),
      ),
    );
  }

  Widget _resultsCard(TextTheme text, AppMonoText mono) {
    final CapacityResult? r = _result;

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
          // Headline output — the recommended AP count.
          Text(
            'Recommended access points',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SelectableText(
                r == null ? '—' : r.recommended.toString(),
                style: mono.outputXL.copyWith(
                  color: r == null
                      ? AppColors.textTertiary
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'APs',
                style: text.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Supporting outputs.
          _outputRow(
            mono,
            'Concurrent users',
            r == null ? '—' : r.concurrent.toString(),
          ),
          _outputRow(
            mono,
            'Aggregate demand',
            r == null ? '—' : '${_formatInt(r.totalBwMbps)} Mbps',
          ),
          _outputRow(
            mono,
            'APs by throughput',
            r == null ? '—' : r.apsByThroughput.toString(),
          ),
          _outputRow(
            mono,
            'APs by density',
            r == null || r.apsByDensity <= 0
                ? '—'
                : r.apsByDensity.toString(),
          ),
        ],
      ),
    );
  }

  Widget _outputRow(AppMonoText mono, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: mono.inlineCode.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SelectableText(
            value,
            style: mono.inlineCode.copyWith(
              color: value == '—'
                  ? AppColors.textTertiary
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // PWA fmt(totalBW, 0): fixed 0-decimal integer string.
  static String _formatInt(double n) {
    if (!n.isFinite) return '—';
    return n.toStringAsFixed(0);
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
            'concurrent = ⌈users · conc% ⌉\n'
            'demand = concurrent · per-user (Mbps)\n'
            'usable/AP = AP max · util%\n'
            'APs = ⌈demand / usable⌉, density = ⌈concurrent / max-clients⌉\n'
            'recommended = max(throughput, density, 1)',
            style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Capacity-first model. AP counts round up. Max clients per AP is '
            'optional and only adds the density floor when set.',
            style: text.labelMedium?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    // Typical planning anchors so a field tech can sanity-check inputs.
    final List<List<String>> refs = const [
      ['Concurrent', 'office', '60–80%'],
      ['Concurrent', 'classroom', '90–100%'],
      ['Per-user', 'web/email', '1–2 Mbps'],
      ['Per-user', 'video call', '4–8 Mbps'],
      ['Util target', 'design max', '50%'],
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
            'Planning anchors',
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
                  // Column widths snap to the 8px base unit (GL-003 §4).
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textSecondary,
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
