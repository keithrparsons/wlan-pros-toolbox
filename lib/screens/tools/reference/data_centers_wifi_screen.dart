// Data Centers and Wi-Fi - read-only field/trade reference (Field & Trade
// Reference set, 2026-07-05). Text-reference only (no decoder plate), exactly
// like CAD & BIM Formats. Clones the CAD & BIM Formats text-reference pattern.
//
// Renders Penn's voice-gated copy VERBATIM (SOP-020 PASS; source in
// Deliverables/2026-07-05-field-trade-reference/content/16-data-centers-wifi.md)
// as native layout. The "do not conflate Rated with Tier" caution renders as a
// warning band (Icons.warning_amber_rounded, §8.13).
//
// States (SOP-007 §5): pure read-only reference - no inputs, no computation, no
// network (GL-008 N/A). Success always renders; loading/empty/error
// unreachable; interactive = §8.16 copy + §8.16.1 help footer; disabled N/A.
// THEME: context.colors only. Glyph rules (GL-004): ASCII hyphen-minus,
// "Wi-Fi".

import 'package:flutter/material.dart';

import '../../../data/data_centers_wifi_data.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'reference_prose.dart';

class DataCentersWifiScreen extends StatelessWidget {
  const DataCentersWifiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Centers & Wi-Fi'),
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
                  const ReferenceLead(kDataCenterLead),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Production Wi-Fi is usually minimal',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kDataCenterMinimalIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kDataCenterWifiRoles),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kDataCenterClarify),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why the room fights your RF',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kDataCenterRfIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kDataCenterRfFights),
                        SizedBox(height: AppSpacing.md),
                        ReferenceBody(kDataCenterCoverage),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ReferenceCard(
                    title: 'Two frameworks people mix up',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const ReferenceBody(kDataCenterFrameworksIntro),
                        const SizedBox(height: AppSpacing.sm),
                        ReferenceTermList(
                          rows: <Widget>[
                            for (final ResilienceFramework f
                                in kResilienceFrameworks)
                              ReferenceTermBlock(
                                term: f.framework,
                                fields: <ReferenceField>[
                                  ReferenceField('Owner', f.owner),
                                  ReferenceField('Levels', f.levels),
                                  ReferenceField('What it rates', f.rates),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceWarnBand(kDataCenterConflateWarning),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kUptimeLadderIntro),
                        const SizedBox(height: AppSpacing.sm),
                        const ReferenceBullets(kUptimeTiers),
                        const SizedBox(height: AppSpacing.md),
                        const ReferenceBody(kDataCenterTierDefer),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'The access regime is the real gate',
                    child: ReferenceBody(kDataCenterAccess),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'What to do when asked for Wi-Fi in or around a '
                        'data center',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ReferenceBody(kDataCenterWhatToDoIntro),
                        SizedBox(height: AppSpacing.sm),
                        ReferenceBullets(kDataCenterWhatToDo),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceCard(
                    title: 'Why a WLAN pro cares',
                    child: ReferenceBody(kDataCenterWlanCares),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const ReferenceInfoBand(kDataCenterDeferNote),
                  ToolHelpFooter(toolId: kDataCentersWifiToolId),
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
      ..writeln('Data Centers and Wi-Fi')
      ..writeln()
      ..writeln(kDataCenterLead)
      ..writeln()
      ..writeln('Production Wi-Fi is usually minimal')
      ..writeln(kDataCenterMinimalIntro);
    for (final String s in kDataCenterWifiRoles) {
      b.writeln('- $s');
    }
    b
      ..writeln(kDataCenterClarify)
      ..writeln()
      ..writeln('Why the room fights your RF')
      ..writeln(kDataCenterRfIntro);
    for (final String s in kDataCenterRfFights) {
      b.writeln('- $s');
    }
    b
      ..writeln(kDataCenterCoverage)
      ..writeln()
      ..writeln('Two frameworks people mix up')
      ..writeln(kDataCenterFrameworksIntro)
      ..writeln(
        <String>['Framework', 'Owner', 'Levels', 'What it rates'].join(tab),
      );
    for (final ResilienceFramework f in kResilienceFrameworks) {
      b.writeln(<String>[f.framework, f.owner, f.levels, f.rates].join(tab));
    }
    b
      ..writeln(kDataCenterConflateWarning)
      ..writeln(kUptimeLadderIntro);
    for (final String s in kUptimeTiers) {
      b.writeln('- $s');
    }
    b
      ..writeln(kDataCenterTierDefer)
      ..writeln()
      ..writeln('The access regime is the real gate')
      ..writeln(kDataCenterAccess)
      ..writeln()
      ..writeln('What to do when asked for Wi-Fi in or around a data center')
      ..writeln(kDataCenterWhatToDoIntro);
    for (final String s in kDataCenterWhatToDo) {
      b.writeln('- $s');
    }
    b
      ..writeln()
      ..writeln('Why a WLAN pro cares')
      ..writeln(kDataCenterWlanCares)
      ..writeln()
      ..writeln(kDataCenterDeferNote);
    return b.toString().trimRight();
  }
}
