// Cellular Information — the iOS mobile-network snapshot tool (TICKET-02).
//
// Parallels the Wi-Fi Information tool, but cellular has exactly ONE live
// source (iOS, via the companion Shortcut) and is a ONE-SHOT snapshot — there is
// no live streaming here (that is a separate ticket). The data source is
// selected per platform behind the [CellularInfoSourceResolver] seam, and the
// iOS payload maps into the normalized [CellularInfo] model:
//
//   * iOS   -> companion-Shortcut stack ([CellularInfoBridge]): an
//             Install-Shortcut onboarding flow, then a one-shot read each time
//             the Shortcut runs and bounces the app forward.
//   * macOS -> HONEST UNAVAILABLE state. Macs ship with no cellular radio, so
//             the tool says so plainly via NetworkUnavailableView.
//   * Android / Windows / desktop Linux -> the same honest unavailable state
//             (no cellular bridge built for this iOS-parallel tool).
//   * web -> download-the-app fallback.
//
// There is intentionally NO native CoreTelephony path and NO private signal
// API: CTCarrier is deprecated and returns junk, and raw signal (dBm/RSRP/RSRQ)
// is hard-blocked for apps. Data comes only via the Shortcuts bridge.
//
// HARD RULE — Signal Bars render as bars or "0 to 4" ONLY. They are NEVER
// relabeled dBm, RSRP, or RSRQ. We do not have a raw signal value.
//
// States (SOP-007 section 5):
//   * web -> NetworkUnavailableView (download the app).
//   * unsupported native (macOS et al.) -> explicit "not available on this
//     platform" state, never a silent empty.
//   * loading -> labeled spinner (announced via liveRegion).
//   * empty -> iOS install / how-to onboarding before the first reading.
//   * success -> grouped metric cards (Carrier / Radio / Signal / Network).
//   * disabled -> the iOS Install button is disabled while the link is a
//     placeholder (the cellular Shortcut is published during device testing).
//   * interactive -> Install / Refresh, keyboard- and screen-reader-labeled.
//
// Layout matches wifi_info_screen: SafeArea + LayoutBuilder + centered
// ConstrainedBox + scroll, surface1 cards with a hairline border, the
// concept-graphic band degrades to nothing when the tool has no graphic asset.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../router/shortcut_deep_link_router.dart';
import '../../../services/network/cellular_info.dart';
import '../../../services/network/cellular_info_adapter.dart';
import '../../../services/network/cellular_info_bridge.dart';
import '../../../services/network/cellular_monitor_controller.dart';
import '../../../services/network/cellular_shortcuts_config.dart';
import '../../../services/network/cellular_time_series.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/shortcut_trigger_result.dart';
import '../../../services/network/wifi_live_shortcuts_config.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_toggle.dart';
import '../../../widgets/sparkline.dart';
import '../concept_graphic_band.dart';
import 'get_reading_action.dart';
import 'network_unavailable_view.dart';

/// Honest error line shown when the cellular one-tap trigger returns x-error.
const String _kCellularTriggerError =
    'Could not get a reading. The companion Shortcut may not be installed, or '
    'the run was cancelled. Install it, then try again.';

/// The Cellular Information tool screen.
class CellularInfoScreen extends StatefulWidget {
  const CellularInfoScreen({
    super.key,
    this.sourceOverride,
    this.iosBridge,
  });

  /// Forces a specific data source (tests). Defaults to the host platform.
  final CellularInfoSource? sourceOverride;

  /// Injectable iOS bridge (tests). Defaults to the real Shortcuts bridge.
  final CellularInfoBridge? iosBridge;

  @override
  State<CellularInfoScreen> createState() => _CellularInfoScreenState();
}

/// The iOS data-flow phase for SNAPSHOT mode (one-shot trigger):
/// load -> (needsInstall | hasData). Live mode runs off the
/// [CellularMonitorController] instead of this phase.
enum _IosPhase { loading, needsInstall, hasData }

/// iOS view mode (TICKET-05). Snapshot is the default (one-tap "Get Reading");
/// Live opens the continuous streaming surface fed by the recursive companion
/// Shortcut.
enum CellularInfoMode { snapshot, live }

