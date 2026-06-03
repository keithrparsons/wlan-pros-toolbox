// Interface Information tool — shows the device's local network state.
//
// Mirrors HE.NET "Interface Information" (brief §4): IP address(es), subnet
// mask, gateway, DNS-relevant link details, interface type, MAC where the
// platform exposes it. Foundational: `primaryIPv4` here is the value the
// future iperf-server screen reads to tell the user "give this IP to the
// client".
//
// States (SOP-007 §5):
//  - loading  → spinner while the snapshot reads.
//  - success  → grouped cards: device summary, Wi-Fi link, per-interface.
//  - empty    → "No active interfaces" (airplane mode / all down).
//  - error    → read threw; retry affordance.
//  - web       → NetworkUnavailableView (brief §15) — never reached on web
//                because the service is only constructed off-web.
//
// Layout matches dbm_watt_converter: SafeArea + LayoutBuilder + centered
// ConstrainedBox + scroll, surface1 cards with hairline border, mono for
// numeric/address values.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/interface_info_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class InterfaceInfoScreen extends StatefulWidget {
  const InterfaceInfoScreen({super.key, this.service});

  /// Injectable for tests; defaults to the real service off-web.
  final InterfaceInfoService? service;

  @override
  State<InterfaceInfoScreen> createState() => _InterfaceInfoScreenState();
}

class _InterfaceInfoScreenState extends State<InterfaceInfoScreen> {
  InterfaceInfoService? _service;
  Future<InterfaceInfoSnapshot>? _future;

