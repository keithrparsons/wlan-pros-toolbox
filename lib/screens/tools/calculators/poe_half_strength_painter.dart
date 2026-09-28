// The drawing for the Wi-Fi Classroom tool "PoE: Why the New AP Runs at
// Half Strength" (poe-half-strength).
//
// A switch on the left, a cable, and the generic AP: its power light (lit in
// every case, which is the lesson) and its three radios, each drawn as four
// stream marks. A live stream is a filled mark; a stream the AP has turned
// off is a hollow, dashed mark; a radio with none live says "Off" in words.
// Under it, a power bar from 0 to 60 W: the watts that reach the AP, and a
// tick at the about 29 W this AP needs for full function.
//
// THEME: colors come from context.colors via the stage. The live-stream fill
// is the brand lime (primary) as a FILL with an ink outline, so on light it
// never carries contrast alone (§8.20.2 rule 1); state is also in words.
// Sizes follow PresenterScale. ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/poe_half_strength_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';

@immutable
class PhPalette {
  const PhPalette({
    required this.ink,
    required this.muted,
    required this.faint,
    required this.fill,
    required this.surface,
    required this.boxBorder,
    required this.track,
    required this.fontFamily,
  });

  final Color ink;
  final Color muted;
  final Color faint;
  final Color fill;
  final Color surface;
  final Color boxBorder;
  final Color track;
  final String? fontFamily;

  @override
  bool operator ==(Object other) =>
      other is PhPalette &&
      other.ink == ink &&
      other.muted == muted &&
      other.faint == faint &&
      other.fill == fill &&
      other.surface == surface &&
      other.boxBorder == boxBorder &&
      other.track == track &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(
    ink,
    muted,
    faint,
    fill,
    surface,
    boxBorder,
    track,
    fontFamily,
  );
}

/// Words drawn on the stage, in one place for the tests.
abstract final class PhStageText {
  static const String switchBox = 'Switch';
  static const String ap = 'Wi-Fi 7 AP';
  static const String light = 'Power light: on';
  static const String barMax = 'Power at the AP, 0 to 60 W';
  static String need() =>
      'Full function: about ${PhAp.fullFunctionWatts.round()} W';
}

class PhStagePainter extends CustomPainter {
  PhStagePainter({
    required this.config,
    required this.palette,
    required this.scale,
  });

  final PhConfig config;
  final PhPalette palette;
  final PresenterScale scale;

  static const double barMaxWatts = 60;

  double get _stroke => scale.strokeWidth(2);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double font = math.min(
      scale.paintFont(math.min(w / 34, h / 22).clamp(10.0, 18.0)),
      24,
    );
    final PhConfig c = config;
    // A tall or small stage (the presenter layout, a phone) stacks the
    // switch above the AP; a wide one puts it to the left.
    final bool narrow = w < h * 1.15 || w < 520;

    final Rect sw;
    final Rect ap;
    if (narrow) {
      sw = Rect.fromLTRB(w * 0.06, h * 0.03, w * 0.94, h * 0.03 + font * 3.6);
      ap = Rect.fromLTRB(w * 0.06, sw.bottom + font * 3.4, w * 0.94, h * 0.70);
    } else {
      sw = Rect.fromLTWH(w * 0.03, h * 0.24, w * 0.22, font * 5.4);
      ap = Rect.fromLTRB(w * 0.34, h * 0.04, w * 0.97, h * 0.70);
    }

