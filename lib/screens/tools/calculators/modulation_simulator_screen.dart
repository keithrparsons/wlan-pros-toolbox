// Modulation Simulator: Wi-Fi Lab tool (modulation-simulator).
//
// Shows how bits become a radio wave. A group of k bits picks one point on the
// I/Q plane; that point sets the carrier's amplitude and phase for one symbol.
// Higher orders carry more bits per symbol, pack points closer, and need a
// cleaner signal to decode.
//
// CLEAN-ROOM BUILD (2026-09-25) from the IEEE 802.11 constellation math and
// textbook AWGN, per myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 01-modulation-simulator.md. All math lives in ModulationMath
// (lib/services/rf/modulation_math.dart); this file is the view.
//
// This is NOT the 'modulation' reference-card tool, which is untouched.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Numerics in DM
// Mono (AppMonoText). Lime (textAccent) marks the measured quantity (received
// points, the bold carrier); status hues appear only on computed verdicts
// (a wrong decision, meets / misses the transmit EVM limit), always paired
// with a word or glyph (§8.13 rules 2 and 6). No new tokens. ASCII copy, no
// em dashes (GL-004).
//
// MOTION (§8.8): the simulator always opens PAUSED, so nothing moves until the
// user asks. Play advances whole symbols on a timer (discrete redraws, no
// tweened transitions); Step sends exactly one. With reduced motion on, a note
// says so and Step is the suggested path; Play still works because the user
// starts it.
//
// States (SOP-007 §5):
//   - empty       -> nothing sent yet: plots show ideal points only, with a
//                    prompt; EVM and error readouts say "send symbols first"
//   - running     -> Play: one symbol per tick at the chosen speed
//   - paused      -> default; Step and +100 work
//   - error       -> text source with an empty message: transport disabled,
//                    inline prompt to type something or switch to random
//   - disabled    -> Step / Play / +100 disabled in the error state; Reset
//                    disabled when there is nothing to clear
//   - interactive -> every control is a themed Material control with the
//                    global focus ring; plots are labelled for screen readers

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';
import 'modulation_simulator_painters.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kModulationSimulatorToolId = 'modulation-simulator';

/// Where the bits come from.
enum BitSource { random, text }

/// Playback speed in symbols per second.
enum SimSpeed {
  slow(1, '1/s'),
  medium(4, '4/s'),
  fast(20, '20/s');

  const SimSpeed(this.symbolsPerSecond, this.label);
  final int symbolsPerSecond;
  final String label;
}

/// Orders up to this many points get a bit label on every point; above it,
/// labels appear on tap or hover only (spec §Screen 2).
const int _kLabelEveryPointMax = 16;

/// Received points kept for the cloud. Enough for 4096-QAM to show a spread,
/// small enough to repaint every tick.
const int _kCloudCap = 2000;

/// Carrier cycles drawn per symbol (spec: 3 is a good visual choice).
const int _kCyclesPerSymbol = 3;

/// Symbols sent by the +100 button.
const int _kBurst = 100;

/// Longest message accepted in text mode.
const int _kMaxTextLength = 120;

class ModulationSimulatorScreen extends StatefulWidget {
  const ModulationSimulatorScreen({super.key, this.seed});

  /// Test seam: a fixed RNG seed makes a run reproducible.
  final int? seed;

  @override
  State<ModulationSimulatorScreen> createState() =>
      _ModulationSimulatorScreenState();
}

