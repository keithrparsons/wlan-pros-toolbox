// My Tools — the shared add/remove flow and its two dialogs.
//
// One flow, every entry point: the long-press on a tool row (category list,
// search results) and the star button both call [toggleMyTool], so the
// list-is-full behavior and the confirmation wording are identical wherever a
// user adds a tool.
//
// Dialogs are designed surfaces on the app dialogTheme (surface2, card
// radius), never a browser confirm. Every value is a GL-003 token.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tool_catalog.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import 'my_tools_controller.dart';

/// Adds [tool] to My Tools, or removes it when it is already there. When the
/// list is full, asks which tool to replace (spec choice 3). Shows a short
/// confirmation in the nearest [ScaffoldMessenger]. Returns the controller's
/// resulting membership for [tool], or null when no controller is in scope.
Future<bool?> toggleMyTool(BuildContext context, ToolEntry tool) async {
  final MyToolsController? controller = MyToolsScope.read(context);
  if (controller == null) return null;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);

  if (controller.contains(tool.id)) {
    await controller.remove(tool.id);
    _confirm(messenger, 'Removed ${tool.title} from My Tools');
    return false;
  }

  final MyToolsAddResult result = await controller.add(tool.id);
  switch (result) {
    case MyToolsAddResult.added:
      _confirm(messenger, 'Added ${tool.title} to My Tools');
      return true;
    case MyToolsAddResult.alreadyPresent:
      return true;
    case MyToolsAddResult.unknown:
      return false;
    case MyToolsAddResult.full:
      if (!context.mounted) return false;
      final String? replacedId = await showMyToolsFullDialog(
        context,
        controller: controller,
        incoming: tool,
      );
      if (replacedId == null) return false;
      final ToolEntry? replaced = toolEntryById(replacedId);
      final bool ok = await controller.replace(replacedId, tool.id);
      if (ok) {
        _confirm(
          messenger,
          replaced == null
              ? 'Added ${tool.title} to My Tools'
              : 'Replaced ${replaced.title} with ${tool.title}',
        );
      }
      return ok;
  }
}

void _confirm(ScaffoldMessengerState? messenger, String message) {
  if (messenger == null) return;
  HapticFeedback.selectionClick();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The list-is-full dialog: names the limit, lists the current tools, and lets
/// the user pick one to replace with [incoming], or cancel. Returns the id the
/// user chose to replace, or null on cancel / dismiss.
Future<String?> showMyToolsFullDialog(
  BuildContext context, {
  required MyToolsController controller,
  required ToolEntry incoming,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      final TextTheme text = Theme.of(dialogContext).textTheme;
      final AppColorScheme colors = dialogContext.colors;
      final List<ToolEntry> current = controller.tools;
      return AlertDialog(
        scrollable: true,
        title: const Text('My Tools is full'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSpacing.contentMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'My Tools holds ${MyToolsController.maxTools} tools. '
                'Choose one to replace with ${incoming.title}, or cancel.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (int i = 0; i < current.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                MyToolsChoiceRow(
                  key: ValueKey<String>('replace-${current[i].id}'),
                  title: current[i].title,
                  semanticLabel:
                      'Replace ${current[i].title} with ${incoming.title}',
                  onTap: () => Navigator.of(dialogContext).pop(current[i].id),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}

/// The clear-all confirmation (Keith, 2026-10-03, spec item 4). Returns true
/// only when the user confirms.
Future<bool> showClearMyToolsDialog(BuildContext context, {required int count}) {
  final String question = count == 1
      ? 'Remove the 1 tool from My Tools?'
      : 'Remove all $count tools from My Tools?';
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      final TextTheme text = Theme.of(dialogContext).textTheme;
      final AppColorScheme colors = dialogContext.colors;
      return AlertDialog(
        title: Text(question),
        content: Text(
          'The tools stay in the app. Only this list is cleared, and you can '
          'add tools back at any time.',
          style: text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      );
    },
  ).then((bool? v) => v ?? false);
}

/// A full-width choice row in the list-is-full dialog: surface1, card radius,
/// borderStrong boundary at rest, the §8.3 lime ring on keyboard focus, 48dp.
class MyToolsChoiceRow extends StatefulWidget {
  const MyToolsChoiceRow({
    required this.title,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String title;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<MyToolsChoiceRow> createState() => _MyToolsChoiceRowState();
}

class _MyToolsChoiceRowState extends State<MyToolsChoiceRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Semantics(
      button: true,
      enabled: true,
      excludeSemantics: true,
      label: widget.semanticLabel,
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (bool f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: myToolsBorder(colors, focused: _focused),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              widget.title,
              style: text.bodyLarge?.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The interactive-boundary border used by every My Tools surface: the §8.3
/// focus ring when focused (darkened-lime 3px in light), else the §8.1
/// borderStrong boundary (1.5px in light). Same values as ToolRow.
Border myToolsBorder(AppColorScheme colors, {required bool focused}) {
  return focused
      ? Border.all(
          color: colors.isLight ? colors.textAccent : colors.primary,
          width: colors.isLight ? 3 : 2,
        )
      : Border.all(
          color: colors.borderStrong,
          width: colors.isLight ? 1.5 : 1,
        );
}
