// State for the Wi-Fi Lab Modulation Simulator (modulation-simulator).
//
// One ChangeNotifier holds every input, the accumulated run and the playback
// timer, so the tool's views are independent widgets over it
// (Keith, 2026-09-25: a stage and controls over one shared state object):
//   - ModulationSimulatorStage    (modulation_simulator_stage.dart)
//   - ModulationPicker, ModulationSimulatorControls, ModulationReadouts,
//     ModulationExplainer         (modulation_simulator_controls.dart)
// The phone screen stacks them; the presenter layout puts the stage beside
// the controls. Both routes hold the SAME controller, so a scene set on one is
// the scene on the other.
//
// Moved verbatim from the screen's State on 2026-09-26 (presenter pilot); the
// behavior is unchanged: it opens PAUSED (§8.8), Play advances whole symbols
// on a timer, Step sends one, and a lifecycle pause stops playback.
//
// All math lives in ModulationMath (lib/services/rf/modulation_math.dart).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../widgets/presenter/presenter_actions.dart';
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
const int kModLabelEveryPointMax = 16;

/// Received points kept for the cloud. Enough for 4096-QAM to show a spread,
/// small enough to repaint every tick.
const int _kCloudCap = 2000;

/// Carrier cycles drawn per symbol (spec: 3 is a good visual choice).
const int kModCyclesPerSymbol = 3;

/// Symbols sent by the +100 button.
const int kModBurst = 100;

/// Longest message accepted in text mode.
const int kModMaxTextLength = 120;

/// SNR slider bounds and the presenter keyboard's step, dB.
const double kModSnrMin = 0;
const double kModSnrMax = 45;
const double kModSnrKeyStep = 1;

