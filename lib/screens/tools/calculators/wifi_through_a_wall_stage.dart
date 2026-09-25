// The stage for "Wi-Fi Through a Wall": the wave drawn along the wall's
// normal, animated in phase. A self-contained widget that takes the model
// state (a WallConfig) and the play state; it holds no inputs of its own, so
// a presenter layout can place it beside WallSlabControls unchanged.
//
// What is drawn, left to right, at true scale:
//   - in front of the wall: incident plus reflected, E = e^(-jkx) + R e^(jkx);
//     its envelope shows the standing-wave ripple, nodes lambda/2 apart;
//   - inside: the wave with lambda/sqrt(e') and exponential decay, including
//     the part bounced off the back face;
//   - behind: the transmitted wave, amplitude |T|.
// The field is the tangential E; SlabResult.fieldAt owns that math.
//
// MOTION (GL-003 §8.8): the phase advances on a Ticker, one cycle every
// [_kSecondsPerCycle] seconds. It starts running only when reduced motion is
// OFF; with reduced motion on, the stage is frozen and says so, and Play still
// works because the user starts it. A Pause control is always offered (WCAG
// 2.2.2).
//
// THEME: lime (textAccent) is the wave, the one quantity the stage is about;
// the envelope and reference lines are neutral; the wall is a surface step.
// No status hues: nothing here is a verdict.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../services/wifi_lab/complex.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import 'wifi_through_a_wall_parts.dart';

/// The drawing is slowed down to one cycle in this many seconds.
const double _kSecondsPerCycle = 2;

/// Air shown on each side of the wall, in free-space wavelengths.
const double _kAirWavelengths = 1.5;

/// Smallest drawn wall width, px, so a 1 mm sheet is still visible.
const double _kMinWallPx = 3;

class WallSlabStage extends StatefulWidget {
  const WallSlabStage({
    super.key,
    required this.config,
    required this.playing,
    required this.onPlayingChanged,
    this.plotHeight = 200,
  });

  final WallConfig config;

  /// Whether the phase is advancing.
  final bool playing;
  final ValueChanged<bool> onPlayingChanged;

  /// Plot height, px. A presenter layout can pass more.
  final double plotHeight;

  @override
  State<WallSlabStage> createState() => _WallSlabStageState();
}

