// The drawing for the Wi-Fi Classroom tool "Why a Long Wi-Fi Password
// Matters More on WPA2" (wpa2-password).
//
// Three boxes: the device(s) on the left, the AP on the right, and the
// attacker's computer below. A solid line is over the air; a dashed line is a
// recording. The ACCENT path is where each guess is checked, the one thing
// the tool teaches: a loop inside the attacker's computer (offline), or a
// line to the AP (a live exchange). Every mark also carries words, so no
// state rests on color alone.
//
// Nothing here is a how-to: the boxes are "a device", "your AP" and "the
// attacker's computer"; no tool, command or step is named.
//
// THEME: colors are passed in from context.colors (textAccent is the
// foreground lime, §8.20.2 rule 1). Sizes follow PresenterScale. ASCII copy,
// no em dashes (GL-004).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/wpa2_password_model.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Colors and sizes the painter needs, read from the theme by the stage.
@immutable
class WpPalette {
  const WpPalette({
    required this.ink,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.box,
    required this.boxBorder,
    required this.fontFamily,
  });

  final Color ink;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color box;
  final Color boxBorder;
  final String? fontFamily;

  @override
  bool operator ==(Object other) =>
      other is WpPalette &&
      other.ink == ink &&
      other.muted == muted &&
      other.faint == faint &&
      other.accent == accent &&
      other.box == box &&
      other.boxBorder == boxBorder &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode =>
      Object.hash(ink, muted, faint, accent, box, boxBorder, fontFamily);
}

/// Words drawn on the stage, in one place so tests can find them.
abstract final class WpStageText {
  static const String computer = "Attacker's computer";
  static const String ap = 'Your AP';
  static const String phone = 'Phone';
  static const String phoneWpa3 = 'Phone (WPA3)';
  static const String laptopWpa2 = 'Older laptop (WPA2 only)';
  static const String fourWay = '4-way handshake';
  static const String saeThenFourWay = 'SAE exchange, then 4-way handshake';
  static const String recordedOnce = 'Recorded once: one association';
  static const String saeRecording =
      'A recording of SAE lets no guess be checked';
  static const String loop = 'Guess, check, repeat';
  static const String loopLimit = 'Limited only by this computer';
  static const String liveGuess = 'Each guess: one live exchange with the AP';
  static const String nothingToCheck =
      'Nothing here to check a guess against: every guess has to go to the AP';
}

class WpStagePainter extends CustomPainter {
  WpStagePainter({
    required this.security,
    required this.guesses,
    required this.apFailed,
    required this.palette,
    required this.scale,
    required this.phase,
  }) : super(repaint: phase);

  final WpSecurity security;
  final int guesses;
  final int apFailed;
  final WpPalette palette;
  final PresenterScale scale;

  /// 0 to 1 while a guess is drawn; negative when none is in flight.
  final ValueListenable<double> phase;

  double get _stroke => scale.strokeWidth(2);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    // Type follows the stage, so a projector gets projector-sized labels.
    final double font = math.min(
      scale.paintFont(math.min(w / 32, h / 24).clamp(10.0, 18.0)),
      26,
    );
    final double boxW = w * 0.28;
    final double boxH = font * 4.6;
    final bool transition = security == WpSecurity.transition;

    final Rect ap = Rect.fromCenter(
      center: Offset(w * 0.84, h * (transition ? 0.30 : 0.20)),
      width: boxW,
      height: boxH,
    );
    final Rect phone = Rect.fromCenter(
      center: Offset(w * 0.16, h * (transition ? 0.12 : 0.20)),
      width: boxW,
      height: boxH,
    );
    final Rect? laptop = transition
        ? Rect.fromCenter(
            center: Offset(w * 0.16, h * 0.42),
            width: boxW,
            height: boxH,
          )
        : null;
    final Rect computer = Rect.fromLTRB(w * 0.06, h * 0.62, w * 0.94, h * 0.97);

