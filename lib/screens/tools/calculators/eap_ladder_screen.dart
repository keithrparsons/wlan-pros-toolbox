// 802.1X and EAP Ladder: Wi-Fi Classroom tool (eap-ladder).
//
// A three-lane ladder (client, AP, RADIUS server) that plays an 802.1X
// connection one message at a time: EAP rides EAPOL over the air and RADIUS
// on the wire, the AP relays, the server hands the AP the PMK in the
// Access-Accept, and the 4-way handshake turns it into session keys. The
// method selector changes the middle of the ladder (EAP-TLS, PEAP, EAP-TTLS),
// PSK and SAE show the same join with no RADIUS at all, and the roam modes
// show what PMK caching and 802.11r FT remove.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/21-eap-ladder.md. Sequences come from IEEE 802.11, IEEE
// 802.1X and RFCs 3748, 3579, 5216, 5281, 2759 and 2548, in
// lib/services/wifi_lab/eap_ladder.dart. Method wording is read from the
// app's 802.1X / EAP Types reference (eap_types_screen.dart), unchanged.
//
// ROAM (spec 21b, 2026-09-26): a Mode toggle (Authenticate or Roam) sits
// above the stage. Roam draws four lanes (client, current AP, target AP,
// RADIUS server), Reassociation, PMK caching, OKC, FT over the air and over
// the DS, and a timeline bar of scan, authentication and key handshake.
// Authenticate is the original ladder, unchanged. Joining a network is its
// own tool (join_ladder_screen.dart) on the same controller and stage.
//
// This is NOT the 'eap-types' reference or the 'frame-exchange' reference;
// both are untouched.
//
// STRUCTURE (Keith, 2026-09-25): the pictures and the controls are separate
// widgets that share one EapLadderController.
//   - EapLadderStage    (eap_ladder_stage.dart): the ladder and its caption.
//   - EapLadderControls (eap_ladder_controls.dart): transport, readouts and
//                       settings, in parts.
// This screen only composes them. On a phone they stack; a presenter layout
// can place the stage and a full EapLadderControls side by side. The Present
// button (desktop and tablet windows) does that, over the SAME controller
// (lib/widgets/presenter/, spec 00).
//
// THEME: chrome from context.colors (dark §8 / light §8.20). The two legs
// take one hue each from eap_ladder_palette.dart under GL-003 §8.15.2, with
// labels, a legend and dashed wire arrows so color is never the only cue.
// Lime marks the two milestones (keys available, traffic protected).
//
// MOTION (§8.8): the ladder opens with nothing sent and moves only when the
// student presses Play; the newest arrow draws in over AppMotion.slow. With
// reduced motion on, arrows appear whole and the screen says so. Playback
// pauses when the app is backgrounded.
//
// States (SOP-007 §5):
//   - fresh       -> nothing sent; every arrow faint, phase headings visible;
//                    the caption reads "Ready"; Back and Reset disabled
//   - running     -> Play sends one message per beat at the chosen speed
//   - paused      -> Pause, Step, Back, Show all, a setting change,
//                    backgrounding
//   - ended       -> Play reads "Play again"; Step and Show all disabled
//   - no RADIUS   -> PSK and SAE: the RADIUS lane is dotted and marked
//                    "not used here"; the wire readout says none
//   - disabled    -> inner method outside EAP-TTLS; certificate size and
//                    RADIUS time when the method or roam mode sends no
//                    certificate or RADIUS message; each says why
//   - loading / error -> not reachable: the model is synchronous and pure,
//                    and every input is a bounded select, toggle or slider
//   - interactive -> themed Material controls with the global focus ring;
//                    every sent message carries a worded screen-reader label
//                    and the caption is a live region

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/eap_ladder.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'eap_ladder_controller.dart';
import 'eap_ladder_controls.dart';
import 'eap_ladder_jr_controls.dart';
import 'eap_ladder_parts.dart';
import 'eap_ladder_stage.dart';

export 'eap_ladder_controller.dart' show kEapLadderToolId;

const String _kTitle = '802.1X and EAP Ladder';

class EapLadderScreen extends StatefulWidget {
  const EapLadderScreen({super.key, this.initial});

  /// Test seam: start from a given configuration.
  final LadderConfig? initial;

  @override
  State<EapLadderScreen> createState() => _EapLadderScreenState();
}

class _EapLadderScreenState extends State<EapLadderScreen>
    with WidgetsBindingObserver {
  // The controller builds its own Ticker, so playback keeps going while the
  // presenter route covers (and mutes) this one.
  late final EapLadderController _controller = EapLadderController(
    initial: widget.initial,
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

  /// The presenter layout over this screen's controller (shared, not
  /// copied). Rebuilt with the controller so the keys follow the mode: B
  /// (Break it) exists only in Authenticate, so the ? list must drop it in
  /// Roam, as Association, Frame by Frame already does for its modes.
  Widget _presenter(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (BuildContext context, _) => PresenterLayout(
      title: _kTitle,
      stage: EapLadderStage(controller: _controller),
      controls: EapLadderControls(controller: _controller),
      actions: _controller.presenterActions,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(toolRoute: AppRouter.eapLadder, builder: _presenter),
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
                      // Authenticate or Roam (spec 21b). Join is its own
                      // tool (join-ladder).
                      ElCard(child: LadderModeToggle(controller: _controller)),
                      const SizedBox(height: AppSpacing.sm),
                      EapLadderStage(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      EapLadderControls(controller: _controller),
                      const SizedBox(height: AppSpacing.sm),
                      ListenableBuilder(
                        listenable: _controller,
                        builder: (BuildContext context, _) =>
                            _AboutCard(roam: _controller.isJr),
                      ),
                      const ToolHelpFooter(toolId: kEapLadderToolId),
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
  const _AboutCard({required this.roam});

  /// Roam mode: say what the four-lane ladder draws and leaves out.
  final bool roam;

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
            'The TLS messages follow the TLS 1.2 shape drawn in the EAP-TLS '
            'and EAP-TTLS standards. TLS 1.3 and session resumption change '
            'the count and are not modelled. Servers and clients differ in '
            'how many fragments a certificate needs, so that is a setting.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The TLS tunnel protects the inner exchange between client and '
            'RADIUS server. It does not protect the Wi-Fi link: nothing is '
            'encrypted over the air until the 4-way handshake completes.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            roam
                ? 'Roam draws a second AP, Reassociation naming the current '
                      'AP, OKC and FT over the DS. Not drawn: how the APs '
                      'share keys for FT and OKC, and any DHCP after the '
                      'roam. Every time is a setting you can change.'
                : 'Not drawn: the client sending EAPOL-Start, accounting, and '
                      'how FT and OKC move keys between APs (Roam mode draws '
                      'FT over the DS and OKC with a second AP). Times are '
                      'illustrative; change the RADIUS time to match what you '
                      'measure.',
            style: body,
          ),
        ],
      ),
    );
  }
}
