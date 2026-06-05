// SearchScreen — global cross-category tool search (mockup 04).
//
// Reached from the home search field. An autofocused, lime-bordered §8.4 input;
// a mono "N results across M categories" count line; results grouped by category
// with a neutral §8.17 source tag per row and the matched term highlighted in
// lime in the title. Reuses the shared ToolRow (lib/widgets/tool_row.dart) and
// the pure-Dart search engine (lib/data/tool_search.dart, which reads the
// web-gated catalog).
//
// States (all explicit):
//   * empty query  → quiet "Start typing to search all tools" hint
//   * no results   → "No tools match '<query>'" with the construction icon
//   * success      → grouped results list

import 'package:flutter/material.dart';

import '../data/content_type.dart';
import '../data/tool_search.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../widgets/centered_content.dart';
import '../widgets/tool_row.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String q = _query.trim();
    final List<ToolSearchHit> hits = searchTools(_query);

    return Scaffold(
      appBar: AppBar(title: const Text('Search'), toolbarHeight: 64),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return CenteredContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      edge,
                      AppSpacing.sm,
                      edge,
                      AppSpacing.xs,
                    ),
                    child: _SearchField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: (String v) => setState(() => _query = v),
                      onClear: () {
                        _controller.clear();
                        setState(() => _query = '');
                        _focusNode.requestFocus();
                      },
                    ),
                  ),
                  Expanded(
                    child: _body(text, edge, q, hits),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _body(
    TextTheme text,
    double edge,
    String q,
    List<ToolSearchHit> hits,
  ) {
    final AppColorScheme colors = context.colors;
    if (q.isEmpty) {
      return _HintState(
        icon: Icons.search,
        message: 'Start typing to search all tools',
        text: text,
      );
    }
    if (hits.isEmpty) {
      return _HintState(
        icon: Icons.construction_outlined,
        message: 'No tools match "$q"',
        text: text,
      );
    }

    final int categories = distinctCategoryCount(hits);
    return ListView(
      padding: EdgeInsets.fromLTRB(edge, 0, edge, edge + AppSpacing.sm),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(
              '${hits.length} ${hits.length == 1 ? 'result' : 'results'} '
              'across $categories '
              '${categories == 1 ? 'category' : 'categories'}',
              // Mono count line (mockup 04) — DM Mono tabular feel.
              style: text.bodyMedium?.copyWith(
                fontFamily: 'DM Mono',
                color: colors.textTertiary,
              ),
            ),
          ),
        ),
        for (int i = 0; i < hits.length; i++) ...<Widget>[
          _hitRow(hits[i], q),
          if (i < hits.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _hitRow(ToolSearchHit hit, String query) {
    // Description/keyword-only hits get the "matches in content" note (mockup
    // 04). Title hits show only the source tag.
    String? note;
    switch (hit.matchedOn) {
      case ToolMatchField.title:
        note = null;
      case ToolMatchField.description:
        note = 'matches in content';
      case ToolMatchField.keyword:
        note = hit.matchedKeyword == null
            ? 'matches in content'
            : 'matches "${hit.matchedKeyword}"';
    }

    return ToolRow(
      key: ValueKey<String>('search-${hit.tool.id}'),
      tool: hit.tool,
      highlightQuery: query,
      contentType: contentTypeFor(hit.tool, hit.categoryId),
      categorySourceLabel: hit.categoryTitle,
      matchNote: note,
      onTap: () => Navigator.of(context).pushNamed(hit.tool.routeName),
    );
  }
}

/// The autofocused, lime-on-focus §8.4 search field with a clear affordance.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      onChanged: onChanged,
      style: text.bodyLarge?.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search, color: colors.textTertiary),
        hintText: 'Search all tools…',
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                tooltip: 'Clear search',
                icon: Icon(
                  Icons.cancel_outlined,
                  color: colors.textTertiary,
                ),
              ),
      ),
      textInputAction: TextInputAction.search,
    );
  }
}

/// Shared quiet state for the empty-query hint and the no-results message.
class _HintState extends StatelessWidget {
  const _HintState({
    required this.icon,
    required this.message,
    required this.text,
  });

  final IconData icon;
  final String message;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: colors.textTertiary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
