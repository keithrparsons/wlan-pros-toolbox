// State for the Wi-Fi Classroom tool "Why a Long Wi-Fi Password Matters More
// on WPA2" (wpa2-password).
//
// One ChangeNotifier over an immutable WpConfig (the pure model in
// lib/services/wifi_lab/wpa2_password_model.dart), plus the guess counter,
// the play state and the predict-then-reveal flag. The stage and the controls
// are separate views over this one object: stacked on a phone, side by side
// on a wide window, and in the full-screen presenter layout, which uses this
// same object (state is shared, not copied).
//
// THE CLOCK. Play tries guesses one after another so the class can watch
// where each guess goes. The on-screen pace is for the eye only and says so:
// an offline guess is drawn as a short loop inside the attacker's computer,
// a WPA3 guess as a longer trip to the AP and back. No rate is computed or
// shown anywhere. The Ticker is built here, not from a widget's
// TickerProvider, because the route under the presenter is muted and the
// guessing must keep going while the presenter shows it (same as Band
// Steering).
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/wpa2_password_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';

export '../../../services/wifi_lab/wpa2_password_model.dart';

/// How long one guess takes ON SCREEN. For the eye only; not a rate.
const Duration kWpOfflineGuessDrawn = Duration(milliseconds: 700);
const Duration kWpLiveGuessDrawn = Duration(milliseconds: 1600);

class Wpa2PasswordController extends ChangeNotifier {
  Wpa2PasswordController({WpConfig initial = const WpConfig()})
    : _config = initial {
    _ticker = Ticker(_onTick, debugLabel: 'wpa2-password-guesses');
  }

  WpConfig _config;
  int _guesses = 0;
  bool _revealed = false;

  late final Ticker _ticker;
  bool _playing = false;
  bool _oneShot = false;
  int _playFrom = 0;
  bool _reducedMotion = false;
  bool _disposed = false;

  /// 0 to 1: where the guess now being drawn is on its path. Negative when
  /// no guess is in flight (nothing drawn).
  final ValueNotifier<double> _phase = ValueNotifier<double>(-1);

  // ── Read side ──────────────────────────────────────────────────────────

  WpConfig get config => _config;

  /// Guesses tried since the last reset or change of security.
  int get guesses => _guesses;

  /// Failed attempts the AP has logged. Zero whenever guessing is offline.
  int get apFailedAttempts => _config.apFailedAttempts(_guesses);

  bool get playing => _playing;
  bool get revealed => _revealed;
  bool get reducedMotion => _reducedMotion;

  /// Repaints the moving guess without rebuilding the cards.
  ValueListenable<double> get phase => _phase;

  Duration get _drawn =>
      _config.security.guessesAtAp ? kWpLiveGuessDrawn : kWpOfflineGuessDrawn;

  // ── Inputs ─────────────────────────────────────────────────────────────

  /// A new security setting is a new network: the counters start over.
  void setSecurity(WpSecurity s) {
    if (s == _config.security) return;
    _stop();
    _config = _config.withSecurity(s);
    _guesses = 0;
    _phase.value = -1;
    _notify();
  }

  void setLength(int n) {
    final WpConfig next = _config.withLength(n);
    if (next == _config) return;
    _config = next;
    _notify();
  }

  void setCharset(WpCharset c) {
    if (c == _config.charset) return;
    _config = _config.withCharset(c);
    _notify();
  }

  void setRevealed(bool v) {
    _revealed = v;
    _notify();
  }

  void toggleReveal() => setRevealed(!_revealed);

  // ── Guessing ───────────────────────────────────────────────────────────

  /// The screen reports the platform's reduced-motion setting. Does not
  /// notify (it is set during a build). With reduced motion the counters
  /// still count; nothing moves.
  set reducedMotion(bool on) {
    if (on == _reducedMotion) return;
    _reducedMotion = on;
    if (on) _phase.value = -1;
  }

  /// Space: keep trying guesses, or stop.
  void togglePlay() {
    if (_playing) {
      _stop();
      _phase.value = -1;
      _notify();
      return;
    }
    _playing = true;
    _oneShot = false;
    _playFrom = _guesses;
    _guesses++;
    _restartTicker();
    _notify();
  }

  /// Right arrow: stop, and try exactly one guess.
  void guessOnce() {
    _stop();
    _guesses++;
    _oneShot = true;
    _restartTicker();
    _notify();
  }

  /// R: back to the defaults, nothing tried, the answer hidden.
  void reset() {
    _stop();
    _config = const WpConfig();
    _guesses = 0;
    _revealed = false;
    _phase.value = -1;
    _notify();
  }

  void _restartTicker() {
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _stop() {
    _playing = false;
    _oneShot = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final int d = _drawn.inMicroseconds;
    final int done = elapsed.inMicroseconds ~/ d;
    if (_oneShot) {
      if (done >= 1) {
        _stop();
        _phase.value = -1;
        _notify();
        return;
      }
      if (!_reducedMotion) _phase.value = elapsed.inMicroseconds / d;
      return;
    }
    if (!_playing) return;
    if (!_reducedMotion) {
      _phase.value = (elapsed.inMicroseconds % d) / d;
    }
    // By elapsed time, not by tick count: a dropped frame never slows it.
    final int target = _playFrom + 1 + done;
    if (target != _guesses) {
      _guesses = target;
      _notify();
    }
  }

  // ── Presenter keys ─────────────────────────────────────────────────────

  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    playPauseLabel: 'Keep guessing, or stop',
    step: guessOnce,
    stepLabel: 'Try one guess',
    reset: reset,
    sliderDown: () => setLength(_config.length - 1),
    sliderUp: () => setLength(_config.length + 1),
    sliderLabel: 'Password length',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.digit1,
        keyLabel: '1',
        description: 'WPA2-Personal',
        onPressed: () => setSecurity(WpSecurity.wpa2),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.digit2,
        keyLabel: '2',
        description: 'WPA3-Personal (SAE)',
        onPressed: () => setSecurity(WpSecurity.wpa3),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.digit3,
        keyLabel: '3',
        description: 'WPA3 transition mode',
        onPressed: () => setSecurity(WpSecurity.transition),
      ),
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Show or hide the prediction answer',
        onPressed: toggleReveal,
      ),
    ],
  );

  // ── Copy payload (GL-003 §8.16) ──────────────────────────────────────────

  String copyText() {
    final WpConfig c = _config;
    return <String>[
      'Why a Long Wi-Fi Password Matters More on WPA2',
      '${c.security.label}; a password of ${c.length} characters, '
          '${c.charset.phrase}',
      'Possible passwords: ${WpFormat.count(c.possiblePasswords)} '
          '(${c.charset.size}^${c.length}); each extra character multiplies '
          'this by ${c.perExtraCharacter}',
      'Where each guess is checked: ${c.guessPlace.label}',
      'What sets the pace: ${c.paceLabel}',
      'Does the AP see the guessing: '
          '${c.apSeesGuesses ? 'Yes, every wrong guess is a failed '
                    'authentication' : 'No'}',
      'Recorded traffic, if the password is learned later: '
          '${c.recordedTraffic}',
      'Guesses tried: ${WpFormat.integer(_guesses)}; failed attempts the AP '
          'logged: ${WpFormat.integer(apFailedAttempts)}',
      'Source: Wi-Fi Alliance, WPA3 Security Considerations, November 2019. '
          'No crack times: they depend on the attacker\'s hardware.',
    ].join('\n');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }
}
