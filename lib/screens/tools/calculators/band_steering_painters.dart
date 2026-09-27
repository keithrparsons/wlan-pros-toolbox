// Painters for the Wi-Fi Classroom Band Steering stage (band-steering).
//
// BsFloorPainter: a top-down floor. The dual-band AP sits at the left; the
// walking path runs out to the right, just below it, with meter ticks. One
// ring per band marks where the client can still hear that band (the
// illustrative -82 dBm floor): 2.4 GHz SOLID, 5 GHz DASHED, each labeled.
// The beacon pulse leaves the AP on both bands in every steering mode. The
// association line runs from the AP to the client in the band's hue and
// pattern, with its band written on it. At a sample where the client
// scanned, one probe arrow per band points from the client at the AP:
// answered is a solid line with a head at each end; ignored is a dashed line
// that ends in a cross, labeled "no answer".
//
// BsGaugePainter: one band's RSSI on a -95 to -30 dBm bar, with the selected
// client's thresholds as lines, each labeled.
//
// Nothing here draws a wave, so nothing can imply a frequency change
// (Wi-Fi Classroom standing rule).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/band_steering_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import 'band_steering_parts.dart' show bsBandDashed;

@immutable
class BsStageStyle {
  const BsStageStyle({
    required this.surface,
    required this.grid,
    required this.ink,
    required this.muted,
    required this.band24,
    required this.band5,
    required this.refused,
    required this.gridLabel,
    required this.label,
    this.scale = PresenterScale.normal,
  });

  final Color surface;
  final Color grid;

  /// AP, client and label text.
  final Color ink;

  /// Secondary label text.
  final Color muted;
  final Color band24;
  final Color band5;

  /// The refused-authentication verdict (a warning hue, always with words).
  final Color refused;
  final TextStyle gridLabel;
  final TextStyle label;
  final PresenterScale scale;

  Color bandColor(BsBand b) => b == BsBand.ghz24 ? band24 : band5;

  @override
  bool operator ==(Object other) =>
      other is BsStageStyle &&
      other.surface == surface &&
      other.grid == grid &&
      other.ink == ink &&
      other.muted == muted &&
      other.band24 == band24 &&
      other.band5 == band5 &&
      other.refused == refused &&
      other.gridLabel == gridLabel &&
      other.label == label &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(
    surface,
    grid,
    ink,
    muted,
    band24,
    band5,
    refused,
    gridLabel,
    label,
    scale,
  );
}

/// Where things sit on the floor, shared by the painter and its tests.
class BsFloorGeometry {
  BsFloorGeometry({required this.size, required this.rangeM});

  final Size size;
  final double rangeM;

  /// The AP.
  Offset get ap => Offset(size.width * 0.10, size.height * 0.42);

  /// Pixels per meter along the path.
  double get pxPerM => (size.width * 0.86) / rangeM;

  /// The path runs this far below the AP, pixels.
  double get pathDrop => math.min(40, size.height * 0.16);

  /// The client at [distanceM] from the AP.
  Offset client(double distanceM) =>
      Offset(ap.dx + distanceM * pxPerM, ap.dy + pathDrop);
}

void _dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint p, {
  double dash = 7,
  double gap = 5,
}) {
  final double len = (b - a).distance;
  if (len == 0) return;
  final Offset dir = (b - a) / len;
  for (double t = 0; t < len; t += dash + gap) {
    canvas.drawLine(a + dir * t, a + dir * math.min(t + dash, len), p);
  }
}

void _dashedCircle(Canvas canvas, Offset c, double r, Paint p, double dash) {
  if (r <= 0) return;
  final double circ = 2 * math.pi * r;
  final int n = math.max(8, (circ / (dash * 2)).floor());
  final double sweep = 2 * math.pi / n;
  for (int i = 0; i < n; i++) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      i * sweep,
      sweep / 2,
      false,
      p,
    );
  }
}

void _arrowHead(Canvas canvas, Offset tip, Offset from, Paint fill, double s) {
  final Offset dir = tip - from;
  final double len = dir.distance;
  if (len == 0) return;
  final Offset u = dir / len;
  final Offset n = Offset(-u.dy, u.dx);
  final Path path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(
      tip.dx - u.dx * s + n.dx * s * 0.55,
      tip.dy - u.dy * s + n.dy * s * 0.55,
    )
    ..lineTo(
      tip.dx - u.dx * s - n.dx * s * 0.55,
      tip.dy - u.dy * s - n.dy * s * 0.55,
    )
    ..close();
  canvas.drawPath(path, fill);
}

TextPainter _text(String s, TextStyle style) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
)..layout();

