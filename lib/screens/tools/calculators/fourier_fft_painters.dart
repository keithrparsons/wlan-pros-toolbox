// Painters for the Wi-Fi Lab "Fourier and FFT" tool (fourier-fft).
//
// Two plots, shared by every mode:
//   - TimeTracePainter: amplitude against time. Draws the sum in the measured
//     color, optional per-sine traces in a quiet neutral, optional sample dots,
//     and an optional dashed window envelope.
//   - SpectrumPainter: level in dB against frequency, with a floor. Draws
//     either ideal lines (one per sine, mode 1) or the N-bin analyzer output
//     (mode 2), plus neutral tick marks at the true tone frequencies.
//
// Every color arrives in a style object built from context.colors, so these
// files hold no hex values. GL-003 §8.15: no categorical palette, so the sines
// are told apart by position and by the readout rows, never by hue.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Colors and text styles for both plots.
class FourierPlotStyle {
  const FourierPlotStyle({
    required this.signal,
    required this.component,
    required this.window,
    required this.grid,
    required this.axis,
    required this.marker,
    required this.labelStyle,
  });

  /// The measured quantity: the summed trace, the spectrum (lime).
  final Color signal;

  /// Individual sines behind the sum (neutral, quiet).
  final Color component;

  /// The window envelope (neutral, dashed).
  final Color window;

  /// Gridlines.
  final Color grid;

  /// Zero line and plot frame.
  final Color axis;

  /// True-frequency tick marks under the spectrum (neutral).
  final Color marker;

  /// Axis label text.
  final TextStyle labelStyle;
}

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

String _fmtHz(double hz) {
  if (hz >= 1000) {
    final double k = hz / 1000;
    return k == k.roundToDouble()
        ? '${k.toStringAsFixed(0)}k'
        : '${k.toStringAsFixed(1)}k';
  }
  return hz.toStringAsFixed(0);
}

