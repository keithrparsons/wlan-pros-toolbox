// Painters for the Wi-Fi Classroom Survey Walk (survey-walk).
//
// Token-only CustomPainters: every neutral color and text style arrives
// resolved from context.colors by the stage, and the AP hues come from
// roaming_walk_palette.dart (GL-003 §8.15.2), so each painter is correct in
// dark (§8) and light (§8.20) without knowing which theme it is in. The stage
// wraps each one in Semantics(excludeSemantics: true) with a worded label,
// and every number a painter shows is also in a text readout.
//
// Color roles:
//   * lime (textAccent) is the measured quantity: the samples of the shown
//     channel, the band of floor they cover, and the radios' current
//     channels on the strip;
//   * "no data" is white (surface white in light, text white in dark) with a
//     dashed outline and the words "No data" (Keith's Rule 6: white means no
//     data, never no coverage);
//   * each AP has its own hue (§8.15.2) and always its "AP n, ch x" label;
//   * in "all channels" view the bands are told apart by marker SHAPE
//     (circle 2.4, square 5, diamond 6 GHz) in one neutral, with a legend;
//   * ghosts (where a sample was really taken) are hollow tertiary rings
//     joined to the placed dot by a thin line;
//   * no status hue appears in a painter; pass and fail are words in the
//     readouts.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/survey_walk_engine.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'roaming_walk_painters.dart' show FloorMapping;

/// Resolved colors and text styles shared by the painters.
@immutable
class SurveyPaintStyle {
  const SurveyPaintStyle({
    required this.apColors,
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.grid,
    required this.axis,
    required this.halo,
    required this.floor,
    required this.noData,
    required this.disabled,
    required this.labelStyle,
    this.sc = PresenterScale.normal,
  });

  final List<Color> apColors;

  /// Lime: the measured samples and their coverage.
  final Color accent;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color grid;
  final Color axis;
  final Color halo;

  /// Floor fill.
  final Color floor;

  /// White: no data.
  final Color noData;

  /// Greyed-out APs an active survey cannot see.
  final Color disabled;
  final TextStyle labelStyle;
  final PresenterScale sc;

  Color ap(int i) => apColors[i % apColors.length];

  @override
  bool operator ==(Object other) =>
      other is SurveyPaintStyle &&
      listEquals(other.apColors, apColors) &&
      other.accent == accent &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.tertiary == tertiary &&
      other.grid == grid &&
      other.axis == axis &&
      other.halo == halo &&
      other.floor == floor &&
      other.noData == noData &&
      other.disabled == disabled &&
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
    floor,
    noData,
    disabled,
    labelStyle,
    sc,
  );
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

void _dashed(Canvas canvas, Path path, Paint paint, {double dash = 5}) {
  for (final ui.PathMetric m in path.computeMetrics()) {
    double d = 0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      d += dash * 1.8;
    }
  }
}

/// A band marker: circle (2.4 GHz), square (5 GHz) or diamond (6 GHz).
void drawBandMarker(
  Canvas canvas,
  Offset c,
  double r,
  RoamBand band,
  Paint paint,
) {
  switch (band) {
    case RoamBand.b24:
      canvas.drawCircle(c, r, paint);
    case RoamBand.b5:
      canvas.drawRect(Rect.fromCircle(center: c, radius: r * 0.9), paint);
    case RoamBand.b6:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r * 1.2)
          ..lineTo(c.dx + r * 1.2, c.dy)
          ..lineTo(c.dx, c.dy + r * 1.2)
          ..lineTo(c.dx - r * 1.2, c.dy)
          ..close(),
        paint,
      );
  }
}

