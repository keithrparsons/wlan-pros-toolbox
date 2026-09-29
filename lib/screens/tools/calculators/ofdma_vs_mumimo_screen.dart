// OFDMA vs MU-MIMO (Wi-Fi Classroom, 2026-09-29) - ofdma-vs-mumimo.
//
// Two ways an 802.11ax AP sends to several clients at once: OFDMA splits the
// channel into resource units, MU-MIMO sends every client the whole channel
// on its own spatial stream, aimed with zero-forcing, after sounding. The
// student moves clients around the AP and sees which scheme needs less
// airtime, and why, on one microsecond scale.
//
// The model is lib/services/wifi_lab/mu_mimo_model.dart; its OFDMA side is
// computeOfdma from OFDMA Resource Units, unchanged. Spec: myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/47-ofdma-vs-mumimo.md.
// Scenarios: Keith's four (2026-09-29).
//
// STRUCTURE. One OfdmaVsMumimoController, a stage (the room, the verdict and
// the timelines) and the controls (readouts and inputs). Phone and desktop
// widths stack them; the Present button opens the same two over the SAME
// controller in the presenter layout.
//
// THEME: context.colors plus the Wi-Fi Classroom client palette (GL-003
// §8.15.2), always with the client letter. Status hues only on verdicts
// (§8.13). Nothing animates, so reduced motion (§8.8) has nothing to remove.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/mu_mimo_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../units/unit_system.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import '../../../widgets/unit_system_switch.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'ofdma_simulator_stage.dart' show AssumptionTag;
import 'ofdma_vs_mumimo_controller.dart';
import 'ofdma_vs_mumimo_controls.dart';
import 'ofdma_vs_mumimo_stage.dart';

export 'ofdma_vs_mumimo_controller.dart' show kOfdmaVsMumimoToolId;

const String _kTitle = 'OFDMA vs MU-MIMO';

class OfdmaVsMumimoScreen extends StatefulWidget {
  const OfdmaVsMumimoScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final OfdmaVsMumimoController? controller;

  @override
  State<OfdmaVsMumimoScreen> createState() => _OfdmaVsMumimoScreenState();
}

class _OfdmaVsMumimoScreenState extends State<OfdmaVsMumimoScreen>
    with UnitSystemFollower<OfdmaVsMumimoScreen> {
  late final OfdmaVsMumimoController _c =
      widget.controller ?? OfdmaVsMumimoController();

  @override
  void applyUnitSystem(UnitSystem system) => _c.setUnits(system);

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    showUnitSwitch: true,
    stage: OfdmaVsMumimoStage(controller: _c),
    controls: OfdmaVsMumimoControls(controller: _c),
    actions: _c.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          const UnitSystemSwitch(),
          PresentButton(
            toolRoute: AppRouter.ofdmaVsMumimo,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _c.copyText),
        ],
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
                  maxWidth: AppSpacing.contentMaxWidth,
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
                      OfdmaVsMumimoStage(controller: _c),
                      const SizedBox(height: AppSpacing.md),
                      OfdmaVsMumimoControls(controller: _c),
                      const SizedBox(height: AppSpacing.md),
                      const _AssumptionsCard(),
                      const ToolHelpFooter(toolId: kOfdmaVsMumimoToolId),
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

class _AssumptionsCard extends StatelessWidget {
  const _AssumptionsCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Assumptions'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'A teaching model. These choices shape every number above.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          for (final MuAssumption a in MuAssumption.values) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            AssumptionTag(title: a.title),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              a.detail,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sources: IEEE Std 802.11-2024 (26.7.3 HE sounding; 9.3.1.19 and '
            '9.3.1.22.3 NDPA and BFRP Trigger; Table 9-45 and 9.4.1.64 MU '
            'feedback; 27.1.1 and 27.3.11.10 HE MU-MIMO); Tse and Viswanath, '
            'Fundamentals of Wireless Communication, ch. 10.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
