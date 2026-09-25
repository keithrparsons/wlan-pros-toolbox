// RoomPropagationStage: the pictures half of Room Propagation.
//
// The floor plan with its heat map of received power (local average), the
// walls by material, the AP and client, and the optional overlays; the dBm
// legend (always shown); and the close-up of the fine ripple around the
// client with its half-wavelength ruler. Takes the shared
// RoomPropagationController and nothing else, so a phone layout can stack it
// with the controls and a presenter layout can put the two side by side.
//
// Drags and taps on the plan act through the controller according to the
// selected tool. Every one of them has a keyboard path in the controls (the
// position sliders, the wall list and its editor), so the plan is a shortcut,
// never the only way.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/room_propagation_model.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_coverage_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'room_propagation_controller.dart';
import 'room_propagation_painters.dart';
import 'wifi_through_a_wall_parts.dart'
    show WallCard, WallSectionLabel, WallNote;

typedef _C = RoomPropagationController;

class RoomPropagationStage extends StatelessWidget {
  const RoomPropagationStage({super.key, required this.controller});

  final RoomPropagationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _PlanCard(controller: controller),
            if (controller.showCloseUp) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _CloseUpCard(controller: controller),
            ],
          ],
        );
      },
    );
  }
}

TextStyle _labelStyle(BuildContext context) {
  final AppMonoText mono =
      Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
  return mono.inlineCode.copyWith(fontSize: AppTextSize.caption - 2);
}

// ── Plan ──────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.controller});

  final RoomPropagationController controller;

  String get _toolHint => switch (controller.tool) {
    RoomTool.move =>
      'Drag the AP or the client. Tap anywhere to put the client there.',
    RoomTool.wall =>
      'Drag to draw a wall of ${controller.newMaterial.label.toLowerCase()}, '
          '${_C.fmtMm(controller.newThicknessMm)} mm. Ends snap to 10 cm and '
          'to other wall ends.',
    RoomTool.door => 'Tap a wall to open a 0.9 m doorway in it.',
    RoomTool.select => 'Tap a wall to select it, then edit it below.',
  };

  String _semantic() {
    final RoomPropagationController c = controller;
    final StringBuffer b = StringBuffer(
      'Floor plan, ${_C.fmt1(c.widthM)} by ${_C.fmt1(c.heightM)} meters, '
      '${c.walls.length} walls. Heat map of received power, local average. ',
    );
    b.write(
      'AP at ${_C.fmt1(c.ap.x)}, ${_C.fmt1(c.ap.y)} meters. Client at '
      '${_C.fmt1(c.client.x)}, ${_C.fmt1(c.client.y)} meters, receiving '
      '${_C.dbm(c.clientDbm)} at that exact spot. ',
    );
    b.write(
      'Move the AP and client with the position sliders, and edit walls in '
      'the wall list, below.',
    );
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoomPropagationController c = controller;
    final String? err = c.error;
    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: WallSectionLabel('Received power on the floor plan'),
              ),
              if (c.computing) const _Computing(),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${c.tool.label} tool: $_toolHint',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: _semantic(),
            excludeSemantics: true,
            child: _PlanView(controller: c),
          ),
          if (c.message != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            WallNote(icon: Icons.info_outline, message: c.message!),
          ],
          if (err != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            WallNote(icon: Icons.error_outline, message: err),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: c.retry,
                style: TextButton.styleFrom(
                  foregroundColor: colors.textAccent,
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
                child: const Text('Try again'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _PowerLegend(),
          const SizedBox(height: AppSpacing.sm),
          _KeyLegend(controller: c),
          const SizedBox(height: AppSpacing.sm),
          WallNote(
            icon: Icons.grid_on,
            message:
                'Each ${(kRoomCellM * 100).toStringAsFixed(0)} cm cell is '
                'the average of ${kAverageSamples * kAverageSamples} points, '
                'each summing path powers: the fine ripple from reflections '
                'is averaged out here and shown in the close-up. '
                '${_timing(c)}',
          ),
          const SizedBox(height: AppSpacing.xs),
          const WallNote(
            icon: Icons.layers_outlined,
            message:
                'A 2D plan of a 3D model: the signal spreads in three '
                'dimensions (1/r), but there is no floor or ceiling bounce.',
          ),
        ],
      ),
    );
  }

  static String _timing(RoomPropagationController c) {
    final FieldGrid? g = c.averageGrid;
    final int? ms = c.averageMs;
    if (g == null || ms == null) return '';
    final int cells = g.cols * g.rows;
    final int points = cells * kAverageSamples * kAverageSamples;
    return 'This map: ${_thousands(cells)} cells, ${_thousands(points)} '
        'points, in ${ms < 1 ? 'under 1' : ms} ms.';
  }

  static String _thousands(int n) => n >= 1000
      ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}'
      : '$n';
}

