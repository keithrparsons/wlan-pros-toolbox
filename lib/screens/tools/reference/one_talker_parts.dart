// Small parts of the One Talker per Channel lesson (one-talker): the painted
// walkie-talkie (the lesson's analogy, Keith 2026-09-29), a device chip, and
// the airtime pie. Drawn fresh; no icon-font glyph and no copied artwork.
//
// THEME: `context.colors` and, for devices, the Classroom client palette
// (GL-003 §8.15.2; every device also carries its letter, so hue is never the
// only cue). Painted strokes and labels scale with PresenterMode.scaleOf.
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/one_talker_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The walkie-talkie.
// ─────────────────────────────────────────────────────────────────────────────

/// One walkie-talkie: antenna, body, speaker grille, the push-to-talk button
/// on the side, and (when [talking]) sound arcs.
class WalkieTalkiePainter extends CustomPainter {
  WalkieTalkiePainter({
    required this.outline,
    required this.body,
    required this.accent,
    required this.talking,
    this.stroke = 2,
  });

  final Color outline;
  final Color body;
  final Color accent;
  final bool talking;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    // The radio sits in the left 60% so the arcs have room on the right.
    final double bw = w * 0.46;
    final double bx = w * 0.14;
    final double by = h * 0.30;
    final Rect bodyRect = Rect.fromLTWH(bx, by, bw, h * 0.68);
    final RRect rr = RRect.fromRectAndRadius(
      bodyRect,
      Radius.circular(bw * .2),
    );
    final Paint line = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // Antenna.
    final double ax = bx + bw * 0.28;
    canvas.drawLine(Offset(ax, by), Offset(ax, h * 0.04), line);
    canvas.drawCircle(Offset(ax, h * 0.04), stroke, Paint()..color = outline);
    // Body.
    canvas.drawRRect(rr, Paint()..color = body);
    canvas.drawRRect(rr, line);
    // Speaker grille.
    for (int i = 0; i < 4; i++) {
      final double y = by + h * (0.10 + i * 0.065);
      canvas.drawLine(
        Offset(bx + bw * 0.22, y),
        Offset(bx + bw * 0.78, y),
        line,
      );
    }
    // Push-to-talk button, on the left side.
    final Rect ptt = Rect.fromLTWH(
      bx - w * 0.07,
      by + h * 0.16,
      w * 0.07,
      h * 0.16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(ptt, Radius.circular(stroke)),
      Paint()..color = talking ? accent : outline,
    );
    // A single round key low on the face.
    canvas.drawCircle(Offset(bx + bw / 2, by + h * 0.52), bw * 0.13, line);
    if (!talking) return;
    final Paint arc = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final Offset c = Offset(bx + bw, by + h * 0.16);
    for (int i = 1; i <= 3; i++) {
      final double r = w * 0.11 * i;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 4,
        math.pi / 2,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(WalkieTalkiePainter old) =>
      old.outline != outline ||
      old.body != body ||
      old.accent != accent ||
      old.talking != talking ||
      old.stroke != stroke;
}

/// A walkie-talkie at [size], in the theme's colors.
class WalkieTalkie extends StatelessWidget {
  const WalkieTalkie({super.key, required this.talking, this.size = 64});

  final bool talking;

  /// Height; the width is 0.8 of it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale s = PresenterMode.scaleOf(context);
    return CustomPaint(
      size: Size(size * 0.8, size),
      painter: WalkieTalkiePainter(
        outline: colors.textSecondary,
        body: colors.surface2,
        accent: colors.textAccent,
        talking: talking,
        stroke: s.strokeWidth(size >= 48 ? 2 : 1.4),
      ),
    );
  }
}

/// The analogy's illustration: one radio talking, one listening, each with
/// its caption. One semantics node describes the pair.
class WalkieTalkiePair extends StatelessWidget {
  const WalkieTalkiePair({super.key});

