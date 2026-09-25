// Painter for the Wi-Fi Lab Rate vs Range stage (rate-vs-range).
//
// A top-down view: the AP at the center, one filled ring per MCS (MCS 0
// outermost), the minimum-basic-rate cell edge as a dashed circle, two
// neutral distance circles, and the client dot with a line back to the AP.
// Distances are linear, so a ring's radius on screen is its radius in meters
// times one scale. The scale ([RvrStageGeometry]) is shared with the stage's
// drag handler so a touch and a drawn position can never disagree.
//
// Nothing here draws a wave, so nothing can imply a frequency change
// (Wi-Fi Lab standing rule).
//
// COLOR: ring hues come in from RvrPalette (GL-003 §8.15.2); every other
// color and text style arrives through [RvrStageStyle], built by the stage
// from context.colors, so dark (§8) and light (§8.20) both work.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Maps meters to pixels and back for one stage size and view range.
@immutable
class RvrStageGeometry {
  const RvrStageGeometry({required this.size, required this.rangeM});

  final Size size;

  /// Meters from the AP to the edge of the drawable circle.
  final double rangeM;

  static const double pad = 10;

  Offset get center => size.center(Offset.zero);

  double get radiusPx => math.max(1, size.shortestSide / 2 - pad);

  double get pxPerM => radiusPx / rangeM;

  /// Distance in meters and bearing of a local point.
  ({double distanceM, double angle}) polarAt(Offset local) {
    final Offset v = local - center;
    return (distanceM: v.distance / pxPerM, angle: v.direction);
  }

  Offset pointAt(double distanceM, double angle) =>
      center + Offset.fromDirection(angle, distanceM * pxPerM);
}

/// One ring as the painter needs it.
@immutable
class RvrPaintRing {
  const RvrPaintRing({
    required this.mcs,
    required this.radiusM,
    required this.color,
  });
  final int mcs;
  final double radiusM;
  final Color color;
}

@immutable
class RvrStageStyle {
  const RvrStageStyle({
    required this.surface,
    required this.grid,
    required this.edge,
    required this.client,
    required this.clientRim,
    required this.ap,
    required this.gridLabel,
    required this.ringLabel,
    required this.edgeLabel,
    required this.clientLabel,
  });

  final Color surface;
  final Color grid;
  final Color edge;
  final Color client;
  final Color clientRim;
  final Color ap;
  final TextStyle gridLabel;
  final TextStyle ringLabel;
  final TextStyle edgeLabel;
  final TextStyle clientLabel;
}

class RvrStagePainter extends CustomPainter {
  RvrStagePainter({
    required this.rangeM,
    required this.rings,
    required this.cellEdgeM,
    required this.cellEdgeLabel,
    required this.clientDistanceM,
    required this.clientAngle,
    required this.clientLabel,
    required this.highlightMcs,
    required this.style,
    required this.revision,
  });

  final double rangeM;

  /// MCS 0 (largest) first.
  final List<RvrPaintRing> rings;
  final double cellEdgeM;
  final String cellEdgeLabel;
  final double clientDistanceM;
  final double clientAngle;
  final String clientLabel;

  /// The client's MCS, drawn with a heavier ring. Null below MCS 0.
  final int? highlightMcs;
  final RvrStageStyle style;
  final int revision;

  static const double _ringFillAlpha = 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    final RvrStageGeometry g = RvrStageGeometry(size: size, rangeM: rangeM);
    final Offset c = g.center;
    final double maxR = size.longestSide; // anything past this is off screen

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Filled discs, outermost first: each inner disc covers the one before,
    // leaving one flat band per MCS.
    for (final RvrPaintRing r in rings) {
      final double px = r.radiusM * g.pxPerM;
      if (px < 0.5) continue;
      canvas.drawCircle(
        c,
        math.min(px, maxR),
        Paint()
          ..color = Color.alphaBlend(
            r.color.withValues(alpha: _ringFillAlpha),
            style.surface,
          ),
      );
    }
    for (final RvrPaintRing r in rings) {
      final double px = r.radiusM * g.pxPerM;
      if (px < 0.5 || px > maxR) continue;
      final bool hi = r.mcs == highlightMcs;
      canvas.drawCircle(
        c,
        px,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hi ? 3 : 1.5
          ..color = r.color,
      );
    }

