// Painter for the Wi-Fi Classroom Predict, Then Measure tool.
//
// THE MAP is drawn on the dark coverage viewport in both themes, exactly as
// Heat Map Builder's and Room Propagation's are (lib/theme/
// app_coverage_ramp.dart): cells are flat fills of one GL-003 §8.22
// brand-green ramp stop, always with a legend. Heat Map Builder's signal and
// error edges are reused, so stops 0 to 6 only: the pale top stop never sits
// next to the white that means NO DATA (Keith's Rule 6). No-data cells on the
// Measured and Difference maps are white with a border-strong hatch, so they
// read as "no data" by pattern as well as by color (SC 1.4.1).
//
// THE DIFFERENCE MAP shows the size of measured minus predicted on the same
// ramp; the sign is in the wall badges and the readouts. GL-003 has no
// diverging ramp, so none is invented.
//
// Walls are cased lines with a label badge: name and design loss, then
// "untested" or "tested: X dB", then the true loss after the reveal. The
// selected wall is drawn thicker in the viewport's text color. The walk is a
// lime line with lime sample dots (lime marks the measured quantity). The AP
// on a stick is a cased square. Nothing animates.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../services/wifi_lab/predict_measure_engine.dart';
import '../../../theme/app_coverage_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter.dart';
import 'heat_map_builder_painters.dart';
import 'predict_measure_controller.dart';

/// A snapshot of what the map draws, so shouldRepaint compares cheaply.
class PmMapPaintData {
  const PmMapPaintData({
    required this.model,
    required this.maps,
    required this.survey,
    required this.legs,
    required this.view,
    required this.revealed,
    required this.selectedWall,
    required this.updatedWalls,
    required this.revision,
  });

  final PmModel model;
  final PmMaps maps;
  final PmSurvey survey;
  final List<List<HmPoint>> legs;
  final PmMapView view;
  final bool revealed;
  final int selectedWall;
  final Set<int> updatedWalls;

  /// Bumped by the stage on every controller change.
  final int revision;
}

/// The wall badge text: name and design loss; tested or untested; the true
/// loss after the reveal.
String pmWallBadge(PmMapPaintData d, int i) {
  final PmWall w = d.model.walls[i];
  final PmWallTest? t = d.survey.tests[i];
  final StringBuffer b = StringBuffer(
    '${PredictMeasureController.wallName(i)} '
    '${fmtM(w.predictedLossDb)} dB'
    '${d.updatedWalls.contains(i) ? ' (updated)' : ''}\n'
    '${t == null ? 'untested' : 'tested: ${t.estimateDb.toStringAsFixed(1)} dB'}',
  );
  if (d.revealed) b.write('\ntrue: ${fmtM(w.trueLossDb)} dB');
  return b.toString();
}

class PmMapPainter extends CustomPainter {
  PmMapPainter({required this.data, required this.sc, required this.font});

  final PmMapPaintData data;
  final PresenterScale sc;

  /// The app's label face (painted text does not inherit the theme).
  final TextStyle font;

  static const Color _viewport = AppCoverageRamp.viewport;
  static const Color _casing = AppCoverageRamp.casing;
  static const Color _text = AppCoverageRamp.viewportText;
  static const Color _muted = AppCoverageRamp.viewportMuted;
  static const Color _lime = AppColors.primary;

