// The stage for OFDMA Resource Units (Wi-Fi Lab): the channel drawn as a
// strip of resource units with the clients in them, and below it the SU, DL
// OFDMA and UL OFDMA timelines on one microsecond scale. Reads an
// [OfdmaSimulatorModel]; owns no state, so a presenter layout can place it
// beside [OfdmaSimulatorControls].
//
// States:
//   - placed        -> every client sits in an RU; timelines drawn
//   - selected      -> the client is ringed; dashed outlines show every free
//                      position the tone plan offers for its RU size
//   - does not fit  -> unplaced clients wait in a tray under the strip; the
//                      OFDMA rows are not drawn and say why (danger + words)
//   - PPDU too long -> that OFDMA row is not drawn and says why
//   - refused move  -> the notice line says why (live region)
//
// Interaction: drag a client along the channel (horizontal drags only, so
// the page still scrolls); or tap a client, then a dashed outline; or focus
// a client and use the arrow keys. Every block and outline is a focusable,
// labeled button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart' show formatTenthsUs;
import '../../../services/wifi_lab/ofdma_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'airtime_anatomy_timeline.dart';
import 'ofdma_simulator_model.dart';
import 'ofdma_simulator_painters.dart';

class OfdmaSimulatorStage extends StatelessWidget {
  const OfdmaSimulatorStage({super.key, required this.model});

  final OfdmaSimulatorModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ChannelCard(model: model),
          const SizedBox(height: AppSpacing.md),
          _TimelinesCard(model: model),
        ],
      ),
    );
  }
}

// ── The channel ─────────────────────────────────────────────────────────────

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({required this.model});

  final OfdmaSimulatorModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final int w = model.widthMhz;
    final List<int> unplaced = model.unplaced;
    final String? notice = model.notice;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The channel, cut into resource units'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$w MHz: ${OfdmaTonePlan.slots(w)} slots of 26 tones. '
            '${model.direction.label} (${model.direction.detail}): each '
            'client gets its own RU in one transmission.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Strip(model: model),
          const SizedBox(height: AppSpacing.xxs),
          _SubchannelAxis(widthMhz: w),
          if (unplaced.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _Tray(model: model, clients: unplaced),
          ],
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            container: true,
            child: Text(
              notice ??
                  (model.selected == null
                      ? 'Drag a client along the channel, or tap one and then '
                            'a dashed outline. Arrow keys move a focused '
                            'client.'
                      : 'Dashed outlines are the free spots the tone plan '
                            'offers a ${model.sizes[model.selected!].toneLabel} '
                            'RU. Tap one to move ${clientLetter(model.selected!)}.'),
              style: text.bodySmall?.copyWith(
                color: notice == null
                    ? colors.textTertiary
                    : colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Drawn in tone-plan order with every 26-tone slot the same width. '
            'Hatched slots are center 26-tone RUs, which only a 26-tone RU '
            'can use. Guard, DC and leftover tones are not drawn.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Drag payload: which client, and how wide its dragged block is.
typedef _Drag = ({int client, double width});

class _Strip extends StatefulWidget {
  const _Strip({required this.model});

  final OfdmaSimulatorModel model;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  final GlobalKey _key = GlobalKey();

  OfdmaSimulatorModel get model => widget.model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final int slots = OfdmaTonePlan.slots(model.widthMhz);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double sw = c.maxWidth / slots;
        Rect rectOf(RuSpan s) => Rect.fromLTWH(
          s.start * sw,
          0,
          s.length * sw,
          OfdmaGeometry.stripHeight,
        );
        final int? sel = model.selected;
        final List<RuSpan> targets = sel == null || model.placement[sel] == null
            ? const <RuSpan>[]
            : model.targetsFor(sel);
        return DragTarget<_Drag>(
          onAcceptWithDetails: (DragTargetDetails<_Drag> d) {
            final RenderBox? box =
                _key.currentContext?.findRenderObject() as RenderBox?;
            if (box == null) return;
            final Offset local = box.globalToLocal(
              d.offset +
                  Offset(d.data.width / 2, OfdmaGeometry.stripHeight / 2),
            );
            final int slot = (local.dx / sw).floor().clamp(0, slots - 1);
            model.moveTo(d.data.client, slot);
          },
          builder: (BuildContext context, List<_Drag?> hovering, _) {
            return SizedBox(
              key: _key,
              height: OfdmaGeometry.stripHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: OfdmaSlotGridPainter(
                          widthMhz: model.widthMhz,
                          colors: colors,
                        ),
                      ),
                    ),
                  ),
                  if (hovering.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: colors.primary, width: 2),
                          ),
                        ),
                      ),
                    ),
                  for (final RuSpan t in targets)
                    Positioned.fromRect(
                      rect: rectOf(t),
                      child: _Target(
                        label:
                            'Move ${clientLetter(sel!)} to ${model.sizes[sel].toneLabel} '
                            'RU at slots ${t.start + 1} to ${t.end}',
                        onTap: () => model.moveTo(sel, t.start),
                      ),
                    ),
                  for (int i = 0; i < model.clients; i++)
                    if (model.placement[i] != null)
                      Positioned.fromRect(
                        rect: rectOf(model.placement[i]!),
                        child: _RuBlock(
                          model: model,
                          client: i,
                          width: rectOf(model.placement[i]!).width,
                        ),
                      ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// One client's RU in the strip (or in the tray): draggable, focusable,
/// selectable, arrow keys to move.
class _RuBlock extends StatefulWidget {
  const _RuBlock({
    required this.model,
    required this.client,
    required this.width,
  });

  final OfdmaSimulatorModel model;
  final int client;
  final double width;

  @override
  State<_RuBlock> createState() => _RuBlockState();
}

class _RuBlockState extends State<_RuBlock> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final OfdmaSimulatorModel model = widget.model;
    final int c = widget.client;
    final bool selected = model.selected == c;
    final RuSize size = model.sizes[c];
    final RuSpan? at = model.placement[c];
    final String where = at == null
        ? 'not placed'
        : 'slots ${at.start + 1} to ${at.end}';

    Widget face({required bool ring}) =>
        _BlockFace(client: c, size: size, width: widget.width, ring: ring);

    return FocusableActionDetector(
      onShowFocusHighlight: (bool v) => setState(() => _focused = v),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): _NudgeIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _NudgeIntent(1),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => model.select(c),
        ),
        _NudgeIntent: CallbackAction<_NudgeIntent>(
          onInvoke: (_NudgeIntent i) => model.nudge(c, i.step),
        ),
      },
      mouseCursor: SystemMouseCursors.grab,
      child: Semantics(
        button: true,
        selected: selected,
        label:
            'Client ${clientLetter(c)}, ${size.toneLabel} RU, $where. '
            '${selected ? 'Selected. ' : ''}Arrow keys move it.',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => model.select(c),
          child: Draggable<_Drag>(
            data: (client: c, width: widget.width),
            affinity: Axis.horizontal,
            onDragStarted: () => model.setSelected(c),
            feedback: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                height: OfdmaGeometry.stripHeight,
                child: face(ring: true),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: face(ring: false)),
            child: face(ring: selected || _focused),
          ),
        ),
      ),
    );
  }
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.step);

  final int step;
}

