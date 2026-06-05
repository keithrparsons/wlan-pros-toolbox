// Port Scan tool — TCP connect scan with common-ports preset + custom spec.
//
// States (SOP-007 §5):
//  - idle      → form only.
//  - loading   → progress bar + live-streaming results; Stop button.
//  - success   → results grouped open / closed / filtered, open ports first.
//  - empty     → scan finished, nothing open (all closed/filtered) — still a
//                valid, informative result, not an error.
//  - error     → empty host / no valid ports parsed.
//  - web        → NetworkUnavailableView (brief §15).
//
// Concurrency and timeouts are handled in PortScanService; this screen only
// drives the stream and renders. The scan is cancellable (Stop) via a
// Completer handed to the service.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/port_scan_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class PortScanScreen extends StatefulWidget {
  const PortScanScreen({super.key, this.service});

  final PortScanService? service;

  @override
  State<PortScanScreen> createState() => _PortScanScreenState();
}

enum _Mode { common, custom }

class _PortScanScreenState extends State<PortScanScreen> {
  late final PortScanService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _portsCtrl = TextEditingController(
    text: '22, 80, 443, 8080',
  );
  final FocusNode _hostFocus = FocusNode();

  _Mode _mode = _Mode.common;

  bool _scanning = false;
  String? _error;
  int _completed = 0;
  int _total = 0;
  final List<PortResult> _results = <PortResult>[];

  StreamSubscription<PortScanProgress>? _sub;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PortScanService();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hostCtrl.dispose();
    _portsCtrl.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  List<int> _selectedPorts() {
    if (_mode == _Mode.common) return PortScanService.commonPorts.ports;
    return PortScanService.parsePortSpec(_portsCtrl.text);
  }

  void _start() {
    final String host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      setState(() => _error = 'Enter a host or IP to scan.');
      return;
    }
    final List<int> ports = _selectedPorts();
    if (ports.isEmpty) {
      setState(
        () => _error = 'No valid ports. Use e.g. "22, 80, 443, 8000-8100".',
      );
      return;
    }

    _hostFocus.unfocus();
    final Completer<void> cancel = Completer<void>();
    setState(() {
      _error = null;
      _scanning = true;
      _completed = 0;
      _total = ports.length;
      _results.clear();
      _cancel = cancel;
    });

