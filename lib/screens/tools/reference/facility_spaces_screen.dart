// Telecom Spaces: MDF, IDF, TR, and the Data Closet - read-only field/trade
// reference (Field & Trade Reference set, 2026-07-05). Clones the Site Access
// reference-screen pattern, with Charta's facility-spaces-topology plate
// embedded at the top via DarkRasterDiagramCard. Every fact the plate depicts
// is ALSO in the native text below it (GL-003 §8.6.2 a11y rule).
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/17-facility-spaces.md)
// as native layout.
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = plate zoom + §8.16 copy + §8.16.1 help footer;
// disabled N/A. THEME: context.colors only. Glyph rules (GL-004): ASCII
// hyphen-minus, "Wi-Fi".

import 'package:flutter/material.dart';

import '../../../data/facility_spaces_data.dart';
import '../../../data/reference_images.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/dark_raster_diagram_card.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class FacilitySpacesScreen extends StatelessWidget {
  const FacilitySpacesScreen({super.key});

  /// The plate's true aspect ratio (width / height). Master render is 3360 x
  /// 2298 (assets/reference/facility-spaces.png).
  static const double _diagramAspect = 3360 / 2298;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telecom Spaces'),
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
            ReferenceImages.isBundled(kFacilitySpacesToolId);
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
                          ReferenceImages.pathFor(kFacilitySpacesToolId),
                      aspectRatio: _diagramAspect,
                      semanticLabel:
                          'Telecom spaces topology: the Entrance Facility, MDF '
                          'or Equipment Room, and the IDF or Telecommunications '
                          'Room hierarchy in a star',
                      caption: 'MDF, IDF, TR, and "data closet" are often one '
                          'room.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const ReferenceLead(kFacilityLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(child: ReferenceBody(kFacilityStandard)),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Same room, several names',
                    child: ReferenceBody(kFacilitySameRoom),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'The terms, decoded',
                    child: ReferenceTermList(
                      rows: <Widget>[
                        for (final TelecomSpaceRow s in kTelecomSpaces)
                          ReferenceTermBlock(
                            term: s.term,
                            body: s.whatItIs,
                            fields: <ReferenceField>[
                              ReferenceField(
                                'Standard or field',
                                s.standardOrField,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The topology',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kFacilityTopology),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kFacilityShape),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The international parallel',
                    child: ReferenceBody(kFacilityInternational),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kFacilityWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kFacilityDeferNote),
                  ToolHelpFooter(toolId: kFacilitySpacesToolId),
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
      ..writeln('Telecom Spaces: MDF, IDF, TR, and the Data Closet')
      ..writeln()
      ..writeln(kFacilityLead)
      ..writeln()
      ..writeln(kFacilityStandard)
      ..writeln()
      ..writeln('Same room, several names')
      ..writeln(kFacilitySameRoom)
      ..writeln()
      ..writeln('The terms, decoded')
      ..writeln(
        <String>['Term', 'What it is', 'Standard or field'].join(tab),
      );
    for (final TelecomSpaceRow s in kTelecomSpaces) {
      b.writeln(
        <String>[s.term, s.whatItIs, s.standardOrField].join(tab),
      );
    }
    b
      ..writeln()
      ..writeln('The topology')
      ..writeln(kFacilityTopology)
      ..writeln(kFacilityShape)
      ..writeln()
      ..writeln('The international parallel')
      ..writeln(kFacilityInternational)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kFacilityWlanCares)
      ..writeln()
      ..writeln(kFacilityDeferNote);
    return b.toString().trimRight();
  }
}
