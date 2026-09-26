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
import '../../../widgets/presenter/presenter_mode.dart';

/// One evidence tag, as the brief writes it.
class EvidenceChip extends StatelessWidget {
  const EvidenceChip(this.evidence, {super.key, this.dense = false});

  final Evidence evidence;

  /// No vertical padding, so the chip sits inside a line of text (the
  /// presenter stage's one-line field rows).
  final bool dense;

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
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: dense ? 0 : AppSpacing.xxs,
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

  /// Rows (group headers and fields) on the presenter stage before the
  /// table flows into a second column.
  static const int presenterRowsPerColumn = 13;

  @override
  Widget build(BuildContext context) {
    if (PresenterMode.isActive(context)) return _presenter(context);
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

extension on BitTableView {
  /// Presenter stage: the fields flow into one or two columns, each field
  /// on one flowing line (bits, name, width, evidence, meaning) that wraps
  /// only when it must, so a whole SIG field reads at once with no scroll.
  Widget _presenter(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String size = table.totalBits != null
        ? '${table.totalBits} bits'
        : table.groupsAreAlternatives
        ? 'layouts shown side by side'
        : '';
    // Every group header and field, in order, in one column, or two when
    // there are more than [BitTableView.presenterRowsPerColumn] rows (two
    // wide columns keep most fields on one line; three narrow ones wrap
    // nearly all of them). A header never ends a column.
    final List<Widget> rows = <Widget>[];
    final List<bool> isHeader = <bool>[];
    for (final BitGroup g in table.groups) {
      rows.add(_GroupHeader(group: g));
      isHeader.add(true);
      for (final BitField f in g.fields) {
        rows.add(_FieldRow(field: f, compact: true));
        isHeader.add(false);
      }
    }
    final int count =
        ((rows.length + BitTableView.presenterRowsPerColumn - 1) ~/
                BitTableView.presenterRowsPerColumn)
            .clamp(1, 2);
    final int per = (rows.length + count - 1) ~/ count;
    final List<List<Widget>> columns = <List<Widget>>[];
    int at = 0;
    for (int c = 0; c < count && at < rows.length; c++) {
      int end = c == count - 1 ? rows.length : (at + per).clamp(0, rows.length);
      if (end < rows.length && isHeader[end - 1]) end--;
      columns.add(rows.sublist(at, end));
      at = end;
    }
    if (at < rows.length) columns.last.addAll(rows.sublist(at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
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
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < columns.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: columns[i],
                ),
              ),
            ],
          ],
        ),
        for (final TableNote n in table.notes)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: MergeSemantics(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: <Widget>[
                  Text(
                    n.text,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  EvidenceChip(n.evidence),
                ],
              ),
            ),
          ),
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
  const _FieldRow({required this.field, this.compact = false});

  final BitField field;

  /// Presenter: the evidence chips ride on the name line and the padding
  /// tightens, so a field takes two lines.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String width = '${field.width} bit${field.width == 1 ? '' : 's'}';
    if (compact) return _compact(context, colors, text, mono, width);
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

  Widget _compact(
    BuildContext context,
    AppColorScheme colors,
    TextTheme text,
    AppMonoText mono,
    String width,
  ) {
    final TextStyle bitsStyle = mono.inlineCode.copyWith(
      color: colors.textPrimary,
    );
    // Wide enough for the widest label ("B23-B25") at this text scale, so
    // no bit range breaks across two lines.
    final TextPainter probe = TextPainter(
      text: TextSpan(text: 'B00-B00', style: bitsStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double bitsW = probe.width;
    probe.dispose();
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs / 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: bitsW + 1,
              child: Text(
                field.bitsLabel,
                semanticsLabel: field.isPlaced
                    ? 'bits ${field.bitsLabel.replaceAll('-', ' to ')}'
                    : 'no bit position given',
                style: bitsStyle,
                softWrap: false,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // Name, width, evidence and meaning flow as one line, wrapping
            // only when the column is too narrow for them.
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: 0,
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
                  for (final Evidence e in field.evidence)
                    EvidenceChip(e, dense: true),
                  Text(
                    field.meaning,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
