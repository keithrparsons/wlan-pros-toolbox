// Network-at-a-glance card (M2) — the essentials about the network this device
// is on, shown at the TOP of the Network Discovery tool BEFORE any scan runs.
//
// WHAT IT SHOWS: SSID, signal, local IP, gateway, subnet, public IP, and ISP.
// Each datum comes from a service the app already ships — nothing new is
// fetched that another tool does not already fetch:
//   * SSID + signal (RSSI)  → the platform Wi-Fi adapter (WifiInfoAdapter),
//                             the same source the Wi-Fi Information tool reads.
//   * local IP / gateway / subnet → SubnetSeedDeriver (network_info_plus), the
//                             same source the scan itself seeds from.
//   * public IP             → PublicIpService (ipify / icanhazip), the shared
//                             "what is my public IP" fetcher.
//   * ISP                   → IpGeoService (ipinfo / geojs), the org/ISP name
//                             for the public egress.
//
// HONESTY (GL-005 / GL-008), load-bearing:
//   * EVERY field is independently optional. A field the current platform
//     cannot expose renders "Not reported" — never a blank that implies zero,
//     never a fabricated value.
//   * iOS does NOT auto-expose SSID/RSSI to a sandboxed app (the Wi-Fi
//     Information tool reaches them only through a user-installed Shortcut that
//     cannot auto-fire). So on iOS the SSID + signal rows say "Not reported on
//     iOS" rather than guess. The local-network rows (IP/gateway/subnet) and
//     the public IP/ISP still populate, because those sources DO work on iOS.
//   * The public IP + ISP need the internet; offline, those two rows say
//     "Unavailable" (a transient/network reason), distinct from "Not reported"
//     (a platform that never exposes the field). The distinction is deliberate.
//
// STATES (SOP-007 §5): the card mounts in `loading` (each field a shimmer-free
// "Reading…"), then resolves each lane independently to success / not-reported /
// unavailable. A manual "Refresh" re-reads. There is no separate error card —
// a failure of any one lane degrades that row honestly, never the whole card.
//
// ACCESSIBILITY (GL-003 §8.3 / §8.9): the refresh control is an IconButton that
// inherits the global focus ring; each row is a label↔value pair read as one
// node by assistive tech; status meaning is always worded ("Not reported",
// "Unavailable"), never carried by color alone.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../../../services/network/connected_ap.dart';
import '../../../services/network/ip_geo_service.dart';
import '../../../services/network/lan_discovery/subnet_seed.dart';
import '../../../services/network/public_ip_service.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';

/// How a single glance field resolved. Drives the value rendering:
///   * [loading]      → "Reading…" (the field's read is in flight);
///   * [value]        → a real datum to show;
///   * [notReported]  → this platform never exposes the field (a stable ceiling);
///   * [unavailable]  → a transient failure (offline, blocked) — try again.
enum GlanceFieldState { loading, value, notReported, unavailable }

/// One resolved glance field: a state plus the value/reason text. Immutable.
@immutable
class GlanceField {
  const GlanceField._(this.state, this.text);

  const GlanceField.loading() : this._(GlanceFieldState.loading, 'Reading…');
  const GlanceField.value(String text)
      : this._(GlanceFieldState.value, text);
  const GlanceField.notReported(String reason)
      : this._(GlanceFieldState.notReported, reason);
  const GlanceField.unavailable(String reason)
      : this._(GlanceFieldState.unavailable, reason);

  final GlanceFieldState state;

  /// The value (when [GlanceFieldState.value]) or the honest reason text.
  final String text;

  bool get isValue => state == GlanceFieldState.value;
}

/// The full snapshot the card renders. Built incrementally as each lane lands;
/// the card setState's a new immutable snapshot each time a lane resolves.
@immutable
class GlanceSnapshot {
  const GlanceSnapshot({
    required this.ssid,
    required this.signal,
    required this.localIp,
    required this.gateway,
    required this.subnet,
    required this.publicIp,
    required this.isp,
  });

  /// Everything loading — the initial mount state.
  const GlanceSnapshot.loading()
      : ssid = const GlanceField.loading(),
        signal = const GlanceField.loading(),
        localIp = const GlanceField.loading(),
        gateway = const GlanceField.loading(),
        subnet = const GlanceField.loading(),
        publicIp = const GlanceField.loading(),
        isp = const GlanceField.loading();

  final GlanceField ssid;
  final GlanceField signal;
  final GlanceField localIp;
  final GlanceField gateway;
  final GlanceField subnet;
  final GlanceField publicIp;
  final GlanceField isp;

  GlanceSnapshot copyWith({
    GlanceField? ssid,
    GlanceField? signal,
    GlanceField? localIp,
    GlanceField? gateway,
    GlanceField? subnet,
    GlanceField? publicIp,
    GlanceField? isp,
  }) {
    return GlanceSnapshot(
      ssid: ssid ?? this.ssid,
      signal: signal ?? this.signal,
      localIp: localIp ?? this.localIp,
      gateway: gateway ?? this.gateway,
      subnet: subnet ?? this.subnet,
      publicIp: publicIp ?? this.publicIp,
      isp: isp ?? this.isp,
    );
  }
}

