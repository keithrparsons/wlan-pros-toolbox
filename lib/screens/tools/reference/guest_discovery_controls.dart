// The controls of the guest-discovery walk-through: the one control Pax named
// (same network / guest network / client isolation) and the step buttons.
// Drawing lives in guest_discovery_stage.dart.
//
// States: Back is disabled on the first step and Step on the last, with the
// disabled look and `Semantics.enabled` false; Reset is disabled at the start.
// Every button is a real button with the theme focus ring; the switch is the
// app's AppToggle (a single tab stop, arrow keys move the choice).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/guest_discovery_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';

class GuestDiscoveryControls extends StatelessWidget {
  const GuestDiscoveryControls({
    super.key,
    required this.mode,
    required this.onMode,
    required this.atStart,
    required this.atEnd,
    required this.onBack,
    required this.onStep,
    required this.onReset,
  });

  final DiscoveryNetwork mode;
  final ValueChanged<DiscoveryNetwork> onMode;
  final bool atStart;
  final bool atEnd;
  final VoidCallback onBack;
  final VoidCallback onStep;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppToggle<DiscoveryNetwork>(
          label: 'Which network the phone is on',
          value: mode,
          expand: true,
          items: const <AppToggleItem<DiscoveryNetwork>>[
            (DiscoveryNetwork.same, 'Same'),
            (DiscoveryNetwork.guest, 'Guest'),
            (DiscoveryNetwork.isolation, 'Isolation'),
          ],
          onChanged: onMode,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: _StepButton(
                icon: Icons.skip_previous_rounded,
                label: 'Back',
                semanticLabel: 'Back one step',
                onPressed: atStart ? null : onBack,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _StepButton(
                icon: Icons.skip_next_rounded,
                label: 'Step',
                semanticLabel: 'Next step',
                onPressed: atEnd ? null : onStep,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _StepButton(
                icon: Icons.restart_alt_rounded,
                label: 'Reset',
                semanticLabel: 'Back to the first step',
                onPressed: atStart ? null : onReset,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// An outlined button in the Classroom style (the same look as the ladders'
/// Back and Step).
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      enabled: enabled,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textAccent,
          disabledForegroundColor: colors.textDisabled,
          side: BorderSide(
            color: enabled ? colors.borderStrong : colors.disabledFill,
            width: colors.isLight ? 1.5 : 1,
          ),
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          // Tight side padding so the word fits beside the icon at 360 px.
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
