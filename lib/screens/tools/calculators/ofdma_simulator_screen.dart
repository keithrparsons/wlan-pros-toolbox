// OFDMA Resource Units (Wi-Fi Classroom, 2026-09-25) — ofdma-simulator.
//
// OFDMA splits one channel into resource units (RUs) so an AP can talk to
// several clients in one transmission. The student places clients into RUs
// on the channel, then compares the airtime of N single-user TXOPs with one
// DL OFDMA and one UL OFDMA TXOP, drawn to the same microsecond scale.
//
// The model is lib/services/wifi_lab/ofdma_model.dart, which reuses the
// Airtime Anatomy service for HE SU timing. Spec: myPKA Deliverables/
// 2026-09-25-wifi-lab-cleanroom/specs/19-ofdma.md; values from the wave-3
// research brief §6.
//
// STRUCTURE. The screen owns an [OfdmaSimulatorModel] and composes two
// separate widgets that share it: [OfdmaSimulatorStage] (the channel strip
// and the timelines) and [OfdmaSimulatorControls] (readouts and inputs).
// Phone and desktop widths stack them; the Present button (desktop and
// tablet windows) opens the same two over the SAME model in the presenter
// layout (lib/widgets/presenter/). The RU table and the assumptions are
// reference cards under them on the phone.
//
// THEME: context.colors, plus the Wi-Fi Classroom client palette (GL-003 §8.15.2)
// for the one-hue-per-client lesson, always paired with the client letter.
// Status hues only on a failed check (§8.13). Nothing animates, so reduced
// motion (§8.8) has nothing to remove.

import 'package:flutter/material.dart';

import '../../../router/app_router.dart';
import '../../../services/wifi_lab/airtime_anatomy.dart' show formatTenthsUs;
import '../../../services/wifi_lab/ofdma_model.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/presenter/presenter.dart';
import '../../../widgets/tool_help_footer.dart';
import 'airtime_anatomy_stage.dart' show AirtimeCard, AirtimeSectionTitle;
import 'ofdma_simulator_controls.dart';
import 'ofdma_simulator_model.dart';
import 'ofdma_simulator_stage.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
const String kOfdmaSimulatorToolId = 'ofdma-simulator';

const String _kTitle = 'OFDMA Resource Units';

class OfdmaSimulatorScreen extends StatefulWidget {
  const OfdmaSimulatorScreen({super.key, this.model});

  /// Test and render seam: a model the caller owns and disposes. Null (the
  /// app) makes the screen create and dispose its own.
  final OfdmaSimulatorModel? model;

  @override
  State<OfdmaSimulatorScreen> createState() => _OfdmaSimulatorScreenState();
}

class _OfdmaSimulatorScreenState extends State<OfdmaSimulatorScreen> {
  late final OfdmaSimulatorModel _model = widget.model ?? OfdmaSimulatorModel();

  @override
  void dispose() {
    if (widget.model == null) _model.dispose();
    super.dispose();
  }

  String? _copyText() {
    final OfdmaResult r = _model.result;
    final StringBuffer b = StringBuffer()
      ..writeln('OFDMA Resource Units (WLAN Pros Toolbox)')
      ..writeln(
        '${_model.widthMhz} MHz, ${_model.clients} clients, '
        '${_model.payloadBytes} bytes each, MCS ${_model.mcs}, 1 SS',
      );
    for (int i = 0; i < _model.clients; i++) {
      final RuSpan? p = _model.placement[i];
      b.writeln(
        '  ${clientLetter(i)}: ${_model.sizes[i].toneLabel} RU'
        '${p == null ? ', not placed' : ', slots ${p.start + 1} to ${p.end}'}',
      );
    }
    for (final OfdmaMode m in OfdmaMode.values) {
      final OfdmaTimeline? t = r.timeline(m);
      b.writeln(
        '${m.label}: '
        '${t == null || t.ppduTooLong ? 'not computed' : '${formatTenthsUs(t.totalTenths)} µs'}',
      );
    }
    for (final OfdmaMode m in <OfdmaMode>[OfdmaMode.dl, OfdmaMode.ul]) {
      final double? x = r.ratio(m);
      if (x != null) {
        b.writeln('SU / ${m.shortLabel}: ${x.toStringAsFixed(2)}x');
      }
    }
    if (!r.check.isOk) b.writeln('Check: ${r.check.message}');
    final String? line = ofdmaSavingsLine(r, _model.direction.mode);
    if (line != null) b.writeln(line);
    b.writeln(
      'Teaching estimate. Assumed: SU Block Acks, HE-SIG-B length, DL block '
      'ack rate, trigger and Multi-STA BlockAck sizes (see the tool).',
    );
    return b.toString().trimRight();
  }

