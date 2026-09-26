// Painter for the Wi-Fi Classroom Uplink vs Downlink stage (uplink-downlink).
//
// A top-down floor: the AP at the center, the client dot, and two rings. The
// SOLID ring is how far the client can decode the AP (downlink at MCS 0); the
// DASHED ring is how far the AP can decode the client (uplink at MCS 0). The
// band between them, the asymmetry zone, is washed in the accent. Two arrows
// run between the AP and the client, one each way, each with its head and a
// label giving its direction, level and MCS, so direction never rests on
// color (spec 28, "directions identified by label and arrow").
//
// Nothing here draws a wave, so nothing can imply a frequency change
// (Wi-Fi Classroom standing rule).
//
// The geometry is Rate vs Range's (RvrStageGeometry): linear meters, one
// scale shared with the stage's drag handler so a touch and a drawn position
// can never disagree.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../widgets/presenter/presenter_mode.dart';
import 'rate_vs_range_painter.dart' show RvrStageGeometry;

export 'rate_vs_range_painter.dart' show RvrStageGeometry;

@immutable
class UdStageStyle {
  const UdStageStyle({
    required this.surface,
    required this.grid,
    required this.ink,
    required this.down,
    required this.up,
    required this.zone,
    required this.gridLabel,
    required this.label,
    this.scale = PresenterScale.normal,
  });

  final Color surface;
  final Color grid;

  /// AP, client and label text.
  final Color ink;
  final Color down;
  final Color up;

  /// The asymmetry-zone accent (washed for the fill, full for its edge).
  final Color zone;
  final TextStyle gridLabel;
  final TextStyle label;

  /// Presenter scale for strokes and markers. The text styles arrive already
  /// scaled (the stage applies paintFont).
  final PresenterScale scale;
}

class UdStagePainter extends CustomPainter {
  UdStagePainter({
    required this.rangeM,
    required this.downRingM,
    required this.upRingM,
    required this.clientDistanceM,
    required this.clientAngle,
    required this.downLabel,
    required this.upLabel,
    required this.downRingLabel,
    required this.upRingLabel,
    required this.zoneLabel,
    required this.zoneAlpha,
    required this.style,
    required this.revision,
  });

  final double rangeM;
  final double downRingM;
  final double upRingM;
  final double clientDistanceM;
  final double clientAngle;

  /// Arrow labels ("Downlink -66.3 dBm, MCS 4").
  final String downLabel;
  final String upLabel;

  /// Ring labels ("Client decodes AP").
  final String downRingLabel;
  final String upRingLabel;

