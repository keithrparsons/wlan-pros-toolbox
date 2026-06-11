// Speed Test Services — a curated, offline reference to the popular internet
// speed-test services, framed for a Wi-Fi pro on the two axes that matter:
// single vs multi-stream, and nearby-CDN-edge vs distant-true-server.
//
// Source of truth: Pax's verified brief (myPKA Deliverables/
// 2026-06-09-speedtest-services/RESEARCH-BRIEF.md). Keith approved all 12
// services. Data lives in lib/data/speedtest_services_data.dart (compile-time
// const); logos resolve through lib/data/speedtest_logos.dart (manifest-gated,
// graceful fallback to a name-label when a logo file is absent).
//
// States (SOP-007 §5):
//  - success → the hero, the honesty caveat band, the three teaching callouts,
//    the optional search field, and the 12 service cards always render (const
//    data; no fetch, so no loading/error path).
//  - empty   → a search query that matches nothing shows an honest "No match"
//    card, never a fabricated entry.
//  - interactive → search field, per-card website link-out chip (keyboard-
//    focusable; the global §8.3 IconButton/focus theme paints the ring), and the
//    AppBar copy action.
//  - disabled → the copy action is always enabled here (const data is always
//    present); the search field is always enabled.
//
// HONESTY (load-bearing, GL-005 / the brief):
//  - The data-per-test figure is the weak column: every figure renders beside a
//    confidence marker ("est." / "rough est." / "measured"), and a persistent
//    warning band states up front that these are community-measured estimates.
//  - Orb carries a "Monitor, not a one-shot test" badge and its own framing note
//    (continuous monitoring; our net_quality engine is the analog with NO
//    composite score, trademark caution).
//  - Where a brand is not its own measurement backend (Waveform on Cloudflare,
//    ISP tests on Ookla/M-Lab, Fast.com on Netflix's CDN), the card shows a
//    "Runs on" note, and a top-level caveat says not all 12 are independent.
//
// THEME: every color comes from `context.colors` (the AppColorScheme
// ThemeExtension) — no raw hex, no AppColors.* — so the screen renders correctly
// in both dark (§8) and light (§8.20). No new tokens introduced.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/speedtest_logos.dart';
import '../../../data/speedtest_services_data.dart';
import '../../../data/throughput_where_diagram.dart';
import '../../../data/tool_assets.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the §8.6.2 concept graphic, the
/// help entry, and the tests.
const String kSpeedtestServicesToolId = 'speedtest-services';

class SpeedtestServicesScreen extends StatefulWidget {
  const SpeedtestServicesScreen({super.key, this.launcher});

  /// Injectable URL opener for tests. Defaults to [launchUrl]. Returns whether
  /// the launch succeeded.
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<SpeedtestServicesScreen> createState() =>
      _SpeedtestServicesScreenState();
}

