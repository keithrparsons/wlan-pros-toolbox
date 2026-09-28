// The stage for Voice Priority, End to End (Wi-Fi Classroom): which queue
// the call waits in and why, the packet's path hop by hop with the marking
// each hop passes on, the AP's four WMM queues with the download and the
// call in them, and the call's wait on the Wi-Fi hop against the other
// queues. Reads a [VoicePriorityController]; owns no state, so a presenter
// layout can place it beside [VoicePriorityControls].
//
// COLOR (GL-003 §8.13 / §8.15 case 3). Neutral stack plus lime for the one
// subject, the call. The hop where the marking is lost carries the danger
// hue WITH a block icon and the words "Marking lost here". The call in a
// queue is a filled block with the word "Call"; download frames are hollow
// blocks; a call not yet at the AP is a dashed block. Nothing rests on color.
//
// MOTION (§8.8). The packet jumps hop to hop; nothing tweens.
//
// ACCESSIBILITY. Every hop is text. The queue lanes are pictures with a
// worded Semantics label, and every number is also printed.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'voice_priority_controller.dart';

/// The first line on the stage: every acronym the tool uses, spelled out.
const String kVpIntroText =
    'The caller\'s app marks voice EF (Expedited Forwarding), a DSCP '
    '(Differentiated Services Code Point) value. The access point (AP) turns '
    'the DSCP into a user priority (UP), and the UP picks one of four WMM '
    '(Wi-Fi Multimedia) queues, called access categories (AC). RFC (Request '
    'for Comments) 8325 is the recommended mapping.';

/// Shown in place of the answer while the class predicts.
const String kVpHiddenText = 'Predict first, then reveal.';

class VoicePriorityStage extends StatelessWidget {
  const VoicePriorityStage({super.key, required this.controller});

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget path = _PathCard(controller: controller);
        final Widget queues = _QueuesCard(controller: controller);
        final Widget waits = _WaitsCard(controller: controller);
        const SizedBox gap = SizedBox(height: AppSpacing.sm);
        if (!presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[headline, gap, path, gap, queues, gap, waits],
          );
        }
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: box.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    headline,
                    gap,
                    path,
                    gap,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(flex: 3, child: queues),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(flex: 2, child: waits),
                      ],
                    ),
                  ],
                ),
              ),
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

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final VpTrip t = controller.trip;
    final bool hide = controller.hidingAnswer;
    return AirtimeCard(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              kVpIntroText,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The call waits in',
              style: text.labelLarge?.copyWith(color: colors.textSecondary),
            ),
            Text(
              hide ? '?' : '${t.queue.label} (${acCode(t.queue)})',
              style: text.headlineSmall?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hide ? kVpHiddenText : t.why,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The path ───────────────────────────────────────────────────────────────

class _PathCard extends StatelessWidget {
  const _PathCard({required this.controller});

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final VpTrip t = controller.trip;
    final bool presenting = PresenterMode.isActive(context);
    final VpHop at = t.hops[controller.hop];
    return AirtimeCard(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final bool across = box.maxWidth >= 640 || presenting;
          final List<Widget> tiles = <Widget>[
            for (int i = 0; i < t.hops.length; i++)
              _HopTile(
                hop: t.hops[i],
                here: i == controller.hop,
                hide: _hideHop(t.hops[i]),
                showNote: !across,
              ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const AirtimeSectionTitle('The packet\'s path, toward the phone'),
              const SizedBox(height: AppSpacing.xs),
              if (across)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < tiles.length; i++) ...<Widget>[
                        if (i > 0) const _Arrow(down: false),
                        Expanded(child: tiles[i]),
                      ],
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < tiles.length; i++) ...<Widget>[
                      if (i > 0) const _Arrow(down: true),
                      tiles[i],
                    ],
                  ],
                ),
              if (across) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${at.id.label}: '
                  '${_hideHop(at) ? kVpHiddenText : at.note}',
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// While predicting, the AP and the air would give the answer away.
  bool _hideHop(VpHop h) =>
      controller.hidingAnswer && (h.id == VpHopId.ap || h.id == VpHopId.air);
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.down});

  final bool down;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Icon(
        down ? Icons.arrow_downward_rounded : Icons.arrow_forward_rounded,
        size: 16 * PresenterMode.scaleOf(context).marker,
        color: context.colors.textTertiary,
      ),
    ),
  );
}

class _HopTile extends StatelessWidget {
  const _HopTile({
    required this.hop,
    required this.here,
    required this.hide,
    required this.showNote,
  });

