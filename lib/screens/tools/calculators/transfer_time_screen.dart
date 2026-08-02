// Transfer Time — how long a transfer takes, how fast a link has to be, or how
// much moves in a window. Three solves over one division.
//
// THE BITS-VERSUS-BYTES TRAP IS THE DESIGN CONSTRAINT, not a footnote. The
// factor of 8 between a link quoted in bits per second and a file quoted in
// bytes is where the wrong answers come from, so this screen makes it hard to
// get wrong by accident and impossible to get wrong silently:
//
//   1. Every unit is picked from a labeled list, never typed. A size unit is a
//      BYTE unit, a rate unit is a BIT unit unless it says B/s, and the lists
//      are the ones the Unit Converter already ships, so there is one
//      definition of a "MB" in the app.
//   2. The bits-and-bytes rule sits ON THE FACE of the form, not in the help
//      sheet.
//   3. The result restates both operands in bits, so the conversion is visible
//      rather than hidden inside the answer.
//   4. Decimal and binary units are both offered and never conflated. The
//      screen names the GB/GiB gap when the size unit is a binary one, because
//      that gap is 6 seconds per gigabyte on a 100 Mbps link.
//
// NO EFFICIENCY SLIDER, on purpose. A default of 85% would be false precision
// dressed as help. The result is the time at exactly the rate entered, and the
// screen says so and tells the user to enter a throughput they measured if
// they want a realistic number.
//
// States (SOP-007 §5):
//  - idle    → the form, seeded with a worked example.
//  - success → the answer, live-recomputed on every keystroke.
//  - error   → a value that is not a number, or a divisor of zero, via the
//              inline error card. Never an infinity and never a NaN.
//  - empty   → an empty field blanks the result rather than showing an error;
//              nothing has been asked yet.
//
// Pure math, no I/O, so it runs on every platform including web.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../data/unit_conversion.dart';
import '../../../services/network/transfer_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import '../network/value_row.dart';

class TransferTimeScreen extends StatefulWidget {
  const TransferTimeScreen({super.key});

  @override
  State<TransferTimeScreen> createState() => _TransferTimeScreenState();
}

class _TransferTimeScreenState extends State<TransferTimeScreen> {
  final TextEditingController _sizeCtrl = TextEditingController(text: '1');
  final TextEditingController _rateCtrl = TextEditingController(text: '100');
  final TextEditingController _timeCtrl = TextEditingController(text: '10');

  // Unit ids, resolved against the shared UnitConversion tables so this screen
  // never carries its own copy of "how many bits in a MB".
  String _sizeUnitId = 'gb';
  String _rateUnitId = 'mbps';
  String _timeUnitId = 'min';

  TransferSolveFor _solveFor = TransferSolveFor.time;

