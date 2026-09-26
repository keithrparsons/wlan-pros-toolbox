// Controls and explainer for the Wi-Fi Classroom Uplink vs Downlink tool.
//
// UplinkDownlinkControls: the regulatory preset, band, width, both transmit
// powers, both antenna gains, the path-loss exponent, and "Turn AP down to
// match". UplinkDownlinkExplainer: the five lessons (spec 28) and the
// formulas. Neither knows about the stage.
//
// "TURN AP DOWN TO MATCH" IS A DEMONSTRATION, NOT ADVICE. Keith's standing
// position (myPKA Team Knowledge/memory/
// feedback_ap_client_txpower_matching_is_a_vendor_trope.md) is that it
// shrinks the cell and fixes nothing on the uplink. The button exists to show
// exactly that, and every word around it says what changed and what did not.
// test/services/wifi_lab/uplink_downlink_model_test.dart sweeps this tool's
// copy for any sentence that recommends matching.
//
// PRESENTER: the explanatory prose drops (the instructor says it); the
// antenna gains and the exponent fold behind a disclosure so the panel fits a
// projector without scrolling. The preset's rule text stays: it is the
// lesson.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'uplink_downlink_controller.dart';
import 'uplink_downlink_parts.dart';

class UplinkDownlinkControls extends StatelessWidget {
  const UplinkDownlinkControls({super.key, required this.controller});
  final UplinkDownlinkController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _children(context),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final UplinkDownlinkController k = controller;
    final UdConfig c = k.config;
    final String Function(double, [int]) n = UdFormat.n;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final bool prose = !PresenterMode.isActive(context);
    final bool ruled = c.preset.isRegulated;

    final List<Widget> rarely = <Widget>[
      _slider(
        context,
        label: 'AP antenna gain',
        valueText: '${n(c.apGainDbi, 0)} dBi',
        value: c.apGainDbi,
        min: UdConfig.apGainMin,
        max: UdConfig.apGainMax,
        divisions: 8,
        onChanged: k.setApGain,
        semantic: (double v) => 'AP antenna gain ${v.round()} dBi',
      ),
      _slider(
        context,
        label: 'Client antenna gain',
        valueText: '${n(c.clientGainDbi, 0)} dBi',
        value: c.clientGainDbi,
        min: UdConfig.clientGainMin,
        max: UdConfig.clientGainMax,
        divisions: 8,
        onChanged: k.setClientGain,
        semantic: (double v) => 'Client antenna gain ${v.round()} dBi',
      ),
      _slider(
        context,
        label: 'Path-loss exponent (model)',
        valueText: 'n = ${n(c.exponent)}',
        value: c.exponent,
        min: UdConfig.exponentMin,
        max: UdConfig.exponentMax,
        divisions: 20,
        onChanged: k.setExponent,
        semantic: (double v) => 'Path-loss exponent ${n(v)}',
      ),
    ];

    return <Widget>[
      Text(
        'Regulatory rule',
        style: text.bodyMedium?.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.xxs),
      AppSelect<UdPreset>(
        value: c.preset,
        semanticLabel: 'Regulatory rule',
        maxLines: 2,
        items: <AppSelectItem<UdPreset>>[
          for (final UdPreset p in UdPreset.values) (p, p.label),
        ],
        onChanged: k.setPreset,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        c.preset.rule,
        style: text.bodySmall?.copyWith(color: colors.textSecondary),
      ),
      const SizedBox(height: AppSpacing.sm),
      AppToggle<WifiBand>(
        label: 'Band',
        value: c.band,
        expand: true,
        items: <AppToggleItem<WifiBand>>[
          for (final WifiBand b in WifiBand.values) (b, b.label),
        ],
        onChanged: k.setBand,
      ),
      if (prose && ruled) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Every rule here is a 6 GHz rule, so another band returns to '
          'Custom.',
          style: small(),
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      AppToggle<int>(
        label: 'Channel width (MHz)',
        value: c.widthMHz,
        expand: true,
        items: <AppToggleItem<int>>[
          for (final int w in c.band.widthsMHz) (w, '$w'),
        ],
        onChanged: k.setWidth,
      ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.sm),
      const UdSectionLabel('Radios (illustrative values)'),
      _slider(
        context,
        label: 'AP transmit power',
        valueText: '${n(c.apTxDbm)} dBm',
        value: c.apTxDbm,
        min: UdConfig.apTxMin,
        max: UdConfig.apTxMax,
        divisions: 60,
        onChanged: k.setApTx,
        semantic: (double v) => 'AP transmit power ${n(v)} dBm',
      ),
      _slider(
        context,
        label: ruled
            ? 'Client transmit power (set by the rule)'
            : 'Client transmit power',
        valueText: '${n(c.clientTxEffectiveDbm)} dBm',
        value: c.clientTxEffectiveDbm,
        min: UdConfig.clientTxMin,
        max: UdConfig.clientTxMax,
        divisions: 48,
        onChanged: ruled ? null : k.setClientTx,
        semantic: (double v) =>
            'Client transmit power ${n(c.clientTxEffectiveDbm)} dBm'
            '${ruled ? ', set by the rule' : ''}',
      ),
      Text(
        'Radiated power, EIRP (equivalent isotropically radiated power: '
        'transmit power plus antenna gain): AP '
        '${n(c.apEirpDbm)} dBm, client ${n(c.clientEirpDbm)} dBm'
        '${c.preset.clientFollowsAp ? '. AP authorized power ${n(c.authorizedApEirpDbm ?? c.apEirpDbm)} dBm' : ''}.',
        style: small(),
      ),
      if (prose) ...<Widget>[
        ...rarely,
        Text(
          'Defaults are illustrative: AP 20 dBm with a 4 dBi antenna, client '
          '14 dBm with a -2 dBi phone-class antenna. n = 2 is free space; '
          'indoors is usually 3 to 4. A model with a chosen exponent, not a '
          'measurement.',
          style: small(),
        ),
      ] else
        PresenterDisclosure(
          title: 'Antenna gains and path-loss exponent',
          children: rarely,
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.sm),
      _MatchButton(controller: k),
    ];
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double>? onChanged,
    required String Function(double) semantic,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool enabled = onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.xs),
        ExcludeSemantics(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: enabled ? colors.textSecondary : colors.textTertiary,
                  ),
                ),
              ),
              Text(
                valueText,
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          label: valueText,
          semanticFormatterCallback: semantic,
        ),
      ],
    );
  }
}