class _Computing extends StatelessWidget {
  const _Computing();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      liveRegion: true,
      label: 'Computing the map',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textAccent,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Computing',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PlanView extends StatefulWidget {
  const _PlanView({required this.controller});

  final RoomPropagationController controller;

  @override
  State<_PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<_PlanView> {
  RoomMarker? _dragging;

  RoomPropagationController get _c => widget.controller;

  /// Touch tolerance, px.
  static const double _grabPx = 28;

  void _panStart(Offset o, PlanTransform t) {
    final P2 p = t.toPlan(o);
    switch (_c.tool) {
      case RoomTool.move:
        final double dAp = (t.toPx(_c.ap) - o).distance;
        final double dCl = (t.toPx(_c.client) - o).distance;
        if (dAp <= _grabPx && dAp <= dCl) {
          _dragging = RoomMarker.ap;
        } else {
          _dragging = RoomMarker.client;
          _c.moveClient(p);
        }
      case RoomTool.wall:
        _c.startWall(p);
      case RoomTool.door:
      case RoomTool.select:
        break;
    }
  }

  void _panUpdate(Offset o, PlanTransform t) {
    final P2 p = t.toPlan(o);
    switch (_c.tool) {
      case RoomTool.move:
        if (_dragging == RoomMarker.ap) {
          _c.moveAp(p);
        } else if (_dragging == RoomMarker.client) {
          _c.moveClient(p);
        }
      case RoomTool.wall:
        _c.updateWall(p);
      case RoomTool.door:
      case RoomTool.select:
        break;
    }
  }

  void _panEnd() {
    _dragging = null;
    if (_c.tool == RoomTool.wall) _c.endWall();
  }

  void _tap(Offset o, PlanTransform t) {
    final P2 p = t.toPlan(o);
    final double tol = _grabPx / t.scale;
    switch (_c.tool) {
      case RoomTool.move:
        _c.moveClient(p);
      case RoomTool.wall:
        break;
      case RoomTool.door:
        _c.tapDoor(p, tol);
      case RoomTool.select:
        _c.tapSelect(p, tol);
    }
  }

  @override
  Widget build(BuildContext context) {
    final RoomPropagationController c = _c;
    final TextStyle label = _labelStyle(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double w = box.maxWidth;
        final double h = w * c.heightM / c.widthM;
        final PlanTransform t = PlanTransform(w / c.widthM);
        final FieldGrid? grid = c.averageGrid;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: SizedBox(
            width: w,
            height: h,
            child: MouseRegion(
              cursor: c.tool == RoomTool.wall
                  ? SystemMouseCursors.precise
                  : SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) => _tap(d.localPosition, t),
                onPanStart: c.tool == RoomTool.move || c.tool == RoomTool.wall
                    ? (DragStartDetails d) => _panStart(d.localPosition, t)
                    : null,
                onPanUpdate: c.tool == RoomTool.move || c.tool == RoomTool.wall
                    ? (DragUpdateDetails d) => _panUpdate(d.localPosition, t)
                    : null,
                onPanEnd: c.tool == RoomTool.move || c.tool == RoomTool.wall
                    ? (DragEndDetails _) => _panEnd()
                    : null,
                onPanCancel: () {
                  _dragging = null;
                  c.cancelWall();
                },
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: HeatMapPainter(
                            grid: grid,
                            transform: t,
                            offsetDb: c.eirpDbm,
                            edges: AppCoverageRamp.powerEdgesDbm,
                            revision: c.revision,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PlanOverlayPainter(
                          data: PlanOverlayData(
                            widthM: c.widthM,
                            heightM: c.heightM,
                            walls: c.walls,
                            ap: c.ap,
                            client: c.client,
                            lambda: c.lambda,
                            selectedWall: c.selectedWall,
                            showFresnel: c.showFresnel,
                            showShadows: c.showShadows,
                            showCloseUpBox: c.showCloseUp,
                            draft: c.draft,
                          ),
                          transform: t,
                          labelStyle: label,
                        ),
                      ),
                    ),
                    if (grid == null)
                      Positioned.fill(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.xxs,
                            ),
                            color: AppCoverageRamp.casing,
                            child: Text(
                              c.error == null
                                  ? 'Computing the map'
                                  : 'No map yet',
                              style: label.copyWith(
                                color: AppCoverageRamp.viewportText,
                                fontSize: AppTextSize.caption,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Legends ───────────────────────────────────────────────────────────────

/// A stepped legend: one swatch per ramp stop, the stop's lower edge under
/// it.
class _StepLegend extends StatelessWidget {
  const _StepLegend({
    required this.title,
    required this.labels,
    required this.semantic,
    this.firstStop = 0,
  });

  final String title;

  /// One label per swatch, lowest first.
  final List<String> labels;
  final String semantic;

  /// Ramp stop of the first swatch.
  final int firstStop;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle label = _labelStyle(
      context,
    ).copyWith(color: colors.textSecondary);
    return Semantics(
      label: semantic,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: <Widget>[
              for (int i = 0; i < labels.length; i++)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppCoverageRamp.stops[firstStop + i],
                          border: Border.all(
                            color: colors.borderStrong,
                            width: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(labels[i], style: label, maxLines: 1),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PowerLegend extends StatelessWidget {
  const _PowerLegend();

  @override
  Widget build(BuildContext context) {
    const List<double> e = AppCoverageRamp.powerEdgesDbm;
    return _StepLegend(
      title: 'Received power, dBm (each color starts at the number under it)',
      labels: <String>[
        '<${e.first.toStringAsFixed(0)}',
        for (final double v in e) v.toStringAsFixed(0),
      ],
      semantic:
          'Legend: eight shades of green from dark to pale. Darkest, below '
          '${e.first.toStringAsFixed(0)} dBm; then one shade per 10 dB up '
          'to the palest, ${e.last.toStringAsFixed(0)} dBm and stronger.',
    );
  }
}

/// Wall materials on the plan, plus the markers and overlays.
class _KeyLegend extends StatelessWidget {
  const _KeyLegend({required this.controller});

  final RoomPropagationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: colors.textSecondary);
    final List<WallMaterial> mats = <WallMaterial>[
      for (final WallMaterial m in WallMaterial.values)
        if (controller.walls.any((RoomWall w) => w.material == m)) m,
    ];
    final bool doors = controller.walls.any((RoomWall w) => w.doors.isNotEmpty);
    Widget item(Widget swatch, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: swatch),
        const SizedBox(width: AppSpacing.xxs),
        Text(text, style: style),
      ],
    );
    Widget line(Color c) => Container(
      width: 22,
      height: 10,
      color: AppCoverageRamp.casing,
      alignment: Alignment.center,
      child: Container(width: 20, height: 4, color: c),
    );
    Widget marker(bool ap) => SizedBox(
      width: 22,
      height: 18,
      child: CustomPaint(painter: _MarkerSwatch(ap: ap)),
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        item(marker(true), 'AP'),
        item(marker(false), 'Client'),
        for (final WallMaterial m in mats)
          item(line(AppCoverageRamp.wall(m)), m.label),
        if (doors) item(line(AppCoverageRamp.casing), 'Doorway (gap)'),
        if (controller.showFresnel)
          item(
            SizedBox(
              width: 22,
              height: 14,
              child: CustomPaint(painter: _EllipseSwatch()),
            ),
            '1st Fresnel zone, AP to client',
          ),
        if (controller.showShadows && doors)
          item(
            SizedBox(
              width: 22,
              height: 10,
              child: CustomPaint(painter: _DashSwatch()),
            ),
            'Doorway shadow edge (straight line)',
          ),
      ],
    );
  }
}

class _MarkerSwatch extends CustomPainter {
  _MarkerSwatch({required this.ap});

  final bool ap;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint()..color = AppCoverageRamp.viewport,
    );
    final Offset c = size.center(Offset.zero);
    if (ap) {
      canvas.drawCircle(c, 6, Paint()..color = AppCoverageRamp.viewportText);
      canvas.drawCircle(c, 2, Paint()..color = AppCoverageRamp.casing);
    } else {
      canvas.drawCircle(
        c,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = AppCoverageRamp.viewportText,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkerSwatch old) => old.ap != ap;
}

class _EllipseSwatch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint()..color = AppCoverageRamp.viewport,
    );
    canvas.drawOval(
      (Offset.zero & size).deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppCoverageRamp.viewportText,
    );
  }

  @override
  bool shouldRepaint(_EllipseSwatch old) => false;
}

class _DashSwatch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppCoverageRamp.viewport,
    );
    dashedLine(
      canvas,
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = AppCoverageRamp.viewportMuted
        ..strokeWidth = 1.5,
      6,
      4,
    );
  }

  @override
  bool shouldRepaint(_DashSwatch old) => false;
}

