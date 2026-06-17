// StatusChip, the reusable word + glyph + hue status indicator (GL-003 §8.13
// / §8.20.4, Iris's Analyze Results report visual spec §2).
//
// One verdict indicator, rendered as a Material status GLYPH + a verdict WORD +
// the status HUE, always all three together. This is §8.13 rule 2 / WCAG 2.2
// SC 1.4.1 made concrete: a colorblind user reads the same verdict from the
// word and the glyph alone, the hue only reinforces. Never color-only.
//
// THEME RESOLUTION (the one job this widget centralizes):
//   * Dark App Mode (§8.13 rule 3): glyph + word BOTH tinted the status hue on
//     the bare card surface. No filled pill in dark, status tokens tint
//     text/icons, never large fills.
//   * Light App Mode (§8.20.4 Style A): a solid status-hue FILL pill, with a
//     WHITE 700 word + WHITE glyph at pill radius (`--app-radius-pill`, 999px).
//     White-on-fill clears AA per §8.20.4.
//
// The chip composes existing tokens only (context.colors.status*, onPrimary's
// white sibling via Colors.white per §8.20.4's white-on-fill spec, the §4
// spacing scale, the §8.6 icon sizes). No new token is introduced.
//
// ZERO em-dashes in this file (engine/UI/strings/comments), per the standing
// Analyze Results rule.

import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The four verdict kinds the chip can carry, mapped 1:1 to the §8.13 status
/// hues and their sanctioned Material glyphs. `info` is NOT a severity: it is
/// the §6 honesty / "not measured" register and is used only where there is
/// genuinely no good / headsUp / issue verdict.
enum StatusChipKind {
  /// "Good" / "Strong" / "Secure", calm reassurance. `check_circle`, success.
  good,

  /// "Worth a look" / "Marginal" / "Slow", advisory, non-blocking. `warning`,
  /// warning hue (bronze on light, §8.20.1 hue-register shift).
  headsUp,

  /// "Issue" / "Weak" / "Fail", direct, never alarmist. `error`, danger hue.
  issue,

  /// "Not measured" / honesty context, info hue. `info`. Not a severity.
  info,
}

/// Resolves a [StatusChipKind] to its §8.13 sanctioned Material glyph.
extension StatusChipKindGlyph on StatusChipKind {
  IconData get glyph {
    switch (this) {
      case StatusChipKind.good:
        return Icons.check_circle;
      case StatusChipKind.headsUp:
        return Icons.warning;
      case StatusChipKind.issue:
        return Icons.error;
      case StatusChipKind.info:
        return Icons.info;
    }
  }

  /// Resolves the kind to its theme-aware status hue off the active scheme
  /// (§8.13 dark / §8.20.1 light, both AA-verified in GL-003).
  Color hue(AppColorScheme colors) {
    switch (this) {
      case StatusChipKind.good:
        return colors.statusSuccess;
      case StatusChipKind.headsUp:
        return colors.statusWarning;
      case StatusChipKind.issue:
        return colors.statusDanger;
      case StatusChipKind.info:
        return colors.statusInfo;
    }
  }
}

/// A single calm verdict chip: `[glyph] WORD`, glyph leading, the §8.13 hue.
///
/// Renders the §2.3 dark-tint treatment under the dark theme and the §8.20.4
/// solid-fill pill under the light theme, resolving off `context.colors`. The
/// caller supplies the [kind] (which fixes glyph + hue) and the verdict [word]
/// (the plain-language label, never color-only). The chip is decorative at the
/// Semantics layer: the parent finding card owns the spoken label, so the chip
/// excludes itself from semantics to avoid a double read.
class StatusChip extends StatelessWidget {
  /// Creates a status chip. [word] is the verdict word shown beside the glyph.
  const StatusChip({required this.kind, required this.word, super.key});

  /// The verdict kind: fixes the glyph and the status hue.
  final StatusChipKind kind;

  /// The plain-language verdict word (e.g. "Good", "Worth a look", "Issue",
  /// "Not measured"). Always present so the verdict never reads as color-only.
  final String word;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color hue = kind.hue(colors);

    // §8.6: glyph at `--app-icon-sm` (16px) so the chip stays compact and reads
    // as a dense badge beside the word.
    const double glyphSize = 16;

    if (colors.isLight) {
      // §8.20.4 Style A, solid status-hue fill pill, white glyph + white 700
      // word. White-on-fill is AA-verified per §8.20.4; no border required.
      return ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: hue,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(kind.glyph, size: glyphSize, color: Colors.white),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                word,
                style: (text.labelMedium ?? const TextStyle()).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // §8.13 rule 3, DARK: glyph + word BOTH tinted the status hue on the bare
    // card surface. No filled pill in dark; status tokens tint text/icons.
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(kind.glyph, size: glyphSize, color: hue),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            word,
            style: (text.labelMedium ?? const TextStyle()).copyWith(
              color: hue,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
