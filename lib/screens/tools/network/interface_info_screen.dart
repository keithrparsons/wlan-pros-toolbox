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
import '../../../services/network/shortcuts_config.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class InterfaceInfoScreen extends StatefulWidget {
  const InterfaceInfoScreen({
    super.key,
    this.service,
    this.publicIpService,
    this.iosBridge,
    this.wifiSourceOverride,
  });

  /// Injectable for tests; defaults to the real service off-web.
  final InterfaceInfoService? service;

  /// Injectable public-IP fetcher for tests; defaults to the real service.
  final PublicIpService? publicIpService;

  /// Injectable iOS Shortcuts bridge (tests). Drives the on-demand "Refresh
  /// Wi-Fi" affordance (Batch 8, item 1): fires the one-shot "WLAN Pros Wi-Fi"
  /// Shortcut so the user can populate the shared reading directly when the
  /// cache is cold, without first visiting the Wi-Fi Information tool. Defaults
  /// to the real bridge.
  final WiFiDetailsBridge? iosBridge;

  /// Forces the Wi-Fi data source (tests). Defaults to the host platform, so the
  /// iOS-only "Refresh Wi-Fi" affordance is shown only on the iOS Shortcut path.
  final WifiInfoSource? wifiSourceOverride;

  @override
  State<InterfaceInfoScreen> createState() => _InterfaceInfoScreenState();
}

/// The async state of the Public IP row: a separate network fetch from the local
/// snapshot, so it carries its own loading / value / unavailable state.
enum _PublicIpStatus { loading, loaded, unavailable }