  /// Null when there is no zone to label.
  final String? zoneLabel;
  final double zoneAlpha;
  final UdStageStyle style;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final RvrStageGeometry g = RvrStageGeometry(size: size, rangeM: rangeM);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _placed.clear();
    _zone(canvas, g);
    _grid(canvas, g);
    _rings(canvas, g);
    _ap(canvas, g.center);
    _arrowsAndClient(canvas, g);
    _ringLabels(canvas, g);
    canvas.restore();
  }

  /// Label boxes already on the canvas this frame. Arrow labels go first
  /// (they carry the numbers); ring and zone labels try their spots in turn
  /// and are skipped rather than drawn over one of these. The legend under
  /// the view names every ring regardless.
  final List<Rect> _placed = <Rect>[];

  bool _free(Rect r, Size size) =>
      r.left >= 0 &&
      r.top >= 0 &&
      r.right <= size.width &&
      r.bottom <= size.height &&
      !_placed.any((Rect p) => p.overlaps(r));

  /// Draws [tp] at the first spot in [tries] that is free, if any.
  void _placeFirstFree(
    Canvas canvas,
    Size size,
    TextPainter tp,
    List<Offset> tries,
  ) {
    for (final Offset at in tries) {
      final Rect r = (at & tp.size).inflate(3);
      if (_free(r, size)) {
        _placed.add(r);
        _knockout(canvas, at, tp);
        return;
      }
    }
  }

  double _px(RvrStageGeometry g, double m) =>
      math.min(m * g.pxPerM, g.size.longestSide * 2);

  void _zone(Canvas canvas, RvrStageGeometry g) {
    final double a = _px(g, downRingM);
    final double b = _px(g, upRingM);
    if ((a - b).abs() < 0.5) return;
    final ui.Path annulus = ui.Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: g.center, radius: math.max(a, b)))
      ..addOval(Rect.fromCircle(center: g.center, radius: math.min(a, b)));
    canvas.drawPath(
      annulus,
      Paint()
        ..color = Color.alphaBlend(
          style.zone.withValues(alpha: zoneAlpha),
          style.surface,
        ),
    );
  }

  void _grid(Canvas canvas, RvrStageGeometry g) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.scale.strokeWidth(1)
      ..color = style.grid;
    for (final double f in <double>[0.5, 1]) {
      final double r = g.radiusPx * f;
      _dashedCircle(canvas, g.center, r, p, dash: 2, gap: 4);
      final TextPainter tp = _text(_meters(rangeM * f), style.gridLabel);
      final Offset at = g.center + Offset(-r + 2, 2);
      _knockout(canvas, at, tp);
      _placed.add((at & tp.size).inflate(2));
    }
  }

  void _rings(Canvas canvas, RvrStageGeometry g) {
    final double w = style.scale.strokeWidth(2.5);
    final double k = style.scale.stroke;
    final double down = _px(g, downRingM);
    final double up = _px(g, upRingM);
    if (down >= 0.5) {
      canvas.drawCircle(
        g.center,
        down,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = style.down,
      );
    }
    if (up >= 0.5) {
      _dashedCircle(
        canvas,
        g.center,
        up,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = style.up,
        dash: 9 * k,
        gap: 6 * k,
      );
    }
  }

  /// Ring labels sit on their ring: the downlink's at the top or bottom,
  /// the uplink's at the bottom or top, each just outside or just inside,
  /// whichever is free first. The zone label sits half way across the zone,
  /// left or right of the AP.
  void _ringLabels(Canvas canvas, RvrStageGeometry g) {
    final Offset c = g.center;
    const double gap = 4;
    void ring(double r, String label, {required bool topFirst}) {
      if (r < 0.5) return;
      final TextPainter tp = _text(label, style.label);
      final double x = c.dx - tp.width / 2;
      final List<Offset> top = <Offset>[
        Offset(x, c.dy - r - tp.height - gap),
        Offset(x, c.dy - r + gap),
      ];
      final List<Offset> bottom = <Offset>[
        Offset(x, c.dy + r + gap),
        Offset(x, c.dy + r - tp.height - gap),
      ];
      _placeFirstFree(
        canvas,
        g.size,
        tp,
        topFirst ? <Offset>[...top, ...bottom] : <Offset>[...bottom, ...top],
      );
    }

    final double down = _px(g, downRingM);
    final double up = _px(g, upRingM);
    ring(down, downRingLabel, topFirst: true);
    ring(up, upRingLabel, topFirst: false);
    final String? zl = zoneLabel;
    if (zl != null && (down - up).abs() > 2) {
      final TextPainter tp = _text(zl, style.label);
      final double mid = (down + up) / 2;
      final double h = tp.height;
      _placeFirstFree(canvas, g.size, tp, <Offset>[
        for (final double dy in <double>[-h - 6, -h / 2, 6])
          for (final double side in <double>[-1, 1])
            c + Offset(side * mid - tp.width / 2, dy),
      ]);
    }
  }

  void _ap(Canvas canvas, Offset c) {
    final double m = style.scale.marker;
    final Rect r = Rect.fromCenter(center: c, width: 12 * m, height: 12 * m);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(2)),
      Paint()..color = style.ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * m
        ..color = style.surface,
    );
    final TextPainter tp = _text('AP', style.label);
    final Offset at = c + Offset(-tp.width / 2, 9 * m);
    _knockout(canvas, at, tp);
    _placed
      ..add(r.inflate(4))
      ..add((at & tp.size).inflate(3));
  }

  void _arrowsAndClient(Canvas canvas, RvrStageGeometry g) {
    final Offset ap = g.center;
    final Offset cl = g.pointAt(clientDistanceM, clientAngle);
    final Offset v = cl - ap;
    final double len = v.distance;
    final Offset u = len < 1e-6 ? const Offset(1, 0) : v / len;
    final Offset p = Offset(-u.dy, u.dx); // perpendicular
    final double off = style.scale.markerSize(6);
    final double apR = style.scale.markerSize(10);
    final double clR = style.scale.markerSize(11);
    final double w = style.scale.strokeWidth(2);

    if (len > apR + clR + 8) {
      // Downlink: AP to client, solid, head at the client.
      _arrow(
        canvas,
        ap + p * off + u * apR,
        cl + p * off - u * clR,
        Paint()
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = style.down,
        dashed: false,
      );
      // Uplink: client to AP, dashed, head at the AP.
      _arrow(
        canvas,
        cl - p * off - u * clR,
        ap - p * off + u * apR,
        Paint()
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = style.up,
        dashed: true,
      );
    }

    // Client dot.
    canvas.drawCircle(
      cl,
      style.scale.markerSize(9),
      Paint()..color = style.surface,
    );
    canvas.drawCircle(cl, style.scale.markerSize(7), Paint()..color = style.ink);

    // Arrow labels, one on each side of the pair, kept on the canvas. When
    // the client is close to the AP they stack beside the client instead.
    final TextPainter dt = _text(downLabel, style.label);
    final TextPainter ut = _text(upLabel, style.label);
    final Offset mid = (ap + cl) / 2;
    Offset centerFor(TextPainter tp, double side) {
      final double e = p.dx.abs() * tp.width / 2 + p.dy.abs() * tp.height / 2;
      return mid + p * side * (off + 6 + e);
    }

    Offset dc = centerFor(dt, 1);
    Offset uc = centerFor(ut, -1);
    if (len < 60) {
      // Close in: stack both labels on the far side of the client, away
      // from the AP, so neither sits on the AP.
      final double w = math.max(dt.width, ut.width);
      final double h = dt.height;
      final Offset base =
          cl + u * (clR + 8 + u.dx.abs() * w / 2 + u.dy.abs() * h);
      dc = base - Offset(0, h * 0.6);
      uc = base + Offset(0, h * 0.6);
    }
    // Step each label outward along the perpendicular until it clears the
    // AP marker and its label.
    Offset clearOfAp(Offset center, Size box, double side) {
      Offset at = _clampTo(g.size, center, box);
      for (int i = 0; i < 12; i++) {
        final Rect r = (at & box).inflate(3);
        if (!_placed.any((Rect p) => p.overlaps(r))) break;
        center += len < 60 ? u * 8 : p * side * 8;
        at = _clampTo(g.size, center, box);
      }
      return at;
    }

    final Offset da = clearOfAp(dc, dt.size, 1);
    Offset ua = clearOfAp(uc, ut.size, -1);
    // Never let the two labels overlap after clamping.
    final Rect dr = (da & dt.size).inflate(2);
    if (dr.overlaps((ua & ut.size).inflate(2))) {
      final double below = dr.bottom + 2;
      final double above = dr.top - ut.height - 2;
      ua = Offset(
        ua.dx,
        below + ut.height <= g.size.height - 2 ? below : math.max(2, above),
      );
    }
    _knockout(canvas, da, dt);
    _knockout(canvas, ua, ut);
    _placed
      ..add((da & dt.size).inflate(3))
      ..add((ua & ut.size).inflate(3))
      ..add(Rect.fromCircle(center: cl, radius: style.scale.markerSize(10)));
  }

  static Offset _clampTo(Size canvas, Offset center, Size box) {
    final double x = (center.dx - box.width / 2).clamp(
      2.0,
      math.max(2.0, canvas.width - box.width - 2),
    );
    final double y = (center.dy - box.height / 2).clamp(
      2.0,
      math.max(2.0, canvas.height - box.height - 2),
    );
    return Offset(x, y);
  }

  void _arrow(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required bool dashed,
  }) {
    final Offset d = to - from;
    final double len = d.distance;
    if (len < 1) return;
    final Offset u = d / len;
    final double head = style.scale.markerSize(9);
    final Offset shaftEnd = to - u * head * 0.8;
    if (dashed) {
      final double dash = 7 * style.scale.stroke;
      final double gap = 5 * style.scale.stroke;
      final double shaft = (shaftEnd - from).distance;
      for (double s = 0; s < shaft; s += dash + gap) {
        canvas.drawLine(
          from + u * s,
          from + u * math.min(s + dash, shaft),
          paint,
        );
      }
    } else {
      canvas.drawLine(from, shaftEnd, paint);
    }
    final Offset n = Offset(-u.dy, u.dx);
    final ui.Path tip = ui.Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        (to - u * head + n * head * 0.5).dx,
        (to - u * head + n * head * 0.5).dy,
      )
      ..lineTo(
        (to - u * head - n * head * 0.5).dx,
        (to - u * head - n * head * 0.5).dy,
      )
      ..close();
    canvas.drawPath(
      tip,
      Paint()
        ..style = PaintingStyle.fill
        ..color = paint.color,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _meters(double m) => m >= 1000
      ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km'
      : '${m.round()} m';

  TextPainter _text(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
  )..layout();

  void _knockout(Canvas canvas, Offset at, TextPainter tp) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at & tp.size).inflate(2),
        const Radius.circular(3),
      ),
      Paint()..color = style.surface.withValues(alpha: 0.88),
    );
    tp.paint(canvas, at);
  }

  void _dashedCircle(
    Canvas canvas,
    Offset c,
    double r,
    Paint p, {
    required double dash,
    required double gap,
  }) {
    final ui.Path path = ui.Path()
      ..addOval(Rect.fromCircle(center: c, radius: r));
    for (final ui.PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(UdStagePainter old) =>
      old.revision != revision || old.style != style;
}
