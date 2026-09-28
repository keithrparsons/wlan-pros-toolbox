// Painters for the Wi-Fi Classroom Heat Map Builder (heat-map-builder).
//
// THE MAP is drawn on the dark coverage viewport in both themes, exactly as
// Room Propagation's is (lib/theme/app_coverage_ramp.dart): cells are flat
// fills of one GL-003 §8.22 brand-green ramp stop, the default ramp for
// non-analyzer heat maps, always with a dBm legend. Only stops 0 to 6 are
// used, so the pale top stop (#EEF7CF) never sits next to the white that
// means NO DATA (Keith's Rule 6: white is no data, not no coverage). No-data
// cells are white (AppColors.neutral0) with a border-strong hatch, so they
// read as "no data" by pattern as well as by color (SC 1.4.1).
//
// THE ERROR MAP uses the same ramp for the size of the error,
// |estimate - truth| in dB, with its own legend; the sign is in the readouts
// and the cell inspector. GL-003 has no diverging ramp, so none is invented
// here.
//
// Samples are lime dots (lime marks the measured quantity) with a dark
// casing, so they read on every stop. APs, walls and labels carry the same
// casing. A hidden wall is not drawn until it is revealed; then it is drawn
// dashed, labeled as the wall no one measured across. Nothing animates.
//
// The spacing plot and the worked-example diagram sit on theme surfaces and
// take theme colors; series are told apart by dash pattern, marker shape and
// a worded legend, never by color alone.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/heat_map_builder_engine.dart';
import '../../../theme/app_coverage_ramp.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter.dart';

/// Signal legend: lower edges of stops 1 to 6, dBm (Room Propagation's
/// edges without the top stop).
final List<double> kHmSignalEdgesDbm = AppCoverageRamp.powerEdgesDbm.sublist(
  0,
  6,
);

/// Error legend: lower edges of stops 1 to 6 for |estimate - truth|, dB.
const List<double> kHmErrorEdgesDb = <double>[1, 2, 4, 7, 10, 15];

/// White: no data.
const Color kHmNoDataColor = AppColors.neutral0;

/// The hatch over no-data cells (3.9:1 on white).
const Color kHmNoDataHatch = AppColors.borderStrong;

/// The ramp stop for a signal value.
int hmSignalStop(double dbm) => AppCoverageRamp.stopFor(dbm, kHmSignalEdgesDbm);

/// The ramp stop for an error.
int hmErrorStop(double errDb) =>
    AppCoverageRamp.stopFor(errDb.abs(), kHmErrorEdgesDb);

/// What the map painter shows.
enum HmPaintView { estimate, truth, error }

/// Meters to pixels for the floor, centered in the box.
class HmFloorMapping {
  HmFloorMapping(this.size, this.widthM, this.depthM)
    : scale = math.min(size.width / widthM, size.height / depthM),
      origin = Offset(
        (size.width -
                widthM * math.min(size.width / widthM, size.height / depthM)) /
            2,
        (size.height -
                depthM * math.min(size.width / widthM, size.height / depthM)) /
            2,
      );

  final Size size;
  final double widthM;
  final double depthM;

  /// Pixels per meter.
  final double scale;

  /// Pixel position of the floor's top-left corner.
  final Offset origin;

  Offset toPx(HmPoint p) => origin + Offset(p.x * scale, p.y * scale);

  HmPoint toFloor(Offset o) =>
      (x: (o.dx - origin.dx) / scale, y: (o.dy - origin.dy) / scale);

  Rect get floorRect => origin & Size(widthM * scale, depthM * scale);
}

/// A snapshot of what the map draws, so shouldRepaint compares cheaply.
class HmMapPaintData {
  const HmMapPaintData({
    required this.floor,
    required this.map,
    required this.samples,
    required this.view,
    required this.wallRevealed,
    required this.inspectedCell,
    required this.inspection,
    required this.revision,
  });

  final HmFloor floor;
  final HmMap map;
  final List<HmSample> samples;
  final HmPaintView view;
  final bool wallRevealed;
  final HmPoint? inspectedCell;
  final HmCellEstimate? inspection;

  /// Bumped by the controller's owner on every change.
  final int revision;
}