/// The path polyline in canvas pixels.
Path _polyline(FloorMapping m, List<FloorPoint> pts) {
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

/// The part of [path] from [s0] to [s1] meters (one contour, uniform scale).
Path _sub(Path path, FloorMapping m, double s0, double s1) {
  final Path out = Path();
  for (final ui.PathMetric pm in path.computeMetrics()) {
    out.addPath(pm.extractPath(s0 * m.scale, s1 * m.scale), Offset.zero);
    break;
  }
  return out;
}

// ── Floor ───────────────────────────────────────────────────────────────────

class SurveyFloorPainter extends CustomPainter {
  SurveyFloorPainter({
    required this.result,
    required this.timeS,
    required this.shown,
    required this.style,
    required this.drawnPoints,
    required this.drawing,
  });

  final SurveyWalkResult result;
  final double timeS;

  /// Channel index to show, or null for all.
  final int? shown;
  final SurveyPaintStyle style;
  final List<FloorPoint> drawnPoints;
  final bool drawing;

  @override
  void paint(Canvas canvas, Size size) {
    final FloorMapping m = FloorMapping(size);
    final Rect floor = m.floorRect;
    final SurveyWalkConfig cfg = result.config;
    final PresenterScale sc = style.sc;

    canvas.drawRect(floor, Paint()..color = style.floor);

    // Corridor and rooms: drawn for orientation only; the model has no walls.
    final Paint wall = Paint()
      ..color = style.grid
      ..strokeWidth = sc.strokeWidth(1);
    for (final double y in const <double>[kCorridorTopM, kCorridorBottomM]) {
      canvas.drawLine(
        m.toCanvas((x: 0, y: y)),
        m.toCanvas((x: kFloorWidthM, y: y)),
        wall,
      );
    }
    for (double x = 10; x < kFloorWidthM; x += 10) {
      canvas.drawLine(
        m.toCanvas((x: x, y: 0)),
        m.toCanvas((x: x, y: kCorridorTopM)),
        wall,
      );
      canvas.drawLine(
        m.toCanvas((x: x, y: kCorridorBottomM)),
        m.toCanvas((x: x, y: kFloorDepthM)),
        wall,
      );
    }

    if (drawing) {
      _paintAps(canvas, m);
      _paintDrawing(canvas, m);
      _outline(canvas, floor);
      return;
    }

    final Path path = _polyline(m, cfg.path);
    final double sNow = result.plan.sAt(timeS);

    // Coverage of the shown channel along the walked part of the path.
    final int? ch = shown;
    if (ch != null && sNow > 0) {
      final List<double> known = <double>[
        for (final SurveySample s in result.samplesOf(ch))
          if (s.measuredAtS <= timeS && _counts(s, ch))
            s.placedAtS <= timeS ? s.placedS : s.trueS,
      ];
      final double band = cfg.guessRangeM * m.scale;
      canvas.save();
      canvas.clipRect(floor);
      canvas.drawPath(
        _sub(path, m, 0, sNow),
        Paint()
          ..color = style.accent.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = band
          ..strokeCap = StrokeCap.butt,
      );
      final List<(double, double)> gaps = noDataIntervals(
        known,
        cfg.guessRangeM,
        sNow,
      );
      (double, double)? widest;
      for (final (double, double) g in gaps) {
        if (g.$2 - g.$1 < 0.05) continue;
        final Path seg = _sub(path, m, g.$1, g.$2);
        canvas.drawPath(
          seg,
          Paint()
            ..color = style.noData
            ..style = PaintingStyle.stroke
            ..strokeWidth = band
            ..strokeCap = StrokeCap.butt,
        );
        if (widest == null || g.$2 - g.$1 > widest.$2 - widest.$1) widest = g;
      }
      for (final (double, double) g in gaps) {
        if (g.$2 - g.$1 < 0.05) continue;
        // Dashed edges either side of the white band.
        final Path seg = _sub(path, m, g.$1, g.$2);
        for (final ui.PathMetric pm in seg.computeMetrics()) {
          for (final double side in <double>[-1, 1]) {
            final Path edge = Path();
            for (double d = 0; d <= pm.length; d += 2) {
              final ui.Tangent? t = pm.getTangentForOffset(d);
              if (t == null) continue;
              final Offset n = Offset(-t.vector.dy, t.vector.dx);
              final Offset p = t.position + n * (side * band / 2);
              if (d == 0) {
                edge.moveTo(p.dx, p.dy);
              } else {
                edge.lineTo(p.dx, p.dy);
              }
            }
            _dashed(
              canvas,
              edge,
              Paint()
                ..color = style.axis
                ..style = PaintingStyle.stroke
                ..strokeWidth = sc.strokeWidth(1.2),
            );
          }
        }
      }
      final (double, double)? w = widest;
      if (w != null && (w.$2 - w.$1) * m.scale > 40) {
        final FloorPoint mid = pointAlong(cfg.path, (w.$1 + w.$2) / 2);
        _label(
          canvas,
          'No data',
          m.toCanvas(mid),
          style.labelStyle.copyWith(color: style.primary),
          background: style.halo,
        );
      }
      canvas.restore();
    }

    // The path: walked solid, still to walk dashed.
    final Paint walked = Paint()
      ..color = style.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(2)
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_sub(path, m, 0, sNow), walked);
    _dashed(
      canvas,
      _sub(path, m, sNow, result.plan.lengthM),
      Paint()
        ..color = style.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1.5),
    );

    // Stops (stop and go) and the door.
    if (cfg.capture == CaptureMethod.stopAndGo) {
      for (final WalkClick c in result.plan.clicks) {
        final Offset o = m.toCanvas(pointAlong(cfg.path, c.s));
        canvas.drawCircle(
          o,
          sc.markerSize(4),
          Paint()
            ..color = style.tertiary
            ..style = PaintingStyle.stroke
            ..strokeWidth = sc.strokeWidth(1),
        );
      }
    }
    if (cfg.doorPause) {
      final double s = cfg.doorS;
      final Offset a = m.toCanvas(pointAlong(cfg.path, s));
      final FloorPoint p0 = cfg.path[0];
      final FloorPoint p1 = cfg.path[1];
      final Offset dir = Offset(p1.x - p0.x, p1.y - p0.y);
      final Offset n = Offset(-dir.dy, dir.dx) / dir.distance;
      final double h = sc.markerSize(10);
      canvas.drawLine(
        a - n * h,
        a + n * h,
        Paint()
          ..color = style.primary
          ..strokeWidth = sc.strokeWidth(3)
          ..strokeCap = StrokeCap.round,
      );
      _label(
        canvas,
        'Door, ${cfg.doorPauseS.toStringAsFixed(0)} s',
        a - n * (h + sc.markerSize(8)),
        style.labelStyle,
        background: style.halo,
      );
    }

    _paintAps(canvas, m);
    _paintSamples(canvas, m);

    // The walker.
    final Offset w = m.toCanvas(pointAlong(cfg.path, sNow));
    canvas.drawCircle(w, sc.markerSize(8), Paint()..color = style.halo);
    canvas.drawCircle(w, sc.markerSize(6), Paint()..color = style.primary);

    _outline(canvas, floor);
  }

  /// A sample counts toward the shown channel's map: passive samples of a
  /// scanned channel, or active samples of a channel nothing else visits.
  bool _counts(SurveySample s, int ch) =>
      !s.active || result.stats[ch].samples == 0 || _onlyActive(ch);

  bool _onlyActive(int ch) =>
      !result.samplesOf(ch).any((SurveySample s) => !s.active);

  void _outline(Canvas canvas, Rect floor) {
    canvas.drawRect(
      floor,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.sc.strokeWidth(1.5),
    );
  }

  void _paintAps(Canvas canvas, FloorMapping m) {
    final List<SurveyAp> aps = result.config.aps;
    final PresenterScale sc = style.sc;
    // Active survey: only the associated AP is seen; every other AP the
    // passive view would show is greyed out (spec 26).
    final bool activeOnly =
        !drawing && result.config.effectiveType == SurveyType.active;
    final int? serving = activeOnly ? result.servingApAt(timeS) : null;
    if (serving != null) {
      final Offset w = m.toCanvas(
        pointAlong(result.config.path, result.plan.sAt(timeS)),
      );
      canvas.drawLine(
        w,
        m.toCanvas(aps[serving].position),
        Paint()
          ..color = style.accent
          ..strokeWidth = sc.strokeWidth(2.5)
          ..strokeCap = StrokeCap.round,
      );
    }
    for (int i = 0; i < aps.length; i++) {
      final SurveyAp ap = aps[i];
      final bool grey = activeOnly && i != serving;
      final Color hue = grey ? style.disabled : style.ap(i);
      final Offset c = m.toCanvas(ap.position);
      final double r = sc.markerSize(7);
      canvas.drawCircle(c, r + sc.strokeWidth(2), Paint()..color = style.halo);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = hue
          ..style = ap.neighbor || grey
              ? PaintingStyle.stroke
              : PaintingStyle.fill
          ..strokeWidth = sc.strokeWidth(2.5),
      );
      final bool below = ap.position.y < kFloorDepthM / 2;
      _label(
        canvas,
        i == serving ? '${ap.label}, associated' : ap.label,
        c + Offset(0, (below ? 1 : -1) * (r + sc.markerSize(9))),
        style.labelStyle.copyWith(color: hue),
        background: style.halo,
      );
    }
  }

  void _paintSamples(Canvas canvas, FloorMapping m) {
    final PresenterScale sc = style.sc;
    final int? ch = shown;
    final Paint ghostLine = Paint()
      ..color = style.tertiary
      ..strokeWidth = sc.strokeWidth(1);
    final Paint ghost = Paint()
      ..color = style.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(1.2);
    final Paint pendingPaint = Paint()
      ..color = style.secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(1.2);
    final Color dot = ch == null ? style.secondary : style.accent;
    final Paint fill = Paint()..color = dot;
    final Paint halo = Paint()..color = style.halo;
    final double r = sc.markerSize(ch == null ? 2.6 : 4);
    for (final SurveySample s in result.samples) {
      if (s.measuredAtS > timeS) break;
      if (ch != null && s.channel != ch) continue;
      final RoamBand band = result.channels[s.channel].band;
      final Offset t = m.toCanvas(s.truePoint);
      if (s.placedAtS > timeS) {
        // Measured, waiting for the next click to be placed.
        drawBandMarker(canvas, t, r, band, pendingPaint);
        continue;
      }
      final Offset p = m.toCanvas(s.placedPoint);
      if (s.errorM > 0.3) {
        canvas.drawLine(t, p, ghostLine);
        drawBandMarker(canvas, t, r, band, ghost);
      }
      drawBandMarker(canvas, p, r + sc.strokeWidth(1), band, halo);
      if (s.active) {
        // Active test: a ring with a center dot.
        canvas.drawCircle(
          p,
          r,
          Paint()
            ..color = dot
            ..style = PaintingStyle.stroke
            ..strokeWidth = sc.strokeWidth(1.5),
        );
        canvas.drawCircle(p, r * 0.4, fill);
      } else {
        drawBandMarker(canvas, p, r, band, fill);
      }
    }
  }

  void _paintDrawing(Canvas canvas, FloorMapping m) {
    final Paint line = Paint()
      ..color = style.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.sc.strokeWidth(2);
    if (drawnPoints.length >= 2) {
      canvas.drawPath(_polyline(m, drawnPoints), line);
    }
    for (int i = 0; i < drawnPoints.length; i++) {
      final Offset o = m.toCanvas(drawnPoints[i]);
      canvas.drawCircle(
        o,
        style.sc.markerSize(5),
        Paint()..color = style.accent,
      );
      _label(
        canvas,
        '${i + 1}',
        o + Offset(0, -style.sc.markerSize(12)),
        style.labelStyle,
        background: style.halo,
      );
    }
  }

  @override
  bool shouldRepaint(SurveyFloorPainter old) =>
      old.result != result ||
      old.timeS != timeS ||
      old.shown != shown ||
      old.style != style ||
      old.drawing != drawing ||
      !listEquals(old.drawnPoints, drawnPoints);
}

