// The stage for A Frame's Journey (Wi-Fi Classroom): the step and what it
// did, the two NICs with the air between them, the frame as sent (and the
// radiotap header the receiver puts in front of it, never sent), the bits
// around the flipped one, the FCS check, and the SIFS-then-ACK timeline.
// Reads a [FrameJourneyController]; owns no state, so a presenter layout can
// place it beside [FrameJourneyControls].
//
// COLOR (GL-003 §8.13 / §8.15.2). The FCS result is a computed verdict:
// statusSuccess with the word "pass", statusDanger with the word "fail", and
// the flipped bit is statusDanger with the word "flipped". Header hues come
// from frame_journey_parts.dart and are always labeled. Lime marks where the
// frame is now.
//
// THE RF DRAWING (Keith's standing rule). The wave between the NICs keeps
// ONE wavelength from end to end; distance only lowers its height (loss
// changes height, never spacing). The ACK is drawn on the same wavelength:
// it goes back on the same channel.
//
// ACCESSIBILITY. The drawing has a worded Semantics label; everything it
// shows is also in text on the cards (SC 1.4.1).
//
// ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/frame_journey_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../units/length_format.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'frame_journey_controller.dart';
import 'frame_journey_parts.dart';

class FrameJourneyStage extends StatelessWidget {
  const FrameJourneyStage({
    super.key,
    required this.controller,
    this.drawingHeight = 250,
  });

  final FrameJourneyController controller;

