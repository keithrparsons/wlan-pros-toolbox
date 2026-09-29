// The stage for OFDMA vs MU-MIMO (Wi-Fi Classroom): the room seen from above
// (AP, zero-forcing beams, draggable clients, a separability badge per pair),
// the verdict, and the two timelines on one microsecond scale.
//
// States:
//   - MU-MIMO runs       -> both bars, the sounding bracket, the verdict and
//                           why, the beams in the room
//   - no zero-forcing    -> too many clients, or two in one direction: the
//                           MU-MIMO row says why (danger, icon and words); no
//                           beams; OFDMA still drawn
//   - loss too high      -> beams drawn; the MU-MIMO row says which client
//                           cannot decode
//   - out of range       -> neither bar; the verdict names the client
//   - dragging           -> the dragged client is selected and everything
//                           recomputes as it moves
//
// Status hues are verdicts only (§8.13): the separability badges (success or
// warning, each with an icon and the word) and the refusal line. Lime
// (textAccent) marks the winner in the verdict.
//
// PRESENTER (PresenterMode.isActive): the verdict is a headline; the room and
// the timelines scale down together in the bounded stage, never a scroll.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart' show formatTenthsUs;
import '../../../services/wifi_lab/mu_mimo_model.dart';
import '../../../services/wifi_lab/ofdma_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'airtime_anatomy_timeline.dart';
import 'ofdma_simulator_painters.dart';
import 'ofdma_vs_mumimo_controller.dart';
import 'ofdma_vs_mumimo_painters.dart';

class OfdmaVsMumimoStage extends StatelessWidget {
  const OfdmaVsMumimoStage({super.key, required this.controller});

  final OfdmaVsMumimoController controller;

  /// Test handle for the room painting.
  static const Key roomKey = ValueKey<String>('mu-room');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        if (PresenterMode.isActive(context)) {
          return _PresenterStage(c: controller);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _RoomCard(c: controller),
            const SizedBox(height: AppSpacing.md),
            _AirtimeCard(c: controller),
          ],
        );
      },
    );
  }
}

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.c});

  final OfdmaVsMumimoController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Verdict(c: c, headline: true),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LayoutBuilder(
            // Room beside the timelines when the stage is wide; the pair
            // scales down as one piece if it still does not fit.
            builder: (BuildContext context, BoxConstraints box) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: box.maxWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 5, child: _RoomCard(c: c)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(flex: 6, child: _AirtimeCard(c: c)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── The room ────────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.c});

  final OfdmaVsMumimoController c;

  String _semantics(MuResult r) {
    final List<String> parts = <String>[
      'Room from above. AP with ${c.antennas} antennas.',
      for (int i = 0; i < c.clientCount; i++)
        'Client ${clientLetter(i)}, ${c.placeOf(i)}.',
      if (!r.precoding.possible)
        'No zero-forcing beams.'
      else
        'Each client has its own beam with a null toward the others.',
      if (c.reflection) 'Side-wall reflection on.',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final PresenterScale ps = PresenterMode.scaleOf(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final MuResult r = c.result;
    final TextStyle base =
        text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The room, from above'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Drag a client. Each colored lobe is the beam zero-forcing aims '
            'at that client, with a null toward every other client.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final double w = box.maxWidth;
              final Size size = Size(
                w,
                MuRoomGeometry.heightFor(w, marker: ps.marker),
              );
              return _DragRoom(
                c: c,
                size: size,
                marker: ps.marker,
                child: Semantics(
                  label: _semantics(r),
                  image: true,
                  excludeSemantics: true,
                  child: CustomPaint(
                    key: OfdmaVsMumimoStage.roomKey,
                    size: size,
                    painter: MuRoomPainter(
                      clients: c.clients,
                      precoding: r.precoding,
                      antennas: c.antennas,
                      reflection: c.reflection,
                      selected: c.selected,
                      colors: colors,
                      labelStyle: base,
                      letterStyle: base.copyWith(fontWeight: FontWeight.w700),
                      textScaler: scaler,
                      units: c.units,
                      viewRadiusM: c.viewRadiusM,
                      stroke: ps.stroke,
                      marker: ps.marker,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              // Pairs only mean something when the whole group can be
              // zero-forced; with more clients than antennas, one badge says
              // so instead of six pairs that would each read separable.
              if (r.block == MuBlock.tooManyClients)
                _Badge(
                  ok: false,
                  text:
                      '${c.clientCount} clients, ${c.antennas} antennas: not '
                      'separable as a group',
                )
              else
                for (final MuPair p in r.precoding.pairs) _PairBadge(pair: p),
            ],
          ),
        ],
      ),
    );
  }
}

