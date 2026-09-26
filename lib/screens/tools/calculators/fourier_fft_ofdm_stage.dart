// FourierOfdmStage: mode 4 of the Wi-Fi Lab "Fourier and FFT" tool
// (fourier-fft), OFDM is an inverse FFT. Plots only; it reads
// FourierLabModel.ofdm and holds no inputs.
//
//   1. s(t), I and Q, from the start of the cyclic prefix. With "same time
//      scale" on, the axis is 16 us in legacy and HE alike, so the HE symbol
//      visibly lasts 4x longer.
//   2. Each subcarrier's sinc against frequency offset from the channel
//      center. The axis is the same in legacy and HE: the channel center never
//      moves; in HE the subcarriers sit 4x closer together.
//   3. The constellation: sent points and what the receiver's FFT got back.
//
// Lime marks the measured quantity (I, the highlighted sinc, the sent
// points). Everything else is neutral: the subcarriers are told apart by
// position and by the highlight, not by hue.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../services/wifi_lab/fourier_ofdm.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_ofdm_state.dart';
import 'fourier_fft_painters.dart';
import 'fourier_fft_part2_painters.dart';
import 'fourier_fft_parts.dart';
import 'fourier_fft_stage.dart';

/// Longest symbol either numerology makes: 12.8 us plus a 3.2 us GI.
const double kOfdmCommonAxisSeconds = 16e-6;

/// Half-width of the spectrum axis around the channel center.
double ofdmHalfSpanHz(OfdmView view) =>
    view == OfdmView.teaching ? 3.125e6 : 12e6;

String fmtK(int k) => k > 0 ? '+$k' : '$k';

class FourierOfdmStage extends StatelessWidget {
  const FourierOfdmStage({
    super.key,
    required this.model,
    this.plotHeight = 176,
  });

  final FourierLabModel model;
  final double plotHeight;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierOfdmState o = model.ofdm;
    final FourierPlotStyle style = fourierPlotStyle(context);
    final OfdmSymbol s = o.symbol;
    final int count = s.points.length;
    final int? h = o.highlight;
    final double axis = o.sameTimeScale
        ? kOfdmCommonAxisSeconds
        : s.totalSeconds;
    final double halfSpan = ofdmHalfSpanHz(o.view);
    // Neutral shade behind the cyclic prefix, strong enough to read on the
    // plot surface in both themes.
    final Color cpFill = colors.borderStrong.withValues(alpha: 0.35);

    final String timeSemantic = count == 0
        ? 'OFDM symbol: every subcarrier is off, so the signal is flat.'
        : 'OFDM symbol from $count subcarrier${count == 1 ? '' : 's'}: a '
              '${fmtTime(s.guardSeconds)} cyclic prefix copied from the end, '
              'then the ${fmtTime(s.usefulSeconds)} useful part, '
              '${fmtTime(s.totalSeconds)} in all.';
    final String specSemantic = count == 0
        ? 'Subcarrier spectrum: nothing is on.'
        : 'Spectrum of $count subcarriers, ${fmtHz(s.spacingHz)} apart '
              'around the channel center. Highlighted subcarrier '
              '${fmtK(h!)}: its sinc is zero at every other subcarrier '
              'center.';

