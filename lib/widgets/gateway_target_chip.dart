// GatewayTargetChip — a one-tap "use my gateway" affordance for the target
// field on Ping, Ping Plotter, and Traceroute.
//
// The spec (Wave 2 / 1.7.2) draws a deliberate line: Ping Sweep and Port Scan
// PREFILL their field, but Ping / Ping Plotter / Traceroute only OFFER the
// gateway — those tools are usually pointed at an internet host (1.1.1.1), so
// auto-filling the gateway would be presumptuous. A chip is the right, lighter
// affordance: a suggestion the user taps or ignores, never a lock.
//
// The caller decides WHEN to show it (gateway known AND the field is still
// empty / untouched) and supplies the fill callback. This widget is only the
// token-styled, accessible button.
//
// Token-only per GL-003 — no literal colors, sizes, or radii. Styling mirrors
// the ChoiceChips already on these screens so it reads as part of the form.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';

class GatewayTargetChip extends StatelessWidget {
  const GatewayTargetChip({
    super.key,
    required this.gatewayIp,
    required this.onSelected,
    this.enabled = true,
  });

  /// The gateway IPv4 to offer. The caller guarantees this is a real, sanitized
  /// address (CurrentNetwork drops `0.0.0.0` / unparseable), so the chip never
  /// offers a dead target.
  final String gatewayIp;

  /// Called with [gatewayIp] when the user taps the chip.
  final ValueChanged<String> onSelected;

  /// Disabled while a run is in flight (matches the form's other controls).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // No Align wrapper: the host form's Column is start-aligned, so the chip
    // sizes to its own content and hugs the leading edge. (A full-width Align
    // would also put the chip's tap-center in empty space.)
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionChip(
            avatar: Icon(
              Icons.router_outlined,
              size: 16,
              color: colors.textAccent,
            ),
            label: Text('Gateway $gatewayIp'),
            labelStyle: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            backgroundColor: colors.surface2,
            // WCAG 2.5.8 / §8.3 — guarantee a ≥48dp hit region.
            materialTapTargetSize: MaterialTapTargetSize.padded,
            // §8.3 shared resolver: idle border + 2px lime keyboard-focus ring.
            side: AppTheme.chipSide(Theme.of(context).brightness),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            // Spell out the action for assistive tech — the visible label is a
            // value, the tooltip/semantics name the verb.
            tooltip: 'Use your gateway $gatewayIp as the target',
            onPressed: enabled ? () => onSelected(gatewayIp) : null,
          ),
        ],
      ),
    );
  }
}
