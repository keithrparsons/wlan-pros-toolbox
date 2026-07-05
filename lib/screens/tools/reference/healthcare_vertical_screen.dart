// Healthcare Wi-Fi - read-only field/trade reference (Field & Trade Reference
// set, 2026-07-05). Clones the Site Access reference-screen pattern, with
// Charta's healthcare-demands plate embedded at the top via
// DarkRasterDiagramCard. Every fact the plate depicts is ALSO in the native
// text below it (GL-003 §8.6.2 a11y rule).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/15-healthcare-vertical.md)
// as native layout. The shielded-rooms caution renders as a warning band
// (Icons.warning_amber_rounded, §8.13).
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = plate zoom + §8.16 copy + §8.16.1 help footer;
// disabled N/A. THEME: context.colors only. Glyph rules (GL-004): ASCII
// hyphen-minus, "Wi-Fi".

import 'package:flutter/material.dart';

import '../../../data/healthcare_vertical_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class HealthcareVerticalScreen extends StatelessWidget {
  const HealthcareVerticalScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2614 (assets/reference/healthcare-vertical.png).
  static const double _diagramAspect = 3360 / 2614;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Healthcare Wi-Fi'),
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
            ReferenceImages.isBundled(kHealthcareVerticalToolId);
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
                      assetPath: ReferenceImages.pathFor(
                        kHealthcareVerticalToolId,
                      ),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Healthcare Wi-Fi demands: the WMTS telemetry band, '
                          'medical-device EMC, roaming and RTLS grades, and the '
                          'four authorities',
                      caption: 'Coordinate with biomed before you touch the '
                          'RF environment.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kHealthcareVerticalToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kHealthcareVerticalToolId),
                      title: 'Healthcare Wi-Fi',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const ReferenceLead(kHealthcareLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    child: ReferenceBody(kHealthcareThroughLine),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why it is not an office',
                    child: ReferenceBody(kHealthcareNotOffice),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The protected telemetry band most Wi-Fi pros have '
                        'never heard of',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kWmtsIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kWmtsBands),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kWmtsHistory),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kWmtsTakeaway),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The shared 2.4 and 5 GHz air',
                    child: ReferenceBody(kHealthcareSharedAir),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Medical-device EMC and IEC 60601-1-2',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kEmcStandard),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kEmcDesignerRead),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'Roaming, RTLS, nurse call, and alarms',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        ReferenceBody(kRoamingHard),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kCoverageGrade),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kRtlsIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kRtlsLandscape),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kRtlsGradeDriver),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kHealthcareSegmentation),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceWarnBand(kHealthcareBuildingWarning),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'The four authorities, and the one handoff that '
                        'matters most',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const ReferenceBody(kHealthcareAuthoritiesIntro),
                        const SizedBox(height: AppSpacing.sm),
                        ReferenceTermList(
                          rows: <Widget>[
                            for (final HealthcareAuthority a
                                in kHealthcareAuthorities)
                              ReferenceTermBlock(
                                term: a.authority,
                                fields: <ReferenceField>[
                                  ReferenceField('What it governs', a.governs),
                                  ReferenceField('Your move', a.yourMove),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Before you quote a hospital',
                    child: ReferenceNumbered(kHealthcarePreQuote),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kHealthcareWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kHealthcareDeferNote),
                  ToolHelpFooter(toolId: kHealthcareVerticalToolId),
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
    const String tab = '\t';
    final StringBuffer b = StringBuffer()
      ..writeln('Healthcare Wi-Fi')
      ..writeln()
      ..writeln(kHealthcareLead)
      ..writeln()
      ..writeln(kHealthcareThroughLine)
      ..writeln()
      ..writeln('Why it is not an office')
      ..writeln(kHealthcareNotOffice)
      ..writeln()
      ..writeln('The protected telemetry band most Wi-Fi pros have never '
          'heard of')
      ..writeln(kWmtsIntro);
    for (final String s in kWmtsBands) {
      b.writeln('- $s');
    }
    b
      ..writeln(kWmtsHistory)
      ..writeln(kWmtsTakeaway)
      ..writeln()
      ..writeln('The shared 2.4 and 5 GHz air')
      ..writeln(kHealthcareSharedAir)
      ..writeln()
      ..writeln('Medical-device EMC and IEC 60601-1-2')
      ..writeln(kEmcStandard)
      ..writeln(kEmcDesignerRead)
      ..writeln()
      ..writeln('Roaming, RTLS, nurse call, and alarms')
      ..writeln(kRoamingHard)
      ..writeln(kCoverageGrade)
      ..writeln(kRtlsIntro);
    for (final String s in kRtlsLandscape) {
      b.writeln('- $s');
    }
    b
      ..writeln(kRtlsGradeDriver)
      ..writeln(kHealthcareSegmentation)
      ..writeln(kHealthcareBuildingWarning)
      ..writeln()
      ..writeln('The four authorities, and the one handoff that matters most')
      ..writeln(kHealthcareAuthoritiesIntro)
      ..writeln(
        <String>['Authority', 'What it governs for you', 'Your move'].join(tab),
      );
    for (final HealthcareAuthority a in kHealthcareAuthorities) {
      b.writeln(<String>[a.authority, a.governs, a.yourMove].join(tab));
    }
    b
      ..writeln()
      ..writeln('Before you quote a hospital');
    for (int i = 0; i < kHealthcarePreQuote.length; i++) {
      b.writeln('${i + 1}. ${kHealthcarePreQuote[i]}');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kHealthcareWlanCares)
      ..writeln()
      ..writeln(kHealthcareDeferNote);
    return b.toString().trimRight();
  }
}
