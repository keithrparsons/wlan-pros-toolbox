// Frameworks That Put Your Wi-Fi in Scope - read-only field/trade reference
// (Field & Trade Reference set, 2026-07-05). Clones the Site Access
// reference-screen pattern, with Charta's compliance-scope-matrix plate
// embedded at the top via DarkRasterDiagramCard (always-dark surface in both
// themes, tap to pinch-zoom). Every fact the plate depicts is ALSO in the
// native text below it (GL-003 §8.6.2 a11y rule).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/
// 11-network-in-scope-compliance.md) as native layout.
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = plate zoom + §8.16 copy + §8.16.1 help footer;
// disabled N/A. THEME: context.colors only. Defer footer is an info band
// (§8.13). Glyph rules (GL-004): ASCII hyphen-minus, "Wi-Fi", "802.1X".

import 'package:flutter/material.dart';

import '../../../data/network_in_scope_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class NetworkInScopeScreen extends StatelessWidget {
  const NetworkInScopeScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2292 (assets/reference/network-in-scope.png).
  static const double _diagramAspect = 3360 / 2292;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network in Scope'),
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
        final bool hasDiagram = ReferenceImages.isBundled(kNetworkInScopeToolId);
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
                          ReferenceImages.pathFor(kNetworkInScopeToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Compliance scope matrix: PCI DSS, HIPAA, SOX, and '
                          'GDPR, the trigger for each, and what it asks of the '
                          'network',
                      caption: 'Recognize the framework; never certify it '
                          'yourself.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kNetworkInScopeToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kNetworkInScopeToolId),
                      title: 'Network in Scope',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const ReferenceLead(kNetScopeLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'PCI DSS: cardholder data over Wi-Fi',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kPciIntro),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kPciAsksIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kPciAsks),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kPciRouteTo),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'HIPAA: health information over Wi-Fi',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kHipaaIntro),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kHipaaSafeguardsIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kHipaaSafeguards),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kHipaaNuance),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kHipaaRouteTo),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'SOX and SEC: public-company controls',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kSoxIntro),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kSoxTouchesIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kSoxTouches),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kSoxNarrowest),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'GDPR on the network side',
                    child: ReferenceBody(kGdprNetworkSide),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kNetScopeWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kNetScopeDeferNote),
                  ToolHelpFooter(toolId: kNetworkInScopeToolId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// §8.16 plain-text payload - the full reference.
  static String _copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('Frameworks That Put Your Wi-Fi in Scope')
      ..writeln()
      ..writeln(kNetScopeLead)
      ..writeln()
      ..writeln('PCI DSS: cardholder data over Wi-Fi')
      ..writeln(kPciIntro)
      ..writeln(kPciAsksIntro);
    for (final String s in kPciAsks) {
      b.writeln('- $s');
    }
    b
      ..writeln(kPciRouteTo)
      ..writeln()
      ..writeln('HIPAA: health information over Wi-Fi')
      ..writeln(kHipaaIntro)
      ..writeln(kHipaaSafeguardsIntro);
    for (final String s in kHipaaSafeguards) {
      b.writeln('- $s');
    }
    b
      ..writeln(kHipaaNuance)
      ..writeln(kHipaaRouteTo)
      ..writeln()
      ..writeln('SOX and SEC: public-company controls')
      ..writeln(kSoxIntro)
      ..writeln(kSoxTouchesIntro);
    for (final String s in kSoxTouches) {
      b.writeln('- $s');
    }
    b
      ..writeln(kSoxNarrowest)
      ..writeln()
      ..writeln('GDPR on the network side')
      ..writeln(kGdprNetworkSide)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kNetScopeWlanCares)
      ..writeln()
      ..writeln(kNetScopeDeferNote);
    return b.toString().trimRight();
  }
}
