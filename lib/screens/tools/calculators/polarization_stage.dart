// PolarizationStage: the rotatable 3D field and its readouts for the Wi-Fi
// Classroom "Polarization" tool (polarization). It reads PolarizationController
// and draws; its own inputs are the camera (drag, pinch, scroll, arrow keys,
// Reset view) and Play or Pause, so a presenter layout can put it beside
// PolarizationControls unchanged.
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box with no
// scroll. The polarization, what the tip traces and the axial ratio sit on top
// as large numbers; the 3D takes the rest of the height, with Play and Reset
// view under it.
//
// MOTION (GL-003 §8.8): the controller's Ticker advances the phase; it starts
// only when reduced motion is off. With reduced motion on the stage says the
// field is frozen, and Play still works. Pause is always offered (WCAG
// 2.2.2).
//
// THEME: the viewport is AppGainRamp.viewport in both themes (as Antenna
// Pattern's 3D), so the lime field and the two component hues are measured
// against one dark surface. Lime is the resultant, the one quantity the tool
// is about. No status hues: nothing here is a verdict.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/polarization_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_gain_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'antenna_pattern_parts.dart';
import 'polarization_controller.dart';
import 'polarization_painter.dart';
import 'polarization_parts.dart';
import 'wifi_lab_orbit.dart';

class PolarizationStage extends StatelessWidget {
  const PolarizationStage({
    super.key,
    required this.controller,
    this.viewportHeight = 320,
  });

  final PolarizationController controller;

  /// Height of the 3D viewport on the phone and desktop layouts.
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return _PresenterStage(controller: controller);
        }
        final PolarizationState s = controller.state;
        return PatternCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PatternSectionLabel(
                'The electric field along the direction of travel',
              ),
              const SizedBox(height: AppSpacing.xs),
              PolarizationViewport(
                controller: controller,
                height: viewportHeight,
              ),
              const SizedBox(height: AppSpacing.xxs),
              _Bar(controller: controller),
              const SizedBox(height: AppSpacing.xs),
              _Legend(showComponents: controller.showComponents),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PatternReadoutRow(
                      label: 'Polarization',
                      value: polarizationName(s),
                      emphasize: true,
                    ),
                    PatternReadoutRow(
                      label: 'The tip traces',
                      value: s.kind.traces,
                    ),
                    PatternReadoutRow(
                      label: 'Axial ratio',
                      value: fmtAxialRatio(s),
                    ),
                    PatternReadoutRow(label: 'Long axis', value: fmtTilt(s)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _MotionNote(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

// ── Presenter arrangement ───────────────────────────────────────────────────

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.controller});
  final PolarizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final TextStyle big = scale.headlineStyle(
      patternMono(context).outputMedium,
    );
    final PolarizationState s = controller.state;

    Widget stat(String label, String value, {bool accent = false}) =>
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              Text(
                value,
                style: big.copyWith(
                  color: accent ? colors.textAccent : colors.textPrimary,
                ),
              ),
            ],
          ),
        );

    return PatternCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PatternSectionLabel(
            'The electric field along the direction of travel',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            liveRegion: true,
            child: Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                stat('Polarization', polarizationName(s), accent: true),
                stat('The tip traces', s.kind.traces),
                stat('Axial ratio', fmtAxialRatio(s)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) =>
                  PolarizationViewport(
                    controller: controller,
                    height: math.max(120, box.maxHeight),
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _Bar(controller: controller),
          _Legend(showComponents: controller.showComponents),
        ],
      ),
    );
  }
}

// ── The 3D viewport ─────────────────────────────────────────────────────────

class PolarizationViewport extends StatefulWidget {
  const PolarizationViewport({
    super.key,
    required this.controller,
    required this.height,
  });

  final PolarizationController controller;
  final double height;

  @override
  State<PolarizationViewport> createState() => _PolarizationViewportState();
}

class _PolarizationViewportState extends State<PolarizationViewport> {
  final FocusNode _focus = FocusNode(debugLabel: 'polarization-3d');
  bool _focused = false;
  OrbitView? _gestureStart;
  double _yawAccum = 0;
  double _pitchAccum = 0;

