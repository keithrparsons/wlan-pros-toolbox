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
//     cannot auto-fire). But the app is NOT blind on iOS: the Wi-Fi Information
//     tool writes every reading it obtains into the app-wide [ConnectedApCache].
//     So on iOS this card READS that shared cache on mount (never firing the
//     Shortcut itself) — if a recent live reading exists, SSID + Signal render
//     the SAME values the Wi-Fi Information tool shows. Only when the cache is
//     cold does the card offer a "Get a live reading" affordance (a user tap
//     routes to the Wi-Fi Information tool, which owns the Shortcut trigger and
//     the install fall-through). Saying "Not reported on iOS" while a live
//     reading already sits in the cache would be a lie (GL-005) — so the card no
//     longer does. The local-network rows (IP/gateway/subnet) and the public
//     IP/ISP still populate independently, because those sources DO work on iOS.
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

import '../../../router/app_router.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/connected_ap_cache.dart';
import '../../../services/network/ip_geo_service.dart';
import '../../../services/network/lan_discovery/subnet_seed.dart';
import '../../../services/network/public_ip_service.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import 'get_reading_icon.dart';

/// How a single glance field resolved. Drives the value rendering:
///   * [loading]      → "Reading…" (the field's read is in flight);
///   * [value]        → a real datum to show;
///   * [notReported]  → this platform never exposes the field (a stable ceiling);
///   * [unavailable]  → a transient failure (offline, blocked) — try again;
///   * [awaitingLiveRead] → iOS-only: the app CAN show this field, but no live
///     reading has been captured yet this session (cold cache). This is neither a
///     platform ceiling nor a failure — it is an idle state the user resolves by
///     tapping "Get a live reading". Never rendered as a value.
enum GlanceFieldState { loading, value, notReported, unavailable, awaitingLiveRead }

