// Spatial Reuse: Wi-Fi Lab tool (spatial-reuse).
//
// Two BSSs on one channel along a line. AP A is sending; AP B has a frame
// ready. Teaches three things (spec 20): a radio defers to any Wi-Fi preamble
// at -82 dBm or energy at -62 dBm, so neighbors take turns even when they
// barely interfere; 802.11ax BSS color lets a radio tell its own BSS from a
// neighbor; and for a neighbor it may raise its threshold (OBSS_PD) toward
// -62 dBm, paying 1 dB of transmit power for every 1 dB. Spatial reuse
// trades range for concurrency.
//
// CLEAN-ROOM BUILD (2026-09-25) per myPKA
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/20-spatial-reuse.md.
//
// STRUCTURE (Keith, 2026-09-25): stage and controls are separate widgets over
// one state object; this screen only composes them.
//   - SpatialReuseState     (spatial_reuse_state.dart)   state + analysis
//   - SpatialReuseStage     (spatial_reuse_stage.dart)   line, meter, timeline
//   - SpatialReuseControls, SpatialReuseReadouts
//                           (spatial_reuse_panels.dart)  inputs, numbers
//   - the math              (services/wifi_lab/spatial_reuse_model.dart)
// A later full-screen presenter layout reuses the same widgets side by side.
//
// LAYOUT: phone (< 720 px) pins the stage above scrolling readouts and
// controls, so moving a slider shows its effect; on a short screen
// (< 640 px tall) everything scrolls together. The stage only takes
// horizontal drags, so it is safe inside a vertical scroll. Desktop: stage
// and readouts on the left, controls in a side panel.
//
// States (SOP-007 §5):
//   - loading     -> none: on-device arithmetic, no I/O
//   - empty       -> none: the four radios are always present
//   - error       -> none reachable: every control is bounded; a level off
//                    the meter's scale is labeled "(below scale)" or
//                    "(above scale)" rather than drawn wrong
//   - success     -> decision, links, rules
//   - disabled    -> color numbers, OBSS_PD and TX_PWRref with coloring off
//   - interactive -> drag on the line; every control is keyboard reachable
//                    with the global focus ring
//
// MOTION (§8.8): none, so reduced motion needs nothing.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'spatial_reuse_panels.dart';
import 'spatial_reuse_stage.dart';
import 'spatial_reuse_state.dart';

export 'spatial_reuse_state.dart' show kSpatialReuseToolId;

const double _kPanelWidth = 360;

/// Below this height the phone layout scrolls the stage too.
const double _kPinStageMinHeight = 640;

class SpatialReuseScreen extends StatefulWidget {
  const SpatialReuseScreen({super.key});

  @override
  State<SpatialReuseScreen> createState() => _SpatialReuseScreenState();
}

class _SpatialReuseScreenState extends State<SpatialReuseScreen> {
  final SpatialReuseState _state = SpatialReuseState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spatial Reuse'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _state.copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) =>
              c.maxWidth >= 720 ? _desktop() : _phone(c),
        ),
      ),
    );
  }

  List<Widget> _below() => <Widget>[
    SpatialReuseReadouts(state: _state),
    const SizedBox(height: AppSpacing.sm),
    ReuseCard(child: SpatialReuseControls(state: _state)),
    const ToolHelpFooter(toolId: kSpatialReuseToolId),
  ];

  Widget _phone(BoxConstraints c) {
    const double edge = AppSpacing.screenEdgeMobile;
    final Widget stage = SpatialReuseStage(state: _state);
    if (c.maxHeight < _kPinStageMinHeight) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(edge, AppSpacing.xs, edge, edge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            stage,
            const SizedBox(height: AppSpacing.sm),
            ..._below(),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(edge, AppSpacing.xs, edge, 0),
          child: stage,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _below(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktop() {
    final AppColorScheme colors = context.colors;
    const double edge = AppSpacing.screenEdgeDesktop;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  edge,
                  AppSpacing.sm,
                  edge,
                  edge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SpatialReuseStage(state: _state),
                    const SizedBox(height: AppSpacing.sm),
                    SpatialReuseReadouts(state: _state),
                    const ToolHelpFooter(toolId: kSpatialReuseToolId),
                  ],
                ),
              ),
            ),
            Container(
              width: _kPanelWidth,
              decoration: BoxDecoration(
                color: colors.surface1,
                border: Border(left: BorderSide(color: colors.border)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: SpatialReuseControls(state: _state),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
