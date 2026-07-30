// Shared section furniture for the reference screens: the section heading that
// stands on the page background, the surface-1 card every table sits in, and the
// lead paragraph at the top of a page.
//
// WHY THIS EXISTS: `_SectionHeading` and `_Card` were authored privately and
// identically in screw_drives_screen.dart, iec_connectors_screen.dart, and
// rj_connectors_screen.dart. The Batteries and SD Cards pages want the same two,
// and a fourth private copy is how a pattern forks. Same widgets, same tokens,
// one home. Existing screens keep their private copies until someone is in them
// for another reason; new reference screens use these.
//
// Tokens only (GL-003 sections 4, 8.1, 8.5, 8.11): surface1 fill, `border`
// hairline (decorative, non-interactive, so the decorative token is correct
// here), AppRadius.card, AppSpacing.*, and the TextTheme registers. No literal
// color, size, or spacing.
//
// Glyph rules (GL-004): no em dash, no en dash in any string this file renders.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// A section heading standing on the page background above a card or graphic.
class ReferenceSectionHeading extends StatelessWidget {
  const ReferenceSectionHeading({super.key, required this.label});

  /// The section name, e.g. `Reading the code`.
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Text(
        label,
        style: text.titleSmall?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// The shared surface-1 card: an optional tertiary heading over its content.
class ReferenceCard extends StatelessWidget {
  const ReferenceCard({super.key, this.heading, required this.child});

  /// Optional card heading. Omit for a card that is a single block of prose.
  final String? heading;

  /// The card content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String? head = heading;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (head != null && head.isNotEmpty) ...<Widget>[
            Text(
              head,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          child,
        ],
      ),
    );
  }
}

/// One fixed-width cell in a reference table, with the column gutter built in.
///
/// WHY IT IS NOT A BARE `SizedBox`: the reference tables lay columns out as
/// fixed-width `SizedBox`es inside a `Row` so the header and every data row
/// align column-for-column. A bare `SizedBox` gives the cell's text the FULL
/// column width, so a value that happens to fill its column butts directly
/// against the next column with no space between them (caught on the Batteries
/// size table during the first golden pass: "21.5 mm x 60 mm" ran straight into
/// "Survives only inside..."). Reserving a `--space-xs` gutter inside the cell
/// guarantees the gap no matter what the content does.
class ReferenceTableCell extends StatelessWidget {
  const ReferenceTableCell({
    super.key,
    required this.width,
    required this.child,
  });

  /// Fixed column width, shared by the header cell and every data cell so the
  /// grid stays aligned.
  final double width;

  /// The cell content, usually a `Text`.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: child,
      ),
    );
  }
}

/// The lead paragraph at the top of a reference page: the conclusion, stated
/// first, before any table.
class ReferenceLead extends StatelessWidget {
  const ReferenceLead({super.key, required this.text});

  /// The lead copy.
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return ReferenceCard(
      child: Text(
        text,
        style: t.bodyMedium?.copyWith(color: colors.textPrimary),
      ),
    );
  }
}
