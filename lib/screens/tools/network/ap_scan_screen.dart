// Nearby AP Scan (H3) — wired for Android and macOS.
//
// Lists the access points visible to a Wi-Fi scan and draws a simple
// channel-occupancy bar per band. The data comes from the
// `com.wlanpros.toolbox/ap_scan` method channel: MainActivity.kt →
// WifiManager.getScanResults() on Android, ApScanChannel.swift → CoreWLAN
// scanForNetworks on macOS. ONE channel name, ONE payload shape, ONE Dart model.
//
// Per-platform reality (GL-005 honesty): iOS blocks nearby-AP scanning at the OS
// level (no public scan API). Windows CAN enumerate nearby APs through its
// Native Wifi API (WlanGetNetworkBssList), but that path is unverified on real
// hardware and stays dark — so the unavailable state says so honestly instead of
// implying only Apple restricts it. This screen guards itself: on an unwired
// platform it renders an honest per-platform unavailable state instead of
// touching the channel (GL-008), with copy chosen from
// ApScanService.platformStatus.
//
// HONESTY (GL-005 / GL-008): the scan exposes CLEAN fields only — SSID, BSSID,
// channel, band, RSSI. NEITHER platform's scan API exposes a per-BSS noise
// floor, SNR, or MCS for a scanned (non-connected) BSS, so those columns do not
// exist here and are never shown, and none is derived.
//
// TWO KINDS OF NULL (load-bearing): an empty AP list is only reported as "no
// networks found" when the scan actually RAN — radio on AND Location granted.
// When the radio is off or the Location grant is missing, the screen says the
// scan could not run and never shows an empty list that would imply there are no
// access points nearby ([[feedback_app_blames_the_wifi]]).
//
// States (SOP-007 §5):
//   * unsupported (iOS / Windows / Linux / web) -> honest per-platform state.
//   * loading  -> labeled spinner (announced via liveRegion) on first scan.
//   * empty    -> Wi-Fi-off card, Location-gate card, or "no networks found".
//   * error    -> channel-error card + Retry.
//   * success  -> sort control + occupancy bars + the AP list.
//   * disabled -> the Scan action shows a spinner while a scan is in flight.
//   * interactive -> Scan (app bar) + the sort segmented control.
//
// DESKTOP LAYOUT: the screen was built for Android phones. On a wide window the
// content column widens, the per-band occupancy cards sit side by side instead
// of stacking, and the AP list switches to a four-column row (name / BSSID /
// signal / channel) rather than stretching a two-column phone row across the
// full width.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/network/ap_scan_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';

/// The Nearby AP Scan tool screen (Android and macOS).
class ApScanScreen extends StatefulWidget {
  const ApScanScreen({super.key, this.service});

  /// Injectable AP-scan service (tests). Defaults to the real native channel.
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
            ? 'Fresh scan declined: showing the last scan'
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
              // A phone-width column stranded in the middle of a desktop window
              // wastes the space this list can actually use, so the column
              // widens on desktop rather than staying pinned at phone width.
              constraints: BoxConstraints(maxWidth: isDesktop ? 1040 : 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _content(isWide: isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content({required bool isWide}) {
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

    // EXACTLY ONE VERDICT. The cards below used to be decided by independent
    // `if`s, which made "the screen states one thing" a property nobody owned:
    // every time a state was added, some combination rendered two verdicts or
    // none. Switching over [ApScanSnapshot.verdict] makes it structural, and a
    // future sixth state cannot be added without failing this switch to
    // compile. See ap_scan_verdict_matrix_test.dart.
    switch (snap.verdict) {
      case ApScanVerdict.radioOff:
        children.add(const _WifiOffCard());
        return children;

      case ApScanVerdict.permissionMissing:
        children.add(
          _LocationCard(
            attempted: _locationGrantAttempted,
            platformName: _service.platformName,
            onGrant: _loading ? null : _grantLocation,
            onOpenSettings: _openLocationSettings,
          ),
        );
        return children;

      case ApScanVerdict.noneReadable:
        // The radio DID report networks. Saying "no access points in range"
        // here would be a false verdict handed to a user standing among APs,
        // and the old copy shipped an action with it ("move to where Wi-Fi is
        // in use"). Unknown is not empty.
        children.add(_NoneReadableCard(count: snap.unreadableCount));
        return children;

      case ApScanVerdict.noScanYet:
        children.add(_NoScanYetCard(onScan: _loading ? null : _retry));
        return children;

      case ApScanVerdict.nothingInRange:
        // The ONLY state entitled to claim an empty RF environment: the scan
        // ran, and every row it reported was read.
        children.add(const _NoNetworksCard());
        return children;

      case ApScanVerdict.apsFound:
        break;
    }

    // Throttle note — the list is the last cached scan, said plainly.
    if (snap.scanThrottled) {
      children
        ..add(_ThrottledNote(platformName: _service.platformName))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    // Disclosed above the list, so the count in the card title below is read in
    // the knowledge that it is not the whole radio picture.
    if (snap.unreadableCount > 0) {
      children
        ..add(_UnreadableRowsNote(count: snap.unreadableCount))
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    final List<ScannedAp> aps = snap.accessPoints;

    // Channel-occupancy bars per band. 6 GHz is included: macOS CoreWLAN reports
    // 6 GHz BSSs, and a band that is present in the list but missing from the
    // charts would be an unexplained gap.
    final List<Widget> occupancyCards = <Widget>[
      for (final String band in const <String>['2.4 GHz', '5 GHz', '6 GHz'])
        if (channelOccupancy(aps, band).isNotEmpty)
          _OccupancyCard(band: band, occupancy: channelOccupancy(aps, band)),
    ];
    if (occupancyCards.isNotEmpty) {
      if (isWide && occupancyCards.length > 1) {
        // Side by side on a wide window; stacking them wastes the width and
        // pushes the AP list below the fold.
        children
          ..add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < occupancyCards.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(child: occupancyCards[i]),
                  ],
                ],
              ),
            ),
          )
          ..add(const SizedBox(height: AppSpacing.sm));
      } else {
        for (final Widget card in occupancyCards) {
          children
            ..add(card)
            ..add(const SizedBox(height: AppSpacing.sm));
        }
      }
    }

