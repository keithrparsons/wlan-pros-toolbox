// Educational Resources — a data-driven directory of Wi-Fi learning resources,
// grouped by topic, searchable, fully offline (bundled JSON asset).
//
// Clones the app's existing bundled-JSON reference pattern (Well-Known Ports):
//   bundled asset → EducationalResourcesService.fromJson → list screen → detail.
// The curated entries render in topic groups (ordered by `_meta.topics`), each
// row showing title + summary. A free-text search field filters the rendered rows
// live, matching the app's other list/reference search UX (substring match,
// SC 4.1.3 live count announcement).
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner + AT announce.
//  - error   → the bundled asset failed to load/parse (should not happen in a
//    shipped build); an honest message card.
//  - success → topic groups with rows, OR the filtered subset.
//  - empty   → a query that matches nothing; an honest "no match" card.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../data/tool_catalog.dart';
import '../../../services/educational/educational_resources_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/centered_content.dart';
import 'educational_resource_detail_screen.dart';
import 'resource_badges.dart';

/// Header label for the in-app PDF reference-cards section, also the chip label
/// and the filter sentinel for the "Reference Cards" filter selection.
const String _kReferenceCardsSection = 'Reference Cards';

/// The PDF reference cards that render at the top of the directory. They are the
/// `tools` of the Educational Resources catalog category (moved there from Quick
/// Reference 2026-06-04); each opens its existing `/tools/<id>` PdfReferenceScreen
/// route. Reading the catalog keeps a single source of truth — the cards are not
/// re-listed here.
List<ToolEntry> educationalReferenceCards() {
  for (final ToolCategory c in kToolCategories) {
    if (c.id == 'educational-resources') {
      return c.tools.where((ToolEntry t) => t.isLive).toList(growable: false);
    }
  }
  return const <ToolEntry>[];
}

/// Asset path for the bundled directory. Overridable in tests so a fixture
/// string can stand in for the bundled asset.
const String kEducationalResourcesAsset =
    'assets/data/educational_resources.json';

class EducationalResourcesScreen extends StatefulWidget {
  const EducationalResourcesScreen({super.key, this.service, this.cards});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final EducationalResourcesService? service;

  /// Inject the reference-card list in tests so the widget test doesn't depend
  /// on the live catalog. Defaults to [educationalReferenceCards] (the catalog).
  final List<ToolEntry>? cards;

  @override
  State<EducationalResourcesScreen> createState() =>
      _EducationalResourcesScreenState();
}

