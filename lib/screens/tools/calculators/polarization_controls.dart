// Controls for the Wi-Fi Classroom "Polarization" tool (polarization): the
// preset, the components switch, and the Adjust fold (H amplitude, V
// amplitude, phase difference). They write PolarizationController and never
// draw, so a presenter layout can put them beside PolarizationStage.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/polarization_model.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/presenter/presenter_disclosure.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import '../labeled_field.dart';
import 'antenna_pattern_parts.dart';
import 'polarization_controller.dart';
import 'polarization_parts.dart';

/// A sentence for each preset: what to watch for.
String polarizationBlurb(PolarizationPreset p) => switch (p) {
  PolarizationPreset.vertical =>
    'The field goes up and down only. The horizontal part is zero.',
  PolarizationPreset.horizontal =>
    'The same wave turned 90°: the field goes side to side only.',
  PolarizationPreset.slant45 =>
    'Equal horizontal and vertical parts, in step. They add to a line at 45°.',
  PolarizationPreset.circular =>
    'Equal parts a quarter cycle apart. The field never shrinks; it turns '
        'round the axis, one full turn per wavelength.',
  PolarizationPreset.elliptical =>
    'Unequal parts a quarter cycle apart. The field turns and stretches: '
        'twice as long one way as the other.',
  PolarizationPreset.custom =>
    'Your own mix. In step (0° or 180°) is always a line; anything else '
        'turns.',
};

class PolarizationControls extends StatelessWidget {
  const PolarizationControls({super.key, required this.controller});
  final PolarizationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final bool presenting = PresenterMode.isActive(context);
        final PolarizationController c = controller;
        final PolarizationState s = c.state;
        final List<Widget> adjust = <Widget>[
          PatternSlider(
            label: 'H amplitude (horizontal part)',
            valueText: fmtAmp(s.ax),
            value: s.ax,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (double v) => c.setField(s.copyWith(ax: v)),
            semanticValue: (double v) => v.toStringAsFixed(2),
          ),
          PatternSlider(
            label: 'V amplitude (vertical part)',
            valueText: fmtAmp(s.ay),
            value: s.ay,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (double v) => c.setField(s.copyWith(ay: v)),
            semanticValue: (double v) => v.toStringAsFixed(2),
          ),
          PatternSlider(
            label: 'Phase difference, V ahead of H',
            valueText: fmtPhase(s.deltaDeg),
            value: s.deltaDeg,
            min: -180,
            max: 180,
            divisions: 24,
            onChanged: (double v) =>
                c.setField(s.copyWith(deltaDeg: v.roundToDouble())),
            semanticValue: (double v) => '${v.round()} degrees',
          ),
          if (!presenting)
            const PatternCaption(
              'A preset picks these for you. The presets all carry the same '
              'power; the sliders do not hold it, so a Custom wave can be '
              'weaker or stronger.',
            ),
        ];
        return PatternCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PatternSectionLabel('Polarization'),
              const SizedBox(height: AppSpacing.xs),
              LabeledField(
                label: 'Preset',
                field: AppSelect<PolarizationPreset>(
                  value: c.preset,
                  semanticLabel: 'Polarization',
                  items: <AppSelectItem<PolarizationPreset>>[
                    for (final PolarizationPreset p
                        in PolarizationPreset.named)
                      (p, p.label),
                    if (c.preset == PolarizationPreset.custom)
                      (PolarizationPreset.custom, 'Custom'),
                  ],
                  onChanged: c.setPreset,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              PatternCaption(polarizationBlurb(c.preset)),
              const SizedBox(height: AppSpacing.xs),
              PolSwitchRow(
                title: 'Show the H and V component waves',
                value: c.showComponents,
                onChanged: c.setShowComponents,
              ),
              PresenterDisclosure(
                title: 'Adjust: amplitudes and phase difference',
                initiallyOpen: c.preset == PolarizationPreset.custom,
                children: adjust,
              ),
            ],
          ),
        );
      },
    );
  }
}
