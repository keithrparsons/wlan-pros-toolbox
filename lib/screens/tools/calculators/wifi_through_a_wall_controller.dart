// State for "Wi-Fi Through a Wall" (wifi-through-a-wall): one ChangeNotifier
// the screen creates and disposes, shared by the phone layout and the
// presenter layout (lib/widgets/presenter/), so a wall set on the normal
// screen is the wall the room sees.
//
// It holds the wall (WallConfig), the play state, the optional "Show
// wavelength inside the material" view, and the wave's phase with the Ticker
// that advances it. THE CLOCK is constructed here directly, not from a
// widget's TickerProvider: a route under the presenter route is muted, and a
// wave started on the phone screen must keep moving when the instructor
// presents it. The painter's phasor cache is NOT here: each stage view owns
// its own, because the phone screen stays mounted under the presenter.
//
// FREQUENCY NEVER CHANGES (Keith, 2026-09-25). Nothing here draws; the
// stage's WallWaveProfile keeps the drawn wavelength fixed. This object only
// decides which phase a still frame freezes at (the one with the most field
// on screen, so a paused wave never shows a flat zero crossing).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/complex.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../widgets/presenter/presenter_actions.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'wifi_through_a_wall_parts.dart';
import 'wifi_through_a_wall_stage.dart' show WallWaveProfile;

/// The drawing is slowed down to one cycle in this many seconds.
const double kWallSecondsPerCycle = 2;

class WallSlabController extends ChangeNotifier {
  WallSlabController({this.initial = const WallConfig()})
    : _config = initial,
      _result = initial.result {
    _ticker = Ticker(_onTick, debugLabel: 'wifi-through-a-wall');
    _phase = _brightestPhase();
  }

  /// The wall the tool opened with; R in presenter mode returns to it.
  final WallConfig initial;

  WallConfig _config;
  SlabResult _result;
  bool _playing = false;
  bool _showMaterialWavelength = false;
  UnitSystem _units = UnitSystem.metric;
  bool _motionDecided = false;
  double _phase = 0;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Read-only state ────────────────────────────────────────────────────

  WallConfig get config => _config;

  /// One result per wall, so the painter's phasor cache survives the
  /// animation frames (which change only the phase).
  SlabResult get result => _result;

  bool get playing => _playing;

  /// Draw the true (shorter) wavelength inside the material. Off by default:
  /// a shorter drawn wavelength reads as a higher frequency, which is wrong.
  bool get showMaterialWavelength => _showMaterialWavelength;

  /// The wave's phase, radians, 0 to 2 pi.
  double get phase => _phase;

  /// Length units on screen. The wall stays in mm.
  UnitSystem get units => _units;

  void setUnits(UnitSystem u) {
    if (u == _units) return;
    _units = u;
    _notify();
  }

  // ── Mutators ───────────────────────────────────────────────────────────

  /// Sets the wall. While paused, the still frame moves to the phase with
  /// the most field on screen; while playing, the phase is left alone so the
  /// animation does not jump.
  void setConfig(WallConfig c) {
    if (c == _config) return;
    _config = c;
    _result = c.result;
    if (!_playing) _phase = _brightestPhase();
    _notify();
  }

  void setShowMaterialWavelength(bool v) {
    if (v == _showMaterialWavelength) return;
    _showMaterialWavelength = v;
    if (!_playing) _phase = _brightestPhase();
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

  /// Back to the opening wall, paused view intact (presenter R).
  void reset() => setConfig(initial);

  /// One presenter key press on the thickness: a fortieth of the 1 to
  /// 100 cm log range (the slider's scale), rounded as the slider rounds, in
  /// the unit on screen.
  void stepThickness(int direction) {
    final double logMin = _log10(kWallMinMm);
    final double logMax = _log10(kWallMaxMm);
    final double p =
        ((_log10(_config.thicknessMm) - logMin) / (logMax - logMin) +
                direction / 40)
        .clamp(0.0, 1.0);
    final LengthFormat f = LengthFormat(_units);
    double mm = f.snapMm(math.pow(10, logMin + p * (logMax - logMin)).toDouble());
    // Always move at least one display step, so a press is never lost to
    // rounding near 1 cm.
    if ((mm - _config.thicknessMm).abs() < 1e-9) {
      // One displayed step: 0.01 or 0.1 cm, 0.01 or 0.1 in.
      final double shown = f.smallValueFromMm(mm);
      final double step = shown < 2 ? 0.01 : 0.1;
      mm = f.smallToMm(shown + direction * step);
    }
    setConfig(_config.copyWith(thicknessMm: mm.clamp(kWallMinMm, kWallMaxMm)));
  }

  /// Presenter keyboard: Space plays or pauses the wave, R returns to the
  /// opening wall, Up and Down change the thickness.
  PresenterActions get presenterActions => PresenterActions(
    playPause: togglePlay,
    reset: reset,
    sliderDown: () => stepThickness(-1),
    sliderUp: () => stepThickness(1),
    sliderLabel: 'Wall thickness',
  );

  // ── Clock ──────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _phase = (_phase + 2 * math.pi * dt / kWallSecondsPerCycle) % (2 * math.pi);
    _notify();
  }

  /// Phase maximizing the summed squared drawn field Re{f·e^(j·phase)}^2:
  /// with a = Re f, b = Im f, the sum is A·cos^2 - 2C·cos·sin + B·sin^2,
  /// which peaks at phase = atan2(-2C, A - B) / 2.
  double _brightestPhase() {
    final WallWaveProfile p = WallWaveProfile(
      _result,
      400,
      showMaterialWavelength: _showMaterialWavelength,
    );
    double a2 = 0, b2 = 0, ab = 0;
    for (final Complex f in p.sample(241)) {
      a2 += f.re * f.re;
      b2 += f.im * f.im;
      ab += f.re * f.im;
    }
    return 0.5 * math.atan2(-2 * ab, a2 - b2);
  }

  static double _log10(double v) => math.log(v) / math.ln10;

  // ── Copy payload (GL-003 §8.16) ────────────────────────────────────────

  String copyText() {
    final WallConfig c = _config;
    final SlabResult r = _result;
    final StringBuffer b = StringBuffer()
      ..writeln('Wi-Fi Through a Wall (ITU-R P.2040-4 model)')
      ..writeln(
        '${c.material.label}, ${fmtThickness(c.thicknessMm, _units)}, '
        '${c.angleDeg.toStringAsFixed(0)} deg, '
        '${c.polarization.name.toUpperCase()}',
      )
      ..writeln('Channel ${c.channel}, ${c.centerMHz} MHz')
      ..writeln(
        'Transmission loss: ${fmtLossDb(r.transmissionLossDb)} '
        '(absorption ${fmtLossDb(r.absorptionDb)}, reflection '
        '${fmtLossDb(r.reflectionPartDb)})',
      );
    if (r.reflectedPower > 0) {
      b.writeln(
        'Reflection: ${fmt1(r.reflectionDb)} dB '
        '(${fmtPct(r.reflectedPower)} of the power)',
      );
    }
    b
      ..writeln('Wavelength in air: ${fmtLength(r.props.lambdaAir, _units)}')
      ..writeln('Same wall by band:');
    for (final double f in kComparisonGhz) {
      b.writeln('  $f GHz: ${fmtLossDb(c.resultAt(f).transmissionLossDb)}');
    }
    b.writeln(
      'Model values, not measurements. Free-space loss is not included.',
    );
    return b.toString().trimRight();
  }
}
