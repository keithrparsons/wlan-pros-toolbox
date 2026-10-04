// MyToolsSection — the "My Tools" block on the home screen (spec choice 1),
// directly under the Check My Connection card.
//
// Renders NOTHING while the list is empty, so a user who has never added a tool
// sees the home screen exactly as it was before this feature.
//
// Two modes:
//   * VIEW: the tools as tappable tiles in a two-column grid at every width
//     (Keith, 2026-10-03), so ten tools take five rows and the category tiles
//     stay in view on a phone. Tapping opens the tool through its normal named
//     route, so routes, deep links and presenter mode are untouched.
//   * EDIT (the Edit button): drag to reorder by the handle, plus visible
//     Move up / Move down / Remove buttons. The buttons are the non-drag
//     alternative the spec requires for screen readers, and they also satisfy
//     WCAG 2.2 SC 2.5.7 (Dragging Movements) for pointer users. "Clear all"
//     empties the list after a confirmation (spec item 4); the section then
//     disappears.
//
// Tokens only: surface1 tiles at card radius with the borderStrong boundary,
// the §8.3 ring on focus, §8.5 H3 section heading, §8.7 spacing, 48dp targets.

import 'package:flutter/material.dart';

import '../data/tool_catalog.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../widgets/tool_row.dart' show ToolLeadingIcon;
import 'my_tools_actions.dart';
import 'my_tools_controller.dart';

class MyToolsSection extends StatefulWidget {
  const MyToolsSection({super.key});

  @override
  State<MyToolsSection> createState() => _MyToolsSectionState();
}

class _MyToolsSectionState extends State<MyToolsSection> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final MyToolsController? controller = MyToolsScope.maybeOf(context);
    if (controller == null || controller.isEmpty) {
      // Leave edit mode behind with the list, so a later first add starts in
      // view mode.
      _editing = false;
      return const SizedBox.shrink();
    }
    final List<ToolEntry> tools = controller.tools;

    return Column(
      key: const ValueKey<String>('my-tools-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(
          editing: _editing,
          onEdit: () => setState(() => _editing = true),
          onDone: () => setState(() => _editing = false),
          onClearAll: () => _clearAll(controller),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_editing)
          _EditList(controller: controller, tools: tools)
        else
          _TileGrid(tools: tools),
      ],
    );
  }

  Future<void> _clearAll(MyToolsController controller) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    final bool confirmed = await showClearMyToolsDialog(
      context,
      count: controller.length,
    );
    if (!confirmed) return;
    await controller.clear();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Cleared My Tools')));
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.editing,
    required this.onEdit,
    required this.onDone,
    required this.onClearAll,
  });

  final bool editing;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'My Tools',
              style: text.headlineSmall?.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
        if (editing) ...<Widget>[
          TextButton(
            key: const ValueKey<String>('my-tools-clear-all'),
            onPressed: onClearAll,
            child: const Text('Clear all'),
          ),
          const SizedBox(width: AppSpacing.xs),
          Semantics(
            label: 'Done editing My Tools',
            button: true,
            excludeSemantics: true,
            child: TextButton(
              key: const ValueKey<String>('my-tools-done'),
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ),
        ] else
          Semantics(
            label: 'Edit My Tools',
            button: true,
            excludeSemantics: true,
            child: TextButton(
              key: const ValueKey<String>('my-tools-edit'),
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
          ),
      ],
    );
  }
}

