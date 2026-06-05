// PLMN ID Reference — a data-driven, searchable, grouped table of 376 US
// mobile-network PLMN IDs (MCC/MNC), fully offline.
//
// Same pattern as the Wi-Fi Glossary and Well-Known Ports: bundled asset →
// PlmnReferenceService.fromJson → grouped list screen. The 376 entries render
// in 7 MCC groups (310–316), each ascending by PLMN ID; search filters by code
// (MCC / MNC / PLMN ID) or by carrier / operator name.
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner with an AT
//    announcement.
//  - error   → the bundled asset failed to load or parse (should not happen in a
//    shipped build); shown via a message card matching the reference register.
//  - success → MCC groups with PLMN rows, OR the filtered subset.
//  - empty   → a query that matches nothing; an honest "no match" panel, never a
//    fabricated row.
//
// Fully offline (bundled JSON), so it ships on every platform incl. web — no
// NetworkUnavailableView. The service does the indexing/search; this screen
// loads the asset string once and renders. All colors via `context.colors`
// (light/dark safe — no raw AppColors).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../services/network/plmn_reference_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_row_semantics.dart';

/// Asset path for the bundled US PLMN table. Overridable in tests so a fixture
/// string can stand in for the bundled asset.
const String kPlmnReferenceAsset = 'assets/data/plmn_us.json';

class PlmnReferenceScreen extends StatefulWidget {
  const PlmnReferenceScreen({super.key, this.service});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final PlmnReferenceService? service;

  @override
  State<PlmnReferenceScreen> createState() => _PlmnReferenceScreenState();
}

class _PlmnReferenceScreenState extends State<PlmnReferenceScreen> {
  final TextEditingController _queryCtrl = TextEditingController();

  PlmnReferenceService? _service;
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
      final String raw = await rootBundle.loadString(kPlmnReferenceAsset);
      final PlmnReferenceService svc = PlmnReferenceService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the PLMN reference: $e');
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final PlmnReferenceService? svc = _service;
    if (svc == null) return;
    // SC 4.1.3 — announce the live result count so AT users hear the list change
    // as they type, without focus leaving the field.
    final int n = svc.search(value).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching PLMN codes' : '$n matching PLMN code${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the current view (filtered subset if searching, else
  /// the full table) as plain text, grouped by MCC. `null` until the service has
  /// loaded or when nothing matches the query, so copy renders disabled in those
  /// states (§8.16 empty/no-results rule).
  String? _buildCopyText() {
    final PlmnReferenceService? svc = _service;
    if (svc == null) return null;
    final List<PlmnGroup> groups = svc.grouped(svc.search(_query));
    if (groups.isEmpty) return null;

    final StringBuffer buf = StringBuffer()..writeln('US PLMN IDs');
    if (_query.trim().isNotEmpty) {
      buf.writeln('Filtered by "${_query.trim()}"');
    }
    for (final PlmnGroup g in groups) {
      buf
        ..writeln()
        ..writeln('MCC ${g.mcc}');
      for (final PlmnEntry e in g.entries) {
        final String parent =
            e.operator.isEmpty || e.operator == e.carrier
                ? ''
                : ' — ${e.operator}';
        buf.writeln(
          '${e.plmnId}\t${e.mccMncLabel}\t${e.carrier}$parent\t${e.status.label}',
        );
      }
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PLMN ID Reference'),
        toolbarHeight: 64,
        // §8.16 — copy the current (grouped) view as plain text. Disabled until
        // results exist; null payload drops it from focus traversal.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        if (_loadError != null) {
          return _PaddedMessage(
            edge: edge,
            icon: Icons.error_outline,
            title: 'Reference unavailable',
            body: _loadError!,
          );
        }

        final PlmnReferenceService? svc = _service;
        if (svc == null) {
          return Padding(
            padding: EdgeInsets.all(edge),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: Semantics(
                  label: 'Loading PLMN reference',
                  liveRegion: true,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.textAccent,
                  ),
                ),
              ),
            ),
          );
        }

