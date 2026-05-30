// LabeledField — the shared "label above field" primitive for every tool
// screen.
//
// GL-003 §8.4 mandates the label sits ABOVE the field as its own line (no
// floating-label / no in-field label). That visual rule means the field's
// purpose is NOT carried by `InputDecoration.labelText`, so VoiceOver / TalkBack
// would announce the bare field with no name. This widget closes that gap:
//
//   1. Renders the §8.4 label line (caption / weight-500 / textSecondary) above
//      the field — identical visual output to the hand-rolled
//      `Text(...) + SizedBox(xs)` block it replaces. An optional `hint` suffix
//      (e.g. the unit hint on the dBm↔Watt converter) renders inline.
//   2. Wraps that visual label in `ExcludeSemantics` so the screen reader does
//      NOT double-announce it as standalone text.
//   3. Wraps the field in `Semantics(label: …, textField: true)` so the field
//      is programmatically associated with its label and announced as a text
//      field on focus — the idiomatic Flutter SR-association pattern.
//
// Visual layout is unchanged: same label style, same `--space-xs` gap, same
// field. Only the semantics tree changes.

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.field,
    this.hint,
    this.semanticLabel,
  });

  /// Visible label text shown above the field (§8.4). Also the default
  /// screen-reader label for the field unless [semanticLabel] overrides it.
  final String label;

  /// The configured input — a `TextField` / `TextFormField`. Passed in fully
  /// built so each screen keeps its own controller, keyboardType, formatters,
  /// hint, etc. unchanged.
  final Widget field;

  /// Optional muted suffix rendered inline after the label (e.g. "(dBm)").
  /// Purely decorative — excluded from the semantics tree with the label.
  final String? hint;

  /// Override the screen-reader label when it should differ from the visible
  /// [label] (e.g. visible "Ports" but announced "Ports to scan"). Defaults to
  /// [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // §8.4 label line — visually identical to the prior inline block.
        // Excluded from semantics so it isn't announced separately; its text is
        // carried by the field's Semantics label below instead.
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible so a long label (e.g. "Target coverage distance")
              // shrinks/ellipsizes instead of overflowing the bounded input
              // row on a phone-width surface, rather than forcing a fixed
              // intrinsic width that pushes past the available space.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Text(
                  hint!,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        // Programmatic label↔field association: the field announces its purpose
        // ("<label>, text field") on focus under VoiceOver / TalkBack.
        Semantics(
          label: semanticLabel ?? label,
          textField: true,
          child: field,
        ),
      ],
    );
  }
}