/// Drag a client dot to move it; the nearest dot within a touch target is
/// picked up.
class _DragRoom extends StatefulWidget {
  const _DragRoom({
    required this.c,
    required this.size,
    required this.marker,
    required this.child,
  });

  final OfdmaVsMumimoController c;
  final Size size;
  final double marker;
  final Widget child;

  @override
  State<_DragRoom> createState() => _DragRoomState();
}

class _DragRoomState extends State<_DragRoom> {
  int? _dragging;

  MuRoomGeometry get _g => MuRoomGeometry(
    widget.size,
    marker: widget.marker,
    viewRadiusM: widget.c.viewRadiusM,
  );

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Pick up the dot where the finger landed, not where the drag was
        // recognized after the slop, or a quick drag misses it.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (DragStartDetails d) {
          final int? i = _g.clientAt(widget.c.clients, d.localPosition);
          _dragging = i;
          if (i != null) {
            widget.c.select(i);
            widget.c.beginDrag();
          }
        },
        onPanUpdate: (DragUpdateDetails d) {
          final int? i = _dragging;
          if (i == null) return;
          widget.c.moveClient(i, _g.toClient(d.localPosition));
        },
        onPanEnd: (_) {
          _dragging = null;
          widget.c.endDrag();
        },
        onPanCancel: () {
          _dragging = null;
          widget.c.endDrag();
        },
        onTapUp: (TapUpDetails d) {
          final int? i = _g.clientAt(widget.c.clients, d.localPosition);
          if (i != null) widget.c.select(i);
        },
        child: widget.child,
      ),
    );
  }
}

class _PairBadge extends StatelessWidget {
  const _PairBadge({required this.pair});

  final MuPair pair;

  @override
  Widget build(BuildContext context) {
    final String names = '${clientLetter(pair.a)} and ${clientLetter(pair.b)}';
    final bool ok = pair.separable;
    return _Badge(
      ok: ok,
      text:
          '$names: ${ok ? 'separable' : 'not separable'}'
          '${ok ? '' : ' (${muLossText(pair.lossDb)})'}',
      semantics:
          '$names: ${ok ? 'separable' : 'not separable'}, '
          '${muLossText(pair.lossDb)} as a pair',
    );
  }
}

/// A verdict chip: success or warning hue, always with its icon and words.
class _Badge extends StatelessWidget {
  const _Badge({required this.ok, required this.text, this.semantics});

  final bool ok;
  final String text;
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Color hue = ok ? colors.statusSuccess : colors.statusWarning;
    return Semantics(
      label: semantics ?? text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: ok ? colors.statusSuccessFill : colors.statusWarningFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: hue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color: hue,
              size: AppSpacing.md,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                text,
                style: t.bodySmall?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The verdict ─────────────────────────────────────────────────────────────

class _Verdict extends StatelessWidget {
  const _Verdict({required this.c, this.headline = false});

  final OfdmaVsMumimoController c;
  final bool headline;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final PresenterScale ps = PresenterMode.scaleOf(context);
    final MuResult r = c.result;
    final String? why = muVerdictWhy(r);
    final TextStyle big =
        (headline
                ? ps.headlineStyle(text.titleLarge ?? const TextStyle())
                : text.titleMedium ?? const TextStyle())
            .copyWith(color: colors.textAccent, fontWeight: FontWeight.w700);
    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Which wins here',
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        Text(muVerdictHeadline(r), style: big),
        if (why != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            why,
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ],
      ],
    );
    return Semantics(
      liveRegion: true,
      container: true,
      child: headline ? AirtimeCard(child: body) : body,
    );
  }
}

// ── The timelines ───────────────────────────────────────────────────────────

/// The OFDMA row's caption. In 802.11ax every RU carries its own MCS; with
/// equal RUs and equal frames the slowest client's RU needs the most symbols,
/// so it sets the PPDU length and the faster clients pad to it. That is the
/// airtime [computeOfdma] gives when run at the slowest client's MCS, which is
/// what the model does. Below a 242-tone RU, MCS 10 and 11 are not allowed,
/// so the model caps every client at MCS 9 (Vera gate B, 2026-09-29).
String ofdmaRowCaption(MuResult r, int exchanges) {
  final String ex =
      '$exchanges ${exchanges == 1 ? 'exchange' : 'exchanges'}, each client '
      'on its own ${r.ofdmaRu.toneLabel} RU';
  final int? run = r.ofdmaMcs;
  if (run == null || r.links.isEmpty) return ex;
  final List<int> mcs = <int>[
    for (final MuClientLink l in r.links) l.ofdmaMcs ?? run,
  ];
  final int slowest = mcs.reduce(math.min);
  if (run < slowest) {
    return '$ex, all at MCS $run: MCS 10 and 11 need a 242-tone RU or '
        'larger';
  }
  if (mcs.toSet().length == 1) return '$ex, all at MCS $run';
  final List<String> letters = <String>[
    for (int i = 0; i < mcs.length; i++)
      if (mcs[i] == slowest) clientLetter(i),
  ];
  final String who = letters.length == 1
      ? letters.single
      : '${letters.sublist(0, letters.length - 1).join(', ')} and '
            '${letters.last}';
  return '$ex at its own MCS; the slowest ($who, MCS $slowest) sets the '
      'length and the others pad';
}

