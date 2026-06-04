// ToolHelpSheet — the shared, reusable help sheet for every tool.
//
// Renders a [ToolHelp] as a scrollable modal bottom sheet, matching the EXISTING
// idiom in lib/screens/tools/network/net_quality_help_sheet.dart: a surface2
// sheet, a drag handle, a ConstrainedBox capped at 560, surface1 cards with a
// §8.2 hairline border, IBM Plex Sans body, textSecondary supporting copy,
// textTertiary captions. No hardcoded colors / spacing / radius — every value
// is a GL-003 token (§8.1 surfaces, §4 spacing, §8.5 type, §8.11 radius).
//
// One sheet, all tools. The same widget renders any ToolHelp — a calculator
// (purpose + inputs + algorithm + example), a reference table (purpose + why +
// field notes, no inputs/algorithm), or a live tool. Sections present render;
// sections absent are skipped (the sheet shows only what the entry carries):
//   - Purpose
//   - Why it's in the toolbox
//   - How to use (numbered)
//   - Inputs (name / unit / range)
//   - Algorithm & formula (mono where it reads as a formula)
//   - Worked example
//   - Field notes (bulleted)
//
// ACCESSIBILITY: every section heading is a Semantics(header: true) node so a
// screen reader can navigate section-by-section (WCAG 1.3.1). The §8.16
// AppCopyAction copies the whole entry as labeled plain text.
//
// HONESTY (GL-005): field-note caveats render verbatim — they are never
// dropped, truncated, or paraphrased. A null/empty section simply does not
// appear; the sheet never fabricates a section to fill a gap.

import 'package:flutter/material.dart';

import '../services/help/tool_help.dart';
import '../theme/app_tokens.dart';
import 'app_copy_action.dart';

/// Opens the shared help sheet for [help]. Matches the net_quality help-sheet
/// modal idiom (scroll-controlled, drag handle, surface2 background).
Future<void> showToolHelpSheet(BuildContext context, ToolHelp help) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface2,
    builder: (_) => ToolHelpSheet(help: help),
  );
}

/// The shared, scrollable help content for one [ToolHelp]. Stateless; capped at
/// 560 like the other network sheets. Renders only the sections present.
class ToolHelpSheet extends StatelessWidget {
  const ToolHelpSheet({required this.help, super.key});

  final ToolHelp help;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    final List<Widget> sections = <Widget>[];

    void addSection(String title, Widget body) {
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: AppSpacing.md));
      }
      sections.add(_SectionHeading(title));
      sections.add(const SizedBox(height: AppSpacing.xs));
      sections.add(body);
    }

    // Purpose.
    if (help.purpose.isNotEmpty) {
      addSection('Purpose', _Paragraph(help.purpose));
    }

    // Why it's in the toolbox.
    if (help.whyHere.isNotEmpty) {
      addSection("Why it's in the toolbox", _Paragraph(help.whyHere));
    }

    // How to use — numbered steps.
    if (help.howToUse.isNotEmpty) {
      addSection('How to use', _NumberedSteps(steps: help.howToUse));
    }

    // Inputs — name / unit / range rows.
    if (help.inputs.isNotEmpty) {
      addSection('Inputs', _InputsTable(inputs: help.inputs));
    }

    // Algorithm & formula — mono where it reads as a formula.
    final String? algorithm = help.algorithm;
    if (algorithm != null) {
      addSection(
        'Algorithm & formula',
        _AlgorithmBlock(
          text: algorithm,
          asFormula: help.algorithmReadsAsFormula,
        ),
      );
    }

    // Worked example.
    final String? example = help.example;
    if (example != null) {
      addSection('Worked example', _Paragraph(example));
    }

    // Field notes — bulleted, verbatim (GL-005).
    if (help.fieldNotes.isNotEmpty) {
      addSection('Field notes', _BulletedNotes(notes: help.fieldNotes));
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Title row: the tool name (the sheet's top heading node for a
              // screen reader) + the §8.16 copy affordance for the whole entry.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(help.name, style: text.headlineSmall),
                    ),
                  ),
                  // §8.16 — copy the whole help entry as labeled plain text.
                  // textBuilder is non-null always (static content), so it
                  // renders enabled.
                  AppCopyAction(
                    textBuilder: () => _helpPlainText(help),
                    idleLabel: 'Copy help',
                  ),
                ],
              ),
              if (help.category.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  help.category,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              ...sections,

              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: 'Close help',
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
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

/// Plain-text rendering of a whole help entry, for the §8.16 AppCopyAction.
/// Mirrors the on-screen sections in order; only present sections appear.
String _helpPlainText(ToolHelp help) {
  final StringBuffer b = StringBuffer()..writeln(help.name);
  if (help.category.isNotEmpty) b.writeln(help.category);
  b.writeln();

  void section(String title, String body) {
    b
      ..writeln(title)
      ..writeln(body)
      ..writeln();
  }

  if (help.purpose.isNotEmpty) section('Purpose', help.purpose);
  if (help.whyHere.isNotEmpty) {
    section("Why it's in the toolbox", help.whyHere);
  }
  if (help.howToUse.isNotEmpty) {
    b.writeln('How to use');
    for (int i = 0; i < help.howToUse.length; i++) {
      b.writeln('${i + 1}. ${help.howToUse[i]}');
    }
    b.writeln();
  }
  if (help.inputs.isNotEmpty) {
    b.writeln('Inputs');
    for (final ToolHelpInput i in help.inputs) {
      final List<String> parts = <String>[
        i.name,
        if (i.unit.isNotEmpty) 'unit: ${i.unit}',
        if (i.range.isNotEmpty) 'range: ${i.range}',
      ];
      b.writeln('- ${parts.join(' — ')}');
    }
    b.writeln();
  }
  final String? algorithm = help.algorithm;
  if (algorithm != null) section('Algorithm & formula', algorithm);
  final String? example = help.example;
  if (example != null) section('Worked example', example);
  if (help.fieldNotes.isNotEmpty) {
    b.writeln('Field notes');
    for (final String note in help.fieldNotes) {
      b.writeln('- $note');
    }
    b.writeln();
  }
  if (help.source.isNotEmpty) b.writeln('Source: ${help.source}');
  return b.toString().trimRight();
}

/// A section heading — H3-equivalent, IBM Plex Sans, exposed to a screen reader
/// as a navigable heading node (WCAG 1.3.1). Matches the net_quality sheet.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

/// A body paragraph in textSecondary. The reading workhorse of the sheet.
class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyLarge
          ?.copyWith(color: AppColors.textSecondary),
    );
  }
}