  final VpHop hop;
  final bool here;
  final bool hide;
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool lost = hop.lostHere && !hide;
    final String marking = hide
        ? '?'
        : showNote
        ? dscpLabel(hop.dscpOut)
        : dscpShort(hop.dscpOut);
    return Semantics(
      container: true,
      label:
          '${hop.id.label}. Marking ${hide ? 'hidden' : dscpLabel(hop.dscpOut)}.'
          '${lost ? ' Marking lost here.' : ''}'
          '${here ? ' The packet is here.' : ''}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: colors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: here
                  ? colors.primary
                  : lost
                  ? colors.statusDanger
                  : colors.border,
              width: here || lost ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                hop.id.label,
                style: text.labelMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                marking,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
              if (lost) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                _Badge(
                  icon: Icons.block_rounded,
                  text: 'Marking lost here',
                  color: colors.statusDanger,
                ),
              ],
              if (here) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                _Badge(
                  icon: Icons.call_rounded,
                  text: 'Packet here',
                  color: colors.textAccent,
                ),
              ],
              if (showNote) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  hide ? kVpHiddenText : hop.note,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon above a short label, so a narrow tile wraps between words.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(
        icon,
        size: 16 * PresenterMode.scaleOf(context).marker,
        color: color,
      ),
      Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

// ── The AP's queues ─────────────────────────────────────────────────────────

/// Download frames drawn in a lane before "+ n more".
const int _kMaxDrawnFrames = 40;

class _QueuesCard extends StatelessWidget {
  const _QueuesCard({required this.controller});

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final VpTrip t = controller.trip;
    final VpConfig c = controller.config;
    final bool hide = controller.hidingAnswer;
    final bool arrived = controller.hop >= VpHopId.air.index;
    final int frames = c.downloadRunning ? c.framesAhead : 0;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The AP\'s four queues (WMM)'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            c.downloadRunning
                ? 'The download waits in Best effort, $frames frames deep '
                      '(illustrative).'
                : 'No download: the queues are empty.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final AccessCategory ac in AccessCategory.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _Lane(
                ac: ac,
                frames: ac == AccessCategory.bestEffort ? frames : 0,
                call: !hide && t.queue == ac,
                arrived: arrived,
              ),
            ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              _Legend(kind: _Block.call, label: 'the call'),
              _Legend(kind: _Block.ghost, label: 'the call, not at the AP yet'),
              _Legend(kind: _Block.frame, label: 'a download frame'),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Block { call, ghost, frame }

class _Lane extends StatelessWidget {
  const _Lane({
    required this.ac,
    required this.frames,
    required this.call,
    required this.arrived,
  });

