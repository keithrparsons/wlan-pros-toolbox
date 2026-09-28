// The stage for Airtime Anatomy (Wi-Fi Classroom): the to-scale TXOP bars, the
// shared microsecond axis, the legend, the selected segment's formula, and a
// segment-by-segment table. Reads an [AirtimeAnatomyModel]; owns no state of
// its own, so a presenter layout can place it beside [AirtimeAnatomyControls].
//
// States:
//   - nothing selected -> the detail panel says how to select
//   - selected         -> the segment is ringed on its bar, the panel shows
//                         its duration, share and formula
//   - invalid scenario -> no bar; the Check verdict in danger, with icon and
//                         words, where the bar would be
//   - nothing drawable -> no axis; each row carries its own verdict
//
// Interaction: tap a segment or its leader label; hover on desktop; or use the
// table below the bars, whose cells are focusable buttons (keyboard and
// screen reader route to the same selection).
//
// PRESENTER (PresenterMode.isActive): the same parts fill the bounded stage
// box with no scroll. Each scenario's throughput, TXOP length and efficiency
// sit on top at the headline scale (the numbers the lesson is about, moved
// here from the controls' readouts); the bars are taller and thicker; the
// selected segment's formula sits under them. The Right arrow walks the
// selection through the TXOP segment by segment; the breakdown table, the
// same selection by pointer or Tab, folds into the panel
// ([AirtimeAnatomyBreakdown]).
//
// VIEW (1.11.0): a Time / Structure toggle heads the stage. Time is the
// TXOP drawn to scale, unchanged. Structure ([AirtimeStructureView]) opens
// the PSDU of the scenario under edit: the same aggregate, in bytes. V
// switches views in presenter mode.

import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';

import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'airtime_anatomy_model.dart';
import 'airtime_anatomy_timeline.dart';
import 'airtime_structure_view.dart';

class AirtimeAnatomyStage extends StatelessWidget {
  const AirtimeAnatomyStage({super.key, required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, _) => PresenterMode.isActive(context)
          ? _PresenterStage(model: model)
          : _StageBody(model: model),
    );
  }
}

// ── Presenter arrangement ─────────────────────────────────────────────────

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double scale = model.scaleUs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The time headline gives its room to the structure drawing.
        if (model.view == AirtimeView.time) ...<Widget>[
          AirtimeCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final int i in model.visible) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _Headline(model: model, index: i, mono: mono),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _ViewToggle(model: model),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LayoutBuilder(
            // Shown at full size when it fits; with RTS/CTS and many leader
            // rows on a 900 px window it scales down as one piece, never a
            // scroll.
            builder: (BuildContext context, BoxConstraints box) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: box.maxWidth,
                child: model.view == AirtimeView.structure
                    ? AirtimeStructureView(model: model)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          AirtimeCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                const AirtimeSectionTitle(
                                  'One TXOP, drawn to scale',
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  'Lime is the only part that carries your data.',
                                  style: text.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                for (final int i in model.visible) ...<Widget>[
                                  _ScenarioRow(
                                    model: model,
                                    index: i,
                                    scaleUs: scale,
                                    mono: mono,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                ],
                                if (scale > 0) _Axis(scaleUs: scale),
                                const SizedBox(height: AppSpacing.sm),
                                const _Legend(),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _Detail(model: model, mono: mono),
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

/// One scenario's lesson numbers, large: throughput at the headline scale,
/// with the TXOP length and the efficiency under it.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.model,
    required this.index,
    required this.mono,
  });

  final AirtimeAnatomyModel model;
  final int index;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final AirtimeResult r = model.result(index);
    final String letter = kScenarioLetters[index];
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _LetterBadge(letter),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  model.name(index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (!r.check.isOk)
            Text(
              'Not drawn: ${r.check.message}.',
              style: text.bodyMedium?.copyWith(color: colors.statusDanger),
            )
          else ...<Widget>[
            Text(
              'Throughput',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${r.throughputMbps.toStringAsFixed(1)} Mbps',
                style: scale
                    .headlineStyle(mono.outputLarge)
                    .copyWith(color: colors.textAccent),
              ),
            ),
            Text(
              '${formatTenthsUs(r.totalTenths)} µs, '
              '${(r.efficiency * 100).toStringAsFixed(1)} % efficient',
              semanticsLabel:
                  '${formatTenthsUs(r.totalTenths)} microseconds on the air, '
                  '${(r.efficiency * 100).toStringAsFixed(1)} percent of the '
                  'PHY rate',
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageBody extends StatelessWidget {
  const _StageBody({required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double scale = model.scaleUs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ViewToggle(model: model),
        const SizedBox(height: AppSpacing.sm),
        if (model.view == AirtimeView.structure)
          AirtimeStructureView(model: model)
        else
          _timeCard(text, colors, mono, scale),
      ],
    );
  }

  Widget _timeCard(
    TextTheme text,
    AppColorScheme colors,
    AppMonoText mono,
    double scale,
  ) {
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AirtimeSectionTitle('One TXOP, drawn to scale'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Wait, preamble, data, SIFS, acknowledgment. Lime is the only '
            'part that carries your data.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final int i in model.visible) ...<Widget>[
            _ScenarioRow(model: model, index: i, scaleUs: scale, mono: mono),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (scale > 0) _Axis(scaleUs: scale),
          const SizedBox(height: AppSpacing.sm),
          const _Legend(),
          const SizedBox(height: AppSpacing.sm),
          _Detail(model: model, mono: mono),
          const SizedBox(height: AppSpacing.sm),
          _Breakdown(model: model, mono: mono),
        ],
      ),
    );
  }
}