    _sub = _service
        .scan(host: host, ports: ports, cancel: cancel.future)
        .listen(
          (PortScanProgress p) {
            if (!mounted) return;
            setState(() {
              _completed = p.completed;
              _total = p.total;
              if (p.lastResult != null) _results.add(p.lastResult!);
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _scanning = false);
            // WCAG 4.1.3 — announce completion + open-port count to AT.
            final int openCount = _results
                .where((PortResult r) => r.status == PortStatus.open)
                .length;
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Scan complete, $openCount open '
              'port${openCount == 1 ? '' : 's'}',
              TextDirection.ltr,
            );
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _scanning = false;
              _error = 'Scan error: $e';
            });
          },
        );
  }

  void _stop() {
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Port Scan'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a scan has
        // started. Copies a TSV of every probed port with its state + service.
        // Copy leads; no help icon on this screen.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — a TSV of every probed port: state + service.
  ///
  /// Returns null (→ disabled) until a scan has begun (`_total > 0`). Mid-run
  /// it copies the rows resolved so far (the §8.16 streaming rule), in the same
  /// open→closed→filtered, then ascending-port order the on-screen list uses.
  /// The §8.13/§8.16 verdict WORD (OPEN / CLOSED / FILTERED) is the State cell —
  /// the on-screen status hue had a word, and that word travels to the
  /// clipboard. A port with no known service name emits an empty Service cell
  /// (never fabricated, GL-005).
  String? _buildCopyText() {
    if (_total == 0) return null;

    final String host = _hostCtrl.text.trim();
    String stateWord(PortStatus s) => switch (s) {
      PortStatus.open => 'OPEN',
      PortStatus.closed => 'CLOSED',
      PortStatus.filtered => 'FILTERED',
    };
    int rank(PortStatus s) => switch (s) {
      PortStatus.open => 0,
      PortStatus.closed => 1,
      PortStatus.filtered => 2,
    };

    final List<PortResult> sorted = List<PortResult>.of(_results)
      ..sort((PortResult a, PortResult b) {
        final int byStatus = rank(a.status).compareTo(rank(b.status));
        return byStatus != 0 ? byStatus : a.port.compareTo(b.port);
      });

    final int openCount = _results
        .where((PortResult r) => r.status == PortStatus.open)
        .length;

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Port Scan — TCP connect')
      ..writeln('Target: ${host.isEmpty ? '(unknown)' : host}')
      ..writeln(
        'Summary: $openCount open of ${_results.length} probed '
        '($_completed/$_total complete)',
      )
      ..writeln()
      ..writeln(<String>['Port', 'State', 'Service'].join(tab));

    for (final PortResult r in sorted) {
      buf.writeln(
        <String>[
          '${r.port}',
          stateWord(r.status),
          r.serviceName ?? '',
        ].join(tab),
      );
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.portScanSupported) {
      return NetworkUnavailableView(
        toolName: 'Port Scan',
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
                  ConceptGraphicBand(toolId: 'port-scan', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('port-scan'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  if (_total > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  if (_results.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _resultsCard(context),
                  ],
                  ToolHelpFooter(toolId: 'port-scan'),
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
              enabled: !_scanning,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '192.168.1.1'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ports',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _modeChip(context, _Mode.common, 'Common'),
              const SizedBox(width: AppSpacing.xs),
              _modeChip(context, _Mode.custom, 'Custom'),
            ],
          ),
          if (_mode == _Mode.common)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                '${PortScanService.commonPorts.ports.length} well-known '
                'ports (SSH, HTTP, HTTPS, SMB, RDP, iperf3, …).',
                style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
            )
          else ...[
            const SizedBox(height: AppSpacing.xs),
            // Visible "Ports" label sits above the Common/Custom chips, so it
            // can't be the field's adjacent label — associate explicitly so the
            // field announces its purpose ("Custom ports, text field").
            Semantics(
              label: 'Custom ports',
              textField: true,
              child: TextField(
                controller: _portsCtrl,
                enabled: !_scanning,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.text,
                cursorColor: AppColors.primary,
                decoration: const InputDecoration(
                  hintText: '22, 80, 443, 8000-8100',
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_scanning)
            OutlinedButton(onPressed: _stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: _start, child: const Text('Scan')),
        ],
      ),
    );
  }

  Widget _modeChip(BuildContext context, _Mode mode, String label) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = _mode == mode;
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
      // WCAG 2.5.8 / §8.3 — guarantee ≥48dp hit region.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders + 2px lime
      // keyboard-focus ring.
      side: AppTheme.chipSide(Theme.of(context).brightness),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _scanning ? null : (_) => setState(() => _mode = mode),
    );
  }

  Widget _progressCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double fraction = _total == 0 ? 0 : _completed / _total;
    final int openCount = _results
        .where((PortResult r) => r.status == PortStatus.open)
        .length;
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
                _scanning ? 'Scanning…' : 'Scan complete',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '$_completed / $_total · $openCount open',
                style: text.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // WCAG 4.1.3 — a bare progress bar announces nothing. Label it with
          // the live scan state and counts so AT users can track progress.
          Semantics(
            label: _scanning
                ? 'Scanning, $_completed of $_total ports, $openCount open'
                : 'Scan complete, $openCount open '
                      'port${openCount == 1 ? '' : 's'}',
            liveRegion: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: LinearProgressIndicator(
                value: _scanning ? fraction : 1.0,
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

    // Open first (the interesting result), then closed, then filtered. Within
    // a status, ascending port order.
    final List<PortResult> sorted = List<PortResult>.of(_results)
      ..sort((PortResult a, PortResult b) {
        int rank(PortStatus s) => switch (s) {
          PortStatus.open => 0,
          PortStatus.closed => 1,
          PortStatus.filtered => 2,
        };
        final int byStatus = rank(a.status).compareTo(rank(b.status));
        return byStatus != 0 ? byStatus : a.port.compareTo(b.port);
      });

    final bool finished = !_scanning && _completed >= _total && _total > 0;
    final bool noOpen =
        finished &&
        !_results.any((PortResult r) => r.status == PortStatus.open);

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
            'Results',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (noOpen)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'No open ports. The host responded on no scanned port — '
                'every port was closed or filtered.',
                style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ...sorted.map((PortResult r) => _portRow(context, r, text, mono)),
        ],
      ),
    );
  }

  Widget _portRow(
    BuildContext context,
    PortResult r,
    TextTheme text,
    AppMonoText mono,
  ) {
    final (Color color, String label, IconData icon) = switch (r.status) {
      PortStatus.open => (AppColors.primary, 'OPEN', Icons.check_circle),
      PortStatus.closed => (
        AppColors.textTertiary,
        'CLOSED',
        Icons.cancel_outlined,
      ),
      PortStatus.filtered => (
        AppColors.textTertiary,
        'FILTERED',
        Icons.shield_outlined,
      ),
    };

    // WCAG 1.4.1 — status must not be carried by icon color alone. The status
    // word is already on-screen as a text label; merge the row into a single
    // explicit semantic node ("Port <n> <STATUS>") and mark the icon
    // decorative so AT reads the label, never the color.
    final String service = r.serviceName == null ? '' : ', ${r.serviceName}';
    return Semantics(
      label: 'Port ${r.port}$service, $label',
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: 64,
                child: Text(
                  '${r.port}',
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.serviceName ?? '—',
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                label,
                style: text.labelSmall?.copyWith(
                  color: color,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
