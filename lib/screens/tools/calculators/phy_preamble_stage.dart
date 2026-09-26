// The stage for the PHY Preamble Reference (Wi-Fi Lab): the preamble drawn to
// scale, its legend, the blocks as a focusable list, and either the selected
// block's bit table (Explore) or the receiver's decision walk (Which PHY?).
// Reads a PhyPreambleModel; owns no state of its own, so a presenter layout
// can place it beside PhyPreambleControls.
//
// States:
//   - nothing selected -> the detail panel says how to open a block
//   - selected         -> ringed on the bar and filled in the list; the panel
//                         shows duration, modulation, evidence and bits
//   - Data selected    -> the SERVICE field (not to scale, said in words)
//   - mystery PPDU     -> every field after L-SIG drawn neutral and named
//                         "?", the list says "hidden", until the walk ends
//   - walk             -> steps revealed one at a time, then the verdict
//   - loading / error  -> not reachable: the model is synchronous and pure
//                         and every input is bounded
//
// PRESENTER (PresenterMode.isActive): the stage fills its bounded box with no
// scroll. The preamble's length is the headline beside the title; the bar is
// taller with larger labels; the block list moves to the panel (the Right
// arrow walks the blocks); and the open block's bit table lays its groups
// side by side. If a table is still taller than the room left, it scales
// down as one piece rather than clip or scroll.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'phy_preamble_bit_table.dart';
import 'phy_preamble_model.dart';
import 'phy_preamble_painter.dart';
import 'phy_preamble_palette.dart';
import 'phy_preamble_parts.dart';

class PhyPreambleStage extends StatelessWidget {
  const PhyPreambleStage({super.key, required this.model});

  final PhyPreambleModel model;

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

class _StageBody extends StatelessWidget {
  const _StageBody({required this.model});

  final PhyPreambleModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool identify = model.mode == PreambleMode.identify;
    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              model.hidden
                  ? 'Mystery PPDU, drawn to scale'
                  : '${model.type.label}, drawn to scale',
              style: text.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            identify
                ? 'A receiver has decoded L-STF, L-LTF and L-SIG. Walk its '
                      'questions to name the PPDU from the symbols that follow.'
                : 'Tap a block, or pick it in the list, to open its bits. '
                      'Filled blocks carry bits; outlined blocks are training '
                      'patterns.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Bar(model: model),
          const SizedBox(height: AppSpacing.sm),
          _Legend(masked: model.hidden),
          const SizedBox(height: AppSpacing.sm),
          _Summary(model: model),
          const SizedBox(height: AppSpacing.sm),
          PreambleBlockList(model: model),
          const SizedBox(height: AppSpacing.sm),
          if (identify) _Walk(model: model) else _Detail(model: model),
        ],
      ),
    );
  }
}

// ── Presenter arrangement ─────────────────────────────────────────────────

class _PresenterStage extends StatelessWidget {
  const _PresenterStage({required this.model});

  final PhyPreambleModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final bool identify = model.mode == PreambleMode.identify;
    final String who = model.hidden ? 'this PPDU' : model.type.shortLabel;
    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      header: true,
                      child: Text(
                        model.hidden
                            ? 'Mystery PPDU, drawn to scale'
                            : '${model.type.label}, drawn to scale',
                        style: text.titleLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      identify
                          ? 'Name the PPDU from the symbols after L-SIG.'
                          : 'Filled blocks carry bits; outlined ones train.',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: 'Preamble  ',
                            style: text.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text:
                                '${formatPreambleTenths(model.preambleTenths)} '
                                'µs',
                            style: scale
                                .headlineStyle(mono.outputMedium)
                                .copyWith(color: colors.textAccent),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      model.type == PpduType.nonHt && !model.hidden
                          ? 'the legacy 20 µs, nothing added'
                          : '20 legacy + '
                                '${formatPreambleTenths(model.addedTenths)} '
                                'added by $who',
                      style: mono.inlineCode.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Bar(model: model, presenting: true),
          const SizedBox(height: AppSpacing.xs),
          // While a bit table is open it needs the height, so the legend
          // steps aside (the bar keeps its colors and the ring); closing the
          // block brings it back.
          if (identify || model.selectedBlock?.table == null) ...<Widget>[
            _Legend(masked: model.hidden, compact: true),
            const SizedBox(height: AppSpacing.sm),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: box.maxWidth,
                  child: identify ? _Walk(model: model) : _Detail(model: model),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.model, this.presenting = false});

