// The stage for Why a Busy Line Lags (Wi-Fi Classroom): the headline
// numbers, the video call's delay over the run, and the queue at the home
// line at the playhead. Reads a [LatencyUnderLoadController]; owns no state,
// so a presenter layout can place it beside [LatencyUnderLoadControls].
//
// COLOR AND MOTION: see latency_under_load_painter.dart.
//
// ACCESSIBILITY. The drawings are pictures: each carries a worded Semantics
// label, and every number they show is also in text (SC 1.4.1). Keyboard
// and screen-reader users move the playhead with the time slider in the
// controls; dragging on the chart does the same with a pointer.
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box; the
// chart takes the spare height and the headline numbers use the presenter
// headline scale.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/latency_under_load_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'latency_under_load_controller.dart';
import 'latency_under_load_painter.dart';

/// Height of the chart outside presenter mode.
const double kLulChartHeight = 260;

/// Height of the queue picture.
const double kLulQueueHeight = 84;

class LatencyUnderLoadStage extends StatelessWidget {
  const LatencyUnderLoadStage({super.key, required this.controller});

  final LatencyUnderLoadController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final Widget headline = _Headline(controller: controller);
        final Widget chart = _ChartCard(
          controller: controller,
          fill: presenting,
        );
        final Widget queue = _QueueCard(controller: controller);
        if (presenting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              headline,
              const SizedBox(height: AppSpacing.xs),
              Expanded(child: chart),
              const SizedBox(height: AppSpacing.xs),
              queue,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            headline,
            const SizedBox(height: AppSpacing.sm),
            chart,
            const SizedBox(height: AppSpacing.sm),
            queue,
          ],
        );
      },
    );
  }
}

/// The styles both painters use, with the presenter scale on painted text.
LulPaintStyle lulPaintStyle(BuildContext context) {
  final AppColorScheme colors = context.colors;
  final TextTheme text = Theme.of(context).textTheme;
  final AppMonoText mono =
      Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
  final PresenterScale scale = PresenterMode.scaleOf(context);
  TextStyle up(TextStyle t) =>
      t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
  return LulPaintStyle(
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

/// "Line idle", "Upload running", "Upload over, queue draining".
String lulPhase(LulLine line, bool sqm, double tS) {
  if (tS < kLulUploadStartS) return 'Line idle';
  if (tS < kLulUploadEndS) return 'Upload running';
  return lulQueueMs(line, sqm: sqm, tS: tS) > 0.05
      ? 'Upload over, queue draining'
      : 'Upload over, line idle';
}

// ── Headline ────────────────────────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.controller});

  final LatencyUnderLoadController controller;

  @override
  Widget build(BuildContext context) {
    final LulSummary s = controller.summary;
    final LulConfig c = controller.config;
    final LulLine l = c.line;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: controller.timeS,
          builder: (BuildContext context, double t, _) {
            final double now = lulLatencyMs(l, sqm: c.sqm, tS: t);
            final String phase = lulPhase(l, c.sqm, t);
            return _HeadlineTile(
              label: 'Video call delay at ${t.toStringAsFixed(1)} s',
              value: lulMs(now),
              note: phase,
              semantics:
                  'Video call delay at ${t.toStringAsFixed(1)} seconds: '
                  '${lulMs(now)}. $phase.',
            );
          },
        ),
        _HeadlineTile(
          label: 'While the upload runs, SQM ${c.sqm ? 'on' : 'off'}',
          value: lulMs(s.busyMs),
          note:
              '${lulTimes(s.timesIdle)}; '
              '${c.sqm ? 'illustrative' : 'FCC chart reading, approximate'}',
          semantics:
              'While the upload runs, smart queue management '
              '${c.sqm ? 'on' : 'off'}: ${lulMs(s.busyMs)}, '
              '${lulTimes(s.timesIdle)}. '
              '${c.sqm ? 'Illustrative.' : 'FCC chart reading, approximate.'}',
        ),
        _HeadlineTile(
          label: 'Idle ${l.inSentence} line',
          value: lulMs(s.idleMs),
          note: 'FCC measured ${lulMs(l.idleLowMs)} to ${lulMs(l.idleHighMs)}',
          semantics:
              'Idle ${l.label} line: ${lulMs(s.idleMs)}. The FCC measured '
              '${lulMs(l.idleLowMs)} to ${lulMs(l.idleHighMs)}.',
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
  });

  final String label;
  final String value;
  final String note;
  final String semantics;

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
          Text(
            note,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

// ── The chart ───────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.controller, required this.fill});

  final LatencyUnderLoadController controller;

  /// Fill a bounded box (presenter) instead of a fixed height.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final LulConfig c = controller.config;
    final Widget view = _ChartView(controller: controller);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('The video call\'s delay'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Round-trip delay of a video call on a ${c.line.inSentence} '
            'line, one sample every 100 ms, while someone else in the house '
            'uploads. Solid: smart queue management (SQM) '
            '${c.sqm ? 'on' : 'off'}. Dashed: SQM ${c.sqm ? 'off' : 'on'}, '
            'for comparison.',
            style: note,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (fill)
            Expanded(child: view)
          else
            SizedBox(height: kLulChartHeight, child: view),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            c.sqm
                ? 'SQM on is illustrative: no published consumer measurement '
                      'exists, so the curve sits at idle plus the 5 ms target '
                      'of FQ-CoDel (RFC 8290).'
                : 'SQM off follows the FCC\'s measurements (Measuring '
                      'Broadband America, 2022 test period), read from its '
                      'chart. The bracket is the range across the ISPs it '
                      'measured.',
            style: note,
          ),
        ],
      ),
    );
  }
}

