// The stage for Repeaters and Mesh Backhaul (Wi-Fi Classroom): the headline
// numbers, the corridor with the root AP, the relays and the client (each
// hop drawn with its rate, the nodes draggable), and the air in use, which
// shows the hops taking turns on one channel or running at once on channels
// of their own. Reads a [RepeaterMeshController]; owns no state beyond a
// drag in progress, so a presenter layout can place it beside
// [RepeaterMeshControls].
//
// COLOR AND MOTION: see repeater_mesh_painter.dart.
//
// ACCESSIBILITY. The drawings are pictures: each carries a worded Semantics
// label, and every number they show is also in text (SC 1.4.1). Keyboard and
// screen-reader users move the nodes with the position sliders in the
// controls.
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box; the
// corridor takes the spare height and the headline numbers use the presenter
// headline scale.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/repeater_mesh_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'repeater_mesh_controller.dart';
import 'repeater_mesh_painter.dart';

/// Height of the corridor view outside presenter mode.
const double kRmCorridorHeight = 240;

class RepeaterMeshStage extends StatelessWidget {
  const RepeaterMeshStage({super.key, required this.controller});

  final RepeaterMeshController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget corridor = _CorridorCard(
          controller: controller,
          fill: presenting,
        );
        final Widget air = _AirCard(controller: controller);
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: corridor),
              const SizedBox(height: AppSpacing.xs),
              air,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            headline,
            const SizedBox(height: AppSpacing.sm),
            corridor,
            const SizedBox(height: AppSpacing.sm),
            air,
          ],
        );
      },
    );
  }
}

/// The styles both painters use, with the presenter scale on painted text.
RmPaintStyle rmPaintStyle(BuildContext context) {
  final AppColorScheme colors = context.colors;
  final TextTheme text = Theme.of(context).textTheme;
  final AppMonoText mono =
      Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
  final PresenterScale scale = PresenterMode.scaleOf(context);
  TextStyle up(TextStyle t) =>
      t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
  return RmPaintStyle(
    colors: colors,
    scale: scale,
    label: up(
      text.labelSmall!.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    ),
    small: up(
      mono.inlineCode.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textTertiary,
      ),
    ),
  );
}

/// "2.0 times" or "89%" of the straight-to-AP throughput.
String rmVersus(RmResult r) {
  final double? v = r.versusDirect;
  if (v == null) return 'The client cannot reach the AP directly from here';
  if (v >= 1.05) return '${v.toStringAsFixed(1)} times straight to the AP';
  if (v > 0.95) return 'About the same as straight to the AP';
  return '${(v * 100).round()}% of straight to the AP';
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final RepeaterMeshController controller;

  @override
  Widget build(BuildContext context) {
    final RmResult r = controller.result;
    final RmConfig c = r.config;
    final bool masked = controller.masked;
    final int n = c.relayCount;
    final String through = 'through $n relay${n == 1 ? '' : 's'}';
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        _HeadlineTile(
          label: 'End to end, $through',
          value: masked ? '?' : rmMbps(r.endToEndMbps),
          note: masked
              ? 'hidden until Reveal'
              : r.broken
              ? 'A hop has no link, so nothing gets through'
              : rmVersus(r),
          semantics: masked
              ? 'End-to-end throughput hidden until Reveal'
              : 'End to end $through: ${rmMbps(r.endToEndMbps)}. '
                    '${r.broken ? 'A hop has no link.' : rmVersus(r)}',
          danger: !masked && r.broken,
        ),
        _HeadlineTile(
          label: 'Straight to the AP, same spot',
          value: masked
              ? '?'
              : r.direct.hasLink
              ? rmMbps(r.direct.throughputMbps)
              : 'no link',
          note: 'from ${rmMeters(c.clientM)}, for comparison',
          semantics: masked
              ? 'Straight-to-AP throughput hidden until Reveal'
              : 'Straight to the AP from ${rmMeters(c.clientM)}: '
                    '${r.direct.hasLink ? rmMbps(r.direct.throughputMbps) : 'no link'}',
        ),
        _HeadlineTile(
          label: 'Forwarding delay',
          value: rmMs(r.delayMs),
          note:
              '${r.hops.length} hops; ${rmMs(r.directDelayMs)} straight to '
              'the AP (illustrative)',
          semantics:
              'Forwarding delay ${rmMs(r.delayMs)} over ${r.hops.length} '
              'hops, ${rmMs(r.directDelayMs)} straight to the AP',
        ),
      ],
    );
  }
}

class _HeadlineTile extends StatelessWidget {
  const _HeadlineTile({
    required this.label,
    required this.value,
    required this.note,
    required this.semantics,
    this.danger = false,
  });

  final String label;
  final String value;
  final String note;
  final String semantics;

  /// A computed "no link" verdict (§8.13): danger, with an icon and words.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          Text(
            value,
            style: scale.headlineStyle(
              mono.outputLarge.copyWith(color: colors.textAccent),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (danger) ...<Widget>[
                Icon(
                  Icons.error_outline_rounded,
                  size: AppSpacing.sm,
                  color: colors.statusDanger,
                ),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  note,
                  style: text.bodySmall?.copyWith(
                    color: danger ? colors.statusDanger : colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── The corridor ────────────────────────────────────────────────────────────

class _CorridorCard extends StatelessWidget {
  const _CorridorCard({required this.controller, required this.fill});

  final RepeaterMeshController controller;

  /// Fill a bounded box (presenter) instead of a fixed height.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RmConfig c = controller.config;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final Widget view = _CorridorView(controller: controller);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The corridor'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${c.band.label}, ${c.band.widthMHz} MHz. Each arc is one hop, '
            'labeled with its MCS (modulation and coding scheme) and the '
            'throughput it would carry alone. Drag a relay or the client.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fill)
            Expanded(child: view)
          else
            SizedBox(height: kRmCorridorHeight, child: view),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Square: the root AP, on the wired network. Diamond: a relay. '
            'Dot: the client. The lime arc and dot: the hop sending now. '
            'Dashed: no link.',
            style: note,
          ),
        ],
      ),
    );
  }
}

