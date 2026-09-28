// The controls of the Connected, No Internet walk-through: the one switch Pax
// named (the network announces its portal, or intercepts traffic) and the
// step buttons. Drawing lives in captive_portal_stage.dart.
//
// States: Back is disabled on the first step and Step on the last, with the
// disabled look and `Semantics.enabled` false; Reset is disabled at the start.
// Every button is a real button with the theme focus ring; the switch is the
// app's AppToggle (a single tab stop, arrow keys move the choice).

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/captive_portal_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';

class CaptivePortalControls extends StatelessWidget {
  const CaptivePortalControls({
    super.key,
    required this.mode,
    required this.onMode,
    required this.atStart,
    required this.atEnd,
    required this.onBack,
    required this.onStep,
    required this.onReset,
  });

  final CaptiveMode mode;
  final ValueChanged<CaptiveMode> onMode;
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
        AppToggle<CaptiveMode>(
          label: 'How the network asks for sign-in',
          value: mode,
          expand: true,
          items: const <AppToggleItem<CaptiveMode>>[
            (CaptiveMode.announced, 'Announces'),
            (CaptiveMode.intercepted, 'Intercepts'),
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
                semanticLabel: 'Back to association, the first step',
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
