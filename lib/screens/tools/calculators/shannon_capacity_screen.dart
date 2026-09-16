// Shannon-Hartley capacity calculator.
//
// The ceiling every Wi-Fi generation pushes against and none of them breaks:
//   C = B · log2(1 + S/N)
//
// Forward mode answers "what does physics permit on this channel at this SNR".
// Inverse mode answers "what SNR would this target rate demand", which is the
// half that teaches: 1,000 Mbps on one 80 MHz stream needs 37.6 dB, and that
// single number explains why a gigabit demo only works standing under the AP.
//
//   snrLinear  = 10^(snrDb / 10)
//   bitsPerHz  = log2(1 + snrLinear)            per stream
//   capacity   = nss · B(Hz) · bitsPerHz
//
//   bitsNeeded = targetBitsPerSec / (nss · B(Hz))
//   snrDbNeeded = 10·log10(2^bitsNeeded − 1)
//
// THE TRAP THIS TOOL EXISTS NOT TO FALL INTO. Shannon-Hartley as normally
// written is a single-channel AWGN bound; Wi-Fi is MIMO. Compute 80 MHz at
// 25 dB, print ~665 Mbps, and a user compares it against a 4x4 Wi-Fi 6 PHY rate
// near 1,200 Mbps and concludes Wi-Fi beats Shannon. It does not — that rate is
// the sum of parallel spatial streams, each sitting under its own bound. So NSS
// is a first-class input here, not an afterthought, and the per-stream figure is
// shown alongside the total so the multiplication is never hidden.
//
// Edge cases:
// - NEGATIVE SNR IS PHYSICALLY MEANINGFUL AND MUST NOT BLANK. At -3 dB you
//   still get ~0.586 bits/s/Hz. Wi-Fi genuinely operates near and below 0 dB
//   SNR at the bottom MCS rates; blanking it would teach something false.
// - SNR / target empty or non-numeric → blank the outputs (house pattern).
// - Inverse mode, target <= 0 → blank.
// - Inverse mode, an IMPOSSIBLE ask does not error. 10 Gbps on one 20 MHz
//   stream honestly needs 1505.1 dB, and printing it is the point of the tool.
// - Bandwidth and NSS always hold a valid selection, so neither blanks alone.
//
// Pure, no network, no platform APIs. Math lives in static functions on the
// public widget class so tests hit it without pumping a widget.

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

/// Channel bandwidth options in MHz, matching the Noise Floor select so the two
/// tools can be read side by side.
enum ShannonBandwidth {
  bw20(20, '20 MHz'),
  bw40(40, '40 MHz'),
  bw80(80, '80 MHz'),
  bw160(160, '160 MHz'),
  bw320(320, '320 MHz (Wi-Fi 7)');

  const ShannonBandwidth(this.mhz, this.label);

  /// Bandwidth in MHz.
  final int mhz;

  /// Display label for the selector.
  final String label;
}

/// Which direction the screen solves in.
enum ShannonMode {
  /// Capacity from bandwidth and SNR.
  capacity,

  /// The SNR a target capacity would demand.
  requiredSnr,
}

class ShannonCapacityScreen extends StatefulWidget {
  const ShannonCapacityScreen({super.key});

  // ─── Math (pure) ──────────────────────────────────────────────────────────

  /// Default SNR in dB when the field is left untouched.
  static const double defaultSnrDb = 25.0;

  /// Default target capacity in Mbps for inverse mode.
  static const double defaultTargetMbps = 1000.0;

  /// SNR expressed as a linear power ratio: 10^(dB/10).
  ///
  /// Feeding dB straight into the formula is the single most common error with
  /// this equation, which is why the screen shows this conversion.
  static double snrLinear(double snrDb) => math.pow(10, snrDb / 10).toDouble();

  /// Spectral efficiency in bits/s/Hz for ONE spatial stream: log2(1 + S/N).
  ///
  /// Dart has no log2, so this is log(x)/ln2.
  static double spectralEfficiency(double snrDb) {
    return math.log(1 + snrLinear(snrDb)) / math.ln2;
  }

  /// Shannon capacity in Mbps: nss · B(Hz) · log2(1 + S/N), rendered in Mbps.
  static double capacityMbps(double bwMhz, double snrDb, int nss) {
    return nss * bwMhz * spectralEfficiency(snrDb);
  }

  /// Capacity of a SINGLE stream in Mbps — the total divided by [nss], shown so
  /// the MIMO multiplication is visible rather than implied.
  static double perStreamCapacityMbps(double bwMhz, double snrDb) {
    return capacityMbps(bwMhz, snrDb, 1);
  }

