// Painters for the Wi-Fi Classroom Multipath Simulator (multipath-simulator).
//
// Token-only CustomPainters in the modulation_simulator_painters.dart idiom:
// every color and text style arrives resolved from context.colors by the
// screen, so each painter is correct in dark (§8) and light (§8.20) without
// knowing which theme it is in. The screen wraps each one in
// `Semantics(excludeSemantics: true)` with a worded label, and every number a
// painter shows is also in a text readout.
//
// Color roles (GL-003 §8.15 case 3, §8.13 rule 6):
//   * the received result is the measured quantity, so it takes lime
//     (`textAccent`): antenna A's trace, the resultant phasor, the histogram;
//   * everything else is neutral and told apart by weight and dash, never
//     hue: the direct and reflected rays and phasors, antenna B's dashed
//     trace, axes, the -10 dB fade line, the Rayleigh curve;
//   * no status hue appears in a painter. The one verdict on this screen
//     (a copy past the guard interval) is a worded text readout.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/multipath_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Resolved colors and text styles shared by every multipath painter.
@immutable
class MultipathPaintStyle {
  const MultipathPaintStyle({
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.grid,
    required this.axis,
    required this.wall,
    required this.labelStyle,
    this.scale = PresenterScale.normal,
  });

  /// Lime: the measured quantity.
  final Color accent;

  /// Strongest neutral: markers and the receiver.
  final Color primary;

  /// Neutral paths, phasors and the second trace.
  final Color secondary;

  /// Quiet neutral: minor labels.
  final Color tertiary;

  /// Decorative grid.
  final Color grid;

  /// Axes and reference lines (3:1 or better on the plot surface).
  final Color axis;

  /// The wall hatch.
  final Color wall;

  /// Axis and scene labels.
  final TextStyle labelStyle;

  /// Presenter scale. The label style arrives already scaled (the stage
  /// applies paintFont); strokes multiply by [k] and markers by [m].
  final PresenterScale scale;

  /// Stroke factor (1 outside presenter mode).
  double get k => scale.stroke;

  /// Marker factor (1 outside presenter mode).
  double get m => scale.marker;

  @override
  bool operator ==(Object other) =>
      other is MultipathPaintStyle &&
      other.accent == accent &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.grid == grid &&
      other.axis == axis &&
      other.wall == wall &&
      other.labelStyle == labelStyle &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(
    accent,
    primary,
    secondary,
    tertiary,
    grid,
    axis,
    wall,
    labelStyle,
    scale,
  );
}

// ── Shared drawing helpers ──────────────────────────────────────────────────

void _label(
  Canvas canvas,
  String text,
  Offset at,
  TextStyle style, {
  Alignment align = Alignment.topLeft,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final double dx = at.dx - tp.width * (align.x + 1) / 2;
  final double dy = at.dy - tp.height * (align.y + 1) / 2;
  tp.paint(canvas, Offset(dx, dy));
}

void _dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 5,
  double gap = 4,
}) {
  final double len = (b - a).distance;
  if (len == 0) return;
  final Offset dir = (b - a) / len;
  double d = 0;
  while (d < len) {
    final double e = math.min(d + dash, len);
    canvas.drawLine(a + dir * d, a + dir * e, paint);
    d = e + gap;
  }
}

void _arrow(
  Canvas canvas,
  Offset from,
  Offset to,
  Paint paint, {
  double head = 7,
}) {
  canvas.drawLine(from, to, paint);
  final Offset v = to - from;
  final double len = v.distance;
  if (len < 2) return;
  final double h = math.min(head, len * 0.5);
  final double ang = math.atan2(v.dy, v.dx);
  const double spread = 0.45;
  final Path p = Path()
    ..moveTo(to.dx, to.dy)
    ..lineTo(
      to.dx - h * math.cos(ang - spread),
      to.dy - h * math.sin(ang - spread),
    )
    ..lineTo(
      to.dx - h * math.cos(ang + spread),
      to.dy - h * math.sin(ang + spread),
    )
    ..close();
  canvas.drawPath(
    p,
    Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill,
  );
}

void _hatchedWall(Canvas canvas, Rect r, Color color) {
  final Paint line = Paint()
    ..color = color
    ..strokeWidth = 1;
  canvas.save();
  canvas.clipRect(r);
  final double span = r.width + r.height;
  for (double s = -span; s < span; s += 6) {
    canvas.drawLine(
      Offset(r.left + s, r.bottom),
      Offset(r.left + s + r.height, r.top),
      line,
    );
  }
  canvas.restore();
}

