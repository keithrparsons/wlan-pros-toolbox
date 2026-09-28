// Painter for the Wi-Fi Classroom Body Loss stage (body-loss).
//
// A top-down auditorium floor: the AP on the front wall, the holder (a body
// seen from above, with a facing arrow and the device held in front), the
// crowd, and the straight line from the AP to the device. Every person the
// line passes through is filled in the accent, outlined and numbered, so an
// obstruction never rests on color alone; the holder's body is outlined and
// labeled with its loss when it is in the path.
//
// Nothing here draws a wave, so nothing can imply a frequency change
// (Wi-Fi Classroom standing rule).
//
// BlFloorGeometry is the one mapping between meters and pixels, shared with
// the stage's drag handler so a touch and a drawn position never disagree.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'body_loss_controller.dart';

/// Meters to pixels for the floor, letterboxed to keep its proportions.
@immutable
class BlFloorGeometry {
  const BlFloorGeometry(this.size);

  final Size size;

  static const double pad = 10;

  double get pxPerM => math.max(
    0.01,
    math.min(
      (size.width - 2 * pad) / BlConfig.floorWidthM,
      (size.height - 2 * pad) / BlConfig.floorDepthM,
    ),
  );

  Offset get origin => Offset(
    (size.width - BlConfig.floorWidthM * pxPerM) / 2,
    (size.height - BlConfig.floorDepthM * pxPerM) / 2,
  );

  Rect get floorRect =>
      origin &
      Size(BlConfig.floorWidthM * pxPerM, BlConfig.floorDepthM * pxPerM);

  Offset toPx(BlPoint p) => origin + Offset(p.x * pxPerM, p.y * pxPerM);

  BlPoint toM(Offset local) {
    final Offset o = (local - origin) / pxPerM;
    return BlPoint(o.dx, o.dy);
  }
}

@immutable
class BlStageStyle {
  const BlStageStyle({
    required this.surface,
    required this.grid,
    required this.ink,
    required this.crowd,
    required this.accent,
    required this.accentStroke,
    required this.onAccent,
    required this.gridLabel,
    required this.label,
    required this.badge,
    this.scale = PresenterScale.normal,
  });

  final Color surface;
  final Color grid;

  /// AP, holder, the line and label text.
  final Color ink;

  /// People not on the line.
  final Color crowd;

  /// FILL for people on the line and the device, always with an ink
  /// outline. On light, lime is a fill only (GL-003 §8.20.2 rule 1); the
  /// outline carries the contrast.
  final Color accent;

  /// The holder's in-path ring, a thin stroke: the foreground lime
  /// (textAccent), the one legal thin lime on light (§8.20.2 rule 1).
  final Color accentStroke;

  /// Badge numbers on the accent.
  final Color onAccent;
  final TextStyle gridLabel;
  final TextStyle label;
  final TextStyle badge;

  /// Presenter scale for strokes and markers. The text styles arrive already
  /// scaled (the stage applies paintFont).
  final PresenterScale scale;
}

class BlStagePainter extends CustomPainter {
  BlStagePainter({
    required this.config,
    required this.style,
    required this.revision,
    required this.holderLabel,
    required this.emptyLabel,
    this.units = UnitSystem.metric,
  });

  /// Units for the scale bar: 5 m, or 15 ft.
  final UnitSystem units;

  final BlConfig config;
  final BlStageStyle style;
  final int revision;

  /// The holder's label ("Holder" or "Holder, body in the path: 9.6 dB").
  final String holderLabel;

  /// Shown on the floor while the building is empty, else null.
  final String? emptyLabel;

  final List<Rect> _placed = <Rect>[];

  @override
  void paint(Canvas canvas, Size size) {
    final BlFloorGeometry g = BlFloorGeometry(size);
    _placed.clear();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _floor(canvas, g);
    final Set<int> onLine = config.crossingIndexes.toSet();
    if (config.occupied) _crowd(canvas, g, onLine);
    _line(canvas, g);
    // Floor marks after the crowd, so no person is drawn over their text.
    _floorMarks(canvas, g);
    _ap(canvas, g);
    _holder(canvas, g);
    if (config.occupied) _badges(canvas, g, onLine);
    _labels(canvas, g);
    canvas.restore();
  }

  double get _bodyR => BlConfig.bodyWidthM / 2;