  /// Spectral efficiency, in bits/s/Hz per stream, that [targetMbps] demands.
  static double requiredBitsPerHz(double bwMhz, double targetMbps, int nss) {
    return targetMbps / (nss * bwMhz);
  }

  /// The SNR in dB that [targetMbps] demands: 10·log10(2^bitsPerHz − 1).
  ///
  /// Computed so an impossible ask returns an honest number rather than
  /// infinity. Above ~60 bits/s/Hz the `− 1` is far below double precision and
  /// `2^bits` itself overflows to infinity past ~1024, so the identity
  /// `10·log10(2^b) = 10·b·log10(2)` is used there instead. The two agree to
  /// double precision at the crossover, and it is what lets 10 Gbps on one
  /// 20 MHz stream print its true 1505.1 dB.
  static double requiredSnrDb(double bwMhz, double targetMbps, int nss) {
    final double bits = requiredBitsPerHz(bwMhz, targetMbps, nss);
    if (bits > 60) {
      return 10 * bits * (math.log(2) / math.ln10);
    }
    final double linear = math.pow(2, bits).toDouble() - 1;
    if (linear <= 0) return double.negativeInfinity;
    return 10 * (math.log(linear) / math.ln10);
  }

  /// A factual band for a required-SNR figure. Deliberately plain, not cute.
  static String verdictForSnrDb(double snrDb) {
    if (!snrDb.isFinite) return '—';
    if (snrDb < 20) return 'Comfortable. An ordinary link reaches this.';
    if (snrDb < 30) return 'A good link. Reasonable coverage distance.';
    if (snrDb < 40) return 'Close to the AP, on clean spectrum.';
    return 'Not achievable on a real Wi-Fi link.';
  }

  @override
  State<ShannonCapacityScreen> createState() => _ShannonCapacityScreenState();
}

class _ShannonCapacityScreenState extends State<ShannonCapacityScreen> {
  final TextEditingController _snrCtrl = TextEditingController(text: '25');
  final TextEditingController _targetCtrl =
      TextEditingController(text: '1000');

  final FocusNode _snrFocus = FocusNode();
  final FocusNode _targetFocus = FocusNode();

  ShannonBandwidth _bw = ShannonBandwidth.bw80;
  int _nss = 1;
  ShannonMode _mode = ShannonMode.capacity;

  // Forward outputs, null when the input is blank or invalid.
  double? _capacityMbps;
  double? _perStreamMbps;
  double? _bitsPerHz;
  double? _snrLinear;

  // Inverse outputs.
  double? _requiredSnrDb;
  double? _requiredBitsPerHz;

  // Field-level message for the target field. Null for an empty field, which
  // legitimately blanks the outputs; set when a value is present but unusable.
  String? _targetError;

  // SNR is SIGNED: negative SNR is legal here and must compute. The target
  // capacity is unsigned — a negative rate has no meaning.
  static final List<TextInputFormatter> _signedDecimal = signedDecimalFormatters;
  static final List<TextInputFormatter> _unsignedDecimal =
      unsignedDecimalFormatters;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _snrCtrl.dispose();
    _targetCtrl.dispose();
    _snrFocus.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  // ─── Handlers ─────────────────────────────────────────────────────────────

