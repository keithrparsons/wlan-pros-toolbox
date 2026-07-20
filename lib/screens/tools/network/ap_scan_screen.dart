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
// THE LOCATION GATE IS TRI-STATE, NOT BOOLEAN (load-bearing). macOS will not
// re-prompt for Location once the status has left `notDetermined`, so a screen
// holding only `isLocationAuthorized` (a bool) cannot tell "never asked" from
// "asked and refused" and offers an in-app "Grant Location" button in both. In
// the second case that button is guaranteed to do nothing: Keith clicked it
// repeatedly in a live deployment and got no prompt, no error, no navigation.
// The gate card therefore reads `locationAuthorizationStatus` and renders the
// in-app grant ONLY under `notDetermined`; under `denied` / `restricted` the
// System Settings deep-link is the sole action, and it is PRIMARY, because it
// is the only route that can work. The copy follows: telling a denied user to
// grant Location inside the app is instructing them to do something the OS
// forbids.
//
// A GRANT IS NOT INSTANTANEOUS. The grant lands before CoreWLAN reflects it, so
// the scan fired immediately after a successful grant comes back unauthorized.
// Rendering that verdict produced "The scan did not run: Location is still not
// granted" seconds after the user granted it. The screen now distinguishes
// "authorization is missing" from "authorization is still propagating"
// (_GrantPhase) and waits out the second, visibly, rather than reporting it as
// the first. An app that blames the environment for its own timing is telling
// the one lie this app must never tell ([[feedback_app_blames_the_wifi]]).
//
// States (SOP-007 §5):
//   * unsupported (iOS / Windows / Linux / web) -> honest per-platform state.
//   * loading  -> labeled spinner (announced via liveRegion) on first scan.
//   * empty    -> Wi-Fi-off card, Location-gate card, or "no networks found".
//   * error    -> channel-error card + Retry.
//   * success  -> sort control + occupancy bars + the AP list.
//   * disabled -> the Scan action shows a spinner while a scan is in flight.
//   * interactive -> Scan (app bar) + the sort segmented control.
//   * permission -> FOUR distinct renderings, one per authorization state:
//       notDetermined -> "Grant Location" (primary) + Open Settings.
//       denied/restricted -> Open Settings ONLY, primary, naming the manual
//         path if the pane will not open.
//       authorized-but-unread -> says the grant is held and the scan still
//         could not read; never claims the grant is missing.
//       in-flight (requesting / settling) -> spinner + status text, no verdict.
//
// DESKTOP LAYOUT: the screen was built for Android phones. On a wide window the
// content column widens, the per-band occupancy cards sit side by side instead
// of stacking, and the AP list switches to a four-column row (name / BSSID /
// signal / channel) rather than stretching a two-column phone row across the
// full width.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/network/ap_scan_service.dart';
import '../../../services/network/wifi_info_service.dart'
    show LocationAuthStatus;
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';

/// Where the Location grant handshake is.
///
/// This exists because a grant is not instantaneous, and the states in between
/// are not failures. Collapsing them into "authorized or not" is what let the
/// screen render a denial verdict during a grant that was in fact succeeding.
enum _GrantPhase {
  /// No grant in flight.
  none,

  /// The native prompt has been requested and has not returned. Nothing is
  /// known about the outcome, so nothing is claimed about it.
  requesting,

  /// The grant is HELD, and the scan has not yet reflected it. A propagation
  /// window, NOT an authorization failure.
  settling,
}

/// The Nearby AP Scan tool screen (Android and macOS).
class ApScanScreen extends StatefulWidget {
  const ApScanScreen({
    super.key,
    this.service,
    this.grantSettleBackoff = kDefaultGrantSettleBackoff,
  });

  /// Injectable AP-scan service (tests). Defaults to the real native channel.
  /// Tests pass an [ApScanService] with a fake `invoke` and a
  /// `platformOverride` so the supported/unsupported branches are exercised
  /// without a real platform channel.
  final ApScanService? service;

  /// How long to wait between the re-scans that follow a successful grant.
  ///
  /// A freshly granted Location authorization does NOT reach CoreWLAN
  /// instantly: the TCC grant lands, the authorization delegate fires, and the
  /// scan path picks it up a beat later. Re-scanning once, immediately, and
  /// rendering whatever comes back produced a confident "Location is still not
  /// granted" in the seconds after the user granted it. These are the waits
  /// between the retries that replace that false verdict; the list length is
  /// the number of retries. Tests inject zero-duration waits.
  final List<Duration> grantSettleBackoff;