void _transmitter(Canvas canvas, Offset c, MultipathPaintStyle s) {
  final Paint p = Paint()
    ..color = s.primary
    ..strokeWidth = 2 * s.k
    ..style = PaintingStyle.stroke;
  canvas.drawLine(c, c.translate(0, 12 * s.m), p);
  for (final double r in <double>[5, 9]) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * s.m),
      -math.pi * 0.85,
      math.pi * 0.7,
      false,
      p,
    );
  }
  canvas.drawCircle(c, 2.5 * s.m, Paint()..color = s.primary);
}

void _receiver(Canvas canvas, Offset c, MultipathPaintStyle s) {
  final RRect body = RRect.fromRectAndRadius(
    Rect.fromCenter(center: c, width: 10 * s.m, height: 16 * s.m),
    const Radius.circular(2),
  );
  canvas.drawRRect(body, Paint()..color = s.primary);
  canvas.drawRRect(body.deflate(2), Paint()..color = s.accent);
}

// ── Mode 1: one wall, seen from above ───────────────────────────────────────

/// Draws the wall (top), transmitter, receiver track, and the direct and
/// reflected rays for the current receiver position.
class TwoRayScenePainter extends CustomPainter {
  TwoRayScenePainter({
    required this.scene,
    required this.t,
    required this.style,
  });

  final TwoRayScene scene;

  /// Receiver offset along the track, meters.
  final double t;
  final MultipathPaintStyle style;

  static const double wallBand = 14;
  static const double pad = 16;

  /// World-to-canvas transform: uniform scale, wall at the top.
  static ({double scale, Offset origin}) transform(
    TwoRayScene scene,
    Size size,
  ) {
    final double minX = math.min(scene.txX, scene.trackStart) - 0.25;
    final double maxX = scene.trackStart + scene.trackLength + 0.25;
    final double worldW = maxX - minX;
    final double worldH = math.max(scene.txY, scene.rxY) + 0.25;
    final double availW = size.width - 2 * pad;
    final double availH = size.height - wallBand - pad - 18;
    final double scale = math.min(availW / worldW, availH / worldH);
    final double usedW = worldW * scale;
    final Offset origin = Offset(
      (size.width - usedW) / 2 - minX * scale,
      wallBand,
    );
    return (scale: scale, origin: origin);
  }

  /// Converts a canvas x to a track offset in meters (for dragging).
  static double trackOffsetAt(double canvasX, TwoRayScene scene, Size size) {
    final ({double scale, Offset origin}) tf = transform(scene, size);
    final double x = (canvasX - tf.origin.dx) / tf.scale;
    return (x - scene.trackStart).clamp(0.0, scene.trackLength);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ({double scale, Offset origin}) tf = transform(scene, size);
    Offset w(double x, double y) =>
        tf.origin + Offset(x * tf.scale, y * tf.scale);

    // Wall along the top.
    final Rect wallRect = Rect.fromLTWH(0, 0, size.width, wallBand);
    _hatchedWall(canvas, wallRect, style.wall);
    canvas.drawLine(
      Offset(0, wallBand),
      Offset(size.width, wallBand),
      Paint()
        ..color = style.axis
        ..strokeWidth = 1.5 * style.k,
    );

    final Offset tx = w(scene.txX, scene.txY);
    final Offset rx = w(scene.rxX(t), scene.rxY);
    final Offset hit = w(scene.reflectionPointX(t), 0);

    // Receiver track.
    final Paint track = Paint()
      ..color = style.grid
      ..strokeWidth = 2 * style.k
      ..strokeCap = StrokeCap.round;
    final Offset a = w(scene.trackStart, scene.rxY);
    final Offset b = w(scene.trackStart + scene.trackLength, scene.rxY);
    canvas.drawLine(a, b, track);
    for (final Offset e in <Offset>[a, b]) {
      canvas.drawLine(e.translate(0, -5), e.translate(0, 5), track);
    }
    _label(
      canvas,
      '1 m track',
      Offset((a.dx + b.dx) / 2, a.dy + 12),
      style.labelStyle,
      align: Alignment.topCenter,
    );

    // Rays: direct solid, reflected dashed; both neutral.
    final Paint direct = Paint()
      ..color = style.secondary
      ..strokeWidth = 1.5 * style.k;
    _arrow(canvas, tx, rx, direct, head: 7 * style.k);
    final Paint refl = Paint()
      ..color = style.secondary
      ..strokeWidth = 1.5 * style.k;
    _dashedLine(canvas, tx, hit, refl);
    _dashedLine(canvas, hit, rx, refl);
    _arrow(canvas, hit + (rx - hit) * 0.9, rx, refl, head: 7 * style.k);

    _transmitter(canvas, tx.translate(0, -6), style);
    _label(
      canvas,
      'AP',
      tx.translate(0, 10),
      style.labelStyle,
      align: Alignment.topCenter,
    );
    _receiver(canvas, rx, style);
    _label(
      canvas,
      'Wall',
      Offset(size.width - 6, wallBand + 4),
      style.labelStyle,
      align: Alignment.topRight,
    );
  }

