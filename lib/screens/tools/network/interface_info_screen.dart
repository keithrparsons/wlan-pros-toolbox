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
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/interface_info_service.dart';
import '../../../services/network/mac_randomization.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/public_ip_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class InterfaceInfoScreen extends StatefulWidget {
  const InterfaceInfoScreen({super.key, this.service, this.publicIpService});

  /// Injectable for tests; defaults to the real service off-web.
  final InterfaceInfoService? service;

  /// Injectable public-IP fetcher for tests; defaults to the real service.
  final PublicIpService? publicIpService;

  @override
  State<InterfaceInfoScreen> createState() => _InterfaceInfoScreenState();
}

/// The async state of the Public IP row: a separate network fetch from the local
/// snapshot, so it carries its own loading / value / unavailable state.
enum _PublicIpStatus { loading, loaded, unavailable }

class _InterfaceInfoScreenState extends State<InterfaceInfoScreen> {
  InterfaceInfoService? _service;
  PublicIpService? _publicIpService;
  Future<InterfaceInfoSnapshot>? _future;

  // The resolved snapshot, mirrored out of the FutureBuilder so the §8.16 copy
  // builder can read the current result and the affordance re-enables when the
  // read completes. Null while loading / before the first read / on error.
  InterfaceInfoSnapshot? _snapshot;

  // Public IP is a SEPARATE network fetch from the local snapshot, so it carries
  // its own state. It starts loading and resolves to the IP or "Unavailable"
  // independently — the local card never waits on it.
  _PublicIpStatus _publicIpStatus = _PublicIpStatus.loading;
  String? _publicIp;

