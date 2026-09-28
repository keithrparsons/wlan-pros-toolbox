// Painter for How to Measure Wall Attenuation (measure-wall).
//
// A side view: the RF source on a stand at the left, the wall, the floor, a
// person holding a laptop at the reading spot on the side they are on, and an
// open ring on the floor at the other side's spot. Above them, one wave from
// the source across the room.
//
// THE WAVE (Wi-Fi Classroom standing rule, Keith 2026-09-25): its height is
// the level in dB above the noise floor, falling steeply near the source (the
// free-space curve) and dropping through the wall. Its drawn wavelength is the
// same everywhere, in front of, inside and behind the wall: loss changes a
// wave's height, never its spacing. The thin line over the crests is the
// level itself.
//
// The wave's height is on a zoomed dB scale: full height at the level next to
// the source, zero 12 dB under the lowest level in view (never below the
// noise floor). At each reading spot a long tick marks the average of that
// side's series; the readings themselves are drawn in the readouts, on a
// scale fine enough to see the fading.
//
// MwStageGeometry is the one mapping between metres and pixels, shared with
// the stage's drag handler so a touch and a drawn position never disagree.
// The wall is drawn at least [MwStageGeometry.minWallPx] wide so a 1 cm wall
// is visible; the metres on each side keep one scale.
//
// THEME: colors arrive from context.colors through MwStageStyle. ASCII copy,
// no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/presenter/presenter_mode.dart';
import 'measure_wall_controller.dart';
import 'measure_wall_format.dart';

/// How much of the room the stage shows. Held by the stage during a drag so
/// the scale does not change under the finger.
@immutable
class MwView {
  const MwView({required this.nearSpanM, required this.farSpanM});

  /// Metres shown in front of the wall, from the left edge to the near face.
  final double nearSpanM;

  /// Metres shown behind the wall.
  final double farSpanM;

  static const List<double> _near = <double>[
    1,
    1.5,
    2,
    3,
    4,
    5,
    6,
    8,
    10,
    12,
    14,
    18,
  ];
  static const List<double> _far = <double>[0.5, 1, 1.5, 2, 3, 4, 5, 6];

  static double _pick(List<double> list, double need) {
    for (final double v in list) {
      if (v >= need) return v;
    }
    return list.last;
  }

  /// A view that fits the source, both spots and some room on either side.
  factory MwView.forConfig(MwConfig c) {
    final double near = _pick(_near, c.sourceToWallM * 1.1 + 0.1);
    final double far = _pick(
      _far,
      math.max(c.farGapM * 1.15 + 0.2, near * 0.3),
    );
    return MwView(nearSpanM: near, farSpanM: far);
  }

  @override
  bool operator ==(Object other) =>
      other is MwView &&
      other.nearSpanM == nearSpanM &&
      other.farSpanM == farSpanM;

  @override
  int get hashCode => Object.hash(nearSpanM, farSpanM);
}

/// Metres to pixels along the room, and the vertical bands.
@immutable
class MwStageGeometry {
  MwStageGeometry(this.size, this.config, this.view, this.scale) {
    final double usable = math.max(1, size.width - 2 * pad);
    final double t = config.thicknessM;
    final double k0 = usable / (view.nearSpanM + view.farSpanM + t);
    if (t * k0 >= minWallPx * scale.marker) {
      pxPerM = k0;
      wallPx = t * k0;
    } else {
      wallPx = minWallPx * scale.marker;
      pxPerM = math.max(
        0.01,
        (usable - wallPx) / (view.nearSpanM + view.farSpanM),
      );
    }
    wallLeft = pad + view.nearSpanM * pxPerM;
  }

  final Size size;
  final MwConfig config;
  final MwView view;
  final PresenterScale scale;

  static const double pad = 12;
  static const double minWallPx = 12;

  late final double pxPerM;
  late final double wallPx;
  late final double wallLeft;