class _AirtimeCard extends StatelessWidget {
  const _AirtimeCard({required this.c});

  final OfdmaVsMumimoController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool presenting = PresenterMode.isActive(context);
    final MuResult r = c.result;
    final double scale = r.scaleUs;
    final int n = c.exchanges;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!presenting) ...<Widget>[
            _Verdict(c: c),
            const SizedBox(height: AppSpacing.sm),
          ],
          const AirtimeSectionTitle('Airtime, drawn to one scale'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${c.clientCount} clients, one ${c.payloadBytes}-byte frame each '
            'per exchange, $n ${n == 1 ? 'exchange' : 'exchanges'} per '
            'sounding, ${c.widthMhz} MHz. Each client keeps its color and '
            'letter from the room.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            title: 'OFDMA',
            detail: r.ofdma == null
                ? ''
                : ofdmaRowCaption(r, n),
            timeline: r.ofdma,
            refusal: r.ofdma == null ? muVerdictHeadline(r) : null,
            scaleUs: scale,
            clients: c.clientCount,
            mono: mono,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Row(
            title: 'MU-MIMO',
            detail:
                'Sounding, then $n ${n == 1 ? 'exchange' : 'exchanges'}, each '
                'client on the whole channel, one stream',
            timeline: r.mu,
            refusal: r.mu == null ? _muRefusal(r) : null,
            scaleUs: scale,
            clients: c.clientCount,
            mono: mono,
            sounding: r.mu == null
                ? null
                : (
                    startUs: r.soundingStartTenths / 10,
                    lengthUs: r.soundingTenths / 10,
                  ),
            soundingLabel: 'Sounding ${formatTenthsUs(r.soundingTenths)} µs',
          ),
          const SizedBox(height: AppSpacing.sm),
          if (scale > 0) _Axis(scaleUs: scale),
          const SizedBox(height: AppSpacing.sm),
          const _Legend(),
          if (!presenting) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: c.toggleWorking,
                icon: Icon(
                  c.showWorking
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  c.showWorking ? 'Hide the arithmetic' : 'Show the arithmetic',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textAccent,
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
              ),
            ),
            if (c.showWorking) _Working(result: r, mono: mono),
          ],
        ],
      ),
    );
  }

  static String _muRefusal(MuResult r) => 'Not drawn. ${muBlockReason(r)}';
}

typedef _Span = ({double startUs, double lengthUs});

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.detail,
    required this.timeline,
    required this.refusal,
    required this.scaleUs,
    required this.clients,
    required this.mono,
    this.sounding,
    this.soundingLabel = '',
  });

  final String title;
  final String detail;
  final OfdmaTimeline? timeline;
  final String? refusal;
  final double scaleUs;
  final int clients;
  final AppMonoText mono;
  final _Span? sounding;
  final String soundingLabel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final OfdmaTimeline? t = timeline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (t != null)
              Text(
                '${formatTenthsUs(t.totalTenths)} µs',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
          ],
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        const SizedBox(height: AppSpacing.xs),
        if (t == null)
          _Refusal(message: refusal ?? '')
        else ...<Widget>[
          _Bar(timeline: t, scaleUs: scaleUs, clients: clients, title: title),
          if (sounding != null)
            _Bracket(span: sounding!, scaleUs: scaleUs, label: soundingLabel),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.timeline,
    required this.scaleUs,
    required this.clients,
    required this.title,
  });

  final OfdmaTimeline timeline;
  final double scaleUs;
  final int clients;
  final String title;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final PresenterScale ps = PresenterMode.scaleOf(context);
    final TextStyle base =
        text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption);
    final TextStyle letter = base.copyWith(fontWeight: FontWeight.w700);
    final double barH = math.max(
      ps.markerSize(OfdmaGeometry.barHeight),
      OfdmaGeometry.ofdmaBarHeight(clients),
    );
    // One spoken summary, not a list of every repeated block.
    final Map<String, int> firstOf = <String, int>{};
    for (final OfdmaSegment s in timeline.segments) {
      firstOf.putIfAbsent(s.label, () => s.tenths);
    }
    final String label =
        '$title, ${formatTenthsUs(timeline.totalTenths)} microseconds in '
        'total. Blocks: '
        '${firstOf.entries.map((MapEntry<String, int> e) => '${e.key} ${formatTenthsUs(e.value)}').join(', ')}.';
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => CustomPaint(
          size: Size(c.maxWidth, barH),
          painter: OfdmaBarPainter(
            timeline: timeline,
            scaleUs: scaleUs,
            barHeight: barH,
            colors: colors,
            labelStyle: base.copyWith(color: colors.textPrimary),
            letterStyle: letter,
            textScaler: scaler,
            stroke: ps.stroke,
          ),
        ),
      ),
    );
  }
}

