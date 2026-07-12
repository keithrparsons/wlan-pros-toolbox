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
//                     ⚠️ DEVICE-PENDING: the native ICMP path is wired
//                     (dart_ping + dart_ping_ios); live round-trip is
//                     device-pending — unverifiable in this environment, to be
//                     confirmed on a device pass. The UI states this plainly.
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

import '../../../data/tool_assets.dart';
import '../../../router/app_router.dart';
import '../../../services/network/dart_ping_icmp_backend.dart';
import '../../../services/network/icmp_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
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
      appBar: AppBar(
        title: const Text('Ping (ICMP)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a run has
        // produced replies (and so always disabled on the sandboxed-desktop
        // state, which never reaches `_stats.sent > 0`). Copies the summary
        // line + a reply TSV. Copy leads; no help icon on this screen.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the ICMP run as a labeled summary plus a reply TSV.
  ///
  /// Returns null (→ disabled) until a run has begun sending (`_stats.sent >
  /// 0`); that also keeps it disabled on the sandboxed-desktop unavailable
  /// state, which never runs. Mid-run it copies the partial stats + replies on
  /// screen at tap time (the §8.16 streaming rule). Replies are emitted in send
  /// order; the ICMP responder IP is carried per reply when known; a lost probe
  /// keeps its honest reason word (GL-005), never a fabricated time.
  String? _buildCopyText() {
    if (_stats.sent == 0) return null;

    final String host = _hostCtrl.text.trim();
    final String lossPct = (_stats.lossFraction * 100).toStringAsFixed(0);
    String ms(double? v) => v == null ? '—' : v.toStringAsFixed(1);

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Ping — ICMP echo')
      ..writeln('Target: ${host.isEmpty ? '(unknown)' : host}')
      ..writeln(
        'Summary: ${_stats.received}/${_stats.sent} replies, $lossPct% loss · '
        'min ${ms(_stats.minMs)} ms / avg ${ms(_stats.avgMs)} ms / '
        'max ${ms(_stats.maxMs)} ms',
      )
      ..writeln()
      ..writeln(<String>['Seq', 'Result', 'From', 'Time (ms)'].join(tab));

    final List<IcmpReply> ordered = List<IcmpReply>.of(_replies)
      ..sort((IcmpReply a, IcmpReply b) => a.sequence.compareTo(b.sequence));
    for (final IcmpReply r in ordered) {
      final String result = r.success ? 'reply' : (r.errorLabel ?? 'no reply');
      final String from = r.fromIp ?? '';
      final String time = r.success && r.rttMs != null
          ? r.rttMs!.toStringAsFixed(1)
          : '';
      buf.writeln(<String>['${r.sequence}', result, from, time].join(tab));
    }

    return buf.toString().trimRight();
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
                children:
                    _service.echoCapability ==
                        IcmpEchoCapability.sandboxedDesktop
                    ? <Widget>[_sandboxedDesktopCard(context)]
                    : _availableChildren(context, isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _availableChildren(BuildContext context, bool isDesktop) {
    return <Widget>[
      ConceptGraphicBand(toolId: 'icmp-ping', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('icmp-ping'))
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
      // §8.16.1 — per-tool help footer at the end of the scroll body.
      const ToolHelpFooter(toolId: 'icmp-ping'),
    ];
  }

  /// Why real ICMP echo is unavailable on THIS desktop, in the terms of the
  /// platform the user is actually running.
  ///
  /// THE BUG THIS FIXES: this card hard-coded the macOS App Sandbox explanation
  /// and showed it to everyone — so a WINDOWS user was told that "the macOS App
  /// Sandbox" was blocking them. There is no macOS App Sandbox on Windows. The
  /// verdict (use TCP Ping on desktop) was right; the reason given was false.
  String _desktopUnavailableReason() {
    switch (_service.osName) {
      case 'macos':
        return 'A real ICMP echo on this desktop build needs the system ping '
            'binary, which the macOS App Sandbox blocks for distributed apps.';
      case 'windows':
        return 'This desktop build does not open the raw ICMP socket a real '
            'echo request needs, so ICMP ping is not available here.';
      case 'linux':
        return 'A real ICMP echo needs a raw socket, which requires elevated '
            'privileges this desktop build does not hold, so ICMP ping is not '
            'available here.';
      default:
        return 'A real ICMP echo is not available in this desktop build.';
    }
  }

  /// Honest desktop state: real ICMP is unavailable on desktop (for a
  /// platform-specific reason — see [_desktopUnavailableReason]). Point the user
  /// at the TCP Ping tool, which IS the desktop reachability/latency path.
  Widget _sandboxedDesktopCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
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
              Icon(
                Icons.shield_outlined,
                size: 24,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'ICMP ping runs on mobile',
                  style: text.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${_desktopUnavailableReason()} '
            'Use the TCP Ping tool here — it measures reachability and '
            'round-trip latency over a TCP round trip, counting a reply when '
            'the host answers, whether it completes the connection or actively '
            'refuses it (not ICMP). Run ICMP Ping from the iOS or Android '
            'build.',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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
              decoration: const InputDecoration(hintText: '1.1.1.1'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Count',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
              'Sends ICMP echo requests and measures the echo-reply round-trip '
              'time — true ICMP, not a TCP probe.',
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
            FilledButton(onPressed: _start, child: const Text('Ping')),
        ],
      ),
    );
  }

  /// Honest disclosure that the native ICMP layer is not yet device-verified.
  /// Never claims it works; tells the user exactly what state the build is in.
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
              'Uses the device\'s real ICMP echo. The native path is wired but '
              'still pending on-device verification; if it cannot run, a run '
              'reports that plainly rather than showing made-up results.',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(BuildContext context, int count) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = _count == count;
    final String label = count == 0 ? 'Until stopped' : '$count';
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? colors.onPrimary : colors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: colors.primary,
      backgroundColor: colors.surface2,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders + 2px lime
      // keyboard-focus ring.
      side: AppTheme.chipSide(Theme.of(context).brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _running ? null : (_) => setState(() => _count = count),
    );
  }

  Widget _statsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
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
        ? 'Pinging by ICMP, ${_stats.received} of ${_stats.sent} replies, '
              '$lossPct percent loss, average $av milliseconds'
        : 'ICMP ping complete, ${_stats.received} of ${_stats.sent} replies, '
              '$lossPct percent loss, average $av milliseconds';

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
                _running ? 'ICMP echo…' : 'Summary',
                style: text.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '${_stats.received} / ${_stats.sent} · $lossPct% loss',
                style: text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: mono.outputMedium.copyWith(color: colors.textAccent),
              ),
              const SizedBox(width: 2),
              if (value != '—')
                Text(
                  'ms',
                  style: text.labelSmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _repliesCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final bool finished = !_running && _stats.sent > 0;
    final bool noReplies = finished && _stats.received == 0;

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
          Text(
            'Replies',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (noReplies)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No replies. The host did not answer the ICMP echo — it may be '
                'down, or ICMP may be filtered on the path.',
                style: text.bodyLarge?.copyWith(color: colors.textTertiary),
              ),
            ),
          ..._replies.reversed.map(
            (IcmpReply r) => _replyRow(context, r, text, mono),
          ),
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
    final AppColorScheme colors = context.colors;
    // WCAG 1.4.1 — outcome carried by text + icon shape, never color alone.
    final (
      Color color,
      IconData icon,
      String value,
      String semantic,
    ) = r.success
        ? (
            colors.textAccent,
            Icons.south_east,
            r.rttMs == null ? 'reply' : '${r.rttMs!.toStringAsFixed(1)} ms',
            'Reply ${r.sequence}, '
                '${r.rttMs == null ? 'no time' : '${r.rttMs!.toStringAsFixed(1)} milliseconds'}',
          )
        : (
            colors.textTertiary,
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
                  style: mono.inlineCode.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.success ? 'reply' : (r.errorLabel ?? 'no reply'),
                  style: text.labelMedium?.copyWith(
                    color: colors.textSecondary,
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