class _ChartView extends StatelessWidget {
  const _ChartView({required this.controller});

  final LatencyUnderLoadController controller;

  @override
  Widget build(BuildContext context) {
    final LulConfig c = controller.config;
    final LulPaintStyle style = lulPaintStyle(context);
    return Semantics(
      label: _semantics(c),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Size size = Size(box.maxWidth, box.maxHeight);
          final LulChartGeometry g = LulChartGeometry(
            size,
            style,
            c.line.axisMaxMs,
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Horizontal only, so a vertical page scroll still wins.
            onHorizontalDragStart: (DragStartDetails d) =>
                controller.seek(g.tOf(d.localPosition.dx)),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                controller.seek(g.tOf(d.localPosition.dx)),
            onTapUp: (TapUpDetails d) =>
                controller.seek(g.tOf(d.localPosition.dx)),
            child: CustomPaint(
              size: size,
              painter: LulTracePainter(
                line: c.line,
                sqm: c.sqm,
                timeS: controller.timeS,
                style: style,
              ),
            ),
          );
        },
      ),
    );
  }

  static String _semantics(LulConfig c) {
    final LulLine l = c.line;
    final LulSummary s = LulSummary(c);
    return 'Chart of the video call\'s delay over ${kLulRunS.round()} '
        'seconds on a ${l.label} line. Idle, ${lulMs(s.idleMs)}. Someone '
        'else\'s upload runs from ${kLulUploadStartS.round()} to '
        '${kLulUploadEndS.round()} seconds. With smart queue management off '
        'the delay climbs to ${lulMs(s.busyOffMs)}; the FCC measured '
        '${lulMs(l.busyLowMs)} to ${lulMs(l.busyHighMs)} across ISPs. With '
        'it on the delay stays at ${lulMs(s.busyOnMs)}, illustrative. '
        'Showing SQM ${c.sqm ? 'on' : 'off'}.';
  }
}

// ── The queue ───────────────────────────────────────────────────────────────

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.controller});

  final LatencyUnderLoadController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);
    final LulConfig c = controller.config;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return AirtimeCard(
      child: ValueListenableBuilder<double>(
        valueListenable: controller.timeS,
        builder: (BuildContext context, double t, _) {
          final double q = lulQueueMs(c.line, sqm: c.sqm, tS: t);
          final String caption = c.sqm
              ? 'SQM on: the upload keeps a short queue of its own, and the '
                    'call\'s packet (the lime dot) goes in its turn. Waiting '
                    'now: ${lulMs(q)}.'
              : 'SQM off: one queue. The call\'s packet (the lime dot) waits '
                    'behind every upload packet (gray boxes). Waiting now: '
                    '${lulMs(q)}.';
          return Semantics(
            label: 'Queue at the home line. $caption',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const AirtimeSectionTitle('The queue at the home line'),
                const SizedBox(height: AppSpacing.xxs),
                Text(caption, style: note),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: kLulQueueHeight * scale.marker,
                  child: CustomPaint(
                    painter: LulQueuePainter(
                      line: c.line,
                      sqm: c.sqm,
                      timeS: controller.timeS,
                      style: lulPaintStyle(context),
                    ),
                    child: const SizedBox.expand(),
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
