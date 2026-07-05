// Safety Basics: PPE + ESD - read-only field/trade reference (Field Reference
// set, 2026-07-05). Clones the Enclosure Ratings reference-screen pattern.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/04-safety-basics.md) as
// native layout, with Charta's PPE-standards plate embedded at the top via the
// established DarkRasterDiagramCard (always-dark surface in both themes, tap to
// pinch-zoom). Every fact the plate depicts is ALSO in the native text below it,
// so the image is decorative for screen readers and never the sole carrier of
// meaning (GL-003 §8.6.2 a11y rule).
//
// The recognize-and-STOP hazards (asbestos/lead, arc-flash/LOTO, confined space,
// seismic bracing) are rendered NAMED-AND-STOPPED - each on a warning band
// (statusWarning glyph + word, never color-only, §8.13) carrying Penn's verbatim
// "recognize it, then hand it off" line. No procedure is added; the screen never
// tells a reader how to work any of them.
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
// Glyph rules (GL-004): ASCII hyphen-minus only, never an em dash; "Wi-Fi"
// casing; standards designators in DM Mono (AppMonoText.inlineCode).

import 'package:flutter/material.dart';

import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../data/safety_basics_data.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';

class SafetyBasicsScreen extends StatelessWidget {
  const SafetyBasicsScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2146 (assets/reference/safety-basics.png).
  static const double _diagramAspect = 3360 / 2146;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Basics'),
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
        final bool hasDiagram =
            ReferenceImages.isBundled(kSafetyBasicsToolId);
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
                      assetPath:
                          ReferenceImages.pathFor(kSafetyBasicsToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'PPE standards reference diagram: hard hat, '
                          'safety-toe footwear, high-visibility apparel, and '
                          'eye protection',
                      caption: 'The PPE a GC expects before you badge on.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kSafetyBasicsToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kSafetyBasicsToolId),
                      title: 'Safety Basics',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _LeadCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _PpeLadderCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _EsdCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _StopCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCaresCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _DeferBand(),
                  ToolHelpFooter(toolId: kSafetyBasicsToolId),
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
      ..writeln('Safety Basics: PPE + ESD')
      ..writeln()
      ..writeln(kSafetyLead)
      ..writeln()
      ..writeln('The PPE ladder')
      ..writeln(kPpeIntro)
      ..writeln(<String>['PPE', 'Standard', 'What the rating means'].join(tab));
    for (final PpeItem p in kPpeItems) {
      b.writeln(<String>[p.name, p.standard, p.meaning].join(tab));
    }
    b
      ..writeln(kPpeProofTestNote)
      ..writeln(kPpeNote)
      ..writeln()
      ..writeln('ESD: protecting the gear, not the person');
    for (final String p in kEsdParagraphs) {
      b.writeln(p);
    }
    b
      ..writeln()
      ..writeln('Recognize and STOP')
      ..writeln(kSafetyStopIntro);
    for (final String h in kSafetyStopHazards) {
      b.writeln('- $h');
    }
    b
      ..writeln(kSafetyStopClosing)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kSafetyWlanCares)
      ..writeln()
      ..writeln(kSafetyDeferNote);
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

/// A muted one-line caption / footnote (tertiary).
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Text(
      text,
      style: t.bodySmall?.copyWith(color: colors.textTertiary),
    );
  }
}

// ─────────────────────────────── section cards ──────────────────────────────

/// The italic lead paragraph.
class _LeadCard extends StatelessWidget {
  const _LeadCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(child: _Body(kSafetyLead));
  }
}

/// The PPE ladder: intro + the four items (name, standard, meaning) + the note.
class _PpeLadderCard extends StatelessWidget {
  const _PpeLadderCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return _Card(
      title: 'The PPE ladder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Body(kPpeIntro),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < kPpeItems.length; i++) ...<Widget>[
            if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
            _PpeRow(item: kPpeItems[i]),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kPpeProofTestNote),
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kPpeNote),
        ],
      ),
    );
  }
}

/// One PPE row: the item name (bold), the standard (accent mono), and what the
/// rating means (secondary). The whole row is one Semantics unit.
class _PpeRow extends StatelessWidget {
  const _PpeRow({required this.item});

  final PpeItem item;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Semantics(
      container: true,
      label: '${item.name}. ${item.standard}. ${item.meaning}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.name,
            style: (t.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.standard,
            style: mono.inlineCode.copyWith(color: colors.textAccent),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            item.meaning,
            style: t.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// ESD: protecting the gear, not the person. Two paragraphs.
class _EsdCard extends StatelessWidget {
  const _EsdCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'ESD: protecting the gear, not the person',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < kEsdParagraphs.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _Body(kEsdParagraphs[i]),
          ],
        ],
      ),
    );
  }
}

/// Recognize and STOP: intro + the four named hazards as warning bands + the
/// closing line. Named-and-stopped, no procedure.
class _StopCard extends StatelessWidget {
  const _StopCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Recognize and STOP',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Body(kSafetyStopIntro),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < kSafetyStopHazards.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _StopBand(kSafetyStopHazards[i]),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _Caption(kSafetyStopClosing),
        ],
      ),
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
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: colors.statusWarning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: (t.bodySmall ?? const TextStyle()).copyWith(
                color: colors.textSecondary,
              ),
            ),
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
      child: _Body(kSafetyWlanCares),
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
              kSafetyDeferNote,
              style: t.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
