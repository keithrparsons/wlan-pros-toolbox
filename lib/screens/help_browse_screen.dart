// HelpBrowseScreen — the "Help & Documentation" browse surface.
//
// Lists every tool that has a help entry, grouped by its catalog category and
// in the catalog's home-grid order (Test Network, Networking Tools, Calculators
// & Tools, Quick Reference). Each row opens that tool's shared ToolHelpSheet.
//
// Reached from the About screen's "Help and Documentation" section ("Browse
// tool help"); registered as a named route (AppRouter.helpBrowse).
//
// GROUPING: the catalog (kToolCategories) is the source of truth for which
// category a tool belongs to and the order tools appear in — the same order the
// rest of the app uses. Help content is looked up by the catalog tool id via
// helpForId(). A tool with no help entry is simply not listed (no fabricated
// help, GL-005). On web, kToolCategories already drops the two network
// categories, so this screen lists only the web-safe tools there, matching
// every other navigation surface.
//
// Tokens: GL-003 §8.1 surface stack, §4 spacing, §8.5 type, §8.3 focus ring
// (inherited on the row InkWell via the local focus-border, matching
// category_screen). Centered + width-capped via CenteredContent so the column
// matches every other screen (Vera web-demo gate, 2026-06-02).

import 'package:flutter/material.dart';

import '../data/tool_catalog.dart';
import '../services/help/tool_help.dart';
import '../services/help/tool_help_loader.dart';
import '../theme/app_tokens.dart';
import '../widgets/centered_content.dart';
import '../widgets/tool_help_sheet.dart';

/// One category and the help-bearing tools within it, in catalog order.
class HelpGroup {
  const HelpGroup({required this.title, required this.entries});

  final String title;
  final List<HelpRow> entries;
}

/// One browse row: the tool's catalog title + the help entry it opens. Title
/// comes from the catalog (the user-facing name they see elsewhere); the body
/// comes from the help JSON.
class HelpRow {
  const HelpRow({required this.title, required this.help});

  final String title;
  final ToolHelp help;
}

/// Build the grouped browse model from the catalog + help store. Categories in
/// catalog order; tools in catalog order within each; a tool with no help entry
/// is skipped; an empty category is dropped.
List<HelpGroup> buildHelpGroups() {
  final List<HelpGroup> groups = <HelpGroup>[];
  for (final ToolCategory category in kToolCategories) {
    final List<HelpRow> rows = <HelpRow>[];
    for (final ToolEntry tool in category.tools) {
      final ToolHelp? help = helpForId(tool.id);
      if (help != null) {
        rows.add(HelpRow(title: tool.title, help: help));
      }
    }
    if (rows.isNotEmpty) {
      groups.add(HelpGroup(title: category.title, entries: rows));
    }
  }
  return groups;
}

class HelpBrowseScreen extends StatelessWidget {
  const HelpBrowseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<HelpGroup> groups = buildHelpGroups();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Documentation'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            // Honest empty state: if the help asset failed to load there are no
            // groups to show, and we say so rather than render a blank screen.
            if (groups.isEmpty) {
              return _EmptyState(text: text, edge: edge);
            }

            return CenteredContent(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge + AppSpacing.sm,
                ),
                children: <Widget>[
                  Text(
                    'Open any tool for what it does, how to use it, the inputs '
                    'it takes, and the honest field notes. Tap a tool to read '
                    'its help.',
                    style: text.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final HelpGroup group in groups) ...<Widget>[
                    _GroupHeading(title: group.title, count: group.entries.length),
                    const SizedBox(height: AppSpacing.xs),
                    for (final HelpRow row in group.entries) ...<Widget>[
                      _HelpToolRow(row: row),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A category heading with a count, exposed as a navigable heading node
/// (WCAG 1.3.1). Count is read into the same node so a screen reader hears
/// "Calculators & Tools, 23 tools".
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String plural = count == 1 ? 'tool' : 'tools';
    return Semantics(
      header: true,
      label: '$title, $count $plural',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(title, style: text.headlineSmall),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$count $plural',
            style: text.labelMedium?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable tool row that opens the shared help sheet. Mirrors the
/// category_screen row treatment: surface1 card, borderStrong at rest, 2px lime
/// focus ring on keyboard focus (§8.3), single curated semantic label.
class _HelpToolRow extends StatefulWidget {
  const _HelpToolRow({required this.row});

  final HelpRow row;

  @override
  State<_HelpToolRow> createState() => _HelpToolRowState();
}

class _HelpToolRowState extends State<_HelpToolRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ToolHelp help = widget.row.help;

    // §8.3 — borderStrong at rest (focusable UI component), 2px lime on focus.
    final Border border = _focused
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(color: AppColors.borderStrong, width: 1);

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: '${widget.row.title}. ${help.purpose}',
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showToolHelpSheet(context, help),
          onFocusChange: (bool hasFocus) {
            if (hasFocus != _focused) setState(() => _focused = hasFocus);
          },
          child: Container(
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.rowPadding,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.row.title,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (help.purpose.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          help.purpose,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Honest empty state — shown only if the help asset failed to load (so there
/// are zero groups). We say what happened rather than render a blank list.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text, required this.edge});

  final TextTheme text;
  final double edge;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(edge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.menu_book_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tool help could not be loaded',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
