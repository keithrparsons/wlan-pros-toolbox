// Painters for the Wi-Fi Classroom tool What an Interferer Costs.
//
//   - IcMeterPainter: a level meter in dBm. Three zones (not heard; heard
//     only if it is Wi-Fi; heard whatever sent it), the noise floor, preamble
//     detect and energy detect, the gap between them bracketed with its dB
//     and power ratio, and the selected source's level in your channel.
//   - IcDistancePainter: how far away the same transmitter still makes your
//     radio wait, as Wi-Fi and as anything else, to one linear scale.
//   - IcTimelinePainter: one 60 ms sample of your channel. The source's time
//     on the air above, what your radio does below: waits (hatched), sends
//     into it (cross-hatched), or is free.
//
// Fixed axes: the meter always runs -100 to -30 dBm and the timeline 0 to
// 60 ms, so changing a setting moves marks, never the scale.
//
// Colors, text styles and the presenter scale are handed in by the stage, so
// these painters read no theme themselves. ASCII only (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/interferer_cost_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Everything the painters take from the theme.
@immutable
class IcPaintStyle {
  const IcPaintStyle({
    required this.scale,
    required this.surface,
    required this.grid,
    required this.axis,
    required this.source,
    required this.yours,
    required this.wait,
    required this.hit,
    required this.label,
    required this.strongLabel,
    required this.sourceLabel,
  });

  final PresenterScale scale;
  final Color surface;
  final Color grid;
  final Color axis;
  final Color source;
  final Color yours;

  /// Waiting (status warning hue, always with its hatch and word).
  final Color wait;

  /// Sending into it (status danger hue, always with its cross-hatch and
  /// word).
  final Color hit;
  final TextStyle label;
  final TextStyle strongLabel;
  final TextStyle sourceLabel;
}

/// The meter's fixed range, dBm.
const double kIcMeterMin = -100;
const double kIcMeterMax = -30;

TextPainter _tp(
  String s,
  TextStyle style, {
  TextAlign align = TextAlign.left,
}) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
  textAlign: align,
)..layout();

/// Paints [s] with its anchor at [at]; ax/ay 0..1 pick the anchor point.
/// Clamped inside [width] when given.
Rect _text(
  Canvas canvas,
  String s,
  TextStyle style,
  Offset at, {
  double ax = 0,
  double ay = 0,
  double? width,
  TextAlign align = TextAlign.left,
  Color? backing,
}) {
  final TextPainter tp = _tp(s, style, align: align);
  Offset o = at - Offset(tp.width * ax, tp.height * ay);
  if (width != null) {
    o = Offset(o.dx.clamp(2, math.max(2, width - tp.width - 2)), o.dy);
  }
  if (backing != null) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (o & tp.size).inflate(2),
        const Radius.circular(3),
      ),
      Paint()..color = backing.withValues(alpha: 0.9),
    );
  }
  tp.paint(canvas, o);
  return o & tp.size;
}

void _dashedV(Canvas canvas, double x, double y0, double y1, Paint p) {
  const double dash = 4;
  const double gap = 3;
  for (double y = y0; y < y1; y += dash + gap) {
    canvas.drawLine(Offset(x, y), Offset(x, math.min(y + dash, y1)), p);
  }
}

/// Diagonal hatching inside [r]; [cross] adds the other diagonal.
void _hatch(
  Canvas canvas,
  Rect r,
  Color c,
  double stroke, {
  bool cross = false,
}) {
  canvas.save();
  canvas.clipRect(r);
  final Paint p = Paint()
    ..color = c
    ..strokeWidth = stroke;
  const double step = 6;
  for (double x = r.left - r.height; x < r.right; x += step) {
    canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), p);
    if (cross) {
      canvas.drawLine(Offset(x, r.top), Offset(x + r.height, r.bottom), p);
    }
  }
  canvas.restore();
}

// ── Level meter ─────────────────────────────────────────────────────────────

class IcMeterPainter extends CustomPainter {
  IcMeterPainter({required this.result, required this.style});

  final IcResult result;
  final IcPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale k = style.scale;
    final double pad = 8 * k.marker;
    final double left = pad;
    final double right = size.width - pad;
    double x(double dbm) =>
        left +
        (dbm - kIcMeterMin) / (kIcMeterMax - kIcMeterMin) * (right - left);

    final double lineH = _tp('Ag', style.label).height;
    final double pd = result.preambleDetectDbm;
    const double ed = kIcEnergyDetectDbm;
    final double xPd = x(pd);
    final double xEd = x(ed);

