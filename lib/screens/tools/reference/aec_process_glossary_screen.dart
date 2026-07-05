// AEC Process and Glossary - read-only field/trade reference (Field & Trade
// Reference set, 2026-07-05). Clones the Plan-Set Literacy / Site Access
// reference-screen pattern, but text-reference only: no DarkRasterDiagramCard
// (a decoder plate is optional here and can be added later, like many existing
// text-only reference screens). This entry is glossary-heavy; its term list is
// laid out as a definition list with mono designators.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/09-aec-process-
// glossary.md) as native layout.
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
// casing; phase and glossary designators (SD, RFI, AHJ, ...) in DM Mono
// (AppMonoText.inlineCode).

import 'package:flutter/material.dart';

import '../../../data/aec_process_glossary_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';

class AecProcessGlossaryScreen extends StatelessWidget {
  const AecProcessGlossaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AEC Process & Glossary'),
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
                  _PhasesCard(),
                  SizedBox(height: AppSpacing.md),
                  _AiaCard(),
                  SizedBox(height: AppSpacing.md),
                  _GlossaryCard(),
                  SizedBox(height: AppSpacing.md),
                  _WlanCaresCard(),
                  SizedBox(height: AppSpacing.md),
                  _DeferBand(),
                  ToolHelpFooter(toolId: kAecProcessGlossaryToolId),
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
      ..writeln('AEC Process & Glossary')
      ..writeln()
      ..writeln(kAecProcessLead)
      ..writeln()
      ..writeln('The design phases, and when Wi-Fi should engage')
      ..writeln(
        <String>['Phase', 'What happens', 'When Wi-Fi engages'].join(tab),
      );
    for (final AecPhase p in kAecPhases) {
      final String phase = p.abbr.isEmpty ? p.phase : '${p.abbr} (${p.phase})';
      b.writeln(<String>[phase, p.whatHappens, p.whenWifi].join(tab));
    }
    b
      ..writeln(kEngageSdNote)
      ..writeln()
      ..writeln('The AIA')
      ..writeln(kAiaNote)
      ..writeln()
      ..writeln('The glossary that trips WLAN pros up');
    for (final GlossaryTerm g in kAecGlossary) {
      b.writeln('${_glossaryLead(g)}: ${g.definition}');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kAecProcessWlanCares)
      ..writeln()
      ..writeln(kAecProcessDeferNote);
    return b.toString().trimRight();
  }

  /// The verbatim lead of a glossary line: `ABBR (Term)`, `ABBR`, or `Term`.
  static String _glossaryLead(GlossaryTerm g) {
    if (g.abbr.isEmpty) return g.term;
    if (g.term.isEmpty) return g.abbr;
    return '${g.abbr} (${g.term})';
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

/// A mono designator (a phase acronym) as a fixed-width accent chip.
class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return SizedBox(
      width: 44,
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
    return const _Card(child: _Body(kAecProcessLead));
  }
}

/// The design-phase table, then the engage-at-SD note.
class _PhasesCard extends StatelessWidget {
  const _PhasesCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'The design phases, and when Wi-Fi should engage',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DividedList(
            rows: <Widget>[
              for (final AecPhase p in kAecPhases) _PhaseRowView(phase: p),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _Body(kEngageSdNote),
        ],
      ),
    );
  }
}

/// One phase row: the phase name (with an optional mono acronym chip), what
/// happens, and when Wi-Fi engages. The whole row is one Semantics unit.
class _PhaseRowView extends StatelessWidget {
  const _PhaseRowView({required this.phase});

  final AecPhase phase;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final String phaseLabel =
        phase.abbr.isEmpty ? phase.phase : '${phase.abbr} (${phase.phase})';
    final TextStyle nameStyle = (t.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return Semantics(
      container: true,
      label:
          '$phaseLabel. ${phase.whatHappens}. When Wi-Fi engages: '
          '${phase.whenWifi}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (phase.abbr.isEmpty)
            Text(phase.phase, style: nameStyle)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _CodeChip(phase.abbr),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(phase.phase, style: nameStyle)),
              ],
            ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            phase.whatHappens,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'When Wi-Fi engages',
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            phase.whenWifi,
            style: t.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The AIA note.
class _AiaCard extends StatelessWidget {
  const _AiaCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(title: 'The AIA', child: _Body(kAiaNote));
  }
}

/// The glossary that trips WLAN pros up.
class _GlossaryCard extends StatelessWidget {
  const _GlossaryCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'The glossary that trips WLAN pros up',
      child: _DividedList(
        rows: <Widget>[
          for (final GlossaryTerm g in kAecGlossary) _GlossaryRowView(term: g),
        ],
      ),
    );
  }
}

/// One glossary entry: a designator lead (mono acronym + optional expansion, or
/// a plain term) then the definition. One Semantics unit.
class _GlossaryRowView extends StatelessWidget {
  const _GlossaryRowView({required this.term});

  final GlossaryTerm term;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final TextStyle nameStyle = (t.bodyMedium ?? const TextStyle()).copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    final TextStyle abbrStyle = mono.inlineCode.copyWith(
      color: colors.textAccent,
      fontWeight: FontWeight.w700,
    );

    final List<InlineSpan> lead = <InlineSpan>[];
    if (term.abbr.isNotEmpty) {
      lead.add(TextSpan(text: term.abbr, style: abbrStyle));
      if (term.term.isNotEmpty) {
        lead.add(TextSpan(text: '  ${term.term}', style: nameStyle));
      }
    } else {
      lead.add(TextSpan(text: term.term, style: nameStyle));
    }

    final String semanticsLead = term.abbr.isEmpty
        ? term.term
        : term.term.isEmpty
            ? term.abbr
            : '${term.abbr} (${term.term})';

    return Semantics(
      container: true,
      label: '$semanticsLead. ${term.definition}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RichText(text: TextSpan(children: lead)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            term.definition,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
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
      child: _Body(kAecProcessWlanCares),
    );
  }
}

/// The defer footer as an info band.
class _DeferBand extends StatelessWidget {
  const _DeferBand();

  @override
  Widget build(BuildContext context) {
    return const _InfoBand(kAecProcessDeferNote);
  }
}