class HmMapPainter extends CustomPainter {
  HmMapPainter({required this.data, required this.sc, required this.font});

  final HmMapPaintData data;
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
    final HmFloor f = data.floor;
    final HmFloorMapping m = HmFloorMapping(size, f.widthM, f.depthM);
    canvas.save();
    canvas.clipRect(m.floorRect);
    _cells(canvas, m);
    canvas.restore();
    // Floor outline.
    canvas.drawRect(
      m.floorRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1)
        ..color = _muted,
    );
    _walls(canvas, m);
    _contributions(canvas, m);
    _samples(canvas, m);
    _aps(canvas, m);
    _inspected(canvas, m);
    _wallLabels(canvas, m);
  }

  Color _cellColor(int c, int r) {
    final HmMap map = data.map;
    switch (data.view) {
      case HmPaintView.truth:
        return AppCoverageRamp.stops[hmSignalStop(map.truthAt(c, r))];
      case HmPaintView.estimate:
        final double v = map.estimateAt(c, r);
        return v.isNaN
            ? kHmNoDataColor
            : AppCoverageRamp.stops[hmSignalStop(v)];
      case HmPaintView.error:
        final double e = map.errorAt(c, r);
        return e.isNaN ? kHmNoDataColor : AppCoverageRamp.stops[hmErrorStop(e)];
    }
  }

  void _cells(Canvas canvas, HmFloorMapping m) {
    final HmMap map = data.map;
    final Paint paint = Paint()..isAntiAlias = false;
    final double cell = map.cellM * m.scale;
    final Path noData = Path();
    for (int r = 0; r < map.rows; r++) {
      int start = 0;
      Color run = _cellColor(0, r);
      for (int c = 1; c <= map.cols; c++) {
        final Color? next = c < map.cols ? _cellColor(c, r) : null;
        if (next == run) continue;
        final Rect rect = Rect.fromLTWH(
          m.origin.dx + start * cell,
          m.origin.dy + r * cell,
          (c - start) * cell,
          cell,
        );
        paint.color = run;
        canvas.drawRect(rect.inflate(0.25), paint);
        if (run == kHmNoDataColor && data.view != HmPaintView.truth) {
          noData.addRect(rect);
        }
        start = c;
        if (next != null) run = next;
      }
    }
    // Hatch the no-data area so white never rests on color alone.
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

  void _dashed(Canvas canvas, Offset a, Offset b, Color color, double w) {
    final double len = (b - a).distance;
    final Offset dir = (b - a) / len;
    final double dash = sc.markerSize(10);
    final double gap = sc.markerSize(6);
    for (double s = 0; s < len; s += dash + gap) {
      final Offset p = a + dir * s;
      final Offset q = a + dir * math.min(len, s + dash);
      _cased(canvas, p, q, color, w);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    Color color = _text,
    bool center = true,
    double px = AppTextSize.caption - 1,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: font.copyWith(
          color: color,
          fontSize: sc.paintFont(px),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Offset raw = center
        ? at - Offset(tp.width / 2, tp.height / 2)
        : at - Offset(0, tp.height / 2);
    // Keep every label inside the painted box.
    final double pad = sc.markerSize(3);
    final Offset o = Offset(
      raw.dx.clamp(pad, math.max(pad, _size.width - tp.width - pad)),
      raw.dy.clamp(pad, math.max(pad, _size.height - tp.height - pad)),
    );
    final Rect bg = (o & tp.size).inflate(sc.markerSize(2));
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(3)),
      Paint()..color = _casing.withValues(alpha: 0.85),
    );
    tp.paint(canvas, o);
  }

  void _walls(Canvas canvas, HmFloorMapping m) {
    for (final HmWall w in data.floor.walls) {
      if (w.hidden && !data.wallRevealed) continue;
      final Offset a = m.toPx(w.a);
      final Offset b = m.toPx(w.b);
      if (w.hidden) {
        _dashed(canvas, a, b, _text, sc.strokeWidth(3));
      } else {
        _cased(canvas, a, b, _muted, sc.strokeWidth(3));
      }
    }
  }

  /// Wall labels last, so no line or marker covers them.
  void _wallLabels(Canvas canvas, HmFloorMapping m) {
    for (final HmWall w in data.floor.walls) {
      if (w.hidden && !data.wallRevealed) continue;
      // A hidden wall is labeled near its far end, away from the middle of
      // the floor where the inspector's lines usually run.
      final Offset at = Offset.lerp(
        m.toPx(w.a),
        m.toPx(w.b),
        w.hidden ? 0.8 : 0.5,
      )!;
      _label(
        canvas,
        w.hidden
            ? 'Hidden wall, ${w.lossDb.toStringAsFixed(0)} dB'
            : '${w.lossDb.toStringAsFixed(0)} dB',
        at,
      );
    }
  }

  void _samples(Canvas canvas, HmFloorMapping m) {
    final double r = sc.markerSize(
      data.samples.length > 400 ? 2.2 : (data.samples.length > 120 ? 3 : 4),
    );
    final Paint casing = Paint()..color = _casing;
    final Paint core = Paint()..color = _lime;
    for (final HmSample s in data.samples) {
      final Offset p = m.toPx(s.p);
      canvas.drawCircle(p, r + sc.markerSize(1.5), casing);
      canvas.drawCircle(p, r, core);
    }
  }

  void _aps(Canvas canvas, HmFloorMapping m) {
    final double r = sc.markerSize(7);
    for (int i = 0; i < data.floor.aps.length; i++) {
      final Offset p = m.toPx(data.floor.aps[i]);
      final Rect sq = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
      canvas.drawRect(sq.inflate(sc.markerSize(2)), Paint()..color = _casing);
      canvas.drawRect(sq, Paint()..color = _text);
      _label(canvas, 'AP ${i + 1}', p + Offset(0, r + sc.markerSize(10)));
    }
  }

  void _contributions(Canvas canvas, HmFloorMapping m) {
    final HmPoint? q = data.inspectedCell;
    final HmCellEstimate? e = data.inspection;
    if (q == null || e == null) return;
    final Offset c = m.toPx(q);
    for (final HmContribution k in e.contributions) {
      final Offset s = m.toPx(data.samples[k.sampleIndex].p);
      _cased(canvas, c, s, _lime, sc.strokeWidth(0.75 + 6 * k.weightShare));
    }
    // Label the three largest shares near their sample end, where the lines
    // have spread apart; skip shares under 10%.
    for (final HmContribution k in e.contributions.take(3)) {
      if (k.weightShare < 0.1) continue;
      final Offset s = m.toPx(data.samples[k.sampleIndex].p);
      _label(
        canvas,
        '${(k.weightShare * 100).toStringAsFixed(0)}%',
        Offset.lerp(c, s, 0.72)!,
      );
    }
  }

  void _inspected(Canvas canvas, HmFloorMapping m) {
    final HmPoint? q = data.inspectedCell;
    if (q == null) return;
    final double half = math.max(
      data.map.cellM * m.scale / 2,
      sc.markerSize(5),
    );
    final Rect r = Rect.fromCenter(
      center: m.toPx(q),
      width: half * 2,
      height: half * 2,
    );
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _casing
        ..strokeWidth = sc.strokeWidth(5),
    );
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = _text
        ..strokeWidth = sc.strokeWidth(2),
    );
  }

  @override
  bool shouldRepaint(HmMapPainter old) =>
      old.data.revision != data.revision || old.sc != sc || old.font != font;
}

