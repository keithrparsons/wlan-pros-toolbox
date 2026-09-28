// The Slowest Link Wins: the interactive panel beside two field plates,
// How Your Devices Access the Internet and Throughput Testing: Where You
// Test (research brief candidate 15, an upgrade to the plates, not a new
// entry). The plate stays exactly as it was; this panel adds one control,
// which hop is slowest, and shows every hop's rate, the slowest one marked,
// and the end-to-end number equal to it.
//
// Math: lib/services/wifi_lab/slowest_link_model.dart.
//
// States (SOP-007 §5):
//   - fresh       -> Switch port chosen: a 100 Mbps port caps a fast Wi-Fi
//                    link and a 300 Mb/s plan at 94.1 Mb/s (the plate's own
//                    worked example is a 100 Mbps uplink)
//   - loading, empty, error -> not reachable: pure arithmetic, no I/O, and
//                    the only input is a three-way toggle
//   - disabled    -> nothing disables
//   - interactive -> AppToggle, keyboard and screen reader through its
//                    radio-group semantics; the global focus ring
//
// COLOR (GL-003 §8.13, §8.20.2). The slowest hop's bar is the vivid lime
// fill and its row carries an icon and the words "Slowest hop", so it is
// never told by hue alone (SC 1.4.1); the other bars are neutral. Its row
// border is textAccent (the thin-foreground lime that passes on light). No
// status hues: "slowest" is the answer the tool computes, not a verdict.
//
// ASCII only, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/slowest_link_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';

/// Where the numbers come from, in words. Pinned by a test.
const String kSlSourcesText =
    'Port rates are the Ethernet line rates; what a port carries is the TCP '
    '(transmission control protocol) payload of a full-size frame, 1448 of '
    'every 1538 bytes on the wire. The Wi-Fi rate is the 802.11ax PHY '
    '(physical layer) rate at 5 GHz, 80 MHz, 2 spatial streams, times an '
    'illustrative 0.6 efficiency, as in Repeaters and Mesh Backhaul. The '
    '300 Mb/s plan is illustrative. CWNA-109 objective 6.6.1 lists port '
    'speed and too little internet bandwidth among the causes of '
    'insufficient throughput.';

class SlowestLinkPanel extends StatefulWidget {
  const SlowestLinkPanel({super.key, this.initial = SlSlowest.switchPort});

  /// The hop that starts slowest.
  final SlSlowest initial;

  @override
  State<SlowestLinkPanel> createState() => _SlowestLinkPanelState();
}

class _SlowestLinkPanelState extends State<SlowestLinkPanel> {
  late SlSlowest _slowest = widget.initial;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final SlChain chain = SlChain(_slowest);
    final SlChain best = chain.withBestWifi;
    final double top = chain.hops
        .map((SlHop h) => h.mbps)
        .reduce((double a, double b) => a > b ? a : b);
    final TextStyle note =
        text.bodySmall?.copyWith(color: colors.textTertiary) ??
        TextStyle(color: colors.textTertiary);

    final bool wifiIsSlowest = chain.bottleneck == 0;
    final String upgrade = wifiIsSlowest
        ? 'A faster Wi-Fi link (MCS $kSlMcsBest, the best here) raises the '
              'total to ${slMbps(best.endToEndMbps)}, and no further: then '
              'the ${best.hops[best.bottleneck].kind.inSentence} '
              'is the slowest hop.'
        : 'A faster Wi-Fi link (MCS $kSlMcsBest, the best here) leaves the '
              'total at ${slMbps(best.endToEndMbps)}. The Wi-Fi was not the '
              'slowest hop, so a new Wi-Fi router cannot make this '
              'internet faster.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Try it: the slowest link wins',
          style: text.titleSmall?.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'Traffic crosses every hop in turn: the Wi-Fi link, the switch '
          'port and the ISP (internet service provider) plan. The whole '
          'path runs at the speed of its slowest hop. Wi-Fi rates are set by '
          'the MCS (modulation and coding scheme).',
          style: note,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppToggle<SlSlowest>(
          label: 'Make this hop the slowest',
          semanticLabel: 'Which hop is the slowest',
          value: _slowest,
          expand: true,
          items: <AppToggleItem<SlSlowest>>[
            for (final SlSlowest s in SlSlowest.values) (s, s.label),
          ],
          onChanged: (SlSlowest s) => setState(() => _slowest = s),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (int i = 0; i < chain.hops.length; i++) ...<Widget>[
          _HopRow(
            hop: chain.hops[i],
            index: i,
            fraction: chain.hops[i].mbps / top,
            slowest: i == chain.bottleneck,
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          label:
              'End to end: ${slMbps(chain.endToEndMbps)}, equal to the '
              'slowest hop, the ${chain.hops[chain.bottleneck].kind.inSentence}.',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'End to end',
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
              Text(
                slMbps(chain.endToEndMbps),
                style: mono.outputLarge.copyWith(color: colors.textAccent),
              ),
              Text(
                'Equal to the slowest hop, the '
                '${chain.hops[chain.bottleneck].kind.inSentence}.',
                style: note,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          upgrade,
          style: text.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(kSlSourcesText, style: note),
      ],
    );
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({
    required this.hop,
    required this.index,
    required this.fraction,
    required this.slowest,
  });

  final SlHop hop;
  final int index;

  /// This hop's rate as a share of the fastest hop's, 0 to 1.
  final double fraction;

  final bool slowest;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      label:
          'Hop ${index + 1}, ${hop.kind.label}, ${hop.kind.span}: '
          '${hop.detail}, carries ${slMbps(hop.mbps)}'
          '${slowest ? '. Slowest hop, it sets the total.' : '.'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: slowest ? colors.textAccent : colors.border,
            width: slowest ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${index + 1}. ${hop.kind.label}',
                    style: text.labelLarge?.copyWith(color: colors.textPrimary),
                  ),
                ),
                Text(
                  slMbps(hop.mbps),
                  style: mono.inlineCode.copyWith(
                    color: slowest ? colors.textAccent : colors.textPrimary,
                  ),
                ),
              ],
            ),
            Text(
              '${hop.kind.span}; ${hop.detail}',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: SizedBox(
                height: AppSpacing.xs,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(color: colors.inputFill),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction.clamp(0.02, 1.0),
                      child: ColoredBox(
                        color: slowest ? colors.primary : colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (slowest) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: AppSpacing.sm,
                    color: colors.textAccent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Slowest hop: it sets the total',
                    style: text.labelMedium?.copyWith(color: colors.textAccent),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