  static const String semantics =
      'Illustration: two walkie-talkies. One holds the button and talks. '
      'The other listens and waits for "over".';

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    Widget one(bool talking, String title, String line) => Expanded(
      child: Column(
        children: <Widget>[
          WalkieTalkie(talking: talking, size: 96),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.labelLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            line,
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            one(true, 'Talking', 'Holds the button'),
            const SizedBox(width: AppSpacing.sm),
            one(false, 'Listening', 'Waits for "over"'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A device chip.
// ─────────────────────────────────────────────────────────────────────────────

/// A device as its letter on its palette hue. [talking] adds a lime ring;
/// the words beside the room say who is talking, so the ring is never the
/// only cue.
class OtClientChip extends StatelessWidget {
  const OtClientChip({
    super.key,
    required this.client,
    this.talking = false,
    this.diameter = 32,
  });

  final OneTalkerClient client;
  final bool talking;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final WifiLabClientStyle st = WifiLabClientPalette.of(client.index, colors);
    final PresenterScale s = PresenterMode.scaleOf(context);
    final double d = s.markerSize(diameter);
    return Container(
      width: d + 8,
      height: d + 8,
      alignment: Alignment.center,
      decoration: talking
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.primary,
                width: s.strokeWidth(3),
              ),
            )
          : null,
      child: Container(
        width: d,
        height: d,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: st.outlined ? colors.surface1 : st.hue,
          border: st.outlined ? Border.all(color: st.hue, width: 2) : null,
        ),
        child: Text(
          client.letter,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: st.outlined ? st.hue : st.onHue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The airtime pie.
// ─────────────────────────────────────────────────────────────────────────────

/// One channel's time as a pie: one slice per device in its hue, split by
/// hairlines in the surface color, the letter on every slice wide enough.
class OtPiePainter extends CustomPainter {
  OtPiePainter({
    required this.clients,
    required this.colors,
    required this.labelStyle,
    required this.stroke,
  });

  final List<OneTalkerClient> clients;
  final AppColorScheme colors;
  final TextStyle labelStyle;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = math.min(size.width, size.height) / 2 - stroke;
    final Rect box = Rect.fromCircle(center: c, radius: r);
    double start = -math.pi / 2;
    final Paint gap = Paint()
      ..color = colors.surface1
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final OneTalkerClient k in clients) {
      final double sweep = 2 * math.pi * k.airtimeShare;
      final WifiLabClientStyle st = WifiLabClientPalette.of(k.index, colors);
      // Devices J to R wear their hue as an outline on chips; in the pie a
      // thin outlined wedge is unreadable, so they get a lighter fill of the
      // same hue instead. The bars beside the pie carry every letter.
      canvas.drawArc(
        box,
        start,
        sweep,
        true,
        Paint()..color = st.outlined ? st.hue.withValues(alpha: 0.45) : st.hue,
      );
      if (clients.length > 1) canvas.drawArc(box, start, sweep, true, gap);
      // The letter, when the slice has room for it.
      if (sweep * r * 0.62 >= (labelStyle.fontSize ?? 14) * 1.5) {
        final double mid = start + sweep / 2;
        final Offset at = c + Offset(math.cos(mid), math.sin(mid)) * r * 0.62;
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: k.letter,
            style: labelStyle.copyWith(
              color: st.outlined ? colors.textPrimary : st.onHue,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
      }
      start += sweep;
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = colors.borderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(OtPiePainter old) =>
      old.clients != clients ||
      old.colors != colors ||
      old.labelStyle != labelStyle ||
      old.stroke != stroke;
}

/// A channel's pie with its title and a spoken summary.
class OtPie extends StatelessWidget {
  const OtPie({super.key, required this.channel, this.diameter = 150});

  final OneTalkerChannel channel;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final PresenterScale s = PresenterMode.scaleOf(context);
    final String spoken = channel.clients
        .map(
          (OneTalkerClient k) => '${k.letter} ${sharePercent(k.airtimeShare)}',
        )
        .join(', ');
    return Semantics(
      container: true,
      label: 'Channel ${channel.number} time, as a pie: $spoken',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Channel ${channel.number} time',
            textAlign: TextAlign.center,
            style: t.labelLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          CustomPaint(
            size: Size.square(s.markerSize(diameter)),
            painter: OtPiePainter(
              clients: channel.clients,
              colors: colors,
              // From the theme, so the painted letters use the app face.
              labelStyle: (t.labelMedium ?? const TextStyle()).copyWith(
                fontSize: s.paintFont(AppTextSize.caption),
                fontWeight: FontWeight.w700,
              ),
              stroke: s.strokeWidth(1.5),
            ),
          ),
        ],
      ),
    );
  }
}