// ── Spacing experiment plot ─────────────────────────────────────────────────

/// Dash pattern per series index: solid, dashed, dotted.
List<double>? hmSeriesDash(int i) => switch (i) {
  0 => null,
  1 => const <double>[8, 5],
  _ => const <double>[2, 4],
};

class HmSpacingPlotStyle {
  const HmSpacingPlotStyle({
    required this.sc,
    required this.series,
    required this.axis,
    required this.grid,
    required this.label,
    required this.font,
  });

  final PresenterScale sc;

  /// The app's label face (painted text does not inherit the theme).
  final TextStyle font;

  /// One color per series; the dash and marker also differ.
  final List<Color> series;
  final Color axis;
  final Color grid;
  final Color label;
}

class HmSpacingPainter extends CustomPainter {
  HmSpacingPainter({
    required this.series,
    required this.style,
    this.spacingsShown = kHmExperimentSpacings,
    this.axisMax = 10,
    this.unit = 'm',
  });

  /// Grid spacings in the unit on screen, the x of each point.
  final List<double> spacingsShown;

  /// Right end of the x axis: 10 m, or 30 ft.
  final double axisMax;

  /// "m" or "ft", for the axis title.
  final String unit;

  final List<HmSpacingSeries> series;
  final HmSpacingPlotStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale sc = style.sc;
    final double font = sc.paintFont(AppTextSize.caption - 2);
    final double left = font * 3.2;
    final double bottom = font * 2.6;
    final Rect plot = Rect.fromLTRB(
      left,
      font * 2.2,
      size.width - font * 0.8,
      size.height - bottom,
    );
    double maxY = 0;
    for (final HmSpacingSeries s in series) {
      for (final double v in s.rmseDb) {
        maxY = math.max(maxY, v);
      }
    }
    final double yTop = math.max(2, (maxY / 2).ceil() * 2.0);
    Offset pt(double spacing, double rmse) => Offset(
      plot.left + spacing / axisMax * plot.width,
      plot.bottom - rmse / yTop * plot.height,
    );
    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = sc.strokeWidth(1);
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = sc.strokeWidth(1.2);
    void text(String s, Offset at, {bool right = false, bool below = false}) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: s,
          style: style.font.copyWith(color: style.label, fontSize: font),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          right ? at.dx - tp.width : at.dx - tp.width / 2,
          below ? at.dy : at.dy - tp.height / 2,
        ),
      );
    }

    final int yStep = yTop <= 6 ? 1 : (yTop <= 12 ? 2 : 4);
    for (int y = 0; y <= yTop; y += yStep) {
      final Offset a = pt(0, y.toDouble());
      canvas.drawLine(a, Offset(plot.right, a.dy), grid);
      text('$y', Offset(plot.left - font * 0.4, a.dy), right: true);
    }
    for (final double x in spacingsShown) {
      final Offset a = pt(x, 0);
      canvas.drawLine(a, a + Offset(0, font * 0.3), axis);
      text(x.toStringAsFixed(0), a + Offset(0, font * 0.4), below: true);
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axis);
    text(
      'Grid spacing, $unit',
      Offset(plot.center.dx, plot.bottom + font * 1.5),
      below: true,
    );
    text('RMSE, dB', Offset(plot.left + font * 1.6, font * 0.7));

    for (int i = 0; i < series.length; i++) {
      final Color c = style.series[i % style.series.length];
      final Paint line = Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(2);
      final List<Offset> pts = <Offset>[
        for (int j = 0; j < spacingsShown.length; j++)
          pt(spacingsShown[j], series[i].rmseDb[j]),
      ];
      final List<double>? dash = hmSeriesDash(i);
      for (int j = 1; j < pts.length; j++) {
        _dashLine(canvas, pts[j - 1], pts[j], line, dash);
      }
      final Paint dot = Paint()..color = c;
      final double r = sc.markerSize(3.5);
      for (final Offset p in pts) {
        switch (i) {
          case 0:
            canvas.drawCircle(p, r, dot);
          case 1:
            canvas.drawRect(
              Rect.fromCenter(center: p, width: r * 2, height: r * 2),
              dot,
            );
          default:
            canvas.drawPath(
              Path()
                ..moveTo(p.dx, p.dy - r * 1.2)
                ..lineTo(p.dx + r * 1.2, p.dy + r)
                ..lineTo(p.dx - r * 1.2, p.dy + r)
                ..close(),
              dot,
            );
        }
      }
    }
  }

  void _dashLine(Canvas c, Offset a, Offset b, Paint p, List<double>? dash) {
    if (dash == null) {
      c.drawLine(a, b, p);
      return;
    }
    final double len = (b - a).distance;
    if (len == 0) return;
    final Offset dir = (b - a) / len;
    final double on = style.sc.markerSize(dash[0]);
    final double off = style.sc.markerSize(dash[1]);
    for (double s = 0; s < len; s += on + off) {
      c.drawLine(a + dir * s, a + dir * math.min(len, s + on), p);
    }
  }

  @override
  bool shouldRepaint(HmSpacingPainter old) =>
      !identical(old.series, series) ||
      old.style.sc != style.sc ||
      old.unit != unit;
}

