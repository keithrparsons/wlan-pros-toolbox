// State for the Wi-Fi Lab 802.1X and EAP Ladder (eap-ladder).
//
// One ChangeNotifier holds the configuration, the built ladder and how many
// of its messages have been sent, so the two halves of the screen stay
// independent widgets: EapLadderStage (the three-lane ladder and the caption)
// and EapLadderControls (transport, readouts and settings) each listen to
// this one object. The phone layout stacks them; a presenter layout can
// place them side by side without either knowing about the other (spec 00).
//
// The ladder is rebuilt whole whenever a setting changes (at most a few dozen
// messages). Playback only moves a counter through it, one message per beat.
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: a route under the presenter route is muted, and playback
// must keep going when the presenter layout opens over the phone screen
// (spec 00). [vsync] is accepted and unused so older callers still compile.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../widgets/presenter/presenter_actions.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kEapLadderToolId = 'eap-ladder';

/// Playback pace: seconds per message.
enum LadderSpeed {
  slow('Slow', 1.6),
  normal('Normal', 0.9),
  fast('Fast', 0.4);

  const LadderSpeed(this.label, this.secondsPerMessage);

  final String label;
  final double secondsPerMessage;
}

class EapLadderController extends ChangeNotifier {
  EapLadderController({TickerProvider? vsync, LadderConfig? initial})
    : _config = initial ?? const LadderConfig() {
    _sequence = buildLadder(_config);
    _skipped = skippedVersusFull(_sequence);
    _ticker = Ticker(_onTick, debugLabel: 'eap-ladder');
  }

  LadderConfig _config;
  late LadderSequence _sequence;
  late LadderSkipped _skipped;
  late final Ticker _ticker;

  int _shown = 0;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;
  double _sinceBeat = 0;
  LadderSpeed _speed = LadderSpeed.normal;

  // ── Read side ─────────────────────────────────────────────────────────────

  LadderConfig get config => _config;
  LadderSequence get sequence => _sequence;
  LadderSkipped get skipped => _skipped;
  LadderSpeed get speed => _speed;
  bool get playing => _playing;

  /// Messages sent so far (0 to the ladder's length).
  int get shown => _shown;

  bool get atStart => _shown == 0;
  bool get atEnd => _shown >= _sequence.length;

  /// The message sent most recently, or null before the first.
  LadderMessage? get current =>
      _shown == 0 ? null : _sequence.messages[_shown - 1];

