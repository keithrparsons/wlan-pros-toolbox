// Ping tool — TCP-handshake RTT probe with live replies, running stats, and a
// token-only RTT sparkline.
//
// HONESTY NOTE (brief §10): this is a TCP round-trip probe, not ICMP echo.
// The form exposes the target port and the metric is labelled "TCP RTT" so the
// user is never misled. See PingService for the full rationale.
//
// States (SOP-007 §5):
//  - idle      → form only.
//  - loading   → live replies streaming, running min/avg/max/loss, sparkline;
//                Stop button.
//  - success   → run finished with at least one reply; final stats persist.
//  - empty/error→ host blank → inline validation; all probes lost → a clear
//                "no replies — host unreachable on TCP <port>" summary (not a
//                crash, not a bare 0).
//  - web        → NetworkUnavailableView (brief §15).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/ping_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class PingScreen extends StatefulWidget {
  const PingScreen({super.key, this.service});

  final PingService? service;

  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  late final PingService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  int _port = PingService.defaultPort;
  int _count = 10;

  bool _running = false;
  String? _error;
  final List<PingReply> _replies = <PingReply>[];
  PingStats _stats = PingStats.empty;

  StreamSubscription<PingProgress>? _sub;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PingService();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hostCtrl.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  void _start() {
    final String host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'Enter a host or IP to ping.');
      return;
    }

    _hostFocus.unfocus();
    final Completer<void> cancel = Completer<void>();
    setState(() {
      _error = null;
      _running = true;
      _replies.clear();
      _stats = PingStats.empty;
      _cancel = cancel;
    });

    _sub = _service
        .ping(host: host, port: _port, count: _count, cancel: cancel.future)
        .listen(
          (PingProgress p) {
            if (!mounted) return;
            setState(() {
              _replies.add(p.reply);
              _stats = p.stats;
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _running = false);
            // WCAG 4.1.3 — announce the final summary to assistive tech.
            final String avg = _stats.avgMs == null
                ? 'no replies'
                : 'average ${_stats.avgMs!.toStringAsFixed(1)} milliseconds';
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Ping complete, ${_stats.received} of ${_stats.sent} replies, $avg',
              TextDirection.ltr,
            );
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _running = false;
              _error = 'Ping error: $e';
            });
          },
        );
  }

  void _stop() {
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ping'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a run has
        // produced replies; copies the summary stats line + a TSV of replies.
        // Copy leads; this screen has no help icon, so copy is the only action
        // (it still lands in the trailing slot the order rule reserves for it).
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the ping run as a labeled summary plus a reply TSV.
  ///
  /// Returns null (→ disabled affordance) until a run has at least started
  /// sending probes (`_stats.sent > 0`): an idle screen has nothing to keep.
  /// Mid-run, it copies whatever is on screen at tap time — the partial stats
  /// and the replies streamed so far (the §8.16 streaming rule). Replies are
  /// emitted in send order (sequence ascending), the natural reading order,
  /// not the reversed on-screen newest-first order. A lost probe carries its
  /// honest reason word in the Result column (GL-005); nothing is fabricated.
  String? _buildCopyText() {
    if (_stats.sent == 0) return null;

    final String host = _hostCtrl.text.trim();
    final String lossPct = (_stats.lossFraction * 100).toStringAsFixed(0);
    String ms(double? v) => v == null ? '—' : v.toStringAsFixed(1);

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ping — TCP handshake RTT (not ICMP echo)')
      ..writeln('Target: ${host.isEmpty ? '(unknown)' : host}  port $_port')
      ..writeln(
        'Summary: ${_stats.received}/${_stats.sent} replies, $lossPct% loss · '
        'min ${ms(_stats.minMs)} ms / avg ${ms(_stats.avgMs)} ms / '
        'max ${ms(_stats.maxMs)} ms',
      )
      ..writeln()
      ..writeln(<String>['Seq', 'Result', 'Time (ms)'].join(tab));

    final List<PingReply> ordered = List<PingReply>.of(_replies)
      ..sort((PingReply a, PingReply b) => a.sequence.compareTo(b.sequence));
    for (final PingReply r in ordered) {
      final String result = r.success ? 'reply' : (r.errorLabel ?? 'no reply');
      final String time = r.success && r.rtt != null
          ? (r.rtt!.inMicroseconds / 1000.0).toStringAsFixed(1)
          : '';
      buf.writeln(<String>['${r.sequence}', result, time].join(tab));
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.pingSupported) {
      return NetworkUnavailableView(
        toolName: 'Ping',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConceptGraphicBand(toolId: 'ping', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('ping'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  if (_stats.sent > 0 || _running) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _statsCard(context),
                  ],
                  if (_replies.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _repliesCard(context),
                  ],
                  ToolHelpFooter(toolId: 'ping'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabeledField(
            label: 'Host or IP',
            field: TextField(
              controller: _hostCtrl,
              focusNode: _hostFocus,
              enabled: !_running,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _running ? null : _start(),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '1.1.1.1'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'TCP port',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: PingService.commonPorts
                .map((int p) => _portChip(context, p))
                .toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Count',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: const <int>[
              5,
              10,
              20,
              0,
            ].map((int c) => _countChip(context, c)).toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Measures TCP handshake round-trip time to port $_port — a '
              'reachability + latency probe, not ICMP echo.',
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_running)
            OutlinedButton(onPressed: _stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: _start, child: const Text('Ping')),
        ],
      ),
    );
  }

  Widget _portChip(BuildContext context, int port) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = _port == port;
    return ChoiceChip(
      label: Text('$port'),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? AppColors.secondary : AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface2,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders + 2px lime
      // keyboard-focus ring.
      side: AppTheme.chipSide(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _running ? null : (_) => setState(() => _port = port),
    );
  }

  Widget _countChip(BuildContext context, int count) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = _count == count;
    final String label = count == 0 ? 'Until stopped' : '$count';
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? AppColors.secondary : AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface2,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders + 2px lime
      // keyboard-focus ring.
      side: AppTheme.chipSide(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _running ? null : (_) => setState(() => _count = count),
    );
  }

  Widget _statsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String lossPct = (_stats.lossFraction * 100).toStringAsFixed(0);
    final String mn = _stats.minMs == null
        ? '—'
        : _stats.minMs!.toStringAsFixed(1);
    final String av = _stats.avgMs == null
        ? '—'
        : _stats.avgMs!.toStringAsFixed(1);
    final String mx = _stats.maxMs == null
        ? '—'
        : _stats.maxMs!.toStringAsFixed(1);

    final String liveLabel = _running
        ? 'Pinging, ${_stats.received} of ${_stats.sent} replies, '
              '$lossPct percent loss, average $av milliseconds'
        : 'Ping complete, ${_stats.received} of ${_stats.sent} replies, '
              '$lossPct percent loss, average $av milliseconds';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _running ? 'Pinging…' : 'Summary',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '${_stats.received} / ${_stats.sent} · $lossPct% loss',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // WCAG 4.1.3 — the numeric grid below is visual; this live region
          // carries the same facts to AT as they update.
          Semantics(
            label: liveLabel,
            liveRegion: true,
            child: Row(
              children: [
                _statCell(context, mono, 'min', mn),
                _statCell(context, mono, 'avg', av),
                _statCell(context, mono, 'max', mx),
              ],
            ),
          ),
          if (_stats.rttsMs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Sparkline(rttsMs: _stats.rttsMs),
          ],
        ],
      ),
    );
  }

  Widget _statCell(
    BuildContext context,
    AppMonoText mono,
    String label,
    String value,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: mono.outputMedium.copyWith(color: AppColors.primary),
              ),
              const SizedBox(width: 2),
              if (value != '—')
                Text(
                  'ms',
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repliesCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool finished = !_running && _stats.sent > 0;
    final bool noReplies = finished && _stats.received == 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Replies',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (noReplies)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No replies. The host did not answer on TCP $_port — it may be '
                'down, the port may be filtered, or ICMP-only.',
                style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ..._replies.reversed.map(
            (PingReply r) => _replyRow(context, r, text, mono),
          ),
        ],
      ),
    );
  }

  Widget _replyRow(
    BuildContext context,
    PingReply r,
    TextTheme text,
    AppMonoText mono,
  ) {
    // WCAG 1.4.1 — outcome is carried by the text label + icon shape, never
    // color alone. The whole row is one semantic node.
    final (
      Color color,
      IconData icon,
      String value,
      String semantic,
    ) = r.success
        ? (
            AppColors.primary,
            Icons.south_east,
            '${(r.rtt!.inMicroseconds / 1000.0).toStringAsFixed(1)} ms',
            'Reply ${r.sequence}, '
                '${(r.rtt!.inMicroseconds / 1000.0).toStringAsFixed(1)} '
                'milliseconds',
          )
        : (
            AppColors.textTertiary,
            Icons.block,
            r.errorLabel ?? 'lost',
            'Probe ${r.sequence} lost, ${r.errorLabel ?? 'no reply'}',
          );

    return Semantics(
      label: semantic,
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: 40,
                child: Text(
                  '#${r.sequence}',
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.success ? 'reply' : (r.errorLabel ?? 'no reply'),
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                value,
                style: mono.inlineCode.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RTT sparkline — token-only (lime line on surface2), decorative for AT (the
/// numeric min/avg/max + live region already carry the data). Renders the
/// successful RTTs as a normalized polyline so trends are visible at a glance.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.rttsMs});

  final List<double> rttsMs;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          height: 56,
          width: double.infinity,
          color: AppColors.surface2,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: CustomPaint(painter: _SparklinePainter(rttsMs)),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.rttsMs);

  final List<double> rttsMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (rttsMs.isEmpty) return;
    double mn = rttsMs.first;
    double mx = rttsMs.first;
    for (final double v in rttsMs) {
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    final double range = (mx - mn).abs() < 1e-9 ? 1 : (mx - mn);

    final int n = rttsMs.length;
    final double dx = n == 1 ? 0 : size.width / (n - 1);

    final Path path = Path();
    for (int i = 0; i < n; i++) {
      final double x = n == 1 ? size.width / 2 : i * dx;
      // Invert Y: lower RTT = higher on the chart.
      final double norm = (rttsMs[i] - mn) / range;
      final double y = size.height - (norm * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final Paint line = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Single point: draw a dot so one reply isn't an invisible empty chart.
    if (n == 1) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        2.5,
        Paint()..color = AppColors.primary,
      );
      return;
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.rttsMs.length != rttsMs.length;
}
