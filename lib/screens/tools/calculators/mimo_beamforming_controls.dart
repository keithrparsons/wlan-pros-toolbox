// MimoControls: the inputs-and-readouts half of the MIMO and Beamforming
// simulator.
//
// Takes the shared MimoController and a set of parts to show, so the phone
// layout can put the chain counts above MimoStage and everything else below
// it, while a presenter layout shows every part in one column beside the
// stage. No part draws a plot; MimoStage owns those.
//
// Control types follow GL-003 §8.14: chain counts, sniffer chains and
// channel width are Selects (4 or more options); beamforming on/off is a
// two-option AppToggle; angles and the sounding interval are sliders.
//
// Status hues (§8.13 rule 6, §8.15.1) appear on exactly one verdict: the
// sniffer cannot separate the streams (statusDanger, with an icon and the
// word "No"). Everything else is neutral, with lime on the headline numbers.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/mimo_beamforming_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../labeled_field.dart';
import 'mimo_beamforming_controller.dart';
import 'mimo_beamforming_parts.dart';

typedef _C = MimoController;

/// The groups MimoControls can show.
enum MimoControlPart {
  /// AP and client chains, swap, beamforming on/off.
  setup,

  /// Client and sniffer angles, sniffer chains, channel width, interval.
  inputs,

  /// Both directions, sounding, the sniffer, the measurement, the explainer.
  readouts,
}

class MimoControls extends StatelessWidget {
  const MimoControls({
    super.key,
    required this.controller,
    this.parts = const <MimoControlPart>{
      MimoControlPart.setup,
      MimoControlPart.inputs,
      MimoControlPart.readouts,
    },
  });

