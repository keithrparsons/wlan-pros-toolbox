// ToolHelpFooter — the shared "About this tool" footer for every tool screen.
//
// Source of truth: Team Knowledge/Guidelines/GL-003-design-system.md §8.16.1
// ("Tool-help footer"). As of 2026-06-04 the per-tool help affordance moved OUT
// of the AppBar (where it was an Icons.help_outline IconButton, §8.16) to a
// shared bottom footer at the END of each tool screen's scroll body. This is
// the single reusable widget that renders that footer — Felix does NOT hand-roll
// a help row per screen. It composes §8.1 surfaces, §8.2 text, §8.6 icon sizing,
// §8.3 touch target + focus ring, §8.7 spacing, and §8.8 motion. No new tokens.
//
// Behavior, keyed by `helpForId(toolId)` (the existing lookup):
//   - help entry exists → render the footer (a full-width "About this tool" row
//     that opens the EXISTING shared help sheet via showToolHelpSheet);
//   - no help entry → render NOTHING (SizedBox.shrink).
//
// This is the §8.16.1 / GL-005 empty-state rule: an affordance that promises
// help must lead to real help, so a tool with no authored help renders no footer
// at all (NOT a disabled footer, NOT an empty "About this tool" that opens to
// nothing). It differs deliberately from §8.16 copy, which DISABLES-and-waits
// because results always eventually arrive — help is either authored or it
// isn't, so the footer renders or it is absent.
//
// PLACEMENT (caller's responsibility, per §8.16.1): drop this as the LAST child
// of the tool screen's scroll-body Column, inside the content-max-width column.
// The footer itself owns its `AppSpacing.lg` (32px) gap above and respects the
// bottom safe area; the caller does not add its own gap.

import 'package:flutter/material.dart';

import '../services/help/tool_help.dart';
import '../services/help/tool_help_loader.dart';
import '../theme/app_tokens.dart';
import 'tool_help_sheet.dart';

/// The §8.16.1 "About this tool" footer for the tool identified by [toolId].
///
/// Renders the footer row only when `helpForId(toolId) != null`; otherwise it
/// renders a zero-size widget (GL-005 — no help entry, no footer). Tapping it
/// opens the existing shared [showToolHelpSheet] for that entry. Stateless;
/// every visual value comes from a GL-003 token (no literal hex / px).
class ToolHelpFooter extends StatelessWidget {
  const ToolHelpFooter({required this.toolId, super.key});

  /// The catalog tool id whose help to surface — the SAME id the screen passed
  /// to the retired AppBar `ToolHelpAction`, and the id used for the route, the
  /// icon asset, and the tests.
  final String toolId;

  @override
  Widget build(BuildContext context) {
    final ToolHelp? help = helpForId(toolId);
    // No entry → no footer. Never a disabled/empty footer (§8.16.1, GL-005).
    if (help == null) return const SizedBox.shrink();

    final TextTheme text = Theme.of(context).textTheme;

    // §8.16.1 label style: --text-body (16px) / IBM Plex Sans 500 / leading 1.45
    // / --app-text-secondary. Derived from the bodyLarge slot (16/1.45) with the
    // medium weight and the quiet secondary color the footer reads in.
    final TextStyle labelStyle =
        (text.bodyLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        );

    return Padding(
      // §8.16.1 "Spacing above": --space-lg (32px) between the last content
      // block and the footer — the footer owns this gap so callers append it
      // directly with no SizedBox of their own.
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: SafeArea(
        // §8.16.1 "Spacing below": respect the bottom safe area + --space-sm
        // (16px) above the tab bar / home indicator. Only the bottom inset is
        // this widget's concern; horizontal edge padding is the screen's.
        top: false,
        left: false,
        right: false,
        minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Semantics(
          // §8.16.1 a11y: one labelled button, one focus stop. The inner
          // children are excluded so the row reads as a single control.
          button: true,
          label: 'About this tool',
          child: _FooterButton(
            onTap: () => showToolHelpSheet(context, help),
            labelStyle: labelStyle,
          ),
        ),
      ),
    );
  }
}

/// The interactive footer row: a full-width recessed surface with a top
/// hairline, a leading help glyph, the "About this tool" label, and an optional
/// trailing chevron. The whole row is the tap target (§8.16.1). Carries the
/// §8.3 lime focus ring via [FocusableActionDetector] — the row is a custom
/// composite (not a bare IconButton), so it cannot inherit the global
/// iconButtonTheme ring and must paint the §8.3 ring itself.
class _FooterButton extends StatefulWidget {
  const _FooterButton({required this.onTap, required this.labelStyle});

  final VoidCallback onTap;
  final TextStyle labelStyle;

  @override
  State<_FooterButton> createState() => _FooterButtonState();
}

class _FooterButtonState extends State<_FooterButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // §8.16.1 motion: the existing showToolHelpSheet governs the open
    // transition; the footer introduces no animation of its own. Under reduced
    // motion that sheet still collapses appropriately — there is nothing extra
    // for the footer to animate here.
    return FocusableActionDetector(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (bool value) {
        if (value != _focused) setState(() => _focused = value);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          // §8.16.1: --app-surface-1 fill, 1px --app-border top hairline
          // (decorative separator — interactive boundary is the focus ring +
          // 44pt hit region, not this divider). The §8.3 lime focus ring is a
          // 2px solid --color-primary outline with a 2px offset, focus-only.
          decoration: BoxDecoration(
            color: AppColors.surface1,
            border: Border(
              top: const BorderSide(color: AppColors.border, width: 1),
              // The §8.3 ring on the other three sides + the offset is drawn via
              // the outer foregroundDecoration below so it never disturbs the
              // 1px content hairline at rest.
            ),
          ),
          foregroundDecoration: _focused
              ? BoxDecoration(
                  border: Border.all(
                    color: AppColors.primary,
                    width: 2,
                  ),
                )
              : null,
          // §8.16.1 padding: --app-row-padding (12px top + 12px bottom) vertical,
          // --space-sm (16px) horizontal. ConstrainedBox guarantees the whole
          // row clears the §8.3 44pt touch-target floor even if content is short.
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.rowPadding,
            horizontal: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              // §8.16.1 leading icon: Icons.help_outline, 24px (--app-icon-nav),
              // --app-text-secondary — the same glyph + idle treatment it carried
              // in the AppBar, so it reads as a sibling to the copy glyph.
              const Icon(
                Icons.help_outline,
                size: 24,
                color: AppColors.textSecondary,
              ),
              // §8.16.1 icon → label gap: --space-xs (8px).
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'About this tool',
                  style: widget.labelStyle,
                ),
              ),
              // §8.16.1 optional trailing chevron: Icons.chevron_right, 24px,
              // --app-text-tertiary. Included as the disclosure cue because the
              // footer opens a bottom sheet (help is not expanded in place).
              const Icon(
                Icons.chevron_right,
                size: 24,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
