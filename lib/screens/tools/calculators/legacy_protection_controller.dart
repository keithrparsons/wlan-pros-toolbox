// State for the Wi-Fi Classroom Legacy Protection Cost tool
// (legacy-protection).
//
// One ChangeNotifier holds the inputs, the computed result, the
// predict-then-reveal question and the playhead, so the stage
// (LegacyProtectionStage) and the controls (LegacyProtectionControls) are
// separate views over one object. The phone screen stacks them; the presenter
// layout puts the same views side by side over this same object (spec 00).
//
// THE CLOCK. As in Multicast at the Basic Rate, the playhead's Ticker is
// constructed here directly, not from a widget's TickerProvider: the route
// under the presenter is muted, and the sweep must keep playing while the
// presenter shows it. The playhead is its own ValueNotifier, so a playing
// sweep repaints the lanes without rebuilding the cards.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/dsss_timing.dart';
import '../../../services/wifi_lab/legacy_protection_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kLegacyProtectionToolId = 'legacy-protection';

/// How long one sweep of the timeline window takes on screen. The window is a
/// few milliseconds, so this is roughly two thousand times slower than real
/// time.
const Duration kLpSweepDuration = Duration(seconds: 6);

/// Where the predict-then-reveal question stands.
enum LpQuestion { idle, asking, revealed }

/// The answer ranges a class can pick from: the share of the laptop's
/// modern-only payload rate that is lost.
enum LpGuess {
  nothing('Nothing', 0, 0.05),
  upToQuarter('5 to 25%', 0.05, 0.25),
  quarterTo40('25 to 40%', 0.25, 0.40),
  aboutHalf('40 to 60%', 0.40, 0.60),
  overSixty('Over 60%', 0.60, double.infinity);

  const LpGuess(this.label, this.low, this.high);

  final String label;
  final double low;
  final double high;

  bool contains(double share) => share >= low && share < high;
}

/// The question's scenario (spec 39): an old 802.11b scanner associated but
/// silent, protection CTS-to-self at 1 Mb/s long preamble, CWmin 15, one
/// laptop sending 1500-byte frames at 54 Mb/s.
const LpConfig kLpQuestionConfig = LpConfig();

class LegacyProtectionController extends ChangeNotifier {
  LegacyProtectionController({LpConfig initial = const LpConfig()})
    : _config = initial,
      _result = computeLegacyProtection(initial) {
    _ticker = Ticker(_onTick, debugLabel: 'legacy-protection-sweep');
  }

  LpConfig _config;
  LpResult _result;
  LpQuestion _question = LpQuestion.idle;
  LpGuess? _guess;

  late final Ticker _ticker;

  /// 0 to 1 across the window. 1 draws every cycle.
  final ValueNotifier<double> _playhead = ValueNotifier<double>(1);
  double _playFrom = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  // ── Read side ─────────────────────────────────────────────────────────────

  LpConfig get config => _config;
  LpResult get result => _result;
  LpQuestion get question => _question;
  LpGuess? get guess => _guess;

  /// True while the cost answers are hidden.
  bool get masked => _question == LpQuestion.asking;

  ValueListenable<double> get playhead => _playhead;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _set(LpConfig next) {
    if (next == _config) return;
    _config = next;
    _result = computeLegacyProtection(next);
    _notify();
  }

  set associated(bool v) => _set(_config.copyWith(associated: v));
  set heard(bool v) => _set(_config.copyWith(heard: v));
  set neighborChannel(NeighborChannel v) =>
      _set(_config.copyWith(neighborChannel: v));
  set policy(NeighborPolicy v) => _set(_config.copyWith(policy: v));
  set oldDeviceShortPreamble(bool v) =>
      _set(_config.copyWith(oldDeviceShortPreamble: v));
  set protectionKind(ProtectionKind v) =>
      _set(_config.copyWith(protection: _config.protection.copyWith(kind: v)));
  set cwMin(LpCwMin v) => _set(_config.copyWith(cwMin: v));
  set payloadBytes(int v) => _set(_config.copyWith(payloadBytes: v));
  set rateMbps(int v) => _set(_config.copyWith(rateMbps: v));

  /// Picks the protection frame's rate and preamble. 1 Mb/s short does not
  /// exist and is refused (the picker shows it disabled, with the reason).
  void pickProtection(ProtectionRate rate, DsssPreamble preamble) {
    final ProtectionChoice next = _config.protection.copyWith(
      rate: rate,
      preamble: preamble,
    );
    if (!next.isAvailable) return;
    _set(_config.copyWith(protection: next));
  }

  /// Up and Down arrows: the protection frame one step faster (Up) or slower
  /// (Down) through the seven 802.11b rate and preamble pairs, ordered by
  /// CTS duration. From the OFDM contrast, Down returns to the fastest
  /// 802.11b pair.
  void nudgeProtectionRate(int delta) {
    final List<(ProtectionRate, DsssPreamble)> order = dsssStepOrder();
    final ProtectionChoice p = _config.protection;
    int at = order.indexWhere(
      ((ProtectionRate, DsssPreamble) e) =>
          e.$1 == p.rate && e.$2 == p.preamble,
    );
    if (at < 0) at = order.length;
    final int next = (at + delta).clamp(0, order.length - 1);
    pickProtection(order[next].$1, order[next].$2);
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question's scenario and hides the answers.
  void ask() {
    _config = kLpQuestionConfig;
    _result = computeLegacyProtection(_config);
    _question = LpQuestion.asking;
    _guess = null;
    _notify();
  }

  set guess(LpGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  void reveal() {
    if (_question != LpQuestion.asking) return;
    _question = LpQuestion.revealed;
    _notify();
    replay();
  }

  /// Closes the question card.
  void dismissQuestion() {
    if (_question == LpQuestion.idle) return;
    _question = LpQuestion.idle;
    _guess = null;
    _notify();
  }

  // ── Playhead ──────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. With it on,
  /// the window is drawn complete and never sweeps by itself. Does not
  /// notify (it is set during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) {
      _stop();
      _playhead.value = 1;
    }
  }

