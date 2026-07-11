// Network Discovery tool (TICKET-HSD-02 W1/W2) — scan the local network for
// live hosts and enrich each with hostname, services, device type, and
// (desktop) MAC + vendor.
//
// This is the production screen that replaces the throwaway SPIKE-HSD-01 debug
// surface. The validated engine is preserved verbatim (3-state TCP connect-scan
// in a background isolate, in-house NetServiceBrowser mDNS, sandbox-safe sysctl
// ARP read, reverse-DNS PTR, device-type heuristic); this screen wires it to a
// GL-003-styled UI and routes MAC→vendor through the full bundled IEEE registry
// (MacOuiService, W2).
//
// States (SOP-007 §5):
//  - idle      → concept band + a single "Scan local network" action; no list.
//  - loading   → live progress (phase + percent + probed-count note) and a
//                "Stop" action; the dwell is surfaced so the screen never looks
//                frozen during the ~4s mDNS window.
//  - success   → a host list, each row carrying IP, hostname, MAC + vendor,
//                services, and device type; plus a scan-summary line.
//  - empty     → scan finished, nothing responded — a valid, informative state,
//                not an error.
//  - error     → the engine could not derive a subnet / the scan failed; an
//                honest reason, never a fabricated result.
//  - desktop MAC/vendor ceiling → when the ARP read is unavailable (every
//                non-macOS platform), an honest one-line note explains why no
//                MAC/vendor column appears — not a blank "Manufacturer: —".
//  - web        → NetworkUnavailableView (the socket engine needs dart:io).
//
// NOT feature-complete: W3 (multi-VLAN grouping), W4 (IPv6), W5 (per-host
// detail + export), W6 (permission UX) are later rounds. The Vera SOP-009 gate
// is W7, not now. This is GL-003-compliant production UI, not ship-ready.
//
// Accessibility (GL-003 §8.9): the scan/stop button carries an explicit label,
// progress is announced via a live region, scan completion + host count are
// announced (WCAG 4.1.3), each host row collapses to one curated screen-reader
// label, and every interactive surface keeps the §8.3 focus treatment from the
// theme. Status hue is never the sole carrier of meaning — device type and
// liveness are always worded.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../data/tool_assets.dart';
import '../../../services/network/chromeos_arc.dart';
import '../../../services/network/lan_discovery/arp_reader.dart';
import '../../../services/network/lan_discovery/device_type.dart';
import '../../../services/network/lan_discovery/lan_discovery_engine.dart';
import '../../../services/network/lan_discovery/lan_host.dart';
import '../../../services/network/mac_oui_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'network_glance_card.dart';
import 'network_unavailable_view.dart';

class NetworkDiscoveryScreen extends StatefulWidget {
  const NetworkDiscoveryScreen({
    super.key,
    this.engineFactory,
    this.service,
    this.glanceCard,
  });

  /// M2 — the "Network at a glance" card shown at the top, before any scan.
  /// Null in production → a real [NetworkGlanceCard] (which reads SSID/IP/
  /// gateway/subnet/public-IP/ISP through the shared services). Tests inject a
  /// stub (e.g. `SizedBox.shrink()`) so the scan-state widget tests stay off the
  /// network and off any platform channel.
  final Widget? glanceCard;

  /// Engine factory seam so tests can inject a fake engine. Null in production,
  /// where a real [LanDiscoveryEngine] (isolate connect-scan) is built, wired
  /// to the bundled IEEE OUI registry once it has loaded.
  final LanDiscoveryEngine Function()? engineFactory;

  /// Inject a pre-built [MacOuiService] in tests so no asset load is required.
  /// In app code this is null and the registry asset loads in the background;
  /// the scan still runs before the registry is ready (vendor stays null until
  /// it loads, never fabricated).
  final MacOuiService? service;

  @override
  State<NetworkDiscoveryScreen> createState() => _NetworkDiscoveryScreenState();
}