class _Bracket extends StatelessWidget {
  const _Bracket({
    required this.span,
    required this.scaleUs,
    required this.label,
  });

  final _Span span;
  final double scaleUs;
  final String label;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextStyle style =
        text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => CustomPaint(
          size: Size(
            c.maxWidth,
            MuSoundingBracketPainter.heightFor(style, scaler),
          ),
          painter: MuSoundingBracketPainter(
            startUs: span.startUs,
            lengthUs: span.lengthUs,
            scaleUs: scaleUs,
            label: label,
            colors: colors,
            style: style,
            textScaler: scaler,
            stroke: PresenterMode.scaleOf(context).stroke,
          ),
        ),
      ),
    );
  }
}

class _Refusal extends StatelessWidget {
  const _Refusal({required this.message});

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
            stroke: PresenterMode.scaleOf(context).stroke,
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
    final PresenterScale scale = PresenterMode.scaleOf(context);

    Widget item(CustomPainter p, String s) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: CustomPaint(
            size: Size(
              scale.markerSize(AppSpacing.md),
              scale.markerSize(AppSpacing.sm),
            ),
            painter: p,
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: Text(s, style: label)),
      ],
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        item(
          AirtimeSwatchPainter(
            style: AirtimeBlockStyle.wait,
            colors: colors,
            stroke: scale.stroke,
          ),
          'Contention (AIFS, backoff)',
        ),
        item(
          AirtimeSwatchPainter(
            style: AirtimeBlockStyle.preamble,
            colors: colors,
            stroke: scale.stroke,
          ),
          'Preamble or sounding NDP',
        ),
        item(
          OfdmaDataSwatchPainter(colors: colors, padding: false),
          'Data: an RU in OFDMA, a stream in MU-MIMO',
        ),
        item(
          OfdmaDataSwatchPainter(colors: colors, padding: true),
          'Idle: that client finished early',
        ),
        item(
          AirtimeSwatchPainter(
            style: AirtimeBlockStyle.control,
            colors: colors,
            stroke: scale.stroke,
          ),
          'NDPA, trigger, reports or acks',
        ),
        item(
          AirtimeSwatchPainter(
            style: AirtimeBlockStyle.gap,
            colors: colors,
            stroke: scale.stroke,
          ),
          'SIFS (silence)',
        ),
      ],
    );
  }
}

/// The first exchange of each scheme (and the sounding), with the working.
class _Working extends StatelessWidget {
  const _Working({required this.result, required this.mono});

  final MuResult result;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    List<Widget> block(String title, List<OfdmaSegment> segs) => <Widget>[
      const SizedBox(height: AppSpacing.xs),
      Text(title, style: text.titleSmall?.copyWith(color: colors.textPrimary)),
      for (final OfdmaSegment s in segs)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '${s.label}, ${formatTenthsUs(s.tenths)} µs. ',
                  style: mono.inlineCode.copyWith(color: colors.textPrimary),
                ),
                TextSpan(
                  text: s.formula,
                  style: TextStyle(color: colors.textSecondary),
                ),
                if (s.estimate != null)
                  TextSpan(
                    text: ' Estimate: ${s.estimate!.title}.',
                    style: TextStyle(color: colors.textTertiary),
                  ),
              ],
            ),
            style: text.bodySmall,
          ),
        ),
    ];

    final OfdmaTimeline? one = result.ofdmaSingle?.dl;
    final OfdmaTimeline? mu = result.mu;
    final List<OfdmaSegment> muFirst = <OfdmaSegment>[];
    if (mu != null) {
      for (final OfdmaSegment s in mu.segments) {
        muFirst.add(s);
        if (s.kind == OfdmaSegmentKind.ack && s.shortLabel == 'BAs') break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (one != null) ...block('OFDMA, one exchange', one.segments),
        if (mu != null)
          ...block('MU-MIMO, sounding and the first exchange', muFirst),
      ],
    );
  }
}
