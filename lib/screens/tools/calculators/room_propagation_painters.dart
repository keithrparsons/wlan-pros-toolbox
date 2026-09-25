// Painters for the Room Propagation stage: the average heat map, the plan
// overlay (walls, doorways, markers, Fresnel zone, shadow edges, the wall
// being drawn) and the close-up of the fine ripple.
//
// Everything is drawn on the dark viewport (AppCoverageRamp.viewport) in both
// themes. Heat-map cells are flat fills of one GL-003 §8.22 ramp stop. Walls
// and markers carry a dark casing so they read on every stop. Nothing
// animates, so no drawing can suggest a change of frequency: the close-up
// shows the ripple's true spacing for the selected channel.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/room_propagation_model.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_coverage_ramp.dart';

/// Meters to pixels for a plan drawn from its top-left corner.
class PlanTransform {
  const PlanTransform(this.scale, [this.origin = const P2(0, 0)]);

  /// Pixels per meter.
  final double scale;

  /// The plan point drawn at pixel (0, 0).
  final P2 origin;

  Offset toPx(P2 p) =>
      Offset((p.x - origin.x) * scale, (p.y - origin.y) * scale);

  P2 toPlan(Offset o) => P2(o.dx / scale + origin.x, o.dy / scale + origin.y);
}

/// Flat-fill heat map of a [FieldGrid]: each cell takes the ramp stop for
/// value + [offsetDb] against [edges].
class HeatMapPainter extends CustomPainter {
  HeatMapPainter({
    required this.grid,
    required this.transform,
    required this.offsetDb,
    required this.edges,
    required this.revision,
  });

  final FieldGrid? grid;
  final PlanTransform transform;
  final double offsetDb;
  final List<double> edges;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppCoverageRamp.viewport,
    );
    final FieldGrid? g = grid;
    if (g == null) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final Paint paint = Paint()..isAntiAlias = false;
    for (int row = 0; row < g.rows; row++) {
      final double y0 = g.origin.y + row * g.cellM;
      int start = 0;
      int stop = AppCoverageRamp.stopFor(g.at(0, row) + offsetDb, edges);
      for (int col = 1; col <= g.cols; col++) {
        final int s = col < g.cols
            ? AppCoverageRamp.stopFor(g.at(col, row) + offsetDb, edges)
            : -1;
        if (s == stop) continue;
        if (stop > 0) {
          final Offset a = transform.toPx(P2(g.origin.x + start * g.cellM, y0));
          final Offset b = transform.toPx(
            P2(g.origin.x + col * g.cellM, y0 + g.cellM),
          );
          paint.color = AppCoverageRamp.stops[stop];
          canvas.drawRect(Rect.fromPoints(a, b), paint);
        }
        start = col;
        stop = s;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HeatMapPainter old) =>
      old.revision != revision ||
      old.offsetDb != offsetDb ||
      old.transform.scale != transform.scale ||
      old.transform.origin != transform.origin ||
      !identical(old.grid, grid);
}

/// What the overlay draws. A snapshot, so the painter can compare cheaply.
class PlanOverlayData {
  const PlanOverlayData({
    required this.widthM,
    required this.heightM,
    required this.walls,
    required this.ap,
    required this.client,
    required this.lambda,
    required this.selectedWall,
    required this.showFresnel,
    required this.showShadows,
    required this.showCloseUpBox,
    required this.draft,
  });

  final double widthM;
  final double heightM;
  final List<RoomWall> walls;
  final P2 ap;
  final P2 client;
  final double lambda;
  final int? selectedWall;
  final bool showFresnel;
  final bool showShadows;
  final bool showCloseUpBox;
  final (P2, P2)? draft;
}

/// Walls, doorways, markers and the optional overlays.
class PlanOverlayPainter extends CustomPainter {
  PlanOverlayPainter({
    required this.data,
    required this.transform,
    required this.labelStyle,
    this.drawMarkers = true,
    this.drawLabels = true,
  });