  Size _size = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    canvas.drawRect(Offset.zero & size, Paint()..color = _viewport);
    final PmModel mo = data.model;
    final HmFloorMapping m = HmFloorMapping(size, mo.widthM, mo.depthM);
    canvas.save();
    canvas.clipRect(m.floorRect);
    _cells(canvas, m);
    canvas.restore();
    canvas.drawRect(
      m.floorRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1)
        ..color = _muted,
    );
    _walls(canvas, m);
    _walk(canvas, m);
    _ap(canvas, m);
    _wallLabels(canvas, m);
  }

  bool get _hasNoData =>
      data.view == PmMapView.measured || data.view == PmMapView.difference;

  Color _cellColor(int i) {
    final PmMaps maps = data.maps;
    switch (data.view) {
      case PmMapView.predicted:
        return AppCoverageRamp.stops[hmSignalStop(maps.predicted[i])];
      case PmMapView.truth:
        return AppCoverageRamp.stops[hmSignalStop(maps.truth[i])];
      case PmMapView.measured:
        final double v = maps.measured[i];
        return v.isNaN
            ? kHmNoDataColor
            : AppCoverageRamp.stops[hmSignalStop(v)];
      case PmMapView.difference:
        final double v = maps.difference[i];
        return v.isNaN
            ? kHmNoDataColor
            : AppCoverageRamp.stops[hmErrorStop(v)];
    }
  }

  void _cells(Canvas canvas, HmFloorMapping m) {
    final PmMaps maps = data.maps;
    final Paint paint = Paint()..isAntiAlias = false;
    final double cell = maps.cellM * m.scale;
    final Path noData = Path();
    for (int r = 0; r < maps.rows; r++) {
      int start = 0;
      Color run = _cellColor(r * maps.cols);
      for (int c = 1; c <= maps.cols; c++) {
        final Color? next = c < maps.cols
            ? _cellColor(r * maps.cols + c)
            : null;
        if (next == run) continue;
        final Rect rect = Rect.fromLTWH(
          m.origin.dx + start * cell,
          m.origin.dy + r * cell,
          (c - start) * cell,
          cell,
        );
        paint.color = run;
        canvas.drawRect(rect.inflate(0.25), paint);
        if (run == kHmNoDataColor && _hasNoData) noData.addRect(rect);
        start = c;
        if (next != null) run = next;
      }
    }
    if (!_hasNoData) return;
    canvas.save();
    canvas.clipPath(noData);
    final Paint hatch = Paint()
      ..color = kHmNoDataHatch
      ..strokeWidth = sc.strokeWidth(1);
    final double step = sc.markerSize(9);
    final Rect fr = m.floorRect;
    for (double x = fr.left - fr.height; x < fr.right; x += step) {
      canvas.drawLine(
        Offset(x, fr.bottom),
        Offset(x + fr.height, fr.top),
        hatch,
      );
    }
    canvas.restore();
  }

  void _cased(Canvas canvas, Offset a, Offset b, Color color, double w) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = _casing
        ..strokeWidth = w + sc.strokeWidth(3)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
  }

  void _walls(Canvas canvas, HmFloorMapping m) {
    final List<PmWall> walls = data.model.walls;
    for (int i = 0; i < walls.length; i++) {
      if (i == data.selectedWall) continue;
      _cased(
        canvas,
        m.toPx(walls[i].a),
        m.toPx(walls[i].b),
        _muted,
        sc.strokeWidth(3),
      );
    }
    final PmWall s = walls[data.selectedWall];
    _cased(canvas, m.toPx(s.a), m.toPx(s.b), _text, sc.strokeWidth(5));
  }

  void _walk(Canvas canvas, HmFloorMapping m) {
    for (final List<HmPoint> leg in data.legs) {
      if (leg.length < 2) continue;
      final Path p = Path()..moveTo(m.toPx(leg.first).dx, m.toPx(leg.first).dy);
      for (final HmPoint q in leg.skip(1)) {
        final Offset o = m.toPx(q);
        p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _casing
          ..strokeWidth = sc.strokeWidth(4.5)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _lime
          ..strokeWidth = sc.strokeWidth(1.5)
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    final double r = sc.markerSize(data.survey.samples.length > 200 ? 2.5 : 3.5);
    final Paint casing = Paint()..color = _casing;
    final Paint core = Paint()..color = _lime;
    for (final HmSample s in data.survey.samples) {
      final Offset p = m.toPx(s.p);
      canvas.drawCircle(p, r + sc.markerSize(1.5), casing);
      canvas.drawCircle(p, r, core);
    }
  }

  void _ap(Canvas canvas, HmFloorMapping m) {
    final double r = sc.markerSize(7);
    final Offset p = m.toPx(data.model.ap);
    final Rect sq = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
    canvas.drawRect(sq.inflate(sc.markerSize(2)), Paint()..color = _casing);
    canvas.drawRect(sq, Paint()..color = _text);
    _label(canvas, 'AP on a stick', p + Offset(0, r + sc.markerSize(11)));
  }

  /// Wall badges last, so no line or marker covers them. Each is tried
  /// beside its wall, away from the AP first, at the middle and then toward
  /// either end, and takes the first spot that no earlier badge covers.
  void _wallLabels(Canvas canvas, HmFloorMapping m) {
    final List<PmWall> walls = data.model.walls;
    final Offset ap = m.toPx(data.model.ap);
    final List<Rect> placed = <Rect>[
      // The AP's own label.
      Rect.fromCenter(
        center: ap + Offset(0, sc.markerSize(18)),
        width: sc.markerSize(90),
        height: sc.markerSize(18),
      ),
    ];
    for (int i = 0; i < walls.length; i++) {
      final PmWall w = walls[i];
      final Offset a = m.toPx(w.a);
      final Offset b = m.toPx(w.b);
      final Offset mid = Offset.lerp(a, b, 0.5)!;
      final Offset along = b - a;
      final double len = along.distance;
      Offset n = len == 0 ? Offset.zero : Offset(-along.dy, along.dx) / len;
      if ((ap - mid).dx * n.dx + (ap - mid).dy * n.dy > 0) n = -n;
      final TextPainter tp = _painter(
        pmWallBadge(data, i),
        i == data.selectedWall ? _lime : _text,
      );
      Rect? best;
      double bestCover = double.infinity;
      search:
      for (final double far in const <double>[1, 2.2]) {
        for (final double side in <double>[1, -1]) {
          for (final double t in const <double>[0.5, 0.3, 0.7, 0.15, 0.85]) {
            final Offset base = Offset.lerp(a, b, t)!;
            final double gap =
                sc.markerSize(6) * far +
                far * (n.dx.abs() * tp.width + n.dy.abs() * tp.height) / 2;
            final Rect r = _fit(
              Rect.fromCenter(
                center: base + n * side * gap,
                width: tp.width,
                height: tp.height,
              ),
            );
            double cover = 0;
            for (final Rect p in placed) {
              final Rect x = p.intersect(r.inflate(sc.markerSize(2)));
              if (x.width > 0 && x.height > 0) cover += x.width * x.height;
            }
            if (cover < bestCover) {
              best = r;
              bestCover = cover;
            }
            if (cover == 0) break search;
          }
        }
      }
      placed.add(best!);
      _drawBadge(canvas, tp, best.topLeft);
    }
  }

  TextPainter _painter(String text, Color color) => TextPainter(
    text: TextSpan(
      text: text,
      style: font.copyWith(
        color: color,
        fontSize: sc.paintFont(AppTextSize.caption - 1),
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();

  /// [r] moved inside the painted box.
  Rect _fit(Rect r) {
    final double pad = sc.markerSize(3);
    return Rect.fromLTWH(
      r.left.clamp(pad, math.max(pad, _size.width - r.width - pad)),
      r.top.clamp(pad, math.max(pad, _size.height - r.height - pad)),
      r.width,
      r.height,
    );
  }

  void _drawBadge(Canvas canvas, TextPainter tp, Offset o) {
    final Rect bg = (o & tp.size).inflate(sc.markerSize(2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(3)),
      Paint()..color = _casing.withValues(alpha: 0.85),
    );
    tp.paint(canvas, o);
  }

  void _label(Canvas canvas, String text, Offset at, {Color color = _text}) {
    final TextPainter tp = _painter(text, color);
    final Rect r = _fit(
      Rect.fromCenter(center: at, width: tp.width, height: tp.height),
    );
    _drawBadge(canvas, tp, r.topLeft);
  }

  @override
  bool shouldRepaint(PmMapPainter old) =>
      old.data.revision != data.revision || old.sc != sc || old.font != font;
}
