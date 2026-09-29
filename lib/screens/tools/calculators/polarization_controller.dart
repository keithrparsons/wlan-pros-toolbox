// State for "Polarization" (polarization): one ChangeNotifier the screen
// creates and disposes, shared by the phone layout and the presenter layout,
// so a preset picked on the phone screen is the one the room sees.
//
// It holds the wave (PolarizationState), the preset, the components switch,
// the play state and phase with the Ticker that advances it, and the orbit
// camera. THE CLOCK is constructed here directly, not from a widget's
// TickerProvider, for the reason Wi-Fi Through a Wall gives: a route under
// the presenter route is muted, and a wave started on the phone screen must
// keep moving when the instructor presents it.
//
// FREQUENCY NEVER CHANGES (Keith, 2026-09-25): the phase advances at one
// fixed rate for every preset; only the shape of the field changes.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../../services/wifi_lab/polarization_model.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import 'polarization_parts.dart';
import 'wifi_lab_orbit.dart';

class PolarizationController extends ChangeNotifier {
  PolarizationController({this.initialPreset = PolarizationPreset.vertical})
    : _preset = initialPreset,
      _state = initialPreset.state {
    _ticker = Ticker(_onTick, debugLabel: 'polarization');
  }

  /// The camera the tool opens with: the axis runs left to right and toward
  /// the viewer, seen a little from above, so the end frame shows its face.
  static const OrbitView initialView = OrbitView(yawDeg: 58, pitchDeg: 20);

  /// The preset the tool opened with; R returns to it.
  final PolarizationPreset initialPreset;

  PolarizationPreset _preset;
  PolarizationState _state;
  bool _showComponents = false;
  bool _playing = false;
  bool _motionDecided = false;

  /// A sixth of a cycle in: the opening still frame shows the field
  /// already built along the axis rather than a zero at the near end.
  double _phase = math.pi / 3;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _disposed = false;

  /// The camera. A notifier of its own, so a drag repaints the 3D without
  /// rebuilding the controls.
  final ValueNotifier<OrbitView> view = ValueNotifier<OrbitView>(initialView);

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    view.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Read-only state ────────────────────────────────────────────────────

  PolarizationState get state => _state;
  PolarizationPreset get preset => _preset;
  bool get showComponents => _showComponents;
  bool get playing => _playing;

  /// The wave phase wt, radians, 0 to 2 pi.
  double get phase => _phase;

  // ── Mutators ───────────────────────────────────────────────────────────

  void setPreset(PolarizationPreset p) {
    if (p == PolarizationPreset.custom) {
      // Custom keeps the current field; it only names it.
      if (_preset == p) return;
      _preset = p;
      _notify();
      return;
    }
    if (p == _preset && _state == p.state) return;
    _preset = p;
    _state = p.state;
    _notify();
  }

  /// One press of P (or Up): the next named preset, wrapping round. From
  /// Custom it starts again at the first.
  void cyclePreset([int direction = 1]) {
    const List<PolarizationPreset> all = PolarizationPreset.named;
    final int i = all.indexOf(_preset);
    final int next = i < 0
        ? (direction > 0 ? 0 : all.length - 1)
        : (i + direction) % all.length;
    setPreset(all[next]);
  }

  /// A slider moved: the field changes and the preset follows it (a named
  /// preset when the sliders land exactly on one, else Custom).
  void setField(PolarizationState s) {
    if (s == _state) return;
    _state = s;
    _preset = s.matchingPreset;
    _notify();
  }

  void setShowComponents(bool v) {
    if (v == _showComponents) return;
    _showComponents = v;
    _notify();
  }

  void setPlaying(bool p) {
    if (p == _playing) return;
    _playing = p;
    if (p) {
      _last = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
    _notify();
  }

  void togglePlay() => setPlaying(!_playing);

  /// Animate on open only when reduced motion is off (GL-003 §8.8). Runs
  /// once; later calls do nothing, so a rebuild never restarts the wave.
  void decideMotion({required bool reduceMotion}) {
    if (_motionDecided) return;
    _motionDecided = true;
    setPlaying(!reduceMotion);
  }

  void resetView() => view.value = initialView;

  /// Presenter R: the opening preset and the opening camera.
  void reset() {
    resetView();
    _preset = initialPreset;
    _state = initialPreset.state;
    _notify();
  }

  /// Presenter keyboard: Space plays or pauses, P and Up step to the next
  /// preset, Down to the previous, R resets the preset and the view. P is a
  /// letter outside the shell's shared set (Space, Right, R, F, Esc, ?, the
  /// arrows and brackets).
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    reset: reset,
    sliderDown: () => cyclePreset(-1),
    sliderUp: () => cyclePreset(1),
    sliderLabel: 'Polarization',
    extra: <PresenterExtraKey>[
      PresenterExtraKey(
        key: LogicalKeyboardKey.keyP,
        keyLabel: 'P',
        description: 'Next polarization',
        onPressed: () => cyclePreset(1),
      ),
    ],
  );

  // ── Clock ──────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _phase =
        (_phase + 2 * math.pi * dt / kPolarizationSecondsPerCycle) %
        (2 * math.pi);
    _notify();
  }

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final PolarizationState s = _state;
    final StringBuffer b = StringBuffer()
      ..writeln('Polarization')
      ..writeln('Polarization: ${polarizationName(s)}')
      ..writeln('The tip of the field traces: ${s.kind.traces}')
      ..writeln('Axial ratio: ${fmtAxialRatio(s)}')
      ..writeln('Long axis: ${fmtTilt(s)}')
      ..writeln(
        'Horizontal amplitude ${fmtAmp(s.ax)}, vertical amplitude '
        '${fmtAmp(s.ay)}, phase difference ${fmtPhase(s.deltaDeg)}',
      )
      ..writeln(
        'E(z,t) = Ax cos(wt - kz) (horizontal) + Ay cos(wt - kz + delta) '
        '(vertical)',
      )
      ..writeln(
        'View after EMANIM Classic by Andras Szilagyi (public domain).',
      );
    return b.toString().trimRight();
  }
}