  final PlanOverlayData data;
  final PlanTransform transform;
  final TextStyle labelStyle;
  final bool drawMarkers;
  final bool drawLabels;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (data.showShadows) _shadows(canvas, size);
    for (int i = 0; i < data.walls.length; i++) {
      paintWall(canvas, transform, data.walls[i], i == data.selectedWall);
    }
    if (data.showFresnel) _fresnel(canvas);
    if (data.showCloseUpBox) _closeUpBox(canvas);
    final (P2, P2)? d = data.draft;
    if (d != null) _draft(canvas, d);
    if (drawMarkers) {
      _marker(canvas, data.client, isAp: false);
      _marker(canvas, data.ap, isAp: true);
    }
    final int? sel = data.selectedWall;
    if (drawLabels && sel != null && sel < data.walls.length) {
      final RoomWall w = data.walls[sel];
      _pill(
        canvas,
        transform.toPx(w.pointAt(w.length / 2)),
        'Wall ${sel + 1}',
        above: true,
      );
    }
    canvas.restore();
  }

  /// One wall: dark casing, hue core scaled to its thickness (3 to 8 px),
  /// doorways left open with a short jamb tick. The selected wall gets end
  /// handles.
  static void paintWall(
    Canvas canvas,
    PlanTransform t,
    RoomWall w,
    bool selected,
  ) {
    final double core =
        (w.thicknessMm / 1000 * t.scale).clamp(3.0, 8.0) *
        (w.material == WallMaterial.metal ? 1.25 : 1);
    final Paint casing = Paint()
      ..color = AppCoverageRamp.casing
      ..strokeWidth = core + 3
      ..strokeCap = StrokeCap.butt;
    final Paint fill = Paint()
      ..color = AppCoverageRamp.wall(w.material)
      ..strokeWidth = core
      ..strokeCap = StrokeCap.butt;
    for (final (double, double) pc in w.solidPieces) {
      final Offset a = t.toPx(w.pointAt(pc.$1));
      final Offset b = t.toPx(w.pointAt(pc.$2));
      canvas.drawLine(a, b, casing);
      canvas.drawLine(a, b, fill);
    }
    // Jamb ticks: a short casing-colored cross bar at each door edge.
    final double l = w.length;
    if (l > 0 && w.doors.isNotEmpty) {
      final P2 u = (w.b - w.a).scale(1 / l);
      final Offset n = Offset(-u.y, u.x) * (core / 2 + 3);
      final Paint jamb = Paint()
        ..color = AppCoverageRamp.viewportText
        ..strokeWidth = 1.5;
      for (final P2 j in w.doorJambs) {
        final Offset c = t.toPx(j);
        canvas.drawLine(c - n, c + n, jamb);
      }
    }
    if (selected) {
      final Paint handle = Paint()..color = AppCoverageRamp.viewportText;
      final Paint ring = Paint()
        ..color = AppCoverageRamp.casing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (final P2 e in <P2>[w.a, w.b]) {
        final Rect r = Rect.fromCenter(
          center: t.toPx(e),
          width: 10,
          height: 10,
        );
        canvas.drawRect(r, handle);
        canvas.drawRect(r, ring);
      }
    }
  }

  void _shadows(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = AppCoverageRamp.viewportMuted
      ..strokeWidth = 1.5;
    final Paint casing = Paint()
      ..color = AppCoverageRamp.casing
      ..strokeWidth = 3.5;
    for (final RoomWall w in data.walls) {
      for (final P2 j in w.doorJambs) {
        final P2 d = j - data.ap;
        final double len = d.length;
        if (len < 0.05) continue;
        final P2 u = d.scale(1 / len);
        final double tExit = _exitDistance(j, u);
        if (tExit <= 0) continue;
        final P2 end = j + u.scale(tExit);
        dashedLine(
          canvas,
          transform.toPx(j),
          transform.toPx(end),
          casing,
          6,
          4,
        );
        dashedLine(canvas, transform.toPx(j), transform.toPx(end), p, 6, 4);
      }
    }
  }

  /// Distance from [p] along unit [u] to the plan edge.
  double _exitDistance(P2 p, P2 u) {
    double t = double.infinity;
    if (u.x > 1e-9) t = math.min(t, (data.widthM - p.x) / u.x);
    if (u.x < -1e-9) t = math.min(t, -p.x / u.x);
    if (u.y > 1e-9) t = math.min(t, (data.heightM - p.y) / u.y);
    if (u.y < -1e-9) t = math.min(t, -p.y / u.y);
    return t.isFinite ? t : 0;
  }

  void _fresnel(Canvas canvas) {
    final double d = data.ap.distanceTo(data.client);
    if (d < 0.2) return;
    final double a = (d + data.lambda / 2) / 2;
    final double b = math.sqrt(math.max(0, a * a - d * d / 4));
    final P2 m = (data.ap + data.client).scale(0.5);
    final double ang = math.atan2(
      data.client.y - data.ap.y,
      data.client.x - data.ap.x,
    );
    canvas.save();
    canvas.translate(transform.toPx(m).dx, transform.toPx(m).dy);
    canvas.rotate(ang);
    final Rect r = Rect.fromCenter(
      center: Offset.zero,
      width: 2 * a * transform.scale,
      height: math.max(2 * b * transform.scale, 2),
    );
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = AppCoverageRamp.casing,
    );
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppCoverageRamp.viewportText,
    );
    canvas.restore();
  }

  void _closeUpBox(Canvas canvas) {
    final Offset c = transform.toPx(data.client);
    final double s = math.max(kRippleWindowM * transform.scale, 6);
    final Rect r = Rect.fromCenter(center: c, width: s, height: s);
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppCoverageRamp.casing,
    );
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppCoverageRamp.viewportText,
    );
  }

  void _draft(Canvas canvas, (P2, P2) d) {
    final Offset a = transform.toPx(d.$1);
    final Offset b = transform.toPx(d.$2);
    dashedLine(
      canvas,
      a,
      b,
      Paint()
        ..color = AppCoverageRamp.casing
        ..strokeWidth = 6,
      8,
      5,
    );
    dashedLine(
      canvas,
      a,
      b,
      Paint()
        ..color = AppCoverageRamp.viewportText
        ..strokeWidth = 3,
      8,
      5,
    );
    final double len = d.$1.distanceTo(d.$2);
    if (drawLabels) {
      _pill(
        canvas,
        Offset.lerp(a, b, 0.5)!,
        '${len.toStringAsFixed(1)} m',
        above: true,
      );
    }
  }

  void _marker(Canvas canvas, P2 p, {required bool isAp}) {
    final Offset c = transform.toPx(p);
    final Paint casing = Paint()..color = AppCoverageRamp.casing;
    final Paint ink = Paint()..color = AppCoverageRamp.viewportText;
    if (isAp) {
      canvas.drawCircle(c, 9, casing);
      canvas.drawCircle(c, 7, ink);
      canvas.drawCircle(c, 2.5, casing);
    } else {
      canvas.drawCircle(c, 9, casing);
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = AppCoverageRamp.viewportText,
      );
    }
    if (drawLabels) {
      _pill(
        canvas,
        c + const Offset(0, -14),
        isAp ? 'AP' : 'Client',
        above: true,
      );
    }
  }

  /// A small dark label with light text, so it reads on any stop.
  void _pill(Canvas canvas, Offset anchor, String text, {bool above = false}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(color: AppCoverageRamp.viewportText),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const double padH = 4;
    const double padV = 1;
    final double w = tp.width + padH * 2;
    final double h = tp.height + padV * 2;
    double left = anchor.dx - w / 2;
    double top = above ? anchor.dy - h : anchor.dy;
    final Rect bounds = canvas.getLocalClipBounds();
    left = left.clamp(
      bounds.left + 2,
      math.max(bounds.left + 2, bounds.right - w - 2),
    );
    top = top.clamp(
      bounds.top + 2,
      math.max(bounds.top + 2, bounds.bottom - h - 2),
    );
    final RRect r = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(3),
    );
    canvas.drawRRect(r, Paint()..color = AppCoverageRamp.casing);
    tp.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(PlanOverlayPainter old) =>
      old.data != data ||
      old.transform.scale != transform.scale ||
      old.transform.origin != transform.origin ||
      old.labelStyle != labelStyle;
}

