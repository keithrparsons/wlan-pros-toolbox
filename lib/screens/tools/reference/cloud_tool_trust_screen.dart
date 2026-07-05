// Reading a Cloud Tool's Trust Claims - read-only field/trade reference (Field &
// Trade Reference set, 2026-07-05). Clones the Site Access / Enclosure Ratings
// reference-screen pattern, with Charta's cloud-cert-decoder plate embedded at
// the top via the established DarkRasterDiagramCard (always-dark surface in both
// themes, tap to pinch-zoom). Every fact the plate depicts is ALSO in the native
// text below it, so the image is decorative for screen readers and never the
// sole carrier of meaning (GL-003 §8.6.2 a11y rule).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/10-cloud-tool-trust.md)
// as native layout.
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

import '../../../data/cloud_tool_trust_data.dart';
import '../../../data/reference_images.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class CloudToolTrustScreen extends StatelessWidget {
  const CloudToolTrustScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 1908 (assets/reference/cloud-tool-trust.png).
  static const double _diagramAspect = 3360 / 1908;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Tool Trust'),
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
        final bool hasDiagram = ReferenceImages.isBundled(kCloudToolTrustToolId);
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
                          ReferenceImages.pathFor(kCloudToolTrustToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Cloud tool trust: certificate vs attestation, the '
                          'five Trust Services Criteria, and the six questions '
                          'to ask a trust page',
                      caption: 'Read the badge; do not just see the logo.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const ReferenceLead(kCloudTrustLead),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'ISO/IEC 27001: a certified management system, '
                        'not a product',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        ReferenceBody(kCloudIso27001Intro),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kCloudIso27001Proves),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kCloudIso27001Trap),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'SOC 2: an attestation report, and "certified" is '
                        'the wrong word',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const ReferenceBody(kCloudSoc2Intro),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kCloudSoc2TypeIntro),
                        const SizedBox(height: AppSpacing.sm),
                        const ReferenceBullets(kCloudSoc2TypeItems),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kCloudSoc2CriteriaIntro),
                        const SizedBox(height: AppSpacing.sm),
                        ReferenceTermList(
                          rows: <Widget>[
                            for (final TrustServicesCriterion c
                                in kTrustServicesCriteria)
                              ReferenceTermBlock(
                                term: c.criterion,
                                body: c.covers,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kCloudSoc2CriteriaMatter),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kCloudSoc2ReadFour),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'GDPR: a law you conform to, not a badge you earn',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        ReferenceBody(kCloudGdprIntro),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kCloudGdprResSovIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kCloudGdprResSovItems),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kCloudGdprNotSame),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kCloudGdprIfClient),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'The adjacent badges',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const ReferenceBody(kCloudBadgesIntro),
                        const SizedBox(height: AppSpacing.sm),
                        ReferenceTermList(
                          rows: <Widget>[
                            for (final AdjacentBadge b in kAdjacentBadges)
                              ReferenceTermBlock(
                                term: b.badge,
                                body: b.whatItIs,
                                fields: <ReferenceField>[
                                  ReferenceField('Buyer read', b.buyerRead),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kCloudHierarchy),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The six questions to ask a trust page',
                    child: ReferenceNumbered(kCloudSixQuestions),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kCloudWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kCloudDeferNote),
                  ToolHelpFooter(toolId: kCloudToolTrustToolId),
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
      ..writeln('Reading a Cloud Tool\'s Trust Claims')
      ..writeln()
      ..writeln(kCloudTrustLead)
      ..writeln()
      ..writeln('ISO/IEC 27001: a certified management system, not a product')
      ..writeln(kCloudIso27001Intro)
      ..writeln(kCloudIso27001Proves)
      ..writeln(kCloudIso27001Trap)
      ..writeln()
      ..writeln('SOC 2: an attestation report, and "certified" is the wrong '
          'word')
      ..writeln(kCloudSoc2Intro)
      ..writeln(kCloudSoc2TypeIntro);
    for (final String s in kCloudSoc2TypeItems) {
      b.writeln('- $s');
    }
    b
      ..writeln(kCloudSoc2CriteriaIntro)
      ..writeln(<String>['Criterion', 'What it covers'].join(tab));
    for (final TrustServicesCriterion c in kTrustServicesCriteria) {
      b.writeln(<String>[c.criterion, c.covers].join(tab));
    }
    b
      ..writeln(kCloudSoc2CriteriaMatter)
      ..writeln(kCloudSoc2ReadFour)
      ..writeln()
      ..writeln('GDPR: a law you conform to, not a badge you earn')
      ..writeln(kCloudGdprIntro)
      ..writeln(kCloudGdprResSovIntro);
    for (final String s in kCloudGdprResSovItems) {
      b.writeln('- $s');
    }
    b
      ..writeln(kCloudGdprNotSame)
      ..writeln(kCloudGdprIfClient)
      ..writeln()
      ..writeln('The adjacent badges')
      ..writeln(kCloudBadgesIntro)
      ..writeln(<String>['Badge', 'What it is', 'Buyer read'].join(tab));
    for (final AdjacentBadge badge in kAdjacentBadges) {
      b.writeln(
        <String>[badge.badge, badge.whatItIs, badge.buyerRead].join(tab),
      );
    }
    b
      ..writeln(kCloudHierarchy)
      ..writeln()
      ..writeln('The six questions to ask a trust page');
    for (int i = 0; i < kCloudSixQuestions.length; i++) {
      b.writeln('${i + 1}. ${kCloudSixQuestions[i]}');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kCloudWlanCares)
      ..writeln()
      ..writeln(kCloudDeferNote);
    return b.toString().trimRight();
  }
}
