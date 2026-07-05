// CAD and BIM Formats - read-only field/trade reference (Field & Trade
// Reference set, 2026-07-05). Clones the Plan-Set Literacy / Site Access
// reference-screen pattern, but text-reference only: no DarkRasterDiagramCard
// (a decoder plate is optional here and can be added later, like many existing
// text-only reference screens).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/07-cad-bim-formats.md)
// as native layout.
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders.
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the AppBar §8.16 copy action and the §8.16.1 help footer
//     (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The defer footer is an info band (statusInfo glyph + word, never color-only,
// §8.13).
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; format and LOD designators in DM Mono (AppMonoText.inlineCode).

import 'package:flutter/material.dart';

import '../../../data/cad_bim_formats_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';

class CadBimFormatsScreen extends StatelessWidget {
  const CadBimFormatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CAD & BIM Formats'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const <Widget>[
                  _LeadCard(),
                  SizedBox(height: AppSpacing.md),
                  _FormatTableCard(),
                  SizedBox(height: AppSpacing.md),
                  _LodCard(),
                  SizedBox(height: AppSpacing.md),
                  _ImportCard(),
                  SizedBox(height: AppSpacing.md),
                  _BoundaryCard(),
                  SizedBox(height: AppSpacing.md),
                  _WlanCaresCard(),
                  SizedBox(height: AppSpacing.md),
                  _DeferBand(),
                  ToolHelpFooter(toolId: kCadBimFormatsToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// §8.16 plain-text payload - the full reference as tab-separated sections.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('CAD & BIM Formats')
      ..writeln()
      ..writeln(kCadBimLead)
      ..writeln()
      ..writeln('The format decode table')
      ..writeln(<String>['Format', 'What it is', 'Authored by'].join(tab));
    for (final CadFormatRow r in kCadFormats) {
      b.writeln(<String>[r.format, r.whatItIs, r.authoredBy].join(tab));
    }
    b
      ..writeln()
      ..writeln('Level of Development (LOD): how much to trust the model')
      ..writeln(<String>['Level', 'Meaning'].join(tab));
    for (final LodLevel l in kLodLevels) {
      b.writeln(<String>[l.level, l.meaning].join(tab));
    }
    b
      ..writeln(kLodWhyMatters)
      ..writeln()
      ..writeln('How a building file becomes a Wi-Fi design')
      ..writeln(kCadImportIntro);
    for (int i = 0; i < kCadImportSteps.length; i++) {
      b.writeln('${i + 1}. ${kCadImportSteps[i]}');
    }
    b
      ..writeln(kCadImportPrep)
      ..writeln()
      ..writeln('The boundary, stated plainly')
      ..writeln(kCadBoundary)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kCadBimWlanCares)
      ..writeln()
      ..writeln(kCadBimDeferNote);
    return b.toString().trimRight();
  }
}

// ─────────────────────────────── shared card shell ──────────────────────────

/// Surface-1 card with an optional section title (labelMedium, tracked).
class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});

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

/// A body paragraph in the standard secondary color.
class _Body extends StatelessWidget {
  const _Body(this.text);

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

/// A mono "code chip" (a format or LOD designator) with a fixed leading width so
/// a column of rows aligns. Accent-tinted, DM Mono.
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code, {this.width = 84});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return SizedBox(
      width: width,
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
          code,
          textAlign: TextAlign.center,
          style: mono.inlineCode.copyWith(
            color: colors.textAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// One key/value reference row: a leading [code] chip then a [label].
class _RefRow extends StatelessWidget {
  const _RefRow({required this.code, required this.label});

  final String code;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$code. $label',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CodeChip(code),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertically-stacked list of rows with hairline dividers between them.
class _DividedList extends StatelessWidget {
  const _DividedList({required this.rows});

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

/// The defer footer as an info band (icon + text, §8.13).
class _InfoBand extends StatelessWidget {
  const _InfoBand(this.text);

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

// ─────────────────────────────── section cards ──────────────────────────────

/// The italic lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kCadBimLead));
  }
}

/// The format decode table: format designator, what it is, and who authors it.
class _FormatTableCard extends StatelessWidget {
  const _FormatTableCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'The format decode table',
      child: _DividedList(
        rows: <Widget>[
          for (final CadFormatRow r in kCadFormats) _FormatRowView(row: r),
        ],
      ),
    );
  }
}

/// One format row: the format designator (mono), what it is, and an "Authored
/// by" line. The whole row is one Semantics unit.
class _FormatRowView extends StatelessWidget {
  const _FormatRowView({required this.row});

  final CadFormatRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '${row.format}. ${row.whatItIs}. Authored by: ${row.authoredBy}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CodeChip(row.format),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  row.whatItIs,
                  style: (t.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 84 + AppSpacing.sm),
            child: RichText(
              text: TextSpan(
                style: (t.bodySmall ?? const TextStyle()).copyWith(
                  color: colors.textTertiary,
                ),
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Authored by ',
                    style: (t.labelSmall ?? const TextStyle()).copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  TextSpan(text: row.authoredBy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Level of Development ladder: mono LOD chip + meaning, then the why-it-matters
/// note.
class _LodCard extends StatelessWidget {
  const _LodCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Level of Development (LOD): how much to trust the model',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DividedList(
            rows: <Widget>[
              for (final LodLevel l in kLodLevels)
                _RefRow(code: l.level, label: l.meaning),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _Body(kLodWhyMatters),
        ],
      ),
    );
  }
}

/// How a building file becomes a Wi-Fi design: intro + numbered steps + prep.
class _ImportCard extends StatelessWidget {
  const _ImportCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'How a building file becomes a Wi-Fi design',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Body(kCadImportIntro),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < kCadImportSteps.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _StepRow(number: i + 1, text: kCadImportSteps[i]),
          ],
          const SizedBox(height: AppSpacing.md),
          const _Body(kCadImportPrep),
        ],
      ),
    );
  }
}

/// One numbered workflow step: a mono ordinal chip then the step text.
class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Step $number. $text',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CodeChip('$number', width: 32),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The boundary, stated plainly.
class _BoundaryCard extends StatelessWidget {
  const _BoundaryCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'The boundary, stated plainly',
      child: _Body(kCadBoundary),
    );
  }
}

/// Why a WLAN pro cares.
class _WlanCaresCard extends StatelessWidget {
  const _WlanCaresCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Why a WLAN pro cares',
      child: _Body(kCadBimWlanCares),
    );
  }
}

/// The defer footer as an info band.
class _DeferBand extends StatelessWidget {
  const _DeferBand();

  @override
  Widget build(BuildContext context) {
    return const _InfoBand(kCadBimDeferNote);
  }
}
