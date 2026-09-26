// Painters for the Wi-Fi Classroom Adjacent Channels and AP Stacking tool.
//
//   - AciSpectrumPainter: power spectral density at the receiver, dBm per
//     MHz, against frequency. Your channel, the wanted signal in it, the
//     neighbor's mask skirt reaching into it (shaded where it lands in your
//     20 MHz), the noise floor, the leakage and the energy-detect threshold
//     spread over your 20 MHz.
//   - AciFloorPainter: the three radios on a line with their distances.
//
// THE STANDING DRAWING RULE (README, Keith 2026-09-25): the x axis comes from
// the channel choice alone and the y axis is fixed, so moving a radio or
// changing a power changes heights only; a channel center never moves.
//
// Colors, text styles and the presenter scale are handed in by the stage, so
// these painters read no theme themselves. ASCII only (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/adjacent_channel_model.dart';
import '../../../services/wifi_lab/fspl_math.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Everything the painters take from the theme.
@immutable
class AciPaintStyle {
  const AciPaintStyle({
    required this.scale,
    required this.surface,
    required this.grid,
    required this.axis,
    required this.neighbor,
    required this.yours,
    required this.noise,
    required this.threshold,
    required this.label,
    required this.strongLabel,
    required this.neighborLabel,
    required this.yoursLabel,
  });

  final PresenterScale scale;
  final Color surface;
  final Color grid;
  final Color axis;
  final Color neighbor;
  final Color yours;
  final Color noise;
  final Color threshold;
  final TextStyle label;
  final TextStyle strongLabel;
  final TextStyle neighborLabel;
  final TextStyle yoursLabel;
}

/// Fixed y range of the spectrum strip, dBm per MHz.
const double kAciPsdTop = -10;
const double kAciPsdBottom = -130;

/// 10 log10(20): spreads a per-20 MHz level over 1 MHz.
final double kAciPer20 = 10 * FsplMath.log10(20);

void _text(
  Canvas canvas,
  String s,
  TextStyle style,
  Offset at, {
  double ax = 0,
  double ay = 0,
  double? maxWidth,
  Color? backing,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final Offset o = at - Offset(tp.width * ax, tp.height * ay);
  if (backing != null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (o & tp.size).inflate(2),
        const Radius.circular(3),
      ),
      Paint()..color = backing.withValues(alpha: 0.85),
    );
  }
  tp.paint(canvas, o);
}

void _dashedH(Canvas canvas, double x0, double x1, double y, Paint p) {
  const double dash = 6;
  const double gap = 4;
  for (double x = x0; x < x1; x += dash + gap) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, x1), y), p);
  }
}

void _dashedV(Canvas canvas, double x, double y0, double y1, Paint p) {
  const double dash = 5;
  const double gap = 4;
  for (double y = y0; y < y1; y += dash + gap) {
    canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, y1)), p);
  }
}

// ── Spectrum strip ──────────────────────────────────────────────────────────

class AciSpectrumPainter extends CustomPainter {
  AciSpectrumPainter({
    required this.result,
    required this.neighborName,
    required this.receiverName,
    required this.style,
  });

  final AciResult result;
  final String neighborName;
  final String receiverName;
  final AciPaintStyle style;

