// Bit tables and evidence tags for the PHY Preamble Reference (Wi-Fi Lab).
//
// A table is a column of rows, never a wide grid, so it fits a 390 px phone
// without sideways scroll: the bit range in DM Mono on the left, then the
// field name with its width, its meaning, and its evidence tags.
//
// EVIDENCE. Every tag is the brief's own text. A settled tag (P from two code
// bases, S2, S2+, P/S2) is a neutral outline. A tag that is not settled (S1,
// INF, P from one vendor, "not verified", or no tag at all) is outlined in
// the §8.13 warning hue with an icon and the words "one source", "inferred",
// "not verified" or "no tag in the brief". That hue is a verdict on the
// evidence, tinted only on the unsettled members and paired with words, so it
// is a §8.15.1 case-2 verdict and never color alone.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// One evidence tag, as the brief writes it.
class EvidenceChip extends StatelessWidget {
  const EvidenceChip(this.evidence, {super.key});

  final Evidence evidence;

  /// The chip's visible text.
  static String textFor(Evidence e) {
    final String scope = e.scope == null ? '' : ' (${e.scope})';
    return e.isSettled ? '${e.tag}$scope' : '${e.tag}$scope · ${e.level.words}';
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool ok = evidence.isSettled;
    final Color ink = ok ? colors.textSecondary : colors.statusWarning;
    return Semantics(
      label: evidence.spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: ok ? colors.borderStrong : colors.statusWarning,
            width: colors.isLight ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!ok) ...<Widget>[
              Icon(Icons.help_outline_rounded, size: 14, color: ink),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Flexible(
              child: Text(
                textFor(evidence),
                style: text.labelSmall?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A wrap of tags.
class EvidenceChips extends StatelessWidget {
  const EvidenceChips(this.evidence, {super.key});

  final List<Evidence> evidence;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.xxs,
    runSpacing: AppSpacing.xxs,
    children: <Widget>[for (final Evidence e in evidence) EvidenceChip(e)],
  );
}

/// What the tags mean, in words.
class EvidenceKey extends StatelessWidget {
  const EvidenceKey({super.key});

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle? s = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textTertiary);
    return Text(
      'Tags are the research brief\'s own. P: code or a document read '
      'directly. S2: two independent sources agree. S1: one source. INF: '
      'derived by the researcher. Tags outlined with a question mark are '
      'not settled.',
      style: s,
    );
  }
}

/// A full SIG table.
class BitTableView extends StatelessWidget {
  const BitTableView({super.key, required this.table});

  final SigTable table;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String size = table.totalBits != null
        ? '${table.totalBits} bits'
        : table.groupsAreAlternatives
        ? 'layouts shown one by one'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            size.isEmpty ? table.title : '${table.title} · $size',
            style: text.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final BitGroup g in table.groups) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          _GroupHeader(group: g),
          for (final BitField f in g.fields) _FieldRow(field: f),
        ],
        if (table.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          for (final TableNote n in table.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      n.text,
                      style: text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    EvidenceChip(n.evidence),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final BitGroup group;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final List<String> parts = <String>[
      group.title,
      if (group.bits != null) '${group.bits} bits',
      if (group.modulation != null) group.modulation!,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Semantics(
        header: true,
        child: Text(
          parts.join(' · '),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final BitField field;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String width = '${field.width} bit${field.width == 1 ? '' : 's'}';
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: AppSpacing.xl + AppSpacing.md, // 72
              child: Text(
                field.bitsLabel,
                semanticsLabel: field.isPlaced
                    ? 'bits ${field.bitsLabel.replaceAll('-', ' to ')}'
                    : 'no bit position given',
                style: mono.inlineCode.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: field.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: '  $width',
                          style: TextStyle(color: colors.textTertiary),
                        ),
                      ],
                    ),
                    style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    field.meaning,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  EvidenceChips(field.evidence),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