  double get wallRight => wallLeft + wallPx;

  /// Pixel x for a distance from the source.
  double xFor(double fromSourceM) {
    final double d = config.sourceToWallM;
    final double t = config.thicknessM;
    if (fromSourceM <= d) return wallLeft - (d - fromSourceM) * pxPerM;
    if (fromSourceM >= d + t) {
      return wallRight + (fromSourceM - d - t) * pxPerM;
    }
    return wallLeft + (t == 0 ? 0 : (fromSourceM - d) / t * wallPx);
  }

  /// Distance from the source for a pixel x.
  double fromSourceAt(double x) {
    final double d = config.sourceToWallM;
    final double t = config.thicknessM;
    if (x <= wallLeft) return d - (wallLeft - x) / pxPerM;
    if (x >= wallRight) return d + t + (x - wallRight) / pxPerM;
    return d + (wallPx == 0 ? 0 : (x - wallLeft) / wallPx * t);
  }

  double get sourceX => xFor(0);

  // Vertical bands.
  double get bottomBand => 44 * scale.text;
  double get floorY => size.height - bottomBand;
  double get figureH =>
      math.min(size.height * 0.30, 96 * scale.marker).clamp(40.0, 400.0);
  double get topPad => 24 * scale.text;

  /// Largest wave half-height.
  double get amp => math.max(
    12,
    math.min(
      size.height * 0.2,
      (floorY - figureH - topPad - 18 * scale.marker) / 2,
    ),
  );

  /// Wave center line.
  double get waveY => topPad + amp;

  /// The level drawn at full height: the one closest to the source.
  double get topDbm => config.levelAtDbm(MwConfig.minFromSourceM);

  /// The level drawn at zero height: 12 dB under the lowest level in view,
  /// never below the noise floor. A zoomed dB scale, so the steep start of
  /// the free-space curve and the step at the wall are both plain to see.
  double get baseDbm {
    final double lowest = config.levelAtDbm(fromSourceAt(size.width));
    return math.max(MwConfig.noiseFloorDbm, lowest - 12);
  }

  /// Height of a level, 0 at [baseDbm], 1 at [topDbm].
  double heightFor(double dbm) {
    final double span = topDbm - baseDbm;
    if (span <= 0) return 0;
    return ((dbm - baseDbm) / span).clamp(0.0, 1.0);
  }

  /// Pixel y of the crest for a level.
  double crestY(double dbm) => waveY - amp * heightFor(dbm);
}

@immutable
class MwStageStyle {
  const MwStageStyle({
    required this.surface,
    required this.ink,
    required this.muted,
    required this.wave,
    required this.wallFill,
    required this.accentFill,
    required this.label,
    required this.small,
    this.scale = PresenterScale.normal,
  });

  final Color surface;

  /// Person, laptop, source, wall outline, labels.
  final Color ink;

  /// Floor, level line, dimension lines, the other spot's ring.
  final Color muted;

  /// The wave stroke: the foreground lime (textAccent), legal as a thin
  /// stroke on light (GL-003 §8.20.2 rule 1).
  final Color wave;
  final Color wallFill;

  /// The laptop screen: a fill only, always with an ink outline.
  final Color accentFill;
  final TextStyle label;
  final TextStyle small;
  final PresenterScale scale;
}

class MwStagePainter extends CustomPainter {
  MwStagePainter({
    required this.config,
    required this.view,
    required this.style,
    required this.format,
    required this.revision,
  });

  final MwConfig config;
  final MwView view;
  final MwStageStyle style;
  final MwFormat format;
  final int revision;

  final List<Rect> _placed = <Rect>[];

  /// The canvas width of the paint in progress, for keeping labels inside.
  double _width = 0;