  @override
  void initState() {
    super.initState();
    _sizeCtrl.addListener(_onChanged);
    _rateCtrl.addListener(_onChanged);
    _timeCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _rateCtrl.dispose();
    _timeCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  // ─── Unit helpers ─────────────────────────────────────────────────────────

  /// Storage units, byte-based only. `bit` is dropped from the picker: a file
  /// size in bits is not a thing anyone types, and offering it would blur the
  /// exact distinction this screen exists to keep sharp.
  List<Unit> get _sizeUnits => UnitConversion.dataStorageUnits
      .where((Unit u) => u.id != 'bit')
      .toList(growable: false);

  /// Rate units, minus the Ethernet line-rate presets. Those are useful in a
  /// converter but they turn this picker into a scroll, and a user who wants
  /// 1000BASE-T can type 1000 Mbps.
  List<Unit> get _rateUnits => UnitConversion.dataRateUnits
      .where((Unit u) => !u.id.startsWith('eth'))
      .toList(growable: false);

  List<Unit> get _timeUnits => UnitConversion.timeUnits
      .where((Unit u) => <String>['ms', 's', 'min', 'hr', 'day'].contains(u.id))
      .toList(growable: false);

  Unit _unit(List<Unit> list, String id) =>
      list.firstWhere((Unit u) => u.id == id, orElse: () => list.first);

  /// True when the chosen size unit is a binary (IEC, ×1024) one.
  bool get _sizeIsBinary =>
      const <String>{'kib', 'mib', 'gib', 'tib'}.contains(_sizeUnitId);

  double? _value(TextEditingController c) {
    final String s = c.text.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  // ─── Computation ──────────────────────────────────────────────────────────

  /// The answer, or null when a field is empty (idle), or an error string.
  ({String? answer, String? error, String? operandA, String? operandB})
  _compute() {
    final Unit sizeUnit = _unit(_sizeUnits, _sizeUnitId);
    final Unit rateUnit = _unit(_rateUnits, _rateUnitId);
    final Unit timeUnit = _unit(_timeUnits, _timeUnitId);

    switch (_solveFor) {
      case TransferSolveFor.time:
        final double? sz = _value(_sizeCtrl);
        final double? rt = _value(_rateCtrl);
        if (sz == null || rt == null) {
          return (answer: null, error: null, operandA: null, operandB: null);
        }
        final double bits = sz * sizeUnit.factorToBase;
        final double bps = rt * rateUnit.factorToBase;
        final double? secs = TransferMath.seconds(
          bits: bits,
          bitsPerSecond: bps,
        );
        if (secs == null) {
          return (
            answer: null,
            error: rt <= 0
                ? 'A rate of zero moves nothing, so there is no transfer time '
                      'to give. Enter a rate above zero.'
                : 'Those numbers do not give an answer. Check both fields.',
            operandA: null,
            operandB: null,
          );
        }
        return (
          answer: TransferMath.formatDuration(secs),
          error: null,
          operandA:
              '${_sizeCtrl.text.trim()} ${sizeUnit.symbol} = '
              '${TransferMath.formatBits(bits)}',
          operandB:
              '${_rateCtrl.text.trim()} ${rateUnit.symbol} = '
              '${TransferMath.formatRate(bps)}',
        );

      case TransferSolveFor.rate:
        final double? sz = _value(_sizeCtrl);
        final double? tm = _value(_timeCtrl);
        if (sz == null || tm == null) {
          return (answer: null, error: null, operandA: null, operandB: null);
        }
        final double bits = sz * sizeUnit.factorToBase;
        final double secs = tm * timeUnit.factorToBase;
        final double? bps = TransferMath.bitsPerSecond(
          bits: bits,
          seconds: secs,
        );
        if (bps == null) {
          return (
            answer: null,
            error: secs <= 0
                ? 'A window of zero has no rate that fits it. Enter a time '
                      'above zero.'
                : 'Those numbers do not give an answer. Check both fields.',
            operandA: null,
            operandB: null,
          );
        }
        return (
          answer: '${_asMbps(bps)} (${TransferMath.formatRate(bps)})',
          error: null,
          operandA:
              '${_sizeCtrl.text.trim()} ${sizeUnit.symbol} = '
              '${TransferMath.formatBits(bits)}',
          operandB:
              '${_timeCtrl.text.trim()} ${timeUnit.symbol} = '
              '${TransferMath.formatDuration(secs)}',
        );

      case TransferSolveFor.size:
        final double? rt = _value(_rateCtrl);
        final double? tm = _value(_timeCtrl);
        if (rt == null || tm == null) {
          return (answer: null, error: null, operandA: null, operandB: null);
        }
        final double bps = rt * rateUnit.factorToBase;
        final double secs = tm * timeUnit.factorToBase;
        final double? bits = TransferMath.bits(
          bitsPerSecond: bps,
          seconds: secs,
        );
        if (bits == null) {
          return (
            answer: null,
            error: 'Those numbers do not give an answer. Check both fields.',
            operandA: null,
            operandB: null,
          );
        }
        return (
          answer: '${_asBytes(bits)} (${TransferMath.formatBits(bits)})',
          error: null,
          operandA:
              '${_rateCtrl.text.trim()} ${rateUnit.symbol} = '
              '${TransferMath.formatRate(bps)}',
          operandB:
              '${_timeCtrl.text.trim()} ${timeUnit.symbol} = '
              '${TransferMath.formatDuration(secs)}',
        );
    }
  }

  /// A bit rate in the largest sensible bit-based unit.
  String _asMbps(double bps) {
    if (bps >= 1e9) return '${(bps / 1e9).toStringAsFixed(2)} Gbps';
    if (bps >= 1e6) return '${(bps / 1e6).toStringAsFixed(2)} Mbps';
    if (bps >= 1e3) return '${(bps / 1e3).toStringAsFixed(2)} kbps';
    return '${bps.toStringAsFixed(2)} bps';
  }

  /// A bit count in the largest sensible DECIMAL byte unit. Decimal and not
  /// binary, because the answer would otherwise silently pick a convention the
  /// user did not choose.
  String _asBytes(double bits) {
    final double bytes = bits / 8;
    if (bytes >= 1e12) return '${(bytes / 1e12).toStringAsFixed(2)} TB';
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(2)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(2)} MB';
    if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(2)} KB';
    return '${bytes.toStringAsFixed(0)} B';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Time'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  String? _buildCopyText() {
    final ({String? answer, String? error, String? operandA, String? operandB})
    r = _compute();
    if (r.answer == null) return null;
    final String label = switch (_solveFor) {
      TransferSolveFor.time => 'Transfer time',
      TransferSolveFor.rate => 'Rate needed',
      TransferSolveFor.size => 'Data moved',
    };
    return (StringBuffer()
          ..writeln('Transfer Time')
          ..writeln('$label: ${r.answer}')
          ..writeln(r.operandA)
          ..writeln(r.operandB)
          ..writeln(
            'This is the time at exactly the rate entered. Real transfers run '
            'slower.',
          ))
        .toString()
        .trimRight();
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                    toolId: 'transfer-time',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('transfer-time'))
                    const SizedBox(height: AppSpacing.md),
                  AppToggle<TransferSolveFor>(
                    value: _solveFor,
                    semanticLabel: 'Solve for',
                    expand: true,
                    items: const <AppToggleItem<TransferSolveFor>>[
                      (TransferSolveFor.time, 'Time'),
                      (TransferSolveFor.rate, 'Speed'),
                      (TransferSolveFor.size, 'Size'),
                    ],
                    onChanged: (TransferSolveFor v) =>
                        setState(() => _solveFor = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _formCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(liveRegion: true, child: _resultCard(context)),
                  ToolHelpFooter(toolId: 'transfer-time'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _numberAndUnit(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required List<Unit> units,
    required String unitId,
    required ValueChanged<String> onUnit,
  }) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          flex: 3,
          child: LabeledField(
            label: label,
            field: TextField(
              controller: controller,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '1'),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 2,
          child: LabeledField(
            label: 'Unit',
            semanticLabel: '$label unit',
            field: AppSelect<String>(
              value: unitId,
              semanticLabel: '$label unit',
              items: <AppSelectItem<String>>[
                for (final Unit u in units) (u.id, u.symbol),
              ],
              onChanged: onUnit,
            ),
          ),
        ),
      ],
    );
  }

  Widget _formCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool needsSize = _solveFor != TransferSolveFor.size;
    final bool needsRate = _solveFor != TransferSolveFor.rate;
    final bool needsTime = _solveFor != TransferSolveFor.time;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (needsSize)
            _numberAndUnit(
              context,
              label: 'Size',
              controller: _sizeCtrl,
              units: _sizeUnits,
              unitId: _sizeUnitId,
              onUnit: (String v) => setState(() => _sizeUnitId = v),
            ),
          if (needsSize && (needsRate || needsTime))
            const SizedBox(height: AppSpacing.sm),
          if (needsRate)
            _numberAndUnit(
              context,
              label: 'Speed',
              controller: _rateCtrl,
              units: _rateUnits,
              unitId: _rateUnitId,
              onUnit: (String v) => setState(() => _rateUnitId = v),
            ),
          if (needsRate && needsTime) const SizedBox(height: AppSpacing.sm),
          if (needsTime)
            _numberAndUnit(
              context,
              label: 'Time',
              controller: _timeCtrl,
              units: _timeUnits,
              unitId: _timeUnitId,
              onUnit: (String v) => setState(() => _timeUnitId = v),
            ),
          const SizedBox(height: AppSpacing.sm),
          // §4 of the design intent: this line is ON THE FACE of the tool, not
          // in the help sheet, because it is the thing the tool exists to stop
          // people getting wrong.
          Text(
            'Link speeds are in bits per second. File sizes are in bytes. '
            '1 byte = 8 bits, so a 100 Mbps link moves 12.5 MB per second, not '
            '100.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          if (_sizeIsBinary) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              'You picked a binary unit. A GiB is 1,073,741,824 bytes and a GB '
              'is 1,000,000,000, which is about 7 percent apart. Your operating '
              'system probably says GB and means GiB.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ({String? answer, String? error, String? operandA, String? operandB})
    r = _compute();

    if (r.error != null) {
      return Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.edit_outlined, size: 20, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Check your input',
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.error!,
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (r.answer == null) return const SizedBox.shrink();

    final String label = switch (_solveFor) {
      TransferSolveFor.time => 'Transfer time',
      TransferSolveFor.rate => 'Speed needed',
      TransferSolveFor.size => 'Data moved',
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Result',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueRow(label: label, value: r.answer, mono: true, emphasize: true),
          const SizedBox(height: AppSpacing.xs),
          // Both operands restated in bits: the conversion is shown, not
          // hidden inside the answer.
          Text(
            'In bits',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            r.operandA!,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          Text(
            r.operandB!,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This is the time at exactly the rate you entered. Real transfers '
            'run slower: protocol overhead, disk, and everyone else on the link '
            'all take a share. Enter a throughput you measured rather than the '
            'number on the label if you want a realistic answer.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
