// NEC Gotchas on a WLAN Job — read-only field/trade reference (#4 of the Field
// Reference REFERENCE-screen set, 2026-07-05). Clones the Enclosure Ratings
// pilot pattern verbatim.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/03-nec-gotchas.md) as
// native layout, with Vera's NEC-gotchas cutaway plate embedded at the top via
// DarkRasterDiagramCard (always-dark surface in both themes, tap to pinch-zoom).
// Every fact the plate depicts is ALSO in the native text below it, so the image
// is decorative for screen readers and never the sole carrier of meaning
// (GL-003 §8.6.2 a11y rule).
//
// RECOGNIZE-AND-DEFER: each article names what to recognize on site, then hands
// it to the AHJ, a licensed electrician, or the equipment listing. The two
// articles where a number must not be eyeballed (PoE bundle ampacity, firestop
// assembly) carry a recognize-and-STOP warning band. It never adds procedure or
// a "how to comply" step.
//
// States (SOP-007 §5): pure read-only reference — no inputs, no computation, no
// network (GL-008 does not apply; nothing to fetch, shell out to, or fabricate).
//   - success  → the compile-time const copy always renders. The diagram card
//     appears only when its PNG is bundled (ReferenceImages.isBundled);
//     otherwise it is omitted and every article still reads end-to-end.
//   - loading / empty / error → not reachable; nothing is fetched or parsed.
//   - interactive → the plate's tap-to-zoom, the §8.16 copy action, and the
//     §8.16.1 help footer (each carries its own §8.3 focus ring).
//   - disabled → copy is always enabled (static content is always present).
//
// THEME: every chrome color comes from context.colors (dark §8 / light §8.20).
// STOP bands use Icons.warning_amber_rounded (the fixed convention); the honest
// caveat and the defer footer use Icons.info_outline. Never color-only meaning
// (§8.13). No new tokens.
//
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing.
//
// Pattern: matches enclosure_ratings_screen — Scaffold + AppBar (toolbarHeight
// 64) + §8.16 copy action, SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView of cards.

import 'package:flutter/material.dart';

import '../../../data/nec_gotchas_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';

class NecGotchasScreen extends StatelessWidget {
  const NecGotchasScreen({super.key});

  /// The cutaway plate's true aspect ratio (width / height). Master render is
  /// 3360 x 2966.
  static const double _diagramAspect = 3360 / 2966;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NEC Gotchas'),
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
        final bool hasDiagram = ReferenceImages.isBundled(kNecGotchasToolId);
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
                      assetPath: ReferenceImages.pathFor(kNecGotchasToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'building cutaway of the NEC articles that bite a WLAN '
                          'install',
                      caption:
                          'Where each code article bites on a real building.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kNecGotchasToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kNecGotchasToolId),
                      title: 'NEC Gotchas',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _LeadCard(),
                  // The six numbered gotchas — a clean set of six, matching the
                  // lead's and recap's "six" claim and the plate's six callouts.
                  for (final NecArticle a in kNecArticles) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _ArticleCard(a),
                  ],
                  // Article 800 cable ladder — set apart as a SUPPORTING
                  // reference, not a seventh peer gotcha (mirrors the plate's
                  // separate fire-rating-ladder band).
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionHeading(label: kNecCableLadderSectionTitle),
                  const SizedBox(height: AppSpacing.sm),
                  const _ArticleCard(kNecCableLadder),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCaresCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DeferBand(),
                  ToolHelpFooter(toolId: kNecGotchasToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// §8.16 plain-text payload — the full reference as sections so it pastes
  /// cleanly into notes or a spec review. Always non-null (static).
  static String _copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('NEC Gotchas on a WLAN Job')
      ..writeln()
      ..writeln(kNecLead);
    for (final NecArticle a in kNecArticles) {
      _writeArticle(b, a);
    }
    // The cable-rating ladder is a supporting reference, set apart under its own
    // heading, not one of the six gotchas.
    b
      ..writeln()
      ..writeln(kNecCableLadderSectionTitle);
    _writeArticle(b, kNecCableLadder);
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kNecWlanCares)
      ..writeln()
      ..writeln(kNecDeferNote);
    return b.toString().trimRight();
  }

  /// Append one article (title, body, optional bullets/tail/stop/caveat) to the
  /// §8.16 copy buffer. Shared by the six gotchas and the supporting ladder so
  /// both serialize identically.
  static void _writeArticle(StringBuffer b, NecArticle a) {
    b
      ..writeln()
      ..writeln(a.title)
      ..writeln(a.body);
    for (final String bullet in a.bullets) {
      b.writeln('- $bullet');
    }
    if (a.tail != null) b.writeln(a.tail);
    if (a.stop != null) b.writeln(a.stop);
    if (a.caveat != null) b.writeln(a.caveat);
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

/// A bulleted list of prose strings, each a real semantic line.
class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                child: Icon(Icons.circle, size: 6, color: colors.textAccent),
              ),
              Expanded(
                child: Text(
                  items[i],
                  style: t.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A recognize-and-STOP warning band (icon + text, never color-only, §8.13).
/// Fixed convention: Icons.warning_amber_rounded.
class _StopBand extends StatelessWidget {
  const _StopBand(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusWarningFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusWarning, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, size: 20, color: colors.statusWarning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An honest-limits caveat band (icon + text, info tone, §8.13).
class _CaveatBand extends StatelessWidget {
  const _CaveatBand(this.text);

  final String text;

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
              text,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── section cards ──────────────────────────────

/// A section heading standing on the page background above a card, used to set
/// the supporting cable-rating ladder apart from the six numbered gotchas.
/// Mirrors the shared reference-screen `_SectionHeading` register (titleSmall,
/// secondary, tracked).
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      label,
      style: text.titleSmall?.copyWith(
        color: colors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// The lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kNecLead));
  }
}

/// One NEC-article card: title + body + optional bullets + tail + STOP + caveat.
class _ArticleCard extends StatelessWidget {
  const _ArticleCard(this.article);

  final NecArticle article;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: article.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Body(article.body),
          if (article.bullets.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Bullets(article.bullets),
          ],
          if (article.tail != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _Body(article.tail!),
          ],
          if (article.stop != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _StopBand(article.stop!),
          ],
          if (article.caveat != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _CaveatBand(article.caveat!),
          ],
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
      child: _Body(kNecWlanCares),
    );
  }
}

/// The recognize-and-defer footer as an info band (icon + text, §8.13).
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
              kNecDeferNote,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
