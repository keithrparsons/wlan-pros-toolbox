// The stage for "Wi-Fi Through a Wall": the wave drawn along the wall's
// normal, animated in phase. It reads the shared WallSlabController (wall,
// play state, view toggle, phase) and holds no inputs of its own, so the
// presenter layout (lib/widgets/presenter/) places it beside WallSlabControls
// over the same state. In presenter mode the wave fills the stage and the
// loss, in headline type, stands under it beside the three-band table.
//
// What is drawn, left to right (the air at true scale, the wall NOT to
// scale, see below):
//   - in front of the wall: incident plus reflected, E = e^(-jkx) + R e^(jkx);
//     its envelope shows the standing-wave ripple, nodes lambda/2 apart;
//   - inside: the same wave, its height a straight ramp in dB from the
//     front face to the back face;
//   - behind: the same wave again, at the level Tx power minus the loss.
// The field is the tangential E; SlabResult.fieldAt owns that math.
//
// HEIGHT IS dB ABOVE THE NOISE FLOOR (Keith, 2026-09-27: "a concrete wall
// perhaps 2' thick and still want to see the wave form on the right not
// turn into a flatline. Since that is what happens in the real world").
// With the height linear in field, 64 dB of loss drew as a flat line. Now
// height = max(0, (P - floor) / (Ptx - floor)) with P = Ptx + 20 log10 |E|:
// 1 is the Tx power (the incident wave), 0 is the noise floor
// ([kWallNoiseFloorDbm]). The standing wave in front is mapped the same way.
// Only the drawing changes; every number stays exact.
//
// NO RIPPLE INSIDE THE WALL (Keith, 2026-09-27: "Why is the radio wave
// changing frequency inside the wall?"). The true inside field carries a
// standing-wave ripple from the wave bounced off the back face. Drawn in a
// band squeezed to a few dozen px, it made the wave wiggle 3 or 4 times
// inside the wall, which reads as a higher frequency. Inside, the drawn
// level is a straight line in dB between the exact levels at the two faces:
// the decay in dB is linear in depth, so the height is a straight ramp and
// the wave stays continuous at both faces.
//
// FREQUENCY NEVER CHANGES (Keith, 2026-09-25: "The only thing that changes
// is the height of the wave, NOT the frequency."). A snapshot of a wave with
// a shorter wavelength reads as a higher frequency, so by DEFAULT the inside
// wave keeps the air wavelength: only its height changes. The optional
// "Show wavelength inside the material" view draws the true lambda/sqrt(e')
// with a note that the frequency is unchanged. In both views the inside
// phase is laid out on the air scale (px per metre), so the wall band's
// drawn width never stretches the wave. See WallWaveProfile.
//
// THE WALL IS NOT DRAWN TO SCALE (Keith, 2026-09-27: "at 1cm only one pixel
// difference, at 1m the two vertical lines should be no more than 3X the
// width of the word 'wall' ... I don't want the 'wall' to ever get very large
// at all on the screen."). The band's width is set by [WallWaveProfile.
// drawnWallPx]: 1 px of space between the edge lines at 1 cm, 3x the drawn
// "Wall" label at 1 m, linear in log10(thickness) between, so 10 cm is
// halfway. The air fills the rest. Every number still uses the true
// thickness, and a caption under the plot says the wall is not to scale.
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

/// The drawn wall at [kWallMaxMm] is this many times the "Wall" label's
/// rendered width (Keith, 2026-09-27).
const double kWallCapLabelWidths = 3;

/// Space between the two wall edge lines at [kWallMinMm], logical px.
const double kWallMinGapPx = 1;

/// The incident wave's drawn height (the Tx power) as a fraction of the
/// half-height of the plot. 0.6 is 29% taller than the old 1 / 2.15 (Keith,
/// 2026-09-27: "perhaps 20%-30% higher"). The tallest standing-wave peak,
/// +6 dB at Tx 0 dBm, is 1.064 x this, so it never clips.
const double kWallIncidentHalfFraction = 0.6;

/// The caption under the plot, because the band is not to scale.
const String kWallNotToScaleCaption = 'Wall thickness not drawn to scale';

/// The caption saying what the height means.
const String kWallHeightCaption =
    'Height shows signal above the noise floor (dB)';

