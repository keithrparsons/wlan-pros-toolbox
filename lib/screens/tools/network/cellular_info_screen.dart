// Cellular Information — the iOS mobile-network tool (LIVE streaming only).
//
// Parallels the Wi-Fi Information tool. On iOS, cellular has exactly ONE mode:
// LIVE streaming, fed by the combined "WLAN Pros Live" companion Shortcut. There
// is no separate one-tap snapshot — Stop freezes the last values on screen (the
// snapshot). The data source is selected per platform behind the
// [CellularInfoSourceResolver] seam, and the iOS payload maps into the
// normalized [CellularInfo] model:
//
//   * iOS   -> LIVE streaming via [CellularMonitorController] over the shared
//             companion-Shortcut bridge ([CellularInfoBridge]). Start raises the
//             shared monitoring flag and fires the PLAIN, fire-and-forget
//             run-shortcut trigger once; the app then passively consumes the
//             cellular side of the combined Live stream.
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
// relabeled dBm, RSRP, or RSRQ. We do not have a raw signal value. Cellular is
// NEVER graded (no fabricated grade).
//
// States (SOP-007 section 5):
//   * web -> NetworkUnavailableView (download the app).
//   * unsupported native (macOS et al.) -> explicit "not available on this
//     platform" state, never a silent empty.
//   * idle -> a clean "Tap Start to begin live readings" state.
//   * streaming -> live-updating cards (Carrier / Radio / Signal / Network).
//   * error -> the Live trigger error banner (Shortcut missing / cancelled).
//   * interactive -> Start / Stop, keyboard- and screen-reader-labeled.
//
// Layout matches wifi_info_screen: SafeArea + LayoutBuilder + centered
// ConstrainedBox + scroll, surface1 cards with a hairline border, the
// concept-graphic band degrades to nothing when the tool has no graphic asset.

import 'package:flutter/material.dart';

import '../../../services/network/cellular_info.dart';
import '../../../services/network/cellular_info_adapter.dart';
import '../../../services/network/cellular_info_bridge.dart';
import '../../../services/network/cellular_monitor_controller.dart';
import '../../../services/network/cellular_time_series.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_live_shortcuts_config.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/sparkline.dart';
import '../../../widgets/tool_help_footer.dart';
import 'network_unavailable_view.dart';

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

class _CellularInfoScreenState extends State<CellularInfoScreen>
    with WidgetsBindingObserver {
  late final CellularInfoSource _source;

  // ---- iOS (Live streaming) state ----
  CellularInfoBridge? _iosBridge;
  CellularMonitorController? _liveController;
  CellularTimeSeries? _series;
  CellularInfo? _lastCharted;
  bool _wasStreaming = false;

  /// Set when the last Live Start could not open the Live Shortcut.
  bool _liveTriggerError = false;

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
      _liveController!.load();
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

  /// Live Start: raise the shared monitoring flag AND fire the recursive
  /// Shortcut once to kick off the stream. The app then passively consumes the
  /// bridge updates; it never loops itself.
  Future<void> _startLive() async {
    final CellularMonitorController? c = _liveController;
    if (c == null) return;
    setState(() => _liveTriggerError = false);
    final bool opened = await c.startMonitoring(
      triggerShortcutName: WifiLiveShortcutsConfig.kLiveShortcutName,
    );
    if (!mounted) return;
    if (!opened) {
      // Could not open the Shortcut. Surface the honest error immediately, then
      // clear the shared monitoring flag (the recursion never started, so there
      // is no producer). Showing the error first means the banner does not wait
      // on the stop cleanup completing.
      setState(() => _liveTriggerError = true);
      await c.stopMonitoring();
    }
  }

  /// Live Stop: clear the shared monitoring flag so the recursive Shortcut halts
  /// on its next check. The last values stay frozen on screen (the snapshot).
  Future<void> _stopLive() async {
    await _liveController?.stopMonitoring();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS only: on resume, re-resolve so a payload delivered while backgrounded
    // lands and any persisted monitoring flag resumes the live state.
    if (state == AppLifecycleState.resumed &&
        _source == CellularInfoSource.iosShortcuts) {
      _liveController?.load();
    }
  }

  @override
  void dispose() {
    if (_source == CellularInfoSource.iosShortcuts) {
      WidgetsBinding.instance.removeObserver(this);
      // Hygiene: leaving the screen clears the shared monitoring flag so the
      // recursive Shortcut stops on its next check and the Wi-Fi tool is never
      // stranded as "streaming".
      final CellularMonitorController? controller = _liveController;
      // Detach the listener FIRST so the stopMonitoring() notify below does not
      // re-enter _captureSample's setState on a defunct element.
      controller?.removeListener(_captureSample);
      if (controller != null && controller.isStreaming) {
        controller.stopMonitoring();
      }
      controller?.dispose();
    }
    super.dispose();
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
    // Copy only makes sense on iOS where live readings exist; it is the only
    // AppBar action now (§8.16). The per-tool help moved to the footer
    // (ToolHelpFooter, §8.16.1) at the end of the live body.
    if (_source != CellularInfoSource.iosShortcuts) {
      return const <Widget>[];
    }
    return <Widget>[
      AppCopyAction(textBuilder: _buildCopyText),
    ];
  }

  /// §8.16 copy payload — the cellular reading as a labeled plain-text block,
  /// mirroring the on-screen metric cards. Returns null (-> disabled affordance)
  /// until a live reading exists. Honest blanks: a missing field is
  /// "Unavailable". Stop freezes the last values, which remain copyable.
  String? _buildCopyText() {
    final CellularInfo? info = _liveController?.info;
    if (info == null || !info.hasAnyData) return null;

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

  // ---- iOS body (Live streaming only) ----

  Widget _iosBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        return _LiveBody(
          controller: _liveController!,
          series: _series!,
          edge: edge,
          triggerError: _liveTriggerError,
          onStart: _startLive,
          onStop: _stopLive,
        );
      },
    );
  }
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
    final AppColorScheme colors = context.colors;
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
                  color: colors.textSecondary,
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
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      'Unavailable',
                      textAlign: TextAlign.end,
                      style: text.bodyMedium?.copyWith(
                        color: colors.textSecondary,
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
    final AppColorScheme colors = context.colors;
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
                // Filled segments: lime in dark; darkened-lime in light so the
                // thin meter bars read on the white surface (§8.20.2).
                color: i < filled
                    ? (colors.isLight ? colors.textAccent : colors.primary)
                    : colors.border,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        'Signal bars are a coarse 0 to 4 indicator, the same scale as the iOS '
        'status bar. Apple does not expose a raw signal reading (RSRP, RSRQ, or '
        'dBm) to apps, so bars are the only signal value available.',
        style: text.bodySmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}


