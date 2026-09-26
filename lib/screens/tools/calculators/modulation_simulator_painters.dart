// Painters for the Wi-Fi Lab Modulation Simulator (modulation-simulator).
//
// Two token-only CustomPainters, following the metric_sparkline.dart idiom:
// every color arrives as a constructor argument resolved from
// context.colors by the screen, so both painters are correct in dark (§8) and
// light (§8.20) without knowing which theme they are in. Both are wrapped in
// `Semantics(excludeSemantics: true)` by the screen, which supplies a worded
// label; the painters themselves carry no information that is not also in
// text.
//
// Color roles (GL-003 §8.15 case 3 + §8.13 rule 6):
//   * received points and the bold carrier are the measured quantity, so they
//     take the lime foreground (`textAccent`, darkened lime on light);
//   * ideal points, axes and I/Q component traces are neutral text/border
//     tokens, told apart by size and dash, not hue;
//   * a point the receiver decided WRONG is a computed verdict and takes
//     `statusDanger`, drawn as an X so shape carries it as well as color.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Resolved colors and text styles for [ConstellationPainter].
@immutable
class ConstellationStyle {
  const ConstellationStyle({
    required this.ideal,
    required this.received,
    required this.error,
    required this.boundary,
    required this.axis,
    required this.highlight,
    required this.labelStyle,
    required this.axisLabelStyle,
    this.scale = PresenterScale.normal,
  });

  final Color ideal;
  final Color received;
  final Color error;
  final Color boundary;
  final Color axis;
  final Color highlight;
  final TextStyle labelStyle;
  final TextStyle axisLabelStyle;

  /// Presenter scale for strokes and markers (1.0 outside presenter mode).
  /// Label font sizes arrive already scaled in [labelStyle].
  final PresenterScale scale;
}