// ── Channel strip ───────────────────────────────────────────────────────────

/// Every channel in the scan set as a cell, grouped by band; each radio's
/// current channel is filled lime and labeled with the radio.
class SurveyChannelStripPainter extends CustomPainter {
  SurveyChannelStripPainter({
    required this.result,
    required this.timeS,
    required this.shown,
    required this.style,
  });

  final SurveyWalkResult result;
  final double timeS;
  final int? shown;
  final SurveyPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final ScanSchedule? sch = result.schedule;
    final PresenterScale sc = style.sc;
    if (sch == null) {
      _label(
        canvas,
        'Active survey: the one radio stays on its AP\'s channel.',
        size.center(Offset.zero),
        style.labelStyle,
      );
      return;
    }
    final List<SurveyChannel> ch = sch.channels;
    final List<RadioNow> now = result.radiosAt(timeS);
    final Map<int, List<RadioNow>> on = <int, List<RadioNow>>{};
    for (final RadioNow r in now) {
      final int? c = r.channel;
      if (c != null) (on[c] ??= <RadioNow>[]).add(r);
    }
    // Band groups with a gap between them.
    final double gap = sc.markerSize(10);
    int bands = 1;
    for (int i = 1; i < ch.length; i++) {
      if (ch[i].band != ch[i - 1].band) bands++;
    }
    final double top = sc.paintFont(14) + 4;
    final double bottomLabel = sc.paintFont(14) + 4;
    final double cellH = math.max(
      12,
      size.height - top - bottomLabel - sc.markerSize(4),
    );
    final double w = (size.width - gap * (bands - 1)) / ch.length;
    final Paint border = Paint()
      ..color = style.axis
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(1);
    final Paint on_ = Paint()..color = style.accent;
    final Paint shownPaint = Paint()
      ..color = style.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(2);
    final TextStyle small = style.labelStyle;
    final List<(double, String)> nicLabels = <(double, String)>[];
    double x = 0;
    int bandStart = 0;
    double bandStartX = 0;
    void bandLabel(int end, double endX) {
      _label(
        canvas,
        ch[bandStart].band.label,
        Offset((bandStartX + endX) / 2, size.height - bottomLabel / 2),
        small,
      );
    }

