// Shared small pieces for the Wi-Fi Classroom tool What an Interferer Costs:
// the palette and the verdict helpers. Cards and section labels come from
// Rate vs Range's parts (RvrCard, RvrSectionLabel) so the Classroom tools
// read as one family. Used by both the stage and the controls, so neither
// imports the other.
//
// THEME: context.colors (dark §8 / light §8.20) plus IcPalette below.
// ASCII copy (GL-004).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/interferer_cost_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import 'adjacent_channel_parts.dart';

/// The two hues this tool draws with, the single home of its palette.
///
/// GL-003 §8.15.2: a teaching simulator may use extra hues from one family
/// when telling things apart by color is part of the lesson. The student must
/// tell the interferer's time on the air from your radio's. The stops are
/// Adjacent Channels' proven pair (lavender for the other transmitter, teal
/// for yours), measured there at 5.2:1 to 7.7:1 on surface2. Neither is a
/// §8.13 status hue, and every block is also labeled and patterned.
abstract final class IcPalette {
  /// The interferer.
  static Color source(AppColorScheme colors) => AciPalette.neighbor(colors);

  /// Your radio.
  static Color yours(AppColorScheme colors) => AciPalette.yours(colors);
}

/// A computed verdict: its word and its §8.13 status hue (the word always
/// travels with the hue).
typedef IcVerdict = ({String word, Color color, IconData icon});

/// What your radio does about [r].
IcVerdict icHeardVerdict(IcSourceResult r, AppColorScheme colors) =>
    switch (r.heard) {
      IcHeard.preamble => (
        word:
            'Your radio waits: a Wi-Fi preamble at or above '
            '${r.thresholdDbm.round()} dBm',
        color: colors.statusWarning,
        icon: Icons.pause_circle_outline,
      ),
      IcHeard.energy => (
        word: 'Your radio waits: energy at or above -62 dBm',
        color: colors.statusWarning,
        icon: Icons.pause_circle_outline,
      ),
      IcHeard.notHeard => (
        word: r.source.isWifi
            ? 'Not heard: under ${r.thresholdDbm.round()} dBm, your radio '
                  'sends into it'
            : 'Not heard: under -62 dBm, your radio sends into it',
        color: r.corruptionShare >= 0.1
            ? colors.statusDanger
            : colors.statusSuccess,
        icon: r.corruptionShare >= 0.1
            ? Icons.error_outline
            : Icons.check_circle_outline,
      ),
      IcHeard.absent => (
        word: 'Not on this band: nothing to wait for',
        color: colors.statusSuccess,
        icon: Icons.check_circle_outline,
      ),
    };

/// A verdict as an icon and its word.
class IcVerdictText extends StatelessWidget {
  const IcVerdictText(this.verdict, {super.key, this.style});

  final IcVerdict verdict;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final TextStyle base =
        style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
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
