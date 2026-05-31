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
//             Services). No streaming on macOS.
//   * iOS   -> companion-Shortcut stack ([WiFiDetailsBridge] +
//             [WifiMonitorController]): an Install-Shortcut onboarding flow, a
//             one-shot run, and Start/Stop LIVE streaming. These affordances are
//             iOS-only and never appear on macOS.
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
//   * empty    -> iOS: install / how-to onboarding. macOS: covered by the
//                location card or the error card.
//   * error    -> in-flow info/error card with the channel detail + retry (macOS).
//   * success  -> grouped metric cards (+ iOS monitoring control bar).
//   * disabled -> the iOS Install button is disabled while the link is a
//                placeholder; macOS Grant button hides after a grant.
//   * interactive -> Refresh / Grant / Install / Start / Stop, all keyboard- and
//                   screen-reader-labeled.
//
// Layout matches interface_info_screen / net_quality_screen: SafeArea +
// LayoutBuilder + centered ConstrainedBox + scroll, surface1 cards with a
// hairline border, mono for addresses/numerics, the concept-graphic band
// degrades to nothing when the tool has no graphic asset.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/connected_ap.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/wifi_details_bridge.dart';
import '../../../services/network/wifi_info_adapter.dart';
import '../../../services/network/wifi_info_service.dart';
import '../../../services/network/wifi_monitor_controller.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import 'install_shortcut_sheet.dart';
import 'network_unavailable_view.dart';

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