/// A legend key for series [index]: its dash pattern and marker shape.
class HmSeriesKeyPainter extends CustomPainter {
  HmSeriesKeyPainter({required this.index, required this.color});

  final int index;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 2;
    final double y = size.height / 2;
    final List<double>? dash = hmSeriesDash(index);
    if (dash == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    } else {
      for (double x = 0; x < size.width; x += dash[0] + dash[1]) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(size.width, x + dash[0]), y),
          line,
        );
      }
    }
    final Offset c = Offset(size.width / 2, y);
    final Paint dot = Paint()..color = color;
    const double r = 4;
    switch (index) {
      case 0:
        canvas.drawCircle(c, r, dot);
      case 1:
        canvas.drawRect(
          Rect.fromCenter(center: c, width: r * 2, height: r * 2),
          dot,
        );
      default:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r * 1.2)
            ..lineTo(c.dx + r * 1.2, c.dy + r)
            ..lineTo(c.dx - r * 1.2, c.dy + r)
            ..close(),
          dot,
        );
    }
  }

  @override
  bool shouldRepaint(HmSeriesKeyPainter old) =>
      old.index != index || old.color != color;
}

// ── Worked example diagram ──────────────────────────────────────────────────

class HmWorkedExamplePainter extends CustomPainter {
  HmWorkedExamplePainter({
    required this.shares,
    required this.line,
    required this.cell,
    required this.sample,
    required this.label,
    required this.sc,
    required this.font,
    this.distancesShown = HmWorkedExample.distancesM,
    this.unitLabel = 'm',
  });

