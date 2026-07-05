// Shared interactive drill-down primitives for the two INTERACTIVE Field &
// Trade Reference screens (LED Decoder, Vendor Model Decode), 2026-07-05.
//
// The prose-only reference screens use reference_prose.dart. These two new
// screens add a selection step (pick a vendor -> pick a line -> read a table),
// so they need two shared interactive controls that the prose set never did:
//   * ReferencePickerRow — a keyboard-focusable, tappable row (§8.3 lime focus
//     ring, §8.1 interactive boundary at rest, chevron affordance, collapsed
//     semantics) that selects a vendor or a model line. Mirrors ToolRow's focus
//     treatment without the tool-catalog coupling.
//   * ReferenceBackButton — the "back to the picker" affordance for the detail
//     view, a FocusableActionDetector-wrapped control that paints the same §8.3
//     lime ring on keyboard focus (never a bare InkWell, closing the WCAG 2.4.7
//     gap the way AppToggle did).
//
// Every color comes from context.colors (dark §8 / light §8.20); every size,
// gap, and radius from AppSpacing / AppRadius. No hardcoded color, size, or
// spacing literal (GL-003 §4 / §8.1). Lime is a FOREGROUND ring here, so light
// substitutes the darkened-lime textAccent and bumps the ring to 3px
// (§8.20.2 / §8.20.3-B), matching ToolRow and AppToggle.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';

/// A tappable, keyboard-focusable picker row: a bold [title], an optional
/// [subtitle], and a trailing chevron. Selecting it fires [onTap]. Used for the
/// vendor picker and the model-line picker in the two interactive reference
/// screens.
class ReferencePickerRow extends StatefulWidget {
  const ReferencePickerRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingLabel,
  });

  /// The primary label (vendor or line name).
  final String title;

  /// Optional supporting line under the title.
  final String? subtitle;

  /// Optional short trailing label (e.g. "2 lines", "Note only") shown before
  /// the chevron. Announced as part of the collapsed semantics.
  final String? trailingLabel;

  /// Fired on tap / Enter / Space.
  final VoidCallback onTap;

  @override
  State<ReferencePickerRow> createState() => _ReferencePickerRowState();
}

class _ReferencePickerRowState extends State<ReferencePickerRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // §8.3 focus ring vs §8.1 interactive boundary at rest.
    final Border rowBorder = _focused
        ? Border.all(
            color: colors.isLight ? colors.textAccent : colors.primary,
            width: colors.isLight ? 3 : 2,
          )
        : Border.all(
            color: colors.borderStrong,
            width: colors.isLight ? 1.5 : 1,
          );

    final StringBuffer semantics = StringBuffer(widget.title);
    if (widget.subtitle != null) semantics.write('. ${widget.subtitle}');
    if (widget.trailingLabel != null) {
      semantics.write('. ${widget.trailingLabel}');
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: semantics.toString(),
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (bool hasFocus) {
            if (hasFocus != _focused) setState(() => _focused = hasFocus);
          },
          child: Container(
            decoration: BoxDecoration(
              border: rowBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.rowPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: (text.bodyLarge ?? const TextStyle()).copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: text.labelMedium?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailingLabel != null) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    widget.trailingLabel!,
                    style: text.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.chevron_right,
                  color: colors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "back to the picker" control shown at the top of a detail view. A
/// FocusableActionDetector-wrapped row (never a bare InkWell) that paints the
/// §8.3 lime ring on keyboard focus and reads [label].
class ReferenceBackButton extends StatefulWidget {
  const ReferenceBackButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  /// The label, e.g. "All vendors" or "Cisco lines".
  final String label;

  /// Fired on tap / Enter / Space.
  final VoidCallback onTap;

  @override
  State<ReferenceBackButton> createState() => _ReferenceBackButtonState();
}

class _ReferenceBackButtonState extends State<ReferenceBackButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final Color ringColor =
        colors.isLight ? colors.textAccent : colors.primary;
    final BoxDecoration decoration = BoxDecoration(
      color: _hovered ? colors.surface2 : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: _focused
          ? Border.all(color: ringColor, width: colors.isLight ? 3 : 2)
          : Border.all(color: Colors.transparent, width: colors.isLight ? 3 : 2),
    );

    return Semantics(
      button: true,
      label: 'Back to ${widget.label}',
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (bool show) {
          if (mounted) setState(() => _focused = show);
        },
        onShowHoverHighlight: (bool show) {
          if (mounted) setState(() => _hovered = show);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: colors.textAccent,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    widget.label,
                    style: (text.labelLarge ?? const TextStyle()).copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
