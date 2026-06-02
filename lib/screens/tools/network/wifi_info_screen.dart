// Wi-Fi Information — the one cross-platform connected-AP tool (TICKET-04).
//
// Consolidates the former macOS-only "Wi-Fi Information" and iOS-only "Wi-Fi
// Details" tools into a SINGLE tool (id/route `wifi-info`, name "Wi-Fi
// Information"). The data source is selected per platform behind the
// [WifiInfoSourceResolver] seam, and every source maps into the normalized
// [ConnectedAp] model:
//
//   * macOS -> CoreWLAN snapshot ([MacWifiInfoAdapter]). Pull + Refresh, with the
//             Location-permission states (SSID/BSSID are gated by macOS Location
//             Services). No Shortcut, no trigger on macOS.
//   * iOS   -> companion-Shortcut ONE-SHOT, fired by a one-tap "Get Reading"
//             trigger ([WiFiDetailsBridge.runShortcut], TICKET-03): the app opens
//             the run-shortcut x-callback URL, iOS flicks to Shortcuts, runs the
//             Shortcut (which stores RF metrics to the App Group via
//             [ReceiveWiFiDetailsIntent]), then returns to the app, which
//             re-reads the payload and refreshes. The streaming Live mode is
//             shelved on `feat/wifi-live`. These affordances are iOS-only.
//   * Android / Windows -> honest "coming in a later update" state (clean seam).
//   * web -> download-the-app fallback.
//
// Both native bridges are retained (macOS WifiInfoChannel.swift + iOS
// ToolboxAppIntents/ShortcutsBridge.swift). Per GL-008/GL-005 a field a platform
// cannot expose renders an explicit "Unavailable" row with a precise reason --
// never a fabricated value, never a silent drop.
//
// States (SOP-007 section 5):
//   * web / unsupported native -> NetworkUnavailableView / coming-soon.
//   * loading  -> labeled spinner (announced via liveRegion).
//   * empty    -> iOS: "Get Reading" primary + install / how-to onboarding.
//                macOS: covered by the location card or the error card.
//   * error    -> macOS: in-flow info/error card + retry. iOS: the trigger error
//                banner (Shortcut missing / cancelled) + install fallback.
//   * success  -> grouped metric cards (+ iOS "Get Reading" trigger).
//   * triggering -> iOS: the app is backgrounded during the flick; the button
//                shows a spinner and "Getting reading…", restored on resume.
//   * disabled -> the iOS Install button is disabled while the link is a
//                placeholder; macOS Grant button hides after a grant.
//   * interactive -> Refresh / Grant / Install / Get Reading, all keyboard- and
//                   screen-reader-labeled.
//
// Layout matches interface_info_screen / net_quality_screen: SafeArea +
// LayoutBuilder + centered ConstrainedBox + scroll, surface1 cards with a
// hairline border, mono for addresses/numerics, the concept-graphic band
// degrades to nothing when the tool has no graphic asset.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:net_quality/net_quality.dart' show QualityGrade, QualityGradeLabel;

import '../../../data/tool_assets.dart';
import '../../../router/shortcut_deep_link_router.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/shortcut_trigger_result.dart';
import '../../../services/network/shortcuts_config.dart';
import '../../../services/network/wifi_details.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_grading.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../services/network/wifi_live_shortcuts_config.dart';
import '../../../services/network/wifi_monitor_controller.dart';
import '../../../services/network/wifi_time_series.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/sparkline.dart';
import '../concept_graphic_band.dart';
import 'get_reading_action.dart';
import 'install_shortcut_sheet.dart';
import 'network_unavailable_view.dart';

/// Honest error line shown when the Wi-Fi one-tap trigger returns x-error.
const String _kWifiTriggerError =
    'Could not get a reading. The companion Shortcut may not be installed, or '
    'the run was cancelled. Install it, then try again.';

/// The one Wi-Fi Information tool screen.
class WifiInfoScreen extends StatefulWidget {
  const WifiInfoScreen({
    super.key,
    this.sourceOverride,
    this.macAdapter,
    this.iosBridge,
  });

  /// Forces a specific data source (tests). Defaults to the host platform.
  final WifiInfoSource? sourceOverride;

  /// Injectable macOS adapter (tests). Defaults to the real CoreWLAN adapter.
  final WifiInfoAdapter? macAdapter;

  /// Injectable iOS bridge (tests). Defaults to the real Shortcuts bridge.
  final WiFiDetailsBridge? iosBridge;

  @override
  State<WifiInfoScreen> createState() => _WifiInfoScreenState();
}

/// iOS data-flow phase for SNAPSHOT mode (TICKET-03 one-shot trigger):
/// load -> (needsInstall | hasData). Live mode runs off the
/// [WifiMonitorController] instead of this phase.
enum _IosPhase { loading, needsInstall, hasData }

/// iOS view mode (TICKET-05). Snapshot is the default (one-tap "Get Reading"
/// one-shot); Live opens the continuous streaming + charting + grading surface
/// fed by the recursive companion Shortcut. macOS never shows the toggle.
enum WifiInfoMode { snapshot, live }