  /// The app's label face (painted text does not inherit the theme).
  final TextStyle font;

  /// The three distances as shown (2, 4, 6 m; or 5, 10, 15 ft).
  final List<double> distancesShown;
  final String unitLabel;

  /// Normalized weight of each of the three samples.
  final List<double> shares;
  final Color line;
  final Color cell;
  final Color sample;
  final Color label;
  final PresenterScale sc;

  @override
  void paint(Canvas canvas, Size size) {
    final double px = sc.paintFont(AppTextSize.caption - 2);
    // The cell at the left; the samples at 2, 4 and 6 m to its right, fanned
    // out so their lines do not overlap.
    final Offset c = Offset(px * 1.2, size.height / 2);
    // Fit both ways: the widest reach is 6 m along x, the tallest is the
    // 6 m sample at 0.5 rad (6 x sin 0.5 = 2.88 units) below the center.
    final double unit = math.min(
      (size.width - c.dx - px * 9) / 6,
      (size.height / 2 - px) / 2.88,
    );
    const List<double> angles = <double>[-0.55, 0.05, 0.5];
    for (int i = 0; i < 3; i++) {
      // Line length keeps the metric proportions; the label is on screen.
      final double d = HmWorkedExample.distancesM[i];
      final Offset s =
          c + Offset(math.cos(angles[i]), math.sin(angles[i])) * (d * unit);
      canvas.drawLine(
        c,
        s,
        Paint()
          ..color = line
          ..strokeCap = StrokeCap.round
          ..strokeWidth = sc.strokeWidth(0.75 + 7 * shares[i]),
      );
      canvas.drawCircle(s, sc.markerSize(4.5), Paint()..color = sample);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text:
              '${HmWorkedExample.valuesDbm[i].toStringAsFixed(0)} dBm, '
              '${distancesShown[i].toStringAsFixed(0)} $unitLabel',
          style: font.copyWith(color: label, fontSize: px),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: px * 8.5);
      tp.paint(canvas, s + Offset(sc.markerSize(7), -tp.height / 2));
    }
    final double h = sc.markerSize(6);
    canvas.drawRect(
      Rect.fromCenter(center: c, width: h * 2, height: h * 2),
      Paint()..color = cell,
    );
  }

  @override
  bool shouldRepaint(HmWorkedExamplePainter old) =>
      old.shares[0] != shares[0] ||
      old.shares[1] != shares[1] ||
      old.shares[2] != shares[2] ||
      old.line != line ||
      old.label != label ||
      old.font != font ||
      old.sc != sc;
}