class _InterfaceInfoScreenState extends State<InterfaceInfoScreen>
    with WidgetsBindingObserver {
  InterfaceInfoService? _service;
  PublicIpService? _publicIpService;
  Future<InterfaceInfoSnapshot>? _future;

  /// iOS Shortcuts bridge for the on-demand "Refresh Wi-Fi" affordance, and the
  /// resolved Wi-Fi source so the affordance only appears on the iOS Shortcut
  /// path (item 1). Both null off the supported/native path.
  WiFiDetailsBridge? _iosBridge;
  WifiInfoSource? _wifiSource;

  /// True while the one-shot "WLAN Pros Wi-Fi" Shortcut bounce is in flight, so
  /// the Refresh Wi-Fi button shows a pending state and the resume re-read knows
  /// to expect a freshly stored payload.
  bool _refreshingWifi = false;

  /// The platform that owns an unreadable-MAC reason note, derived from the
  /// resolved Wi-Fi source, so the "MAC type" row names the RIGHT OS limit (the
  /// S24 bug was the iOS "Apple does not expose…" reason leaking onto Android).
  /// macOS reads the real burned-in MAC, so its unreadable case (rare) falls to
  /// the generic note.
  MacAddressPlatform get _macPlatform {
    switch (_wifiSource) {
      case WifiInfoSource.iosShortcuts:
        return MacAddressPlatform.ios;
      case WifiInfoSource.androidWifiManager:
        return MacAddressPlatform.android;
      case WifiInfoSource.macosCoreWlan:
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
      case null:
        return MacAddressPlatform.other;
    }
  }

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
      _wifiSource = widget.wifiSourceOverride ?? WifiInfoSourceResolver.resolve();
      // The on-demand Refresh Wi-Fi affordance is the iOS Shortcut path only;
      // macOS already re-reads the link directly via the AppBar Refresh.
      if (_wifiSource == WifiInfoSource.iosShortcuts) {
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
        WidgetsBinding.instance.addObserver(this);
      }
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS: the one-shot "WLAN Pros Wi-Fi" Shortcut bounces the user to the
    // Shortcuts app and back. On return, re-read so the freshly stored Wi-Fi
    // payload (now in the shared cache via readLatest) surfaces here without a
    // manual Refresh tap.
    if (state == AppLifecycleState.resumed && _refreshingWifi) {
      _refreshingWifi = false;
      if (mounted) _load();
    }
  }

  @override
  void dispose() {
    if (_iosBridge != null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  /// iOS on-demand "Refresh Wi-Fi" (item 1). Fires the one-shot "WLAN Pros Wi-Fi"
  /// Shortcut, which harvests the connected AP and stores it where the shared
  /// cache / readLatest path picks it up. This IS a user-initiated bounce to the
  /// Shortcuts app — acceptable because the user explicitly asked to read the
  /// Wi-Fi identity; it is NOT an at-launch auto-run. On resume the snapshot
  /// re-reads (see [didChangeAppLifecycleState]). A failure to open the Shortcut
  /// leaves the row honestly unchanged.
  Future<void> _refreshWifi() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    setState(() => _refreshingWifi = true);
    final bool opened =
        await bridge.runShortcut(ShortcutsConfig.kCompanionShortcutName);
    if (!mounted) return;
    if (!opened) {
      // Could not open the Shortcut (missing / not installed). Drop the pending
      // state; the row stays as-is and the user can install it from the Wi-Fi
      // Information tool. No fabricated value (GL-005).
      setState(() => _refreshingWifi = false);
    }
    // When opened, the bounce is now in flight; the resume handler re-reads.
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
    line(
      'MAC type',
      MacRandomizationClassifier.label(
        w.hardwareAddress,
        platform: _macPlatform,
      ),
    );

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
              // iOS-only on-demand Wi-Fi read. Null off the iOS Shortcut path so
              // the affordance never shows where the link is read directly.
              onRefreshWifi:
                  _wifiSource == WifiInfoSource.iosShortcuts ? _refreshWifi : null,
              refreshingWifi: _refreshingWifi,
              macPlatform: _macPlatform,
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
    required this.onRefreshWifi,
    required this.refreshingWifi,
    required this.macPlatform,
  });

  final InterfaceInfoSnapshot data;
  final double edge;
  final bool isDesktop;
  final _PublicIpStatus publicIpStatus;
  final String? publicIp;

  /// iOS-only: fires the one-shot Wi-Fi Shortcut to populate SSID/BSSID on
  /// demand (item 1). Null off the iOS Shortcut path.
  final Future<void> Function()? onRefreshWifi;

  /// True while the Wi-Fi Shortcut bounce is in flight (button pending state).
  final bool refreshingWifi;

  /// The platform whose limitation the unreadable-MAC note names, so the row
  /// never leaks one OS's wording onto another (GL-005 / GL-008).
  final MacAddressPlatform macPlatform;

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

  /// "as of 2:14 PM" — 12-hour clock, no intl dependency. Matches the
  /// time-format convention already used in test_my_connection_screen.dart.
  static String _asOfClock(DateTime at) {
    final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String minute = at.minute.toString().padLeft(2, '0');
    final String meridiem = at.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $meridiem';
  }

  Widget _wifiCard(BuildContext context) {
    final WifiLinkInfo w = data.wifi;
    final bool showLocationHint = w.ssid == null && w.locationNeeded;
    // iOS Refresh Wi-Fi affordance: shown when the iOS path is active AND the
    // network name has not been read this session (cold cache). Once any tool
    // has a reading, the cache fills it in and the prompt disappears (item 1).
    final bool showWifiRefresh =
        onRefreshWifi != null && w.ssid == null && !w.locationNeeded;
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
          _MacTypeRow(
            hardwareAddress: w.hardwareAddress,
            platform: macPlatform,
          ),
          // When the Wi-Fi identity was served FROM THE CACHE (a remembered
          // reading, not a fresh native/live read), say so honestly with an
          // "as of HH:MM" line so it is never mistaken for a live reading. A
          // fresh read leaves cachedAt null and this line never shows
          // (Batch 8 truthfulness fix).
          if (w.cachedAt != null) _CacheAsOfLine(at: w.cachedAt!),
          if (showWifiRefresh)
            _RefreshWifiPrompt(
              onRefresh: onRefreshWifi!,
              pending: refreshingWifi,
            ),
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
            title,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final Widget statusText = Text(
      message,
      textAlign: TextAlign.right,
      style: (text.bodyLarge ?? const TextStyle()).copyWith(
        color: colors.textTertiary,
        fontStyle: FontStyle.italic,
      ),
    );

    final Widget right = showSpinner
        ? Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.textAccent,
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
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        'The network name needs Location Services for this app on macOS. '
        'Enable it in System Settings, or read the name in the Wi-Fi '
        'Information tool, which can request it.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

/// The honest "as of HH:MM" line shown beneath the Wi-Fi identity rows when that
/// identity was served from the shared cache (a remembered reading) rather than
/// a fresh native/live read (Batch 8 truthfulness fix). It tells the user the
/// SSID/BSSID/MAC are a remembered reading and when it was taken, so a cached
/// identity is never silently presented as current. Fresh reads carry no
/// `cachedAt`, so this line never appears for them.
class _CacheAsOfLine extends StatelessWidget {
  const _CacheAsOfLine({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String clock = _Success._asOfClock(at);
    final String message = 'Remembered reading, as of $clock. '
        'Refresh to read the connected network live.';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.history,
            size: 14,
            color: colors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS-only on-demand "Refresh Wi-Fi" prompt (Batch 8, item 1). Shown under the
/// Wi-Fi link rows when the network name has not been read this session. Tapping
/// it fires the one-shot "WLAN Pros Wi-Fi" Shortcut (a user-initiated bounce to
/// the Shortcuts app and back), which harvests the connected AP and stores it
/// where the shared cache picks it up — so the user can populate SSID/BSSID here
/// directly, without first opening the Wi-Fi Information tool. This is NOT an
/// at-launch auto-run; it fires only on an explicit tap.
class _RefreshWifiPrompt extends StatelessWidget {
  const _RefreshWifiPrompt({required this.onRefresh, required this.pending});

  final Future<void> Function() onRefresh;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The network name has not been read yet this session. Read it from '
            'the connected network — this opens the WLAN Pros Wi-Fi Shortcut, '
            'then returns here.',
            style: text.bodySmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              enabled: !pending,
              // Fold the pending state into the explicit label, and
              // excludeSemantics so the OutlinedButton.icon's own label does not
              // double-announce (matches _MacTypeRow / _PublicIpPendingRow).
              label: pending
                  ? 'Reading Wi-Fi, running the WLAN Pros Wi-Fi Shortcut'
                  : 'Refresh Wi-Fi by running the WLAN Pros Wi-Fi Shortcut',
              excludeSemantics: true,
              child: OutlinedButton.icon(
                onPressed: pending ? null : () => onRefresh(),
                icon: pending
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textAccent,
                        ),
                      )
                    : const Icon(Icons.wifi_find, size: 18),
                label: Text(pending ? 'Reading…' : 'Refresh Wi-Fi'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The derived "MAC type" row beneath the Hardware Address: classifies the MAC's
/// locally-administered bit as Randomized vs Universal, or — when the MAC is
/// unreadable (null, blank, or the iOS sentinel) — shows the honest
/// platform-limitation note instead of a meaningless flag (GL-005).
class _MacTypeRow extends StatelessWidget {
  const _MacTypeRow({
    required this.hardwareAddress,
    required this.platform,
  });

  final String? hardwareAddress;

  /// The platform whose limitation an unreadable-MAC note names (GL-005).
  final MacAddressPlatform platform;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final MacRandomization kind =
        MacRandomizationClassifier.classify(hardwareAddress);
    final String label =
        MacRandomizationClassifier.label(hardwareAddress, platform: platform);
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
                    text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: (text.bodyMedium ?? const TextStyle()).copyWith(
                  color: unreadable
                      ? colors.textTertiary
                      : colors.textPrimary,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      title: 'Interfaces',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          'No active interfaces with an assigned address.',
          style: text.bodyLarge?.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // WCAG 4.1.3 — a bare progress indicator announces nothing. Label it so
    // VoiceOver/TalkBack speak the loading state. `Semantics` is not a const
    // constructor, so `Center` cannot be const here; the indicator stays const.
    return Center(
      child: Semantics(
        label: 'Reading network state…',
        liveRegion: true,
        child: CircularProgressIndicator(color: colors.textAccent),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not read network state',
              style: text.headlineSmall?.copyWith(color: colors.textPrimary),
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