/// Rendered width of the stage's "Wall" label in [style], px. The painter
/// and the tests measure it the same way, so the cap follows the presenter
/// text scale.
double wallLabelWidth(TextStyle style) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: 'Wall', style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final double w = tp.width;
  tp.dispose();
  return w;
}

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
    final double behind = cfg.levelBehindDbm(r);
    return 'Wave through ${fmtThickness(cfg.thicknessMm, _c.units)} of '
        '${cfg.material.label.toLowerCase()} at ${cfg.centerMHz} MHz. '
        'In front, the reflected wave makes a ripple of '
        '${r.standingWaveRippleDb <= 40 ? '${fmt1(r.standingWaveRippleDb)} dB' : 'full nulls'}. '
        '${_c.showMaterialWavelength ? 'Inside, the same frequency packs into a shorter wavelength, ${fmtLength(r.props.lambdaInMaterial, _c.units)} instead of ${fmtLength(r.props.lambdaAir, _c.units)} in air, and the wave shrinks in height. ' : 'Inside, the wave keeps the same frequency and shrinks in height. '}'
        'Behind, ${fmtLossDb(r.transmissionLossDb)} of loss takes '
        '${fmtDbm(cfg.txPowerDbm)} to ${_behindText(behind)}. The height '
        'shows signal above a ${fmtDbm(kWallNoiseFloorDbm)} noise floor.';
  }

  /// The level behind the wall in words: dBm and dB above the floor, or
  /// below the floor.
  static String _behindText(double dbm) {
    if (!dbm.isFinite || dbm <= kWallNoiseFloorDbm) {
      return 'below the ${fmtDbm(kWallNoiseFloorDbm)} noise floor';
    }
    return '${fmtDbm(dbm)}, ${fmt1(dbm - kWallNoiseFloorDbm)} dB above the '
        'noise floor';
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
              txPowerDbm: _c.config.txPowerDbm,
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
    final double behind = _c.config.levelBehindDbm(r);

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
          const SizedBox(height: AppSpacing.xxs),
          _notToScale(colors, text),
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
                      'of the power. Behind the wall: '
                      '${_behindText(behind)}.',
                ),
              ],
            ),
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          if (_belowFloor(behind)) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _belowFloorNote(),
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
    final double behind = _c.config.levelBehindDbm(_c.result);

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
          const SizedBox(height: AppSpacing.xxs),
          _notToScale(colors, text),
          if (widget.showWavelengthSwitch) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _wavelengthSwitch(colors, text),
          ],
          const SizedBox(height: AppSpacing.xs),
          _legend(context),
          if (_belowFloor(behind)) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            _belowFloorNote(),
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
            Text(
              'Behind: ${_behindText(cfg.levelBehindDbm(r))}.',
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${fmtThickness(cfg.thicknessMm, _c.units)} '
              '${cfg.material.label.toLowerCase()}, ${cfg.centerMHz} MHz, '
              'Tx ${fmtDbm(cfg.txPowerDbm)}',
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
            'Tx power (the incident wave)',
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

  Widget _notToScale(AppColorScheme colors, TextTheme text) => Text(
    '$kWallHeightCaption. $kWallNotToScaleCaption.',
    style: text.bodySmall?.copyWith(color: colors.textSecondary),
  );

  static bool _belowFloor(double dbm) =>
      !dbm.isFinite || dbm <= kWallNoiseFloorDbm;

  Widget _belowFloorNote() => WallNote(
    icon: Icons.visibility_off_outlined,
    message:
        'Behind the wall the line is flat: the signal is below the '
        '${fmtDbm(kWallNoiseFloorDbm)} noise floor. It is not zero, and the '
        'loss above is exact.',
  );

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

/// What the stage draws: phasors whose angle is the wave's phase and whose
/// length is the drawn height, along the wall normal, mapped to pixels. Pure
/// and deterministic, so the tests can measure the drawn wavelength and
/// height directly.
///
/// The wall band's width is [drawnWallPx], not to scale. The air on each
/// side is [_kAirWavelengths] free-space wavelengths at true scale and fills
/// the rest of the width.
///
/// HEIGHT: [heightForDbm] of the level [levelDbmAtPx], so 1 is the Tx power
/// and 0 the noise floor. In front the level is Ptx + 20 log10 |fieldAt|,
/// the standing wave included. Inside it is a straight line in dB from the
/// exact level at the front face to the exact level at the back face, so the
/// height is a straight ramp with no ripple at any thickness. Behind it is
/// Ptx minus the transmission loss.
///
/// PHASE: one carrier. In front it is the incident wave's phase, -k x, so
/// the drawn wave is a clean sinusoid under the envelope (the standing
/// wave's own phase advances unevenly, and under a dB height that drew as
/// flat-topped, warped cycles). Inside, it advances on the air
/// scale (px per metre of air) at either the air wavenumber (default: same
/// wavelength everywhere) or the true inside wavenumber Re(q)/d
/// (showMaterialWavelength). Because the phase uses the air scale in both
/// cases, the band's drawn width changes how much wave the band shows, never
/// its wavelength. Behind the wall the wave continues from the phase the
/// inside ended on, so the drawing is continuous at both faces.
class WallWaveProfile {
  factory WallWaveProfile(
    SlabResult result,
    double width, {
    required bool showMaterialWavelength,
    double txPowerDbm = kWallDefaultTxDbm,
    double noiseFloorDbm = kWallNoiseFloorDbm,
    double edgeStrokePx = 1,
    double labelWidthPx = 24,
  }) {
    final double lambda = result.props.lambdaAir;
    final double side = _kAirWavelengths * lambda;
    final double wallPx = drawnWallPx(
      thicknessMm: result.thicknessM * 1000,
      width: width,
      edgeStrokePx: edgeStrokePx,
      labelWidthPx: labelWidthPx,
    );
    final double frontPx = (width - wallPx) / 2;
    return WallWaveProfile._(
      result: result,
      width: width,
      showMaterialWavelength: showMaterialWavelength,
      txPowerDbm: txPowerDbm,
      noiseFloorDbm: noiseFloorDbm,
      side: side,
      frontPx: frontPx,
      wallPx: wallPx,
      airPxPerM: frontPx / side,
    );
  }

  WallWaveProfile._({
    required this.result,
    required this.width,
    required this.showMaterialWavelength,
    required this.txPowerDbm,
    required this.noiseFloorDbm,
    required this.side,
    required this.frontPx,
    required this.wallPx,
    required this.airPxPerM,
  }) : _k0z =
           2 *
           math.pi /
           result.props.lambdaAir *
           math.cos(result.angleDeg * math.pi / 180),
       _front = result.fieldAt(0);

  /// Drawn width of the wall band, px, measured edge line centre to edge
  /// line centre. At [kWallMinMm] the space between the two lines (each
  /// [edgeStrokePx] wide) is [kWallMinGapPx]; at [kWallMaxMm] the band is
  /// [kWallCapLabelWidths] x [labelWidthPx]; linear in log10(thickness)
  /// between, clamped at both ends. Never wider than the cap, and never more
  /// than a third of [width] on a very narrow stage.
  static double drawnWallPx({
    required double thicknessMm,
    required double width,
    double edgeStrokePx = 1,
    double labelWidthPx = 24,
  }) {
    final double minPx = kWallMinGapPx + edgeStrokePx;
    final double maxPx = math.max(
      minPx,
      math.min(kWallCapLabelWidths * labelWidthPx, width / 3),
    );
    final double lo = math.log(kWallMinMm);
    final double hi = math.log(kWallMaxMm);
    final double t = thicknessMm <= 0
        ? 0
        : ((math.log(thicknessMm) - lo) / (hi - lo)).clamp(0.0, 1.0);
    return minPx + t * (maxPx - minPx);
  }

  /// Field magnitude relative to the incident wave, in dB, floored so a
  /// metal wall's underflowed zero stays a finite (very low) number.
  static double fieldDb(double magnitude) {
    if (magnitude <= 0 || !magnitude.isFinite) return -1e4;
    return math.max(-1e4, 20 * math.log(magnitude) / math.ln10);
  }

  /// Drawn height for a level: 0 at [noiseFloorDbm] and below, 1 at
  /// [txPowerDbm] (the incident wave), linear in dB.
  static double heightForDbm(
    double dbm, {
    required double txPowerDbm,
    double noiseFloorDbm = kWallNoiseFloorDbm,
  }) => math.max(0, (dbm - noiseFloorDbm) / (txPowerDbm - noiseFloorDbm));

  final SlabResult result;
  final double width;
  final bool showMaterialWavelength;

  /// Tx power, dBm: drawn at height 1.
  final double txPowerDbm;

  /// Noise floor, dBm: drawn at height 0.
  final double noiseFloorDbm;

  /// Air shown on each side, metres.
  final double side;

  /// Pixel extent of the air in front, and of the drawn wall band.
  final double frontPx;
  final double wallPx;

  /// Pixels per metre of air (both sides).
  final double airPxPerM;

  final double _k0z;
  final Complex _front;

  /// Exact level at the front face and behind the wall, dBm.
  double get frontFaceDbm => txPowerDbm + fieldDb(_front.abs);
  double get behindDbm => txPowerDbm + fieldDb(result.t.abs);

  /// Whether the level behind the wall is at or below the noise floor, so
  /// the drawn wave there is flat.
  bool get belowFloorBehind => behindDbm <= noiseFloorDbm;

  /// Level at pixel column [px], dBm (see the class doc).
  double levelDbmAtPx(double px) {
    if (px < frontPx) {
      return txPowerDbm + fieldDb(result.fieldAt((px - frontPx) / airPxPerM).abs);
    }
    if (px <= frontPx + wallPx) {
      final double f = wallPx == 0 ? 1 : (px - frontPx) / wallPx;
      return frontFaceDbm + f * (behindDbm - frontFaceDbm);
    }
    return behindDbm;
  }

  /// Drawn height at pixel column [px]: 1 at the Tx power, 0 at the floor.
  double heightAtPx(double px) => heightForDbm(
    levelDbmAtPx(px),
    txPowerDbm: txPowerDbm,
    noiseFloorDbm: noiseFloorDbm,
  );

  /// Phase wavenumber inside the band, rad per metre of AIR scale.
  double get insideWavenumber {
    if (!showMaterialWavelength || result.thicknessM == 0) return _k0z;
    return result.q.re / result.thicknessM;
  }

  /// Carrier phase at the front face: the incident wave's, 0.
  double get _psi0 => 0;

  /// Phase at the back face of the drawn band.
  double get _psiEnd => _psi0 - insideWavenumber * (wallPx / airPxPerM);

  /// The wave's phase at pixel column [px].
  double phaseAtPx(double px) {
    if (px < frontPx) return -_k0z * ((px - frontPx) / airPxPerM);
    if (px <= frontPx + wallPx) {
      return _psi0 - insideWavenumber * ((px - frontPx) / airPxPerM);
    }
    return _psiEnd - _k0z * ((px - frontPx - wallPx) / airPxPerM);
  }

  /// The drawn phasor at pixel column [px] (0..width): length
  /// [heightAtPx], angle [phaseAtPx].
  Complex phasorAtPx(double px) =>
      Complex.polar(heightAtPx(px), phaseAtPx(px));

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
  double _tx = double.nan;
  double _edge = 0;
  double _labelW = 0;
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
    this.txPowerDbm = kWallDefaultTxDbm,
  });

  final SlabResult result;
  final double phase;
  final WallWaveStyle style;
  final WallPhasorCache cache;
  final bool showMaterialWavelength;
  final double txPowerDbm;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final int n = size.width.ceil() + 1;
    final double k = style.scale.stroke;
    final double labelW = wallLabelWidth(style.label);
    if (!identical(cache._for, result) ||
        cache._n != n ||
        cache._mode != showMaterialWavelength ||
        cache._tx != txPowerDbm ||
        cache._edge != k ||
        cache._labelW != labelW) {
      final WallWaveProfile prof = WallWaveProfile(
        result,
        size.width,
        showMaterialWavelength: showMaterialWavelength,
        txPowerDbm: txPowerDbm,
        edgeStrokePx: k,
        labelWidthPx: labelW,
      );
      cache
        .._profile = prof
        .._phasors = prof.sample(n)
        .._for = result
        .._n = n
        .._mode = showMaterialWavelength
        .._tx = txPowerDbm
        .._edge = k
        .._labelW = labelW;
    }
    final WallWaveProfile g = cache._profile!;
    final List<Complex> ph = cache._phasors;

    final double labelBand = 20 * style.scale.text;
    final double top = labelBand;
    final double plotH = size.height - labelBand - AppSpacing.xxs;
    final double midY = top + plotH / 2;
    // Height 1 (the Tx power) at [kWallIncidentHalfFraction] of the half
    // height; the tallest standing-wave peak is at most 1.064 of it.
    final double yScale = plotH / 2 * kWallIncidentHalfFraction;

    // Wall band, under the label band so the "Wall" label sits above it at
    // every thickness, even a 1 px gap.
    final Rect wall = Rect.fromLTWH(
      g.frontPx,
      labelBand,
      g.wallPx,
      size.height - labelBand,
    );
    canvas.drawRect(wall, Paint()..color = style.wallFill);
    final Paint edge = Paint()
      ..color = style.wallEdge
      ..strokeWidth = k;
    canvas.drawLine(wall.topLeft, wall.bottomLeft, edge);
    canvas.drawLine(wall.topRight, wall.bottomRight, edge);

    // Zero axis (the noise floor) and the Tx-power reference (+/-1).
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
    _wallLabel(canvas, g.frontPx + g.wallPx / 2);
  }

  /// "Wall", centred over the band. The band is at most 3x this label wide
  /// and the air on each side is far wider, so it never meets "In front" or
  /// "Behind".
  void _wallLabel(Canvas canvas, double centreX) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: 'Wall', style: style.label),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, Offset(centreX - tp.width / 2, AppSpacing.xxs / 2));
    tp.dispose();
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
      old.showMaterialWavelength != showMaterialWavelength ||
      old.txPowerDbm != txPowerDbm;
}
