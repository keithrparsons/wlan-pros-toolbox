// Diffie-Hellman (by colors) — read-only crypto-fundamentals reference (Tier-1,
// Pass 2b 2026-06-12).
//
// Mostly visual: the staged paint-mixing diagram (the analogy taught alongside
// the labeled math) is the content, so it is embedded at the top via the
// established DarkRasterDiagramCard (always-dark in both themes, tap to
// pinch-zoom; the plate is dark-baked, GL-003 §8). Beneath it a short NATIVE
// explainer carries the paint analogy paired with the real modular-
// exponentiation math, and ties the whole thing to WPA3 SAE. Every fact the
// diagram shows is ALSO in the native text, so the image is decorative for
// screen readers, never the sole carrier of meaning.
//
// States (SOP-007 §5):
//  - success    → the explainer always renders (compile-time const data); the
//    diagram card appears only when its PNG is bundled
//    (ReferenceImages.isBundled), otherwise it is omitted and the explainer
//    still reads end-to-end.
//  - loading / empty / error → not reachable; nothing fetched or parsed.
//  - interactive→ the diagram's tap-to-zoom + the AppBar §8.16 copy action.
//  - disabled   → copy is always enabled (const content always present).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The danger callout
// uses the status-danger token paired with the word (§8.13). No new tokens.
// Glyph note: math tokens in ASCII (g^a mod p); no em dash; "Wi-Fi" casing.

import 'package:flutter/material.dart';

import '../../../data/diffie_hellman_data.dart';
import '../../../data/reference_images.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';

/// Stable catalog tool id — backs the route, the help entry, the bundled diagram
/// PNG (assets/reference/diffie-hellman.png), and the tests.
const String kDiffieHellmanToolId = 'diffie-hellman';

class DiffieHellmanScreen extends StatelessWidget {
  const DiffieHellmanScreen({super.key});

  /// The diagram's true aspect ratio (width / height), pinned so the inline card
  /// is the right shape with no measuring and no letterbox gutters.
  static const double _diagramAspect = 2560 / 1440;

  /// §8.16 plain-text payload — the summary, every stage (analogy + math), the
  /// eavesdropper verdict, and the WPA3 tie-in. Always non-null (static data).
  static String _copyText() {
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Diffie-Hellman key exchange (by colors)')
      ..writeln()
      ..writeln(kDhSummary)
      ..writeln()
      ..writeln(<String>['Stage', 'Paint analogy', 'Math'].join(tab));
    for (final DhStage s in kDhStages) {
      b.writeln(<String>[s.stage, s.analogy, s.math].join(tab));
    }
    b
      ..writeln()
      ..writeln('Eavesdropper: $kDhEavesdropperVerdict')
      ..writeln()
      ..writeln('Why it matters for Wi-Fi: $kDhWlanRelevance');
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diffie-Hellman'),
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
        final bool hasDiagram = ReferenceImages.isBundled(kDiffieHellmanToolId);
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
                      assetPath: ReferenceImages.pathFor(kDiffieHellmanToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Diffie-Hellman paint-mixing key-exchange diagram',
                      caption:
                          'The paint-mixing analogy with the real math labeled.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _SummaryCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _StagesCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _EavesdropperCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _WlanCard(),
                  ToolHelpFooter(toolId: kDiffieHellmanToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The plain-language summary.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard();

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
        kDhSummary,
        style: (text.bodyMedium ?? const TextStyle()).copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// The stage-by-stage explainer: analogy on top, math beneath in DM Mono.
class _StagesCard extends StatelessWidget {
  const _StagesCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
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
            'The exchange, step by step',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < kDhStages.length; i++) ...<Widget>[
            if (i > 0) Divider(color: colors.border, height: AppSpacing.md),
            _StageRow(stage: kDhStages[i], mono: mono),
          ],
        ],
      ),
    );
  }
}

/// One stage: bold stage label, analogy line, then the math token.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.mono});

  final DhStage stage;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${stage.stage}. ${stage.analogy}. ${stage.math}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            stage.stage,
            style: (text.bodyMedium ?? const TextStyle()).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stage.analogy,
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            stage.math,
            style: mono.inlineCode.copyWith(color: colors.textAccent),
          ),
        ],
      ),
    );
  }
}

/// The eavesdropper verdict as a danger callout (glyph + word, §8.13).
class _EavesdropperCard extends StatelessWidget {
  const _EavesdropperCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.statusDangerFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.statusDanger, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            Icons.visibility_off_outlined,
            size: 20,
            color: colors.statusDanger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'The eavesdropper cannot un-mix',
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  kDhEavesdropperVerdict,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The WPA3 SAE tie-in.
class _WlanCard extends StatelessWidget {
  const _WlanCard();

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
          Text(
            'Why it matters for Wi-Fi',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            kDhWlanRelevance,
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