String _fmtMs(double s) {
  final double ms = s * 1000;
  if (ms >= 10) return ms.toStringAsFixed(0);
  if (ms >= 1) return ms.toStringAsFixed(ms == ms.roundToDouble() ? 0 : 1);
  return ms.toStringAsFixed(2);
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

void _dashedPath(Canvas canvas, List<Offset> pts, Paint paint) {
  const double dash = 5;
  const double gap = 4;
  double carry = 0;
  bool on = true;
  for (int i = 1; i < pts.length; i++) {
    final Offset a = pts[i - 1];
    final Offset b = pts[i];
    final double len = (b - a).distance;
    if (len == 0) continue;
    final Offset dir = (b - a) / len;
    double pos = 0;
    while (pos < len) {
      final double seg = (on ? dash : gap) - carry;
      final double end = math.min(len, pos + seg);
      if (on) canvas.drawLine(a + dir * pos, a + dir * end, paint);
      if (end - pos < seg) {
        carry += end - pos;
      } else {
        carry = 0;
        on = !on;
      }
      pos = end;
    }
  }
}

/// Amplitude against time.
///
/// [signalAt] gives the summed signal at time t (seconds). When [samples] is
/// set, the painter draws those instead of [signalAt]: dots when they are at
/// least 4 px apart, a line through them from 1 to 4 px, and below 1 px the
/// min/max range per pixel column (the only truthful drawing at that density).
class TimeTracePainter extends CustomPainter {
  TimeTracePainter({
    required this.durationSeconds,
    required this.yMax,
    required this.style,
    required this.revision,
    this.signalAt,
    this.componentsAt = const <double Function(double)>[],
    this.samples,
    this.windowValues,
  });

  final double durationSeconds;

  /// Top of the y axis (the plot spans -yMax .. +yMax).
  final double yMax;
  final FourierPlotStyle style;

  /// Bump to force a repaint when the inputs change.
  final int revision;

  final double Function(double t)? signalAt;
  final List<double Function(double t)> componentsAt;
  final Float64List? samples;

  /// When set, drawn as a dashed envelope scaled to yMax.
  final Float64List? windowValues;

  static const double _left = 36;
  static const double _bottom = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      _left,
      4,
      size.width - 4,
      size.height - _bottom,
    );
    double x(double t) => plot.left + t / durationSeconds * plot.width;
    double y(double v) =>
        plot.center.dy - (v / yMax).clamp(-1.1, 1.1) * plot.height / 2;

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = 1;

    // Y gridlines at -yMax, 0, +yMax.
    for (final double v in <double>[-yMax, 0, yMax]) {
      canvas.drawLine(
        Offset(plot.left, y(v)),
        Offset(plot.right, y(v)),
        v == 0 ? axis : grid,
      );
      _label(
        canvas,
        v == 0 ? '0' : (v > 0 ? '+' : '-') + _fmtAmp(yMax),
        style.labelStyle,
        Offset(plot.left - 4, y(v)),
        alignRight: true,
      );
    }
    // X ticks in ms.
    final double step = _niceStep(durationSeconds, 4);
    for (double t = 0; t <= durationSeconds + step * 1e-6; t += step) {
      final double px = x(t);
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), grid);
      // Leave the right corner to the unit label.
      if (px < plot.right - 28) {
        _label(
          canvas,
          t == 0 ? '0' : _fmtMs(t),
          style.labelStyle,
          Offset(px, plot.bottom + _bottom / 2),
          center: t > 0,
        );
      }
    }
    _label(
      canvas,
      'ms',
      style.labelStyle,
      Offset(plot.right, plot.bottom + _bottom / 2),
      alignRight: true,
    );

    canvas.save();
    canvas.clipRect(plot.inflate(2));

    final Float64List? w = windowValues;
    if (w != null && w.isNotEmpty) {
      final Paint wp = Paint()
        ..color = style.window
        ..strokeWidth = 1.5;
      final List<Offset> top = <Offset>[];
      final List<Offset> bottom = <Offset>[];
      for (int i = 0; i <= w.length; i++) {
        final double t = i / w.length * durationSeconds;
        final double v = w[i % w.length] * yMax;
        top.add(Offset(x(t), y(v)));
        bottom.add(Offset(x(t), y(-v)));
      }
      _dashedPath(canvas, top, wp);
      _dashedPath(canvas, bottom, wp);
    }

    final int cols = plot.width.ceil();
    if (componentsAt.length > 1) {
      final Paint cp = Paint()
        ..color = style.component
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      for (final double Function(double) f in componentsAt) {
        canvas.drawPath(_curve(f, cols * 2, x, y), cp);
      }
    }

    final Paint sp = Paint()
      ..color = style.signal
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final Float64List? s = samples;
    if (s != null && s.isNotEmpty) {
      final double spacing = plot.width / s.length;
      if (spacing >= 4) {
        final Paint stem = Paint()
          ..color = style.signal.withValues(alpha: 0.5)
          ..strokeWidth = 1;
        final Paint dot = Paint()..color = style.signal;
        for (int i = 0; i < s.length; i++) {
          final double px = x(i / s.length * durationSeconds);
          canvas.drawLine(Offset(px, y(0)), Offset(px, y(s[i])), stem);
          canvas.drawCircle(Offset(px, y(s[i])), spacing >= 8 ? 3 : 2, dot);
        }
      } else if (spacing >= 1) {
        // A line through the samples: close, but still fewer than one per
        // pixel column.
        final Path p = Path();
        for (int i = 0; i < s.length; i++) {
          final Offset o = Offset(x(i / s.length * durationSeconds), y(s[i]));
          if (i == 0) {
            p.moveTo(o.dx, o.dy);
          } else {
            p.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(p, sp..strokeWidth = 1.5);
      } else {
        // More than one sample per pixel column: draw each column's range.
        final Paint band = Paint()
          ..color = style.signal
          ..strokeWidth = 1;
        for (int c = 0; c < cols; c++) {
          final int i0 = (c / cols * s.length).floor();
          final int i1 = math.max(i0 + 1, ((c + 1) / cols * s.length).floor());
          double lo = double.infinity;
          double hi = double.negativeInfinity;
          for (int i = i0; i < math.min(i1 + 1, s.length); i++) {
            lo = math.min(lo, s[i]);
            hi = math.max(hi, s[i]);
          }
          final double px = plot.left + c + 0.5;
          canvas.drawLine(Offset(px, y(hi)), Offset(px, y(lo) + 0.5), band);
        }
      }
    } else if (signalAt != null) {
      canvas.drawPath(_curve(signalAt!, cols * 2, x, y), sp);
    }
    canvas.restore();

    canvas.drawRect(plot, axis..style = PaintingStyle.stroke);
  }

  Path _curve(
    double Function(double) f,
    int points,
    double Function(double) x,
    double Function(double) y,
  ) {
    final Path p = Path();
    for (int i = 0; i <= points; i++) {
      final double t = i / points * durationSeconds;
      final Offset o = Offset(x(t), y(f(t)));
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p;
  }

  static String _fmtAmp(double v) =>
      v >= 10 || v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  bool shouldRepaint(TimeTracePainter old) =>
      old.revision != revision ||
      old.style != style ||
      old.durationSeconds != durationSeconds ||
      old.yMax != yMax;
}

/// One ideal spectral line (mode 1).
typedef SpectrumLine = ({double frequencyHz, double levelDb});

/// Level in dB against frequency.
///
/// Either [lines] (ideal: one stem per sine) or [bins] (analyzer output, one
/// value per bin, [binSpacingHz] apart, starting at 0 Hz). Anything below
/// [floorDb] is drawn at the floor. [markersHz] puts a small neutral tick
/// under the axis at each true tone frequency.
class SpectrumPainter extends CustomPainter {
  SpectrumPainter({
    required this.maxHz,
    required this.floorDb,
    required this.style,
    required this.revision,
    this.lines = const <SpectrumLine>[],
    this.bins,
    this.binSpacingHz = 0,
    this.markersHz = const <double>[],
    this.topDb = 0,
  });

  final double maxHz;
  final double floorDb;
  final double topDb;
  final FourierPlotStyle style;
  final int revision;
  final List<SpectrumLine> lines;
  final Float64List? bins;
  final double binSpacingHz;
  final List<double> markersHz;

  static const double _left = 40;
  static const double _bottom = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = Rect.fromLTRB(
      _left,
      6,
      size.width - 8,
      size.height - _bottom,
    );
    double x(double hz) => plot.left + hz / maxHz * plot.width;
    double y(double db) {
      final double d = db.isFinite ? db.clamp(floorDb, topDb) : floorDb;
      return plot.top + (topDb - d) / (topDb - floorDb) * plot.height;
    }

    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    final Paint axis = Paint()
      ..color = style.axis
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final double dbStep = (topDb - floorDb) > 80 ? 20 : 10;
    for (double d = topDb; d >= floorDb - 1e-9; d -= dbStep) {
      canvas.drawLine(Offset(plot.left, y(d)), Offset(plot.right, y(d)), grid);
      _label(
        canvas,
        d.toStringAsFixed(0),
        style.labelStyle,
        Offset(plot.left - 4, y(d)),
        alignRight: true,
      );
    }
    final double fStep = _niceStep(maxHz, 5);
    for (double f = 0; f <= maxHz + fStep * 1e-6; f += fStep) {
      final double px = x(f);
      canvas.drawLine(Offset(px, plot.top), Offset(px, plot.bottom), grid);
      if (px < plot.right - 24) {
        _label(
          canvas,
          _fmtHz(f),
          style.labelStyle,
          Offset(px, plot.bottom + 17),
          center: f > 0,
        );
      }
    }
    _label(
      canvas,
      'Hz',
      style.labelStyle,
      Offset(plot.right, plot.bottom + 17),
      alignRight: true,
    );

    // True-frequency ticks just under the plot.
    final Paint mk = Paint()
      ..color = style.marker
      ..strokeWidth = 2;
    for (final double f in markersHz) {
      if (f < 0 || f > maxHz) continue;
      canvas.drawLine(
        Offset(x(f), plot.bottom + 1),
        Offset(x(f), plot.bottom + 6),
        mk,
      );
    }

    canvas.save();
    canvas.clipRect(plot);
    final Paint sp = Paint()
      ..color = style.signal
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final SpectrumLine l in lines) {
      if (!l.levelDb.isFinite || l.levelDb <= floorDb) continue;
      final double px = x(l.frequencyHz);
      canvas.drawLine(
        Offset(px, plot.bottom),
        Offset(px, y(l.levelDb)),
        sp..strokeWidth = 3,
      );
      canvas.drawCircle(
        Offset(px, y(l.levelDb)),
        3.5,
        Paint()..color = style.signal,
      );
    }

    final Float64List? b = bins;
    if (b != null && b.isNotEmpty && binSpacingHz > 0) {
      final int shown = math.min(b.length, (maxHz / binSpacingHz).floor() + 1);
      final double spacing = plot.width * binSpacingHz / maxHz;
      if (spacing >= 3) {
        // Stems with a dot: each bin is visibly one value.
        final Paint stem = Paint()
          ..color = style.signal
          ..strokeWidth = math.min(3, math.max(1.5, spacing / 4));
        final Paint dot = Paint()..color = style.signal;
        for (int k = 0; k < shown; k++) {
          final double px = x(k * binSpacingHz);
          canvas.drawLine(Offset(px, plot.bottom), Offset(px, y(b[k])), stem);
          if (spacing >= 6) {
            canvas.drawCircle(Offset(px, y(b[k])), 2.5, dot);
          }
        }
      } else {
        final Path p = Path();
        for (int k = 0; k < shown; k++) {
          final Offset o = Offset(x(k * binSpacingHz), y(b[k]));
          if (k == 0) {
            p.moveTo(o.dx, o.dy);
          } else {
            p.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(
          p,
          Paint()
            ..color = style.signal
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
    canvas.drawRect(plot, axis);
  }

  @override
  bool shouldRepaint(SpectrumPainter old) =>
      old.revision != revision ||
      old.style != style ||
      old.maxHz != maxHz ||
      old.floorDb != floorDb;
}
