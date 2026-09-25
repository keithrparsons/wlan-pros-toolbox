// FSPL Simulator: Wi-Fi Lab tool (fspl-simulator).
//
// Draws free-space path loss (or the received power it leaves) against
// distance on a log axis, one curve per band, and splits the loss into the
// part every band shares (spreading) and the part that changes with frequency
// (the receive antenna's aperture). The lesson it exists to teach: higher
// bands lose more because the receive antenna is smaller, not because the air
// absorbs more.
//
// CLEAN-ROOM BUILD (2026-09-25) from the Friis transmission equation, per
// myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/03-fspl-simulator.md.
// This is NOT the 'fspl' calculator, which is untouched.
//
// STRUCTURE (Keith, 2026-09-25): the stage and the controls are separate
// widgets over one model, and this screen only composes them.
//   - FsplSimModel      (fspl_simulator_model.dart)  state + derived numbers
//   - FsplStage         (fspl_simulator_stage.dart)  toggles, plot, legend,
//                                                     cursor
//   - FsplBandChips, FsplControls, FsplReadouts, FsplExplainer
//                       (fspl_simulator_panels.dart) inputs and readouts
//   - FsplChartPainter  (fspl_simulator_chart.dart)  the log-axis painter
// A later full-screen presenter layout reuses the same widgets side by side.
//
// LAYOUT: phone first. Below 720 px the stage leads the scroll and the
// controls live in a bottom sheet collapsed to one row of band toggles. At
// 720 px and up the sheet becomes a side panel.
//
// States (SOP-007 §5):
//   - loading     -> none: pure on-device arithmetic, no I/O
//   - empty       -> every band off: plot and readouts say to turn one on
//   - error       -> measured RSSI or distance invalid: inline field error,
//                    nothing plotted
//   - success     -> curves, cursor readout, Why bars, measured gap
//   - disabled    -> indoor exponent slider while the overlay is off; the
//                    cursor slider while no band is on
//   - interactive -> plot drag and tap, cursor slider (keyboard), themed
//                    Material controls with the global focus ring
//
// MOTION (§8.8): the only animation is the sheet opening; it is instant when
// reduced motion is on.

import 'package:flutter/material.dart';

import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'fspl_simulator_model.dart';
import 'fspl_simulator_panels.dart';
import 'fspl_simulator_stage.dart';

export 'fspl_simulator_model.dart' show kFsplSimulatorToolId;

/// Side panel width on desktop.
const double _kPanelWidth = 360;

class FsplSimulatorScreen extends StatefulWidget {
  const FsplSimulatorScreen({super.key});

  @override
  State<FsplSimulatorScreen> createState() => _FsplSimulatorScreenState();
}

class _FsplSimulatorScreenState extends State<FsplSimulatorScreen> {
  final FsplSimModel _model = FsplSimModel();
  bool _sheetOpen = false;

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FSPL Simulator'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _model.copyText)],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            if (c.maxWidth >= 720) return _desktop(c);
            final double chartH = (c.maxHeight * 0.46).clamp(240.0, 420.0);
            return Column(
              children: <Widget>[
                Expanded(
                  child: _main(
                    edge: AppSpacing.screenEdgeMobile,
                    chartHeight: chartH,
                  ),
                ),
                _sheet(c.maxHeight, reduceMotion),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _main({required double edge, required double chartHeight}) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(edge, AppSpacing.sm, edge, edge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FsplStage(model: _model, chartHeight: chartHeight),
          const SizedBox(height: AppSpacing.sm),
          FsplReadouts(model: _model),
          const SizedBox(height: AppSpacing.sm),
          const FsplExplainer(),
          const ToolHelpFooter(toolId: kFsplSimulatorToolId),
        ],
      ),
    );
  }

  Widget _desktop(BoxConstraints c) {
    final AppColorScheme colors = context.colors;
    final double chartH = (c.maxHeight * 0.55).clamp(300.0, 480.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.gridMaxWidth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _main(
                edge: AppSpacing.screenEdgeDesktop,
                chartHeight: chartH,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const FsplSectionLabel('Bands'),
                    const SizedBox(height: AppSpacing.xs),
                    FsplBandChips(model: _model),
                    const SizedBox(height: AppSpacing.md),
                    FsplControls(model: _model),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Phone bottom sheet: one row of band toggles plus a button that opens the
  /// rest of the controls.
  Widget _sheet(double bodyHeight, bool reduceMotion) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String toggleLabel = _sheetOpen ? 'Hide controls' : 'Show controls';
    return Material(
      color: colors.surface2,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      child: AnimatedSize(
        duration: reduceMotion ? Duration.zero : AppMotion.slow,
        curve: AppMotion.standardEase,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.xxs,
                AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(child: FsplBandChips(model: _model)),
                  Semantics(
                    button: true,
                    expanded: _sheetOpen,
                    label: toggleLabel,
                    excludeSemantics: true,
                    child: IconButton(
                      tooltip: toggleLabel,
                      onPressed: () => setState(() => _sheetOpen = !_sheetOpen),
                      icon: Icon(
                        _sheetOpen ? Icons.expand_more : Icons.tune,
                        color: colors.textAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_sheetOpen)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: bodyHeight * 0.55),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.border)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: FsplControls(model: _model),
                  ),
                ),
              )
            else
              ListenableBuilder(
                listenable: _model,
                builder: (BuildContext context, Widget? _) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    _summary(),
                    style: text.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _summary() {
    final String Function(double, [int]) n = FsplFormat.n;
    return 'Tx ${n(_model.txPowerDbm, 0)} dBm, gains '
        '${n(_model.txGainDbi)} / ${n(_model.rxGainDbi)} dBi'
        '${_model.otherLossDb > 0 ? ', losses ${n(_model.otherLossDb)} dB' : ''}'
        '${_model.indoor ? ', indoor n = ${n(_model.exponent)}' : ''}';
  }
}