class ModulationSimulatorController extends ChangeNotifier
    with WidgetsBindingObserver {
  ModulationSimulatorController({int? seed}) : _rng = math.Random(seed) {
    WidgetsBinding.instance.addObserver(this);
  }

  final math.Random _rng;
  bool _disposed = false;

  Modulation _mod = Modulation.qam16;
  double _snrDb = 25;
  BitSource _source = BitSource.random;
  SimSpeed _speed = SimSpeed.medium;

  /// The message in text mode. Shared by every view's TextField.
  final TextEditingController textCtrl = TextEditingController(
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
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    textCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) pause();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Read-only state ─────────────────────────────────────────────────────

  Modulation get modulation => _mod;
  double get snrDb => _snrDb;
  BitSource get source => _source;
  SimSpeed get speed => _speed;
  bool get playing => _playing;
  List<SimulatedSymbol> get history => _history;
  int get sent => _sent;
  int get symbolErrors => _symbolErrors;
  int get bitErrors => _bitErrors;
  int get bitsSent => _bitsSent;
  int get revision => _revision;
  int get textPos => _textPos;
  bool get hasRxSymbols => _rxSymbols.isNotEmpty;
  String? get lastFullRx => _lastFullRx;
  int get passes => _passes;
  ConstellationPoint? get probe => _probe;

  // ── Derived ─────────────────────────────────────────────────────────────

  SymbolFrame get frame => ModulationMath.groupBits(
    ModulationMath.textToBits(textCtrl.text),
    _mod.bitsPerSymbol,
  );

  int get messageBits => ModulationMath.textToBits(textCtrl.text).length;

  bool get canSend => _source == BitSource.random || textCtrl.text.isNotEmpty;

  SimulatedSymbol? get current => _history.isEmpty ? null : _history.last;

  bool get labelAllPoints => _mod.points <= kModLabelEveryPointMax;

  double get theoryEvmDb =>
      ModulationMath.evmToDb(ModulationMath.theoreticalEvmRms(_snrDb));

  double? get measuredEvmDb => _sent == 0
      ? null
      : ModulationMath.evmToDb(
          ModulationMath.measuredEvmRms(_sumErrorSq, _sent),
        );

  // ── Simulation ──────────────────────────────────────────────────────────

  /// Sends one symbol. Mutates state; callers notify.
  void _sendOne() {
    final int symbol;
    SymbolFrame? f;
    if (_source == BitSource.random) {
      symbol = ModulationMath.randomSymbol(_mod, _rng);
    } else {
      f = frame;
      if (f.symbols.isEmpty) return;
      if (_textPos >= f.symbols.length) _textPos = 0;
      symbol = f.symbols[_textPos];
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

    if (f != null) {
      _rxSymbols.add(s.decided.symbol);
      _textPos++;
      if (_textPos >= f.symbols.length) {
        _lastFullRx = decodeRx();
        _passes++;
        _rxSymbols.clear();
        _textPos = 0;
      }
    }
  }

  /// Text decoded from the symbols received so far in this pass, with the
  /// zero padding dropped.
  String decodeRx() {
    final List<int> bits = ModulationMath.symbolsToBits(
      _rxSymbols,
      _mod.bitsPerSymbol,
    );
    final int keep = math.min(bits.length, messageBits);
    return ModulationMath.bitsToText(bits.sublist(0, keep));
  }

  /// Sends one symbol (the Step button and the Right-arrow key). Does nothing
  /// while playing, matching the disabled Step button.
  void step() {
    if (!canSend || _playing) return;
    _sendOne();
    _notify();
  }

  /// Sends [kModBurst] symbols at once.
  void burst() {
    if (!canSend || _playing) return;
    for (int n = 0; n < kModBurst; n++) {
      _sendOne();
    }
    _notify();
  }

  void play() {
    if (!canSend) return;
    _timer?.cancel();
    final int ms = (1000 / _speed.symbolsPerSecond).round();
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (_disposed || !canSend) {
        pause();
        return;
      }
      _sendOne();
      _notify();
    });
    _playing = true;
    _notify();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _playing = false;
    _notify();
  }

  void togglePlay() => _playing ? pause() : play();

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

  /// The Reset button and the R key.
  void reset() {
    _resetStats();
    _notify();
  }

  void setModulation(Modulation m) {
    _mod = m;
    _resetStats();
    _notify();
  }

  void setSnr(double v) {
    _snrDb = v;
    _resetStats();
    _notify();
  }

  /// The presenter keyboard's slider keys: SNR up or down one step.
  void nudgeSnr(double delta) {
    final double v = (_snrDb + delta).clamp(kModSnrMin, kModSnrMax);
    if (v != _snrDb) setSnr(v);
  }

  void setSource(BitSource s) {
    _source = s;
    _resetStats();
    _notify();
    if (_playing && !canSend) pause();
  }

  void setSpeed(SimSpeed s) {
    _speed = s;
    _notify();
    if (_playing) play();
  }

  /// Called by the message field on every edit.
  void onTextChanged(String _) {
    _resetStats();
    _notify();
    if (_playing && !canSend) pause();
  }

  void probeAt(Offset local, Size size) {
    final ({double i, double q}) iq = ConstellationPainter.toIq(
      local,
      size,
      _mod,
    );
    final ConstellationPoint p = ModulationMath.decide(_mod, iq.i, iq.q);
    if (p.symbol != _probe?.symbol) {
      _probe = p;
      _notify();
    }
  }

  // ── Presenter keyboard ──────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: step,
    reset: reset,
    sliderDown: () => nudgeSnr(-kModSnrKeyStep),
    sliderUp: () => nudgeSnr(kModSnrKeyStep),
    sliderLabel: 'SNR',
  );

  // ── Formatting ──────────────────────────────────────────────────────────

  static String db(double v) {
    if (!v.isFinite) return '-';
    final String s = v.toStringAsFixed(1);
    return s == '-0.0' ? '0.0' : s;
  }

  static String pct(double evmDb) {
    final double ratio = math.pow(10, evmDb / 20).toDouble();
    final double p = ratio * 100;
    return p >= 10 ? p.toStringAsFixed(1) : p.toStringAsFixed(2);
  }

  static String signed(int v) => v > 0 ? '+$v' : '$v';

  static String signedD(double v, int decimals) {
    final String s = v.toStringAsFixed(decimals);
    if (s.startsWith('-')) {
      final bool allZero = RegExp(r'^-0\.?0*$').hasMatch(s);
      return allZero ? s.substring(1) : s;
    }
    return '+$s';
  }

  String kModText() {
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

  String levelsText() {
    final int l = _mod.levelsPerAxis;
    final String range = l == 2
        ? '+/-1'
        : '+/-1, +/-3${l > 4 ? ' ... +/-${l - 1}' : ''}';
    if (_mod.isBpsk) return '2 on I ($range); Q unused';
    return '$l on I, $l on Q ($range)';
  }

  String bitsSplit(int symbol) {
    final String b = ModulationMath.bitString(symbol, _mod.bitsPerSymbol);
    if (_mod.isBpsk) return b;
    final int h = _mod.bitsPerAxis;
    return '${b.substring(0, h)} ${b.substring(h)}';
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String? copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('Modulation Simulator')
      ..writeln(
        '${_mod.label}: ${_mod.bitsPerSymbol} bits/symbol, '
        '${_mod.points} points',
      )
      ..writeln('SNR: ${db(_snrDb)} dB')
      ..writeln('Theoretical EVM: ${db(theoryEvmDb)} dB');
    final double? m = measuredEvmDb;
    if (m != null) {
      b
        ..writeln('Measured EVM: ${db(m)} dB over $_sent symbols')
        ..writeln('Symbol errors: $_symbolErrors of $_sent')
        ..writeln('Bit errors: $_bitErrors of $_bitsSent');
    }
    for (final EvmRequirement r in ModulationMath.requiredEvm(_mod)) {
      final bool ok = ModulationMath.meetsRequirement(
        theoryEvmDb,
        r.requiredDb,
      );
      b.writeln(
        'Transmit EVM limit, rate ${r.codingRates}: '
        '${db(r.requiredDb)} dB (${ok ? 'meets' : 'misses'})',
      );
    }
    b.writeln(
      'Transmit EVM limits are transmitter accuracy, not receiver '
      'sensitivity.',
    );
    return b.toString().trimRight();
  }
}
