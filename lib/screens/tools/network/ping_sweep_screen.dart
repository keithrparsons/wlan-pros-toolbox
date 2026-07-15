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
import '../../../services/network/current_network.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/ping_sweep_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class PingSweepScreen extends StatefulWidget {
  const PingSweepScreen({super.key, this.service, this.network});

  final PingSweepService? service;

  /// Injectable current-network helper (Wave 2 prefill). Null in production →
  /// the real CurrentNetwork(); tests pass a stub reader so the prefill is
  /// exercised with no device.
  final CurrentNetwork? network;

  @override
  State<PingSweepScreen> createState() => _PingSweepScreenState();
}

class _PingSweepScreenState extends State<PingSweepScreen> {
  late final PingSweepService _service;
  late final CurrentNetwork _network;

  /// The generic fallback default, kept when the device network is unknown
  /// (the honest NONE case). A real subnet replaces it once measured.
  static const String _defaultSubnet = '192.168.1.0/24';

  final TextEditingController _subnetCtrl = TextEditingController(
    text: _defaultSubnet,
  );
  final FocusNode _subnetFocus = FocusNode();

  /// True once the user edits the field — the prefill must never clobber a
  /// user-typed value (spec: suggestion, not a lock).
  bool _userTouched = false;

  /// Guards our own programmatic prefill from being mistaken for a user edit.
  bool _applyingPrefill = false;

