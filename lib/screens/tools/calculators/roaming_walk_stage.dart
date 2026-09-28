// RoamingWalkStage: the pictures half of the Roaming Walk.
//
// The floor plan (APs, their -67 and -70 dBm contours, the path, the walking
// client and its association line) and, below it, the RSSI of every AP over
// the walk with the trigger line and roam markers. Takes the shared
// RoamingWalkController and nothing else, so a phone layout can stack it with
// RoamingWalkControls and a presenter layout can put the two side by side.
//
// Dragging an AP moves it and tapping the floor in drawing mode adds a
// waypoint; both go through the controller. The AP position sliders and the
// path select in RoamingWalkControls do the same for keyboard users.
//
// PRESENTER (spec 00): inside a PresenterLayout the floor and the RSSI plot
// share the stage height with no scroll, the phone prose is dropped, and a
// strip over the floor carries the number the lesson is about: which AP the
// client is on and at what signal, with the walk time, roams so far and the
// gap per roam. Painters read PresenterMode.scaleOf through RoamPaintStyle.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/roaming_walk_engine.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'roaming_walk_controller.dart';
import 'roaming_walk_painters.dart';
import 'roaming_walk_palette.dart';
import 'roaming_walk_parts.dart';

class RoamingWalkStage extends StatelessWidget {
  const RoamingWalkStage({super.key, required this.controller});

  final RoamingWalkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final RoamPaintStyle style = _paintStyle(context);
        if (PresenterMode.isActive(context)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NowStrip(controller: controller),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                flex: 5,
                child: _FloorCard(
                  controller: controller,
                  style: style,
                  fill: true,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                flex: 4,
                child: _PlotCard(
                  controller: controller,
                  style: style,
                  fill: true,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _FloorCard(controller: controller, style: style),
            const SizedBox(height: AppSpacing.sm),
            _PlotCard(controller: controller, style: style),
          ],
        );
      },
    );
  }

  static RoamPaintStyle _paintStyle(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    return RoamPaintStyle(
      sc: sc,
      apColors: <Color>[
        for (int i = 0; i < kMaxAps; i++)
          roamApColor(i, isLight: colors.isLight),
      ],
      accent: colors.textAccent,
      primary: colors.textPrimary,
      secondary: colors.textSecondary,
      tertiary: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      halo: colors.surface2,
      labelStyle: mono.inlineCode.copyWith(
        // Painted labels do not see MediaQuery's text scale.
        fontSize: sc.paintFont(AppTextSize.caption - 2),
        color: colors.textSecondary,
      ),
    );
  }
}

/// A pan recognizer that wins the gesture arena at once when the pointer
/// lands on an AP, so dragging an AP never scrolls the page, while a drag
/// that starts on empty floor still scrolls.
class _ApDragRecognizer extends PanGestureRecognizer {
  _ApDragRecognizer({required this.claims});

  final bool Function(Offset local) claims;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (claims(event.localPosition)) resolve(GestureDisposition.accepted);
  }
}

class _FloorCard extends StatefulWidget {
  const _FloorCard({
    required this.controller,
    required this.style,
    this.fill = false,
  });

  final RoamingWalkController controller;
  final RoamPaintStyle style;

  /// Presenter: fill a bounded box; the floor takes the height the legend
  /// leaves, and the teaching prose is dropped.
  final bool fill;

  @override
  State<_FloorCard> createState() => _FloorCardState();
}

class _FloorCardState extends State<_FloorCard> {
  int? _dragging;
  Size _size = Size.zero;

  RoamingWalkController get c => widget.controller;

  /// Touch radius around an AP, meters (at least 22 px).
  double _hitRadiusM(FloorMapping m) =>
      widget.style.sc.markerSize(22) / m.scale;

  bool _claims(Offset local) {
    if (c.drawing || _size == Size.zero) return false;
    final FloorMapping m = FloorMapping(_size);
    return c.apNear(m.toFloor(local), _hitRadiusM(m)) != null;
  }