class _WallSlabStageState extends State<WallSlabStage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _phase = 0;
  Duration _last = Duration.zero;

  // One result per config, so the painter's phasor cache survives the
  // animation frames (which rebuild without changing the config).
  WallConfig? _resultFor;
  late SlabResult _result;
  final WallPhasorCache _cache = WallPhasorCache();

  SlabResult get _current {
    if (_resultFor != widget.config) {
      _result = widget.config.result;
      _resultFor = widget.config;
      // A still frame should show the wave, not a zero crossing: in front of
      // metal the standing wave is flat at phase 0. While paused, freeze at
      // the phase with the most field on screen. While playing, leave the
      // phase alone so the animation does not jump.
      if (!widget.playing) _phase = _brightestPhase(_result);
    }
    return _result;
  }

  /// Phase maximizing the summed squared field Re{f·e^(j·phase)}^2 over the
  /// drawn span: with a = Re f, b = Im f, the sum is
  /// A·cos^2 - 2C·cos·sin + B·sin^2, which peaks at
  /// phase = atan2(-2C, A - B) / 2.
  static double _brightestPhase(SlabResult r) {
    final double lambda = r.props.lambdaAir;
    final double d = r.thicknessM;
    final double side = math.max(_kAirWavelengths * lambda, 0.15 * d);
    double a2 = 0, b2 = 0, ab = 0;
    const int n = 240;
    for (int i = 0; i <= n; i++) {
      final double x = -side + (2 * side + d) * i / n;
      final Complex f = r.fieldAt(x);
      a2 += f.re * f.re;
      b2 += f.im * f.im;
      ab += f.re * f.im;
    }
    return 0.5 * math.atan2(-2 * ab, a2 - b2);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(WallSlabStage old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    setState(() {
      _phase = (_phase + 2 * math.pi * dt / _kSecondsPerCycle) % (2 * math.pi);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final WallConfig cfg = widget.config;
    final SlabResult r = _current;
    final double ampBehind = r.t.abs;

    final String semantic =
        'Wave through ${fmtMm(cfg.thicknessMm)} mm of '
        '${cfg.material.label.toLowerCase()} at ${cfg.centerMHz} MHz. '
        'In front, the reflected wave makes a ripple of '
        '${r.standingWaveRippleDb <= 40 ? '${fmt1(r.standingWaveRippleDb)} dB' : 'full nulls'}. '
        'Inside, the wavelength is ${fmtLength(r.props.lambdaInMaterial)} '
        'instead of ${fmtLength(r.props.lambdaAir)} in air. '
        'Behind, the amplitude is ${fmtPct(ampBehind)} of the incident '
        'amplitude: ${fmtLossDb(r.transmissionLossDb)} of loss.';

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: WallSectionLabel(
                  'The wave, along a line through the wall',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _playButton(colors),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: semantic,
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Container(
                height: widget.plotHeight,
                color: colors.surface2,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: WallWavePainter(
                    result: r,
                    phase: _phase,
                    cache: _cache,
                    style: WallWaveStyle(
                      wave: colors.textAccent,
                      envelope: colors.textTertiary,
                      reference: colors.border,
                      axis: colors.borderStrong,
                      wallFill: colors.surface3,
                      wallEdge: colors.borderStrong,
                      label:
                          text.labelSmall?.copyWith(
                            color: colors.textSecondary,
                          ) ??
                          TextStyle(color: colors.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                _legendItem(
                  context,
                  _line(colors.textAccent, 3),
                  'The wave now',
                ),
                _legendItem(
                  context,
                  _dashed(colors.textTertiary),
                  'Its peak (envelope)',
                ),
                _legendItem(
                  context,
                  _dashed(colors.border),
                  'Incident peak, for scale',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Through the wall: '),
                TextSpan(
                  text: fmtLossDb(r.transmissionLossDb),
                  style: TextStyle(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text:
                      ' of loss. Reflected back: ${fmtPct(r.reflectedPower)} '
                      'of the power.',
                ),
              ],
            ),
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          if (ampBehind < 0.02) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const WallNote(
              icon: Icons.visibility_off_outlined,
              message:
                  'Behind the wall the wave is too small to see at this '
                  'scale, but not zero: the loss above is how much smaller.',
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: reduceMotion && !widget.playing
                ? Icons.motion_photos_off_outlined
                : Icons.slow_motion_video_outlined,
            message: reduceMotion && !widget.playing
                ? 'Reduced motion is on, so the wave is frozen. Press Play to '
                      'animate it.'
                : 'Slowed down: one cycle every ${_kSecondsPerCycle.toStringAsFixed(0)} '
                      'seconds. At ${cfg.centerMHz} MHz a real wave cycles '
                      '${fmt1(cfg.fGhz)} billion times a second. The wall and '
                      'the air are drawn to the same scale.',
          ),
        ],
      ),
    );
  }

  Widget _playButton(AppColorScheme colors) {
    final bool p = widget.playing;
    return Semantics(
      button: true,
      label: p ? 'Pause the wave' : 'Play the wave',
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: () => widget.onPlayingChanged(!p),
        icon: Icon(p ? Icons.pause : Icons.play_arrow, size: 20),
        label: Text(p ? 'Pause' : 'Play'),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.borderStrong, width: 1.5),
          minimumSize: const Size(96, AppSpacing.minTouchTarget),
        ),
      ),
    );
  }

  Widget _legendItem(BuildContext context, Widget swatch, String label) {
    final AppColorScheme colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 22, child: Center(child: swatch)),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _line(Color c, double w) => Container(width: 20, height: w, color: c);

  Widget _dashed(Color c) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 5, height: 1.5, color: c),
      const SizedBox(width: 3),
      Container(width: 5, height: 1.5, color: c),
      const SizedBox(width: 3),
      Container(width: 4, height: 1.5, color: c),
    ],
  );
}

/// Colors and label style for [WallWavePainter]; all from the theme.
@immutable
class WallWaveStyle {
  const WallWaveStyle({
    required this.wave,
    required this.envelope,
    required this.reference,
    required this.axis,
    required this.wallFill,
    required this.wallEdge,
    required this.label,
  });

  final Color wave;
  final Color envelope;
  final Color reference;
  final Color axis;
  final Color wallFill;
  final Color wallEdge;
  final TextStyle label;

  @override
  bool operator ==(Object other) =>
      other is WallWaveStyle &&
      other.wave == wave &&
      other.envelope == envelope &&
      other.reference == reference &&
      other.axis == axis &&
      other.wallFill == wallFill &&
      other.wallEdge == wallEdge &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(wave, envelope, reference, axis, wallFill, wallEdge, label);
}

/// Sampled field phasors for one result at one width. Owned by the stage's
/// state so each animation frame only rotates them.
class WallPhasorCache {
  SlabResult? _for;
  int _n = 0;
  List<Complex> _phasors = const <Complex>[];
  _Geometry? _geo;
}

/// Draws the field along the wall normal.
class WallWavePainter extends CustomPainter {
  WallWavePainter({
    required this.result,
    required this.phase,
    required this.style,
    required this.cache,
  });

  final SlabResult result;
  final double phase;
  final WallWaveStyle style;
  final WallPhasorCache cache;

