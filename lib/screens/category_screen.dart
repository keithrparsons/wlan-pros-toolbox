// CategoryScreen — grouped listing for a single category.
//
// Quick Reference (37) and Calculators & Tools (24) render as ordered SECTIONS
// (section headers + per-section count chip) in ONE scroll (mockup 02), plus an
// in-category search field that filters the rendered rows live and a row of
// section filter chips (selected = lime §8.3, unselected = neutral §8.17).
// Categories without a subgroup map (Test Network, Networking Tools) render FLAT
// with no headers, exactly as before — the pinned Test Network order is
// untouched (it stays on the orderedCategoryTools path via groupedCategoryTools).
//
// Live tools route via Navigator.pushNamed (default in ToolRow). Non-live tools
// render as a disabled "Coming soon" row.

import 'package:flutter/material.dart';

import '../data/content_type.dart';
import '../data/tool_catalog.dart';
import '../data/tool_ordering.dart';
import '../data/tool_search.dart';
import '../data/tool_subgroups.dart';
import '../services/network/wifi_details_bridge.dart';
import '../services/network/wifi_info_adapter.dart';
import '../theme/app_color_scheme.dart';
import '../theme/app_tokens.dart';
import '../widgets/centered_content.dart';
import '../widgets/section_header.dart';
import '../widgets/tool_row.dart';
import 'tools/network/install_shortcut_sheet.dart';
import 'tools/network/live_setup_card.dart';