        final List<PlmnEntry> filtered = svc.search(_query);
        final List<PlmnGroup> groups = svc.grouped(filtered);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              children: <Widget>[
                _IntroCard(total: svc.count, mccCount: svc.mccCount),
                const SizedBox(height: AppSpacing.sm),
                _SearchField(
                  controller: _queryCtrl,
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (groups.isEmpty)
                  _NoMatch(query: _query.trim())
                else ...[
                  ..._groupWidgets(groups),
                  const SizedBox(height: AppSpacing.sm),
                  ToolHelpFooter(toolId: 'plmn-id-reference'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _groupWidgets(List<PlmnGroup> groups) {
    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final PlmnGroup group = groups[g];
      out.add(_MccHeader(mcc: group.mcc, count: group.count));
      out.add(const SizedBox(height: AppSpacing.xs));
      for (int i = 0; i < group.entries.length; i++) {
        out.add(_PlmnRow(entry: group.entries[i]));
        if (i < group.entries.length - 1) {
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

/// One-line intro + counts.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.total, required this.mccCount});

  final int total;
  final int mccCount;

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
      child: Text(
        'US mobile-network identifiers — $total PLMN IDs across $mccCount '
        'country codes (MCC 310–316). Search by MCC, MNC, PLMN ID, or carrier '
        'name.',
        style: text.labelMedium?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    return Semantics(
      textField: true,
      label: 'Search PLMN codes by MCC, MNC, PLMN ID, or carrier name',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        // 16px field text dodges iOS Safari auto-zoom (§8.4).
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: colors.textPrimary),
        cursorColor: colors.textAccent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: colors.textTertiary),
          hintText: 'e.g. 310260, AT&T, or 030',
        ),
      ),
    );
  }
}

/// An MCC group header with a count pill (reference section-header register).
class _MccHeader extends StatelessWidget {
  const _MccHeader({required this.mcc, required this.count});

  final String mcc;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: 'MCC $mcc, $count code${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'MCC $mcc',
                style: text.headlineSmall?.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$count',
                style: text.labelLarge?.copyWith(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One PLMN entry: the PLMN ID (mono identifier) + MCC-MNC line, the carrier
/// name, the parent operator where it differs, and a status chip. Read-only — no
/// tap target, so no focus ring; announced as one coherent node.
class _PlmnRow extends StatelessWidget {
  const _PlmnRow({required this.entry});

  final PlmnEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool showParent =
        entry.operator.isNotEmpty && entry.operator != entry.carrier;

    // SR summary: PLMN ID, MCC-MNC, carrier, parent (if shown), status.
    final String srLabel = rowLabel(entry.plmnId, <String?>[
      'MCC ${entry.mcc}, MNC ${entry.mnc}',
      entry.carrier,
      showParent ? entry.operator : null,
      entry.region == 'US' ? null : entry.region,
      entry.status.label,
    ]);

    return ReferenceRowSemantics(
      label: srLabel,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Code line: PLMN ID (mono identifier) + MCC-MNC, with the status
            // chip pinned to the right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    children: <Widget>[
                      Text(
                        entry.plmnId,
                        style: mono.robotoMono.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        entry.mccMncLabel,
                        style: text.labelMedium?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      if (entry.region != 'US')
                        _RegionTag(region: entry.region),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _StatusChip(status: entry.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              entry.carrier,
              style: text.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showParent)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  entry.operator,
                  style: text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small neutral tag for a non-US territory (PR / GU / VI / AS), so a Guam or
/// Puerto Rico allocation is distinguishable at a glance.
class _RegionTag extends StatelessWidget {
  const _RegionTag({required this.region});

  final String region;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        region,
        style: text.labelLarge?.copyWith(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// Status pill — color-keyed to the verdict palette (§8.13): operational =
/// success, not operational = danger, reserved = info, unknown = neutral
/// (tertiary, deliberately muted so the long `unknown` tail does not read as a
/// positive signal).
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PlmnStatus status;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    final Color fg;
    switch (status) {
      case PlmnStatus.operational:
        fg = colors.statusSuccess;
        break;
      case PlmnStatus.notOperational:
        fg = colors.statusDanger;
        break;
      case PlmnStatus.reserved:
        fg = colors.statusInfo;
        break;
      case PlmnStatus.unknown:
        fg = colors.textTertiary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: fg, width: 1),
      ),
      child: Text(
        status.label,
        style: text.labelLarge?.copyWith(
          fontSize: AppTextSize.caption,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Honest empty state for a query that matches nothing.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(Icons.search_off_outlined, size: 48, color: colors.textTertiary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isEmpty
                ? 'No PLMN codes loaded.'
                : 'No US PLMN code matches "$query".',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// An error / message card with leading icon (reference message-card register).
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(edge),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
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
      ),
    );
  }
}