    // Sort control + AP list.
    children
      ..add(_SortControl(
        value: _sort,
        onChanged: (ApSortOrder v) => setState(() => _sort = v),
      ))
      ..add(const SizedBox(height: AppSpacing.sm))
      ..add(_ApListCard(aps: sortAps(aps, _sort), isWide: isWide));

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
      ..writeln('${aps.length} access point${aps.length == 1 ? '' : 's'}'
          '${snap.scanThrottled ? ' (last scan, fresh scan throttled)' : ''}');
    // THE EXPORT MUST CARRY THE DISCLOSURE THE SCREEN MAKES. This text is what
    // lands in a client report, detached from the screen that qualified it — so
    // an export claiming "3 access points" with no note is a completeness claim
    // the app knows to be false, made in the one artifact that outlives the
    // session. The screen being honest is not enough if the artifact is not.
    if (snap.unreadableCount > 0) {
      buf.writeln(
        'Note: the radio reported ${snap.unreadableCount} further '
        'network${snap.unreadableCount == 1 ? '' : 's'} this app could not '
        'read (channel, band or signal missing or not recognized). '
        'They are NOT included in the count above or the list below.',
      );
    }
    buf.writeln();
    for (final ScannedAp ap in aps) {
      buf.writeln(
        '${ap.ssid ?? '(hidden network)'}  '
        '${ap.bssid}  '
        'ch ${ap.channel} (${ap.band})  ${ap.rssiDbm} dBm',
      );
    }
    return buf.toString().trimRight();
  }
}

// ---------------------------------------------------------------------------
// Unwired-platform state (off Android / macOS guard)
// ---------------------------------------------------------------------------

/// Honest per-platform unavailable state for the nearby-AP scan.
///
/// The scan is wired for Android and macOS. This card explains WHY it isn't
/// running here without overstating the reason: iOS blocks it at the OS level,
/// whereas Windows (Native Wifi) can do it but the path isn't wired into this
/// tool yet. Copy is chosen from [ApScanPlatformStatus].
class _ScanUnavailable extends StatelessWidget {
  const _ScanUnavailable({required this.status});

  final ApScanPlatformStatus status;

  static const String _lead =
      'Nearby AP Scan lists the access points around you using a native Wi-Fi '
      'scan. It is available on Android and macOS. ';

  String get _heading {
    switch (status) {
      case ApScanPlatformStatus.windowsNotWired:
        return 'Not wired for Windows yet';
      case ApScanPlatformStatus.appleRestricted:
      case ApScanPlatformStatus.unavailable:
      case ApScanPlatformStatus.supported:
        return 'Available on Android and macOS';
    }
  }