  @override
  void paint(Canvas canvas, Size size) {
    _placed.clear();
    _width = size.width;
    final MwStageGeometry g = MwStageGeometry(size, config, view, style.scale);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _floor(canvas, g);
    _wall(canvas, g);
    _wave(canvas, g);
    _source(canvas, g);
    final MwSide other = config.side == MwSide.near ? MwSide.far : MwSide.near;
    _spotRing(canvas, g, other);
    _person(canvas, g);
    _series(canvas, g, MwSide.near);
    _series(canvas, g, MwSide.far);
    _dimensions(canvas, g);
    canvas.restore();
  }

  double _s(double w) => style.scale.strokeWidth(w);
  double _m(double r) => style.scale.markerSize(r);

  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _s(w)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = c;

  void _floor(Canvas canvas, MwStageGeometry g) {
    canvas.drawLine(
      Offset(0, g.floorY),
      Offset(g.size.width, g.floorY),
      _stroke(style.muted, 1.5),
    );
  }

  void _wall(Canvas canvas, MwStageGeometry g) {
    final Rect r = Rect.fromLTRB(
      g.wallLeft,
      g.waveY - g.amp - 8 * style.scale.marker,
      g.wallRight,
      g.floorY,
    );
    canvas.drawRect(r, Paint()..color = style.wallFill);
    canvas.drawRect(r, _stroke(style.ink, 1.5));
    _label(
      canvas,
      '${config.material.label}, ${format.thickness(config.thicknessM)}',
      Offset(r.center.dx, r.top - 2),
      style.small,
      anchor: _Anchor.bottomCenter,
    );
  }

  /// Level at a pixel x, dBm: free space in front, free space minus the wall
  /// behind, a straight line in dB through the wall.
  double _levelAtPx(MwStageGeometry g, double x) {
    final double d = config.sourceToWallM;
    final double t = config.thicknessM;
    if (x > g.wallLeft && x < g.wallRight) {
      final double front = config.levelAtDbm(d);
      final double back = config.levelAtDbm(d + t + 1e-9);
      final double u = (x - g.wallLeft) / g.wallPx;
      return front + (back - front) * u;
    }
    return config.levelAtDbm(g.fromSourceAt(x));
  }

  void _wave(Canvas canvas, MwStageGeometry g) {
    final double x0 = g.sourceX;
    final double lambda = _m(24);
    final Path wave = Path();
    final Path level = Path();
    bool first = true;
    for (double x = x0; x <= g.size.width; x += 1) {
      final double dbm = _levelAtPx(g, x);
      final double h = g.heightFor(dbm);
      final double y =
          g.waveY - g.amp * h * math.sin(2 * math.pi * (x - x0) / lambda);
      final double yl = g.waveY - g.amp * h;
      if (first) {
        wave.moveTo(x, y);
        level.moveTo(x, yl);
        first = false;
      } else {
        wave.lineTo(x, y);
        level.lineTo(x, yl);
      }
    }
    canvas.drawPath(level, _stroke(style.muted, 1));
    canvas.drawPath(wave, _stroke(style.wave, 2));
    // Center line, so a flat wave behind a metal wall still reads as a line.
    canvas.drawLine(
      Offset(x0, g.waveY),
      Offset(g.size.width, g.waveY),
      _stroke(style.muted, 0.75),
    );
  }

