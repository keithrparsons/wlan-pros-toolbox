// The shared failure marker for the Wi-Fi Classroom ladders (spec 42).
//
// "The exchange stops here." Three marks, used by the 802.1X and EAP Ladder
// (eap_ladder_stage.dart, Break it) and by Association, Frame by Frame
// (eap_ladder_jr_stage.dart, feature 1 of the 2026-09-29 plan):
//
//   - a failure mark: an X in a circle at the end of the arrow that carries
//     the failure or was refused (LadderMessage.failure, JrMessage.failure);
//   - a lost arrow: dashed, stopping [kLostReach] of the way across, with a
//     clock at its end (LadderMessage.lost, JrMessage.lost): sent, never
//     answered;
//   - a "Stopped here" band after the last message, in place of the
//     milestones the exchange never reached.
//
// COLOR (GL-003 §8.13). The status danger hue is a verdict here (this
// exchange failed), so it tints only the X, the band's icon and the band's
// border, never an arrow, a label or a fill. It never stands alone: the X
// and block icons carry the shape, and the band, the caption and every
// screen-reader label say it in words (§8.13 rule 2, WCAG 1.4.1). The lost
// arrow's clock is neutral: silence is not a verdict until the band says so.
// Measured §8.12: dark #F26E6E on surface1 5.48:1, on surface2 about 5.0:1;
// light #C62D2D 5.4:1 on white.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter.dart';

/// How far a lost arrow reaches toward its target before it stops.
const double kLostReach = 0.62;

/// Where the failure mark sits on a row: the center of the arrow's end.
const IconData kFailureIcon = Icons.cancel_rounded;

/// The "no answer" clock at the end of a lost arrow.
const IconData kLostIcon = Icons.schedule_rounded;

/// The icon at the head of the "Stopped here" band.
const IconData kStoppedIcon = Icons.block_rounded;

/// The failure mark: an X in a circle, in the status danger hue. Decorative
/// for screen readers; the row's label says "failed here".
class LadderFailureMark extends StatelessWidget {
  const LadderFailureMark({super.key, this.size = 16});

  /// Unscaled size; the presenter scale is applied here.
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double s = PresenterMode.scaleOf(context).markerSize(size);
    return ExcludeSemantics(
      child: DecoratedBox(
        // A card-colored disc behind the X so the lane line does not run
        // through it.
        decoration: BoxDecoration(
          color: colors.surface1,
          shape: BoxShape.circle,
        ),
        child: Icon(kFailureIcon, size: s, color: colors.statusDanger),
      ),
    );
  }
}

/// The end of a lost arrow: a clock and "no answer". Neutral ink.
class LadderLostMark extends StatelessWidget {
  const LadderLostMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final double s = PresenterMode.scaleOf(context).markerSize(size);
    return ExcludeSemantics(
      child: ColoredBox(
        color: colors.surface1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(kLostIcon, size: s, color: colors.textSecondary),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'no answer',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Places the failure or lost mark on a message row whose arrow runs
/// [fromX] to [toX] in a band [band] high at the bottom of a row [rowWidth]
/// wide. The failure mark centers on the arrow's end; the lost mark starts
/// just past the gap where the lost arrow stops, on the far side of the gap.
Widget positionedLadderMark({
  required bool lost,
  required double fromX,
  required double toX,
  required double rowWidth,
  required double band,
  required double iconSize,
  required Widget child,
}) {
  final double bottom = (band - iconSize) / 2;
  if (!lost) {
    return Positioned(
      left: toX - iconSize / 2,
      bottom: bottom,
      width: iconSize,
      height: iconSize,
      child: child,
    );
  }
  final double endX = fromX + (toX - fromX) * kLostReach;
  const double gap = AppSpacing.xxs;
  // Bounded between the gap and the row's edge, and scaled down rather than
  // run past it on a narrow phone.
  final bool rightward = toX >= fromX;
  return Positioned(
    left: rightward ? endX + gap : 0,
    right: rightward ? 0 : rowWidth - endX + gap,
    bottom: bottom,
    height: iconSize,
    child: Align(
      alignment: rightward ? Alignment.centerLeft : Alignment.centerRight,
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    ),
  );
}

/// The band after the last message of a failed exchange. Held back (its
/// space kept) until [reached], like the milestone bands.
class LadderStoppedBand extends StatelessWidget {
  const LadderStoppedBand({
    super.key,
    required this.text,
    required this.reached,
  });

  /// One sentence: what failed, and where.
  final String text;
  final bool reached;

  /// Finds the band in tests.
  static const Key bandKey = ValueKey<String>('ladder-stopped-band');

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme theme = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    final Widget band = Container(
      key: bandKey,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.statusDanger, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            kStoppedIcon,
            size: sc.markerSize(20),
            color: colors.statusDanger,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Stopped here. ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: theme.bodySmall?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
    if (!reached) {
      return ExcludeSemantics(
        child: Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: band,
        ),
      );
    }
    return Semantics(
      container: true,
      label: 'Stopped here. $text',
      excludeSemantics: true,
      child: band,
    );
  }
}

/// The caption's line for a failure or lost message: the icon and the words,
/// so the caption never relies on the arrow's mark.
class LadderFailureCaptionLine extends StatelessWidget {
  const LadderFailureCaptionLine({super.key, required this.lost});

  final bool lost;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Icon(
            lost ? kLostIcon : kFailureIcon,
            size: sc.markerSize(20),
            color: lost ? colors.textSecondary : colors.statusDanger,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            lost
                ? 'No answer: nothing comes back, so the sender waits and '
                      'tries again.'
                : 'This is where it fails.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// The caption's closing block for a failed exchange at its last message:
/// the "Stopped here" sentence and what the help desk sees.
class LadderStoppedCaption extends StatelessWidget {
  const LadderStoppedCaption({
    super.key,
    required this.faultNote,
    this.helpDesk,
  });

  final String faultNote;
  final String? helpDesk;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PresenterScale sc = PresenterMode.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: Icon(
                kStoppedIcon,
                size: sc.markerSize(20),
                color: colors.statusDanger,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Stopped here. $faultNote',
                style: text.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (helpDesk != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Icon(
                  Icons.support_agent_rounded,
                  size: sc.markerSize(20),
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(
                        text: 'What the help desk sees: ',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: helpDesk),
                    ],
                  ),
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
