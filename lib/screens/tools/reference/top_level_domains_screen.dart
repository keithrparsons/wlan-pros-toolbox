// Top-Level Domains — read-only, grouped reference of the DNS top-level
// domains a network / IT pro actually meets, with each TLD's type and a short
// "managed by / typical use" note.
//
// Pure read-only reference — no inputs beyond a type filter, no computation, no
// network. Works on every platform (no NetworkUnavailableView). The only real
// state is "success": the compile-time const dataset always renders. An
// "empty" path exists defensively for a filter that matches nothing (it cannot
// today, but a future filter value must not ship a blank surface).
//
// Pattern: matches standards_screen — Scaffold + AppBar (toolbarHeight 64),
// SafeArea(top: false), LayoutBuilder isDesktop @720, ConstrainedBox to
// calculatorMaxWidth, SingleChildScrollView, cards from app_tokens, an
// AppSelect (§8.14) type filter, ValueRow data rows, AppCopyAction (§8.16),
// ToolHelpFooter (§8.16.1), and ReferenceRowSemantics for one-node-per-row AT.
//
// EPISTEMIC HONESTY (GL-005 + Truthfulness Audit): the set is CURATED, not
// exhaustive. There are ~1,500 gTLDs and ~250 ccTLDs in the live root zone;
// this lists the meaningful field-relevant set and says so in the intro and the
// footnote. Where a TLD is technically a ccTLD but used generically (.io, .ai,
// .tv, .me, .co), the note states that accurately rather than misclassifying
// it. .io and .ai are ccTLDs (British Indian Ocean Territory / Anguilla),
// commonly marketed as generic — that distinction is the whole point of the
// note. Source: IANA Root Zone Database (iana.org/domains/root/db) for registry
// classification and sponsoring organizations; ICANN for gTLD program facts.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// The classification of a top-level domain, used both as the section grouping
/// and as the filter dimension. Order here is the on-screen section order.
enum TldType {
  generic,
  countryCode,
  sponsored,
  infrastructure,
  newGtld,
}

extension TldTypeLabel on TldType {
  /// Section header / filter label.
  String get label {
    switch (this) {
      case TldType.generic:
        return 'Generic (gTLD)';
      case TldType.countryCode:
        return 'Country-code (ccTLD)';
      case TldType.sponsored:
        return 'Sponsored / restricted';
      case TldType.infrastructure:
        return 'Infrastructure';
      case TldType.newGtld:
        return 'Newer gTLDs';
    }
  }

  /// One-line description shown under a section header.
  String get blurb {
    switch (this) {
      case TldType.generic:
        return 'The original open / general-purpose domains.';
      case TldType.countryCode:
        return 'Two-letter ISO 3166-1 codes; a representative set of ~250.';
      case TldType.sponsored:
        return 'Restricted to a defined community, vetted on registration.';
      case TldType.infrastructure:
        return 'Reserved for technical infrastructure, not public registration.';
      case TldType.newGtld:
        return 'From ICANN\'s 2012+ new-gTLD program; a notable sample.';
    }
  }
}

/// One curated top-level-domain reference entry.
@immutable
class TldEntry {
  const TldEntry({
    required this.tld,
    required this.type,
    required this.note,
  });

  /// The TLD label including the leading dot, e.g. `.com`.
  final String tld;

  /// Its registry classification.
  final TldType type;

  /// Short "managed by / typical use" note — accurate, plain-language.
  final String note;
}

class TopLevelDomainsScreen extends StatefulWidget {
  const TopLevelDomainsScreen({super.key});