class _BlockFace extends StatelessWidget {
  const _BlockFace({
    required this.client,
    required this.size,
    required this.width,
    required this.ring,
  });

  final int client;
  final RuSize size;
  final double width;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final WifiLabClientStyle st = WifiLabClientPalette.of(client, colors);
    final Color ink = st.outlined ? st.hue : st.onHue;
    final TextStyle letter =
        (text.labelLarge ?? const TextStyle(fontSize: AppTextSize.body))
            .copyWith(color: ink, fontWeight: FontWeight.w700);
    final TextStyle small =
        (text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption))
            .copyWith(color: ink);
    return Container(
      width: width,
      height: OfdmaGeometry.stripHeight,
      decoration: BoxDecoration(
        color: st.outlined ? colors.surface1 : st.hue,
        border: Border.all(
          color: ring
              ? colors.textPrimary
              : (st.outlined ? st.hue : colors.surface1),
          width: ring || st.outlined ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(clientLetter(client), style: letter),
              if (width >= AppSpacing.xl) Text(size.label, style: small),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed outline marking a free position for the selected client.
class _Target extends StatefulWidget {
  const _Target({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_Target> createState() => _TargetState();
}

class _TargetState extends State<_Target> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return FocusableActionDetector(
      onShowFocusHighlight: (bool v) => setState(() => _focused = v),
      onShowHoverHighlight: (bool v) => setState(() => _hover = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      mouseCursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: CustomPaint(
            painter: _DashedBoxPainter(
              color: _focused || _hover ? colors.primary : colors.textSecondary,
              width: _focused || _hover ? 2 : 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  _DashedBoxPainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(width / 2 + 1);
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = width;
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
  bool shouldRepaint(_DashedBoxPainter old) =>
      old.color != color || old.width != width;
}

/// 20 MHz subchannel labels under the strip.
class _SubchannelAxis extends StatelessWidget {
  const _SubchannelAxis({required this.widthMhz});

  final int widthMhz;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final int slots = OfdmaTonePlan.slots(widthMhz);
    final List<int> starts = OfdmaSlotGridPainter.subchannelStarts(widthMhz);
    final TextStyle style =
        (text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption))
            .copyWith(color: colors.textTertiary);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double sw = c.maxWidth / slots;
          final double subW = 9 * sw;
          final bool long = subW >= AppSpacing.xxl + AppSpacing.md;
          return SizedBox(
            height: AppSpacing.sm + AppSpacing.xxs,
            child: Stack(
              children: <Widget>[
                for (int k = 0; k < starts.length; k++)
                  Positioned(
                    left: starts[k] * sw,
                    width: subW,
                    top: 0,
                    child: Text(
                      starts.length == 1
                          ? '20 MHz'
                          : (long ? '20 MHz #${k + 1}' : '${k + 1}'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: style,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Clients with no room, waiting under the strip.
class _Tray extends StatelessWidget {
  const _Tray({required this.model, required this.clients});

  final OfdmaSimulatorModel model;
  final List<int> clients;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.statusDangerFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.statusDanger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                color: colors.statusDanger,
                size: AppSpacing.md,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'No room for ${clients.map(clientLetter).join(', ')}. '
                  'Make some RUs smaller, use a wider channel, or remove a '
                  'client.',
                  style: text.bodySmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final int c in clients)
                _RuBlock(model: model, client: c, width: AppSpacing.xl),
            ],
          ),
        ],
      ),
    );
  }
}

// ── The timelines ───────────────────────────────────────────────────────────

class _TimelinesCard extends StatelessWidget {
  const _TimelinesCard({required this.model});

  final OfdmaSimulatorModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final OfdmaResult r = model.result;
    final double scale = model.scaleUs;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Airtime, drawn to one scale'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${model.clients} ${model.clients == 1 ? 'client' : 'clients'}, '
            'one ${model.payloadBytes}-byte frame each, MCS ${model.mcs}. '
            'Each client keeps its color and letter from the channel above.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final OfdmaMode m in OfdmaMode.values) ...<Widget>[
            _Row(model: model, mode: m, scaleUs: scale, mono: mono),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (scale > 0) _Axis(scaleUs: scale),
          const SizedBox(height: AppSpacing.sm),
          const _Legend(),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: model.toggleWorking,
              icon: Icon(
                model.showWorking
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                model.showWorking
                    ? 'Hide the arithmetic'
                    : 'Show the arithmetic',
              ),
              style: TextButton.styleFrom(
                foregroundColor: colors.textAccent,
                minimumSize: const Size(0, AppSpacing.minTouchTarget),
              ),
            ),
          ),
          if (model.showWorking)
            for (final OfdmaMode m in OfdmaMode.values)
              if (r.timeline(m) != null)
                _Working(result: r, mode: m, mono: mono),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.model,
    required this.mode,
    required this.scaleUs,
    required this.mono,
  });

  final OfdmaSimulatorModel model;
  final OfdmaMode mode;
  final double scaleUs;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final OfdmaResult r = model.result;
    final OfdmaTimeline? t = r.timeline(mode);
    final bool compared = model.direction.mode == mode;
    final String? why = t == null
        ? r.check.message
        : (t.ppduTooLong
              ? 'Its PPDU would run past the 5.484 ms limit. A real AP would '
                    'give the slow client a bigger RU or a higher MCS'
              : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: mode.shortLabel,
                      style: TextStyle(
                        color: compared && mode != OfdmaMode.su
                            ? colors.textAccent
                            : colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: mode == OfdmaMode.su
                          ? '  ${model.clients} TXOPs, one per client'
                          : '  one TXOP',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ],
                ),
                style: text.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (why == null) ...<Widget>[
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${formatTenthsUs(t!.totalTenths)} µs',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (why != null)
          _Verdict(message: 'Not drawn. $why.')
        else
          _Bar(timeline: t!, scaleUs: scaleUs, clients: model.clients),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.timeline,
    required this.scaleUs,
    required this.clients,
  });

  final OfdmaTimeline timeline;
  final double scaleUs;
  final int clients;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextStyle base =
        text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption);
    final TextStyle letter = base.copyWith(fontWeight: FontWeight.w700);
    final double barH = timeline.mode == OfdmaMode.su
        ? OfdmaGeometry.barHeight
        : OfdmaGeometry.ofdmaBarHeight(clients);
    final double h = OfdmaBarPainter.heightFor(
      timeline: timeline,
      barHeight: barH,
      letterStyle: letter,
      textScaler: scaler,
    );

    final List<String> parts = <String>[
      '${timeline.mode.label}, ${formatTenthsUs(timeline.totalTenths)} '
          'microseconds in total',
    ];
    if (timeline.mode == OfdmaMode.su) {
      final List<OfdmaSegment> one = timeline.segments
          .where((OfdmaSegment s) => s.client == 0)
          .toList();
      parts.add(
        'each client in turn: '
        '${one.map((OfdmaSegment s) => '${s.label.replaceAll(' (A)', '')} ${formatTenthsUs(s.tenths)}').join(', ')}',
      );
    } else {
      for (final OfdmaSegment s in timeline.segments) {
        parts.add('${s.label} ${formatTenthsUs(s.tenths)}');
      }
    }

    return Semantics(
      label: parts.join('; '),
      image: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => CustomPaint(
          size: Size(c.maxWidth, h),
          painter: OfdmaBarPainter(
            timeline: timeline,
            scaleUs: scaleUs,
            barHeight: barH,
            colors: colors,
            labelStyle: base.copyWith(color: colors.textPrimary),
            letterStyle: letter,
            textScaler: scaler,
          ),
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.statusDangerFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.statusDanger),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: colors.statusDanger,
            size: AppSpacing.md,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Axis extends StatelessWidget {
  const _Axis({required this.scaleUs});

  final double scaleUs;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextStyle style =
        (text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption))
            .copyWith(color: colors.textTertiary);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => CustomPaint(
          size: Size(c.maxWidth, AirtimeAxisPainter.heightFor(style, scaler)),
          painter: AirtimeAxisPainter(
            scaleUs: scaleUs,
            colors: colors,
            style: style,
            textScaler: scaler,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextStyle label =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget item(CustomPainter p, String s) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: CustomPaint(
            size: const Size(AppSpacing.md, AppSpacing.sm),
            painter: p,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(s, style: label),
      ],
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        item(
          AirtimeSwatchPainter(style: AirtimeBlockStyle.wait, colors: colors),
          'Contention (AIFS, backoff)',
        ),
        item(
          AirtimeSwatchPainter(
            style: AirtimeBlockStyle.preamble,
            colors: colors,
          ),
          'Preamble',
        ),
        item(
          OfdmaDataSwatchPainter(colors: colors, padding: false),
          'Data, one color and letter per client',
        ),
        item(
          OfdmaDataSwatchPainter(colors: colors, padding: true),
          'Idle: that RU finished early',
        ),
        item(
          AirtimeSwatchPainter(
            style: AirtimeBlockStyle.control,
            colors: colors,
          ),
          'Trigger or acknowledgment',
        ),
        item(
          AirtimeSwatchPainter(style: AirtimeBlockStyle.gap, colors: colors),
          'SIFS (silence)',
        ),
      ],
    );
  }
}

/// One mode's segments with their working; estimates are tagged.
class _Working extends StatelessWidget {
  const _Working({
    required this.result,
    required this.mode,
    required this.mono,
  });

  final OfdmaResult result;
  final OfdmaMode mode;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final OfdmaTimeline t = result.timeline(mode)!;
    final bool su = mode == OfdmaMode.su;
    final List<OfdmaSegment> rows = su
        ? t.segments.where((OfdmaSegment s) => s.client == 0).toList()
        : t.segments;
    final int n = result.scenario.clients;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                su
                    ? '${mode.label}: client A shown; every client repeats it'
                    : mode.label,
                style: text.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final OfdmaSegment s in rows) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      su ? s.label.replaceAll(' (A)', '') : s.label,
                      style: text.bodySmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    s.durationLabel,
                    style: mono.inlineCode.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
              if (s.estimate != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                AssumptionTag(title: s.estimate!.title),
              ],
              const SizedBox(height: AppSpacing.xxs),
              Text(
                s.formula,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              su
                  ? 'One TXOP ${formatTenthsUs(result.suTxopTenths)} µs x $n = '
                        '${formatTenthsUs(t.totalTenths)} µs.'
                  : 'Total ${formatTenthsUs(t.totalTenths)} µs.',
              style: mono.inlineCode.copyWith(color: colors.textAccent),
            ),
          ],
        ),
      ),
    );
  }
}

/// A neutral "Assumption" tag (not a verdict, so no status hue).
class AssumptionTag extends StatelessWidget {
  const AssumptionTag({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Text(
          'Assumption: $title',
          style: text.labelSmall?.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
