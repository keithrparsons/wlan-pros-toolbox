// UnitSystemSwitch — the metric / imperial switch every Wi-Fi Classroom tool
// that shows a length carries, in the same place: the AppBar actions, first,
// ahead of Present and Copy; and in presenter mode, the top bar.
//
// It sets ONE app-wide preference (UnitSystemController), so flipping it in
// one tool flips every tool, and the pick survives a relaunch. Metric is the
// default and is listed first (Keith, 2026-09-27).
//
// An AppToggle (GL-003 §8.14.1): two short options, radio-group keyboard
// model, the mandatory focus ring. Labels are the full words where there is
// room and the unit symbols (m / ft) on a phone-width screen, where the tool
// title needs the space. Screen readers always hear the full words.
//
// With no UnitSystemScope in the tree (a bare widget test) it renders nothing.

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../units/unit_system.dart';
import 'app_toggle.dart';

/// Below this screen width the switch shows "m / ft" instead of the words.
const double kUnitSwitchCompactBelow = 600;

class UnitSystemSwitch extends StatelessWidget {
  const UnitSystemSwitch({super.key, this.compact});

  /// Force the symbol labels (true) or the word labels (false). Null picks by
  /// screen width.
  final bool? compact;

  /// Test handle.
  static const Key switchKey = ValueKey<String>('unit-system-switch');

  @override
  Widget build(BuildContext context) {
    final UnitSystemController? controller = UnitSystemScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final bool short =
        compact ?? MediaQuery.sizeOf(context).width < kUnitSwitchCompactBelow;
    return Padding(
      key: switchKey,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Center(
        child: Tooltip(
          message: 'Length units for every Classroom tool',
          child: Semantics(
            // AppToggle announces each segment by its label; on a phone that
            // label is a symbol, so the group names what the symbols mean.
            hint: 'Metric or imperial. Applies to every Classroom tool.',
            // IntrinsicHeight: AppToggle's segment dividers fill any loose
            // height, and an AppBar hands its actions the whole toolbar.
            child: IntrinsicHeight(
              child: AppToggle<UnitSystem>(
                semanticLabel: 'Length units',
                value: controller.system,
                items: short
                    ? const <AppToggleItem<UnitSystem>>[
                        (UnitSystem.metric, 'm'),
                        (UnitSystem.imperial, 'ft'),
                      ]
                    : const <AppToggleItem<UnitSystem>>[
                        (UnitSystem.metric, 'Metric'),
                        (UnitSystem.imperial, 'Imperial'),
                      ],
                onChanged: controller.setSystem,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
