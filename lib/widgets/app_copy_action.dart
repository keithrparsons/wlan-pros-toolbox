// AppCopyAction — the shared "Copy results" AppBar affordance (GL-003 §8.16).
//
// Source of truth: Team Knowledge/Guidelines/GL-003-design-system.md §8.16
// ("Copy affordance (results screens)"), with §8.6 icon sizing/color, §8.3
// touch target + focus ring, §8.8 motion, §8.9 a11y floor, and §8.13's
// never-color-only / verdict-word rule.
//
// One reusable affordance, dropped into any results screen's AppBar `actions:`
// slot. It owns:
//   - the clipboard write (`Clipboard.setData`);
//   - the icon-swap confirmation (copy_outlined → check) + 1500ms window +
//     §8.8 cross-fade (collapsed to 0ms under reduced motion);
//   - the live-region SR announcement ("Results copied", SC 4.1.3);
//   - the disabled / no-results state (textDisabled, not focusable).
//
// The §8.3 keyboard focus ring is NO LONGER drawn here. As of 2026-06-01 the
// app ThemeData carries an `iconButtonTheme` whose `ButtonStyle.side` paints
// the 2px lime `_focusRingSide` on WidgetState.focused, so every icon-only
// IconButton — including this one — inherits the ring globally. This widget's
// inner control is a standard IconButton, so the theme reaches it.
//
// Contract: the screen passes a [textBuilder] closure that returns the full
// plain-text payload to copy, or `null` when there are no results yet. Null →
// the affordance renders disabled and drops from focus traversal; non-null →
// idle/enabled. The closure is evaluated lazily AT TAP TIME, so the screen
// never has to pre-serialize its results — it serializes on demand. (The same
// closure's null-ness is also read at build time to decide enabled state, so a
// screen that flips from no-results to results must rebuild this widget — which
// every StatefulWidget results screen already does on setState.)

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

/// The §8.16 "Copy results" AppBar action. Place in `AppBar.actions` per the
/// §8.16 order rule: **copy leading, help trailing** where both exist
/// (`[ … title … ] [copy] [help]`).
class AppCopyAction extends StatefulWidget {
  const AppCopyAction({
    required this.textBuilder,
    this.idleLabel = 'Copy results',
    this.copiedLabel = 'Results copied',
    super.key,
  });

  /// Returns the full plain-text payload to write to the clipboard, or `null`
  /// when the screen has no results yet (→ disabled, not focusable, §8.16
  /// empty/no-results rule). Evaluated at tap time for the copy, and its
  /// null-ness is read at build time to resolve the enabled/disabled state.
  ///
  /// Per the §8.16 content contract: any on-screen verdict the screen conveys
  /// with a §8.13 status hue MUST appear in this text as its WORD — the color
  /// is the on-screen carrier; the word is the clipboard carrier.
  final String? Function() textBuilder;

  /// Semantics label in the idle state (§8.16: verb + object).
  final String idleLabel;

  /// Semantics label during the confirm window (§8.16: state flip).
  final String copiedLabel;

  @override
  State<AppCopyAction> createState() => _AppCopyActionState();
}

class _AppCopyActionState extends State<AppCopyAction> {
  /// §8.16 confirm window — 1.5s, then auto-revert.
  static const Duration _confirmWindow = Duration(milliseconds: 1500);

  bool _confirmed = false;

  // Increments on every tap; the revert callback only acts if its captured
  // generation still matches — this is how a re-tap inside the window
  // RESTARTS the timer (§8.16) without a Timer field to cancel.
  int _confirmGeneration = 0;

  Future<void> _handleTap() async {
    final String? text = widget.textBuilder();
    // Defensive: disabled state already nulls onPressed, but never copy null.
    if (text == null) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    // SC 4.1.3 — status reaches AT users without moving focus and without a
    // visible toast (the app rejects SnackBar noise, §8.16).
    SemanticsService.sendAnnouncement(
      View.of(context),
      widget.copiedLabel,
      TextDirection.ltr,
    );

    final int generation = ++_confirmGeneration;
    setState(() => _confirmed = true);

    // Re-tap inside the window restarts the 1.5s timer: a later generation
    // supersedes this revert, so this callback no-ops when stale.
    Future<void>.delayed(_confirmWindow, () {
      if (!mounted || generation != _confirmGeneration) return;
      setState(() => _confirmed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool enabled = widget.textBuilder() != null;

    // §8.8 — cross-fade over `fast` (150ms), collapsed to 0ms under
    // prefers-reduced-motion (the glyph still swaps; only the fade is removed).
    final bool reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Duration swapDuration = reduceMotion ? Duration.zero : AppMotion.fast;

    // §8.16 icon + color resolution.
    //   disabled → textDisabled  (#7F7F7F, not focusable)
    //   confirmed → check in statusSuccess (#5BD68A — a genuine pass verdict)
    //   idle (enabled) → copy_outlined in textSecondary (#E5E5E5)
    final IconData icon = _confirmed ? Icons.check : Icons.copy_outlined;
    final Color iconColor = !enabled
        ? colors.textDisabled
        : (_confirmed ? colors.statusSuccess : colors.textSecondary);

    // §8.16: the label flips to copiedLabel during the confirm window; the
    // disabled control keeps the idle label with the platform disabled flag.
    final String label = _confirmed ? widget.copiedLabel : widget.idleLabel;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // excludeSemantics keeps the inner Icon/IconButton out of the tree — the
      // parent Semantics owns the single labelled, button role.
      child: ExcludeSemantics(
        // §8.3 keyboard focus ring is provided globally by the app's
        // iconButtonTheme (ButtonStyle.side → _focusRingSide on
        // WidgetState.focused), so this IconButton inherits the 2px lime ring
        // without any local drawing. The IconButton remains the real
        // actionable, focusable control (Enter/Space activation works for free).
        child: IconButton(
          // §8.16: onPressed null when disabled drops it from focus traversal
          // and exposes the platform disabled state to AT.
          onPressed: enabled ? _handleTap : null,
          // The visual glyph is 24px (§8.6 nav size); IconButton's hit region
          // stays ≥48dp for the §8.3 touch-target floor.
          iconSize: 24,
          // Tooltip mirrors the live label so pointer/hover users get the
          // same state text; suppressed while disabled.
          tooltip: enabled ? label : null,
          icon: AnimatedSwitcher(
            duration: swapDuration,
            child: Icon(
              icon,
              key: ValueKey<bool>(_confirmed),
              size: 24,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
