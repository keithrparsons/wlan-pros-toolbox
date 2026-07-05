// Site Access ("Know Before You Go") - read-only field/trade reference (Field
// Reference set, 2026-07-05). Clones the Enclosure Ratings reference-screen
// pattern.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/06-site-access.md) as
// native layout, with Charta's site-access-matrix plate embedded at the top via
// the established DarkRasterDiagramCard (always-dark surface in both themes, tap
// to pinch-zoom). Every fact the plate depicts is ALSO in the native text below
// it, so the image is decorative for screen readers and never the sole carrier
// of meaning (GL-003 §8.6.2 a11y rule).
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders. The diagram card
//     appears only when its PNG is bundled (ReferenceImages.isBundled);
//     otherwise it is omitted and every card still reads end-to-end.
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the plate's tap-to-zoom, the AppBar §8.16 copy action, and
//     the §8.16.1 help footer (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// The defer footer is an info band (statusInfo glyph + word, never color-only,
// §8.13).
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.

import 'package:flutter/material.dart';

import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../data/site_access_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';

class SiteAccessScreen extends StatelessWidget {
  const SiteAccessScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2456 (assets/reference/site-access.png).
  static const double _diagramAspect = 3360 / 2456;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Site Access'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
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
        final bool hasDiagram = ReferenceImages.isBundled(kSiteAccessToolId);
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
                  if (hasDiagram) ...<Widget>[
                    DarkRasterDiagramCard(
                      assetPath: ReferenceImages.pathFor(kSiteAccessToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Site-access matrix: environment, what may gate you, '
                          'and what to ask about before you mobilize',
                      caption: 'Scope the credential before you quote.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kSiteAccessToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kSiteAccessToolId),
                      title: 'Site Access',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _LeadCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _PatternCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _ChecklistCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCaresCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DeferBand(),
                  ToolHelpFooter(toolId: kSiteAccessToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// §8.16 plain-text payload - the full reference as tab-separated sections.
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Site Access (Know Before You Go)')
      ..writeln()
      ..writeln(kSiteAccessLead)
      ..writeln()
      ..writeln(kSiteAccessPattern)
      ..writeln()
      ..writeln('The checklist')
      ..writeln(
        <String>['Environment', 'What may gate you', 'Ask about'].join(tab),
      );
    for (final SiteAccessRow r in kSiteAccessRows) {
      b.writeln(<String>[r.environment, r.gate, r.askAbout].join(tab));
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kSiteAccessWlanCares)
      ..writeln()
      ..writeln(kSiteAccessDeferNote);
    return b.toString().trimRight();
  }
}

// ─────────────────────────────── shared card shell ──────────────────────────

/// Surface-1 card with an optional section title (labelMedium, tracked).
class _Card extends StatelessWidget {
  const _Card({this.title, required this.child});

  final String? title;
  final Widget child;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// A body paragraph in the standard secondary color.
class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: (t.bodyMedium ?? const TextStyle()).copyWith(
        color: colors.textSecondary,
      ),
    );
  }
}

// ─────────────────────────────── section cards ──────────────────────────────

/// The italic lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kSiteAccessLead));
  }
}

/// The shared pattern across every checklist item (untitled card).
class _PatternCard extends StatelessWidget {
  const _PatternCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kSiteAccessPattern));
  }
}

/// The eight-environment access checklist.
class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return _Card(
      title: 'The checklist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < kSiteAccessRows.length; i++) ...<Widget>[
            if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
            _SiteAccessRowView(row: kSiteAccessRows[i]),
          ],
        ],
      ),
    );
  }
}

/// One access-checklist row: the environment (bold), what may gate you (body),
/// and an "Ask about" label with its list. The whole row is one Semantics unit.
class _SiteAccessRowView extends StatelessWidget {
  const _SiteAccessRowView({required this.row});

  final SiteAccessRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label:
          '${row.environment}. What may gate you: ${row.gate}. '
          'Ask about: ${row.askAbout}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            row.environment,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            row.gate,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ask about',
            style: (t.labelSmall ?? const TextStyle()).copyWith(
              color: colors.textAccent,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            row.askAbout,
            style: t.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Why a WLAN pro cares.
class _WlanCaresCard extends StatelessWidget {
  const _WlanCaresCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      title: 'Why a WLAN pro cares',
      child: _Body(kSiteAccessWlanCares),
    );
  }
}

/// The defer footer as an info band (icon + text, §8.13).
class _DeferBand extends StatelessWidget {
  const _DeferBand();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusInfoFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusInfo, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 20, color: colors.statusInfo),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              kSiteAccessDeferNote,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
