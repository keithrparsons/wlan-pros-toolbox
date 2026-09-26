// Painters for OFDMA Resource Units (Wi-Fi Lab): the channel's slot grid and
// the to-scale airtime bars.
//
// COLOR. Clients carry one hue each, from the Wi-Fi Lab client palette
// (lib/theme/wifi_lab_client_palette.dart, GL-003 §8.15.2): the same hue marks
// a client's RU in the channel strip and its data in every timeline, and its
// letter is always drawn or spoken with it, so nothing rests on color alone.
// Everything else reuses the Airtime Anatomy block styles (hatched waits, a
// neutral preamble, outlined control frames, a dashed SIFS), so the two tools
// read the same. Status hues appear only on a failed check (§8.13).
//
// The painting is a picture: the stage wraps each bar in a worded Semantics
// label and lists every segment in "Show the arithmetic".

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/ofdma_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import 'airtime_anatomy_timeline.dart';

/// Geometry shared by the stage, the painters and the tests.
class OfdmaGeometry {
  OfdmaGeometry._();

  /// Height of the channel strip (also the RU blocks' touch height).
  static const double stripHeight = AppSpacing.xl;

  /// SU bar height; OFDMA bars grow with the client count, one lane each.
  static const double barHeight = AppSpacing.lg;

  /// Per-client lane height the OFDMA bar aims for, and its cap.
  static const double laneTarget = AppSpacing.sm;
  static const double ofdmaBarMax = AppSpacing.xxl + AppSpacing.xl;

  /// Space for the client brackets under the SU bar.
  static const double bracketGap = AppSpacing.xxs;

  static double ofdmaBarHeight(int clients) =>
      (clients * laneTarget).clamp(barHeight, ofdmaBarMax);
}

/// The block style for a segment kind, or null for data (drawn per client).
AirtimeBlockStyle? ofdmaBlockStyle(OfdmaSegmentKind k) {
  switch (k) {
    case OfdmaSegmentKind.aifs:
    case OfdmaSegmentKind.backoff:
      return AirtimeBlockStyle.wait;
    case OfdmaSegmentKind.preamble:
      return AirtimeBlockStyle.preamble;
    case OfdmaSegmentKind.data:
      return null;
    case OfdmaSegmentKind.sifs:
      return AirtimeBlockStyle.gap;
    case OfdmaSegmentKind.trigger:
    case OfdmaSegmentKind.ack:
      return AirtimeBlockStyle.control;
  }
}

