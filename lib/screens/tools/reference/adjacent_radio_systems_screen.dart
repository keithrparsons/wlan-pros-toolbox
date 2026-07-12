// Beyond Wi-Fi: The Adjacent Radios - read-only field/trade reference (Field &
// Trade Reference set, 2026-07-05). Clones the Site Access reference-screen
// pattern, with Charta's spectrum-matrix plate embedded at the top via
// DarkRasterDiagramCard. Every fact the plate depicts is ALSO in the native
// text below it (GL-003 §8.6.2 a11y rule).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/
// 12-adjacent-radio-systems.md) as native layout. The real-world-envelope
// caution renders as a warning band (Icons.warning_amber_rounded, §8.13).
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = plate zoom + §8.16 copy + §8.16.1 help footer;
// disabled N/A. THEME: context.colors only. Glyph rules (GL-004): ASCII
// hyphen-minus, "Wi-Fi".

import 'package:flutter/material.dart';

import '../../../data/adjacent_radio_systems_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class AdjacentRadioSystemsScreen extends StatelessWidget {
  const AdjacentRadioSystemsScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2370 (assets/reference/adjacent-radio-systems.png).
  static const double _diagramAspect = 3360 / 2370;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adjacent Radio Systems'),
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
            ReferenceImages.isBundled(kAdjacentRadioSystemsToolId);
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
                        kAdjacentRadioSystemsToolId,
                      ),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Spectrum matrix: which adjacent radios share the '
                          '2.4 GHz air and which run coexistence-clean in '
                          'sub-GHz or licensed spectrum',
                      caption: 'Five of them contend for your 2.4 GHz airtime.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kAdjacentRadioSystemsToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kAdjacentRadioSystemsToolId),
                      title: 'Adjacent Radio Systems',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const ReferenceLead(kAdjacentLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'What shares your 2.4 GHz air',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kTwoFourIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kTwoFourContenders),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kTwoFourCoordinate),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    // WAS: "What does not touch your air" — which was flatly
                    // contradicted by three of the ten rows inside it. Zigbee,
                    // Thread and BLE each render "Shares 2.4 GHz: Yes" directly
                    // beneath that heading. The rows are right (they DO share
                    // 2.4 GHz); the heading was wrong. The per-row "Shares
                    // 2.4 GHz" field is the answer, so the heading now points at
                    // it instead of pre-empting it with a false blanket claim.
                    title: 'The other radios, and which share your air',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const ReferenceBody(kSubGhzIntro),
                        const SizedBox(height: AppSpacing.sm),
                        ReferenceTermList(
                          rows: <Widget>[
                            for (final RadioSystemRow r in kRadioSystems)
                              ReferenceTermBlock(
                                term: r.system,
                                fields: <ReferenceField>[
                                  ReferenceField('Band', r.band),
                                  ReferenceField('Range', r.range),
                                  ReferenceField('Data rate', r.dataRate),
                                  ReferenceField(
                                    'Shares 2.4 GHz',
                                    r.sharesTwoFour,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceWarnBand(kEnvelopeWarning),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Three corrections worth carrying',
                    child: ReferenceBullets(kRadioCorrections),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Which radio when',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kWhichRadioIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kWhichRadioWhen),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kAdjacentWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kAdjacentDeferNote),
                  ToolHelpFooter(toolId: kAdjacentRadioSystemsToolId),
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
      ..writeln('Beyond Wi-Fi: The Adjacent Radios')
      ..writeln()
      ..writeln(kAdjacentLead)
      ..writeln()
      ..writeln('What shares your 2.4 GHz air')
      ..writeln(kTwoFourIntro);
    for (final String s in kTwoFourContenders) {
      b.writeln('- $s');
    }
    b
      ..writeln(kTwoFourCoordinate)
      ..writeln()
      // Same heading as the card (§8.16 — the clipboard must not disagree with
      // the screen it was copied from).
      ..writeln('The other radios, and which share your air')
      ..writeln(kSubGhzIntro)
      ..writeln(
        <String>['System', 'Band', 'Range', 'Data rate', 'Shares 2.4 GHz?']
            .join(tab),
      );
    for (final RadioSystemRow r in kRadioSystems) {
      b.writeln(
        <String>[r.system, r.band, r.range, r.dataRate, r.sharesTwoFour]
            .join(tab),
      );
    }
    b
      ..writeln(kEnvelopeWarning)
      ..writeln()
      ..writeln('Three corrections worth carrying');
    for (final String s in kRadioCorrections) {
      b.writeln('- $s');
    }
    b
      ..writeln()
      ..writeln('Which radio when')
      ..writeln(kWhichRadioIntro);
    for (final String s in kWhichRadioWhen) {
      b.writeln('- $s');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kAdjacentWlanCares)
      ..writeln()
      ..writeln(kAdjacentDeferNote);
    return b.toString().trimRight();
  }
}