  @override
  bool shouldRepaint(TwoRayScenePainter old) =>
      old.t != t || old.style != style || old.scene != scene;
}

// ── Mode 2: standing wave in front of a wall ────────────────────────────────

/// Draws the wall on the left, the receiver at distance d, the incoming and
/// reflected waves, and a tick at every null.
class StandingWaveScenePainter extends CustomPainter {
  StandingWaveScenePainter({
    required this.range,
    required this.distance,
    required this.nulls,
    required this.style,
  });

  /// Meters of floor shown in front of the wall.
  final double range;

  /// Receiver distance from the wall, meters.
  final double distance;

  /// Null positions, meters from the wall.
  final List<double> nulls;
  final MultipathPaintStyle style;

  static const double wallBand = 14;
  static const double rightPad = 16;

  static double _x(double d, double range, Size size) =>
      wallBand + d / range * (size.width - wallBand - rightPad);

  /// Converts a canvas x to a distance from the wall (for dragging).
  static double distanceAt(double canvasX, double range, Size size) {
    final double w = size.width - wallBand - rightPad;
    return ((canvasX - wallBand) / w * range).clamp(0.0, range);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect wallRect = Rect.fromLTWH(0, 0, wallBand, size.height);
    _hatchedWall(canvas, wallRect, style.wall);
    canvas.drawLine(
      const Offset(wallBand, 0),
      Offset(wallBand, size.height),
      Paint()
        ..color = style.axis
        ..strokeWidth = 1.5 * style.k,
    );

    final double floorY = size.height - 22;
    final Paint floor = Paint()
      ..color = style.grid
      ..strokeWidth = 1 * style.k;
    canvas.drawLine(
      Offset(wallBand, floorY),
      Offset(size.width - rightPad, floorY),
      floor,
    );

    // Null ticks along the floor.
    final Paint tick = Paint()
      ..color = style.axis
      ..strokeWidth = 1.5 * style.k;
    for (final double n in nulls) {
      final double x = _x(n, range, size);
      canvas.drawLine(Offset(x, floorY - 5), Offset(x, floorY + 5), tick);
    }
    _label(
      canvas,
      'Nulls',
      Offset(size.width - rightPad, floorY + 6),
      style.labelStyle,
      align: Alignment.topRight,
    );

    final double rx = _x(distance, range, size);
    final double y1 = size.height * 0.28;
    final double y2 = size.height * 0.48;
    final double right = size.width - rightPad;

    // Incoming (direct) wave from the AP off to the right, reaching the
    // receiver; it continues to the wall and comes back (dashed).
    final Paint direct = Paint()
      ..color = style.secondary
      ..strokeWidth = 1.5 * style.k;
    _arrow(
      canvas,
      Offset(right, y1),
      Offset(rx + 8, y1),
      direct,
      head: 7 * style.k,
    );
    _dashedLine(canvas, Offset(rx, y1), Offset(wallBand, y1), direct);
    _dashedLine(canvas, Offset(wallBand, y1), Offset(wallBand, y2), direct);
    _dashedLine(canvas, Offset(wallBand, y2), Offset(rx - 8, y2), direct);
    _arrow(
      canvas,
      Offset(rx - 16, y2),
      Offset(rx - 7, y2),
      direct,
      head: 7 * style.k,
    );
    _label(
      canvas,
      'from AP, 10 m',
      Offset(right, y1 - 4),
      style.labelStyle,
      align: Alignment.bottomRight,
    );

    // Receiver and its guide down to the floor.
    _dashedLine(
      canvas,
      Offset(rx, (y1 + y2) / 2 + 10),
      Offset(rx, floorY),
      Paint()
        ..color = style.grid
        ..strokeWidth = 1 * style.k,
      dash: 3,
      gap: 3,
    );
    _receiver(canvas, Offset(rx, (y1 + y2) / 2), style);
  }

