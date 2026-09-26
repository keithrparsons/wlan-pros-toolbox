// Painters for the Wi-Fi Classroom Roaming Walk (roaming-walk).
//
// Token-only CustomPainters: every neutral color and text style arrives
// resolved from context.colors by the stage, and the AP hues come from
// roaming_walk_palette.dart (GL-003 §8.15.2), so each painter is correct in
// dark (§8) and light (§8.20) without knowing which theme it is in. The stage
// wraps each one in Semantics(excludeSemantics: true) with a worded label,
// and every number a painter shows is also in a text readout.
//
// Color roles:
//   * each AP has its own hue (§8.15.2): its marker, its label, its -67 and
//     -70 dBm contours and its RSSI trace, so the student can match them;
//   * lime (textAccent) is the serving link: the association line on the
//     floor and the serving-RSSI line on the plot (§8.3, the measured
//     quantity);
//   * everything else is neutral: floor, grid, path, trigger line, roam
//     markers, the "now" cursor;
//   * no status hue appears in a painter. Ping-pong is marked with the
//     letters PP and counted, with its verdict word, in the readouts.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/roaming_walk_engine.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Resolved colors and text styles shared by both painters.
@immutable
class RoamPaintStyle {
  const RoamPaintStyle({
    required this.apColors,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.grid,
    required this.axis,
    required this.halo,
    required this.labelStyle,
    this.sc = PresenterScale.normal,
  });

  /// One hue per AP index (§8.15.2).
  final List<Color> apColors;

  /// Lime: the serving link.
  final Color accent;

  /// Strongest neutral: the client and the "now" cursor.
  final Color primary;

  /// Walked path, roam markers.
  final Color secondary;

  /// The path still to walk, minor labels.
  final Color tertiary;

  /// Decorative grid.
  final Color grid;

  /// Floor outline, axes and the trigger line (3:1 or better).
  final Color axis;

  /// Outline drawn around markers so they separate from lines under them.
  final Color halo;

  /// Axis and marker labels.
  final TextStyle labelStyle;

  /// Presenter scale for strokes, markers and label offsets (identity
  /// outside presenter mode; labelStyle already carries the text factor).
  final PresenterScale sc;

  Color ap(int i) => apColors[i % apColors.length];

  @override
  bool operator ==(Object other) =>
      other is RoamPaintStyle &&
      _colorsEq(other.apColors, apColors) &&
      other.accent == accent &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.grid == grid &&
      other.axis == axis &&
      other.halo == halo &&
      other.labelStyle == labelStyle &&
      other.sc == sc;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(apColors),
    accent,
    primary,
    secondary,
    tertiary,
    grid,
    axis,
    halo,
    labelStyle,
    sc,
  );
}

bool _colorsEq(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Draws [path] dashed.
void _dashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  double dash = 6,
  double gap = 4,
}) {
  for (final ui in path.computeMetrics()) {
    double d = 0;
    while (d < ui.length) {
      canvas.drawPath(ui.extractPath(d, math.min(d + dash, ui.length)), paint);
      d += dash + gap;
    }
  }
}

void _label(
  Canvas canvas,
  String text,
  Offset at,
  TextStyle style, {
  Alignment align = Alignment.center,
  Color? background,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final Offset o = Offset(
    at.dx - tp.width * (align.x + 1) / 2,
    at.dy - tp.height * (align.y + 1) / 2,
  );
  if (background != null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (o & tp.size).inflate(2),
        const Radius.circular(2),
      ),
      Paint()..color = background,
    );
  }
  tp.paint(canvas, o);
}

// ── Floor plan ──────────────────────────────────────────────────────────────

/// Maps floor meters to canvas pixels, keeping 1 m the same on both axes.
@immutable
class FloorMapping {
  factory FloorMapping(Size size) {
    const double inset = 10;
    final double scale = math.min(
      (size.width - 2 * inset) / kFloorWidthM,
      (size.height - 2 * inset) / kFloorDepthM,
    );
    final double w = kFloorWidthM * scale;
    final double h = kFloorDepthM * scale;
    return FloorMapping._(
      scale,
      Offset((size.width - w) / 2, (size.height - h) / 2),
    );
  }

  const FloorMapping._(this.scale, this.origin);

  /// Pixels per meter.
  final double scale;
  final Offset origin;

  Offset toCanvas(FloorPoint p) => origin + Offset(p.x * scale, p.y * scale);

  FloorPoint toFloor(Offset o) {
    final Offset d = (o - origin) / scale;
    return (x: d.dx, y: d.dy);
  }

  Rect get floorRect => Rect.fromLTWH(
    origin.dx,
    origin.dy,
    kFloorWidthM * scale,
    kFloorDepthM * scale,
  );
}

