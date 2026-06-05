// AppearanceControl — the §8.20.5 theme toggle (System / Light / Dark).
//
// A three-segment `AppToggle<ThemeMode>` (§8.14.1) driving the app's
// [ThemeController] through the inherited [ThemeControllerScope]. Three short
// segments fit phone width, so a Toggle is the correct §8.20.5 control (not a
// Select). Default System; the pick persists across launches (handled by the
// controller). When no scope is present (a bare widget test), the control hides
// itself so it never throws.
//
// Tokens only: AppToggle carries the §8.14.1 segmented-toggle treatment; the
// surrounding label/help text reads `context.colors` so it switches with the
// theme it controls.

import 'package:flutter/material.dart';

import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_controller.dart';
import 'app_toggle.dart';

/// The Appearance selector. Renders a §8.4 label line, a short helper sentence,
/// then the three-segment System / Light / Dark toggle.
class AppearanceControl extends StatelessWidget {
  const AppearanceControl({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController? controller = ThemeControllerScope.maybeOf(context);
    // No controller in scope (e.g. an isolated widget test) → render nothing.
    if (controller == null) return const SizedBox.shrink();

    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppToggle<ThemeMode>(
          label: 'Appearance',
          semanticLabel: 'App appearance',
          value: controller.mode,
          items: const <AppToggleItem<ThemeMode>>[
            (ThemeMode.system, 'System'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
          ],
          expand: true,
          onChanged: (ThemeMode mode) => controller.setMode(mode),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'System follows your device setting. Light is built for projection '
          'and outdoor glare; Dark is the default.',
          style: text.bodySmall?.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