  @override
  void initState() {
    super.initState();
    if (NetworkSupport.interfaceInfoSupported) {
      _service = widget.service ?? InterfaceInfoService();
      _publicIpService = widget.publicIpService ?? PublicIpService();
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
    _loadPublicIp();
  }

  /// Fetches the device's public IP independently of the local snapshot. Never
  /// throws — a failure resolves to the honest "Unavailable" state (GL-005).
  void _loadPublicIp() {
    setState(() {
      _publicIpStatus = _PublicIpStatus.loading;
      _publicIp = null;
    });
    _publicIpService!.fetch().then((String? ip) {
      if (!mounted) return;
      setState(() {
        _publicIp = ip;
        _publicIpStatus = ip == null
            ? _PublicIpStatus.unavailable
            : _PublicIpStatus.loaded;
      });
      // WCAG 4.1.3 — an AT user who heard "Public IP, Looking up…" must hear
      // the resolution, not silence. The loaded row (a ValueRow) and the
      // unavailable row carry no live region of their own, so announce the
      // transition explicitly here. The unavailable row is also wrapped in a
      // liveRegion below for AT that re-reads on rebuild.
      SemanticsService.sendAnnouncement(
        View.of(context),
        ip == null
            ? 'Public IP unavailable, no internet or blocked.'
            : 'Public IP $ip',
        Directionality.of(context),
      );
    }).catchError((Object _) {
      if (!mounted) return;
      setState(() => _publicIpStatus = _PublicIpStatus.unavailable);
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Public IP unavailable, no internet or blocked.',
        Directionality.of(context),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Interface Info'),
        toolbarHeight: 64,
        // §8.16 — copy leads, the meta action (refresh) trails. Help is NOT in
        // the AppBar: per §8.16.1 it lives in the body footer (`ToolHelpFooter`
        // in `_Success`), so the AppBar carries only the copy and refresh
        // actions. Copy is disabled until a read completes.
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
    // Public IP is a separate async fetch; copy reflects whatever state it is in.
    switch (_publicIpStatus) {
      case _PublicIpStatus.loaded:
        line('Public IP', _publicIp);
      case _PublicIpStatus.unavailable:
        line('Public IP', 'Unavailable (no internet / blocked)');
      case _PublicIpStatus.loading:
        // Omit while still resolving — copy never reports a half-read value.
        break;
    }
    line('Hostname', data.hostname);

    // Wi-Fi link.
    final WifiLinkInfo w = data.wifi;
    buf.writeln();
    buf.writeln('Wi-Fi link');
    if (w.ssid == null && w.locationNeeded) {
      line('SSID', 'Needs Location Services (macOS)');
    } else {
      line('SSID', w.ssid);
      line('BSSID', w.bssid);
    }
    line('IPv4', w.wifiIPv4);
    line('IPv6', w.wifiIPv6);
    line('Subnet mask', w.subnetMask);
    line('Gateway', w.gatewayIP);
    line('Interface', w.interfaceName);
    line('Hardware Address', w.hardwareAddress);
    line('MAC type', MacRandomizationClassifier.label(w.hardwareAddress));

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
            return _Success(
              data: data,
              edge: edge,
              isDesktop: isDesktop,
              publicIpStatus: _publicIpStatus,
              publicIp: _publicIp,
            );
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
    required this.publicIpStatus,
    required this.publicIp,
  });

  final InterfaceInfoSnapshot data;
  final double edge;
  final bool isDesktop;
  final _PublicIpStatus publicIpStatus;
  final String? publicIp;

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
              ToolHelpFooter(toolId: 'interface-info'),
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
          // Public IP sits directly beneath the local Primary IPv4 so the user
          // can compare the address their device holds vs the address the
          // internet sees them as (NAT). Its own async state.
          _PublicIpRow(status: publicIpStatus, ip: publicIp),
          ValueRow(label: 'Hostname', value: data.hostname),
        ],
      ),
    );
  }

  Widget _wifiCard(BuildContext context) {
    final WifiLinkInfo w = data.wifi;
    final bool showLocationHint = w.ssid == null && w.locationNeeded;
    return _Card(
      title: 'Wi-Fi link',
      child: Column(
        children: [
          ValueRow(label: 'SSID', value: w.ssid),
          if (showLocationHint) const _LocationHint(),
          ValueRow(label: 'BSSID', value: w.bssid, identifier: true),
          ValueRow(label: 'IPv4', value: w.wifiIPv4, identifier: true),
          ValueRow(label: 'IPv6', value: w.wifiIPv6, identifier: true),
          ValueRow(label: 'Subnet mask', value: w.subnetMask, identifier: true),
          ValueRow(label: 'Gateway', value: w.gatewayIP, identifier: true),
          ValueRow(label: 'Interface', value: w.interfaceName, identifier: true),
          ValueRow(
            label: 'Hardware Address',
            value: w.hardwareAddress,
            identifier: true,
          ),
          _MacTypeRow(hardwareAddress: w.hardwareAddress),
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

/// The Public IP row: a [ValueRow]-shaped line that reflects the separate
/// public-IP fetch state — a labeled spinner while loading, the address once
/// fetched, or an honest "Unavailable" when no internet / blocked (GL-005).
/// Loading/unavailable get their own treatment rather than reusing ValueRow's
/// "Not available on this platform" copy (the platform is fine; the network is
/// the variable).
class _PublicIpRow extends StatelessWidget {
  const _PublicIpRow({required this.status, required this.ip});

  final _PublicIpStatus status;
  final String? ip;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _PublicIpStatus.loaded:
        return ValueRow(label: 'Public IP', value: ip, identifier: true);
      case _PublicIpStatus.loading:
        return const _PublicIpPendingRow(
          message: 'Looking up…',
          showSpinner: true,
        );
      case _PublicIpStatus.unavailable:
        return const _PublicIpPendingRow(
          message: 'Unavailable (no internet / blocked)',
          showSpinner: false,
        );
    }
  }
}

/// The loading / unavailable presentation of the Public IP row. Label left,
/// status right in muted italic text; the loading variant adds a small spinner.
///
/// Both variants are wrapped in a `liveRegion` Semantics so an assistive-tech
/// user who heard "Public IP, Looking up…" also hears the *resolution* on
/// rebuild rather than silence (WCAG 4.1.3). The success/failure transition is
/// additionally announced imperatively from `_loadPublicIp` via
/// `SemanticsService.announce` — the live region here is the redundant,
/// rebuild-driven half that AT which re-reads liveRegions will pick up.
class _PublicIpPendingRow extends StatelessWidget {
  const _PublicIpPendingRow({required this.message, required this.showSpinner});

  final String message;

  /// Loading-only: shows the inline progress spinner beside the status text.
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget statusText = Text(
      message,
      textAlign: TextAlign.right,
      style: (text.bodyLarge ?? const TextStyle()).copyWith(
        color: AppColors.textTertiary,
        fontStyle: FontStyle.italic,
      ),
    );

    final Widget right = showSpinner
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(child: statusText),
            ],
          )
        : statusText;

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: ValueRow.labelColumnWidth,
            child: Text(
              'Public IP',
              style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: right),
        ],
      ),
    );

    return Semantics(
      liveRegion: true,
      label: 'Public IP, $message',
      excludeSemantics: true,
      child: content,
    );
  }
}

/// The honest "needs Location Services" hint shown under an empty SSID on macOS.
/// Mirrors the Wi-Fi Information tool's Location messaging so the empty name
/// reads as a permission gate, not a platform limitation.
class _LocationHint extends StatelessWidget {
  const _LocationHint();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        'The network name needs Location Services for this app on macOS. '
        'Enable it in System Settings, or read the name in the Wi-Fi '
        'Information tool, which can request it.',
        style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

/// The derived "MAC type" row beneath the Hardware Address: classifies the MAC's
/// locally-administered bit as Randomized vs Universal, or — when the MAC is
/// unreadable (null, blank, or the iOS sentinel) — shows the honest
/// platform-limitation note instead of a meaningless flag (GL-005).
class _MacTypeRow extends StatelessWidget {
  const _MacTypeRow({required this.hardwareAddress});

  final String? hardwareAddress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final MacRandomization kind =
        MacRandomizationClassifier.classify(hardwareAddress);
    final String label = MacRandomizationClassifier.label(hardwareAddress);
    final bool unreadable = kind == MacRandomization.unreadable;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: 'MAC type, $label',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ValueRow.labelColumnWidth,
              child: Text(
                'MAC type',
                style:
                    text.labelMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: (text.bodyMedium ?? const TextStyle()).copyWith(
                  color: unreadable
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                  fontStyle: unreadable ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
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
