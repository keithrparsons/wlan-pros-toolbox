// FourierOfdmControls: mode 4 of the Wi-Fi Lab "Fourier and FFT" tool
// (fourier-fft), OFDM is an inverse FFT. Inputs and readouts only; it writes
// FourierLabModel.ofdm and never draws a plot.

import 'package:flutter/material.dart';

import '../../../services/rf/modulation_math.dart';
import '../../../services/wifi_lab/fourier_ofdm.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'fourier_fft_model.dart';
import 'fourier_fft_ofdm_stage.dart';
import 'fourier_fft_ofdm_state.dart';
import 'fourier_fft_parts.dart';

class FourierOfdmControls extends StatelessWidget {
  const FourierOfdmControls({super.key, required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    const Widget gap = SizedBox(height: AppSpacing.sm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SubcarriersCard(model: model),
        gap,
        _NumerologyCard(model: model),
        gap,
        _ReceiverCard(model: model),
        gap,
        const OfdmReceiverIsFftCard(),
      ],
    );
  }
}

class _SubcarriersCard extends StatelessWidget {
  const _SubcarriersCard({required this.model});
  final FourierLabModel model;

  /// Slider position to a list index, clamped.
  static int _at(double v, List<int> on) => v.round().clamp(0, on.length - 1);

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierOfdmState o = model.ofdm;
    final bool teaching = o.view == OfdmView.teaching;
    final List<int> on = o.activeIndices;
    final int? h = o.highlight;

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<OfdmView>(
            label: 'View',
            value: o.view,
            expand: true,
            items: const <AppToggleItem<OfdmView>>[
              (OfdmView.teaching, 'Teaching (16)'),
              (OfdmView.real, 'Real Wi-Fi'),
            ],
            onChanged: o.setView,
          ),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(
            teaching
                ? 'A 16-point IFFT, subcarriers -8 to +7. Tap a subcarrier to '
                      'turn it on or off.'
                : 'One 20 MHz channel: ${o.numerology == OfdmNumerology.legacy ? '52 subcarriers (48 data + 4 pilot) in a 64-point IFFT' : 'the 242-tone RU in a 256-point IFFT'}, '
                      'all on.',
          ),
          if (teaching) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            LabSectionLabel('Subcarriers on (${on.length} of 16)'),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                for (final int k in OfdmMath.teachingIndices)
                  FilterChip(
                    label: Text(
                      fmtK(k),
                      style: labMono(context).inlineCode.copyWith(
                        color: o.isOn(k)
                            ? colors.onPrimary
                            : colors.textPrimary,
                      ),
                    ),
                    selected: o.isOn(k),
                    showCheckmark: false,
                    selectedColor: colors.primary,
                    backgroundColor: colors.surface2,
                    side: BorderSide(color: colors.borderStrong),
                    tooltip:
                        'Subcarrier ${fmtK(k)}, ${o.isOn(k) ? 'on' : 'off'}'
                        '${k == 0 ? '. Real Wi-Fi leaves the center (DC) '
                                  'subcarrier empty' : ''}',
                    onSelected: (_) => o.toggle(k),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: LabOutlinedAction(
                    label: 'All on',
                    icon: Icons.select_all_rounded,
                    semantic: on.length == 16
                        ? 'All on, unavailable: every subcarrier is on'
                        : 'Turn every subcarrier on',
                    enabled: on.length < 16,
                    onTap: o.allOn,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: LabOutlinedAction(
                    label: 'All off',
                    icon: Icons.deselect_rounded,
                    semantic: on.isEmpty
                        ? 'All off, unavailable: nothing is on'
                        : 'Turn every subcarrier off',
                    enabled: on.isNotEmpty,
                    onTap: o.allOff,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Modulation on every subcarrier',
            semanticLabel: 'Modulation',
            field: AppSelect<Modulation>(
              value: o.modulation,
              semanticLabel: 'Modulation',
              items: <AppSelectItem<Modulation>>[
                for (final Modulation m in kOfdmModulations) (m, m.label),
              ],
              onChanged: o.setModulation,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: o.newData,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('New data'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.textPrimary,
              side: BorderSide(color: colors.borderStrong, width: 1.5),
              minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabCaption(
            'Picks a new random point for each subcarrier, from the same '
            'constellations the Modulation Simulator draws.',
          ),
          if (on.length > 1 && h != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Text(
                  'Highlighted subcarrier',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
                const Spacer(),
                Text(
                  fmtK(h),
                  style: labMono(
                    context,
                  ).inlineCode.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            Slider(
              // A new slider per list, so no callback outlives its list.
              key: ValueKey<String>('${o.view.name}-${on.length}'),
              value: on.indexOf(h).toDouble(),
              min: 0,
              max: (on.length - 1).toDouble(),
              divisions: on.length - 1,
              onChanged: (double v) => o.setHighlight(on[_at(v, on)]),
              activeColor: colors.primary,
              inactiveColor: colors.borderStrong,
              semanticFormatterCallback: (double v) =>
                  'Highlighted subcarrier ${fmtK(on[_at(v, on)])}',
            ),
          ],
          if (on.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabNote(
              icon: Icons.info_outline,
              message: 'Every subcarrier is off. Turn one on to see a symbol.',
            ),
          ],
        ],
      ),
    );
  }
}

class _NumerologyCard extends StatelessWidget {
  const _NumerologyCard({required this.model});
  final FourierLabModel model;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final FourierOfdmState o = model.ofdm;
    final OfdmNumerology nu = o.numerology;
    final OfdmSymbol s = o.symbol;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppToggle<OfdmNumerology>(
            label: 'Numerology',
            value: nu,
            expand: true,
            items: <AppToggleItem<OfdmNumerology>>[
              for (final OfdmNumerology v in OfdmNumerology.values)
                (v, v.shortLabel),
            ],
            onChanged: o.setNumerology,
          ),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(nu.label),
          const SizedBox(height: AppSpacing.sm),
          if (nu.guardOptionsSeconds.length > 1)
            LabeledField(
              label: 'Guard interval',
              semanticLabel: 'Guard interval',
              field: AppSelect<double>(
                value: o.guardSeconds,
                semanticLabel: 'Guard interval',
                items: <AppSelectItem<double>>[
                  for (final double g in nu.guardOptionsSeconds)
                    (g, fmtTime(g)),
                ],
                onChanged: o.setGuard,
              ),
            ),
          if (nu.guardOptionsSeconds.length > 1)
            const SizedBox(height: AppSpacing.sm),
          LabReadoutRow(
            label: 'Subcarrier spacing',
            value: fmtHz(nu.spacingHz),
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'Useful symbol',
            value: '${fmtTime(nu.usefulSeconds)} (1 / spacing)',
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'Guard interval',
            value: fmtTime(s.guardSeconds),
          ),
          LabReadoutRow(label: 'Total symbol', value: fmtTime(s.totalSeconds)),
          LabReadoutRow(label: 'IFFT size N', value: '${s.n}'),
          LabReadoutRow(
            label: 'Sample rate',
            value: '${fmtHz(s.sampleRateHz)} (N x spacing)',
          ),
          LabReadoutRow(
            label: 'Cyclic prefix',
            value: '${s.cpSamples} sample${s.cpSamples == 1 ? '' : 's'}',
          ),
          const SizedBox(height: AppSpacing.xs),
          MergeSemantics(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Same time scale for legacy and HE',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Switch(value: o.sameTimeScale, onChanged: o.setSameTimeScale),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const LabNote(
            icon: Icons.info_outline,
            message:
                'HE puts the subcarriers 4 times closer together (78.125 kHz '
                'instead of 312.5 kHz), so each symbol lasts 4 times longer '
                '(12.8 µs instead of 3.2 µs). Nothing about the carrier '
                'frequency changes: the channel center stays where it is, '
                'and a 20 MHz channel is still 20 MHz wide.',
          ),
          if (o.view == OfdmView.teaching) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const LabCaption(
              'In the teaching view the same 16 subcarriers are kept, so in '
              'HE they span a quarter of the width and the drawn wave turns '
              'more slowly. Real HE fills the same 20 MHz with 4 times as '
              'many subcarriers: switch to Real Wi-Fi to see it.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiverCard extends StatelessWidget {
  const _ReceiverCard({required this.model});
  final FourierLabModel model;

  static String _iq(double i, double q) {
    String f(double v) {
      final String s = v.toStringAsFixed(3);
      return s == '-0.000' ? '0.000' : s;
    }

    return '(${f(i)}, ${f(q)})';
  }

  @override
  Widget build(BuildContext context) {
    final FourierOfdmState o = model.ofdm;
    final List<RecoveredPoint> rec = o.recovered;
    final OfdmSymbol s = o.symbol;
    final double err = o.maxRecoveryError;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('The receiver runs the forward FFT'),
          const SizedBox(height: AppSpacing.xs),
          LabCaption(
            'It drops the ${s.cpSamples}-sample cyclic prefix, runs a '
            '${s.n}-point FFT on the rest, and reads one bin per subcarrier. '
            'With no noise it gets back exactly what was sent.',
          ),
          const SizedBox(height: AppSpacing.xs),
          LabReadoutRow(
            label: 'Largest error',
            value: rec.isEmpty
                ? 'nothing sent'
                : '${err.toStringAsExponential(1)} (rounding only)',
            emphasize: true,
          ),
          if (o.view == OfdmView.teaching && rec.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            for (final RecoveredPoint p in rec)
              LabReadoutRow(
                label: 'Subcarrier ${fmtK(p.k)}',
                value:
                    'sent ${_iq(s.points[p.k]!.i, s.points[p.k]!.q)}, got '
                    '${_iq(p.i, p.q)}',
              ),
          ],
        ],
      ),
    );
  }
}

/// The closing line (research brief §4): the receiver is an FFT analyzer
/// whose bins are the subcarriers.
class OfdmReceiverIsFftCard extends StatelessWidget {
  const OfdmReceiverIsFftCard({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    const double fs = OfdmMath.channelSampleRateHz;
    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionLabel('The receiver is an FFT analyzer'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A 20 MHz legacy receiver sampling at 20 MS/s with N = 64 has bins '
            'exactly 312.5 kHz apart and a 3.2 µs frame, so the receiver is an '
            'FFT analyzer whose bins are the subcarriers.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          LabReadoutRow(
            label: 'Legacy, N = 64',
            value:
                '${fmtHz(OfdmMath.spacingFor(fs, 64))} bins, '
                '${fmtTime(64 / fs)} frame',
            emphasize: true,
          ),
          LabReadoutRow(
            label: 'HE, N = 256',
            value:
                '${fmtHz(OfdmMath.spacingFor(fs, 256))} bins, '
                '${fmtTime(256 / fs)} frame',
            emphasize: true,
          ),
        ],
      ),
    );
  }
}