class RoamFloorPainter extends CustomPainter {
  RoamFloorPainter({
    required this.config,
    required this.result,
    required this.sample,
    required this.style,
    required this.editingAp,
    required this.drawnPoints,
    required this.drawing,
  });

  final RoamWalkConfig config;
  final RoamWalkResult result;
  final int sample;
  final RoamPaintStyle style;
  final int editingAp;
  final List<FloorPoint> drawnPoints;
  final bool drawing;

  @override
  void paint(Canvas canvas, Size size) {
    final FloorMapping m = FloorMapping(size);
    final Rect floor = m.floorRect;

    // Grid every 10 m.
    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = style.sc.strokeWidth(1);
    for (double x = 10; x < kFloorWidthM; x += 10) {
      canvas.drawLine(
        m.toCanvas((x: x, y: 0)),
        m.toCanvas((x: x, y: kFloorDepthM)),
        grid,
      );
    }
    for (double y = 10; y < kFloorDepthM; y += 10) {
      canvas.drawLine(
        m.toCanvas((x: 0, y: y)),
        m.toCanvas((x: kFloorWidthM, y: y)),
        grid,
      );
    }

    // Contours, clipped to the floor.
    canvas.save();
    canvas.clipRect(floor);
    final double r67 = config.contourRadiusM(kDesignOverlapDbm) * m.scale;
    final double r70 = config.contourRadiusM(kWeakSignalDbm) * m.scale;
    for (int i = 0; i < config.aps.length; i++) {
      final Offset c = m.toCanvas(config.aps[i]);
      final Paint p = Paint()
        ..color = style.ap(i)
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.sc.strokeWidth(1.5);
      canvas.drawCircle(c, r67, p);
      _dashedPath(
        canvas,
        Path()..addOval(Rect.fromCircle(center: c, radius: r70)),
        p,
      );
    }
    canvas.restore();

    // Floor outline.
    canvas.drawRect(
      floor,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.sc.strokeWidth(1.5),
    );

    // The path: still to walk (dashed, quiet), walked (solid).
    final Path whole = _polyline(m, config.path);
    _dashedPath(
      canvas,
      whole,
      Paint()
        ..color = style.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.sc.strokeWidth(1.5),
    );
    if (sample > 0) {
      final Path walked = Path()
        ..moveTo(
          m.toCanvas(result.positions.first).dx,
          m.toCanvas(result.positions.first).dy,
        );
      for (int k = 1; k <= sample; k++) {
        final Offset o = m.toCanvas(result.positions[k]);
        walked.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        walked,
        Paint()
          ..color = style.secondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.sc.strokeWidth(2),
      );
    }
    // Where the walk starts: a short label beside the first point, on the
    // side with room.
    final FloorPoint start = config.path.first;
    final bool labelBelow = start.y < kFloorDepthM - 3;
    _label(
      canvas,
      'start',
      m.toCanvas(start) + Offset(4, labelBelow ? 5 : -5),
      style.labelStyle.copyWith(color: style.secondary),
      align: labelBelow ? Alignment.topLeft : Alignment.bottomLeft,
      background: style.halo,
    );

    final FloorPoint client = result.positions[sample];
    final Offset cp = m.toCanvas(client);

    if (!drawing) {
      // Association line (lime) or, mid-roam, a dashed line to the target.
      final int? s = result.servingAt(sample);
      if (s != null) {
        canvas.drawLine(
          cp,
          m.toCanvas(config.aps[s]),
          Paint()
            ..color = style.accent
            ..strokeWidth = style.sc.strokeWidth(3)
            ..strokeCap = StrokeCap.round,
        );
      } else {
        final RoamEvent? e = result.gapAt(sample);
        if (e != null) {
          _dashedPath(
            canvas,
            Path()
              ..moveTo(cp.dx, cp.dy)
              ..lineTo(
                m.toCanvas(config.aps[e.toAp]).dx,
                m.toCanvas(config.aps[e.toAp]).dy,
              ),
            Paint()
              ..color = style.secondary
              ..style = PaintingStyle.stroke
              ..strokeWidth = style.sc.strokeWidth(2),
            dash: 4,
            gap: 3,
          );
        }
      }
    }

    // APs.
    for (int i = 0; i < config.aps.length; i++) {
      final Offset c = m.toCanvas(config.aps[i]);
      if (i == editingAp) {
        canvas.drawCircle(
          c,
          style.sc.markerSize(11),
          Paint()
            ..color = style.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.sc.strokeWidth(1.5),
        );
      }
      canvas.drawCircle(c, style.sc.markerSize(8), Paint()..color = style.halo);
      canvas.drawCircle(
        c,
        style.sc.markerSize(6.5),
        Paint()..color = style.ap(i),
      );
      final bool below = config.aps[i].y < 3;
      _label(
        canvas,
        'AP ${i + 1}',
        c + Offset(0, (below ? 18 : -18) * style.sc.text),
        style.labelStyle.copyWith(
          color: style.ap(i),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    // The client.
    if (!drawing) {
      canvas.drawCircle(
        cp,
        style.sc.markerSize(7.5),
        Paint()..color = style.halo,
      );
      canvas.drawCircle(
        cp,
        style.sc.markerSize(6),
        Paint()..color = style.primary,
      );
    }

    // A path being drawn.
    if (drawing && drawnPoints.isNotEmpty) {
      final Paint pen = Paint()
        ..color = style.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.sc.strokeWidth(2.5)
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(_polyline(m, drawnPoints), pen);
      for (final FloorPoint p in drawnPoints) {
        canvas.drawCircle(
          m.toCanvas(p),
          style.sc.markerSize(4),
          Paint()..color = style.accent,
        );
      }
    }
  }

  static Path _polyline(FloorMapping m, List<FloorPoint> pts) {
    final Path p = Path();
    for (int i = 0; i < pts.length; i++) {
      final Offset o = m.toCanvas(pts[i]);
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p;
  }

  @override
  bool shouldRepaint(RoamFloorPainter old) =>
      old.config != config ||
      old.result != result ||
      old.sample != sample ||
      old.style != style ||
      old.editingAp != editingAp ||
      old.drawing != drawing ||
      old.drawnPoints.length != drawnPoints.length;
}

// ── RSSI over time ──────────────────────────────────────────────────────────

/// Plot range, dBm.
const double kPlotTopDbm = -30;
const double kPlotBottomDbm = -95;

class RoamRssiPainter extends CustomPainter {
  RoamRssiPainter({
    required this.result,
    required this.sample,
    required this.style,
  });

  final RoamWalkResult result;
  final int sample;
  final RoamPaintStyle style;

  static const double _left = 36;
  static const double _right = 18;
  static const double _top = 18;
  static const double _bottom = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final RoamWalkConfig c = result.config;
    final double k = style.sc.text;
    final Rect plot = Rect.fromLTRB(
      _left * k,
      _top * k,
      size.width - _right * k,
      size.height - _bottom * k,
    );
    final double dur = math.max(result.durationS, kRoamSampleSeconds);
    double xOf(double t) => plot.left + plot.width * t / dur;
    double yOf(double dbm) {
      final double v = dbm.clamp(kPlotBottomDbm, kPlotTopDbm);
      return plot.top +
          plot.height * (kPlotTopDbm - v) / (kPlotTopDbm - kPlotBottomDbm);
    }

    final TextStyle axisLabel = style.labelStyle.copyWith(
      color: style.secondary,
    );

    // Grid and dBm labels every 10 dB.
    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = style.sc.strokeWidth(1);
    for (double d = -40; d >= kPlotBottomDbm; d -= 10) {
      final double y = yOf(d);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(
        canvas,
        d.toStringAsFixed(0),
        Offset(plot.left - 4, y),
        axisLabel,
        align: Alignment.centerRight,
      );
    }
    // Time labels: the smallest step that leaves room for each label.
    double tick = 60;
    for (final double t in <double>[5, 10, 20, 30, 60]) {
      if (plot.width * t / dur >= 44) {
        tick = t;
        break;
      }
    }
    for (double t = 0; t <= dur + 1e-9; t += tick) {
      _label(
        canvas,
        '${t.toStringAsFixed(0)} s',
        Offset(xOf(t), plot.bottom + 4),
        axisLabel,
        align: Alignment.topCenter,
      );
    }
    // Axis frame.
    canvas.drawRect(
      plot,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.sc.strokeWidth(1),
    );

    // Trigger, and -70 dBm when the trigger is elsewhere.
    final Paint ref = Paint()
      ..color = style.axis
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.sc.strokeWidth(1.5);
    final double yT = yOf(c.triggerDbm);
    _dashedPath(
      canvas,
      Path()
        ..moveTo(plot.left, yT)
        ..lineTo(plot.right, yT),
      ref,
    );
    if (c.triggerDbm != kWeakSignalDbm) {
      final double y70 = yOf(kWeakSignalDbm);
      _dashedPath(
        canvas,
        Path()
          ..moveTo(plot.left, y70)
          ..lineTo(plot.right, y70),
        Paint()
          ..color = style.tertiary
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.sc.strokeWidth(1),
        dash: 2,
        gap: 3,
      );
    }

    // Reference-line labels, drawn UNDER the traces: data is never hidden
    // behind a label, and the label reads wherever no trace crosses it.
    _label(
      canvas,
      'trigger ${c.triggerDbm.toStringAsFixed(0)}',
      Offset(plot.left + 4, yT - 3),
      axisLabel.copyWith(color: style.primary),
      align: Alignment.bottomLeft,
      background: style.halo,
    );
    if (c.triggerDbm != kWeakSignalDbm) {
      final double y70 = yOf(kWeakSignalDbm);
      _label(
        canvas,
        '-70',
        Offset(plot.right - 4, y70 + (y70 < yT ? -2 : 2)),
        axisLabel.copyWith(color: style.secondary),
        align: y70 < yT ? Alignment.bottomRight : Alignment.topRight,
        background: style.halo,
      );
    }

    canvas.save();
    canvas.clipRect(plot.inflate(2));

    // One trace per AP, up to now.
    final int last = sample.clamp(0, result.sampleCount - 1);
    for (int a = 0; a < result.rssi.length; a++) {
      final Path p = Path();
      for (int k = 0; k <= last; k++) {
        final Offset o = Offset(xOf(result.timeOf(k)), yOf(result.rssi[a][k]));
        if (k == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = style.ap(a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.sc.strokeWidth(1.5)
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // The serving RSSI (lime), broken during roam gaps.
    final Paint serve = Paint()
      ..color = style.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.sc.strokeWidth(3)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? run;
    for (int k = 0; k <= last; k++) {
      final int? s = result.servingAt(k);
      final int? prev = k > 0 ? result.servingAt(k - 1) : null;
      if (s == null) {
        if (run != null) canvas.drawPath(run, serve);
        run = null;
        continue;
      }
      final Offset o = Offset(xOf(result.timeOf(k)), yOf(result.rssi[s][k]));
      if (run == null || prev != s) {
        if (run != null) canvas.drawPath(run, serve);
        run = Path()..moveTo(o.dx, o.dy);
        if (k == last || result.servingAt(k + 1) != s) {
          run.lineTo(o.dx + 0.5, o.dy);
        }
      } else {
        run.lineTo(o.dx, o.dy);
      }
    }
    if (run != null) canvas.drawPath(run, serve);
    canvas.restore();

    // Roam markers, labelled with the gap. A label that would overlap the
    // one before it is skipped; the roam log lists every gap.
    double lastLabelRight = -1e9;
    final Paint mark = Paint()
      ..color = style.secondary
      ..strokeWidth = style.sc.strokeWidth(1);
    final TextStyle markStyle = axisLabel.copyWith(color: style.primary);
    for (final RoamEvent e in result.events) {
      if (e.sample > last) break;
      final double x = xOf(e.timeS);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), mark);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${e.gapMs.round()}${e.pingPong ? ' PP' : ''}',
          style: markStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double left = (x - tp.width / 2).clamp(
        plot.left + (44 - _left) * k,
        size.width - tp.width,
      );
      if (left >= lastLabelRight + 4) {
        tp.paint(canvas, Offset(left, plot.top - 3 - tp.height));
        lastLabelRight = left + tp.width;
      }
    }
    _label(
      canvas,
      'gap, ms',
      Offset(2, plot.top - 3),
      axisLabel.copyWith(color: style.secondary),
      align: Alignment.bottomLeft,
    );

    // Trace labels at the right end of what has been walked, pushed apart.
    final double xNow = xOf(result.timeOf(last));
    final List<({int ap, double y})> tags = <({int ap, double y})>[
      for (int a = 0; a < result.rssi.length; a++)
        (ap: a, y: yOf(result.rssi[a][last])),
    ]..sort((x, y) => x.y.compareTo(y.y));
    final double gapPx = 11 * k;
    final List<double> ys = <double>[for (final t in tags) t.y];
    for (int i = 1; i < ys.length; i++) {
      if (ys[i] - ys[i - 1] < gapPx) ys[i] = ys[i - 1] + gapPx;
    }
    final double overflow = ys.isEmpty ? 0 : ys.last - plot.bottom;
    if (overflow > 0) {
      for (int i = 0; i < ys.length; i++) {
        ys[i] -= overflow;
      }
    }
    final bool rightSide = xNow < plot.right - 14;
    for (int i = 0; i < tags.length; i++) {
      _label(
        canvas,
        '${tags[i].ap + 1}',
        Offset(rightSide ? xNow + 5 : plot.right + 3, ys[i]),
        axisLabel.copyWith(
          color: style.ap(tags[i].ap),
          fontWeight: FontWeight.w700,
        ),
        align: Alignment.centerLeft,
      );
    }

    // "Now" cursor.
    canvas.drawLine(
      Offset(xNow, plot.top),
      Offset(xNow, plot.bottom),
      Paint()
        ..color = style.primary
        ..strokeWidth = style.sc.strokeWidth(1.5),
    );
  }

  @override
  bool shouldRepaint(RoamRssiPainter old) =>
      old.result != result || old.sample != sample || old.style != style;
}
