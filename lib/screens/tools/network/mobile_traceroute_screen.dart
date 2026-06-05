// Mobile Traceroute tool — hop-by-hop path discovery via an ICMP TTL-walk on
// the shared IcmpService foundation. Extends the desktop-only system
// Traceroute (traceroute_screen.dart, left untouched) to mobile *only where the
// platform genuinely supports it*.
//
// HONESTY (GL-005 + GL-008) — the method is labelled "ICMP TTL-walk", distinct
// from the desktop tool's "system traceroute". The per-platform capability is
// surfaced exactly, never faked:
//
//   - Android:  TTL-walk feasible — the system ping surfaces the responding hop
//               on TimeExceeded, so each TTL names a router.
//               ⚠️ DEVICE-PENDING: the native ICMP path is wired (dart_ping);
//               live round-trip is device-pending — unverifiable in this
//               environment, to be confirmed on a device pass. The UI states
//               this plainly.
//   - iOS:      ICMP echo works, but the iOS ICMP layer (GBPing) only accepts
//               EchoReply and drops TimeExceeded, so a TTL-walk cannot name
//               intermediate hops. Honest "not available on iOS" card → use the
//               desktop Traceroute. NOT faked from echo timing.
//   - desktop:  the system Traceroute tool is the desktop path; this ICMP
//               TTL-walk is sandboxed out. Card points at the system tool.
//   - web:      NetworkUnavailableView.
//
// States (SOP-007 §5): idle · loading (hops appearing) · success (path; reached
// or stopped) · empty/error (blank host inline) · platform-unavailable.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../router/app_router.dart';
import '../../../services/network/dart_ping_icmp_backend.dart';
import '../../../services/network/icmp_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class MobileTracerouteScreen extends StatefulWidget {
  const MobileTracerouteScreen({super.key, this.service});

  final IcmpService? service;

  @override
  State<MobileTracerouteScreen> createState() => _MobileTracerouteScreenState();
}

class _MobileTracerouteScreenState extends State<MobileTracerouteScreen> {
  late final IcmpService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  bool _running = false;
  bool _completed = false;
  bool _reachedTarget = false;
  String? _error;
  final List<IcmpHop> _hops = <IcmpHop>[];