/// Time or Structure. Both views describe the scenario under edit; the
/// structure view names which one.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) => AppToggle<AirtimeView>(
    value: model.view,
    expand: true,
    semanticLabel:
        'View: time, the TXOP to scale, or structure, inside the PSDU',
    items: <AppToggleItem<AirtimeView>>[
      (AirtimeView.time, 'Time'),
      (AirtimeView.structure, 'Structure'),
    ],
    onChanged: model.setView,
  );
}

/// Header line plus bar (or verdict) for one scenario.
class _ScenarioRow extends StatelessWidget {
  const _ScenarioRow({
    required this.model,
    required this.index,
    required this.scaleUs,
    required this.mono,
  });

  final AirtimeAnatomyModel model;
  final int index;
  final double scaleUs;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AirtimeResult r = model.result(index);
    final String letter = kScenarioLetters[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            _LetterBadge(letter),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                model.name(index),
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (r.check.isOk)
              Text(
                '${formatTenthsUs(r.totalTenths)} µs',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (r.check.isOk)
          _Bar(model: model, index: index, scaleUs: scaleUs)
        else
          _Verdict(check: r.check),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.model, required this.index, required this.scaleUs});

  final AirtimeAnatomyModel model;
  final int index;
  final double scaleUs;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final PresenterScale pscale = PresenterMode.scaleOf(context);
    final AirtimeResult r = model.result(index);
    final TextStyle base =
        text.labelSmall ?? const TextStyle(fontSize: AppTextSize.caption);
    final AirtimeSelection? sel = model.selection;
    final TxopSegmentKind? selected = sel != null && sel.scenario == index
        ? sel.kind
        : null;

    final String spoken = <String>[
      'Scenario ${kScenarioLetters[index]}, ${model.name(index)}, '
          '${formatTenthsUs(r.totalTenths)} microseconds in total',
      for (final TxopSegment s in r.segments)
        if (s.tenths > 0) '${s.label} ${formatTenthsUs(s.tenths)} microseconds',
    ].join('; ');

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final AirtimeBarLayout layout = AirtimeBarLayout.compute(
          result: r,
          width: c.maxWidth,
          scaleUs: scaleUs,
          insideStyle: base.copyWith(color: colors.textPrimary),
          dataInsideStyle: base.copyWith(
            color: colors.onPrimary,
            fontWeight: FontWeight.w600,
          ),
          leaderStyle: base.copyWith(color: colors.textSecondary),
          textScaler: scaler,
          barHeight: pscale.markerSize(AirtimeBarGeometry.barHeight),
        );
        return Semantics(
          label: spoken,
          image: true,
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (PointerHoverEvent e) {
              final TxopSegmentKind? k = layout.hitTest(e.localPosition);
              if (k != null) model.hover(index, k);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) {
                final TxopSegmentKind? k = layout.hitTest(d.localPosition);
                if (k != null) model.select(index, k);
              },
              child: CustomPaint(
                size: Size(c.maxWidth, layout.height),
                painter: AirtimeBarPainter(
                  layout: layout,
                  colors: colors,
                  selected: selected,
                  stroke: pscale.stroke,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.check});

  final AirtimeCheck check;

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
              'Not drawn. ${check.message}.',
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
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final AirtimeBlockStyle s in AirtimeBlockStyle.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: CustomPaint(
                  size: Size(
                    scale.markerSize(AppSpacing.md),
                    scale.markerSize(AppSpacing.sm),
                  ),
                  painter: AirtimeSwatchPainter(
                    style: s,
                    colors: colors,
                    stroke: scale.stroke,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                s.label,
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.model, required this.mono});

  final AirtimeAnatomyModel model;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AirtimeSelection? sel = model.selection;

    final Widget body;
    if (sel == null) {
      body = Text(
        PresenterMode.isActive(context)
            ? 'Press the Right arrow to walk the TXOP segment by segment, or '
                  'tap a segment, to see its duration and the formula '
                  'behind it.'
            : 'Tap or hover a segment, or pick one in the table, to see its '
                  'duration and the formula behind it.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      );
    } else {
      final AirtimeResult r = model.result(sel.scenario);
      final TxopSegment s = r.segment(sel.kind);
      final double pct = r.totalTenths == 0
          ? 0
          : s.tenths / r.totalTenths * 100;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${kScenarioLetters[sel.scenario]} · ${s.label}',
            style: text.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${s.durationLabel}, ${pct.toStringAsFixed(1)} % of this TXOP',
            style: mono.inlineCode.copyWith(color: colors.textAccent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            s.formula,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border),
        ),
        child: body,
      ),
    );
  }
}

