// State for the Wi-Fi Classroom Multicast at the Basic Rate tool
// (multicast-basic-rate).
//
// One ChangeNotifier holds the inputs, the computed result, which lanes the
// stage shows, the predict-then-reveal question and the playhead, so the
// stage (MulticastBasicRateStage) and the controls (MulticastBasicRateControls)
// are separate views over one object. The phone screen stacks them; the
// presenter layout puts the same views side by side over this same object
// (spec 00).
//
// THE CLOCK. The playhead's Ticker is constructed here directly, not from a
// widget's TickerProvider: the route under the presenter is muted, and the
// sweep must keep playing while the presenter shows it. The playhead is its
// own ValueNotifier, so a playing sweep repaints the lanes without
// rebuilding the cards; this object notifies only when an input, the play
// state or the question changes.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/multicast_basic_rate_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kMulticastBasicRateToolId = 'multicast-basic-rate';

/// How long the one-second timeline takes to sweep: six times slower than
/// real time, so a class can follow it.
const Duration kMcSweepDuration = Duration(seconds: 6);

/// Which lanes the stage draws.
enum McView {
  multicast('Multicast'),
  unicast('Converted to unicast'),
  compare('Compare both');

  const McView(this.label);

  final String label;

  bool get showsMulticast => this != McView.unicast;
  bool get showsUnicast => this != McView.multicast;
}

/// Where the predict-then-reveal question stands.
enum McQuestion {
  /// Not asked: every number is on screen.
  idle,

  /// Asked: the airtime answers are hidden until Reveal.
  asking,

  /// Revealed: the answer and the guess are shown side by side.
  revealed,
}

/// The answer ranges a class can pick from.
enum McGuess {
  under10('Under 10%', 0, 0.10),
  from10to30('10 to 30%', 0.10, 0.30),
  from30to60('30 to 60%', 0.30, 0.60),
  over60('Over 60%', 0.60, double.infinity);

  const McGuess(this.label, this.low, this.high);

  final String label;
  final double low;
  final double high;

  bool contains(double share) => share >= low && share < high;
}

/// The question's scenario: a 4 Mb/s video stream on a Wi-Fi 6 AP at 5 GHz,
/// basic rate 6 Mb/s, nobody in power save.
const McConfig kMcQuestionConfig = McConfig();

class MulticastBasicRateController extends ChangeNotifier {
  MulticastBasicRateController({McConfig initial = const McConfig()})
    : _config = initial,
      _result = computeMulticast(initial) {
    _ticker = Ticker(_onTick, debugLabel: 'multicast-basic-rate-sweep');
  }

  McConfig _config;
  McResult _result;
  McView _view = McView.compare;
  McQuestion _question = McQuestion.idle;
  McGuess? _guess;

  late final Ticker _ticker;

  /// 0 to 1 across the second. 1 draws every frame.
  final ValueNotifier<double> _playhead = ValueNotifier<double>(1);
  double _playFrom = 0;
  bool _playing = false;
  bool _reducedMotion = false;
  bool _disposed = false;

  // ── Read side ─────────────────────────────────────────────────────────────

  McConfig get config => _config;
  McResult get result => _result;
  McView get view => _view;
  McQuestion get question => _question;
  McGuess? get guess => _guess;

  /// True while the airtime answers are hidden.
  bool get masked => _question == McQuestion.asking;

  ValueListenable<double> get playhead => _playhead;
  bool get playing => _playing;
  bool get reducedMotion => _reducedMotion;

  // ── Inputs ────────────────────────────────────────────────────────────────

  void _set(McConfig next) {
    if (next == _config) return;
    _config = next;
    _result = computeMulticast(next);
    _notify();
  }

  set streamMbps(double v) => _set(_config.copyWith(streamMbps: v));
  set packetBytes(int v) => _set(_config.copyWith(packetBytes: v));
  set band(McBand v) => _set(_config.copyWith(band: v));
  set basicRate(BasicRate v) => _set(_config.copyWith(basicRate: v));
  set listeners(int v) => _set(
    _config.copyWith(listeners: v.clamp(kMcMinListeners, kMcMaxListeners)),
  );
  set rates(ListenerRates v) => _set(_config.copyWith(rates: v));
  set dtimPeriod(int v) =>
      _set(_config.copyWith(dtimPeriod: v.clamp(kMcMinDtim, kMcMaxDtim)));
  set powerSave(bool v) => _set(_config.copyWith(powerSave: v));

  void applyPreset(StreamPreset p) =>
      _set(_config.copyWith(streamMbps: p.mbps, packetBytes: p.packetBytes));

