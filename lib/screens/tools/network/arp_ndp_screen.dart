// ARP / NDP Lookup tool — discover local-network neighbors (IP ↔ MAC where the
// platform exposes it). See ArpNdpService for the full honest capability matrix.
//
// The capability is stated plainly in the UI, never faked:
//   - Linux / Android: active subnet sweep + real MAC from /proc/net/arp.
//   - macOS / Windows: active subnet sweep lists responders; MAC is NOT exposed
//     to a sandboxed app, so each row shows "Not exposed on this platform" —
//     never a fabricated MAC.
//   - iOS: the ARP table is not accessible to third-party apps → a clear
//     unavailable state (the traceroute-on-mobile pattern), no fake neighbors.
//   - web: NetworkUnavailableView.
//
// States (SOP-007 §5):
//  - idle      → form + capability banner (or the iOS unavailable card).
//  - loading   → neighbors appear as the sweep finds them; Stop button.
//  - success   → list of neighbors; "found N of M probed".
//  - empty     → sweep finished, nothing answered.
//  - error     → no local IPv4 to derive a subnet from.
//  - web       → NetworkUnavailableView.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/arp_ndp_service.dart';
import '../../../services/network/interface_info_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';

class ArpNdpScreen extends StatefulWidget {
  const ArpNdpScreen({
    super.key,
    this.service,
    this.interfaceService,
    this.capabilityOverride,
  });

  final ArpNdpService? service;
  final InterfaceInfoService? interfaceService;

  /// Test-only: force a capability instead of reading the real platform.
  final ArpCapability? capabilityOverride;

  @override
  State<ArpNdpScreen> createState() => _ArpNdpScreenState();
}

class _ArpNdpScreenState extends State<ArpNdpScreen> {
  ArpNdpService? _service;
  InterfaceInfoService? _interfaceService;
  late final ArpCapability _capability;

  bool _running = false;
  String? _error;
  int _probed = 0;
  int _total = 0;
  String? _subnetLabel;
  final List<Neighbor> _neighbors = <Neighbor>[];

  /// Fate of this sweep's neighbor-table read. Drives whether a missing MAC is
  /// reported as a platform limit, a failed read, or simply a host the read
  /// did not cover. Never assert a negative about a source we did not query.
  MacReadOutcome _macRead = MacReadOutcome.notAttempted;

  StreamSubscription<ArpScanProgress>? _sub;
  Completer<void>? _cancel;