    if (PresenterMode.isActive(context)) {
      return _presenter(
        context,
        colors: colors,
        o: o,
        style: style,
        s: s,
        count: count,
        h: h,
        axis: axis,
        halfSpan: halfSpan,
        cpFill: cpFill,
        timeSemantic: timeSemantic,
        specSemantic: specSemantic,
      );
    }
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabSectionLabel(
            'Time: one symbol, ${fmtTime(s.totalSeconds)} '
            '(${o.numerology.shortLabel}, N = ${s.n})',
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final bool dots = OfdmTimePainter.dotsFit(
                s,
                axis,
                c.maxWidth -
                    2 * AppSpacing.xs -
                    OfdmTimePainter.horizontalMargins,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FourierPlot(
                    semantic: timeSemantic,
                    height: plotHeight,
                    painter: OfdmTimePainter(
                      symbol: s,
                      axisSeconds: axis,
                      style: style,
                      revision: model.revision,
                      cpFill: cpFill,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  LabLegend(
                    items: <(Widget, String)>[
                      (labLineSample(colors.textAccent, 2), 'I (real part)'),
                      (
                        labLineSample(style.component, 1.2),
                        'Q (imaginary part)',
                      ),
                      (
                        Container(width: 14, height: 10, color: cpFill),
                        'Cyclic prefix',
                      ),
                      if (dots)
                        (labDot(colors.textAccent, 3), 'IFFT output samples'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  LabCaption(
                    'The inverse FFT turns the $count constellation point'
                    '${count == 1 ? '' : 's'} into ${s.n} time samples. '
                    '${dots ? 'The dots sit on the curve because they are samples of it. ' : 'At this time scale they sit too close to mark; turn off Same time scale to see them. '}'
                    'The last ${fmtTime(s.guardSeconds)} (dashed) is copied '
                    'to the front as the cyclic prefix.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          LabSectionLabel(
            'Frequency: each subcarrier, ${fmtHz(s.spacingHz)} apart',
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final OfdmSpectrumPainter painter = OfdmSpectrumPainter(
                symbol: s,
                highlight: h,
                halfSpanHz: halfSpan,
                style: style,
                revision: model.revision,
              );
              // Plot width inside the frame's padding and the painter's
              // margins, to match its own density rule.
              final bool every =
                  count == 0 ||
                  painter.drawsEverySinc(c.maxWidth - 2 * AppSpacing.xs - 36);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  FourierPlot(
                    semantic: specSemantic,
                    height: plotHeight,
                    painter: painter,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  LabLegend(
                    items: <(Widget, String)>[
                      (
                        labLineSample(colors.textAccent, 2.5),
                        h == null
                            ? 'Highlighted subcarrier'
                            : 'Subcarrier ${fmtK(h)}',
                      ),
                      if (every)
                        (labLineSample(style.component, 1.2), 'The others'),
                      if (every)
                        (
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.textAccent,
                                width: 1.5,
                              ),
                            ),
                          ),
                          'Its zeros',
                        ),
                      (
                        Container(width: 2, height: 10, color: style.marker),
                        '0 MHz: channel center',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  LabCaption(
                    '${every ? '' : 'At this width the $count sincs are too '
                              'close to draw one by one, so only the '
                              'highlighted one is drawn; the teaching view '
                              'shows each one and its zeros. '}'
                    'Each subcarrier is a sinc, drawn here with its phase '
                    'removed. Over the receiver\'s ${fmtTime(s.usefulSeconds)} '
                    'FFT window every sinc is exactly zero at every other '
                    'subcarrier\'s center, so the subcarriers overlap and '
                    'still do not interfere. That is orthogonality.',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          const LabSectionLabel('Constellation: sent and recovered'),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: SizedBox(
              width: plotHeight + 24,
              child: FourierPlot(
                semantic:
                    '${o.modulation.label} constellation with $count sent '
                    'point${count == 1 ? '' : 's'}. The receiver\'s FFT '
                    'puts every recovered point on its sent point.',
                height: plotHeight + 24,
                painter: OfdmConstellationPainter(
                  modulation: o.modulation,
                  sent: <ConstellationPoint>[
                    for (final int k in s.indices) s.points[k]!,
                  ],
                  recovered: o.recovered,
                  style: style,
                  revision: model.revision,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabLegend(
            items: <(Widget, String)>[
              (
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textAccent, width: 2),
                  ),
                ),
                'Sent',
              ),
              (labDot(style.marker, 2.5), 'Recovered by the FFT'),
            ],
          ),
          if (count == 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Every subcarrier is off, so there is no signal. Turn one '
                  'on in Subcarriers below.',
            ),
          ],
        ],
      ),
    );
  }

  /// Presenter: spacing and symbol times lead; the symbol runs full width,
  /// the subcarriers' sincs and the constellation share the row below. The
  /// long captions stay on the phone.
  Widget _presenter(
    BuildContext context, {
    required AppColorScheme colors,
    required FourierOfdmState o,
    required FourierPlotStyle style,
    required OfdmSymbol s,
    required int count,
    required int? h,
    required double axis,
    required double halfSpan,
    required Color cpFill,
    required String timeSemantic,
    required String specSemantic,
  }) {
    final OfdmSpectrumPainter spectrum = OfdmSpectrumPainter(
      symbol: s,
      highlight: h,
      halfSpanHz: halfSpan,
      style: style,
      revision: model.revision,
    );
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LabStatRow(
            children: <Widget>[
              LabStat(
                label: 'Subcarrier spacing',
                value: fmtHz(s.spacingHz),
                accent: true,
              ),
              LabStat(
                label: 'Useful symbol, 1 / spacing',
                value: fmtTime(s.usefulSeconds),
              ),
              LabStat(
                label: 'With the ${fmtTime(s.guardSeconds)} guard',
                value: fmtTime(s.totalSeconds),
              ),
              LabStat(
                label: '${o.numerology.shortLabel}, IFFT size',
                value: 'N = ${s.n}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              LabSectionLabel('Time: one symbol, $count on'),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: LabLegend(
                  items: <(Widget, String)>[
                    (labLineSample(colors.textAccent, 2), 'I'),
                    (labLineSample(style.component, 1.2), 'Q'),
                    (
                      Container(width: 14, height: 10, color: cpFill),
                      'Cyclic prefix',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            flex: 4,
            child: FourierPlot(
              semantic: timeSemantic,
              height: double.infinity,
              painter: OfdmTimePainter(
                symbol: s,
                axisSeconds: axis,
                style: style,
                revision: model.revision,
                cpFill: cpFill,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            flex: 5,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                // The constellation is a square as tall as the row allows
                // under its label, never more than a third of the width.
                final double labelRoom =
                    MediaQuery.textScalerOf(
                          context,
                        ).scale(AppTextSize.caption) *
                        1.6 +
                    AppSpacing.xs;
                final double side = math.min(
                  box.maxHeight - labelRoom,
                  box.maxWidth / 3,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              LabSectionLabel(
                                'Frequency: ${fmtHz(s.spacingHz)} apart',
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: LabLegend(
                                  items: <(Widget, String)>[
                                    (
                                      labLineSample(colors.textAccent, 2.5),
                                      h == null
                                          ? 'Highlighted'
                                          : 'Subcarrier ${fmtK(h)}',
                                    ),
                                    (
                                      labLineSample(style.component, 1.2),
                                      'The others',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Expanded(
                            child: FourierPlot(
                              semantic: specSemantic,
                              height: double.infinity,
                              painter: spectrum,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: math.max(0, side),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const LabSectionLabel('Sent and recovered'),
                          const SizedBox(height: AppSpacing.xs),
                          FourierPlot(
                            semantic:
                                '${o.modulation.label} constellation with '
                                '$count sent point${count == 1 ? '' : 's'}. '
                                'The receiver\'s FFT puts every recovered '
                                'point on its sent point.',
                            height: math.max(0, side),
                            painter: OfdmConstellationPainter(
                              modulation: o.modulation,
                              sent: <ConstellationPoint>[
                                for (final int k in s.indices) s.points[k]!,
                              ],
                              recovered: o.recovered,
                              style: style,
                              revision: model.revision,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (count == 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabNote(
              icon: Icons.info_outline,
              message:
                  'Every subcarrier is off, so there is no signal. Turn one '
                  'on beside the stage.',
            ),
          ],
        ],
      ),
    );
  }
}
