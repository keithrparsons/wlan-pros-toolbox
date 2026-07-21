// Roaming Log — records BSSID transitions (roams) within the same SSID during a
// foreground monitoring session (Feature 2, Felix 2026-06-13, per Pax's gap
// brief Deliverables/2026-06-13-toolbox-gap-feasibility/feasibility-brief.md).
//
// REUSE, no new measurement / permission / plugin: it drives the SAME shared
// [WifiSignalSampler] the live "Wi-Fi signal" card uses (macOS CoreWLAN poll /
// iOS companion-Shortcut stream), and reads the roam log the sampler now keeps
// via its [RoamDetector]. macOS auto-polls continuously while the screen is open;
// iOS streams via the companion Shortcut behind a single deliberate Start tap
// (auto-firing it would bounce the user out of the app — GL-008).
//
// HONESTY (GL-005 / GL-008): on iOS this captures roams during an ACTIVE
// FOREGROUND session only — there is no public iOS API for background Wi-Fi /
// BSSID-change callbacks, the same ceiling Wi-Fi Check shares. The screen says
// so plainly. A roam is recorded only when both the prior and current BSSID are
// known; a network (SSID) switch is excluded; nothing is fabricated.
//
// STATES (all explicit): unsupported/web (NetworkUnavailableView), monitoring +
// no roams yet (honest "watching" empty state), monitoring + roams (the event
// list), iOS-not-started (Start control), iOS feed failed (honest retry note),
// stopped (last list frozen). LAYOUT: SafeArea + centered ConstrainedBox(560) +
// scroll; surface1 cards with the §8.1 hairline; help is the §8.16.1 footer.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/pdf_download.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/device_info_service.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/roam_detector.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart' show LocationAuthStatus;
import '../../../services/network/wifi_signal_sampler.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import 'network_unavailable_view.dart';

/// The share/download seam this screen calls to export the formatted roam
/// document. Matches the [shareBytes] signature so a test can inject a fake that
/// never touches a platform channel.
typedef RoamShareFn = Future<void> Function({
  required List<int> bytes,
  required String filename,
  required String mimeType,
  String? title,
  ShareOrigin? shareOrigin,
});

/// The Roaming Log screen — a foreground roam recorder built on the shared live
/// sampler.
class RoamingLogScreen extends StatefulWidget {
  const RoamingLogScreen({
    super.key,
    this.sourceOverride,
    this.sampler,
    this.macAdapter,
    this.enableSampling = true,
    this.shareFn = shareBytes,
    this.deviceInfoReader,
  });

  /// Forces a specific Wi-Fi data source (tests). Defaults to the host platform
  /// via [WifiInfoSourceResolver].
  final WifiInfoSource? sourceOverride;

  /// Injectable live sampler (tests). Defaults to a real [WifiSignalSampler] on
  /// the resolved platform.
  final WifiSignalSampler? sampler;

  /// Injectable macOS Location adapter (tests). Used only for the macOS Location
  /// (name-gate) status + grant/deep-link flow — the same [WifiInfoAdapter] seam
  /// Wi-Fi Information and Test My Connection use. Defaults to the real CoreWLAN
  /// adapter on the macOS source and is null on every other source (they have no
  /// macOS Location gate to resolve here).
  final WifiInfoAdapter? macAdapter;

  /// When false, no sampler is started (tests that drive the sampler manually).
  final bool enableSampling;

  /// The share seam for the §8.16 Share document action. Defaults to the real
  /// [shareBytes]; tests inject a fake so the platform share channel is never
  /// touched.
  final RoamShareFn shareFn;

  /// Injectable device-info reader (tests). Defaults to the real
  /// [DeviceInfoService.read] on the resolved platform. Supplies the device
  /// model + OS version that enrich the exported "Captured on" stamp; a test
  /// injects a fake so no device_info_plus platform channel is touched.
  final Future<DeviceInfoSnapshot> Function()? deviceInfoReader;

  @override
  State<RoamingLogScreen> createState() => _RoamingLogScreenState();
}