class BsFloorPainter extends CustomPainter {
  BsFloorPainter({
    required this.rangeM,
    required this.ring24M,
    required this.ring5M,
    required this.step,
    required this.walkFrom,
    required this.walkTo,
    required this.clientLetter,
    required this.style,
    required this.pulse,
    this.units = UnitSystem.metric,
  }) : super(repaint: pulse);

  /// Units for the path ticks.
  final UnitSystem units;

  final double rangeM;
  final double ring24M;
  final double ring5M;
  final BsStep step;

  /// Walk start and end, meters from the AP (the arrow's direction).
  final double walkFrom;
  final double walkTo;
  final String clientLetter;
  final BsStageStyle style;

  /// 0 to 1: the beacon pulse.
  final ValueListenable<double> pulse;

  PresenterScale get _s => style.scale;

  @override
  void paint(Canvas canvas, Size size) {
    final BsFloorGeometry g = BsFloorGeometry(size: size, rangeM: rangeM);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = style.surface);
    _path(canvas, g);
    _rings(canvas, g, size);
    _beacons(canvas, g);
    _association(canvas, g);
    _probes(canvas, g);
    _ap(canvas, g);
    _client(canvas, g);
    canvas.restore();
  }

  void _path(Canvas canvas, BsFloorGeometry g) {
    final Paint line = Paint()
      ..color = style.grid
      ..strokeWidth = _s.strokeWidth(1.5);
    final Offset a = g.client(kBsNearM);
    final Offset b = g.client(kBsEdgeM);
    _dashedLine(canvas, a, b, line, dash: 3, gap: 4);
    // Ticks every 10 m, or every 50 ft (25 ft crowds the 180 ft path and
    // runs into the client marker at its end).
    final LengthFormat f = LengthFormat(units);
    final double stepShown = units.isMetric ? 10 : 50;
    for (
      double v = stepShown;
      f.distToMetres(v) <= kBsEdgeM + 1e-9;
      v += stepShown
    ) {
      final Offset t = g.client(f.distToMetres(v));
      canvas.drawLine(t, t + Offset(0, 5 * _s.marker), line);
      final TextPainter tp = _text(
        '${v.round()} ${f.distUnit}',
        style.gridLabel,
      );
      tp.paint(canvas, t + Offset(-tp.width / 2, 7 * _s.marker));
    }
    // The walk's direction, at the far end of the path, above it: an arrow
    // and the words, so the direction never rests on the arrow alone.
    final bool inward = walkFrom > walkTo;
    final TextPainter walk = _text(
      inward ? 'Walking in' : 'Walking out',
      style.gridLabel,
    );
    final Offset far = g.client(kBsEdgeM);
    final double y = far.dy - 14 * _s.marker - walk.height / 2;
    final double len = 26 * _s.marker;
    final double right = math.min(far.dx, g.size.width - 4);
    final double textX = right - len - 6 - walk.width;
    walk.paint(canvas, Offset(textX, y - walk.height / 2));
    final Offset a0 = Offset(right - len, y);
    final Offset a1 = Offset(right, y);
    final Paint arrow = Paint()
      ..color = style.muted
      ..strokeWidth = _s.strokeWidth(1.5);
    canvas.drawLine(a0, a1, arrow);
    if (inward) {
      _arrowHead(canvas, a0, a1, arrow, 7 * _s.marker);
    } else {
      _arrowHead(canvas, a1, a0, arrow, 7 * _s.marker);
    }
  }

  void _rings(Canvas canvas, BsFloorGeometry g, Size size) {
    for (final BsBand b in BsBand.values) {
      final double r = (b == BsBand.ghz24 ? ring24M : ring5M) * g.pxPerM;
      final Paint p = Paint()
        ..color = style.bandColor(b)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s.strokeWidth(2);
      if (b == BsBand.ghz5) {
        _dashedCircle(canvas, g.ap, r, p, 6);
      } else {
        canvas.drawCircle(g.ap, r, p);
      }
      // Label where the ring crosses the top of the view, or at its right
      // edge when it fits.
      final TextPainter tp = _text(
        '${b.label} edge',
        style.label.copyWith(color: style.bandColor(b)),
      );
      final double x = g.ap.dx + r;
      Offset at;
      if (x + tp.width + 4 < size.width) {
        at = Offset(x + 4, g.ap.dy - tp.height - 6);
      } else {
        // Where the ring meets y = 4.
        final double dy = g.ap.dy - 4;
        final double dx = r > dy ? math.sqrt(r * r - dy * dy) : 0;
        at = Offset(math.min(g.ap.dx + dx + 4, size.width - tp.width - 4), 4);
      }
      _knockout(canvas, at, tp);
    }
  }

  void _beacons(Canvas canvas, BsFloorGeometry g) {
    final double t = pulse.value;
    for (final BsBand b in BsBand.values) {
      final double base = (b == BsBand.ghz24 ? 30 : 20) * _s.marker;
      final double r = base + t * 26 * _s.marker;
      final Paint p = Paint()
        ..color = style.bandColor(b).withValues(alpha: 1 - 0.7 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s.strokeWidth(1.5);
      final Rect rect = Rect.fromCircle(center: g.ap, radius: r);
      // An arc over the AP, so the beacon never hides the path.
      if (bsBandDashed(b)) {
        for (int i = 0; i < 6; i++) {
          canvas.drawArc(
            rect,
            math.pi + i * math.pi / 6,
            math.pi / 12,
            false,
            p,
          );
        }
      } else {
        canvas.drawArc(rect, math.pi * 1.05, math.pi * 0.9, false, p);
      }
    }
    final TextPainter tp = _text('Beacons, both bands', style.gridLabel);
    tp.paint(
      canvas,
      Offset(
        math.max(4, g.ap.dx - 14 * _s.marker),
        g.ap.dy - 50 * _s.marker - tp.height,
      ),
    );
  }

  void _association(Canvas canvas, BsFloorGeometry g) {
    final BsBand? b = step.band;
    if (b == null) return;
    final Offset c = g.client(step.distanceM);
    final Paint p = Paint()
      ..color = style.bandColor(b)
      ..strokeWidth = _s.strokeWidth(3);
    if (bsBandDashed(b)) {
      _dashedLine(canvas, g.ap, c, p);
    } else {
      canvas.drawLine(g.ap, c, p);
    }
    final TextPainter tp = _text(
      'On ${b.label}',
      style.label.copyWith(color: style.bandColor(b)),
    );
    final Offset mid = Offset.lerp(g.ap, c, 0.5)!;
    // Below the line: the probe arrows run above it.
    _knockout(canvas, mid + Offset(-tp.width / 2, 8 * _s.marker), tp);
  }

  void _probes(Canvas canvas, BsFloorGeometry g) {
    if (!step.scanned) return;
    final Offset c = g.client(step.distanceM);
    final Offset toAp = g.ap - c;
    final double len = toAp.distance;
    if (len < 1) return;
    final Offset u = toAp / len;
    final Offset n = Offset(-u.dy, u.dx);
    final double arrowLen = math.min(90 * _s.marker, len * 0.7);
    int row = 0;
    for (final BsBand b in <BsBand>[BsBand.ghz24, BsBand.ghz5]) {
      BsFrame? f;
      for (final BsFrame x in step.frames) {
        if (x.kind == BsFrameKind.probeBroadcast && x.band == b) f = x;
      }
      if (f == null) continue;
      final double off = (row == 0 ? 16 : 30) * _s.marker;
      row++;
      final Offset a = c + n * off + u * 10 * _s.marker;
      final Offset tip = a + u * arrowLen;
      final Paint p = Paint()
        ..color = style.bandColor(b)
        ..strokeWidth = _s.strokeWidth(2);
      final bool answered = f.outcome == BsOutcome.answered;
      final Paint fill = Paint()..color = style.bandColor(b);
      if (answered) {
        canvas.drawLine(a, tip, p);
        _arrowHead(canvas, tip, a, fill, 8 * _s.marker);
        _arrowHead(canvas, a, tip, fill, 8 * _s.marker);
      } else {
        _dashedLine(canvas, a, tip, p, dash: 5, gap: 4);
        final double x = 6 * _s.marker;
        canvas.drawLine(tip + Offset(-x, -x), tip + Offset(x, x), p);
        canvas.drawLine(tip + Offset(-x, x), tip + Offset(x, -x), p);
      }
      final TextPainter tp = _text(
        'Probe ${b.label}: ${answered ? 'answered' : 'no answer'}',
        style.gridLabel.copyWith(color: style.ink),
      );
      // Labels stack above the client, clear of the AP and the arrows.
      final double lx = (c.dx - tp.width / 2).clamp(
        4.0,
        math.max(4.0, g.size.width - tp.width - 4),
      );
      final double ly = c.dy - (48 + (row - 1) * 18) * _s.marker - tp.height;
      _knockout(canvas, Offset(lx, ly), tp);
    }
  }

  void _ap(Canvas canvas, BsFloorGeometry g) {
    final double s = 14 * _s.marker;
    final Rect r = Rect.fromCenter(center: g.ap, width: s * 2, height: s * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()..color = style.surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()
        ..color = style.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s.strokeWidth(2),
    );
    final TextPainter tp = _text('AP', style.label.copyWith(color: style.ink));
    tp.paint(canvas, g.ap - Offset(tp.width / 2, tp.height / 2));
  }

  void _client(Canvas canvas, BsFloorGeometry g) {
    final Offset c = g.client(step.distanceM);
    final double r = 12 * _s.marker;
    canvas.drawCircle(c, r, Paint()..color = style.surface);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = style.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s.strokeWidth(2),
    );
    final TextPainter tp = _text(
      clientLetter,
      style.label.copyWith(color: style.ink),
    );
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    final bool refused = step.frames.any(
      (BsFrame f) => f.outcome == BsOutcome.refused,
    );
    final String? note = refused
        ? 'Refused on 2.4 GHz'
        : step.band == null
        ? 'Not connected'
        : null;
    if (note != null) {
      final TextPainter n = _text(
        note,
        style.label.copyWith(color: refused ? style.refused : style.muted),
      );
      _knockout(canvas, c + Offset(-n.width / 2, r + 22 * _s.marker), n);
    }
  }

  void _knockout(Canvas canvas, Offset at, TextPainter tp) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at & tp.size).inflate(2),
        const Radius.circular(3),
      ),
      Paint()..color = style.surface.withValues(alpha: 0.85),
    );
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(BsFloorPainter old) =>
      old.rangeM != rangeM ||
      old.units != units ||
      old.ring24M != ring24M ||
      old.ring5M != ring5M ||
      !identical(old.step, step) ||
      old.walkFrom != walkFrom ||
      old.walkTo != walkTo ||
      old.clientLetter != clientLetter ||
      old.style != style ||
      old.pulse != pulse;
}

