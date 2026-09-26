// Small building blocks shared by BandSteeringStage and BandSteeringControls
// (Wi-Fi Classroom Band Steering): the band hues and swatch, a labeled
// slider, a switch row and a choice button. Theme tokens only. Kept local so
// this tool does not reach into a sibling's controls; the card and section
// title are Airtime Anatomy's, as the other Classroom tools use them.
//
// BAND HUES (GL-003 §8.15.2, Keith 2026-09-25): the two bands are told apart
// by color because the lesson is WHICH band the client is on. They are the
// same two members of the Wi-Fi Classroom family (lib/theme/
// wifi_lab_client_palette.dart, contrast measured there) that Multi-Link
// Operation uses: the pink for 2.4 GHz, the sky for 5 GHz, so a student reads
// both tools the same way. Color never carries the band alone: 2.4 GHz is
// drawn SOLID and 5 GHz DASHED, and every ring, line and gauge prints its
// band's name.
//
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/band_steering_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/wifi_lab_client_palette.dart';
import '../../../widgets/presenter/presenter_mode.dart';

/// Palette slot per band (Multi-Link Operation's choice).
int _slot(BsBand b) => switch (b) {
  BsBand.ghz24 => 8,
  BsBand.ghz5 => 5,
};

/// The band's hue in the current theme.
Color bsBandColor(BsBand b, AppColorScheme colors) =>
    WifiLabClientPalette.of(_slot(b), colors).hue;

/// True when the band is drawn dashed (5 GHz).
bool bsBandDashed(BsBand b) => b == BsBand.ghz5;

/// A short line in the band's hue and pattern, for legends.
class BsBandSwatch extends StatelessWidget {
  const BsBandSwatch({super.key, required this.band});

  final BsBand band;

  @override
  Widget build(BuildContext context) {
    final PresenterScale scale = PresenterMode.scaleOf(context);
    return CustomPaint(
      size: Size(28 * scale.marker, 10 * scale.marker),
      painter: _SwatchPainter(
        color: bsBandColor(band, context.colors),
        dashed: bsBandDashed(band),
        stroke: scale.strokeWidth(3),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter({
    required this.color,
    required this.dashed,
    required this.stroke,
  });

  final Color color;
  final bool dashed;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final double y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    final double dash = size.width / 5;
    for (double x = 0; x < size.width; x += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), p);
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color || old.dashed != dashed || old.stroke != stroke;
}

/// A labeled slider with its value on the right.
class BsSlider extends StatelessWidget {
  const BsSlider({
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
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool enabled = onChanged != null;
    final Widget valueWidget = Text(
      valueText,
      textAlign: TextAlign.right,
      style: mono.inlineCode.copyWith(
        color: enabled ? colors.textPrimary : colors.textDisabled,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: enabled ? colors.textSecondary : colors.textDisabled,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (PresenterMode.isActive(context))
                valueWidget
              else
                Flexible(child: valueWidget),
            ],
          ),
        ),
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

/// A switch with its title; the whole row toggles.
class BsSwitchRow extends StatelessWidget {
  const BsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        canRequestFocus: false,
        excludeFromSemantics: true,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable outlined button, filled when selected.
class BsChoiceButton extends StatelessWidget {
  const BsChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          backgroundColor: selected ? colors.primary : null,
          foregroundColor: selected ? colors.onPrimary : colors.textPrimary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
