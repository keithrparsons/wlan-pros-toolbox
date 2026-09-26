// Painters for part 2 of the Wi-Fi Lab "Fourier and FFT" tool (fourier-fft).
//
//   - WaterfallPainter (mode 3): frequency across, time up (newest at the
//     top, GL-003 §8.22), each cell a flat fill of the §8.22 analyzer
//     rainbow. The data area is dark navy in both themes; axis labels sit
//     outside it in theme colors. The swept analyzer's tuned frequency is
//     drawn as a lime diagonal (one per sweep), the §8.22 "non-trace accent
//     stays lime" rule, over a navy halo so it reads on yellow and green.
//   - OfdmTimePainter (mode 4): s(t) from the start of the cyclic prefix,
//     I and Q, with the prefix shaded and the tail it was copied from marked.
//   - OfdmSpectrumPainter (mode 4): each subcarrier's sinc against frequency
//     offset from the channel center, the highlighted one in lime, with its
//     zeros marked at every other subcarrier's center.
//   - OfdmConstellationPainter (mode 4): the ideal grid, the sent points and
//     what the receiver's FFT got back.
//
// Every non-rainbow color arrives in FourierPlotStyle, built from
// context.colors. The rainbow comes from AppAnalyzerRainbow only.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../services/wifi_lab/fourier_ofdm.dart';
import '../../../services/wifi_lab/fourier_race.dart';
import '../../../theme/app_analyzer_rainbow.dart';
import 'fourier_fft_painters.dart';

double _niceStep(double span, int targetTicks) {
  final double raw = span / targetTicks;
  final double mag = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final double r = raw / mag;
  final double nice = r < 1.5
      ? 1
      : r < 3
      ? 2
      : r < 7
      ? 5
      : 10;
  return nice * mag;
}

