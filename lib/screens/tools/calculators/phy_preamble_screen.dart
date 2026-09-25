// PHY Preamble Reference: Wi-Fi Lab tool (phy-preamble).
//
// Every Wi-Fi PPDU since 802.11a starts with the same 20 µs legacy preamble,
// so older radios can hear it and defer. This tool draws the preamble of each
// PHY to scale (Legacy, HT mixed, VHT, HE SU, HE ER SU, HE MU, HE TB, EHT MU,
// EHT TB), with BPSK or QBPSK under every SIG symbol; opens the bit table of
// any SIG field with an evidence tag on every field; walks the receiver's
// decision from the first symbols after L-SIG ("Which PHY?"); and computes
// the spoofed L-SIG LENGTH that makes a legacy radio defer for the whole PPDU.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/13-phy-preamble.md, from Pax's wave-5 brief (Deliverables/
// 2026-09-25-wifi-lab-wave5-research/brief.md, sections 1 to 8), in
// lib/services/wifi_lab/phy_preamble.dart. Durations agree with Airtime
// Anatomy (lib/services/wifi_lab/airtime_anatomy.dart) wherever both apply.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one PhyPreambleModel.
//   - PhyPreambleStage    (phy_preamble_stage.dart): the bar, legend, block
//                         list, and the bit table or the decision walk.
//   - PhyPreambleControls (phy_preamble_controls.dart): mode, settings,
//                         readouts and the LENGTH calculator, in parts.
// This screen only composes them.
//
// THEME: chrome from context.colors (dark §8 / light §8.20). Blocks take a
// sand (legacy) or blue (added) hue from phy_preamble_palette.dart under
// GL-003 §8.15.2, always labeled, with a legend; lime marks the Data field;
// the §8.13 warning hue marks evidence tags that are not settled, with words.
// Nothing animates, so reduced motion (§8.8) has nothing to remove.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/phy_preamble.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'phy_preamble_controls.dart';
import 'phy_preamble_model.dart';
import 'phy_preamble_parts.dart';
import 'phy_preamble_stage.dart';

export 'phy_preamble_model.dart' show kPhyPreambleToolId;

class PhyPreambleScreen extends StatefulWidget {
  const PhyPreambleScreen({
    super.key,
    this.initial = const PreambleSettings(),
    this.initialMode = PreambleMode.explore,
    this.initialSelection,
  });

  /// Test seams: start from given settings, mode and open block.
  final PreambleSettings initial;
  final PreambleMode initialMode;
  final String? initialSelection;

  @override
  State<PhyPreambleScreen> createState() => _PhyPreambleScreenState();
}

class _PhyPreambleScreenState extends State<PhyPreambleScreen> {
  late final PhyPreambleModel _model = PhyPreambleModel(
    initial: widget.initial,
    mode: widget.initialMode,
    selectedBlock: widget.initialSelection,
  );

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PHY Preamble Reference'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _model.copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
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
                      PhyPreambleStage(model: _model),
                      const SizedBox(height: AppSpacing.sm),
                      PhyPreambleControls(model: _model),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kPhyPreambleToolId),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return PpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PpSectionLabel('Where this comes from, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The IEEE 802.11 standard itself was not read for this reference. '
            'Bit positions come from open-source driver and receiver code and '
            'from secondary sources, and every field carries the research '
            'brief\'s own tag. Treat a field marked one source, inferred or '
            'not verified as a lead, not a fact.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Durations are per field and do not change with channel width. '
            'LTF counts follow the Airtime Anatomy table (1, 2, 4, 4, 6, 6, '
            '8, 8); the brief confirms 1 to 4 for HT from one source. The '
            'packet extension and the 2.4 GHz signal extension come after '
            'the data and are not drawn.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Airtime Anatomy draws the same preambles inside a whole '
            'transmit opportunity.',
            style: body,
          ),
        ],
      ),
    );
  }
}
