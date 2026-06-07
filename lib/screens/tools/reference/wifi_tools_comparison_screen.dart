// Wi-Fi Tools Comparison — an offline, vendor-neutral capability-and-cost
// reference comparing professional Wi-Fi survey, design, spectrum, and
// troubleshooting toolkits, grouped by the activity they serve (Design /
// Validation / Spectrum Analysis / Troubleshooting). Clones the data-driven
// reference pattern (bundled JSON asset → pure service → search/group → render),
// the same idiom as Optical Transceivers and Port Reference.
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner with an AT
//    announcement.
//  - error   → the bundled asset failed to load or parse (should not happen in a
//    shipped build); shown via the shared message card.
//  - success → the disclaimer band + matching activities + the toolkit roll-up +
//    the per-vendor summaries render.
//  - empty   → a query that matches nothing; an honest "no match" card, never a
//    fabricated config.
//  - interactive → search field, link-out chips (keyboard-focusable, the global
//    §8.3 IconButton/focus theme paints the ring), and the AppBar copy action.
//
// NEUTRALITY + HONESTY (GL-005 / GL-007 / Pax brief 2026-06-05):
//  - Capability-and-cost reference, NOT a ranking. No rank, no score, no "best".
//    Configs render in asset order, which is alphabetical by vendor.
//  - TCO and up-front figures are MODELED ESTIMATES, surfaced WITH a visible
//    date-stamp ("Pricing as of <date>, confirm current pricing with the
//    vendor") and a modeled-estimate disclaimer (the truthfulness rule). A
//    beta-review note (vendors being consulted) and a no-logos note
//    (trademarks/photos pending permission) ride at the top.
//  - No vendor logos, no product photos — text and data only.
//  - Tamosoft is absent from the dataset (removed by Keith 2026-06-05); this
//    screen renders whatever the asset lists and contains no vendor-specific
//    handling.
//
// THEME: every color comes from `context.colors` (the AppColorScheme
// ThemeExtension) — no raw AppColors.* — so the screen renders correctly in both
// dark (§8) and light (§8.20). No new tokens introduced.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/wifi_tools_comparison_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the icon/graphic assets, the help
/// entry, and the tests.
const String kWifiToolsComparisonToolId = 'wifi-tools-comparison';

/// Asset path for the bundled comparison. Overridable in tests so a fixture
/// string can stand in for the bundled asset.
const String kWifiToolsComparisonAsset =
    'assets/data/wifi_tools_comparison.json';

class WifiToolsComparisonScreen extends StatefulWidget {
  const WifiToolsComparisonScreen({super.key, this.service, this.launcher});

  /// Intro line for the "Typical professional toolkit" roll-up — a neutral
  /// description in the same register as the activity intros (BF6-15: the
  /// section previously carried only a heading). States what the roll-up is
  /// without ranking or recommending.
  static const String toolkitIntro =
      'A representative bundle a working professional might carry across all '
      'four activities, with its modeled three-year cost of ownership. '
      'Illustrative, not a recommendation.';

  /// Intro line for the "Vendors" section (BF6-15: the last section had no
  /// description). Neutral, matching the activity-intro style.
  static const String vendorsIntro =
      'The vendors referenced above, with a neutral capability summary and '
      'links to their own site and documentation. Listed alphabetically, not '
      'ranked.';

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final WifiToolsComparisonService? service;

  /// Injectable URL opener for tests. Defaults to [launchUrl]. Returns whether
  /// the launch succeeded.
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<WifiToolsComparisonScreen> createState() =>
      _WifiToolsComparisonScreenState();
}