class _SpeedtestServicesScreenState extends State<SpeedtestServicesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  String _query = '';
  String? _launchError;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  List<SpeedtestService> get _matches {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return kSpeedtestServices;
    return kSpeedtestServices.where((SpeedtestService s) {
      return s.name.toLowerCase().contains(q) ||
          s.operator.toLowerCase().contains(q) ||
          s.what.toLowerCase().contains(q) ||
          s.how.toLowerCase().contains(q) ||
          s.streamModel.label.toLowerCase().contains(q) ||
          s.proximity.label.toLowerCase().contains(q) ||
          (s.backendNote?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final int n = _matches.length;
    // WCAG 4.1.3 — announce the live result count without moving focus.
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0
          ? 'No matching services'
          : '$n matching service${n == 1 ? '' : 's'}',
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
    setState(
      () => _launchError = 'Could not open the browser. The link is $url',
    );
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  /// §8.16 plain-text payload — the hero, every honesty caveat, and every
  /// service's full row so nothing on-screen survives only as a color or layout.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Speed Test Services')
      ..writeln()
      ..writeln(kSpeedtestHeroLine)
      ..writeln()
      ..writeln('Data caveat: $kSpeedtestDataCaveat')
      ..writeln('Independence: $kSpeedtestBackendNote')
      ..writeln('Orb: $kSpeedtestOrbNote')
      ..writeln()
      ..writeln(
        <String>[
          'Service',
          'Operator',
          'Site',
          'Stream',
          'Server',
          'Measures',
          'How',
          'Data per test',
          'Open-source / self-host',
        ].join(tab),
      );
    for (final SpeedtestService s in kSpeedtestServices) {
      b.writeln(
        <String>[
          s.isMonitor ? '${s.name} (monitor, not a one-shot test)' : s.name,
          s.operator,
          s.url,
          s.streamModel.label,
          s.proximity.label,
          s.what,
          s.how,
          '${s.dataPerTest} (${s.dataConfidence.marker})',
          s.openSource,
        ].join(tab),
      );
      if (s.backendNote != null) b.writeln('  Runs on: ${s.backendNote}');
    }
    b
      ..writeln()
      ..writeln('Teaching notes:');
    for (final ({String title, String body}) c in kSpeedtestCallouts) {
      b.writeln('- ${c.title}: ${c.body}');
    }
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speed Test Services'),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(textBuilder: _copyText),
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
        final List<SpeedtestService> matches = _matches;
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
                    toolId: kSpeedtestServicesToolId,
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic(kSpeedtestServicesToolId))
                    const SizedBox(height: AppSpacing.md),
                  const _HeroCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _CaveatBand(),
                  const SizedBox(height: AppSpacing.md),
                  const _CalloutGrid(),
                  // The "where you test along the path changes the result"
                  // reference diagram — the visual summary of the three callouts
                  // above. Omitted entirely (no gap, no broken box) when the
                  // asset is not bundled.
                  if (ThroughputWhereDiagram.isBundled) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    const ThroughputWhereDiagramCard(),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _searchCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  if (matches.isEmpty)
                    _MessageCard(
                      icon: Icons.search_off,
                      title: 'No match',
                      body: 'No service matches "${_query.trim()}".',
                    )
                  else
                    ...matches.map(
                      (SpeedtestService s) =>
                          _ServiceCard(service: s, onOpen: _openUrl),
                    ),
                  if (_launchError != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _MessageCard(
                      icon: Icons.link_off,
                      title: 'Could not open the link',
                      body: _launchError!,
                    ),
                  ],
                  ToolHelpFooter(toolId: kSpeedtestServicesToolId),
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
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LabeledField(
        label: 'Search',
        hint: 'service, operator, or how it measures',
        semanticLabel:
            'Search speed test services by name, operator, or method',
        field: TextField(
          controller: _queryCtrl,
          focusNode: _queryFocus,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          cursorColor: colors.textAccent,
          decoration: const InputDecoration(
            hintText: 'e.g. Cloudflare, bufferbloat, single-stream, self-host',
          ),
        ),
      ),
    );
  }
}

/// The hero band: the brief's conclusion-first line that a speed test measures
/// one path at one moment, not your Wi-Fi.
class _HeroCard extends StatelessWidget {
  const _HeroCard();

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
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        kSpeedtestHeroLine,
        style: (t.bodyLarge ?? const TextStyle()).copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The persistent honesty caveat band (data-per-test estimates + independence +
/// the Orb framing). Warning-toned, paired with text, never color-only (§8.13).
class _CaveatBand extends StatelessWidget {
  const _CaveatBand();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final Color warn = colors.statusWarning;

    Widget line(IconData icon, String text, {bool warnTone = false}) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: warnTone ? warn : colors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: t.bodySmall?.copyWith(
                  color: warnTone ? warn : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'How to read this page. $kSpeedtestDataCaveat '
          '$kSpeedtestBackendNote $kSpeedtestOrbNote',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'HOW TO READ THIS PAGE',
              style: (t.labelMedium ?? const TextStyle()).copyWith(
                color: warn,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            line(Icons.calculate_outlined, kSpeedtestDataCaveat,
                warnTone: true),
            line(Icons.account_tree_outlined, kSpeedtestBackendNote),
            line(Icons.monitor_heart_outlined, kSpeedtestOrbNote),
          ],
        ),
      ),
    );
  }
}

