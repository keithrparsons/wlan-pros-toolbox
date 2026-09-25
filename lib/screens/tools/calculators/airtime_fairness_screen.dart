// Airtime Fairness (Wi-Fi Lab, 2026-09-25) — airtime-fairness.
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
// STRUCTURE (Keith, 2026-09-25): the screen owns all state and composes two
// independent widgets, AirtimeFairnessStage (what the student watches) and
// the controls (AirtimeFairnessRuleCard + AirtimeFairnessClientsCard, or both
// as AirtimeFairnessControls). Phone stacks rule, stage, clients, about. A
// later presenter layout can place stage and controls side by side.
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

import '../../../services/wifi_lab/airtime_fairness_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_fairness_common.dart';
import 'airtime_fairness_controls.dart';
import 'airtime_fairness_stage.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kAirtimeFairnessToolId = 'airtime-fairness';

const Duration _kRoundDuration = Duration(milliseconds: 2400);

class AirtimeFairnessScreen extends StatefulWidget {
  const AirtimeFairnessScreen({super.key});

  @override
  State<AirtimeFairnessScreen> createState() => _AirtimeFairnessScreenState();
}

class _AirtimeFairnessScreenState extends State<AirtimeFairnessScreen>
    with SingleTickerProviderStateMixin {
  int _nextId = 0;

  /// Spec defaults: three clients at 867 Mbps sending 32 frames per turn,
  /// plus one legacy client at 6 Mbps with no aggregation.
  late List<AirtimeClientDraft> _clients = <AirtimeClientDraft>[
    for (int i = 0; i < 3; i++)
      AirtimeClientDraft(
        id: _nextId++,
        preset: RatePreset.vht867,
        aggregation: 32,
      ),
    AirtimeClientDraft(id: _nextId++, preset: RatePreset.legacy6),
  ];
  FairnessView _view = FairnessView.compare;
  int _payload = AirtimeConstants.defaultPayloadBytes;

  late final AnimationController _round = AnimationController(
    vsync: this,
    duration: _kRoundDuration,
  );
  bool _startedRound = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_startedRound) {
      _startedRound = true;
      _replay();
    } else if (_reducedMotion) {
      _round.value = 1;
    }
  }

  @override
  void dispose() {
    _round.dispose();
    for (final AirtimeClientDraft c in _clients) {
      c.controller.dispose();
    }
    super.dispose();
  }

  bool get _reducedMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _replay() {
    if (_reducedMotion) {
      _round.value = 1;
    } else {
      _round.forward(from: 0);
    }
  }

  void _change(VoidCallback f) {
    setState(f);
    _replay();
  }

  void _add() => _change(
    () => _clients = <AirtimeClientDraft>[
      ..._clients,
      AirtimeClientDraft(id: _nextId++, preset: RatePreset.vht867),
    ],
  );

  void _remove(int id) => _change(() {
    final AirtimeClientDraft gone = _clients.firstWhere(
      (AirtimeClientDraft d) => d.id == id,
    );
    // Dispose after the row's TextField has detached from the controller.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => gone.controller.dispose(),
    );
    _clients = <AirtimeClientDraft>[
      for (final AirtimeClientDraft d in _clients)
        if (d.id != id) d,
    ];
  });

  /// All client configs, or null while any row is invalid.
  List<ClientConfig>? get _configs {
    final List<ClientConfig> out = <ClientConfig>[];
    for (final AirtimeClientDraft c in _clients) {
      final ClientConfig? cfg = c.toConfig();
      if (cfg == null) return null;
      out.add(cfg);
    }
    return out;
  }

  // ── Copy ───────────────────────────────────────────────────────────────────

  String? _copyText() {
    final List<ClientConfig>? cs = _configs;
    if (cs == null) return null;
    final FairnessResult p = computeFairness(
      cs,
      FairnessMode.packet,
      payloadBytes: _payload,
    );
    final FairnessResult a = computeFairness(
      cs,
      FairnessMode.airtime,
      payloadBytes: _payload,
    );
    final StringBuffer b = StringBuffer()
      ..writeln('Airtime Fairness (WLAN Pros Toolbox)')
      ..writeln('Payload $_payload bytes per frame; downlink, no collisions')
      ..writeln(airtimeTakeaway(p, a, FairnessView.compare));
    for (int i = 0; i < cs.length; i++) {
      b.writeln(
        'Client ${clientLetter(i)}: ${rateText(cs[i])} per turn, '
        '${fmtUs(p.clients[i].airtimePerTxUs)} per turn; '
        'packet ${fmtMbps(p.clients[i].throughputMbps)} Mbps '
        '(${fmtPct(p.clients[i].airtimeShare)} of air), '
        'airtime ${fmtMbps(a.clients[i].throughputMbps)} Mbps '
        '(${fmtPct(a.clients[i].airtimeShare)} of air)',
      );
    }
    b.writeln(
      'Total: packet ${fmtMbps(p.aggregateMbps)} Mbps, '
      'airtime ${fmtMbps(a.aggregateMbps)} Mbps',
    );
    return b.toString().trimRight();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<ClientConfig>? cs = _configs;
    String? takeaway;
    if (cs != null) {
      takeaway = airtimeTakeaway(
        computeFairness(cs, FairnessMode.packet, payloadBytes: _payload),
        computeFairness(cs, FairnessMode.airtime, payloadBytes: _payload),
        _view,
      );
    }
    final int invalid = _clients.indexWhere(
      (AirtimeClientDraft c) => c.rateError != null,
    );

    final AirtimeFairnessRuleCard rule = AirtimeFairnessRuleCard(
      view: _view,
      onViewChanged: (FairnessView v) => _change(() => _view = v),
      takeaway: takeaway,
      onReplay: cs == null ? null : _replay,
      reducedMotion: _reducedMotion,
    );
    final Widget stage = AirtimeFairnessStage(
      clients: cs,
      payloadBytes: _payload,
      view: _view,
      round: _round,
      invalidClient: invalid < 0 ? null : invalid,
    );
    final AirtimeFairnessClientsCard clients = AirtimeFairnessClientsCard(
      clients: _clients,
      payloadBytes: _payload,
      onPayloadChanged: (int b) => _change(() => _payload = b),
      onEdit: _change,
      onAdd: _add,
      onRemove: _remove,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Airtime Fairness'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
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
                      rule,
                      const SizedBox(height: AppSpacing.md),
                      stage,
                      const SizedBox(height: AppSpacing.md),
                      clients,
                      const SizedBox(height: AppSpacing.md),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kAirtimeFairnessToolId),
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