class _WifiToolsComparisonScreenState extends State<WifiToolsComparisonScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  WifiToolsComparisonService? _service;
  String? _loadError;
  String? _launchError;
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
      final String raw = await rootBundle.loadString(kWifiToolsComparisonAsset);
      final WifiToolsComparisonService svc =
          WifiToolsComparisonService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _loadError = 'Could not load the Wi-Fi tools comparison: $e',
      );
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // WCAG 4.1.3 — announce the live result count so AT users hear the list
    // change as they type, without focus leaving the field.
    final WifiToolsComparisonService? svc = _service;
    if (svc == null) return;
    final int n = svc.search(value).fold<int>(
          0,
          (int sum, WifiToolActivity a) => sum + a.configs.length,
        );
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching tools' : '$n matching tool config${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  Future<void> _openUrl(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      _showLaunchError(url);
      return;
    }
    final Future<bool> Function(Uri) launch = widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      final bool ok = await launch(uri);
      if (!ok) {
        _showLaunchError(url);
        return;
      }
      if (!mounted) return;
      setState(() => _launchError = null);
    } on Object {
      _showLaunchError(url);
    }
  }

  void _showLaunchError(String url) {
    if (!mounted) return;
    setState(() => _launchError = 'Could not open the browser. The link is $url');
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  /// Plain-text payload for AppCopyAction. Carries the disclaimer words, the
  /// activity grouping, and every config's vendor/product/cost/TCO/notes so
  /// nothing that was on-screen survives only as a value (§8.16 content
  /// contract — the clipboard has no color).
  String _copyText() {
    final WifiToolsComparisonService? svc = _service;
    if (svc == null) return 'Wi-Fi Tools Comparison';
    final WifiToolsComparisonMeta m = svc.meta;
    final StringBuffer b = StringBuffer()..writeln('Wi-Fi Tools Comparison');
    if (m.pricingNote.isNotEmpty) b.writeln(m.pricingNote);
    if (m.estimateNote.isNotEmpty) b.writeln(m.estimateNote);
    if (m.betaNote.isNotEmpty) b.writeln(m.betaNote);
    if (m.neutralityNote.isNotEmpty) b.writeln(m.neutralityNote);
    if (m.noLogosNote.isNotEmpty) b.writeln(m.noLogosNote);
    for (final WifiToolActivity a in svc.activities) {
      b
        ..writeln()
        ..writeln('== ${a.title} ==');
      for (final WifiToolConfig c in a.configs) {
        final String up = c.upFront == null ? '' : ' · Up front ${_money(c.upFront!, m.currency)}';
        final String tco = c.tco3yr == null ? '' : ' · ${m.tcoLabel} ${_money(c.tco3yr!, m.currency)}';
        b.writeln('${c.vendor} — ${c.product} (${c.costModel.label})$up$tco');
        if (c.notes.isNotEmpty) b.writeln('  ${c.notes}');
      }
    }
    if (svc.toolkits.isNotEmpty) {
      b
        ..writeln()
        ..writeln('== Typical professional toolkit (${m.tcoLabel}) ==');
      for (final WifiToolkit t in svc.toolkits) {
        final String tco =
            t.tco3yr == null ? '' : ' · ${_money(t.tco3yr!, m.currency)}';
        b.writeln('${t.vendor} — ${t.product}$tco');
        if (t.notes.isNotEmpty) b.writeln('  ${t.notes}');
      }
    }
    if (m.source.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Source: ${m.source}');
    }
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = _service != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Tools Comparison'),
        toolbarHeight: 64,
        actions: <Widget>[
          // §8.16: copy leads the actions slot. Disabled until the asset loads.
          if (ready) AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: kWifiToolsComparisonToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kWifiToolsComparisonToolId))
                    const SizedBox(height: AppSpacing.md),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _content(context),
                  ToolHelpFooter(toolId: kWifiToolsComparisonToolId),
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
        hint: 'vendor, product, activity, or capability',
        semanticLabel:
            'Search Wi-Fi tools by vendor, product, activity, or capability',
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
          decoration: const InputDecoration(
            hintText: 'e.g. Ekahau, spectrum, survey, or perpetual',
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_loadError != null) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Reference unavailable',
        body: _loadError!,
      );
    }

    final WifiToolsComparisonService? svc = _service;
    if (svc == null) {
      return _LoadingCard(label: 'Loading Wi-Fi tools comparison');
    }

    final List<WifiToolActivity> activities = svc.search(_query);
    final bool filtering = _query.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DisclaimerCard(meta: svc.meta),
        const SizedBox(height: AppSpacing.md),
        if (activities.isEmpty)
          _MessageCard(
            icon: Icons.search_off,
            title: 'No match',
            body: 'No tool matches "${_query.trim()}".',
          )
        else
          ...activities.map(
            (WifiToolActivity a) => _ActivityBlock(meta: svc.meta, activity: a),
          ),
        // The toolkit roll-up and vendor list are fixed companions — always
        // shown in full (not part of the config search), so a search that hides
        // activities still leaves them available, mirroring the optical
        // form-factor table.
        if (!filtering || activities.isNotEmpty) ...<Widget>[
          if (svc.toolkits.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _SectionHeading(label: 'Typical professional toolkit'),
            const SizedBox(height: AppSpacing.xs),
            _SectionIntro(text: WifiToolsComparisonScreen.toolkitIntro),
            const SizedBox(height: AppSpacing.xs),
            _ToolkitTable(meta: svc.meta, rows: svc.toolkits),
          ],
          if (svc.vendors.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _SectionHeading(label: 'Vendors'),
            const SizedBox(height: AppSpacing.xs),
            _SectionIntro(text: WifiToolsComparisonScreen.vendorsIntro),
            const SizedBox(height: AppSpacing.xs),
            ...svc.vendors.map(
              (WifiToolVendor v) =>
                  _VendorCard(vendor: v, onOpen: _openUrl),
            ),
          ],
        ],
        if (_launchError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _MessageCard(
            icon: Icons.link_off,
            title: 'Could not open the link',
            body: _launchError!,
          ),
        ],
      ],
    );
  }
}

