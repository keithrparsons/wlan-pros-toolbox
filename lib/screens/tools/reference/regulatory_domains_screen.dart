// Regulatory Domains — per-jurisdiction directory of the radio regulator that
// governs Wi-Fi in each market.
//
// SUPERSEDES the earlier region-level FCC / ETSI / ITU summary that carried this
// same `regulatory-domains` id (a four-card region overview). This richer page
// lists 43 jurisdictions, each with: the regulator's logo (or a styled
// abbreviation badge when the logo asset is not bundled), the jurisdiction, the
// regulator's full name + abbreviation, a tappable official-website link
// (url_launcher, system browser), the governing regulation / standard, and the
// 2.4 / 5 / 6 GHz band + power note.
//
// SNAPSHOT BANNER (binding, per the brief): ONE prominent banner at the top
// states the data is a dated snapshot and that regulations change, so the user
// confirms against the regulator before relying on a value. The band note in
// every row is volatile by nature (GL-005); the banner and each row's website
// link are the verification path.
//
// SEARCH: a search-as-you-type field (mirrors the Educational Resources inline
// search + SC 4.1.3 live-count announcement) filters rows by jurisdiction,
// regulator name, abbreviation, and governing docs.
//
// ABBREVIATION COLLISIONS: where an abbreviation is shared across jurisdictions
// (NCC = Taiwan / Nigeria; TRA = Oman / Bahrain; CRA = Qatar), the badge and the
// screen-reader label append the jurisdiction so the abbreviation is
// unambiguous (brief requirement).
//
// STATES (SOP-007 §5): the dataset is a compile-time const, so there is no
// loading / fetch / parse path — `success` (the full list or a filtered subset)
// and `empty` (a query that matches nothing) are the only states. The
// per-row website launch carries its own honest error state when the browser
// hand-off fails (the URL stays readable). GL-008: HTTPS browser hand-off, no
// in-app cleartext fetch, no subprocess.
//
// DESIGN: context.colors tokens only (theme-aware, light + dark); DM Mono
// (AppMonoText.inlineCode) for the abbreviation and the website URL identifier;
// §8.3 lime focus ring inherited from the theme on the tappable link.
//
// Glyph hygiene (GL-004): "Wi-Fi" never "WiFi"; "802.1X" never "802.1x"; ASCII
// hyphen-minus, no em dash; US spelling.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/regulatory_domains_data.dart';
import '../../../data/regulatory_logos.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/centered_content.dart';
import '../../../widgets/tool_help_footer.dart';

class RegulatoryDomainsScreen extends StatefulWidget {
  const RegulatoryDomainsScreen({
    super.key,
    this.domains = kRegulatoryDomains,
    this.launcher,
  });

  /// The records to render. Defaults to the bundled dataset; injectable so a
  /// widget test can pump a small fixture without depending on all 43 rows.
  final List<RegulatoryDomain> domains;

  /// Injectable URL opener for tests. Defaults to [launchUrl]
  /// (externalApplication). Returns whether the launch succeeded.
  final Future<bool> Function(Uri url)? launcher;

  /// Stable catalog id — backs the route and the help entry.
  static const String toolId = 'regulatory-domains';

  /// The persistent snapshot caveat, surfaced in the top banner and reused in
  /// the copy payload so the warning travels with any pasted data.
  static String get snapshotCaveat =>
      'Snapshot verified $kRegulatorySnapshotDate. Regulations change; confirm '
      'against the regulator before relying on a value.';

  @override
  State<RegulatoryDomainsScreen> createState() =>
      _RegulatoryDomainsScreenState();
}

