// Controls and explainer for the Wi-Fi Classroom Body Loss tool.
//
// BodyLossControls: band, holder facing, the two body losses and the two
// band multipliers (every one labeled illustrative, from BlLabels), and the
// crowd: empty vs occupied, crowd size, scatter. BodyLossExplainer: the four
// lessons (spec 34), the formulas, and pointers to the wall tools. Neither
// knows about the stage.
//
// ILLUSTRATIVE, EVERYWHERE. No primary source was read for any body-loss
// figure, so each loss is a setting and every label that names one says so.
// test/services/wifi_lab/body_loss_model_test.dart holds BlLabels to it and
// test/screens/calculators/body_loss_screen_test.dart finds each on screen.
//
// PRESENTER: the explanatory prose drops (the instructor says it); the band
// multipliers fold behind a disclosure so the panel fits a projector without
// scrolling. The section title "Body losses (illustrative values)" stays.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../router/app_router.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'body_loss_controller.dart';
import 'body_loss_parts.dart';

class BodyLossControls extends StatelessWidget {
  const BodyLossControls({super.key, required this.controller});
  final BodyLossController controller;

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
    final BodyLossController k = controller;
    final BlConfig c = k.config;
    final String Function(double, [int]) n = BlFormat.n;
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);
    final bool prose = !PresenterMode.isActive(context);
    final String keys = prose ? '' : ' (Left, Right)';

    final List<Widget> multipliers = <Widget>[
      _slider(
        context,
        label: BlLabels.multiplier5,
        valueText: 'x${n(c.multiplier5, 2)}',
        value: c.multiplier5,
        min: BlConfig.multiplierMin,
        max: BlConfig.multiplierMax,
        divisions: 20,
        onChanged: k.setMultiplier5,
        semantic: (double v) =>
            '5 GHz body-loss multiplier, illustrative, times ${n(v, 2)}',
      ),
      _slider(
        context,
        label: BlLabels.multiplier6,
        valueText: 'x${n(c.multiplier6, 2)}',
        value: c.multiplier6,
        min: BlConfig.multiplierMin,
        max: BlConfig.multiplierMax,
        divisions: 20,
        onChanged: k.setMultiplier6,
        semantic: (double v) =>
            '6 GHz body-loss multiplier, illustrative, times ${n(v, 2)}',
      ),
    ];

    return <Widget>[
      AppToggle<WifiBand>(
        label: 'Band',
        value: c.band,
        expand: true,
        items: <AppToggleItem<WifiBand>>[
          for (final WifiBand b in WifiBand.values) (b, b.label),
        ],
        onChanged: k.setBand,
      ),
      SizedBox(height: prose ? AppSpacing.sm : AppSpacing.xs),
      _slider(
        context,
        label: 'Holder facing$keys',
        valueText:
            '${BlFormat.deg(c.facingDeg)}, ${BlFormat.deg(c.offAxisDeg)} off '
            'the AP',
        value: c.facingDeg,
        min: 0,
        max: 360,
        divisions: 72,
        onChanged: k.setFacing,
        semantic: (double v) =>
            'Holder facing ${v.round() % 360} degrees, '
            '${c.offAxisDeg.round()} degrees away from the AP',
      ),
      Wrap(
        spacing: AppSpacing.xs,
        children: <Widget>[
          TextButton(onPressed: k.faceAp, child: const Text('Face the AP')),
          TextButton(
            onPressed: k.backToAp,
            child: const Text('Back to the AP'),
          ),
        ],
      ),
      if (prose)
        Text(
          '0 degrees is up the page, 90 is right. ${BlLabels.turnRamp}',
          style: small(),
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      const BlSectionLabel(BlLabels.lossesSection),
      _slider(
        context,
        label: BlLabels.holderLoss,
        valueText: BlFormat.db(c.holderLossDb),
        value: c.holderLossDb,
        min: BlConfig.holderLossMin,
        max: BlConfig.holderLossMax,
        divisions: 40,
        onChanged: k.setHolderLoss,
        semantic: (double v) =>
            'Holder body loss at 2.4 gigahertz, illustrative, ${n(v)} dB',
      ),
      _slider(
        context,
        label: BlLabels.perPersonLoss,
        valueText: BlFormat.db(c.perPersonLossDb),
        value: c.perPersonLossDb,
        min: BlConfig.perPersonLossMin,
        max: BlConfig.perPersonLossMax,
        divisions: 20,
        onChanged: k.setPerPersonLoss,
        semantic: (double v) =>
            'Loss per person on the line at 2.4 gigahertz, illustrative, '
            '${n(v)} dB',
      ),
      if (prose) ...<Widget>[
        ...multipliers,
        Text(
          'Defaults are illustrative: 8 dB for the holder and 4 dB per '
          'person at 2.4 GHz, times 1.2 at 5 GHz and 1.3 at 6 GHz. Higher '
          'bands generally lose more to the body; the multipliers show that '
          'trend, not a measured table.',
          style: small(),
        ),
      ] else
        PresenterDisclosure(
          title: 'Band multipliers (illustrative)',
          children: multipliers,
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      const BlSectionLabel('Crowd'),
      const SizedBox(height: AppSpacing.xxs),
      AppToggle<bool>(
        label: prose ? 'Building' : 'Building (Space)',
        value: c.occupied,
        expand: true,
        items: const <AppToggleItem<bool>>[
          (false, 'Empty'),
          (true, 'Occupied'),
        ],
        onChanged: k.setOccupied,
      ),
      _slider(
        context,
        label: prose ? 'People in the room' : 'People in the room (Up, Down)',
        valueText: '${c.crowdSize}',
        value: c.crowdSize.toDouble(),
        min: 0,
        max: BlConfig.maxCrowd.toDouble(),
        divisions: BlConfig.maxCrowd,
        onChanged: c.occupied ? (double v) => k.setCrowdSize(v.round()) : null,
        semantic: (double v) => '${v.round()} people in the room',
      ),
      if (!c.occupied)
        Text(
          'The building is empty. Choose Occupied to bring the crowd back.',
          style: small(),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: c.occupied && c.crowdSize > 0 ? k.scatter : null,
          icon: const Icon(Icons.shuffle),
          label: const Text('Scatter the crowd'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, AppSpacing.minTouchTarget),
          ),
        ),
      ),
      if (prose)
        Text(
          'Scatter places the crowd again from the next seed; the same seed '
          'always gives the same room. Drag any person to place them.',
          style: small(),
        ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.bodyMedium?.copyWith(
                    color: enabled ? colors.textSecondary : colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
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

// ── Explainer ─────────────────────────────────────────────────────────────

class BodyLossExplainer extends StatelessWidget {
  const BodyLossExplainer({super.key});

  /// The four lessons (spec 34), in order.
  static const List<String> lessons = <String>[
    '1. A person between the device and the AP costs decibels. The person '
        'holding the device often costs the most, because their body is '
        'right next to its antenna.',
    '2. The loss depends on which way the holder faces. Facing the AP with '
        'the device in front costs little; turning your back puts your body '
        'in the path.',
    '3. Crowds add up. A room full of people is a room full of obstacles '
        'that are mostly water, which is why a survey of the empty building '
        'reads better than the building in use.',
    '4. Higher bands generally lose more to the body. The multipliers here '
        'show that trend with illustrative values, not a measured table.',
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
    return BlCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const BlSectionLabel('What the bodies cost'),
          const SizedBox(height: AppSpacing.xs),
          for (final String l in lessons) ...<Widget>[
            Text(l, style: body()),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Received = 20 dBm radiated - path loss - holder loss - crowd loss',
            style: formula(),
          ),
          Text(
            'Path loss = free-space path loss (FSPL) at 1 m + 10 x 3 x '
            'log10(d)',
            style: formula(),
          ),
          Text(
            'Holder loss = holder setting x band multiplier x turn share',
            style: formula(),
          ),
          Text(
            'Crowd loss = per-person setting x band multiplier x people on '
            'the line',
            style: formula(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The AP radiates 20 dBm and the device antenna adds nothing (0 '
            'dBi, decibels over an isotropic antenna). The path-loss exponent '
            'is 3, the Roaming Walk default. MCS comes from the Rate vs Range '
            'receiver floors at 20 MHz. The turn share is 0 facing the AP and '
            'rises along a cosine curve to 1 as the back turns square to it. '
            'A person is on the line when the straight line from the AP to '
            'the device passes through their body, taken as 0.5 m wide.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For walls and building materials rather than people, see RF '
            'Attenuation (RF: radio frequency) and Wi-Fi Through a Wall.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.rfAttenuation),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open RF Attenuation'),
              ),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.wifiThroughAWall),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Wi-Fi Through a Wall'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