  final MimoController controller;
  final Set<MimoControlPart> parts;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final MimoController c = controller;
        final List<Widget> cards = <Widget>[
          if (parts.contains(MimoControlPart.setup)) _SetupCard(c),
          if (parts.contains(MimoControlPart.inputs)) _InputsCard(c),
          if (parts.contains(MimoControlPart.readouts)) ...<Widget>[
            _DirectionsCard(c),
            _SnifferCard(c),
            const _MeasurementCard(),
            if (c.sounding) _SoundingReadoutCard(c),
            _ExplainerCard(c),
          ],
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < cards.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

// ── Setup ───────────────────────────────────────────────────────────────────

class _SetupCard extends StatelessWidget {
  const _SetupCard(this.c);

  final MimoController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: LabeledField(
                  label: 'AP chains',
                  semanticLabel: 'AP antenna chains',
                  field: AppSelect<int>(
                    value: c.apChains,
                    semanticLabel: 'AP antenna chains',
                    items: <AppSelectItem<int>>[
                      for (final int n in kApChainOptions) (n, '$n'),
                    ],
                    onChanged: (int n) => c.apChains = n,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LabeledField(
                  label: 'Client chains',
                  semanticLabel: 'Client antenna chains',
                  field: AppSelect<int>(
                    value: c.clientChains,
                    semanticLabel: 'Client antenna chains',
                    items: <AppSelectItem<int>>[
                      for (final int n in kClientChainOptions) (n, '$n'),
                    ],
                    onChanged: (int n) => c.clientChains = n,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${c.apChains}x${c.apChains} AP, '
                  '${c.clientChains}x${c.clientChains} client: '
                  '${c.downlink.streams} stream'
                  '${c.downlink.streams == 1 ? '' : 's'} each way.',
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
              Semantics(
                button: true,
                label:
                    'Swap: give the AP the client\'s chains and the '
                    'client the AP\'s',
                excludeSemantics: true,
                child: OutlinedButton.icon(
                  onPressed: c.swapSides,
                  icon: Icon(Icons.swap_horiz, color: colors.textAccent),
                  label: Text(
                    'Swap',
                    style: text.labelLarge?.copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textAccent,
                    side: BorderSide(color: colors.borderStrong, width: 1.5),
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                ),
              ),
            ],
          ),
          if (c.swapClamps)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                'Clients stop at 4 chains, so a swap makes the client 4x4.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          AppToggle<bool>(
            label: 'AP transmit beamforming',
            value: c.beamforming,
            expand: true,
            enabled: c.apCanBeamform,
            items: const <AppToggleItem<bool>>[(true, 'On'), (false, 'Off')],
            onChanged: (bool v) => c.beamforming = v,
          ),
          if (!c.apCanBeamform)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                'A 1-chain AP cannot beamform.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Inputs ──────────────────────────────────────────────────────────────────

class _InputsCard extends StatelessWidget {
  const _InputsCard(this.c);

  final MimoController c;

  Slider _angleSlider(
    AppColorScheme colors,
    String name,
    double value,
    ValueChanged<double> set,
  ) => Slider(
    value: value,
    min: -kMaxAngleDeg,
    max: kMaxAngleDeg,
    divisions: (2 * kMaxAngleDeg).round(),
    onChanged: (double v) => set(v),
    activeColor: colors.primary,
    inactiveColor: colors.disabledFill,
    label: _C.deg(value),
    semanticFormatterCallback: (double v) => '$name ${_C.deg(v)}',
  );

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MbSliderHeader(label: 'Client angle', value: _C.deg(c.clientDeg)),
          _angleSlider(
            colors,
            'Client angle',
            c.clientDeg,
            (double v) => c.clientDeg = v,
          ),
          MbSliderHeader(label: 'Sniffer angle', value: _C.deg(c.snifferDeg)),
          _angleSlider(
            colors,
            'Sniffer angle',
            c.snifferDeg,
            (double v) => c.snifferDeg = v,
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: LabeledField(
                  label: 'Sniffer chains',
                  semanticLabel: 'Sniffer receive chains',
                  field: AppSelect<int>(
                    value: c.snifferChains,
                    semanticLabel: 'Sniffer receive chains',
                    items: <AppSelectItem<int>>[
                      for (final int n in kClientChainOptions) (n, '$n'),
                    ],
                    onChanged: (int n) => c.snifferChains = n,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: LabeledField(
                  label: 'Channel width',
                  semanticLabel: 'Channel width',
                  field: AppSelect<ChannelWidth>(
                    value: c.width,
                    semanticLabel: 'Channel width',
                    items: <AppSelectItem<ChannelWidth>>[
                      for (final ChannelWidth w in ChannelWidth.values)
                        (w, w.label),
                    ],
                    onChanged: (ChannelWidth w) => c.width = w,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          MbSliderHeader(
            label: 'Sounding interval',
            value: c.sounding ? _C.ms(c.intervalMs) : 'no sounding',
          ),
          Slider(
            value: c.intervalIndex.toDouble(),
            max: (kSoundingIntervalsMs.length - 1).toDouble(),
            divisions: kSoundingIntervalsMs.length - 1,
            onChanged: c.sounding
                ? (double v) => c.intervalIndex = v.round()
                : null,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            label: _C.ms(c.intervalMs),
            semanticFormatterCallback: (double v) =>
                'Sounding interval '
                '${_C.ms(kSoundingIntervalsMs[v.round()])}',
          ),
          MbNote(
            icon: Icons.swipe,
            message:
                'Drag the client or the sniffer in the beam pattern, or use '
                'the angle sliders. Arrow keys move them 1 deg at a time.',
          ),
        ],
      ),
    );
  }
}

// ── Readouts ────────────────────────────────────────────────────────────────

/// A label and two DM Mono values: downlink, uplink.
class _PairRow extends StatelessWidget {
  const _PairRow({
    required this.label,
    required this.down,
    required this.up,
    this.emphasize = false,
    this.header = false,
    this.quiet = false,
  });

  final String label;
  final String down;
  final String up;
  final bool emphasize;
  final bool header;

  /// A second, smaller header line (who sends).
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle value = header
        ? (quiet ? text.bodySmall! : text.labelMedium!).copyWith(
            color: quiet ? colors.textTertiary : colors.textSecondary,
            fontWeight: quiet ? FontWeight.w400 : FontWeight.w600,
          )
        : mono.inlineCode.copyWith(
            color: emphasize ? colors.textAccent : colors.textPrimary,
            fontWeight: emphasize ? FontWeight.w500 : FontWeight.w400,
          );
    return Semantics(
      label: header ? null : '$label: downlink $down, uplink $up',
      excludeSemantics: !header,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 5,
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(flex: 3, child: Text(down, style: value)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(flex: 3, child: Text(up, style: value)),
          ],
        ),
      ),
    );
  }
}

String _short(double gainDb) =>
    gainDb <= 0 ? 'none' : '+${gainDb.toStringAsFixed(1)} dB';

class _DirectionsCard extends StatelessWidget {
  const _DirectionsCard(this.c);

  final MimoController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final MimoLink dl = c.downlink;
    final MimoLink ul = c.uplink;
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('Both directions side by side'),
          const SizedBox(height: AppSpacing.xxs),
          const _PairRow(
            label: '',
            down: 'Downlink',
            up: 'Uplink',
            header: true,
          ),
          const _PairRow(
            label: '',
            down: 'AP sends',
            up: 'Client sends',
            header: true,
            quiet: true,
          ),
          _PairRow(
            label: 'Spatial streams',
            down: '${dl.streams}',
            up: '${ul.streams}',
            emphasize: true,
          ),
          _PairRow(
            label: 'Transmitter chains',
            down: '${dl.txChains}',
            up: '${ul.txChains}',
          ),
          _PairRow(
            label: 'Receiver chains',
            down: '${dl.rxChains}',
            up: '${ul.rxChains}',
          ),
          _PairRow(
            label: 'Transmit beamforming, ideal upper bound',
            down: _short(dl.idealTxBfGainDb),
            up: _short(ul.idealTxBfGainDb),
          ),
          _PairRow(
            label: 'Receive combining, ideal upper bound',
            down: _short(dl.idealCombiningGainDb),
            up: _short(ul.idealCombiningGainDb),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ideal gains are upper bounds: 10 log10(chains / streams). Real '
            'gain is lower and changes with the room. The client does not '
            'beamform in this model, so the uplink never has a transmit '
            'beamforming gain.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _SnifferCard extends StatelessWidget {
  const _SnifferCard(this.c);

  final MimoController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool ok = c.snifferDecodes;
    final int n = c.streams;
    final String dir = c.direction.label.toLowerCase();
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('The sniffer\'s view'),
          const SizedBox(height: AppSpacing.xxs),
          Semantics(
            label:
                'Separates the $dir streams: ${ok ? 'yes' : 'no'}. '
                '${c.snifferChains} chain${c.snifferChains == 1 ? '' : 's'} '
                'for $n stream${n == 1 ? '' : 's'}.',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 120,
                    child: Text(
                      'Separates the streams',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (!ok) ...<Widget>[
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: colors.statusDanger,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Expanded(
                    child: Text(
                      ok
                          ? 'Yes: ${c.snifferChains} chains for $n '
                                'stream${n == 1 ? '' : 's'}'
                          : 'No: ${c.snifferChains} '
                                'chain${c.snifferChains == 1 ? '' : 's'} '
                                'for $n streams',
                      style: mono.inlineCode.copyWith(
                        color: ok ? colors.textPrimary : colors.statusDanger,
                        fontWeight: ok ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          MbRow(
            label: 'Level vs the client',
            value: c.steered
                ? _C.db(c.snifferRelativeDb)
                : '${_C.db(0)}, not steered',
            emphasize: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ok
                ? 'Enough chains to separate the streams. It can still miss '
                      'frames the client decoded: '
                      '${c.steered ? 'the AP aims at the client, not at the sniffer, so the sniffer hears a weaker, distorted mix.' : 'it sits in a different spot with its own fades.'}'
                : 'Each of the sniffer\'s chains hears every stream mixed '
                      'together. With fewer chains than streams it cannot '
                      'pull them apart, so every $n-stream frame fails, even '
                      'at a strong signal.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// OUR MEASUREMENT, never a model output. The figures come from
/// [CaptureMeasurement], which cites the number audit.
class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('Our measurement, not a model output'),
          const SizedBox(height: AppSpacing.xxs),
          const MbRow(
            label: 'FCS failed, beamformed',
            value: '${CaptureMeasurement.fcsFailBeamformedPct}%',
            emphasize: true,
          ),
          const MbRow(
            label: 'FCS failed, not beamformed',
            value: '${CaptureMeasurement.fcsFailNotBeamformedPct}%',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One 802.11ax capture taken by a nearby sniffer, not by the '
            'client. At matched signal strength, beamformed downlink frames '
            'failed their frame check about ${CaptureMeasurement.ratio} '
            'times as often as frames that were not beamformed. The client '
            'received them. The sniffer was not the one being aimed at.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Signal-matched: only the signal levels where each group had at '
            'least 200 frames; 14,825 beamformed and 6,891 not.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _SoundingReadoutCard extends StatelessWidget {
  const _SoundingReadoutCard(this.c);

  final MimoController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final SoundingEstimate s = c.soundingEstimate;
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('Sounding, estimated'),
          const SizedBox(height: AppSpacing.xxs),
          MbRow(
            label: 'Share of airtime',
            value: '${_C.pct(c.soundingShare)} every ${_C.ms(c.intervalMs)}',
            emphasize: true,
          ),
          MbRow(label: 'One exchange', value: _C.us(s.totalUs)),
          MbRow(
            label: 'Report size',
            value: '${_C.bytes(s.reportBytes)} (${s.nr}x${s.nc})',
          ),
          MbRow(
            label: 'Report angles',
            value: '${s.angles} x ${s.subcarrierGroups} groups',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For one client. Each beamformed client is sounded on its own '
            'schedule, so more clients cost more. The estimate assumes the '
            'NDPA at 6 Mbps, the report at 1 stream MCS 4, every 4th '
            'subcarrier reported, and leaves out the wait for the medium. A '
            'wider channel makes the report bigger, but the report also '
            'travels over the wider channel, so its airtime stays the same; '
            'more AP chains and more streams are what cost more.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard(this.c);

  final MimoController c;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? body = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary);
    const List<String> paras = <String>[
      'Streams are capped by the smaller side. A 4x4 AP and a 2x2 client '
          'talk at 2 spatial streams in both directions.',
      'The extra chains still earn their keep, differently each way. On the '
          'downlink the AP\'s spare transmit chains steer energy at the '
          'client. On the uplink the AP\'s spare receive chains listen too '
          'and combine. Press Swap for the vice versa case, where the client '
          'has the spare chains.',
      'Beamforming is not free. The AP must sound the client first, and the '
          'report grows with the antennas and the channel width.',
      'A capture on your laptop is not the AP\'s view. The AP aims at the '
          'client, not at your sniffer, and a sniffer with fewer chains than '
          'the streams cannot separate them. So a local capture drops '
          'downlink frames the client received fine. A capture on the AP '
          'sees more: the AP knows what it sent and is the intended receiver '
          'for the uplink.',
    ];
    return MbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const MbSectionLabel('What you are seeing'),
          const SizedBox(height: AppSpacing.xs),
          for (int i = 0; i < paras.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            Text(paras[i], style: body),
          ],
        ],
      ),
    );
  }
}
