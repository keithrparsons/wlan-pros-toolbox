// Shared small widgets for the Wi-Fi Classroom tool The Number on the Box vs
// the Number in Your Hand (box-vs-hand): card, section label, and the
// throughput bar. Used by the stage and the controls, so neither imports the
// other.
//
// COLOR: context.colors only. The link a client can use takes the accent
// (colors.primary) as a fill; radios it cannot use take textTertiary. On
// light, lime is a fill only, so every fill carries an ink outline
// (GL-003 §8.20.2 rule 1). Nothing rests on color alone: every bar has its
// label and number in words, and the legend names both fills.
//
// ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'box_vs_hand_controller.dart';

class BvhCard extends StatelessWidget {
  const BvhCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
      child: child,
    );
  }
}

class BvhSectionLabel extends StatelessWidget {
  const BvhSectionLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0.4,
          fontWeight: colors.isLight ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// One stretch of a bar, as a share of the box number.
@immutable
class BvhSegment {
  const BvhSegment({required this.share, required this.usable});

  /// Length as a share of the full track, 0 to 1.
  final double share;

  /// True for the link a client uses (accent fill), false for a radio it
  /// does not (neutral fill).
  final bool usable;
}

/// A horizontal bar on the box-number scale. With one segment and a
/// [fromShare], the bar starts at [fromShare] and shrinks (or grows) to its
/// own length over [kBvhShrinkDuration]; under reduced motion it jumps.
class BvhBar extends StatelessWidget {
  const BvhBar({super.key, required this.segments, this.fromShare});

  final List<BvhSegment> segments;
  final double? fromShare;

  @override
  Widget build(BuildContext context) {
    final PresenterScale s = PresenterMode.scaleOf(context);
    final bool still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final double height = AppSpacing.md * s.marker;
    if (segments.length != 1 || fromShare == null) {
      return SizedBox(height: height, child: _paint(context, segments));
    }
    final BvhSegment only = segments.single;
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: fromShare, end: only.share),
        duration: still ? Duration.zero : kBvhShrinkDuration,
        curve: AppMotion.standardEase,
        builder: (BuildContext context, double v, Widget? _) => _paint(
          context,
          <BvhSegment>[BvhSegment(share: v, usable: only.usable)],
        ),
      ),
    );
  }

  Widget _paint(BuildContext context, List<BvhSegment> segs) {
    final AppColorScheme colors = context.colors;
    final PresenterScale s = PresenterMode.scaleOf(context);
    final BorderSide ink = BorderSide(
      color: colors.textPrimary,
      width: colors.isLight ? s.strokeWidth(1.5) : s.strokeWidth(1),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final double w = c.maxWidth;
        final List<Widget> fills = <Widget>[];
        double x = 0;
        for (final BvhSegment seg in segs) {
          final double len = (seg.share.clamp(0.0, 1.0)) * w;
          if (len > 0.5) {
            fills.add(
              Positioned(
                left: x,
                top: 0,
                bottom: 0,
                width: len,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: seg.usable ? colors.primary : colors.textTertiary,
                    border: Border.fromBorderSide(ink),
                    borderRadius: BorderRadius.circular(AppRadius.control / 2),
                  ),
                ),
              ),
            );
          }
          x += len;
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.disabledFill,
                  borderRadius: BorderRadius.circular(AppRadius.control / 2),
                ),
              ),
            ),
            ...fills,
          ],
        );
      },
    );
  }
}

/// A legend swatch drawn the way the bar draws the fill it names.
class BvhSwatch extends StatelessWidget {
  const BvhSwatch({super.key, required this.usable});
  final bool usable;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final PresenterScale s = PresenterMode.scaleOf(context);
    return Container(
      width: AppSpacing.md * s.marker,
      height: AppSpacing.sm * s.marker,
      decoration: BoxDecoration(
        color: usable ? colors.primary : colors.textTertiary,
        border: Border.all(color: colors.textPrimary, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.control / 2),
      ),
    );
  }
}