  StreamSubscription<IcmpTraceEvent>? _sub;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? IcmpService(backend: defaultIcmpBackend());
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
      _completed = false;
      _reachedTarget = false;
      _hops.clear();
      _cancel = cancel;
    });

    _sub = _service
        .traceroute(host: host, cancel: cancel.future)
        .listen(
          (IcmpTraceEvent e) {
            if (!mounted) return;
            setState(() {
              if (e.hop != null) {
                _hops.add(e.hop!);
              } else if (e.done) {
                _running = false;
                _completed = true;
                _reachedTarget = e.reachedTarget;
              }
            });
            if (e.done) _announce();
          },
          onDone: () {
            if (!mounted) return;
            if (_running) setState(() => _running = false);
          },
          onError: (Object err) {
            if (!mounted) return;
            setState(() {
              _running = false;
              _error = err is StateError
                  ? err.message
                  : 'Traceroute error: $err';
            });
          },
        );
  }

  void _announce() {
    final String msg = _reachedTarget
        ? 'Traceroute complete, target reached in ${_hops.length} hops'
        : 'Traceroute finished at ${_hops.length} hops without reaching the '
              'target';
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
        title: const Text('Traceroute (Mobile)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until hops exist
        // (so it stays disabled on the iOS / sandboxed-desktop unavailable
        // cards, which produce no hops). Copies a hop TSV with a status header.
        // Copy leads; no help icon on this screen.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the ICMP TTL-walk path as a hop TSV with a status
  /// line.
  ///
  /// Returns null (→ disabled) until at least one hop exists; that also keeps
  /// it disabled across the unavailable states (iOS no-TimeExceeded, sandboxed
  /// desktop), neither of which produces hops. Mid-run it copies the hops
  /// streamed so far (the §8.16 streaming rule). A timed-out hop is written
  /// honestly as "no response" with a "*" time (GL-005); the status header
  /// carries the reached/stopped verdict WORD.
  String? _buildCopyText() {
    if (_hops.isEmpty) return null;

    final String host = _hostCtrl.text.trim();
    final String status;
    if (_running) {
      status = 'Tracing… ${_hops.length} hops so far';
    } else if (_completed) {
      status = _reachedTarget
          ? 'Reached target in ${_hops.length} hops'
          : 'Stopped at ${_hops.length} hops, target not reached';
    } else {
      status = '${_hops.length} hops';
    }

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln(
        'Traceroute (mobile) — ICMP TTL-walk to '
        '${host.isEmpty ? '(unknown)' : host}',
      )
      ..writeln('Status: $status')
      ..writeln()
      ..writeln(<String>['Hop', 'Host / IP', 'Time (ms)'].join(tab));

    for (final IcmpHop h in _hops) {
      final String addr = h.timedOut ? 'no response' : (h.fromIp ?? '—');
      final String time = h.timedOut
          ? '*'
          : (h.rttMs == null ? '—' : h.rttMs!.toStringAsFixed(1));
      buf.writeln(<String>['${h.ttl}', addr, time].join(tab));
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.icmpTracerouteSupported) {
      return NetworkUnavailableView(
        toolName: 'Mobile Traceroute',
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
                children: _childrenForCapability(context, isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _childrenForCapability(BuildContext context, bool isDesktop) {
    switch (_service.tracerouteCapability) {
      case IcmpTracerouteCapability.available:
        return <Widget>[
          ConceptGraphicBand(toolId: 'mobile-traceroute', isDesktop: isDesktop),
          if (ToolAssets.hasGraphic('mobile-traceroute'))
            const SizedBox(height: AppSpacing.md),
          _formCard(context),
          if (_hops.isNotEmpty || _running) ...[
            const SizedBox(height: AppSpacing.sm),
            _hopsCard(context),
          ],
          ToolHelpFooter(toolId: 'mobile-traceroute'),
        ];
      case IcmpTracerouteCapability.noTimeExceeded:
        return <Widget>[_unavailableCard(context, _iosCopy)];
      case IcmpTracerouteCapability.sandboxedDesktop:
        return <Widget>[_unavailableCard(context, _desktopCopy)];
      case IcmpTracerouteCapability.web:
        // Unreachable — gated above — but keep the switch exhaustive.
        return <Widget>[_unavailableCard(context, _desktopCopy)];
    }
  }

  static const _UnavailableCopy _iosCopy = _UnavailableCopy(
    icon: Icons.route_outlined,
    title: 'Traceroute is not available on iOS',
    body:
        'iOS can send ICMP echo (used by ICMP Ping) but its ICMP layer does not '
        'surface the Time-Exceeded replies from intermediate routers, so a '
        'TTL-walk cannot name the hops. Faking a path from echo timing would be '
        'a guess, not a traceroute. Run Traceroute from the macOS or Windows '
        'build, or use ICMP Ping here to test reachability and latency.',
  );

  static const _UnavailableCopy _desktopCopy = _UnavailableCopy(
    icon: Icons.desktop_windows_outlined,
    title: 'Use the system Traceroute on desktop',
    body:
        'On desktop the genuine traceroute uses the operating system tool. The '
        'ICMP TTL-walk in this screen is the mobile path; on a sandboxed '
        'desktop build the ICMP subprocess is blocked. Open the Traceroute tool '
        'to map the path here.',
  );

  Widget _unavailableCard(BuildContext context, _UnavailableCopy copy) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isDesktopCopy = identical(copy, _desktopCopy);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(copy.icon, size: 24, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  copy.title,
                  style: text.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            copy.body,
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: isDesktopCopy
                  ? 'Open the system Traceroute tool'
                  : 'Open ICMP Ping',
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  isDesktopCopy ? AppRouter.traceroute : AppRouter.icmpPing,
                ),
                icon: Icon(
                  isDesktopCopy ? Icons.route : Icons.network_ping,
                  size: 18,
                ),
                label: Text(
                  isDesktopCopy ? 'Open Traceroute' : 'Open ICMP Ping',
                ),
              ),
            ),
          ),
        ],
      ),
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
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: 'example.com'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Walks the IP TTL from 1 upward, naming each router that returns '
              'an ICMP Time-Exceeded — an ICMP TTL-walk, not the system '
              'traceroute.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ),
          _devicePendingNote(context),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: colors.textTertiary),
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

  Widget _devicePendingNote(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Uses the device\'s real ICMP TTL-walk. The native path is wired '
              'but still pending on-device verification; if it cannot run, a run '
              'reports that plainly rather than showing made-up hops.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hopsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String header;
    if (_running) {
      header = 'Tracing… ${_hops.length} hops';
    } else if (_completed) {
      header = _reachedTarget
          ? 'Reached target · ${_hops.length} hops'
          : 'Stopped at ${_hops.length} hops · target not reached';
    } else {
      header = '${_hops.length} hops';
    }

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
          Semantics(
            liveRegion: true,
            label: header,
            child: Text(
              header,
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._hops.map((IcmpHop h) => _hopRow(context, h, text, mono)),
        ],
      ),
    );
  }

  Widget _hopRow(
    BuildContext context,
    IcmpHop h,
    TextTheme text,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    final String rttLabel = h.timedOut
        ? '*'
        : (h.rttMs == null ? '—' : '${h.rttMs!.toStringAsFixed(1)} ms');
    final String addr = h.timedOut ? 'no response' : (h.fromIp ?? '—');
    final String semantic = h.timedOut
        ? 'Hop ${h.ttl}, no response'
        : 'Hop ${h.ttl}, ${h.fromIp ?? 'unknown'}, $rttLabel';

    return Semantics(
      label: semantic,
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          // Shared row-padding token (GL-003 §8.7) for tool-result rows.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${h.ttl}',
                  style: mono.inlineCode.copyWith(
                    color: colors.textAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  addr,
                  // Hop IP is an identifier → Roboto Mono (GL-003 §8.5).
                  // TTL counter and RTT stay DM Mono.
                  style: h.timedOut
                      ? text.bodyLarge?.copyWith(
                          color: colors.textTertiary,
                          fontStyle: FontStyle.italic,
                        )
                      : mono.robotoMono.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                rttLabel,
                style: mono.inlineCode.copyWith(
                  color: h.timedOut
                      ? colors.textTertiary
                      : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Immutable copy bundle for the two honest-unavailable variants.
@immutable
class _UnavailableCopy {
  const _UnavailableCopy({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
