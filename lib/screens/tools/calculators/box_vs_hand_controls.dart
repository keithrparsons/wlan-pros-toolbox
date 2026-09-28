// Controls and explainer for the Wi-Fi Classroom tool The Number on the Box
// vs the Number in Your Hand (box-vs-hand).
//
// BoxVsHandControls: the client (the one control that matters, default a
// 2x2 phone), then the distance and the channel width for the third step.
// BoxVsHandExplainer: the lesson, the formulas, and the tools whose math this
// one reuses. Neither knows about the stage.
//
// PRESENTER: the explanatory prose drops (the instructor says it) and each
// label carries its key.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'box_vs_hand_controller.dart';
import 'box_vs_hand_parts.dart';

class BoxVsHandControls extends StatelessWidget {
  const BoxVsHandControls({super.key, required this.controller});
  final BoxVsHandController controller;

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
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final BoxVsHandController k = controller;
    final bool prose = !PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final String dist = k.length.dist(k.distanceM);

    return <Widget>[
      const BvhSectionLabel('Who is holding the device'),
      const SizedBox(height: AppSpacing.xxs),
      AppToggle<BvhClient>(
        label: prose
            ? 'Client: phone and laptop are 2x2'
            : 'Client, phone and laptop 2x2 (Up, Down)',
        value: k.client,
        expand: true,
        items: <AppToggleItem<BvhClient>>[
          for (final BvhClient c in BvhClient.values) (c, c.shortLabel),
        ],
        onChanged: k.setClient,
      ),
      if (prose) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '2x2 means two antennas and two spatial streams, what current '
          'phones publish. The 4-stream reference is a client as big as the '
          'router, for comparison.',
          style: small(),
        ),
      ],
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.sm),
      const BvhSectionLabel('Step 3: distance and width'),
      const SizedBox(height: AppSpacing.xs),
      ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Distance from the router',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Text(
              dist,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
      Slider(
        value: k.distanceM,
        min: BoxVsHand.minDistanceM,
        max: BoxVsHand.maxDistanceM,
        divisions: ((BoxVsHand.maxDistanceM - BoxVsHand.minDistanceM) * 2)
            .round(),
        onChanged: k.setDistance,
        activeColor: colors.primary,
        inactiveColor: colors.disabledFill,
        label: dist,
        semanticFormatterCallback: (double v) =>
            'Distance from the router, ${k.length.distSpoken(v)}',
      ),
      if (prose)
        Text(
          'The default, ${k.length.dist(BoxVsHand.defaultDistanceM)}, is an '
          'illustrative choice.',
          style: small(),
        ),
      const SizedBox(height: AppSpacing.xs),
      AppToggle<int>(
        label: 'Channel width, 6 GHz (MHz)',
        value: k.widthMHz,
        expand: true,
        items: <AppToggleItem<int>>[
          for (final int w in BoxVsHand.widthsMHz) (w, '$w'),
        ],
        onChanged: k.setWidth,
      ),
      if (prose) ...<Widget>[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'A wider channel carries more per symbol but needs a stronger '
          'signal for the same MCS, so at a distance a narrower one can win.',
          style: small(),
        ),
      ],
      if (k.step != BvhStep.atDistance) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'These set step 3. Press Show the next step on the bars to reach it.',
          style: small(),
        ),
      ],
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: k.reset,
          icon: const Icon(Icons.restart_alt),
          label: Text(prose ? 'Reset' : 'Reset (R)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTouchTarget),
          ),
        ),
      ),
    ];
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class BoxVsHandExplainer extends StatelessWidget {
  const BoxVsHandExplainer({super.key});

  static const List<String> lessons = <String>[
    '1. The class number on a router box adds every radio at its maximum: '
        'each band at its widest channel, its top MCS and all its streams.',
    '2. One client uses one link at a time here, with its own streams. A '
        '2x2 phone gets half of the fastest radio at the very most, and only '
        'a few meters away.',
    '3. Distance takes it lower again: the signal weakens, the MCS steps '
        'down, and the rate follows.',
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
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    return BvhCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const BvhSectionLabel('Why the numbers differ'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lessons) ...<Widget>[
            Text(l, style: body()),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text('Box = 11,520 + 5,760 + 1,376 = 18,656 Mbps', style: formula()),
          Text(
            'PHY rate = data subcarriers x bits per symbol x streams / '
            'symbol time',
            style: formula(),
          ),
          Text('Estimate = PHY rate x 0.80', style: formula()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'PHY rates come from the Throughput Calculator (802.11be, 0.8 us '
            'guard interval), the same figures as the MCS Index. The received '
            'level and the MCS come from Rate vs Range at its defaults: 20 dBm '
            'EIRP (effective isotropic radiated power), a 0 dBi client antenna '
            '(decibels over an isotropic antenna) and a path-loss exponent of '
            '3, on 6 GHz channel 37. The 0.80 factor is the Throughput '
            'Calculator estimate for 802.11be and is favorable: real traffic '
            'usually gets less. Other clients sharing the airtime, walls and '
            'interference are left out, so step 3 is an upper limit for this '
            'client.',
            style: small(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              for (final (String label, String route) in <(String, String)>[
                ('Open Throughput Calculator', AppRouter.throughputCalc),
                ('Open MCS Index', AppRouter.mcsIndex),
                ('Open Rate vs Range', AppRouter.rateVsRange),
              ])
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(route),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
