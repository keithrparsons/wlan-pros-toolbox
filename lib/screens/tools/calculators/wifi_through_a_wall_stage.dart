// The stage for "Wi-Fi Through a Wall": the wave drawn along the wall's
// normal, animated in phase. It reads the shared WallSlabController (wall,
// play state, view toggle, phase) and holds no inputs of its own, so the
// presenter layout (lib/widgets/presenter/) places it beside WallSlabControls
// over the same state. In presenter mode the wave fills the stage and the
// loss, in headline type, stands under it beside the three-band table.
//
// What is drawn, left to right, at true scale:
//   - in front of the wall: incident plus reflected, E = e^(-jkx) + R e^(jkx);
//     its envelope shows the standing-wave ripple, nodes lambda/2 apart;
//   - inside: the same wave, its height taken from the physics (the decay,
//     including the part bounced off the back face);
//   - behind: the same wave again, height |T|.
// The field is the tangential E; SlabResult.fieldAt owns that math.
//
// FREQUENCY NEVER CHANGES (Keith, 2026-09-25: "The only thing that changes
// is the height of the wave, NOT the frequency."). A snapshot of a wave with
// a shorter wavelength reads as a higher frequency, so by DEFAULT the inside
// wave keeps the air wavelength: only its height changes. The optional
// "Show wavelength inside the material" view draws the true lambda/sqrt(e')
// with a note that the frequency is unchanged. In both views the inside
// phase is laid out on the air scale (px per metre), so widening a thin
// wall's band to stay visible never stretches the wave. See WallWaveProfile.
//
// MOTION (GL-003 §8.8): the phase advances on the controller's Ticker, one
// cycle every [kWallSecondsPerCycle] seconds. It starts running only when reduced motion is
// OFF; with reduced motion on, the stage is frozen and says so, and Play still
// works because the user starts it. A Pause control is always offered (WCAG
// 2.2.2).
//
// THEME: lime (textAccent) is the wave, the one quantity the stage is about;
// the envelope and reference lines are neutral; the wall is a surface step.
// No status hues: nothing here is a verdict.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/complex.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'wifi_through_a_wall_controller.dart';
import 'wifi_through_a_wall_controls.dart' show WallBandsCard;
import 'wifi_through_a_wall_parts.dart';

/// Air shown on each side of the wall, in free-space wavelengths.
const double _kAirWavelengths = 1.5;

/// Smallest drawn wall width, px, so a 1 mm sheet is still visible.
const double _kMinWallPx = 3;

class WallSlabStage extends StatefulWidget {
  const WallSlabStage({
    super.key,
    required this.controller,
    this.plotHeight = 200,
    this.showWavelengthSwitch = true,
  });

  /// The shared state: wall, play state, view toggle and phase.
  final WallSlabController controller;

  /// Plot height, px. Ignored in presenter mode, where the plot fills the
  /// stage.
  final double plotHeight;

  /// False hides the "Show wavelength inside the material" switch (a
  /// presenter can own it elsewhere).
  final bool showWavelengthSwitch;

  @override
  State<WallSlabStage> createState() => _WallSlabStageState();
}

class _WallSlabStageState extends State<WallSlabStage> {
  // View-local: sized to this view's plot, so each mounted stage (phone and
  // presenter) keeps its own.
  final WallPhasorCache _cache = WallPhasorCache();