void _label(
  Canvas canvas,
  String s,
  TextStyle style,
  Offset at, {
  bool alignRight = false,
  bool center = false,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  double dx = at.dx;
  if (alignRight) dx -= tp.width;
  if (center) dx -= tp.width / 2;
  tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
}

String _trimNum(double v, int decimals) {
  String s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s == '-0' ? '0' : s;
}

// ── Mode 3: waterfall ──────────────────────────────────────────────────────

/// Most sweep lines drawn before the path is too dense to be worth drawing.
const int kMaxSweepLinesDrawn = 24;

class WaterfallPainter extends CustomPainter {
  WaterfallPainter({
    required this.run,
    required this.grid,
    required this.progress,
    required this.style,
    required this.revision,
    this.showSweepPath = true,
  });

  final RaceRun run;

  /// Row-major dBm, NaN = never looked at.
  final Float32List grid;

  /// 0 .. 1 of the rows revealed.
  final double progress;
  final FourierPlotStyle style;
  final int revision;
  final bool showSweepPath;

  static const double left = 34;
  static const double top = 16;
  static const double bottom = 20;
  static const double right = 6;

  /// Channel 1, 6 and 11 centers (2.4 GHz).
  static const List<(String, double)> _channels = <(String, double)>[
    ('1', 2412),
    ('6', 2437),
    ('11', 2462),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      style.t(left),
      style.t(top),
      size.width - right,
      size.height - style.t(bottom),
    );
    final double start = run.swept.startMhz;
    final double span = run.swept.spanMhz;
    final double runS = run.runSeconds;
    double x(double mhz) => plot.left + (mhz - start) / span * plot.width;
    double y(double t) => plot.bottom - t / runS * plot.height;

    // Data area.
    canvas.drawRect(plot, Paint()..color = AppAnalyzerRainbow.viewport);

    final int rows = run.rows;
    final int cols = run.cols;
    final int shown = (progress * rows).ceil().clamp(0, rows);
    final double cw = plot.width / cols;
    final double rh = plot.height / rows;
    final List<Paint> fills = <Paint>[
      for (final Color c in AppAnalyzerRainbow.stops) Paint()..color = c,
    ];
    for (int r = 0; r < shown; r++) {
      final double y1 = plot.bottom - r * rh;
      final double y0 = y1 - rh;
      int c = 0;
      while (c < cols) {
        final int s = AppAnalyzerRainbow.stopFor(
          grid[r * cols + c],
          floorDbm: RaceRun.noiseFloorDbm,
          topDbm: RaceRun.topDbm,
        );
        int e = c + 1;
        while (e < cols &&
            AppAnalyzerRainbow.stopFor(
                  grid[r * cols + e],
                  floorDbm: RaceRun.noiseFloorDbm,
                  topDbm: RaceRun.topDbm,
                ) ==
                s) {
          e++;
        }
        if (s != 0) {
          // Overlap by a hair so no seam shows between merged runs.
          canvas.drawRect(
            Rect.fromLTRB(
              plot.left + c * cw,
              y0 - 0.25,
              plot.left + e * cw + 0.25,
              y1,
            ),
            fills[s],
          );
        }
        c = e;
      }
    }

    // Swept analyzer's tuned frequency: one diagonal per sweep.
    final double st = run.swept.sweepSeconds;
    final double elapsed = progress * runS;
    if (showSweepPath && runS / st <= kMaxSweepLinesDrawn) {
      canvas.save();
      canvas.clipRect(plot);
      final Paint halo = Paint()
        ..color = AppAnalyzerRainbow.annotationHalo
        ..strokeWidth = style.w(3)
        ..strokeCap = StrokeCap.round;
      final Paint line = Paint()
        ..color = AppAnalyzerRainbow.annotation
        ..strokeWidth = style.w(1.5)
        ..strokeCap = StrokeCap.round;
      for (int m = 0; m * st < elapsed; m++) {
        final double t0 = m * st;
        final double t1 = math.min((m + 1) * st, elapsed);
        final Offset a = Offset(x(start), y(t0));
        final Offset b = Offset(x(start + span * (t1 - t0) / st), y(t1));
        canvas.drawLine(a, b, halo);
        canvas.drawLine(a, b, line);
      }
      canvas.restore();
    }

    // Frame.
    canvas.drawRect(
      plot,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.w(1),
    );

    // Frequency axis (MHz) below.
    final double fStep = _niceStep(span, 4);
    final double first = (start / fStep).ceil() * fStep;
    for (double f = first; f <= start + span + 1e-6; f += fStep) {
      final double px = x(f);
      canvas.drawLine(
        Offset(px, plot.bottom),
        Offset(px, plot.bottom + 3),
        Paint()
          ..color = style.axis
          ..strokeWidth = style.w(1),
      );
      if (px < plot.right - 26 && px > plot.left + 10) {
        _label(
          canvas,
          _trimNum(f, 0),
          style.labelStyle,
          Offset(px, plot.bottom + 11),
          center: true,
        );
      }
    }
    _label(
      canvas,
      'MHz',
      style.labelStyle,
      Offset(plot.right, plot.bottom + 11),
      alignRight: true,
    );

    // Channel markers above.
    for (final (String name, double f) in _channels) {
      if (f < start || f > start + span) continue;
      final double px = x(f);
      canvas.drawLine(
        Offset(px, plot.top - 3),
        Offset(px, plot.top),
        Paint()
          ..color = style.marker
          ..strokeWidth = style.w(1.5),
      );
      _label(
        canvas,
        'Ch $name',
        style.labelStyle,
        Offset(px, plot.top - 9),
        center: true,
      );
    }

    // Time axis (ms): 0 at the bottom, the run's end at the top.
    final double tStep = _niceStep(runS, 3);
    for (double t = 0; t <= runS + 1e-9; t += tStep) {
      final double py = y(t);
      _label(
        canvas,
        _trimNum(t * 1000, t * 1000 < 10 ? 1 : 0),
        style.labelStyle,
        Offset(plot.left - 4, py),
        alignRight: true,
      );
    }
    // The unit (ms) is stated in the stage caption: a corner label here
    // collided with the top tick.
  }

  @override
  bool shouldRepaint(WaterfallPainter old) =>
      old.revision != revision ||
      old.run != run ||
      old.progress != progress ||
      old.style != style ||
      old.showSweepPath != showSweepPath;
}

// ── Mode 4: OFDM ───────────────────────────────────────────────────────────

/// s(t) from the start of the cyclic prefix. [axisSeconds] fixes the time
/// axis (16 us keeps legacy and HE on one scale); the symbol fills
/// [symbol.totalSeconds] of it.
class OfdmTimePainter extends CustomPainter {
  OfdmTimePainter({
    required this.symbol,
    required this.axisSeconds,
    required this.style,
    required this.revision,
    required this.cpFill,
  });

  final OfdmSymbol symbol;
  final double axisSeconds;
  final FourierPlotStyle style;
  final int revision;

