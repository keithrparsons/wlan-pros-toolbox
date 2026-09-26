// SixGhzPsdStage: the plot half of the Wi-Fi Lab 6 GHz Power and PSD tool.
//
// The stage is the chart and everything that belongs to reading it: the view
// toggle (EIRP / SNR / Spectrum), the plot, its legend, and the width cursor
// (tap a column on the chart; a slider under it for keyboard and
// screen-reader users). It takes a SixGhzPsdModel and knows nothing about the
// controls, so a screen can place it above the controls (phone), beside them
// (desktop) or full screen beside them (the presenter layout).
//
// PRESENTER (lib/widgets/presenter/): inside a PresenterLayout the plot
// fills the stage's height and each shown class's EIRP and SNR at the
// selected width stand beside it in headline type, with the one-line reason
// (PSD-limited: SNR holds; cap-limited: SNR falls). Strokes, markers and
// painted labels follow PresenterMode.scaleOf.
//
// THEME: context.colors (dark §8 / light §8.20) plus PsdPalette, one hue per
// power class under GL-003 §8.15.2. Every class also has its own stroke,
// marker and label, so meaning never rests on color alone.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/six_ghz_psd_math.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'fspl_simulator_chart.dart';
import 'six_ghz_psd_chart.dart';
import 'six_ghz_psd_model.dart';
import 'six_ghz_psd_parts.dart';

class SixGhzPsdStage extends StatelessWidget {
  const SixGhzPsdStage({
    super.key,
    required this.model,
    required this.chartHeight,
  });

  final SixGhzPsdModel model;

  /// Height of the plot itself. The toggles, legend and width slider add to
  /// it. Ignored in presenter mode, where the plot fills the stage.
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PowerClass? focus = model.focus;
    final bool spectrum = model.view == PsdView.spectrum;
    final bool presenter = PresenterMode.isActive(context);

