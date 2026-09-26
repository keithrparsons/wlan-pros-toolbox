// Painters for the Wi-Fi Classroom tool Why Two Devices Disagree
// (devices-disagree).
//
// Token-only CustomPainters: every neutral color and text style arrives
// resolved from context.colors by the stage, and the device hues come from
// the shared WifiLabClientPalette (GL-003 §8.15.2) through ddDeviceStyle, so
// each painter is right in dark (§8) and light (§8.20) without knowing which
// theme it is in. The stage wraps each one in a Semantics with a worded
// label, and every number a painter shows is also in a text readout.
//
// Color roles:
//   * each device has its own hue and always its letter: its dot on the
//     floor and its trace on the strip chart;
//   * the true power is the strongest neutral (textPrimary), dashed, and
//     labeled "true" in words;
//   * everything else is neutral: floor, grid, axes, labels.
//   * no status hue appears: a spread is a size, not a verdict.
//
// Nothing here draws a wave, so nothing can imply a frequency change.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/devices_disagree_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'devices_disagree_controller.dart' show DdFormat;

/// Resolved colors and text styles shared by both painters.
@immutable
class DdPaintStyle {
  const DdPaintStyle({
    required this.deviceColors,
    required this.onDevice,
    required this.primary,
    required this.secondary,
    required this.grid,
    required this.axis,
    required this.halo,
    required this.floor,
    required this.labelStyle,
    this.sc = PresenterScale.normal,
  });

  /// One hue per device index.
  final List<Color> deviceColors;

  /// Letter color on a device hue.
  final Color onDevice;

  /// Strongest neutral: the true-power line, the AP.
  final Color primary;

  /// Axis labels, the distance line.
  final Color secondary;

  /// Decorative grid.
  final Color grid;

  /// Floor outline and plot frame (3:1 or better).
  final Color axis;

  /// Background behind labels drawn over lines.
  final Color halo;

  /// The floor fill.
  final Color floor;

  /// Axis and marker labels (already carries the presenter text factor).
  final TextStyle labelStyle;

  final PresenterScale sc;

  Color device(int i) => deviceColors[i % deviceColors.length];

  @override
  bool operator ==(Object other) =>
      other is DdPaintStyle &&
      _colorsEq(other.deviceColors, deviceColors) &&
      other.onDevice == onDevice &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.grid == grid &&
      other.axis == axis &&
      other.halo == halo &&
      other.floor == floor &&
      other.labelStyle == labelStyle &&
      other.sc == sc;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(deviceColors),
    onDevice,
    primary,
    secondary,
    grid,
    axis,
    halo,
    floor,
    labelStyle,
    sc,
  );
}

bool _colorsEq(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _dashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 6,
  double gap = 4,
}) {
  final double len = (b - a).distance;
  if (len == 0) return;
  final Offset dir = (b - a) / len;
  double d = 0;
  while (d < len) {
    canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), paint);
    d += dash + gap;
  }
}

Size _label(
  Canvas canvas,
  String text,
  Offset at,
  TextStyle style, {
  Alignment align = Alignment.center,
  Color? background,
}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final Offset o = Offset(
    at.dx - tp.width * (align.x + 1) / 2,
    at.dy - tp.height * (align.y + 1) / 2,
  );
  if (background != null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (o & tp.size).inflate(2),
        const Radius.circular(2),
      ),
      Paint()..color = background,
    );
  }
  tp.paint(canvas, o);
  return tp.size;
}

// ── Floor: the AP, the distance, the devices side by side ─────────────────

class DdFloorPainter extends CustomPainter {
  DdFloorPainter({
    required this.distanceM,
    required this.spacingM,
    required this.deviceCount,
    required this.style,
  });

