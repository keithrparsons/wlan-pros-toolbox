// Controls and explainer for the Wi-Fi Classroom tool "PoE: Why the New AP
// Runs at Half Strength" (poe-half-strength).
//
// PoeHalfStrengthControls: the switch port type (the one main control) and,
// on 802.3at, what the AP gives up (both choices are in the vendor guide);
// disabled with the reason in words on the other ports.
//
// PoeHalfStrengthExplainer: the lessons, the sources, and links to the PoE
// Budget and PoE Reference tools.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'poe_half_strength_controller.dart';
import 'poe_half_strength_parts.dart';

class PoeHalfStrengthControls extends StatelessWidget {
  const PoeHalfStrengthControls({super.key, required this.controller});
  final PoeHalfStrengthController controller;

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
    final PoeHalfStrengthController k = controller;
    final PhConfig c = k.config;
    final bool prose = !PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final bool onAt = c.port == PhPort.at;

    return <Widget>[
      AppToggle<PhPort>(
        label: prose ? 'Switch port type' : 'Switch port type (Up, Down)',
        semanticLabel: 'Switch port type',
        value: c.port,
        expand: true,
        items: <AppToggleItem<PhPort>>[
          for (final PhPort p in PhPort.values) (p, p.standard),
        ],
        onChanged: k.setPort,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        '${c.port.label}: ${PhFormat.watts(c.port.pseWatts)} from the switch, '
        'up to ${PhFormat.watts(c.port.pdWatts)} at the AP after the cable. '
        'PoE: Power over Ethernet.',
        style: small(),
      ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      AppToggle<PhAtMode>(
        label: prose
            ? 'What the AP gives up on 802.3at'
            : 'What the AP gives up on 802.3at (Space)',
        semanticLabel: 'What the AP gives up on 802.3at',
        value: c.atMode,
        expand: true,
        enabled: onAt,
        items: const <AppToggleItem<PhAtMode>>[
          (PhAtMode.allAt2x2, 'Three at 2x2'),
          (PhAtMode.twoAt4x4, 'Two at 4x4'),
        ],
        onChanged: k.setAtMode,
      ),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        onAt
            ? (c.atMode == PhAtMode.allAt2x2
                  ? 'All three radios drop to two streams each.'
                  : 'Two radios keep four streams each; this model turns off '
                        '2.4 GHz.')
            : 'Applies only on an 802.3at port. On ${c.port.standard} the AP '
                  '${c.port == PhPort.bt ? 'has all the power it needs' : 'runs no Wi-Fi radio in this model'}.',
        style: small(),
      ),
      if (prose) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The guide this AP follows lists both 802.3at choices. Which one '
          'an AP takes, or whether you can pick, depends on the vendor.',
          style: small(),
        ),
      ],
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: k.reset,
          icon: const Icon(Icons.restart_alt),
          label: Text('Reset${prose ? '' : ' (R)'}'),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTouchTarget),
          ),
        ),
      ),
    ];
  }
}

// ── Explainer ────────────────────────────────────────────────────────────

class PoeHalfStrengthExplainer extends StatelessWidget {
  const PoeHalfStrengthExplainer({super.key});

  static const List<String> lessons = <String>[
    '1. A power light proves the AP has power, not that it has enough. A '
        'Wi-Fi 7 AP on a port that cannot supply its full power still boots '
        'and still lights up.',
    '2. Short of power, the AP quietly turns things off: here, on 802.3at, '
        'either every radio drops from four streams to two, or one radio '
        'goes dark. Either way it is running at part strength.',
    '3. Check the AP\'s own power status, and the power the switch has '
        'granted the port, before you trust a survey or a speed test on a '
        'new AP.',
    '4. Plan the switch before the AP: an 802.3bt port, or a switch budget '
        'large enough for every AP at full power.',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    TextStyle body() => text.bodyMedium!.copyWith(color: colors.textPrimary);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    return PhCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PhSectionLabel('What the port costs the AP'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lessons) ...<Widget>[
            Text(l, style: body()),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(PhLabels.vendorsDiffer, style: small()),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Port power: IEEE 802.3, the figures in PoE Reference. The AP\'s '
            'need and its 802.3at behavior follow a published Wi-Fi 7 AP '
            'guide; the sources are named in the help.',
            style: small(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'To add up a whole switch, use PoE Budget; for every class and '
            'type, PoE Reference.',
            style: small(),
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.poeBudget),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open PoE Budget'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.poeReference),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open PoE Reference'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