    for (int i = 0; i < ch.length; i++) {
      if (i > 0 && ch[i].band != ch[i - 1].band) {
        bandLabel(i, x);
        x += gap;
        bandStart = i;
        bandStartX = x;
      }
      final Rect cell = Rect.fromLTWH(x + 0.5, top, w - 1, cellH);
      final int ri = result.indexOf(ch[i]);
      if (on.containsKey(ri)) {
        canvas.drawRect(cell, on_);
      }
      canvas.drawRect(cell, border);
      if (sch.isPriority && sch.isPriorityChannel(i)) {
        canvas.drawLine(
          Offset(cell.left + 1, cell.bottom + sc.markerSize(3)),
          Offset(cell.right - 1, cell.bottom + sc.markerSize(3)),
          Paint()
            ..color = style.primary
            ..strokeWidth = sc.strokeWidth(2),
        );
      }
      if (ri == shown) canvas.drawRect(cell.inflate(1.5), shownPaint);
      // Channel numbers only where they fit.
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: ch[i].shortLabel,
          style: small.copyWith(
            color: on.containsKey(ri) ? style.halo : style.secondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width <= w - 2) {
        tp.paint(
          canvas,
          Offset(cell.center.dx - tp.width / 2, cell.center.dy - tp.height / 2),
        );
      }
      final List<RadioNow>? rs = on[ri];
      if (rs != null) {
        for (final RadioNow r in rs) {
          nicLabels.add((cell.center.dx, 'NIC ${r.radio + 1}'));
        }
      }
      x += w;
    }
    bandLabel(ch.length, x);