  /// Shade behind the cyclic prefix (a neutral surface step).
  final Color cpFill;

  static const double _left = 30;
  static const double _bottom = 18;
  static const double _top = 16;

  /// Horizontal space the painter takes for margins.
  static const double horizontalMargins = _left + 6;

  /// True when the IFFT samples are at least 5 px apart on a plot
  /// [plotWidth] wide, so they are drawn as dots. The stage words its caption
  /// with the same rule.
  static bool dotsFit(OfdmSymbol s, double axisSeconds, double plotWidth) =>
      s.usefulSeconds / s.n / axisSeconds * plotWidth >= 5;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      style.t(_left),
      style.t(_top),
      size.width - 6,
      size.height - style.t(_bottom),
    );
    final double gi = symbol.guardSeconds;
    final double total = symbol.totalSeconds;
    final double tUseful = symbol.usefulSeconds;
    double x(double tp) => plot.left + tp / axisSeconds * plot.width;

    // Curve first (to find its peak for the y scale).
    final int points = math.max(200, (plot.width * 1.5).round());
    final List<({double re, double im})> vals = <({double re, double im})>[];
    double peak = 1e-9;
    for (int i = 0; i <= points; i++) {
      final double tp = i / points * total;
      final ({double re, double im}) v = symbol.valueAt(tp - gi);
      vals.add(v);
      peak = math.max(peak, math.max(v.re.abs(), v.im.abs()));
    }
    final double yMax = peak * 1.1;
    double y(double v) => plot.center.dy - v / yMax * plot.height / 2;

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = style.w(1);
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = style.w(1);

    // CP shade and the tail it was copied from.
    final Rect cp = Rect.fromLTRB(x(0), plot.top, x(gi), plot.bottom);
    canvas.drawRect(cp, Paint()..color = cpFill);
    final Rect tail = Rect.fromLTRB(
      x(gi + tUseful - gi),
      plot.top,
      x(total),
      plot.bottom,
    );
    _dashedRect(
      canvas,
      tail,
      Paint()
        ..color = style.window
        ..strokeWidth = style.w(1.2),
    );
    _label(
      canvas,
      'CP',
      style.labelStyle,
      Offset(cp.center.dx, plot.top - 8),
      center: true,
    );
    _label(
      canvas,
      'copied',
      style.labelStyle,
      Offset(tail.center.dx, plot.top - 8),
      center: true,
    );

    // Zero line, the symbol's end, and time ticks (us).
    canvas.drawLine(Offset(plot.left, y(0)), Offset(plot.right, y(0)), axis);
    canvas.drawLine(
      Offset(x(total), plot.top),
      Offset(x(total), plot.bottom),
      axis,
    );
    final double step = _niceStep(axisSeconds * 1e6, 4) / 1e6;
    for (double t = 0; t <= axisSeconds + step * 1e-6; t += step) {
      final double px = x(t);
      canvas.drawLine(
        Offset(px, plot.bottom),
        Offset(px, plot.bottom + 3),
        grid,
      );
      if (px < plot.right - 22) {
        _label(
          canvas,
          _trimNum(t * 1e6, 1),
          style.labelStyle,
          Offset(px, plot.bottom + 10),
          center: t > 0,
        );
      }
    }
    _label(
      canvas,
      'µs',
      style.labelStyle,
      Offset(plot.right, plot.bottom + 10),
      alignRight: true,
    );

    canvas.save();
    canvas.clipRect(plot.inflate(1));
    // Q first (quiet), then I (the measured quantity, lime).
    Path trace(double Function(({double re, double im})) pick) {
      final Path p = Path();
      for (int i = 0; i <= points; i++) {
        final Offset o = Offset(x(i / points * total), y(pick(vals[i])));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p;
    }

    canvas.drawPath(
      trace((({double re, double im}) v) => v.im),
      Paint()
        ..color = style.component
        ..strokeWidth = style.w(1.2)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      trace((({double re, double im}) v) => v.re),
      Paint()
        ..color = style.signal
        ..strokeWidth = style.w(2)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // The IFFT's outputs are samples of this curve: dots on I when they fit.
    final ({Float64List re, Float64List im}) tx = symbol.withCyclicPrefix();
    final int count = tx.re.length;
    final double ts = tUseful / symbol.n;
    if (count > 0 && dotsFit(symbol, axisSeconds, plot.width)) {
      final Paint dot = Paint()..color = style.signal;
      final Paint ring = Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.w(1);
      for (int i = 0; i < count; i++) {
        final Offset o = Offset(x(i * ts), y(tx.re[i]));
        canvas.drawCircle(o, style.m(3), dot);
        canvas.drawCircle(o, style.m(3), ring);
      }
    }
    canvas.restore();
    canvas.drawRect(plot, axis..style = PaintingStyle.stroke);
  }

  void _dashedRect(Canvas canvas, Rect r, Paint p) {
    const double dash = 4;
    const double gap = 3;
    void seg(Offset a, Offset b) {
      final double len = (b - a).distance;
      final Offset dir = (b - a) / len;
      for (double s = 0; s < len; s += dash + gap) {
        canvas.drawLine(a + dir * s, a + dir * math.min(len, s + dash), p);
      }
    }

    seg(r.topLeft, r.topRight);
    seg(r.topRight, r.bottomRight);
    seg(r.bottomRight, r.bottomLeft);
    seg(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(OfdmTimePainter old) =>
      old.revision != revision ||
      old.style != style ||
      old.axisSeconds != axisSeconds ||
      old.symbol != symbol;
}

/// Each active subcarrier's sinc, drawn with its point's phase removed so
/// the shapes line up: |X_k| sinc((f - k df) / df). The highlighted one is
/// lime; small rings mark where it crosses zero at the other centers.
class OfdmSpectrumPainter extends CustomPainter {
  OfdmSpectrumPainter({
    required this.symbol,
    required this.highlight,
    required this.halfSpanHz,
    required this.style,
    required this.revision,
  });

  final OfdmSymbol symbol;
  final int? highlight;

  /// The x axis runs from -halfSpanHz to +halfSpanHz around the channel
  /// center, the same in legacy and HE.
  final double halfSpanHz;
  final FourierPlotStyle style;
  final int revision;

  static const double _left = 30;
  static const double _bottom = 20;

  /// Below this many pixels between subcarriers, only the highlighted sinc
  /// is drawn (the rest would be a smear).
  static const double minSpacingForAll = 8;

  bool drawsEverySinc(double plotWidth) =>
      symbol.spacingHz / (2 * halfSpanHz) * plotWidth >= minSpacingForAll;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      style.t(_left),
      6,
      size.width - 6,
      size.height - style.t(_bottom),
    );
    final double df = symbol.spacingHz;
    double peakAmp = 1e-9;
    symbol.points.forEach((int k, ConstellationPoint p) {
      peakAmp = math.max(peakAmp, p.amplitude);
    });
    final double yTop = peakAmp * 1.1;
    final double yBottom = -peakAmp * 0.35;
    double x(double hz) =>
        plot.left + (hz + halfSpanHz) / (2 * halfSpanHz) * plot.width;
    double y(double v) =>
        plot.top + (yTop - v) / (yTop - yBottom) * plot.height;

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = style.w(1);
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = style.w(1);

    // Frequency ticks (MHz from the channel center).
    final double stepHz = _niceStep(2 * halfSpanHz / 1e6, 4) * 1e6;
    final double firstHz = (-halfSpanHz / stepHz).ceil() * stepHz;
    for (double f = firstHz; f <= halfSpanHz + 1e-3; f += stepHz) {
      final double px = x(f);
      canvas.drawLine(
        Offset(px, plot.bottom),
        Offset(px, plot.bottom + 3),
        axis,
      );
      if (px < plot.right - 26) {
        _label(
          canvas,
          _trimNum(f / 1e6, 3),
          style.labelStyle,
          Offset(px, plot.bottom + 11),
          center: true,
        );
      }
    }
    _label(
      canvas,
      'MHz',
      style.labelStyle,
      Offset(plot.right, plot.bottom + 11),
      alignRight: true,
    );

    final List<int> ks = symbol.indices;
    // Center lines at each active subcarrier.
    for (final int k in ks) {
      final double px = x(k * df);
      if (px < plot.left || px > plot.right) continue;
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), grid);
    }
    // Channel center (the carrier): a stronger rule.
    canvas.drawLine(
      Offset(x(0), plot.top),
      Offset(x(0), plot.bottom),
      Paint()
        ..color = style.marker
        ..strokeWidth = style.w(1.5),
    );
    canvas.drawLine(Offset(plot.left, y(0)), Offset(plot.right, y(0)), axis);
    _label(
      canvas,
      '0',
      style.labelStyle,
      Offset(plot.left - 4, y(0)),
      alignRight: true,
    );
    _label(
      canvas,
      _trimNum(peakAmp, 2),
      style.labelStyle,
      Offset(plot.left - 4, y(peakAmp)),
      alignRight: true,
    );

    canvas.save();
    canvas.clipRect(plot);
    final int pts = math.max(300, (plot.width * 2).round());
    Path sincPath(int k, double amp) {
      final Path p = Path();
      for (int i = 0; i <= pts; i++) {
        final double f = -halfSpanHz + i / pts * 2 * halfSpanHz;
        final double v = amp * OfdmMath.subcarrierSpectrum(k, f, df);
        final Offset o = Offset(x(f), y(v));
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p;
    }

    final bool every = drawsEverySinc(plot.width);
    if (every) {
      final Paint each = Paint()
        ..color = style.component
        ..strokeWidth = style.w(1.2)
        ..style = PaintingStyle.stroke;
      for (final int k in ks) {
        if (k == highlight) continue;
        canvas.drawPath(sincPath(k, symbol.points[k]!.amplitude), each);
      }
    }
    final int? h = highlight;
    if (h != null) {
      final double amp = symbol.points[h]!.amplitude;
      canvas.drawPath(
        sincPath(h, amp),
        Paint()
          ..color = style.signal
          ..strokeWidth = style.w(2.5)
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        Offset(x(h * df), y(amp)),
        style.m(4),
        Paint()..color = style.signal,
      );
      // Its zeros at every other active center, when they are far enough
      // apart to tell apart (otherwise the rings merge into a bar).
      if (!every) {
        canvas.restore();
        canvas.drawRect(plot, axis..style = PaintingStyle.stroke);
        return;
      }
      final Paint ring = Paint()
        ..color = style.signal
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.w(1.5);
      for (final int k in ks) {
        if (k == h) continue;
        final double px = x(k * df);
        if (px < plot.left || px > plot.right) continue;
        canvas.drawCircle(Offset(px, y(0)), style.m(3.5), ring);
      }
    }
    canvas.restore();
    canvas.drawRect(plot, axis..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(OfdmSpectrumPainter old) =>
      old.revision != revision ||
      old.style != style ||
      old.highlight != highlight ||
      old.halfSpanHz != halfSpanHz ||
      old.symbol != symbol;
}

/// The modulation's ideal grid (quiet), the sent points (lime rings) and the
/// receiver's recovered points (solid dots).
class OfdmConstellationPainter extends CustomPainter {
  OfdmConstellationPainter({
    required this.modulation,
    required this.sent,
    required this.recovered,
    required this.style,
    required this.revision,
  });

  final Modulation modulation;
  final List<ConstellationPoint> sent;
  final List<RecoveredPoint> recovered;
  final FourierPlotStyle style;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Rect plot = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side - 4,
      height: side - 4,
    );
    final double lim = ModulationMath.maxAmplitude(modulation) * 1.25;
    Offset at(double i, double q) => Offset(
      plot.center.dx + i / lim * plot.width / 2,
      plot.center.dy - q / lim * plot.height / 2,
    );
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = style.w(1);
    canvas.drawLine(plot.centerLeft, plot.centerRight, axis);
    canvas.drawLine(plot.topCenter, plot.bottomCenter, axis);
    _label(
      canvas,
      'I',
      style.labelStyle,
      plot.centerRight + const Offset(-6, -8),
    );
    _label(canvas, 'Q', style.labelStyle, plot.topCenter + const Offset(5, 6));

    final double r = modulation.points > 256
        ? 1
        : modulation.points > 16
        ? 1.5
        : 2.5;
    final Paint gridDot = Paint()..color = style.grid;
    for (final ConstellationPoint p in ModulationMath.constellation(
      modulation,
    )) {
      canvas.drawCircle(at(p.i, p.q), style.m(r), gridDot);
    }
    final Paint ring = Paint()
      ..color = style.signal
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.w(2);
    for (final ConstellationPoint p in sent) {
      canvas.drawCircle(at(p.i, p.q), style.m(6), ring);
    }
    final Paint dot = Paint()..color = style.marker;
    for (final RecoveredPoint p in recovered) {
      canvas.drawCircle(at(p.i, p.q), style.m(2.5), dot);
    }
  }

  @override
  bool shouldRepaint(OfdmConstellationPainter old) =>
      old.revision != revision ||
      old.style != style ||
      old.modulation != modulation;
}