  WallSlabController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) return _presenter(context);
        return _phone(context);
      },
    );
  }

  String _semantic() {
    final WallConfig cfg = _c.config;
    final SlabResult r = _c.result;
    final double ampBehind = r.t.abs;
    return 'Wave through ${fmtThickness(cfg.thicknessMm, _c.units)} of '
        '${cfg.material.label.toLowerCase()} at ${cfg.centerMHz} MHz. '
        'In front, the reflected wave makes a ripple of '
        '${r.standingWaveRippleDb <= 40 ? '${fmt1(r.standingWaveRippleDb)} dB' : 'full nulls'}. '
        '${_c.showMaterialWavelength ? 'Inside, the same frequency packs into a shorter wavelength, ${fmtLength(r.props.lambdaInMaterial, _c.units)} instead of ${fmtLength(r.props.lambdaAir, _c.units)} in air, and the wave shrinks in height. ' : 'Inside, the wave keeps the same frequency and shrinks in height. '}'
        'Behind, the amplitude is ${fmtPct(ampBehind)} of the incident '
        'amplitude: ${fmtLossDb(r.transmissionLossDb)} of loss.';
  }

  Widget _plot(BuildContext context, {double? height}) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final TextStyle label =
        text.labelSmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return Semantics(
      label: _semantic(),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: height,
          color: colors.surface2,
          child: CustomPaint(
            size: Size.infinite,
            painter: WallWavePainter(
              result: _c.result,
              phase: _c.phase,
              cache: _cache,
              showMaterialWavelength: _c.showMaterialWavelength,
              style: WallWaveStyle(
                wave: colors.textAccent,
                envelope: colors.textTertiary,
                reference: colors.border,
                axis: colors.borderStrong,
                wallFill: colors.surface3,
                wallEdge: colors.borderStrong,
                // Painted labels do not see MediaQuery's text scale; the
                // presenter scale reaches them here (1.0 elsewhere).
                label: label.copyWith(
                  fontSize: scale.paintFont(
                    label.fontSize ?? AppTextSize.caption,
                  ),
                ),
                scale: scale,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phone(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SlabResult r = _c.result;
    final double ampBehind = r.t.abs;

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
          _plot(context, height: widget.plotHeight),
          if (widget.showWavelengthSwitch) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _wavelengthSwitch(colors, text),
          ],
          const SizedBox(height: AppSpacing.xs),
          _legend(context),
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
          _motionNote(context),
        ],
      ),
    );
  }

  /// Presenter: the wave fills the stage; under it, the loss in headline
  /// type beside the same wall at all three bands.
  Widget _presenter(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final SlabResult r = _c.result;
    final double ampBehind = r.t.abs;

    final Widget wave = WallCard(
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
          Expanded(child: _plot(context)),
          if (widget.showWavelengthSwitch) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _wavelengthSwitch(colors, text),
          ],
          const SizedBox(height: AppSpacing.xs),
          _legend(context),
          if (ampBehind < 0.02) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            const WallNote(
              icon: Icons.visibility_off_outlined,
              message:
                  'Behind the wall the wave is too small to see at this '
                  'scale, but not zero.',
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          _motionNote(context),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.34).clamp(280.0, 440.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: wave),
            const SizedBox(height: AppSpacing.sm),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(width: side, child: _lossHeadline(context)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: WallBandsCard(config: _c.config)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The number the lesson is about, in headline type.
  Widget _lossHeadline(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final SlabResult r = _c.result;
    final WallConfig cfg = _c.config;
    return WallCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const WallSectionLabel('Through the wall'),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                fmtLossDb(r.transmissionLossDb),
                style: PresenterMode.scaleOf(context)
                    .headlineStyle(mono.outputLarge)
                    .copyWith(color: colors.textAccent),
              ),
            ),
            Text(
              'Reflected back: ${fmtPct(r.reflectedPower)} of the power.',
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${fmtThickness(cfg.thicknessMm, _c.units)} '
              '${cfg.material.label.toLowerCase()}, ${cfg.centerMHz} MHz',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double k = PresenterMode.scaleOf(context).stroke;
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          _legendItem(context, _line(colors.textAccent, 3 * k), 'The wave now'),
          _legendItem(
            context,
            _dashed(colors.textTertiary, k),
            'Its peak (envelope)',
          ),
          _legendItem(
            context,
            _dashed(colors.border, k),
            'Incident peak, for scale',
          ),
        ],
      ),
    );
  }

  Widget _motionNote(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final WallConfig cfg = _c.config;
    final bool frozen = reduceMotion && !_c.playing;
    return WallNote(
      icon: frozen
          ? Icons.motion_photos_off_outlined
          : Icons.slow_motion_video_outlined,
      message: frozen
          ? 'Reduced motion is on, so the wave is frozen. Press Play to '
                'animate it.'
          : 'Slowed down: one cycle every '
                '${kWallSecondsPerCycle.toStringAsFixed(0)} seconds. At '
                '${cfg.centerMHz} MHz a real wave cycles '
                '${fmt1(cfg.fGhz)} billion times a second, in front of, '
                'inside and behind the wall alike.',
    );
  }

  Widget _wavelengthSwitch(AppColorScheme colors, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MergeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Show wavelength inside the material',
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
              Switch(
                value: _c.showMaterialWavelength,
                onChanged: _c.setShowMaterialWavelength,
              ),
            ],
          ),
        ),
        Text(
          PresenterMode.isActive(context)
              ? 'Frequency never changes. Inside, slower travel packs the '
                    'same frequency into a shorter wavelength.'
              : 'Frequency never changes. Inside a material the wave travels '
                    'slower, so the same frequency packs into a shorter '
                    'wavelength.',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }

  Widget _playButton(AppColorScheme colors) {
    final bool p = _c.playing;
    return Semantics(
      button: true,
      label: p ? 'Pause the wave' : 'Play the wave',
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: _c.togglePlay,
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
    final double k = PresenterMode.scaleOf(context).stroke;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 22 * k,
          child: Center(child: swatch),
        ),
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

  Widget _dashed(Color c, [double k = 1]) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(width: 5 * k, height: 1.5 * k, color: c),
      SizedBox(width: 3 * k),
      Container(width: 5 * k, height: 1.5 * k, color: c),
      SizedBox(width: 3 * k),
      Container(width: 4 * k, height: 1.5 * k, color: c),
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
    this.scale = PresenterScale.normal,
  });

  final Color wave;
  final Color envelope;
  final Color reference;
  final Color axis;
  final Color wallFill;
  final Color wallEdge;
  final TextStyle label;

  /// Presenter scale for strokes and the label band (1 elsewhere). [label]
  /// arrives already scaled.
  final PresenterScale scale;

  @override
  bool operator ==(Object other) =>
      other is WallWaveStyle &&
      other.wave == wave &&
      other.envelope == envelope &&
      other.reference == reference &&
      other.axis == axis &&
      other.wallFill == wallFill &&
      other.wallEdge == wallEdge &&
      other.label == label &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(
    wave,
    envelope,
    reference,
    axis,
    wallFill,
    wallEdge,
    label,
    scale,
  );
}

