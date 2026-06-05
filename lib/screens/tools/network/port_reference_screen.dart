// Well-Known Ports tool — search a curated TCP/UDP port reference, offline.
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner with an AT
//    announcement.
//  - error   → the bundled asset failed to load or parse (should not happen in
//    a shipped build); shown via LookupErrorCard so the surface matches the
//    other tools.
//  - success → matching ports rendered as ValueRows.
//  - empty   → a query that matches nothing; an honest "no match" card, never a
//    fabricated row.
//
// This is a fully offline tool (bundled JSON asset), so it works on every
// platform — no NetworkUnavailableView. The service does the indexing/search;
// this screen only loads the asset string once and renders.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../data/tool_assets.dart';
import '../../../services/network/port_reference_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'value_row.dart';

/// Asset path for the curated port table. Overridable in tests so a fixture
/// string can stand in for the bundled asset.
const String kPortReferenceAsset = 'assets/ports/well_known_ports.json';

class PortReferenceScreen extends StatefulWidget {
  const PortReferenceScreen({super.key, this.service});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final PortReferenceService? service;

  @override
  State<PortReferenceScreen> createState() => _PortReferenceScreenState();
}

class _PortReferenceScreenState extends State<PortReferenceScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  PortReferenceService? _service;
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
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    try {
      final String raw = await rootBundle.loadString(kPortReferenceAsset);
      final PortReferenceService svc = PortReferenceService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the port reference: $e');
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // WCAG 4.1.3 — announce the live result count so AT users hear the list
    // change as they type, without focus leaving the field.
    final PortReferenceService? svc = _service;
    if (svc == null) return;
    final int n = svc.search(value).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching ports' : '$n matching port${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Well-Known Ports'),
        toolbarHeight: 64,
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConceptGraphicBand(
                    toolId: 'port-reference',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('port-reference'))
                    const SizedBox(height: AppSpacing.md),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _resultsSection(context),
                  ToolHelpFooter(toolId: 'port-reference'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool ready = _service != null;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Search',
        hint: 'port number or service name',
        semanticLabel: 'Search ports by number or service name',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          enabled: ready,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(hintText: 'e.g. 443 or radius'),
        ),
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    final AppColorScheme colors = context.colors;
    if (_loadError != null) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Reference unavailable',
        body: _loadError!,
      );
    }

    final PortReferenceService? svc = _service;
    if (svc == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            // Semantics is not const, so this subtree cannot be const.
            child: Semantics(
              label: 'Loading port reference',
              liveRegion: true,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.textAccent,
              ),
            ),
          ),
        ),
      );
    }

    final List<PortEntry> results = svc.search(_query);
    if (results.isEmpty) {
      return _MessageCard(
        icon: Icons.search_off,
        title: 'No match',
        body: _query.trim().isEmpty
            ? 'No ports are loaded.'
            : 'No curated port matches "${_query.trim()}".',
      );
    }
    return _ResultsCard(results: results, total: svc.count, query: _query);
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({
    required this.results,
    required this.total,
    required this.query,
  });

  final List<PortEntry> results;
  final int total;
  final String query;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool showingAll = query.trim().isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showingAll
                ? 'All $total ports'
                : '${results.length} of $total ports',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...results.map((PortEntry e) => _PortRow(entry: e)),
        ],
      ),
    );
  }
}

/// One port result: the port/protocol line as a mono ValueRow, with the
/// service name and description underneath.
class _PortRow extends StatelessWidget {
  const _PortRow({required this.entry});

  final PortEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueRow(
            label: entry.name,
            value: '${entry.port} · ${entry.protocolLabel}',
            mono: true,
          ),
          if (entry.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                entry.description,
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
