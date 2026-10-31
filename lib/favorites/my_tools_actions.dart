// My Tools — the shared add/remove flow and its two dialogs.
//
// One flow, every entry point: the long-press on a tool row (category list,
// search results), every Educational Resources row (2026-10-09), and the star
// button all call [toggleMyToolsItem], so the list-is-full behavior and the
// confirmation wording are identical wherever a user adds something. Rows get
// their long-press, right-click menu, context-menu key and screen-reader
// action from one place, [MyToolsRowHooks].
//
// Dialogs are designed surfaces on the app dialogTheme (surface2, card
// radius), never a browser confirm. Every value is a GL-003 token.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../data/tool_catalog.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import 'my_tools_controller.dart';
import 'my_tools_item.dart';

/// Adds [tool] to My Tools, or removes it when it is already there. See
/// [toggleMyToolsItem].
Future<bool?> toggleMyTool(BuildContext context, ToolEntry tool) =>
    toggleMyToolsItem(context, MyToolsItem.tool(tool));

/// Adds [item] to My Tools, or removes it when it is already there. When the
/// list is full, asks which entry to replace (spec choice 3). Shows a short
/// confirmation in the nearest [ScaffoldMessenger]. Returns the controller's
/// resulting membership for [item], or null when no controller is in scope.
Future<bool?> toggleMyToolsItem(BuildContext context, MyToolsItem item) async {
  final MyToolsController? controller = MyToolsScope.read(context);
  if (controller == null) return null;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);

  if (controller.contains(item.id)) {
    await controller.remove(item.id);
    _confirm(messenger, 'Removed ${item.title} from My Tools');
    return false;
  }

  final MyToolsAddResult result = await controller.add(item.id);
  switch (result) {
    case MyToolsAddResult.added:
      _confirm(messenger, 'Added ${item.title} to My Tools');
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
        incoming: item,
      );
      if (replacedId == null) return false;
      final MyToolsItem? replaced = myToolsItemById(replacedId);
      final bool ok = await controller.replace(replacedId, item.id);
      if (ok) {
        _confirm(
          messenger,
          replaced == null
              ? 'Added ${item.title} to My Tools'
              : 'Replaced ${replaced.title} with ${item.title}',
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

/// The list-is-full dialog: names the limit, lists the current entries, and
/// lets the user pick one to replace with [incoming], or cancel. Returns the id
/// the user chose to replace, or null on cancel / dismiss.
Future<String?> showMyToolsFullDialog(
  BuildContext context, {
  required MyToolsController controller,
  required MyToolsItem incoming,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      final TextTheme text = Theme.of(dialogContext).textTheme;
      final AppColorScheme colors = dialogContext.colors;
      final List<MyToolsItem> current = controller.items;
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

/// What a row needs to offer Add to / Remove from My Tools: a long-press, a
/// right-click menu, the context-menu key and Shift-F10 menu, a named
/// screen-reader action, and "In My Tools." on its label. Built fresh in the
/// row's build with the row's own context, which also anchors the menu.
///
/// With no [MyToolsScope] above the row (a bare widget test), or when
/// [enabled] is false, every hook is null or empty and the row is unchanged.
class MyToolsRowHooks {
  MyToolsRowHooks._(this._context, this._item, this.enabled, this.inMyTools);

  /// Reads the controller with a dependency, so the row rebuilds when the
  /// list changes and its label and menu wording follow.
  factory MyToolsRowHooks.of(
    BuildContext context,
    MyToolsItem item, {
    bool enabled = true,
  }) {
    final MyToolsController? myTools = MyToolsScope.maybeOf(context);
    return MyToolsRowHooks._(
      context,
      item,
      enabled && myTools != null,
      myTools?.contains(item.id) ?? false,
    );
  }

  final BuildContext _context;
  final MyToolsItem _item;

  /// True when the row can add or remove at all.
  final bool enabled;

  /// True when [_item] is in My Tools now.
  final bool inMyTools;

  /// The long-press handler: toggles straight away, as on a tool row.
  VoidCallback? get onLongPress =>
      enabled ? () => toggleMyToolsItem(_context, _item) : null;

  /// The right-click handler: opens the one-item menu at the pointer.
  GestureTapUpCallback? get onSecondaryTapUp =>
      enabled ? (TapUpDetails d) => showMenuAt(d.globalPosition) : null;

  /// The context-menu key and Shift-F10, for a [CallbackShortcuts] around
  /// the row's focusable part.
  Map<ShortcutActivator, VoidCallback> get shortcuts => !enabled
      ? const <ShortcutActivator, VoidCallback>{}
      : <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.contextMenu): showMenuAt,
          const SingleActivator(LogicalKeyboardKey.f10, shift: true):
              showMenuAt,
        };

  /// The named screen-reader action.
  Map<CustomSemanticsAction, VoidCallback>? get semanticsActions => !enabled
      ? null
      : <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(
            label: inMyTools ? 'Remove from My Tools' : 'Add to My Tools',
          ): () =>
              toggleMyToolsItem(_context, _item),
        };

  /// [base] with "In My Tools." added when the entry is in the list.
  String label(String base) => !inMyTools
      ? base
      : '$base${base.trimRight().endsWith('.') ? '' : '.'} In My Tools.';

  /// Opens the one-item My Tools menu. A right-click anchors it at the
  /// pointer ([globalPosition]); the keyboard path anchors it on the row.
  Future<void> showMenuAt([Offset? globalPosition]) async {
    final BuildContext context = _context;
    final MyToolsController? myTools = MyToolsScope.read(context);
    if (myTools == null || !enabled || !context.mounted) return;
    final RenderBox row = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final Rect anchor = globalPosition != null
        ? overlay.globalToLocal(globalPosition) & Size.zero
        : row.localToGlobal(Offset.zero, ancestor: overlay) & row.size;
    final bool inList = myTools.contains(_item.id);
    final bool? picked = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      items: <PopupMenuEntry<bool>>[
        PopupMenuItem<bool>(
          key: ValueKey<String>('my-tools-menu-${_item.id}'),
          value: true,
          child: Text(inList ? 'Remove from My Tools' : 'Add to My Tools'),
        ),
      ],
    );
    if (picked != true || !context.mounted) return;
    await toggleMyToolsItem(context, _item);
  }
}

/// The clear-all confirmation (Keith, 2026-10-03, spec item 4). Returns true
/// only when the user confirms.
Future<bool> showClearMyToolsDialog(
  BuildContext context, {
  required int count,
}) {
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
      : Border.all(color: colors.borderStrong, width: colors.isLight ? 1.5 : 1);
}