class _WifiInfoScreenState extends State<WifiInfoScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;

  // ---- macOS (CoreWLAN snapshot) state ----
  WifiInfoAdapter? _macAdapter;
  bool _macLoading = false;
  ConnectedAp? _macInfo;
  WifiInfoUnavailable? _macError;
  bool _locationGrantAttempted = false;

  // ---- iOS (Shortcuts one-shot) state ----
  WiFiDetailsBridge? _iosBridge;
  _IosPhase _iosPhase = _IosPhase.loading;
  WiFiDetails? _iosDetails;

  // ---- iOS Live mode (TICKET-05) ----
  /// iOS view mode. Snapshot leads; Live opens the streaming surface.
  WifiInfoMode _mode = WifiInfoMode.snapshot;

  /// Live monitoring state machine, built lazily on the iOS path. Owns the
  /// stream subscription, the monitoring flag, and the recursion kickoff.
  WifiMonitorController? _liveController;

  /// Rolling window of streamed RF fields for the Live sparklines + grading.
  WifiTimeSeries? _series;

  /// The last details object folded into [_series], so the listener appends one
  /// sample per NEW payload (the controller notifies on phase changes too).
  WiFiDetails? _lastCharted;

  /// Whether the controller was streaming on the previous notification, so a
  /// Stop->Start transition clears the window (a new session does not chart the
  /// previous one's stale samples).
  bool _wasStreaming = false;

  /// Set when the last Live Start could not open the looping Shortcut (Shortcuts
  /// missing / not installed). Surfaced as the honest error in the Live bar.
  bool _liveTriggerError = false;

  // ---- One-tap trigger state (TICKET-03) ----
  /// True from the moment "Get Reading" is tapped until the x-callback returns
  /// (the app is backgrounded during the flick to Shortcuts).
  bool _triggering = false;

  /// Set when the last trigger returned x-error (Shortcut missing / cancelled).
  bool _triggerError = false;

  StreamSubscription<ShortcutTriggerResult>? _triggerSub;

  /// Guards the one-time read of the deep-link route argument (TICKET-03 cold
  /// launch): a `status=err` return that cold-launched the app into this screen
  /// must surface the error banner here, not on home.
  bool _consumedDeepLinkArgs = false;

  /// Latched true when the app was cold-launched into this screen by a
  /// `status=err` deep link. Keeps the honest error banner visible through the
  /// initState `_loadIos` (which clears `_triggerError` on any reading it finds),
  /// until the user's next Get Reading attempt resolves it.
  bool _deepLinkError = false;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? WifiInfoSourceResolver.resolve();

    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        _macAdapter = widget.macAdapter ?? MacWifiInfoAdapter();
        _fetchMac();
      case WifiInfoSource.iosShortcuts:
        _iosBridge = widget.iosBridge ?? WiFiDetailsBridge();
        _liveController = WifiMonitorController(bridge: _iosBridge!);
        _series = WifiTimeSeries();
        _liveController!.addListener(_captureSample);
        WidgetsBinding.instance.addObserver(this);
        _triggerSub = _iosBridge!.triggerResults.listen(_onTriggerResult);
        _loadIos();
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cold-launch deep-link arg (TICKET-03): when the app was relaunched by a
    // `status=err` x-callback and deep-linked here, the router passes
    // ShortcutTriggerArgs(initialError: true). Read it once so the honest error
    // banner shows on THIS tool screen rather than home. status=ok needs no flag
    // — _loadIos already re-reads the fresh payload.
    if (_consumedDeepLinkArgs || _source != WifiInfoSource.iosShortcuts) return;
    final Object? args = ModalRoute.of(context)?.settings.arguments;
    if (args is ShortcutTriggerArgs) {
      _consumedDeepLinkArgs = true;
      if (args.initialError && mounted) {
        // Latches the error so the initState _loadIos (which clears _triggerError
        // on any reading it finds) cannot stomp it before the banner shows.
        _deepLinkError = true;
        setState(() => _triggerError = true);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS only: the Shortcut bounces the app to the foreground; on resume,
    // re-read so a payload delivered while backgrounded lands. Clearing
    // _triggering here covers a manual return (no x-callback) so the button
    // never sticks on "Getting reading…".
    if (state == AppLifecycleState.resumed &&
        _source == WifiInfoSource.iosShortcuts) {
      if (_triggering && mounted) {
        setState(() => _triggering = false);
      }
      _loadIos();
      // Live mode: re-resolve so a payload delivered while backgrounded lands
      // and any persisted monitoring flag resumes the live state.
      _liveController?.load();
    }
  }

  /// Handles the x-callback return from a one-tap trigger (TICKET-03). On
  /// success it re-reads the App Group payload directly (belt-and-suspenders
  /// with the lifecycle-resume re-read, so the refresh does not depend solely on
  /// the OS delivering a resume event). On error it keeps the install affordance
  /// as the fallback and surfaces an honest message.
  void _onTriggerResult(ShortcutTriggerResult result) {
    if (!mounted) return;
    setState(() {
      _triggering = false;
      _triggerError = result == ShortcutTriggerResult.error;
      // A live trigger result supersedes any latched cold-launch deep-link err.
      _deepLinkError = result == ShortcutTriggerResult.error;
    });
    if (result == ShortcutTriggerResult.success) {
      _loadIos();
    }
  }

  @override
  void dispose() {
    if (_source == WifiInfoSource.iosShortcuts) {
      WidgetsBinding.instance.removeObserver(this);
      // Hygiene (TICKET-05 point 4): leaving the screen clears the monitoring
      // flag so the recursive Shortcut stops on its next check and the other
      // tool is never stranded as "streaming".
      final WifiMonitorController? controller = _liveController;
      // Detach the listener FIRST so the stopMonitoring() notify below does not
      // re-enter _captureSample's setState on a defunct element.
      controller?.removeListener(_captureSample);
      if (controller != null && controller.isStreaming) {
        controller.stopMonitoring();
      }
      controller?.dispose();
    }
    _triggerSub?.cancel();
    super.dispose();
  }

  /// Controller listener (iOS Live): appends a sample to [_series] each time a
  /// NEW streamed payload lands while monitoring is running. Guarded so the
  /// many non-sample notifications (phase changes, Start/Stop) do not duplicate
  /// the last reading into the window.
  void _captureSample() {
    final WifiMonitorController? c = _liveController;
    final WifiTimeSeries? series = _series;
    if (c == null || series == null) return;

    final bool streaming = c.isStreaming;
    // Fresh Stop->Start: drop the previous session's window.
    if (streaming && !_wasStreaming) {
      series.clear();
      _lastCharted = null;
    }
    _wasStreaming = streaming;

    if (mounted) setState(() {}); // reflect live indicator / timestamp ticks

    if (!streaming) return;
    final WiFiDetails? d = c.details;
    if (d == null || d == _lastCharted) return;
    _lastCharted = d;
    series.add(ConnectedAp.fromWifiDetails(d));
  }

  void _onModeChanged(WifiInfoMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  /// Live Start (TICKET-05): raise the monitoring flag AND fire the recursive
  /// Shortcut once to kick off the stream. The app then passively consumes the
  /// bridge updates; it never loops itself.
  Future<void> _startLive() async {
    final WifiMonitorController? c = _liveController;
    if (c == null) return;
    setState(() => _liveTriggerError = false);
    final bool opened = await c.startMonitoring(
      triggerShortcutName: ShortcutsConfig.kCompanionShortcutName,
      triggerTool: 'wifi-info',
    );
    if (!mounted) return;
    if (!opened) {
      // Could not open the Shortcut: stop monitoring (clear the flag) and show
      // the honest error rather than leaving a flag set with no producer.
      await c.stopMonitoring();
      if (!mounted) return;
      setState(() => _liveTriggerError = true);
    }
  }

  /// Live Stop (TICKET-05): clear the monitoring flag so the recursive
  /// Shortcut halts on its next `ShouldContinueMonitoringIntent` check.
  Future<void> _stopLive() async {
    await _liveController?.stopMonitoring();
    if (mounted) setState(() {});
  }

  // ---- iOS data flow ----

  /// Reads the latest Wi-Fi payload + install state. Re-entrant: callable from
  /// the "I've installed it, run it" retry and from app-resume (the Shortcut
  /// bounces the app to the foreground).
  Future<void> _loadIos() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;

    final WiFiDetails? latest = await bridge.readLatest();
    final bool ever = await bridge.hasEverReceivedPayload();
    if (!mounted) return;

    setState(() {
      if (latest != null && latest.hasAnyData) {
        _iosDetails = latest;
        _iosPhase = _IosPhase.hasData;
        // A fresh reading clears any prior error — EXCEPT a latched cold-launch
        // deep-link error, which must stay visible (the err callback may carry a
        // stale payload that is not a successful new reading).
        if (!_deepLinkError) _triggerError = false;
      } else if (ever || _iosDetails != null) {
        _iosPhase =
            _iosDetails != null ? _IosPhase.hasData : _IosPhase.needsInstall;
      } else {
        _iosPhase = _IosPhase.needsInstall;
      }
    });
  }

  /// Fires the one-tap trigger: opens the run-shortcut x-callback URL for the
  /// canonical Wi-Fi Shortcut name. If iOS cannot open it, fall back to the
  /// honest error + install affordance.
  Future<void> _getReading() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null || _triggering) return;
    setState(() {
      _triggering = true;
      _triggerError = false;
      _deepLinkError = false; // a fresh attempt clears the latched deep-link err
    });
    final bool opened = await bridge.runShortcut(
      ShortcutsConfig.kCompanionShortcutName,
      tool: 'wifi-info',
    );
    if (!mounted) return;
    if (!opened) {
      setState(() {
        _triggering = false;
        _triggerError = true;
      });
    }
  }

  // ---- macOS data flow ----

  /// Reads a fresh macOS snapshot. [manual] is true for the app-bar Refresh,
  /// which shows a brief confirmation so a refresh that returns identical values
  /// is never silent.
  ///
  /// WCAG 4.1.3 -- the loading state is announced by the liveRegion on
  /// [_LoadingCard]; no imperative announce here (the first read fires from
  /// initState and would race teardown).
  Future<void> _fetchMac({bool manual = false}) async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    setState(() {
      _macLoading = true;
      _macError = null;
    });
    try {
      final ConnectedAp info = await adapter.fetch();
      if (!mounted) return;
      setState(() {
        _macInfo = info;
        _macLoading = false;
      });
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wi-Fi information updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on WifiInfoUnavailable catch (e) {
      if (!mounted) return;
      setState(() {
        _macError = e;
        _macLoading = false;
      });
    } catch (e) {
      // Defensive: never sit on a spinner forever.
      if (!mounted) return;
      setState(() {
        _macError = WifiInfoUnavailable(
          WifiInfoUnavailableReason.channelError,
          e.toString(),
        );
        _macLoading = false;
      });
    }
  }

  /// macOS: requests Location authorization, then re-reads regardless of result.
  Future<void> _grantLocation() async {
    final WifiInfoAdapter? adapter = _macAdapter;
    if (adapter == null) return;
    await adapter.requestNamePermission();
    if (!mounted) return;
    _locationGrantAttempted = true;
    await _fetchMac();
  }

  // ---- iOS install flow ----

  Future<void> _openInstallSheet() async {
    final WiFiDetailsBridge? bridge = _iosBridge;
    if (bridge == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface2,
      builder: (_) =>
          InstallShortcutSheet(bridge: bridge, onInstalled: _loadIos),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Information'),
        toolbarHeight: 64,
        actions: _appBarActions(),
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  List<Widget> _appBarActions() {
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        // §8.16 order: copy LEADS, the Refresh action trails. Copy is disabled
        // until a snapshot has resolved (textBuilder → null while loading or on
        // error with no info), enabled once link details exist.
        return [
          AppCopyAction(textBuilder: _buildCopyText),
          _macLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                )
              : Semantics(
                  button: true,
                  label: 'Refresh Wi-Fi information',
                  child: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: () => _fetchMac(manual: true),
                  ),
                ),
        ];
      case WifiInfoSource.iosShortcuts:
        // §8.16 order: copy LEADS, help (How-to) trails. Copy is disabled
        // (textBuilder → null) until a reading exists; the help icon appears
        // only once there is data to be about.
        final bool hasData = _iosPhase == _IosPhase.hasData;
        return <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          if (hasData)
            Semantics(
              button: true,
              label: 'How to install the Shortcut',
              child: IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'How to install the Shortcut',
                onPressed: _openInstallSheet,
              ),
            ),
        ];
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return const [];
    }
  }

  /// The connected-AP link currently shown, regardless of platform source:
  /// the macOS CoreWLAN snapshot, or the latest iOS streamed/one-shot payload.
  /// Null when nothing is on screen yet.
  ConnectedAp? _currentAp() {
    switch (_source) {
      case WifiInfoSource.macosCoreWlan:
        return _macInfo;
      case WifiInfoSource.iosShortcuts:
        return _iosDetails == null
            ? null
            : ConnectedAp.fromWifiDetails(_iosDetails!);
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return null;
    }
  }

  /// §8.16 copy payload — the connected-AP link as a labeled plain-text block,
  /// mirroring the on-screen metric cards (Network / Signal / Rate / Channel /
  /// Radio / Status). Returns null (→ disabled affordance) until link details
  /// exist. On iOS this copies whatever the live stream currently shows; a tap
  /// re-serializes on demand, so a later sample copies its newer values.
  ///
  /// Honesty (GL-005): a field the platform cannot expose is written as
  /// "Unavailable", and the two per-platform reasons the cards surface
  /// (Rx rate, Channel width) travel as an explicit "Not reported on this
  /// platform" note — never a blank, never a fabricated value.
  String? _buildCopyText() {
    final ConnectedAp? info = _currentAp();
    if (info == null) return null;

    final String platformLabel = _source == WifiInfoSource.iosShortcuts
        ? 'iOS'
        : 'macOS CoreWLAN';
    final StringBuffer buf = StringBuffer()..writeln('Wi-Fi Information');

    buf
      ..writeln()
      ..writeln('Network')
      ..writeln('  SSID: ${_copyVal(info.ssid, null)}')
      ..writeln('  BSSID: ${_copyVal(info.bssid, null)}');

    buf
      ..writeln()
      ..writeln('Signal')
      ..writeln('  RSSI: ${_copyVal(info.rssiDbm?.toString(), 'dBm')}')
      ..writeln('  Noise: ${_copyVal(info.noiseDbm?.toString(), 'dBm')}')
      ..writeln(
        '  SNR: ${_copyVal(info.snrDb?.toString(), 'dB')}'
        '${info.snrDerived ? ' (derived)' : ''}',
      );

    buf
      ..writeln()
      ..writeln('Rate')
      ..writeln('  Tx Rate: ${_copyVal(_formatRate(info.txRateMbps), 'Mbps')}')
      ..writeln(
        '  Rx Rate: ${info.rxRateAvailable ? _copyVal(_formatRate(info.rxRateMbps), 'Mbps') : 'Not exposed by $platformLabel'}',
      );

    final bool isPsc = _isPscChannel(info.channel, info.band);
    buf
      ..writeln()
      ..writeln('Channel')
      ..writeln(
        '  Channel: ${_copyVal(info.channel?.toString(), null)}'
        '${isPsc ? ' (Preferred Scanning Channel)' : ''}',
      )
      ..writeln(
        '  Width: ${info.channelWidthAvailable ? _copyVal(info.channelWidthMhz?.toString(), 'MHz') : 'Not reported by $platformLabel'}',
      )
      ..writeln(
        '  Band: ${_copyVal(info.band, null)}'
        '${info.bandDerived ? ' (derived)' : ''}',
      );

    buf
      ..writeln()
      ..writeln('Radio')
      ..writeln('  Wi-Fi Standard: ${_copyVal(info.standard, null)}')
      ..writeln('  Country: ${_copyVal(info.countryCode, null)}')
      ..writeln('  Interface: ${_copyVal(info.interfaceName, null)}')
      ..writeln('  Hardware Address: ${_copyVal(info.hardwareAddress, null)}');

    buf
      ..writeln()
      ..writeln('Status')
      ..writeln('  Wi-Fi Power: ${info.poweredOn ? 'On' : 'Off'}');

    return buf.toString().trimRight();
  }

  /// Clipboard analog of `_MetricRow`: "value unit", or "Unavailable" when the
  /// value is missing (GL-005 honest blanks).
  static String _copyVal(String? value, String? unit) {
    if (value == null || value.trim().isEmpty) return 'Unavailable';
    return unit == null ? value : '$value $unit';
  }

  Widget _body() {
    switch (_source) {
      case WifiInfoSource.web:
        return const NetworkUnavailableView(
          toolName: 'Wi-Fi Information',
          reason: NetworkUnavailableReason.web,
        );
      case WifiInfoSource.unsupported:
        return const _PlatformComingSoon();
      case WifiInfoSource.macosCoreWlan:
        return _macBody();
      case WifiInfoSource.iosShortcuts:
        return _iosBody();
    }
  }

  // ---- macOS body ----

  Widget _macBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
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
                children: _macContent(isDesktop),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _macContent(bool isDesktop) {
    final List<Widget> children = <Widget>[
      ConceptGraphicBand(toolId: 'wifi-info', isDesktop: isDesktop),
      if (ToolAssets.hasGraphic('wifi-info'))
        const SizedBox(height: AppSpacing.md),
    ];

    if (_macLoading && _macInfo == null && _macError == null) {
      children.add(const _LoadingCard());
      return children;
    }

    if (_macError != null && _macInfo == null) {
      children.add(
        _ErrorCard(error: _macError!, onRetry: _macLoading ? null : _fetchMac),
      );
      return children;
    }

    final ConnectedAp? info = _macInfo;
    if (info == null) {
      children.add(
        _ErrorCard(error: null, onRetry: _macLoading ? null : _fetchMac),
      );
      return children;
    }

    if (!info.poweredOn) {
      children
        ..add(const _WifiOffCard())
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    final Widget? locationCard = _buildLocationCard(info);
    if (locationCard != null) {
      children
        ..add(locationCard)
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    if (_macError != null) {
      children
        ..add(
          _ErrorCard(
            error: _macError!,
            onRetry: _macLoading ? null : _fetchMac,
          ),
        )
        ..add(const SizedBox(height: AppSpacing.sm));
    }

    children.addAll(_metricCards(info, platformLabel: 'macOS CoreWLAN'));
    return children;
  }

  /// macOS location card (three states). Returns null when no card is needed.
  Widget? _buildLocationCard(ConnectedAp info) {
    final bool nameMissing = info.ssid == null && info.bssid == null;
    if (info.ssid != null) return null;

    if (info.ssid == null && _locationGrantAttempted) {
      return const _LocationCard(
        message:
            'Permission granted. macOS may need an app relaunch before the '
            'network name appears. The signal and channel details below are '
            'unaffected.',
        onGrant: null,
      );
    }

    if (nameMissing) {
      return _LocationCard(
        message:
            'Network name needs Location permission. macOS requires Location '
            'Services authorization to read the SSID and BSSID. The signal '
            'and channel details below do not need it.',
        onGrant: _macLoading ? null : _grantLocation,
      );
    }

    return null;
  }

  // ---- iOS body ----

  Widget _iosBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        // Live mode: the continuous streaming surface, driven by the controller.
        if (_mode == WifiInfoMode.live) {
          return _LiveBody(
            controller: _liveController!,
            series: _series!,
            mode: _mode,
            onModeChanged: _onModeChanged,
            edge: edge,
            triggerError: _liveTriggerError,
            onStart: _startLive,
            onStop: _stopLive,
          );
        }

        // Snapshot mode (one-shot trigger).
        switch (_iosPhase) {
          case _IosPhase.loading:
            return const _IosLoadingState();
          case _IosPhase.needsInstall:
            return _EmptyInstallState(
              onGetReading: _triggering ? null : _getReading,
              onInstall: _openInstallSheet,
              triggering: _triggering,
              triggerError: _triggerError,
              mode: _mode,
              onModeChanged: _onModeChanged,
            );
          case _IosPhase.hasData:
            return _IosSuccess(
              ap: ConnectedAp.fromWifiDetails(_iosDetails!),
              edge: edge,
              isDesktop: isDesktop,
              onGetReading: _triggering ? null : _getReading,
              triggering: _triggering,
              triggerError: _triggerError,
              onOpenInstall: _openInstallSheet,
              mode: _mode,
              onModeChanged: _onModeChanged,
              metricCards: (ConnectedAp ap) =>
                  _metricCards(ap, platformLabel: 'iOS'),
            );
        }
      },
    );
  }

  // ---- Shared metric cards (render the normalized model) ----

  /// Builds the grouped metric cards from the normalized [ConnectedAp]. Used by
  /// BOTH platform bodies so the data presentation is identical regardless of
  /// source; only the per-field availability reasons differ ([platformLabel]).
  List<Widget> _metricCards(ConnectedAp info, {required String platformLabel}) {
    return <Widget>[
      _networkCard(info),
      const SizedBox(height: AppSpacing.sm),
      _signalCard(info),
      const SizedBox(height: AppSpacing.sm),
      _rateCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _channelCard(info, platformLabel),
      const SizedBox(height: AppSpacing.sm),
      _radioCard(info),
      const SizedBox(height: AppSpacing.sm),
      _statusCard(info),
    ];
  }

  Widget _networkCard(ConnectedAp info) => _Card(
    title: 'Network',
    child: Column(
      children: [
        _MetricRow(label: 'SSID', value: info.ssid),
        _MetricRow(label: 'BSSID', value: info.bssid, mono: true),
      ],
    ),
  );

  Widget _signalCard(ConnectedAp info) => _Card(
    title: 'Signal',
    child: Column(
      children: [
        _MetricRow(
          label: 'RSSI',
          value: info.rssiDbm?.toString(),
          unit: 'dBm',
          mono: true,
        ),
        _MetricRow(
          label: 'Noise',
          value: info.noiseDbm?.toString(),
          unit: 'dBm',
          mono: true,
        ),
        _MetricRow(
          label: 'SNR',
          value: info.snrDb?.toString(),
          unit: 'dB',
          mono: true,
          derived: info.snrDerived,
        ),
      ],
    ),
  );

  Widget _rateCard(ConnectedAp info, String platformLabel) => _Card(
    title: 'Rate',
    child: Column(
      children: [
        _MetricRow(
          label: 'Tx Rate',
          value: _formatRate(info.txRateMbps),
          unit: 'Mbps',
          mono: true,
        ),
        _MetricRow(
          label: 'Rx Rate',
          value: _formatRate(info.rxRateMbps),
          unit: 'Mbps',
          mono: true,
          // When the platform never exposes Rx rate, say so precisely
          // instead of a generic "Unavailable".
          note: info.rxRateAvailable ? null : 'Not exposed by $platformLabel',
        ),
      ],
    ),
  );

  Widget _channelCard(ConnectedAp info, String platformLabel) {
    final bool isPsc = _isPscChannel(info.channel, info.band);
    return _Card(
      title: 'Channel',
      child: Column(
        children: [
          _MetricRow(
            label: 'Channel',
            value: info.channel?.toString(),
            mono: true,
            marker: isPsc ? '*' : null,
            note: isPsc ? 'Preferred Scanning Channel (PSC)' : null,
          ),
          _MetricRow(
            label: 'Width',
            value: info.channelWidthMhz?.toString(),
            unit: 'MHz',
            mono: true,
            note: info.channelWidthAvailable
                ? null
                : 'Not reported by $platformLabel',
          ),
          _MetricRow(
            label: 'Band',
            value: info.band,
            derived: info.bandDerived,
          ),
        ],
      ),
    );
  }

  Widget _radioCard(ConnectedAp info) => _Card(
    title: 'Radio',
    child: Column(
      children: [
        _MetricRow(label: 'Wi-Fi Standard', value: info.standard),
        _MetricRow(label: 'Country', value: info.countryCode),
        _MetricRow(label: 'Interface', value: info.interfaceName, mono: true),
        _MetricRow(
          label: 'Hardware Address',
          value: info.hardwareAddress,
          mono: true,
        ),
      ],
    ),
  );

  Widget _statusCard(ConnectedAp info) => _Card(
    title: 'Status',
    child: Column(
      children: [
        _MetricRow(label: 'Wi-Fi Power', value: info.poweredOn ? 'On' : 'Off'),
      ],
    ),
  );

  /// Whether [channel] is a 6 GHz Preferred Scanning Channel (PSC). PSC channels
  /// are 5, 21, 37, ... 229 -- (ch - 5) a multiple of 16 across 6 GHz. False for
  /// 2.4 and 5 GHz.
  static bool _isPscChannel(int? channel, String? band) {
    if (channel == null || band != '6 GHz') return false;
    if (channel < 5 || channel > 233) return false;
    return (channel - 5) % 16 == 0;
  }

  /// Formats a Mbps rate without a trailing ".0", or null so the row renders
  /// "Unavailable".
  static String? _formatRate(double? mbps) {
    if (mbps == null) return null;
    if (mbps == mbps.roundToDouble()) return mbps.toStringAsFixed(0);
    return mbps.toStringAsFixed(1);
  }
}

