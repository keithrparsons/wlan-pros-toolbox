// Chart painter for the Wi-Fi Classroom FSPL Simulator (fspl-simulator).
//
// A CustomPainter rather than fl_chart: the distance axis is logarithmic
// (1 m to 100 m or 1 km, decade grid with 2..9 minor ticks), and the chart
// carries a cursor, per-band markers, reference lines and a measured point
// with a labelled gap. Painting it directly keeps all of that on one
// coordinate mapping, exposed as [FsplChartGeometry] so the screen's drag
// handler and the painter can never disagree about where a distance sits.
//
// COLOR (GL-003 §8.15): there is no categorical palette, so the bands are NOT
// told apart by hue. Every free-space curve is lime (the one quantity the
// chart is about) and the bands differ by stroke (solid / dashed / dotted) and
// by cursor marker shape (circle / square / triangle). The indoor model draws
// the same strokes, thinner, in a neutral grey. Reference lines and the grid
// are neutral. No status hue is used: nothing here is a verdict.
//
// All colors and text styles arrive through [FsplChartStyle], built by the
// screen from context.colors, so dark (§8) and light (§8.20) both work.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// How a series line is stroked. One per band, so bands are distinguishable
/// without color.
enum CurveStroke { solid, dashed, dotted }

/// Marker drawn where a series meets the cursor. One per band.
enum CurveMarker { circle, square, triangle }

/// One plotted line.
@immutable
class FsplSeries {
  const FsplSeries({
    required this.points,
    required this.stroke,
    required this.marker,
    required this.isModel,
    this.cursorValue,
  });

  /// (distance m, y) pairs in ascending distance.
  final List<(double, double)> points;
  final CurveStroke stroke;
  final CurveMarker marker;

  /// True for the indoor log-distance overlay: thinner, neutral, hollow marker.
  final bool isModel;

  /// y at the cursor distance, for the marker. Null draws no marker.
  final double? cursorValue;
}

/// A horizontal reference line (a design target such as -67 dBm).
@immutable
class FsplRefLine {
  const FsplRefLine({
    required this.y,
    required this.label,
    this.labelBelow = false,
  });
  final double y;
  final String label;

  /// Put the label under the line instead of over it, so two close lines do
  /// not print on top of each other.
  final bool labelBelow;
}

/// A user-entered measurement and the free-space value at the same distance.
@immutable
class FsplMeasuredMark {
  const FsplMeasuredMark({
    required this.distanceM,
    required this.y,
    required this.curveY,
    required this.label,
  });
  final double distanceM;
  final double y;
  final double curveY;
  final String label;
}

/// Theme-derived paints and text styles. Built by the screen from tokens.
@immutable
class FsplChartStyle {
  const FsplChartStyle({
    required this.curve,
    required this.model,
    required this.grid,
    required this.axis,
    required this.refLine,
    required this.cursor,
    required this.measured,
    required this.surface,
    required this.axisLabel,
    required this.refLabel,
    required this.cursorLabel,
    required this.emptyLabel,
    this.scale = PresenterScale.normal,
  });

  final Color curve;
  final Color model;
  final Color grid;
  final Color axis;
  final Color refLine;
  final Color cursor;
  final Color measured;

  /// The plot background, used to knock out behind labels and marker rims.
  final Color surface;
  final TextStyle axisLabel;
  final TextStyle refLabel;
  final TextStyle cursorLabel;
  final TextStyle emptyLabel;

  /// Presenter scale for strokes, markers and the axis gutters. The text
  /// styles above arrive already scaled (the stage applies paintFont).
  final PresenterScale scale;
}

/// The single coordinate mapping shared by painter and gesture code.
@immutable
class FsplChartGeometry {
  const FsplChartGeometry({
    required this.size,
    required this.maxDistanceM,
    required this.yMin,
    required this.yMax,
    this.padScale = 1,
    this.logDistance = true,
    this.minDistanceM = defaultMinDistanceM,
  });

  static const double padLeft = 40;
  static const double padRight = 12;
  static const double padTop = 12;
  static const double padBottom = 24;