  String _semantic() {
    final RoamWalkConfig cfg = c.config;
    final RoamWalkResult r = c.result;
    final int k = c.sample;
    final FloorPoint p = r.positions[k];
    final StringBuffer b = StringBuffer(
      'Floor plan, ${c.lf.distNumber(kFloorWidthM, decimals: 0)} by '
      '${c.lf.distNumber(kFloorDepthM, decimals: 0)} ${c.lf.distUnitSpoken}, '
      'seen from above. ',
    );
    for (int i = 0; i < cfg.aps.length; i++) {
      b.write(
        'AP ${i + 1} at ${c.lf.distValue(cfg.aps[i].x).toStringAsFixed(1)}, '
        '${c.len1(cfg.aps[i].y)}. ',
      );
    }
    b.write(
      'Minus 67 dBm reaches '
      '${c.len1(cfg.contourRadiusM(kDesignOverlapDbm))} from '
      'each AP and minus 70 dBm '
      '${c.len1(cfg.contourRadiusM(kWeakSignalDbm))}. ',
    );
    if (c.drawing) {
      b.write(
        'Drawing a path: ${c.drawnPoints.length} points so far. Tap the '
        'floor to add a point.',
      );
      return b.toString();
    }
    b.write(
      'Client at ${c.lf.distValue(p.x).toStringAsFixed(1)}, '
      '${c.len1(p.y)}, ',
    );
    final int? s = r.servingAt(k);
    final RoamEvent? g = r.gapAt(k);
    if (s != null) {
      b.write('on AP ${s + 1} at ${fmtDbm(r.rssi[s][k])}.');
    } else if (g != null) {
      b.write('between APs, roaming to AP ${g.toAp + 1}.');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoamWalkConfig cfg = c.config;
    final bool wide = MediaQuery.sizeOf(context).width >= 720;
    final bool fill = widget.fill;
    final Widget floor = Semantics(
      label: _semantic(),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          color: colors.surface2,
          child: fill
              ? _plan(cfg)
              : AspectRatio(aspectRatio: wide ? 2.8 : 2.4, child: _plan(cfg)),
        ),
      ),
    );
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RwSectionLabel(
            'Floor plan, seen from above '
            '(${LengthFormat(UnitSystemScope.systemOf(context)).dist(kFloorWidthM, decimals: 0)} x '
            '${LengthFormat(UnitSystemScope.systemOf(context)).dist(kFloorDepthM, decimals: 0)})',
          ),
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'A teaching model: every AP radiates the same way in every '
              'direction and there are no walls. Signal falls with distance '
              'and wanders a little (shadowing).',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          if (fill) Expanded(child: floor) else floor,
          const SizedBox(height: AppSpacing.xs),
          if (c.drawing)
            _DrawBar(controller: c)
          else ...<Widget>[
            _FloorLegend(style: widget.style, apCount: cfg.aps.length),
            if (!fill) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Drag an AP to move it.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _plan(RoamWalkConfig cfg) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints bc) {
      _size = Size(bc.maxWidth, bc.maxHeight);
      final FloorMapping m = FloorMapping(_size);
      return MouseRegion(
        cursor: c.drawing
            ? SystemMouseCursors.precise
            : SystemMouseCursors.basic,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: <Type, GestureRecognizerFactory>{
            _ApDragRecognizer:
                GestureRecognizerFactoryWithHandlers<_ApDragRecognizer>(
                  () => _ApDragRecognizer(claims: _claims),
                  (_ApDragRecognizer r) {
                    r
                      ..onStart = (DragStartDetails d) {
                        _dragging = c.apNear(
                          m.toFloor(d.localPosition),
                          _hitRadiusM(m),
                        );
                      }
                      ..onUpdate = (DragUpdateDetails d) {
                        final int? i = _dragging;
                        if (i != null) {
                          c.moveAp(i, m.toFloor(d.localPosition));
                        }
                      }
                      ..onEnd = (DragEndDetails _) {
                        _dragging = null;
                      }
                      ..onCancel = () {
                        _dragging = null;
                      };
                  },
                ),
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (TapGestureRecognizer r) {
                    r.onTapUp = (TapUpDetails d) {
                      if (c.drawing) {
                        c.addWaypoint(m.toFloor(d.localPosition));
                        return;
                      }
                      final int? i = c.apNear(
                        m.toFloor(d.localPosition),
                        _hitRadiusM(m),
                      );
                      if (i != null) c.editingAp = i;
                    };
                  },
                ),
          },
          child: CustomPaint(
            size: _size,
            painter: RoamFloorPainter(
              config: cfg,
              result: c.result,
              sample: c.sample,
              style: widget.style,
              editingAp: c.editingAp,
              drawnPoints: List<FloorPoint>.of(c.drawnPoints),
              drawing: c.drawing,
              units: c.units,
            ),
          ),
        ),
      );
    },
  );
}

