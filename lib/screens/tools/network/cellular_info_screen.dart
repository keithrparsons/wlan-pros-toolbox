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

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/cellular_info.dart';
import '../../../services/network/cellular_info_adapter.dart';
import '../../../services/network/cellular_info_bridge.dart';
import '../../../services/network/cellular_shortcuts_config.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
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

/// The iOS data-flow phase. Cellular is one-shot, so this is simpler than the
/// Wi-Fi streaming controller: load -> (needsInstall | hasData).
enum _IosPhase { loading, needsInstall, hasData }

class _CellularInfoScreenState extends State<CellularInfoScreen>
    with WidgetsBindingObserver {
  late final CellularInfoSource _source;

  // ---- iOS (Shortcuts one-shot) state ----
  CellularInfoBridge? _iosBridge;
  _IosPhase _iosPhase = _IosPhase.loading;
  CellularInfo? _iosInfo;

  @override
  void initState() {
    super.initState();
    _source = widget.sourceOverride ?? CellularInfoSourceResolver.resolve();

    if (_source == CellularInfoSource.iosShortcuts) {
      _iosBridge = widget.iosBridge ?? CellularInfoBridge();
      WidgetsBinding.instance.addObserver(this);
      _loadIos();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS only: the Shortcut bounces the app to the foreground; on resume,
    // re-read so a payload delivered while backgrounded lands.
    if (state == AppLifecycleState.resumed &&
        _source == CellularInfoSource.iosShortcuts) {
      _loadIos();
    }
  }

  @override
  void dispose() {
    if (_source == CellularInfoSource.iosShortcuts) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
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

        switch (_iosPhase) {
          case _IosPhase.loading:
            return const _IosLoadingState();
          case _IosPhase.needsInstall:
            return _EmptyInstallState(edge: edge, onInstall: _openInstallSheet);
          case _IosPhase.hasData:
            return _IosSuccess(
              info: _iosInfo!,
              edge: edge,
              isDesktop: isDesktop,
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

/// iOS empty state — no payload has ever arrived. Offers the install onboarding.
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
                'Install the companion Shortcut once, then run it to populate '
                "this screen with your carrier, radio technology, signal bars, "
                'country code, and roaming status.',
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

/// iOS success body: the shared metric cards rendering the [CellularInfo].
class _IosSuccess extends StatelessWidget {
  const _IosSuccess({
    required this.info,
    required this.edge,
    required this.isDesktop,
  });

  final CellularInfo info;
  final double edge;
  final bool isDesktop;

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

  /// Number of filled bars, 0..[CellularInfo.maxSignalBars].
  final int filled;

  @override
  Widget build(BuildContext context) {
    const double barWidth = 6;
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
              width: barWidth,
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
