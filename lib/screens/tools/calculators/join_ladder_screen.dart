// Association, Frame by Frame: Wi-Fi Classroom tool (join-ladder).
//
// NOT the 'join-network' tool (Join a Network, Networking Tools), which
// really joins this device or a WLAN Pi to a network. This one teaches the
// frames; its id pairs it with 'eap-ladder'.
//
// Keith, 2026-09-26: "Teach and show with animation how a client associates
// to a network". Then, the same day: Join is its own simulator, not a mode
// inside the 802.1X and EAP Ladder.
//
// A ladder of every frame a client sends and receives from the first scan to
// the first useful packet: the scan (a channel strip with each channel's
// dwell and the AP's beacons, heard or missed), Open System or SAE
// authentication, association (tap it to see what it carries), the EAP
// exchange for 802.1X, the 4-way handshake drawn as the data frames it is,
// DHCP, the address check (Address Conflict Detection or Detecting Network
// Attachment), then ARP and DNS. A lock after message 4; a PMF shield only on
// management frames once keys exist.
//
// CLEAN-ROOM BUILD (2026-09-26) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/21b-join-and-roam-frames.md and the research brief it
// cites. The model is lib/services/wifi_lab/join_roam.dart; the EAP middle
// is the ladder's own model (eap_ladder.dart), unchanged.
//
// SHARED ENGINE, NOT A COPY: this screen drives the ladder's controller
// (EapLadderController) in Join mode, and draws with the ladder's Join/Roam
// stage and controls (eap_ladder_jr_stage.dart, eap_ladder_jr_controls.dart),
// which import the ladder's palette and parts. The 802.1X and EAP Ladder
// uses the same stage for its Roam mode.
//
// STRUCTURE (spec 00): stage and controls are separate widgets over one
// controller; the phone layout stacks them and the Present button places
// them side by side over the SAME controller.
//
// States (SOP-007 §5):
//   - fresh       -> nothing sent; faint arrows; "Ready"; Back, Reset disabled
//   - running / paused / ended -> as the ladder (Play, Pause, Step, Back,
//                    Show all, Play again)
//   - inspecting  -> a tapped message in the caption, outlined in lime
//   - not found   -> a passive dwell shorter than the wait for the beacon:
//                    a warning band, and the ladder stops after the scan
//   - disabled    -> settings that change nothing for the choice (PMF for
//                    Open, OWE and SAE; 6 GHz discovery outside 6 GHz; the
//                    Address Conflict Detection sliders under DNAv4), each
//                    with a sentence saying why
//   - loading / error -> not reachable: the model is synchronous and pure
//   - interactive -> themed Material controls with the global focus ring;
//                    every sent message is a labeled button; the caption is a
//                    live region

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/join_roam.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_controls.dart';
import 'eap_ladder_jr_stage.dart';
import 'eap_ladder_parts.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kJoinLadderToolId = 'join-ladder';

const String _kTitle = 'Association, Frame by Frame';

class JoinLadderScreen extends StatefulWidget {
  const JoinLadderScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final JrConfig? initial;

  @override
  State<JoinLadderScreen> createState() => _JoinLadderScreenState();
}

class _JoinLadderScreenState extends State<JoinLadderScreen>
    with WidgetsBindingObserver {
  late final EapLadderController _controller = EapLadderController(
    mode: LadderMode.join,
    initialJr: widget.initial,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: JoinRoamStage(controller: _controller),
    controls: EapLadderControls(controller: _controller),
    actions: _controller.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.joinLadder, builder: _presenter),
          AppCopyAction(textBuilder: _controller.copyText),
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
                      JoinRoamStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      EapLadderControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kJoinLadderToolId),
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
    return ElCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const ElSectionLabel('What this models, and what it leaves out'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Open System authentication and association are bookkeeping, not '
            'security. The keys come after association, in the 4-way '
            'handshake (or SAE before it, for WPA3-Personal), and even then '
            'the client has no IP address until DHCP finishes.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Every phase time is a setting: no published measurement breaks '
            'a typical association down by phase. The scan uses US 20 MHz channels, '
            'one AP, and the Linux mac80211 dwell times as one real example. '
            'Channel changes, the DHCP client\'s own start-up delay and '
            'retries are not drawn.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'With Detecting Network Attachment (DNAv4), a real client often '
            'skips the four DHCP messages and asks only to keep its old '
            'address. The ladder keeps them so the two address checks '
            'compare side by side.',
            style: body,
          ),
        ],
      ),
    );
  }
}