/// Draws the I/Q plane: decision boundaries, ideal points (optionally with
/// their bit labels), the received cloud, the current symbol and its error
/// vector, and an optional probed point.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.modulation,
    required this.ideal,
    required this.cloud,
    required this.current,
    required this.probe,
    required this.showBitLabels,
    required this.style,
    required this.revision,
  });

  final Modulation modulation;
  final List<ConstellationPoint> ideal;
  final List<SimulatedSymbol> cloud;
  final SimulatedSymbol? current;
  final ConstellationPoint? probe;
  final bool showBitLabels;
  final ConstellationStyle style;

  /// Bumped by the screen on every simulated symbol so repaint is cheap to
  /// decide without diffing the cloud.
  final int revision;

  /// Half-width of the plotted square in normalized units: the outer decision
  /// edge plus half a level spacing of margin, so received points just past
  /// the edge are still visible before they clamp.
  static double plotRange(Modulation m) {
    final double k = ModulationMath.kMod(m);
    return (m.levelsPerAxis + 0.5) * k;
  }

  /// Canvas position for normalized (i, q). Q grows upward.
  static Offset toCanvas(double i, double q, Size size, Modulation m) {
    final double r = plotRange(m);
    final double side = math.min(size.width, size.height);
    final double ox = (size.width - side) / 2;
    final double oy = (size.height - side) / 2;
    final double x = ox + (i.clamp(-r, r) + r) / (2 * r) * side;
    final double y = oy + (r - q.clamp(-r, r)) / (2 * r) * side;
    return Offset(x, y);
  }

  /// Normalized (i, q) for a canvas position (inverse of [toCanvas]).
  static ({double i, double q}) toIq(Offset p, Size size, Modulation m) {
    final double r = plotRange(m);
    final double side = math.min(size.width, size.height);
    final double ox = (size.width - side) / 2;
    final double oy = (size.height - side) / 2;
    final double i = (p.dx - ox) / side * 2 * r - r;
    final double q = r - (p.dy - oy) / side * 2 * r;
    return (i: i, q: q);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Modulation m = modulation;
    final double k = ModulationMath.kMod(m);
    final int levels = m.levelsPerAxis;
    final PresenterScale sc = style.scale;
    final double side = math.min(size.width, size.height);
    final double spacingPx = side / (2 * plotRange(m)) * 2 * k;

    // Decision boundaries: midway between adjacent levels (even multiples of
    // K_MOD). Hairlines in the decorative border token; the I and Q axes are
    // drawn stronger on top because they are also the zero lines.
    final Paint boundary = Paint()
      ..color = style.boundary
      ..strokeWidth = sc.strokeWidth(1);
    final double edge = levels * k;
    for (int b = -(levels - 2); b <= levels - 2; b += 2) {
      if (b == 0) continue;
      final double v = b * k;
      canvas.drawLine(
        toCanvas(v, -edge, size, m),
        toCanvas(v, edge, size, m),
        boundary,
      );
      if (!m.isBpsk) {
        canvas.drawLine(
          toCanvas(-edge, v, size, m),
          toCanvas(edge, v, size, m),
          boundary,
        );
      }
    }
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = sc.strokeWidth(1);
    final double r = plotRange(m);
    canvas.drawLine(toCanvas(-r, 0, size, m), toCanvas(r, 0, size, m), axis);
    canvas.drawLine(toCanvas(0, -r, size, m), toCanvas(0, r, size, m), axis);
    _axisLabel(canvas, 'I', toCanvas(r, 0, size, m), alignRight: true);
    _axisLabel(canvas, 'Q', toCanvas(0, r, size, m), alignRight: false);

    // Ideal points. Dot size follows the grid spacing so 4096-QAM still
    // resolves and BPSK does not look like a pinprick.
    final double idealR = sc.markerSize((spacingPx * 0.14).clamp(1.0, 4.0));
    final Paint idealPaint = Paint()..color = style.ideal;
    for (final ConstellationPoint p in ideal) {
      canvas.drawCircle(toCanvas(p.i, p.q, size, m), idealR, idealPaint);
    }
    if (showBitLabels) {
      for (final ConstellationPoint p in ideal) {
        _pointLabel(
          canvas,
          ModulationMath.bitString(p.symbol, m.bitsPerSymbol),
          toCanvas(p.i, p.q, size, m),
          idealR,
        );
      }
    }

    // Received cloud.
    final double rxR = sc.markerSize((spacingPx * 0.09).clamp(1.2, 3.0));
    final Paint rxPaint = Paint()..color = style.received;
    final Paint errPaint = Paint()
      ..color = style.error
      ..strokeWidth = sc.strokeWidth(1.5)
      ..strokeCap = StrokeCap.round;
    for (final SimulatedSymbol s in cloud) {
      final Offset c = toCanvas(s.receivedI, s.receivedQ, size, m);
      if (s.isSymbolError) {
        final double x = rxR + 1;
        canvas.drawLine(c.translate(-x, -x), c.translate(x, x), errPaint);
        canvas.drawLine(c.translate(-x, x), c.translate(x, -x), errPaint);
      } else {
        canvas.drawCircle(c, rxR, rxPaint);
      }
    }

    // Current symbol: ring on the ideal point, the error vector to where it
    // actually landed, and a larger received dot.
    final SimulatedSymbol? cur = current;
    if (cur != null) {
      final Offset ideal0 = toCanvas(cur.sent.i, cur.sent.q, size, m);
      final Offset rx = toCanvas(cur.receivedI, cur.receivedQ, size, m);
      final Paint ring = Paint()
        ..color = style.highlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(2);
      canvas.drawCircle(ideal0, idealR + sc.markerSize(4), ring);
      canvas.drawLine(
        ideal0,
        rx,
        Paint()
          ..color = style.highlight
          ..strokeWidth = sc.strokeWidth(1.5),
      );
      canvas.drawCircle(
        rx,
        rxR + sc.markerSize(2),
        Paint()..color = cur.isSymbolError ? style.error : style.received,
      );
      canvas.drawCircle(
        rx,
        rxR + sc.markerSize(2),
        Paint()
          ..color = style.highlight
          ..style = PaintingStyle.stroke
          ..strokeWidth = sc.strokeWidth(1),
      );
    }

    // Probed point (tap or hover), for orders too dense to label every point.
    final ConstellationPoint? pr = probe;
    if (pr != null && !showBitLabels) {
      final Offset c = toCanvas(pr.i, pr.q, size, m);
      canvas.drawCircle(
        c,
        idealR + sc.markerSize(3),
        Paint()
          ..color = style.highlight
          ..style = PaintingStyle.stroke
          ..strokeWidth = sc.strokeWidth(1.5),
      );
    }
  }

  void _pointLabel(Canvas canvas, String text, Offset at, double dotR) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style.labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at.translate(-tp.width / 2, dotR + 2));
  }

  void _axisLabel(
    Canvas canvas,
    String text,
    Offset at, {
    required bool alignRight,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: style.axisLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final Offset o = alignRight
        ? at.translate(-tp.width - 2, -tp.height - 2)
        : at.translate(4, 0);
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(ConstellationPainter old) =>
      old.revision != revision ||
      old.modulation != modulation ||
      old.probe?.symbol != probe?.symbol ||
      old.showBitLabels != showBitLabels ||
      old.style != style;
}

/// Resolved colors for [WaveformPainter].
@immutable
class WaveformStyle {
  const WaveformStyle({
    required this.iTrace,
    required this.qTrace,
    required this.sum,
    required this.boundary,
    required this.baseline,
    required this.currentBar,
    this.scale = PresenterScale.normal,
  });

  final Color iTrace;
  final Color qTrace;
  final Color sum;
  final Color boundary;
  final Color baseline;
  final Color currentBar;

  /// Presenter scale for strokes (1.0 outside presenter mode).
  final PresenterScale scale;
}

/// Draws the carrier for a run of symbols: [cyclesPerSymbol] cycles each, the
/// I component (I cos) as a thin solid trace, the Q component (-Q sin) as a
/// thin dashed trace, and their sum as the bold carrier. Symbol boundaries are
/// vertical rules; the newest (current) symbol gets a bar along its top.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.symbols,
    required this.slots,
    required this.maxAmplitude,
    required this.style,
    required this.revision,
    this.cyclesPerSymbol = 3,
  });

  /// Symbols to draw, oldest first; at most [slots] of them.
  final List<ConstellationPoint> symbols;

  /// Number of symbol slots across the strip.
  final int slots;

  /// Amplitude that maps to the full half-height (the modulation's corner
  /// point), so every symbol of a modulation shares one scale.
  final double maxAmplitude;

  final WaveformStyle style;
  final int revision;
  final int cyclesPerSymbol;

  static const int _samplesPerCycle = 32;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale sc = style.scale;
    final double mid = size.height / 2;
    final double amp = (size.height / 2) * 0.88;
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = style.baseline
        ..strokeWidth = sc.strokeWidth(1),
    );
    if (symbols.isEmpty || slots <= 0) return;

    final double slotW = size.width / slots;
    final Paint boundary = Paint()
      ..color = style.boundary
      ..strokeWidth = sc.strokeWidth(1);
    for (int s = 1; s < slots; s++) {
      canvas.drawLine(
        Offset(s * slotW, 0),
        Offset(s * slotW, size.height),
        boundary,
      );
    }

    // Right-align: the newest symbol always sits in the last slot.
    final int first = slots - symbols.length;
    final double scale = maxAmplitude <= 0 ? 0 : amp / maxAmplitude;

    final Path iPath = Path();
    final Path sumPath = Path();
    final List<List<Offset>> qDashes = <List<Offset>>[];
    const int n = _samplesPerCycle;

    for (int idx = 0; idx < symbols.length; idx++) {
      final ConstellationPoint p = symbols[idx];
      final double x0 = (first + idx) * slotW;
      final int total = cyclesPerSymbol * n;
      List<Offset>? dash;
      for (int t = 0; t <= total; t++) {
        final double frac = t / total;
        final double theta = 2 * math.pi * cyclesPerSymbol * frac;
        final double x = x0 + frac * slotW;
        final double yi = mid - p.i * math.cos(theta) * scale;
        final double yq = mid + p.q * math.sin(theta) * scale; // -Q sin
        final double ys = mid - ModulationMath.carrier(p.i, p.q, theta) * scale;
        if (t == 0) {
          iPath.moveTo(x, yi);
          if (idx == 0) {
            sumPath.moveTo(x, ys);
          } else {
            sumPath.lineTo(x, ys);
          }
        } else {
          iPath.lineTo(x, yi);
          sumPath.lineTo(x, ys);
        }
        // Dashes: alternate 4-sample runs on and off.
        final bool on = (t ~/ 4).isEven;
        if (on) {
          dash ??= <Offset>[];
          dash.add(Offset(x, yq));
        } else if (dash != null) {
          qDashes.add(dash);
          dash = null;
        }
      }
      if (dash != null) qDashes.add(dash);
    }

    canvas.drawPath(
      iPath,
      Paint()
        ..color = style.iTrace
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1),
    );
    final Paint qPaint = Paint()
      ..color = style.qTrace
      ..style = PaintingStyle.stroke
      ..strokeWidth = sc.strokeWidth(1);
    for (final List<Offset> d in qDashes) {
      if (d.length < 2) continue;
      canvas.drawPath(Path()..addPolygon(d, false), qPaint);
    }
    canvas.drawPath(
      sumPath,
      Paint()
        ..color = style.sum
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(2.5)
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Current (newest) symbol marker: a filled bar along the top of its slot.
    canvas.drawRect(
      Rect.fromLTWH((slots - 1) * slotW, 0, slotW, sc.strokeWidth(3)),
      Paint()..color = style.currentBar,
    );
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.revision != revision ||
      old.slots != slots ||
      old.maxAmplitude != maxAmplitude ||
      old.style != style;
}