class _NetworkDiscoveryScreenState extends State<NetworkDiscoveryScreen> {
  /// Desktop breakpoint, consistent with the other network tools.
  static const double _desktopBreakpoint = 720;

  StreamSubscription<DiscoveryProgress>? _sub;
  LanDiscoveryEngine? _engine;

  bool _scanning = false;
  DiscoveryPhase _phase = DiscoveryPhase.idle;
  double _fraction = 0;
  String? _note;
  DiscoveryResult? _result;
  String? _error;
  bool _ranOnce = false;

  // W2 — the bundled IEEE registry, loaded once. Null until the asset parses;
  // the scan can still run before it lands (vendor stays null, never faked).
  MacOuiService? _oui;

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _oui = widget.service;
    } else {
      _loadOuiRegistry();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadOuiRegistry() async {
    try {
      final String raw = await rootBundle.loadString(
        'assets/oui/oui_table.tsv',
      );
      final Map<String, String> table = MacOuiService.parseTable(raw);
      if (!mounted) return;
      setState(() => _oui = MacOuiService.fromTable(table));
    } on Object {
      // A failed registry load is non-fatal: the scan still runs and reports
      // hosts; MAC rows just stay vendor-less rather than fabricated. No error
      // surface — vendor enrichment is best-effort (GL-005).
    }
  }

  void _scan() {
    final LanDiscoveryEngine engine =
        widget.engineFactory?.call() ??
        LanDiscoveryEngine(
          // W2 — resolve MAC→vendor through the full bundled IEEE registry once
          // it is loaded; before that, no vendor (never fabricated).
          vendorResolver: (String mac) => _oui?.vendorLabelFor(mac),
        );
    _engine = engine;

    setState(() {
      _scanning = true;
      _ranOnce = true;
      _phase = DiscoveryPhase.seeding;
      _fraction = 0;
      _note = null;
      _result = null;
      _error = null;
    });

    _sub = engine.run().listen(
      (DiscoveryProgress p) {
        if (!mounted) return;
        setState(() {
          _phase = p.phase;
          _fraction = p.fraction;
          if (p.note != null) _note = p.note;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _error = '$e';
        });
        _announce('Scan failed.');
      },
      onDone: () {
        if (!mounted) return;
        final DiscoveryResult? r = engine.lastResult;
        setState(() {
          _scanning = false;
          _result = r;
        });
        // WCAG 4.1.3 — announce the outcome to assistive tech.
        if (r == null || r.error != null) {
          _announce('Scan could not complete.');
        } else {
          final int n = r.hosts.length;
          _announce('Scan complete. $n host${n == 1 ? '' : 's'} found.');
        }
      },
    );
  }

  void _stop() {
    // Cancelling the engine stream tears down the underlying isolate / mDNS
    // stream via the engine's own cleanup. A full cooperative-cancel API is W8;
    // for now stopping detaches the UI and marks the run ended honestly.
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _result = _engine?.lastResult;
    });
    _announce('Scan stopped.');
  }

  void _announce(String message) {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Discovery'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a scan has
        // produced hosts; copies the host table as TSV (header + one row per
        // host). Copy leads; this screen has no help icon, so copy is the only
        // action (it still lands in the same trailing slot the order rule
        // reserves for it).
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the discovered host table as TSV.
  ///
  /// Returns null (→ disabled affordance) until a scan has completed with at
  /// least one host: a failed/empty/in-progress scan has nothing to keep. The
  /// header row names every column the host list shows; each host is one
  /// tab-separated row in the same column order, null/empty cells emitted as
  /// empty strings (never fabricated, GL-005). Set fields (ports, services)
  /// are sorted and space-joined inside their single cell so the row stays
  /// one tab-delimited line.
  String? _buildCopyText() {
    final DiscoveryResult? r = _result;
    if (_scanning || r == null || r.error != null || r.hosts.isEmpty) {
      return null;
    }

    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln(
        <String>[
          'IP',
          'Name',
          'Type',
          'MAC',
          'Vendor',
          'Services',
          'Open ports',
        ].join(tab),
      );

    for (final LanHost h in r.hosts) {
      final String name = h.mdnsName ?? h.hostname ?? '';
      final String services = (h.mdnsServices.toList()..sort()).join(' ');
      final String ports = (h.openPorts.toList()..sort()).join(' ');
      buf.writeln(
        <String>[
          h.ip,
          name,
          h.deviceType.label,
          h.mac ?? '',
          h.vendor ?? '',
          services,
          ports,
        ].join(tab),
      );
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.networkDiscoverySupported) {
      return NetworkUnavailableView(
        toolName: 'Network Discovery',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }

    // CHROMEOS (2026-07-10). This tool's failure here is the WORST shape of the
    // ARC-VM bug, because it does not look like a failure at all — it looks like
    // an answer.
    //
    // The sweep seeds its target range from the device's own address and mask.
    // Inside ARC that is a 100.115.92.x address in a /30 — a subnet with exactly
    // two usable hosts, one of which is us. So the scan runs, completes cleanly,
    // finds nothing, and reports "no devices found" about a school network with
    // two hundred devices on it. There is no error, no empty-state hint, nothing
    // to tip the admin off: it is a confident, wrong, actionable answer, and an
    // admin could reasonably conclude their LAN or their discovery protocols are
    // broken. That is precisely the "confidently wrong is worse than no tool"
    // case, so the tool is not offered here at all.
    //
    // (ARC's traffic IS NAT'd out onto the real LAN, so a DIRECTED probe at a
    // known real address can still work. But this tool does not take a target —
    // it derives one — so there is nothing honest to run. The copy points the
    // user at a device that can do the job.)
    if (ChromeOsArc.isChromeOs) {
      return const NetworkUnavailableView(
        toolName: 'Network Discovery',
        reason: NetworkUnavailableReason.platformApiMissing,
        headline: ChromeOsArc.lanScanUnavailableHeadline,
        message: ChromeOsArc.lanScanUnavailableBody,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= _desktopBreakpoint;
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
                children: <Widget>[
                  ConceptGraphicBand(
                    toolId: 'network-discovery',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('network-discovery'))
                    const SizedBox(height: AppSpacing.md),
                  // M2 — network-at-a-glance, above the scan control.
                  widget.glanceCard ?? const NetworkGlanceCard(),
                  const SizedBox(height: AppSpacing.sm),
                  _controlCard(context),
                  if (_scanning || _note != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _progressCard(context),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    _MessageCard(
                      icon: Icons.error_outline,
                      title: 'Scan failed',
                      body: _error!,
                    ),
                  ],
                  ..._resultSection(context),
                  ToolHelpFooter(toolId: 'network-discovery'),
                ],
              ),
            ),
          ),
        );
      },
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
        children: <Widget>[
          Text(
            'Scan the local subnet for live hosts, then enrich each with its '
            'hostname, advertised services, a device-type guess, and — on '
            'desktop — its MAC address and vendor.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_scanning)
            FilledButton.tonal(onPressed: _stop, child: const Text('Stop'))
          else
            FilledButton(
              onPressed: _scan,
              child: Text(_ranOnce ? 'Scan again' : 'Scan local network'),
            ),
        ],
      ),
    );
  }

  Widget _progressCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final int pct = (_fraction.clamp(0, 1) * 100).round();
    final bool inDwell = _phase == DiscoveryPhase.mdns;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Live region so AT hears progress without stealing focus. One node
          // carries the worded phase + percent; the bar itself is decorative.
          Semantics(
            liveRegion: true,
            label: '${_phaseLabel(_phase)}, $pct percent',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: LinearProgressIndicator(
                      value: _fraction == 0 ? null : _fraction,
                      minHeight: 6,
                      backgroundColor: colors.surface2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors.textAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          _phaseLabel(_phase),
                          style: text.labelMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: mono.inlineCode.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_note != null) ...<Widget>[
            const SizedBox(height: 2),
            ExcludeSemantics(
              child: Text(
                _note!,
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
          if (inDwell) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            ExcludeSemantics(
              child: Text(
                'Listening for Bonjour / mDNS responders (~4 seconds) — slow '
                'devices answer late, so the scan waits.',
                style: text.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _resultSection(BuildContext context) {
    final DiscoveryResult? r = _result;
    if (r == null || r.error != null) {
      // A run that failed to even start (no subnet) reports r.error; surface it
      // as an honest message, not a blank list.
      if (r?.error != null) {
        return <Widget>[
          const SizedBox(height: AppSpacing.sm),
          _MessageCard(
            icon: Icons.wifi_find_outlined,
            title: 'Could not scan',
            body: r!.error!,
          ),
        ];
      }
      return const <Widget>[];
    }

    return <Widget>[
      const SizedBox(height: AppSpacing.sm),
      _summaryCard(context, r),
      const SizedBox(height: AppSpacing.sm),
      if (r.hosts.isEmpty)
        _MessageCard(
          icon: Icons.search_off_outlined,
          title: 'No hosts responded',
          body:
              'No devices on ${r.subnetLabel} answered on the probed ports '
              'or via mDNS. They may be firewalled, asleep, or the subnet may '
              'be empty.',
        )
      else
        _hostListCard(context, r),
    ];
  }

  Widget _summaryCard(BuildContext context, DiscoveryResult r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final int n = r.hosts.length;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$n host${n == 1 ? '' : 's'} found',
            style: text.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _summaryRow(context, 'Subnet', r.subnetLabel, mono),
          if (r.selfIp != null)
            _summaryRow(context, 'This device', r.selfIp!, mono),
          if (r.gateway != null)
            _summaryRow(context, 'Gateway', r.gateway!, mono),
          const SizedBox(height: AppSpacing.xs),
          _macAvailabilityNote(context, r),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context,
    String label,
    String value,
    AppMonoText mono,
  ) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            // _summaryRow only renders IP addresses (self IP, gateway) →
            // Roboto Mono identifier register (GL-003 §8.5).
            child: SelectableText(
              value,
              style: mono.robotoMono.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// Honest MAC/vendor availability line. On macOS the ARP read populates
  /// MAC + vendor; on iOS (and any platform that cannot read the ARP cache) it
  /// is unavailable — say so once here, plainly, rather than render an empty
  /// "Manufacturer: —" on every row (brief anti-pattern #2).
  Widget _macAvailabilityNote(BuildContext context, DiscoveryResult r) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final ArpReadResult? arp = r.arp;
    final String message;
    if (arp != null && arp.available) {
      final int withMac = r.hosts.where((LanHost h) => h.mac != null).length;
      message =
          'MAC + vendor read from the ARP cache — '
          '$withMac of ${r.hosts.length} host${r.hosts.length == 1 ? '' : 's'} '
          'matched.';
    } else {
      message =
          'MAC address and vendor need a desktop ARP read, which this platform '
          'cannot do — those fields are omitted here, not blank.';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.info_outline, size: 16, color: colors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ),
      ],
    );
  }

  Widget _hostListCard(BuildContext context, DiscoveryResult r) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < r.hosts.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: colors.border),
            _HostRow(host: r.hosts[i]),
          ],
        ],
      ),
    );
  }

  String _phaseLabel(DiscoveryPhase phase) => switch (phase) {
    DiscoveryPhase.idle => 'Idle',
    DiscoveryPhase.seeding => 'Finding the local subnet',
    DiscoveryPhase.scanning => 'Probing hosts',
    DiscoveryPhase.resolving => 'Resolving hostnames',
    DiscoveryPhase.mdns => 'Browsing mDNS / Bonjour',
    DiscoveryPhase.arp => 'Reading MAC addresses',
    DiscoveryPhase.complete => 'Complete',
    DiscoveryPhase.failed => 'Failed',
  };
}