String _money(int value, String currency) {
  // Simple thousands grouping for USD-style figures. No locale dependency so the
  // unit test renders deterministically. The amount is a modeled estimate (the
  // disclaimer carries that fact); this only formats it.
  final String digits = value.abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  final String prefix = currency.toUpperCase() == 'USD' ? '\$' : '';
  return '$prefix${value < 0 ? '-' : ''}${out.toString()}';
}

/// The top disclaimer band: pricing date-stamp, modeled-estimate note,
/// beta-review note, neutrality framing, and the no-logos note. Every line is a
/// required honesty caveat, rendered in full (never truncated).
class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard({required this.meta});

  final WifiToolsComparisonMeta meta;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;

    final List<Widget> lines = <Widget>[];
    void addLine(IconData icon, String text, {bool warn = false}) {
      if (text.isEmpty) return;
      if (lines.isNotEmpty) {
        lines.add(const SizedBox(height: AppSpacing.xs));
      }
      lines.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: warn ? colors.statusWarning : colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: t.bodySmall?.copyWith(
                  color: warn ? colors.statusWarning : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Beta + pricing date are the loudest caveats (status-warning, paired with
    // text — never color-only, GL-003 §8.13 rule 2).
    addLine(Icons.science_outlined, meta.betaNote, warn: true);
    addLine(Icons.event_outlined, meta.pricingNote, warn: true);
    addLine(Icons.calculate_outlined, meta.estimateNote);
    addLine(Icons.balance_outlined, meta.neutralityNote);
    addLine(Icons.image_not_supported_outlined, meta.noLogosNote);

    return Semantics(
      container: true,
      label:
          'About this comparison. ${meta.betaNote} ${meta.pricingNote} ${meta.estimateNote} ${meta.neutralityNote} ${meta.noLogosNote}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines,
        ),
      ),
    );
  }
}

/// One activity block: the activity heading, its neutral intro paragraph, and
/// its config cards.
class _ActivityBlock extends StatelessWidget {
  const _ActivityBlock({required this.meta, required this.activity});

  final WifiToolsComparisonMeta meta;
  final WifiToolActivity activity;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeading(label: activity.title, count: activity.configs.length),
          if (activity.intro.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              activity.intro,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          ...activity.configs.map(
            (WifiToolConfig c) => _ConfigCard(meta: meta, config: c),
          ),
        ],
      ),
    );
  }
}

/// One config card: vendor + cost-model chip on the header row, the product
/// line, the up-front / 3-year-TCO figures, and the neutral note. Read by a
/// screen reader as one coherent node keyed on the vendor + product.
class _ConfigCard extends StatelessWidget {
  const _ConfigCard({required this.meta, required this.config});

  final WifiToolsComparisonMeta meta;
  final WifiToolConfig config;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;

    final String upFront = config.upFront == null
        ? '—'
        : _money(config.upFront!, meta.currency);
    final String tco =
        config.tco3yr == null ? '—' : _money(config.tco3yr!, meta.currency);

    final String spoken = rowLabel('${config.vendor}, ${config.product}', <String?>[
      config.costModel.label,
      'up front $upFront',
      '${meta.tcoLabel} $tco',
      config.notes,
    ]);