/// The network-at-a-glance card. Self-contained: it owns its own reads through
/// injectable seams (so a widget test drives it with no real network, no
/// platform channel) and renders the honest per-field result.
class NetworkGlanceCard extends StatefulWidget {
  const NetworkGlanceCard({
    super.key,
    this.wifiFetcher,
    this.seedDeriver,
    this.publicIpService,
    this.ipGeoService,
    this.platformOverride,
  });

  /// Reads the connected AP (SSID + RSSI). Null in production → the per-platform
  /// [WifiInfoAdapter] is used. A test injects a fake that returns a scripted
  /// [ConnectedAp] or throws [WifiInfoUnavailable].
  final Future<ConnectedAp> Function()? wifiFetcher;

  /// Derives the local subnet seed (local IP / gateway / subnet label). Null in
  /// production → a real [SubnetSeedDeriver]; tests inject a fake reader.
  final SubnetSeedDeriver? seedDeriver;

  /// Fetches the public IP. Null in production → a real [PublicIpService].
  final PublicIpService? publicIpService;

  /// Resolves the ISP/org for the public egress. Null in production → a real
  /// [IpGeoService].
  final IpGeoService? ipGeoService;

  /// Forces a platform branch in tests (the SSID/signal "not reported on iOS"
  /// rule). Null in production → the real platform.
  final TargetPlatform? platformOverride;

  @override
  State<NetworkGlanceCard> createState() => _NetworkGlanceCardState();
}

class _NetworkGlanceCardState extends State<NetworkGlanceCard> {
  GlanceSnapshot _snapshot = const GlanceSnapshot.loading();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  TargetPlatform get _platform =>
      widget.platformOverride ?? defaultTargetPlatform;

  /// Whether the current platform can auto-read the SSID/RSSI without a user
  /// gesture. macOS (CoreWLAN) and Android (WifiManager) can; iOS cannot (it
  /// needs the install-once Shortcut, which the app can't fire on mount).
  bool get _wifiAutoReadable {
    if (kIsWeb) return false;
    return _platform == TargetPlatform.macOS ||
        _platform == TargetPlatform.android;
  }

  String get _platformLabel {
    if (kIsWeb) return 'the web';
    return switch (_platform) {
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.android => 'Android',
      _ => 'this platform',
    };
  }