/// A Material glyph for each coarse device type — a quiet leading affordance,
/// never the sole carrier of meaning (the worded label sits beside it).
IconData _deviceIcon(DeviceType type) => switch (type) {
  DeviceType.printer => Icons.print_outlined,
  DeviceType.camera => Icons.videocam_outlined,
  DeviceType.speaker => Icons.speaker_outlined,
  DeviceType.mediaStreamer => Icons.cast_outlined,
  DeviceType.appleDevice => Icons.devices_outlined,
  DeviceType.iosDevice => Icons.smartphone_outlined,
  DeviceType.windowsHost => Icons.desktop_windows_outlined,
  DeviceType.accessPoint => Icons.wifi_outlined,
  DeviceType.networkGear => Icons.router_outlined,
  DeviceType.webServer => Icons.dns_outlined,
  DeviceType.sshHost => Icons.terminal_outlined,
  DeviceType.mdnsDevice => Icons.lan_outlined,
  DeviceType.unknown => Icons.device_unknown_outlined,
};

/// One discovered host, rendered as a list row inside the host-list card. Every
/// enrichment field is shown only when present (honest blanks per GL-005), and
/// the whole row collapses to a single curated screen-reader label so AT reads
/// it once rather than field-by-field.
class _HostRow extends StatelessWidget {
  const _HostRow({required this.host});