  /// Metric axis start. Imperial starts at 3 ft (FsplSimModel.minM).
  static const double defaultMinDistanceM = 1;

  /// Where the distance axis starts, metres (the log axis cannot start at 0;
  /// the linear axis starts at 0 and this is only the cursor's floor).
  final double minDistanceM;

  final Size size;
  final double maxDistanceM;
  final double yMin;
  final double yMax;

  /// Grows the gutters with the axis labels (the presenter text scale; 1
  /// elsewhere), so larger tick labels never run off the plot.
  final double padScale;

  /// True: log distance axis (decades). False: linear axis from 0 to
  /// [maxDistanceM]; the same dB values then draw as the familiar curve.
  final bool logDistance;

  Rect get plot => Rect.fromLTRB(
    padLeft * padScale,
    padTop * padScale,
    math.max(padLeft * padScale + 1, size.width - padRight * padScale),
    math.max(padTop * padScale + 1, size.height - padBottom * padScale),
  );

  static double _log10(double v) => math.log(v) / math.ln10;

  double xFor(double distanceM) {
    final Rect p = plot;
    final double t = logDistance
        ? (_log10(distanceM) - _log10(minDistanceM)) /
              (_log10(maxDistanceM) - _log10(minDistanceM))
        : distanceM / maxDistanceM;
    return p.left + t.clamp(0.0, 1.0) * p.width;
  }

  double yFor(double v) {
    final Rect p = plot;
    final double t = (v - yMin) / (yMax - yMin);
    return p.bottom - t * p.height;
  }

  /// Inverse of [xFor], clamped to the axis. Used by drag and tap.
  double distanceAt(double x) {
    final Rect p = plot;
    final double t = ((x - p.left) / p.width).clamp(0.0, 1.0);
    if (!logDistance) {
      return math.max(minDistanceM, t * maxDistanceM);
    }
    final double lg =
        _log10(minDistanceM) +
        t * (_log10(maxDistanceM) - _log10(minDistanceM));
    return math.pow(10, lg).toDouble();
  }
}

class FsplChartPainter extends CustomPainter {
  FsplChartPainter({
    required this.maxDistanceM,
    required this.yMin,
    required this.yMax,
    required this.yStep,
    required this.series,
    required this.refLines,
    required this.cursorDistanceM,
    required this.cursorLabel,
    required this.style,
    required this.revision,
    this.measured,
    this.emptyMessage,
    this.logDistance = true,
    this.minDistanceM = FsplChartGeometry.defaultMinDistanceM,
    this.units = UnitSystem.metric,
  });

  /// See [FsplChartGeometry.logDistance].
  final bool logDistance;

  /// See [FsplChartGeometry.minDistanceM].
  final double minDistanceM;

  /// Units the distance ticks are labelled in; ticks are round in this unit.
  final UnitSystem units;
  final double maxDistanceM;
  final double yMin;
  final double yMax;
  final double yStep;
  final List<FsplSeries> series;
  final List<FsplRefLine> refLines;
  final double cursorDistanceM;
  final String cursorLabel;
  final FsplMeasuredMark? measured;
  final FsplChartStyle style;

  /// Shown centered when there is nothing to draw (no band turned on).
  final String? emptyMessage;

  /// Bumped by the screen on every input change; drives [shouldRepaint].
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final FsplChartGeometry g = FsplChartGeometry(
      size: size,
      maxDistanceM: maxDistanceM,
      yMin: yMin,
      yMax: yMax,
      padScale: style.scale.text,
      logDistance: logDistance,
      minDistanceM: minDistanceM,
    );
    final Rect p = g.plot;
    _grid(canvas, g, p);

    canvas.save();
    canvas.clipRect(p.inflate(2));
    for (final FsplRefLine r in refLines) {
      _refLine(canvas, g, p, r);
    }
    // Models first so the free-space curves sit on top.
    for (final FsplSeries s in series.where((FsplSeries s) => s.isModel)) {
      _series(canvas, g, s);
    }
    for (final FsplSeries s in series.where((FsplSeries s) => !s.isModel)) {
      _series(canvas, g, s);
    }
    canvas.restore();

