// Airtime Anatomy (Wi-Fi Classroom, 2026-09-25) — airtime-anatomy.
//
// One transmit opportunity drawn to scale: AIFS, average backoff, optional
// RTS/CTS, preamble, data, SIFS, ACK or Block Ack. Two scenarios stack on one
// microsecond axis, so aggregation, width, MCS, guard interval and band are
// compared by length.
//
// The math is a port of the WLAN Pros Airtime Calculator sheet (myPKA
// Deliverables/2026-09-25-wlanpros-airtime-calculator/build.py), in
// lib/services/wifi_lab/airtime_anatomy.dart. Spec: myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/05-airtime-anatomy.md.
//
// STRUCTURE. The screen owns an [AirtimeAnatomyModel] and composes two
// separate widgets that share it: [AirtimeAnatomyStage] (the bars, axis,
// legend, formula and breakdown) and [AirtimeAnatomyControls] (readouts and
// inputs). Phone and desktop widths stack them; the Present button (desktop
// and tablet windows) opens the same two over the SAME model in the
// presenter layout (lib/widgets/presenter/).
//
// THEME: context.colors only (dark §8 / light §8.20). No categorical hues
// (§8.15); lime marks the data symbols; status hues only on the Check verdict
// (§8.13). Nothing animates, so reduced motion (§8.8) has nothing to remove.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/aggregation_structure.dart';
import '../../../services/wifi_lab/airtime_anatomy.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_anatomy_controls.dart';
import 'airtime_anatomy_model.dart';
import 'airtime_anatomy_stage.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kAirtimeAnatomyToolId = 'airtime-anatomy';

const String _kTitle = 'Airtime Anatomy';

class AirtimeAnatomyScreen extends StatefulWidget {
  const AirtimeAnatomyScreen({super.key, this.model});

  /// Test and render seam: a model the caller owns and disposes. Null (the
  /// app) makes the screen create and dispose its own.
  final AirtimeAnatomyModel? model;

  @override
  State<AirtimeAnatomyScreen> createState() => _AirtimeAnatomyScreenState();
}

class _AirtimeAnatomyScreenState extends State<AirtimeAnatomyScreen> {
  late final AirtimeAnatomyModel _model = widget.model ?? AirtimeAnatomyModel();

  @override
  void dispose() {
    if (widget.model == null) _model.dispose();
    super.dispose();
  }

  String? _copyText() {
    final StringBuffer b = StringBuffer()
      ..writeln('Airtime Anatomy (WLAN Pros Toolbox)');
    for (final int i in _model.visible) {
      final AirtimeScenario s = _model.scenario(i);
      final AirtimeResult r = _model.result(i);
      b.writeln();
      b.writeln('${kScenarioLetters[i]}: ${_model.name(i)}');
      b.writeln(
        '${s.band.label}, ${s.phy.shortLabel}'
        '${s.phy == AirtimePhy.legacy ? ' ${s.legacyRateMbps} Mbps' : ', ${s.widthMhz} MHz, MCS ${s.mcs}, ${s.streams} SS, GI ${s.guardInterval.label}'}'
        ', ${s.payloadBytes} bytes x ${r.framesSent}'
        ', ${s.accessCategory.shortLabel}'
        '${s.rtsCts ? ', RTS/CTS' : ''}',
      );
      if (!r.check.isOk) {
        b.writeln('Check: ${r.check.message}');
        continue;
      }
      for (final TxopSegment seg in r.segments) {
        if (seg.tenths == 0) continue;
        b.writeln('  ${seg.label}: ${seg.durationLabel}');
      }
      b.writeln('  Total: ${formatTenthsUs(r.totalTenths)} µs');
      b.writeln('PHY rate: ${r.phyRateMbps.toStringAsFixed(2)} Mbps');
      b.writeln('Throughput: ${r.throughputMbps.toStringAsFixed(1)} Mbps');
      b.writeln(
        'Efficiency vs PHY rate: ${(r.efficiency * 100).toStringAsFixed(1)} %',
      );
      b.writeln('Check: ${r.check.message}');
    }
    if (_model.view == AirtimeView.structure) {
      final AggregateStructure st = _model.structure;
      final StructureTotals t = st.totals;
      b.writeln();
      b.writeln(
        'Structure (${kScenarioLetters[_model.editing]}): ${st.kind.label}, '
        '${st.unitCount} unit${st.unitCount == 1 ? '' : 's'}, '
        '${st.msduCount} MSDU${st.msduCount == 1 ? '' : 's'}',
      );
      for (final StructurePartKind k in StructurePartKind.values) {
        if (t[k] > 0) b.writeln('  ${k.label}: ${t[k]} bytes');
      }
      b.writeln('  PSDU: ${t.total} bytes');
      final CorruptionOutcome? o = _model.corruption;
      if (o != null) {
        b.writeln(
          'Corrupted MSDU ${o.corruptedMsdu + 1}: resent ${o.resentBytes} of '
          '${st.psduBytes} bytes, ${o.resentMsdus} MSDU'
          '${o.resentMsdus == 1 ? '' : 's'}'
          '${o.usesBlockAck ? ' (Block Ack bit ${o.failedUnit + 1} = 0)' : ' (no ACK)'}',
        );
      }
    }
    return b.toString().trimRight();
  }

  /// The presenter layout over this screen's model (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: AirtimeAnatomyStage(model: _model),
    controls: AirtimeAnatomyControls(model: _model),
    actions: _model.presenterActions,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(_kTitle),
        toolbarHeight: 64,
        actions: <Widget>[
          PresentButton(
            toolRoute: AppRouter.airtimeAnatomy,
            builder: _presenter,
          ),
          AppCopyAction(textBuilder: _copyText),
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
                      AirtimeAnatomyStage(model: _model),
                      const SizedBox(height: AppSpacing.md),
                      AirtimeAnatomyControls(model: _model),
                      const SizedBox(height: AppSpacing.md),
                      const _AboutCard(),
                      const ToolHelpFooter(toolId: kAirtimeAnatomyToolId),
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
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final TextStyle body =
        text.bodySmall?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('What this models'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'One station, no contention, no retries. Backoff is the average '
            'draw, half of CWmin in 9 µs slots. Control frames go at the '
            'legacy rate you choose.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'HT and VHT use one BCC encoder. HE uses LDPC with pre-FEC '
            'padding ignored, 2x HE-LTFs (4x at a 3.2 µs guard interval), '
            'and covers the single-user PPDU, not OFDMA resource units.',
            style: body,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The Check catches the main band and MCS rules, not every VHT '
            'exclusion. Confirm unusual combinations in the MCS Index tool.',
            style: body,
          ),
        ],
      ),
    );
  }
}