  /// The presenter layout over this screen's model (shared, not copied).
  Widget _presenter(BuildContext context) => PresenterLayout(
    title: _kTitle,
    stage: OfdmaSimulatorStage(model: _model),
    controls: OfdmaSimulatorControls(model: _model),
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
            toolRoute: AppRouter.ofdmaSimulator,
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
                      OfdmaSimulatorStage(model: _model),
                      const SizedBox(height: AppSpacing.md),
                      OfdmaSimulatorControls(model: _model),
                      const SizedBox(height: AppSpacing.md),
                      ListenableBuilder(
                        listenable: _model,
                        builder: (BuildContext context, _) =>
                            OfdmaRuTableCard(widthMhz: _model.widthMhz),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _AssumptionsCard(),
                      const ToolHelpFooter(toolId: kOfdmaSimulatorToolId),
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

/// The RU table: tones, data + pilot, and how many fit at each width. The
/// current width's column is marked.
class OfdmaRuTableCard extends StatelessWidget {
  const OfdmaRuTableCard({super.key, required this.widthMhz});

  final int widthMhz;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextStyle head =
        text.labelMedium?.copyWith(color: colors.textSecondary) ??
        TextStyle(color: colors.textSecondary);
    final TextStyle cell = mono.inlineCode.copyWith(color: colors.textPrimary);
    final TextStyle na = mono.inlineCode.copyWith(color: colors.textTertiary);

    Widget pad(Widget c, {bool on = false}) => Container(
      color: on ? colors.surface2 : null,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxs,
        horizontal: AppSpacing.xxs,
      ),
      child: c,
    );

    return AirtimeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AirtimeSectionTitle('Resource units at a glance'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'How many of each RU fit in each channel width (802.11ax). The '
            '$widthMhz MHz column is the one on screen.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Table(
            // The two text columns take their natural width, so "2x996" and
            // "1960 + 32" never wrap at phone width; counts share the rest.
            columnWidths: const <int, TableColumnWidth>{
              0: IntrinsicColumnWidth(),
              1: IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                children: <Widget>[
                  pad(Text('RU tones', style: head)),
                  pad(Text('Data + pilot', style: head)),
                  for (final int w in OfdmaTonePlan.widthsMhz)
                    pad(
                      Text(
                        '$w',
                        textAlign: TextAlign.end,
                        style: w == widthMhz
                            ? head.copyWith(
                                color: colors.textAccent,
                                fontWeight: FontWeight.w700,
                              )
                            : head,
                        semanticsLabel: '$w MHz',
                      ),
                      on: w == widthMhz,
                    ),
                ],
              ),
              for (final RuSize s in RuSize.values)
                TableRow(
                  children: <Widget>[
                    pad(Text(s.label, style: cell)),
                    pad(Text('${s.dataTones}+${s.pilotTones}', style: cell)),
                    for (final int w in OfdmaTonePlan.widthsMhz)
                      pad(
                        Text(
                          OfdmaTonePlan.count(s, w)?.toString() ?? 'n/a',
                          textAlign: TextAlign.end,
                          style: OfdmaTonePlan.count(s, w) == null ? na : cell,
                        ),
                        on: w == widthMhz,
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Column heads are channel widths in MHz.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
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
            'These values are estimates, not figures from the standard. Each '
            'one is tagged where it appears in the arithmetic.',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          for (final OfdmaAssumption a in OfdmaAssumption.values) ...<Widget>[
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
            'SU timing comes from the Airtime Anatomy tool: HE single-user '
            'PPDU, 0.8 µs guard interval, LDPC, CCMP, 5 or 6 GHz.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