  void _source(Canvas canvas, MwStageGeometry g) {
    final double x = g.sourceX;
    final double boxW = _m(18), boxH = _m(12);
    final double top = g.floorY - g.figureH * 0.7;
    final Rect box = Rect.fromCenter(
      center: Offset(x, top),
      width: boxW,
      height: boxH,
    );
    // Stand.
    canvas.drawLine(
      Offset(x, box.bottom),
      Offset(x, g.floorY),
      _stroke(style.ink, 2),
    );
    canvas.drawLine(
      Offset(x - boxW * 0.6, g.floorY),
      Offset(x + boxW * 0.6, g.floorY),
      _stroke(style.ink, 2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(_m(2))),
      Paint()..color = style.surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(_m(2))),
      _stroke(style.ink, 2),
    );
    // Antenna.
    canvas.drawLine(
      Offset(box.right - _m(4), box.top),
      Offset(box.right - _m(4), box.top - _m(10)),
      _stroke(style.ink, 2),
    );
    _label(
      canvas,
      'RF source',
      Offset(x + boxW / 2 + 4, top + boxH / 2 + 2),
      style.label,
      anchor: _Anchor.topLeft,
    );
  }

  double _spotX(MwStageGeometry g, MwSide s) =>
      g.xFor(s == MwSide.near ? config.nearDistM : config.farDistM);

  void _spotRing(Canvas canvas, MwStageGeometry g, MwSide s) {
    final double x = _spotX(g, s);
    final double r = _m(6);
    canvas.drawCircle(Offset(x, g.floorY - r), r, _stroke(style.muted, 2));
  }

  void _person(Canvas canvas, MwStageGeometry g) {
    final double x = _spotX(g, config.side);
    final double h = g.figureH;
    final double foot = g.floorY;
    final double headR = h * 0.09;
    final double headY = foot - h + headR;
    final double neck = headY + headR;
    final double hip = foot - h * 0.42;
    // Faces the wall: right on the near side, left on the far side.
    final double dir = config.side == MwSide.near ? 1 : -1;
    final Paint ink = _stroke(style.ink, 2.5);
    canvas.drawCircle(Offset(x, headY), headR, ink);
    canvas.drawLine(Offset(x, neck), Offset(x, hip), ink);
    canvas.drawLine(Offset(x, hip), Offset(x - h * 0.12, foot), ink);
    canvas.drawLine(Offset(x, hip), Offset(x + h * 0.12, foot), ink);
    // Arms forward to the laptop.
    final double handY = neck + h * 0.22;
    final Offset hand = Offset(x + dir * h * 0.20, handY);
    canvas.drawLine(Offset(x, neck + h * 0.06), hand, ink);
    // The laptop: a base in the hands and an open screen, the screen filled
    // with the accent and outlined in ink.
    final double baseW = h * 0.26;
    final Offset b0 = Offset(hand.dx - dir * baseW * 0.35, handY);
    final Offset b1 = Offset(b0.dx + dir * baseW, handY);
    final Offset lid = Offset(b0.dx + dir * baseW * 0.05, handY - baseW * 0.72);
    final Path screen = Path()
      ..moveTo(b0.dx, b0.dy)
      ..lineTo(lid.dx - dir * baseW * 0.12, lid.dy)
      ..lineTo(lid.dx + dir * baseW * 0.10, lid.dy + baseW * 0.06)
      ..lineTo(b0.dx + dir * baseW * 0.18, b0.dy)
      ..close();
    canvas.drawPath(screen, Paint()..color = style.accentFill);
    canvas.drawPath(screen, _stroke(style.ink, 1.5));
    canvas.drawLine(b0, b1, _stroke(style.ink, 3));
  }

  void _series(Canvas canvas, MwStageGeometry g, MwSide s) {
    final MwSeries ser = config.seriesFor(s);
    final double x = _spotX(g, s);
    final double tick = _m(6);
    final double crest = g.crestY(ser.modelDbm);
    // A dashed drop line from the level to the floor.
    _dashed(canvas, Offset(x, crest), Offset(x, g.floorY), style.muted);
    if (ser.belowFloor) {
      _label(
        canvas,
        'Below the noise floor',
        Offset(x + (s == MwSide.near ? -6 : 6), g.waveY - 4),
        style.small,
        anchor: s == MwSide.near ? _Anchor.bottomRight : _Anchor.bottomLeft,
      );
      return;
    }
    final double ya = g.crestY(ser.averageDbm);
    canvas.drawLine(
      Offset(x - tick * 2.2, ya),
      Offset(x + tick * 2.2, ya),
      _stroke(style.ink, 3),
    );
    final bool near = s == MwSide.near;
    _label(
      canvas,
      '${near ? 'Near' : 'Far'} average ${MwFormat.dbm(ser.averageDbm)}',
      Offset(x + (near ? -tick * 2.6 : tick * 2.6), ya - 2),
      style.small,
      anchor: near ? _Anchor.bottomRight : _Anchor.bottomLeft,
    );
  }

  void _dimensions(Canvas canvas, MwStageGeometry g) {
    // Gaps first, right under the floor beside each spot, outside the wall.
    final double yGap = g.floorY + 3;
    _label(
      canvas,
      format.gap(config.nearGapM),
      Offset(_spotX(g, MwSide.near) - 4, yGap),
      style.small,
      anchor: _Anchor.topRight,
    );
    _label(
      canvas,
      format.gap(config.farGapM),
      Offset(_spotX(g, MwSide.far) + 4, yGap),
      style.small,
      anchor: _Anchor.topLeft,
    );
    // Source to wall, below them.
    final double y = g.floorY + 24 * style.scale.text;
    final Paint p = _stroke(style.muted, 1.25);
    final double xs = g.sourceX, xw = g.wallLeft;
    canvas.drawLine(Offset(xs, y), Offset(xw, y), p);
    canvas.drawLine(Offset(xs, y - 4), Offset(xs, y + 4), p);
    canvas.drawLine(Offset(xw, y - 4), Offset(xw, y + 4), p);
    _label(
      canvas,
      'Source to wall ${format.dist(config.sourceToWallM)}',
      Offset((xs + xw) / 2, y + 2),
      style.small,
      anchor: _Anchor.topCenter,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color c) {
    final Paint p = _stroke(c, 1);
    final double len = (b - a).distance;
    if (len <= 0) return;
    final Offset dir = (b - a) / len;
    final double dash = _m(4), gap = _m(3);
    for (double t = 0; t < len; t += dash + gap) {
      canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, len), p);
    }
  }

  /// Draws a label on a knockout, nudged down past labels already placed so
  /// two never overlap, and kept inside the canvas.
  void _label(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle ts, {
    required _Anchor anchor,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: ts),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    double dx = at.dx, dy = at.dy;
    switch (anchor) {
      case _Anchor.topLeft:
        break;
      case _Anchor.topRight:
        dx -= tp.width;
      case _Anchor.topCenter:
        dx -= tp.width / 2;
      case _Anchor.bottomLeft:
        dy -= tp.height;
      case _Anchor.bottomRight:
        dx -= tp.width;
        dy -= tp.height;
      case _Anchor.bottomCenter:
        dx -= tp.width / 2;
        dy -= tp.height;
    }
    dx = dx.clamp(2.0, math.max(2.0, _width - tp.width - 2));
    Rect r = Rect.fromLTWH(dx, dy, tp.width, tp.height).inflate(2);
    for (int i = 0; i < 6; i++) {
      final Rect? hit = _placed.where((Rect q) => q.overlaps(r)).firstOrNull;
      if (hit == null) break;
      final bool up =
          anchor == _Anchor.bottomLeft ||
          anchor == _Anchor.bottomRight ||
          anchor == _Anchor.bottomCenter;
      r = r.shift(Offset(0, up ? hit.top - r.bottom : hit.bottom - r.top));
    }
    _placed.add(r);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()..color = style.surface,
    );
    tp.paint(canvas, r.topLeft + const Offset(2, 2));
  }

  @override
  bool shouldRepaint(MwStagePainter old) =>
      old.revision != revision ||
      old.view != view ||
      old.style.scale != style.scale ||
      old.style.ink != style.ink ||
      old.style.wave != style.wave ||
      old.style.surface != style.surface ||
      old.format.units != format.units;
}

enum _Anchor {
  topLeft,
  topRight,
  topCenter,
  bottomLeft,
  bottomRight,
  bottomCenter,
}