  /// The curated TLD dataset. Public + static const so tests assert against the
  /// same single source the UI renders. CURATED, not exhaustive — see the file
  /// header and [footnote]. Classification + sponsoring orgs per the IANA Root
  /// Zone Database.
  static const List<TldEntry> domains = <TldEntry>[
    // ── Generic (the original open gTLDs) ──
    TldEntry(
      tld: '.com',
      type: TldType.generic,
      note: 'Commercial; the default open gTLD. Verisign registry. Any use.',
    ),
    TldEntry(
      tld: '.org',
      type: TldType.generic,
      note: 'Originally organizations / non-profits; now open. PIR registry.',
    ),
    TldEntry(
      tld: '.net',
      type: TldType.generic,
      note: 'Originally network infrastructure; now open. Verisign registry.',
    ),
    TldEntry(
      tld: '.info',
      type: TldType.generic,
      note: 'Open informational gTLD (2001). Identity Digital registry.',
    ),
    TldEntry(
      tld: '.biz',
      type: TldType.generic,
      note: 'Business gTLD (2001), intended as a .com alternative. Open.',
    ),
    TldEntry(
      tld: '.name',
      type: TldType.generic,
      note: 'For individuals / personal names (2001). Open.',
    ),
    TldEntry(
      tld: '.pro',
      type: TldType.generic,
      note: 'Originally licensed professionals; now open.',
    ),

    // ── Country-code (ISO 3166-1 two-letter; representative subset) ──
    TldEntry(
      tld: '.us',
      type: TldType.countryCode,
      note: 'United States. Managed by Registry Services LLC under NTIA.',
    ),
    TldEntry(
      tld: '.uk',
      type: TldType.countryCode,
      note: 'United Kingdom. Nominet registry (.co.uk is the common 2nd level).',
    ),
    TldEntry(
      tld: '.ca',
      type: TldType.countryCode,
      note: 'Canada. CIRA registry. Canadian-presence requirement.',
    ),
    TldEntry(
      tld: '.de',
      type: TldType.countryCode,
      note: 'Germany. DENIC registry, one of the largest ccTLDs.',
    ),
    TldEntry(
      tld: '.fr',
      type: TldType.countryCode,
      note: 'France. AFNIC registry.',
    ),
    TldEntry(
      tld: '.jp',
      type: TldType.countryCode,
      note: 'Japan. JPRS registry.',
    ),
    TldEntry(
      tld: '.cn',
      type: TldType.countryCode,
      note: 'China. CNNIC registry.',
    ),
    TldEntry(
      tld: '.au',
      type: TldType.countryCode,
      note: 'Australia. auDA registry (.com.au is the common 2nd level).',
    ),
    TldEntry(
      tld: '.in',
      type: TldType.countryCode,
      note: 'India. NIXI registry.',
    ),
    TldEntry(
      tld: '.eu',
      type: TldType.countryCode,
      note: 'European Union (a supranational ccTLD). EURid registry.',
    ),

    // ── Sponsored / restricted (community-vetted) ──
    TldEntry(
      tld: '.gov',
      type: TldType.sponsored,
      note: 'US government only. Administered by CISA. Eligibility-verified.',
    ),
    TldEntry(
      tld: '.edu',
      type: TldType.sponsored,
      note: 'US accredited post-secondary institutions. Educause registry.',
    ),
    TldEntry(
      tld: '.mil',
      type: TldType.sponsored,
      note: 'US Department of Defense / military only. DISA administered.',
    ),
    TldEntry(
      tld: '.int',
      type: TldType.sponsored,
      note: 'International treaty organizations only. IANA administered.',
    ),
    TldEntry(
      tld: '.aero',
      type: TldType.sponsored,
      note: 'Air-transport industry. SITA-sponsored, membership-verified.',
    ),
    TldEntry(
      tld: '.museum',
      type: TldType.sponsored,
      note: 'Accredited museums. Sponsored by MuseDoma.',
    ),
    TldEntry(
      tld: '.coop',
      type: TldType.sponsored,
      note: 'Cooperatives. Sponsored by DotCooperation.',
    ),

    // ── Infrastructure (not for public registration) ──
    TldEntry(
      tld: '.arpa',
      type: TldType.infrastructure,
      note: 'Address and Routing Parameter Area: reverse DNS (in-addr.arpa, '
          'ip6.arpa). IETF/IANA managed; no public registration.',
    ),

    // ── Newer gTLDs (ICANN 2012+ program — notable sample) ──
    TldEntry(
      tld: '.app',
      type: TldType.newGtld,
      note: 'Apps / developers (Google Registry). HTTPS-only, preloaded HSTS.',
    ),
    TldEntry(
      tld: '.dev',
      type: TldType.newGtld,
      note: 'Developers / development (Google Registry). HTTPS-only HSTS preload.',
    ),
    TldEntry(
      tld: '.xyz',
      type: TldType.newGtld,
      note: 'General-purpose new gTLD (2014). Popular low-cost open domain.',
    ),
    TldEntry(
      tld: '.io',
      type: TldType.newGtld,
      note: 'Technically a ccTLD (British Indian Ocean Territory); marketed '
          'generically by tech / startups. Not a true gTLD.',
    ),
    TldEntry(
      tld: '.ai',
      type: TldType.newGtld,
      note: 'Technically a ccTLD (Anguilla); used generically for AI products. '
          'Not a true gTLD.',
    ),
    TldEntry(
      tld: '.co',
      type: TldType.newGtld,
      note: 'Technically a ccTLD (Colombia); marketed generically as a .com '
          'alternative. Not a true gTLD.',
    ),
    TldEntry(
      tld: '.tech',
      type: TldType.newGtld,
      note: 'Technology-focused new gTLD (Radix registry). Open.',
    ),
  ];