  /// Sweeps from the start, or draws the window complete with reduced motion
  /// on.
  void replay() {
    if (_reducedMotion) {
      _stop();
      _playhead.value = 1;
      _notify();
      return;
    }
    _playFrom = 0;
    _playhead.value = 0;
    _start();
  }

  /// Space: pause a sweep, resume a paused one, or replay a finished one.
  /// Pressed by the user, so it plays even with reduced motion on.
  void togglePlay() {
    if (_playing) {
      _stop();
      _notify();
      return;
    }
    _playFrom = _playhead.value >= 1 ? 0 : _playhead.value;
    _playhead.value = _playFrom;
    _start();
  }

  /// Right arrow: pause and move the playhead to the end of the next send
  /// cycle on this network's lane.
  void stepCycle() {
    _stop();
    final double window = _result.windowUs.toDouble();
    final double cycle = _result.cycle.cycleUs;
    final double atUs = (_playhead.value >= 1 ? 0 : _playhead.value) * window;
    final double next = ((atUs / cycle + 1e-9).floor() + 1) * cycle;
    _playhead.value = (next / window).clamp(0.0, 1.0);
    _notify();
  }

  /// R: an empty window, paused, ready to play or step.
  void resetSweep() {
    _stop();
    _playhead.value = 0;
    _notify();
  }

  void _start() {
    _playing = true;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
    _notify();
  }

  void _stop() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double t =
        _playFrom + elapsed.inMicroseconds / kLpSweepDuration.inMicroseconds;
    if (t >= 1) {
      _playhead.value = 1;
      _stop();
      _notify();
      return;
    }
    _playhead.value = t;
  }

  // ── Presenter keys ────────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: stepCycle,
    reset: resetSweep,
    sliderDown: () => nudgeProtectionRate(-1),
    sliderUp: () => nudgeProtectionRate(1),
    sliderLabel: 'Protection frame rate',
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final LpConfig c = _config;
    final LpResult r = _result;
    String bit(bool b) => b ? '1' : '0';
    final StringBuffer b = StringBuffer()
      ..writeln('Legacy Protection Cost (WLAN Pros Toolbox)')
      ..writeln(
        'Sender: ${c.payloadBytes}-byte frames at ${c.rateMbps} Mb/s, '
        '802.11g OFDM (orthogonal frequency-division multiplexing), 2.4 GHz',
      )
      ..writeln(
        '802.11b device associated: ${c.associated ? 'yes' : 'no'}; '
        '802.11b network heard: '
        '${c.heard ? '${c.neighborChannel.label.toLowerCase()}, AP reacts to '
                  '${c.policy.label.toLowerCase()}' : 'no'}',
      )
      ..writeln(
        'ERP (Extended Rate PHY) element: NonERP_Present '
        '${bit(r.erp.nonErpPresent)}, Use_Protection '
        '${bit(r.erp.useProtection)}, Barker_Preamble_Mode '
        '${bit(r.erp.barkerPreambleMode)}',
      )
      ..writeln('HT (High Throughput) Protection: ${r.ht.value} (${r.ht.name})')
      ..writeln(
        r.protecting
            ? 'Protection: ${c.protection.label}, '
                  '${lpUs(r.protectionTenths / 10)} per frame'
            : 'Protection: none',
      )
      ..writeln('Slot: ${r.cycle.spec.slotUs} µs; CWmin ${r.cycle.spec.cwMin}')
      ..writeln(
        'Cycle: ${lpUs(r.cycle.cycleUs)} (modern devices only: '
        '${lpUs(r.baseline.cycleUs)})',
      )
      ..writeln(
        'Payload rate: ${lpMbps(r.cycle.payloadRateMbps)} (modern devices '
        'only: ${lpMbps(r.baseline.payloadRateMbps)}), '
        '${lpPct(r.lostShare)} lost',
      );
    return b.toString().trimRight();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _playhead.dispose();
    super.dispose();
  }
}

/// 393.5 -> "393.5 µs", 812 -> "812 µs", 1941.5 -> "1,941.5 µs".
String lpUs(double us) {
  final String fixed = us == us.roundToDouble()
      ? us.toStringAsFixed(0)
      : us.toStringAsFixed(1);
  final List<String> parts = fixed.split('.');
  final String whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (Match m) => '${m[1]},',
  );
  return '${parts.length > 1 ? '$whole.${parts[1]}' : whole} µs';
}

/// 30.49 -> "30.5 Mb/s".
String lpMbps(double v) => '${v.toStringAsFixed(1)} Mb/s';

/// 0.515 -> "51.5%".
String lpPct(double share) => '${(share * 100).toStringAsFixed(1)}%';
