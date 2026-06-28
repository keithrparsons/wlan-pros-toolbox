// Ham Radio Study Resources — a vetted, offline list of where to study for the
// amateur-radio exams, with each resource credited and an "Open website" button
// (url_launcher, externalApplication mode, matching the Educational Resources
// detail screen).
//
// DATA: lib/data/ham_reference_data.dart (kHamStudyResources,
// kHamExamStructure, and the two currency caveats). The two landmines are baked
// in as guardrails: the new Technician question pool (1 Jul 2026) is surfaced as
// "35 questions, 26 to pass" with NO hard-coded pool count, and the 60 m rule
// change (13 Feb 2026) is called out.
//
// States (SOP-007 sec 5):
//   - success     -> the resource cards + exam structure render.
//   - error       -> a browser hand-off that fails shows an honest inline note
//                    with the raw URL, never a silent failure.
//   - empty/loading -> not reachable; the data is a compile-time const.
//   - interactive -> the per-resource "Open website" buttons + AppCopyAction.
//
// NETWORK (GL-008): the only network action is a browser hand-off via
// url_launcher (HTTPS, externalApplication) — not an in-app fetch, so no ATS
// exception or macOS entitlement is needed.
//
// THEME: chrome from context.colors; no DM Mono numerics. No new tokens; no em
// dash (GL-004).
//
// ICON: bespoke Tier-2 icon resolves at assets/tool-icons/ham-study-resources
// .svg when Charta ships it; falls back to the category glyph until then.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/ham_reference_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../reference/reference_row_semantics.dart';

/// Stable catalog tool id — backs the route, the help entry, and the tests.
const String kHamStudyResourcesToolId = 'ham-study-resources';

class HamStudyResourcesScreen extends StatefulWidget {
  const HamStudyResourcesScreen({super.key, this.launcher});

  /// Injectable URL opener for tests. Defaults to [launchUrl]. Returns whether
  /// the launch succeeded.
  final Future<bool> Function(Uri url)? launcher;

  @override
  State<HamStudyResourcesScreen> createState() =>
      _HamStudyResourcesScreenState();
}

class _HamStudyResourcesScreenState extends State<HamStudyResourcesScreen> {
  /// The resource title whose launch failed, plus its URL — drives the inline
  /// error note. Null when no launch has failed.
  String? _launchErrorFor;
  String? _launchErrorUrl;

  Future<void> _open(HamStudyResource r) async {
    final String? url = r.url;
    if (url == null) return;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      _showLaunchError(r.title, url);
      return;
    }
    final Future<bool> Function(Uri) launch = widget.launcher ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      final bool ok = await launch(uri);
      if (!ok) {
        _showLaunchError(r.title, url);
        return;
      }
      if (!mounted) return;
      setState(() {
        _launchErrorFor = null;
        _launchErrorUrl = null;
      });
    } on Object {
      _showLaunchError(r.title, url);
    }
  }

  void _showLaunchError(String title, String url) {
    if (!mounted) return;
    setState(() {
      _launchErrorFor = title;
      _launchErrorUrl = url;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Could not open the browser',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the resources (with credit + URL), the exam
  /// structure, and the two currency caveats.
  static String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ham Radio Study Resources');
    for (final HamStudyResource r in kHamStudyResources) {
      buf
        ..writeln()
        ..writeln(r.title)
        ..writeln('For: ${r.forWhat}')
        ..writeln('Classes: ${r.classes}')
        ..writeln('Currency: ${r.authority}')
        ..writeln('Credit: ${r.credit}')
        ..writeln('Note: ${r.vetNote}');
      if (r.url != null) buf.writeln('Link: ${r.url}');
    }
    buf
      ..writeln()
      ..writeln('Exam structure (NCVEC / 97.503)')
      ..writeln(<String>['Element', 'Questions', 'To pass'].join(tab));
    for (final HamExamFact f in kHamExamStructure) {
      buf.writeln(<String>[f.element, f.questions, f.toPass].join(tab));
    }
    buf
      ..writeln(kHamExamNoMorse)
      ..writeln()
      ..writeln('Question pools: $kHamPoolCaveat')
      ..writeln('60 m: $kHam60mCaveat');
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ham Radio Study Resources'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
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
                  _caveatsCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ...kHamStudyResources.map(
                    (HamStudyResource r) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _ResourceCard(
                        resource: r,
                        onOpen: () => _open(r),
                        errorUrl: _launchErrorFor == r.title
                            ? _launchErrorUrl
                            : null,
                      ),
                    ),
                  ),
                  _examCard(context),
                  ToolHelpFooter(toolId: kHamStudyResourcesToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The two currency caveats up top — they govern how to read everything
  /// below, so they lead.
  Widget _caveatsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    Widget caveat(String body) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline, size: 18, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  body,
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Read these first',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          caveat(kHamPoolCaveat),
          caveat(kHam60mCaveat),
        ],
      ),
    );
  }

  Widget _examCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Exam structure',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...kHamExamStructure.asMap().entries.expand(
            (MapEntry<int, HamExamFact> entry) {
              final HamExamFact f = entry.value;
              return <Widget>[
                if (entry.key > 0)
                  Divider(color: colors.border, height: AppSpacing.sm),
                ReferenceRowSemantics(
                  label: rowLabel(
                    f.element,
                    <String?>[f.questions, f.toPass],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            f.element,
                            style: text.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            '${f.questions}, ${f.toPass}',
                            style: text.bodyMedium
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ];
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kHamExamNoMorse,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// One study resource: title, the "for / classes / currency" facts, credit, the
/// vet note, and an "Open website" button (when it has a URL). Renders an inline
/// error note if a launch failed.
class _ResourceCard extends StatelessWidget {
  const _ResourceCard({
    required this.resource,
    required this.onOpen,
    this.errorUrl,
  });

  final HamStudyResource resource;
  final VoidCallback onOpen;

  /// Non-null when this resource's last launch attempt failed.
  final String? errorUrl;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    Widget fact(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: text.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  value,
                  style: text.labelMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            resource.title,
            style: text.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            resource.forWhat,
            style: text.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          fact('Classes', resource.classes),
          fact('Currency', resource.authority),
          fact('Credit', resource.credit),
          const SizedBox(height: AppSpacing.xs),
          Text(
            resource.vetNote,
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          if (resource.url != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open website'),
              ),
            ),
          ],
          if (errorUrl != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline,
                    size: 18, color: colors.statusDanger),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Could not open the browser. The link is $errorUrl',
                    style: text.labelMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
