// Controls and explainer for How to Measure Wall Attenuation (measure-wall).
//
// MeasureWallControls: the geometry (preset scenes, source distance, which
// side the laptop is on, and each reading's distance from the wall), the wall
// (band, which locks the channel; material and thickness from Wi-Fi Through
// a Wall's ITU-R P.2040 list), and the readings (how many per side, and the
// fading spread, labeled illustrative). MeasureWallExplainer: Keith's method,
// why the source goes far away, the formula, and what the tool leaves out.
// Neither knows about the stage.
//
// PRESENTER: the explanatory prose drops, and the readings settings fold
// behind a disclosure so the panel fits a projector without scrolling.
//
// THEME: context.colors only. ASCII copy, no em dashes (GL-004).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/channel_frequency_data.dart';
import '../../../router/app_router.dart';
import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../units/length_format.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'measure_wall_controller.dart';
import 'measure_wall_format.dart';
import 'wifi_through_a_wall_parts.dart'
    show WallCard, WallSectionLabel, kWallMinMm, kWallMaxMm;

/// Labels that name an illustrative value. The tests find each on screen.
abstract final class MwLabels {
  static const String readingsSection = 'Readings (illustrative spread)';
  static const String spread =
      'Fading spread, standard deviation '
      '(illustrative)';
}

class MeasureWallControls extends StatelessWidget {
  const MeasureWallControls({super.key, required this.controller});
  final MeasureWallController controller;

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

  static double _log10(double v) => math.log(v) / math.ln10;

  List<Widget> _children(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final MeasureWallController k = controller;
    final MwConfig c = k.config;
    final MwFormat f = MwFormat(k.units);
    final LengthFormat lf = LengthFormat(k.units);
    final bool prose = !PresenterMode.isActive(context);
    TextStyle small() => text.bodySmall!.copyWith(color: colors.textTertiary);

    // Thickness on the wall tool's log scale, 1 to 100 cm, snapped to what
    // the readout prints.
    final double logMin = _log10(kWallMinMm), logMax = _log10(kWallMaxMm);
    double toSlider(double m) =>
        ((_log10(m * 1000) - logMin) / (logMax - logMin)).clamp(0.0, 1.0);
    double fromSlider(double p) =>
        lf
            .snapMm(math.pow(10, logMin + p * (logMax - logMin)).toDouble())
            .clamp(kWallMinMm, kWallMaxMm) /
        1000;

    final List<Widget> readings = <Widget>[
      _slider(
        context,
        label: 'Readings per side',
        valueText: '${c.samplesPerSide}',
        value: c.samplesPerSide.toDouble(),
        min: MwConfig.minSamples.toDouble(),
        max: MwConfig.maxSamples.toDouble(),
        onChanged: (double v) => k.setSamples(v.round()),
        semantic: (double v) => '${v.round()} readings per side',
      ),
      _slider(
        context,
        label: MwLabels.spread,
        valueText: MwFormat.db(c.spreadDb),
        value: c.spreadDb,
        min: 0,
        max: MwConfig.maxSpreadDb,
        onChanged: (double v) => k.setSpread((v * 2).round() / 2),
        semantic: (double v) =>
            'Fading spread, illustrative, ${MwFormat.n(v)} dB',
      ),
    ];

    return <Widget>[
      const WallSectionLabel('Scenes'),
      const SizedBox(height: AppSpacing.xxs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xxs,
        children: <Widget>[
          for (final MwPreset p in MwPreset.values)
            if (p != MwPreset.predict) _presetButton(context, p, f),
        ],
      ),
      if (prose)
        Text(
          'Each scene sets the source and both readings; the wall and the '
          'readings stay as they are.',
          style: small(),
        ),
      SizedBox(height: prose ? AppSpacing.sm : AppSpacing.xs),
      const WallSectionLabel('Source and laptop'),
      _slider(
        context,
        label: prose ? 'Source to wall' : 'Source to wall (Up, Down)',
        valueText: f.dist(c.sourceToWallM),
        value: c.sourceToWallM,
        min: MwConfig.minSourceM,
        max: MwConfig.maxSourceM,
        onChanged: (double v) => k.setSourceToWall((v * 10).round() / 10),
        semantic: (double v) => 'Source to wall, ${f.distSpoken(v)}',
      ),
      const SizedBox(height: AppSpacing.xs),
      AppToggle<MwSide>(
        label: prose ? 'Laptop on the' : 'Laptop on the (S)',
        value: c.side,
        expand: true,
        items: const <AppToggleItem<MwSide>>[
          (MwSide.near, 'Near side'),
          (MwSide.far, 'Far side'),
        ],
        onChanged: k.setSide,
      ),
      _slider(
        context,
        label: 'Near reading, in front of the wall',
        valueText: f.gap(c.nearGapM),
        value: c.nearGapM,
        min: MwConfig.minGapM,
        max: MwConfig.maxNearGap(c.sourceToWallM),
        onChanged: (double v) => k.setNearGap((v * 100).round() / 100),
        semantic: (double v) =>
            'Near reading, ${f.gapSpoken(v)} in front of the wall',
      ),
      _slider(
        context,
        label: 'Far reading, behind the wall',
        valueText: f.gap(c.farGapM),
        value: c.farGapM,
        min: MwConfig.minGapM,
        max: MwConfig.maxFarGapM,
        onChanged: (double v) => k.setFarGap((v * 100).round() / 100),
        semantic: (double v) =>
            'Far reading, ${f.gapSpoken(v)} behind the wall',
      ),
      if (prose)
        Text(
          'The near reading stays at least ${f.gap(MwConfig.minFromSourceM)} '
          'from the source: the free-space formula has no meaning at the '
          'source itself.',
          style: small(),
        ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      const WallSectionLabel('The wall (from Wi-Fi Through a Wall)'),
      const SizedBox(height: AppSpacing.xxs),
      AppToggle<WifiBand>(
        label: 'Band',
        value: c.band,
        expand: true,
        items: <AppToggleItem<WifiBand>>[
          for (final WifiBand b in WifiBand.values) (b, b.label),
        ],
        onChanged: k.setBand,
      ),
      if (prose)
        Text(
          'The laptop is locked to channel ${c.channel} (${c.freqMHz} MHz) '
          'for both series, so every reading is of the same signal.',
          style: small(),
        ),
      const SizedBox(height: AppSpacing.xs),
      LabeledField(
        label: 'Material (ITU-R P.2040 Table 3)',
        semanticLabel: 'Material',
        field: AppSelect<WallMaterial>(
          value: c.material,
          semanticLabel: 'Material',
          items: <AppSelectItem<WallMaterial>>[
            for (final WallMaterial m in WallMaterial.values) (m, m.label),
          ],
          onChanged: k.setMaterial,
        ),
      ),
      _slider(
        context,
        label: 'Thickness',
        valueText: f.thickness(c.thicknessM),
        value: toSlider(c.thicknessM),
        min: 0,
        max: 1,
        onChanged: (double v) => k.setThicknessM(fromSlider(v)),
        semantic: (double v) => 'Thickness ${lf.smallSpoken(fromSlider(v))}',
      ),
      SizedBox(height: prose ? AppSpacing.md : AppSpacing.xs),
      if (prose) ...<Widget>[
        const WallSectionLabel(MwLabels.readingsSection),
        ...readings,
        Text(
          'Each reading is the model level plus a random draw with this '
          'standard deviation. The value is illustrative, not measured. Set '
          'it to 0 to see the geometry error alone.',
          style: small(),
        ),
      ] else
        PresenterDisclosure(
          title: MwLabels.readingsSection,
          children: readings,
        ),
    ];
  }

  Widget _presetButton(BuildContext context, MwPreset p, MwFormat f) {
    final bool on = controller.activePreset == p;
    final String label =
        '${p.title}: source ${f.dist(p.sourceToWallM)}, readings '
        '${f.gap(p.gapM)} from the wall';
    // The projector panel has no room for the long form; the stage shows
    // the distances.
    final String shown = PresenterMode.isActive(context) ? p.title : label;
    return Semantics(
      selected: on,
      button: true,
      excludeSemantics: true,
      label: label,
      child: OutlinedButton.icon(
        onPressed: on ? null : () => controller.applyPreset(p),
        icon: Icon(on ? Icons.check : Icons.straighten, size: 18),
        label: Text(shown),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
        ),
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double>? onChanged,
    required String Function(double) semantic,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool enabled = onChanged != null && max > min;
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
          value: value.clamp(min, math.max(min, max)),
          min: min,
          max: math.max(min + 1e-6, max),
          onChanged: enabled ? onChanged : null,
          activeColor: colors.primary,
          inactiveColor: colors.disabledFill,
          semanticFormatterCallback: semantic,
        ),
      ],
    );
  }
}