    // Row A: the gap, the picture's centerpiece, over a bracket with end
    // ticks that spans preamble detect to energy detect.
    final TextStyle gapStyle = style.strongLabel.copyWith(
      fontSize: (style.strongLabel.fontSize ?? 12) * 1.25,
    );
    final String gap =
        '${result.gapDb.round()} dB = '
        '${result.gapPowerRatio.round()}x the power';
    final TextPainter gapTp = _tp(gap, gapStyle, align: TextAlign.center);
    final double mid = (xPd + xEd) / 2;
    gapTp.paint(
      canvas,
      Offset((mid - gapTp.width / 2).clamp(2, size.width - gapTp.width - 2), 2),
    );
    final double bracketY = 2 + gapTp.height + 4 * k.marker;
    final double tickH = 6 * k.marker;
    final Paint br = Paint()
      ..color = style.axis
      ..strokeWidth = k.strokeWidth(2);
    canvas.drawLine(Offset(xPd, bracketY), Offset(xEd, bracketY), br);
    canvas.drawLine(Offset(xPd, bracketY), Offset(xPd, bracketY + tickH), br);
    canvas.drawLine(Offset(xEd, bracketY), Offset(xEd, bracketY + tickH), br);

    final double barTop = bracketY + tickH + 2;
    final double barH = math.max(
      44 * k.marker,
      size.height - barTop - (4 * lineH + 22),
    );
    final double barBottom = barTop + barH;
    final double axisY = barBottom + 3;

    // Zones.
    final Rect notHeard = Rect.fromLTRB(left, barTop, xPd, barBottom);
    final Rect wifiOnly = Rect.fromLTRB(xPd, barTop, xEd, barBottom);
    final Rect anything = Rect.fromLTRB(xEd, barTop, right, barBottom);
    canvas.drawRect(
      notHeard,
      Paint()..color = style.grid.withValues(alpha: 0.10),
    );
    canvas.drawRect(
      wifiOnly,
      Paint()..color = style.source.withValues(alpha: 0.22),
    );
    canvas.drawRect(
      anything,
      Paint()..color = style.source.withValues(alpha: 0.42),
    );
    canvas.drawRect(
      Rect.fromLTRB(left, barTop, right, barBottom),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = style.grid
        ..strokeWidth = k.strokeWidth(1),
    );

    // Noise floor, dashed, named at the bottom of the bar.
    final double xN = x(kIcNoiseFloorDbm);
    _dashedV(
      canvas,
      xN,
      barTop,
      barBottom,
      Paint()
        ..color = style.axis
        ..strokeWidth = k.strokeWidth(1),
    );

    // Thresholds: solid lines from the bracket through the bar.
    final Paint th = Paint()
      ..color = style.axis
      ..strokeWidth = k.strokeWidth(2);
    canvas.drawLine(Offset(xPd, bracketY), Offset(xPd, barBottom + 3), th);
    canvas.drawLine(Offset(xEd, bracketY), Offset(xEd, barBottom + 3), th);

    // The selected source's marker line goes under the words.
    final IcSourceResult s = result.selected;
    final double? lv = s.levelInChannelDbm?.clamp(kIcMeterMin, kIcMeterMax);
    final double rowD = axisY + 4 + lineH + 2;
    final double rowE = rowD + 2 * lineH + 4;
    if (lv != null) {
      final double mx = x(lv);
      canvas.drawLine(
        Offset(mx, barTop - 2),
        Offset(mx, barBottom + 3),
        Paint()
          ..color = style.surface
          ..strokeWidth = k.strokeWidth(6),
      );
      canvas.drawLine(
        Offset(mx, barTop - 2),
        Offset(mx, barBottom + 3),
        Paint()
          ..color = style.source
          ..strokeWidth = k.strokeWidth(3),
      );
    }