  final PhyPreambleModel model;

  /// Presenter stage: a taller bar with larger labels.
  final bool presenting;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final TextStyle style =
        (presenting ? text.labelLarge : text.labelSmall) ??
        const TextStyle(fontSize: AppTextSize.caption);
    final bool masked = model.hidden;
    final List<PreambleBlock> blocks = model.blocks;
    final String spoken = <String>[
      '${masked ? 'Mystery PPDU' : model.type.label} preamble, '
          '${formatPreambleTenths(model.preambleTenths)} microseconds',
      for (final PreambleBlock b in blocks)
        if (!b.isToScale)
          'then Data'
        else if (PreambleBarLayout.isMasked(b, masked))
          'hidden field ${formatPreambleTenths(b.tenths)} microseconds'
              '${b.modulations.isEmpty ? '' : ', ${b.modulations.map((SymbolModulation m) => m.label).join(' ')}'}'
        else
          '${b.name} ${formatPreambleTenths(b.tenths)} microseconds'
              '${b.modulations.isEmpty ? '' : ', ${b.modulations.map((SymbolModulation m) => m.label).join(' ')}'}',
    ].join('; ');

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final PreambleBarLayout layout = PreambleBarLayout.compute(
          blocks: blocks,
          width: c.maxWidth,
          labelStyle: style,
          textScaler: scaler,
          masked: masked,
          barHeight: presenting
              ? PreambleBarLayout.defaultBarHeight * scale.marker * 1.2
              : PreambleBarLayout.defaultBarHeight,
        );
        return Semantics(
          label: spoken,
          image: true,
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) {
                final int? i = layout.hitTest(d.localPosition);
                if (i != null) model.select(i);
              },
              child: CustomPaint(
                size: Size(c.maxWidth, layout.height),
                painter: PreambleBarPainter(
                  layout: layout,
                  colors: colors,
                  labelStyle: style,
                  textScaler: scaler,
                  selected: model.selected,
                  scale: scale,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.masked, this.compact = false});

  final bool masked;