/// One threshold line on a gauge.
@immutable
class BsGaugeMark {
  const BsGaugeMark(this.dbm, this.label);

  final double dbm;
  final String label;
}

/// Lowest and highest dBm on a gauge.
const double kBsGaugeMinDbm = -95;
const double kBsGaugeMaxDbm = -30;

class BsGaugePainter extends CustomPainter {
  BsGaugePainter({
    required this.band,
    required this.rssiDbm,
    required this.marks,
    required this.style,
  });

  final BsBand band;
  final double rssiDbm;
  final List<BsGaugeMark> marks;
  final BsStageStyle style;

  PresenterScale get _s => style.scale;

  double _x(double dbm, double w) =>
      ((dbm - kBsGaugeMinDbm) / (kBsGaugeMaxDbm - kBsGaugeMinDbm)).clamp(
        0.0,
        1.0,
      ) *
      w;

  @override
  void paint(Canvas canvas, Size size) {
    final double barH = 12 * _s.marker;
    final TextPainter probe = _text('-00', style.gridLabel);
    final double rowH = probe.height + 2;
    // Row of labels above the bar, the bar, a row of labels below.
    final double top = rowH + 2;
    final Rect track = Rect.fromLTWH(0, top, size.width, barH);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(3)),
      Paint()
        ..color = style.grid
        ..style = PaintingStyle.stroke
        ..strokeWidth = _s.strokeWidth(1),
    );
    final Color hue = style.bandColor(band);
    final double fillW = _x(rssiDbm, size.width);
    final Rect fill = Rect.fromLTWH(0, top, fillW, barH);
    if (bsBandDashed(band)) {
      // Striped fill: the 5 GHz pattern.
      canvas.save();
      canvas.clipRect(fill);
      final Paint stripe = Paint()
        ..color = hue
        ..strokeWidth = 4 * _s.marker;
      for (double x = -barH; x < fillW + barH; x += 9 * _s.marker) {
        canvas.drawLine(Offset(x, top + barH), Offset(x + barH, top), stripe);
      }
      canvas.restore();
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(fill, const Radius.circular(3)),
        Paint()..color = hue,
      );
    }

    // Threshold lines. Their dBm numbers alternate above and below the bar
    // in level order, so neighbors two or three dB apart never collide; the
    // words are in the text line under the gauge.
    final Paint line = Paint()
      ..color = style.ink
      ..strokeWidth = _s.strokeWidth(2);
    final List<BsGaugeMark> sorted = List<BsGaugeMark>.of(marks)
      ..sort((BsGaugeMark a, BsGaugeMark b) => a.dbm.compareTo(b.dbm));
    for (int i = 0; i < sorted.length; i++) {
      final BsGaugeMark m = sorted[i];
      final double x = _x(m.dbm, size.width);
      final bool above = i.isEven;
      canvas.drawLine(
        Offset(x, above ? top - 3 : top),
        Offset(x, above ? top + barH : top + barH + 3),
        line,
      );
      final TextPainter tp = _text(m.dbm.toStringAsFixed(0), style.gridLabel);
      final double lx = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(
        canvas,
        Offset(lx, above ? top - 3 - tp.height : top + barH + 3),
      );
    }
  }

  @override
  bool shouldRepaint(BsGaugePainter old) =>
      old.band != band ||
      old.rssiDbm != rssiDbm ||
      !listEquals(
        old.marks.map((BsGaugeMark m) => '${m.dbm}${m.label}').toList(),
        marks.map((BsGaugeMark m) => '${m.dbm}${m.label}').toList(),
      ) ||
      old.style != style;
}