/// The three teaching callouts (CDN-edge vs real internet; bufferbloat beats
/// peak; single vs multi-stream). One card each, stacked.
class _CalloutGrid extends StatelessWidget {
  const _CalloutGrid();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < kSpeedtestCallouts.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Semantics(
            container: true,
            label:
                '${kSpeedtestCallouts[i].title}. ${kSpeedtestCallouts[i].body}',
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
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 4,
                        height: 14,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          kSpeedtestCallouts[i].title,
                          style: (t.titleSmall ?? const TextStyle()).copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    kSpeedtestCallouts[i].body,
                    style: t.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One service card: logo (or name-label fallback) + name + operator, the
/// monitor badge for Orb, the two-axis chips, what/how prose, the data-per-test
/// figure with its confidence marker, the open-source note, the optional
/// "Runs on" backend note, and a website link-out chip.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onOpen});

  final SpeedtestService service;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;

    final String spoken = rowLabel(service.name, <String?>[
      service.operator,
      if (service.isMonitor) 'continuous monitor, not a one-shot test',
      service.streamModel.label,
      service.proximity.label,
      service.what,
      service.how,
      'data per test ${service.dataPerTest}, ${service.dataConfidence.marker}',
      service.openSource,
      if (service.backendNote != null) 'Runs on ${service.backendNote}',
    ]);

    return ReferenceRowSemantics(
      label: spoken,
      merge: false,
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
            // Header: logo (or fallback) + name + operator.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ServiceLogo(service: service),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        service.name,
                        style: (t.titleMedium ?? const TextStyle()).copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        service.operator,
                        style: t.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (service.isMonitor) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              const _MonitorBadge(),
            ],
            const SizedBox(height: AppSpacing.xs),
            // The two teaching axes as neutral chips.
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                _AxisChip(
                  icon: Icons.alt_route,
                  label: service.streamModel.label,
                ),
                _AxisChip(
                  icon: Icons.dns_outlined,
                  label: service.proximity.label,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _LabeledLine(label: 'Measures', value: service.what),
            const SizedBox(height: AppSpacing.xxs),
            _LabeledLine(label: 'How', value: service.how),
            const SizedBox(height: AppSpacing.xs),
            _DataPerTest(service: service),
            const SizedBox(height: AppSpacing.xxs),
            _LabeledLine(label: 'Open-source', value: service.openSource),
            if (service.backendNote != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              _BackendNote(text: service.backendNote!),
            ],
            const SizedBox(height: AppSpacing.sm),
            _LinkChip(
              icon: Icons.open_in_new,
              label: 'Visit site',
              semanticLabel: 'Open the ${service.name} website',
              onTap: () => onOpen(service.url),
            ),
          ],
        ),
      ),
    );
  }
}

/// The logo slot: a manifest-gated wordmark when bundled, else a name-initial
/// label fallback so the card never shows a broken-image box and a missing logo
/// degrades cleanly (per the build brief).
class _ServiceLogo extends StatelessWidget {
  const _ServiceLogo({required this.service});

  final SpeedtestService service;

  static const double _box = 40;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final SpeedtestLogo? logo = SpeedtestLogos.logoFor(service.slug);

    // No bundled wordmark → the name-initial fallback, which already paints its
    // own bordered chip. Render it bare so the chip is not doubled.
    if (logo == null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ExcludeSemantics(child: _LogoFallback(name: service.name)),
      );
    }

    // Vendor wordmarks carry fixed brand colors; dark-fill marks (Ookla,
    // OpenSpeedTest) would be invisible on the dark canvas, and white marks fail
    // on light. Render every wordmark on a neutral chip in BOTH modes — the same
    // treatment the shipped Regulatory Domains and Wi-Fi Standards Bodies screens
    // use for official marks (colors.isLight ? surface1 : surface2, AppRadius
    // .control, AppSpacing.xxs padding). Consistency across the three logo
    // screens is the goal.
    final double inner = _box - AppSpacing.xxs * 2;
    final Widget mark = logo.format == SpeedtestLogoFormat.svg
        ? SvgPicture.asset(
            logo.path,
            width: inner,
            height: inner,
            fit: BoxFit.contain,
            // Wordmark — decorative; the name is the text carrier beside it.
            excludeFromSemantics: true,
            placeholderBuilder: (BuildContext _) =>
                _LogoFallback(name: service.name),
          )
        : Image.asset(
            logo.path,
            width: inner,
            height: inner,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                _LogoFallback(name: service.name),
          );

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ExcludeSemantics(
        child: SizedBox(
          width: _box,
          height: _box,
          child: Container(
            decoration: BoxDecoration(
              color: colors.isLight ? colors.surface1 : colors.surface2,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            padding: const EdgeInsets.all(AppSpacing.xxs),
            alignment: Alignment.center,
            child: mark,
          ),
        ),
      ),
    );
  }
}