  @override
  bool shouldRepaint(StandingWaveScenePainter old) =>
      old.distance != distance ||
      old.range != range ||
      old.style != style ||
      !identical(old.nulls, nulls);
}

// ── Phasors ─────────────────────────────────────────────────────────────────

/// Draws path phasors head to tail from the origin and the resultant from
/// the origin to the last head. Scaled so the longest of (resultant, chain
/// extent, unit circle) fits.
class PhasorPainter extends CustomPainter {
  PhasorPainter({
    required this.phasors,
    required this.style,
    required this.showUnitCircle,
    this.dashedAfterFirst = true,
  });

  /// Contributions already normalized (direct path = 1 + 0j in two-path
  /// modes; unit mean power in many-path mode).
  final List<Complex> phasors;
  final MultipathPaintStyle style;

  /// Draws the unit circle (the direct path alone, or the mean amplitude).
  final bool showUnitCircle;

  /// Two-path modes dash the reflected phasor to match its ray.
  final bool dashedAfterFirst;

  @override
  void paint(Canvas canvas, Size size) {
    // Bounds of the chain and the resultant.
    double minX = -1, maxX = 1, minY = -1, maxY = 1;
    double cx = 0, cy = 0;
    for (final Complex p in phasors) {
      cx += p.re;
      cy += p.im;
      minX = math.min(minX, cx);
      maxX = math.max(maxX, cx);
      minY = math.min(minY, cy);
      maxY = math.max(maxY, cy);
    }
    const double pad = 14;
    final double scale = math.min(
      (size.width - 2 * pad) / (maxX - minX),
      (size.height - 2 * pad) / (maxY - minY),
    );
    final Offset origin = Offset(
      pad +
          (-minX) * scale +
          ((size.width - 2 * pad) - (maxX - minX) * scale) / 2,
      // Imaginary axis up.
      pad +
          maxY * scale +
          ((size.height - 2 * pad) - (maxY - minY) * scale) / 2,
    );
    Offset at(double re, double im) => origin + Offset(re * scale, -im * scale);

    final Paint axis = Paint()
      ..color = style.grid
      ..strokeWidth = 1 * style.k;
    canvas.drawLine(Offset(0, origin.dy), Offset(size.width, origin.dy), axis);
    canvas.drawLine(Offset(origin.dx, 0), Offset(origin.dx, size.height), axis);
    if (showUnitCircle) {
      _dashedCircle(canvas, origin, scale, style.axis);
    }

    // Resultant first, lime and heavier, so the thinner path arrows stay
    // visible on top of it when they line up.
    final Paint res = Paint()
      ..color = style.accent
      ..strokeWidth = 3.5 * style.k
      ..strokeCap = StrokeCap.round;
    _arrow(canvas, origin, at(cx, cy), res, head: 11 * style.k);

    final bool many = phasors.length > 2;
    double hx = 0, hy = 0;
    for (int i = 0; i < phasors.length; i++) {
      final Complex p = phasors[i];
      final Offset from = at(hx, hy);
      hx += p.re;
      hy += p.im;
      final Offset to = at(hx, hy);
      final Paint paint = Paint()
        ..color = style.secondary
        ..strokeWidth = (many ? 1.25 : 2) * style.k;
      if (!many && dashedAfterFirst && i > 0) {
        _dashedLine(canvas, from, to, paint);
        _arrow(canvas, from + (to - from) * 0.85, to, paint, head: 7 * style.k);
      } else {
        _arrow(canvas, from, to, paint, head: (many ? 5 : 7) * style.k);
      }
    }

    canvas.drawCircle(origin, 3 * style.m, Paint()..color = style.primary);
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1 * style.k
      ..style = PaintingStyle.stroke;
    const int segs = 48;
    for (int i = 0; i < segs; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        2 * math.pi * i / segs,
        2 * math.pi / segs,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(PhasorPainter old) =>
      old.style != style ||
      old.showUnitCircle != showUnitCircle ||
      old.phasors.length != phasors.length ||
      !_same(old.phasors, phasors);

  static bool _same(List<Complex> a, List<Complex> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i].re != b[i].re || a[i].im != b[i].im) return false;
    }
    return true;
  }
}