  /// Height of the drawing on the normal screen; the presenter fills.
  final double drawingHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget frame = _FrameCard(controller: controller);
        final Widget bits = _BitsCard(controller: controller);
        final Widget fcs = _FcsCard(controller: controller);
        final Widget radiotap = _RadiotapCard(controller: controller);
        if (!presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.sm),
              _DrawingCard(controller: controller, height: drawingHeight),
              const SizedBox(height: AppSpacing.sm),
              frame,
              const SizedBox(height: AppSpacing.sm),
              fcs,
              const SizedBox(height: AppSpacing.sm),
              bits,
              const SizedBox(height: AppSpacing.sm),
              radiotap,
            ],
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double side = (box.maxWidth * 0.36).clamp(320.0, 520.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: _DrawingCard(controller: controller)),
                      const SizedBox(height: AppSpacing.xs),
                      frame,
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: side,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: side,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          headline,
                          const SizedBox(height: AppSpacing.xs),
                          fcs,
                          const SizedBox(height: AppSpacing.xs),
                          bits,
                          const SizedBox(height: AppSpacing.xs),
                          radiotap,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final FrameJourneyController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final FhStep s = controller.step;
    return AirtimeCard(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Step ${s.index + 1} of ${controller.stepCount}  |  '
              'Attempt ${s.attempt}  |  ${s.stage.where}',
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              s.title,
              style: text.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              s.detail,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// "FCS pass" or "FCS fail", in words and the verdict hue.
class FhVerdict extends StatelessWidget {
  const FhVerdict({super.key, required this.pass});

  final bool pass;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color c = pass ? colors.statusSuccess : colors.statusDanger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          pass ? Icons.check_circle_outline : Icons.error_outline,
          color: c,
          semanticLabel: pass ? 'Pass' : 'Fail',
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          pass ? 'FCS pass' : 'FCS fail',
          style: text.titleMedium?.copyWith(
            color: c,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ── The drawing ─────────────────────────────────────────────────────────────

class _DrawingCard extends StatelessWidget {
  const _DrawingCard({required this.controller, this.height});

  final FrameJourneyController controller;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    final FhStep s = controller.step;
    final FhConfig c = controller.config;
    final LengthFormat lf = LengthFormat(controller.units);
    final FhStyle style = FhStyle(
      scale: scale,
      box: colors.surface2,
      boxBorder: colors.borderStrong,
      active: colors.primary,
      muted: colors.textSecondary,
      faint: colors.textTertiary,
      danger: colors.statusDanger,
      label: up(
        text.labelLarge!.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      small: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textSecondary,
        ),
      ),
    );
    final String spoken =
        'The transmitting NIC on the left, the receiving NIC on the right, '
        '${lf.distSpoken(c.distanceM, decimals: 0)} apart on '
        '${c.band.label}. ${s.stage.label}.';
    final Widget paint = Semantics(
      label: spoken,
      excludeSemantics: true,
      child: ValueListenableBuilder<double>(
        valueListenable: controller.wave,
        builder: (BuildContext context, double phase, _) => CustomPaint(
          painter: FhHopPainter(
            step: s,
            phase: phase,
            distanceLabel: lf.dist(c.distanceM, decimals: 0),
            levelLabel:
                '${fjSignalDbm(c.distanceM, c.band).toStringAsFixed(1)} dBm',
            sifs: controller.sifs,
            corruptMarked: c.corrupt && s.attempt == 1,
            style: style,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    return AirtimeCard(
      child: height == null ? paint : SizedBox(height: height, child: paint),
    );
  }
}

/// Theme values the hop painter needs.
class FhStyle {
  const FhStyle({
    required this.scale,
    required this.box,
    required this.boxBorder,
    required this.active,
    required this.muted,
    required this.faint,
    required this.danger,
    required this.label,
    required this.small,
  });

  final PresenterScale scale;
  final Color box;
  final Color boxBorder;
  final Color active;
  final Color muted;
  final Color faint;
  final Color danger;
  final TextStyle label;
  final TextStyle small;
}

/// Two NICs, the air between them, the frame or the ACK crossing it, and the
/// timeline underneath.
class FhHopPainter extends CustomPainter {
  FhHopPainter({
    required this.step,
    required this.phase,
    required this.distanceLabel,
    required this.levelLabel,
    required this.sifs,
    required this.corruptMarked,
    required this.style,
  });

  final FhStep step;
  final double phase;
  final String distanceLabel;
  final String levelLabel;
  final SifsTiming sifs;
  final bool corruptMarked;
  final FhStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final PresenterScale k = style.scale;
    final FjHopStage st = step.stage;
    final double h = size.height;
    final TextPainter nameTp = _tp('Receiving NIC', style.label);
    final double nicW = math.min(
      math.max(nameTp.width + 20 * k.marker, size.width * 0.16),
      size.width * 0.3,
    );
    final double nicH = math.min(math.max(h * 0.34, 56.0), 150 * k.marker);
    final double labelH = style.small.fontSize! * 1.6;
    final double top = labelH + 4 * k.marker;
    final Rect tx = Rect.fromLTWH(0, top, nicW, nicH);
    final Rect rx = Rect.fromLTWH(size.width - nicW, top, nicW, nicH);
    final bool txActive =
        st == FjHopStage.build ||
        st == FjHopStage.toRf ||
        st == FjHopStage.retry ||
        st == FjHopStage.done;
    final bool rxActive =
        st == FjHopStage.decode ||
        st == FjHopStage.radiotap ||
        st == FjHopStage.fcs ||
        st == FjHopStage.sifs ||
        st == FjHopStage.noAck;
    final bool roomy = nameTp.width + 12 * k.marker <= nicW;
    _nic(canvas, tx, roomy ? 'Sending NIC' : 'Sender', 'Laptop', txActive);
    _nic(canvas, rx, roomy ? 'Receiving NIC' : 'Receiver', 'AP', rxActive);

    // The air. One wavelength end to end; the height falls with distance.
    final double y = top + nicH / 2;
    final double x0 = tx.right + 10 * k.marker;
    final double x1 = rx.left - 10 * k.marker;
    final double wl = 24 * k.marker;
    final double a0 = nicH * 0.36;
    final bool forward = st == FjHopStage.air;
    final bool back = st == FjHopStage.ack;
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = k.strokeWidth(1.5)
      ..color = style.faint;
    final Paint lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = k.strokeWidth(3)
      ..strokeCap = StrokeCap.round
      ..color = style.active;
    double amp(double t) => a0 / (1 + 2.5 * t);
    _wave(canvas, x0, x1, y, wl, amp, forward || back ? phase : 0, base);
    if (forward) {
      _wave(
        canvas,
        x0,
        x1,
        y,
        wl,
        amp,
        phase,
        lit,
        from: math.max(0, phase - 0.35),
        to: phase,
      );
    } else if (back) {
      final double head = 1 - phase;
      _wave(
        canvas,
        x0,
        x1,
        y,
        wl,
        amp,
        phase,
        lit,
        from: head,
        to: math.min(1, head + 0.2),
      );
    }
    // Labels: distance under the middle, the level above the receiver end.
    _text(
      canvas,
      distanceLabel,
      style.small,
      Offset(x0 + (x1 - x0) * 0.3, y + a0 + 4 * k.marker),
      center: true,
    );
    _text(
      canvas,
      'arrives at $levelLabel',
      style.small,
      Offset(x1, 0),
      right: true,
    );
    final double noteY = y - a0 - style.label.fontSize! * 1.5;
    if (back) {
      _text(
        canvas,
        'ACK',
        style.label.copyWith(color: style.active),
        Offset((x0 + x1) / 2, math.max(labelH, noteY)),
        center: true,
      );
    }
    if (st == FjHopStage.noAck || st == FjHopStage.retry) {
      _text(
        canvas,
        'no ACK comes back',
        style.label.copyWith(color: style.danger),
        Offset((x0 + x1) / 2, math.max(labelH, noteY)),
        center: true,
      );
    }
    // The wrong bit, marked on the air and in words.
    if (corruptMarked && (forward || st.index >= FjHopStage.decode.index)) {
      final double xm = x0 + (x1 - x0) * 0.62;
      final double r = 7 * k.marker;
      final Paint p = Paint()
        ..color = style.danger
        ..strokeWidth = k.strokeWidth(3)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(xm - r, y - r), Offset(xm + r, y + r), p);
      canvas.drawLine(Offset(xm - r, y + r), Offset(xm + r, y - r), p);
      _text(
        canvas,
        '1 bit flipped',
        style.small.copyWith(color: style.danger),
        Offset(xm, y + a0 + 6 * k.marker + style.small.fontSize! * 1.3),
        center: true,
      );
    }

    // The timeline: frame, gap, ACK (or the wait with no ACK). Not to scale.
    final double footH = style.small.fontSize! * 1.6;
    final double th = math.min(math.max(h * 0.14, 20.0), 48 * k.marker);
    final double ty = math.max(
      top + nicH + a0 * 0.2 + 24 * k.marker,
      h - footH - th - 4 * k.marker,
    );
    if (ty + th + footH > h) return;
    final double w = size.width;
    final bool failed = step.check != null && !step.check!.pass;
    final String us = 'µs';
    final List<(String, double, bool, bool)> blocks = failed
        ? <(String, double, bool, bool)>[
            ('Frame', 0.46, true, st == FjHopStage.air),
            (
              'waiting for an ACK',
              0.54,
              false,
              st == FjHopStage.noAck || st == FjHopStage.retry,
            ),
          ]
        : <(String, double, bool, bool)>[
            (
              'Frame',
              0.52,
              true,
              st.index >= FjHopStage.toRf.index &&
                  st.index <= FjHopStage.fcs.index,
            ),
            (
              sifs.signalExtensionUs > 0
                  ? 'SIFS ${sifs.sifsUs}+${sifs.signalExtensionUs} $us'
                  : 'SIFS ${sifs.sifsUs} $us',
              0.24,
              false,
              st == FjHopStage.sifs,
            ),
            ('ACK', 0.24, true, st == FjHopStage.ack || st == FjHopStage.done),
          ];
    double x = 0;
    for (final (String label, double frac, bool filled, bool on) in blocks) {
      final Rect r = Rect.fromLTWH(x, ty, w * frac - 4, th);
      final RRect rr = RRect.fromRectAndRadius(
        r,
        Radius.circular(4 * k.marker),
      );
      if (filled) canvas.drawRRect(rr, Paint()..color = style.box);
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = k.strokeWidth(on ? 3 : 1)
          ..color = on ? style.active : style.boxBorder,
      );
      _text(
        canvas,
        label,
        style.small.copyWith(color: on ? style.label.color : style.muted),
        r.center,
        center: true,
        middle: true,
        maxWidth: r.width - 6,
      );
      x += w * frac;
    }
    _text(
      canvas,
      'time, not to scale',
      style.small.copyWith(color: style.faint),
      Offset(0, ty + th + 3 * k.marker),
    );
  }

  TextPainter _tp(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  void _nic(Canvas c, Rect r, String name, String device, bool on) {
    final PresenterScale k = style.scale;
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(8 * k.marker));
    c.drawRRect(rr, Paint()..color = style.box);
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = k.strokeWidth(on ? 3 : 1)
        ..color = on ? style.active : style.boxBorder,
    );
    _text(
      c,
      name,
      style.label,
      Offset(r.center.dx, r.center.dy - style.label.fontSize! * 0.75),
      center: true,
      middle: true,
      maxWidth: r.width - 8,
    );
    _text(
      c,
      device,
      style.small,
      Offset(r.center.dx, r.center.dy + style.small.fontSize! * 0.9),
      center: true,
      middle: true,
      maxWidth: r.width - 8,
    );
  }

  void _wave(
    Canvas c,
    double x0,
    double x1,
    double y,
    double wavelength,
    double Function(double t) amp,
    double phase,
    Paint p, {
    double from = 0,
    double to = 1,
  }) {
    if (to <= from) return;
    final Path path = Path();
    const int steps = 120;
    bool started = false;
    for (int j = 0; j <= steps; j++) {
      final double t = j / steps;
      if (t < from || t > to) continue;
      final double x = x0 + (x1 - x0) * t;
      final double v =
          math.sin(2 * math.pi * ((x - x0) / wavelength - phase * 3)) * amp(t);
      if (!started) {
        path.moveTo(x, y + v);
        started = true;
      } else {
        path.lineTo(x, y + v);
      }
    }
    c.drawPath(path, p);
  }

  void _text(
    Canvas c,
    String s,
    TextStyle st,
    Offset at, {
    bool center = false,
    bool middle = false,
    bool right = false,
    double? maxWidth,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final double dx = center
        ? at.dx - tp.width / 2
        : right
        ? at.dx - tp.width
        : at.dx;
    final double dy = middle ? at.dy - tp.height / 2 : at.dy;
    tp.paint(c, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(FhHopPainter old) =>
      old.step != step ||
      old.phase != phase ||
      old.distanceLabel != distanceLabel ||
      old.levelLabel != levelLabel ||
      old.corruptMarked != corruptMarked ||
      old.style.scale != style.scale ||
      old.style.active != style.active ||
      old.style.box != style.box;
}

// ── The frame (and the radiotap header in front of it) ─────────────────────

class _FrameCard extends StatelessWidget {
  const _FrameCard({required this.controller});

  final FrameJourneyController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final FhStep s = controller.step;
    final FjSizes z = s.frame.sizes;
    final List<FjPiece> pieces = <FjPiece>[
      FjPiece(FjPart.wifiHeader, z.macHeader, '802.11 ${z.macHeader} B'),
      FjPiece(FjPart.llcSnap, z.llcSnap, 'LLC/SNAP ${z.llcSnap} B'),
      FjPiece(FjPart.ip, z.ipHeader, 'IPv4 ${z.ipHeader} B'),
      FjPiece(
        FjPart.transport,
        z.transportHeader,
        '${z.transport.label} ${z.transportHeader} B',
      ),
      FjPiece(FjPart.data, z.payload, 'Data ${z.payload} B'),
      FjPiece(FjPart.fcs, z.fcs, 'FCS ${z.fcs} B'),
    ];
    final bool tapped = s.radiotap != null;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle(
            'The frame: ${s.frame.length} bytes, ${s.frame.bitCount} bits',
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (tapped)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: colors.textSecondary, width: 1.5),
                  ),
                  child: Text(
                    'radiotap: added here, never sent',
                    style: mono.inlineCode.copyWith(
                      color: colors.textPrimary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              FjPduStrip(pieces: pieces),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${fjPieceLegend(pieces)}. The same frame Down the Stack sends on '
            'the laptop\'s air hop; the FCS covers everything before it.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── The FCS check ───────────────────────────────────────────────────────────

class _FcsCard extends StatelessWidget {
  const _FcsCard({required this.controller});

  final FrameJourneyController controller;

  @override
  Widget build(BuildContext context) {
    final FhStep s = controller.step;
    final FcsCheck? check = s.check;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The check: FCS (frame check sequence)'),
          const SizedBox(height: AppSpacing.xxs),
          FjReadoutTable(
            rows: <(String, String)>[
              ('Sent in the frame', hex32(s.frame.fcsSent)),
              (
                'Arrived',
                s.received == null
                    ? 'not yet'
                    : hex32(AirFrame.fcsField(s.received!)),
              ),
              (
                'Receiver computes',
                check == null ? 'not yet' : hex32(check.computed),
              ),
            ],
          ),
          if (check != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            FhVerdict(pass: check.pass),
          ],
        ],
      ),
    );
  }
}

// ── The bits ────────────────────────────────────────────────────────────────

class _BitsCard extends StatelessWidget {
  const _BitsCard({required this.controller});

  final FrameJourneyController controller;

  static const int _window = 24;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final FhStep s = controller.step;
    final FhConfig c = controller.config;
    final AirFrame f = s.frame;
    final bool corrupt = c.corrupt && s.attempt == 1;
    final int flip = c.flipBit.clamp(0, f.bitCount - 1);
    final int start = ((corrupt ? flip : 0) - _window ~/ 2).clamp(
      0,
      f.bitCount - _window,
    );
    final List<int> bytes = s.received ?? f.bytes;
    int bitAt(int i) => (bytes[i ~/ 8] >> (7 - i % 8)) & 1;
    final bool arrived = s.received != null;

    final TextStyle base = mono.inlineCode.copyWith(color: colors.textPrimary);
    final List<InlineSpan> spans = <InlineSpan>[];
    for (int i = start; i < start + _window; i++) {
      final bool flipped = corrupt && arrived && i == flip;
      if (i > start && i % 8 == 0) spans.add(TextSpan(text: ' ', style: base));
      spans.add(
        TextSpan(
          text: flipped ? '[${bitAt(i)}]' : '${bitAt(i)}',
          style: flipped
              ? base.copyWith(
                  color: colors.statusDanger,
                  fontWeight: FontWeight.w700,
                )
              : base,
        ),
      );
    }
    final String where = f.fieldAtBit(corrupt ? flip : start).name;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle(
            arrived ? 'Bits as they arrived' : 'Bits as sent',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label: corrupt && arrived
                ? 'Bit $flip, in $where, arrived flipped.'
                : 'Bits $start to ${start + _window - 1}, in $where.',
            excludeSemantics: true,
            child: Text.rich(TextSpan(children: spans)),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            corrupt && arrived
                ? 'Bit $flip, in $where: flipped (shown in brackets).'
                : corrupt
                ? 'Bit $flip, in $where, will arrive flipped.'
                : 'Bits $start to ${start + _window - 1}, starting in $where.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Radiotap ────────────────────────────────────────────────────────────────

class _RadiotapCard extends StatelessWidget {
  const _RadiotapCard({required this.controller});

  final FrameJourneyController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RadiotapView? rt = controller.step.radiotap;
    final bool capturing = controller.config.capturing;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What the receiver adds (radiotap)'),
          const SizedBox(height: AppSpacing.xxs),
          if (rt == null)
            Text(
              capturing
                  ? 'Appears once the frame has arrived. A capturing '
                        'receiver\'s driver writes it; it is never sent.'
                  : 'This receiver is not capturing, so nothing is added.',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            )
          else ...<Widget>[
            FjReadoutTable(
              rows: <(String, String)>[
                ('Timer at the first bit (TSFT)', '${rt.tsftUs} \u00B5s'),
                ('Antenna signal', '${rt.signalDbm} dBm'),
                ('Channel', '${rt.freqMHz} MHz (channel ${rt.channel})'),
                (
                  'MCS (modulation and coding scheme), illustrative',
                  '${rt.mcs}',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Written by the receiver from what it measured. None of it '
              'crossed the air, and a different receiver would write '
              'different values for the same frame. The timer value and MCS '
              'are illustrative.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