  /// Presenter stage: shorter names and the BPSK sentence as one more item,
  /// so the legend takes as few lines as it can.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    PreambleBlockStyle st(BlockRole r, BlockForm f, {bool m = false}) =>
        preambleBlockStyle(
          PreambleBlock(
            name: '',
            shortName: '',
            role: r,
            form: f,
            count: 1,
            unitTenths: 0,
            durationNote: '',
            durationEvidence: const <Evidence>[],
            purpose: '',
          ),
          colors,
          masked: m,
        );
    final List<(PreambleBlockStyle, bool, String)> items =
        <(PreambleBlockStyle, bool, String)>[
          (
            st(BlockRole.legacy, BlockForm.signal),
            false,
            compact ? 'Legacy signal' : 'Legacy signal field (L-SIG)',
          ),
          (
            st(BlockRole.legacy, BlockForm.training),
            true,
            compact ? 'Legacy training' : 'Legacy training field',
          ),
          (
            st(BlockRole.added, BlockForm.signal),
            false,
            compact ? 'Added signal' : 'Signal field this PHY adds',
          ),
          (
            st(BlockRole.added, BlockForm.training),
            true,
            compact ? 'Added training' : 'Training field this PHY adds',
          ),
          if (masked)
            (
              st(BlockRole.added, BlockForm.signal, m: true),
              false,
              'Not named yet',
            ),
          (
            st(BlockRole.data, BlockForm.data),
            false,
            compact ? 'Data, not to scale' : 'Data (continues, not to scale)',
          ),
        ];
    final TextStyle? label = text.bodySmall?.copyWith(
      color: colors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final (PreambleBlockStyle s, bool training, String name)
                in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ExcludeSemantics(
                    child: CustomPaint(
                      size: const Size(AppSpacing.md, AppSpacing.sm),
                      painter: PreambleSwatchPainter(
                        style: s,
                        training: training,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(name, style: label),
                ],
              ),
            if (compact)
              Text(
                'B = BPSK, Q = QBPSK',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
          ],
        ),
        if (!compact) const SizedBox(height: AppSpacing.xs),
        if (!compact)
          Text(
            'Under each SIG symbol: BPSK, or QBPSK (the same two points turned '
            '90 degrees). B and Q when the symbol is narrow.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.model});

  final PhyPreambleModel model;

  @override
  Widget build(BuildContext context) {
    final String who = model.hidden ? 'this PPDU' : model.type.shortLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PpRow(
          label: 'Preamble, before the data',
          value: '${formatPreambleTenths(model.preambleTenths)} µs',
          emphasize: true,
        ),
        PpRow(label: 'Legacy part, in every PHY', value: '20 µs'),
        if (model.type != PpduType.nonHt || model.hidden)
          PpRow(
            label: 'Added by $who',
            value: '${formatPreambleTenths(model.addedTenths)} µs',
          ),
      ],
    );
  }
}

/// Every block as a focusable button: the keyboard and screen-reader route
/// to the same selection as tapping the bar. The presenter panel shows it on
/// its own, so it listens to the model itself.
class PreambleBlockList extends StatelessWidget {
  const PreambleBlockList({super.key, required this.model});