// ── Power vs position ───────────────────────────────────────────────────────

/// Power (dB) against position, with a -10 dB fade line, a receiver marker,
/// and an optional dashed second trace.
class PowerPlotPainter extends CustomPainter {
  PowerPlotPainter({
    required this.traceA,
    required this.traceB,
    required this.xMax,
    required this.xUnitLabel,
    required this.marker,
    required this.style,
    required this.revision,
    this.yMin = -30,
    this.yMax = 10,
    this.fadeLine = true,
  });

  /// Evenly spaced samples from x = 0 to [xMax].
  final List<double> traceA;
  final List<double>? traceB;

  /// Axis end in display units (cm).
  final double xMax;
  final String xUnitLabel;

  /// Receiver position in display units.
  final double marker;
  final MultipathPaintStyle style;

  /// Bumped whenever a trace is recomputed.
  final int revision;
  final double yMin;
  final double yMax;
  final bool fadeLine;

  static const double leftGutter = 34;
  static const double bottomGutter = 20;
  static const double topPad = 6;
  static const double rightPad = 8;

  static Rect plotRect(Size size) => Rect.fromLTRB(
    leftGutter,
    topPad,
    size.width - rightPad,
    size.height - bottomGutter,
  );

  /// Converts a canvas x to a display-unit position (for dragging).
  static double positionAt(double canvasX, double xMax, Size size) {
    final Rect r = plotRect(size);
    return ((canvasX - r.left) / r.width * xMax).clamp(0.0, xMax);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = plotRect(size);
    double yOf(double db) =>
        r.bottom - (db.clamp(yMin, yMax) - yMin) / (yMax - yMin) * r.height;
    double xOf(double x) => r.left + x / xMax * r.width;

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1 * style.k;
    for (double db = yMin; db <= yMax + 1e-9; db += 10) {
      final double y = yOf(db);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      _label(
        canvas,
        db == 0
            ? '0'
            : db > 0
            ? '+${db.round()}'
            : '${db.round()}',
        Offset(r.left - 4, y),
        style.labelStyle,
        align: Alignment.centerRight,
      );
    }
    // x ticks: 0, half, end.
    for (final double f in <double>[0, 0.5, 1]) {
      final double x = xMax * f;
      final double cx = xOf(x);
      canvas.drawLine(Offset(cx, r.bottom), Offset(cx, r.bottom + 4), grid);
      _label(
        canvas,
        '${_trim(x)}${f == 1 ? ' $xUnitLabel' : ''}',
        Offset(cx, r.bottom + 5),
        style.labelStyle,
        align: f == 0
            ? Alignment.topLeft
            : f == 1
            ? Alignment.topRight
            : Alignment.topCenter,
      );
    }

    // 0 dB (direct / mean) line and the -10 dB fade line.
    canvas.drawLine(
      Offset(r.left, yOf(0)),
      Offset(r.right, yOf(0)),
      Paint()
        ..color = style.axis
        ..strokeWidth = 1 * style.k,
    );
    if (fadeLine) {
      _dashedLine(
        canvas,
        Offset(r.left, yOf(kFadeThresholdDb)),
        Offset(r.right, yOf(kFadeThresholdDb)),
        Paint()
          ..color = style.axis
          ..strokeWidth = 1 * style.k,
      );
    }

    canvas.save();
    canvas.clipRect(r.inflate(1));
    final List<double>? b = traceB;
    if (b != null && b.length > 1) {
      _trace(canvas, b, xOf, yOf, style.secondary, 1.5, dashed: true);
    }
    _trace(canvas, traceA, xOf, yOf, style.accent, 2);
    canvas.restore();

    // Receiver marker.
    final double mx = xOf(marker.clamp(0, xMax));
    canvas.drawLine(
      Offset(mx, r.top),
      Offset(mx, r.bottom),
      Paint()
        ..color = style.primary
        ..strokeWidth = 1.5 * style.k,
    );
    canvas.drawCircle(
      Offset(mx, r.top + 1),
      3.5 * style.m,
      Paint()..color = style.primary,
    );
  }

