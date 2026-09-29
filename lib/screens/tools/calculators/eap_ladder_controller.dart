// State for the Wi-Fi Classroom 802.1X and EAP Ladder (eap-ladder).
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
// MODES (spec 21b, 2026-09-26). Authenticate is the original ladder and its
// state (config, sequence, skipped, current) is exactly as before. Roam is
// the ladder's second mode. Join is its own tool, Association, Frame
// by Frame (join-ladder, Keith 2026-09-26), which constructs this controller in Join
// mode so it shares the engine rather than copying it. Join and Roam share
// one JrConfig and one JrSequence; playback, Step, Back and Reset
// move the same counter through whichever ladder the mode shows. A student
// can tap a sent message in Join or Roam to inspect what it carries.
//
// THE CLOCK. The Ticker is constructed here directly, not from a widget's
// TickerProvider: a route under the presenter route is muted, and playback
// must keep going when the presenter layout opens over the phone screen
// (spec 00). [vsync] is accepted and unused so older callers still compile.

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../services/wifi_lab/join_roam.dart';
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
  EapLadderController({
    TickerProvider? vsync,
    LadderConfig? initial,
    LadderMode mode = LadderMode.authenticate,
    JrConfig? initialJr,
  }) : _config = initial ?? const LadderConfig(),
       _jrConfig = initialJr ?? const JrConfig() {
    _mode = mode;
    _sequence = buildLadder(_config);
    _skipped = skippedVersusFull(_sequence);
    _rebuildJr();
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

  LadderMode _mode = LadderMode.authenticate;
  JrConfig _jrConfig;
  late JrSequence _jr;
  RoamSkipped? _roamSkipped;

  /// A sent Join or Roam message the student tapped, shown in the caption
  /// instead of the latest; null for the latest.
  int? _inspected;

  // ── Read side ─────────────────────────────────────────────────────────────

  LadderMode get mode => _mode;

  /// Join or Roam (spec 21b), as opposed to the original ladder.
  bool get isJr => _mode != LadderMode.authenticate;

  JrConfig get jrConfig => _jrConfig;

  /// The Join or Roam ladder for the current mode (built for Join while the
  /// mode is Authenticate).
  JrSequence get jr => _jr;

  /// What the roam method skipped (Roam mode only).
  RoamSkipped? get roamSkipped => _roamSkipped;

  int get _length => isJr ? _jr.length : _sequence.length;

  LadderConfig get config => _config;
  LadderSequence get sequence => _sequence;
  LadderSkipped get skipped => _skipped;
  LadderSpeed get speed => _speed;
  bool get playing => _playing;

  /// Messages sent so far (0 to the ladder's length).
  int get shown => _shown;

  bool get atStart => _shown == 0;
  bool get atEnd => _shown >= _length;

  /// Messages in the ladder on show.
  int get length => _length;

  /// The message sent most recently, or null before the first. Authenticate
  /// mode only; Join and Roam read [currentJr].
  LadderMessage? get current =>
      _shown == 0 || isJr ? null : _sequence.messages[_shown - 1];

  /// The Join or Roam message sent most recently, or null.
  JrMessage? get currentJr =>
      _shown == 0 || !isJr ? null : _jr.messages[_shown - 1];

  /// Index of the message the caption shows: the tapped one, else the
  /// latest; -1 before the first.
  int get captionIndex => _inspected ?? _shown - 1;

  /// Whether the caption shows a tapped message rather than the latest.
  bool get inspecting => _inspected != null;

  /// The Join or Roam message the caption shows.
  JrMessage? get captionJr {
    if (!isJr) return null;
    final int i = captionIndex;
    return i < 0 ? null : _jr.messages[i];
  }

  /// Whether [milestone] has been reached at the current step.
  bool reached(LadderMilestone milestone) {
    final int i = isJr
        ? _jr.indexOfMilestone(milestone)
        : _sequence.indexOfMilestone(milestone);
    return i >= 0 && i < _shown;
  }

  /// Shows sent message [index] in the caption (Join and Roam). Tapping the
  /// one already shown, or the latest, goes back to following the latest.
  void inspect(int index) {
    if (!isJr || index < 0 || index >= _shown) return;
    _inspected = (index == _inspected || index == _shown - 1) ? null : index;
    notifyListeners();
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  void togglePlay() {
    if (_playing) {
      _pause();
    } else {
      if (atEnd) _shown = 0;
      _inspected = null;
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
    _inspected = null;
    if (!atEnd) _shown += 1;
    notifyListeners();
  }

  void back() {
    _pause();
    _inspected = null;
    if (!atStart) _shown -= 1;
    notifyListeners();
  }

  void reset() {
    _pause();
    _inspected = null;
    _shown = 0;
    notifyListeners();
  }

  void showAll() {
    _pause();
    _inspected = null;
    _shown = _length;
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
    _inspected = null;
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
    if (isJr) {
      if (!jrCertificateMatters) return;
      jrConfig = _jrConfig.copyWith(
        certFragments: _jrConfig.certFragments + dir.sign,
      );
      return;
    }
    if (!_config.certificateMatters) return;
    certFragments = (_config.certFragments + dir.sign)
        .clamp(kMinCertFragments, kMaxCertFragments)
        .toDouble();
  }

  /// The presenter's Up and Down: the passive dwell in Join (the setting
  /// that makes a scan miss a beacon), the certificate size otherwise.
  void _nudgeMain(int dir) {
    if (_mode == LadderMode.join) {
      jrConfig = _jrConfig.copyWith(
        passiveDwellMs: _jrConfig.passiveDwellMs + 10 * dir.sign,
      );
      return;
    }
    nudgeCertFragments(dir);
  }

  /// Whether the Join or Roam ladder sends a certificate (EAP runs).
  bool get jrCertificateMatters => _mode == LadderMode.roam
      ? _jrConfig.roamMethod == JrRoamMethod.full
      : _jrConfig.effectiveSecurity == JrSecurity.dot1x;

  /// Presenter keys (spec 00): Space plays or pauses, Right steps one
  /// message, Left takes one back, R resets, Up and Down change the
  /// certificate size (the passive dwell in Join).
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    step: step,
    reset: reset,
    sliderDown: () => _nudgeMain(-1),
    sliderUp: () => _nudgeMain(1),
    sliderLabel: _mode == LadderMode.join
        ? 'Passive dwell'
        : 'Certificate size',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.arrowLeft,
        keyLabel: 'Left arrow',
        description: 'Back one message',
        onPressed: back,
      ),
    ],
  );

  // ── Join and Roam ─────────────────────────────────────────────────────────

  /// Switches mode. Each mode's ladder starts again from the top.
  set mode(LadderMode m) {
    if (m == _mode) return;
    _pause();
    _mode = m;
    _inspected = null;
    _rebuildJr();
    _shown = 0;
    notifyListeners();
  }

  /// Applies a Join or Roam setting. Same rule as [_apply]: a new ladder
  /// starts from the top unless the whole previous one was on show; a
  /// timing-only change keeps the place.
  set jrConfig(JrConfig next) {
    if (next == _jrConfig) return;
    final bool wasAll = atEnd && _shown > 0;
    final JrSequence before = _jr;
    _jrConfig = next;
    _rebuildJr();
    if (isJr && !_sameJr(before, _jr)) {
      _pause();
      _inspected = null;
      _shown = wasAll ? _jr.length : 0;
    }
    notifyListeners();
  }

  void _rebuildJr() {
    _jr = _mode == LadderMode.roam
        ? buildRoam(_jrConfig)
        : buildJoin(_jrConfig);
    _roamSkipped = _mode == LadderMode.roam ? roamSkippedVersusFull(_jr) : null;
  }

  static bool _sameJr(JrSequence a, JrSequence b) {
    String key(JrMessage m) =>
        '${m.from.name}|${m.to.name}|${m.label}|${m.contents}|'
        '${m.pmfProtected}|${m.encrypted}';
    return listEquals(
      a.messages.map(key).toList(),
      b.messages.map(key).toList(),
    );
  }

  /// Test seam: show a hand-built ladder (the shared failure marker's
  /// drawing tests), from the top.
  @visibleForTesting
  set debugSequence(LadderSequence s) {
    _pause();
    _sequence = s;
    _skipped = skippedVersusFull(s);
    _shown = 0;
    notifyListeners();
  }

  set method(LadderMethod m) => _apply(_config.copyWith(method: m));
  set inner(LadderInner i) => _apply(_config.copyWith(inner: i));
  set roam(LadderRoam r) => _apply(_config.copyWith(roam: r));
  set certFragments(double v) =>
      _apply(_config.copyWith(certFragments: v.round()));
  set radiusRttMs(double v) =>
      _apply(_config.copyWith(radiusRttMs: v.roundToDouble()));

  // ── Copy ──────────────────────────────────────────────────────────────────

  String copyText() {
    if (isJr) return _copyJr();
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

  String _copyJr() {
    final JrSequence s = _jr;
    final JrConfig c = _jrConfig;
    final bool roam = _mode == LadderMode.roam;
    final StringBuffer b = StringBuffer()
      ..writeln(
        roam
            ? '802.1X and EAP Ladder, Roam (WLAN Pros Toolbox)'
            : 'Association, Frame by Frame (WLAN Pros Toolbox)',
      )
      ..writeln(
        roam
            ? '${c.roamMethod.label}, ${c.band.label}, '
                  '${c.scanType.label.toLowerCase()} scan'
            : '${s.security.label}, ${c.band.label}, '
                  '${c.scanType.label.toLowerCase()} scan, '
                  '${c.addressCheck.label}',
      )
      ..writeln();
    for (int i = 0; i < s.length; i++) {
      final JrMessage m = s.messages[i];
      final String via = m.via == null ? '' : ' via ${m.via!.label}';
      final String contents = m.contents.isEmpty ? '' : ': ${m.contents}';
      final String marks = <String>[
        if (m.encrypted) 'encrypted',
        if (m.pmfProtected) 'PMF protected',
        if (m.missed) 'missed',
      ].join(', ');
      b.writeln(
        '${i + 1}. ${m.from.label} -> ${m.to.label}$via '
        '(${m.kind.frameClass.label.toLowerCase()}) ${m.label}$contents'
        '${marks.isEmpty ? '' : ' [$marks]'}',
      );
      if (m.milestoneText != null) b.writeln('   ${m.milestoneText}');
    }
    b
      ..writeln()
      ..writeln(
        'Over the air: ${s.airCount} frames (${s.managementCount} '
        'management, ${s.dataCount} data)',
      )
      ..writeln('On the wire: ${s.wireCount} packets');
    if (roam) {
      final Map<RoamBar, double> t = s.roamTotals;
      for (final RoamBar bar in RoamBar.values) {
        b.writeln('${bar.label}: ${formatJrMs(t[bar]!)}');
      }
    } else {
      final Map<JrClock, double> t = s.clockTotals;
      for (final JrClock clock in JrClock.joinClocks) {
        if (t[clock]! == 0) continue;
        b.writeln('${clock.label}: ${formatJrMs(t[clock]!)}');
      }
    }
    b.writeln('Total (illustrative inputs): ${formatJrMs(s.totalMs)}');
    for (final String line in _roamSkipped?.lines ?? const <String>[]) {
      b.writeln('Skipped versus full 802.1X: $line');
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
