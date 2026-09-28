// Painters for Why a Busy Line Lags (Wi-Fi Classroom): the video call's
// delay over the run, and the queue at the home line that the call's
// packets wait in.
//
// COLOR (GL-003 §8.13 / §8.20.2). Lime marks the one quantity the tool is
// about, the call's delay in the current setting: the trace is textAccent
// (the thin-foreground lime on light), and the call's packet is a vivid lime
// fill with a charcoal outline. The other setting's trace, kept for
// comparison, is a dashed textTertiary line with its own words ("SQM off,
// for comparison"), so the two are never told apart by hue alone
// (SC 1.4.1). The upload's time span is a neutral band with a label. No
// status hues: nothing here is a pass or fail verdict.
//
// MOTION (§8.8). Both painters repaint from the controller's run-time
// notifier, and only while the run plays; stopped, they draw the same
// moment still.
//
// PRESENTER. Strokes, markers and painted labels follow PresenterScale.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/latency_under_load_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Everything the painters need from the theme, resolved once per build.
@immutable
class LulPaintStyle {
  const LulPaintStyle({
    required this.colors,
    required this.scale,
    required this.label,
    required this.small,
  });

  final AppColorScheme colors;
  final PresenterScale scale;

  /// Trace names and lane names.
  final TextStyle label;

  /// Axis ticks and notes.
  final TextStyle small;

  @override
  bool operator ==(Object other) =>
      other is LulPaintStyle &&
      other.colors == colors &&
      other.scale == scale &&
      other.label == label &&
      other.small == small;

  @override
  int get hashCode => Object.hash(colors, scale, label, small);
}

TextPainter _text(String s, TextStyle style, {double? maxWidth}) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '...',
  );
  tp.layout(maxWidth: maxWidth ?? double.infinity);
  return tp;
}

/// Draws [path] dashed.
void _dashed(Canvas canvas, Path path, Paint paint, double dash, double gap) {
  for (final ui.PathMetric m in path.computeMetrics()) {
    double d = 0;
    while (d < m.length) {
      final double end = math.min(d + dash, m.length);
      canvas.drawPath(m.extractPath(d, end), paint);
      d = end + gap;
    }
  }
}

/// Maps run seconds and milliseconds to the chart and back.
@immutable
class LulChartGeometry {
  LulChartGeometry(this.size, this.style, this.axisMaxMs)
    : _tick = _text('000 ms', style.small);

  final Size size;
  final LulPaintStyle style;
  final double axisMaxMs;
  final TextPainter _tick;

  double get left => _tick.width + 8 * style.scale.marker;
  double get right => size.width - 6 * style.scale.marker;
  double get top => _tick.height + 10 * style.scale.marker;
  double get bottom => size.height - (_tick.height + 8 * style.scale.marker);

  double x(double tS) => left + (right - left) * (tS / kLulRunS);
  double y(double ms) =>
      bottom - (bottom - top) * (ms.clamp(0, axisMaxMs) / axisMaxMs);

  /// Run seconds under painter x, for a tap or drag on the chart.
  double tOf(double px) =>
      ((px - left) / (right - left) * kLulRunS).clamp(0, kLulRunS).toDouble();
}

/// The call's delay over the run: the current setting solid up to the
/// playhead, the other setting dashed for comparison, the upload's span
/// shaded, and the FCC's measured busy range as a bracket.
class LulTracePainter extends CustomPainter {
  LulTracePainter({
    required this.line,
    required this.sqm,
    required this.timeS,
    required this.style,
  }) : super(repaint: timeS);

  final LulLine line;
  final bool sqm;
  final ValueListenable<double> timeS;
  final LulPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final AppColorScheme c = style.colors;
    final PresenterScale s = style.scale;
    final LulChartGeometry g = LulChartGeometry(size, style, line.axisMaxMs);
    final double now = timeS.value;

    // Gridlines and millisecond ticks, four steps.
    final Paint grid = Paint()
      ..color = c.border
      ..strokeWidth = s.strokeWidth(1);
    for (int i = 0; i <= 4; i++) {
      final double ms = line.axisMaxMs * i / 4;
      final double yy = g.y(ms);
      canvas.drawLine(Offset(g.left, yy), Offset(g.right, yy), grid);
      final TextPainter tp = _text(
        '${ms.round()} ms',
        style.small.copyWith(color: c.textTertiary),
      );
      tp.paint(canvas, Offset(g.left - tp.width - 4, yy - tp.height / 2));
    }
    // Seconds along the bottom.
    for (int sec = 0; sec <= kLulRunS; sec += 4) {
      final TextPainter tp = _text(
        sec == kLulRunS ? '$sec s' : '$sec',
        style.small.copyWith(color: c.textTertiary),
      );
      tp.paint(
        canvas,
        Offset(g.x(sec.toDouble()) - tp.width / 2, g.bottom + 4),
      );
    }