    // ── The switch and the cable ─────────────────────────────────────────
    final Offset cableA = narrow ? sw.bottomCenter : sw.centerRight;
    final Offset cableB = narrow
        ? Offset(sw.center.dx, ap.top)
        : Offset(ap.left, sw.center.dy);
    _line(canvas, cableA, cableB, palette.ink, _stroke * 1.4);
    _box(canvas, sw);
    if (narrow) {
      _textAt(
        canvas,
        '${PhStageText.switchBox}: ${c.port.standard} port',
        Offset(sw.center.dx, sw.top + font * 1.2),
        font * 1.05,
        palette.ink,
        sw.width - font,
        bold: true,
      );
      _textAt(
        canvas,
        '${PhFormat.watts(c.port.pseWatts)} sent',
        Offset(sw.center.dx, sw.top + font * 2.5),
        font,
        palette.muted,
        sw.width - font,
      );
      _textAt(
        canvas,
        '${PhFormat.watts(c.port.pdWatts)} reaches the AP',
        Offset(cableA.dx + font * 0.8, (cableA.dy + cableB.dy) / 2),
        font * 0.95,
        palette.muted,
        w * 0.45,
        align: TextAlign.left,
      );
    } else {
      _textAt(
        canvas,
        PhStageText.switchBox,
        Offset(sw.center.dx, sw.top + font),
        font * 1.05,
        palette.ink,
        sw.width - font,
        bold: true,
      );
      _textAt(
        canvas,
        '${c.port.standard} port',
        Offset(sw.center.dx, sw.top + font * 2.4),
        font,
        palette.ink,
        sw.width - font * 0.5,
      );
      _textAt(
        canvas,
        '${PhFormat.watts(c.port.pseWatts)} sent',
        Offset(sw.center.dx, sw.top + font * 3.8),
        font,
        palette.muted,
        sw.width - font * 0.5,
      );
      _textAt(
        canvas,
        '${PhFormat.watts(c.port.pdWatts)} reaches the AP',
        Offset((cableA.dx + cableB.dx) / 2, cableA.dy + font * 2.2),
        font * 0.9,
        palette.muted,
        (cableB.dx - cableA.dx) - font * 0.4,
      );
    }

    // ── The AP ───────────────────────────────────────────────────────────
    _box(canvas, ap);
    _textAt(
      canvas,
      PhStageText.ap,
      Offset(ap.left + font, ap.top + font * 1.1),
      font * 1.1,
      palette.ink,
      ap.width * 0.5,
      bold: true,
      align: TextAlign.left,
    );
    // Power light: a lit dot with a ring, and the words.
    final Offset led = Offset(ap.right - font * 1.2, ap.top + font * 1.1);
    canvas.drawCircle(led, font * 0.5, Paint()..color = palette.fill);
    canvas.drawCircle(
      led,
      font * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke * 0.75
        ..color = palette.ink,
    );
    _textAt(
      canvas,
      PhStageText.light,
      Offset(led.dx - font * 0.9, led.dy),
      font,
      palette.ink,
      ap.width * 0.45,
      align: TextAlign.right,
      anchorRight: true,
    );

    // Radios: one row each. Columns are sized from the type, not the box.
    final double rowsTop = ap.top + font * 2.6;
    final double rowH = (ap.bottom - font * 0.6 - rowsTop) / 3;
    final double markR = math.min(rowH * 0.28, font * 0.75);
    final double gap = markR * 2.7;
    final double x0 = ap.left + font * 5.6 + markR;
    final double stateX = x0 + (PhAp.fullStreams - 1) * gap + markR + font;
    for (int i = 0; i < PhRadio.values.length; i++) {
      final PhRadio r = PhRadio.values[i];
      final double cy = rowsTop + rowH * (i + 0.5);
      final int live = c.streamsOn(r);
      _textAt(
        canvas,
        r.label,
        Offset(ap.left + font, cy),
        font * 1.05,
        palette.ink,
        font * 4.8,
        bold: true,
        align: TextAlign.left,
      );
      for (int s = 0; s < PhAp.fullStreams; s++) {
        final Offset m = Offset(x0 + s * gap, cy);
        if (s < live) {
          canvas.drawCircle(m, markR, Paint()..color = palette.fill);
          canvas.drawCircle(
            m,
            markR,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _stroke * 0.75
              ..color = palette.ink,
          );
        } else {
          _dashedCircle(canvas, m, markR, palette.faint);
        }
      }
      _textAt(
        canvas,
        live == 0 ? 'Off' : c.radioState(r),
        Offset(stateX, cy),
        font * 1.05,
        live == 0 ? palette.muted : palette.ink,
        ap.right - stateX - font * 0.5,
        align: TextAlign.left,
        bold: live > 0,
      );
    }