/// What the stage draws: complex field phasors along the wall normal,
/// mapped to pixels. Pure and deterministic, so the tests can measure the
/// drawn wavelength directly.
///
/// Front of the wall and behind it are the physics' field (SlabResult.fieldAt)
/// on the air scale. Inside, the HEIGHT is the physics' |fieldAt| across the
/// drawn band, while the PHASE advances on the air scale (px per metre of
/// air) at either the air wavenumber (default: same wavelength everywhere)
/// or the true inside wavenumber Re(q)/d (showMaterialWavelength). Because
/// the phase uses the air scale in both cases, widening a thin wall's band to
/// [_kMinWallPx] changes how much wave the band shows, never its wavelength.
/// Behind the wall the wave continues from the phase the inside ended on, at
/// height |T|, so the drawing is continuous at both faces.
class WallWaveProfile {
  factory WallWaveProfile(
    SlabResult result,
    double width, {
    required bool showMaterialWavelength,
  }) {
    final double lambda = result.props.lambdaAir;
    final double d = result.thicknessM;
    final double side = math.max(_kAirWavelengths * lambda, 0.15 * d);
    final double pxPerM = width / (2 * side + d);
    double wallPx = d * pxPerM;
    double frontPx = side * pxPerM;
    bool widened = false;
    if (wallPx < _kMinWallPx) {
      frontPx -= (_kMinWallPx - wallPx) / 2;
      wallPx = _kMinWallPx;
      widened = true;
    }
    return WallWaveProfile._(
      result: result,
      width: width,
      showMaterialWavelength: showMaterialWavelength,
      side: side,
      frontPx: frontPx,
      wallPx: wallPx,
      airPxPerM: frontPx / side,
      widened: widened,
    );
  }

  WallWaveProfile._({
    required this.result,
    required this.width,
    required this.showMaterialWavelength,
    required this.side,
    required this.frontPx,
    required this.wallPx,
    required this.airPxPerM,
    required this.widened,
  }) : _k0z =
           2 *
           math.pi /
           result.props.lambdaAir *
           math.cos(result.angleDeg * math.pi / 180),
       _front = result.fieldAt(0);