/// Paints one client's block: a hue fill, or for clients 10 and up a hue
/// outline on the surface.
void paintClientBlock(
  Canvas canvas,
  Rect rect,
  int client,
  AppColorScheme colors,
) {
  final WifiLabClientStyle st = WifiLabClientPalette.of(client, colors);
  if (st.outlined) {
    canvas.drawRect(rect, Paint()..color = colors.surface1);
    final double w = math.min(2, math.min(rect.width, rect.height) / 2);
    canvas.drawRect(
      rect.deflate(w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = st.hue,
    );
  } else {
    canvas.drawRect(rect, Paint()..color = st.hue);
  }
}

/// Padding in an OFDMA data block: the RU finished early and sits idle to
/// the end. A dotted line along the lane in borderStrong (3:1 or better on
/// both themes' surfaces), so it reads on white as well as on dark.
void paintPadding(Canvas canvas, Rect rect, AppColorScheme colors) {
  canvas.drawRect(rect, Paint()..color = colors.surface1);
  final Paint p = Paint()
    ..color = colors.borderStrong
    ..strokeWidth = math.min(2, math.max(1, rect.height / 4));
  final double y = rect.center.dy;
  const double dot = 2;
  for (double x = rect.left + dot; x < rect.right - dot; x += dot * 3) {
    canvas.drawLine(Offset(x, y), Offset(math.min(x + dot, rect.right), y), p);
  }
}

/// The channel's 26-tone slot grid, with 20 MHz boundaries heavier.
class OfdmaSlotGridPainter extends CustomPainter {
  OfdmaSlotGridPainter({
    required this.widthMhz,
    required this.colors,
    this.stroke = 1,
  });

  final int widthMhz;
  final AppColorScheme colors;

  /// Presenter stroke factor (PresenterScale.stroke); 1 elsewhere.
  final double stroke;

  /// Slot indices where a 20 MHz subchannel starts, in order. Center 26-tone
  /// slots (80 and 160 MHz) sit between them.
  static List<int> subchannelStarts(int widthMhz) {
    final List<int> out = <int>[];
    for (final RuSpan p in OfdmaTonePlan.positions(widthMhz, RuSize.ru242)) {
      out.add(p.start);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final int slots = OfdmaTonePlan.slots(widthMhz);
    final double sw = size.width / slots;
    final Rect all = Offset.zero & size;
    canvas.drawRect(all, Paint()..color = colors.surface2);
    final Paint thin = Paint()
      ..color = colors.border
      ..strokeWidth = stroke;
    for (int i = 1; i < slots; i++) {
      final double x = i * sw;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thin);
    }
    // Center 26-tone slots (only a 26-tone RU fits): lightly hatched.
    final Set<int> covered = <int>{
      for (final RuSpan p in OfdmaTonePlan.positions(widthMhz, RuSize.ru52))
        for (int s = p.start; s < p.end; s++) s,
    };
    final Paint hatch = Paint()
      ..color = colors.border
      ..strokeWidth = stroke;
    for (int i = 0; i < slots; i++) {
      if (covered.contains(i)) continue;
      final Rect r = Rect.fromLTWH(i * sw, 0, sw, size.height);
      canvas.save();
      canvas.clipRect(r);
      for (double y = -r.width; y < size.height; y += 6) {
        canvas.drawLine(Offset(r.left, y + r.width), Offset(r.right, y), hatch);
      }
      canvas.restore();
    }
    final Paint strong = Paint()
      ..color = colors.borderStrong
      ..strokeWidth = 1.5 * stroke;
    for (final int s in subchannelStarts(widthMhz)) {
      final double x = s * sw;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), strong);
      final double xe = (s + 9) * sw;
      canvas.drawLine(Offset(xe, 0), Offset(xe, size.height), strong);
    }
    canvas.drawRect(
      all.deflate(stroke / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colors.borderStrong,
    );
  }

  @override
  bool shouldRepaint(OfdmaSlotGridPainter old) =>
      old.widthMhz != widthMhz || old.colors != colors || old.stroke != stroke;
}

/// Paints one timeline bar to scale.
class OfdmaBarPainter extends CustomPainter {
  OfdmaBarPainter({
    required this.timeline,
    required this.scaleUs,
    required this.barHeight,
    required this.colors,
    required this.labelStyle,
    required this.letterStyle,
    required this.textScaler,
    this.stroke = 1,
  });

  final OfdmaTimeline timeline;
  final double scaleUs;
  final double barHeight;
  final AppColorScheme colors;
  final TextStyle labelStyle;

  /// Base style for client letters; the color is set per client.
  final TextStyle letterStyle;
  final TextScaler textScaler;

  /// Presenter stroke factor (PresenterScale.stroke); 1 elsewhere.
  final double stroke;

  bool get _isSu => timeline.mode == OfdmaMode.su;

  /// Height the painter needs: the bar, plus the client brackets under SU.
  static double heightFor({
    required OfdmaTimeline timeline,
    required double barHeight,
    required TextStyle letterStyle,
    required TextScaler textScaler,
  }) {
    if (timeline.mode != OfdmaMode.su) return barHeight;
    final TextPainter tp = _text('A', letterStyle, textScaler);
    return barHeight + OfdmaGeometry.bracketGap * 2 + tp.height;
  }

