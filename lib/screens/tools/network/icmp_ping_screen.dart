// Real ICMP Ping tool — genuine ICMP echo request/reply, the documented
// fast-follow to the TCP-handshake Ping (ping_screen.dart, which remains the
// desktop path). Built on the shared IcmpService foundation.
//
// HONESTY (GL-005 + GL-008): the metric is labelled "ICMP echo" everywhere, in
// contrast to the TCP Ping screen which labels itself "TCP-handshake probe (not
// ICMP)". The two tools are deliberately distinct and cross-reference each
// other so the user always knows which primitive they are running.
//
// PLATFORM MATRIX (surfaced honestly, never faked):
//   - iOS / Android:  real ICMP echo via the native backend.
//                     ⚠️ DEVICE-PENDING: the native ICMP path cannot be
//                     verified in this environment; the backend throws until a
//                     device pass wires dart_ping. The UI states this plainly.
//   - macOS/desktop:  ICMP needs a subprocess the App Sandbox blocks → honest
//                     "not available in the sandboxed desktop build" card that
//                     points the user at the TCP Ping tool.
//   - web:            NetworkUnavailableView.
//
// States (SOP-007 §5): idle · loading (live replies + running stats) · success
// · empty/error (blank host inline; all-lost summary) · platform-unavailable.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../router/app_router.dart';
import '../../../services/network/dart_ping_icmp_backend.dart';
import '../../../services/network/icmp_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'network_unavailable_view.dart';

class IcmpPingScreen extends StatefulWidget {
  const IcmpPingScreen({super.key, this.service});

  /// Injected in tests. In production this is null and the screen builds an
  /// [IcmpService] with the real backend on supported native targets
  /// ([defaultIcmpBackend]) — null on web/desktop, where the capability gate
  /// routes to the unavailable/sandboxed-desktop state before any run.
  final IcmpService? service;

  @override
  State<IcmpPingScreen> createState() => _IcmpPingScreenState();
}

class _IcmpPingScreenState extends State<IcmpPingScreen> {
  late final IcmpService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  int _count = 10;

  bool _running = false;
  String? _error;
  final List<IcmpReply> _replies = <IcmpReply>[];
  IcmpStats _stats = IcmpStats.empty;

  StreamSubscription<IcmpProgress>? _sub;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? IcmpService(backend: defaultIcmpBackend());
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
    final String? invalid = IcmpService.validateHost(host);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    _hostFocus.unfocus();
    final Completer<void> cancel = Completer<void>();
    setState(() {
      _error = null;
      _running = true;
      _replies.clear();
      _stats = IcmpStats.empty;
      _cancel = cancel;
    });

