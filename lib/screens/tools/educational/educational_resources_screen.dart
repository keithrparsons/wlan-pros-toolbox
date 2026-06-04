// Educational Resources — a data-driven directory of Wi-Fi learning resources,
// grouped by topic, searchable, fully offline (bundled JSON asset).
//
// Clones the app's existing bundled-JSON reference pattern (Well-Known Ports):
//   bundled asset → EducationalResourcesService.fromJson → list screen → detail.
// The 52 entries render in 7 topic groups (ordered by `_meta.topics`), each row
// showing title + summary. A free-text search field filters the rendered rows
// live, matching the app's other list/reference search UX (substring match,
// SC 4.1.3 live count announcement).
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner + AT announce.
//  - error   → the bundled asset failed to load/parse (should not happen in a
//    shipped build); an honest message card.
//  - success → topic groups with rows, OR the filtered subset.
//  - empty   → a query that matches nothing; an honest "no match" card.
//
// ATTRIBUTION: the destinations portion of the directory (the wlan-talks set —
// conference archives, YouTube, podcasts, independent blogs, training) is
// credited "Inspired by wlan-talks.net by Victor Njoroge" per `_meta.attribution`
// and scoped to the destination buckets only (`_meta.attribution_scope`). The
// credit renders as a small footer note UNDER each destination topic group, and
// never on the canonical tools / vendor-doc groups.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../services/educational/educational_resources_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/centered_content.dart';
import 'educational_resource_detail_screen.dart';
import 'resource_badges.dart';

/// Asset path for the bundled directory. Overridable in tests so a fixture
/// string can stand in for the bundled asset.
const String kEducationalResourcesAsset =
    'assets/data/educational_resources.json';

class EducationalResourcesScreen extends StatefulWidget {
  const EducationalResourcesScreen({super.key, this.service});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final EducationalResourcesService? service;

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

    final List<EducationalResource> filtered = svc.search(_query);
    final List<ResourceGroup> groups = svc.grouped(filtered);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        edge,
        AppSpacing.sm,
        edge,
        edge + AppSpacing.sm,
      ),
      children: <Widget>[
        _IntroCard(total: svc.count),
        const SizedBox(height: AppSpacing.sm),
        _SearchField(
          controller: _queryCtrl,
          onChanged: _onQueryChanged,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (groups.isEmpty)
          _NoMatch(query: _query.trim())
        else
          ..._groupSlivers(svc, groups),
      ],
    );
  }

  List<Widget> _groupSlivers(
    EducationalResourcesService svc,
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
      // Destinations-only credit, scoped per `_meta.attribution_scope`.
      if (svc.attribution.isNotEmpty && svc.isDestinationTopic(group.topic)) {
        out.add(const SizedBox(height: AppSpacing.xs));
        out.add(_AttributionNote(text: svc.attribution));
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
        '$total curated places to learn Wi-Fi — tools, vendor docs, talk '
        'archives, channels, podcasts, blogs, and training. Tap any resource '
        'to read more and open its website.',
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

/// The destinations attribution note — a small, quiet footer line under each
/// destination topic group (`_meta.attribution`, scoped per
/// `_meta.attribution_scope`).
class _AttributionNote extends StatelessWidget {
  const _AttributionNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2, right: AppSpacing.xs),
            child: Icon(
              Icons.favorite_outline,
              size: 14,
              color: AppColors.textTertiary,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: t.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
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