/// The breakdown table on its own, for the presenter panel's fold.
class AirtimeAnatomyBreakdown extends StatelessWidget {
  const AirtimeAnatomyBreakdown({super.key, required this.model});

  final AirtimeAnatomyModel model;

  @override
  Widget build(BuildContext context) => _Breakdown(
    model: model,
    mono: Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults(),
  );
}

/// Segment | A | B, each duration a focusable button that selects it.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.model, required this.mono});

  final AirtimeAnatomyModel model;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final List<int> cols = model.visible;
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);

    Widget cell(int i, TxopSegmentKind kind) {
      final AirtimeResult r = model.result(i);
      if (!r.check.isOk) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            '--',
            textAlign: TextAlign.end,
            style: mono.inlineCode.copyWith(color: colors.textTertiary),
          ),
        );
      }
      final TxopSegment s = r.segment(kind);
      final AirtimeSelection? sel = model.selection;
      final bool on = sel != null && sel.scenario == i && sel.kind == kind;
      return Semantics(
        selected: on,
        child: TextButton(
          onPressed: s.tenths == 0 ? null : () => model.select(i, kind),
          style: TextButton.styleFrom(
            alignment: Alignment.centerRight,
            minimumSize: const Size(0, AppSpacing.minTouchTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            backgroundColor: on ? colors.primary : null,
            foregroundColor: on ? colors.onPrimary : colors.textPrimary,
            disabledForegroundColor: colors.textTertiary,
            textStyle: mono.inlineCode,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          child: Text(
            s.tenths == 0 ? 'off' : formatTenthsUs(s.tenths),
            semanticsLabel:
                '${kScenarioLetters[i]} ${s.label}: '
                '${s.tenths == 0 ? 'off' : '${formatTenthsUs(s.tenths)} microseconds'}',
          ),
        ),
      );
    }

    String rowLabel(TxopSegmentKind k) {
      if (k != TxopSegmentKind.ack) return k.label;
      final Set<String> labels = <String>{
        for (final int i in cols) model.result(i).segment(k).label,
      };
      return labels.length == 1 ? labels.first : 'ACK / Block Ack';
    }

    return Table(
      columnWidths: <int, TableColumnWidth>{
        0: const FlexColumnWidth(1.3),
        for (int c = 1; c <= cols.length; c++) c: const FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: <TableRow>[
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text('Segment (µs)', style: head),
            ),
            for (final int i in cols)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: AppSpacing.xxs,
                  right: AppSpacing.xs,
                ),
                child: Text(
                  kScenarioLetters[i],
                  textAlign: TextAlign.end,
                  style: head,
                ),
              ),
          ],
        ),
        for (final TxopSegmentKind k in TxopSegmentKind.values)
          TableRow(
            children: <Widget>[
              Text(
                rowLabel(k),
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              for (final int i in cols) cell(i, k),
            ],
          ),
        TableRow(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Total',
                style: text.bodySmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final int i in cols)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                ),
                child: Text(
                  model.result(i).check.isOk
                      ? formatTenthsUs(model.result(i).totalTenths)
                      : '--',
                  textAlign: TextAlign.end,
                  style: mono.inlineCode.copyWith(color: colors.textPrimary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LetterBadge extends StatelessWidget {
  const _LetterBadge(this.letter);

  final String letter;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: AppSpacing.md,
      height: AppSpacing.md,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Text(
        letter,
        style: text.labelMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AirtimeSectionTitle extends StatelessWidget {
  const AirtimeSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The standard tool card, shared with the controls (surface1, card radius, hairline border).
class AirtimeCard extends StatelessWidget {
  const AirtimeCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
