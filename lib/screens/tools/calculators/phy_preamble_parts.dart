// Small building blocks shared by PhyPreambleStage and PhyPreambleControls
// (Wi-Fi Classroom PHY Preamble Reference). Same card, label, row, slider header and switch
// idiom as the other Wi-Fi Classroom simulators, kept local so this tool does not
// reach into a sibling's private parts. Theme tokens only.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'calc_parts.dart';

/// A surface-1 card with the calculator border and padding.
typedef PpCard = CalcCard;

/// Section heading inside a card.
typedef PpSectionLabel = CalcSectionLabel;

/// Label on the left, DM Mono value on the right.
typedef PpRow = CalcRow;

/// Icon plus a small explanatory sentence.
typedef PpNote = CalcIconNote;

/// A label with its current value on the right, above a slider.
class PpSliderHeader extends StatelessWidget {
  const PpSliderHeader({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(child: PpSectionLabel(label)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            value,
            style: mono.inlineCode.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// A labelled slider: header, then a themed Slider whose screen-reader value
/// is worded.
class PpSlider extends StatelessWidget {
  const PpSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.semanticValue,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// Null disables the slider.
  final ValueChanged<double>? onChanged;
  final String Function(double v) semanticValue;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PpSliderHeader(label: label, value: valueText),
        Semantics(
          label: label,
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: colors.primary,
            inactiveColor: colors.disabledFill,
            semanticFormatterCallback: semanticValue,
          ),
        ),
      ],
    );
  }
}

/// An outlined button in the calculator style (Back, Step, Reset, Show all).
typedef PpOutlineButton = CalcOutlineButton;