/// Draws [a] -> [b] as dashes.
void dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint,
  double dash,
  double gap,
) {
  final Offset d = b - a;
  final double len = d.distance;
  if (len <= 0) return;
  final Offset u = d / len;
  double t = 0;
  while (t < len) {
    final double e = math.min(t + dash, len);
    canvas.drawLine(a + u * t, a + u * e, paint);
    t = e + gap;
  }
}

/// The close-up: the fine ripple around the client, the walls inside the
/// window, the client, and a ruler with a tick every half wavelength laid
/// along the nearest wall's normal (or across the window when no wall is
/// near).
class RipplePainter extends CustomPainter {
  RipplePainter({
    required this.grid,
    required this.walls,
    required this.client,
    required this.lambda,
    required this.rulerNormal,
    required this.labelStyle,
    required this.revision,
  });

  final FieldGrid? grid;
  final List<RoomWall> walls;
  final P2 client;
  final double lambda;

  /// Unit direction for the ruler (the nearest wall's normal).
  final P2 rulerNormal;
  final TextStyle labelStyle;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final FieldGrid? g = grid;
    final double sizeM = g == null ? kRippleWindowM : g.cols * g.cellM;
    final P2 origin =
        g?.origin ??
        P2(client.x - kRippleWindowM / 2, client.y - kRippleWindowM / 2);
    final PlanTransform t = PlanTransform(size.width / sizeM, origin);
    HeatMapPainter(
      grid: g,
      transform: t,
      offsetDb: 0,
      edges: AppCoverageRamp.rippleEdgesDb,
      revision: revision,
    ).paint(canvas, size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final RoomWall w in walls) {
      PlanOverlayPainter.paintWall(canvas, t, w, false);
    }
    _ruler(canvas, t, size);
    final Offset c = t.toPx(client);
    canvas.drawCircle(c, 7, Paint()..color = AppCoverageRamp.casing);
    canvas.drawCircle(
      c,
      4.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppCoverageRamp.viewportText,
    );
    canvas.restore();
  }

  void _ruler(Canvas canvas, PlanTransform t, Size size) {
    const int ticks = 4;
    final double half = lambda / 2;
    final P2 u = rulerNormal;
    final P2 start = client - u.scale(half * ticks / 2);
    final P2 end = client + u.scale(half * ticks / 2);
    final Offset a = t.toPx(start);
    final Offset b = t.toPx(end);
    // Offset the ruler sideways so it does not sit on the client marker.
    final Offset side = Offset(-u.y, u.x) * 18;
    final Paint casing = Paint()
      ..color = AppCoverageRamp.casing
      ..strokeWidth = 5;
    final Paint ink = Paint()
      ..color = AppCoverageRamp.viewportText
      ..strokeWidth = 2;
    canvas.drawLine(a + side, b + side, casing);
    canvas.drawLine(a + side, b + side, ink);
    final Offset tick = Offset(-u.y, u.x) * 6;
    for (int i = 0; i <= ticks; i++) {
      final Offset p = t.toPx(start + u.scale(half * i)) + side;
      canvas.drawLine(p - tick, p + tick, casing);
      canvas.drawLine(p - tick, p + tick, ink);
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text:
            'ticks every half wavelength, ${(half * 100).toStringAsFixed(1)} cm',
        style: labelStyle.copyWith(color: AppCoverageRamp.viewportText),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 8);
    final Rect r = Rect.fromLTWH(4, 4, tp.width + 8, tp.height + 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()..color = AppCoverageRamp.casing,
    );
    tp.paint(canvas, const Offset(8, 5));
  }

  @override
  bool shouldRepaint(RipplePainter old) =>
      old.revision != revision ||
      !identical(old.grid, grid) ||
      old.client != client ||
      old.lambda != lambda ||
      old.rulerNormal != rulerNormal ||
      old.walls != walls;
}
