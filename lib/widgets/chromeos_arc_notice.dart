// ChromeOsArcNotice — the one explanatory surface for the ChromeOS honest-null
// suppressions.
//
// Per Keith (2026-07-10): "Explain, don't just hide." A field that vanishes with
// no reason reads as a broken tool; a field that vanishes with a plain-English
// reason reads as an honest one. This card is that reason, rendered once at the
// top of every screen whose data ChromeOS's ARC virtual machine taints.
//
// It is deliberately NOT an error affordance. Nothing has failed — the platform
// simply cannot supply these values truthfully, exactly as Windows cannot supply
// a noise floor. So it uses the informational status token (§8.13
// `statusInfo` / `statusInfoFill`), the same band the reference screens use for
// a neutral fact, never the danger/warning tokens.
//
// A11y (GL-003 §8.13 rule 2, WCAG 2.2 SC 1.4.1): the meaning is carried by the
// WORDS ("Some fields are hidden on ChromeOS"), never by color alone. The icon is
// decorative and excluded from the semantics tree; the whole card is merged into
// one semantics node so a screen reader announces headline → body → what is
// still true, in that order, as a single coherent statement rather than three
// orphaned fragments.
//
// All copy lives in [ChromeOsArc] (SSOT), never inline here — the same wording
// has to appear in the per-tool help, and two copies would drift.

import 'package:flutter/material.dart';

import '../services/network/chromeos_arc.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The ChromeOS / ARC-VM explanation band. Renders nothing at all when the app
/// is not on ChromeOS, so a caller can drop it into any screen unconditionally.
class ChromeOsArcNotice extends StatelessWidget {
  const ChromeOsArcNotice({
    super.key,
    this.stillTrue,
    this.isChromeOsOverride,
  });

  /// The optional "what you CAN still trust here" line, which differs per screen
  /// (see [ChromeOsArc.stillTrueWifi] / [ChromeOsArc.stillTrueConnection] /
  /// [ChromeOsArc.stillTrueInterface]). Omitted when null.
  final String? stillTrue;

  /// Test-only override of the platform verdict, so a widget test can render the
  /// ChromeOS state without a platform channel. Null (production) reads the real
  /// cached [ChromeOsArc.isChromeOs].
  final bool? isChromeOsOverride;

  bool get _isChromeOs => isChromeOsOverride ?? ChromeOsArc.isChromeOs;

  @override
  Widget build(BuildContext context) {
    // Not on ChromeOS → this card does not exist. No empty box, no zero-height
    // padding artifact in the parent's Column.
    if (!_isChromeOs) return const SizedBox.shrink();

    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      // One node, read in order. Without this the reader announces the icon and
      // three disconnected paragraphs.
      label: '${ChromeOsArc.noticeHeadline}. ${ChromeOsArc.noticeBody}'
          '${stillTrue != null ? ' $stillTrue' : ''}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.statusInfoFill,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.statusInfo, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline, size: 20, color: colors.statusInfo),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    ChromeOsArc.noticeHeadline,
                    style: text.titleSmall?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ChromeOsArc.noticeBody,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (stillTrue != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      stillTrue!,
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
