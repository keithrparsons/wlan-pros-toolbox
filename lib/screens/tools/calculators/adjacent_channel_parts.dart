// Shared small pieces for the Wi-Fi Classroom Adjacent Channels and AP
// Stacking tool: the two-hue palette and the verdict helpers. Cards, section
// labels and notes come from Rate vs Range's parts (RvrCard, RvrSectionLabel,
// RvrNote) so the Classroom tools read as one family. Used by both the stage
// and the controls, so neither imports the other.
//
// THEME: context.colors (dark §8 / light §8.20) plus AciPalette below.
// ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/adjacent_channel_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// The two transmitters' hues, the single home of this tool's palette.
///
/// GL-003 §8.15.2 (Keith, 2026-09-25): a teaching simulator may use extra
/// hues from one family when telling categories apart by color is the lesson.
/// Here the student must see whose energy is whose inside one channel: the
/// neighbor's skirt reaching into yours. The stops are the lavender and teal
/// already proven in this family (RvrPalette, PsdPalette), each measured at
/// 5.2:1 to 7.7:1 on surface2, over the 3:1 floor for graphics. Neither is a
/// §8.13 status hue, and every curve is also labeled with its channel.
abstract final class AciPalette {
  /// The neighbor transmitter and its leakage.
  static Color neighbor(AppColorScheme colors) =>
      colors.isLight ? const Color(0xFF6B48B8) : const Color(0xFFB89AF0);

  /// Your channel and the wanted signal.
  static Color yours(AppColorScheme colors) =>
      colors.isLight ? const Color(0xFF0F7A73) : const Color(0xFF4CC9C0);
}

/// A computed verdict: its word and its §8.13 status hue (the word always
/// travels with the hue).
typedef AciVerdict = ({String word, Color color, IconData icon});

/// The link verdict: what the neighbor costs.
AciVerdict linkVerdict(AciResult r, AppColorScheme colors) {
  if (r.mcsWithout == null) {
    return (
      word: 'No link even without the neighbor',
      color: colors.statusDanger,
      icon: Icons.error_outline,
    );
  }
  if (r.mcsWith == null) {
    return (
      word: 'Link lost',
      color: colors.statusDanger,
      icon: Icons.error_outline,
    );
  }
  if (r.mcsWith! < r.mcsWithout!) {
    final int steps = r.mcsWithout! - r.mcsWith!;
    return (
      word: 'Down $steps MCS ${steps == 1 ? 'step' : 'steps'}',
      color: colors.statusWarning,
      icon: Icons.warning_amber_rounded,
    );
  }
  return (
    word: 'No rate lost',
    color: colors.statusSuccess,
    icon: Icons.check_circle_outline,
  );
}

/// The energy-detect verdict.
AciVerdict ccaVerdict(AciResult r, AppColorScheme colors) => r.ccaBusy
    ? (
        word: 'Busy: your radio waits',
        color: colors.statusWarning,
        icon: Icons.warning_amber_rounded,
      )
    : (
        word: 'Clear',
        color: colors.statusSuccess,
        icon: Icons.check_circle_outline,
      );

/// A verdict as an icon and its word.
class AciVerdictText extends StatelessWidget {
  const AciVerdictText(this.verdict, {super.key, this.style});

  final AciVerdict verdict;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final TextStyle base =
        style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          verdict.icon,
          size: (base.fontSize ?? AppTextSize.body) * 1.1,
          color: verdict.color,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(
          child: Text(
            verdict.word,
            style: base.copyWith(
              color: verdict.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