class _WifiInfoScreenState extends State<WifiInfoScreen>
    with WidgetsBindingObserver {
  late final WifiInfoSource _source;

  // ---- macOS (CoreWLAN snapshot) state ----
  WifiInfoAdapter? _macAdapter;
  bool _macLoading = false;
  ConnectedAp? _macInfo;
  WifiInfoUnavailable? _macError;
  bool _locationGrantAttempted = false;

  // ---- iOS (Shortcuts streaming) state ----
  WiFiDetailsBridge? _iosBridge;
  WifiMonitorController? _iosController;

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
        _iosController = WifiMonitorController(bridge: _iosBridge!);
        WidgetsBinding.instance.addObserver(this);
        _iosController!.load();
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS only: the Shortcut bounces the app to the foreground; on resume,
    // re-resolve so a payload delivered while backgrounded lands and any
    // persisted monitoring flag resumes the live state.
    if (state == AppLifecycleState.resumed) {
      _iosController?.load();
    }
  }

  @override
  void dispose() {
    if (_source == WifiInfoSource.iosShortcuts) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _iosController?.dispose();
    super.dispose();
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
    final WifiMonitorController? controller = _iosController;
    if (bridge == null || controller == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface2,
      builder: (_) => InstallShortcutSheet(
        bridge: bridge,
        onInstalled: controller.load,
      ),
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
        // Refresh, swapping to a spinner while a read is in flight so a refresh
        // is visibly working even when the values come back unchanged.
        return [
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
        final WifiMonitorController? controller = _iosController;
        if (controller == null) return const [];
        // How-to is reachable from the data states; the empty state surfaces
        // install inline, so no redundant app-bar action there.
        return [
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              if (controller.phase == WifiMonitorPhase.idleWithData ||
                  controller.phase == WifiMonitorPhase.streaming) {
                return Semantics(
                  button: true,
                  label: 'How to install the Shortcut',
                  child: IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: 'How to install the Shortcut',
                    onPressed: _openInstallSheet,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ];
      case WifiInfoSource.unsupported:
      case WifiInfoSource.web:
        return const [];
    }
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
          _ErrorCard(error: _macError!, onRetry: _macLoading ? null : _fetchMac),
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
    final WifiMonitorController controller = _iosController!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            switch (controller.phase) {
              case WifiMonitorPhase.loading:
                return const _IosLoadingState();
              case WifiMonitorPhase.needsInstall:
                return _EmptyInstallState(
                  edge: edge,
                  onInstall: _openInstallSheet,
                );
              case WifiMonitorPhase.idleWithData:
              case WifiMonitorPhase.streaming:
                return _IosSuccess(
                  controller: controller,
                  edge: edge,
                  isDesktop: isDesktop,
                  metricCards: (ConnectedAp ap) =>
                      _metricCards(ap, platformLabel: 'iOS'),
                );
            }
          },
        );
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
              note: info.rxRateAvailable
                  ? null
                  : 'Not exposed by $platformLabel',
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
            _MetricRow(
              label: 'Interface',
              value: info.interfaceName,
              mono: true,
            ),
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
            _MetricRow(
              label: 'Wi-Fi Power',
              value: info.poweredOn ? 'On' : 'Off',
            ),
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

/// iOS empty state -- no payload has ever arrived. Offers the install onboarding.
class _EmptyInstallState extends StatelessWidget {
  const _EmptyInstallState({required this.edge, required this.onInstall});

  final double edge;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(edge + AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                'Install the companion Shortcut once, then run it to populate '
                "this screen with the connected access point's RF metrics.",
                style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                button: true,
                label: 'Install Shortcut',
                child: FilledButton.icon(
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

/// iOS success body: the monitoring control bar + the shared metric cards.
class _IosSuccess extends StatelessWidget {
  const _IosSuccess({
    required this.controller,
    required this.edge,
    required this.isDesktop,
    required this.metricCards,
  });

  final WifiMonitorController controller;
  final double edge;
  final bool isDesktop;
  final List<Widget> Function(ConnectedAp ap) metricCards;

  @override
  Widget build(BuildContext context) {
    final ConnectedAp? ap = controller.details == null
        ? null
        : ConnectedAp.fromWifiDetails(controller.details!);
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
              _MonitorControlBar(controller: controller),
              const SizedBox(height: AppSpacing.sm),
              if (ap == null || !ap.hasAnyData)
                _WaitingForFirstPayload(streaming: controller.isStreaming)
              else ...[
                ConceptGraphicBand(
                  toolId: 'wifi-info',
                  isDesktop: isDesktop,
                ),
                if (ToolAssets.hasGraphic('wifi-info'))
                  const SizedBox(height: AppSpacing.md),
                ...metricCards(ap),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS Start/Stop control + live indicator + last-updated timestamp.
class _MonitorControlBar extends StatelessWidget {
  const _MonitorControlBar({required this.controller});

  final WifiMonitorController controller;

  static String _formatTimestamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Below this width the status and action stack vertically (reflow, not clip)
  /// so the bar survives 320px at 200% type. GL-003 section 8.9.
  static const double _reflowThreshold = 280;

  @override
  Widget build(BuildContext context) {
    final bool streaming = controller.isStreaming;
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
          final Widget status = _StatusBlock(controller: controller);
          final Widget action =
              _ActionButton(streaming: streaming, controller: controller);

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

/// Status block: state icon + "Live"/"Paused" + "Updated HH:MM:SS". The whole
/// block is one live region so both Start and Stop transitions announce (WCAG
/// 2.2 SC 4.1.3). The dot/icon is decorative; the changing text announces.
class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.controller});

  final WifiMonitorController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool streaming = controller.isStreaming;
    final DateTime? lastUpdated = controller.lastUpdated;
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
                  Text(
                    'Updated ${_MonitorControlBar._formatTimestamp(lastUpdated)}',
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
  const _ActionButton({required this.streaming, required this.controller});

  final bool streaming;
  final WifiMonitorController controller;

  @override
  Widget build(BuildContext context) {
    return streaming
        ? Semantics(
            button: true,
            label: 'Stop live monitoring',
            child: OutlinedButton.icon(
              onPressed: controller.stopMonitoring,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
            ),
          )
        : Semantics(
            button: true,
            label: 'Start live monitoring',
            child: FilledButton.icon(
              onPressed: controller.startMonitoring,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            ),
          );
  }
}

/// Decorative lime "live" dot. The live region + changing label live on
/// [_StatusBlock]; this dot is excluded from the a11y tree so Stop -> Paused
/// still announces. Lime is the section 8.3 active-state accent, not a verdict.
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
            ? 'Listening. Run the Shortcut to send Wi-Fi details.'
            : 'Press Start, then run the Shortcut to send Wi-Fi details.',
        style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
        textAlign: TextAlign.center,
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
    final String displayValue =
        (hasValue && marker != null) ? '$shown $marker' : shown;
    final bool showNote = note != null;
    final String footnote = note == null
        ? ''
        : (marker != null ? '$marker $note' : note!);

    final String labelSpoken = derived ? '$label, derived' : label;
    final String semanticLabel =
        showNote ? '$labelSpoken, $shown, $note' : '$labelSpoken, $shown';

    final AppMonoText monoText =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final Color valueColor =
        hasValue ? AppColors.textPrimary : AppColors.textSecondary;
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
                style: text.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