  static TextPainter _text(String s, TextStyle style, TextScaler scaler) =>
      TextPainter(
        text: TextSpan(text: s, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (scaleUs <= 0) return;
    final double px = size.width / scaleUs;
    Rect rectOf(OfdmaSegment s) {
      final double x0 = s.startUs * px;
      final double x1 = math.max(s.endUs * px, x0 + 1);
      return Rect.fromLTRB(x0, 0, math.min(x1, size.width), barHeight);
    }

    for (final OfdmaSegment s in timeline.segments) {
      if (s.tenths == 0) continue;
      final Rect r = rectOf(s);
      final AirtimeBlockStyle? style = ofdmaBlockStyle(s.kind);
      if (style != null) {
        paintAirtimeBlock(canvas, r, style, colors, stroke: stroke);
        _label(canvas, r, s.shortLabel, labelStyle);
        continue;
      }
      final List<int>? lanes = s.lanes;
      if (lanes == null) {
        // SU data: the whole channel is one client's.
        final int c = s.client ?? 0;
        paintClientBlock(canvas, r, c, colors);
        _clientLabel(canvas, r, c);
        continue;
      }
      final double lh = r.height / lanes.length;
      for (int c = 0; c < lanes.length; c++) {
        final double top = r.top + c * lh;
        final double end = r.left + lanes[c] / 10 * px;
        final Rect used = Rect.fromLTRB(
          r.left,
          top,
          math.min(end, r.right),
          top + lh,
        );
        if (used.right < r.right - 0.5) {
          paintPadding(
            canvas,
            Rect.fromLTRB(used.right, top, r.right, top + lh),
            colors,
          );
        }
        paintClientBlock(canvas, used, c, colors);
        _clientLabel(canvas, used, c);
        if (c > 0 && lh >= 3) {
          canvas.drawLine(
            Offset(r.left, top),
            Offset(r.right, top),
            Paint()
              ..color = colors.surface1
              ..strokeWidth = stroke,
          );
        }
      }
    }

    if (_isSu) _brackets(canvas, size, px);
  }

  void _label(Canvas canvas, Rect r, String text, TextStyle style) {
    final TextPainter tp = _text(text, style, textScaler);
    if (tp.width + AppSpacing.xxs * 2 > r.width || tp.height > r.height) {
      return;
    }
    tp.paint(
      canvas,
      Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2),
    );
  }

  void _clientLabel(Canvas canvas, Rect r, int client) {
    final WifiLabClientStyle st = WifiLabClientPalette.of(client, colors);
    _label(
      canvas,
      r,
      clientLetter(client),
      letterStyle.copyWith(color: st.outlined ? st.hue : st.onHue),
    );
  }

  /// A bracket under each client's TXOP with its letter.
  void _brackets(Canvas canvas, Size size, double px) {
    final Map<int, (double, double)> spans = <int, (double, double)>{};
    for (final OfdmaSegment s in timeline.segments) {
      final int? c = s.client;
      if (c == null) continue;
      final (double, double)? cur = spans[c];
      spans[c] = cur == null
          ? (s.startUs * px, s.endUs * px)
          : (cur.$1, s.endUs * px);
    }
    final double y = barHeight + OfdmaGeometry.bracketGap;
    final Paint line = Paint()
      ..color = colors.textTertiary
      ..strokeWidth = stroke;
    for (final MapEntry<int, (double, double)> e in spans.entries) {
      final double l = e.value.$1 + 1;
      final double r = math.min(e.value.$2, size.width) - 1;
      if (r - l < 2) continue;
      canvas.drawLine(Offset(l, y), Offset(r, y), line);
      canvas.drawLine(Offset(l, y - 3), Offset(l, y), line);
      canvas.drawLine(Offset(r, y - 3), Offset(r, y), line);
      final TextPainter tp = _text(
        clientLetter(e.key),
        letterStyle.copyWith(color: colors.textSecondary),
        textScaler,
      );
      if (tp.width > r - l) continue;
      tp.paint(canvas, Offset((l + r) / 2 - tp.width / 2, y + 1));
    }
  }

  @override
  bool shouldRepaint(OfdmaBarPainter old) =>
      old.timeline != timeline ||
      old.scaleUs != scaleUs ||
      old.barHeight != barHeight ||
      old.colors != colors ||
      old.labelStyle != labelStyle ||
      old.letterStyle != letterStyle ||
      old.textScaler != textScaler ||
      old.stroke != stroke;
}

/// A legend swatch for one client-colored data block with padding.
class OfdmaDataSwatchPainter extends CustomPainter {
  OfdmaDataSwatchPainter({required this.colors, required this.padding});

  final AppColorScheme colors;
  final bool padding;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    if (padding) {
      paintPadding(canvas, r, colors);
      return;
    }
    final double w = size.width / 3;
    for (int c = 0; c < 3; c++) {
      paintClientBlock(
        canvas,
        Rect.fromLTWH(r.left + c * w, r.top, w, r.height),
        c,
        colors,
      );
    }
  }

  @override
  bool shouldRepaint(OfdmaDataSwatchPainter old) =>
      old.colors != colors || old.padding != padding;
}