class _RoamingLogScreenState extends State<RoamingLogScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;
  WifiSignalSampler? _sampler;

  /// macOS Location (name-gate) adapter, used only for the Location status +
  /// grant/deep-link flow. Non-null only on the macOS source.
  WifiInfoAdapter? _macAdapter;

  /// The RESOLVED macOS Location authorization, or null until the first
  /// no-prompt status read completes. While null the screen keeps its normal
  /// body, so a granted status resolves straight into the live roam log with no
  /// flash of the denied state. A resolved not-authorized status is what flips
  /// the body to the honest "Location access needed" surface.
  LocationAuthStatus? _macNameAuth;

  /// Guards the one proactive native Location prompt per screen mount. macOS
  /// remembers the first answer, so re-prompting would be pointless and jarring;
  /// after the first fire the only path forward for a denied user is the deep
  /// link to System Settings.
  bool _macLocationPromptFired = false;

  /// Wall-clock time this foreground recording session opened — stamped when the
  /// sampler is wired (macOS auto-polls from here; iOS begins on the Start tap,
  /// so this is the honest "log opened" time, never a fabricated reading). Feeds
  /// the §8.16 copy export header. Null when no sampler is active.
  DateTime? _sessionStart;

  /// The device's own model + OS version, read once on entry so the exported
  /// "Captured on" stamp can name the specific device (e.g. "MacBook Air, macOS
  /// 26.1") and multi-device roaming captures are told apart. Null until the
  /// async read resolves — and stays null on any platform that exposes nothing,
  /// in which case the stamp degrades to the bare platform word.
  DeviceInfoSnapshot? _deviceInfo;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();

    // macOS ONLY: the connected-AP identity every roam is built from (SSID/BSSID)
    // is withheld by CoreWLAN without a Location Services grant, so a denied user
    // sees roams that never record — a perpetual, unexplained "watching" that
    // looks broken (Keith hit this on-device). Hold the Location adapter so the
    // screen can resolve that status, request the grant when it is still
    // promptable, and deep-link System Settings when it is denied. iOS reads the
    // name through its own Shortcut flow and is deliberately untouched here.
    if (_source == WifiInfoSource.macosCoreWlan) {
      _macAdapter = widget.macAdapter ?? MacWifiInfoAdapter(enrichApName: true);
    }

    // Delegate the "can this platform monitor at all?" decision to the shared
    // SSOT [WifiSignalSampler.isSupportedSource] rather than repeating an inline
    // four-source list here (Vera LOW finding, 2026-06-30). The inline list is
    // exactly what let the roam log drift from the sampler and darken Windows
    // (bug C3); anchoring to the predicate means a new native source the sampler
    // learns to poll lights up here automatically with no edit, and can never
    // fall out of sync.
    if (widget.enableSampling && WifiSignalSampler.isSupportedSource(_source)) {
      // Share the macOS Location adapter with the sampler so both read one
      // CoreWLAN/CLLocationManager instance. `_macAdapter` is null off macOS, in
      // which case the sampler builds its own default source, exactly as before.
      _sampler = widget.sampler ??
          WifiSignalSampler(source: _source, macAdapter: _macAdapter);
      _sessionStart = DateTime.now();
      // Read the device model + OS version once, on a supported (native) source
      // only, so the export stamp names the device. Gated inside this block so a
      // web / unsupported source never reaches the dart:io device_info read.
      _initDeviceInfo();
      WidgetsBinding.instance.addObserver(this);
      _sampler!.load();
      // Every supported NON-iOS source (macOS / Android / Windows, and any future
      // native adapter) reads the feed from NATIVE polling with no app switch, so
      // it auto-starts on entry. iOS alone waits for the single deliberate Start
      // tap — firing the companion Shortcut on entry would bounce the user out of
      // the app (GL-008). Expressed as "supported and not iOS" so it, too, tracks
      // the SSOT instead of re-listing platforms.
      if (_source != WifiInfoSource.iosShortcuts) {
        _sampler!.start();
      }
    }

    // Resolve (and, when still promptable, request) the macOS Location grant.
    // Fire-and-forget with mounted guards; a denied result flips the body to the
    // honest "Location access needed" state. No-op off macOS.
    _initMacLocation();
  }

  /// Resolves the macOS Location (name-gate) status on entry and, when it is
  /// still PROMPTABLE (`notDetermined`), fires the native system prompt ONCE so
  /// the user gets the OS dialog rather than a silent wall. A `denied` /
  /// `restricted` status cannot raise a dialog, so it skips straight to the
  /// deep-link state the body renders. No-op off macOS / for an ungated adapter.
  /// Never throws.
  Future<void> _initMacLocation() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null || !adapter.gatesNameBehindPermission) return;
    try {
      LocationAuthStatus auth = await adapter.nameAuthorizationStatus();
      if (auth.isPromptable && !_macLocationPromptFired) {
        _macLocationPromptFired = true;
        await adapter.requestNamePermission();
        if (!mounted) return;
        // Re-read the now-resolved status so the body reflects the user's choice
        // without waiting for a resume.
        auth = await adapter.nameAuthorizationStatus();
      }
      if (!mounted) return;
      setState(() => _macNameAuth = auth);
    } on Object {
      // Honest fallback: leave the status unresolved (null) so the screen keeps
      // its normal body rather than asserting a denial it could not confirm.
    }
  }

  /// Reads the device's model + OS version once on entry (async, fire-and-forget
  /// with a mounted guard, exactly like [_initMacLocation]) so the exported
  /// "Captured on" stamp can name the specific device — e.g. "MacBook Air, macOS
  /// 26.1" or "iPhone 17, iOS 26". A failed or empty read leaves [_deviceInfo]
  /// null and the stamp degrades to the bare platform word (the graceful floor).
  /// Never throws; never fabricates a model or version.
  Future<void> _initDeviceInfo() async {
    final Future<DeviceInfoSnapshot> Function() reader =
        widget.deviceInfoReader ?? DeviceInfoService().read;
    try {
      final DeviceInfoSnapshot snap = await reader();
      if (!mounted) return;
      setState(() => _deviceInfo = snap);
    } on Object {
      // Honest floor: keep _deviceInfo null → the bare platform label stands.
    }
  }

  /// Re-reads the macOS Location status WITHOUT a prompt, so a grant the user
  /// made in System Settings while the screen was backgrounded lands on return
  /// with no relaunch. No-op off macOS. Never throws.
  Future<void> _refreshMacLocation() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null || !adapter.gatesNameBehindPermission) return;
    try {
      final LocationAuthStatus auth = await adapter.nameAuthorizationStatus();
      if (!mounted) return;
      setState(() => _macNameAuth = auth);
    } on Object {
      // Keep the prior status; never fabricate a reason.
    }
  }

  /// Deep-links System Settings -> Privacy and Security -> Location Services so
  /// the user can enable this app manually. macOS cannot toggle its own Location
  /// grant in code (TCC protection), so this opens the exact pane; the resume
  /// re-read then flips the screen back to the live roam log once it is on.
  Future<void> _openLocationSettings() async {
    await _macAdapter?.openNamePermissionSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final WifiSignalSampler? sampler = _sampler;
    if (sampler == null) return;
    if (state == AppLifecycleState.resumed) {
      sampler.load();
      sampler.resumeMac();
      // Pick up a macOS Location grant made in System Settings while backgrounded.
      _refreshMacLocation();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      sampler.pauseMac();
    }
  }

  @override
  void dispose() {
    if (_sampler != null) {
      WidgetsBinding.instance.removeObserver(this);
      if (widget.sampler == null) _sampler!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roaming Log'),
        toolbarHeight: 64,
        // §8.16: copy leads, then the Share document export. Both serialize the
        // session on demand and are disabled (not focusable) on the honest empty
        // state, so neither ever exports a fake/empty log.
        //
        // The sampler is a ChangeNotifier: new roams fire notifyListeners(),
        // which without this wrapper would only rebuild the roam-list card,
        // NEVER these AppBar actions — so AppCopyAction, which resolves its
        // enabled state from textBuilder() at BUILD time, would latch to the
        // disabled state it had at screen-open (zero roams) for the whole
        // session (the dead-Copy-button bug). Wrapping them in an AnimatedBuilder
        // bound to the sampler re-resolves enabled as roams land. The null /
        // unsupported branch keeps a static disabled copy action, matching the
        // prior behavior.
        actions: <Widget>[
          if (_sampler != null)
            AnimatedBuilder(
              animation: _sampler!,
              builder: (BuildContext context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppCopyAction(textBuilder: _buildCopyText),
                  _RoamShareAction(
                    htmlBuilder: _buildShareHtml,
                    shareFn: widget.shareFn,
                  ),
                ],
              ),
            )
          else
            AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// The capture platform, resolved from the same [WifiInfoSource] the screen
  /// already uses. Stamped into the Copy report and the Share document so three
  /// side-by-side captures (iPhone + Android + macOS) are each self-identifying.
  String get _capturePlatform => capturePlatformLabel(_source);

  /// The enriched "Captured on" stamp: the device model + platform + OS version
  /// when known (e.g. "MacBook Air, macOS 26.1"), degrading to the bare platform
  /// word when the device exposes nothing. Feeds the exports' display line; the
  /// bare [_capturePlatform] still drives the platform-specific honesty note.
  String get _capturedOnLabel => captureLabel(_capturePlatform, _deviceInfo);

  /// §8.16 copy payload — delegates to the pure [buildRoamLogCopyText] so the
  /// serialization is unit-testable without a live sampler. Returns null
  /// (→ disabled affordance) when no sampler is active or no roam is recorded.
  String? _buildCopyText() {
    final WifiSignalSampler? s = _sampler;
    if (s == null) return null;
    final List<RoamEvent> events = s.roamEvents;
    return buildRoamLogCopyText(
      events: events,
      network: _sessionNetwork(s, events),
      sessionStart: _sessionStart,
      capturePlatform: _capturePlatform,
      capturedOnLabel: _capturedOnLabel,
    );
  }

  /// §8.16 Share document payload — delegates to the pure [buildRoamLogShareHtml]
  /// so the HTML is unit-testable without a live sampler. Returns null (→ disabled
  /// Share affordance) when no sampler is active or no roam is recorded.
  String? _buildShareHtml() {
    final WifiSignalSampler? s = _sampler;
    if (s == null) return null;
    final List<RoamEvent> events = s.roamEvents;
    return buildRoamLogShareHtml(
      events: events,
      network: _sessionNetwork(s, events),
      sessionStart: _sessionStart,
      capturePlatform: _capturePlatform,
      capturedOnLabel: _capturedOnLabel,
    );
  }

  /// The network the session belongs to: the live SSID where the platform still
  /// exposes it, else the most recent roam's SSID, else the honest "Wi-Fi"
  /// fallback the rows use when no name was read.
  String _sessionNetwork(WifiSignalSampler s, List<RoamEvent> events) {
    final String? live = s.latest?.ssid;
    if (live != null && live.trim().isNotEmpty) return live;
    for (final RoamEvent e in events.reversed) {
      final String? ssid = e.ssid;
      if (ssid != null && ssid.trim().isNotEmpty) return ssid;
    }
    return 'Wi-Fi';
  }

  Widget _body() {
    if (!NetworkSupport.activeNetworkSupported ||
        _source == WifiInfoSource.web) {
      return const NetworkUnavailableView(
        toolName: 'Roaming Log',
        reason: NetworkUnavailableReason.web,
      );
    }
    if (_source == WifiInfoSource.unsupported) {
      return const NetworkUnavailableView(
        toolName: 'Roaming Log',
        reason: NetworkUnavailableReason.platformApiMissing,
      );
    }

    // macOS with Location DENIED / RESTRICTED: CoreWLAN withholds the SSID/BSSID
    // every roam is built from, so the log can never record. Show the actionable
    // "Location access needed" state (with a deep link to the settings pane)
    // rather than a perpetual empty "watching for roams" that looks broken.
    //
    // Only the DEEP-LINK-ONLY statuses render this. A `notDetermined` status is
    // PROMPTABLE — `_initMacLocation` fires the native prompt for it — so the body
    // stays normal while that prompt is in flight; it resolves into either the
    // live log (granted) or this state (the user denied and the re-read returns
    // `denied`). A null (unresolved) status also keeps the normal body, so a
    // granted status never flashes this state on the way in.
    if (_source == WifiInfoSource.macosCoreWlan &&
        _macNameAuth != null &&
        !_macNameAuth!.isAuthorized &&
        !_macNameAuth!.isPromptable) {
      return NetworkUnavailableView(
        toolName: 'Roaming Log',
        reason: NetworkUnavailableReason.macosLocationDenied,
        actionLabel: 'Open Location settings',
        onAction: _openLocationSettings,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
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
                AppSpacing.md,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Current connection LEADS the body so the user sees their live
                  // link state the instant the tool opens — before any roam fires.
                  // It renders the SAME sampler reading the roam watch consumes
                  // (no second fetcher) and refreshes at the same cadence.
                  if (_sampler != null) ...<Widget>[
                    _CurrentConnectionCard(sampler: _sampler!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _intro(context),
                  const SizedBox(height: AppSpacing.md),
                  if (_sampler != null)
                    _RoamLogCard(sampler: _sampler!)
                  else
                    _RoamLogCard.disabled(context),
                  const ToolHelpFooter(toolId: 'roaming-log'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _intro(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final bool isIos = _source == WifiInfoSource.iosShortcuts;
    return Text(
      isIos
          ? 'Walk around with this open to record each time your device roams '
              'from one access point to another on the same network. iOS records '
              'roams while this screen is open and running. There is no '
              'background Wi-Fi monitoring on iOS.'
          // macOS / Android / Windows all auto-poll the link natively — keep the
          // copy platform-neutral so it stays true on each (it previously said
          // "macOS" for every non-iOS platform, wrong on Android and Windows).
          : 'Walk around with this open to record each time your device roams '
              'from one access point to another on the same network. Your device '
              'reads the link continuously while this screen is open.',
      style: text.bodyLarge?.copyWith(color: colors.textSecondary),
    );
  }
}

/// The last two octets (last 4 hex digits) of a BSSID, e.g. ":3a:10" — the part
/// that identifies the AP on a same-brand deployment where the OUI (the first
/// three octets) is shared across every radio. Falls back to the whole value for
/// a short / malformed BSSID that has fewer than two colon-separated octets, so
/// a non-standard identifier is shown in full rather than mangled (GL-005).
@visibleForTesting
String lastOctets(String bssid) {
  final String trimmed = bssid.trim();
  final List<String> parts = trimmed.split(':');
  if (parts.length < 2) return trimmed.isEmpty ? bssid : trimmed;
  return ':${parts.sublist(parts.length - 2).join(':')}';
}

/// The capture platform label for a [WifiInfoSource], stamped into the exported
/// reports so three side-by-side captures (iPhone + Android + macOS laptop) are
/// each self-identifying. macOS / Android / Windows report the band directly;
/// iOS derives it from the channel (see [ConnectedAp.bandDerived]).
@visibleForTesting
String capturePlatformLabel(WifiInfoSource source) {
  switch (source) {
    case WifiInfoSource.macosCoreWlan:
      return 'macOS';
    case WifiInfoSource.iosShortcuts:
      return 'iOS';
    case WifiInfoSource.androidWifiManager:
      return 'Android';
    case WifiInfoSource.windowsNativeWifi:
      return 'Windows';
    case WifiInfoSource.unsupported:
    case WifiInfoSource.web:
      return 'this device';
  }
}

/// Builds the enriched "Captured on" stamp from the bare [platform] word and an
/// optional [DeviceInfoSnapshot], so several devices roaming the same path are
/// each self-identifying in the exported report — e.g. "MacBook Air, macOS 26.1"
/// or "iPhone 17, iOS 26".
///
/// Honest fallback chain (GL-005 — never fabricate a model or version):
///   * model = `modelName`, else the raw `modelIdentifier`, else absent;
///   * version appended after the platform word only when known;
///   * with a model:   `model, platform version`
///   * without a model: `platform version`
/// so a snapshot exposing nothing (or a null snapshot) degrades to exactly the
/// bare [platform] word — the same graceful floor the reports had before.
@visibleForTesting
String captureLabel(String platform, DeviceInfoSnapshot? info) {
  String? clean(String? v) =>
      (v != null && v.trim().isNotEmpty) ? v.trim() : null;

  final String? model = clean(info?.modelName) ?? clean(info?.modelIdentifier);
  final String? version = clean(info?.osVersion);
  final String platformPart = version != null ? '$platform $version' : platform;
  return model != null ? '$model, $platformPart' : platformPart;
}

/// The channel-first band/channel descriptor for one side of a roam, e.g.
/// "ch 44 · 5 GHz". Channel LEADS because it is exact on every platform; band
/// is the derived companion on iOS, where a bare channel number mislabels 6 GHz
/// APs (channels 36 to 177 read as "5 GHz", channels 1 to 14 as "2.4 GHz"). A
/// [derived] band carries the trailing "*" that the report's footnote explains.
/// Omits any null part honestly; returns "" when neither is known.
@visibleForTesting
String bandChannelLabel(int? channel, String? band, {bool derived = false}) {
  final List<String> parts = <String>[];
  if (channel != null) parts.add('ch $channel');
  if (band != null && band.trim().isNotEmpty) {
    parts.add(derived ? '$band*' : band);
  }
  return parts.join(' · ');
}

/// True when any roam in the session carried a band that was derived app-side
/// (iOS). Drives the "band derived" footnote so it appears only when relevant.
bool _anyBandDerived(List<RoamEvent> events) => events.any(
      (RoamEvent e) =>
          (e.fromBandDerived && e.fromBand != null) ||
          (e.toBandDerived && e.toBand != null),
    );

/// The one-line derived-band caveat. Kept identical between the Copy report and
/// the Share document so both read the same honest way.
const String _kDerivedBandNote =
    '* Band derived from the channel number on iOS; it can disagree with a '
    'device that reads the band directly, notably in 6 GHz. The channel is '
    'exact on every platform.';

/// The foreground caveat, matched to the capture platform so a macOS / Android
/// report does not carry an iOS-specific note. iOS states the hard ceiling (no
/// background Wi-Fi callbacks exist); the others state the plainer truth.
String _foregroundNote(String capturePlatform) => capturePlatform == 'iOS'
    ? 'iOS records roams only while this screen is open and running. There is no '
        'background Wi-Fi monitoring on iOS.'
    : 'Roams are recorded while this screen is open.';

/// Builds the §8.16 copy payload: the recorded roam session as a clean,
/// monospace-aligned, paste-anywhere plain-text report. A header (network,
/// capture platform, session window, roam count, and a signal summary) then a
/// fixed-column table, one row per [RoamEvent] in chronological order, each
/// leading with the CHANNEL (exact everywhere) and carrying the last-octet AP
/// identifiers, the band (marked derived on iOS), the signal + SNR, and the
/// dwell on the prior AP.
///
/// Honesty (GL-005): a field a sample omitted prints as "n/a" or is dropped from
/// the summary — never a fabricated value. Returns null (→ disabled affordance)
/// when [events] is empty; the empty session is not a "log to keep".
///
/// Pure and deterministic (no clock, no I/O). ASCII-safe arrows ("->") and no em
/// dashes, so the voice guard passes. Unit-tested directly with synthetic
/// [RoamEvent]s, no live sampler required.
@visibleForTesting
String? buildRoamLogCopyText({
  required List<RoamEvent> events,
  required String network,
  String capturePlatform = 'this device',
  String? capturedOnLabel,
  DateTime? sessionStart,
}) {
  if (events.isEmpty) return null;

  // The display stamp is the enriched device label when provided, else the bare
  // platform word. [capturePlatform] itself stays the bare word so the honesty
  // note ([_foregroundNote]) keeps matching on "iOS".
  final String capturedOn = capturedOnLabel ?? capturePlatform;

  final StringBuffer buf = StringBuffer()
    ..writeln('Roaming Log')
    ..writeln('Network: $network')
    ..writeln('Captured on: $capturedOn');

  // Session window: opened at sessionStart (or the first roam if none), through
  // the last roam.
  final DateTime windowStart = sessionStart ?? events.first.at;
  final DateTime windowEnd = events.last.at;
  buf.writeln(
    'Session: ${_RoamRow._formatTime(windowStart)} to '
    '${_RoamRow._formatTime(windowEnd)} '
    '(${_formatDwell(windowEnd.difference(windowStart))})',
  );
  buf.writeln(
    events.length == 1 ? '1 roam recorded' : '${events.length} roams recorded',
  );
  buf.writeln(_signalSummary(events));

  // Build the table cells, then size each column to its widest cell so the
  // report aligns in any monospace context (a code block, Notes, a terminal).
  const List<String> headers = <String>[
    '#',
    'Time',
    'From',
    'To',
    'Signal',
    'On prev AP',
  ];
  final List<List<String>> rows = <List<String>>[];
  for (int i = 0; i < events.length; i++) {
    final RoamEvent e = events[i];
    rows.add(<String>[
      '${i + 1}',
      _RoamRow._formatTime(e.at),
      _apCell(e.fromBssid, e.fromChannel, e.fromBand, e.fromBandDerived,
          apName: e.resolvedFromApName()),
      _apCell(e.toBssid, e.toChannel, e.toBand, e.toBandDerived,
          apName: e.resolvedToApName()),
      _signalCell(e),
      // The first roam has no prior roam to measure dwell from, so it is honestly
      // "n/a" rather than a guessed 0.
      i == 0 ? 'n/a' : _formatDwell(e.at.difference(events[i - 1].at)),
    ]);
  }

  final List<int> widths = List<int>.generate(headers.length, (int c) {
    int w = headers[c].length;
    for (final List<String> r in rows) {
      if (r[c].length > w) w = r[c].length;
    }
    return w;
  });

  String pad(String cell, int col) {
    // Right-align the ordinal column, left-align the rest.
    return col == 0
        ? cell.padLeft(widths[col])
        : cell.padRight(widths[col]);
  }

  String line(List<String> cells) {
    final List<String> padded = <String>[
      for (int c = 0; c < cells.length; c++) pad(cells[c], c),
    ];
    return padded.join('  ').trimRight();
  }

  buf
    ..writeln()
    ..writeln(line(headers));
  for (final List<String> r in rows) {
    buf.writeln(line(r));
  }

  // Honesty footnotes.
  buf.writeln();
  if (_anyBandDerived(events)) buf.writeln(_kDerivedBandNote);
  buf.write(_foregroundNote(capturePlatform));

  return buf.toString().trimRight();
}

/// One from/to table cell: last-octet identifier, then the channel-first band
/// descriptor (e.g. ":3a:10 ch 44 · 5 GHz").
String _apCell(String bssid, int? channel, String? band, bool derived,
    {String? apName}) {
  final String tail = lastOctets(bssid);
  final String bc = bandChannelLabel(channel, band, derived: derived);
  final String core = bc.isEmpty ? tail : '$tail $bc';
  // The vendor-advertised name (when present) LEADS the cell, matching the
  // on-screen row where the name sits above the BSSID tail.
  if (apName != null && apName.trim().isNotEmpty) {
    return '${apName.trim()} $core';
  }
  return core;
}

/// The signal cell for the table: the OLD ("from") AP's last RSSI, an arrow, and
/// the NEW ("to") AP's RSSI at the roam, so the delta reads left to right in the
/// same direction as the From/To AP columns, e.g. "-67 dBm -> -72 dBm". SNR (the
/// single reading at the roam) trails when present. Honest-null: a reading the
/// platform omitted prints "n/a"; both absent collapses to "signal n/a" (GL-005).
/// ASCII "->" keeps the report paste-safe and past the voice guard.
String _signalCell(RoamEvent e) {
  final int? from = e.fromRssiDbm;
  final int? to = e.rssiDbm;
  final String snr = e.snrDb != null ? ' SNR ${e.snrDb} dB' : '';
  if (from == null && to == null) return 'signal n/a$snr';
  final String fromStr = from != null ? '$from dBm' : 'n/a';
  final String toStr = to != null ? '$to dBm' : 'n/a';
  return '$fromStr -> $toStr$snr';
}

/// The pre-roam ("before") RSSI population: the last reading on each AP the
/// client LEFT. This is the roam TRIGGER level — how weak the client let the
/// signal get before it let go. Honest-null: a roam whose prior AP carried no
/// RSSI (always the first roam, which has no prior AP) contributes nothing. It
/// is never zeroed, because a 0 would read as a signal and drag the average.
List<int> _preRoamRssi(List<RoamEvent> events) => <int>[
      for (final RoamEvent e in events)
        if (e.fromRssiDbm != null) e.fromRssiDbm!,
    ];

/// The post-roam ("after") RSSI population: the reading on each AP the client
/// JOINED. This is the roam DESTINATION level — what the client got in return.
List<int> _postRoamRssi(List<RoamEvent> events) => <int>[
      for (final RoamEvent e in events)
        if (e.rssiDbm != null) e.rssiDbm!,
    ];

/// Average / strongest / weakest over one RSSI population. RSSI is negative
/// dBm, so the STRONGEST is the greatest value (closest to zero). Returns null
/// for an empty population so the caller can degrade honestly (GL-005).
_RssiStats? _rssiStats(List<int> values) {
  if (values.isEmpty) return null;
  final int sum = values.reduce((int a, int b) => a + b);
  return _RssiStats(
    avg: (sum / values.length).round(),
    strongest: values.reduce((int a, int b) => a > b ? a : b),
    weakest: values.reduce((int a, int b) => a < b ? a : b),
  );
}

/// Aggregates over ONE RSSI population. Deliberately never mixes the pre-roam
/// and post-roam sets: an average over the two pooled together describes no
/// physical quantity, and its value would shift with the ratio of readings the
/// platform happened to record rather than with the RF.
class _RssiStats {
  const _RssiStats({
    required this.avg,
    required this.strongest,
    required this.weakest,
  });

  final int avg;
  final int strongest;
  final int weakest;
}

/// The sample-size disclosure for ONE RSSI population: `n of N roams`, or the
/// empty string when the population is COMPLETE (every roam reported).
///
/// Suppressing on a complete capture is deliberate. Printing "4 of 4 roams" on
/// both lines of every report trains the reader to skim past the count, which
/// would blind them on the one capture where it matters. Because the note is
/// emitted only when something was omitted, its PRESENCE is the signal.
///
/// The test is completeness against the roam count, NOT equality between the
/// two populations: 3-of-40 beside 3-of-40 is a fair comparison between the two
/// lines and an unfair one against the session, and the reader is owed that.
///
/// Suppressing at n == total also guarantees grammatical output — n < total
/// implies total >= 2, so the plural "roams" is always correct, and the
/// degenerate "1 of 1 roams" can never be emitted.
///
/// LOAD-BEARING PRECONDITION — do not remove the per-roam table.
/// Silence on a complete capture is only honest because the export carries the
/// full per-roam table below the summary, where every non-reporting roam
/// renders `signal n/a`. That table is what makes completeness auditable FROM
/// THE ARTIFACT ITSELF, so the absence of a count is checkable rather than
/// merely trusted. If the table is ever dropped, or a summary-only export
/// ships, suppression stops being safe and this function must emit the count
/// unconditionally.
///
/// n == 0 also returns empty: an empty population has no statistic to qualify,
/// so its callers take the honest "not reported" path instead (GL-005).
///
/// That guard is REACHED, not unreachable, and no test can currently kill it.
/// Both halves of that sentence matter, and an earlier version of this comment
/// got the reason wrong in a way worth recording.
///
/// n == 0 DOES arrive: the share-HTML tile block computes `preCoverage` /
/// `postCoverage` eagerly, before the `if (before != null)` guard four lines
/// below it, so an empty population calls straight through. Replacing this
/// body with a `throw` made four existing tests throw from that call when this
/// was written (a measurement, not an invariant — re-run the probe rather than
/// trusting the number).
///
/// What protects the output is therefore NOT "no caller passes 0" — that is
/// false. It is that the ONE caller which passes 0 DISCARDS the result: the
/// coverage string is only ever consumed inside the null guard, so a "0 of 40
/// roams" label cannot reach a tile. That is a property of that one line, not
/// of the call sites, and it is fragile in exactly the way the false version
/// was not: move the consumption out of the guard, or add a caller that uses
/// the value eagerly, and the guard here becomes the only thing standing
/// between a reader and a count attached to an average that does not exist.
///
/// Removing the guard still passes the whole suite, because the discarded
/// string is unobservable. So it is documented rather than covered — a test
/// asserting on a value nothing renders would be theatre. To tell a surviving
/// mutant apart from genuinely dead code, replace the body with a `throw`:
/// survival proves nothing, a throw proves reachability or its absence.
String _coverageNote(int n, int total) =>
    (n == 0 || n == total) ? '' : '$n of $total roams';

/// The parenthetical for a population line: which AP the reading came from,
/// plus the sample size when the population is incomplete.
String _populationQualifier(String population, int n, int total) {
  final String coverage = _coverageNote(n, total);
  return coverage.isEmpty ? population : '$population, $coverage';
}

/// The header signal-summary: ONE line per population, each labeled for the
/// reading it actually summarizes and for the number of roams behind it.
///
/// `rssiDbm` is always the POST-roam reading (the AP just joined, so always
/// comparatively strong) and `fromRssiDbm` is always the PRE-roam reading (the
/// AP being left, so always comparatively weak). Summarizing only the former
/// reported the network as better than the client experienced and discarded
/// exactly the number a designer needs. The two are reported separately rather
/// than pooled, because "the level this client roams at" and "the level it
/// lands on" are different measurements and one average cannot label both.
///
/// The two lines are typographic peers but are NOT always sample-size peers:
/// iOS omits RSSI far more often than macOS, so "before" can be computed from a
/// handful of roams while "after" is computed from all of them. Presenting those
/// as a side-by-side comparison without stating n invites exactly the false
/// read this summary exists to prevent — the same reason the two populations
/// are never pooled. Each line therefore carries its own [_coverageNote].
///
/// "Signal: not reported" when neither population carried a reading (GL-005).
String _signalSummary(List<RoamEvent> events) {
  final List<int> pre = _preRoamRssi(events);
  final List<int> post = _postRoamRssi(events);
  final _RssiStats? before = _rssiStats(pre);
  final _RssiStats? after = _rssiStats(post);
  if (before == null && after == null) return 'Signal: not reported';

  final int total = events.length;
  String line(String label, String population, int n, _RssiStats s) =>
      '$label (${_populationQualifier(population, n, total)}): '
      'avg ${s.avg} dBm, strongest ${s.strongest} dBm, '
      'weakest ${s.weakest} dBm';

  final List<String> lines = <String>[
    before != null
        ? line('Signal before roam', 'on the AP being left', pre.length, before)
        : 'Signal before roam: not reported',
    after != null
        ? line('Signal after roam', 'on the AP joined', post.length, after)
        : 'Signal after roam: not reported',
  ];
  return lines.join('\n');
}

/// "45s" / "2m" / "2m 5s" — dwell between consecutive roams, no intl dependency.
/// Negative/zero clamps to "0s".
String _formatDwell(Duration d) {
  final int total = d.inSeconds;
  if (total <= 0) return '0s';
  if (total < 60) return '${total}s';
  final int minutes = total ~/ 60;
  final int seconds = total % 60;
  return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
}

/// Builds the §8.16 Share document: a self-contained HTML report that visually
/// echoes the Copy report (title header, a summary block, the full roam table,
/// and the honesty notes). Shared to the platform sheet as a file (Mail
/// attachment / Files / AirDrop). Unlike the compact on-screen rows, the table
/// carries the COMPLETE BSSIDs alongside the channel and band, because a
/// document has room for them.
///
/// The layout is identical across iOS / macOS / Android (only the "Captured on"
/// stamp and the derived-band footnote differ), so three captures read as one
/// tool. Pure and deterministic; returns null when [events] is empty. No em
/// dashes; every interpolated value is HTML-escaped.
@visibleForTesting
String? buildRoamLogShareHtml({
  required List<RoamEvent> events,
  required String network,
  String capturePlatform = 'this device',
  String? capturedOnLabel,
  DateTime? sessionStart,
}) {
  if (events.isEmpty) return null;

  // Enriched device stamp for display; the bare [capturePlatform] still drives
  // the platform-specific honesty note ([_foregroundNote]).
  final String capturedOn = capturedOnLabel ?? capturePlatform;

  final DateTime windowStart = sessionStart ?? events.first.at;
  final DateTime windowEnd = events.last.at;
  final String sessionLen = _formatDwell(windowEnd.difference(windowStart));
  final String countLabel =
      events.length == 1 ? '1 roam recorded' : '${events.length} roams recorded';

  // Element-content escaping (escapes & < >). The values below are inserted as
  // element text, never into attributes, so element mode is correct and keeps
  // readable characters like "/" and "'" intact (the default `unknown` mode
  // would render them as numeric entities).
  String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

  // Computed aggregates (each honest: derived only from the events present).
  // The two RSSI populations stay separate end to end — see [_signalSummary].
  final List<int> preRssi = _preRoamRssi(events);
  final List<int> postRssi = _postRoamRssi(events);
  final List<int> snr = <int>[
    for (final RoamEvent e in events)
      if (e.snrDb != null) e.snrDb!,
  ];
  final List<Duration> dwells = <Duration>[
    for (int i = 1; i < events.length; i++) events[i].at.difference(events[i - 1].at),
  ];
  final List<_PingPong> pingPongs = _detectPingPongs(events);
  final Set<int> flapRows = <int>{
    for (final _PingPong p in pingPongs) ...<int>[p.firstIndex, p.firstIndex + 1],
  };

  // ---- Stat tiles (omit a tile whose datum is absent) ----
  final StringBuffer tiles = StringBuffer()
    ..write(_statTile('${events.length}', 'roams in $sessionLen'));
  // Signal tiles, each labeled for the population it computes. The old pair
  // ('dBm avg at roam' / 'dBm strongest / weakest') read as the trigger level
  // but computed the destination, so a client-facing report could claim a floor
  // its own table contradicted. Each tile is emitted only when its population
  // carried a reading (GL-005) — a missing tile, never an invented number.
  //
  // The before/after tiles sit adjacent in the grid, so they read as peers. Any
  // tile computed from fewer than every roam carries its sample size, for the
  // same reason the copy-report lines do — see [_coverageNote]. The label wraps
  // inside the tile (`.stat .l` sets no `white-space`), so the suffix costs
  // height, not width.
  final _RssiStats? before = _rssiStats(preRssi);
  final _RssiStats? after = _rssiStats(postRssi);
  final String preCoverage = _coverageNote(preRssi.length, events.length);
  final String postCoverage = _coverageNote(postRssi.length, events.length);
  String tileLabel(String base, String coverage) =>
      coverage.isEmpty ? base : '$base ($coverage)';
  if (before != null) {
    tiles
      ..write(_statTile('${before.avg}', tileLabel('dBm avg before roam', preCoverage)))
      // The number the designer sizes cell overlap from: how weak the client
      // let it get before it let go.
      ..write(_statTile(
          '${before.weakest}', tileLabel('dBm weakest before roam', preCoverage)));
  }
  if (after != null) {
    tiles.write(_statTile('${after.avg}', tileLabel('dBm avg after roam', postCoverage)));
  }
  // SNR carries a count for the same reason the RSSI tiles do, and it is this
  // change that made it necessary. Before the coverage notes existed, a bare
  // tile meant nothing in particular. Now that three tiles beside it disclose
  // their sample size, a SILENT tile asserts completeness by convention — so an
  // SNR range over 3 of 40 roams, printed bare next to them, would lie in the
  // vocabulary this commit taught the reader.
  if (snr.isNotEmpty) {
    final int lo = snr.reduce((int a, int b) => a < b ? a : b);
    final int hi = snr.reduce((int a, int b) => a > b ? a : b);
    tiles.write(_statTile(lo == hi ? '$lo' : '$lo-$hi',
        tileLabel('dB SNR range', _coverageNote(snr.length, events.length))));
  }
  if (dwells.isNotEmpty) {
    final int avgDwell =
        (dwells.map((Duration d) => d.inSeconds).reduce((int a, int b) => a + b) /
                dwells.length)
            .round();
    tiles.write(_statTile(_formatDwell(Duration(seconds: avgDwell)), 'avg dwell per AP'));
  }

  // ---- Roam-event rows (Signal and SNR split into their own columns) ----
  final StringBuffer rowsHtml = StringBuffer();
  for (int i = 0; i < events.length; i++) {
    final RoamEvent e = events[i];
    final String dwell =
        i == 0 ? 'n/a' : _formatDwell(e.at.difference(events[i - 1].at));
    final String signal = _htmlSignalFromTo(e);
    final String snrCell = e.snrDb != null ? '${e.snrDb} dB' : 'not recorded';
    final String cls = flapRows.contains(i) ? ' class="flap"' : '';
    rowsHtml.writeln(
      '<tr$cls>'
      '<td class="num">${i + 1}</td>'
      '<td>${esc(_RoamRow._formatTime(e.at))}</td>'
      '<td>${_apCellHtml(e.fromBssid, e.fromChannel, e.fromBand, e.fromBandDerived, esc, apName: e.resolvedFromApName())}</td>'
      '<td>${_apCellHtml(e.toBssid, e.toChannel, e.toBand, e.toBandDerived, esc, apName: e.resolvedToApName())}</td>'
      '<td class="num">${esc(signal)}</td>'
      '<td class="num">${esc(snrCell)}</td>'
      '<td class="num">${esc(dwell)}</td>'
      '</tr>',
    );
  }

  // ---- Session at a glance: COMPUTED facts only (GL-005) ----
  final List<String> facts = _sessionFacts(events, dwells, pingPongs);
  final StringBuffer glance = StringBuffer();
  if (facts.isNotEmpty) {
    glance.writeln('<h2>Session at a glance</h2>');
    glance.writeln('<ul class="notes">');
    for (final String f in facts) {
      glance.writeln('  <li>${esc(f)}</li>');
    }
    glance.writeln('</ul>');
  }

  // ---- Honesty callout (same content as the plain notes, in a proper box) ----
  final StringBuffer callout = StringBuffer()
    ..write('<div class="callout"><strong>Honesty notes on this capture.</strong> ');
  if (_anyBandDerived(events)) {
    callout.write('${esc(_kDerivedBandNote)} ');
  }
  callout
    ..write(esc(_foregroundNote(capturePlatform)))
    ..write('</div>');

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Roaming Log</title>
<style>
  :root{
    --ink:#1a1a1a; --muted:#5f6368; --faint:#8a8f98;
    --line:#e3e5e8; --surface:#f7f8f9; --accent:#5a7d2a;
    --mono:"SF Mono",ui-monospace,Menlo,Consolas,monospace;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  }
  *{box-sizing:border-box}
  html,body{margin:0}
  body{font-family:var(--sans);color:var(--ink);line-height:1.5;
    background:#fff;padding:40px 32px 56px;max-width:920px;margin:0 auto;font-size:15px}
  header{border-bottom:2px solid var(--ink);padding-bottom:14px;margin-bottom:20px}
  h1{font-size:24px;margin:0 0 4px;letter-spacing:-.01em}
  .sub{color:var(--muted);font-size:14px}
  h2{font-size:16px;margin:28px 0 10px;letter-spacing:-.01em;
    border-bottom:1px solid var(--line);padding-bottom:6px}
  .meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:6px 32px;
    margin:16px 0;font-size:14px}
  .meta div{display:flex;justify-content:space-between;
    border-bottom:1px dotted var(--line);padding:4px 0}
  .meta .k{color:var(--muted)}
  .meta .v{font-weight:600;text-align:right}
  .stats{display:flex;flex-wrap:wrap;gap:12px;margin:14px 0 4px}
  .stat{flex:1 1 130px;background:var(--surface);border:1px solid var(--line);
    border-radius:8px;padding:12px 14px}
  .stat .n{font-size:22px;font-weight:700;letter-spacing:-.02em}
  .stat .l{font-size:12px;color:var(--muted);margin-top:2px}
  table{width:100%;border-collapse:collapse;margin:8px 0 4px;font-size:13.5px}
  th,td{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);
    vertical-align:top}
  th{font-size:11px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);
    font-weight:600;border-bottom:1.5px solid var(--line)}
  td.num,th.num{text-align:right;white-space:nowrap}
  code{font-family:var(--mono);font-size:12.5px}
  tr.flap td{background:#fbf3e6}
  ul.notes{padding-left:18px;margin:8px 0}
  ul.notes li{margin:6px 0}
  .callout{background:var(--surface);border-left:3px solid var(--accent);
    border-radius:0 6px 6px 0;padding:12px 16px;margin:14px 0;font-size:13.5px;
    color:var(--muted)}
  .callout strong{color:var(--ink)}
  footer{margin-top:36px;padding-top:12px;border-top:1px solid var(--line);
    color:var(--faint);font-size:12px}
  @media print{body{padding:0;font-size:12px}.stat{break-inside:avoid}tr{break-inside:avoid}}
</style>
</head>
<body>
<header>
  <h1>Roaming Log</h1>
  <div class="sub">Network <strong>${esc(network)}</strong> &middot; ${esc(capturedOn)} &middot; ${esc(countLabel)}</div>
</header>

<div class="meta">
  <div><span class="k">Network (SSID)</span><span class="v">${esc(network)}</span></div>
  <div><span class="k">Captured on</span><span class="v">${esc(capturedOn)}</span></div>
  <div><span class="k">Session window</span><span class="v">${esc(_RoamRow._formatTime(windowStart))} to ${esc(_RoamRow._formatTime(windowEnd))}</span></div>
  <div><span class="k">Session length</span><span class="v">${esc(sessionLen)}</span></div>
  <div><span class="k">Roams recorded</span><span class="v">${events.length}</span></div>
  <div><span class="k">Tool</span><span class="v">WLAN Pros Toolbox &middot; Roaming Log</span></div>
</div>

<h2>Session summary</h2>
<div class="stats">
${tiles.toString()}
</div>

<h2>Roam events</h2>
<table>
<thead>
<tr><th class="num">#</th><th>Time</th><th class="mono">From AP</th><th class="mono">To AP</th><th class="num">Signal (from &rarr; to)</th><th class="num">SNR</th><th class="num">Dwell on prev AP</th></tr>
</thead>
<tbody>
${rowsHtml.toString().trimRight()}
</tbody>
</table>
${glance.toString().trimRight()}
${callout.toString()}
<footer>Generated by the WLAN Pros Toolbox, Roaming Log. Field record, local use.</footer>
</body>
</html>
''';
}

/// One summary stat tile: a big number over a small caption. Values are
/// pre-formatted; the caller omits a tile whose datum is absent (GL-005).
String _statTile(String number, String label) {
  const HtmlEscape esc = HtmlEscape(HtmlEscapeMode.element);
  return '  <div class="stat"><div class="n">${esc.convert(number)}</div>'
      '<div class="l">${esc.convert(label)}</div></div>\n';
}

/// An immediate roam-and-return: the device roamed A to B, then B back to A
/// within [_kPingPongWindow]. [firstIndex] is the index of the A-to-B roam.
class _PingPong {
  const _PingPong({
    required this.firstIndex,
    required this.firstAt,
    required this.secondAt,
    required this.bssidA,
    required this.bssidB,
  });

  final int firstIndex;
  final DateTime firstAt;
  final DateTime secondAt;
  final String bssidA;
  final String bssidB;
}

/// The window within which a roam-and-return counts as a ping-pong.
const Duration _kPingPongWindow = Duration(seconds: 30);

/// Detects immediate roam-and-return pairs: consecutive roams where the second
/// returns to the BSSID the first left, within [_kPingPongWindow]. Precise and
/// conservative — reports only genuine A to B to A flaps, never an inferred one.
List<_PingPong> _detectPingPongs(List<RoamEvent> events) {
  final List<_PingPong> out = <_PingPong>[];
  for (int i = 1; i < events.length; i++) {
    final RoamEvent a = events[i - 1];
    final RoamEvent b = events[i];
    final bool returned = _bssidEq(b.toBssid, a.fromBssid) &&
        _bssidEq(b.fromBssid, a.toBssid);
    if (returned && b.at.difference(a.at) <= _kPingPongWindow) {
      out.add(_PingPong(
        firstIndex: i - 1,
        firstAt: a.at,
        secondAt: b.at,
        bssidA: a.fromBssid,
        bssidB: a.toBssid,
      ));
    }
  }
  return out;
}

/// Case-insensitive, trimmed BSSID equality.
bool _bssidEq(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

/// Builds the "Session at a glance" lines from COMPUTED facts only. Each line is
/// defensible from the events; a pattern that is not present is omitted entirely
/// (GL-005). No interpretation, no health verdict.
List<String> _sessionFacts(
  List<RoamEvent> events,
  List<Duration> dwells,
  List<_PingPong> pingPongs,
) {
  final List<String> facts = <String>[];

  /// The extremes of one RSSI population, carrying the event each came from so
  /// the sentence can timestamp it. [read] selects the reading; an event whose
  /// reading is null is skipped, never zeroed.
  (RoamEvent, RoamEvent)? extremes(int? Function(RoamEvent) read) {
    RoamEvent? strongest;
    RoamEvent? weakest;
    for (final RoamEvent e in events) {
      final int? v = read(e);
      if (v == null) continue;
      if (strongest == null || v > read(strongest)!) strongest = e;
      if (weakest == null || v < read(weakest)!) weakest = e;
    }
    if (strongest == null || weakest == null) return null;
    return (strongest, weakest);
  }

  /// Prefixes a population sentence with its sample size when the population is
  /// incomplete, and leaves the sentence untouched when every roam reported.
  ///
  /// The narrative gets a LEADING clause rather than the parenthetical the
  /// tiles and copy lines use: these sentences already carry two parentheticals
  /// (the strongest/weakest timestamps), and a third turns a readable finding
  /// into a data dump. Leading with the coverage also puts the caveat before
  /// the number it qualifies, which is the order a reader needs it in.
  String scoped(int n, String sentence, String reported) {
    if (n == events.length) return sentence;
    final String lower = sentence[0].toLowerCase() + sentence.substring(1);
    return 'Of ${events.length} roams, $n reported $reported; $lower';
  }

  /// A UNIVERSAL ("they were all the same value") sentence, quantified over the
  /// population that was actually MEASURED.
  ///
  /// A universal cannot borrow the [scoped] wrapper. "Of 40 roams, 3 reported
  /// the signal they landed on; every roam landed on -53 dBm" states a coverage
  /// clause and then contradicts it inside the same sentence: "every roam" is a
  /// claim about 37 measurements that were never taken, in the document a
  /// customer quotes back. The quantifier has to shrink to the population, so
  /// the subject becomes "all 3" — or "the one that did" at n == 1.
  ///
  /// This is NOT an edge case. n == 1 always forces strongest == weakest, so
  /// this branch is the normal path for the sparse captures iOS produces.
  ///
  /// At n == total the plain universal is exactly true and needs no hedge —
  /// note that "every RECORDED roam" is deliberately gone, since on a complete
  /// population "recorded" is a hedge qualifying nothing.
  String universal(int n, String reported, String verb, int dbm) {
    if (n == events.length) return 'Every roam $verb $dbm dBm.';
    final String subject = n == 1 ? 'the one that did' : 'all $n';
    return 'Of ${events.length} roams, $n reported $reported; '
        '$subject $verb $dbm dBm.';
  }

  // The TRIGGER level, computed from the pre-roam readings. "Roams fired at" is
  // trigger language, so it must be computed from the signal on the AP the
  // client was LEAVING. It previously read the post-roam value, which put a
  // trigger label on a destination number.
  final (RoamEvent, RoamEvent)? fired = extremes((RoamEvent e) => e.fromRssiDbm);
  if (fired != null) {
    final (RoamEvent strongest, RoamEvent weakest) = fired;
    final int n = _preRoamRssi(events).length;
    // "1 reported the signal they left" is a number/pronoun mismatch, and n == 1
    // is the common iOS shape, not a corner.
    final String reported = n == 1 ? 'the signal it left' : 'the signal they left';
    if (strongest.fromRssiDbm == weakest.fromRssiDbm) {
      facts.add(universal(n, reported, 'fired at', strongest.fromRssiDbm!));
    } else {
      facts.add(scoped(
        n,
        'Roams fired between ${strongest.fromRssiDbm} dBm (strongest, at '
        '${_RoamRow._formatTime(strongest.at)}) and ${weakest.fromRssiDbm} dBm '
        '(weakest, at ${_RoamRow._formatTime(weakest.at)}).',
        reported,
      ));
    }
  }

  // The DESTINATION level, computed from the post-roam readings and labeled as
  // what the client landed on rather than what made it move.
  final (RoamEvent, RoamEvent)? landed = extremes((RoamEvent e) => e.rssiDbm);
  if (landed != null) {
    final (RoamEvent strongest, RoamEvent weakest) = landed;
    final int n = _postRoamRssi(events).length;
    final String reported =
        n == 1 ? 'the signal it landed on' : 'the signal they landed on';
    if (strongest.rssiDbm == weakest.rssiDbm) {
      facts.add(universal(n, reported, 'landed on', strongest.rssiDbm!));
    } else {
      facts.add(scoped(
        n,
        'Roams landed between ${strongest.rssiDbm} dBm (strongest, at '
        '${_RoamRow._formatTime(strongest.at)}) and ${weakest.rssiDbm} dBm '
        '(weakest, at ${_RoamRow._formatTime(weakest.at)}).',
        reported,
      ));
    }
  }

  // Dwell on the previous AP: min / max / average.
  if (dwells.isNotEmpty) {
    final List<int> secs = dwells.map((Duration d) => d.inSeconds).toList();
    final int lo = secs.reduce((int a, int b) => a < b ? a : b);
    final int hi = secs.reduce((int a, int b) => a > b ? a : b);
    final int avg = (secs.reduce((int a, int b) => a + b) / secs.length).round();
    if (lo == hi) {
      facts.add('Dwell on the previous AP was ${_formatDwell(Duration(seconds: lo))}.');
    } else {
      facts.add(
        'Dwell on the previous AP ranged ${_formatDwell(Duration(seconds: lo))} '
        'to ${_formatDwell(Duration(seconds: hi))}, averaging '
        '${_formatDwell(Duration(seconds: avg))}.',
      );
    }
  }

  // Ping-pong flaps: reported only when precisely detected.
  for (final _PingPong p in pingPongs) {
    facts.add(
      'Ping-pong at ${_RoamRow._formatTime(p.firstAt)} to '
      '${_RoamRow._formatTime(p.secondAt)}: roamed to ${lastOctets(p.bssidB)} '
      'and back to ${lastOctets(p.bssidA)} within '
      '${_formatDwell(p.secondAt.difference(p.firstAt))}.',
    );
  }

  return facts;
}

/// The from/to signal cell for the Share document: the OLD ("from") AP's last
/// RSSI, an arrow, and the NEW ("to") AP's RSSI at the roam, e.g. "-64 dBm ->
/// -56 dBm". The reader sees whether the client left a weakening AP for a
/// stronger one, or roamed sideways. Honest-null: a reading the platform omitted
/// renders "n/a"; both absent collapse to "signal n/a" (GL-005). The arrow is a
/// literal U+2192 (rendered markup, HTML-escape-safe, past the voice guard).
String _htmlSignalFromTo(RoamEvent e) {
  final int? from = e.fromRssiDbm;
  final int? to = e.rssiDbm;
  if (from == null && to == null) return 'signal n/a';
  final String fromStr = from != null ? '$from dBm' : 'n/a';
  final String toStr = to != null ? '$to dBm' : 'n/a';
  return '$fromStr → $toStr';
}

/// One from/to document cell: the FULL BSSID (there is room in a document) as
/// mono code, then the channel-first band descriptor beneath.
String _apCellHtml(
  String bssid,
  int? channel,
  String? band,
  bool derived,
  String Function(String) esc, {
  String? apName,
}) {
  final String bc = bandChannelLabel(channel, band, derived: derived);
  final String code = '<code>${esc(bssid)}</code>';
  final String core = bc.isEmpty ? code : '$code<br>${esc(bc)}';
  // The vendor-advertised name (when present) LEADS the cell in bold, above the
  // full BSSID — matching the on-screen row's name-first layout.
  if (apName != null && apName.trim().isNotEmpty) {
    return '<strong>${esc(apName.trim())}</strong><br>$core';
  }
  return core;
}

/// The band + Wi-Fi-standard descriptor for the current-connection card, e.g.
/// "6 GHz · Wi-Fi 7". A band computed app-side (iOS, [ConnectedAp.bandDerived])
/// carries the app-standard "(derived)" caption so it is never presented as a
/// measured value (GL-005). Omits a null part; returns null when neither the
/// band nor the standard is known, so the row is dropped rather than blanked.
@visibleForTesting
String? currentBandStandard(ConnectedAp ap) {
  final List<String> parts = <String>[];
  final String? band = ap.band?.trim();
  if (band != null && band.isNotEmpty) {
    parts.add(ap.bandDerived ? '$band (derived)' : band);
  }
  final String? standard = ap.standard?.trim();
  if (standard != null && standard.isNotEmpty) parts.add(standard);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The channel + width descriptor, e.g. "ch 69 · 80 MHz". Channel LEADS because
/// it is exact on every platform; the width follows only when the platform can
/// expose it ([ConnectedAp.channelWidthAvailable]) AND this reading carried one,
/// never guessed. The 80+80 MHz sentinel (8080) renders its own unit. Returns
/// null when the channel is unknown, so the row is dropped honestly.
@visibleForTesting
String? currentChannelWidth(ConnectedAp ap) {
  final int? channel = ap.channel;
  if (channel == null) return null;
  final StringBuffer b = StringBuffer('ch $channel');
  if (ap.channelWidthAvailable && ap.channelWidthMhz != null) {
    b.write(ap.channelWidthMhz == 8080 ? ' · 80+80 MHz' : ' · ${ap.channelWidthMhz} MHz');
  }
  return b.toString();
}

/// Formats a Tx rate in Mbps with the unit and no trailing ".0" (mirrors Wi-Fi
/// Information's rate formatter). Returns null when the rate is absent, so the
/// row is dropped rather than showing a fabricated value (GL-005).
@visibleForTesting
String? currentTxRate(double? mbps) {
  if (mbps == null) return null;
  final String n =
      mbps == mbps.roundToDouble() ? mbps.toStringAsFixed(0) : mbps.toStringAsFixed(1);
  return '$n Mbps';
}

/// The "Current connection" header card at the top of the Roaming Log: a compact,
/// honest snapshot of the link the roam watch is reading THIS cycle.
///
/// REUSE, no new data path: it renders the SAME [WifiSignalSampler.latest]
/// [ConnectedAp] that feeds the [RoamDetector] (macOS/Android/Windows CoreWLAN-
/// style poll; iOS companion-Shortcut stream), and rebuilds on the sampler's own
/// [ChangeNotifier] notifications, so it stays current at exactly the roam-watch
/// cadence with no second fetcher. The BSSID tail and name-first layout reuse the
/// SAME [lastOctets] helper and name-leads pattern as the roam rows' [_ApBlock].
///
/// HONESTY (GL-005 / GL-008 / "THE APP BLAMES THE WI-FI"): every field is
/// honest-null — a value the platform omitted is dropped, a derived band/SNR is
/// captioned "(derived)", and the states are kept distinct: "no reading yet"
/// (waiting / iOS not started) is NOT reported as a disconnect; a powered-off
/// radio reads "Wi-Fi is turned off"; only a powered-on reading that carries no
/// link data is the honest "Not connected to Wi-Fi". No RF verdict is printed.
class _CurrentConnectionCard extends StatelessWidget {
  const _CurrentConnectionCard({required this.sampler});

  final WifiSignalSampler sampler;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sampler,
      builder: (BuildContext context, _) {
        final TextTheme text = Theme.of(context).textTheme;
        final AppColorScheme colors = context.colors;
        final ConnectedAp? ap = sampler.latest;

        // Honest state split (GL-005): a present, powered-on reading with real
        // link data is a live connection; everything else is a distinct, honest
        // non-connected state — never a fabricated reading.
        final bool hasReading = ap != null && ap.poweredOn && ap.hasAnyData;

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  'Current connection',
                  style: text.labelMedium?.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (hasReading)
                _ConnectionDetails(ap: ap)
              else
                _Note(message: _emptyMessage(ap)),
            ],
          ),
        );
      },
    );
  }

  /// The honest non-connected copy, kept precise so the app never blames the
  /// Wi-Fi for what is really a waiting or radio-off state (GL-005).
  String _emptyMessage(ConnectedAp? ap) {
    if (ap == null) {
      // No reading has arrived. On iOS the feed waits for the deliberate Start
      // tap, so say that rather than implying a disconnect.
      return sampler.isIos && !sampler.isStreaming
          ? 'Tap Start below to read your current connection.'
          : 'Reading your connection…';
    }
    if (!ap.poweredOn) {
      return 'Wi-Fi is turned off. Turn it on to see your current connection.';
    }
    return 'Not connected to Wi-Fi. Join a network and it appears here.';
  }
}

/// The connected-state detail rows for [_CurrentConnectionCard]. Each RF row is
/// dropped when its value is null, so the card only ever shows measured fields.
class _ConnectionDetails extends StatelessWidget {
  const _ConnectionDetails({required this.ap});

  final ConnectedAp ap;

  @override
  Widget build(BuildContext context) {
    final String? bandStd = currentBandStandard(ap);
    final String? chWidth = currentChannelWidth(ap);
    final String? signal = ap.rssiDbm != null ? '${ap.rssiDbm} dBm' : null;
    final String? snr = ap.snrDb != null
        ? '${ap.snrDb} dB${ap.snrDerived ? ' (derived)' : ''}'
        : null;
    final String? tx = currentTxRate(ap.txRateMbps);
    final String? ssid =
        (ap.ssid != null && ap.ssid!.trim().isNotEmpty) ? ap.ssid!.trim() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FactRow(label: 'Network', value: ssid ?? '—'),
        _FactRow(label: 'Access point', child: _ApValue(apName: ap.apName, bssid: ap.bssid)),
        if (bandStd != null) _FactRow(label: 'Band', value: bandStd),
        if (chWidth != null) _FactRow(label: 'Channel', value: chWidth),
        if (signal != null) _FactRow(label: 'Signal', value: signal),
        if (snr != null) _FactRow(label: 'SNR', value: snr),
        if (tx != null) _FactRow(label: 'Tx rate', value: tx),
      ],
    );
  }
}

/// The access-point value: the vendor-advertised name (when present) LEADS, with
/// the identifying BSSID tail beneath it in mono — the SAME name-first / tail
/// layout the roam rows use ([_ApBlock]), via the SAME [lastOctets] helper. With
/// no name the tail stands alone; with neither it is the neutral "—".
class _ApValue extends StatelessWidget {
  const _ApValue({required this.apName, required this.bssid});

  final String? apName;
  final String? bssid;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool hasName = apName != null && apName!.trim().isNotEmpty;
    final bool hasBssid = bssid != null && bssid!.trim().isNotEmpty;

    if (!hasName && !hasBssid) {
      return Text(
        '—',
        style: text.bodyMedium?.copyWith(color: colors.textPrimary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (hasName)
          Text(
            apName!.trim(),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (hasBssid)
          Text(
            lastOctets(bssid!),
            softWrap: false,
            style: mono.robotoMono.copyWith(
              color: hasName ? colors.textTertiary : colors.textPrimary,
            ),
          ),
      ],
    );
  }
}

/// One compact label/value row for the current-connection card: a fixed-width
/// label column and the value (a plain string, or a [child] for richer content
/// like the AP name/tail block). Left-aligned; the label sits in the tertiary
/// tint, the value in the primary.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, this.value, this.child})
      : assert(value != null || child != null,
            'a _FactRow needs either a value string or a child widget');

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: child ??
                Text(
                  value!,
                  style: text.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

/// The roam-log card: a header with the live/Start control + roam count, then
/// the roam-events list (or an honest empty / not-started state).
class _RoamLogCard extends StatelessWidget {
  const _RoamLogCard({required this.sampler}) : _disabledMessage = null;

  /// The web/unsupported branch never reaches a card, but keep a graceful
  /// non-null fallback so the screen never renders a bare hole.
  const _RoamLogCard._disabled(this._disabledMessage) : sampler = null;

  factory _RoamLogCard.disabled(BuildContext context) =>
      const _RoamLogCard._disabled(
        'Live Wi-Fi monitoring is off on this device.',
      );

  final WifiSignalSampler? sampler;
  final String? _disabledMessage;

  @override
  Widget build(BuildContext context) {
    final WifiSignalSampler? s = sampler;
    if (s == null) {
      return _Card(
        child: Text(
          _disabledMessage ?? 'Unavailable.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: context.colors.textSecondary),
        ),
      );
    }
    return AnimatedBuilder(
      animation: s,
      builder: (BuildContext context, _) {
        final TextTheme text = Theme.of(context).textTheme;
        final AppColorScheme colors = context.colors;
        final List<RoamEvent> events = s.roamEvents;
        final Color liveColor =
            colors.isLight ? colors.textAccent : colors.primary;

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(sampler: s, liveColor: liveColor, roamCount: events.length),
              const SizedBox(height: AppSpacing.sm),
              if (s.isIos && s.triggerError)
                _Note(
                  message:
                      'Could not start the live Wi-Fi feed. The companion '
                      '"WLAN Pros Live" Shortcut may not be installed. Install '
                      'it, then tap Start.',
                )
              else if (s.isIos && !s.isStreaming)
                _Note(
                  message:
                      'Tap Start to begin recording roams from the companion '
                      'Shortcut. Then walk your space with this screen open.',
                )
              else if (events.isEmpty)
                _Note(
                  message:
                      'Watching for roams… none recorded yet. Move around your '
                      'space. A roam is logged each time your device switches '
                      'to a different access point on the same network.',
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = events.length - 1; i >= 0; i--)
                      _RoamRow(
                        event: events[i],
                        index: i + 1,
                      ),
                  ],
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.isIos
                    ? 'Foreground session only on iOS. Roams that happen with '
                        'the app closed or your phone in your pocket are not '
                        'recorded. No app can do that on iOS.'
                    : 'Records roams while this screen is open.',
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Card header: title + roam count, plus the iOS Start/LIVE/Stop control (macOS
/// shows a passive LIVE indicator since it auto-polls).
class _Header extends StatelessWidget {
  const _Header({
    required this.sampler,
    required this.liveColor,
    required this.roamCount,
  });

  final WifiSignalSampler sampler;
  final Color liveColor;
  final int roamCount;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final String countLabel =
        roamCount == 1 ? '1 roam' : '$roamCount roams';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Roams this session',
              style: text.labelMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
        // Roam count badge — always carries the number as a word, never color.
        Text(
          countLabel,
          style: text.labelMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _control(context),
      ],
    );
  }

  Widget _control(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    // iOS, not streaming → Start. iOS, streaming → LIVE + Stop. macOS → LIVE.
    if (sampler.isIos && !sampler.isStreaming) {
      return Semantics(
        button: true,
        // This branch renders ONLY while `!sampler.isStreaming`, so `onPressed:
        // sampler.start` is never null here — the Start control is unconditionally
        // operational whenever it is on screen (it is HIDDEN, not disabled, while
        // recording — the `isStreaming` branch below replaces it with LIVE + Stop).
        // Matching that with `enabled: true` mirrors the sibling Stop button; an
        // UNSET isEnabled would make AT announce this working control as DISABLED
        // (see 68d9b93). `enabled: true` tracks the real `onPressed` null-ness, not
        // a blind assertion.
        enabled: true,
        label: 'Start recording roams',
        child: OutlinedButton.icon(
          onPressed: sampler.start,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start'),
        ),
      );
    }
    if (sampler.isIos && sampler.isStreaming) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _LiveDot(color: liveColor),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'LIVE',
            style: text.labelMedium?.copyWith(
              color: liveColor,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Semantics(
            button: true,
            // Always available while recording; `onPressed: sampler.stop` is
            // never null here. Without this the node leaves isEnabled unset,
            // which AT announces as a DISABLED button (see 68d9b93).
            enabled: true,
            label: 'Stop recording roams',
            child: IconButton(
              icon: const Icon(Icons.stop, size: 20),
              tooltip: 'Stop',
              visualDensity: VisualDensity.compact,
              onPressed: sampler.stop,
            ),
          ),
        ],
      );
    }
    // macOS / Android — passive LIVE indicator (auto-poll, no Start/Stop).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _LiveDot(color: liveColor),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'LIVE',
          style: text.labelMedium?.copyWith(
            color: liveColor,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Builds ONE on-screen roam row in isolation, so a test can assert what a row
/// actually renders without driving a live sampler through a real roam. This is
/// the SAME widget the list builds — not a stand-in — so a test through it
/// exercises the real render path.
@visibleForTesting
Widget buildRoamRowForTest(RoamEvent event, int index) =>
    _RoamRow(event: event, index: index);

/// One roam event: ordinal + timestamp, the from→to BSSID pair, and the signal
/// at the roam. The whole row is one SR node.
class _RoamRow extends StatelessWidget {
  const _RoamRow({required this.event, required this.index});

  final RoamEvent event;
  final int index;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;

    final String time = _formatTime(event.at);
    final String signalLine = _rowSignalLine(event);
    final String spokenSignal = _spokenSignal(event);
    final String network = event.ssid != null && event.ssid!.trim().isNotEmpty
        ? event.ssid!
        : 'Wi-Fi';

    // The a11y label keeps the FULL BSSID (the visible row shows only the
    // identifying last octets) plus the channel-first band for each AP.
    final String fromSpoken = _spokenAp(
      event.fromBssid, event.fromChannel, event.fromBand, event.fromBandDerived,
      apName: event.resolvedFromApName());
    final String toSpoken = _spokenAp(
      event.toBssid, event.toChannel, event.toBand, event.toBandDerived,
      apName: event.resolvedToApName());

    return Semantics(
      container: true,
      label: 'Roam $index on $network at $time, from access point '
          '$fromSpoken to access point $toSpoken, $spokenSignal.',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Time + network + ordinal.
              Row(
                children: <Widget>[
                  Icon(
                    Icons.swap_horiz,
                    size: 16,
                    color: colors.textAccent,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '$time · $network',
                      style: text.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '#$index',
                    style: text.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              // From -> To APs. The identifier is the LAST TWO OCTETS (the OUI is
              // shared across a same-brand deployment; the tail is what tells the
              // radios apart), never truncated. Beneath each: the channel-first
              // band descriptor (channel is exact on every platform; band is the
              // derived companion on iOS).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Flexible(
                    child: _ApBlock(
                      bssid: event.fromBssid,
                      channel: event.fromChannel,
                      band: event.fromBand,
                      bandDerived: event.fromBandDerived,
                      color: colors.textSecondary,
                      apName: event.resolvedFromApName(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                  Flexible(
                    child: _ApBlock(
                      bssid: event.toBssid,
                      channel: event.toChannel,
                      band: event.toBand,
                      bandDerived: event.toBandDerived,
                      color: colors.textPrimary,
                      apName: event.resolvedToApName(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              // Signal on each AP: the old AP's last reading and the new AP's
              // reading at the roam, so the delta is readable at a glance.
              Text(
                signalLine,
                style: text.bodySmall?.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "2:14:07 PM" — 12-hour clock with seconds (roams cluster, so seconds help
  /// distinguish them), no intl dependency.
  static String _formatTime(DateTime at) {
    final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final String minute = at.minute.toString().padLeft(2, '0');
    final String second = at.second.toString().padLeft(2, '0');
    final String meridiem = at.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute:$second $meridiem';
  }
}

/// The on-screen from/to signal line for a roam row: the OLD ("from") AP's last
/// RSSI and the NEW ("to") AP's RSSI at the roam, labeled so it is clear which
/// is the old AP and which is the new, e.g. "Signal on prev AP -64 dBm -> this AP
/// -56 dBm". The reader sees whether the client left a weakening AP for a
/// stronger one, or roamed sideways. SNR (the single reading at the roam) trails.
/// Honest-null: a reading the platform omitted renders "not recorded"; both
/// absent collapse to "Signal at roam: unavailable" (GL-005). The arrow is a
/// literal U+2192, the app-standard transition glyph, past the voice guard.
String _rowSignalLine(RoamEvent e) {
  final int? from = e.fromRssiDbm;
  final int? to = e.rssiDbm;
  final String snr = e.snrDb != null ? ' · SNR ${e.snrDb} dB' : '';
  if (from == null && to == null) return 'Signal at roam: unavailable$snr';
  final String fromStr = from != null ? '$from dBm' : 'not recorded';
  final String toStr = to != null ? '$to dBm' : 'not recorded';
  return 'Signal on prev AP $fromStr → this AP $toStr$snr';
}

/// The spoken (screen-reader) form of the from/to signal: the old AP's last RSSI
/// and the new AP's RSSI, in words so the direction is unambiguous. Honest-null
/// mirrors [_rowSignalLine]. No trailing period (the caller adds one).
String _spokenSignal(RoamEvent e) {
  final int? from = e.fromRssiDbm;
  final int? to = e.rssiDbm;
  final String snr = e.snrDb != null ? ', SNR ${e.snrDb} dB' : '';
  if (from == null && to == null) return 'signal unavailable$snr';
  final String fromStr = from != null ? '$from dBm' : 'not recorded';
  final String toStr = to != null ? '$to dBm' : 'not recorded';
  return 'signal on the previous access point $fromStr, '
      'on this access point $toStr$snr';
}

/// The spoken form of an AP for the row's a11y label: the FULL BSSID (so screen
/// readers announce the whole address, not just the visible tail) plus the
/// channel and band, with the honest "derived" note when the band was computed
/// app-side.
String _spokenAp(String bssid, int? channel, String? band, bool bandDerived,
    {String? apName}) {
  final StringBuffer b = StringBuffer();
  if (apName != null && apName.trim().isNotEmpty) {
    b.write('${apName.trim()}, ');
  }
  b.write(bssid);
  if (channel != null) b.write(' on channel $channel');
  if (band != null && band.trim().isNotEmpty) {
    b.write(', $band band${bandDerived ? ' derived' : ''}');
  }
  return b.toString();
}

/// The on-screen channel-first band descriptor beneath an AP identifier, e.g.
/// "ch 44 · 5 GHz". Channel LEADS (exact on every platform); band is the derived
/// companion on iOS and carries the app-standard "(derived)" caption then. Omits
/// null parts honestly; returns "" when neither is known.
String _rowBandChannel(int? channel, String? band, bool derived) {
  final List<String> parts = <String>[];
  if (channel != null) parts.add('ch $channel');
  if (band != null && band.trim().isNotEmpty) {
    parts.add(derived ? '$band (derived)' : band);
  }
  return parts.join(' · ');
}

/// One AP in a roam row: the identifying last two octets (mono, never
/// truncated), and beneath it the channel-first band descriptor.
class _ApBlock extends StatelessWidget {
  const _ApBlock({
    required this.bssid,
    required this.channel,
    required this.band,
    required this.bandDerived,
    required this.color,
    this.apName,
  });

  final String bssid;
  final int? channel;
  final String? band;
  final bool bandDerived;
  final Color color;

  /// The vendor-advertised AP name, when the beacon carried one (macOS today).
  /// Null renders exactly as before — the BSSID tail alone, no placeholder.
  final String? apName;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String meta = _rowBandChannel(channel, band, bandDerived);
    final bool hasName = apName != null && apName!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // When a name is present it LEADS (prominent), and the BSSID tail drops
        // to a secondary tint beneath it. Honest-null: no name → tail alone,
        // rendered exactly as before.
        if (hasName)
          Text(
            apName!.trim(),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          lastOctets(bssid),
          softWrap: false,
          style: mono.robotoMono.copyWith(
            color: hasName ? colors.textTertiary : color,
          ),
        ),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              meta,
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// The §8.16 "Share document" AppBar action: exports the session as a formatted
/// HTML document to the platform share sheet (Mail attachment / Files / AirDrop).
/// Mirrors [AppCopyAction]'s enabled/disabled contract — [htmlBuilder] returns
/// null when there is no roam to export, and the affordance then renders disabled
/// and drops from focus traversal. Placed AFTER copy per the §8.16 order rule.
class _RoamShareAction extends StatelessWidget {
  const _RoamShareAction({
    required this.htmlBuilder,
    required this.shareFn,
  });

  /// Returns the full HTML document to share, or null when there is nothing to
  /// export yet (→ disabled). Evaluated at tap time to serialize on demand, and
  /// its null-ness is read at build time to resolve the enabled state.
  final String? Function() htmlBuilder;

  /// The share seam. Defaults to the real [shareBytes]; tests inject a fake so
  /// the platform share channel is never touched.
  final RoamShareFn shareFn;

  Future<void> _handleTap(BuildContext context) async {
    final String? html = htmlBuilder();
    if (html == null) return;

    // Anchor the iPad/macOS share popover to this button's rect, or the platform
    // throws (mirrors the PDF-card share path).
    ShareOrigin? origin;
    final RenderObject? box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final Offset topLeft = box.localToGlobal(Offset.zero);
      origin = ShareOrigin(
        topLeft.dx,
        topLeft.dy,
        box.size.width,
        box.size.height,
      );
    }

    await shareFn(
      bytes: utf8.encode(html),
      filename: 'roaming-log.html',
      mimeType: 'text/html',
      title: 'Roaming Log',
      shareOrigin: origin,
    );

    if (context.mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Sharing roaming log',
        TextDirection.ltr,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool enabled = htmlBuilder() != null;
    const String label = 'Share roaming log';

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: enabled ? () => _handleTap(context) : null,
          iconSize: 24,
          tooltip: enabled ? label : null,
          icon: Icon(
            Icons.ios_share,
            size: 24,
            color: enabled ? colors.textSecondary : colors.textDisabled,
          ),
        ),
      ),
    );
  }
}

/// An honest status note inside the card (empty / not-started / failed states).
class _Note extends StatelessWidget {
  const _Note({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Text(
      message,
      style: text.bodyMedium?.copyWith(color: context.colors.textSecondary),
    );
  }
}

/// The "LIVE" dot — lime is the §8.3 active-state accent, resolved by the parent
/// so it stays visible on white (§8.20.2).
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// A surface1 card with the §8.1 hairline border, matching the sibling result
/// cards across the network tools.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: colors.border,
          width: colors.isLight ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