    if (emptyMessage != null) {
      _text(
        canvas,
        emptyMessage!,
        style.emptyLabel,
        p.center,
        maxWidth: p.width - 16,
        align: TextAlign.center,
        anchor: const Offset(0.5, 0.5),
      );
      return;
    }

    _cursor(canvas, g, p);
    for (final FsplSeries s in series) {
      final double? v = s.cursorValue;
      if (v == null || v < yMin || v > yMax) continue;
      _marker(
        canvas,
        Offset(g.xFor(cursorDistanceM), g.yFor(v)),
        s.marker,
        hollow: s.isModel,
      );
    }
    final FsplMeasuredMark? m = measured;
    if (m != null) _measured(canvas, g, p, m);
  }

  // ── Grid and axes ────────────────────────────────────────────────────────

  void _grid(Canvas canvas, FsplChartGeometry g, Rect p) {
    final Paint minor = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    final Paint majorPaint = Paint()
      ..color = style.axis
      ..strokeWidth = 1;

    final List<FsplDistanceTick> ticks = distanceTicks(
      units: units,
      minDistanceM: minDistanceM,
      maxDistanceM: maxDistanceM,
      logDistance: logDistance,
    );
    for (final FsplDistanceTick t in ticks) {
      final double x = g.xFor(t.metres);
      canvas.drawLine(
        Offset(x, p.top),
        Offset(x, p.bottom),
        t.major ? majorPaint : minor,
      );
    }
    // Labels: the two ends always; an interior label only where it clears
    // its neighbours (3 ft to 300 ft puts 100 ft close to 300 ft on a phone).
    final List<(FsplDistanceTick, Rect)> labelled =
        <(FsplDistanceTick, Rect)>[
          for (final FsplDistanceTick t in ticks)
            if (t.label != null) (t, _labelRect(g, t)),
        ]..sort(((FsplDistanceTick, Rect) a, (FsplDistanceTick, Rect) b) {
          int rank(FsplDistanceTick t) => (t.first || t.last) ? 0 : 1;
          return rank(a.$1).compareTo(rank(b.$1));
        });
    final List<Rect> drawn = <Rect>[];
    for (final (FsplDistanceTick t, Rect r) in labelled) {
      if (drawn.any((Rect d) => d.inflate(3).overlaps(r))) continue;
      drawn.add(r);
      _text(canvas, t.label!, style.axisLabel, r.topLeft);
    }

    // Level: every yStep.
    final double first = (yMin / yStep).ceil() * yStep;
    for (double v = first; v <= yMax + 1e-9; v += yStep) {
      final double y = g.yFor(v);
      canvas.drawLine(Offset(p.left, y), Offset(p.right, y), minor);
      _text(
        canvas,
        v.toStringAsFixed(0),
        style.axisLabel,
        Offset(p.left - 6, y),
        anchor: const Offset(1, 0.5),
      );
    }
    canvas.drawRect(
      p,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// The distance grid, every tick a round number in the unit on screen.
  ///
  /// Linear: a labelled major every NiceTicks step (20 m on 100 m, 200 m on
  /// 1 km, 50 ft on 300 ft, 500 ft on 3,000 ft) and a minor halfway.
  /// Log: in the displayed unit, a labelled major at each power of ten and
  /// at both ends of the axis, a minor at every other whole multiple (2..9 m,
  /// 20..90 m; 4..9 ft, 20..90 ft, 200 ft).
  static List<FsplDistanceTick> distanceTicks({
    required UnitSystem units,
    required double minDistanceM,
    required double maxDistanceM,
    required bool logDistance,
  }) {
    final LengthFormat f = LengthFormat(units);
    final double lo = f.distValue(minDistanceM);
    final double hi = f.distValue(maxDistanceM);
    bool near(double a, double b) => (a - b).abs() <= 1e-6 * math.max(1, b);
    final List<FsplDistanceTick> out = <FsplDistanceTick>[];
    if (!logDistance) {
      final double major = NiceTicks.step(hi);
      final double minorStep = major / 2;
      for (int i = 0; i * minorStep <= hi * (1 + 1e-9); i++) {
        final double v = i * minorStep;
        final bool isMajor = i.isEven;
        out.add(
          FsplDistanceTick(
            metres: f.distToMetres(v),
            major: isMajor,
            label: !isMajor ? null : (v == 0 ? '0' : _tickLabel(v, units)),
            first: v == 0,
            last: near(v, hi),
          ),
        );
      }
      return out;
    }
    final double firstDecade = math
        .pow(10, (math.log(lo) / math.ln10 + 1e-9).floor())
        .toDouble();
    for (double decade = firstDecade; decade <= hi * (1 + 1e-9); decade *= 10) {
      for (int k = 1; k <= 9; k++) {
        final double v = decade * k;
        if (v < lo * (1 - 1e-9) || v > hi * (1 + 1e-9)) continue;
        final bool isFirst = near(v, lo);
        final bool isLast = near(v, hi);
        final bool isMajor = k == 1 || isFirst || isLast;
        out.add(
          FsplDistanceTick(
            metres: f.distToMetres(v),
            major: isMajor,
            label: isMajor ? _tickLabel(v, units) : null,
            first: isFirst,
            last: isLast,
          ),
        );
      }
    }
    return out;
  }

  /// A tick label: whole metres (km from 1000) or whole feet.
  static String _tickLabel(double shown, UnitSystem u) {
    if (u.isMetric) {
      return shown >= 1000
          ? '${(shown / 1000).toStringAsFixed(shown % 1000 == 0 ? 0 : 1)} km'
          : '${shown.round()} m';
    }
    final int ft = shown.round();
    return ft >= 1000
        ? '${ft ~/ 1000},${(ft % 1000).toString().padLeft(3, '0')} ft'
        : '$ft ft';
  }

  // ── Series ───────────────────────────────────────────────────────────────

  void _series(Canvas canvas, FsplChartGeometry g, FsplSeries s) {
    if (s.points.length < 2) return;
    final Path path = Path();
    for (int i = 0; i < s.points.length; i++) {
      final (double d, double v) = s.points[i];
      final Offset o = Offset(g.xFor(d), g.yFor(v));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final Paint paint = Paint()
      ..color = s.isModel ? style.model : style.curve
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.scale.strokeWidth(s.isModel ? 1.5 : 2.5)
      ..strokeCap = s.stroke == CurveStroke.dotted
          ? StrokeCap.round
          : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round;
    final double k = style.scale.stroke;
    switch (s.stroke) {
      case CurveStroke.solid:
        canvas.drawPath(path, paint);
      case CurveStroke.dashed:
        canvas.drawPath(_dash(path, 10 * k, 6 * k), paint);
      case CurveStroke.dotted:
        canvas.drawPath(_dash(path, 0.1, 6 * k), paint);
    }
  }

  static Path _dash(Path source, double on, double off) {
    final Path out = Path();
    for (final ui.PathMetric m in source.computeMetrics()) {
      double at = 0;
      while (at < m.length) {
        out.addPath(
          m.extractPath(at, math.min(at + on, m.length)),
          Offset.zero,
        );
        at += on + off;
      }
    }
    return out;
  }

  void _marker(
    Canvas canvas,
    Offset c,
    CurveMarker shape, {
    bool hollow = false,
  }) {
    final double r = style.scale.markerSize(5.5);
    final Paint rim = Paint()
      ..color = style.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.scale.strokeWidth(4);
    final Paint body = Paint()
      ..color = hollow ? style.model : style.curve
      ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = style.scale.strokeWidth(2);
    final Path path = Path();
    switch (shape) {
      case CurveMarker.circle:
        path.addOval(Rect.fromCircle(center: c, radius: r));
      case CurveMarker.square:
        path.addRect(
          Rect.fromCenter(center: c, width: r * 1.8, height: r * 1.8),
        );
      case CurveMarker.triangle:
        path
          ..moveTo(c.dx, c.dy - r * 1.1)
          ..lineTo(c.dx + r * 1.05, c.dy + r * 0.8)
          ..lineTo(c.dx - r * 1.05, c.dy + r * 0.8)
          ..close();
    }
    canvas.drawPath(path, rim);
    canvas.drawPath(path, body);
  }

  // ── Reference lines ──────────────────────────────────────────────────────

  void _refLine(Canvas canvas, FsplChartGeometry g, Rect p, FsplRefLine r) {
    if (r.y < yMin || r.y > yMax) return;
    final double y = g.yFor(r.y);
    final Paint paint = Paint()
      ..color = style.refLine
      ..strokeWidth = style.scale.strokeWidth(1.25)
      ..style = PaintingStyle.stroke;
    final Path line = Path()
      ..moveTo(p.left, y)
      ..lineTo(p.right, y);
    canvas.drawPath(_dash(line, 4, 4), paint);
    // Labels sit at the left (near) end: in the received view the curves
    // are strongest there, far above the targets, so the label covers no
    // curve. Close lines put one label over and one under.
    _text(
      canvas,
      r.label,
      style.refLabel,
      Offset(p.left + 6, r.labelBelow ? y + 2 : y - 2),
      anchor: Offset(0, r.labelBelow ? 0 : 1),
      knockout: true,
    );
  }

  // ── Cursor ───────────────────────────────────────────────────────────────

  void _cursor(Canvas canvas, FsplChartGeometry g, Rect p) {
    final double x = g.xFor(cursorDistanceM);
    canvas.drawLine(
      Offset(x, p.top),
      Offset(x, p.bottom),
      Paint()
        ..color = style.cursor
        ..strokeWidth = style.scale.strokeWidth(1.5),
    );
    // Handle at the foot of the line: shows the line can be dragged.
    canvas.drawCircle(
      Offset(x, p.bottom),
      style.scale.markerSize(5),
      Paint()..color = style.cursor,
    );
    final TextPainter tp = _layout(cursorLabel, style.cursorLabel);
    final double w = tp.width + 10;
    final double left = (x - w / 2).clamp(p.left, p.right - w);
    final RRect pill = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, p.top + 2, w, tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(pill, Paint()..color = style.cursor);
    tp.paint(canvas, Offset(left + 5, p.top + 4));
  }

  // ── Measured point ───────────────────────────────────────────────────────

  void _measured(
    Canvas canvas,
    FsplChartGeometry g,
    Rect p,
    FsplMeasuredMark m,
  ) {
    if (m.distanceM > maxDistanceM || m.distanceM < 1) return;
    final double x = g.xFor(m.distanceM);
    final double y = g.yFor(m.y.clamp(yMin, yMax));
    final double yc = g.yFor(m.curveY.clamp(yMin, yMax));
    final Paint link = Paint()
      ..color = style.measured
      ..strokeWidth = style.scale.strokeWidth(1.5)
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      _dash(
        Path()
          ..moveTo(x, yc)
          ..lineTo(x, y),
        3,
        3,
      ),
      link,
    );
    // Diamond marker.
    final double r = style.scale.markerSize(7);
    final Path diamond = Path()
      ..moveTo(x, y - r)
      ..lineTo(x + r, y)
      ..lineTo(x, y + r)
      ..lineTo(x - r, y)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..color = style.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawPath(diamond, Paint()..color = style.measured);

    final TextPainter tp = _layout(m.label, style.refLabel);
    final double mid = (y + yc) / 2;
    final bool right = x + 10 + tp.width <= p.right;
    final double lx = right ? x + 10 : x - 10 - tp.width;
    final double ly = (mid - tp.height / 2).clamp(p.top, p.bottom - tp.height);
    canvas.drawRect(
      Rect.fromLTWH(lx - 2, ly, tp.width + 4, tp.height),
      Paint()..color = style.surface,
    );
    tp.paint(canvas, Offset(lx, ly));
  }

  // ── Text ─────────────────────────────────────────────────────────────────

  static TextPainter _layout(
    String s,
    TextStyle ts, {
    double maxWidth = double.infinity,
    TextAlign align = TextAlign.left,
  }) {
    return TextPainter(
      text: TextSpan(text: s, style: ts),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth);
  }

  /// Paints [s] so that [anchor] (0..1 of the text box) lands on [at].
  /// Where a distance tick label sits: under its line, pulled inside the
  /// plot at the two ends.
  Rect _labelRect(FsplChartGeometry g, FsplDistanceTick t) {
    final TextPainter tp = _layout(t.label!, style.axisLabel);
    final double ax = t.first ? 0 : (t.last ? 1 : 0.5);
    final Offset o = Offset(
      g.xFor(t.metres) - tp.width * ax,
      g.plot.bottom + 4,
    );
    return o & tp.size;
  }

  void _text(
    Canvas canvas,
    String s,
    TextStyle ts,
    Offset at, {
    Offset anchor = Offset.zero,
    double maxWidth = double.infinity,
    TextAlign align = TextAlign.left,
    bool knockout = false,
  }) {
    final TextPainter tp = _layout(s, ts, maxWidth: maxWidth, align: align);
    final Offset o = at - Offset(tp.width * anchor.dx, tp.height * anchor.dy);
    if (knockout) {
      canvas.drawRect(
        Rect.fromLTWH(o.dx - 3, o.dy, tp.width + 6, tp.height),
        Paint()..color = style.surface,
      );
    }
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(FsplChartPainter old) =>
      old.revision != revision ||
      old.logDistance != logDistance ||
      old.units != units ||
      old.minDistanceM != minDistanceM ||
      old.cursorDistanceM != cursorDistanceM ||
      old.style != style;
}

/// A short stroke sample for legends and band chips, drawn with the same
/// dash rules as the chart so the legend matches the plot exactly.
class FsplStrokeSamplePainter extends CustomPainter {
  FsplStrokeSamplePainter({
    required this.stroke,
    required this.marker,
    required this.color,
    required this.surface,
    this.model = false,
    this.scale = 1,
  });

  final CurveStroke stroke;
  final CurveMarker? marker;
  final Color color;
  final Color surface;
  final bool model;

  /// Presenter factor on the stroke and marker (1 elsewhere), so a legend
  /// sample matches the thicker presenter curves.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final Path line = Path()
      ..moveTo(0, y)
      ..lineTo(size.width, y);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (model ? 1.5 : 2.5) * scale
      ..strokeCap = stroke == CurveStroke.dotted
          ? StrokeCap.round
          : StrokeCap.butt;
    switch (stroke) {
      case CurveStroke.solid:
        canvas.drawPath(line, paint);
      case CurveStroke.dashed:
        canvas.drawPath(FsplChartPainter._dash(line, 7, 4), paint);
      case CurveStroke.dotted:
        canvas.drawPath(FsplChartPainter._dash(line, 0.1, 5), paint);
    }
    final CurveMarker? m = marker;
    if (m == null) return;
    final Offset c = Offset(size.width / 2, y);
    final double r = 4.5 * scale;
    final Paint body = Paint()
      ..color = color
      ..style = model ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = 1.5 * scale;
    final Paint rim = Paint()
      ..color = surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale;
    final Path path = Path();
    switch (m) {
      case CurveMarker.circle:
        path.addOval(Rect.fromCircle(center: c, radius: r));
      case CurveMarker.square:
        path.addRect(
          Rect.fromCenter(center: c, width: r * 1.8, height: r * 1.8),
        );
      case CurveMarker.triangle:
        path
          ..moveTo(c.dx, c.dy - r * 1.1)
          ..lineTo(c.dx + r * 1.05, c.dy + r * 0.8)
          ..lineTo(c.dx - r * 1.05, c.dy + r * 0.8)
          ..close();
    }
    canvas.drawPath(path, rim);
    canvas.drawPath(path, body);
  }

  @override
  bool shouldRepaint(FsplStrokeSamplePainter old) =>
      old.stroke != stroke ||
      old.marker != marker ||
      old.color != color ||
      old.surface != surface ||
      old.model != model ||
      old.scale != scale;
}

/// One distance grid line: where it sits, whether it is major, and its label
/// (null for an unlabelled minor line). [first] and [last] anchor the label
/// inside the plot at the two ends.
@immutable
class FsplDistanceTick {
  const FsplDistanceTick({
    required this.metres,
    required this.major,
    required this.label,
    this.first = false,
    this.last = false,
  });

  final double metres;
  final bool major;
  final String? label;
  final bool first;
  final bool last;
}