  String get _detail {
    switch (status) {
      case ApScanPlatformStatus.windowsNotWired:
        return '${_lead}Windows can list nearby access points through its '
            'Native Wifi API, but this tool does not wire up the Windows scan '
            'yet. The rest of the toolbox works normally here.';
      case ApScanPlatformStatus.appleRestricted:
        return '${_lead}iOS blocks nearby-AP scanning at the OS level, so this '
            'tool cannot run it there. The rest of the toolbox works normally '
            'here.';
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
              // The ONLY empty state that claims an empty RF environment, and it
              // is only ever shown when the scan actually ran (radio on and
              // Location granted). See the two-kinds-of-null note at the top.
              'The scan ran and found no access points in range. Move to where '
              'Wi-Fi is in use, then run Scan again.',
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
              // The second kind of null: nothing was measured, so the screen
              // says so rather than showing an empty list that would read as
              // "no access points nearby".
              'Wi-Fi is off, so the scan could not run. Turn it on to list the '
              'nearby access points.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says plainly that the list on screen is the LAST scan, not a fresh one.
///
/// The reason differs by platform and the copy names it: Android's OS throttles
/// `startScan()`, while on macOS an active CoreWLAN scan takes the radio
/// off-channel for seconds, so the app spaces fresh scans out itself.
class _ThrottledNote extends StatelessWidget {
  const _ThrottledNote({required this.platformName});

  /// The OS name for the copy, or null on a platform with no name to attribute.
  final String? platformName;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String message = platformName == 'macOS'
        ? 'A fresh scan ran moments ago. Showing those results. A full scan '
            'briefly takes the radio off channel, so scans are spaced out. Tap '
            'Scan again in a moment for a new one.'
        : '${platformName ?? 'The system'} throttled the fresh scan. Showing '
            'the last scan. Tap Scan again in a moment for newer results.';
    return _Surface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.history, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Discloses rows the radio reported that could not be read.
///
/// Without this the screen presents a short list as a COMPLETE one: the radio
/// sees four BSSs, the card title says "2 access points", and nothing tells the
/// user the other two were discarded. That under-reports the RF environment,
/// which is the same class of lie as over-reporting it — an engineer counting
/// APs on a channel would be counting the wrong number and never know
/// ([[feedback_app_blames_the_wifi]]). The rows genuinely cannot be shown (no
/// channel, no band, or a 0 dBm non-measurement), so the honest move is to say
/// how many rather than to invent them or hide them.
class _UnreadableRowsNote extends StatelessWidget {
  const _UnreadableRowsNote({required this.count});

  /// How many reported rows could not be parsed into an honest AP row.
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.filter_alt_off_outlined, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              count == 1
                  ? 'The radio reported 1 more network this app could not '
                      'read: its channel, band or signal reading was missing '
                      'or not recognized. It is not counted below.'
                  : 'The radio reported $count more networks this app could '
                      'not read: their channel, band or signal reading was '
                      'missing or not recognized. They are not counted below.',
              style: text.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// No scan has run yet and the OS scan cache is empty.
///
/// The screen's first load reads the cache rather than triggering a scan, and
/// on a machine that has not scanned since boot that cache is empty. This state
/// used to render "The scan ran and found no access points in range. Move to
/// where Wi-Fi is in use." — claiming a measurement that had not happened, and
/// holding that claim on screen for the whole duration of the first real scan.
/// It is the same false action deleted from [_NoneReadableCard], one path over.
///
/// The copy therefore claims nothing about the air, because nothing has been
/// measured, and offers the one thing that will change that: run a scan
/// ([[feedback_app_blames_the_wifi]]).
class _NoScanYetCard extends StatelessWidget {
  const _NoScanYetCard({required this.onScan});

  /// Runs the first scan. Null while one is already in flight.
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.radar, size: 20, color: colors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'No scan yet',
                  style: text.titleSmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nothing has been measured yet. This machine has no stored scan '
            'results, which is normal before the first scan. Tap Scan to look '
            'at what is on the air.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: onScan,
              child: const Text('Scan'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The scan ran, the radio reported networks, and NONE could be read.
///
/// This state used to render the "no access points in range" card, which told a
/// user standing among APs that there were none — and shipped an action with
/// the false verdict ("move to where Wi-Fi is in use").
///
/// TODO(keith-decision): this card may be UNREACHABLE on macOS. It renders only
/// when `unreadableCount > 0`, and the native layers drop those rows before the
/// payload is built (ApScanChannel.swift:237-288, the 6 GHz `bandUnknown` case
/// at :314, and MainActivity.kt:485-488). An earlier version of this doc claimed
/// the `bandUnknown` drop "produces exactly this payload"; that was wrong — it
/// is handled natively and never reaches Dart. Either the native layers report
/// what they dropped, or this card and its copy go. See the gate #4 QA report
/// (F-2/F-3/F-4).
///
/// The honest verdict is that the RF environment is UNKNOWN, not empty. The
/// copy therefore states what the radio did (reported networks), what the app
/// could not do (read them), and offers no location advice, because nothing
/// here suggests the user is in the wrong place
/// ([[feedback_app_blames_the_wifi]]).
class _NoneReadableCard extends StatelessWidget {
  const _NoneReadableCard({required this.count});

  /// How many rows the radio reported that could not be read.
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.help_outline, size: 20, color: colors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Networks detected, none readable',
                  style: text.titleSmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            count == 1
                ? 'The radio reported 1 network, but its channel, band or '
                    'signal reading was missing or not recognized, so this app '
                    'cannot describe it. The air is not quiet. This scan could '
                    'not read what is on it. Tap Scan again for another look.'
                : 'The radio reported $count networks, but their channel, band '
                    'or signal readings were missing or not recognized, so this '
                    'app cannot describe them. The air is not quiet. This scan '
                    'could not read what is on it. Tap Scan again for another '
                    'look.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The Location gate: the scan COULD NOT RUN, said as such.
///
/// This is the first of the two kinds of null. It must never read as "no access
/// points nearby" — without the Location grant the app measured nothing, and
/// claiming an empty RF environment would be a verdict it never took
/// ([[feedback_app_blames_the_wifi]]). The lead sentence therefore states the
/// scan did not run before anything else.
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.attempted,
    required this.platformName,
    required this.onGrant,
    required this.onOpenSettings,
  });

  /// Whether a grant has already been attempted (swaps the copy).
  final bool attempted;

  /// The OS name for the copy, or null on a platform with no name to attribute.
  final String? platformName;
  final VoidCallback? onGrant;
  final VoidCallback? onOpenSettings;

  /// Why this OS gates the scan behind Location. Both are true statements about
  /// the platform, not a guess: Android withholds scan results entirely, macOS
  /// withholds the SSID and BSSID of every scanned network.
  String get _reason {
    switch (platformName) {
      case 'macOS':
        return 'macOS requires Location Services to read the name and BSSID of '
            'nearby Wi-Fi networks.';
      case 'Android':
        return 'Android requires the Location permission to read Wi-Fi scan '
            'results.';
      default:
        return 'This system requires the Location permission to read Wi-Fi '
            'scan results.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String message = attempted
        ? 'The scan did not run: Location is still not granted. If you just '
            'allowed it, the nearby networks appear on the next scan. '
            'Otherwise open Settings and enable Location for this app. This '
            'list being empty does not mean there are no access points nearby.'
        : 'The scan could not run. $_reason Grant it to list the nearby access '
            'points. Until then this screen cannot tell you what is on the air.';
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
  const _ApListCard({required this.aps, required this.isWide});

  final List<ScannedAp> aps;

  /// Wide (desktop) window: the row splits into four labeled columns instead of
  /// the stacked two-column phone row.
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: '${aps.length} access point${aps.length == 1 ? '' : 's'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (isWide) ...<Widget>[
            const _ApColumnHeader(),
            const _RowDivider(),
          ],
          for (int i = 0; i < aps.length; i++) ...<Widget>[
            if (i > 0) const _RowDivider(),
            _ApRow(ap: aps[i], isWide: isWide),
          ],
        ],
      ),
    );
  }
}

/// Column headings for the wide (desktop) AP list. Not shown on a phone-width
/// window, where the row is stacked and self-labeling.
class _ApColumnHeader extends StatelessWidget {
  const _ApColumnHeader();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = text.labelSmall?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(flex: 4, child: Text('NETWORK', style: style)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(flex: 3, child: Text('BSSID', style: style)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text('SIGNAL', style: style, textAlign: TextAlign.end),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text('CHANNEL', style: style, textAlign: TextAlign.end),
          ),
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
  const _ApRow({required this.ap, required this.isWide});

  final ScannedAp ap;

  /// Wide (desktop) window: four columns matching [_ApColumnHeader]. Narrow:
  /// the original stacked phone row.
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final String name = ap.ssid ?? '(hidden network)';
    final bool hidden = ap.ssid == null;

    final Text nameText = Text(
      name,
      style: text.bodyMedium?.copyWith(
        color: hidden ? colors.textTertiary : colors.textPrimary,
        fontStyle: hidden ? FontStyle.italic : null,
      ),
    );
    final Text bssidText = Text(
      ap.bssid,
      style: mono.robotoMono.copyWith(
        fontSize: AppTextSize.caption,
        color: colors.textTertiary,
      ),
    );
    final Text rssiText = Text(
      '${ap.rssiDbm} dBm',
      textAlign: TextAlign.end,
      style: mono.robotoMono.copyWith(color: colors.textPrimary),
    );
    final Text channelText = Text(
      'ch ${ap.channel} · ${ap.band}',
      textAlign: TextAlign.end,
      style: text.bodySmall?.copyWith(color: colors.textSecondary),
    );

    return Semantics(
      container: true,
      label: '$name, '
          '${ap.bssid}, '
          'channel ${ap.channel}, ${ap.band}, ${ap.rssiDbm} dBm',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(flex: 4, child: nameText),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 3, child: bssidText),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 2, child: rssiText),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(flex: 2, child: channelText),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        nameText,
                        const SizedBox(height: AppSpacing.xxs),
                        bssidText,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        rssiText,
                        const SizedBox(height: AppSpacing.xxs),
                        channelText,
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