  /// True only when the field was prefilled with an ASSUMED /24 (PARTIAL case:
  /// IP known, real mask not). Drives the visible "assumed /24" honesty hint.
  /// Never true for a measured CIDR (BEST) — that would fabricate authority.
  bool _maskAssumed = false;

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
    _network = widget.network ?? CurrentNetwork();
    _subnetCtrl.addListener(_onSubnetChanged);
    _prefillFromCurrentNetwork();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subnetCtrl.removeListener(_onSubnetChanged);
    _subnetCtrl.dispose();
    _subnetFocus.dispose();
    super.dispose();
  }

  /// Any change to the field that did NOT come from our own prefill means the
  /// user has taken over — stop suggesting and drop the assumption hint (it
  /// described the prefilled value, which no longer stands).
  void _onSubnetChanged() {
    if (_applyingPrefill) return;
    if (!_userTouched || _maskAssumed) {
      setState(() {
        _userTouched = true;
        _maskAssumed = false;
      });
    }
  }

  /// Prefill the subnet field with the device's REAL network when we can
  /// measure it. Honest-null: BEST → the true CIDR (no hint); PARTIAL → an
  /// assumed /24 (with the hint); NONE → leave the generic default untouched.
  /// Never overwrites a value the user already typed.
  Future<void> _prefillFromCurrentNetwork() async {
    final NetworkSuggestion s = await _network.suggest();
    if (!mounted || _userTouched) return;
    if (s.cidr == null) return; // NONE — keep the generic default, no fabrication.

    _applyingPrefill = true;
    _subnetCtrl.text = s.cidr!;
    _subnetCtrl.selection =
        TextSelection.collapsed(offset: s.cidr!.length);
    _applyingPrefill = false;

    setState(() => _maskAssumed = s.isAssumedPrefix);
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
              'host${_total == 1 ? '' : 's'} answered on TCP $_port',
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
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the sweep tally plus a TSV of responsive hosts.
  ///
  /// Returns null (→ disabled) until a sweep has begun (`_total > 0`). Mid-run
  /// it copies the partial tally and the responsive hosts found so far (the
  /// §8.16 streaming rule). The service only retains hosts that ANSWERED — it
  /// keeps no per-address list of silent hosts — so the TSV is the responsive
  /// set. The State column names HOW each host answered ("answered (handshake)"
  /// vs "answered (refused)"), matching the on-screen rows, and the report
  /// carries its own Method line defining "responded" plus the caveat that
  /// silent hosts may still be up (GL-005). Hosts sort by numeric address,
  /// matching the on-screen order.
  ///
  /// The Method line and the split count are NOT decoration. A middlebox that
  /// RSTs on behalf of every address in the range would otherwise paste as
  /// "254 of 254 hosts responded" — the exact string that started this
  /// investigation — with nothing to distinguish it from 254 live web servers.
  /// The pasted report is the permanent record, read by someone who never saw
  /// the screen; it has to define its own terms.
  String? _buildCopyText() {
    if (_total == 0) return null;

    final List<SweepHostResult> sorted = List<SweepHostResult>.of(_responsive)
      ..sort(
        (SweepHostResult a, SweepHostResult b) =>
            _ipKey(a.host).compareTo(_ipKey(b.host)),
      );

    final int refusedCount =
        sorted.where((SweepHostResult r) => r.refused).length;
    final int handshakeCount = sorted.length - refusedCount;

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ping Sweep — TCP-probe (reachability on a port, not ICMP)')
      ..writeln(
        _rangeLabel.isEmpty ? 'Range: (unknown)' : 'Range: $_rangeLabel',
      )
      ..writeln(
        'Summary: $_live of $_total host${_total == 1 ? '' : 's'} answered '
        'on TCP $_port '
        '($handshakeCount by completing the handshake, '
        '$refusedCount by actively refusing).',
      )
      ..writeln(
        'Method: a host is listed when it ANSWERS. Both a completed handshake '
        'and an active refusal (RST) count — a refusal proves the host is '
        'there, it just is not listening on TCP $_port. Silence is not an '
        'answer: hosts that never replied are not listed, though a host silent '
        'on TCP $_port may still be up. This is reachability on one port, not '
        'ICMP liveness.',
      )
      ..writeln()
      ..writeln(<String>['IP', 'State', 'Time (ms)'].join(tab));

    for (final SweepHostResult r in sorted) {
      final String time = r.rttMs == null ? '' : r.rttMs!.toStringAsFixed(1);
      final String state =
          r.refused ? 'answered (refused)' : 'answered (handshake)';
      buf.writeln(<String>[r.host, state, time].join(tab));
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
                  ToolHelpFooter(toolId: 'ping-sweep'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
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
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: '192.168.1.0/24'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'CIDR (192.168.1.0/24) or a range (192.168.1.1-50). '
            'Capped at ${PingSweepService.maxHosts} hosts (a /24).',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          // Honest-null hint (GL-005): only shown when the field was prefilled
          // with an ASSUMED /24 — we had the device IP but not a real mask, so
          // the prefix is a guess, not a measurement. Never shown for a measured
          // CIDR. Presenting an assumed /24 as measured is the exact small lie
          // the 1.7.1 audit removed.
          if (_maskAssumed) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    'Assumed /24 — edit if your network is wider.',
                    style: text.labelSmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'TCP port',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
              'TCP-probe sweep: a host is listed when it ANSWERS on port '
              '$_port, either by completing the TCP handshake or by actively '
              'refusing it. Both prove the host replied. Silence does not, so '
              'a host that never answers is not listed. This is reachability '
              'on that port, not ICMP liveness: a host silent on TCP $_port '
              'may still be up.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = _port == port;
    return ChoiceChip(
      label: Text('$port'),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? colors.onPrimary : colors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: colors.primary,
      backgroundColor: colors.surface2,
      // WCAG 2.5.8 / §8.3 — guarantee ≥48dp hit region.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders + 2px lime
      // keyboard-focus ring.
      side: AppTheme.chipSide(Theme.of(context).brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _sweeping ? null : (_) => setState(() => _port = port),
    );
  }

  Widget _progressCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final double fraction = _total == 0 ? 0 : _completed / _total;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
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
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '$_completed / $_total · $_live live',
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // WCAG 4.1.3 — a bare progress bar announces nothing. Label it with
          // the live "scanning N/total" state and the running live tally.
          Semantics(
            label: _sweeping
                ? 'Scanning, $_completed of $_total hosts, $_live answered'
                : 'Sweep complete, $_live of $_total '
                      'host${_total == 1 ? '' : 's'} answered',
            liveRegion: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: LinearProgressIndicator(
                value: _sweeping ? fraction : 1.0,
                minHeight: 6,
                backgroundColor: colors.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  colors.textAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
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
                  color: colors.textSecondary,
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
                      color: colors.textTertiary,
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
                // No em dash (GL-004 P0, [[feedback_no_em_dashes]]): this string is
                // published in Keith's voice and is reproduced verbatim on a
                // LinkedIn graphic. The point of the sentence is that SILENCE IS
                // NOT PROOF OF ABSENCE, and it must survive the rewrite intact.
                'No hosts answered on TCP $_port across $_total '
                'address${_total == 1 ? '' : 'es'}. That does not mean the '
                'subnet is empty. Hosts that are ICMP-only, or that firewall '
                'TCP $_port, will not appear. Try another common port.',
                style: text.bodyLarge?.copyWith(color: colors.textTertiary),
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
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
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
    final AppColorScheme colors = context.colors;
    final String rttLabel = r.rttMs == null
        ? '—'
        : '${r.rttMs!.toStringAsFixed(1)} ms';

    // HOW the host answered. A refusal counts as responded (correct — a RST
    // proves the host is there), but the user must be able to SEE that it was a
    // refusal, not a listening service. Otherwise a middlebox RSTing for the
    // whole range renders as a screen full of indistinguishable green ticks.
    // This label is the on-screen twin of the copy-report's State column.
    final bool refused = r.refused;
    final String stateLabel = refused ? 'refused' : 'handshake';

    // WCAG 1.4.1 — outcome carried by text + icon SHAPE, never color alone.
    // The whole row is one semantic node so AT reads the full outcome.
    return Semantics(
      label: 'Host ${r.host} answered on TCP $_port by '
          '${refused ? 'actively refusing (port closed, host is there)' : 'completing the handshake'}'
          '${r.rttMs == null ? '' : ', ${r.rttMs!.toStringAsFixed(1)} milliseconds'}',
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          // §8.7 named row-padding token (12px) — not hardcoded.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            children: [
              Icon(
                // Distinct SHAPE per outcome, not a color swap (WCAG 1.4.1).
                refused ? Icons.block : Icons.check_circle,
                size: 16,
                color: refused ? colors.textSecondary : colors.textAccent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  r.host,
                  // Responsive host IP is an identifier → Roboto Mono (§8.5).
                  // The RTT label stays DM Mono.
                  style: mono.robotoMono.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                stateLabel,
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                rttLabel,
                style: mono.inlineCode.copyWith(
                  color: colors.textAccent,
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