/// Name-initial fallback when no wordmark is bundled. A bordered square with the
/// first letter — never a broken-image box.
class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final String initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colors.border, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: (t.titleMedium ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The Orb-only badge: "Monitor, not a one-shot test." Carries the fact in text
/// (never color-only); a thin info-toned outline.
class _MonitorBadge extends StatelessWidget {
  const _MonitorBadge();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      label: 'Continuous monitor, not a one-shot test',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: colors.statusInfo, width: 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.monitor_heart_outlined,
                size: 14, color: colors.statusInfo),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'Monitor, not a one-shot test',
              style: (t.labelSmall ?? const TextStyle()).copyWith(
                color: colors.statusInfo,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A neutral outlined chip for one of the two teaching axes (stream model /
/// server proximity). Carries the fact in its label, no verdict color.
class _AxisChip extends StatelessWidget {
  const _AxisChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong, width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// An inline "Label: value" line, label in the muted tertiary, value in body.
class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return RichText(
      text: TextSpan(
        style: t.bodySmall?.copyWith(color: colors.textSecondary),
        children: <InlineSpan>[
          TextSpan(
            text: '$label  ',
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textTertiary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

/// The data-per-test figure with its always-visible confidence marker. The
/// marker is the hedge: the figure is never stated as a settled fact.
class _DataPerTest extends StatelessWidget {
  const _DataPerTest({required this.service});

  final SpeedtestService service;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool firm = service.dataConfidence == DataConfidence.high;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.data_usage_outlined, size: 16, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
              children: <InlineSpan>[
                TextSpan(
                  text: 'DATA PER TEST  ',
                  style: (t.labelSmall ?? const TextStyle()).copyWith(
                    color: colors.textTertiary,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '${service.dataPerTest} '),
                TextSpan(
                  text: '(${service.dataConfidence.marker})',
                  style: t.bodySmall?.copyWith(
                    color: firm ? colors.textTertiary : colors.statusWarning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Runs on" backend note for services that are not their own measurement
/// infrastructure. Info-toned so it reads as an editorial flag, not a verdict.
class _BackendNote extends StatelessWidget {
  const _BackendNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.isLight
            ? colors.statusInfoFill
            : colors.statusInfo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.account_tree_outlined,
              size: 14, color: colors.statusInfo),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: t.bodySmall?.copyWith(color: colors.textSecondary),
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Runs on  ',
                    style: (t.labelSmall ?? const TextStyle()).copyWith(
                      color: colors.statusInfo,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
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

/// The "where you test throughput along the path changes the result" reference
/// diagram — a Vera-passed, DARK-BAKED raster (white WLAN Pros logo on the §8
/// dark canvas). It visually summarizes the three teaching callouts above: the
/// number a speed test reports depends on WHERE along the
/// client → Wi-Fi → router → ISP → CDN-edge → distant-server path you measure.
///
/// PRESENTATION (load-bearing): the diagram is a pre-rendered PNG, so it cannot
/// take the §8.20.7 runtime light-mode per-mark swap that the SVG concept
/// graphics use. It is therefore mounted on an ALWAYS-DARK surface card in both
/// themes — the #222222 surface it was authored against (§8.6.2) — so it never
/// reads inverted on a light canvas. The always-dark backing comes from
/// [AppColorScheme.dark], the same "render on the always-dark scrim/chip" idiom
/// the zoom badge and the logo chips already use.
///
/// INTERACTION: tap (or keyboard-activate) the diagram to open a full-screen
/// pinch-zoom + pan view (raster `InteractiveViewer`, minScale 1, maxScale 5) —
/// the detail-dense diagram is hard to read inline on a phone. A subtle
/// magnifier badge advertises the affordance.
///
/// A11Y (§8.6.2): the image itself is decorative (every fact it depicts is in
/// the screen's hero, caveats, and callouts), so it is `ExcludeSemantics` /
/// `excludeFromSemantics`. The TAP TARGET is a real labeled
/// `Semantics(button: true, label: 'Zoom the throughput-testing diagram')` so
/// screen readers announce an operable control and Enter/Space activate it. The
/// caption below carries the one-line teaching point as real text.
class ThroughputWhereDiagramCard extends StatelessWidget {
  const ThroughputWhereDiagramCard({super.key});

  /// The diagram's true aspect ratio (3360 × 4178 source PNG ≈ 0.804). Pinning
  /// it keeps the inline render the right shape without measuring the image.
  static const double _aspectRatio = 3360 / 4178;

  static const String _caption =
      'Where you test along the path changes the number. The same connection '
      'reads differently at the Wi-Fi link, the router, the ISP edge, a nearby '
      'CDN, or a distant server. Tap to zoom.';

  void _openZoom(BuildContext context) {
    final AppColorScheme zoomColors = AppColorScheme.dark();
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        // Opaque so the underlying page does not bleed through; the dark-baked
        // raster wants an always-dark lightbox in both themes.
        opaque: true,
        barrierColor: zoomColors.scrim,
        barrierDismissible: true,
        barrierLabel: 'Zoomed throughput-testing diagram',
        transitionDuration: AppMotion.base,
        reverseTransitionDuration: AppMotion.fast,
        pageBuilder: (BuildContext context, Animation<double> a,
                Animation<double> b) =>
            const _ThroughputWhereZoomView(),
        transitionsBuilder: (BuildContext context, Animation<double> anim,
            Animation<double> secondary, Widget child) {
          return FadeTransition(
            opacity:
                CurvedAnimation(parent: anim, curve: AppMotion.standardEase),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ALWAYS-DARK surface for the dark-baked raster, regardless of app theme.
    final AppColorScheme dark = AppColorScheme.dark();
    final TextTheme t = Theme.of(context).textTheme;
    // The caption sits below the dark card on the SCREEN surface, so it uses the
    // live theme colors (context.colors) to read on both light and dark canvases.
    final AppColorScheme live = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Zoom the throughput-testing diagram',
          onTap: () => _openZoom(context),
          child: Container(
            decoration: BoxDecoration(
              color: dark.surface1,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: dark.border, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Stack(
              children: <Widget>[
                ExcludeSemantics(
                  // A minimum height guarantees the card (and its tap target)
                  // always has real layout even before the async image decodes
                  // or if a platform reports no intrinsic image size, so the
                  // whole-graphic tap region is never zero-size.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSpacing.xxl),
                    child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Image.asset(
                        ThroughputWhereDiagram.assetPath,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        errorBuilder:
                            (BuildContext _, Object _, StackTrace? _) =>
                                const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                // Whole-graphic tap layer (single click on desktop) → zoom.
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openZoom(context),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                // Subtle, discoverable magnifier badge (bottom-right).
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: ExcludeSemantics(
                    child: Container(
                      decoration: BoxDecoration(
                        color: dark.scrim,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: Icon(
                        Icons.zoom_in,
                        color: dark.textPrimary,
                        size: AppSpacing.sm,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _caption,
          style: t.bodySmall?.copyWith(color: live.textTertiary),
        ),
      ],
    );
  }
}

/// Full-screen pinch-zoom + pan view for the throughput-testing reference
/// diagram. Raster sibling of [ZoomableGraphic]'s `_ZoomView` (that one is
/// SVG-only via an svgBuilder; this renders the bundled PNG). Always-dark
/// backdrop in both themes — the diagram is dark-baked. Dismisses on the X
/// button, a tap on the empty backdrop, a swipe-down, or system back / Escape.
class _ThroughputWhereZoomView extends StatelessWidget {
  const _ThroughputWhereZoomView();

  static const double _minScale = 1;
  static const double _maxScale = 5;

  @override
  Widget build(BuildContext context) {
    // Always-dark lightbox for the dark-baked raster.
    final AppColorScheme dark = AppColorScheme.dark();
    final MediaQueryData mq = MediaQuery.of(context);
    final EdgeInsets safe = mq.padding;

    return Scaffold(
      backgroundColor: dark.surface0,
      body: Stack(
        children: <Widget>[
          // Tap / swipe-down the empty backdrop to dismiss.
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                onVerticalDragEnd: (DragEndDetails d) {
                  if ((d.primaryVelocity ?? 0) > 0) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              safe.left + AppSpacing.md,
              safe.top + AppSpacing.xxl,
              safe.right + AppSpacing.md,
              safe.bottom + AppSpacing.md,
            ),
            child: Center(
              child: InteractiveViewer(
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(AppSpacing.xxl),
                child: ExcludeSemantics(
                  child: Image.asset(
                    ThroughputWhereDiagram.assetPath,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                    errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          // Close affordance — a real labeled button, top-right.
          Positioned(
            top: safe.top + AppSpacing.xs,
            right: safe.right + AppSpacing.xs,
            child: Semantics(
              button: true,
              label: 'Close zoom',
              child: Material(
                color: dark.scrim,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: SizedBox(
                    height: AppSpacing.minTouchTarget,
                    width: AppSpacing.minTouchTarget,
                    child: Icon(
                      Icons.close,
                      color: dark.textPrimary,
                      size: AppSpacing.md,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