  // The resolved snapshot, mirrored out of the FutureBuilder so the §8.16 copy
  // builder can read the current result and the affordance re-enables when the
  // read completes. Null while loading / before the first read / on error.
  InterfaceInfoSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    if (NetworkSupport.interfaceInfoSupported) {
      _service = widget.service ?? InterfaceInfoService();
      _load();
    }
  }

  void _load() {
    final Future<InterfaceInfoSnapshot> future = _service!.read();
    setState(() {
      _future = future;
      // Disable copy while the (re)read is in flight; it re-enables on success.
      _snapshot = null;
    });
    // Mirror the resolved snapshot into state so AppCopyAction rebuilds (via
    // setState) and reads the current result; an error/cancel leaves it null.
    future
        .then((InterfaceInfoSnapshot data) {
          if (!mounted || !identical(_future, future)) return;
          setState(() => _snapshot = data);
        })
        .catchError((Object _) {
          // Errors are surfaced by the FutureBuilder's error branch; copy stays
          // disabled (snapshot null). Swallow here so no unhandled-error fires.
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interface Info'),
        toolbarHeight: 64,
        // §8.16 — copy leads, the meta action (refresh) trails, matching the
        // copy-before-help order rule. Copy is disabled until a read completes.
        actions: [
          if (NetworkSupport.interfaceInfoSupported) ...[
            AppCopyAction(textBuilder: _buildCopyText),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          ],
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the interface snapshot as a labeled plain-text block.
  ///
  /// Returns null (→ disabled affordance) while a read is in flight, before the
  /// first read, or after an error — none of those is a result to keep. Absent
  /// fields are omitted (GL-005 honest blanks), matching the on-screen
  /// `ValueRow` treatment. The Wi-Fi link and each active interface are grouped
  /// under their own subheadings, mirroring the on-screen card grouping.
  String? _buildCopyText() {
    final InterfaceInfoSnapshot? data = _snapshot;
    if (data == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('Interface Info');
    void line(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        buf.writeln('$label: ${value.trim()}');
      }
    }

    // Device summary.
    buf.writeln();
    buf.writeln('Device');
    line('Primary IPv4', data.primaryIPv4);
    line('Hostname', data.hostname);

    // Wi-Fi link.
    final WifiLinkInfo w = data.wifi;
    buf.writeln();
    buf.writeln('Wi-Fi link');
    line('SSID', w.ssid);
    line('BSSID', w.bssid);
    line('IPv4', w.wifiIPv4);
    line('IPv6', w.wifiIPv6);
    line('Subnet mask', w.subnetMask);
    line('Gateway', w.gatewayIP);

    // Per-interface, only those with an assigned address (matching _Success).
    final List<NetworkInterfaceInfo> active = data.interfaces
        .where((NetworkInterfaceInfo i) => i.addresses.isNotEmpty)
        .toList(growable: false);
    if (active.isEmpty) {
      buf
        ..writeln()
        ..writeln('Interfaces')
        ..writeln('No active interfaces with an assigned address.');
    } else {
      for (final NetworkInterfaceInfo iface in active) {
        buf
          ..writeln()
          ..writeln('${iface.name}  ·  ${_Success._kindLabel(iface.kind)}');
        for (final InterfaceAddress a in iface.addresses) {
          line(a.isIPv4 ? 'IPv4' : 'IPv6', a.ip);
        }
      }
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.interfaceInfoSupported) {
      return NetworkUnavailableView(
        toolName: 'Interface Information',
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

        return FutureBuilder<InterfaceInfoSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingState();
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _load);
            }
            final InterfaceInfoSnapshot? data = snapshot.data;
            if (data == null) {
              return _ErrorState(onRetry: _load);
            }
            return _Success(data: data, edge: edge, isDesktop: isDesktop);
          },
        );
      },
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({
    required this.data,
    required this.edge,
    required this.isDesktop,
  });

  final InterfaceInfoSnapshot data;
  final double edge;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final List<NetworkInterfaceInfo> active = data.interfaces
        .where((NetworkInterfaceInfo i) => i.addresses.isNotEmpty)
        .toList(growable: false);

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
                toolId: 'interface-info',
                isDesktop: isDesktop,
              ),
              if (ToolAssets.hasGraphic('interface-info'))
                const SizedBox(height: AppSpacing.md),
              _summaryCard(context),
              const SizedBox(height: AppSpacing.sm),
              _wifiCard(context),
              const SizedBox(height: AppSpacing.sm),
              if (active.isEmpty)
                _NoInterfaces()
              else
                ...active.map(
                  (NetworkInterfaceInfo i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _interfaceCard(context, i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    return _Card(
      title: 'Device',
      child: Column(
        children: [
          ValueRow(
            label: 'Primary IPv4',
            value: data.primaryIPv4,
            emphasize: true,
          ),
          ValueRow(label: 'Hostname', value: data.hostname),
        ],
      ),
    );
  }

  Widget _wifiCard(BuildContext context) {
    final WifiLinkInfo w = data.wifi;
    return _Card(
      title: 'Wi-Fi link',
      child: Column(
        children: [
          ValueRow(label: 'SSID', value: w.ssid),
          ValueRow(label: 'BSSID', value: w.bssid, identifier: true),
          ValueRow(label: 'IPv4', value: w.wifiIPv4, identifier: true),
          ValueRow(label: 'IPv6', value: w.wifiIPv6, identifier: true),
          ValueRow(label: 'Subnet mask', value: w.subnetMask, identifier: true),
          ValueRow(label: 'Gateway', value: w.gatewayIP, identifier: true),
        ],
      ),
    );
  }

  Widget _interfaceCard(BuildContext context, NetworkInterfaceInfo iface) {
    return _Card(
      title: '${iface.name}  ·  ${_kindLabel(iface.kind)}',
      child: Column(
        children: [
          for (final InterfaceAddress a in iface.addresses)
            ValueRow(
              label: a.isIPv4 ? 'IPv4' : 'IPv6',
              value: a.ip,
              identifier: true,
            ),
        ],
      ),
    );
  }

  static String _kindLabel(InterfaceKind kind) {
    switch (kind) {
      case InterfaceKind.wifi:
        return 'Wi-Fi';
      case InterfaceKind.ethernet:
        return 'Ethernet';
      case InterfaceKind.cellular:
        return 'Cellular';
      case InterfaceKind.loopback:
        return 'Loopback';
      case InterfaceKind.vpn:
        return 'VPN / Tunnel';
      case InterfaceKind.other:
        return 'Interface';
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
            title,
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

class _NoInterfaces extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      title: 'Interfaces',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          'No active interfaces with an assigned address.',
          style: text.bodyLarge?.copyWith(color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    // WCAG 4.1.3 — a bare progress indicator announces nothing. Label it so
    // VoiceOver/TalkBack speak the loading state. `Semantics` is not a const
    // constructor, so `Center` cannot be const here; the indicator stays const.
    return Center(
      child: Semantics(
        label: 'Reading network state…',
        liveRegion: true,
        child: const CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not read network state',
              style: text.headlineSmall?.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