  void _floor(Canvas canvas, BlFloorGeometry g) {
    final Rect r = g.floorRect;
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.scale.strokeWidth(1.5)
        ..color = style.grid,
    );
    // The front wall, where the AP hangs, drawn heavier.
    canvas.drawLine(
      r.topLeft,
      r.bottomLeft,
      Paint()
        ..strokeWidth = style.scale.strokeWidth(4)
        ..color = style.grid,
    );
  }

  /// The 5 m scale bar and the Front label.
  void _floorMarks(Canvas canvas, BlFloorGeometry g) {
    final Rect r = g.floorRect;
    // A 5 m scale bar along the bottom edge.
    final double y = r.bottom - 8 * style.scale.marker;
    // The scale bar is a round length in the unit on screen.
    final double barM = units.isMetric ? 5 : LengthUnits.feetToMetres(15);
    final double x0 = r.right - 8 - barM * g.pxPerM;
    final Paint p = Paint()
      ..strokeWidth = style.scale.strokeWidth(1.5)
      ..color = style.grid;
    canvas.drawLine(Offset(x0, y), Offset(x0 + barM * g.pxPerM, y), p);
    canvas.drawLine(Offset(x0, y - 4), Offset(x0, y + 4), p);
    canvas.drawLine(
      Offset(x0 + barM * g.pxPerM, y - 4),
      Offset(x0 + barM * g.pxPerM, y + 4),
      p,
    );
    final TextPainter tp = _text(
      units.isMetric ? '5 m' : '15 ft',
      style.gridLabel,
    );
    final Offset at = Offset(
      x0 + barM * g.pxPerM / 2 - tp.width / 2,
      y - tp.height - 4,
    );
    _knockout(canvas, at, tp);
    _placed.add((at & tp.size).inflate(2));
    final TextPainter front = _text('Front', style.gridLabel);
    final Offset fAt = Offset(r.left + 6, r.top + 4);
    _knockout(canvas, fAt, front);
    _placed.add((fAt & front.size).inflate(2));
  }

  double _personR(BlFloorGeometry g) =>
      math.max(_bodyR * g.pxPerM, style.scale.markerSize(3.5));

  void _crowd(Canvas canvas, BlFloorGeometry g, Set<int> onLine) {
    final double r = _personR(g);
    for (int i = 0; i < config.crowdSize; i++) {
      final Offset c = g.toPx(config.people[i]);
      if (onLine.contains(i)) {
        canvas.drawCircle(c, r, Paint()..color = style.accent);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.scale.strokeWidth(1.5)
            ..color = style.ink,
        );
      } else {
        canvas.drawCircle(c, r, Paint()..color = style.crowd);
      }
    }
  }

  void _line(Canvas canvas, BlFloorGeometry g) {
    canvas.drawLine(
      g.toPx(BlConfig.ap),
      g.toPx(config.device),
      Paint()
        ..strokeWidth = style.scale.strokeWidth(2)
        ..strokeCap = StrokeCap.round
        ..color = style.ink,
    );
  }

  void _ap(Canvas canvas, BlFloorGeometry g) {
    final Offset c = g.toPx(BlConfig.ap);
    final double m = style.scale.marker;
    final Rect r = Rect.fromCenter(center: c, width: 14 * m, height: 14 * m);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)),
      Paint()..color = style.surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(2)),
      Paint()..color = style.ink,
    );
    final TextPainter tp = _text('AP', style.label);
    final Offset at = c + Offset(-tp.width / 2, 10 * m);
    _knockout(canvas, at, tp);
    _placed
      ..add(r.inflate(3))
      ..add((at & tp.size).inflate(3));
  }

  void _holder(Canvas canvas, BlFloorGeometry g) {
    final Offset c = g.toPx(config.holder);
    final double a = config.facingDeg * math.pi / 180;
    final Offset fwd = Offset(math.sin(a), -math.cos(a));
    final double k = g.pxPerM;
    final double m = style.scale.marker;
    final bool inPath = config.holderShare > 0.001;

    // Facing arrow, from the body forward.
    final double arrowLen = math.max(1.4 * k, 26 * m);
    final Offset tip = c + fwd * arrowLen;
    final Paint arrow = Paint()
      ..strokeWidth = style.scale.strokeWidth(2)
      ..strokeCap = StrokeCap.round
      ..color = style.ink;
    final double head = style.scale.markerSize(8);
    canvas.drawLine(c, tip - fwd * head * 0.8, arrow);
    final Offset n = Offset(-fwd.dy, fwd.dx);
    canvas.drawPath(
      ui.Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          (tip - fwd * head + n * head * 0.5).dx,
          (tip - fwd * head + n * head * 0.5).dy,
        )
        ..lineTo(
          (tip - fwd * head - n * head * 0.5).dx,
          (tip - fwd * head - n * head * 0.5).dy,
        )
        ..close(),
      Paint()..color = style.ink,
    );

    // The body: shoulders across the facing direction.
    final double w = math.max(BlConfig.bodyWidthM * k, 16 * m);
    final double d = math.max(0.28 * k, 10 * m);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(a);
    final Rect body = Rect.fromCenter(center: Offset.zero, width: w, height: d);
    canvas.drawOval(body.inflate(1.5), Paint()..color = style.surface);
    canvas.drawOval(body, Paint()..color = style.ink);
    if (inPath) {
      canvas.drawOval(
        body.inflate(3 * m),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.scale.strokeWidth(2.5)
          ..color = style.accentStroke,
      );
    }
    canvas.restore();

    // The device, held in front.
    final Offset dev = g.toPx(config.device);
    final double ds = math.max(0.16 * k, 7 * m);
    final Rect dr = Rect.fromCenter(center: dev, width: ds, height: ds);
    canvas.drawRRect(
      RRect.fromRectAndRadius(dr.inflate(1.5), const Radius.circular(2)),
      Paint()..color = style.ink,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(dr, const Radius.circular(2)),
      Paint()..color = style.accent,
    );
    _placed
      ..add(Rect.fromCircle(center: c, radius: w / 2 + 3 * m))
      ..add(dr.inflate(2));
  }

  void _badges(Canvas canvas, BlFloorGeometry g, Set<int> onLine) {
    final double r = _personR(g);
    int k = 0;
    // Number the people along the line, from the AP outward.
    final List<int> order = onLine.toList()
      ..sort(
        (int a, int b) => config.people[a]
            .distanceTo(BlConfig.ap)
            .compareTo(config.people[b].distanceTo(BlConfig.ap)),
      );
    for (final int i in order) {
      k++;
      final Offset c = g.toPx(config.people[i]);
      final TextPainter tp = _text('$k', style.badge);
      final double br = math.max(tp.width, tp.height) / 2 + 3;
      // Above the person, or below when that is off the floor.
      Offset bc = c + Offset(0, -(r + br + 2));
      if (bc.dy - br < 0) bc = c + Offset(0, r + br + 2);
      canvas.drawCircle(bc, br + 1.5, Paint()..color = style.ink);
      canvas.drawCircle(bc, br, Paint()..color = style.accent);
      tp.paint(canvas, bc - Offset(tp.width / 2, tp.height / 2));
      _placed.add(Rect.fromCircle(center: bc, radius: br + 2));
    }
  }

  void _labels(Canvas canvas, BlFloorGeometry g) {
    final Offset c = g.toPx(config.holder);
    final TextPainter tp = _text(holderLabel, style.label);
    final double m = style.scale.marker;
    final double a = config.facingDeg * math.pi / 180;
    // Behind the holder first (the arrow points forward), then below, above.
    final Offset back = -Offset(math.sin(a), -math.cos(a));
    final double off = 22 * m;
    final List<Offset> tries = <Offset>[
      c + back * (off + tp.width / 2) - Offset(tp.width / 2, tp.height / 2),
      c + Offset(-tp.width / 2, off),
      c + Offset(-tp.width / 2, -off - tp.height),
      c + Offset(off, -tp.height / 2),
      c + Offset(-off - tp.width, -tp.height / 2),
    ];
    _placeFirstFree(canvas, g.size, tp, tries, fallback: true);

    final String? e = emptyLabel;
    if (e != null) {
      final TextPainter et = _text(e, style.label);
      final Rect r = g.floorRect;
      final Offset at = Offset(r.center.dx - et.width / 2, r.top + 6);
      _knockout(canvas, at, et);
    }
  }

  bool _free(Rect r, Size size) =>
      r.left >= 0 &&
      r.top >= 0 &&
      r.right <= size.width &&
      r.bottom <= size.height &&
      !_placed.any((Rect p) => p.overlaps(r));

  void _placeFirstFree(
    Canvas canvas,
    Size size,
    TextPainter tp,
    List<Offset> tries, {
    bool fallback = false,
  }) {
    for (final Offset at in tries) {
      final Rect r = (at & tp.size).inflate(3);
      if (_free(r, size)) {
        _placed.add(r);
        _knockout(canvas, at, tp);
        return;
      }
    }
    if (!fallback || tries.isEmpty) return;
    final Offset at = _clampTo(size, tries.first, tp.size);
    _placed.add((at & tp.size).inflate(3));
    _knockout(canvas, at, tp);
  }

  static Offset _clampTo(Size canvas, Offset at, Size box) => Offset(
    at.dx.clamp(2.0, math.max(2.0, canvas.width - box.width - 2)),
    at.dy.clamp(2.0, math.max(2.0, canvas.height - box.height - 2)),
  );

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

  @override
  bool shouldRepaint(BlStagePainter old) =>
      old.revision != revision ||
      old.style != style ||
      old.holderLabel != holderLabel ||
      old.units != units ||
      old.emptyLabel != emptyLabel;
}