class _CorridorView extends StatefulWidget {
  const _CorridorView({required this.controller});

  final RepeaterMeshController controller;

  @override
  State<_CorridorView> createState() => _CorridorViewState();
}

class _CorridorViewState extends State<_CorridorView> {
  /// The node being dragged, or null.
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    final RepeaterMeshController k = widget.controller;
    final RmResult r = k.result;
    final RmPaintStyle style = rmPaintStyle(context);
    return Semantics(
      label: _semantics(r, k.masked),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Size size = Size(box.maxWidth, box.maxHeight);
          final RmCorridorGeometry g = RmCorridorGeometry(
            size,
            style.scale,
            rmLineHeight(style.small),
          );
          void start(Offset local) {
            _dragging = g.nearestMovable(r.config.nodesM, local.dx);
            _move(local);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A horizontal drag recognizer, not pan: nodes move along the
            // corridor only, and a vertical page scroll still wins.
            onHorizontalDragStart: (DragStartDetails d) =>
                start(d.localPosition),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _move(d.localPosition),
            onHorizontalDragEnd: (_) => _dragging = null,
            onHorizontalDragCancel: () => _dragging = null,
            child: CustomPaint(
              size: size,
              painter: RmCorridorPainter(
                result: r,
                schedule: rmSchedule(r),
                masked: k.masked,
                style: style,
                phase: k.phase,
              ),
            ),
          );
        },
      ),
    );
  }

  void _move(Offset local) {
    final int? i = _dragging;
    if (i == null) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final RmCorridorGeometry g = RmCorridorGeometry(
      box.size,
      PresenterMode.scaleOf(context),
      rmLineHeight(rmPaintStyle(context).small),
    );
    widget.controller.moveNode(i, g.mOf(local.dx));
  }

  static String _semantics(RmResult r, bool masked) {
    final RmConfig c = r.config;
    final StringBuffer b = StringBuffer(
      'Corridor, ${c.band.label}, ${c.backhaul.label}. ',
    );
    for (final RmHop h in r.hops) {
      final String from = rmNodeName(h.from, c.relayCount);
      final String to = rmNodeName(h.to, c.relayCount);
      if (h.wired) {
        b.write('Hop ${h.from + 1}, $from to $to: cable. ');
      } else if (!h.link.hasLink) {
        b.write(
          'Hop ${h.from + 1}, $from to $to, ${rmMeters(h.link.distanceM)}: '
          'no link. ',
        );
      } else {
        b.write(
          'Hop ${h.from + 1}, $from to $to, ${rmMeters(h.link.distanceM)}: '
          'MCS ${h.link.mcs}'
          '${masked ? '' : ', ${rmMbps(h.throughputMbps)}'}. ',
        );
      }
    }
    return b.toString().trimRight();
  }
}

// ── Air in use ──────────────────────────────────────────────────────────────

class _AirCard extends StatelessWidget {
  const _AirCard({required this.controller});

  final RepeaterMeshController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final RmResult r = controller.result;
    final RmConfig c = r.config;
    final RmPaintStyle style = rmPaintStyle(context);
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final List<RmSlot?> schedule = rmSchedule(r);
    final List<List<(int, RmSlot)>> lanes = rmLanes(r, schedule);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final TextStyle laneLabel =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    String pct(double s) => '${(s * 100).round()}%';
    String label(List<(int, RmSlot)> lane) {
      if (c.backhaul == RmBackhaul.sameChannel) {
        return 'One shared channel';
      }
      final int hop = lane.first.$1;
      return 'Hop ${hop + 1}, own channel, busy '
          '${pct(r.hops[hop].airShare)}';
    }

    final String caption = r.broken
        ? 'A hop the chain needs has no link, so no air is used.'
        : switch (c.backhaul) {
            RmBackhaul.sameChannel =>
              'One channel, shared: the hops take turns, back to back. Each '
                  'block is one hop\'s share of the air: '
                  '${r.hops.map((RmHop h) => 'hop ${h.from + 1} ${pct(h.airShare)}').join(', ')}.',
            RmBackhaul.dedicated =>
              'A channel per hop: all hops send at once. The slowest hop is '
                  'busy all the time; the others wait for it.',
            RmBackhaul.wired =>
              'Only the last hop is on the air; the cable carries the rest.',
          };

    final double laneHeight = AppSpacing.md * scale.text;
    // Label beside its lane, so four lanes stay short enough for the
    // presenter's corridor to keep its height.
    final List<Widget> rows = <Widget>[
      if (!r.broken)
        for (final List<(int, RmSlot)> lane in lanes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              children: <Widget>[
                Expanded(flex: 2, child: Text(label(lane), style: laneLabel)),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  flex: 5,
                  child: SizedBox(
                    height: laneHeight,
                    child: CustomPaint(
                      painter: RmLanePainter(
                        blocks: lane,
                        style: style,
                        phase: controller.phase,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
    ];

    return AirtimeCard(
      child: Semantics(
        label: 'Air in use. $caption',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const AirtimeSectionTitle('Air in use'),
            const SizedBox(height: AppSpacing.xxs),
            Text(caption, style: note),
            const SizedBox(height: AppSpacing.xs),
            ...rows,
          ],
        ),
      ),
    );
  }
}
