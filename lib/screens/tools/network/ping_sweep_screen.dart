// Ping Sweep tool — discover responsive hosts on a subnet using the same
// TCP-handshake probe as Ping, run across a range of addresses.
//
// HONESTY NOTE (GL-008 corollary, GL-005): a result means the host RESPONDED
// ON A TCP PORT, not that the host is "up". A host silent on the probed port
// may still be alive (ICMP-only, firewalled port). The form labels the method
// ("TCP-probe sweep") and the results card states the limitation in plain
// language. We never claim ICMP-style liveness.
//
// NO SUBPROCESS: this never spawns /sbin/ping, fping, or nmap. The sweep is the
// PingSweepService's TCP `Socket.connect` probe across the parsed host list.
//
// States (SOP-007 §5):
//  - idle      → form only.
//  - loading   → progress bar + live "scanning N/total", responsive hosts
//                streaming in; Stop button.
//  - success   → responsive hosts listed with RTT + live/total tally.
//  - empty     → sweep finished, no host responded — a valid, informative
//                result (with the honesty caveat), not an error.
//  - error     → blank / malformed spec → "Check your input"; oversized range →
//                an explicit "that's N hosts, cap is M" message (no truncation).
//  - web        → NetworkUnavailableView (brief §15).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/ping_sweep_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class PingSweepScreen extends StatefulWidget {
  const PingSweepScreen({super.key, this.service});

  final PingSweepService? service;

  @override
  State<PingSweepScreen> createState() => _PingSweepScreenState();
}

class _PingSweepScreenState extends State<PingSweepScreen> {
  late final PingSweepService _service;
  final TextEditingController _subnetCtrl = TextEditingController(
    text: '192.168.1.0/24',
  );
  final FocusNode _subnetFocus = FocusNode();

  int _port = PingSweepService.defaultPort;

  bool _sweeping = false;
  String? _error;
  int _completed = 0;
  int _total = 0;
  int _live = 0;
  String _rangeLabel = '';
  final List<SweepHostResult> _responsive = <SweepHostResult>[];

