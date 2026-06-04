// Traceroute tool — hop-by-hop path discovery via the system traceroute.
//
// Desktop-full / mobile-limited by design (see TracerouteService for the full
// rationale). The capability is stated plainly in the UI, never faked:
//   - macOS / Windows / Linux: live hops stream in, cancellable.
//   - iOS / Android: a clear "Traceroute runs on desktop — use Ping here"
//     state (TracerouteUnavailableReason.unsupportedPlatform).
//   - sandbox denial / missing binary on desktop: an explicit
//     "could not launch the system traceroute" state with the detail.
//   - web: NetworkUnavailableView (brief §15).
//
// States (SOP-007 §5):
//  - idle      → form only (desktop) / platform notice (mobile).
//  - loading   → hops appearing as discovered; Stop button.
//  - success   → full path; "reached target" or "stopped at N hops".
//  - empty/error→ host blank → inline validation; unavailable verdicts above.
//  - web        → NetworkUnavailableView.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/traceroute_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class TracerouteScreen extends StatefulWidget {
  const TracerouteScreen({super.key, this.service});

  final TracerouteService? service;

  @override
  State<TracerouteScreen> createState() => _TracerouteScreenState();
}

class _TracerouteScreenState extends State<TracerouteScreen> {
  late final TracerouteService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  bool _running = false;
  String? _error;
  final List<TracerouteHop> _hops = <TracerouteHop>[];
  TracerouteResult? _result;

  StreamSubscription<TracerouteEvent>? _sub;
  Completer<void>? _cancel;