  final PhyPreambleModel model;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (BuildContext context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final List<PreambleBlock> blocks = model.blocks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PpSectionLabel('Blocks in order (µs)'),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: <Widget>[
            for (int i = 0; i < blocks.length; i++)
              _blockButton(context, i, blocks[i], colors, mono),
          ],
        ),
      ],
    );
  }

  Widget _blockButton(
    BuildContext context,
    int i,
    PreambleBlock b,
    AppColorScheme colors,
    AppMonoText mono,
  ) {
    final bool masked = PreambleBarLayout.isMasked(b, model.hidden);
    final bool on = model.selected == i;
    // The presenter panel is narrow and the bar's axis shows the durations,
    // so its chips carry the names only (the spoken label keeps both).
    final String dur = b.isToScale && !PresenterMode.isActive(context)
        ? ' ${formatPreambleTenths(b.tenths)}'
        : '';
    final String label = masked ? '?$dur' : '${b.name}$dur';
    final String spoken = masked
        ? 'Hidden field, ${formatPreambleTenths(b.tenths)} microseconds, '
              'named when the walk ends'
        : b.isToScale
        ? '${b.name}, ${formatPreambleTenths(b.tenths)} microseconds'
        : 'Data, the SERVICE field';
    return Semantics(
      selected: on,
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: masked ? null : () => model.select(i),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          backgroundColor: on ? colors.primary : null,
          foregroundColor: on ? colors.onPrimary : colors.textPrimary,
          disabledForegroundColor: colors.textDisabled,
          side: BorderSide(
            color: on
                ? colors.primary
                : masked
                ? colors.disabledFill
                : colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          ),
          textStyle: mono.inlineCode,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.model});

  final PhyPreambleModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PreambleBlock? b = model.selectedBlock;

    final bool presenting = PresenterMode.isActive(context);
    final Widget body;
    if (b == null) {
      body = Text(
        presenting
            ? 'Nothing open. Press the Right arrow, tap a block on the bar, '
                  'or pick one in the list beside the stage, to see its '
                  'duration, its modulation and, for a signal field, every '
                  'bit with its evidence tag.'
            : 'Nothing open. Tap a block on the bar, or pick one in the list, '
                  'to see its duration, its modulation and, for a signal '
                  'field, every bit with its evidence tag.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Presenter: name, duration and their evidence on one line.
          if (presenting)
            Row(
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xxs,
                    children: <Widget>[
                      Semantics(
                        header: true,
                        child: Text(
                          b.name,
                          style: text.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        b.isToScale
                            ? '${formatPreambleTenths(b.tenths)} µs · '
                                  '${b.durationNote}'
                            : b.durationNote,
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                        ),
                      ),
                      if (b.durationEvidence.isNotEmpty)
                        _TaggedLine(
                          label: 'Duration',
                          evidence: b.durationEvidence,
                        ),
                      if (b.countEvidence != null)
                        _TaggedLine(
                          label: 'Count ${b.count}',
                          evidence: <Evidence>[b.countEvidence!],
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: model.clearSelection,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(
                      AppSpacing.minTouchTarget,
                      AppSpacing.minTouchTarget,
                    ),
                  ),
                  child: Text('Close', semanticsLabel: 'Close ${b.name}'),
                ),
              ],
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      b.name,
                      style: text.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: model.clearSelection,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    minimumSize: const Size(
                      AppSpacing.minTouchTarget,
                      AppSpacing.minTouchTarget,
                    ),
                  ),
                  child: Text('Close', semanticsLabel: 'Close ${b.name}'),
                ),
              ],
            ),
            Text(
              b.isToScale
                  ? '${formatPreambleTenths(b.tenths)} µs · ${b.durationNote}'
                  : b.durationNote,
              style: mono.inlineCode.copyWith(color: colors.textAccent),
            ),
            if (b.durationEvidence.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              _TaggedLine(label: 'Duration', evidence: b.durationEvidence),
            ],
            if (b.countEvidence != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              _TaggedLine(
                label: 'Count ${b.count}',
                evidence: <Evidence>[b.countEvidence!],
              ),
            ],
          ],
          if (b.modulationNote != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              b.modulationNote!,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            b.purpose,
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          if (b.table != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            // The presenter panel folds the key under Sources.
            if (!presenting) ...<Widget>[
              const EvidenceKey(),
              const SizedBox(height: AppSpacing.xs),
            ],
            BitTableView(table: b.table!),
          ],
        ],
      );
    }
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: b == null ? colors.border : colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          ),
        ),
        child: body,
      ),
    );
  }
}

class _TaggedLine extends StatelessWidget {
  const _TaggedLine({required this.label, required this.evidence});

  final String label;
  final List<Evidence> evidence;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          for (final Evidence e in evidence) EvidenceChip(e),
        ],
      ),
    );
  }
}

class _Walk extends StatelessWidget {
  const _Walk({required this.model});

  final PhyPreambleModel model;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final Classification c = model.classification;
    final int shown = model.stepsShown;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const PpSectionLabel('The receiver\'s questions'),
            const SizedBox(height: AppSpacing.xs),
            if (shown == 0)
              Text(
                'No question asked yet. Press Next step to ask the first.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            for (int i = 0; i < shown; i++)
              _StepTile(index: i, step: c.steps[i]),
            if (model.walkDone) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Verdict: ${c.result.label}',
                style: text.titleMedium?.copyWith(
                  color: colors.textAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'The PPDU was ${model.type.label}.'
                '${model.type.isEht ? ' The tree stops at EHT; U-SIG-2 PPDU Type tells MU from TB.' : ''}',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.index, required this.step});

  final int index;
  final DecisionStep step;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${index + 1}. ${step.question}',
              style: text.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${step.answer} ${step.conclusion}',
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            EvidenceChip(step.evidence),
          ],
        ),
      ),
    );
  }
}
