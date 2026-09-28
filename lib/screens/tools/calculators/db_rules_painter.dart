// DbRulesPainter: the picture in the Wi-Fi Classroom tool Decibels in Your
// Head, the Rules of 3 and 10 (db-rules).
//
// Two scales, one above the other, joined by a line for every whole dB:
//   - top: power on a LINEAR milliwatt bar, full length at -60 dBm. The fill
//     is the signal; a dashed line marks the -70 dBm reference (10%).
//   - bottom: the same levels on the dB ruler the slider uses, evenly spaced
//     from -80 to -60 dBm.
// The joining lines start evenly spaced on the ruler and bunch toward zero on
// the linear bar, which is the whole lesson: equal dB steps are equal RATIOS,
// not equal amounts. The signal's line is the accent and thickest; the
// reference's is dashed; the rest are neutral.
//
// COLOR: passed in from context.colors by the stage. Nothing rests on color
// alone: the signal line is also the thickest and ends in a marker, the
// reference line is dashed, and both are named in the legend and readouts.
// On light, the lime fill carries an ink outline (GL-003 §8.20.2 rule 1).
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/db_rules_model.dart';

class DbRulesPainter extends CustomPainter {
  DbRulesPainter({
    required this.dbm,
    required this.ink,
    required this.neutral,
    required this.secondary,
    required this.accent,
    required this.track,
    required this.surface,
    required this.stroke,
    required this.marker,
    required this.fontScale,
    required this.labelStyle,
  });

  final int dbm;
  final Color ink;
  final Color neutral;
  final Color secondary;
  final Color accent;
  final Color track;
  final Color surface;

  /// Presenter stroke factor.
  final double stroke;

  /// Presenter marker factor.
  final double marker;

  /// Presenter text factor.
  final double fontScale;

  final TextStyle labelStyle;

  static const double _barHeight = 26;
  static const double _rulerLabels = 22;
  static const double _tick = 7;

  double _left(Size s) => 10 * marker;
  double _width(Size s) => s.width - 2 * _left(s);

  double xLinear(Size s, num d) =>
      _left(s) + DbRules.barShare(d).clamp(0.0, 1.0) * _width(s);

  double xRuler(Size s, num d) =>
      _left(s) +
      (d - DbRules.minDbm) / (DbRules.maxDbm - DbRules.minDbm) * _width(s);

  @override
  void paint(Canvas canvas, Size size) {
    final double barH = _barHeight * marker;
    final double labelH = _rulerLabels * fontScale;
    final double rulerY = size.height - labelH - _tick * marker;
    final double left = _left(size);
    final double right = left + _width(size);
    final Radius r = Radius.circular(barH / 4);

    // Linear bar: track, fill, outline.
    canvas.drawRRect(
      RRect.fromLTRBR(left, 0, right, barH, r),
      Paint()..color = track,
    );
    final double xFill = xLinear(size, dbm);
    final RRect fill = RRect.fromLTRBR(left, 0, xFill, barH, r);
    canvas.drawRRect(fill, Paint()..color = accent);
    canvas.drawRRect(
      fill,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * stroke
        ..color = ink,
    );

    // Joining lines, one per whole dB. The signal and the reference last, so
    // they sit on top.
    final Paint thin = Paint()
      ..strokeWidth = 1 * stroke
      ..color = neutral;
    for (int d = DbRules.minDbm; d <= DbRules.maxDbm; d++) {
      if (d == dbm || d == DbRules.referenceDbm) continue;
      canvas.drawLine(
        Offset(xLinear(size, d), barH),
        Offset(xRuler(size, d), rulerY),
        thin,
      );
    }
    _dashed(
      canvas,
      Offset(xLinear(size, DbRules.referenceDbm), 0),
      Offset(xLinear(size, DbRules.referenceDbm), barH),
      Paint()
        ..strokeWidth = 2 * stroke
        ..color = ink,
    );
    if (dbm != DbRules.referenceDbm) {
      _dashed(
        canvas,
        Offset(xLinear(size, DbRules.referenceDbm), barH),
        Offset(xRuler(size, DbRules.referenceDbm), rulerY),
        Paint()
          ..strokeWidth = 1.5 * stroke
          ..color = secondary,
      );
    }
    final Offset top = Offset(xFill, barH);
    final Offset bottom = Offset(xRuler(size, dbm), rulerY);
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..strokeWidth = 4.5 * stroke
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..strokeWidth = 2.5 * stroke
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );

    // The dB ruler.
    canvas.drawLine(
      Offset(left, rulerY),
      Offset(right, rulerY),
      Paint()
        ..strokeWidth = 1.5 * stroke
        ..color = secondary,
    );
    for (int d = DbRules.minDbm; d <= DbRules.maxDbm; d++) {
      final bool major = d % 10 == 0;
      final double x = xRuler(size, d);
      canvas.drawLine(
        Offset(x, rulerY),
        Offset(x, rulerY + (major ? _tick : _tick / 2) * marker),
        Paint()
          ..strokeWidth = (major ? 1.5 : 1) * stroke
          ..color = secondary,
      );
    }
    for (final int d in <int>[DbRules.minDbm, -70, DbRules.maxDbm]) {
      _label(
        canvas,
        '$d dBm',
        Offset(xRuler(size, d), rulerY + _tick * marker + 2),
        size,
      );
    }
    // The signal's marker on the ruler.
    canvas.drawCircle(bottom, 6 * marker, Paint()..color = surface);
    canvas.drawCircle(bottom, 5 * marker, Paint()..color = ink);
    canvas.drawCircle(bottom, 3 * marker, Paint()..color = accent);
  }

  void _label(Canvas canvas, String text, Offset at, Size size) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          fontSize: (labelStyle.fontSize ?? 12) * fontScale,
          color: secondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double x = (at.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
    tp.paint(canvas, Offset(x, at.dy));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    final double len = (b - a).distance;
    if (len <= 0) return;
    final Offset dir = (b - a) / len;
    final double dash = 5 * marker;
    final double gap = 4 * marker;
    double t = 0;
    while (t < len) {
      final double e = (t + dash).clamp(0.0, len);
      canvas.drawLine(a + dir * t, a + dir * e, p);
      t = e + gap;
    }
  }

  @override
  bool shouldRepaint(DbRulesPainter old) =>
      old.dbm != dbm ||
      old.ink != ink ||
      old.neutral != neutral ||
      old.secondary != secondary ||
      old.accent != accent ||
      old.track != track ||
      old.surface != surface ||
      old.stroke != stroke ||
      old.marker != marker ||
      old.fontScale != fontScale ||
      old.labelStyle != labelStyle;
}