class _RegulatoryDomainsScreenState extends State<RegulatoryDomainsScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// The records matching the active query (substring over the search haystack:
  /// jurisdiction + regulator + abbreviation + docs). Empty query → all rows.
  /// All domains sorted alphabetically by jurisdiction (country) — the on-screen
  /// order Keith asked for (2026-06-09).
  List<RegulatoryDomain> get _sortedDomains =>
      <RegulatoryDomain>[...widget.domains]..sort(
          (RegulatoryDomain a, RegulatoryDomain b) =>
              a.jurisdiction.toLowerCase().compareTo(b.jurisdiction.toLowerCase()));

  List<RegulatoryDomain> get _filtered {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sortedDomains;
    return _sortedDomains
        .where((RegulatoryDomain d) => d.searchHaystack.contains(q))
        .toList(growable: false);
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    // SC 4.1.3 — announce the live result count so AT users hear the list
    // change as they type, without focus leaving the field.
    final int n = _filtered.length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0
          ? 'No matching jurisdictions'
          : '$n matching jurisdiction${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the snapshot caveat then one TSV line per row.
  String _copyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Regulatory Domains')
      ..writeln(RegulatoryDomainsScreen.snapshotCaveat)
      ..writeln()
      ..writeln(
        <String>[
          'Jurisdiction',
          'ITU Region',
          'Regulator',
          'Abbreviation',
          'Website',
          'Governing docs',
          'Band / power notes',
        ].join(tab),
      );
    for (final RegulatoryDomain d in _sortedDomains) {
      buf.writeln(
        <String>[
          d.jurisdiction,
          'Region ${d.ituRegion}',
          d.regulatorName,
          d.abbreviation,
          d.websiteUrl,
          d.governingDocs,
          d.bandNotes,
        ].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regulatory Domains'),
        toolbarHeight: 64,
        // §8.16 — copy all rows as TSV, led by the snapshot caveat. Static data,
        // always enabled.
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double edge = constraints.maxWidth >= 720
                ? AppSpacing.screenEdgeDesktop
                : AppSpacing.screenEdgeMobile;
            return CenteredContent(child: _body(edge));
          },
        ),
      ),
    );
  }

  Widget _body(double edge) {
    final List<RegulatoryDomain> rows = _filtered;
    final bool filtering = _query.trim().isNotEmpty;

    final List<Widget> children = <Widget>[
      const _SnapshotBanner(),
      const SizedBox(height: AppSpacing.sm),
      _SearchField(controller: _queryCtrl, onChanged: _onQueryChanged),
      const SizedBox(height: AppSpacing.sm),
    ];

    if (rows.isEmpty) {
      children.add(_NoMatch(query: _query.trim()));
    } else {
      for (int i = 0; i < rows.length; i++) {
        children.add(
          _RegulatorRow(domain: rows[i], launcher: widget.launcher),
        );
        if (i < rows.length - 1) {
          children.add(const SizedBox(height: AppSpacing.xs));
        }
      }
    }

    children.add(
      ToolHelpFooter(toolId: RegulatoryDomainsScreen.toolId),
    );

    // A header line so AT users hear the total / filtered count.
    final String countLabel = filtering
        ? '${rows.length} of ${widget.domains.length} jurisdictions'
        : '${widget.domains.length} jurisdictions';

    return ListView(
      padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge + AppSpacing.sm),
      children: <Widget>[
        Semantics(
          header: true,
          label: countLabel,
          child: const SizedBox.shrink(),
        ),
        ...children,
      ],
    );
  }
}

/// The ONE prominent snapshot banner at the top of the page. Warning-toned
/// callout (left-accent border, warning tint fill in light / faint wash in dark,
/// warning icon + body), wrapped in one Semantics container so a screen reader
/// reads it as a single node. Mirrors the freeradius / volatility-caveat idiom.
class _SnapshotBanner extends StatelessWidget {
  const _SnapshotBanner();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;

    return Semantics(
      container: true,
      label: 'Snapshot notice. ${RegulatoryDomainsScreen.snapshotCaveat}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.isLight
              ? colors.statusWarningFill
              : warn.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border(
            top: BorderSide(color: warn),
            right: BorderSide(color: warn),
            bottom: BorderSide(color: warn),
            left: BorderSide(color: warn, width: 6),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 24, color: warn),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'SNAPSHOT VERIFIED $kRegulatorySnapshotDate',
                    style: (text.labelMedium ?? const TextStyle()).copyWith(
                      color: warn,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Regulations change; confirm against the regulator before '
                    'relying on a value. Band and power notes are a snapshot, '
                    'not a settled constant.',
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: colors.textSecondary,
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

/// In-screen search field (§8.4 input spec). 16px field text dodges iOS Safari
/// auto-zoom; mirrors the Educational Resources search field.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Semantics(
      textField: true,
      label: 'Search regulatory domains by jurisdiction or regulator',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: colors.textPrimary),
        cursorColor: colors.textAccent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: colors.textTertiary),
          hintText: 'Search jurisdiction or regulator…',
        ),
      ),
    );
  }
}

/// One jurisdiction card: logo (or abbreviation badge) + jurisdiction + regulator
/// name + abbreviation chip, the governing docs, the band / power note, and a
/// tappable official-website link. Stateful only to carry the per-row launch
/// error state.
class _RegulatorRow extends StatefulWidget {
  const _RegulatorRow({required this.domain, this.launcher});

  final RegulatoryDomain domain;
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<_RegulatorRow> createState() => _RegulatorRowState();
}

class _RegulatorRowState extends State<_RegulatorRow> {
  String? _launchError;

  /// The abbreviation as shown to the user — appended with the jurisdiction when
  /// it collides across jurisdictions (NCC, TRA, CRA) so it is unambiguous.
  String get _displayAbbrev => widget.domain.abbreviationCollides
      ? '${widget.domain.abbreviation} (${widget.domain.jurisdiction})'
      : widget.domain.abbreviation;