    _sub = _service
        .ping(host: host, count: _count, cancel: cancel.future)
        .listen(
      (IcmpProgress p) {
        if (!mounted) return;
        setState(() {
          _replies.add(p.reply);
          _stats = p.stats;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _running = false);
        final String avg = _stats.avgMs == null
            ? 'no replies'
            : 'average ${_stats.avgMs!.toStringAsFixed(1)} milliseconds';
        SemanticsService.sendAnnouncement(
          View.of(context),
          'ICMP ping complete, ${_stats.received} of ${_stats.sent} replies, '
          '$avg',
          TextDirection.ltr,
        );
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          // The device-pending backend throws an explanatory StateError; show
          // it verbatim rather than a generic failure (honesty bar).
          _error = e is StateError ? e.message : 'ICMP ping error: $e';
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
      appBar: AppBar(title: const Text('ICMP Ping'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (!NetworkSupport.icmpPingSupported) {
      return NetworkUnavailableView(
        toolName: 'ICMP Ping',
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
                children: _service.echoCapability ==
                        IcmpEchoCapability.sandboxedDesktop
                    ? <Widget>[_sandboxedDesktopCard(context)]
                    : _availableChildren(context),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _availableChildren(BuildContext context) {
    return <Widget>[
      _formCard(context),
      if (_stats.sent > 0 || _running) ...[
        const SizedBox(height: AppSpacing.sm),
        _statsCard(context),
      ],
      if (_replies.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        _repliesCard(context),
      ],
    ];
  }

  /// Honest desktop state: real ICMP needs a subprocess the macOS App Sandbox
  /// blocks (GL-008). Point the user at the TCP Ping tool, which IS the desktop
  /// reachability/latency path.
  Widget _sandboxedDesktopCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined,
                  size: 24, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'ICMP ping runs on mobile',
                  style:
                      text.headlineSmall?.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A real ICMP echo on this desktop build needs the system ping '
            'binary, which the macOS App Sandbox blocks for distributed apps. '
            'Use the TCP Ping tool here — it measures reachability and '
            'round-trip latency over a TCP handshake (not ICMP). Run ICMP Ping '
            'from the iOS or Android build.',
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: 'Open the TCP Ping tool',
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRouter.ping),
                icon: const Icon(Icons.network_ping, size: 18),
                label: const Text('Open TCP Ping'),
              ),
            ),
          ),
        ],
      ),
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
          Text(
            'Host or IP',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
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
            children: const <int>[5, 10, 20, 0]
                .map((int c) => _countChip(context, c))
                .toList(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Sends ICMP echo requests and measures the echo-reply round-trip '
              'time — true ICMP, not a TCP probe.',
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          _devicePendingNote(context),
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

  /// Honest disclosure that the native ICMP layer is not yet device-verified.
  /// Never claims it works; tells the user exactly what state the build is in.
  Widget _devicePendingNote(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Uses the device\'s real ICMP echo. The native path is wired but '
              'still pending on-device verification; if it cannot run, a run '
              'reports that plainly rather than showing made-up results.',
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
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
      side: BorderSide(
        color: selected ? AppColors.primary : AppColors.borderStrong,
        width: 1,
      ),
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
    final String mn =
        _stats.minMs == null ? '—' : _stats.minMs!.toStringAsFixed(1);
    final String av =
        _stats.avgMs == null ? '—' : _stats.avgMs!.toStringAsFixed(1);
    final String mx =
        _stats.maxMs == null ? '—' : _stats.maxMs!.toStringAsFixed(1);

    final String liveLabel = _running
        ? 'Pinging by ICMP, ${_stats.received} of ${_stats.sent} replies, '
            '$lossPct percent loss, average $av milliseconds'
        : 'ICMP ping complete, ${_stats.received} of ${_stats.sent} replies, '
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
                _running ? 'ICMP echo…' : 'Summary',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '${_stats.received} / ${_stats.sent} · $lossPct% loss',
                style:
                    text.labelMedium?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
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
                  style: text.labelSmall
                      ?.copyWith(color: AppColors.textTertiary),
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
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No replies. The host did not answer the ICMP echo — it may be '
                'down, or ICMP may be filtered on the path.',
                style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ..._replies.reversed
              .map((IcmpReply r) => _replyRow(context, r, text, mono)),
        ],
      ),
    );
  }

  Widget _replyRow(
    BuildContext context,
    IcmpReply r,
    TextTheme text,
    AppMonoText mono,
  ) {
    // WCAG 1.4.1 — outcome carried by text + icon shape, never colour alone.
    final (Color color, IconData icon, String value, String semantic) =
        r.success
            ? (
                AppColors.primary,
                Icons.south_east,
                r.rttMs == null ? 'reply' : '${r.rttMs!.toStringAsFixed(1)} ms',
                'Reply ${r.sequence}, '
                    '${r.rttMs == null ? 'no time' : '${r.rttMs!.toStringAsFixed(1)} milliseconds'}',
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
          // Shared row-padding token (GL-003 §8.7) for tool-result rows.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: 40,
                child: Text(
                  '#${r.sequence}',
                  style: mono.inlineCode
                      .copyWith(color: AppColors.textTertiary),
                ),
              ),
              Expanded(
                child: Text(
                  r.success ? 'reply' : (r.errorLabel ?? 'no reply'),
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              Text(
                value,
                style: mono.inlineCode
                    .copyWith(color: color, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
