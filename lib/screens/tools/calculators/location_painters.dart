// Painters for the Wi-Fi Classroom "Where Am I?" tool (location-rssi-ftm).
//
// THE FLOOR is drawn on theme surfaces (surface 2 with a 5 m grid in the
// border color), with a margin around it so an estimate that lands off the
// floor is still seen. Everything takes theme colors passed in by the stage.
//
// MARKERS. Methods are told apart by label and marker SHAPE, never by color
// alone (spec 33; SC 1.4.1):
//   - AP:                       filled square, "AP n"
//   - true device position:     ring with a crosshair (the thing you drag)
//   - signal-strength estimate: diamond
//   - FTM (timing) estimate:    triangle
// The estimate and its 50 repeats are lime (textAccent): lime marks the
// computed quantity the lesson is about. Circles at each AP's estimated
// distance are neutral; a circle for an AP whose direct path is blocked is
// dashed and its AP is labeled "blocked". A dotted line joins the true
// position to the estimate: that length is the position error.
//
// Nothing animates. Painters read the presenter scale passed in.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/location_engine.dart';
import '../../../widgets/presenter/presenter.dart';

/// Meters of margin drawn around the floor.
const double kLocMarginM = 4;

/// Meters to pixels for the floor plus its margin, centered in the box.
class LocFloorMapping {
  LocFloorMapping(this.size)
    : scale = math.min(
        size.width / (kLocFloorWidthM + 2 * kLocMarginM),
        size.height / (kLocFloorDepthM + 2 * kLocMarginM),
      ) {
    final double w = (kLocFloorWidthM + 2 * kLocMarginM) * scale;
    final double h = (kLocFloorDepthM + 2 * kLocMarginM) * scale;
    origin = Offset(
      (size.width - w) / 2 + kLocMarginM * scale,
      (size.height - h) / 2 + kLocMarginM * scale,
    );
  }

  final Size size;

  /// Pixels per meter.
  final double scale;

  /// Screen position of the floor's top-left corner.
  late final Offset origin;

  Offset toPx(LocPoint p) => origin + Offset(p.x * scale, p.y * scale);

  LocPoint toFloor(Offset o) =>
      (x: (o.dx - origin.dx) / scale, y: (o.dy - origin.dy) / scale);

  Rect get floorRect =>
      origin & Size(kLocFloorWidthM * scale, kLocFloorDepthM * scale);

  Rect get viewRect => floorRect.inflate(kLocMarginM * scale);
}

/// Theme colors and scale for the floor painter.
class LocFloorStyle {
  const LocFloorStyle({
    required this.sc,
    required this.floor,
    required this.margin,
    required this.grid,
    required this.outline,
    required this.ap,
    required this.apText,
    required this.circle,
    required this.device,
    required this.estimate,
    required this.casing,
    required this.label,
    required this.font,
  });

  final PresenterScale sc;
  final Color floor;
  final Color margin;
  final Color grid;
  final Color outline;
  final Color ap;
  final Color apText;
  final Color circle;
  final Color device;
  final Color estimate;

  /// Outline under lime marks so they read on the floor in both themes.
  final Color casing;
  final Color label;
  final TextStyle font;
}

/// Draws one method's floor.
class LocFloorPainter extends CustomPainter {
  LocFloorPainter({
    required this.run,
    required this.method,
    required this.style,
  });

  final LocRun run;
  final LocMethod method;
  final LocFloorStyle style;

  PresenterScale get sc => style.sc;