// ── Close-up ──────────────────────────────────────────────────────────────

class _CloseUpCard extends StatelessWidget {
  const _CloseUpCard({required this.controller});

  final RoomPropagationController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RoomPropagationController c = controller;
    final (double, double)? range = c.rippleRange;
    final double half = c.lambda / 2;
    final (int, double)? near = c.wallNearClient;

    P2 normal = const P2(1, 0);
    String nearText = 'There is no wall on the plan, so there is no ripple.';
    if (near != null) {
      final RoomWall w = c.walls[near.$1];
      final double l = w.length;
      if (l > 0) {
        final P2 u = (w.b - w.a).scale(1 / l);
        normal = P2(-u.y, u.x);
      }
      nearText =
          'Nearest wall: ${c.wallName(near.$1).split(': ').last}, '
          '${_C.meters(near.$2)} away. The ruler runs toward it.';
    }

    final String swing = range == null
        ? 'The close-up is being computed.'
        : 'Across this ${(kRippleWindowM * 100).toStringAsFixed(0)} cm '
              'square the signal swings from ${_C.signedDb(range.$1)} to '
              '${_C.signedDb(range.$2)} around the average: moving the phone '
              'a few centimeters changes RSSI.';

    final List<String> labels = <String>[
      '<${AppCoverageRamp.rippleEdgesDb[1].toStringAsFixed(0)}',
      for (final double v in AppCoverageRamp.rippleEdgesDb.skip(1))
        v > 0 ? '+${v.toStringAsFixed(0)}' : v.toStringAsFixed(0),
    ];

    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Close-up: the ripple around the client'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'A ${(kRippleWindowM * 100).toStringAsFixed(0)} cm square '
            'centered on the client (the small square on the plan), every '
            'path added with its phase. Peaks and nulls repeat about every '
            'half wavelength, ${_C.cm(half)} on channel ${c.channel}.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: AspectRatio(
                aspectRatio: 1,
                child: Semantics(
                  label:
                      'Close-up of the fine ripple around the client. $swing '
                      'Peaks repeat every ${_C.cm(half)}.',
                  excludeSemantics: true,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: CustomPaint(
                      painter: RipplePainter(
                        grid: c.rippleGrid,
                        walls: c.walls,
                        client: c.client,
                        lambda: c.lambda,
                        rulerNormal: normal,
                        labelStyle: _labelStyle(context),
                        revision: c.revision,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StepLegend(
            title: 'dB above or below the local average',
            labels: labels,
            firstStop: 1,
            semantic:
                'Legend: seven shades of green. Darkest, more than 12 dB '
                'below the average (a null); then one shade per 3 dB; '
                'palest, more than 3 dB above the average.',
          ),
          const SizedBox(height: AppSpacing.xs),
          WallNote(icon: Icons.swap_vert, message: swing),
          const SizedBox(height: AppSpacing.xxs),
          WallNote(icon: Icons.straighten, message: nearText),
          if (c.rippleMs != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            WallNote(
              icon: Icons.grid_on,
              message:
                  '$kRippleCells x $kRippleCells points, '
                  '${(kRippleWindowM / kRippleCells * 1000).toStringAsFixed(0)} '
                  'mm apart, in ${math.max(1, c.rippleMs!)} ms.',
            ),
          ],
        ],
      ),
    );
  }
}