// ===========================================================================
// Shared presentation widgets
// ===========================================================================

/// Honest per-platform state for Android / Windows / desktop Linux (adapters are
/// later tickets).
class _PlatformComingSoon extends StatelessWidget {
  const _PlatformComingSoon();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_find_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Coming in a later update',
                style: text.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The native Wi-Fi data path for this platform is coming in a '
                "later update. On macOS, Wi-Fi Information reads the link "
                'directly through CoreWLAN; on iOS, it reads the connected '
                "access point's RF metrics through a companion Shortcut.",
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS loading card (before the first snapshot resolves).
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

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
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Reading Wi-Fi link state…',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS brief loading state while install-state + latest payload resolve.
class _IosLoadingState extends StatelessWidget {
  const _IosLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading Wi-Fi information',
        child: const CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

/// iOS empty state -- no payload has ever arrived. "Get Reading" is the primary
/// action (one tap fires the companion Shortcut); installing the Shortcut is the
/// secondary affordance for the first run / the fallback when it is missing.
class _EmptyInstallState extends StatelessWidget {
  const _EmptyInstallState({
    required this.onGetReading,
    required this.onInstall,
    required this.triggering,
    required this.triggerError,
    required this.mode,
    required this.onModeChanged,
  });

  final VoidCallback? onGetReading;
  final VoidCallback onInstall;
  final bool triggering;
  final bool triggerError;
  final WifiInfoMode mode;
  final ValueChanged<WifiInfoMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeToggle(mode: mode, onChanged: onModeChanged),
              const SizedBox(height: AppSpacing.md),
              const Icon(
                Icons.wifi_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No Wi-Fi data yet',
                style: text.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tap Get Reading to run the companion Shortcut and fill this '
                "screen with the connected access point's RF metrics. If you "
                'have not installed the Shortcut yet, install it first.',
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              GetReadingAction(
                onGetReading: onGetReading,
                triggering: triggering,
                triggerError: triggerError,
                errorMessage: _kWifiTriggerError,
                onOpenInstall: onInstall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Semantics(
                button: true,
                label: 'Install Shortcut',
                child: OutlinedButton.icon(
                  onPressed: onInstall,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Install Shortcut'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS success body: the Snapshot/Live mode toggle, the "Get Reading" trigger,
/// and the shared metric cards.
class _IosSuccess extends StatelessWidget {
  const _IosSuccess({
    required this.ap,
    required this.edge,
    required this.isDesktop,
    required this.onGetReading,
    required this.triggering,
    required this.triggerError,
    required this.onOpenInstall,
    required this.mode,
    required this.onModeChanged,
    required this.metricCards,
  });

  final ConnectedAp ap;
  final double edge;
  final bool isDesktop;
  final VoidCallback? onGetReading;
  final bool triggering;
  final bool triggerError;
  final VoidCallback onOpenInstall;
  final WifiInfoMode mode;
  final ValueChanged<WifiInfoMode> onModeChanged;
  final List<Widget> Function(ConnectedAp ap) metricCards;

  @override
  Widget build(BuildContext context) {
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
              _ModeToggle(mode: mode, onChanged: onModeChanged),
              const SizedBox(height: AppSpacing.sm),
              GetReadingAction(
                onGetReading: onGetReading,
                triggering: triggering,
                triggerError: triggerError,
                errorMessage: _kWifiTriggerError,
                onOpenInstall: onOpenInstall,
              ),
              const SizedBox(height: AppSpacing.sm),
              ConceptGraphicBand(toolId: 'wifi-info', isDesktop: isDesktop),
              if (ToolAssets.hasGraphic('wifi-info'))
                const SizedBox(height: AppSpacing.md),
              ...metricCards(ap),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- macOS location card ----

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.message, required this.onGrant});

  final String message;

  /// When null, the card is informational (post-grant) and hides the Grant
  /// button to avoid an endless re-tap loop.
  final VoidCallback? onGrant;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (onGrant != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Grant Location permission',
                child: FilledButton(
                  onPressed: onGrant,
                  child: const Text('Grant Location permission'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- macOS Wi-Fi off card ----

class _WifiOffCard extends StatelessWidget {
  const _WifiOffCard();

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Wi-Fi is off',
                  style: text.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Turn Wi-Fi on to read live link details. Any values still '
                  'reported by the system are shown below.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
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

// ---- macOS error card ----

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final WifiInfoUnavailable? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? detail = error?.detail;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Wi-Fi reading available',
                      style: text.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail != null && detail.trim().isNotEmpty
                          ? detail
                          : 'The system did not return a Wi-Fi snapshot. '
                                'There may be no active Wi-Fi interface.',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Retry reading Wi-Fi information',
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

// ---- Reusable card shell (matches interface_info_screen._Card) ----

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

// ---- Single metric row ----
//
// One label -> value row. A null/empty value renders "Unavailable" in
// textSecondary (muted but clears WCAG 4.5:1 -- never textTertiary for value
// text, never a dash, never a fake 0). Live values render in textPrimary. Each
// row is a single semantic node so a screen reader speaks "label, value" (or
// "label, Unavailable", with any honesty note appended) as one unit.

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    this.mono = false,
    this.note,
    this.unit,
    this.marker,
    this.derived = false,
  });

  final String label;
  final String? value;
  final bool mono;

  /// Optional note under the value. For an Unavailable value it explains why
  /// (e.g. "Not exposed by macOS CoreWLAN"); for a present value it is a
  /// footnote tied to [marker] (e.g. the PSC explanation).
  final String? note;

  /// Unit appended to the value (e.g. "dBm"), tied to the number so it scans as
  /// "-50 dBm". Omitted when unavailable.
  final String? unit;

  /// Optional marker glyph (e.g. "*") appended to the value and prefixing
  /// [note]. Shown only for a present value; excluded from the spoken value.
  final String? marker;

  /// Appends a quiet "derived" caption -- the value is app-computed (e.g. SNR or
  /// Band on the iOS path), not source-reported. Honest labeling.
  final bool derived;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue
        ? (unit == null ? value! : '${value!} $unit')
        : 'Unavailable';
    final String displayValue = (hasValue && marker != null)
        ? '$shown $marker'
        : shown;
    final bool showNote = note != null;
    final String footnote = note == null
        ? ''
        : (marker != null ? '$marker $note' : note!);

    final String labelSpoken = derived ? '$label, derived' : label;
    final String semanticLabel = showNote
        ? '$labelSpoken, $shown, $note'
        : '$labelSpoken, $shown';

    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color valueColor = hasValue
        ? AppColors.textPrimary
        : AppColors.textSecondary;
    final TextStyle? valueStyle = (mono && hasValue)
        ? monoText.robotoMono.copyWith(color: valueColor)
        : text.bodyMedium?.copyWith(color: valueColor);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (derived)
                        Text(
                          'derived',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                            letterSpacing: 0.4,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.end,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
            if (showNote) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                footnote,
                textAlign: TextAlign.end,
                style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Snapshot / Live mode toggle (TICKET-05) — §8.14.1 segmented selector
// ===========================================================================

/// The Snapshot/Live segmented toggle. Snapshot leads (the default); switching
/// mode never starts or stops monitoring — that is the Start/Stop control's job.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final WifiInfoMode mode;
  final ValueChanged<WifiInfoMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppToggle<WifiInfoMode>(
      value: mode,
      semanticLabel: 'View mode',
      expand: true,
      items: const <AppToggleItem<WifiInfoMode>>[
        (WifiInfoMode.snapshot, 'Snapshot'),
        (WifiInfoMode.live, 'Live'),
      ],
      onChanged: onChanged,
    );
  }
}

// ===========================================================================
// Live mode (TICKET-05) — continuous streaming surface
// ===========================================================================

/// The Live body: the mode toggle, the Start/Stop monitor bar, and either the
/// start hint, the waiting state, or the live charts. Rebuilds on each streamed
/// payload via an [AnimatedBuilder] over the [WifiMonitorController].
class _LiveBody extends StatelessWidget {
  const _LiveBody({
    required this.controller,
    required this.series,
    required this.mode,
    required this.onModeChanged,
    required this.edge,
    required this.triggerError,
    required this.onStart,
    required this.onStop,
  });

  final WifiMonitorController controller;
  final WifiTimeSeries series;
  final WifiInfoMode mode;
  final ValueChanged<WifiInfoMode> onModeChanged;
  final double edge;
  final bool triggerError;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final ConnectedAp? ap = controller.details == null
                ? null
                : ConnectedAp.fromWifiDetails(controller.details!);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ModeToggle(mode: mode, onChanged: onModeChanged),
                  const SizedBox(height: AppSpacing.sm),
                  _MonitorControlBar(
                    streaming: controller.isStreaming,
                    lastUpdated: controller.lastUpdated,
                    onStart: onStart,
                    onStop: onStop,
                  ),
                  if (triggerError) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const _LiveTriggerErrorCard(),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  if (!controller.isStreaming && series.isEmpty)
                    const _LiveStartHint()
                  else if (series.isEmpty)
                    _WaitingForFirstPayload(streaming: controller.isStreaming)
                  else
                    _LiveCharts(series: series, latest: ap),
                  const SizedBox(height: AppSpacing.sm),
                  const _LoopShortcutNote(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Live-mode prompt before any sample has been captured and monitoring is not
/// running.
class _LiveStartHint extends StatelessWidget {
  const _LiveStartHint();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        'Press Start to launch the recursive Shortcut. Each sample charts here '
        'and the signal dimensions are graded as they arrive.',
        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Honest error card when Live Start could not open the looping Shortcut.
class _LiveTriggerErrorCard extends StatelessWidget {
  const _LiveTriggerErrorCard();

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 20, color: AppColors.statusDanger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Could not start live streaming. The looping companion Shortcut '
                'may not be installed, or the run was cancelled. Install it, '
                'then press Start again.',
                style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Live charting + grading surface. RSSI and SNR each carry a graded chip +
/// sparkline; Tx and Rx rate each carry a trend label + sparkline (rates are
/// NOT hard-graded — a "good" rate is relative to band/width/MCS, so the value +
/// direction is the honest signal). Congestion / CCA is intentionally absent —
/// iOS does not expose channel utilization and we do not fabricate it (GL-005).
class _LiveCharts extends StatelessWidget {
  const _LiveCharts({required this.series, required this.latest});

  final WifiTimeSeries series;

  /// The latest connected-AP reading, for the current-value readout. May be
  /// null briefly between Start and the first streamed payload.
  final ConnectedAp? latest;

  @override
  Widget build(BuildContext context) {
    final int? rssi = latest?.rssiDbm;
    final int? snr = latest?.snrDb;
    final double? tx = latest?.txRateMbps;
    final double? rx = latest?.rxRateMbps;
    final bool rxAvail = latest?.rxRateAvailable ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _GradedMetricChart(
          label: 'RSSI',
          unit: 'dBm',
          currentValue: rssi?.toString(),
          grade: WifiGrading.gradeRssi(rssi),
          window: series.rssi,
        ),
        const SizedBox(height: AppSpacing.sm),
        _GradedMetricChart(
          label: 'SNR',
          unit: 'dB',
          currentValue: snr?.toString(),
          grade: WifiGrading.gradeSnr(snr),
          window: series.snr,
          derived: latest?.snrDerived ?? false,
        ),
        const SizedBox(height: AppSpacing.sm),
        _TrendMetricChart(
          label: 'Tx Rate',
          unit: 'Mbps',
          currentValue: _WifiInfoScreenState._formatRate(tx),
          trend: WifiGrading.rateTrend(series.txRate),
          window: series.txRate,
        ),
        const SizedBox(height: AppSpacing.sm),
        _TrendMetricChart(
          label: 'Rx Rate',
          unit: 'Mbps',
          currentValue:
              rxAvail ? _WifiInfoScreenState._formatRate(rx) : null,
          trend: rxAvail
              ? WifiGrading.rateTrend(series.rxRate)
              : WifiRateTrend.unavailable,
          window: series.rxRate,
          unavailableNote: (latest != null && !rxAvail)
              ? 'Not exposed by iOS'
              : null,
        ),
      ],
    );
  }
}

/// A hard-graded dimension card: label, current value, grade chip, and a
/// sparkline tinted to the grade. The grade WORD carries the meaning; the tint
/// only reinforces it (SC 1.4.1). A null current value renders "Unavailable"
/// and the grade is [QualityGrade.unavailable].
class _GradedMetricChart extends StatelessWidget {
  const _GradedMetricChart({
    required this.label,
    required this.unit,
    required this.currentValue,
    required this.grade,
    required this.window,
    this.derived = false,
  });

  final String label;
  final String unit;
  final String? currentValue;
  final QualityGrade grade;
  final List<double?> window;
  final bool derived;

  @override
  Widget build(BuildContext context) {
    final bool hasValue =
        currentValue != null && currentValue!.trim().isNotEmpty;
    final String shown = hasValue ? '$currentValue $unit' : 'Unavailable';
    final String semantic =
        '$label${derived ? ', derived' : ''}, $shown, ${grade.label}';
    final Color lineColor = _gradeLineColor(grade);

    return _Card(
      title: label,
      child: Semantics(
        container: true,
        label: semantic,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: _CurrentReadout(value: shown, hasValue: hasValue),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _GradeChip(grade: grade),
                ],
              ),
              if (derived) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'derived',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Sparkline(
                values: window,
                lineColor: lineColor,
                semanticLabel: '$label trend',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tints the sparkline to match the grade chip (reinforcement only). The
  /// unavailable case stays neutral tertiary so it does not read as a verdict.
  static Color _gradeLineColor(QualityGrade grade) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return AppColors.statusSuccess;
      case QualityGrade.fair:
        return AppColors.statusWarning;
      case QualityGrade.poor:
        return AppColors.statusDanger;
      case QualityGrade.unavailable:
        return AppColors.textTertiary;
    }
  }
}

/// A trend dimension card (rates): label, current value, trend label, and a
/// lime sparkline. Rates are not hard-graded, so the line stays the §8.3 lime
/// accent (no verdict tint) and the trend word is the signal. When the platform
/// does not expose the rate, an honest [unavailableNote] explains why.
class _TrendMetricChart extends StatelessWidget {
  const _TrendMetricChart({
    required this.label,
    required this.unit,
    required this.currentValue,
    required this.trend,
    required this.window,
    this.unavailableNote,
  });

  final String label;
  final String unit;
  final String? currentValue;
  final WifiRateTrend trend;
  final List<double?> window;
  final String? unavailableNote;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue =
        currentValue != null && currentValue!.trim().isNotEmpty;
    final String shown = hasValue ? '$currentValue $unit' : 'Unavailable';
    final String semantic = unavailableNote != null
        ? '$label, $shown, $unavailableNote'
        : '$label, $shown, trend ${trend.label}';

    return _Card(
      title: label,
      child: Semantics(
        container: true,
        label: semantic,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: _CurrentReadout(value: shown, hasValue: hasValue),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _TrendBadge(trend: trend),
                ],
              ),
              if (unavailableNote != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  unavailableNote!,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Sparkline(
                values: window,
                semanticLabel: '$label trend',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large mono current-value readout for a Live chart card.
class _CurrentReadout extends StatelessWidget {
  const _CurrentReadout({required this.value, required this.hasValue});

  final String value;
  final bool hasValue;

  @override
  Widget build(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final TextTheme text = Theme.of(context).textTheme;
    return hasValue
        ? Text(
            value,
            style: mono.outputMedium.copyWith(color: AppColors.textPrimary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Text(
            value,
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          );
  }
}

/// The §8.13 grade chip, matching net_quality_screen / wifi_vs_internet_screen
/// so every graded surface reads identically. The grade WORD carries the
/// meaning; the color only reinforces it (SC 1.4.1).
class _GradeChip extends StatelessWidget {
  const _GradeChip({required this.grade});

  final QualityGrade grade;

  static (Color, Color) _colors(QualityGrade grade) {
    switch (grade) {
      case QualityGrade.excellent:
      case QualityGrade.good:
        return (AppColors.statusSuccess, AppColors.secondary);
      case QualityGrade.fair:
        return (AppColors.statusWarning, AppColors.secondary);
      case QualityGrade.poor:
        return (AppColors.statusDanger, AppColors.secondary);
      case QualityGrade.unavailable:
        return (AppColors.surface2, AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final (Color bg, Color fg) = _colors(grade);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: grade == QualityGrade.unavailable
            ? Border.all(color: AppColors.borderStrong, width: 1)
            : null,
      ),
      child: Text(
        grade.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Trend badge for the rate cards: an arrow glyph + the trend word, on a quiet
/// surface2 chip with a borderStrong outline. Rates are not verdicts, so the
/// badge does NOT use a status color — the word + arrow carry the direction.
class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});

  final WifiRateTrend trend;

  IconData get _icon {
    switch (trend) {
      case WifiRateTrend.rising:
        return Icons.trending_up;
      case WifiRateTrend.falling:
        return Icons.trending_down;
      case WifiRateTrend.steady:
        return Icons.trending_flat;
      case WifiRateTrend.unavailable:
        return Icons.remove;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            trend.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest note about the recursive companion Shortcut for Live mode. While the
/// looping Shortcut link is still a placeholder (pre-publish), the affordance to
/// get it is a plain disabled note rather than a tappable link the app could not
/// open — mirroring how the cellular tool gated its Install action.
class _LoopShortcutNote extends StatelessWidget {
  const _LoopShortcutNote();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool placeholder =
        WifiLiveShortcutsConfig.isLoopShortcutUrlPlaceholder;
    final String message = placeholder
        ? 'Live streaming needs the recursive companion Shortcut, which is '
              'published during device testing. The single-shot Shortcut used by '
              'Snapshot does not stream.'
        : 'Live streaming uses the recursive companion Shortcut. Install it, '
              'then press Start.';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// iOS Start/Stop control + live indicator + last-updated timestamp.
class _MonitorControlBar extends StatelessWidget {
  const _MonitorControlBar({
    required this.streaming,
    required this.lastUpdated,
    required this.onStart,
    required this.onStop,
  });

  final bool streaming;
  final DateTime? lastUpdated;
  final VoidCallback onStart;
  final VoidCallback onStop;

  static String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Below this width the status and action stack vertically (reflow, not clip)
  /// so the bar survives 320px at 200% type. GL-003 §8.9.
  static const double _reflowThreshold = 280;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool narrow = constraints.maxWidth < _reflowThreshold;
          final Widget status = _StatusBlock(
            streaming: streaming,
            lastUpdated: lastUpdated,
          );
          final Widget action = _ActionButton(
            streaming: streaming,
            onStart: onStart,
            onStop: onStop,
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: AppSpacing.xs),
              action,
            ],
          );
        },
      ),
    );
  }
}

/// Status block: state icon + "Live"/"Paused" + "Updated HH:MM:SS". The block
/// is one live region keyed only on the "Live"/"Paused" state word, so a Start
/// or Stop transition announces once (WCAG 2.2 SC 4.1.3). The "Updated" stamp
/// ticks ~1×/s while streaming, so it is wrapped in [ExcludeSemantics] to avoid
/// re-announcing the whole line every tick.
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.streaming, required this.lastUpdated});

  final bool streaming;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String label = streaming ? 'Live' : 'Paused';

    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (streaming)
            const _LiveIndicator()
          else
            const Icon(
              Icons.pause_circle_outline,
              size: 20,
              color: AppColors.textTertiary,
            ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.labelLarge?.copyWith(
                    color: streaming
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                if (lastUpdated != null)
                  ExcludeSemantics(
                    child: Text(
                      'Updated ${_MonitorControlBar._formatTimestamp(lastUpdated!)}',
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.streaming,
    required this.onStart,
    required this.onStop,
  });

  final bool streaming;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return streaming
        ? Semantics(
            button: true,
            label: 'Stop live monitoring',
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          )
        : Semantics(
            button: true,
            label: 'Start live monitoring',
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            ),
          );
  }
}

/// Decorative lime "live" dot. The live region + changing label live on
/// [_StatusBlock]; this dot is excluded from the a11y tree. Lime is the §8.3
/// active-state accent, not a verdict.
class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _WaitingForFirstPayload extends StatelessWidget {
  const _WaitingForFirstPayload({required this.streaming});

  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        streaming
            ? 'Listening. The recursive Shortcut is sending Wi-Fi details.'
            : 'Press Start to begin streaming Wi-Fi details.',
        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