    final Widget chart = Semantics(
      label: _semantics(focus),
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: ColoredBox(
          color: colors.surface2,
          child: spectrum ? _spectrum(context, focus) : _widthChart(context),
        ),
      ),
    );
    final Widget card = PsdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<PsdView>(
            semanticLabel: 'Chart shows',
            value: model.view,
            expand: true,
            items: <AppToggleItem<PsdView>>[
              for (final PsdView v in PsdView.values) (v, v.label),
            ],
            onChanged: model.setView,
          ),
          if (spectrum &&
              focus != null &&
              model.classes.length > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            AppSelect<PowerClass>(
              value: focus,
              semanticLabel: 'Class drawn in the spectrum view',
              items: <AppSelectItem<PowerClass>>[
                for (final PowerClass c in model.classes) (c, c.label),
              ],
              onChanged: model.setFocus,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            _caption(focus),
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (presenter)
            Expanded(child: chart)
          else
            SizedBox(height: chartHeight, child: chart),
          const SizedBox(height: AppSpacing.xs),
          if (!spectrum) _legend(context) else _spectrumLegend(context),
          const SizedBox(height: AppSpacing.xxs),
          _widthSlider(context),
        ],
      ),
    );
    if (!presenter) return card;

    // Presenter: the plot takes the height; the per-class numbers stand
    // beside it.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double side = (box.maxWidth * 0.37).clamp(330.0, 480.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: card),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: side,
              // Many classes on at once shrink as one piece rather than clip.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(width: side, child: _headline(context)),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Presenter stage: each shown class's EIRP and SNR at the selected width
  /// in headline type, with why it rises or holds.
  Widget _headline(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final PresenterScale scale = PresenterMode.scaleOf(context);
    final List<PowerClass> cs = model.classes;
    final String Function(double, [int]) n = PsdFormat.n;
    final TextStyle big = scale
        .headlineStyle(mono.outputMedium)
        .copyWith(color: colors.textAccent);

    Widget number(String label, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: text.labelSmall?.copyWith(color: colors.textTertiary),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(v, style: big),
        ),
      ],
    );

    String tag(PsdLimit l) => switch (l) {
      PsdLimit.psd => 'PSD',
      PsdLimit.cap => 'cap',
      PsdLimit.apRelative => 'AP -6',
      PsdLimit.authorized => 'grant',
    };

    String why(PsdClassReading r) => switch (r.limit) {
      PsdLimit.psd => 'PSD-limited: wider adds 3 dB, SNR holds.',
      PsdLimit.cap => 'Cap-limited: SNR falls 3 dB per doubling.',
      PsdLimit.apRelative => 'Held 6 dB below its AP: SNR falls.',
      PsdLimit.authorized => 'Held to its grant: SNR falls.',
    };

    return PsdCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PsdSectionLabel(
              'At ${model.widthMHz} MHz, ${PsdFormat.dist(model.distanceM)}'
              '${model.extraLossDb > 0 ? ' + ${n(model.extraLossDb, 0)} dB' : ''}',
            ),
            if (cs.isEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              const PsdNote(
                Icons.visibility_off_outlined,
                'No class is on. Turn one on to read its EIRP and SNR.',
              ),
            ],
            // More than three classes: one row each, so they stay legible.
            if (cs.length > 3) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Table(
                columnWidths: const <int, TableColumnWidth>{
                  0: FlexColumnWidth(),
                  1: IntrinsicColumnWidth(),
                  2: IntrinsicColumnWidth(),
                  3: IntrinsicColumnWidth(),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: <TableRow>[
                  TableRow(
                    children: <Widget>[
                      for (final String h in <String>[
                        'Class',
                        'EIRP',
                        'SNR',
                        'Limit',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.xs,
                            bottom: AppSpacing.xxs,
                          ),
                          child: Text(
                            h,
                            textAlign: h == 'Class'
                                ? TextAlign.left
                                : TextAlign.right,
                            style: text.labelSmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final PowerClass c in cs)
                    _tableRow(context, model.reading(c), tag),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'EIRP in dBm, SNR in dB. PSD: wider adds 3 dB, SNR holds. '
                'Any other limit: SNR falls 3 dB per doubling.',
                style: text.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
            if (cs.length <= 3)
              for (final PowerClass c in cs) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 28 * scale.marker,
                      height: 14 * scale.marker,
                      child: ExcludeSemantics(
                        child: PsdClassSample(powerClass: c),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        c.shortLabel,
                        style: text.titleSmall?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Builder(
                  builder: (BuildContext context) {
                    final PsdClassReading r = model.reading(c);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: number('EIRP', '${n(r.eirpDbm)} dBm'),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: number('SNR', '${n(r.snrDb)} dB')),
                          ],
                        ),
                        Text(
                          why(r),
                          style: text.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
          ],
        ),
      ),
    );
  }

  String _caption(PowerClass? focus) {
    switch (model.view) {
      case PsdView.eirp:
        return 'EIRP (dBm) vs channel width';
      case PsdView.snr:
        return 'SNR (dB) at ${PsdFormat.dist(model.distanceM)} vs channel '
            'width';
      case PsdView.spectrum:
        return focus == null
            ? 'PSD (dBm/MHz) across one channel'
            : '${focus.shortLabel}: PSD (dBm/MHz) vs MHz from the channel '
                  'center';
    }
  }

  String _semantics(PowerClass? focus) {
    final List<PowerClass> cs = model.classes;
    if (cs.isEmpty) {
      return 'No class is on. Turn one on to draw it.';
    }
    final int w = model.widthMHz;
    if (model.view == PsdView.spectrum && focus != null) {
      final PsdClassReading r = model.reading(focus);
      return '${focus.label} at $w MHz: a flat block '
          '${PsdFormat.n(r.radiatedPsd)} dBm per MHz high and $w MHz wide, '
          'total ${PsdFormat.n(r.eirpDbm)} dBm. PSD limit '
          '${PsdFormat.n(focus.psdDbmPerMHz, 0)} dBm per MHz.';
    }
    final String what = model.view == PsdView.snr ? 'SNR' : 'EIRP';
    final String lines = cs
        .map(
          (PowerClass c) =>
              '${c.shortLabel} ${SixGhzPsdMath.widthsMHz.map((int x) => PsdFormat.n(model.y(c, x))).join(', ')}',
        )
        .join('; ');
    return '$what in ${model.unit} at 20, 40, 80, 160 and 320 MHz: $lines. '
        'Selected width $w MHz.';
  }

  TableRow _tableRow(
    BuildContext context,
    PsdClassReading r,
    String Function(PsdLimit) tag,
  ) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double k = PresenterMode.scaleOf(context).marker;
    final String Function(double, [int]) n = PsdFormat.n;
    Widget cell(String v, {bool accent = false}) => Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, top: AppSpacing.xxs),
      child: Text(
        v,
        textAlign: TextAlign.right,
        style: mono.inlineCode.copyWith(
          color: accent ? colors.textAccent : colors.textSecondary,
          fontWeight: accent ? FontWeight.w600 : null,
        ),
      ),
    );
    return TableRow(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 22 * k,
                height: 14 * k,
                child: ExcludeSemantics(
                  child: PsdClassSample(powerClass: r.powerClass),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  r.powerClass.shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        cell(n(r.eirpDbm), accent: true),
        cell(n(r.snrDb), accent: true),
        cell(tag(r.limit)),
      ],
    );
  }

  PsdChartStyle _style(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Painted text does not see MediaQuery's text scale; the presenter scale
    // reaches it here (1.0 outside presenter mode).
    final PresenterScale scale = PresenterMode.scaleOf(context);
    TextStyle up(TextStyle t) =>
        t.copyWith(fontSize: scale.paintFont(t.fontSize ?? AppTextSize.body));
    return PsdChartStyle(
      scale: scale,
      ghost: colors.textTertiary,
      grid: colors.border,
      axis: colors.borderStrong,
      limit: colors.textSecondary,
      highlight: colors.surface3,
      pill: colors.textPrimary,
      surface: colors.surface2,
      axisLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
        ),
      ),
      limitLabel: up(text.labelSmall!.copyWith(color: colors.textSecondary)),
      pillLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.surface2,
          fontWeight: FontWeight.w500,
        ),
      ),
      blockLabel: up(
        mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: colors.textPrimary,
        ),
      ),
      emptyLabel: up(text.bodyMedium!.copyWith(color: colors.textSecondary)),
    );
  }

  Widget _widthChart(BuildContext context) {
    final ({double min, double max, double step}) yr = model.yRange();
    final List<PsdSeries> series = <PsdSeries>[
      for (final PowerClass c in model.classes)
        PsdSeries(
          values: <double>[
            for (final int w in SixGhzPsdMath.widthsMHz) model.y(c, w),
          ],
          stroke: kPsdClassLook[c]!.$1,
          marker: kPsdClassLook[c]!.$2,
          color: PsdPalette.of(c, context.colors),
        ),
    ];
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size size = Size(c.maxWidth, c.maxHeight);
        final PsdWidthGeometry g = PsdWidthGeometry(
          size: size,
          columns: SixGhzPsdMath.widthsMHz.length,
          yMin: yr.min,
          yMax: yr.max,
          padScale: PresenterMode.scaleOf(context).text,
        );
        void pick(Offset local) {
          if (model.classes.isEmpty) return;
          model.setWidthIndex(g.columnAt(local.dx));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => pick(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              pick(d.localPosition),
          child: CustomPaint(
            size: size,
            painter: PsdWidthChartPainter(
              columnLabels: <String>[
                for (final int w in SixGhzPsdMath.widthsMHz) '$w',
              ],
              selectedColumn: model.widthIndex,
              yMin: yr.min,
              yMax: yr.max,
              yStep: yr.step,
              series: series,
              style: _style(context),
              revision: model.revision,
              emptyMessage: model.classes.isEmpty
                  ? 'Turn on a class to draw its line.'
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _spectrum(BuildContext context, PowerClass? focus) {
    if (focus == null) {
      return CustomPaint(
        size: Size.infinite,
        painter: PsdSpectrumPainter(
          selected: null,
          blockColor: context.colors.textAccent,
          others: const <PsdBlock>[],
          psdLimit: 0,
          psdLimitLabel: '',
          blockLabel: '',
          yMin: -10,
          yMax: 30,
          yStep: 10,
          style: _style(context),
          revision: model.revision,
          emptyMessage: 'Turn on a class to draw its spectrum.',
        ),
      );
    }
    final PsdClassReading r = model.reading(focus);
    final List<PsdBlock> others = <PsdBlock>[
      for (final int w in SixGhzPsdMath.widthsMHz)
        if (w != model.widthMHz)
          PsdBlock(
            widthMHz: w,
            psdDbmPerMHz: SixGhzPsdMath.radiatedPsdDbmPerMHz(
              model.eirp(focus, w).eirpDbm,
              w,
            ),
          ),
    ];
    // y range: from 10 dB under the lowest block to 8 dB over the limit (room
    // for the limit label), on a 5 dB grid.
    double lo = r.radiatedPsd;
    for (final PsdBlock b in others) {
      if (b.psdDbmPerMHz < lo) lo = b.psdDbmPerMHz;
    }
    final double yMin = ((lo - 10) / 5).floor() * 5.0;
    final double yMax = ((focus.psdDbmPerMHz + 8) / 5).ceil() * 5.0;
    final String Function(double, [int]) n = PsdFormat.n;
    return CustomPaint(
      size: Size.infinite,
      painter: PsdSpectrumPainter(
        selected: PsdBlock(
          widthMHz: model.widthMHz,
          psdDbmPerMHz: r.radiatedPsd,
        ),
        blockColor: PsdPalette.of(focus, context.colors),
        others: others,
        psdLimit: focus.psdDbmPerMHz,
        psdLimitLabel: 'PSD limit ${n(focus.psdDbmPerMHz, 0)} dBm/MHz',
        blockLabel:
            '${n(r.radiatedPsd)} dBm/MHz x ${model.widthMHz} MHz\n'
            '= ${n(r.eirpDbm)} dBm',
        yMin: yMin,
        yMax: yMax,
        yStep: 5,
        style: _style(context),
        revision: model.revision,
      ),
    );
  }

  Widget _legendItem(BuildContext context, Widget swatch, String label) {
    final AppColorScheme colors = context.colors;
    final double k = PresenterMode.scaleOf(context).marker;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 28 * k, height: 14 * k, child: swatch),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context) {
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final PowerClass c in model.classes)
            _legendItem(context, PsdClassSample(powerClass: c), c.shortLabel),
        ],
      ),
    );
  }

  Widget _spectrumLegend(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double k = PresenterMode.scaleOf(context).marker;
    if (model.focus == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          _legendItem(
            context,
            CustomPaint(
              painter: FsplStrokeSamplePainter(
                stroke: CurveStroke.solid,
                marker: null,
                color: PsdPalette.of(model.focus!, colors),
                surface: colors.surface1,
                scale: k,
              ),
            ),
            '${model.widthMHz} MHz channel',
          ),
          _legendItem(
            context,
            CustomPaint(
              painter: FsplStrokeSamplePainter(
                stroke: CurveStroke.dashed,
                marker: null,
                color: colors.textTertiary,
                surface: colors.surface1,
                scale: k,
                model: true,
              ),
            ),
            'Other widths',
          ),
          _legendItem(
            context,
            CustomPaint(
              painter: FsplStrokeSamplePainter(
                stroke: CurveStroke.dashed,
                marker: null,
                color: colors.textSecondary,
                surface: colors.surface1,
                scale: k,
                model: true,
              ),
            ),
            'PSD limit',
          ),
        ],
      ),
    );
  }

  Widget _widthSlider(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'Width',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: model.widthIndex.toDouble(),
            min: 0,
            max: SixGhzPsdMath.widthsMHz.length - 1.0,
            divisions: SixGhzPsdMath.widthsMHz.length - 1,
            onChanged: model.classes.isEmpty
                ? null
                : (double v) => model.setWidthIndex(v.round()),
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: '${model.widthMHz} MHz',
            semanticFormatterCallback: (double v) =>
                'Channel width ${SixGhzPsdMath.widthsMHz[v.round().clamp(0, SixGhzPsdMath.widthsMHz.length - 1)]} MHz',
          ),
        ),
        ExcludeSemantics(
          child: SizedBox(
            width: PresenterMode.isActive(context)
                ? 88 * PresenterMode.scaleOf(context).text
                : 64,
            child: Text(
              '${model.widthMHz} MHz',
              textAlign: TextAlign.right,
              style:
                  (Theme.of(context).extension<AppMonoText>() ??
                          AppMonoText.defaults())
                      .inlineCode
                      .copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