  /// Real-world backoff. Total worst-case settle ~2.5s, spent showing an honest
  /// "waiting" state rather than a wrong one.
  static const List<Duration> kDefaultGrantSettleBackoff = <Duration>[
    Duration(milliseconds: 300),
    Duration(milliseconds: 700),
    Duration(milliseconds: 1500),
  ];

  @override
  State<ApScanScreen> createState() => _ApScanScreenState();
}

class _ApScanScreenState extends State<ApScanScreen> {
  late final ApScanService _service;

  bool _loading = false;
  ApScanSnapshot? _snapshot;
  ApScanUnavailable? _error;
  ApSortOrder _sort = ApSortOrder.signalDesc;

  /// The TRI-STATE Location authorization, read from the native side.
  ///
  /// This screen used to hold only the boolean `isLocationAuthorized`, which
  /// cannot tell "never asked" (promptable) from "asked and refused" (NOT
  /// promptable — macOS never re-prompts once the status has left
  /// `notDetermined`). Holding only the bool is what made the gate card offer
  /// an in-app "Grant Location" button in a state where that button was
  /// guaranteed to do nothing at all.
  ///
  /// Defaults to `notDetermined`, matching [LocationAuthStatus.fromToken]'s
  /// documented fallback: offer the harmless prompt rather than a dead
  /// deep-link when the truth is not yet known.
  LocationAuthStatus _locationStatus = LocationAuthStatus.notDetermined;

  /// Where the screen is in the grant handshake. See [_GrantPhase].
  _GrantPhase _grantPhase = _GrantPhase.none;

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
      // The gate card is about to render, and WHICH card it renders depends on
      // the tri-state, not on the boolean inside the snapshot. Read it here so
      // the card never has to guess between "never asked" and "refused".
      if (snap.verdict == ApScanVerdict.permissionMissing) {
        await _refreshLocationStatus();
        if (!mounted) return;
      }
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

  /// Reads the tri-state authorization and stores it. Never throws; the service
  /// already falls back to `notDetermined` on a channel failure.
  Future<void> _refreshLocationStatus() async {
    final LocationAuthStatus status =
        await _service.locationAuthorizationStatus();
    if (!mounted) return;
    if (status == _locationStatus) return;
    setState(() => _locationStatus = status);
  }

  /// Runs the grant handshake, and — critically — does NOT report an
  /// authorization failure while the grant is still propagating.
  ///
  /// THE BUG THIS REPLACES: this method used to request the permission and
  /// immediately re-scan, rendering whatever that scan returned. A grant does
  /// not reach CoreWLAN instantly, so the immediate scan came back unauthorized
  /// and the screen stated "The scan did not run: Location is still not
  /// granted" — in the seconds after the user granted it. It corrected itself a
  /// moment later, but the user had already been told the feature was broken.
  /// An app that blames the environment for its own timing is telling the one
  /// lie this app must never tell ([[feedback_app_blames_the_wifi]]).
  ///
  /// So the handshake splits on a question the screen can actually answer: is
  /// the grant HELD? If it is not (the user refused, or Location Services is
  /// off system-wide), the tri-state now says so and the card renders the
  /// honest deep-link path. If it IS held, then anything the scan says about
  /// authorization from here is a statement about PROPAGATION, not about the
  /// user's choice — so the screen waits for it, visibly, instead of reporting
  /// it as a denial.
  Future<void> _grantLocation() async {
    setState(() => _grantPhase = _GrantPhase.requesting);
    try {
      final bool granted = await _service.requestLocationPermission();
      if (!mounted) return;
      await _refreshLocationStatus();
      if (!mounted) return;

      final bool held =
          granted || _locationStatus == LocationAuthStatus.authorized;
      if (!held) {
        // A real refusal. The card now has the tri-state it needs to offer the
        // only route that can work, so one scan to reflect reality is enough.
        await _runScan(fresh: true);
        return;
      }

      setState(() => _grantPhase = _GrantPhase.settling);
      for (final Duration wait in widget.grantSettleBackoff) {
        await _runScan(fresh: true);
        if (!mounted) return;
        // The grant landed AND the scan picked it up. Done.
        if (_snapshot?.verdict != ApScanVerdict.permissionMissing) return;
        await Future<void>.delayed(wait);
        if (!mounted) return;
      }
      // Backoff exhausted. The screen does NOT now claim the grant is missing:
      // the tri-state says it is held, so the card reports what is actually
      // true — granted, and the scan still could not read.
      await _runScan(fresh: true);
    } finally {
      if (mounted) setState(() => _grantPhase = _GrantPhase.none);
    }
  }