    return ReferenceRowSemantics(
      label: spoken,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Vendor + cost-model chip.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    config.vendor,
                    style: (t.titleMedium ?? const TextStyle()).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _CostModelChip(label: config.costModel.label),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              config.product,
              style: t.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Up front + 3-year TCO figures (mono, decimal-aligned per §8.5).
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                _MoneyItem(label: 'Up front', value: upFront),
                _MoneyItem(label: meta.tcoLabel, value: tco, emphasize: true),
              ],
            ),
            if (config.notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                config.notes,
                style: t.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labeled money figure: an uppercase key and its value in DM Mono. The TCO
/// figure emphasizes in primary text; up-front sits in secondary.
class _MoneyItem extends StatelessWidget {
  const _MoneyItem({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: (t.labelSmall ?? const TextStyle()).copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          style: (t.bodyMedium ?? const TextStyle()).copyWith(
            color: emphasize ? colors.textPrimary : colors.textSecondary,
            fontFamily: 'DM Mono',
            fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The cost / license-model chip — outlined in the strong border, secondary
/// text. Carries a neutral category (no verdict color); the label always carries
/// the fact (never color-only meaning).
class _CostModelChip extends StatelessWidget {
  const _CostModelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: '$label license',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderStrong, width: 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (t.labelSmall ?? const TextStyle()).copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// The "typical professional toolkit" roll-up table: vendor + product + 3-year
/// TCO, with the notes beneath each row.
class _ToolkitTable extends StatelessWidget {
  const _ToolkitTable({required this.meta, required this.rows});

  final WifiToolsComparisonMeta meta;
  final List<WifiToolkit> rows;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          // Header row.
          Container(
            decoration: BoxDecoration(
              color: colors.surface2,
              border: Border(
                bottom: BorderSide(color: colors.border, width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.rowPadding,
            ),
            child: Semantics(
              header: true,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'VENDOR & TOOLKIT',
                      style: (t.labelSmall ?? const TextStyle()).copyWith(
                        color: colors.textTertiary,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    meta.tcoLabel.toUpperCase(),
                    style: (t.labelSmall ?? const TextStyle()).copyWith(
                      color: colors.textTertiary,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...List<Widget>.generate(rows.length, (int i) {
            return _ToolkitRow(
              meta: meta,
              row: rows[i],
              isLast: i == rows.length - 1,
            );
          }),
        ],
      ),
    );
  }
}

class _ToolkitRow extends StatelessWidget {
  const _ToolkitRow({
    required this.meta,
    required this.row,
    required this.isLast,
  });

  final WifiToolsComparisonMeta meta;
  final WifiToolkit row;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final String tco =
        row.tco3yr == null ? '—' : _money(row.tco3yr!, meta.currency);

    final String spoken = rowLabel(row.vendor, <String?>[
      row.product,
      '${meta.tcoLabel} $tco',
      row.notes,
    ]);

    return ReferenceRowSemantics(
      label: spoken,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          border: !isLast
              ? Border(bottom: BorderSide(color: colors.border, width: 1))
              : null,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        row.vendor,
                        style: (t.bodyMedium ?? const TextStyle()).copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        row.product,
                        style: t.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  tco,
                  style: (t.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontFamily: 'DM Mono',
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures()
                    ],
                  ),
                ),
              ],
            ),
            if (row.notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                row.notes,
                style: t.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One per-vendor summary card: vendor name, neutral capability summary, and
/// link-out chips (website / docs) that open the system browser.
class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor, required this.onOpen});

  final WifiToolVendor vendor;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              vendor.name,
              style: (t.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (vendor.summary.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              vendor.summary,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          if (vendor.website.isNotEmpty || vendor.docs.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                if (vendor.website.isNotEmpty)
                  _LinkChip(
                    icon: Icons.open_in_new,
                    label: 'Website',
                    semanticLabel: 'Open the ${vendor.name} website',
                    onTap: () => onOpen(vendor.website),
                  ),
                if (vendor.docs.isNotEmpty)
                  _LinkChip(
                    icon: Icons.menu_book_outlined,
                    label: 'Docs',
                    semanticLabel: 'Open the ${vendor.name} documentation',
                    onTap: () => onOpen(vendor.docs),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A keyboard-focusable link-out chip. The global §8.3 focus theme paints the
/// ring on focus; the outline is the foreground-lime accent (safe as a thin line
/// and text in both themes).
class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colors.textAccent, width: 1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 16, color: colors.textAccent),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    label,
                    style: (t.labelMedium ?? const TextStyle()).copyWith(
                      color: colors.textAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section heading with a short lime underbar accent and an optional trailing
/// count. BF6-14: the category/section headings stand out — rendered at the
/// larger `headlineSmall` (H3, §8.5) in the lime accent so they read clearly
/// above their config cards, not as just-bigger body text.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              // BF6-14: larger (H3 headlineSmall) + lime accent so the activity
              // categories visibly lead their groups. textAccent = lime in dark,
              // darkened-lime in light (§8.20.2), AA-safe as heading text.
              style: (t.headlineSmall ?? const TextStyle()).copyWith(
                color: colors.textAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 38,
            height: 3,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (count != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$count',
              style: t.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A neutral one-paragraph section intro, styled exactly like the activity
/// intros (bodySmall / textSecondary) so the toolkit and vendor sections read as
/// siblings of the activity categories (BF6-15).
class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.bodySmall?.copyWith(color: colors.textSecondary),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: Semantics(
            label: label,
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
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