    // NIC labels over their cells, pushed right so neighbors never overlap.
    nicLabels.sort(
      ((double, String) a, (double, String) b) => a.$1.compareTo(b.$1),
    );
    double nextFree = 0;
    for (final (double cx, String t) in nicLabels) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: t,
          style: small.copyWith(color: style.primary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      double left = cx - tp.width / 2;
      if (left < nextFree) left = nextFree;
      if (left + tp.width > size.width) left = size.width - tp.width;
      tp.paint(canvas, Offset(left, (top - tp.height) / 2));
      nextFree = left + tp.width + sc.markerSize(6);
    }
  }

  @override
  bool shouldRepaint(SurveyChannelStripPainter old) =>
      old.result != result ||
      old.timeS != timeS ||
      old.shown != shown ||
      old.style != style;
}

// ── Signal along the path ───────────────────────────────────────────────────

/// Level of every AP on the shown channel along the path: the log-distance
/// mean as a line, each sample (mean + fade) as a dot at its true position.
class SurveySignalPainter extends CustomPainter {
  SurveySignalPainter({
    required this.result,
    required this.timeS,
    required this.shown,
    required this.style,
    this.units = UnitSystem.metric,
  });

  /// Units for the distance-walked axis: 10 or 20 m, or 25 or 50 ft.
  final UnitSystem units;