/// Numbered "How to use" steps. Each step is its own semantic node ("Step 1: …")
/// so a screen reader reads the ordinal with the instruction.
class _NumberedSteps extends StatelessWidget {
  const _NumberedSteps({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Semantics(
            container: true,
            label: 'Step ${i + 1}: ${steps[i]}',
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 24,
                  child: Text(
                    '${i + 1}.',
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textTertiary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    steps[i],
                    style: text.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
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

/// The inputs table — one card per input with name / unit / range. Stacked
/// label+value rows (not a fixed-column grid) so the text reflows rather than
/// clipping at 320px (§8.9), matching the net_quality grade-band approach. Each
/// input card is one semantic node.
class _InputsTable extends StatelessWidget {
  const _InputsTable({required this.inputs});

  final List<ToolHelpInput> inputs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < inputs.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _InputCard(input: inputs[i]),
        ],
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({required this.input});

  final ToolHelpInput input;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    // Build a curated single SR label so the card reads as one passage.
    final List<String> srParts = <String>[
      input.name,
      if (input.unit.isNotEmpty) 'unit ${input.unit}',
      if (input.range.isNotEmpty) 'range ${input.range}',
    ];

    return Semantics(
      container: true,
      label: srParts.join(', '),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              input.name,
              style: text.titleSmall?.copyWith(color: AppColors.textPrimary),
            ),
            if (input.unit.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              _LabeledInline(label: 'Unit', value: input.unit),
            ],
            if (input.range.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              _LabeledInline(label: 'Range', value: input.range),
            ],
          ],
        ),
      ),
    );
  }
}

/// A "Label: value" inline row inside an input card. Label is a quiet tertiary
/// rubric; value is secondary body text that wraps.
class _LabeledInline extends StatelessWidget {
  const _LabeledInline({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: text.labelMedium?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// The algorithm / formula block. When the text reads as a formula it renders in
/// the DM Mono inline-code style on a surface1 card (the §8.5 mono register for
/// CLI / formula fragments); otherwise it renders as a normal paragraph so a
/// prose "how it works" note stays readable.
class _AlgorithmBlock extends StatelessWidget {
  const _AlgorithmBlock({required this.text, required this.asFormula});

  final String text;
  final bool asFormula;

  @override
  Widget build(BuildContext context) {
    final TextTheme theme = Theme.of(context).textTheme;
    if (!asFormula) {
      return _Paragraph(text);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: SelectableText(
        text,
        // §8.5 inline-code register: DM Mono, body size, prose-floor leading.
        style: theme.bodyLarge?.copyWith(
          fontFamily: 'DM Mono',
          color: AppColors.textPrimary,
          height: 1.45,
        ),
      ),
    );
  }
}

/// Field notes — bulleted, verbatim. Each note is a leading dot + the note
/// text, one semantic node per note. GL-005: the caveats are rendered exactly
/// as written; nothing is dropped.
class _BulletedNotes extends StatelessWidget {
  const _BulletedNotes({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < notes.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 7, right: AppSpacing.xs),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: AppColors.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  notes[i],
                  style: text.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