class _DrawBar extends StatelessWidget {
  const _DrawBar({required this.controller});

  final RoamingWalkController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final RoamingWalkController c = controller;
    final int n = c.drawnPoints.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          child: Text(
            n == 0
                ? 'Drawing a path: tap the floor where the walk starts, then '
                      'tap each turn.'
                : n == 1
                ? '1 point. Tap the next one.'
                : '$n points, ${pathLengthM(c.drawnPoints).toStringAsFixed(0)} '
                      'm. Tap to add more, or Use this path.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            SizedBox(
              width: 160,
              child: FilledButton(
                onPressed: c.canFinishDrawing ? c.finishDrawing : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
                ),
                child: const Text('Use this path'),
              ),
            ),
            SizedBox(
              width: 120,
              child: RwOutlineButton(
                icon: Icons.undo_rounded,
                label: 'Undo',
                semanticLabel: 'Remove the last point',
                onPressed: n > 0 ? c.undoWaypoint : null,
              ),
            ),
            SizedBox(
              width: 120,
              child: RwOutlineButton(
                icon: Icons.close_rounded,
                label: 'Cancel',
                semanticLabel: 'Stop drawing and keep the old path',
                onPressed: c.cancelDrawing,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FloorLegend extends StatelessWidget {
  const _FloorLegend({required this.style, required this.apCount});

  final RoamPaintStyle style;
  final int apCount;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle t =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    Widget line(Color color, {bool dashed = false, double width = 2}) =>
        SizedBox(
          width: 20,
          child: dashed
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Container(width: 6, height: width, color: color),
                    Container(width: 6, height: width, color: color),
                  ],
                )
              : Container(height: width, color: color),
        );
    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        swatch,
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: t),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          item(line(colors.textSecondary), '-67 dBm'),
          item(line(colors.textSecondary, dashed: true), '-70 dBm'),
          item(line(style.accent, width: 3), 'Serving link'),
          item(
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: style.primary,
                shape: BoxShape.circle,
              ),
            ),
            'Client',
          ),
        ],
      ),
    );
  }
}

class _PlotCard extends StatelessWidget {
  const _PlotCard({
    required this.controller,
    required this.style,
    this.fill = false,
  });

  final RoamingWalkController controller;
  final RoamPaintStyle style;

  /// Presenter: fill a bounded box. The "now" line is on the strip over the
  /// floor, and the marker note is in the help.
  final bool fill;