class _CellularInfoScreenState extends State<CellularInfoScreen>
    with WidgetsBindingObserver {
  late final CellularInfoSource _source;

  // ---- iOS (Shortcuts one-shot) state ----
  CellularInfoBridge? _iosBridge;
  _IosPhase _iosPhase = _IosPhase.loading;
  CellularInfo? _iosInfo;

  // ---- iOS Live mode (TICKET-05) ----
  CellularInfoMode _mode = CellularInfoMode.snapshot;
  CellularMonitorController? _liveController;
  CellularTimeSeries? _series;
  CellularInfo? _lastCharted;
  bool _wasStreaming = false;

  /// Set when the last Live Start could not open the looping Shortcut.
  bool _liveTriggerError = false;

  // ---- One-tap trigger state (TICKET-03) ----
  /// True from the moment "Get Reading" is tapped until the x-callback returns
  /// (the app is backgrounded during the flick to Shortcuts). Suppresses a
  /// second tap and labels the button "Getting reading…".
  bool _triggering = false;

  /// Set when the last trigger returned `x-error` (Shortcut missing / errored /
  /// user cancelled). Cleared on the next successful read or trigger attempt.
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
    _source = widget.sourceOverride ?? CellularInfoSourceResolver.resolve();

    if (_source == CellularInfoSource.iosShortcuts) {
      _iosBridge = widget.iosBridge ?? CellularInfoBridge();
      _liveController = CellularMonitorController(bridge: _iosBridge!);
      _series = CellularTimeSeries();
      _liveController!.addListener(_captureSample);
      WidgetsBinding.instance.addObserver(this);
      _triggerSub = _iosBridge!.triggerResults.listen(_onTriggerResult);
      _loadIos();
    }
  }

  /// Controller listener (iOS Live): appends a bars sample each time a NEW
  /// streamed payload lands while monitoring is running. Guarded so phase-change
  /// notifications do not duplicate the last reading.
  void _captureSample() {
    final CellularMonitorController? c = _liveController;
    final CellularTimeSeries? series = _series;
    if (c == null || series == null) return;

    final bool streaming = c.isStreaming;
    if (streaming && !_wasStreaming) {
      series.clear();
      _lastCharted = null;
    }
    _wasStreaming = streaming;

    if (mounted) setState(() {}); // reflect live indicator / timestamp ticks

    if (!streaming) return;
    final CellularInfo? d = c.info;
    if (d == null || d == _lastCharted) return;
    _lastCharted = d;
    series.add(d);
  }

  void _onModeChanged(CellularInfoMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  /// Live Start (TICKET-05): raise the shared monitoring flag AND fire the
  /// recursive Shortcut once to kick off the stream. The app then passively
  /// consumes the bridge updates; it never loops itself.
  Future<void> _startLive() async {
    final CellularMonitorController? c = _liveController;
    if (c == null) return;
    setState(() => _liveTriggerError = false);
    final bool opened = await c.startMonitoring(
      triggerShortcutName: CellularShortcutsConfig.kCompanionShortcutName,
      triggerTool: 'cellular-info',
    );
    if (!mounted) return;
    if (!opened) {
      await c.stopMonitoring();
      if (!mounted) return;
      setState(() => _liveTriggerError = true);
    }
  }

  /// Live Stop (TICKET-05): clear the shared monitoring flag so the recursive
  /// Shortcut halts on its next check.
  Future<void> _stopLive() async {
    await _liveController?.stopMonitoring();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cold-launch deep-link arg (TICKET-03): when the app was relaunched by a
    // `status=err` x-callback and deep-linked here, the router passes
    // ShortcutTriggerArgs(initialError: true). Read it once so the honest error
    // banner shows on THIS tool screen rather than home. status=ok needs no flag
    // — _loadIos already re-reads the fresh payload.
    if (_consumedDeepLinkArgs ||
        _source != CellularInfoSource.iosShortcuts) {
      return;
    }
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
    // _triggering here covers the path where the user returns to the app
    // WITHOUT an x-callback (e.g. swiped back manually) so the button never
    // sticks on "Getting reading…".
    if (state == AppLifecycleState.resumed &&
        _source == CellularInfoSource.iosShortcuts) {
      if (_triggering && mounted) {
        setState(() => _triggering = false);
      }
      _loadIos();
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
    if (_source == CellularInfoSource.iosShortcuts) {
      WidgetsBinding.instance.removeObserver(this);
      // Hygiene (TICKET-05 point 4): leaving the screen clears the shared
      // monitoring flag so the recursive Shortcut stops on its next check and
      // the Wi-Fi tool is never stranded as "streaming".
      final CellularMonitorController? controller = _liveController;
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

  /// Fires the one-tap trigger: opens the run-shortcut x-callback URL for the
  /// canonical cellular Shortcut name. If iOS cannot open it (Shortcuts missing,
  /// or the Shortcut is not installed so the open fails), fall back to the
  /// honest error + install affordance.
  Future<void> _getReading() async {
    final CellularInfoBridge? bridge = _iosBridge;
    if (bridge == null || _triggering) return;
    setState(() {
      _triggering = true;
      _triggerError = false;
      _deepLinkError = false; // a fresh attempt clears the latched deep-link err
    });
    final bool opened = await bridge.runShortcut(
      CellularShortcutsConfig.kCompanionShortcutName,
      tool: 'cellular-info',
    );
    if (!mounted) return;
    if (!opened) {
      // Could not even reach Shortcuts — show the honest error now (the
      // x-callback will never arrive in this case).
      setState(() {
        _triggering = false;
        _triggerError = true;
      });
    }
  }

  // ---- iOS data flow ----

  /// Reads the latest cellular payload + install state. [manual] is true for the
  /// app-bar Refresh, which shows a brief confirmation so a refresh that returns
  /// identical values is never silent.
  Future<void> _loadIos({bool manual = false}) async {
    final CellularInfoBridge? bridge = _iosBridge;
    if (bridge == null) return;
    if (manual && mounted) {
      setState(() => _iosPhase = _IosPhase.loading);
    }

    final CellularInfo? latest = await bridge.readLatest();
    final bool ever = await bridge.hasEverReceivedPayload();
    if (!mounted) return;

    setState(() {
      if (latest != null && latest.hasAnyData) {
        _iosInfo = latest;
        _iosPhase = _IosPhase.hasData;
        // A fresh reading clears any prior trigger error — EXCEPT a latched
        // cold-launch deep-link error, which must stay visible.
        if (!_deepLinkError) _triggerError = false;
      } else if (ever) {
        // A payload arrived before but carried no data this read — still show
        // whatever we last held, or fall back to the install onboarding.
        _iosPhase = _iosInfo != null ? _IosPhase.hasData : _IosPhase.needsInstall;
      } else {
        _iosPhase = _IosPhase.needsInstall;
      }
    });

    if (manual && mounted && _iosPhase == _IosPhase.hasData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cellular information updated'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openInstallSheet() async {
    final CellularInfoBridge? bridge = _iosBridge;
    if (bridge == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface2,
      builder: (_) => _InstallCellularShortcutSheet(
        bridge: bridge,
        onInstalled: () => _loadIos(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cellular Information'),
        toolbarHeight: 64,
        actions: _appBarActions(),
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  List<Widget> _appBarActions() {
    if (_source != CellularInfoSource.iosShortcuts) return const [];
    final bool hasData = _iosPhase == _IosPhase.hasData;
    return <Widget>[
      // §8.16 order: copy LEADS, then the trailing actions. Copy is disabled
      // (textBuilder -> null) until a reading exists.
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
      if (_iosPhase == _IosPhase.loading)
        const Padding(
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
      else
        Semantics(
          button: true,
          label: 'Refresh cellular information',
          child: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadIos(manual: true),
          ),
        ),
    ];
  }

  /// §8.16 copy payload — the cellular reading as a labeled plain-text block,
  /// mirroring the on-screen metric cards. Returns null (-> disabled affordance)
  /// until a reading exists. Honest blanks: a missing field is "Unavailable".
  String? _buildCopyText() {
    final CellularInfo? info = _iosInfo;
    if (_iosPhase != _IosPhase.hasData || info == null) return null;

    final StringBuffer buf = StringBuffer()
      ..writeln('Cellular Information')
      ..writeln()
      ..writeln('Carrier')
      ..writeln('  Carrier: ${_copyVal(info.carrier)}')
      ..writeln()
      ..writeln('Radio')
      ..writeln('  Radio Technology: ${_copyVal(info.radioTechnology)}')
      ..writeln()
      ..writeln('Signal')
      ..writeln('  Signal Bars: ${_barsCopy(info.signalBars)}')
      ..writeln()
      ..writeln('Network')
      ..writeln('  Country Code: ${_copyVal(info.countryCode)}')
      ..writeln('  Roaming: ${_roamingCopy(info.roaming)}');

    return buf.toString().trimRight();
  }

  static String _copyVal(String? value) {
    if (value == null || value.trim().isEmpty) return 'Unavailable';
    return value;
  }

  /// Signal bars as "N of 4" — never a dBm/RSRP value.
  static String _barsCopy(int? bars) {
    if (bars == null) return 'Unavailable';
    return '$bars of ${CellularInfo.maxSignalBars}';
  }

  static String _roamingCopy(bool? roaming) {
    if (roaming == null) return 'Unavailable';
    return roaming ? 'Yes' : 'No';
  }

  Widget _body() {
    switch (_source) {
      case CellularInfoSource.web:
        return const NetworkUnavailableView(
          toolName: 'Cellular Information',
          reason: NetworkUnavailableReason.web,
        );
      case CellularInfoSource.unsupported:
        // HARD REQUIREMENT: macOS (and every non-iOS native platform) shows an
        // unmistakable "not supported" state, never a silent empty.
        return const NetworkUnavailableView(
          toolName: 'Cellular Information',
          reason: NetworkUnavailableReason.platformApiMissing,
          icon: Icons.signal_cellular_off_outlined,
          headline: 'Cellular is not available here',
          message:
              'Cellular information is not available on this platform. This '
              'tool requires an iPhone with a cellular connection. Macs and '
              'desktops ship with no cellular radio, so there is nothing to '
              'read. The rest of the toolbox works normally here.',
        );
      case CellularInfoSource.iosShortcuts:
        return _iosBody();
    }
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
        if (_mode == CellularInfoMode.live) {
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
              info: _iosInfo!,
              edge: edge,
              isDesktop: isDesktop,
              onGetReading: _triggering ? null : _getReading,
              triggering: _triggering,
              triggerError: _triggerError,
              onOpenInstall: _openInstallSheet,
              mode: _mode,
              onModeChanged: _onModeChanged,
            );
        }
      },
    );
  }
}

// ===========================================================================
// iOS states
// ===========================================================================

/// iOS brief loading state while install-state + latest payload resolve.
class _IosLoadingState extends StatelessWidget {
  const _IosLoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: 'Loading cellular information',
        child: const CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

/// iOS empty state — no payload has ever arrived. "Get Reading" is the primary
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
  final CellularInfoMode mode;
  final ValueChanged<CellularInfoMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          // §4 single sanctioned token: a uniform `--space-lg` pad on the
          // centered empty-state card. Replaces the prior `edge + AppSpacing.md`
          // combination, which summed to an off-grid 40px (mobile) / 48px
          // (desktop) and drifted with the breakpoint.
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeToggle(mode: mode, onChanged: onModeChanged),
              const SizedBox(height: AppSpacing.md),
              const Icon(
                Icons.signal_cellular_alt_outlined,
                size: 48,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No cellular data yet',
                style: text.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tap Get Reading to run the companion Shortcut and fill this '
                "screen with your carrier, radio technology, signal bars, "
                'country code, and roaming status. If you have not installed '
                'the Shortcut yet, install it first.',
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              GetReadingAction(
                onGetReading: onGetReading,
                triggering: triggering,
                triggerError: triggerError,
                errorMessage: _kCellularTriggerError,
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

/// iOS success body: the "Get Reading" trigger + the shared metric cards
/// rendering the [CellularInfo].
class _IosSuccess extends StatelessWidget {
  const _IosSuccess({
    required this.info,
    required this.edge,
    required this.isDesktop,
    required this.onGetReading,
    required this.triggering,
    required this.triggerError,
    required this.onOpenInstall,
    required this.mode,
    required this.onModeChanged,
  });

  final CellularInfo info;
  final double edge;
  final bool isDesktop;
  final VoidCallback? onGetReading;
  final bool triggering;
  final bool triggerError;
  final VoidCallback onOpenInstall;
  final CellularInfoMode mode;
  final ValueChanged<CellularInfoMode> onModeChanged;

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
                errorMessage: _kCellularTriggerError,
                onOpenInstall: onOpenInstall,
              ),
              const SizedBox(height: AppSpacing.sm),
              ConceptGraphicBand(toolId: 'cellular-info', isDesktop: isDesktop),
              if (ToolAssets.hasGraphic('cellular-info'))
                const SizedBox(height: AppSpacing.md),
              _carrierCard(info),
              const SizedBox(height: AppSpacing.sm),
              _radioCard(info),
              const SizedBox(height: AppSpacing.sm),
              _signalCard(info),
              const SizedBox(height: AppSpacing.sm),
              _networkCard(info),
              const SizedBox(height: AppSpacing.sm),
              const _SignalFootnote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carrierCard(CellularInfo info) => _Card(
        title: 'Carrier',
        child: Column(
          children: [_MetricRow(label: 'Carrier', value: info.carrier)],
        ),
      );

  Widget _radioCard(CellularInfo info) => _Card(
        title: 'Radio',
        child: Column(
          children: [
            _MetricRow(label: 'Radio Technology', value: info.radioTechnology),
          ],
        ),
      );

  Widget _signalCard(CellularInfo info) => _Card(
        title: 'Signal',
        child: _SignalBarsRow(bars: info.signalBars),
      );

  Widget _networkCard(CellularInfo info) => _Card(
        title: 'Network',
        child: Column(
          children: [
            _MetricRow(label: 'Country Code', value: info.countryCode),
            _MetricRow(
              label: 'Roaming',
              value: info.roaming == null
                  ? null
                  : (info.roaming! ? 'Yes' : 'No'),
            ),
          ],
        ),
      );
}

// ===========================================================================
// Signal bars — rendered as a 0-to-4 bar meter, NEVER as dBm / RSRP / RSRQ.
// ===========================================================================

/// One metric row whose value is the signal-bar meter. When bars are absent the
/// row renders an honest "Unavailable" (no fake zero-bar meter). The spoken
/// label says "N of 4 bars" — never a dBm reading.
class _SignalBarsRow extends StatelessWidget {
  const _SignalBarsRow({required this.bars});

  final int? bars;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue = bars != null;
    final int value = bars ?? 0;
    final String spoken = hasValue
        ? 'Signal Bars, $value of ${CellularInfo.maxSignalBars} bars'
        : 'Signal Bars, Unavailable';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: spoken,
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                'Signal Bars',
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: hasValue
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _BarMeter(filled: value),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '$value of ${CellularInfo.maxSignalBars}',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Unavailable',
                      textAlign: TextAlign.end,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 4-segment bar meter. Filled segments use the lime active accent; empty
/// segments use the decorative border. Purely a count display — it carries no
/// dBm/RSRP meaning and is excluded from the a11y tree (the parent row speaks
/// "N of 4 bars").
class _BarMeter extends StatelessWidget {
  const _BarMeter({required this.filled});

  /// Width of a single signal-bar segment, in logical pixels. A fixed glyph
  /// metric for the meter shape (not a layout spacing gap, so it is not a §4
  /// spacing token): wide enough to read at a glance, narrow enough that four
  /// segments plus their `--space-xxs` gaps sit compactly beside the "N of 4"
  /// label.
  static const double _barSegmentWidth = 6;

  /// Number of filled bars, 0..[CellularInfo.maxSignalBars].
  final int filled;

  @override
  Widget build(BuildContext context) {
    const double gap = AppSpacing.xxs;
    final int total = CellularInfo.maxSignalBars;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Container(
              width: _barSegmentWidth,
              // Ascending heights so the meter reads as a signal staircase.
              height: 8 + i * 4,
              decoration: BoxDecoration(
                color: i < filled ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Footnote stating plainly that bars are the only signal indicator available
/// and that raw RSRP/RSRQ/dBm is not exposed to apps. Honest labeling (GL-005).
class _SignalFootnote extends StatelessWidget {
  const _SignalFootnote();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        'Signal bars are a coarse 0 to 4 indicator, the same scale as the iOS '
        'status bar. Apple does not expose a raw signal reading (RSRP, RSRQ, or '
        'dBm) to apps, so bars are the only signal value available.',
        style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

// ===========================================================================
// Install sheet
// ===========================================================================

/// Install-the-companion-Shortcut onboarding sheet for the cellular tool.
/// Mirrors the Wi-Fi InstallShortcutSheet; the Install action is disabled while
/// the iCloud link is still a placeholder so the app never opens a dead link.
class _InstallCellularShortcutSheet extends StatelessWidget {
  const _InstallCellularShortcutSheet({
    required this.bridge,
    required this.onInstalled,
  });

  final CellularInfoBridge bridge;
  final Future<void> Function() onInstalled;

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final bool ok =
        await bridge.openUrl(CellularShortcutsConfig.kCompanionShortcutUrl);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the Shortcut link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isPlaceholder = CellularShortcutsConfig.isShortcutUrlPlaceholder;

    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Install the companion Shortcut',
                style: text.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Cellular Information reads your mobile network from a small '
                'Shortcut you install once. After installing, run it to send '
                'your carrier, radio technology, signal bars, country code, and '
                'roaming status to the app.',
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              const _Step(
                number: 1,
                text: 'Tap Install Shortcut to open it in the Shortcuts app, '
                    'then add it.',
              ),
              const _Step(
                number: 2,
                text: 'Run the Shortcut once. Its details appear here.',
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: isPlaceholder ? null : () => _install(context),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Install Shortcut'),
              ),
              if (isPlaceholder) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Install link coming soon.',
                  style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await onInstalled();
                },
                child: const Text("I've installed it, run it"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: AppSpacing.md,
            height: AppSpacing.md,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.surface3,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

// ===========================================================================
// Shared presentation widgets (mirror wifi_info_screen)
// ===========================================================================

/// Reusable card shell (matches wifi_info_screen._Card).
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

/// One label -> value row. A null/empty value renders "Unavailable" in
/// textSecondary (muted but clears WCAG 4.5:1 — never a dash, never a fake
/// value). Each row is a single semantic node so a screen reader speaks
/// "label, value" (or "label, Unavailable") as one unit.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue ? value! : 'Unavailable';
    final Color valueColor =
        hasValue ? AppColors.textPrimary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Semantics(
        container: true,
        label: '$label, $shown',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 3,
              child: Text(
                shown,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(color: valueColor),
              ),
            ),
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
/// mode never starts or stops monitoring.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final CellularInfoMode mode;
  final ValueChanged<CellularInfoMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppToggle<CellularInfoMode>(
      value: mode,
      semanticLabel: 'View mode',
      expand: true,
      items: const <AppToggleItem<CellularInfoMode>>[
        (CellularInfoMode.snapshot, 'Snapshot'),
        (CellularInfoMode.live, 'Live'),
      ],
      onChanged: onChanged,
    );
  }
}

// ===========================================================================
// Live mode (TICKET-05) — continuous streaming surface
// ===========================================================================

/// The Live body: the mode toggle, the Start/Stop monitor bar, and either the
/// start hint, the waiting state, or the live cards. Rebuilds on each streamed
/// payload via an [AnimatedBuilder] over the [CellularMonitorController].
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

  final CellularMonitorController controller;
  final CellularTimeSeries series;
  final CellularInfoMode mode;
  final ValueChanged<CellularInfoMode> onModeChanged;
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
            final CellularInfo? info = controller.info;
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
                  else if (info == null)
                    _WaitingForFirstPayload(streaming: controller.isStreaming)
                  else
                    _LiveCards(info: info, series: series),
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

/// The Live cellular surface: live-updating Carrier / Radio / Network cards,
/// a live Signal-Bars readout, an optional small bars-history sparkline, and the
/// honest signal footnote. Bars stay the coarse 0..4 scale and are never a grade
/// or a dBm value (GL-005). No fabricated grade is shown for cellular.
class _LiveCards extends StatelessWidget {
  const _LiveCards({required this.info, required this.series});

  final CellularInfo info;
  final CellularTimeSeries series;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Card(
          title: 'Carrier',
          child: Column(
            children: [_MetricRow(label: 'Carrier', value: info.carrier)],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Card(
          title: 'Radio',
          child: Column(
            children: [
              _MetricRow(label: 'Radio Technology', value: info.radioTechnology),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Card(
          title: 'Signal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SignalBarsRow(bars: info.signalBars),
              if (series.length >= 2) ...[
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  label: 'Signal bars trend',
                  child: ExcludeSemantics(
                    child: Sparkline(
                      values: series.bars,
                      semanticLabel: 'Signal bars trend',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _Card(
          title: 'Network',
          child: Column(
            children: [
              _MetricRow(label: 'Country Code', value: info.countryCode),
              _MetricRow(
                label: 'Roaming',
                value: info.roaming == null
                    ? null
                    : (info.roaming! ? 'Yes' : 'No'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _SignalFootnote(),
      ],
    );
  }
}

/// Live-mode prompt before streaming and before any sample.
class _LiveStartHint extends StatelessWidget {
  const _LiveStartHint();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        'Press Start to launch the recursive Shortcut. Your carrier, radio '
        'technology, signal bars, country code, and roaming status update here '
        'as each sample arrives.',
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

/// Honest note about the recursive companion Shortcut for Live mode.
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

/// Status block: state icon + "Live"/"Paused" + "Updated HH:MM:SS". One live
/// region keyed only on the state word (Start/Stop announces once, SC 4.1.3);
/// the ticking timestamp is excluded so it does not re-announce every tick.
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

/// Decorative lime "live" dot. Excluded from the a11y tree (the live region +
/// label live on [_StatusBlock]).
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
            ? 'Listening. The recursive Shortcut is sending cellular details.'
            : 'Press Start to begin streaming cellular details.',
        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