  final LanHost host;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String ports = (host.openPorts.toList()..sort()).join(', ');
    final String services = (host.mdnsServices.toList()..sort()).join(', ');
    final String? name = host.mdnsName ?? host.hostname;

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: _semanticLabel(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                _deviceIcon(host.deviceType),
                size: 20,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // IP + device type — the row's headline.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: SelectableText(
                          host.ip,
                          // Discovered host IP is an identifier → Roboto Mono.
                          style: mono.robotoMono.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        host.deviceType.label,
                        style: text.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (name != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                  if (host.mac != null) ...<Widget>[
                    const SizedBox(height: 2),
                    _detail(
                      context,
                      mono,
                      host.vendor == null
                          ? host.mac!
                          : '${host.mac}  ·  ${host.vendor}',
                    ),
                  ],
                  if (services.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    _caption(text, colors, 'Services: $services'),
                  ],
                  const SizedBox(height: 2),
                  _caption(
                    text,
                    colors,
                    'Ports: ${ports.isEmpty ? 'none open' : ports}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, AppMonoText mono, String value) {
    final AppColorScheme colors = context.colors;
    // The detail line leads with the host MAC (optionally " · vendor") — a MAC
    // identifier → Roboto Mono (GL-003 §8.5).
    return SelectableText(
      value,
      style: mono.robotoMono.copyWith(color: colors.textSecondary),
    );
  }

  Widget _caption(TextTheme text, AppColorScheme colors, String value) {
    return Text(
      value,
      style: text.labelSmall?.copyWith(color: colors.textTertiary),
    );
  }

  String _semanticLabel() {
    final List<String> parts = <String>['Host ${host.ip}'];
    parts.add(host.deviceType.label);
    final String? name = host.mdnsName ?? host.hostname;
    if (name != null) parts.add('named $name');
    if (host.mac != null) {
      parts.add('MAC ${host.mac}');
      if (host.vendor != null) parts.add('vendor ${host.vendor}');
    }
    if (host.mdnsServices.isNotEmpty) {
      parts.add('services ${(host.mdnsServices.toList()..sort()).join(', ')}');
    }
    final List<int> openPorts = host.openPorts.toList()..sort();
    parts.add(
      openPorts.isEmpty
          ? 'no open ports'
          : 'open ports ${openPorts.join(', ')}',
    );
    return parts.join(', ');
  }
}

/// Shared neutral message card (error / empty / unavailable). Color-free per
/// §8.4 — meaning is carried by the title + body text, never hue alone.
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
        children: <Widget>[
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
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