    // The upload's span: a neutral band with its label at the top.
    final Rect band = Rect.fromLTRB(
      g.x(kLulUploadStartS),
      g.top,
      g.x(kLulUploadEndS),
      g.bottom,
    );
    canvas.drawRect(
      band,
      Paint()..color = c.textTertiary.withValues(alpha: 0.12),
    );
    TextPainter bandLabel = _text(
      'Someone else\'s upload runs',
      style.small.copyWith(color: c.textSecondary),
    );
    if (bandLabel.width > band.width - 8) {
      bandLabel = _text(
        'Upload runs',
        style.small.copyWith(color: c.textSecondary),
        maxWidth: band.width - 8,
      );
    }
    bandLabel.paint(
      canvas,
      Offset(
        band.center.dx - bandLabel.width / 2,
        g.top - bandLabel.height - 2,
      ),
    );

    // The FCC's measured busy range for this technology: a bracket just
    // inside the right edge of the upload band.
    final double bx = band.right - 10 * s.marker;
    final Paint bracket = Paint()
      ..color = c.textSecondary
      ..strokeWidth = s.strokeWidth(1.5)
      ..style = PaintingStyle.stroke;
    final double yLo = g.y(line.busyLowMs);
    final double yHi = g.y(line.busyHighMs);
    canvas.drawPath(
      Path()
        ..moveTo(bx + 5 * s.marker, yHi)
        ..lineTo(bx, yHi)
        ..lineTo(bx, yLo)
        ..lineTo(bx + 5 * s.marker, yLo),
      bracket,
    );
    final TextPainter fcc = _text(
      'FCC range',
      style.small.copyWith(color: c.textSecondary),
    );
    fcc.paint(
      canvas,
      Offset(bx - fcc.width - 4, (yHi + yLo) / 2 - fcc.height / 2),
    );

    Path traceOf(bool on, double until) {
      final Path p = Path();
      bool first = true;
      for (final LulSample smp in lulTrace(line, sqm: on)) {
        if (smp.tS > until + 1e-9) break;
        final Offset o = Offset(g.x(smp.tS), g.y(smp.ms));
        if (first) {
          p.moveTo(o.dx, o.dy);
          first = false;
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      if (until < kLulRunS) {
        p.lineTo(g.x(until), g.y(lulLatencyMs(line, sqm: on, tS: until)));
      }
      return p;
    }

    // The other setting, whole, dashed, for comparison.
    _dashed(
      canvas,
      traceOf(!sqm, kLulRunS),
      Paint()
        ..color = c.textTertiary
        ..strokeWidth = s.strokeWidth(1.5)
        ..style = PaintingStyle.stroke,
      6 * s.stroke,
      4 * s.stroke,
    );

    // The current setting, solid, up to the playhead.
    canvas.drawPath(
      traceOf(sqm, now),
      Paint()
        ..color = c.textAccent
        ..strokeWidth = s.strokeWidth(2.5)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Trace names, placed inside the upload band beside each plateau.
    final double offMs = line.busyMs;
    final double onMs = line.idleMs + kLulSqmTargetMs;
    final String curName = sqm ? 'SQM on' : 'SQM off';
    final String otherName = sqm
        ? 'SQM off, for comparison'
        : 'SQM on, for comparison';
    final TextPainter cur = _text(
      curName,
      style.label.copyWith(color: c.textAccent),
    );
    final TextPainter oth = _text(
      otherName,
      style.label.copyWith(color: c.textTertiary),
    );
    // Each name sits just above its own plateau. The higher trace's name
    // starts early in the band and the lower one's later, so when the two
    // plateaus are close (fiber) the names never overprint.
    final double hiMs = math.max(offMs, onMs);
    final bool curIsHigh = (sqm ? onMs : offMs) == hiMs;
    final double earlyX = g.x(kLulUploadStartS + 1.2);
    final double lateX = math.max(
      g.x(kLulUploadStartS + 5.5),
      earlyX + (curIsHigh ? cur.width : oth.width) + 12 * s.marker,
    );
    void place(TextPainter tp, double ms, double x) {
      final double yy = math.max(g.top, g.y(ms) - tp.height - 3 * s.marker);
      final double xx = math.max(g.left, math.min(x, g.right - tp.width));
      tp.paint(canvas, Offset(xx, yy));
    }

    place(cur, sqm ? onMs : offMs, curIsHigh ? earlyX : lateX);
    place(oth, sqm ? offMs : onMs, curIsHigh ? lateX : earlyX);

    // The playhead, while the run is anywhere but the end.
    if (now < kLulRunS) {
      final double px = g.x(now);
      canvas.drawLine(
        Offset(px, g.top),
        Offset(px, g.bottom),
        Paint()
          ..color = c.textSecondary
          ..strokeWidth = s.strokeWidth(1),
      );
    }
    final Offset dot = Offset(
      g.x(now),
      g.y(lulLatencyMs(line, sqm: sqm, tS: now)),
    );
    canvas.drawCircle(dot, s.markerSize(5), Paint()..color = c.primary);
    canvas.drawCircle(
      dot,
      s.markerSize(5),
      Paint()
        ..color = c.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.strokeWidth(1.2),
    );
  }

  @override
  bool shouldRepaint(LulTracePainter old) =>
      old.line != line ||
      old.sqm != sqm ||
      old.style != style ||
      old.timeS != timeS;
}

/// Boxes drawn for a queue that fills the whole axis.
const int kLulQueueBoxes = 24;

/// How many upload boxes a queue of [queueMs] draws on [line]'s scale.
/// Any queue at all draws at least one box, so a short queue is still seen.
int lulQueueBoxes(LulLine line, double queueMs) {
  if (queueMs <= 0.5) return 0;
  return (queueMs / (line.axisMaxMs / kLulQueueBoxes)).round().clamp(
    1,
    kLulQueueBoxes,
  );
}

/// The queue at the home line at the playhead. SQM off: one line, the
/// call's packet at the back of the upload. SQM on: the upload keeps a
/// short queue of its own and the call's packet goes in its turn.
class LulQueuePainter extends CustomPainter {
  LulQueuePainter({
    required this.line,
    required this.sqm,
    required this.timeS,
    required this.style,
  }) : super(repaint: timeS);

  final LulLine line;
  final bool sqm;
  final ValueListenable<double> timeS;
  final LulPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final AppColorScheme c = style.colors;
    final PresenterScale s = style.scale;
    final double q = lulQueueMs(line, sqm: sqm, tS: timeS.value);
    final int boxes = lulQueueBoxes(line, q);

    final TextPainter exit = _text(
      'to the internet',
      style.small.copyWith(color: c.textSecondary),
    );
    final double laneRight = size.width - exit.width - 18 * s.marker;
    final TextPainter nameProbe = _text('Upload', style.label);
    final double laneLeft = nameProbe.width + 12 * s.marker;
    final double laneW = laneRight - laneLeft;
    final double slot = laneW / (kLulQueueBoxes + 1);
    final double boxW = slot * 0.78;
    final int lanes = sqm ? 2 : 1;
    final double laneH = math.min(
      size.height / lanes - 6 * s.marker,
      30 * s.marker,
    );

    final Paint uploadFill = Paint()..color = c.textTertiary;
    final Paint rail = Paint()
      ..color = c.border
      ..strokeWidth = s.strokeWidth(1);
    final Paint callFill = Paint()..color = c.primary;
    final Paint callEdge = Paint()
      ..color = c.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.strokeWidth(1.2);

    double laneTop(int i) {
      final double total = lanes * laneH + (lanes - 1) * 8 * s.marker;
      return (size.height - total) / 2 + i * (laneH + 8 * s.marker);
    }

    void laneName(String name, double top) {
      final TextPainter tp = _text(
        name,
        style.label.copyWith(color: c.textSecondary),
      );
      tp.paint(canvas, Offset(0, top + laneH / 2 - tp.height / 2));
    }

    void rails(double top) {
      canvas.drawLine(Offset(laneLeft, top), Offset(laneRight, top), rail);
      canvas.drawLine(
        Offset(laneLeft, top + laneH),
        Offset(laneRight, top + laneH),
        rail,
      );
    }

    void uploadBoxes(int n, double top) {
      for (int i = 0; i < n; i++) {
        final double right = laneRight - i * slot - (slot - boxW) / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(right - boxW, top + 4, right, top + laneH - 4),
            Radius.circular(2 * s.marker),
          ),
          uploadFill,
        );
      }
    }

