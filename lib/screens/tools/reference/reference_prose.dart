// Shared layout primitives for the Field & Trade Reference set (2026-07-05).
//
// The pilot Field Reference screens (Enclosure Ratings, Site Access, CAD & BIM
// Formats) each hand-rolled a private _Card / _Body / _InfoBand shell. The
// second wave of eight reference screens (Cloud Tool Trust, Network in Scope,
// Adjacent Radio Systems, Credentials & Licenses, By-Vertical Index, Healthcare
// Wi-Fi, Data Centers & Wi-Fi, Facility Spaces) is prose-heavy and shares the
// exact same shell, so the shell is factored into ONE library-public widget set
// here - the same "factor the repeated reference idiom into a shared widget"
// move that produced ReferenceRowSemantics and DarkRasterDiagramCard. One
// implementation means one no-overflow guarantee and one a11y treatment across
// all eight screens; a screen just composes these primitives around Penn's
// verbatim const copy.
//
// Every color comes from context.colors (dark §8 / light §8.20); every size,
// gap, and radius from AppSpacing / AppRadius. No hardcoded color, size, or
// spacing literal (GL-003 §4 / §8.1). Warning bands use
// Icons.warning_amber_rounded; info bands use Icons.info_outline (§8.13).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// A surface-1 card with an optional tracked section title (labelMedium).
class ReferenceCard extends StatelessWidget {
  const ReferenceCard({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// The italic-lead card: a single body paragraph in a titleless card.
class ReferenceLead extends StatelessWidget {
  const ReferenceLead(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ReferenceCard(child: ReferenceBody(text));
  }
}

/// A body paragraph in the standard secondary color.
class ReferenceBody extends StatelessWidget {
  const ReferenceBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textSecondary,
      ),
    );
  }
}

/// A vertically-stacked bulleted list. Each item is a wrapping paragraph led by
/// an accent bullet glyph in a fixed-width gutter so the text block aligns.
class ReferenceBullets extends StatelessWidget {
  const ReferenceBullets(this.items, {super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Semantics(
            container: true,
            label: items[i],
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: AppSpacing.sm,
                  child: Text(
                    '•',
                    style: (t.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    items[i],
                    style: (t.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A vertically-stacked numbered list. Each item leads with a mono ordinal chip
/// (DM Mono, accent) then the wrapping step text.
class ReferenceNumbered extends StatelessWidget {
  const ReferenceNumbered(this.items, {super.key});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Semantics(
            container: true,
            label: 'Step ${i + 1}. ${items[i]}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 32,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                      horizontal: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(color: colors.border, width: 1),
                    ),
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: mono.inlineCode.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    items[i],
                    style: (t.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// One labeled sub-field inside a [ReferenceTermBlock]: an accent all-caps label
/// above its wrapping value. Used for a table cell that needs a column name
/// (e.g. "Lead time", "Your move").
class ReferenceField {
  const ReferenceField(this.label, this.value);

  /// The column label (accent, tracked, small).
  final String label;

  /// The cell value.
  final String value;
}

/// One reference-table row rendered as a stacked block (never true columns, so
/// it never overflows at 320px): a bold [term], an optional plain [body] line,
/// then each [fields] entry as a labeled value. The whole block is one
/// screen-reader node.
class ReferenceTermBlock extends StatelessWidget {
  const ReferenceTermBlock({
    super.key,
    required this.term,
    this.body,
    this.fields = const <ReferenceField>[],
  });

  final String term;
  final String? body;
  final List<ReferenceField> fields;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final StringBuffer semantics = StringBuffer(term);
    if (body != null) semantics.write('. $body');
    for (final ReferenceField f in fields) {
      semantics.write('. ${f.label}: ${f.value}');
    }
    return Semantics(
      container: true,
      label: semantics.toString(),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            term,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              body!,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          for (final ReferenceField f in fields) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              f.label,
              style: (t.labelSmall ?? const TextStyle()).copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              f.value,
              style: t.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A vertically-stacked list of [ReferenceTermBlock]s with hairline dividers
/// between them.
class ReferenceTermList extends StatelessWidget {
  const ReferenceTermList({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
          rows[i],
        ],
      ],
    );
  }
}

/// An info band (icon + text, never color-only, §8.13). Fixed convention:
/// Icons.info_outline. Used for the reference-only defer footer.
class ReferenceInfoBand extends StatelessWidget {
  const ReferenceInfoBand(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusInfoFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusInfo, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: colors.statusInfo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A warning band (icon + text, never color-only, §8.13). Fixed convention:
/// Icons.warning_amber_rounded. Used for a standalone "do not / common error"
/// caution rendered verbatim from the copy.
class ReferenceWarnBand extends StatelessWidget {
  const ReferenceWarnBand(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: (t.bodySmall ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
