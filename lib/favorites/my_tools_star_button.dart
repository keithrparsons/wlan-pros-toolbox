// MyToolsStarButton — the "add to My Tools" star for a tool screen's top bar
// (spec choice 2).
//
// An icon-only IconButton, so it inherits the §8.3 focus ring from the app
// iconButtonTheme and the 48dp default target. The screen-reader label states
// the action the button will take ("Add to My Tools" / "Remove from My Tools")
// and the node reports its toggled state, per the spec's accessibility line.
//
// Renders nothing when no MyToolsScope is above it (a bare widget test) or when
// the id is not a tool on this platform, so it is safe to drop into any AppBar.

import 'package:flutter/material.dart';

import '../data/tool_catalog.dart';
import '../theme/app_color_scheme.dart';
import 'my_tools_actions.dart';
import 'my_tools_controller.dart';

class MyToolsStarButton extends StatelessWidget {
  const MyToolsStarButton({required this.toolId, super.key});

  /// The catalog id of the tool whose screen this sits on.
  final String toolId;

  @override
  Widget build(BuildContext context) {
    final MyToolsController? controller = MyToolsScope.maybeOf(context);
    final ToolEntry? tool = toolEntryById(toolId);
    if (controller == null || tool == null) return const SizedBox.shrink();

    final bool starred = controller.contains(toolId);
    final AppColorScheme colors = context.colors;
    final String label = starred ? 'Remove from My Tools' : 'Add to My Tools';

    return Semantics(
      button: true,
      enabled: true,
      toggled: starred,
      label: label,
      excludeSemantics: true,
      child: IconButton(
        key: ValueKey<String>('my-tools-star-$toolId'),
        tooltip: label,
        icon: Icon(
          starred ? Icons.star : Icons.star_border,
          color: starred ? colors.textAccent : null,
        ),
        onPressed: () => toggleMyTool(context, tool),
      ),
    );
  }
}
