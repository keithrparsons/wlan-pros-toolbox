// Airtime Fairness (Wi-Fi Classroom, 2026-09-25) — airtime-fairness.
//
// Why one slow client drags every fast client down under plain 802.11
// contention (the performance anomaly), and how giving each client an equal
// share of TIME, rather than an equal number of turns, fixes it. The student
// builds a cell of 1 to 8 clients, flips between Packet and Airtime fairness
// (or compares both), and reads the airtime share bar, the throughput bars and
// an animated round whose blocks are as wide as their airtime.
//
// Built clean-room from IEEE 802.11 timing and Heusse et al., INFOCOM 2003.
// Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 04-throughput-airtime-fairness.md.
//
// STRUCTURE (Keith, 2026-09-25; controller split 2026-09-26 for the
// presenter layout): AirtimeFairnessController holds all state and the round
// clock; the screen owns it and composes two independent widgets over it,
// AirtimeFairnessStage (what the student watches) and the controls
// (AirtimeFairnessRuleCard + AirtimeFairnessClientsCard, or both as
// AirtimeFairnessControls). Phone stacks rule, stage, clients, about. The
// Present button (desktop and tablet windows) opens the same views over the
// SAME controller in the presenter layout (lib/widgets/presenter/).
//
// States (SOP-007 §5):
//   - success   -> every client valid: takeaway, share bars, throughput bars,
//                  round
//   - error     -> a custom rate is empty or out of range: the field shows
//                  the error and the stage says which client to fix
//   - empty     -> not reachable: the cell never drops below one client; with
//                  one client the takeaway says both rules agree
//   - loading   -> none: the model is synchronous
//   - disabled  -> Add at 8 clients, Remove at 1, aggregation for legacy
//   - reduced motion -> the round is drawn complete, no playhead, no Replay
//   - interactive -> themed Material controls with the global focus ring

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_fairness_common.dart';
import 'airtime_fairness_controller.dart';
import 'airtime_fairness_controls.dart';
import 'airtime_fairness_stage.dart';

export 'airtime_fairness_controller.dart'
    show kAirtimeFairnessToolId, AirtimeFairnessController;

const String _kTitle = 'Airtime Fairness';

class AirtimeFairnessScreen extends StatefulWidget {
  const AirtimeFairnessScreen({super.key, this.controller});

  /// Test and render seam: a controller the caller owns and disposes. Null
  /// (the app) makes the screen create and dispose its own.
  final AirtimeFairnessController? controller;

  @override
  State<AirtimeFairnessScreen> createState() => _AirtimeFairnessScreenState();
}

class _AirtimeFairnessScreenState extends State<AirtimeFairnessScreen> {
  late final AirtimeFairnessController _controller =
      widget.controller ?? AirtimeFairnessController();
  bool _startedRound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.reducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_startedRound) {
      _startedRound = true;
      _controller.replay();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  AirtimeFairnessRuleCard _rule() {
    final AirtimeFairnessController c = _controller;
    final bool valid = c.configs != null;
    return AirtimeFairnessRuleCard(
      view: c.view,
      onViewChanged: (FairnessView v) => c.view = v,
      takeaway: c.takeaway,
      onReplay: valid ? c.replay : null,
      reducedMotion: c.reducedMotion,
      playing: c.playing,
      onPlayPause: c.togglePlay,
      onStep: c.stepTransmission,
      onReset: c.resetRound,
    );
  }

  Widget _stage() {
    final AirtimeFairnessController c = _controller;
    return AirtimeFairnessStage(
      clients: c.configs,
      payloadBytes: c.payloadBytes,
      view: c.view,
      round: c.round,
      invalidClient: c.invalidClient,
      takeaway: c.takeaway,
    );
  }

  AirtimeFairnessClientsCard _clients() {
    final AirtimeFairnessController c = _controller;
    return AirtimeFairnessClientsCard(
      clients: c.clients,
      payloadBytes: c.payloadBytes,
      onPayloadChanged: (int b) => c.payloadBytes = b,
      onEdit: c.edit,
      onAdd: c.addClient,
      onRemove: c.removeClient,
    );
  }

  /// The presenter layout over this screen's controller (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, _) => _stage(),
    ),
    controls: ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, _) =>
          AirtimeFairnessControls(rule: _rule(), clients: _clients()),
    ),
    actions: _controller.presenterActions,
  );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.airtimeFairness,
            builder: _presenter,
          ),
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
                  maxWidth: AppSpacing.contentMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    edge,
                    AppSpacing.sm,
                    edge,
                    edge + AppSpacing.sm,
                  ),
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (BuildContext context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _rule(),
                        const SizedBox(height: AppSpacing.md),
                        _stage(),
                        const SizedBox(height: AppSpacing.md),
                        _clients(),
                        const SizedBox(height: AppSpacing.md),
                        const _AboutCard(),
                        const ToolHelpFooter(toolId: kAirtimeFairnessToolId),
                      ],
                    ),
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

// ── About ────────────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle cell = mono.inlineCode.copyWith(
      fontSize: AppTextSize.caption,
      color: colors.textPrimary,
    );
    String us(double v) => '${v == v.roundToDouble() ? v.round() : v} µs';
    Widget row(String what, String value, String source) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Text(
                what,
                style: body.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: AppSpacing.xxl,
              child: Text(value, style: cell),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(flex: 4, child: Text(source, style: body)),
          ],
        ),
      ),
    );

    return LabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const LabSectionTitle('What this models'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This is a teaching model: one AP sending to every client, every '
            'client always has data waiting, and no collisions. Airtime '
            'Anatomy does the exact per-PHY calculation.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            'T = overhead + 8 x frames x (payload + 34) / rate',
            style: cell.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          row(
            'AIFS, best effort',
            us(AirtimeConstants.aifsUs),
            'SIFS + 3 slots of 9 µs',
          ),
          row(
            'Average backoff',
            us(AirtimeConstants.avgBackoffUs),
            'CWmin 15, mean 7.5 slots',
          ),
          row(
            'Preamble, legacy',
            us(AirtimeConstants.preambleLegacyUs),
            'OFDM preamble and SIGNAL',
          ),
          row(
            'Preamble, HT or newer',
            us(AirtimeConstants.preambleHtUs),
            'One teaching value for HT, VHT and HE',
          ),
          row('SIFS', us(AirtimeConstants.sifsUs), '5 GHz OFDM'),
          row(
            'ACK',
            us(AirtimeConstants.ackUs),
            'One frame per turn, sent at 24 Mbps',
          ),
          row(
            'Block Ack',
            us(AirtimeConstants.blockAckUs),
            'Aggregated turns, sent at 24 Mbps',
          ),
          row('Bytes per frame', '34 B', 'MAC header 26, FCS 4, delimiter 4'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Packet fairness: each client gets one turn per round. Airtime '
            'fairness: each client gets 1/N of the time. Not modeled: '
            'collisions, retries, rate adaptation, uplink traffic, and the '
            'limits on how many frames one aggregate may carry.',
            style: body,
          ),
        ],
      ),
    );
  }
}