  void _recompute() {
    final double bwMhz = _bw.mhz.toDouble();

    if (_mode == ShannonMode.capacity) {
      final double? snr = tryParseFlexibleDouble(_snrCtrl.text);
      // NOTE: no lower bound. Negative SNR is a real operating point.
      setState(() {
        _targetError = null;
        if (snr == null) {
          _capacityMbps = null;
          _perStreamMbps = null;
          _bitsPerHz = null;
          _snrLinear = null;
          return;
        }
        _capacityMbps = ShannonCapacityScreen.capacityMbps(bwMhz, snr, _nss);
        _perStreamMbps =
            ShannonCapacityScreen.perStreamCapacityMbps(bwMhz, snr);
        _bitsPerHz = ShannonCapacityScreen.spectralEfficiency(snr);
        _snrLinear = ShannonCapacityScreen.snrLinear(snr);
      });
      return;
    }

    final String raw = _targetCtrl.text.trim();
    final double? target = tryParseFlexibleDouble(_targetCtrl.text);
    setState(() {
      if (target == null || target <= 0) {
        _requiredSnrDb = null;
        _requiredBitsPerHz = null;
        _targetError =
            raw.isEmpty ? null : 'Target capacity must be greater than zero.';
        return;
      }
      _targetError = null;
      // An impossible ask is NOT an error. It computes, and it prints.
      _requiredSnrDb =
          ShannonCapacityScreen.requiredSnrDb(bwMhz, target, _nss);
      _requiredBitsPerHz =
          ShannonCapacityScreen.requiredBitsPerHz(bwMhz, target, _nss);
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  static String _fmt(double? value, int decimals) {
    if (value == null || !value.isFinite) return '—';
    return value.toStringAsFixed(decimals);
  }

  /// The linear ratio spans many orders of magnitude, so it switches to
  /// scientific notation rather than printing a wall of digits.
  static String _fmtLinear(double? value) {
    if (value == null || !value.isFinite) return '—';
    if (value >= 100000 || (value > 0 && value < 0.01)) {
      return value.toStringAsExponential(2);
    }
    return value.toStringAsFixed(value < 10 ? 3 : 1);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shannon Capacity'),
        toolbarHeight: 64,
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
                      ConceptGraphicBand(
                        toolId: 'shannon-capacity',
                        isDesktop: isDesktop,
                      ),
                      if (ToolAssets.hasGraphic('shannon-capacity'))
                        const SizedBox(height: AppSpacing.md),
                      _inputCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _formulaCard(text, mono),
                      const SizedBox(height: AppSpacing.md),
                      _referenceCard(text, mono),
                      ToolHelpFooter(toolId: 'shannon-capacity'),
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

  /// §8.16 copy payload. Returns null (→ disabled affordance) whenever the
  /// outputs are blank, and reflects the mode actually on screen.
  String? _buildCopyText() {
    final StringBuffer b = StringBuffer()..writeln('Shannon Capacity');
    if (_mode == ShannonMode.capacity) {
      final double? c = _capacityMbps;
      if (c == null || !c.isFinite) return null;
      b
        ..writeln('Channel bandwidth: ${_bw.mhz} MHz')
        ..writeln('SNR: ${_snrCtrl.text.trim()} dB')
        ..writeln('Spatial streams (NSS): $_nss')
        ..writeln('Shannon capacity: ${_fmt(c, 1)} Mbps');
      if (_nss > 1) {
        b.writeln('Per stream: ${_fmt(_perStreamMbps, 1)} Mbps');
      }
      b
        ..writeln('Spectral efficiency: ${_fmt(_bitsPerHz, 2)} bits/s/Hz')
        ..writeln('SNR as a linear ratio: ${_fmtLinear(_snrLinear)}');
      return b.toString().trimRight();
    }

    final double? db = _requiredSnrDb;
    if (db == null || !db.isFinite) return null;
    b
      ..writeln('Channel bandwidth: ${_bw.mhz} MHz')
      ..writeln('Target capacity: ${_targetCtrl.text.trim()} Mbps')
      ..writeln('Spatial streams (NSS): $_nss')
      ..writeln('Required SNR: ${_fmt(db, 1)} dB')
      ..writeln(
        'Required spectral efficiency: ${_fmt(_requiredBitsPerHz, 2)} bits/s/Hz',
      )
      ..writeln(ShannonCapacityScreen.verdictForSnrDb(db));
    return b.toString().trimRight();
  }

  Widget _inputCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool forward = _mode == ShannonMode.capacity;
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
          // Two short options → segmented control, not a Select (§8.14).
          Semantics(
            label: 'Solve for',
            child: SegmentedButton<ShannonMode>(
              segments: const <ButtonSegment<ShannonMode>>[
                ButtonSegment<ShannonMode>(
                  value: ShannonMode.capacity,
                  label: Text('Capacity'),
                ),
                ButtonSegment<ShannonMode>(
                  value: ShannonMode.requiredSnr,
                  label: Text('Required SNR'),
                ),
              ],
              selected: <ShannonMode>{_mode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<ShannonMode> s) {
                setState(() => _mode = s.first);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LabeledField(
            label: 'Channel bandwidth',
            hint: '(MHz)',
            semanticLabel: 'Channel bandwidth in MHz',
            field: AppSelect<ShannonBandwidth>(
              value: _bw,
              semanticLabel: 'Channel bandwidth',
              items: ShannonBandwidth.values
                  .map((b) => (b, b.label))
                  .toList(growable: false),
              onChanged: (b) {
                setState(() => _bw = b);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (forward)
            LabeledField(
              label: 'Signal-to-noise ratio',
              hint: '(dB)',
              semanticLabel: 'Signal to noise ratio in dB',
              field: TextField(
                controller: _snrCtrl,
                focusNode: _snrFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: _signedDecimal,
                onChanged: (_) => _recompute(),
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                style: mono.outputLarge.copyWith(
                  fontSize: AppTextSize.fieldNumeric,
                ),
                cursorColor: colors.textAccent,
                decoration: const InputDecoration(hintText: '25'),
              ),
            )
          else
            LabeledField(
              label: 'Target capacity',
              hint: '(Mbps)',
              semanticLabel: 'Target capacity in Mbps',
              field: TextField(
                controller: _targetCtrl,
                focusNode: _targetFocus,
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
                decoration: InputDecoration(
                  hintText: '1000',
                  errorText: _targetError,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Spatial streams (NSS)',
            hint: '',
            semanticLabel: 'Spatial streams',
            field: AppSelect<int>(
              value: _nss,
              semanticLabel: 'Spatial streams',
              items: List<AppSelectItem<int>>.generate(
                8,
                (i) => (i + 1, '${i + 1}'),
                growable: false,
              ),
              onChanged: (n) {
                setState(() => _nss = n);
                _recompute();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (forward) ...[
            _resultRow(
              text,
              mono,
              label: 'Shannon capacity',
              value: _fmt(_capacityMbps, 1),
              unit: 'Mbps',
              primary: true,
            ),
            if (_nss > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              _resultRow(
                text,
                mono,
                label: 'Per stream',
                value: _fmt(_perStreamMbps, 1),
                unit: 'Mbps',
                primary: false,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            _resultRow(
              text,
              mono,
              label: 'Spectral efficiency',
              value: _fmt(_bitsPerHz, 2),
              unit: 'bits/s/Hz',
              primary: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            _resultRow(
              text,
              mono,
              label: 'SNR as a linear ratio',
              value: _fmtLinear(_snrLinear),
              unit: '',
              primary: false,
            ),
          ] else ...[
            _resultRow(
              text,
              mono,
              label: 'Required SNR',
              value: _fmt(_requiredSnrDb, 1),
              unit: 'dB',
              primary: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            _resultRow(
              text,
              mono,
              label: 'Required spectral efficiency',
              value: _fmt(_requiredBitsPerHz, 2),
              unit: 'bits/s/Hz',
              primary: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _requiredSnrDb == null
                  ? '—'
                  : ShannonCapacityScreen.verdictForSnrDb(_requiredSnrDb!),
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(
    TextTheme text,
    AppMonoText mono, {
    required String label,
    required String value,
    required String unit,
    required bool primary,
  }) {
    final AppColorScheme colors = context.colors;
    final bool blank = value == '—';
    // One SR node per result, not value/unit/label as separate fragments.
    return Semantics(
      label: label,
      value: blank
          ? 'not calculated'
          : (unit.isEmpty ? value : '$value $unit'),
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
              Flexible(
                child: SelectableText(
                  value,
                  style: (primary ? mono.outputXL : mono.outputLarge).copyWith(
                    color: blank
                        ? colors.textTertiary
                        : (primary ? colors.textAccent : colors.textPrimary),
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  unit,
                  style: text.labelLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
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
            // log2 stays ASCII (the subscript glyph is absent from Roboto Mono).
            'C = NSS × B × log2(1 + S/N)',
            style: mono.robotoMono.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'B is the channel bandwidth in Hz and S/N is the signal-to-noise '
            'ratio as a LINEAR power ratio, not dB: 25 dB is 316, not 25. '
            'Shannon-Hartley bounds one channel, so a MIMO link gets one bound '
            'per spatial stream and NSS multiplies the total. The PHY rate a '
            'radio advertises is the sum of those streams, which is why it can '
            'exceed the single-stream figure without breaking anything.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _referenceCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    // Single-stream capacity at each bandwidth for a good 25 dB link, computed
    // from the same functions this screen uses.
    final List<List<String>> refs = <List<String>>[
      for (final ShannonBandwidth b in ShannonBandwidth.values)
        <String>[
          '${b.mhz} MHz',
          '${ShannonCapacityScreen.capacityMbps(b.mhz.toDouble(), 25, 1).toStringAsFixed(0)} Mbps',
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
            'One stream at 25 dB SNR',
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
                  SizedBox(
                    width: 96,
                    child: Text(
                      row[0],
                      style: mono.inlineCode.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
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