  /// Frequency span shown, MHz: from below the neighbor's lower edge to
  /// above your upper edge. Depends on the channel choice only.
  static (double, double) spanMHz(AciChannelPlan p) {
    final double lo = p.neighborLowMHz;
    final double hi = p.receiverHighMHz;
    final double pad = math.max(12, (hi - lo) * 0.1);
    return (lo - pad, hi + pad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final AciPaintStyle s = style;
    final AciChannelPlan p = result.plan;
    final AciConfig c = result.config;
    final PresenterScale k = s.scale;

    final double left = 44 * k.text;
    final double right = 8;
    final double top = 34 * k.text;
    final double bottom = 36 * k.text;
    final Rect plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (plot.width <= 10 || plot.height <= 10) return;

    final (double f0, double f1) = spanMHz(p);
    double xOf(double f) => plot.left + (f - f0) / (f1 - f0) * plot.width;
    double yOf(double dbm) =>
        plot.top +
        (kAciPsdTop - dbm.clamp(kAciPsdBottom, kAciPsdTop)) /
            (kAciPsdTop - kAciPsdBottom) *
            plot.height;

    // Your channel, tinted, with its edges.
    final double rx0 = xOf(p.receiverLowMHz);
    final double rx1 = xOf(p.receiverHighMHz);
    canvas.drawRect(
      Rect.fromLTRB(rx0, plot.top, rx1, plot.bottom),
      Paint()..color = s.yours.withValues(alpha: 0.10),
    );

    // Grid and y labels every 20 dB.
    final Paint grid = Paint()
      ..color = s.grid.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (double v = kAciPsdTop - 10; v >= kAciPsdBottom; v -= 20) {
      final double y = yOf(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(
        canvas,
        v.round().toString(),
        s.label,
        Offset(plot.left - 4, y),
        ax: 1,
        ay: 0.5,
      );
    }

    final Paint edge = Paint()
      ..color = s.yours
      ..strokeWidth = k.strokeWidth(1.2);
    _dashedV(canvas, rx0, plot.top, plot.bottom, edge);
    _dashedV(canvas, rx1, plot.top, plot.bottom, edge);
    final Paint nEdge = Paint()
      ..color = s.neighbor.withValues(alpha: 0.7)
      ..strokeWidth = k.strokeWidth(1);
    for (final double f in <double>[p.neighborLowMHz, p.neighborHighMHz]) {
      final double x = xOf(f);
      if (x >= plot.left && x <= plot.right) {
        _dashedV(canvas, x, plot.top, plot.bottom, nEdge);
      }
    }

    // Noise floor, per MHz.
    final double noisePsd = result.receiverNoiseDbm - kAciPer20;
    final Paint noise = Paint()
      ..color = s.noise
      ..strokeWidth = k.strokeWidth(1.5);
    canvas.drawLine(
      Offset(plot.left, yOf(noisePsd)),
      Offset(plot.right, yOf(noisePsd)),
      noise,
    );
    _text(
      canvas,
      'Noise floor',
      s.label,
      Offset(plot.left + 4, yOf(noisePsd) - 2),
      ay: 1,
      backing: s.surface,
    );

    // A transmitter's curve, sampled across the plot.
    Path curve(int widthMHz, double centerMHz, double inChannelDbm) {
      final Path path = Path();
      const int n = 400;
      for (int i = 0; i <= n; i++) {
        final double f = f0 + (f1 - f0) * i / n;
        final double y = yOf(
          aciPsdDbmPerMHz(
            family: c.family,
            widthMHz: widthMHz,
            centerMHz: centerMHz,
            inChannelDbm: inChannelDbm,
            freqMHz: f,
          ),
        );
        if (i == 0) {
          path.moveTo(xOf(f), y);
        } else {
          path.lineTo(xOf(f), y);
        }
      }
      return path;
    }

    // The neighbor's leakage inside your 20 MHz, shaded.
    final Path leak = Path()..moveTo(rx0, plot.bottom);
    const int m = 120;
    for (int i = 0; i <= m; i++) {
      final double f = p.receiverLowMHz + 20 * i / m;
      leak.lineTo(
        xOf(f),
        yOf(
          aciPsdDbmPerMHz(
            family: c.family,
            widthMHz: p.neighborWidthMHz,
            centerMHz: p.neighborCenterMHz,
            inChannelDbm: result.neighborDbm,
            freqMHz: f,
          ),
        ),
      );
    }
    leak
      ..lineTo(rx1, plot.bottom)
      ..close();
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(leak, Paint()..color = s.neighbor.withValues(alpha: 0.35));

    final Paint yoursLine = Paint()
      ..style = PaintingStyle.stroke
      ..color = s.yours
      ..strokeWidth = k.strokeWidth(2.2);
    canvas.drawPath(
      curve(20, p.receiverCenterMHz, result.wantedDbm),
      yoursLine,
    );
    final Paint neighborLine = Paint()
      ..style = PaintingStyle.stroke
      ..color = s.neighbor
      ..strokeWidth = k.strokeWidth(2.2);
    canvas.drawPath(
      curve(p.neighborWidthMHz, p.neighborCenterMHz, result.neighborDbm),
      neighborLine,
    );

    // Energy-detect threshold and the leakage, both spread over your 20 MHz.
    final double ccaY = yOf(c.ccaThresholdDbm - kAciPer20);
    _dashedH(
      canvas,
      rx0,
      rx1,
      ccaY,
      Paint()
        ..color = s.threshold
        ..strokeWidth = k.strokeWidth(1.6),
    );
    final double leakY = yOf(result.leakageDbm - kAciPer20);
    canvas.drawLine(
      Offset(rx0, leakY),
      Offset(rx1, leakY),
      Paint()
        ..color = s.neighbor
        ..strokeWidth = k.strokeWidth(3),
    );
    canvas.restore();

    // Labels on the right of your channel for the two per-20 MHz levels,
    // kept apart when they are close.
    final double labelX = math.min(rx1 + 4, plot.right - 4);
    final bool roomRight = plot.right - rx1 > 110 * k.text;
    final double ax = roomRight ? 0 : 1;
    final double lx = roomRight ? labelX : rx0 - 4;
    double ccaLabelY = ccaY;
    double leakLabelY = leakY;
    final double minGap = 16 * k.text;
    if ((ccaLabelY - leakLabelY).abs() < minGap) {
      if (leakLabelY >= ccaLabelY) {
        leakLabelY = ccaLabelY + minGap;
      } else {
        leakLabelY = ccaLabelY - minGap;
      }
    }
    _text(
      canvas,
      'CCA ${c.ccaThresholdDbm.round()} dBm',
      s.label,
      Offset(lx, ccaLabelY),
      ax: ax,
      ay: 0.5,
      backing: s.surface,
    );
    _text(
      canvas,
      'Leakage ${result.leakageDbm.toStringAsFixed(1)} dBm',
      s.neighborLabel,
      Offset(lx, leakLabelY),
      ax: ax,
      ay: 0.5,
      backing: s.surface,
    );

    // Channel names over the curves; centers and frequencies under the axis.
    void center(double fMHz, String name, String sub, TextStyle st) {
      final double x = xOf(fMHz);
      if (x < plot.left || x > plot.right) return;
      canvas.drawLine(
        Offset(x, plot.bottom),
        Offset(x, plot.bottom + 5),
        Paint()
          ..color = s.axis
          ..strokeWidth = k.strokeWidth(1.2),
      );
      _text(canvas, sub, s.label, Offset(x, plot.bottom + 6), ax: 0.5);
      _text(canvas, name, st, Offset(x, plot.top - 4), ax: 0.5, ay: 1);
    }

    center(
      p.neighborCenterMHz,
      'Neighbor ${p.neighborLabel}',
      '${p.neighborCenterMHz.round()} MHz',
      s.neighborLabel,
    );
    center(
      p.receiverCenterMHz,
      'Yours ${p.receiverLabel}',
      '${p.receiverCenterMHz.round()} MHz',
      s.yoursLabel,
    );
    canvas.drawRect(
      plot,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = s.grid.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(AciSpectrumPainter old) =>
      !identical(old.result, result) ||
      old.style != style ||
      old.neighborName != neighborName ||
      old.receiverName != receiverName;
}

// ── Floor line ──────────────────────────────────────────────────────────────

class AciFloorPainter extends CustomPainter {
  AciFloorPainter({
    required this.result,
    required this.receiverName,
    required this.wantedName,
    required this.style,
  });

  final AciResult result;
  final String receiverName;
  final String wantedName;
  final AciPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final AciPaintStyle s = style;
    final AciConfig c = result.config;
    final AciChannelPlan p = result.plan;
    final PresenterScale k = s.scale;
    final double y = size.height * 0.62;
    final double margin = 70 * k.text;
    final double rxX = size.width * 0.42;

    // Log distance: the wanted side runs 1 to 60 m, the neighbor side 30 cm
    // to 30 m. Not to scale; every distance is labeled.
    double wantedX(double d) {
      final double t =
          FsplMath.log10(d / AciLimits.wantedDistanceMin) /
          FsplMath.log10(
            AciLimits.wantedDistanceMax / AciLimits.wantedDistanceMin,
          );
      return rxX - 40 * k.marker - t * (rxX - 40 * k.marker - margin);
    }

    double neighborX(double d) {
      final double t =
          FsplMath.log10(d / AciLimits.neighborDistanceMin) /
          FsplMath.log10(
            AciLimits.neighborDistanceMax / AciLimits.neighborDistanceMin,
          );
      return rxX +
          24 * k.marker +
          t * (size.width - margin - rxX - 24 * k.marker);
    }

    final double wx = wantedX(c.wantedDistanceM);
    final double nx = neighborX(c.neighborDistanceM);
    final Paint line = Paint()
      ..color = s.grid.withValues(alpha: 0.6)
      ..strokeWidth = k.strokeWidth(1.2);
    canvas.drawLine(
      Offset(margin * 0.5, y),
      Offset(size.width - margin * 0.5, y),
      line,
    );

    final Paint wantedLink = Paint()
      ..color = s.yours
      ..strokeWidth = k.strokeWidth(2.5);
    canvas.drawLine(Offset(wx, y), Offset(rxX, y), wantedLink);
    final Paint nLink = Paint()
      ..color = s.neighbor
      ..strokeWidth = k.strokeWidth(2.5);
    canvas.drawLine(Offset(rxX, y), Offset(nx, y), nLink);

    void radio(double x, Color fill, String name, String sub, TextStyle st) {
      final double r = k.markerSize(8);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = fill);
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = s.surface
          ..strokeWidth = k.strokeWidth(1.5),
      );
      _text(canvas, name, st, Offset(x, y - r - 4), ax: 0.5, ay: 1);
      _text(canvas, sub, s.label, Offset(x, y + r + 4), ax: 0.5);
    }

    radio(
      wx,
      s.yours,
      wantedName,
      '${_dist(c.wantedDistanceM)} away, ${c.wantedPowerDbm.round()} dBm',
      s.yoursLabel,
    );
    radio(
      nx,
      s.neighbor,
      'Neighbor, ${p.neighborLabel}',
      '${_dist(c.neighborDistanceM)} away, ${c.neighborPowerDbm.round()} dBm',
      s.neighborLabel,
    );
    // The receiver: a ring, drawn last so it sits on both links.
    final double rr = k.markerSize(11);
    canvas.drawCircle(Offset(rxX, y), rr, Paint()..color = s.surface);
    canvas.drawCircle(
      Offset(rxX, y),
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = s.axis
        ..strokeWidth = k.strokeWidth(2.5),
    );
    _text(
      canvas,
      '$receiverName, listening on ${p.receiverLabel}',
      s.strongLabel,
      Offset(rxX, y - rr - 22 * k.text),
      ax: 0.5,
      ay: 1,
    );
  }

  static String _dist(double d) => d < 1
      ? '${(d * 100).round()} cm'
      : (d < 10 ? '${d.toStringAsFixed(1)} m' : '${d.round()} m');

  @override
  bool shouldRepaint(AciFloorPainter old) =>
      !identical(old.result, result) ||
      old.style != style ||
      old.receiverName != receiverName ||
      old.wantedName != wantedName;
}
