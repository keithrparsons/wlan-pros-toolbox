// TriageLadderCard, the "Where it looks off" ladder on Check My Connection and
// Analyze Results (Keith, 2026-11-13, approach B).
//
// Each rung is a name plus a [StatusChip] (glyph + WORD + hue, always all three,
// WCAG 2.2 SC 1.4.1). No logic lives here: every status, reason and sentence comes
// from the pure [TriageLadder]. The card only lays it out.
//
// LAYOUT. Name and chip sit in a [Wrap] with spaceBetween, so on a normal phone
// the chip is right-aligned beside the name, and when the pair does not fit (320
// px, or 2x text, or "Can't check on this device") the chip drops to its own line
// instead of overflowing.
//
// Tokens only: surface1, border, textPrimary / textSecondary / textTertiary, the
// §4 spacing scale and card radius. ZERO em dashes.

import 'package:flutter/material.dart';

import '../services/network/analyze/triage_ladder.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import 'status_chip.dart';

class TriageLadderCard extends StatelessWidget {
  const TriageLadderCard({
    required this.ladder,
    this.showReasons = false,
    super.key,
  });

  final TriageLadder ladder;

  /// Analyze shows each rung's reason and the caption; Check My Connection keeps
  /// one line per rung.
  final bool showReasons;

  @override
  Widget build(BuildContext context) {
    if (ladder.isEmpty) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Where it looks off',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          for (final TriageRung rung in ladder.rungs) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _RungRow(rung: rung, showReason: showReasons),
          ],
          if (ladder.summary != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                ladder.summary!,
                style: text.bodyMedium?.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
          if (showReasons) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This uses the check you just ran. Looks fine means this device '
              'could see it working, not a guarantee.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _RungRow extends StatelessWidget {
  const _RungRow({required this.rung, required this.showReason});

  final TriageRung rung;
  final bool showReason;

  static StatusChipKind _kind(TriageStatus s) {
    switch (s) {
      case TriageStatus.looksFine:
        return StatusChipKind.good;
      case TriageStatus.looksOff:
        return StatusChipKind.issue;
      case TriageStatus.notChecked:
      case TriageStatus.notOnWifi:
      case TriageStatus.cantCheck:
      case TriageStatus.checking:
        return StatusChipKind.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String? reason = showReason ? rung.reason : null;

    return Semantics(
      container: true,
      label:
          '${rung.name}, ${rung.status.word}.'
          '${reason == null ? '' : ' $reason'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                Text(
                  rung.name,
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
                StatusChip(kind: _kind(rung.status), word: rung.status.word),
              ],
            ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  reason,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