  final SurveyWalkResult result;
  final double timeS;
  final int shown;
  final SurveyPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final SurveyWalkConfig cfg = result.config;
    final SurveyChannel ch = result.channels[shown];
    final List<int> aps = <int>[
      for (int a = 0; a < cfg.aps.length; a++)
        if (cfg.aps[a].channel == ch) a,
    ];
    final PresenterScale sc = style.sc;
    if (aps.isEmpty) {
      _label(
        canvas,
        'No AP on ch ${ch.shortLabel}. The scanner still spends its dwell '
        'here.',
        size.center(Offset.zero),
        style.labelStyle,
      );
      return;
    }
    final double length = result.plan.lengthM;
    const int n = 160;
    final List<List<double>> curves = <List<double>>[
      for (final int a in aps)
        <double>[
          for (int i = 0; i <= n; i++)
            meanDbm(cfg.aps[a], pointAlong(cfg.path, length * i / n)),
        ],
    ];
    double hi = -200;
    double lo = 0;
    for (final List<double> c in curves) {
      for (final double v in c) {
        hi = math.max(hi, v);
        lo = math.min(lo, v);
      }
    }
    hi = ((hi + 10) / 10).ceil() * 10.0;
    lo = ((lo - 20) / 10).floor() * 10.0;

    final double left = sc.paintFont(40);
    final double bottom = sc.paintFont(18);
    final Rect plot = Rect.fromLTRB(
      left,
      6,
      size.width - 8,
      size.height - bottom,
    );
    double px(double s) => plot.left + plot.width * (s / length);
    double py(double dbm) =>
        plot.top + plot.height * ((hi - dbm) / (hi - lo)).clamp(0.0, 1.0);

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = sc.strokeWidth(1);
    for (double v = lo; v <= hi + 0.1; v += 10) {
      canvas.drawLine(
        Offset(plot.left, py(v)),
        Offset(plot.right, py(v)),
        grid,
      );
      _label(
        canvas,
        v.toStringAsFixed(0),
        Offset(plot.left - 4, py(v)),
        style.labelStyle,
        align: Alignment.centerRight,
      );
    }
    final LengthFormat f = LengthFormat(units);
    final double lenShown = f.distValue(length);
    final double stepShown = units.isMetric
        ? (length > 80 ? 20 : 10)
        : (lenShown > 260 ? 50 : 25);
    for (double v = 0; v <= lenShown + 0.1; v += stepShown) {
      final double s = f.distToMetres(v);
      _label(
        canvas,
        '${v.toStringAsFixed(0)} ${f.distUnit}',
        Offset(px(s), plot.bottom + 2),
        style.labelStyle,
        align: Alignment.topCenter,
      );
    }
    canvas.drawRect(
      plot,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1),
    );

    canvas.save();
    canvas.clipRect(plot);
    for (int k = 0; k < aps.length; k++) {
      final Path p = Path();
      for (int i = 0; i <= n; i++) {
        final Offset o = Offset(px(length * i / n), py(curves[k][i]));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(
        p,
        Paint()
          ..color = style.ap(aps[k])
          ..style = PaintingStyle.stroke
          ..strokeWidth = sc.strokeWidth(2),
      );
    }
    final double r = sc.markerSize(3.2);
    for (final SurveySample s in result.samples) {
      if (s.measuredAtS > timeS) break;
      if (s.channel != shown) continue;
      for (final HeardAp h in s.heard) {
        final Offset o = Offset(px(s.trueS), py(h.rssiDbm));
        canvas.drawCircle(
          o,
          r + sc.strokeWidth(1),
          Paint()..color = style.halo,
        );
        canvas.drawCircle(o, r, Paint()..color = style.ap(h.ap));
      }
    }
    final double x = px(result.plan.sAt(timeS));
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = style.primary
        ..strokeWidth = sc.strokeWidth(1.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SurveySignalPainter old) =>
      old.result != result ||
      old.units != units ||
      old.timeS != timeS ||
      old.shown != shown ||
      old.style != style;
}