// Ordering moved to lib/data/tool_ordering.dart (to break a screen↔data import
// cycle with tool_subgroups). Re-exported here so existing importers
// (category_tool_order_test.dart and any caller of category_screen.dart) keep
// resolving `orderedCategoryTools` / `kTestNetworkPinnedToolIds` unchanged.
export '../data/tool_ordering.dart'
    show orderedCategoryTools, kTestNetworkPinnedToolIds, kPinnedCategoryId;

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.category,
    this.sourceOverride,
    this.iosBridge,
  });

  final ToolCategory category;

  /// Forces the Wi-Fi data source (tests). Defaults to the host platform. Only
  /// used to decide whether the iOS one-time live-setup banner is eligible.
  final WifiInfoSource? sourceOverride;

  /// Injectable iOS bridge (tests). Defaults to the real Shortcuts bridge. Only
  /// used by the one-time live-setup banner on the Test Network category.
  final WiFiDetailsBridge? iosBridge;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  /// The live in-category filter query (lower-cased compare happens in search).
  String _query = '';

  /// The selected section filter, or null for "All". Only meaningful for grouped
  /// categories; flat categories show no filter row.
  String? _selectedSection;

  /// Whether this category renders as grouped sections (has a subgroup order).
  bool get _grouped => kCategorySubgroupOrder.containsKey(widget.category.id);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.category.title), toolbarHeight: 64),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;

            return CenteredContent(
              child: CustomScrollView(
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      edge,
                      AppSpacing.sm,
                      edge,
                      edge + AppSpacing.sm,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(
                        _bodyChildren(text),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _bodyChildren(TextTheme text) {
    if (widget.category.tools.isEmpty) {
      return <Widget>[_EmptyCategoryState(text: text)];
    }

    final List<Widget> children = <Widget>[
      // iOS-only, one-time live-setup banner. On the Test Network category (the
      // home of the live diagnostics) a new iOS user learns they need the
      // companion Shortcut BEFORE they tap into a live tool and hit an empty
      // wall. It resolves install-state from the App Group flag and removes
      // itself the moment any live payload has ever arrived, so an already-set-up
      // user (e.g. Keith) never sees it and is never nagged. Non-iOS never builds
      // it (macOS reads CoreWLAN natively; web/Android have no Shortcut path).
      if (widget.category.id == kPinnedCategoryId)
        _LiveSetupBanner(
          sourceOverride: widget.sourceOverride,
          iosBridge: widget.iosBridge,
        ),
      // In-category search field (mockup 02). Filters the rendered rows live.
      _InCategorySearchField(
        controller: _searchController,
        hint: 'Search ${widget.category.title}…',
        onChanged: (String v) => setState(() => _query = v),
      ),
    ];

    // Section filter chips — grouped categories only, and only when not actively
    // typing a free-text query (the two filters would compound confusingly).
    if (_grouped && _query.trim().isEmpty) {
      final List<String> sections = groupedCategoryTools(widget.category)
          .map((ToolSection s) => s.header)
          .where((String h) => h.isNotEmpty)
          .toList();
      if (sections.length > 1) {
        children
          ..add(const SizedBox(height: AppSpacing.sm))
          ..add(_SectionFilterChips(
            sections: sections,
            selected: _selectedSection,
            onSelect: (String? s) => setState(() => _selectedSection = s),
          ));
      }
    }

    children.add(const SizedBox(height: AppSpacing.sm));
    children.addAll(_resultsChildren(text));
    return children;
  }

  /// The section/row content under the search + filter controls.
  List<Widget> _resultsChildren(TextTheme text) {
    final bool filtering = _query.trim().isNotEmpty;

    // FREE-TEXT FILTER: flatten to matching rows across the whole category,
    // hiding section structure (mockup 02 collapse behavior).
    if (filtering) {
      final List<ToolSearchHit> hits = searchTools(
        _query,
        categoryId: widget.category.id,
      );
      if (hits.isEmpty) {
        return <Widget>[_NoMatchState(query: _query.trim(), text: text)];
      }
      return _interleaveRows(
        hits.map((ToolSearchHit h) => h.tool).toList(),
      );
    }

    // FLAT CATEGORY (no subgroup map): a single unnamed section, no headers.
    if (!_grouped) {
      final List<ToolEntry> tools = orderedCategoryTools(widget.category);
      return _interleaveRows(tools);
    }

    // GROUPED CATEGORY: ordered sections with headers + count chips. When a
    // section filter is active, render only that section's rows (no header).
    final List<ToolSection> sections = groupedCategoryTools(widget.category);
    final List<Widget> out = <Widget>[];

    if (_selectedSection != null) {
      final ToolSection? sel = sections
          .where((ToolSection s) => s.header == _selectedSection)
          .cast<ToolSection?>()
          .firstWhere((ToolSection? s) => s != null, orElse: () => null);
      if (sel == null) return <Widget>[];
      out.addAll(_interleaveRows(sel.tools));
      return out;
    }

    for (int i = 0; i < sections.length; i++) {
      final ToolSection s = sections[i];
      out.add(SectionHeader(title: s.header, count: s.count));
      out.add(const SizedBox(height: AppSpacing.xs));
      for (int j = 0; j < s.tools.length; j++) {
        out.add(_row(s.tools[j]));
        if (j < s.tools.length - 1) {
          out.add(const SizedBox(height: AppSpacing.sm));
        }
      }
    }
    return out;
  }

  /// Rows separated by sm gaps (the original ListView.separated spacing).
  List<Widget> _interleaveRows(List<ToolEntry> tools) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < tools.length; i++) {
      out.add(_row(tools[i]));
      if (i < tools.length - 1) out.add(const SizedBox(height: AppSpacing.sm));
    }
    return out;
  }

  /// A single tool row. Grouped categories show the neutral §8.17 content-type
  /// chip (mockup 02); flat categories keep the plain description row.
  Widget _row(ToolEntry tool) {
    return ToolRow(
      key: ValueKey<String>(tool.id),
      tool: tool,
      contentType: _grouped
          ? contentTypeFor(tool, widget.category.id)
          : null,
    );
  }
}

/// iOS-only, one-time live-setup banner shown at the top of the Test Network
/// category. Surfaces the companion-Shortcut setup BEFORE a new user taps into a
/// live tool and finds it empty. Self-hides on three honest conditions, so it
/// never nags a user who is already set up:
///   * not the iOS Shortcuts source (macOS / Android / web) — renders nothing;
///   * still resolving install-state — renders nothing (no flicker / no guess);
///   * the app has ever received a live payload (hasEverReceivedPayload) — the
///     Shortcut demonstrably works, so renders nothing permanently.
class _LiveSetupBanner extends StatefulWidget {
  const _LiveSetupBanner({this.sourceOverride, this.iosBridge});

  final WifiInfoSource? sourceOverride;
  final WiFiDetailsBridge? iosBridge;

  @override
  State<_LiveSetupBanner> createState() => _LiveSetupBannerState();
}

class _LiveSetupBannerState extends State<_LiveSetupBanner> {
  late final WifiInfoSource _source;
  WiFiDetailsBridge? _bridge;