    _distanceGrid(canvas, g);
    _cellEdge(canvas, g);
    _ringLabels(canvas, g);
    _ap(canvas, c);
    _client(canvas, g);
    canvas.restore();
  }

  void _distanceGrid(Canvas canvas, RvrStageGeometry g) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = style.grid;
    for (final double f in <double>[0.5, 1]) {
      final double r = g.radiusPx * f;
      _dashedCircle(canvas, g.center, r, p, dash: 2, gap: 4);
      final String label = _meters(rangeM * f);
      final TextPainter tp = _text(label, style.gridLabel);
      // Left of the AP: the client starts up and to the right.
      final Offset at = g.center + Offset(-r + 2, 2);
      _knockout(canvas, at, tp);
    }
  }

  void _cellEdge(Canvas canvas, RvrStageGeometry g) {
    final double r = cellEdgeM * g.pxPerM;
    if (r < 1 || r > g.size.longestSide) return;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = style.edge;
    _dashedCircle(canvas, g.center, r, p, dash: 8, gap: 5);
    final TextPainter tp = _text(cellEdgeLabel, style.edgeLabel);
    Offset at = g.center + Offset(-tp.width / 2, r + 4);
    if (at.dy + tp.height > g.size.height) {
      at = g.center + Offset(-tp.width / 2, r - tp.height - 4);
    }
    if (at.dy + tp.height <= g.size.height && at.dy >= 0) {
      _knockout(canvas, at, tp);
    }
  }

  /// "MCS n" at the top of each band where it fits between this ring and the
  /// next one in. The legend lists every ring regardless.
  void _ringLabels(Canvas canvas, RvrStageGeometry g) {
    double lastTop = double.infinity; // y of the previous label's top edge
    for (int i = 0; i < rings.length; i++) {
      final double outer = rings[i].radiusM * g.pxPerM;
      final double inner = i + 1 < rings.length
          ? rings[i + 1].radiusM * g.pxPerM
          : 0;
      final TextPainter tp = _text('${rings[i].mcs}', style.ringLabel);
      if (outer - inner < tp.height + 2) continue;
      final double mid = (outer + inner) / 2;
      if (mid < 16) continue; // would sit on the AP marker
      final Offset at = g.center + Offset(-tp.width / 2, -mid - tp.height / 2);
      if (at.dy < 0) continue;
      if (at.dy + tp.height > lastTop - 1) continue;
      tp.paint(canvas, at);
      lastTop = at.dy;
    }
  }

  void _ap(Canvas canvas, Offset c) {
    final Rect r = Rect.fromCenter(center: c, width: 12, height: 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(2)),
      Paint()..color = style.ap,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.inflate(1.5), const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = style.surface,
    );
    final TextPainter tp = _text('AP', style.clientLabel);
    _knockout(canvas, c + Offset(-tp.width / 2, 9), tp);
  }

  void _client(Canvas canvas, RvrStageGeometry g) {
    final Offset p = g.pointAt(clientDistanceM, clientAngle);
    _dashedLine(
      canvas,
      g.center,
      p,
      Paint()
        ..strokeWidth = 1.5
        ..color = style.client,
    );
    canvas.drawCircle(p, 9, Paint()..color = style.clientRim);
    canvas.drawCircle(p, 7, Paint()..color = style.client);

    final TextPainter tp = _text(clientLabel, style.clientLabel);
    // Put the label on the side of the dot away from the AP, kept on screen.
    final bool right = p.dx >= g.center.dx;
    double x = right ? p.dx + 12 : p.dx - 12 - tp.width;
    double y = p.dy - tp.height / 2;
    x = x.clamp(2, math.max(2, g.size.width - tp.width - 2));
    y = y.clamp(2, math.max(2, g.size.height - tp.height - 2));
    _knockout(canvas, Offset(x, y), tp);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  static String _meters(double m) => m >= 1000
      ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km'
      : '${m.round()} m';

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
      Paint()..color = style.surface.withValues(alpha: 0.85),
    );
    tp.paint(canvas, at);
  }

  void _dashedCircle(
    Canvas canvas,
    Offset c,
    double r,
    Paint p, {
    required double dash,
    required double gap,
  }) {
    final ui.Path path = ui.Path()
      ..addOval(Rect.fromCircle(center: c, radius: r));
    for (final ui.PathMetric m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint p) {
    final double len = (b - a).distance;
    if (len < 1) return;
    final Offset dir = (b - a) / len;
    double d = 0;
    while (d < len) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + 4, len), p);
      d += 8;
    }
  }

  @override
  bool shouldRepaint(RvrStagePainter old) =>
      old.revision != revision || old.style != style;
}
