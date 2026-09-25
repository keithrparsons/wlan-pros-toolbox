// Wi-Fi Through a Wall: Wi-Fi Lab tool (wifi-through-a-wall).
//
// One wave, one wall. Part of the wave reflects off the face, the wavelength
// shrinks inside the material while the frequency stays the same, and the
// amplitude decays through it. Then the per-band story: concrete loses more
// at 6 GHz than at 2.4 GHz, but thin panels do not lose monotonically more at
// higher frequency, because of thin-slab resonance.
//
// CLEAN-ROOM BUILD (2026-09-25) from ITU-R P.2040-4 as set out in myPKA
// Deliverables/2026-09-25-wifi-lab-research/brief.md §6.3-§6.4, per
// Deliverables/2026-09-25-wifi-lab-cleanroom/specs/12-wall-slab.md. All math
// lives in lib/services/wifi_lab/wall_slab_physics.dart.
//
// This is NOT the 'rf-attenuation' tool, which is untouched; whether its
// numbers change is Keith's decision (spec).
//
// STRUCTURE: the screen owns one WallConfig and composes separate widgets,
// so a later presenter layout can reuse them side by side:
//   WallSlabStage     the animated wave (wifi_through_a_wall_stage.dart)
//   WallSlabControls  the inputs      (wifi_through_a_wall_controls.dart)
//   WallSlabReadouts, WallBandsCard, WallMeasuredCard  the numbers
//
// States (SOP-007 §5):
//   - running     -> the wave animates (default unless reduced motion is on)
//   - paused      -> Pause, app backgrounded, or reduced motion at open
//   - error       -> thickness field outside 1-500 mm or unparseable: inline
//                    error text, the last valid wall stays on screen
//   - empty       -> a material with no measured data: the measured card says
//                    so instead of showing an empty table
//   - disabled    -> "Set the wall to N mm" is hidden when the wall is
//                    already that thick
//   - interactive -> themed Material controls with the global focus ring;
//                    the plot and tables carry worded Semantics labels

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/wall_slab_physics.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'wifi_through_a_wall_controls.dart';
import 'wifi_through_a_wall_parts.dart';
import 'wifi_through_a_wall_stage.dart';

export 'wifi_through_a_wall_parts.dart' show kWifiThroughAWallToolId;

class WifiThroughAWallScreen extends StatefulWidget {
  const WifiThroughAWallScreen({super.key, this.initial = const WallConfig()});

  /// Starting wall. Defaults to 102 mm concrete on channel 100.
  final WallConfig initial;

  @override
  State<WifiThroughAWallScreen> createState() => _WifiThroughAWallScreenState();
}

class _WifiThroughAWallScreenState extends State<WifiThroughAWallScreen>
    with WidgetsBindingObserver {
  late WallConfig _config = widget.initial;
  bool _playing = false;
  bool _motionDecided = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motionDecided) {
      // Animate on open only when reduced motion is off (GL-003 §8.8).
      _playing = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
      _motionDecided = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _playing) {
      setState(() => _playing = false);
    }
  }

  void _set(WallConfig c) {
    if (c != _config) setState(() => _config = c);
  }

  String _buildCopyText() {
    final WallConfig c = _config;
    final SlabResult r = c.result;
    final StringBuffer b = StringBuffer()
      ..writeln('Wi-Fi Through a Wall (ITU-R P.2040-4 model)')
      ..writeln(
        '${c.material.label}, ${fmtMm(c.thicknessMm)} mm, '
        '${c.angleDeg.toStringAsFixed(0)} deg, '
        '${c.polarization.name.toUpperCase()}',
      )
      ..writeln('Channel ${c.channel}, ${c.centerMHz} MHz')
      ..writeln(
        'Transmission loss: ${fmtLossDb(r.transmissionLossDb)} '
        '(absorption ${fmtLossDb(r.absorptionDb)}, reflection '
        '${fmtLossDb(r.reflectionPartDb)})',
      );
    if (r.reflectedPower > 0) {
      b.writeln(
        'Reflection: ${fmt1(r.reflectionDb)} dB '
        '(${fmtPct(r.reflectedPower)} of the power)',
      );
    }
    b
      ..writeln('Wavelength in air: ${fmtLength(r.props.lambdaAir)}')
      ..writeln('Same wall by band:');
    for (final double f in kComparisonGhz) {
      b.writeln('  $f GHz: ${fmtLossDb(c.resultAt(f).transmissionLossDb)}');
    }
    b.writeln(
      'Model values, not measurements. Free-space loss is not included.',
    );
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Through a Wall'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
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
                      WallSlabStage(
                        config: _config,
                        plotHeight: isDesktop ? 260 : 200,
                        playing: _playing,
                        onPlayingChanged: (bool p) =>
                            setState(() => _playing = p),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      WallSlabControls(config: _config, onChanged: _set),
                      const SizedBox(height: AppSpacing.sm),
                      WallSlabReadouts(config: _config),
                      const SizedBox(height: AppSpacing.sm),
                      WallBandsCard(config: _config),
                      const SizedBox(height: AppSpacing.sm),
                      WallMeasuredCard(
                        config: _config,
                        onUseThickness: (double mm) =>
                            _set(_config.copyWith(thicknessMm: mm)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const _FreeSpaceCard(),
                      const SizedBox(height: AppSpacing.sm),
                      const _ExplainerCard(),
                      ToolHelpFooter(toolId: kWifiThroughAWallToolId),
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

/// Free-space loss is a separate effect (spec): keeps the student from
/// blaming the wall for the antenna-aperture difference.
class _FreeSpaceCard extends StatelessWidget {
  const _FreeSpaceCard();

  @override
  Widget build(BuildContext context) {
    return WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const WallSectionLabel('Not the wall: free-space loss'),
          const SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.settings_input_antenna,
            message:
                'Every number above is the wall alone. Separately, with the '
                'same antennas, free-space loss rises '
                '${fmt1(fsplDeltaDb(2.4, 5.5))} dB from 2.4 to 5.5 GHz and '
                '${fmt1(fsplDeltaDb(2.4, 6.5))} dB from 2.4 to 6.5 GHz, '
                'because an antenna at a shorter wavelength captures less. '
                'That happens with no wall at all. The Free Space Path Loss '
                'calculator covers it.',
          ),
        ],
      ),
    );
  }
}

class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard();

  @override
  Widget build(BuildContext context) {
    return const WallCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          WallSectionLabel('What you are seeing'),
          SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.u_turn_left,
            message:
                'Reflection: in front of the wall the incident and reflected '
                'waves overlap. Their peaks line up every half wavelength and '
                'cancel in between, which is why moving a phone a few '
                'centimeters can change the signal.',
          ),
          SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.compress,
            message:
                'Shorter wavelength inside: the wave slows down in the '
                'material, so its wavelength shrinks by the square root of '
                'the permittivity. The frequency does not change.',
          ),
          SizedBox(height: AppSpacing.xs),
          WallNote(
            icon: Icons.trending_down,
            message:
                'Decay: the material turns some of the energy into heat, so '
                'the amplitude falls steadily through the wall. The wave '
                'behind is the same frequency, just smaller.',
          ),
        ],
      ),
    );
  }
}