// ── Explainer ─────────────────────────────────────────────────────────────

class MeasureWallExplainer extends StatelessWidget {
  const MeasureWallExplainer({super.key});

  /// The method, in order, with lengths in the unit on screen.
  static List<String> steps(MwFormat f) => <String>[
    '1. Use a measuring device you can lock to one channel, so every '
        'reading is of the same signal.',
    '2. Place something that makes RF (radio frequency), such as a hotspot '
        'or a small AP (access point), ${f.dist(4)} or more from the wall '
        'under test.',
    '3. Take a series of readings close to the near side of the wall and '
        'average them.',
    '4. Move to the far side, close to the wall, take a series there and '
        'average them.',
    '5. The difference of the two averages is the wall attenuation.',
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
    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('The method'),
          const SizedBox(height: AppSpacing.xs),
          for (final String s in steps(
            MwFormat(UnitSystemScope.systemOf(context)),
          )) ...<Widget>[
            Text(s, style: body()),
            const SizedBox(height: AppSpacing.xxs),
          ],
          const SizedBox(height: AppSpacing.xs),
          const WallSectionLabel('Why the source goes far away'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The far reading is farther from the source than the near one, '
            'so it carries more free-space path loss (FSPL) as well as the '
            'wall. Close to the source the free-space curve is steep, and '
            'that extra loss is large. With the source far away and both '
            'readings close to the wall, the two spots sit at almost the '
            'same distance, and the difference is almost all wall.',
            style: body(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Measured = wall loss + 20 log10(far / near) + fading left over',
            style: formula(),
          ),
          Text('near = source to wall - near gap', style: formula()),
          Text(
            'far = source to wall + wall thickness + far gap',
            style: formula(),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The error term does not depend on the channel: the frequency '
            'part of FSPL is the same at both spots and cancels. The source '
            'radiates 20 dBm, both antennas are 0 dBi (decibels over an '
            'isotropic antenna), and the laptop reads nothing below a -95 '
            'dBm noise floor. The wall is Wi-Fi Through a Wall\'s ITU-R '
            'P.2040 model, head on.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Left out: the reflection off the near face of the wall, which '
            'makes readings close to it rise and fall over a short '
            'distance; paths around the wall through doors and other '
            'rooms; and the laptop\'s own body and antenna pattern. Several '
            'readings over a small area, averaged, are how a field '
            'measurement handles the first.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.wifiThroughAWall),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Wi-Fi Through a Wall'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(
                  context,
                ).pushNamed(AppRouter.predictThenMeasure),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Predict, Then Measure'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