/// "Turn AP down to match", or "Put the AP back" while a match is shown.
class _MatchButton extends StatelessWidget {
  const _MatchButton({required this.controller});
  final UplinkDownlinkController controller;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final UdConfig c = controller.config;
    final bool presenter = PresenterMode.isActive(context);
    final String key = presenter ? ' (M)' : '';
    final UdConfig? before = controller.beforeMatch;
    final String? why = c.isMatched || c.canMatch
        ? null
        : c.clientTxEffectiveDbm >= c.apTxDbm
        ? 'The AP already transmits no more than the client.'
        : 'The client\'s power is below the AP slider\'s range.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: c.isMatched || c.canMatch ? controller.toggleMatch : null,
          icon: Icon(c.isMatched ? Icons.undo : Icons.compare_arrows),
          label: Text(
            before != null
                ? 'Put the AP back to ${UdFormat.n(before.apTxDbm)} dBm$key'
                : 'Turn AP down to match$key',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          why ??
              (c.isMatched
                  ? 'Showing the AP at the client\'s power. Compare the solid '
                        'ring with the dashed one.'
                  : 'Sets the AP\'s transmit power to the client\'s, to show '
                        'what that does to each direction.'),
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class UplinkDownlinkExplainer extends StatelessWidget {
  const UplinkDownlinkExplainer({super.key});

  /// The five lessons (spec 28), in order.
  static const List<String> lessons = <String>[
    '1. Every Wi-Fi link is two links: the downlink, AP to client, and the '
        'uplink, client to AP. Each has its own transmitter and receiver, so '
        'each has its own received level and its own MCS.',
    '2. The client usually transmits less power than the AP, and its antenna '
        'is usually worse. The AP\'s better antenna counts on receive too, so '
        'it recovers part of the uplink.',
    '3. So there is a zone where the client hears the AP well enough to stay '
        'connected while the AP barely hears the client. Asymmetry is normal, '
        'not a fault.',
    '4. Regulations can set the client\'s power relative to the AP\'s (US '
        '6 GHz Standard Power and Geofenced Variable Power, GVP: 6 dB below '
        'the AP\'s authorized power), as a flat number (US 6 GHz Low Power '
        'Indoor, LPI), or not at all (the EU).',
    '5. Turning the AP down to "match" the client shrinks the cell on the '
        'side that was already stronger and fixes nothing on the uplink. The '
        'client is the weak end of the link, and it needs the AP\'s extra '
        'power.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle formula() =>
        mono.inlineCode.copyWith(color: colors.textSecondary);
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const UdSectionLabel('What the two rings say'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lessons) ...<Widget>[
            Text(l, style: body()),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Downlink = AP power + AP gain - path loss + client gain',
            style: formula(),
          ),
          Text(
            'Uplink = client power + client gain - path loss + AP gain',
            style: formula(),
          ),
          Text(
            'Path loss = free-space path loss (FSPL) at 1 m + 10 n log10(d), '
            'the same both ways',
            style: formula(),
          ),
          Text('Downlink - uplink = AP power - client power', style: formula()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A ring is where the level falls to '
            'the MCS 0 receiver floor at the chosen width (-82 dBm at 20 MHz, '
            '3 dB higher per doubling). For one direction in detail, with '
            'cable losses and fade margin, use the Link Budget tool.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRouter.linkBudget),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Link Budget'),
            ),
          ),
        ],
      ),
    );
  }
}