  Future<void> _load() async {
    setState(() {
      _refreshing = true;
      _snapshot = const GlanceSnapshot.loading();
    });
    // Three independent lanes, run concurrently; each updates only its own
    // fields. A slow/failed lane never blocks the others (e.g. the public-IP
    // round-trip does not delay the instant local-subnet read).
    await Future.wait(<Future<void>>[
      _loadWifi(),
      _loadSubnet(),
      _loadPublic(),
    ]);
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  /// Lane 1 — SSID + signal from the platform Wi-Fi adapter.
  Future<void> _loadWifi() async {
    if (!_wifiAutoReadable) {
      // iOS / web: the app cannot auto-read the link — state it honestly,
      // per-field, instead of leaving a blank that implies "no Wi-Fi".
      final String reason = 'Not reported on $_platformLabel';
      if (!mounted) return;
      setState(() => _snapshot = _snapshot.copyWith(
            ssid: GlanceField.notReported(reason),
            signal: GlanceField.notReported(reason),
          ));
      return;
    }

    try {
      final Future<ConnectedAp> Function() fetch =
          widget.wifiFetcher ?? _defaultWifiFetch;
      final ConnectedAp ap = await fetch();
      if (!mounted) return;
      setState(() => _snapshot = _snapshot.copyWith(
            ssid: ap.ssid != null
                ? GlanceField.value(ap.ssid!)
                // A reading arrived but no SSID — on macOS/Android that is the
                // Location-permission gate, not a missing network.
                : const GlanceField.unavailable(
                    'Network name needs Location permission',
                  ),
            signal: ap.rssiDbm != null
                ? GlanceField.value('${ap.rssiDbm} dBm')
                : const GlanceField.unavailable('No signal reading'),
          ));
    } on WifiInfoUnavailable {
      if (!mounted) return;
      const GlanceField gone =
          GlanceField.unavailable('No Wi-Fi reading');
      setState(() => _snapshot = _snapshot.copyWith(ssid: gone, signal: gone));
    } on Object {
      if (!mounted) return;
      const GlanceField gone =
          GlanceField.unavailable('No Wi-Fi reading');
      setState(() => _snapshot = _snapshot.copyWith(ssid: gone, signal: gone));
    }
  }

  /// Lane 2 — local IP / gateway / subnet from the subnet seed (instant, local).
  Future<void> _loadSubnet() async {
    try {
      final SubnetSeedDeriver deriver =
          widget.seedDeriver ?? SubnetSeedDeriver();
      final SubnetSeed seed = await deriver.derive();
      if (!mounted) return;
      setState(() => _snapshot = _snapshot.copyWith(
            localIp: seed.selfIp != null
                ? GlanceField.value(seed.selfIp!)
                : const GlanceField.unavailable('No local IPv4'),
            gateway: seed.gateway != null
                ? GlanceField.value(seed.gateway!)
                : const GlanceField.notReported('Not reported by the OS'),
            subnet: seed.label.isNotEmpty
                ? GlanceField.value(seed.label)
                : const GlanceField.unavailable('Could not derive subnet'),
          ));
    } on Object {
      if (!mounted) return;
      const GlanceField gone = GlanceField.unavailable('Could not read');
      setState(() => _snapshot = _snapshot.copyWith(
            localIp: gone,
            gateway: gone,
            subnet: gone,
          ));
    }
  }

  /// Lane 3 — public IP + ISP from the shared public-IP fetcher + geo service.
  Future<void> _loadPublic() async {
    if (kIsWeb) {
      const GlanceField gone =
          GlanceField.notReported('Not reported on the web');
      if (!mounted) return;
      setState(() => _snapshot = _snapshot.copyWith(publicIp: gone, isp: gone));
      return;
    }
    try {
      final PublicIpService ipService =
          widget.publicIpService ?? PublicIpService();
      final String? ip = await ipService.fetch();
      if (!mounted) return;
      setState(() => _snapshot = _snapshot.copyWith(
            publicIp: ip != null
                ? GlanceField.value(ip)
                : const GlanceField.unavailable('Unavailable (offline?)'),
          ));

      // ISP comes from the geo lookup on the egress IP. A null/failed lookup
      // leaves the ISP row honestly "Unavailable" — never a guessed carrier.
      final IpGeoService geo = widget.ipGeoService ?? IpGeoService();
      final IpGeoResult result = await geo.lookup(rawQuery: '');
      if (!mounted) return;
      setState(() => _snapshot = _snapshot.copyWith(
            isp: (!result.isError && result.isp != null)
                ? GlanceField.value(result.isp!)
                : const GlanceField.unavailable('Unavailable'),
          ));
    } on Object {
      if (!mounted) return;
      const GlanceField gone = GlanceField.unavailable('Unavailable');
      setState(() => _snapshot = _snapshot.copyWith(publicIp: gone, isp: gone));
    }
  }

  Future<ConnectedAp> _defaultWifiFetch() {
    final WifiInfoSource source =
        WifiInfoSourceResolver.resolve(platformOverride: widget.platformOverride);
    final WifiInfoAdapter adapter = switch (source) {
      WifiInfoSource.macosCoreWlan => MacWifiInfoAdapter(),
      WifiInfoSource.androidWifiManager => AndroidWifiInfoAdapter(),
      // iOS/unsupported/web never reach here (gated by _wifiAutoReadable), but
      // be defensive: an unsupported source reads as an honest unavailable.
      _ => throw const WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          'No auto-readable Wi-Fi source on this platform.',
        ),
    };
    return adapter.fetch();
  }

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Network at a glance',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Refresh inherits the global §8.3 focus ring (icon-only control).
              IconButton(
                onPressed: _refreshing ? null : _load,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                iconSize: 20,
                color: colors.textSecondary,
                disabledColor: colors.textDisabled,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          _row(context, 'SSID', _snapshot.ssid, identifier: false),
          _row(context, 'Signal', _snapshot.signal, identifier: false),
          _row(context, 'Local IP', _snapshot.localIp, identifier: true),
          _row(context, 'Gateway', _snapshot.gateway, identifier: true),
          _row(context, 'Subnet', _snapshot.subnet, identifier: true),
          _row(context, 'Public IP', _snapshot.publicIp, identifier: true),
          _row(context, 'ISP', _snapshot.isp, identifier: false),
        ],
      ),
    );
  }

  /// One label↔value row. [identifier] true → render the value in Roboto Mono
  /// (IP/subnet are identifiers, GL-003 §8.5); false → proportional body text
  /// (SSID, signal, ISP are prose-y). A non-value state renders its honest
  /// reason in the tertiary ink, never the identifier mono (it is not a datum).
  Widget _row(
    BuildContext context,
    String label,
    GlanceField field, {
    required bool identifier,
  }) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final Widget value;
    if (field.isValue) {
      value = identifier
          ? SelectableText(
              field.text,
              style: mono.robotoMono.copyWith(color: colors.textPrimary),
            )
          : SelectableText(
              field.text,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            );
    } else {
      // loading / notReported / unavailable — worded, tertiary, never mono.
      value = Text(
        field.text,
        style: text.labelMedium?.copyWith(color: colors.textTertiary),
      );
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$label: ${field.text}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 84,
              child: Text(
                label,
                style: text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: value),
          ],
        ),
      ),
    );
  }
}