/// View mode: a compact two-column grid at every width (Keith, 2026-10-03:
/// ten full-width rows pushed the category tiles off a phone screen). Rows are
/// equal height per pair. A cell narrower than [_iconCellMinWidth] drops the
/// leading icon so the title keeps usable width; titles wrap to two lines and
/// then ellipsize, and the full title is always the semantics label.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tools});

  final List<ToolEntry> tools;

  static const int _columns = 2;

  /// Below this cell width (phones up to ~460 wide) the 40px icon tile would
  /// leave the title under ~100px, so compact cells show the title alone.
  static const double _iconCellMinWidth = 220;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cellWidth =
            (constraints.maxWidth - AppSpacing.sm * (_columns - 1)) / _columns;
        final bool compact = cellWidth < _iconCellMinWidth;
        final List<Widget> rows = <Widget>[];
        for (int i = 0; i < tools.length; i += _columns) {
          if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.xs));
          final List<Widget> cells = <Widget>[];
          for (int c = 0; c < _columns; c++) {
            if (c > 0) cells.add(const SizedBox(width: AppSpacing.sm));
            final int at = i + c;
            cells.add(
              Expanded(
                child: at < tools.length
                    ? _MyToolTile(tool: tools[at], compact: compact)
                    : const SizedBox.shrink(),
              ),
            );
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class _MyToolTile extends StatefulWidget {
  const _MyToolTile({required this.tool, required this.compact});

  final ToolEntry tool;

  /// Narrow cell: no leading icon, body-medium title (still 600 weight).
  final bool compact;

  @override
  State<_MyToolTile> createState() => _MyToolTileState();
}

class _MyToolTileState extends State<_MyToolTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool compact = widget.compact;
    final Widget title = Text(
      widget.tool.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: (compact ? text.bodyMedium : text.bodyLarge)?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    return Semantics(
      key: ValueKey<String>('my-tools-tile-${widget.tool.id}'),
      container: true,
      button: true,
      enabled: true,
      excludeSemantics: true,
      label: widget.tool.title,
      child: Material(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pushNamed(widget.tool.routeName),
          onFocusChange: (bool f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: myToolsBorder(colors, focused: _focused),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.rowPadding : AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            alignment: Alignment.centerLeft,
            child: compact
                ? title
                : Row(
                    children: <Widget>[
                      ToolLeadingIcon(tool: widget.tool),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: title),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Edit mode: a reorderable list, ONE ROW PER TOOL at every width, with a drag
/// handle and visible Move up / Move down / Remove buttons on every row. It
/// stays single-column because three 48dp buttons plus the handle need the
/// full width; below 440 the buttons drop under the title.
class _EditList extends StatelessWidget {
  const _EditList({required this.controller, required this.tools});

  final MyToolsController controller;
  final List<ToolEntry> tools;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      key: const ValueKey<String>('my-tools-edit-list'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: tools.length,
      onReorderItem: (int from, int to) => controller.reorder(from, to),
      itemBuilder: (BuildContext context, int index) {
        final ToolEntry tool = tools[index];
        return Padding(
          key: ValueKey<String>('my-tools-edit-${tool.id}'),
          padding: EdgeInsets.only(
            bottom: index < tools.length - 1 ? AppSpacing.xs : 0,
          ),
          child: _EditRow(
            index: index,
            tool: tool,
            isFirst: index == 0,
            isLast: index == tools.length - 1,
            onUp: () => controller.moveUp(tool.id),
            onDown: () => controller.moveDown(tool.id),
            onRemove: () => controller.remove(tool.id),
          ),
        );
      },
    );
  }
}

class _EditRow extends StatelessWidget {
  const _EditRow({
    required this.index,
    required this.tool,
    required this.isFirst,
    required this.isLast,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final int index;
  final ToolEntry tool;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    Widget action({
      required String keyName,
      required IconData icon,
      required String tooltip,
      required String semanticLabel,
      required VoidCallback? onPressed,
    }) {
      return Semantics(
        button: true,
        enabled: onPressed != null,
        label: semanticLabel,
        excludeSemantics: true,
        child: IconButton(
          key: ValueKey<String>('my-tools-$keyName-${tool.id}'),
          icon: Icon(icon),
          tooltip: tooltip,
          color: colors.textSecondary,
          // §8.3: disabled foreground is the measured textDisabled token, not
          // the Material opacity default.
          disabledColor: colors.textDisabled,
          onPressed: onPressed,
        ),
      );
    }

    final List<Widget> actions = <Widget>[
      action(
        keyName: 'up',
        icon: Icons.arrow_upward,
        tooltip: 'Move up',
        semanticLabel: 'Move ${tool.title} up',
        onPressed: isFirst ? null : onUp,
      ),
      action(
        keyName: 'down',
        icon: Icons.arrow_downward,
        tooltip: 'Move down',
        semanticLabel: 'Move ${tool.title} down',
        onPressed: isLast ? null : onDown,
      ),
      action(
        keyName: 'remove',
        icon: Icons.remove_circle_outline,
        tooltip: 'Remove',
        semanticLabel: 'Remove ${tool.title} from My Tools',
        onPressed: onRemove,
      ),
    ];

    final Widget handle = ReorderableDragStartListener(
      index: index,
      // The visible handle is for pointer drag; screen readers use the Move
      // buttons, so the handle stays out of the accessibility tree.
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox(
            width: AppSpacing.minTouchTarget,
            height: AppSpacing.minTouchTarget,
            child: Icon(Icons.drag_indicator, color: colors.textTertiary),
          ),
        ),
      ),
    );

    final Widget title = Text(
      tool.title,
      style: text.bodyLarge?.copyWith(
        color: colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );

    return Material(
      color: colors.surface1,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: myToolsBorder(colors, focused: false),
        ),
        padding: const EdgeInsets.only(right: AppSpacing.xxs),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // Below the compact breakpoint the three buttons drop under the
            // title so a long title is never squeezed to a sliver.
            if (constraints.maxWidth < AppSpacing.gridTwoColBreakpoint) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  handle,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: title,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                handle,
                Expanded(child: title),
                ...actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