class _EducationalResourcesScreenState
    extends State<EducationalResourcesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();

  EducationalResourcesService? _service;
  String? _loadError;
  String _query = '';

  /// The selected filter section, or null for "All". Holds either
  /// [_kReferenceCardsSection] or a topic name. Meaningful only when no free-text
  /// query is active (the chips hide while the user is typing, mirroring the
  /// Quick Reference category screen).
  String? _selectedSection;

  late final List<ToolEntry> _cards = widget.cards ?? educationalReferenceCards();

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _service = widget.service;
    } else {
      _loadAsset();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    try {
      final String raw =
          await rootBundle.loadString(kEducationalResourcesAsset);
      final EducationalResourcesService svc =
          EducationalResourcesService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _loadError = 'Could not load the educational resources: $e',
      );
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final EducationalResourcesService? svc = _service;
    if (svc == null) return;
    // SC 4.1.3 — announce the live result count so AT users hear the list
    // change as they type, without focus leaving the field.
    final int n = svc.search(value).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching resources' : '$n matching resource${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Educational Resources'),
        toolbarHeight: 64,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return CenteredContent(
              child: _body(edge),
            );
          },
        ),
      ),
    );
  }

  Widget _body(double edge) {
    if (_loadError != null) {
      return _PaddedMessage(
        edge: edge,
        icon: Icons.error_outline,
        title: 'Resources unavailable',
        body: _loadError!,
      );
    }

    final EducationalResourcesService? svc = _service;
    if (svc == null) {
      return Padding(
        padding: EdgeInsets.all(edge),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            // Semantics is not const, so this subtree cannot be const.
            child: Semantics(
              label: 'Loading educational resources',
              liveRegion: true,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      );
    }

    // The total shown in the intro: reference cards + online resources, the
    // same figure the home tile's countLabelOverride pins.
    final int total = _cards.length + svc.count;

    final bool filtering = _query.trim().isNotEmpty;

    final List<Widget> children = <Widget>[
      _IntroCard(total: total),
      const SizedBox(height: AppSpacing.sm),
      _SearchField(
        controller: _queryCtrl,
        onChanged: _onQueryChanged,
      ),
    ];

    // Filter chips — only when not actively typing a free-text query (the two
    // filters would compound confusingly; mirrors the Quick Reference screen).
    if (!filtering) {
      final List<String> sections = _sectionChips(svc);
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

    children
      ..add(const SizedBox(height: AppSpacing.sm))
      ..addAll(_content(svc, filtering));

    return ListView(
      padding: EdgeInsets.fromLTRB(
        edge,
        AppSpacing.sm,
        edge,
        edge + AppSpacing.sm,
      ),
      children: children,
    );
  }

  /// The chip labels in order: "Reference Cards" (only when cards exist), then
  /// one per online topic in `_meta.topics` order. The "All" chip is added by
  /// [_SectionFilterChips] itself.
  List<String> _sectionChips(EducationalResourcesService svc) {
    final List<String> out = <String>[];
    if (_cards.isNotEmpty) out.add(_kReferenceCardsSection);
    for (final ResourceGroup g in svc.grouped()) {
      out.add(g.topic);
    }
    return out;
  }

  /// The content under the search + chips, honoring the active query and the
  /// selected filter section.
  List<Widget> _content(EducationalResourcesService svc, bool filtering) {
    // FREE-TEXT SEARCH: flatten to matching online resources across all topics
    // (reference cards are not in the search index, so they are hidden while a
    // query is active — same collapse behavior as the category screen).
    if (filtering) {
      final List<EducationalResource> filtered = svc.search(_query);
      final List<ResourceGroup> groups = svc.grouped(filtered);
      if (groups.isEmpty) return <Widget>[_NoMatch(query: _query.trim())];
      return _topicGroupWidgets(groups);
    }

    final bool showCards = _selectedSection == null ||
        _selectedSection == _kReferenceCardsSection;
    final bool showTopics = _selectedSection != _kReferenceCardsSection;

    final List<Widget> out = <Widget>[];

    if (showCards && _cards.isNotEmpty) {
      out.addAll(_referenceCardWidgets());
    }

    if (showTopics) {
      List<ResourceGroup> groups = svc.grouped();
      if (_selectedSection != null) {
        groups = groups
            .where((ResourceGroup g) => g.topic == _selectedSection)
            .toList(growable: false);
      }
      if (groups.isNotEmpty) {
        if (out.isNotEmpty) out.add(const SizedBox(height: AppSpacing.lg));
        out.addAll(_topicGroupWidgets(groups));
      }
    }

    // Defensive: a filter that matched nothing (should not happen with valid
    // chips) renders the honest no-match state rather than a blank screen.
    if (out.isEmpty) out.add(_NoMatch(query: ''));
    return out;
  }

  /// The "Reference Cards" section: a header with count, then one tappable row
  /// per card (reusing the directory row visual style), opening its
  /// PdfReferenceScreen route by name.
  List<Widget> _referenceCardWidgets() {
    final List<Widget> out = <Widget>[
      _TopicHeader(topic: _kReferenceCardsSection, count: _cards.length),
      const SizedBox(height: AppSpacing.xs),
    ];
    for (int i = 0; i < _cards.length; i++) {
      out.add(_ReferenceCardRow(card: _cards[i]));
      if (i < _cards.length - 1) {
        out.add(const SizedBox(height: AppSpacing.xs));
      }
    }
    return out;
  }

  List<Widget> _topicGroupWidgets(
    List<ResourceGroup> groups,
  ) {
    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final ResourceGroup group = groups[g];
      out.add(_TopicHeader(topic: group.topic, count: group.count));
      out.add(const SizedBox(height: AppSpacing.xs));
      for (int i = 0; i < group.resources.length; i++) {
        out.add(_ResourceRow(resource: group.resources[i]));
        if (i < group.resources.length - 1) {
          out.add(const SizedBox(height: AppSpacing.xs));
        }
      }
      if (g < groups.length - 1) {
        out.add(const SizedBox(height: AppSpacing.lg));
      }
    }
    return out;
  }
}