  String _semantic() {
    final RoamingWalkController c = controller;
    final RoamWalkResult r = c.result;
    final int k = c.sample;
    final RoamTotals t = c.totals;
    final StringBuffer b = StringBuffer(
      'Signal from every AP over the walk, ${r.timeOf(k).toStringAsFixed(1)} '
      'of ${r.durationS.toStringAsFixed(1)} seconds shown. Trigger at '
      '${fmtDbm(c.config.triggerDbm)}. Now: ',
    );
    for (int a = 0; a < r.rssi.length; a++) {
      b.write('AP ${a + 1} ${fmtDbm(r.rssi[a][k])}. ');
    }
    b.write('${t.roams} roams so far.');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoamingWalkController c = controller;
    final bool wide = MediaQuery.sizeOf(context).width >= 720;
    final int k = c.sample;
    final RoamWalkResult r = c.result;
    final int? s = r.servingAt(k);
    final RoamEvent? gap = r.gapAt(k);
    final String now = s != null
        ? 'On AP ${s + 1} at ${fmtDbm(r.rssi[s][k])}'
        : gap != null
        ? 'Between APs: roaming to AP ${gap.toAp + 1}'
        : 'Between APs';
    final Widget plot = Semantics(
      label: _semantic(),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: fill ? null : (wide ? 260 : 200),
          color: colors.surface2,
          child: CustomPaint(
            painter: RoamRssiPainter(result: r, sample: k, style: style),
            size: Size.infinite,
          ),
        ),
      ),
    );
    return RwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const RwSectionLabel('Signal from every AP (dBm) over time'),
          const SizedBox(height: AppSpacing.xs),
          if (fill) Expanded(child: plot) else plot,
          const SizedBox(height: AppSpacing.xs),
          ExcludeSemantics(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                for (int a = 0; a < c.apCount; a++)
                  _Swatch(color: style.ap(a), label: 'AP ${a + 1}'),
                _Swatch(color: style.accent, label: 'Serving', thick: true),
                _Swatch(
                  color: colors.borderStrong,
                  label: 'Trigger',
                  dashed: true,
                ),
              ],
            ),
          ),
          if (!fill) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Each vertical line is a roam; the number above it is the gap '
              'in ms with no AP. PP marks a ping-pong.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Semantics(
              liveRegion: false,
              child: Text(
                '${r.timeOf(k).toStringAsFixed(1)} s of '
                '${r.durationS.toStringAsFixed(1)} s. $now.',
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    this.thick = false,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool thick;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double h = thick ? 3 : 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 20,
          child: dashed
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Container(width: 6, height: h, color: color),
                    Container(width: 6, height: h, color: color),
                  ],
                )
              : Container(height: h, color: color),
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
}

// ── Presenter strip ─────────────────────────────────────────────────────────

/// Presenter only: the client's AP and signal right now (the headline), then
/// the walk time, roams so far, the gap per roam, and the two warnings.
class _NowStrip extends StatelessWidget {
  const _NowStrip({required this.controller});

  final RoamingWalkController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final RoamingWalkController c = controller;
    final RoamWalkResult r = c.result;
    final RoamWalkConfig cfg = c.config;
    final int k = c.sample;
    final int? s = r.servingAt(k);
    final RoamEvent? gap = r.gapAt(k);
    final RoamTotals t = c.totals;
    final RoamCost first = cfg.costFor(cfg.authMethodFor(joinedBefore: false));

    final String now = s != null
        ? 'AP ${s + 1}, ${fmtDbm(r.rssi[s][k])}'
        : gap != null
        ? 'Roaming to AP ${gap.toAp + 1}'
        : 'Between APs';

    Widget stat(String label, String value, {Color? color}) => MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: mono.outputMedium.copyWith(
              color: color ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );

    Widget warn(String message) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.warning_amber_rounded, color: colors.statusWarning),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          message,
          style: text.bodyMedium?.copyWith(color: colors.statusWarning),
        ),
      ],
    );

    return RwCard(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: <Widget>[
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Client now',
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      Text(
                        now,
                        style: sc
                            .headlineStyle(mono.outputLarge)
                            .copyWith(
                              color: s != null
                                  ? colors.textAccent
                                  : colors.textPrimary,
                            ),
                      ),
                    ],
                  ),
                ),
                stat(
                  'Walk',
                  '${r.timeOf(k).toStringAsFixed(1)} of '
                      '${r.durationS.toStringAsFixed(1)} s',
                ),
                stat('Roams', '${t.roams}'),
                stat('Gap per roam', fmtMs(first.totalMs)),
              ],
            ),
            if (t.pingPongs > 0 || t.secondsBelowWeak > 0) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xxs,
                children: <Widget>[
                  if (t.pingPongs > 0)
                    warn(
                      '${t.pingPongs} ping-pong'
                      '${t.pingPongs == 1 ? '' : 's'}',
                    ),
                  if (t.secondsBelowWeak > 0)
                    warn(
                      '${t.secondsBelowWeak.toStringAsFixed(1)} s below '
                      '-70 dBm',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
