// AntennaPatternStage: the plots for the Wi-Fi Lab "Antenna Pattern" tool
// (antenna-pattern). It reads AntennaPatternLab and draws; its only inputs
// are the camera (drag, pinch, scroll, arrow keys, Reset view), so a
// presenter layout can put it beside AntennaPatternControls unchanged.
//
//   3D:  the pattern as a surface, radius and color = gain in dBi, on a dark
//        viewport in both themes (the §8.15.2 gain ramp is measured against
//        it; see app_gain_ramp.dart). Floor and mounting surface as lines.
//   2D:  the horizontal cut (top view) and vertical cut (side view) on the
//        same dBi scale, updating live.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_gain_ramp.dart';
import '../../../theme/app_tokens.dart';
import 'antenna_pattern_mesh.dart';
import 'antenna_pattern_model.dart';
import 'antenna_pattern_painters.dart';
import 'antenna_pattern_parts.dart';

class AntennaPatternStage extends StatelessWidget {
  const AntennaPatternStage({
    super.key,
    required this.lab,
    this.viewportHeight = 320,
  });

  final AntennaPatternLab lab;

  /// Height of the 3D viewport. A presenter layout can pass a taller value.
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lab,
      builder: (BuildContext context, _) {
        final PatternResult? r = lab.result;
        final PatternMesh? mesh = lab.mesh;
        if (r == null || mesh == null) {
          return _EmptyStage(height: viewportHeight);
        }
        return PatternCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PatternSectionLabel(
                r.estimated
                    ? '3D pattern, estimated from two cuts '
                          '(${lab.method.label.toLowerCase()})'
                    : '3D pattern, gain in dBi',
              ),
              const SizedBox(height: AppSpacing.xs),
              _Viewport(
                lab: lab,
                mesh: mesh,
                result: r,
                height: viewportHeight,
              ),
              const SizedBox(height: AppSpacing.xs),
              _GainLegend(topDbi: r.topDbi),
              const SizedBox(height: AppSpacing.xxs),
              PatternCaption(
                'Radius and color are gain in dBi. Each color band is 5 dB; '
                'anything below ${fmtDbi(r.topDbi - kScaleSpanDb)} sits at the '
                'center as the floor. The scale stays put as you change the '
                'antenna, so more gain in one direction shows as less '
                'somewhere else.',
              ),
              const SizedBox(height: AppSpacing.sm),
              _Cuts(lab: lab, result: r),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return PatternCard(
      child: SizedBox(
        height: height * 0.6,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.content_paste_go_outlined,
                  size: 32,
                  color: colors.textTertiary,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'No pattern loaded yet. Paste an MSI or NSMA file below, or '
                  'pick a generated example.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Viewport extends StatefulWidget {
  const _Viewport({
    required this.lab,
    required this.mesh,
    required this.result,
    required this.height,
  });

  final AntennaPatternLab lab;
  final PatternMesh mesh;
  final PatternResult result;
  final double height;

  @override
  State<_Viewport> createState() => _ViewportState();
}

class _ViewportState extends State<_Viewport> {
  final FocusNode _focus = FocusNode(debugLabel: 'antenna-pattern-3d');
  bool _focused = false;
  OrbitView? _gestureStart;
  double _yawAccum = 0;
  double _pitchAccum = 0;

  ValueNotifier<OrbitView> get _view => widget.lab.view;

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
    // A full drag across the viewport turns the pattern about 180°.
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

  String _semantic() {
    final PatternResult r = widget.result;
    final double below = r.grid.peakTheta - 90.0;
    return '${r.estimated ? 'Estimated 3D' : '3D'} antenna pattern, '
        '${widget.lab.mount.label.toLowerCase()} mounted. Peak '
        '${fmtDbi(r.grid.peakDbi)}, ${fmtElevation(below)} in the antenna\'s '
        'own frame. Drag to rotate, pinch or scroll to zoom; with keyboard '
        'focus, arrow keys rotate and plus or minus zoom.';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle label = Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(color: AppGainRamp.viewportText);
    final bool omniFrame = !widget.lab.rotatedForMount
        ? widget.lab.mount == AntennaMount.ceiling
        : widget.lab.mount == AntennaMount.wall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          label: _semantic(),
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
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: OrbitPainter(
                          mesh: widget.mesh,
                          view: _view,
                          surface: widget.lab.mount == AntennaMount.ceiling
                              ? MountSurface.ceiling
                              : MountSurface.wall,
                          labelStyle: label,
                          frontLabel: omniFrame ? '0°' : 'Front',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Row(
          children: <Widget>[
            Expanded(
              child: PatternCaption(
                widget.lab.mount == AntennaMount.ceiling
                    ? 'Ceiling mount: the square just above the antenna is '
                          'the ceiling; the grid below is the floor.'
                    : 'Wall mount: the square just behind the antenna is the '
                          'wall; the grid below is the floor.',
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            TextButton.icon(
              onPressed: widget.lab.resetView,
              icon: const Icon(Icons.threed_rotation, size: 18),
              label: const Text('Reset view'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The stepped dBi scale for the 3D colors: meaning never rests on color
/// alone (§8.15.2, §8.22 legend rule).
class _GainLegend extends StatelessWidget {
  const _GainLegend({required this.topDbi});
  final double topDbi;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle ts = patternMono(
      context,
    ).inlineCode.copyWith(color: colors.textSecondary, fontSize: 11);
    final double floor = topDbi - kScaleSpanDb;
    return Semantics(
      label:
          'Color scale: seven bands of 5 dB, from ${fmtDbi(floor)} to '
          '${fmtDbi(topDbi)}, darker blue lowest, pale cream highest.',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('dBi', style: ts),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    for (final Color c in AppGainRamp.bands)
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: c,
                            border: Border.all(
                              color: AppGainRamp.viewport,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double w = c.maxWidth / 7;
                    String edge(int k) => fmtDb1(
                      floor + AppGainRamp.bandDb * k,
                    ).replaceAll('.0', '');
                    // Every band edge when there is room, else every other.
                    final int every = w < 36 ? 2 : 1;
                    return SizedBox(
                      height: 16,
                      child: Stack(
                        children: <Widget>[
                          Positioned(left: 0, child: Text(edge(0), style: ts)),
                          for (int k = every; k < 7; k += every)
                            Positioned(
                              left: w * k - 16,
                              width: 32,
                              child: Text(
                                edge(k),
                                textAlign: TextAlign.center,
                                style: ts,
                              ),
                            ),
                          Positioned(right: 0, child: Text(edge(7), style: ts)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cuts extends StatelessWidget {
  const _Cuts({required this.lab, required this.result});
  final AntennaPatternLab lab;
  final PatternResult result;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PolarStyle style = PolarStyle(
      trace: colors.textAccent,
      ring: colors.border,
      axis: colors.borderStrong,
      isotropic: colors.textTertiary,
      labelStyle: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: colors.textTertiary,
        fontSize: 10,
      ),
    );
    final double? hbw = result.cuts.horizontalBeamwidthDeg;
    final double? vbw = result.cuts.verticalBeamwidthDeg;
    Widget plot(CutKind kind, String title, String semantic) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label: semantic,
            image: true,
            excludeSemantics: true,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: CustomPaint(
                  painter: PolarCutPainter(
                    lossDb: kind == CutKind.horizontal
                        ? result.cuts.horizontalLossDb
                        : result.cuts.verticalLossDb,
                    peakDbi: result.cuts.peakGainDbi,
                    topDbi: result.topDbi,
                    kind: kind,
                    style: style,
                    revision: lab.revision,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PatternSectionLabel('The two 2D cuts, antenna frame'),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            plot(
              CutKind.horizontal,
              'Horizontal (from above)',
              'Horizontal cut, seen from above with the front at the top. '
                  '${hbw == null ? 'Omnidirectional: no half-power points.' : 'Half-power beamwidth ${fmtDeg1(hbw)}.'}',
            ),
            const SizedBox(width: AppSpacing.xs),
            plot(
              CutKind.vertical,
              'Vertical (from the side)',
              'Vertical cut, seen from the side with the front at the right '
                  'and down at the bottom. '
                  '${vbw == null ? '' : 'Half-power beamwidth ${fmtDeg1(vbw)}. '}'
                  'Peak ${fmtElevation(result.cuts.verticalPeakAngle.toDouble())}.',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        PatternCaption(
          'Same dBi scale as the 3D; rings every 10 dB. The dashed ring is '
          '0 dBi, an isotropic antenna fed the same power: outside it this '
          'antenna is stronger, inside it weaker. In the side view the front '
          'is at the right. These are the cuts a pattern file carries.',
        ),
        if (result.estimated) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          const PatternCaption(
            'These cuts are taken from the rebuilt 3D. The horizontal cut and '
            'the front of the vertical cut match the file; the back of the '
            'vertical cut is the rebuild\'s guess, which is where two cuts '
            'fall short.',
          ),
        ],
      ],
    );
  }
}
