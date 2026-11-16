// PortCheckScreen: "What This Network Lets Out". Tap to run; nothing runs when
// the screen opens, and nothing runs in the background (Keith, 16 NOV). Every
// verdict comes from the pure [judgePortCheck]; this file only lays it out.
//
// Status is a glyph plus a WORD from the triage ladder's set, never color alone.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/network/analyze/triage_ladder.dart' show TriageStatus;
import '../../../services/network/port_check_service.dart';
import '../../../services/network/port_check_verdict.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/tool_help_footer.dart';

/// A second tap within this window is ignored: the check opens about 20
/// connections to third parties and is not for retry loops.
const Duration kPortCheckCooldown = Duration(seconds: 10);

class PortCheckScreen extends StatefulWidget {
  const PortCheckScreen({super.key, this.service, this.signInNeeded = false});

  final PortCheckService? service;

  /// True when Check My Connection saw a sign-in (captive portal) page. Every
  /// non-web port reads blocked before sign-in, so the run is skipped.
  final bool signInNeeded;

  @override
  State<PortCheckScreen> createState() => _PortCheckScreenState();
}

class _PortCheckScreenState extends State<PortCheckScreen> {
  late final PortCheckService _service = widget.service ?? PortCheckService();
  PortCheckReport? _report;
  DateTime? _checkedAt;
  bool _busy = false;
  Timer? _cooldown;

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final PortCheckReport report = widget.signInNeeded
        ? judgePortCheck(<PortCheckTarget, TargetOutcome>{}, signInNeeded: true)
        : judgePortCheck(await _service.run());
    if (!mounted) return;
    setState(() {
      _report = report;
      _checkedAt = DateTime.now();
    });
    _cooldown = Timer(kPortCheckCooldown, () {
      if (mounted) setState(() => _busy = false);
    });
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  String? _copyText() {
    final PortCheckReport? report = _report;
    if (report == null) return null;
    final StringBuffer out = StringBuffer(
      'What this network lets out, checked ${_clock(_checkedAt!)}\n',
    );
    for (final PortCheckGroup g in report.groups) {
      out.writeln('${g.name}: ${g.status.word}');
      for (final String d in g.details) {
        out.writeln('  $d');
      }
    }
    out.write(report.summary);
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final PortCheckReport? report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('What This Network Lets Out'),
        toolbarHeight: 64,
        actions: <Widget>[AppCopyAction(textBuilder: _copyText)],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenEdgeMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'This opens connections to well-known mail, SSH, DNS and '
                    'time servers to see which ones this network lets out. It '
                    'sends no mail and no data. It takes about 4 seconds.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _busy ? null : _run,
                    child: Text(report == null ? 'Run the check' : 'Run again'),
                  ),
                  if (report != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    _ResultsCard(
                      report: report,
                      checkedAt: _clock(_checkedAt!),
                    ),
                  ],
                  const ToolHelpFooter(toolId: 'egress-check'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultsCard extends StatelessWidget {
  const _ResultsCard({required this.report, required this.checkedAt});

  final PortCheckReport report;
  final String checkedAt;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Checked $checkedAt',
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          for (final PortCheckGroup g in report.groups) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _GroupRow(group: g),
          ],
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              report.summary,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});

  final PortCheckGroup group;

  static StatusChipKind _kind(TriageStatus s) => switch (s) {
    TriageStatus.looksFine => StatusChipKind.good,
    TriageStatus.looksOff => StatusChipKind.issue,
    _ => StatusChipKind.info,
  };

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Semantics(
      container: true,
      label: '${group.name}, ${group.status.word}. ${group.details.join(' ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: <Widget>[
                Text(
                  group.name,
                  style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                ),
                StatusChip(kind: _kind(group.status), word: group.status.word),
              ],
            ),
            for (final String d in group.details)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  d,
                  style: text.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