  final double distanceM;
  final double spacingM;
  final int deviceCount;
  final DdPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale sc = style.sc;
    final Rect floor = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(floor.deflate(1), const Radius.circular(8)),
      Paint()..color = style.floor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(floor.deflate(1), const Radius.circular(8)),
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1),
    );

    final double cy = size.height / 2;
    final double r = sc.markerSize(14);
    final Offset ap = Offset(r + sc.markerSize(18), cy);

    // The spot: a ring around the devices, at the right. The devices are
    // drawn at least a dot apart so letters never collide (the true spacing
    // is in the label), and everything is sized to fit the floor's height.
    final double inner = size.height - sc.markerSize(12);
    final double pitch = inner / deviceCount;
    final double dot = math.min(sc.markerSize(11), pitch * 0.42);
    final double groupH = pitch * (deviceCount - 1);
    final double ring = size.height / 2 - 3;
    final Offset spot = Offset(size.width - ring - sc.markerSize(10), cy);
    canvas.drawCircle(
      spot,
      ring,
      Paint()
        ..color = style.secondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1),
    );

    // Distance line from the AP to the spot.
    final Paint line = Paint()
      ..color = style.secondary
      ..strokeWidth = sc.strokeWidth(1.5);
    _dashedLine(
      canvas,
      ap + Offset(r + 4, 0),
      spot - Offset(ring + 4, 0),
      line,
    );
    _label(
      canvas,
      DdFormat.meters(distanceM),
      Offset((ap.dx + spot.dx - ring) / 2, cy - sc.markerSize(4)),
      style.labelStyle.copyWith(color: style.primary),
      align: Alignment.bottomCenter,
      background: style.floor,
    );

    // The AP.
    canvas.drawCircle(ap, r, Paint()..color = style.primary);
    _label(
      canvas,
      'AP',
      ap,
      style.labelStyle.copyWith(
        color: style.floor,
        fontWeight: FontWeight.w700,
      ),
    );

    // The devices, stacked across the direction to the AP.
    for (int i = 0; i < deviceCount; i++) {
      final Offset c = Offset(spot.dx, spot.dy - groupH / 2 + i * pitch);
      canvas.drawCircle(c, dot, Paint()..color = style.device(i));
      _label(
        canvas,
        deviceLetter(i),
        c,
        style.labelStyle.copyWith(
          color: style.onDevice,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    _label(
      canvas,
      '${DdFormat.cm(spacingM)} apart',
      Offset(spot.dx - ring - 6, cy + sc.markerSize(8)),
      style.labelStyle.copyWith(color: style.secondary),
      align: Alignment.topRight,
      background: style.floor,
    );
  }

  @override
  bool shouldRepaint(DdFloorPainter old) =>
      old.distanceM != distanceM ||
      old.spacingM != spacingM ||
      old.deviceCount != deviceCount ||
      old.style != style;
}

// ── Strip chart: each device's reading over the last few seconds ──────────

class DdStripPainter extends CustomPainter {
  DdStripPainter({
    required this.result,
    required this.corrected,
    required this.style,
  });

  final DdResult result;

  /// Plot readings with each device's offset removed.
  final bool corrected;
  final DdPaintStyle style;

  static const double _left = 44;
  static const double _right = 24;
  static const double _top = 10;
  static const double _bottom = 22;

  /// Axis limits: 25 dB below true to 12 dB above, on the 5 dB grid. Held
  /// around the true power, so Re-sample never rescales the axis.
  (double, double) get axis {
    final double t = result.trueDbm;
    return (
      ((t - 25) / 5).floorToDouble() * 5,
      ((t + 12) / 5).ceilToDouble() * 5,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale sc = style.sc;
    final double k = sc.text;
    final Rect plot = Rect.fromLTRB(
      _left * k,
      _top * k,
      size.width - _right * k,
      size.height - _bottom * k,
    );
    final (double lo, double hi) = axis;
    const int n = kStripSamples;
    double xOf(int t) => plot.left + plot.width * t / n;
    double yOf(double dbm) =>
        plot.top + plot.height * (hi - dbm.clamp(lo, hi)) / (hi - lo);

    final TextStyle axisLabel = style.labelStyle.copyWith(
      color: style.secondary,
    );
    final Paint grid = Paint()
      ..color = style.grid
      ..strokeWidth = sc.strokeWidth(1);
    for (double d = hi; d >= lo; d -= 5) {
      final double y = yOf(d);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      if (d > lo && ((d / 5).round().isEven || plot.height > 220)) {
        _label(
          canvas,
          d.toStringAsFixed(0),
          Offset(plot.left - 4, y),
          axisLabel,
          align: Alignment.centerRight,
        );
      }
    }
    for (int s = 0; s <= kStripSeconds; s++) {
      final double x = xOf(s * kSamplesPerSecond);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      _label(
        canvas,
        s == kStripSeconds ? 'now' : '-${kStripSeconds - s} s',
        Offset(x, plot.bottom + 3),
        axisLabel,
        align: Alignment.topCenter,
      );
    }
    canvas.drawRect(
      plot,
      Paint()
        ..color = style.axis
        ..style = PaintingStyle.stroke
        ..strokeWidth = sc.strokeWidth(1),
    );
    canvas.save();
    canvas.clipRect(plot.inflate(2));

    // Each device as a step line: a reading holds until the next one.
    final List<double> ends = <double>[];
    for (int i = 0; i < result.traces.length; i++) {
      final DeviceTrace tr = result.traces[i];
      final double off = corrected ? tr.settings.offsetDb : 0;
      final Path p = Path();
      for (int t = 0; t < n; t++) {
        final double y = yOf(tr.reportedDbm[t] - off);
        if (t == 0) {
          p.moveTo(xOf(0), y);
        } else {
          p.lineTo(xOf(t), y);
        }
        p.lineTo(xOf(t + 1), y);
      }
      ends.add(yOf(tr.reportedDbm[n - 1] - off));
      canvas.drawPath(
        p,
        Paint()
          ..color = style.device(i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = sc.strokeWidth(2)
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // True power, over the traces so it is never hidden.
    final double yTrue = yOf(result.trueDbm);
    _dashedLine(
      canvas,
      Offset(plot.left, yTrue),
      Offset(plot.right, yTrue),
      Paint()
        ..color = style.primary
        ..strokeWidth = sc.strokeWidth(2),
      dash: 10,
      gap: 5,
    );
    canvas.restore();
    _label(
      canvas,
      'true',
      Offset(plot.left + 6, yTrue - 3),
      axisLabel.copyWith(color: style.primary, fontWeight: FontWeight.w700),
      align: Alignment.bottomLeft,
      background: style.halo,
    );

    // Letters at the right edge, pushed apart so they never overlap.
    final List<int> order = <int>[for (int i = 0; i < ends.length; i++) i]
      ..sort((int a, int b) => ends[a].compareTo(ends[b]));
    final double gapPx = 12 * k;
    final List<double> ys = <double>[for (final int i in order) ends[i]];
    for (int j = 1; j < ys.length; j++) {
      if (ys[j] - ys[j - 1] < gapPx) ys[j] = ys[j - 1] + gapPx;
    }
    final double over = ys.isEmpty ? 0 : ys.last - plot.bottom;
    if (over > 0) {
      for (int j = 0; j < ys.length; j++) {
        ys[j] -= over;
      }
    }
    for (int j = 0; j < order.length; j++) {
      _label(
        canvas,
        deviceLetter(order[j]),
        Offset(plot.right + 4, ys[j]),
        axisLabel.copyWith(
          color: style.device(order[j]),
          fontWeight: FontWeight.w700,
        ),
        align: Alignment.centerLeft,
      );
    }
  }

  @override
  bool shouldRepaint(DdStripPainter old) =>
      old.result != result || old.corrected != corrected || old.style != style;
}