  /// Intro copy — public so tests assert the curation caveat is present.
  static const String intro =
      'A curated reference to the top-level domains a network / IT pro actually '
      'meets, grouped by registry type. It is NOT exhaustive: the live root '
      'zone has ~1,500 generic TLDs and ~250 country-code TLDs.';

  /// Footnote — public so tests assert the ccTLD-vs-gTLD honesty caveat.
  static const String footnote =
      'Curated, not exhaustive. .io, .ai, .co, .tv and .me are technically '
      'country-code TLDs (ISO 3166-1) but are commonly used generically; they '
      'are not true generic TLDs. The authoritative list is the IANA Root Zone '
      'Database.';

  @override
  State<TopLevelDomainsScreen> createState() => _TopLevelDomainsScreenState();
}

/// Filter: `all` shows every type; otherwise narrow to one [TldType].
class _TopLevelDomainsScreenState extends State<TopLevelDomainsScreen> {
  TldType? _filter; // null → all types

  static const List<AppSelectItem<TldType?>> _filterItems =
      <AppSelectItem<TldType?>>[
        (null, 'All types'),
        (TldType.generic, 'Generic (gTLD)'),
        (TldType.countryCode, 'Country-code (ccTLD)'),
        (TldType.sponsored, 'Sponsored / restricted'),
        (TldType.infrastructure, 'Infrastructure'),
        (TldType.newGtld, 'Newer gTLDs'),
      ];

  /// The TldType sections to render, in enum order, each with its matching
  /// entries, after applying the current filter.
  List<({TldType type, List<TldEntry> entries})> get _sections {
    final List<({TldType type, List<TldEntry> entries})> out =
        <({TldType type, List<TldEntry> entries})>[];
    for (final TldType t in TldType.values) {
      if (_filter != null && _filter != t) continue;
      final List<TldEntry> rows = TopLevelDomainsScreen.domains
          .where((TldEntry e) => e.type == t)
          .toList();
      if (rows.isNotEmpty) out.add((type: t, entries: rows));
    }
    return out;
  }

  void _onFilterChanged(TldType? next) {
    setState(() => _filter = next);
    final int n = _sections.fold<int>(0, (int a, s) => a + s.entries.length);
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No domains in this type' : '$n domain${n == 1 ? '' : 's'} shown',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the FULL curated set as TSV regardless of the on-screen
  /// filter (the filter narrows the view, not the reference). One header row,
  /// then one tab-separated row per TLD, grouped by type.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Top-Level Domains (curated)')
      ..writeln(<String>['TLD', 'Type', 'Managed by / typical use'].join(tab));
    for (final TldType t in TldType.values) {
      for (final TldEntry e in TopLevelDomainsScreen.domains.where(
        (TldEntry e) => e.type == t,
      )) {
        buf.writeln(<String>[e.tld, t.label, e.note].join(tab));
      }
    }
    buf
      ..writeln()
      ..writeln(TopLevelDomainsScreen.footnote);
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top-Level Domains'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
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
        final List<({TldType type, List<TldEntry> entries})> sections =
            _sections;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
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
                    toolId: 'top-level-domains',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('top-level-domains'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _filterCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  if (sections.isEmpty)
                    _emptyCard(context)
                  else
                    ...sections.map(
                      (({TldType type, List<TldEntry> entries}) s) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _TypeCard(type: s.type, entries: s.entries),
                      ),
                    ),
                  ToolHelpFooter(toolId: 'top-level-domains'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            TopLevelDomainsScreen.intro,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            TopLevelDomainsScreen.footnote,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _filterCard(BuildContext context) {
    return _Card(
      child: LabeledField(
        label: 'Type',
        semanticLabel: 'Filter top-level domains by type',
        field: AppSelect<TldType?>(
          value: _filter,
          items: _filterItems,
          onChanged: _onFilterChanged,
          semanticLabel: 'Type filter',
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.search_off, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'No match',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'No domains in this type.',
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
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

/// One type section: a header (the type label + blurb) over the TLD rows.
class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.entries});

  final TldType type;
  final List<TldEntry> entries;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            type.label,
            style: text.headlineSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            type.blurb,
            style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(color: AppColors.border, height: 1),
          ...entries.map((TldEntry e) => _TldRow(entry: e)),
        ],
      ),
    );
  }
}

/// One TLD result: the TLD label as a lime Roboto Mono identifier (the key
/// column a user scans by), with the plain-language note underneath. Reads as
/// one AT node summarizing the whole row.
class _TldRow extends StatelessWidget {
  const _TldRow({required this.entry});

  final TldEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: rowLabel(entry.tld, <String?>[entry.type.label, entry.note]),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 84,
              child: Text(
                entry.tld,
                style: mono.robotoMono.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                entry.note,
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared surface-1 card with the standard border, radius, and padding.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