  StreamSubscription<SweepProgress>? _sub;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PingSweepService();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subnetCtrl.dispose();
    _subnetFocus.dispose();
    super.dispose();
  }

  void _start() {
    final SweepSpec spec = PingSweepService.parseSpec(_subnetCtrl.text);
    if (!spec.isValid) {
      setState(() {
        _error = switch (spec.error) {
          SweepSpecError.tooLarge =>
            'That range is ${spec.requestedCount} hosts — the sweep cap is '
                '${PingSweepService.maxHosts} (a /24). Narrow the range, e.g. '
                'a /24 or a base-and-range like 192.168.1.1-50.',
          SweepSpecError.malformed || null =>
            'Enter a subnet in CIDR (192.168.1.0/24) or a range '
                '(192.168.1.1-50).',
        };
      });
      return;
    }

    _subnetFocus.unfocus();
    final Completer<void> cancel = Completer<void>();
    setState(() {
      _error = null;
      _sweeping = true;
      _completed = 0;
      _total = spec.hosts.length;
      _live = 0;
      _rangeLabel = spec.label;
      _responsive.clear();
      _cancel = cancel;
    });

    _sub = _service
        .sweep(spec: spec, ports: <int>[_port], cancel: cancel.future)
        .listen(
          (SweepProgress p) {
            if (!mounted) return;
            setState(() {
              _completed = p.completed;
              _total = p.total;
              _live = p.live;
              if (p.lastResponsive != null) _responsive.add(p.lastResponsive!);
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _sweeping = false);
            // WCAG 4.1.3 — announce the final tally to assistive tech.
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Sweep complete, $_live of $_total '
              'host${_total == 1 ? '' : 's'} responded on TCP $_port',
              TextDirection.ltr,
            );
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _sweeping = false;
              _error = 'Sweep error: $e';
            });
          },
        );
  }

  void _stop() {
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
    setState(() => _sweeping = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ping Sweep'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a sweep has
        // started (a range is in flight). Copies the tally summary + a TSV of
        // the responsive hosts. Copy leads; no help icon on this screen.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the sweep tally plus a TSV of responsive hosts.
  ///
  /// Returns null (→ disabled) until a sweep has begun (`_total > 0`). Mid-run
  /// it copies the partial tally and the responsive hosts found so far (the
  /// §8.16 streaming rule). The service only retains hosts that RESPONDED — it
  /// keeps no per-address list of silent hosts — so the TSV is the responsive
  /// set (State column always "responded"), and the honest caveat that silent
  /// hosts may still be up is carried into the copied text exactly as it is
  /// shown on screen (GL-005). Hosts sort by numeric address, matching the
  /// on-screen order.
  String? _buildCopyText() {
    if (_total == 0) return null;

    final List<SweepHostResult> sorted = List<SweepHostResult>.of(_responsive)
      ..sort(
        (SweepHostResult a, SweepHostResult b) =>
            _ipKey(a.host).compareTo(_ipKey(b.host)),
      );

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ping Sweep — TCP-probe (reachability on a port, not ICMP)')
      ..writeln(
        _rangeLabel.isEmpty ? 'Range: (unknown)' : 'Range: $_rangeLabel',
      )
      ..writeln(
        'Summary: $_live of $_total host${_total == 1 ? '' : 's'} responded '
        'on TCP $_port. A host silent on TCP $_port may still be up.',
      )
      ..writeln()
      ..writeln(<String>['IP', 'State', 'Time (ms)'].join(tab));

    for (final SweepHostResult r in sorted) {
      final String time = r.rttMs == null ? '' : r.rttMs!.toStringAsFixed(1);
      buf.writeln(<String>[r.host, 'responded', time].join(tab));
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.pingSweepSupported) {
      return NetworkUnavailableView(
        toolName: 'Ping Sweep',
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
                  ConceptGraphicBand(
                    toolId: 'ping-sweep',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ping-sweep'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  if (_total > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  if (_total > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _resultsCard(context),
                  ],
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
            label: 'Subnet or range',
            field: TextField(
              controller: _subnetCtrl,
              focusNode: _subnetFocus,
              enabled: !_sweeping,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _sweeping ? null : _start(),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '192.168.1.0/24'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'CIDR (192.168.1.0/24) or a range (192.168.1.1-50). '
            'Capped at ${PingSweepService.maxHosts} hosts (a /24).',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
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
            children: PingSweepService.commonPorts
                .map((int p) => _portChip(context, p))
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'TCP-probe sweep: a host is listed when it answers a TCP '
              'handshake on port $_port. This is reachability on that port — '
              'not ICMP liveness. A host silent on TCP $_port may still be up.',
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
          if (_sweeping)
            OutlinedButton(onPressed: _stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: _start, child: const Text('Sweep')),
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
      // WCAG 2.5.8 / §8.3 — guarantee ≥48dp hit region.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders + 2px lime
      // keyboard-focus ring.
      side: AppTheme.chipSide(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _sweeping ? null : (_) => setState(() => _port = port),
    );
  }

  Widget _progressCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double fraction = _total == 0 ? 0 : _completed / _total;
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
                _sweeping ? 'Scanning…' : 'Sweep complete',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '$_completed / $_total · $_live live',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // WCAG 4.1.3 — a bare progress bar announces nothing. Label it with
          // the live "scanning N/total" state and the running live tally.
          Semantics(
            label: _sweeping
                ? 'Scanning, $_completed of $_total hosts, $_live responded'
                : 'Sweep complete, $_live of $_total '
                      'host${_total == 1 ? '' : 's'} responded',
            liveRegion: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: LinearProgressIndicator(
                value: _sweeping ? fraction : 1.0,
                minHeight: 6,
                backgroundColor: AppColors.surface2,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool finished = !_sweeping && _completed >= _total && _total > 0;
    final bool noneResponded = finished && _responsive.isEmpty;

    // Responsive hosts ascending by numeric address so the list reads as a
    // tidy subnet column rather than arrival order.
    final List<SweepHostResult> sorted = List<SweepHostResult>.of(_responsive)
      ..sort(
        (SweepHostResult a, SweepHostResult b) =>
            _ipKey(a.host).compareTo(_ipKey(b.host)),
      );

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
                'Responsive hosts',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              if (_rangeLabel.isNotEmpty)
                Flexible(
                  child: Text(
                    _rangeLabel,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    // Address-range label is an identifier → Roboto Mono (§8.5).
                    style: mono.robotoMono.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (noneResponded)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No hosts answered on TCP $_port across $_total '
                'address${_total == 1 ? '' : 'es'}. That does not mean the '
                'subnet is empty — hosts that are ICMP-only or that firewall '
                'TCP $_port will not appear. Try another common port.',
                style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
              ),
            )
          else ...[
            ...sorted.map(
              (SweepHostResult r) => _hostRow(context, r, text, mono),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Honesty footer — always present alongside results so a populated
            // list is never read as authoritative liveness.
            Text(
              'Responded on TCP $_port — reachability on that port, not ICMP '
              'liveness. Silent hosts may still be up.',
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hostRow(
    BuildContext context,
    SweepHostResult r,
    TextTheme text,
    AppMonoText mono,
  ) {
    final String rttLabel = r.rttMs == null
        ? '—'
        : '${r.rttMs!.toStringAsFixed(1)} ms';

    // WCAG 1.4.1 — outcome carried by text + icon shape, never color alone.
    // The whole row is one semantic node so AT reads "<host> responded, <rtt>".
    return Semantics(
      label:
          'Host ${r.host} responded on TCP $_port'
          '${r.rttMs == null ? '' : ', ${r.rttMs!.toStringAsFixed(1)} milliseconds'}',
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          // §8.7 named row-padding token (12px) — not hardcoded.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  r.host,
                  // Responsive host IP is an identifier → Roboto Mono (§8.5).
                  // The RTT label stays DM Mono.
                  style: mono.robotoMono.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                rttLabel,
                style: mono.inlineCode.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Numeric sort key for an IPv4 string so 192.168.1.9 sorts before
  /// 192.168.1.10 (a lexical sort would not).
  static int _ipKey(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length != 4) return 0;
    int v = 0;
    for (final String p in parts) {
      v = (v << 8) | (int.tryParse(p) ?? 0);
    }
    return v & 0xFFFFFFFF;
  }
}