  @override
  void initState() {
    super.initState();
    if (NetworkSupport.arpNdpSupported) {
      _service = widget.service ?? ArpNdpService();
      _interfaceService = widget.interfaceService ?? InterfaceInfoService();
    }
    _capability =
        widget.capabilityOverride ??
        (NetworkSupport.arpNdpSupported
            ? ArpNdpService.capabilityFor()
            : ArpCapability.unavailable);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Why this neighbor has no MAC. Delegates to the shared [missingMacReason]
  /// so the row, the export, and any future surface read one derivation.
  String get _missingMacReason => missingMacReason(_macRead);

  Future<void> _start() async {
    if (_running || _service == null || _interfaceService == null) return;

    setState(() {
      _error = null;
      _running = true;
      _neighbors.clear();
      _probed = 0;
      _total = 0;
      _subnetLabel = null;
      _macRead = MacReadOutcome.notAttempted;
    });

    // Derive the local /24 from the device's primary IPv4.
    final InterfaceInfoSnapshot snap = await _interfaceService!.read();
    if (!mounted) return;
    final String? ipv4 = snap.primaryIPv4;
    if (ipv4 == null) {
      setState(() {
        _running = false;
        _error =
            'No active IPv4 interface found, so there is no local subnet '
            'to scan. Connect to a Wi-Fi or Ethernet network and try again.';
      });
      return;
    }

    final List<String> hosts = ArpNdpService.defaultLanHosts(ipv4);
    final List<String> parts = ipv4.split('.');
    _subnetLabel = parts.length == 4
        ? '${parts[0]}.${parts[1]}.${parts[2]}.0/24'
        : ipv4;

    final Completer<void> cancel = Completer<void>();
    _cancel = cancel;
    setState(() => _total = hosts.length);

    _sub = _service!
        .discover(
          hosts: hosts,
          capabilityOverride: _capability,
          cancel: cancel.future,
        )
        .listen(
          (ArpScanProgress p) {
            if (!mounted) return;
            setState(() {
              _probed = p.probed;
              _total = p.total;
              _macRead = p.macRead;
              if (p.lastFound != null) _neighbors.add(p.lastFound!);
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _running = false);
            SemanticsService.sendAnnouncement(
              View.of(context),
              'Scan complete. Found ${_neighbors.length} '
              '${_neighbors.length == 1 ? 'neighbor' : 'neighbors'}.',
              TextDirection.ltr,
            );
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _running = false;
              _error = 'Discovery error: $e';
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
        title: const Text('Lookup (ARP/NDP)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. No help icon here, so copy
        // is the only action. Disabled until the sweep has found a neighbor.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the neighbor table as TSV (header + one row per
  /// neighbor). Columns are IP, MAC, RTT (ms): this tool's [Neighbor] model
  /// carries no vendor or per-host interface field, so those columns are not
  /// emitted (never a fabricated cell, GL-005). Where the platform sandboxes
  /// the MAC away the cell carries the on-screen honesty WORD "Not exposed on
  /// this platform" rather than a blank that reads as missing-data.
  ///
  /// Returns null (→ disabled affordance) until the sweep has found at least
  /// one neighbor; an in-flight or empty sweep has nothing to keep. Copyable
  /// while the sweep is still running (partial results are real results), as
  /// long as a neighbor has answered.
  String? _buildCopyText() {
    if (_neighbors.isEmpty) return null;

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('ARP / NDP Neighbors')
      ..writeln(<String>['IP', 'MAC', 'RTT (ms)'].join(tab));

    for (final Neighbor n in _neighbors) {
      final bool hasMac = n.mac != null && n.mac!.isNotEmpty;
      final String mac = hasMac ? n.mac! : _missingMacReason;
      final String rtt = n.rttMs == null ? '' : n.rttMs!.toStringAsFixed(0);
      buf.writeln(<String>[n.ip, mac, rtt].join(tab));
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.arpNdpSupported) {
      return NetworkUnavailableView(
        toolName: 'ARP / NDP Lookup',
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
                children: _capability == ArpCapability.unavailable
                    ? <Widget>[_unavailableCard(context)]
                    : _scanChildren(context, isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _scanChildren(BuildContext context, bool isDesktop) {
    return <Widget>[
      ConceptGraphicBand(toolId: 'arp-ndp', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('arp-ndp'))
        const SizedBox(height: AppSpacing.md),
      _capabilityCard(context),
      const SizedBox(height: AppSpacing.sm),
      _controlCard(context),
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.sm),
        _MessageCard(
          icon: Icons.error_outline,
          title: 'Cannot scan',
          body: _error!,
        ),
      ],
      if (_total > 0 || _neighbors.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        _resultsCard(context),
      ],
      // §8.16.1 — per-tool help footer at the end of the scan body.
      const ToolHelpFooter(toolId: 'arp-ndp'),
    ];
  }

  Widget _capabilityCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final (String title, String body) = switch (_capability) {
      ArpCapability.sweepWithMac => (
        'Discovery with MAC addresses',
        'On this platform the toolbox sweeps the local subnet and reads the '
            'kernel neighbor table to attach each responder\'s real MAC '
            'address. macOS reads it through a native sysctl call, Windows '
            'through the IP Helper API. No subprocess, no elevated privilege. '
            'If a read fails, the toolbox says so rather than reporting the '
            'MAC as unavailable.',
      ),
      ArpCapability.sweepNoMac => (
        'Discovery only: MAC not exposed',
        'This platform sandboxes the neighbor table away from apps, and '
            'shelling out to the system arp command is blocked. The toolbox '
            'sweeps the local subnet and lists every host that answers; MAC '
            'addresses are shown as "Not exposed on this platform" rather '
            'than guessed.',
      ),
      ArpCapability.unavailable => ('', ''),
    };
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _capability == ArpCapability.sweepWithMac
                ? Icons.lan_outlined
                : Icons.info_outline,
            size: 20,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlCard(BuildContext context) {
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
          Text(
            _subnetLabel == null
                ? 'Scans the local /24 around your primary IPv4.'
                : 'Scanning $_subnetLabel',
            style: text.labelMedium?.copyWith(color: colors.textSecondary),
          ),
          if (_running) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              label:
                  'Scanning, $_probed of $_total probed, '
                  '${_neighbors.length} found',
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _probed / _total,
                backgroundColor: colors.surface0,
                // Progress fill: lime in dark; darkened-lime in light so a 6px
                // bar reads on the white surface (§8.20.2).
                color: colors.isLight ? colors.textAccent : colors.primary,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_probed of $_total probed · ${_neighbors.length} found',
              style: text.labelSmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_running)
            OutlinedButton(onPressed: _stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: _start, child: const Text('Scan subnet')),
        ],
      ),
    );
  }

  Widget _resultsCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String header = _running
        ? 'Neighbors · ${_neighbors.length} so far'
        : (_neighbors.isEmpty
              ? 'No neighbors answered'
              : '${_neighbors.length} '
                    '${_neighbors.length == 1 ? 'neighbor' : 'neighbors'} found');

    if (!_running && _neighbors.isEmpty) {
      return _MessageCard(
        icon: Icons.search_off,
        title: 'No neighbors answered',
        body:
            'Swept $_total hosts on ${_subnetLabel ?? 'the local subnet'} and '
            'none responded to a reachability probe. Hosts that block all '
            'probe ports will not appear.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._neighbors.map(
            (Neighbor n) => _neighborRow(context, n, text, mono),
          ),
        ],
      ),
    );
  }

  Widget _neighborRow(
    BuildContext context,
    Neighbor n,
    TextTheme text,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    final bool hasMac = n.mac != null && n.mac!.isNotEmpty;
    final String rtt = n.rttMs == null
        ? ''
        : '${n.rttMs!.toStringAsFixed(0)} ms';
    final String semantic = hasMac
        ? 'Neighbor ${n.ip}, MAC ${n.mac}, $rtt'
        : 'Neighbor ${n.ip}, MAC not exposed on this platform, $rtt';

    return Semantics(
      container: true,
      label: semantic,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      n.ip,
                      style: mono.robotoMono.copyWith(
                        color: colors.textAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (rtt.isNotEmpty)
                    Text(
                      rtt,
                      style: mono.inlineCode.copyWith(
                        color: colors.textTertiary,
                        fontSize: AppTextSize.caption,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              hasMac
                  ? SelectableText(
                      n.mac!,
                      style: mono.robotoMono.copyWith(
                        color: colors.textSecondary,
                        fontSize: AppTextSize.caption,
                      ),
                    )
                  : Text(
                      _macRead == MacReadOutcome.notAttempted
                          ? 'MAC not exposed on this platform'
                          : _missingMacReason,
                      style: text.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unavailableCard(BuildContext context) {
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
                Icons.devices_other_outlined,
                size: 24,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Not available on iOS',
                  style: text.headlineSmall?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'iOS does not give third-party apps access to the ARP/NDP neighbor '
            'table, so there is no reliable way to list IP-to-MAC mappings for '
            'the local network on this device. Run ARP / NDP from the macOS, '
            'Windows, Linux, or Android build. On macOS and Windows the toolbox '
            'lists reachable hosts; on Linux and Android it also attaches the '
            'real MAC addresses.',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: colors.textTertiary,
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