    // Zone words in the top part of the bar, backed so the marker passes
    // behind them. Shorter words when a zone is narrow.
    void zoneWord(Rect r, List<String> options) {
      for (final String s in options) {
        final TextPainter tp = _tp(s, style.label, align: TextAlign.center);
        if (tp.width > r.width - 8) continue;
        final Offset o = Offset(r.center.dx - tp.width / 2, r.top + 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (o & tp.size).inflate(1.5),
            const Radius.circular(3),
          ),
          Paint()..color = style.surface.withValues(alpha: 0.8),
        );
        tp.paint(canvas, o);
        return;
      }
    }

    zoneWord(notHeard, <String>['not heard', 'no']);
    zoneWord(wifiOnly, <String>['heard if Wi-Fi', 'if Wi-Fi', 'Wi-Fi']);
    zoneWord(anything, <String>['heard, whatever it is', 'anything']);
    for (final String w in <String>['noise -95', 'noise']) {
      final TextPainter tp = _tp(w, style.label);
      if (xN + 4 + tp.width > xPd - 4) continue;
      tp.paint(canvas, Offset(xN + 4, barBottom - tp.height - 3));
      break;
    }

    // Axis ticks every 10 dB.
    final Paint tick = Paint()
      ..color = style.grid
      ..strokeWidth = k.strokeWidth(1);
    for (double v = kIcMeterMin; v <= kIcMeterMax; v += 10) {
      canvas.drawLine(Offset(x(v), barBottom), Offset(x(v), axisY + 3), tick);
      _text(
        canvas,
        v.round().toString(),
        style.label,
        Offset(x(v), axisY + 4),
        ax: 0.5,
        width: size.width,
      );
    }

    // Row D: threshold names, preamble detect ending at its line and energy
    // detect starting at its line.
    final TextPainter pdTp = _tp(
      'Preamble detect\n${pd.round()} dBm, Wi-Fi',
      style.strongLabel,
      align: TextAlign.right,
    );
    pdTp.paint(canvas, Offset(math.max(2, xPd - 4 - pdTp.width), rowD));
    final TextPainter edTp = _tp(
      'Energy detect\n${ed.round()} dBm, anything',
      style.strongLabel,
    );
    edTp.paint(
      canvas,
      Offset(math.min(xEd + 4, size.width - edTp.width - 2), rowD),
    );

    // Row E: the selected source's level.
    if (lv == null) {
      _text(
        canvas,
        '${s.source.label}: not on this band',
        style.sourceLabel,
        Offset(left, rowE),
        width: size.width,
      );
      return;
    }
    final double mx = x(lv);
    final Offset c = Offset(mx, barTop + barH * 0.68);
    canvas.drawCircle(c, k.markerSize(7), Paint()..color = style.surface);
    canvas.drawCircle(c, k.markerSize(5.5), Paint()..color = style.source);
    final double caret = k.markerSize(5);
    canvas.drawPath(
      Path()
        ..moveTo(mx, rowE - caret - 1)
        ..lineTo(mx - caret, rowE - 1)
        ..lineTo(mx + caret, rowE - 1)
        ..close(),
      Paint()..color = style.source,
    );
    _text(
      canvas,
      '${s.source.label}: ${s.levelInChannelDbm!.round()} dBm',
      style.sourceLabel,
      Offset(mx, rowE),
      ax: 0.5,
      width: size.width,
      backing: style.surface,
    );
  }

  @override
  bool shouldRepaint(IcMeterPainter old) =>
      old.result != result || old.style != style;
}

// ── Heard-at distances ──────────────────────────────────────────────────────

class IcDistancePainter extends CustomPainter {
  IcDistancePainter({
    required this.result,
    required this.style,
    required this.format,
  });

  final IcResult result;
  final IcPaintStyle style;

  /// Distance in the screen's units.
  final String Function(double m) format;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale k = style.scale;
    final double lineH = _tp('Ag', style.label).height;
    final double left = 10 * k.marker;
    final double right = size.width - 8;
    final double full = right - left;
    final double rowH = (size.height - 4) / 2;
    final double barH = math.max(10 * k.marker, rowH - lineH - 8);

    void row(int i, String name, double metres, {required bool solid}) {
      final double top = 2 + i * rowH;
      _text(
        canvas,
        name,
        style.strongLabel,
        Offset(left, top),
        width: size.width,
      );
      final double y = top + lineH + 3;
      final double w = full * metres / result.wifiHeardAtM;
      final Rect bar = Rect.fromLTWH(left, y, math.max(w, 2), barH);
      if (solid) {
        canvas.drawRect(
          bar,
          Paint()..color = style.source.withValues(alpha: 0.85),
        );
      } else {
        canvas.drawRect(
          bar,
          Paint()..color = style.source.withValues(alpha: 0.25),
        );
        canvas.drawRect(
          bar,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = style.source
            ..strokeWidth = k.strokeWidth(2),
        );
      }
      // Your radio at the start of every bar.
      canvas.drawCircle(
        Offset(left, y + barH / 2),
        k.markerSize(5),
        Paint()..color = style.yours,
      );
      final String d = format(metres);
      final TextPainter tp = _tp(d, style.strongLabel);
      final bool inside = tp.width + 12 < w && solid;
      final Offset at = inside
          ? Offset(left + w - tp.width - 6, y + (barH - tp.height) / 2)
          : Offset(
              math.min(left + w + 6, size.width - tp.width - 2),
              y + (barH - tp.height) / 2,
            );
      if (inside) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (at & tp.size).inflate(2),
            const Radius.circular(3),
          ),
          Paint()..color = style.surface.withValues(alpha: 0.9),
        );
      }
      tp.paint(canvas, at);
    }

    row(
      0,
      'Another Wi-Fi radio makes you wait out to',
      result.wifiHeardAtM,
      solid: true,
    );
    row(
      1,
      'Non-Wi-Fi energy of the same power, only out to',
      result.energyHeardAtM,
      solid: false,
    );
  }

  @override
  bool shouldRepaint(IcDistancePainter old) =>
      old.result != result || old.style != style;
}