    // ── Power bar ────────────────────────────────────────────────────────
    final Rect bar = Rect.fromLTRB(
      w * 0.05,
      h * 0.83,
      w * 0.95,
      h * 0.83 + math.max(font * 0.9, 8),
    );
    double xAt(double watts) =>
        bar.left + bar.width * (watts / barMaxWatts).clamp(0.0, 1.0);
    final RRect track = RRect.fromRectAndRadius(
      bar,
      Radius.circular(bar.height / 2),
    );
    canvas.drawRRect(track, Paint()..color = palette.track);
    canvas.drawRRect(
      RRect.fromLTRBR(
        bar.left,
        bar.top,
        xAt(c.port.pdWatts),
        bar.bottom,
        Radius.circular(bar.height / 2),
      ),
      Paint()..color = palette.fill,
    );
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke * 0.6
        ..color = palette.boxBorder,
    );
    final double needX = xAt(PhAp.fullFunctionWatts);
    canvas.drawLine(
      Offset(needX, bar.top - font * 0.6),
      Offset(needX, bar.bottom + font * 0.6),
      Paint()
        ..color = palette.ink
        ..strokeWidth = _stroke * 1.2
        ..strokeCap = StrokeCap.round,
    );
    _textAt(
      canvas,
      PhStageText.need(),
      Offset(needX, bar.top - font * 1.5),
      font,
      palette.ink,
      w * 0.5,
    );
    _textAt(
      canvas,
      'At the AP: ${PhFormat.watts(c.port.pdWatts)}',
      Offset(bar.left, bar.bottom + font * 1.2),
      font,
      palette.ink,
      w * 0.45,
      align: TextAlign.left,
      bold: true,
    );
    _textAt(
      canvas,
      '0 W',
      Offset(bar.left, bar.top - font * 1.5),
      font * 0.9,
      palette.muted,
      font * 4,
      align: TextAlign.left,
    );
    _textAt(
      canvas,
      '60 W',
      Offset(bar.right, bar.top - font * 1.5),
      font * 0.9,
      palette.muted,
      font * 4,
      align: TextAlign.right,
      anchorRight: true,
    );
  }

  // ── Primitives ─────────────────────────────────────────────────────────

  void _box(Canvas c, Rect r) {
    final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
    c.drawRRect(rr, Paint()..color = palette.surface);
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = palette.boxBorder,
    );
  }

  void _line(Canvas c, Offset a, Offset b, Color color, double width) {
    c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _dashedCircle(Canvas c, Offset at, double r, Color color) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke * 0.75
      ..color = color;
    const int n = 10;
    for (int i = 0; i < n; i++) {
      final double a = 2 * math.pi * i / n;
      c.drawArc(
        Rect.fromCircle(center: at, radius: r),
        a,
        math.pi / n,
        false,
        p,
      );
    }
  }

  /// Draws [s] centered vertically on [at]: centered on it, left-aligned
  /// from it, or right-aligned to it with [anchorRight].
  void _textAt(
    Canvas c,
    String s,
    Offset at,
    double size,
    Color color,
    double maxWidth, {
    bool bold = false,
    TextAlign align = TextAlign.center,
    bool anchorRight = false,
  }) {
    final TextPainter t = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontFamily: palette.fontFamily,
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          height: 1.2,
        ),
      ),
      textAlign: align,
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: math.max(1, maxWidth));
    final double dx = anchorRight
        ? at.dx - t.width
        : align == TextAlign.left
        ? at.dx
        : at.dx - t.width / 2;
    t.paint(c, Offset(dx, at.dy - t.height / 2));
  }

  @override
  bool shouldRepaint(PhStagePainter old) =>
      old.config != config || old.palette != palette || old.scale != scale;
}