    // ── Air links ────────────────────────────────────────────────────────
    final Offset phoneA = phone.centerRight;
    final Offset phoneB =
        ap.centerLeft - Offset(0, transition ? boxH * 0.2 : 0);
    _line(canvas, phoneA, phoneB, palette.muted, _stroke);
    _label(
      canvas,
      security == WpSecurity.wpa2
          ? WpStageText.fourWay
          : WpStageText.saeThenFourWay,
      Offset.lerp(phoneA, phoneB, 0.5)!,
      font,
      palette.muted,
      maxWidth: phoneB.dx - phoneA.dx - font,
      side: -1,
    );
    Offset? laptopMid;
    if (laptop != null) {
      final Offset a = laptop.centerRight;
      final Offset b = ap.centerLeft + Offset(0, boxH * 0.2);
      _line(canvas, a, b, palette.muted, _stroke);
      laptopMid = Offset.lerp(a, b, 0.3)!;
      _label(
        canvas,
        '${WpStageText.fourWay} (WPA2)',
        Offset.lerp(a, b, 0.74)!,
        font,
        palette.muted,
        maxWidth: (b.dx - a.dx) * 0.8,
        side: 1,
      );
    }

    // ── The recording (dashed) ───────────────────────────────────────────
    final Offset recFrom = laptopMid ?? Offset.lerp(phoneA, phoneB, 0.5)!;
    final Offset recTo = Offset(w * 0.34, computer.top);
    _dashed(canvas, recFrom, recTo, palette.faint, _stroke);
    final bool recordingUseful = security.exposedOffline;
    _label(
      canvas,
      recordingUseful ? WpStageText.recordedOnce : WpStageText.saeRecording,
      recordingUseful
          ? Offset(w * 0.66, h * (transition ? 0.53 : 0.44))
          : Offset(w * 0.22, h * 0.43),
      font,
      palette.muted,
      maxWidth: w * 0.34,
    );
    if (!recordingUseful) {
      // An X where the recording meets the computer: it carries nothing the
      // computer can check a guess against (said in words beside it).
      final double r = font * 0.55;
      final Paint x = Paint()
        ..color = palette.ink
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round;
      final Offset c = Offset.lerp(recFrom, recTo, 0.82)!;
      canvas.drawCircle(c, r * 1.7, Paint()..color = palette.box);
      canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), x);
      canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), x);
    }

    // ── The computer (drawn under its contents) ──────────────────────────
    _box(
      canvas,
      computer,
      WpStageText.computer,
      'Guesses tried: ${WpFormat.integer(guesses)}',
      font,
      topAligned: true,
    );

    // ── Where each guess is checked (accent) ─────────────────────────────
    final double p = phase.value;
    if (security.guessesAtAp) {
      final Offset from = Offset(w * 0.80, computer.top);
      final Offset to = ap.bottomCenter;
      _line(canvas, from, to, palette.accent, _stroke * 1.6);
      _arrowHead(canvas, from, to, palette.accent);
      _label(
        canvas,
        WpStageText.liveGuess,
        Offset(w * 0.60, h * 0.47),
        font,
        palette.accent,
        maxWidth: w * 0.28,
        bold: true,
      );
      if (p >= 0) {
        final double t = p < 0.5 ? p * 2 : (1 - p) * 2;
        _dot(canvas, Offset.lerp(from, to, t)!, font * 0.45);
      }
      final TextPainter none = _text(
        WpStageText.nothingToCheck,
        font,
        palette.muted,
        computer.width * 0.55,
        align: TextAlign.left,
      );
      none.paint(
        canvas,
        Offset(computer.left + font, computer.center.dy + font * 0.4),
      );
    } else {
      final double r = math.min(computer.height * 0.27, computer.width * 0.13);
      final Offset c = Offset(
        computer.right - r - font * 1.6,
        computer.center.dy + font * 0.6,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2 + 0.35,
        2 * math.pi - 0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke * 1.6
          ..strokeCap = StrokeCap.round
          ..color = palette.accent,
      );
      Offset on(double a) => c + Offset(math.cos(a), math.sin(a)) * r;
      _arrowHead(
        canvas,
        on(-math.pi / 2 - 0.7),
        on(-math.pi / 2 - 0.35),
        palette.accent,
      );
      if (p >= 0) {
        _dot(
          canvas,
          on(-math.pi / 2 + 0.35 + p * (2 * math.pi - 0.7)),
          font * 0.45,
        );
      }
      final double colLeft = computer.left + font;
      final double colW = (c.dx - r) - colLeft - font;
      final TextPainter t1 = _text(
        WpStageText.loop,
        font * 1.1,
        palette.accent,
        colW,
        bold: true,
        align: TextAlign.left,
      );
      final TextPainter t2 = _text(
        WpStageText.loopLimit,
        font,
        palette.ink,
        colW,
        align: TextAlign.left,
      );
      final double top = c.dy - (t1.height + t2.height + font * 0.3) / 2;
      t1.paint(canvas, Offset(colLeft, top));
      t2.paint(canvas, Offset(colLeft, top + t1.height + font * 0.3));
    }

    // ── Device and AP boxes on top ───────────────────────────────────────
    _box(
      canvas,
      phone,
      transition ? WpStageText.phoneWpa3 : WpStageText.phone,
      null,
      font,
    );
    if (laptop != null) {
      _box(canvas, laptop, WpStageText.laptopWpa2, null, font);
    }
    _box(
      canvas,
      ap,
      WpStageText.ap,
      'Failed attempts: ${WpFormat.integer(apFailed)}',
      font,
    );
  }

  // ── Primitives ─────────────────────────────────────────────────────────

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

  void _dashed(Canvas c, Offset a, Offset b, Color color, double width) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final double len = (b - a).distance;
    if (len <= 0) return;
    final Offset dir = (b - a) / len;
    final double dash = 6 * scale.marker;
    final double gap = 5 * scale.marker;
    for (double d = 0; d < len; d += dash + gap) {
      c.drawLine(a + dir * d, a + dir * math.min(d + dash, len), p);
    }
  }

  void _arrowHead(Canvas c, Offset from, Offset to, Color color) {
    final double len = (to - from).distance;
    if (len <= 0) return;
    final Offset dir = (to - from) / len;
    final Offset n = Offset(-dir.dy, dir.dx);
    final double s = scale.markerSize(7);
    final Path path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo((to - dir * s * 1.6 + n * s).dx, (to - dir * s * 1.6 + n * s).dy)
      ..lineTo((to - dir * s * 1.6 - n * s).dx, (to - dir * s * 1.6 - n * s).dy)
      ..close();
    c.drawPath(path, Paint()..color = color);
  }

  void _dot(Canvas c, Offset at, double r) {
    c.drawCircle(at, r + _stroke * 0.6, Paint()..color = palette.box);
    c.drawCircle(at, r, Paint()..color = palette.ink);
  }

  void _box(
    Canvas c,
    Rect r,
    String title,
    String? sub,
    double font, {
    bool topAligned = false,
  }) {
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(font * 0.6));
    c.drawRRect(rr, Paint()..color = palette.box);
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = palette.boxBorder,
    );
    final TextAlign align = topAligned ? TextAlign.left : TextAlign.center;
    final TextPainter t = _text(
      title,
      font * 1.05,
      palette.ink,
      r.width - font,
      bold: true,
      align: align,
    );
    final TextPainter? s = sub == null
        ? null
        : _text(sub, font, palette.ink, r.width - font, align: align);
    final double total = t.height + (s == null ? 0 : s.height + font * 0.2);
    final double top = topAligned
        ? r.top + font * 0.5
        : r.center.dy - total / 2;
    final double left = topAligned ? r.left + font * 0.7 : r.center.dx;
    t.paint(c, Offset(topAligned ? left : left - t.width / 2, top));
    if (s != null) {
      s.paint(
        c,
        Offset(
          topAligned ? left : left - s.width / 2,
          top + t.height + font * 0.2,
        ),
      );
    }
  }

  void _label(
    Canvas c,
    String s,
    Offset at,
    double font,
    Color color, {
    required double maxWidth,
    bool bold = false,
    double side = 0,
  }) {
    final TextPainter t = _text(
      s,
      font,
      color,
      math.max(40, maxWidth),
      bold: bold,
    );
    // side < 0: the label sits above [at]; side > 0: below it.
    final Offset center = side == 0
        ? at
        : at + Offset(0, side.sign * (t.height / 2 + font * 0.5));
    final Rect bg = Rect.fromCenter(
      center: center,
      width: t.width + font * 0.6,
      height: t.height + font * 0.2,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(bg, Radius.circular(font * 0.3)),
      Paint()..color = palette.box.withValues(alpha: 0.85),
    );
    t.paint(c, center - Offset(t.width / 2, t.height / 2));
  }

  TextPainter _text(
    String s,
    double size,
    Color color,
    double maxWidth, {
    bool bold = false,
    TextAlign align = TextAlign.center,
  }) {
    return TextPainter(
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
  }

  @override
  bool shouldRepaint(WpStagePainter old) =>
      old.security != security ||
      old.guesses != guesses ||
      old.apFailed != apFailed ||
      old.palette != palette ||
      old.scale != scale ||
      old.phase != phase;
}