  void _trace(
    Canvas canvas,
    List<double> ys,
    double Function(double) xOf,
    double Function(double) yOf,
    Color color,
    double width, {
    bool dashed = false,
  }) {
    final int n = ys.length;
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = width * style.k
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (!dashed) {
      final Path path = Path();
      for (int i = 0; i < n; i++) {
        final Offset o = Offset(xOf(xMax * i / (n - 1)), yOf(ys[i]));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, p);
      return;
    }
    // Dashed polyline: walk the samples, toggling every ~6 px of x.
    Offset? prev;
    double run = 0;
    bool on = true;
    for (int i = 0; i < n; i++) {
      final Offset o = Offset(xOf(xMax * i / (n - 1)), yOf(ys[i]));
      if (prev != null) {
        if (on) canvas.drawLine(prev, o, p);
        run += (o.dx - prev.dx).abs();
        if (run >= (on ? 6 : 4)) {
          on = !on;
          run = 0;
        }
      }
      prev = o;
    }
  }

  static String _trim(double v) {
    final String s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
    return s;
  }

  @override
  bool shouldRepaint(PowerPlotPainter old) =>
      old.revision != revision ||
      old.marker != marker ||
      old.style != style ||
      old.xMax != xMax;
}

// ── Histogram ───────────────────────────────────────────────────────────────

/// Bars: share of samples per dB bin. Line: the Rayleigh prediction.
class HistogramPainter extends CustomPainter {
  HistogramPainter({
    required this.histogram,
    required this.style,
    required this.revision,
  });

  final PowerHistogram histogram;
  final MultipathPaintStyle style;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    const double left = 34, bottom = 20, top = 6, right = 8;
    final Rect r = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final PowerHistogram h = histogram;
    double peak = 0.05;
    for (int i = 0; i < h.bins; i++) {
      peak = math.max(peak, math.max(h.fraction(i), h.rayleighFraction(i)));
    }
    // Ticks every 10% (5% for a flat histogram); the top is the next tick.
    final double tickStep = peak > 0.2 ? 0.1 : 0.05;
    final double yTop = (peak / tickStep).ceil() * tickStep;
    double yOf(double f) => r.bottom - f / yTop * r.height;
    final double bw = r.width / h.bins;

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1 * style.k;
    for (double f = 0; f <= yTop + 1e-9; f += tickStep) {
      final double y = yOf(f);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      _label(
        canvas,
        '${(f * 100).round()}%',
        Offset(r.left - 4, y),
        style.labelStyle,
        align: Alignment.centerRight,
      );
    }
    for (final double db in <double>[-30, -20, -10, 0, 10]) {
      if (db < h.lo || db > h.hi) continue;
      final double x = r.left + (db - h.lo) / (h.hi - h.lo) * r.width;
      canvas.drawLine(Offset(x, r.bottom), Offset(x, r.bottom + 4), grid);
      _label(
        canvas,
        db == h.hi ? '${db.round()} dB' : '${db.round()}',
        Offset(x, r.bottom + 5),
        style.labelStyle,
        align: db == h.lo
            ? Alignment.topLeft
            : db == h.hi
            ? Alignment.topRight
            : Alignment.topCenter,
      );
    }

    final Paint bar = Paint()..color = style.accent;
    for (int i = 0; i < h.bins; i++) {
      final double f = h.fraction(i);
      if (f <= 0) continue;
      canvas.drawRect(
        Rect.fromLTRB(
          r.left + i * bw + 1,
          yOf(f),
          r.left + (i + 1) * bw - 1,
          r.bottom,
        ),
        bar,
      );
    }

    // Rayleigh prediction through the bin centers, with a dot per bin.
    final Paint curve = Paint()
      ..color = style.primary
      ..strokeWidth = 2 * style.k
      ..style = PaintingStyle.stroke;
    final Path path = Path();
    for (int i = 0; i < h.bins; i++) {
      final Offset o = Offset(
        r.left + (i + 0.5) * bw,
        yOf(h.rayleighFraction(i)),
      );
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, curve);
    for (int i = 0; i < h.bins; i++) {
      canvas.drawCircle(
        Offset(r.left + (i + 0.5) * bw, yOf(h.rayleighFraction(i))),
        2.5 * style.m,
        Paint()..color = style.primary,
      );
    }
  }

  @override
  bool shouldRepaint(HistogramPainter old) =>
      old.revision != revision || old.style != style;
}
