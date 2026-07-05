// Verticals: What You're Walking Into - read-only field/trade reference (Field &
// Trade Reference set, 2026-07-05). Text-reference only (no decoder plate),
// exactly like CAD & BIM Formats: this entry is the index that points at the
// other reference entries. Clones the CAD & BIM Formats text-reference pattern.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/14-by-vertical-index.md)
// as native layout.
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = §8.16 copy + §8.16.1 help footer; disabled N/A.
// THEME: context.colors only. Glyph rules (GL-004): ASCII hyphen-minus,
// "Wi-Fi", "802.1X".

import 'package:flutter/material.dart';

import '../../../data/by_vertical_index_data.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class ByVerticalIndexScreen extends StatelessWidget {
  const ByVerticalIndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verticals Index'),
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
                  const ReferenceLead(kVerticalLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(child: ReferenceBody(kVerticalCodesNote)),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'The map',
                    child: ReferenceTermList(
                      rows: <Widget>[
                        for (final VerticalRow v in kVerticals)
                          ReferenceTermBlock(
                            term: v.vertical,
                            fields: <ReferenceField>[
                              ReferenceField('Tends to trigger', v.triggers),
                              ReferenceField('Read first', v.readFirst),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(child: ReferenceBody(kVerticalTwoNotes)),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Retail and PCI DSS',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kRetailPciIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kRetailPciFacts),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kRetailPciDefer),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Very-high-density venues',
                    child: ReferenceBody(kHighDensityNote),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kVerticalWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kVerticalDeferNote),
                  ToolHelpFooter(toolId: kByVerticalIndexToolId),
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
      ..writeln('Verticals: What You\'re Walking Into')
      ..writeln()
      ..writeln(kVerticalLead)
      ..writeln()
      ..writeln(kVerticalCodesNote)
      ..writeln()
      ..writeln('The map')
      ..writeln(
        <String>['Vertical', 'What it tends to trigger', 'Read first']
            .join(tab),
      );
    for (final VerticalRow v in kVerticals) {
      b.writeln(<String>[v.vertical, v.triggers, v.readFirst].join(tab));
    }
    b
      ..writeln()
      ..writeln(kVerticalTwoNotes)
      ..writeln()
      ..writeln('Retail and PCI DSS')
      ..writeln(kRetailPciIntro);
    for (final String s in kRetailPciFacts) {
      b.writeln('- $s');
    }
    b
      ..writeln(kRetailPciDefer)
      ..writeln()
      ..writeln('Very-high-density venues')
      ..writeln(kHighDensityNote)
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kVerticalWlanCares)
      ..writeln()
      ..writeln(kVerticalDeferNote);
    return b.toString().trimRight();
  }
}
