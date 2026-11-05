// Small building blocks shared by EapLadderStage and EapLadderControls
// (Wi-Fi Classroom 802.1X and EAP Ladder). Same card, label, row, slider header and switch
// idiom as the other Wi-Fi Classroom simulators, kept local so this tool does not
// reach into a sibling's private parts. Theme tokens only.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'calc_parts.dart';

/// A surface-1 card with the calculator border and padding.
typedef ElCard = CalcCard;

/// Text that wraps only between words. When the widest single word (or
/// hyphen-ended part, like "4-") is wider than the space it has, the text
/// scales down until that word fits, so a narrow phone never breaks
/// "Deauthentication" inside the word (Keith, 2026-09-29, at 390 px). At
/// widths where every word fits, it is a plain [Text] in [style].
class ElWholeWordText extends StatelessWidget {
  const ElWholeWordText(this.data, {super.key, this.style, this.textAlign});

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  static final RegExp _words = RegExp(r'[^\s-]+-?');

  /// Head room under the measured fit: glyph widths do not scale exactly
  /// linearly with the font size.
  static const double _margin = 0.98;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final TextStyle base = DefaultTextStyle.of(context).style.merge(style);
        final double? size = base.fontSize;
        double factor = 1;
        if (box.hasBoundedWidth && size != null) {
          final TextScaler scaler = MediaQuery.textScalerOf(context);
          final TextDirection dir = Directionality.of(context);
          double widest = 0;
          for (final RegExpMatch m in _words.allMatches(data)) {
            final TextPainter tp = TextPainter(
              text: TextSpan(text: m[0], style: base),
              textDirection: dir,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            widest = math.max(widest, tp.width);
            tp.dispose();
          }
          if (widest > box.maxWidth && widest > 0) {
            factor = box.maxWidth / widest * _margin;
          }
        }
        return Text(
          data,
          textAlign: textAlign,
          style: factor == 1
              ? style
              : (style ?? const TextStyle()).copyWith(
                  fontSize: size! * factor,
                  letterSpacing: base.letterSpacing == null
                      ? null
                      : base.letterSpacing! * factor,
                ),
        );
      },
    );
  }
}

/// Section heading inside a card.
typedef ElSectionLabel = CalcSectionLabel;

/// Label on the left, DM Mono value on the right.
typedef ElRow = CalcRow;

/// Icon plus a small explanatory sentence.
typedef ElNote = CalcIconNote;

/// A label with its current value on the right, above a slider.
class ElSliderHeader extends StatelessWidget {
  const ElSliderHeader({super.key, required this.label, required this.value});

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
          Expanded(child: ElSectionLabel(label)),
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
class ElSlider extends StatelessWidget {
  const ElSlider({
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
        ElSliderHeader(label: label, value: valueText),
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
typedef ElOutlineButton = CalcOutlineButton;