  _Geometry _geometry(double width) {
    final double lambda = result.props.lambdaAir;
    final double d = result.thicknessM;
    final double side = math.max(_kAirWavelengths * lambda, 0.15 * d);
    final double span = 2 * side + d;
    final double pxPerM = width / span;
    double wallPx = d * pxPerM;
    double frontPx = side * pxPerM;
    if (wallPx < _kMinWallPx) {
      // Keep the physics at true scale; only widen the drawn band.
      frontPx -= (_kMinWallPx - wallPx) / 2;
      wallPx = _kMinWallPx;
    }
    return _Geometry(side: side, span: span, frontPx: frontPx, wallPx: wallPx);
  }

  /// Maps a pixel column to metres from the front face, with the drawn wall
  /// band standing in for the true thickness when it had to be widened.
  double _xAt(double px, _Geometry g) {
    final double d = result.thicknessM;
    if (px < g.frontPx) return -(g.frontPx - px) / g.frontPx * g.side;
    if (px <= g.frontPx + g.wallPx) {
      return g.wallPx == 0 ? 0 : (px - g.frontPx) / g.wallPx * d;
    }
    final double backPx = g.frontPx + g.wallPx;
    final double backWidth = math.max(1.0, g.frontPx);
    return d + (px - backPx) / backWidth * g.side;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final int n = size.width.ceil() + 1;
    if (!identical(cache._for, result) || cache._n != n) {
      final _Geometry geo = _geometry(size.width);
      cache
        .._geo = geo
        .._phasors = <Complex>[
          for (int i = 0; i < n; i++)
            result.fieldAt(_xAt(i * size.width / (n - 1), geo)),
        ]
        .._for = result
        .._n = n;
    }
    final _Geometry g = cache._geo!;
    final List<Complex> ph = cache._phasors;

    const double labelBand = 20;
    final double top = labelBand;
    final double plotH = size.height - labelBand - AppSpacing.xxs;
    final double midY = top + plotH / 2;
    // Amplitude 2 (full standing-wave peak) reaches just inside the edge.
    final double yScale = plotH / 2 / 2.15;

    // Wall band.
    final Rect wall = Rect.fromLTWH(g.frontPx, 0, g.wallPx, size.height);
    canvas.drawRect(wall, Paint()..color = style.wallFill);
    final Paint edge = Paint()
      ..color = style.wallEdge
      ..strokeWidth = 1;
    canvas.drawLine(wall.topLeft, wall.bottomLeft, edge);
    canvas.drawLine(wall.topRight, wall.bottomRight, edge);

    // Zero axis and the incident-amplitude reference (+/-1).
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = style.axis
        ..strokeWidth = 1,
    );
    final Paint ref = Paint()
      ..color = style.reference
      ..strokeWidth = 1.5;
    _dashedH(canvas, midY - yScale, size.width, ref);
    _dashedH(canvas, midY + yScale, size.width, ref);

    // Envelope |f(x)|, above and below.
    final Paint env = Paint()
      ..color = style.envelope
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final double step = size.width / (ph.length - 1);
    for (final int sign in <int>[1, -1]) {
      for (int i = 0; i < ph.length - 1; i += 4) {
        final int j = math.min(i + 2, ph.length - 1);
        canvas.drawLine(
          Offset(i * step, midY - sign * ph[i].abs * yScale),
          Offset(j * step, midY - sign * ph[j].abs * yScale),
          env,
        );
      }
    }

    // The wave now: Re{f(x)·e^(j·phase)}.
    final double c = math.cos(phase);
    final double s = math.sin(phase);
    final Path wave = Path();
    for (int i = 0; i < ph.length; i++) {
      final double v = ph[i].re * c - ph[i].im * s;
      final Offset p = Offset(i * step, midY - v * yScale);
      if (i == 0) {
        wave.moveTo(p.dx, p.dy);
      } else {
        wave.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = style.wave
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Region labels.
    _label(canvas, 'In front', 0, g.frontPx, TextAlign.left);
    _label(canvas, 'Behind', g.frontPx + g.wallPx, size.width, TextAlign.right);
    if (g.wallPx >= 44) {
      _label(canvas, 'Wall', g.frontPx, g.frontPx + g.wallPx, TextAlign.center);
    }
  }

  void _dashedH(Canvas canvas, double y, double width, Paint p) {
    for (double x = 0; x < width; x += 10) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 5, width), y), p);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    double left,
    double right,
    TextAlign align,
  ) {
    final double w = right - left - 2 * AppSpacing.xxs;
    if (w < 24) return;
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style.label),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '',
    )..layout(minWidth: w, maxWidth: w);
    tp.paint(canvas, Offset(left + AppSpacing.xxs, AppSpacing.xxs / 2));
  }

  @override
  bool shouldRepaint(WallWavePainter old) =>
      old.phase != phase || old.result != result || old.style != style;
}

class _Geometry {
  const _Geometry({
    required this.side,
    required this.span,
    required this.frontPx,
    required this.wallPx,
  });

  final double side;
  final double span;
  final double frontPx;
  final double wallPx;
}