  /// Runtime capability probe result. null while the probe is in flight,
  /// then true (this build can launch the system traceroute) or false (the
  /// build cannot — e.g. the sandboxed macOS App Store build). On mobile the
  /// probe is never run; the platform notice handles that case.
  bool? _launchable;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? TracerouteService();
    _probeLaunchable();
  }

  /// Probes whether this build can actually spawn the system traceroute, so the
  /// screen can show upfront guidance instead of letting the user type a target
  /// and hit a sandbox wall on Run. Only meaningful on a supported (desktop)
  /// platform; mobile is handled by the platform notice.
  Future<void> _probeLaunchable() async {
    if (!_service.isSupportedPlatform) return;
    final bool launchable = await _service.isLaunchable();
    if (!mounted) return;
    setState(() => _launchable = launchable);
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
      setState(() => _error = 'Enter a host or IP to trace.');
      return;
    }

    _hostFocus.unfocus();
    final Completer<void> cancel = Completer<void>();
    setState(() {
      _error = null;
      _running = true;
      _hops.clear();
      _result = null;
      _cancel = cancel;
    });

    _sub = _service
        .trace(host: host, cancel: cancel.future)
        .listen(
          (TracerouteEvent e) {
            if (!mounted) return;
            setState(() {
              if (e.hop != null) {
                _hops.add(e.hop!);
              } else if (e.result != null) {
                _result = e.result;
                _running = false;
              }
            });
            if (e.result != null) _announce(e.result!);
          },
          onDone: () {
            if (!mounted) return;
            if (_running) setState(() => _running = false);
          },
          onError: (Object err) {
            if (!mounted) return;
            setState(() {
              _running = false;
              _error = 'Traceroute error: $err';
            });
          },
        );
  }

  void _announce(TracerouteResult result) {
    final String msg = switch (result) {
      TracerouteComplete(:final bool reachedTarget) =>
        reachedTarget
            ? 'Traceroute complete, target reached in ${_hops.length} hops'
            : 'Traceroute finished at ${_hops.length} hops without reaching '
                  'the target',
      TracerouteCancelled() => 'Traceroute stopped',
      TracerouteUnavailable() => 'Traceroute not available on this platform',
    };
    SemanticsService.sendAnnouncement(View.of(context), msg, TextDirection.ltr);
  }

  void _stop() {
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traceroute (System)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until hops exist
        // (so it stays disabled in the capability-probe, mobile-notice, and
        // unavailable states, which produce no hops). Copies a hop TSV with a
        // status header. Copy leads; no help icon on this screen.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the discovered path as a hop TSV with a status line.
  ///
  /// Returns null (→ disabled) until at least one hop exists; that also keeps
  /// it disabled across every unavailable state (mobile notice, sandboxed
  /// build, capability probe), none of which produce hops. Mid-run it copies
  /// the hops streamed so far (the §8.16 streaming rule). A timed-out hop is
  /// written honestly as "no response" with a "*" time (GL-005), matching the
  /// on-screen row; the status header carries the reached/stopped verdict WORD.
  String? _buildCopyText() {
    if (_hops.isEmpty) return null;

    final String host = _hostCtrl.text.trim();
    final String status;
    if (_running) {
      status = 'Tracing… ${_hops.length} hops so far';
    } else if (_result case TracerouteComplete(:final bool reachedTarget)) {
      status = reachedTarget
          ? 'Reached target in ${_hops.length} hops'
          : 'Stopped at ${_hops.length} hops, target not reached';
    } else if (_result is TracerouteCancelled) {
      status = 'Stopped at ${_hops.length} hops';
    } else {
      status = '${_hops.length} hops';
    }

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln(
        'Traceroute (system) — path to '
        '${host.isEmpty ? '(unknown)' : host}',
      )
      ..writeln('Status: $status')
      ..writeln()
      ..writeln(<String>['Hop', 'Host / IP', 'Time (ms)'].join(tab));

    for (final TracerouteHop h in _hops) {
      final String addr = h.timedOut
          ? 'no response'
          : (h.host != null && h.host != h.ip
                ? '${h.host} (${h.ip})'
                : (h.ip ?? '—'));
      final String time = h.timedOut
          ? '*'
          : (h.bestRttMs == null ? '—' : h.bestRttMs!.toStringAsFixed(1));
      buf.writeln(<String>['${h.ttl}', addr, time].join(tab));
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.tracerouteSupported) {
      return NetworkUnavailableView(
        toolName: 'Traceroute',
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
                children: _service.isSupportedPlatform
                    ? _desktopChildren(context, isDesktop)
                    : <Widget>[_mobileNotice(context)],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _desktopChildren(BuildContext context, bool isDesktop) {
    final List<Widget> head = <Widget>[
      ConceptGraphicBand(toolId: 'traceroute', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('traceroute'))
        const SizedBox(height: AppSpacing.md),
    ];

    // Capability probe still in flight — a brief loading state, never the form.
    if (_launchable == null) {
      return <Widget>[
        ...head,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: Semantics(
              label: 'Checking traceroute availability',
              child: const CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
        ),
      ];
    }

    // This build cannot launch the system traceroute (e.g. the sandboxed App
    // Store build). Show upfront guidance instead of an input + button that
    // would only fail on Run. Rendered through NetworkUnavailableView, the
    // same surface the web state uses, so an expected platform limit reads as
    // a normal "not available" state, not an error. (GL-005 / GL-008: name
    // why, name which builds do work, point to a real alternative here.)
    if (_launchable == false) {
      return <Widget>[
        ...head,
        const NetworkUnavailableView(
          toolName: 'Traceroute',
          reason: NetworkUnavailableReason.platformApiMissing,
          icon: Icons.route_outlined,
          headline: 'Traceroute is not available in this build',
          message:
              'The macOS App Store build runs in a sandbox that blocks '
              'launching the system traceroute. It works on Windows, and on '
              'the direct-download macOS build. For a path test on this '
              'machine, use Ping (TCP) or the Network Quality reachability '
              'table.',
        ),
      ];
    }

    // Launchable: the normal form + results flow.
    return <Widget>[
      ...head,
      _formCard(context),
      if (_hops.isNotEmpty || _running) ...[
        const SizedBox(height: AppSpacing.sm),
        _hopsCard(context),
      ],
      // Safety net: the probe said launchable, but a specific run can still
      // come back with an unavailable verdict (e.g. a transient denial).
      if (_result is TracerouteUnavailable) ...[
        const SizedBox(height: AppSpacing.sm),
        _unavailableCard(context, _result! as TracerouteUnavailable),
      ],
      // §8.16.1 — per-tool help footer at the end of the scroll body.
      const ToolHelpFooter(toolId: 'traceroute'),
    ];
  }

  Widget _mobileNotice(BuildContext context) {
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
              const Icon(
                Icons.route_outlined,
                size: 24,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Traceroute runs on desktop',
                  style: text.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Mapping the hops to a host needs the operating system traceroute, '
            'which mobile sandboxes do not expose to apps. Run Traceroute from '
            'the macOS or Windows build. On this device, use Ping to measure '
            'reachability and latency to the target.',
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
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
              decoration: const InputDecoration(hintText: 'example.com'),
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
            FilledButton(onPressed: _start, child: const Text('Trace')),
        ],
      ),
    );
  }

  Widget _hopsCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    String header;
    if (_running) {
      header = 'Tracing… ${_hops.length} hops';
    } else if (_result case TracerouteComplete(:final bool reachedTarget)) {
      header = reachedTarget
          ? 'Reached target · ${_hops.length} hops'
          : 'Stopped at ${_hops.length} hops · target not reached';
    } else if (_result is TracerouteCancelled) {
      header = 'Stopped · ${_hops.length} hops';
    } else {
      header = '${_hops.length} hops';
    }

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
          Semantics(
            liveRegion: true,
            label: header,
            child: Text(
              header,
              style: text.labelMedium?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._hops.map((TracerouteHop h) => _hopRow(context, h, text, mono)),
        ],
      ),
    );
  }

  Widget _hopRow(
    BuildContext context,
    TracerouteHop h,
    TextTheme text,
    AppMonoText mono,
  ) {
    final String rttLabel = h.timedOut
        ? '*'
        : (h.bestRttMs == null ? '—' : '${h.bestRttMs!.toStringAsFixed(1)} ms');
    final String addr = h.timedOut
        ? 'no response'
        : (h.host != null && h.host != h.ip
              ? '${h.host}  (${h.ip})'
              : (h.ip ?? '—'));

    final String semantic = h.timedOut
        ? 'Hop ${h.ttl}, no response'
        : 'Hop ${h.ttl}, ${h.ip ?? 'unknown'}, $rttLabel';

    return Semantics(
      label: semantic,
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${h.ttl}',
                  style: mono.inlineCode.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  addr,
                  // Hop address (hostname + IP) is an identifier → Roboto Mono
                  // (GL-003 §8.5). TTL counter and RTT stay DM Mono.
                  style: h.timedOut
                      ? text.bodyLarge?.copyWith(
                          color: AppColors.textTertiary,
                          fontStyle: FontStyle.italic,
                        )
                      : mono.robotoMono.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                rttLabel,
                style: mono.inlineCode.copyWith(
                  color: h.timedOut
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unavailableCard(BuildContext context, TracerouteUnavailable u) {
    final TextTheme text = Theme.of(context).textTheme;
    final String body = switch (u.reason) {
      TracerouteUnavailableReason.unsupportedPlatform =>
        'Traceroute runs on desktop only — use Ping on this device.',
      TracerouteUnavailableReason.binaryUnavailable =>
        'The system traceroute could not be launched here. On a sandboxed '
            'build the OS may block it.${u.detail == null ? '' : '\n\n${u.detail}'}',
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 20,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Traceroute unavailable',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