  /// The preset the stream still matches, or null.
  StreamPreset? get preset {
    for (final StreamPreset p in StreamPreset.values) {
      if (p.mbps == _config.streamMbps &&
          p.packetBytes == _config.packetBytes) {
        return p;
      }
    }
    return null;
  }

  set view(McView v) {
    if (v == _view) return;
    _view = v;
    _notify();
  }

  /// Up and Down arrows: the basic rate one step faster or slower, among the
  /// rates the band offers.
  void nudgeBasicRate(int delta) {
    final List<BasicRate> rates = BasicRate.on(_config.band);
    final int at = rates.indexOf(_config.basicRate);
    basicRate = rates[(at + delta).clamp(0, rates.length - 1)];
  }

  // ── Predict, then reveal ──────────────────────────────────────────────────

  /// Loads the question's scenario and hides the answers.
  void ask() {
    _config = kMcQuestionConfig;
    _result = computeMulticast(_config);
    _view = McView.multicast;
    _question = McQuestion.asking;
    _guess = null;
    _notify();
  }

  set guess(McGuess? g) {
    if (g == _guess) return;
    _guess = g;
    _notify();
  }

  void reveal() {
    if (_question != McQuestion.asking) return;
    _question = McQuestion.revealed;
    _notify();
    replay();
  }

  /// Closes the question card.
  void dismissQuestion() {
    if (_question == McQuestion.idle) return;
    _question = McQuestion.idle;
    _guess = null;
    _notify();
  }

  // ── Playhead ──────────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. With it on,
  /// the second is drawn complete and never sweeps by itself. Does not
  /// notify (it is set during a build).
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) {
      _stop();
      _playhead.value = 1;
    }
  }

  /// Sweeps from the start, or draws the second complete with reduced
  /// motion on.
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

  /// Right arrow: pause and move the playhead to the next beacon.
  void stepBeacon() {
    _stop();
    final double atUs =
        (_playhead.value >= 1 ? 0 : _playhead.value) * kMcWindowUs;
    final double next =
        ((atUs / kMcBeaconIntervalUs).floor() + 1) * kMcBeaconIntervalUs;
    _playhead.value = (next / kMcWindowUs).clamp(0.0, 1.0);
    _notify();
  }

  /// R: an empty second, paused, ready to play or step.
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
        _playFrom + elapsed.inMicroseconds / kMcSweepDuration.inMicroseconds;
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
    step: stepBeacon,
    reset: resetSweep,
    sliderDown: () => nudgeBasicRate(-1),
    sliderUp: () => nudgeBasicRate(1),
    sliderLabel: 'Basic rate',
  );

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final McConfig c = _config;
    final McResult r = _result;
    String pct(double s) => '${(s * 100).toStringAsFixed(1)}%';
    final StringBuffer b = StringBuffer()
      ..writeln('Multicast at the Basic Rate (WLAN Pros Toolbox)')
      ..writeln(
        'Stream: ${fmtMbps(c.streamMbps)} Mb/s in ${c.packetBytes}-byte '
        'packets (${r.packetsPerSecond.toStringAsFixed(1)} per second)',
      )
      ..writeln(
        'Band ${c.band.label}, basic rate ${c.basicRate.label} '
        '(${c.basicRate.phyLabel})',
      )
      ..writeln(
        'Multicast: ${r.multicast.totalUs.toStringAsFixed(1)} µs per packet, '
        'no acknowledgment; ${pct(r.multicastShare)} of the channel',
      )
      ..writeln(
        'Converted to unicast for ${c.listeners} listener'
        '${c.listeners == 1 ? '' : 's'} (${c.rates.label}): '
        '${(r.unicastPerPacketTenths / 10).toStringAsFixed(1)} µs per packet; '
        '${pct(r.unicastShare)} of the channel',
      )
      ..writeln(
        r.breakEven == null
            ? 'Break-even: unicast stays cheaper up to $kMcMaxListeners '
                  'listeners'
            : 'Break-even: ${r.breakEven} listener'
                  '${r.breakEven == 1 ? '' : 's'}',
      )
      ..writeln(
        c.powerSave
            ? 'DTIM (delivery traffic indication message) period '
                  '${c.dtimPeriod}: multicast held up to '
                  '${(r.maxDtimDelayUs / 1000).toStringAsFixed(1)} ms'
            : 'Nobody in power save: multicast is not held',
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

/// 4 -> "4", 0.064 -> "0.064", 0.25 -> "0.25".
String fmtMbps(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  String s = v.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s;
}