// ===========================================================================
// Shared presentation widgets (mirror wifi_info_screen)
// ===========================================================================

/// Reusable card shell (matches wifi_info_screen._Card).
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
    this.verticalPadding = AppSpacing.sm,
  });

  final String title;
  final Widget child;

  /// Top/bottom inset for the card. Defaults to `sm` (16px). The Live cards
  /// pass a tighter `xs` (8px) so the per-metric Live stack fits a phone screen
  /// without the bottom card clipping; horizontal inset stays `sm` so content
  /// edges still align.
  final double verticalPadding;

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
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: verticalPadding,
      ),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool hasValue = value != null && value!.trim().isNotEmpty;
    final String shown = hasValue ? value! : 'Unavailable';
    final Color valueColor =
        hasValue ? colors.textPrimary : colors.textSecondary;

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
                  color: colors.textSecondary,
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
// iOS Live mode — continuous streaming surface (the only iOS mode)
// ===========================================================================

/// The Live body: the Start/Stop monitor bar, and either the idle start hint,
/// the waiting state, or the live cards. Rebuilds on each streamed payload via
/// an [AnimatedBuilder] over the [CellularMonitorController]. Stop freezes the
/// last values on screen (the snapshot); there is no separate snapshot mode.
class _LiveBody extends StatelessWidget {
  const _LiveBody({
    required this.controller,
    required this.series,
    required this.edge,
    required this.triggerError,
    required this.onStart,
    required this.onStop,
  });

  final CellularMonitorController controller;
  final CellularTimeSeries series;
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
                  // First-time SETUP hint only. Once the app has EVER received a
                  // Live payload (hasEverReceived — mirrors the App Group
                  // shortcuts_bridge.has_received_payload flag), the user clearly
                  // has the companion Shortcut working, so the install/how-to note
                  // is noise and is hidden permanently.
                  if (!controller.hasEverReceived) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const _LoopShortcutNote(),
                  ],
                  // §8.16.1 — per-tool help at the end of the scroll body.
                  const ToolHelpFooter(toolId: 'cellular-info'),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Live sparkline chart height. A denser glyph metric than the [Sparkline]
/// default (40) so the Live card stack fits a phone screen without the bottom
/// card clipping; still tall enough to read the trend. Live-mode only.
const double _liveSparklineHeight = 32;

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
          verticalPadding: AppSpacing.xs,
          child: Column(
            children: [_MetricRow(label: 'Carrier', value: info.carrier)],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Card(
          title: 'Radio',
          verticalPadding: AppSpacing.xs,
          child: Column(
            children: [
              _MetricRow(label: 'Radio Technology', value: info.radioTechnology),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Card(
          title: 'Signal',
          verticalPadding: AppSpacing.xs,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SignalBarsRow(bars: info.signalBars),
              if (series.length >= 2) ...[
                const SizedBox(height: AppSpacing.xxs),
                Semantics(
                  label: 'Signal bars trend',
                  child: ExcludeSemantics(
                    child: Sparkline(
                      values: series.bars,
                      semanticLabel: 'Signal bars trend',
                      height: _liveSparklineHeight,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _Card(
          title: 'Network',
          verticalPadding: AppSpacing.xs,
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
        const SizedBox(height: AppSpacing.xs),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        'Tap Start to begin live readings. Your carrier, radio technology, '
        'signal bars, country code, and roaming status update here as each '
        'sample arrives. Stop freezes the last values on screen.',
        style: text.bodyLarge?.copyWith(color: colors.textSecondary),
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
          Icon(Icons.error_outline, size: 20, color: colors.statusDanger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Could not start live streaming. The looping companion Shortcut '
                'may not be installed, or the run was cancelled. Install it, '
                'then press Start again.',
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final bool placeholder =
        WifiLiveShortcutsConfig.isLiveShortcutUrlPlaceholder;
    final String message = placeholder
        ? 'Live streaming needs the combined "WLAN Pros Live" companion '
              'Shortcut, which is published during device testing.'
        : 'Live streaming uses the combined "WLAN Pros Live" companion '
              'Shortcut. Install it, then tap Start.';
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
          Icon(Icons.info_outline, size: 20, color: colors.textTertiary),
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
    final AppColorScheme colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
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
    final AppColorScheme colors = context.colors;
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
            Icon(
              Icons.pause_circle_outline,
              size: 20,
              color: colors.textTertiary,
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
                        ? colors.textAccent
                        : colors.textSecondary,
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
    final AppColorScheme colors = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: colors.textAccent,
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Text(
        streaming
            ? 'Listening. The recursive Shortcut is sending cellular details.'
            : 'Press Start to begin streaming cellular details.',
        style: text.bodyLarge?.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