  /// Tri-state: null while resolving, true/false once the App Group flag is
  /// read. The banner only renders when this is explicitly false (not set up).
  bool? _everReceived;

  bool get _isIos => _source == WifiInfoSource.iosShortcuts;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();
    if (_isIos) {
      _bridge = widget.iosBridge ?? WiFiDetailsBridge();
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final bool received =
        await (_bridge?.hasEverReceivedPayload() ?? Future<bool>.value(true));
    if (!mounted) return;
    setState(() => _everReceived = received);
  }

  Future<void> _openInstallSheet() async {
    final WiFiDetailsBridge? bridge = _bridge;
    if (bridge == null) return;
    await showInstallShortcutSheet(
      context: context,
      openUrl: bridge.openUrl,
      // Shortcuts-app presence gate + post-install priming flag (consistent with
      // the live tools; the one combined Shortcut drives all of them).
      isShortcutsAppInstalled: bridge.isShortcutsAppInstalled,
      onSetupInitiated: bridge.markSetupInitiated,
      onInstalled: () async {
        // Re-resolve so the banner removes itself if the Shortcut has since
        // delivered a payload. It cannot confirm an install on its own (iOS
        // limit), so it stays until a real payload arrives.
        await _resolve();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Not iOS, still resolving, or already set up → render nothing (and take no
    // vertical space, so the search field stays flush to the top).
    if (!_isIos || _everReceived != false) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: LiveSetupCard.prompt(
        label: 'Set up live Wi-Fi (one-time)',
        onSetUp: _openInstallSheet,
      ),
    );
  }
}

/// The in-category search field (mockup 02), built from the §8.4 input spec.
class _InCategorySearchField extends StatelessWidget {
  const _InCategorySearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      // 16px field text dodges iOS Safari auto-zoom (§8.4).
      style: Theme.of(context)
          .textTheme
          .bodyLarge
          ?.copyWith(color: colors.textPrimary),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search, color: colors.textTertiary),
        hintText: hint,
      ),
      textInputAction: TextInputAction.search,
    );
  }
}

/// Section filter chips: an "All" chip plus one per section. Selected = lime
/// (§8.3 active/selected), unselected = neutral §8.17.
class _SectionFilterChips extends StatelessWidget {
  const _SectionFilterChips({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<String> sections;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<({String? value, String label})> chips =
        <({String? value, String label})>[
      (value: null, label: 'All'),
      ...sections.map((String s) => (value: s, label: s)),
    ];

    return Semantics(
      container: true,
      label: 'Filter by section',
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: <Widget>[
          for (final ({String? value, String label}) c in chips)
            _SelectableFilterChip(
              label: c.label,
              selected: selected == c.value,
              onTap: () => onSelect(c.value),
            ),
        ],
      ),
    );
  }
}

/// One filter chip. Selected → lime fill + charcoal text (§8.3 selected role).
/// Unselected → neutral §8.17 (surface-2 fill, secondary text). The global
/// iconButtonTheme does not cover this (it's an InkWell), so it carries its own
/// §8.3 lime focus ring.
class _SelectableFilterChip extends StatefulWidget {
  const _SelectableFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SelectableFilterChip> createState() => _SelectableFilterChipState();
}

class _SelectableFilterChipState extends State<_SelectableFilterChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool sel = widget.selected;

    final Border border = _focused
        ? Border.all(color: colors.textAccent, width: 2)
        : Border.all(
            color: sel ? colors.textAccent : colors.borderStrong,
            width: 1,
          );

    return Semantics(
      button: true,
      selected: sel,
      label: widget.label,
      excludeSemantics: true,
      child: Material(
        color: sel ? colors.primary : colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (bool f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: Container(
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              widget.label,
              style: text.labelLarge?.copyWith(
                fontSize: AppTextSize.caption,
                fontWeight: FontWeight.w500,
                // §8.3: charcoal text on lime when selected; neutral otherwise.
                color: sel ? colors.onPrimary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-category no-results state when the live filter matches nothing.
class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.query, required this.text});

  final String query;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.search_off_outlined,
            size: 48,
            color: colors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No tools match "$query" here',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Empty state — a category with no tools at all (defensive; not expected).
class _EmptyCategoryState extends StatelessWidget {
  const _EmptyCategoryState({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.construction_outlined,
            size: 48,
            color: colors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No tools in this category yet',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