  final AccessCategory ac;
  final int frames;
  final bool call;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final int more = frames - _kMaxDrawnFrames;
    final String words =
        '${ac.label} queue, ${acCode(ac)}, ${upsLabel(ac)}: '
        '${frames == 0 ? 'no download frames' : '$frames download frames'}'
        '${call ? (arrived ? ', then the call' : ', the call is on its way') : ''}.';
    return Semantics(
      label: words,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 132 * scale.text,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ac.label,
                    style: text.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: call ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${acCode(ac)}, ${upsLabel(ac)}',
                    style: text.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 28 * scale.marker,
                child: CustomPaint(
                  painter: _LanePainter(
                    frames: frames.clamp(0, _kMaxDrawnFrames),
                    call: call ? (arrived ? _Block.call : _Block.ghost) : null,
                    ink: colors.textSecondary,
                    track: colors.border,
                    callFill: colors.primary,
                    onCall: colors.onPrimary,
                    ghost: colors.textAccent,
                    callStyle: text.labelSmall!.copyWith(
                      fontSize: scale.paintFont(
                        text.labelSmall!.fontSize ?? AppTextSize.caption,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                    stroke: scale.strokeWidth(1.5),
                  ),
                ),
              ),
            ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxs),
                child: Text(
                  '+ $more',
                  style: text.labelSmall?.copyWith(color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A lane: the AP transmits from the left. Download frames sit at the head;
/// the call sits behind them.
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.frames,
    required this.call,
    required this.ink,
    required this.track,
    required this.callFill,
    required this.onCall,
    required this.ghost,
    required this.callStyle,
    required this.stroke,
  });

  /// Dashed outline and label of a call not yet at the AP (textAccent, which
  /// clears contrast on the card in both themes; lime alone does not on
  /// white).
  final Color ghost;

  final int frames;
  final _Block? call;
  final Color ink;
  final Color track;
  final Color callFill;
  final Color onCall;
  final TextStyle callStyle;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final RRect lane = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.control),
    );
    canvas.drawRRect(lane, trackPaint);
    const double pad = 3;
    final double h = size.height - 2 * pad;
    const double callW = 44;
    final double room = size.width - 2 * pad - callW - pad;
    final double slot = frames == 0
        ? 0
        : (room / frames).clamp(2.0, h * 0.6).toDouble();
    final Paint framePaint = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (int i = 0; i < frames; i++) {
      final double x = pad + i * slot;
      canvas.drawRect(
        Rect.fromLTWH(x + 0.5, pad + 1, (slot - 1.5).clamp(1.0, 99.0), h - 2),
        framePaint,
      );
    }
    final _Block? kind = call;
    if (kind == null) return;
    final double x = pad + frames * slot + (frames == 0 ? 0 : pad);
    final RRect box = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, pad, callW, h),
      const Radius.circular(4),
    );
    if (kind == _Block.call) {
      canvas.drawRRect(box, Paint()..color = callFill);
    } else {
      _dashed(canvas, box.outerRect, ghost);
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: 'Call',
        style: callStyle.copyWith(
          color: kind == _Block.call ? onCall : ghost,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: callW);
    tp.paint(
      canvas,
      Offset(x + (callW - tp.width) / 2, pad + (h - tp.height) / 2),
    );
  }

  void _dashed(Canvas canvas, Rect r, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = stroke * 1.3
      ..style = PaintingStyle.stroke;
    const double dash = 4;
    for (double x = r.left; x < r.right; x += dash * 2) {
      final double e = (x + dash).clamp(r.left, r.right);
      canvas.drawLine(Offset(x, r.top), Offset(e, r.top), p);
      canvas.drawLine(Offset(x, r.bottom), Offset(e, r.bottom), p);
    }
    for (double y = r.top; y < r.bottom; y += dash * 2) {
      final double e = (y + dash).clamp(r.top, r.bottom);
      canvas.drawLine(Offset(r.left, y), Offset(r.left, e), p);
      canvas.drawLine(Offset(r.right, y), Offset(r.right, e), p);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.frames != frames ||
      old.call != call ||
      old.ink != ink ||
      old.track != track ||
      old.callFill != callFill ||
      old.ghost != ghost ||
      old.stroke != stroke ||
      old.callStyle != callStyle;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.kind, required this.label});

  final _Block kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            width: (kind == _Block.frame ? 14 : 50) * scale.marker,
            height: 18 * scale.marker,
            child: CustomPaint(
              painter: _LanePainter(
                frames: kind == _Block.frame ? 1 : 0,
                call: kind == _Block.frame ? null : kind,
                ink: colors.textSecondary,
                track: Colors.transparent,
                callFill: colors.primary,
                onCall: colors.onPrimary,
                ghost: colors.textAccent,
                callStyle: text.labelSmall!.copyWith(
                  fontSize: 9 * scale.text,
                  fontWeight: FontWeight.w700,
                ),
                stroke: scale.strokeWidth(1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ── The wait on the Wi-Fi hop ──────────────────────────────────────────────

class _WaitsCard extends StatelessWidget {
  const _WaitsCard({required this.controller});

  final VoicePriorityController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final VpTrip t = controller.trip;
    final bool hide = controller.hidingAnswer;
    final Map<AccessCategory, double> waits = t.waitsByQueue;
    final double top = waits.values.reduce(
      (double a, double b) => a > b ? a : b,
    );
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Wait on the Wi-Fi hop'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            controller.config.downloadRunning
                ? 'While the download runs, per packet, average.'
                : 'No download, per packet, average.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final AccessCategory ac in kVpComparedQueues) ...<Widget>[
            Semantics(
              label:
                  '${ac.label}: ${vpMs(waits[ac]!)}'
                  '${!hide && t.queue == ac ? ', the call is here' : ''}',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            !hide && t.queue == ac
                                ? '${ac.label}: the call'
                                : ac.label,
                            style: text.labelMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: !hide && t.queue == ac
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          vpMs(waits[ac]!),
                          style: mono.inlineCode.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints b) {
                        final double w = top <= 0
                            ? 0
                            : (b.maxWidth * waits[ac]! / top).clamp(
                                3.0,
                                b.maxWidth,
                              );
                        final bool mine = !hide && t.queue == ac;
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: w,
                            height: 12 * scale.marker,
                            decoration: BoxDecoration(
                              color: mine ? colors.primary : colors.surface3,
                              border: Border.all(
                                color: mine
                                    ? colors.primary
                                    : colors.borderStrong,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            'From the Medium Access Simulator\'s engine: 1,500-byte frames at '
            '54 Mbps and a voice packet every 20 ms (illustrative). Wired '
            'hops add delay of their own, not shown.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
