// ReferenceCallout — the shared "pull one load-bearing rule out of the body
// text" primitive for the reference screens.
//
// WHY THIS EXISTS: the callout idiom (a surface-1 card with a status-hue accent
// rail down the left edge and a tone-tinted heading) was authored privately
// inside screw_drives_screen.dart and then wanted verbatim by the next two
// "decode the markings" pages (Batteries, SD Cards). Copying a third and fourth
// copy is how a pattern forks. This is the same widget, factored out, plus one
// addition the safety content needs: a `danger` tone.
//
// GL-003 section 8.13 rules honored:
//   * The status hues are VERDICT colors, used here to rank the severity of a
//     rule (danger = a safety fact, warning = a rule that costs you money or a
//     stripped head, info = a neutral clarification). Lime `primary` stays the
//     interactive / computed accent and is never used as a callout tone.
//   * NEVER color alone (SC 1.4.1). Every callout carries a heading WORD, and
//     the heading is what a colorblind or screen-reader user reads. The hue only
//     reinforces it.
//   * The BODY stays at `textPrimary`, so the sentence a reader actually needs
//     is at full contrast rather than tinted down to a status hue.
//
// Accessibility: the whole callout is one Semantics node labeled
// "<heading>. <body>", so a screen reader announces the rule as a single
// coherent statement instead of two disconnected fragments.
//
// Glyph rules (GL-004): no em dash, no en dash in any string this file renders;
// the strings themselves come from the calling screen's data file.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// Severity of a [ReferenceCallout], mapped to the GL-003 section 8.13 status
/// palette. Always paired with a heading word, never color alone.
enum ReferenceCalloutTone {
  /// A safety fact where getting it wrong causes harm. Use sparingly.
  danger,

  /// A rule that costs field time, money, or accuracy when ignored.
  warning,

  /// A neutral clarification or a myth debunk. Not a severity.
  info,
}

/// Resolves a tone to its GL-003 section 8.13 hue in the active theme.
extension ReferenceCalloutToneColor on ReferenceCalloutTone {
  /// The status hue for this tone in [colors]. Both App Modes are covered,
  /// because the lookup goes through the theme extension rather than a literal.
  Color color(AppColorScheme colors) => switch (this) {
        ReferenceCalloutTone.danger => colors.statusDanger,
        ReferenceCalloutTone.warning => colors.statusWarning,
        ReferenceCalloutTone.info => colors.statusInfo,
      };
}

/// A bordered callout that pulls one load-bearing rule out of the body text.
/// The left accent rail and the heading take the tone hue; the body reads at
/// primary ink so it stays full-contrast.
class ReferenceCallout extends StatelessWidget {
  const ReferenceCallout({
    super.key,
    required this.tone,
    required this.heading,
    required this.body,
  });

  /// Severity, which selects the accent hue. Never the only carrier of meaning.
  final ReferenceCalloutTone tone;

  /// The rule in a few words. This is what an assistive-technology user hears
  /// first, and what a colorblind user reads instead of the hue.
  final String heading;

  /// The rule in full.
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color toneColor = tone.color(colors);
    return Semantics(
      container: true,
      label: '$heading. $body',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        // IntrinsicHeight bounds the Row's height so the stretch-rail child gets
        // a finite height. Without it, the Row sits in a SingleChildScrollView
        // Column with unbounded vertical constraints and the zero-intrinsic-
        // height accent rail cannot stretch, which is what threw the
        // "RenderBox was not laid out: hasSize" failure at 320pt on the Screw
        // Drives page this widget is factored out of.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                width: AppSpacing.xxs,
                decoration: BoxDecoration(
                  color: toneColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.card),
                    bottomLeft: Radius.circular(AppRadius.card),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        heading,
                        style: text.labelLarge?.copyWith(
                          color: toneColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        body,
                        style: text.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