// ── Timeline ────────────────────────────────────────────────────────────────

class IcTimelinePainter extends CustomPainter {
  IcTimelinePainter({
    required this.result,
    required this.spans,
    required this.style,
  });

  final IcResult result;
  final List<IcSpan> spans;
  final IcPaintStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale k = style.scale;
    final double lineH = _tp('Ag', style.label).height;
    final double left = 6;
    final double right = size.width - 8;
    double x(double ms) => left + ms / kIcTimelineMs * (right - left);

    final IcSourceResult s = result.selected;
    final double laneH = math.max(
      14 * k.marker,
      (size.height - 3 * lineH - 16) / 2,
    );
    final double lane1Top = lineH + 2;
    final double lane2Top = lane1Top + laneH + lineH + 6;
    final double axisY = lane2Top + laneH + 2;

    _text(
      canvas,
      '${s.source.label}, on the air in your channel',
      style.strongLabel,
      Offset(left, 0),
      width: size.width,
    );
    _text(
      canvas,
      'Your radio',
      style.strongLabel,
      Offset(left, lane1Top + laneH + 3),
      width: size.width,
    );

    // Lane frames.
    final Paint frame = Paint()
      ..style = PaintingStyle.stroke
      ..color = style.grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final Rect lane1 = Rect.fromLTRB(left, lane1Top, right, lane1Top + laneH);
    final Rect lane2 = Rect.fromLTRB(left, lane2Top, right, lane2Top + laneH);
    canvas.drawRect(lane1, frame);

    // Your radio is free wherever nothing else happens: a teal base.
    canvas.drawRect(
      lane2,
      Paint()..color = style.yours.withValues(alpha: 0.18),
    );
    canvas.drawRect(lane2, frame);

    if (s.heard == IcHeard.absent) {
      _text(
        canvas,
        'Not on this band: nothing to wait for',
        style.label,
        lane1.center,
        ax: 0.5,
        ay: 0.5,
      );
    }

    // Mains cycle boundaries for the oven.
    if (s.source == IcSource.microwave && s.heard != IcHeard.absent) {
      final double t = icMicrowavePeriodMs(result.config.mains);
      final Paint cyc = Paint()
        ..color = style.grid
        ..strokeWidth = 1;
      for (double c = 0; c <= kIcTimelineMs; c += t) {
        _dashedV(canvas, x(c), lane1Top - 2, lane2.bottom, cyc);
      }
    }

    for (final IcSpan sp in spans) {
      final double x0 = x(sp.startMs);
      final double x1 = math.max(x(sp.endMs), x0 + 1.5);
      final Rect r1 = Rect.fromLTRB(x0, lane1Top, x1, lane1Top + laneH);
      canvas.drawRect(
        r1,
        Paint()..color = style.source.withValues(alpha: 0.85),
      );
      final Rect r2 = Rect.fromLTRB(x0, lane2Top, x1, lane2Top + laneH);
      canvas.drawRect(r2, Paint()..color = style.surface);
      if (s.heard.waits) {
        _hatch(canvas, r2, style.wait, k.strokeWidth(1.5));
        canvas.drawRect(
          r2,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = style.wait
            ..strokeWidth = k.strokeWidth(1),
        );
      } else {
        _hatch(canvas, r2, style.hit, k.strokeWidth(1.2), cross: true);
        canvas.drawRect(
          r2,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = style.hit
            ..strokeWidth = k.strokeWidth(1),
        );
      }
    }

    // Axis: 0 to 60 ms every 10.
    final Paint tick = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (double t = 0; t <= kIcTimelineMs; t += 10) {
      canvas.drawLine(Offset(x(t), axisY), Offset(x(t), axisY + 4), tick);
      _text(
        canvas,
        t == kIcTimelineMs ? '${t.round()} ms' : t.round().toString(),
        style.label,
        Offset(x(t), axisY + 5),
        ax: 0.5,
        width: size.width,
      );
    }
  }

  @override
  bool shouldRepaint(IcTimelinePainter old) =>
      old.result != result || old.style != style || old.spans != spans;
}