  /// Opens the OS Location settings, and says so when it CANNOT.
  ///
  /// `openLocationSettings` has always returned whether the pane actually
  /// opened, and this screen has always thrown that answer away. That was
  /// survivable while "Open Settings" was the outlined afterthought beside
  /// "Grant Location". It is not survivable now: under `denied` this is the
  /// ONLY action on the card, so a silent false makes the sole remaining
  /// control a dead button — the very defect this change exists to remove, one
  /// step further along the same path.
  ///
  /// The fallback is the manual route, named step by step, because a user who
  /// cannot be taken to the pane still needs to reach it.
  Future<void> _openLocationSettings() async {
    final bool opened = await _service.openLocationSettings();
    if (!mounted || opened) return;
    final String manualPath;
    switch (_service.platformName) {
      case 'macOS':
        manualPath = 'Open System Settings, then Privacy & Security, then '
            'Location Services, and enable this app.';
      case 'Android':
        manualPath = 'Open Settings, then Apps, then this app, then '
            'Permissions, and allow Location.';
      default:
        manualPath =
            'Open your system settings and allow Location for this app.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open the settings page. $manualPath'),
        duration: const Duration(seconds: 6),
      ),
    );
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
              // This branch renders only when not already scanning, so the
              // scan action is always available; `onPressed` is never null.
              // Without this the node leaves isEnabled unset, which AT
              // announces as a DISABLED button (see 68d9b93).
              enabled: true,
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
            status: _locationStatus,
            phase: _grantPhase,
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
        // `scanning` is the whole point: the state this card is FOR is the
        // window between the cache read and the first scan landing, and in that
        // window a scan is already running. Telling the user to tap a button
        // that is disabled underneath the sentence is a screen that does not do
        // what its copy says ([[feedback_screen_does_what_copy_says]]).
        children.add(_NoScanYetCard(
          scanning: _loading,
          onScan: _loading ? null : _retry,
        ));
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
  const _NoScanYetCard({required this.onScan, required this.scanning});

  /// Runs the first scan. Null while one is already in flight.
  final VoidCallback? onScan;

  /// Whether a scan is already running. In the ordinary first-load path this is
  /// TRUE, because the card renders in the window between the cache read and
  /// the first scan landing. The copy and the button both follow it, so the
  /// card never invites a tap it has already disabled.
  final bool scanning;

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
                  scanning ? 'Scanning' : 'No scan yet',
                  style: text.titleSmall?.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            scanning
                ? 'Nothing has been measured yet. This machine has no stored '
                    'scan results, which is normal before the first scan. A '
                    'scan is running now.'
                : 'Nothing has been measured yet. This machine has no stored '
                    'scan results, which is normal before the first scan. Tap '
                    'Scan to look at what is on the air.',
            style: text.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          // No button at all while a scan runs: a disabled control under copy
          // that does not ask for a tap is just noise.
          if (!scanning)
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
/// payload is built (ApScanChannel.swift `mapNetwork`/`mapNetworks`, the 6 GHz
/// `.bandUnknown` case in `bandString`, and MainActivity.kt `mapScanResult`). An
/// earlier version of this doc claimed the `bandUnknown` drop "produces exactly
/// this payload"; that was wrong — it is handled natively and never reaches
/// Dart. Either the native layers report what they dropped, or this card and its
/// copy go. See the gate #4 QA report (F-2/F-3/F-4).
///
/// Pins here name SYMBOLS, not line numbers: the first version of this note
/// cited `ApScanChannel.swift:314` for the `bandUnknown` case and was wrong by
/// exactly the length of the note itself, because inserting these lines moved
/// the target. A line number written inside the file it points into is
/// self-invalidating.
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
    required this.status,
    required this.phase,
    required this.platformName,
    required this.onGrant,
    required this.onOpenSettings,
  });

  /// The tri-state authorization. THE load-bearing input: it decides whether an
  /// in-app grant is even possible, and therefore whether the button exists.
  final LocationAuthStatus status;

  /// Where the grant handshake is, so the card can describe a grant in flight
  /// instead of rendering a verdict about one that has not landed yet.
  final _GrantPhase phase;

  /// The OS name for the copy, or null on a platform with no name to attribute.
  final String? platformName;
  final VoidCallback? onGrant;
  final VoidCallback? onOpenSettings;

  /// Whether the OS can still surface an in-app prompt. `notDetermined` is the
  /// ONLY state where it can: once the user (or an MDM/parental restriction)
  /// has answered, macOS will not ask again from inside the app, ever.
  ///
  /// Delegates to the shared accessor rather than re-deriving the comparison
  /// locally (Vera LOW-1, 2026-07-20): one representation, one derivation. A
  /// local re-derivation is the seam where the two definitions drift apart.
  bool get _promptable => status.isPromptable;

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

  /// The OS name for a settings instruction, never a bare "the system".
  String get _settingsName =>
      platformName == 'macOS' ? 'System Settings' : 'Settings';

  /// The one sentence this card exists to get right.
  ///
  /// Every branch is a statement the app can actually support. There is
  /// deliberately NO branch that asserts "Location is still not granted",
  /// because the only moment that sentence used to be reachable was the one
  /// moment it was most likely to be FALSE: immediately after a successful
  /// grant, before it had propagated.
  String get _message {
    // A grant is in flight. Nothing is known yet, so nothing is claimed.
    if (phase == _GrantPhase.requesting) {
      return 'Waiting for the system Location prompt. Answer it to list the '
          'nearby access points.';
    }
    // The grant is HELD and the scan has not caught up. This is a statement
    // about propagation, and it is said as one.
    if (phase == _GrantPhase.settling) {
      return 'Location is granted. Waiting for the scan to pick it up. This '
          'takes a moment after the grant lands.';
    }
    switch (status) {
      case LocationAuthStatus.denied:
      case LocationAuthStatus.restricted:
        // NOT promptable. The old copy said "Grant it to list the nearby
        // access points", which instructed the user to do something the OS
        // forbids, beside a button that could not do it. Both are gone.
        return 'The scan could not run. $_reason Location is turned off for '
            'this app, and this app cannot ask again. That switch only exists '
            'in $_settingsName. Open it, enable Location for this app, then '
            'run Scan again. Until then this screen cannot tell you what is on '
            'the air, and this list being empty does not mean there are no '
            'access points nearby.';
      case LocationAuthStatus.authorized:
        // Authorization is held but the scan still reports it missing. Saying
        // the grant is missing would be a false statement about the machine.
        return 'Location is granted, but the scan still could not read the '
            'nearby networks. Tap Scan to try again. This screen cannot tell '
            'you what is on the air until it does, and this list being empty '
            'does not mean there are no access points nearby.';
      case LocationAuthStatus.notDetermined:
        return 'The scan could not run. $_reason Grant it to list the nearby '
            'access points. Until then this screen cannot tell you what is on '
            'the air.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String message = _message;
    // A grant in flight offers no buttons: the prompt owns the interaction, and
    // a second control underneath it is a race the user cannot win.
    final bool inFlight = phase != _GrantPhase.none;
    // THE FIX for the dead button. The in-app grant is rendered ONLY where the
    // OS can actually surface a prompt. Everywhere else the deep-link is the
    // only thing that can work, so it carries the primary weight instead of
    // sitting as an outlined afterthought beside a button that cannot act.
    final bool showGrant = !inFlight && _promptable && onGrant != null;
    final bool settingsIsPrimary = !showGrant;
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
          if (!inFlight && (showGrant || onOpenSettings != null)) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: <Widget>[
                if (showGrant)
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
                    label: settingsIsPrimary
                        ? 'Open $_settingsName to enable Location for this app'
                        : 'Open Location settings',
                    // Primary weight when it is the only action that can work,
                    // so the one usable route is not the quiet one.
                    child: settingsIsPrimary
                        ? FilledButton(
                            onPressed: onOpenSettings,
                            child: const Text('Open Settings'),
                          )
                        : OutlinedButton(
                            onPressed: onOpenSettings,
                            child: const Text('Open Settings'),
                          ),
                  ),
              ],
            ),
          ],
          // A grant in flight is progress, not a dead card: the spinner is the
          // visible counterpart to the copy above, so the settling window reads
          // as "working" rather than "stuck".
          if (inFlight) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.textAccent,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  phase == _GrantPhase.requesting
                      ? 'Waiting for your answer…'
                      : 'Checking again…',
                  style: text.bodySmall?.copyWith(color: colors.textTertiary),
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