  /// Whether [milestone] has been reached at the current step.
  bool reached(LadderMilestone milestone) {
    final int i = _sequence.indexOfMilestone(milestone);
    return i >= 0 && i < _shown;
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  void togglePlay() {
    if (_playing) {
      _pause();
    } else {
      if (atEnd) _shown = 0;
      // The first message goes at once, so Play answers the press.
      _shown += 1;
      if (!atEnd) {
        _playing = true;
        _lastElapsed = Duration.zero;
        _sinceBeat = 0;
        _ticker.start();
      }
    }
    notifyListeners();
  }

  void _pause() {
    _playing = false;
    if (_ticker.isActive) _ticker.stop();
  }

  /// Pause without toggling (app backgrounded).
  void pause() {
    if (!_playing) return;
    _pause();
    notifyListeners();
  }

  void step() {
    _pause();
    if (!atEnd) _shown += 1;
    notifyListeners();
  }

  void back() {
    _pause();
    if (!atStart) _shown -= 1;
    notifyListeners();
  }

  void reset() {
    _pause();
    _shown = 0;
    notifyListeners();
  }

  void showAll() {
    _pause();
    _shown = _sequence.length;
    notifyListeners();
  }

  set speed(LadderSpeed s) {
    if (s == _speed) return;
    _speed = s;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    // A stalled frame cannot send more than one message.
    _sinceBeat += dt.clamp(0.0, _speed.secondsPerMessage);
    if (_sinceBeat < _speed.secondsPerMessage) return;
    _sinceBeat -= _speed.secondsPerMessage;
    _shown += 1;
    if (atEnd) _pause();
    notifyListeners();
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  /// Applies [next]. A new ladder starts again from the top unless the whole
  /// previous ladder was on show, in which case the new one is shown whole,
  /// so a class can flip between methods and compare.
  void _apply(LadderConfig next) {
    if (next == _config) return;
    final bool wasAll = atEnd;
    _config = next;
    final LadderSequence built = buildLadder(next);
    final bool sameShape = _sameMessages(built, _sequence);
    _sequence = built;
    _skipped = skippedVersusFull(built);
    if (!sameShape) {
      _pause();
      _shown = wasAll ? built.length : 0;
    }
    notifyListeners();
  }

  /// True when only a timing setting changed: same messages, same order.
  static bool _sameMessages(LadderSequence a, LadderSequence b) {
    String key(LadderMessage m) =>
        '${m.from.name}|${m.to.name}|${m.label}|${m.contents}';
    return listEquals(
      a.messages.map(key).toList(),
      b.messages.map(key).toList(),
    );
  }

  /// One more or one fewer certificate fragment, when the certificate is
  /// sent in this method and roam mode; otherwise nothing.
  void nudgeCertFragments(int dir) {
    if (!_config.certificateMatters) return;
    certFragments = (_config.certFragments + dir.sign)
        .clamp(kMinCertFragments, kMaxCertFragments)
        .toDouble();
  }

  /// Presenter keys (spec 00): Space plays or pauses, Right steps one
  /// message, Left takes one back, R resets, Up and Down change the
  /// certificate size.
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: step,
    reset: reset,
    sliderDown: () => nudgeCertFragments(-1),
    sliderUp: () => nudgeCertFragments(1),
    sliderLabel: 'Certificate size',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Back one message',
        onPressed: back,
      ),
    ],
  );

  set method(LadderMethod m) => _apply(_config.copyWith(method: m));
  set inner(LadderInner i) => _apply(_config.copyWith(inner: i));
  set roam(LadderRoam r) => _apply(_config.copyWith(roam: r));
  set certFragments(double v) =>
      _apply(_config.copyWith(certFragments: v.round()));
  set radiusRttMs(double v) =>
      _apply(_config.copyWith(radiusRttMs: v.roundToDouble()));

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    final LadderSequence s = _sequence;
    final LadderConfig c = _config;
    final StringBuffer b = StringBuffer()
      ..writeln('802.1X and EAP Ladder (WLAN Pros Toolbox)')
      ..writeln(
        '${c.method.label}'
        '${c.method == LadderMethod.eapTtls ? ', inner ${c.inner.label}' : ''}'
        ', ${c.roam.label}'
        '${c.certificateMatters ? ', certificate ${c.certFragments} fragment${c.certFragments == 1 ? '' : 's'} per message' : ''}',
      )
      ..writeln();
    for (int i = 0; i < s.length; i++) {
      final LadderMessage m = s.messages[i];
      final String contents = m.contents.isEmpty ? '' : ': ${m.contents}';
      b.writeln(
        '${i + 1}. ${m.from.label} -> ${m.to.label} '
        '(${m.leg == LadderLeg.air ? 'air' : 'wire'}) ${m.label}$contents',
      );
      if (m.milestoneText != null) b.writeln('   ${m.milestoneText}');
    }
    b
      ..writeln()
      ..writeln('Over the air: ${s.airCount} frames')
      ..writeln('On the wire: ${s.wireCount} RADIUS messages')
      ..writeln('RADIUS round trips: ${s.radiusRoundTrips}')
      ..writeln(
        'Estimated time after the scan (illustrative): '
        '${formatLadderMs(s.estimatedMs)}'
        '${s.usesRadius ? ' at ${c.radiusRttMs.round()} ms per RADIUS round trip' : ''}',
      );
    for (final String line in _skipped.lines) {
      b.writeln('Skipped versus full: $line');
    }
    return b.toString().trimRight();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

/// "12 ms", "1.2 s".
String formatLadderMs(double ms) {
  if (ms < 1000) return '${ms.round()} ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}
