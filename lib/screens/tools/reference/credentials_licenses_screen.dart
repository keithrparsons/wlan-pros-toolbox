// Credentials, Licenses, and Federal IDs - read-only field/trade reference
// (Field & Trade Reference set, 2026-07-05). Companion to Site Access. Clones
// the Site Access reference-screen pattern, with Charta's credential-lead-time
// plate embedded at the top via DarkRasterDiagramCard. Every fact the plate
// depicts is ALSO in the native text below it (GL-003 §8.6.2 a11y rule).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/13-credentials-licenses.md)
// as native layout.
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = plate zoom + §8.16 copy + §8.16.1 help footer;
// disabled N/A. THEME: context.colors only. Glyph rules (GL-004): ASCII
// hyphen-minus, "Wi-Fi".

import 'package:flutter/material.dart';

import '../../../data/credentials_licenses_data.dart';
import '../../../data/reference_images.dart';
import '../../../data/reference_pdfs.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/reference_pdf_download.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class CredentialsLicensesScreen extends StatelessWidget {
  const CredentialsLicensesScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2490 (assets/reference/credentials-licenses.png).
  static const double _diagramAspect = 3360 / 2490;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credentials & Licenses'),
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
            ReferenceImages.isBundled(kCredentialsLicensesToolId);
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
                        kCredentialsLicensesToolId,
                      ),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Credential lead-time chart: TWIC, CAC, DBIDS, SIDA, '
                          'HAZWOPER, and background checks, and how long each '
                          'takes to obtain',
                      caption: 'The credential you do not hold is the schedule '
                          'you cannot keep.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (ReferencePdfs.isBundled(kCredentialsLicensesToolId)) ...<Widget>[
                    ReferencePdfDownloadCard(
                      assetPath: ReferencePdfs.pathFor(kCredentialsLicensesToolId),
                      title: 'Credentials & Licenses',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const ReferenceLead(kCredentialsLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'You probably do not need an FCC operator license',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kFccConceptsIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kFccConcepts),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kGrolFactsIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kGrolFacts),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kGrolException),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'The credentials that gate the site',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const ReferenceBody(kCredentialsTableIntro),
                        const SizedBox(height: AppSpacing.sm),
                        ReferenceTermList(
                          rows: <Widget>[
                            for (final CredentialRow c in kCredentials)
                              ReferenceTermBlock(
                                term: c.credential,
                                fields: <ReferenceField>[
                                  ReferenceField(
                                    'Issuing authority',
                                    c.authority,
                                  ),
                                  ReferenceField(
                                    'Where it gates you',
                                    c.gatesYou,
                                  ),
                                  ReferenceField(
                                    'Typical lead time',
                                    c.leadTime,
                                  ),
                                  ReferenceField('Validity', c.validity),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (int i = 0; i < kCredentialNotes.length; i++) ...<
                            Widget>[
                          if (i > 0) const SizedBox(height: AppSpacing.md),
                          ReferenceBody(kCredentialNotes[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The lead times cluster three ways',
                    child: ReferenceBullets(kLeadTimeClusters),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kCredentialsWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kCredentialsDeferNote),
                  ToolHelpFooter(toolId: kCredentialsLicensesToolId),
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
      ..writeln('Credentials, Licenses, and Federal IDs')
      ..writeln()
      ..writeln(kCredentialsLead)
      ..writeln()
      ..writeln('You probably do not need an FCC operator license')
      ..writeln(kFccConceptsIntro);
    for (final String s in kFccConcepts) {
      b.writeln('- $s');
    }
    b.writeln(kGrolFactsIntro);
    for (final String s in kGrolFacts) {
      b.writeln('- $s');
    }
    b
      ..writeln(kGrolException)
      ..writeln()
      ..writeln('The credentials that gate the site')
      ..writeln(kCredentialsTableIntro)
      ..writeln(
        <String>[
          'Credential',
          'Issuing authority',
          'Where it gates you',
          'Typical lead time',
          'Validity',
        ].join(tab),
      );
    for (final CredentialRow c in kCredentials) {
      b.writeln(
        <String>[c.credential, c.authority, c.gatesYou, c.leadTime, c.validity]
            .join(tab),
      );
    }
    for (final String s in kCredentialNotes) {
      b.writeln(s);
    }
    b
      ..writeln()
      ..writeln('The lead times cluster three ways');
    for (final String s in kLeadTimeClusters) {
      b.writeln('- $s');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kCredentialsWlanCares)
      ..writeln()
      ..writeln(kCredentialsDeferNote);
    return b.toString().trimRight();
  }
}