class _ModulationSimulatorScreenState extends State<ModulationSimulatorScreen>
    with WidgetsBindingObserver {
  late final math.Random _rng;

  Modulation _mod = Modulation.qam16;
  double _snrDb = 25;
  BitSource _source = BitSource.random;
  SimSpeed _speed = SimSpeed.medium;
  final TextEditingController _textCtrl = TextEditingController(
    text: 'Hello, Wi-Fi',
  );

  bool _playing = false;
  Timer? _timer;

  // Accumulated since the last reset.
  final List<SimulatedSymbol> _history = <SimulatedSymbol>[];
  int _sent = 0;
  int _symbolErrors = 0;
  int _bitErrors = 0;
  int _bitsSent = 0;
  double _sumErrorSq = 0;
  int _revision = 0;

  // Text-mode progress through the message.
  int _textPos = 0;
  final List<int> _rxSymbols = <int>[];
  String? _lastFullRx;
  int _passes = 0;

  // Tap / hover probe for dense constellations.
  ConstellationPoint? _probe;

  @override
  void initState() {
    super.initState();
    _rng = math.Random(widget.seed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) _pause();
  }

  // ── Derived ─────────────────────────────────────────────────────────────

  SymbolFrame get _frame => ModulationMath.groupBits(
    ModulationMath.textToBits(_textCtrl.text),
    _mod.bitsPerSymbol,
  );

  int get _messageBits => ModulationMath.textToBits(_textCtrl.text).length;

  bool get _canSend => _source == BitSource.random || _textCtrl.text.isNotEmpty;

  SimulatedSymbol? get _current => _history.isEmpty ? null : _history.last;

  double get _theoryEvmDb =>
      ModulationMath.evmToDb(ModulationMath.theoreticalEvmRms(_snrDb));

  double? get _measuredEvmDb => _sent == 0
      ? null
      : ModulationMath.evmToDb(
          ModulationMath.measuredEvmRms(_sumErrorSq, _sent),
        );

  // ── Simulation ──────────────────────────────────────────────────────────

  /// Sends one symbol. Mutates state; the caller wraps it in setState.
  void _sendOne() {
    final int symbol;
    SymbolFrame? frame;
    if (_source == BitSource.random) {
      symbol = ModulationMath.randomSymbol(_mod, _rng);
    } else {
      frame = _frame;
      if (frame.symbols.isEmpty) return;
      if (_textPos >= frame.symbols.length) _textPos = 0;
      symbol = frame.symbols[_textPos];
    }
    final SimulatedSymbol s = ModulationMath.transmit(
      _mod,
      symbol,
      _snrDb,
      _rng,
    );
    _history.add(s);
    if (_history.length > _kCloudCap) _history.removeAt(0);
    _sent++;
    _bitsSent += _mod.bitsPerSymbol;
    _sumErrorSq += s.errorVectorSquared;
    if (s.isSymbolError) _symbolErrors++;
    _bitErrors += s.bitErrors;
    _revision++;

    if (frame != null) {
      _rxSymbols.add(s.decided.symbol);
      _textPos++;
      if (_textPos >= frame.symbols.length) {
        _lastFullRx = _decodeRx();
        _passes++;
        _rxSymbols.clear();
        _textPos = 0;
      }
    }
  }

  /// Text decoded from the symbols received so far in this pass, with the
  /// zero padding dropped.
  String _decodeRx() {
    final List<int> bits = ModulationMath.symbolsToBits(
      _rxSymbols,
      _mod.bitsPerSymbol,
    );
    final int keep = math.min(bits.length, _messageBits);
    return ModulationMath.bitsToText(bits.sublist(0, keep));
  }

  void _step() {
    if (!_canSend) return;
    setState(_sendOne);
  }

  void _burst() {
    if (!_canSend) return;
    setState(() {
      for (int n = 0; n < _kBurst; n++) {
        _sendOne();
      }
    });
  }

  void _play() {
    if (!_canSend) return;
    _timer?.cancel();
    final int ms = (1000 / _speed.symbolsPerSecond).round();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted || !_canSend) {
        _pause();
        return;
      }
      setState(_sendOne);
    });
    setState(() => _playing = true);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _playing = false);
  }

  void _togglePlay() => _playing ? _pause() : _play();

  /// Clears every accumulated count. Called when anything that would make the
  /// old cloud misleading changes (modulation, SNR, bit source, message).
  void _resetStats() {
    _history.clear();
    _sent = 0;
    _symbolErrors = 0;
    _bitErrors = 0;
    _bitsSent = 0;
    _sumErrorSq = 0;
    _textPos = 0;
    _rxSymbols.clear();
    _lastFullRx = null;
    _passes = 0;
    _probe = null;
    _revision++;
  }

  void _onModulation(Modulation m) => setState(() {
    _mod = m;
    _resetStats();
  });

  void _onSnr(double v) => setState(() {
    _snrDb = v;
    _resetStats();
  });

  void _onSource(BitSource s) {
    setState(() {
      _source = s;
      _resetStats();
    });
    if (_playing && !_canSend) _pause();
  }

  void _onSpeed(SimSpeed s) {
    setState(() => _speed = s);
    if (_playing) _play();
  }

  void _onText(String _) {
    setState(_resetStats);
    if (_playing && !_canSend) _pause();
  }

  void _probeAt(Offset local, Size size) {
    final ({double i, double q}) iq = ConstellationPainter.toIq(
      local,
      size,
      _mod,
    );
    final ConstellationPoint p = ModulationMath.decide(_mod, iq.i, iq.q);
    if (p.symbol != _probe?.symbol) setState(() => _probe = p);
  }

  // ── Formatting ──────────────────────────────────────────────────────────

  static String _db(double v) {
    if (!v.isFinite) return '-';
    final String s = v.toStringAsFixed(1);
    return s == '-0.0' ? '0.0' : s;
  }

  static String _pct(double evmDb) {
    final double ratio = math.pow(10, evmDb / 20).toDouble();
    final double p = ratio * 100;
    return p >= 10 ? p.toStringAsFixed(1) : p.toStringAsFixed(2);
  }

  static String _signed(int v) => v > 0 ? '+$v' : '$v';

  static String _signedD(double v, int decimals) {
    final String s = v.toStringAsFixed(decimals);
    if (s.startsWith('-')) {
      final bool allZero = RegExp(r'^-0\.?0*$').hasMatch(s);
      return allZero ? s.substring(1) : s;
    }
    return '+$s';
  }

  String _kModText() {
    switch (_mod) {
      case Modulation.bpsk:
        return '1';
      case Modulation.qpsk:
        return '1/sqrt(2) = ${ModulationMath.kMod(_mod).toStringAsFixed(4)}';
      default:
        final int d = (2 * (_mod.points - 1)) ~/ 3;
        return '1/sqrt($d) = ${ModulationMath.kMod(_mod).toStringAsFixed(4)}';
    }
  }

  String _levelsText() {
    final int l = _mod.levelsPerAxis;
    final String range = l == 2
        ? '+/-1'
        : '+/-1, +/-3${l > 4 ? ' ... +/-${l - 1}' : ''}';
    if (_mod.isBpsk) return '2 on I ($range); Q unused';
    return '$l on I, $l on Q ($range)';
  }

  String _bitsSplit(int symbol) {
    final String b = ModulationMath.bitString(symbol, _mod.bitsPerSymbol);
    if (_mod.isBpsk) return b;
    final int h = _mod.bitsPerAxis;
    return '${b.substring(0, h)} ${b.substring(h)}';
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String? _buildCopyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('Modulation Simulator')
      ..writeln(
        '${_mod.label}: ${_mod.bitsPerSymbol} bits/symbol, '
        '${_mod.points} points',
      )
      ..writeln('SNR: ${_db(_snrDb)} dB')
      ..writeln('Theoretical EVM: ${_db(_theoryEvmDb)} dB');
    final double? m = _measuredEvmDb;
    if (m != null) {
      b
        ..writeln('Measured EVM: ${_db(m)} dB over $_sent symbols')
        ..writeln('Symbol errors: $_symbolErrors of $_sent')
        ..writeln('Bit errors: $_bitErrors of $_bitsSent');
    }
    for (final EvmRequirement r in ModulationMath.requiredEvm(_mod)) {
      final bool ok = ModulationMath.meetsRequirement(
        _theoryEvmDb,
        r.requiredDb,
      );
      b.writeln(
        'Transmit EVM limit, rate ${r.codingRates}: '
        '${_db(r.requiredDb)} dB (${ok ? 'meets' : 'misses'})',
      );
    }
    b.writeln(
      'Transmit EVM limits are transmitter accuracy, not receiver '
      'sensitivity.',
    );
    return b.toString().trimRight();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modulation Simulator'),
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
                      _modulationCard(text, mono),
                      const SizedBox(height: AppSpacing.sm),
                      _constellationCard(text, mono),
                      const SizedBox(height: AppSpacing.sm),
                      _waveformCard(text, mono),
                      const SizedBox(height: AppSpacing.sm),
                      _controlsCard(text, mono, reduceMotion),
                      const SizedBox(height: AppSpacing.sm),
                      _readoutsCard(text, mono),
                      const SizedBox(height: AppSpacing.sm),
                      _evmCard(text, mono),
                      const SizedBox(height: AppSpacing.sm),
                      _explainerCard(text),
                      ToolHelpFooter(toolId: kModulationSimulatorToolId),
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

  // ── Modulation selector ─────────────────────────────────────────────────

  Widget _modulationCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Seven options: GL-003 §8.14 routes 4+ options to AppSelect, not
          // a segmented toggle (which never wraps and caps at 3).
          LabeledField(
            label: 'Modulation',
            semanticLabel: 'Modulation',
            field: AppSelect<Modulation>(
              value: _mod,
              semanticLabel: 'Modulation',
              items: <AppSelectItem<Modulation>>[
                for (final Modulation m in Modulation.values)
                  (
                    m,
                    '${m.label} (${m.bitsPerSymbol} '
                        'bit${m.bitsPerSymbol == 1 ? '' : 's'} per symbol)',
                  ),
              ],
              onChanged: _onModulation,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_mod.points} points, ${_mod.bitsPerSymbol} '
            'bit${_mod.bitsPerSymbol == 1 ? '' : 's'} per symbol. '
            'First used in ${_mod.firstUsed}.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── Constellation ───────────────────────────────────────────────────────

  Widget _constellationCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final bool labelAll = _mod.points <= _kLabelEveryPointMax;
    final SimulatedSymbol? cur = _current;
    final ConstellationStyle style = ConstellationStyle(
      ideal: colors.textSecondary,
      received: colors.textAccent,
      error: colors.statusDanger,
      boundary: colors.border,
      axis: colors.borderStrong,
      highlight: colors.textPrimary,
      labelStyle: mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textSecondary,
      ),
      axisLabelStyle: text.labelMedium!.copyWith(color: colors.textTertiary),
    );

    final String semantic =
        'Constellation for ${_mod.label}: ${_mod.points} ideal points. '
        '${_sent == 0 ? 'No symbols sent yet.' : '$_sent received points, $_symbolErrors decided wrong.'}'
        '${cur == null ? '' : ' Current symbol ${ModulationMath.bitString(cur.sent.symbol, _mod.bitsPerSymbol)}, ${cur.isSymbolError ? 'decided wrong' : 'decided correctly'}.'}';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionLabel(text, 'Constellation (I/Q plane)'),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AspectRatio(
                aspectRatio: 1,
                child: Semantics(
                  label: semantic,
                  excludeSemantics: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Container(
                      color: colors.surface2,
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints c) {
                          final Size size = Size(c.maxWidth, c.maxHeight);
                          final Widget paint = CustomPaint(
                            size: size,
                            painter: ConstellationPainter(
                              modulation: _mod,
                              ideal: ModulationMath.constellation(_mod),
                              cloud: _history,
                              current: cur,
                              probe: _probe,
                              showBitLabels: labelAll,
                              style: style,
                              revision: _revision,
                            ),
                          );
                          if (labelAll) return paint;
                          return MouseRegion(
                            onHover: (PointerHoverEvent e) =>
                                _probeAt(e.localPosition, size),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (TapDownDetails d) =>
                                  _probeAt(d.localPosition, size),
                              child: paint,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _legend(text, <Widget>[
            _legendItem(text, _dot(colors.textSecondary, 3), 'Ideal point'),
            _legendItem(text, _dot(colors.textAccent, 3), 'Received'),
            _legendItem(
              text,
              Icon(Icons.close, size: 14, color: colors.statusDanger),
              'Decided wrong',
            ),
            _legendItem(
              text,
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.textPrimary, width: 2),
                ),
              ),
              'Current symbol',
            ),
          ]),
          const SizedBox(height: AppSpacing.xs),
          if (_sent == 0)
            _note(
              text,
              Icons.touch_app_outlined,
              'Press Step to send one symbol, or Play to keep sending. '
              'Received points land around the ideal points; the thin lines '
              'are the decision boundaries the receiver uses.',
            )
          else if (!labelAll)
            _probeReadout(text, mono),
        ],
      ),
    );
  }

  Widget _probeReadout(TextTheme text, AppMonoText mono) {
    final ConstellationPoint? p = _probe;
    if (p == null) {
      return _note(
        text,
        Icons.ads_click,
        'Too many points to label them all. Tap or hover a point to see '
        'its bits.',
      );
    }
    return _row(
      text,
      mono,
      label: 'Point',
      value:
          '${_bitsSplit(p.symbol)}  (I ${_signed(p.levelI)}, '
          'Q ${_signed(p.levelQ)})',
    );
  }

  // ── Waveform ────────────────────────────────────────────────────────────

  Widget _waveformCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    return _card(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          // Fewer, wider slots on a phone so each symbol's bits still fit.
          final int slots = (c.maxWidth / 80).floor().clamp(3, 6);
          final int start = math.max(0, _history.length - slots);
          final List<SimulatedSymbol> shown = _history.sublist(start);
          final List<ConstellationPoint> pts = <ConstellationPoint>[
            for (final SimulatedSymbol s in shown) s.sent,
          ];
          final String semantic = shown.isEmpty
              ? 'Carrier waveform. No symbols sent yet.'
              : 'Carrier waveform for the last ${shown.length} symbols, '
                    'bits ${shown.map((SimulatedSymbol s) => ModulationMath.bitString(s.sent.symbol, _mod.bitsPerSymbol)).join(', ')}.';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _sectionLabel(text, 'Carrier, last $slots symbols'),
              const SizedBox(height: AppSpacing.xs),
              // Bits above each symbol slot, right-aligned like the traces.
              ExcludeSemantics(
                child: Row(
                  children: <Widget>[
                    for (int s = 0; s < slots; s++)
                      Expanded(child: _slotBits(text, mono, s, slots, shown)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Semantics(
                label: semantic,
                excludeSemantics: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Container(
                    height: 140,
                    color: colors.surface2,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: WaveformPainter(
                        symbols: pts,
                        slots: slots,
                        maxAmplitude: ModulationMath.maxAmplitude(_mod),
                        revision: _revision,
                        cyclesPerSymbol: _kCyclesPerSymbol,
                        style: WaveformStyle(
                          iTrace: colors.textSecondary,
                          qTrace: colors.textTertiary,
                          sum: colors.textAccent,
                          boundary: colors.borderStrong,
                          baseline: colors.border,
                          currentBar: colors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _legend(text, <Widget>[
                _legendItem(
                  text,
                  _lineSample(colors.textSecondary, 1),
                  'I cos(wt)',
                ),
                _legendItem(
                  text,
                  _lineSample(colors.textTertiary, 1, dashed: true),
                  '-Q sin(wt)',
                ),
                _legendItem(
                  text,
                  _lineSample(colors.textAccent, 3),
                  'Sum: the carrier sent',
                ),
              ]),
              const SizedBox(height: AppSpacing.xs),
              _note(
                text,
                Icons.slow_motion_video_outlined,
                'Drawn slowed down: $_kCyclesPerSymbol carrier cycles per '
                'symbol. A real Wi-Fi carrier runs billions of cycles per '
                'second. Each symbol changes only the amplitude and phase.',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _slotBits(
    TextTheme text,
    AppMonoText mono,
    int slot,
    int slots,
    List<SimulatedSymbol> shown,
  ) {
    final AppColorScheme colors = context.colors;
    final int idx = slot - (slots - shown.length);
    if (idx < 0) return const SizedBox(height: AppSpacing.md);
    final bool isCurrent = idx == shown.length - 1;
    final String b = ModulationMath.bitString(
      shown[idx].sent.symbol,
      _mod.bitsPerSymbol,
    );
    final String display = _mod.bitsPerSymbol > 6
        ? '${b.substring(0, _mod.bitsPerAxis)}\n${b.substring(_mod.bitsPerAxis)}'
        : b;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          height: 1.2,
          fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
          color: isCurrent ? colors.textAccent : colors.textTertiary,
        ),
      ),
    );
  }

  // ── Controls ────────────────────────────────────────────────────────────

  Widget _controlsCard(TextTheme text, AppMonoText mono, bool reduceMotion) {
    final AppColorScheme colors = context.colors;
    final bool can = _canSend;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Semantics(
                  button: true,
                  label: _playing ? 'Pause' : 'Play',
                  excludeSemantics: true,
                  child: FilledButton.icon(
                    onPressed: can ? _togglePlay : null,
                    icon: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(_playing ? 'Pause' : 'Play'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      disabledBackgroundColor: colors.disabledFill,
                      disabledForegroundColor: colors.textDisabled,
                      minimumSize: const Size.fromHeight(
                        AppSpacing.minTouchTarget,
                      ),
                      textStyle: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _outlined(
                  text,
                  label: 'Step',
                  icon: Icons.skip_next_rounded,
                  semantic: 'Step: send one symbol',
                  enabled: can && !_playing,
                  onTap: _step,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: _outlined(
                  text,
                  label: '+$_kBurst',
                  icon: Icons.fast_forward_rounded,
                  semantic: 'Send $_kBurst symbols at once',
                  enabled: can && !_playing,
                  onTap: _burst,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _outlined(
                  text,
                  label: 'Reset',
                  icon: Icons.restart_alt_rounded,
                  semantic: 'Reset: clear received points and counts',
                  enabled: _sent > 0,
                  onTap: () => setState(_resetStats),
                ),
              ),
            ],
          ),
          if (reduceMotion) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _note(
              text,
              Icons.motion_photos_off_outlined,
              'Reduced motion is on, so nothing moves until you ask. Step '
              'sends one symbol at a time.',
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              _sectionLabel(text, 'Signal-to-noise ratio (SNR)'),
              const Spacer(),
              Text(
                '${_db(_snrDb)} dB',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
          Slider(
            value: _snrDb,
            min: 0,
            max: 45,
            divisions: 90,
            onChanged: _onSnr,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${_db(_snrDb)} dB',
            semanticFormatterCallback: (double v) => 'SNR ${_db(v)} dB',
          ),
          const SizedBox(height: AppSpacing.xs),
          AppToggle<SimSpeed>(
            label: 'Speed (symbols per second)',
            value: _speed,
            expand: true,
            items: <AppToggleItem<SimSpeed>>[
              for (final SimSpeed s in SimSpeed.values) (s, s.label),
            ],
            onChanged: _onSpeed,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<BitSource>(
            label: 'Bits to send',
            value: _source,
            expand: true,
            items: const <AppToggleItem<BitSource>>[
              (BitSource.random, 'Random'),
              (BitSource.text, 'Your text'),
            ],
            onChanged: _onSource,
          ),
          if (_source == BitSource.text) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _textSection(text, mono),
          ],
        ],
      ),
    );
  }

  Widget _textSection(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final SymbolFrame frame = _frame;
    final int bits = _messageBits;
    final String rxSoFar = _rxSymbols.isEmpty ? '' : _decodeRx();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LabeledField(
          label: 'Message',
          hint: '(sent as UTF-8 bits)',
          semanticLabel: 'Message to send',
          field: TextField(
            controller: _textCtrl,
            onChanged: _onText,
            maxLength: _kMaxTextLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            autocorrect: false,
            enableSuggestions: false,
            style: text.bodyLarge?.copyWith(color: colors.textPrimary),
            cursorColor: colors.textAccent,
            decoration: const InputDecoration(hintText: 'Type a message'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (frame.symbols.isEmpty)
          _note(
            text,
            Icons.edit_outlined,
            'Type a message to send it, or switch to Random bits.',
            tint: colors.statusWarning,
          )
        else ...<Widget>[
          Text(
            '${bits ~/ 8} bytes = $bits bits = ${frame.symbols.length} '
            'symbols of ${_mod.bitsPerSymbol} '
            'bit${_mod.bitsPerSymbol == 1 ? '' : 's'}. '
            '${frame.padBits == 0 ? 'No padding needed.' : 'The last symbol is padded with ${frame.padBits} zero bit${frame.padBits == 1 ? '' : 's'}.'}',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          _row(
            text,
            mono,
            label: 'Progress',
            value:
                '$_textPos of ${frame.symbols.length} symbols sent'
                '${_passes > 0 ? ', pass ${_passes + 1}' : ''}',
          ),
          _row(
            text,
            mono,
            label: 'Received so far',
            value: rxSoFar.isEmpty ? '-' : rxSoFar,
          ),
          if (_lastFullRx != null)
            _row(text, mono, label: 'Last full copy', value: _lastFullRx!),
        ],
      ],
    );
  }

  // ── Readouts ────────────────────────────────────────────────────────────

  Widget _readoutsCard(TextTheme text, AppMonoText mono) {
    final AppColorScheme colors = context.colors;
    final SimulatedSymbol? cur = _current;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionLabel(text, 'Readouts'),
          const SizedBox(height: AppSpacing.xs),
          _row(
            text,
            mono,
            label: 'Bits per symbol',
            value: '${_mod.bitsPerSymbol}',
          ),
          _row(text, mono, label: 'Levels per axis', value: _levelsText()),
          _row(text, mono, label: 'Scale (K_MOD)', value: _kModText()),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: cur == null
                ? _note(
                    text,
                    Icons.info_outline,
                    'The current symbol appears here once you send one.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _row(
                        text,
                        mono,
                        label: 'Current bits',
                        value: _bitsSplit(cur.sent.symbol),
                        emphasize: true,
                      ),
                      _row(
                        text,
                        mono,
                        label: 'I, Q',
                        value:
                            '${_signedD(cur.sent.i, 4)}, '
                            '${_signedD(cur.sent.q, 4)}',
                      ),
                      _row(
                        text,
                        mono,
                        label: 'Amplitude, phase',
                        value:
                            '${cur.sent.amplitude.toStringAsFixed(4)}, '
                            '${_signedD(cur.sent.phase * 180 / math.pi, 1)} deg',
                      ),
                      _row(
                        text,
                        mono,
                        label: 'Decided as',
                        value:
                            '${_bitsSplit(cur.decided.symbol)} '
                            '${cur.isSymbolError ? '(wrong, ${cur.bitErrors} bit${cur.bitErrors == 1 ? '' : 's'} off)' : '(correct)'}',
                        valueColor: cur.isSymbolError
                            ? colors.statusDanger
                            : null,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _row(text, mono, label: 'Symbols sent', value: '$_sent'),
          _row(
            text,
            mono,
            label: 'Symbol errors',
            value: _sent == 0
                ? '-'
                : '$_symbolErrors (${(100 * _symbolErrors / _sent).toStringAsFixed(2)}%)',
          ),
          _row(
            text,
            mono,
            label: 'Bit errors',
            value: _bitsSent == 0
                ? '-'
                : '$_bitErrors of $_bitsSent '
                      '(${(100 * _bitErrors / _bitsSent).toStringAsFixed(3)}%)',
          ),
        ],
      ),
    );
  }

  // ── EVM ─────────────────────────────────────────────────────────────────

  Widget _evmCard(TextTheme text, AppMonoText mono) {
    final double theory = _theoryEvmDb;
    final double? measured = _measuredEvmDb;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionLabel(text, 'Error vector magnitude (EVM)'),
          const SizedBox(height: AppSpacing.xs),
          _row(
            text,
            mono,
            label: 'Measured',
            value: measured == null
                ? 'send symbols first'
                : '${_db(measured)} dB (${_pct(measured)}%) '
                      'over $_sent symbol${_sent == 1 ? '' : 's'}',
            emphasize: measured != null,
          ),
          _row(
            text,
            mono,
            label: 'Theory',
            value: '${_db(theory)} dB (${_pct(theory)}%) = -SNR',
          ),
          const SizedBox(height: AppSpacing.sm),
          _sectionLabel(text, '802.11 transmit EVM limit, ${_mod.label}'),
          const SizedBox(height: AppSpacing.xxs),
          for (final EvmRequirement r in ModulationMath.requiredEvm(_mod))
            _requirementRow(text, mono, r, theory),
          const SizedBox(height: AppSpacing.xs),
          _note(
            text,
            Icons.info_outline,
            'These limits are the transmitter\'s required accuracy (how '
            'cleanly a radio must build each point), not a receiver '
            'sensitivity threshold. Meets or misses compares them with the '
            'EVM this SNR produces.',
          ),
        ],
      ),
    );
  }

  Widget _requirementRow(
    TextTheme text,
    AppMonoText mono,
    EvmRequirement r,
    double evmDb,
  ) {
    final AppColorScheme colors = context.colors;
    final bool ok = ModulationMath.meetsRequirement(evmDb, r.requiredDb);
    final Color tone = ok ? colors.statusSuccess : colors.statusDanger;
    final String verdict = ok ? 'Meets' : 'Misses';
    return Semantics(
      label:
          'Coding rate ${r.codingRates}, limit ${_db(r.requiredDb)} dB, '
          '$verdict at ${_db(evmDb)} dB',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Rate ${r.codingRates}',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Text(
              '${_db(r.requiredDb)} dB',
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              size: 18,
              color: tone,
            ),
            const SizedBox(width: AppSpacing.xxs),
            SizedBox(
              width: 56,
              child: Text(
                verdict,
                style: text.labelLarge?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Explainer ───────────────────────────────────────────────────────────

  Widget _explainerCard(TextTheme text) {
    final AppColorScheme colors = context.colors;
    TextStyle? body() => text.bodyMedium?.copyWith(color: colors.textSecondary);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _sectionLabel(text, 'What you are seeing'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Each group of bits picks one point on the I/Q plane. The point\'s '
            'distance from the center sets the carrier\'s amplitude, and its '
            'angle sets the phase. That one amplitude and phase is held for '
            'one symbol, then the next group of bits picks the next point.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Higher orders carry more bits per symbol by packing the points '
            'closer together. Noise pushes each received point off its ideal '
            'spot; once it crosses a decision boundary the receiver picks a '
            'neighbor. Neighbors are Gray coded, so that usually costs one bit.',
            style: body(),
          ),
        ],
      ),
    );
  }

  // ── Small building blocks ───────────────────────────────────────────────

  Widget _outlined(
    TextTheme text, {
    required String label,
    required IconData icon,
    required String semantic,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final AppColorScheme colors = context.colors;
    final Color fg = enabled ? colors.textAccent : colors.textDisabled;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, color: fg),
        label: Text(
          label,
          style: text.labelLarge?.copyWith(
            color: fg,
            fontWeight: enabled ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          disabledBackgroundColor: colors.disabledFill,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: 1.5,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
        ),
      ),
    );
  }

  Widget _sectionLabel(TextTheme text, String label) {
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
    bool emphasize = false,
    Color? valueColor,
  }) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 136,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              value,
              style: mono.inlineCode.copyWith(
                color:
                    valueColor ??
                    (emphasize ? colors.textAccent : colors.textPrimary),
                fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(TextTheme text, IconData icon, String message, {Color? tint}) {
    final AppColorScheme colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: tint ?? colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _legend(TextTheme text, List<Widget> items) => ExcludeSemantics(
    child: Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: items,
    ),
  );

  Widget _legendItem(TextTheme text, Widget swatch, String label) {
    final AppColorScheme colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 20, child: Center(child: swatch)),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _dot(Color c, double r) => Container(
    width: r * 2,
    height: r * 2,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget _lineSample(Color c, double w, {bool dashed = false}) {
    if (!dashed) return Container(width: 20, height: w, color: c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(width: 5, height: w, color: c),
        const SizedBox(width: AppSpacing.xxs),
        Container(width: 5, height: w, color: c),
      ],
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
}