  @override
  void paint(Canvas canvas, Size size) {
    final LocFloorMapping m = LocFloorMapping(size);
    canvas.save();
    canvas.clipRect(m.viewRect);
    canvas.drawRect(m.viewRect, Paint()..color = style.margin);
    canvas.drawRect(m.floorRect, Paint()..color = style.floor);
    _grid(canvas, m);
    canvas.drawRect(
      m.floorRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1.5)
        ..color = style.outline,
    );
    _circles(canvas, m);
    _scatter(canvas, m);
    _errorLine(canvas, m);
    _aps(canvas, m);
    _device(canvas, m);
    _estimate(canvas, m);
    canvas.restore();
    canvas.drawRect(
      m.viewRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1)
        ..color = style.grid,
    );
  }

  void _grid(Canvas canvas, LocFloorMapping m) {
    final Paint p = Paint()
      ..color = style.grid
      ..strokeWidth = sc.strokeWidth(1);
    for (double x = 5; x < kLocFloorWidthM; x += 5) {
      canvas.drawLine(
        m.toPx((x: x, y: 0)),
        m.toPx((x: x, y: kLocFloorDepthM)),
        p,
      );
    }
    for (double y = 5; y < kLocFloorDepthM; y += 5) {
      canvas.drawLine(
        m.toPx((x: 0, y: y)),
        m.toPx((x: kLocFloorWidthM, y: y)),
        p,
      );
    }
    _text(
      canvas,
      '5 m grid',
      m.floorRect.bottomRight + Offset(-sc.markerSize(4), sc.markerSize(4)),
      align: _Align.topRight,
      small: true,
    );
  }

  void _circles(Canvas canvas, LocFloorMapping m) {
    final List<LocApReading> drawn = run.drawn;
    for (int i = 0; i < drawn.length; i++) {
      final double r = drawn[i].distanceFor(method);
      final Offset c = m.toPx(run.settings.aps[i]);
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1.5)
        ..color = style.circle;
      final bool dashed = method == LocMethod.ftm && run.settings.isBlocked(i);
      if (dashed) {
        _dashedCircle(canvas, c, r * m.scale, p);
      } else {
        canvas.drawCircle(c, r * m.scale, p);
      }
    }
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint p) {
    if (r <= 0) return;
    final double dash = sc.markerSize(6);
    final int n = math.max(8, (2 * math.pi * r / (2 * dash)).floor());
    final double step = 2 * math.pi / n;
    for (int k = 0; k < n; k++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        k * step,
        step / 2,
        false,
        p,
      );
    }
  }

  void _scatter(Canvas canvas, LocFloorMapping m) {
    final List<LocPoint> pts = run.result(method).scatter;
    final Paint fill = Paint()..color = style.estimate.withValues(alpha: 0.55);
    final double r = sc.markerSize(3.2);
    for (int k = 1; k < pts.length; k++) {
      canvas.drawPath(_shape(m.toPx(pts[k]), r), fill);
    }
  }

  void _errorLine(Canvas canvas, LocFloorMapping m) {
    final LocFix? fix = run.result(method).fix;
    if (fix == null) return;
    final Offset a = m.toPx(run.settings.device);
    final Offset b = m.toPx(fix.position);
    final double len = (b - a).distance;
    if (len < 1) return;
    final Paint p = Paint()
      ..color = style.device
      ..strokeWidth = sc.strokeWidth(1.5);
    final double dot = sc.markerSize(3);
    for (double t = 0; t < len; t += dot * 2) {
      final Offset s = Offset.lerp(a, b, t / len)!;
      final Offset e = Offset.lerp(a, b, math.min(t + dot, len) / len)!;
      canvas.drawLine(s, e, p);
    }
  }

  void _aps(Canvas canvas, LocFloorMapping m) {
    final double r = sc.markerSize(7);
    for (int i = 0; i < run.settings.aps.length; i++) {
      final Offset p = m.toPx(run.settings.aps[i]);
      final Rect sq = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
      canvas.drawRect(
        sq.inflate(sc.markerSize(1.5)),
        Paint()..color = style.floor,
      );
      canvas.drawRect(sq, Paint()..color = style.ap);
      final bool blocked = method == LocMethod.ftm && run.settings.isBlocked(i);
      _text(
        canvas,
        blocked ? 'AP ${i + 1}, blocked' : 'AP ${i + 1}',
        p + Offset(0, r + sc.markerSize(3)),
        align: _Align.topCenter,
      );
    }
  }

  void _device(Canvas canvas, LocFloorMapping m) {
    final Offset p = m.toPx(run.settings.device);
    final double r = sc.markerSize(8);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(2.5)
      ..color = style.device;
    canvas.drawCircle(p, r, ring);
    canvas.drawLine(p - Offset(r * 1.6, 0), p + Offset(r * 1.6, 0), ring);
    canvas.drawLine(p - Offset(0, r * 1.6), p + Offset(0, r * 1.6), ring);
  }

  void _estimate(Canvas canvas, LocFloorMapping m) {
    final LocFix? fix = run.result(method).fix;
    if (fix == null) return;
    final Offset p = m.toPx(fix.position);
    final double r = sc.markerSize(8);
    canvas.drawPath(
      _shape(p, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(3)
        ..color = style.casing,
    );
    canvas.drawPath(_shape(p, r), Paint()..color = style.estimate);
  }

  /// A diamond for signal strength, a triangle for timing.
  Path _shape(Offset c, double r) => locMarkerPath(method, c, r);

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    _Align align = _Align.topCenter,
    bool small = false,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: style.font.copyWith(
          color: style.apText,
          fontSize: sc.paintFont(small ? 10 : 11),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Offset o = switch (align) {
      _Align.topCenter => at - Offset(tp.width / 2, 0),
      _Align.topRight => at - Offset(tp.width, 0),
    };
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(LocFloorPainter old) =>
      old.run != run ||
      old.method != method ||
      old.style.sc != style.sc ||
      old.style.estimate != style.estimate ||
      old.style.floor != style.floor;
}

enum _Align { topCenter, topRight }

/// The marker shape for a method: diamond (signal strength) or triangle
/// (timing). Shared by the floor and the legend.
Path locMarkerPath(LocMethod method, Offset c, double r) {
  switch (method) {
    case LocMethod.signal:
      return Path()
        ..moveTo(c.dx, c.dy - r * 1.2)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r * 1.2)
        ..lineTo(c.dx - r, c.dy)
        ..close();
    case LocMethod.ftm:
      return Path()
        ..moveTo(c.dx, c.dy - r * 1.2)
        ..lineTo(c.dx + r * 1.1, c.dy + r * 0.8)
        ..lineTo(c.dx - r * 1.1, c.dy + r * 0.8)
        ..close();
  }
}

/// A legend swatch: one marker shape, or the device ring, or an AP square.
enum LocLegendMark { device, ap, signal, ftm }

class LocLegendPainter extends CustomPainter {
  LocLegendPainter({required this.mark, required this.color});

  final LocLegendMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = math.min(size.width, size.height) * 0.38;
    switch (mark) {
      case LocLegendMark.device:
        final Paint p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color;
        canvas.drawCircle(c, r * 0.7, p);
        canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), p);
        canvas.drawLine(c - Offset(0, r), c + Offset(0, r), p);
      case LocLegendMark.ap:
        canvas.drawRect(
          Rect.fromCenter(center: c, width: r * 1.6, height: r * 1.6),
          Paint()..color = color,
        );
      case LocLegendMark.signal:
        canvas.drawPath(
          locMarkerPath(LocMethod.signal, c, r * 0.85),
          Paint()..color = color,
        );
      case LocLegendMark.ftm:
        canvas.drawPath(
          locMarkerPath(LocMethod.ftm, c, r * 0.9),
          Paint()..color = color,
        );
    }
  }

  @override
  bool shouldRepaint(LocLegendPainter old) =>
      old.mark != mark || old.color != color;
}