/// How long a cached iOS reading stays presentable as "current" before it is
/// treated as cold. Mirrors the Interface Info staleness gate
/// (`InterfaceInfoService.cacheStaleThreshold`), duplicated here rather than
/// imported because that service pulls in `dart:io` (web-unsafe) — a reading
/// older than this belongs to a previous network and must not be shown as live.
const Duration _kIosCacheStaleThreshold = Duration(minutes: 5);

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
  const GlanceField.awaitingLiveRead()
      : this._(GlanceFieldState.awaitingLiveRead, 'Not read yet');

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
    this.apCache,
    this.liveReadingRequester,
  });

  /// Reads the connected AP (SSID + RSSI). Null in production → the per-platform
  /// [WifiInfoAdapter] is used. A test injects a fake that returns a scripted
  /// [ConnectedAp] or throws [WifiInfoUnavailable]. NOT used on the iOS branch
  /// (iOS reads the shared [ConnectedApCache] instead — see [apCache]).
  final Future<ConnectedAp> Function()? wifiFetcher;

  /// The app-wide connected-AP cache the iOS lane READS on mount (never firing
  /// the Shortcut). Null in production → the process-wide
  /// [ConnectedApCache.instance], the SAME cache the Wi-Fi Information tool
  /// writes every reading into. A test injects an isolated instance (warm or
  /// cold) to drive the iOS branch deterministically.
  final ConnectedApCache? apCache;

  /// Obtains a fresh live reading on the iOS "Get a live reading" tap. Null in
  /// production → [_defaultLiveReadingRequest], which routes to the Wi-Fi
  /// Information tool (the SSOT for the Shortcut trigger + the install
  /// fall-through) and returns the reading it cached. Returns null when no
  /// reading could be obtained (Shortcut not installed / user cancelled) — the
  /// card then keeps the affordance rather than lying with "Not reported". A
  /// test injects a fake returning a scripted [ConnectedAp] (or null). Fired
  /// ONLY by an explicit user tap — never on mount.
  final Future<ConnectedAp?> Function()? liveReadingRequester;

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

  /// The shared connected-AP cache the iOS lane reads. Resolved once from the
  /// injected cache or the process-wide singleton.
  late final ConnectedApCache _apCache;

  /// iOS-only: true when the cache was cold on the last read, so the SSID/Signal
  /// rows sit in the idle "Not read yet" state and the "Get a live reading"
  /// affordance is offered. False once a reading (cached or freshly obtained) is
  /// on screen.
  bool _iosNeedsLiveReading = false;

  /// iOS-only: true while a user-initiated live reading is in flight (the
  /// "Get a live reading" tap). Hides the affordance and shows the rows as
  /// "Reading…" until the requester resolves.
  bool _iosLiveReadInFlight = false;

  @override
  void initState() {
    super.initState();
    _apCache = widget.apCache ?? ConnectedApCache.instance;
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
    // iOS: the app cannot AUTO-read the link (the reading comes from a
    // user-installed Shortcut that must not auto-fire). But the Wi-Fi
    // Information tool writes every reading it captures into the shared
    // [ConnectedApCache], so on mount/refresh we READ that cache (never firing
    // the Shortcut). A recent reading renders the real SSID + Signal — the same
    // values the other tool shows; a cold cache offers "Get a live reading"
    // instead of the false "Not reported on iOS".
    if (!kIsWeb && _platform == TargetPlatform.iOS) {
      _loadIosWifiFromCache();
      return;
    }

    if (!_wifiAutoReadable) {
      // web / other unsupported native: the app cannot read the link at all —
      // state it honestly, per-field, instead of a blank that implies "no Wi-Fi".
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

  /// iOS Lane 1 — SSID + Signal from the shared [ConnectedApCache] (READ-ONLY;
  /// never fires the Shortcut). A recent reading renders the real SSID + Signal,
  /// matching the Wi-Fi Information tool. A cold/stale cache drops to the idle
  /// "Not read yet" state and flags the "Get a live reading" affordance.
  void _loadIosWifiFromCache() {
    if (!mounted) return;
    final ConnectedAp? cached = _freshCachedReading();
    if (cached != null && (cached.ssid != null || cached.rssiDbm != null)) {
      setState(() {
        _iosNeedsLiveReading = false;
        _iosLiveReadInFlight = false;
        _snapshot = _snapshot.copyWith(
          ssid: _iosSsidField(cached),
          signal: _iosSignalField(cached),
        );
      });
      return;
    }
    // Cold cache: honest idle state + the actionable affordance. NOT "Not
    // reported on iOS" (a lie once the tool has ever cached a reading).
    setState(() {
      _iosNeedsLiveReading = true;
      _iosLiveReadInFlight = false;
      _snapshot = _snapshot.copyWith(
        ssid: const GlanceField.awaitingLiveRead(),
        signal: const GlanceField.awaitingLiveRead(),
      );
    });
  }

  /// The most-recent cached reading, but only when it is fresh enough to present
  /// as current (mirrors the Interface Info staleness gate: a reading older than
  /// [_kIosCacheStaleThreshold] belongs to a previous network and is treated as
  /// cold). Null when the cache is empty, data-empty, or stale.
  ConnectedAp? _freshCachedReading() {
    final ConnectedAp? cached = _apCache.latest;
    final DateTime? at = _apCache.updatedAt;
    if (cached == null || !cached.hasAnyData || at == null) return null;
    final bool fresh =
        DateTime.now().difference(at) < _kIosCacheStaleThreshold;
    return fresh ? cached : null;
  }

  GlanceField _iosSsidField(ConnectedAp ap) => ap.ssid != null
      ? GlanceField.value(ap.ssid!)
      : const GlanceField.unavailable('Not in this reading');

  GlanceField _iosSignalField(ConnectedAp ap) => ap.rssiDbm != null
      ? GlanceField.value('${ap.rssiDbm} dBm')
      : const GlanceField.unavailable('No signal reading');

  /// iOS "Get a live reading" tap: obtains a fresh reading through the injected
  /// [NetworkGlanceCard.liveReadingRequester] (default: route to the Wi-Fi
  /// Information tool). Fired ONLY here, by an explicit user gesture. On success
  /// the SSID + Signal rows populate from the real reading; on a null result
  /// (Shortcut not installed / cancelled) the affordance stays — never a dead
  /// "Not reported" string.
  Future<void> _requestIosLiveReading() async {
    if (_iosLiveReadInFlight) return;
    setState(() {
      _iosLiveReadInFlight = true;
      _snapshot = _snapshot.copyWith(
        ssid: const GlanceField.loading(),
        signal: const GlanceField.loading(),
      );
    });

    final Future<ConnectedAp?> Function() request =
        widget.liveReadingRequester ?? _defaultLiveReadingRequest;
    ConnectedAp? reading;
    try {
      reading = await request();
    } on Object {
      reading = null;
    }
    if (!mounted) return;

    if (reading != null && (reading.ssid != null || reading.rssiDbm != null)) {
      // A genuine reading: share it app-wide (consistency with the Wi-Fi
      // Information tool's cache) and render it.
      _apCache.update(reading);
      setState(() {
        _iosLiveReadInFlight = false;
        _iosNeedsLiveReading = false;
        _snapshot = _snapshot.copyWith(
          ssid: _iosSsidField(reading!),
          signal: _iosSignalField(reading),
        );
      });
      return;
    }

    // No reading obtained. The install/onboarding fall-through already happened
    // in the Wi-Fi Information tool; keep the honest idle state + affordance.
    setState(() {
      _iosLiveReadInFlight = false;
      _iosNeedsLiveReading = true;
      _snapshot = _snapshot.copyWith(
        ssid: const GlanceField.awaitingLiveRead(),
        signal: const GlanceField.awaitingLiveRead(),
      );
    });
  }

  /// Default production live-reading request: route to the Wi-Fi Information
  /// tool, which owns the "WLAN Pros Live" Shortcut trigger, the app-lifecycle
  /// bounce handling, and the companion-install fall-through — so no bridge
  /// logic is duplicated here. On return, read whatever reading the tool cached.
  Future<ConnectedAp?> _defaultLiveReadingRequest() async {
    if (!mounted) return null;
    await Navigator.of(context).pushNamed(AppRouter.wifiInfo);
    return _freshCachedReading();
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
          // iOS-only: when no fresh live reading is cached, offer to get one
          // (an explicit tap → the Wi-Fi Information tool's Shortcut flow),
          // instead of the false "Not reported on iOS".
          if (_iosNeedsLiveReading && !_iosLiveReadInFlight) _getReadingAction(),
          _row(context, 'Local IP', _snapshot.localIp, identifier: true),
          _row(context, 'Gateway', _snapshot.gateway, identifier: true),
          _row(context, 'Subnet', _snapshot.subnet, identifier: true),
          _row(context, 'Public IP', _snapshot.publicIp, identifier: true),
          _row(context, 'ISP', _snapshot.isp, identifier: false),
        ],
      ),
    );
  }

  /// iOS "Get a live reading" affordance (§8.6.1 custom icon + §8.3 focus ring).
  /// A prominent [FilledButton.icon] with the custom [GetReadingIcon] (a generic
  /// Material glyph here would be a flag per [[feedback_custom_icons]]). The
  /// button inherits the theme's focus ring and its foreground/background clear
  /// WCAG 2.2 AA (the lime-on-ink primary pair, GL-003 §8.2). The enclosing
  /// [Semantics] carries the accessible name so the decorative glyph is silent.
  Widget _getReadingAction() {
    const String label = 'Get a live reading';
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xxs,
        bottom: AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: label,
          child: FilledButton.icon(
            onPressed: _requestIosLiveReading,
            icon: const GetReadingIcon(size: 18),
            label: const Text(label),
          ),
        ),
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
