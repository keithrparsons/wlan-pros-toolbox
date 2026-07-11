// Nearby AP Scan (H3) — wired for Android today.
//
// Lists the access points visible to a Wi-Fi scan and draws a simple
// channel-occupancy bar per band. The data comes from the Android
// `com.wlanpros.toolbox/ap_scan` method channel (MainActivity.kt →
// WifiManager.getScanResults()).
//
// Per-platform reality (GL-005 honesty): iOS and macOS block nearby-AP scanning
// at the OS level. Windows CAN enumerate nearby APs through its Native Wifi API
// (WlanGetNetworkBssList), but that path is not wired into this tool yet — so the
// unavailable state says so honestly instead of implying only Apple restricts
// it. This screen guards itself: off Android it renders an honest per-platform
// unavailable state instead of touching the channel (GL-008), with copy chosen
// from ApScanService.platformStatus.
//
// HONESTY (GL-005 / GL-008): the scan exposes CLEAN fields only — SSID, BSSID,
// channel, band, RSSI. The Android scan API does not expose a per-BSS noise
// floor, SNR, or MCS for a scanned (non-connected) BSS, so those columns do not
// exist here and are never shown.
//
// States (SOP-007 §5):
//   * unsupported (iOS / macOS / web) -> honest "Android only" state.
//   * loading  -> labeled spinner (announced via liveRegion) on first scan.
//   * empty    -> Wi-Fi-off card, Location-gate card, or "no networks found".
//   * error    -> channel-error card + Retry.
//   * success  -> sort control + occupancy bars + the AP list.
//   * disabled -> the Scan action shows a spinner while a scan is in flight.
//   * interactive -> Scan (app bar) + the sort segmented control.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/network/ap_scan_service.dart';
import '../../../services/network/chromeos_arc.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';

/// The Nearby AP Scan tool screen (Android-only).
class ApScanScreen extends StatefulWidget {
  const ApScanScreen({super.key, this.service});

  /// Injectable AP-scan service (tests). Defaults to the real Android channel.
  /// Tests pass an [ApScanService] with a fake `invoke` and a
  /// `platformOverride` so the supported/unsupported branches are exercised
  /// without a real platform channel.
  final ApScanService? service;

  @override
  State<ApScanScreen> createState() => _ApScanScreenState();
}

class _ApScanScreenState extends State<ApScanScreen> {
  late final ApScanService _service;

  bool _loading = false;
  ApScanSnapshot? _snapshot;
  ApScanUnavailable? _error;
  ApSortOrder _sort = ApSortOrder.signalDesc;