/// One-line directory intro + count.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        '$total curated places to learn Wi-Fi: tools, talk archives, channels, '
        'podcasts, blogs, and training. Tap any resource to read more and open '
        'its website.',
        style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

/// In-screen search field (§8.4 input spec).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'Search educational resources by name, topic, or tag',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        // 16px field text dodges iOS Safari auto-zoom (§8.4).
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: AppColors.textPrimary),
        cursorColor: AppColors.primary,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, color: AppColors.textTertiary),
          hintText: 'Search resources…',
        ),
      ),
    );
  }
}

/// A topic group header with a count chip (matches the reference section-header
/// register: H3 title + neutral count pill).
class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic, required this.count});

  final String topic;
  final int count;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: '$topic, $count resource${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                topic,
                style: text.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$count',
                style: text.labelLarge?.copyWith(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One directory row: title + summary + cost/level badges, taps to the detail
/// screen. Carries the §8.3 focus ring (lime 2px on keyboard focus).
class _ResourceRow extends StatefulWidget {
  const _ResourceRow({required this.resource});

  final EducationalResource resource;

  @override
  State<_ResourceRow> createState() => _ResourceRowState();
}

class _ResourceRowState extends State<_ResourceRow> {
  bool _focused = false;

  void _open() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            EducationalResourceDetailScreen(resource: widget.resource),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final EducationalResource r = widget.resource;

    final Border rowBorder = _focused
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(color: AppColors.borderStrong, width: 1);

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '${r.title}. ${r.summary} '
          '${r.cost.label}. ${r.level.label}.',
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          onFocusChange: (bool f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: Container(
            decoration: BoxDecoration(
              border: rowBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.rowPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        r.title,
                        style: text.bodyLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.summary,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ResourceMetaBadges(
                        cost: r.cost,
                        level: r.level,
                      ),
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

/// One reference-card row: the card title, tapping it pushes the existing
/// PdfReferenceScreen route by name. Mirrors [_ResourceRow]'s visual register
/// (surface-1 card, §8.3 lime focus ring, chevron affordance) but carries no
/// cost/level badges — a card is an in-app PDF, not an external destination.
class _ReferenceCardRow extends StatefulWidget {
  const _ReferenceCardRow({required this.card});

  final ToolEntry card;

  @override
  State<_ReferenceCardRow> createState() => _ReferenceCardRowState();
}

class _ReferenceCardRowState extends State<_ReferenceCardRow> {
  bool _focused = false;

  void _open() {
    Navigator.of(context).pushNamed(widget.card.routeName);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ToolEntry card = widget.card;

    final Border rowBorder = _focused
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(color: AppColors.borderStrong, width: 1);

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '${card.title}. ${card.description}.',
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          onFocusChange: (bool f) {
            if (f != _focused) setState(() => _focused = f);
          },
          child: Container(
            decoration: BoxDecoration(
              border: rowBorder,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.rowPadding,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.sm),
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        card.title,
                        style: text.bodyLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card.description,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
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

/// Section filter chips: an "All" chip plus one per section (Reference Cards +
/// each online topic). Selected = lime (§8.3 active/selected), unselected =
/// neutral §8.17. An edu-local copy of the Quick Reference category screen's
/// `_SectionFilterChips` (kept local so the shared category screen is untouched).
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
/// Unselected → neutral §8.17 (surface-2 fill, secondary text). Carries its own
/// §8.3 lime focus ring (the global iconButtonTheme does not cover an InkWell).
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
    final TextTheme text = Theme.of(context).textTheme;
    final bool sel = widget.selected;

    final Border border = _focused
        ? Border.all(color: AppColors.primary, width: 2)
        : Border.all(
            color: sel ? AppColors.primary : AppColors.borderStrong,
            width: 1,
          );

    return Semantics(
      button: true,
      selected: sel,
      label: widget.label,
      excludeSemantics: true,
      child: Material(
        color: sel ? AppColors.primary : AppColors.surface2,
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
                color: sel ? AppColors.secondary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-screen no-results state when the live filter matches nothing.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.search_off_outlined,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isEmpty
                ? 'No resources loaded.'
                : 'No resources match "$query".',
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// An error / message card with leading icon (mirrors the port-reference
/// message card register).
class _PaddedMessage extends StatelessWidget {
  const _PaddedMessage({
    required this.edge,
    required this.icon,
    required this.title,
    required this.body,
  });

  final double edge;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(edge),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: text.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