  Future<void> _openWebsite() async {
    final Uri? uri = Uri.tryParse(widget.domain.websiteUrl);
    if (uri == null) {
      _showLaunchError();
      return;
    }
    final Future<bool> Function(Uri) launch = widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      final bool ok = await launch(uri);
      if (!ok) {
        _showLaunchError();
        return;
      }
      if (!mounted) return;
      setState(() => _launchError = null);
    } on Object {
      _showLaunchError();
    }
  }

  void _showLaunchError() {
    if (!mounted) return;
    setState(
      () => _launchError =
          'Could not open the browser. The link is ${widget.domain.websiteUrl}',
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final RegulatoryDomain d = widget.domain;

    return Semantics(
      container: true,
      label: '${d.jurisdiction}, ITU Region ${d.ituRegion}. '
          '${d.regulatorName}, $_displayAbbrev. '
          'Governing documents: ${d.governingDocs}. '
          'Bands: ${d.bandNotes}',
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header: logo/badge + jurisdiction + regulator + abbreviation.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _RegulatorLogo(domain: d, displayAbbrev: _displayAbbrev),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        d.jurisdiction,
                        style: text.bodyLarge?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d.regulatorName,
                        style: text.labelMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      // Abbreviation in DM Mono (identifier), with the
                      // jurisdiction appended when it collides.
                      Text(
                        _displayAbbrev,
                        style: mono.inlineCode.copyWith(
                          color: colors.textAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(
                    'Region ${d.ituRegion}',
                    style: text.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _LabeledBlock(
              label: 'Governing documents',
              value: d.governingDocs,
            ),
            const SizedBox(height: AppSpacing.xs),
            _LabeledBlock(
              label: 'Bands and power (verify)',
              value: d.bandNotes,
            ),
            const SizedBox(height: AppSpacing.sm),
            _WebsiteLink(
              url: d.websiteUrl,
              regulator: d.regulatorName,
              onTap: _openWebsite,
            ),
            if (_launchError != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              _LaunchError(message: _launchError!),
            ],
          ],
        ),
      ),
    );
  }
}

/// The leading logo slot: the regulator's bundled logo when one is present,
/// otherwise a styled abbreviation badge (NEVER a broken image). 96x96 square so
/// the row aligns whether a logo or a badge is shown (doubled from 48, Keith
/// 2026-06-09).
class _RegulatorLogo extends StatelessWidget {
  const _RegulatorLogo({required this.domain, required this.displayAbbrev});

  final RegulatoryDomain domain;
  final String displayAbbrev;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final String key = domain.logoKey;
    final String? logoPath = RegulatoryLogos.path(key);

    if (logoPath != null) {
      final Widget logo = RegulatoryLogos.isSvg(key)
          ? SvgPicture.asset(
              logoPath,
              width: _size,
              height: _size,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              placeholderBuilder: (_) => _AbbrevBadge(
                abbreviation: domain.abbreviation,
              ),
            )
          : Image.asset(
              logoPath,
              width: _size,
              height: _size,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              errorBuilder: (_, Object _, StackTrace? _) =>
                  _AbbrevBadge(abbreviation: domain.abbreviation),
            );
      return SizedBox(
        width: _size,
        height: _size,
        // White-ish chip behind the logo so colored official marks read on the
        // dark surface; in light mode the card is already light.
        child: Container(
          decoration: BoxDecoration(
            color: colors.isLight ? colors.surface1 : colors.surface2,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: logo,
        ),
      );
    }

    // No bundled logo → styled abbreviation badge.
    return _AbbrevBadge(abbreviation: domain.abbreviation);
  }
}

/// The fallback badge shown when a regulator logo asset is not bundled: a
/// tinted, rounded square carrying the abbreviation in DM Mono. The raw
/// abbreviation only (kept short so it fits the 96x96 square); the colliding
/// jurisdiction disambiguation lives on the text label beside it, not the badge.
class _AbbrevBadge extends StatelessWidget {
  const _AbbrevBadge({required this.abbreviation});

  final String abbreviation;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    // Keep the badge text short: first token of the abbreviation, up to 4 chars.
    final String badge = abbreviation.length > 4
        ? abbreviation.substring(0, 4)
        : abbreviation;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      child: Text(
        badge,
        textAlign: TextAlign.center,
        style: mono.inlineCode.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w500,
          fontSize: badge.length > 3 ? AppTextSize.caption : AppTextSize.body,
        ),
      ),
    );
  }
}

/// A labeled prose block: a caption-style label over the value text.
class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: text.labelSmall?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: text.labelMedium?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// The tappable official-website link. An outlined, full-width control with a
/// link glyph and the URL in DM Mono (identifier). Carries the §8.3 lime focus
/// ring (inherited from the theme's button styling via TextButton); explicit SR
/// label names the regulator and that it opens in the browser.
class _WebsiteLink extends StatelessWidget {
  const _WebsiteLink({
    required this.url,
    required this.regulator,
    required this.onTap,
  });

  final String url;
  final String regulator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      button: true,
      link: true,
      label: 'Open the $regulator website in the browser',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colors.borderStrong, width: 1),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.open_in_new, size: 18, color: colors.textAccent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    url,
                    style: mono.inlineCode.copyWith(
                      color: colors.textAccent,
                    ),
                    overflow: TextOverflow.ellipsis,
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

/// Honest error shown when the browser hand-off fails (the link stays readable).
class _LaunchError extends StatelessWidget {
  const _LaunchError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.statusDanger, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: colors.statusDanger),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: text.labelMedium?.copyWith(color: colors.textPrimary),
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
                ? 'No jurisdictions loaded.'
                : 'No jurisdictions match "$query".',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