  /// Set once a Location grant has been attempted, so the Location card swaps to
  /// its post-attempt copy rather than looping the same prompt.
  bool _locationGrantAttempted = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ApScanService();
    if (_service.isSupportedPlatform) {
      // Seed with the last cached scan immediately (cheap, no throttle), then
      // request a fresh one so the list fills without a manual tap.
      _initialLoad();
    }
  }

  Future<void> _initialLoad() async {
    await _runScan(fresh: false, manual: false);
    if (!mounted) return;
    await _runScan(fresh: true, manual: false);
  }

  /// Runs a scan. [fresh] requests a new scan (may be throttled); false reads
  /// the last cached scan. [manual] confirms a user-triggered refresh with a
  /// snackbar so a refresh that returns identical results is never silent.
  Future<void> _runScan({required bool fresh, bool manual = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ApScanSnapshot snap =
          fresh ? await _service.scan() : await _service.lastResults();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
      if (manual && mounted) {
        final String msg = snap.scanThrottled
            ? 'Scan throttled by Android — showing the last scan'
            : 'Scan updated';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    } on ApScanUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (e) {
      // Defensive: never sit on a spinner forever.
      if (!mounted) return;
      setState(() {
        _error = ApScanUnavailable(
          ApScanUnavailableReason.channelError,
          e.toString(),
        );
        _loading = false;
      });
    }
  }

  Future<void> _grantLocation() async {
    await _service.requestLocationPermission();
    if (!mounted) return;
    _locationGrantAttempted = true;
    await _runScan(fresh: true);
  }

  Future<void> _openLocationSettings() async {
    await _service.openLocationSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby AP Scan'),
        toolbarHeight: 64,
        actions: _appBarActions(),
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  List<Widget> _appBarActions() {
    if (!_service.isSupportedPlatform) return const <Widget>[];
    return <Widget>[
      AppCopyAction(textBuilder: _buildCopyText),
      _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.textAccent,
                  ),
                ),
              ),
            )
          : Semantics(
              button: true,
              label: 'Scan for nearby access points',
              child: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Scan',
                onPressed: () => _runScan(fresh: true, manual: true),
              ),
            ),
    ];
  }

  Widget _body() {
    if (!_service.isSupportedPlatform) {
      return _ScanUnavailable(status: _service.platformStatus);
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            edge,
            AppSpacing.sm,
            edge,
            edge + AppSpacing.sm,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _content(),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content() {
    // First-load spinner: nothing on screen yet.
    if (_loading && _snapshot == null && _error == null) {
      return const <Widget>[_LoadingCard()];
    }

    // Hard channel error with nothing to fall back on.
    if (_error != null && _snapshot == null) {
      return <Widget>[
        _ErrorCard(error: _error!, onRetry: _loading ? null : _retry),
      ];
    }

    final ApScanSnapshot? snap = _snapshot;
    if (snap == null) {
      return <Widget>[_ErrorCard(error: null, onRetry: _loading ? null : _retry)];
    }

    final List<Widget> children = <Widget>[];

    if (!snap.poweredOn) {
      children
        ..add(const _WifiOffCard())
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (!snap.locationAuthorized) {
      children
        ..add(
          _LocationCard(
            attempted: _locationGrantAttempted,
            onGrant: _loading ? null : _grantLocation,
            onOpenSettings: _openLocationSettings,
          ),
        )
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // Throttle note — the list is the last cached scan, said plainly.
    if (snap.scanThrottled && snap.accessPoints.isNotEmpty) {
      children
        ..add(const _ThrottledNote())
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    final List<ScannedAp> aps = snap.accessPoints;

    if (aps.isEmpty) {
      // Only show the bare "no networks" empty state when there is no more
      // specific reason already shown above (Wi-Fi off / Location gate).
      if (snap.poweredOn && snap.locationAuthorized) {
        children.add(const _NoNetworksCard());
      }
      return children;
    }

    // Channel-occupancy bars for 2.4 GHz and 5 GHz.
    final List<ChannelOccupancy> occ24 = channelOccupancy(aps, '2.4 GHz');
    final List<ChannelOccupancy> occ5 = channelOccupancy(aps, '5 GHz');
    if (occ24.isNotEmpty) {
      children
        ..add(_OccupancyCard(band: '2.4 GHz', occupancy: occ24))
        ..add(const SizedBox(height: AppSpacing.sm));
    }
    if (occ5.isNotEmpty) {
      children
        ..add(_OccupancyCard(band: '5 GHz', occupancy: occ5))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // Sort control + AP list.
    children
      ..add(_SortControl(
        value: _sort,
        onChanged: (ApSortOrder v) => setState(() => _sort = v),
      ))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_ApListCard(aps: sortAps(aps, _sort)));

    return children;
  }

  Future<void> _retry() => _runScan(fresh: true);

  /// §8.16 copy payload: the visible APs as a labeled plain-text block. Returns
  /// null (→ disabled affordance) until a scan with at least one AP resolves.
  String? _buildCopyText() {
    final ApScanSnapshot? snap = _snapshot;
    if (snap == null || snap.accessPoints.isEmpty) return null;
    final List<ScannedAp> aps = sortAps(snap.accessPoints, _sort);
    final StringBuffer buf = StringBuffer()
      ..writeln('Nearby AP Scan')
      ..writeln('${aps.length} access points'
          '${snap.scanThrottled ? ' (last scan — fresh scan throttled)' : ''}')
      ..writeln();
    for (final ScannedAp ap in aps) {
      buf.writeln(
        '${ap.ssid ?? '(hidden network)'}  '
        '${ap.bssid ?? 'BSSID unavailable'}  '
        'ch ${ap.channel} (${ap.band})  ${ap.rssiDbm} dBm',
      );
    }
    return buf.toString().trimRight();
  }
}

// ---------------------------------------------------------------------------
// Android-only state (off-Android guard)
// ---------------------------------------------------------------------------

/// Honest per-platform unavailable state for the nearby-AP scan.
///
/// The scan is wired for Android only today. This card explains WHY it isn't
/// running here without overstating the reason: iOS and macOS block it at the
/// OS level, whereas Windows can do it (Native Wifi) but the path isn't wired
/// into this tool yet. Copy is chosen from [ApScanPlatformStatus].
class _ScanUnavailable extends StatelessWidget {
  const _ScanUnavailable({required this.status});

  final ApScanPlatformStatus status;

  static const String _lead =
      'Nearby AP Scan lists the access points around you using a native Wi-Fi '
      'scan. It currently runs on Android. ';

  String get _heading {
    switch (status) {
      case ApScanPlatformStatus.windowsNotWired:
        return 'Not wired for Windows yet';
      // ChromeOS is NOT "runs on Android" — this IS the Android build. The
      // scan runs; its signal readings just cannot be trusted. Say that.
      case ApScanPlatformStatus.chromeOsUnreliable:
        return ChromeOsArc.scanUnavailableHeadline;
      case ApScanPlatformStatus.appleRestricted:
      case ApScanPlatformStatus.unavailable:
      case ApScanPlatformStatus.supported:
        return 'Runs on Android';
    }
  }

  String get _detail {
    switch (status) {
      case ApScanPlatformStatus.windowsNotWired:
        return '${_lead}Windows can list nearby access points through its '
            'Native Wifi API, but this tool does not wire up the Windows scan '
            'yet. The rest of the toolbox works normally here.';
      case ApScanPlatformStatus.appleRestricted:
        return '${_lead}iOS and macOS block nearby-AP scanning at the OS level, '
            'so this tool cannot run it there. The rest of the toolbox works '
            'normally here.';
      // The ChromeOS copy does NOT reuse `_lead` ("It currently runs on
      // Android") — on a Chromebook that sentence is actively confusing, since
      // the user IS running the Android build. The reason here is data trust,
      // not platform support (SSOT: ChromeOsArc).
      case ApScanPlatformStatus.chromeOsUnreliable:
        return ChromeOsArc.scanUnavailableBody;
      case ApScanPlatformStatus.unavailable:
      case ApScanPlatformStatus.supported:
        return '${_lead}It is not available on this platform. The rest of the '
            'toolbox works normally here.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.wifi_find, size: 48, color: colors.textTertiary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _heading,
                style: text.headlineSmall?.copyWith(color: colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _detail,
                style: text.bodyLarge?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading / empty / error / gate cards
// ---------------------------------------------------------------------------

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.textAccent,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Scanning for nearby access points…',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoNetworksCard extends StatelessWidget {
  const _NoNetworksCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.wifi_find_outlined, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No access points in range. Move to where Wi-Fi is in use, then '
              'tap Scan again.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _WifiOffCard extends StatelessWidget {
  const _WifiOffCard();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.wifi_off, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Wi-Fi is off. Turn it on to scan for nearby access points.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThrottledNote extends StatelessWidget {
  const _ThrottledNote();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.history, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Android throttled the fresh scan. Showing the last scan — tap '
              'Scan again in a moment for newer results.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.attempted,
    required this.onGrant,
    required this.onOpenSettings,
  });

  /// Whether a grant has already been attempted (swaps the copy).
  final bool attempted;
  final VoidCallback? onGrant;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String message = attempted
        ? 'If you allowed Location, the nearby networks appear on the next '
            'scan. If the list is still empty, the permission was denied — open '
            'Settings to enable Location for this app.'
        : 'Android requires the Location permission to read Wi-Fi scan '
            'results. Grant it to list the nearby access points.';
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.location_on_outlined,
                size: 20,
                color: colors.textAccent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style:
                      text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          if (onGrant != null || onOpenSettings != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                if (onGrant != null)
                  Semantics(
                    button: true,
                    label: 'Grant Location permission to scan',
                    child: FilledButton(
                      onPressed: onGrant,
                      child: const Text('Grant Location'),
                    ),
                  ),
                if (onOpenSettings != null)
                  Semantics(
                    button: true,
                    label: 'Open Location settings',
                    child: OutlinedButton(
                      onPressed: onOpenSettings,
                      child: const Text('Open Settings'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final ApScanUnavailable? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String detail = error?.detail ?? 'The scan could not be read.';
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, size: 20, color: colors.statusDanger),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  detail,
                  style:
                      text.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Retry the scan',
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sort control
// ---------------------------------------------------------------------------

class _SortControl extends StatelessWidget {
  const _SortControl({required this.value, required this.onChanged});

  final ApSortOrder value;
  final ValueChanged<ApSortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Text(
          'Sort',
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SegmentedButton<ApSortOrder>(
            segments: const <ButtonSegment<ApSortOrder>>[
              ButtonSegment<ApSortOrder>(
                value: ApSortOrder.signalDesc,
                label: Text('Signal'),
              ),
              ButtonSegment<ApSortOrder>(
                value: ApSortOrder.channelAsc,
                label: Text('Channel'),
              ),
              ButtonSegment<ApSortOrder>(
                value: ApSortOrder.ssidAsc,
                label: Text('Name'),
              ),
            ],
            selected: <ApSortOrder>{value},
            showSelectedIcon: false,
            onSelectionChanged: (Set<ApSortOrder> s) => onChanged(s.first),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Channel-occupancy bars
// ---------------------------------------------------------------------------

class _OccupancyCard extends StatelessWidget {
  const _OccupancyCard({required this.band, required this.occupancy});

  final String band;
  final List<ChannelOccupancy> occupancy;

  @override
  Widget build(BuildContext context) {
    final int maxCount = occupancy
        .map((ChannelOccupancy o) => o.apCount)
        .fold<int>(1, (int a, int b) => a > b ? a : b);
    return _Card(
      title: '$band channel occupancy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final ChannelOccupancy o in occupancy)
            _OccupancyBar(occupancy: o, maxCount: maxCount),
        ],
      ),
    );
  }
}

class _OccupancyBar extends StatelessWidget {
  const _OccupancyBar({required this.occupancy, required this.maxCount});

  final ChannelOccupancy occupancy;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final double fraction =
        maxCount <= 0 ? 0 : occupancy.apCount / maxCount;
    final String countLabel =
        '${occupancy.apCount} AP${occupancy.apCount == 1 ? '' : 's'}';
    return Semantics(
      container: true,
      label: 'Channel ${occupancy.channel}, $countLabel, strongest '
          '${occupancy.strongestRssiDbm} dBm',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 36,
              child: Text(
                '${occupancy.channel}',
                textAlign: TextAlign.end,
                style: mono.robotoMono.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Stack(
                  children: <Widget>[
                    Container(height: 16, color: colors.surface2),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.04, 1.0),
                      child: Container(height: 16, color: colors.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              countLabel,
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AP list
// ---------------------------------------------------------------------------

class _ApListCard extends StatelessWidget {
  const _ApListCard({required this.aps});

  final List<ScannedAp> aps;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '${aps.length} access point${aps.length == 1 ? '' : 's'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < aps.length; i++) ...<Widget>[
            if (i > 0) const _RowDivider(),
            _ApRow(ap: aps[i]),
          ],
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, thickness: 1, color: context.colors.border);
}

class _ApRow extends StatelessWidget {
  const _ApRow({required this.ap});

  final ScannedAp ap;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String name = ap.ssid ?? '(hidden network)';
    final bool hidden = ap.ssid == null;

    return Semantics(
      container: true,
      label: '$name, '
          '${ap.bssid ?? 'BSSID unavailable'}, '
          'channel ${ap.channel}, ${ap.band}, ${ap.rssiDbm} dBm',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: text.bodyMedium?.copyWith(
                      color: hidden ? colors.textTertiary : colors.textPrimary,
                      fontStyle: hidden ? FontStyle.italic : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    ap.bssid ?? 'BSSID unavailable',
                    style: mono.robotoMono.copyWith(
                      fontSize: AppTextSize.caption,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '${ap.rssiDbm} dBm',
                    textAlign: TextAlign.end,
                    style: mono.robotoMono.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'ch ${ap.channel} · ${ap.band}',
                    textAlign: TextAlign.end,
                    style: text.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared surfaces (match wifi_info_screen _Card / _Surface convention)
// ---------------------------------------------------------------------------

/// A bordered surface-1 card with a section title. Matches the `_Card` shape in
/// wifi_info_screen.dart.
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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

/// A plain bordered surface-1 card with no title (notes / gate cards).
class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
