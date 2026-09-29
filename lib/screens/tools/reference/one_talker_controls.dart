// The controls of the One Talker per Channel lesson (one-talker): devices on
// access point 1, the second access point (none, same channel, other
// channel), its devices, the slow device, Next turn and Reset. Drawing lives
// in one_talker_stage.dart.
//
// States: minus is disabled at 1 device and plus at the cap, each with the
// disabled look and `Semantics.enabled` false; Reset is disabled at the
// opening scene. Every button is a real Material button with the theme focus
// ring; the three-way choice is the app's AppToggle (one tab stop, arrow keys
// move the choice).
//
// PRESENTER: each label carries its key.
//
// THEME: `context.colors` only. ASCII copy, no em dashes (GL-004).

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/presenter/presenter_mode.dart';
import 'one_talker_controller.dart';

class OneTalkerControls extends StatelessWidget {
  const OneTalkerControls({super.key, required this.controller});

  final OneTalkerController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final OneTalkerController k = controller;
    final OneTalkerConfig c = k.config;
    final bool present = PresenterMode.isActive(context);
    String key(String label, String keys) => present ? '$label ($keys)' : label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OtStepper(
          label: key('Devices on access point 1', 'Up, Down'),
          value: c.clientsA,
          what: 'access point 1',
          onMinus: k.canRemoveA ? () => k.shiftClientsA(-1) : null,
          onPlus: k.canAddA ? () => k.shiftClientsA(1) : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppToggle<SecondAp>(
          label: key('Second access point, on which channel?', 'A, Space'),
          value: c.secondAp,
          expand: true,
          items: const <AppToggleItem<SecondAp>>[
            (SecondAp.none, 'None'),
            (SecondAp.sameChannel, 'Same'),
            (SecondAp.otherChannel, 'Other'),
          ],
          onChanged: k.setSecondAp,
        ),
        if (c.hasSecondAp) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          OtStepper(
            label: 'Devices on access point 2',
            value: c.clientsB,
            what: 'access point 2',
            onMinus: k.canRemoveB ? () => k.shiftClientsB(-1) : null,
            onPlus: k.canAddB ? () => k.shiftClientsB(1) : null,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        _SlowSwitch(
          title: key('Make device A slow', 'S'),
          subtitle:
              'Far from the access point, so each turn takes 4 times '
              'as long',
          value: c.slowTalker,
          onChanged: k.setSlowTalker,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(
              child: _Button(
                icon: Icons.skip_next_rounded,
                label: key('Next turn', 'Right'),
                semanticLabel: 'Pass the turn to the next device',
                onPressed: k.nextTurn,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _Button(
                icon: Icons.restart_alt_rounded,
                label: key('Reset', 'R'),
                semanticLabel: 'Back to the opening scene',
                onPressed: k.isDefault ? null : k.reset,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A count with minus and plus buttons.
class OtStepper extends StatelessWidget {
  const OtStepper({
    super.key,
    required this.label,
    required this.value,
    required this.what,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;

  /// Used in the buttons' spoken labels ("Remove a device from access
  /// point 1").
  final String what;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    Widget button(IconData icon, String spoken, VoidCallback? on) => Semantics(
      button: true,
      enabled: on != null,
      label: spoken,
      excludeSemantics: true,
      child: IconButton.outlined(
        onPressed: on,
        icon: Icon(icon),
        tooltip: spoken,
        color: colors.textAccent,
        disabledColor: colors.textDisabled,
        constraints: const BoxConstraints(
          minWidth: AppSpacing.minTouchTarget,
          minHeight: AppSpacing.minTouchTarget,
        ),
        style: IconButton.styleFrom(
          side: BorderSide(
            color: on != null ? colors.borderStrong : colors.disabledFill,
            width: colors.isLight ? 1.5 : 1,
          ),
        ),
      ),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: t.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
        button(Icons.remove_rounded, 'Remove a device from $what', onMinus),
        Semantics(
          liveRegion: true,
          label: '$value ${value == 1 ? 'device' : 'devices'} on $what',
          excludeSemantics: true,
          child: SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        button(Icons.add_rounded, 'Add a device to $what', onPlus),
      ],
    );
  }
}

class _SlowSwitch extends StatelessWidget {
  const _SlowSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: t.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: t.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.primary,
          ),
        ],
      ),
    );
  }
}

/// An outlined button in the Classroom style (Guest Discovery's Back and
/// Step).
class _Button extends StatelessWidget {
  const _Button({
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