  ValueNotifier<OrbitView> get _view => widget.controller.view;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStart = _view.value;
    _yawAccum = 0;
    _pitchAccum = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final OrbitView start = _gestureStart ?? _view.value;
    // A full drag across the viewport turns the view about 180 degrees.
    final double perPx = 180 / math.max(200, widget.height);
    _yawAccum += d.focalPointDelta.dx * perPx;
    _pitchAccum += d.focalPointDelta.dy * perPx;
    _view.value = start.rotated(-_yawAccum, _pitchAccum).zoomed(d.scale);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey k = e.logicalKey;
    OrbitView? next;
    if (k == LogicalKeyboardKey.arrowLeft) next = _view.value.rotated(10, 0);
    if (k == LogicalKeyboardKey.arrowRight) next = _view.value.rotated(-10, 0);
    if (k == LogicalKeyboardKey.arrowUp) next = _view.value.rotated(0, 10);
    if (k == LogicalKeyboardKey.arrowDown) next = _view.value.rotated(0, -10);
    if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add) {
      next = _view.value.zoomed(1.15);
    }
    if (k == LogicalKeyboardKey.minus) next = _view.value.zoomed(1 / 1.15);
    if (next == null) return KeyEventResult.ignored;
    _view.value = next;
    return KeyEventResult.handled;
  }

  String _semantic(PolarizationState s) {
    if (!s.hasField) {
      return '3D view of the direction of travel. No field: both amplitudes '
          'are zero.';
    }
    return '3D view of the electric field along the direction of travel. '
        '${polarizationName(s)} polarization: seen end on, the tip of the '
        'field traces ${s.kind.traces}. '
        'Drag to rotate, pinch or scroll to zoom; with keyboard focus, arrow '
        'keys rotate and plus or minus zoom.';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final TextStyle base = Theme.of(context).textTheme.labelSmall!;
    final TextStyle label = base.copyWith(
      color: AppGainRamp.viewportText,
      fontSize: scale.paintFont(base.fontSize ?? AppTextSize.caption),
    );
    final PolarizationState s = widget.controller.state;
    return Semantics(
      label: _semantic(s),
      image: true,
      excludeSemantics: true,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        onFocusChange: (bool f) => setState(() => _focused = f),
        child: Listener(
          onPointerSignal: (PointerSignalEvent e) {
            if (e is PointerScrollEvent) {
              _view.value = _view.value.zoomed(
                e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1,
              );
            }
          },
          child: GestureDetector(
            onTap: _focus.requestFocus,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: AppGainRamp.viewport,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: _focused ? colors.textAccent : colors.border,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: PolarizationPainter(
                          state: s,
                          phase: widget.controller.phase,
                          view: _view,
                          showComponents: widget.controller.showComponents,
                          lead: AppColors.primary,
                          hHue: kPolarizationHHue,
                          vHue: kPolarizationVHue,
                          labelStyle: label,
                          scale: scale,
                        ),
                      ),
                    ),
                    if (!s.hasField)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            'No field: raise the H or V amplitude.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppGainRamp.viewportText),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bar under the viewport: Play or Pause, Reset view ───────────────────────

class _Bar extends StatelessWidget {
  const _Bar({required this.controller});
  final PolarizationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool p = controller.playing;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Semantics(
          button: true,
          label: p ? 'Pause the wave' : 'Play the wave',
          excludeSemantics: true,
          child: OutlinedButton.icon(
            onPressed: controller.togglePlay,
            icon: Icon(p ? Icons.pause : Icons.play_arrow, size: 20),
            label: Text(p ? 'Pause' : 'Play'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderStrong, width: 1.5),
              minimumSize: const Size(96, AppSpacing.minTouchTarget),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: controller.resetView,
          icon: const Icon(Icons.threed_rotation, size: 18),
          label: const Text('Reset view'),
        ),
      ],
    );
  }
}

// ── Legend: what each line is (color is never the only carrier) ─────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.showComponents});
  final bool showComponents;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double k = PresenterMode.scaleOf(context).stroke;

    // Each swatch sits on a chip of the viewport's own dark surface, so the
    // legend shows exactly the colors the 3D draws, in both themes.
    Widget item(Color swatch, double weight, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: AppGainRamp.viewport,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Container(
            width: 18,
            height: math.max(2, weight * k),
            color: swatch,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        item(AppColors.primary, 3, 'E: the field'),
        if (showComponents) ...<Widget>[
          item(kPolarizationHHue, 2, 'H: the horizontal part alone'),
          item(kPolarizationVHue, 2, 'V: the vertical part alone'),
        ],
        item(
          AppGainRamp.viewportRuleStrong,
          1.5,
          'End-on view: the shape the tip traces, from the front end looking back',
        ),
      ],
    );
  }
}

// ── Motion note ─────────────────────────────────────────────────────────────

class _MotionNote extends StatelessWidget {
  const _MotionNote({required this.controller});
  final PolarizationController controller;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bool frozen = reduceMotion && !controller.playing;
    return PatternNote(
      icon: frozen
          ? Icons.motion_photos_off_outlined
          : Icons.slow_motion_video_outlined,
      message: frozen
          ? 'Reduced motion is on, so the wave is frozen. Press Play to '
                'animate it.'
          : 'Slowed down: one cycle every '
                '${kPolarizationSecondsPerCycle.toStringAsFixed(0)} seconds. '
                'The real wave cycles billions of times a second. Its '
                'frequency and wavelength are the same for every '
                'polarization.',
    );
  }
}
