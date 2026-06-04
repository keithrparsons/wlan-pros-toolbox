// ToolHelpAction — the shared "help" AppBar affordance, keyed by tool id.
//
// Drop this into a tool screen's AppBar `actions:` slot, AFTER the §8.16
// AppCopyAction, to honor the §8.16 order rule (copy LEADS, help TRAILS):
//   actions: <Widget>[ AppCopyAction(...), ToolHelpAction(toolId: '<id>') ]
//
// It resolves `helpForId(toolId)` and:
//   - shows an Icons.help_outline IconButton when an entry exists, opening the
//     shared ToolHelpSheet for that entry;
//   - renders NOTHING (a zero-size widget) when there is no entry — the help
//     icon never appears for a tool with no help (no fabricated help, GL-005).
//
// This mirrors the existing help-icon idiom on net_quality / wifi_info (an
// Icons.help_outline IconButton inside a Semantics(button: true) with a label),
// so the two read as siblings. The §8.3 focus ring is inherited from the global
// iconButtonTheme; nothing is drawn locally. No hardcoded colors / sizes.

import 'package:flutter/material.dart';

import '../services/help/tool_help.dart';
import '../services/help/tool_help_loader.dart';
import 'tool_help_sheet.dart';

/// AppBar help action for the tool identified by [toolId]. Renders the
/// Icons.help_outline button only when `helpForId(toolId) != null`.
class ToolHelpAction extends StatelessWidget {
  const ToolHelpAction({required this.toolId, super.key});

  /// The catalog tool id whose help to surface. Same id used for the route,
  /// the icon asset, and the tests.
  final String toolId;

  @override
  Widget build(BuildContext context) {
    final ToolHelp? help = helpForId(toolId);
    // No entry → no affordance. Never fabricate help (GL-005).
    if (help == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: 'Help',
      child: IconButton(
        icon: const Icon(Icons.help_outline),
        tooltip: 'Help',
        onPressed: () => showToolHelpSheet(context, help),
      ),
    );
  }
}