  final SlabResult result;
  final double width;
  final bool showMaterialWavelength;

  /// Air shown on each side, metres.
  final double side;

  /// Pixel extent of the air in front, and of the drawn wall band.
  final double frontPx;
  final double wallPx;

  /// Pixels per metre of air (both sides).
  final double airPxPerM;

  /// Whether the wall band was widened to stay visible.
  final bool widened;

  final double _k0z;
  final Complex _front;

  /// Phase wavenumber inside the band, rad per metre of AIR scale.
  double get insideWavenumber {
    if (!showMaterialWavelength || result.thicknessM == 0) return _k0z;
    return result.q.re / result.thicknessM;
  }

  double get _psi0 => _front.arg;

  /// Phase at the back face of the drawn band.
  double get _psiEnd => _psi0 - insideWavenumber * (wallPx / airPxPerM);

  /// The drawn phasor at pixel column [px] (0..width).
  Complex phasorAtPx(double px) {
    if (px < frontPx) {
      return result.fieldAt((px - frontPx) / airPxPerM);
    }
    final double d = result.thicknessM;
    if (px <= frontPx + wallPx) {
      final double u = px - frontPx;
      final double mag = result.fieldAt(wallPx == 0 ? 0 : u / wallPx * d).abs;
      return Complex.polar(mag, _psi0 - insideWavenumber * (u / airPxPerM));
    }
    final double xBehind = (px - frontPx - wallPx) / airPxPerM;
    return Complex.polar(result.t.abs, _psiEnd - _k0z * xBehind);
  }

  /// [n] evenly spaced phasors across the width.
  List<Complex> sample(int n) => <Complex>[
    for (int i = 0; i < n; i++) phasorAtPx(i * width / (n - 1)),
  ];
}

/// Sampled drawn phasors for one result, width and view. Owned by the
/// stage's state so each animation frame only rotates them.
class WallPhasorCache {
  SlabResult? _for;
  int _n = 0;
  bool? _mode;
  List<Complex> _phasors = const <Complex>[];
  WallWaveProfile? _profile;
}

/// Draws the field along the wall normal.
class WallWavePainter extends CustomPainter {
  WallWavePainter({
    required this.result,
    required this.phase,
    required this.style,
    required this.cache,
    this.showMaterialWavelength = false,
  });

  final SlabResult result;
  final double phase;
  final WallWaveStyle style;
  final WallPhasorCache cache;
  final bool showMaterialWavelength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final int n = size.width.ceil() + 1;
    if (!identical(cache._for, result) ||
        cache._n != n ||
        cache._mode != showMaterialWavelength) {
      final WallWaveProfile prof = WallWaveProfile(
        result,
        size.width,
        showMaterialWavelength: showMaterialWavelength,
      );
      cache
        .._profile = prof
        .._phasors = prof.sample(n)
        .._for = result
        .._n = n
        .._mode = showMaterialWavelength;
    }
    final WallWaveProfile g = cache._profile!;
    final List<Complex> ph = cache._phasors;

    final double k = style.scale.stroke;
    final double labelBand = 20 * style.scale.text;
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
      ..strokeWidth = k;
    canvas.drawLine(wall.topLeft, wall.bottomLeft, edge);
    canvas.drawLine(wall.topRight, wall.bottomRight, edge);

    // Zero axis and the incident-amplitude reference (+/-1).
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = style.axis
        ..strokeWidth = k,
    );
    final Paint ref = Paint()
      ..color = style.reference
      ..strokeWidth = 1.5 * k;
    _dashedH(canvas, midY - yScale, size.width, ref, k);
    _dashedH(canvas, midY + yScale, size.width, ref, k);

    // Envelope |f(x)|, above and below.
    final Paint env = Paint()
      ..color = style.envelope
      ..strokeWidth = 1.2 * k
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
        ..strokeWidth = 2.5 * k
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

  void _dashedH(Canvas canvas, double y, double width, Paint p, double k) {
    for (double x = 0; x < width; x += 10 * k) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 5 * k, width), y), p);
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
      old.phase != phase ||
      old.result != result ||
      old.style != style ||
      old.showMaterialWavelength != showMaterialWavelength;
}