    void call(double cx, double top) {
      final Offset o = Offset(cx, top + laneH / 2);
      final double r = math.min(laneH / 2 - 3, slot * 0.6);
      canvas.drawCircle(o, r, callFill);
      canvas.drawCircle(o, r, callEdge);
    }

    // The exit, with its arrow, at the lane's right end.
    final double midY = size.height / 2;
    final Paint arrow = Paint()
      ..color = c.textSecondary
      ..strokeWidth = s.strokeWidth(1.5)
      ..style = PaintingStyle.stroke;
    final double ax = laneRight + 4 * s.marker;
    canvas.drawLine(Offset(ax, midY), Offset(ax + 10 * s.marker, midY), arrow);
    canvas.drawPath(
      Path()
        ..moveTo(ax + 6 * s.marker, midY - 4 * s.marker)
        ..lineTo(ax + 10 * s.marker, midY)
        ..lineTo(ax + 6 * s.marker, midY + 4 * s.marker),
      arrow,
    );
    exit.paint(canvas, Offset(ax + 14 * s.marker, midY - exit.height / 2));

    if (!sqm) {
      final double top = laneTop(0);
      laneName('Queue', top);
      rails(top);
      uploadBoxes(boxes, top);
      // The call's packet waits behind every upload box.
      call(laneRight - boxes * slot - slot / 2, top);
      return;
    }
    final double upTop = laneTop(0);
    laneName('Upload', upTop);
    rails(upTop);
    uploadBoxes(boxes, upTop);
    final double callTop = laneTop(1);
    laneName('Call', callTop);
    rails(callTop);
    call(laneRight - slot / 2, callTop);
  }

  @override
  bool shouldRepaint(LulQueuePainter old) =>
      old.line != line ||
      old.sqm != sqm ||
      old.style != style ||
      old.timeS != timeS;
}
