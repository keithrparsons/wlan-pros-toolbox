// Device Info tool — the device's own system facts (Batch 6).
//
// Shows: device MODEL (marketing name + raw identifier), TOTAL MEMORY (RAM,
// human-readable), system UPTIME (since last boot), and the CELLULAR IP (iOS
// `pdp_ip0` heuristic). A sibling to Interface Information: that tool owns the
// NETWORK state (IPs, gateway, Wi-Fi link); this one owns DEVICE/SYSTEM state.
// Kept a separate tool deliberately — folding these rows into Interface Info
// would blur its networking focus and crowd an already-dense screen.
//
// States (SOP-007 §5):
//  - loading  → labeled spinner while the snapshot reads.
//  - success  → grouped cards: Device, System, Cellular.
//  - error    → read threw; retry affordance.
//  - per-field unavailable → each row that the platform can't supply renders
//    the honest "Not available on this platform" / "No cellular interface"
//    state, never a fabricated 0 (GL-005 / Truthfulness Audit).
//  - web      → NetworkUnavailableView (never reached; service is off-web).
//
// Layout + tokens mirror interface_info_screen.dart exactly (SafeArea +
// LayoutBuilder + centered ConstrainedBox + scroll, surface1 cards with a
// hairline border, ValueRow for label/value lines, AppCopyAction in the AppBar,
// ToolHelpFooter at the foot). No new design tokens.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/device_info_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key, this.service});

  /// Injectable for tests; defaults to the real service off-web.
  final DeviceInfoService? service;

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  DeviceInfoService? _service;
  Future<DeviceInfoSnapshot>? _future;

  // The resolved snapshot, mirrored out of the FutureBuilder so the §8.16 copy
  // builder can read the current result and the affordance re-enables when the
  // read completes. Null while loading / before the first read / on error.
  DeviceInfoSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    if (NetworkSupport.interfaceInfoSupported) {
      _service = widget.service ?? DeviceInfoService();
      _load();
    }
  }

  void _load() {
    final Future<DeviceInfoSnapshot> future = _service!.read();
    setState(() {
      _future = future;
      // Disable copy while the (re)read is in flight; it re-enables on success.
      _snapshot = null;
    });
    future
        .then((DeviceInfoSnapshot data) {
          if (!mounted || !identical(_future, future)) return;
          setState(() => _snapshot = data);
        })
        .catchError((Object _) {
          // Errors surface via the FutureBuilder's error branch; copy stays
          // disabled (snapshot null). Swallow here so no unhandled-error fires.
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Info'),
        toolbarHeight: 64,
        // §8.16 — copy leads, refresh trails. Help lives in the body footer
        // (§8.16.1), not the AppBar. Copy is disabled until a read completes.
        actions: [
          if (NetworkSupport.interfaceInfoSupported) ...[
            AppCopyAction(textBuilder: _buildCopyText),
            // Explicit accessible name (WCAG 2.2 AA SC 4.1.2, GL-003 §8.16):
            // `tooltip:` maps to AXHelp, not AXTitle, so an icon-only button
            // reads as `label="" button=true` without this. `enabled:` is set
            // so the node reads as an enabled button; the refresh action is
            // always available (a fresh read can be requested at any time).
            Semantics(
              button: true,
              enabled: true,
              label: 'Refresh device info',
              child: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _load,
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the device snapshot as a labeled plain-text block.
  /// Returns null (→ disabled affordance) while a read is in flight, before the
  /// first read, or after an error. Absent fields are omitted, matching the
  /// on-screen honest blanks (GL-005).
  String? _buildCopyText() {
    final DeviceInfoSnapshot? data = _snapshot;
    if (data == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('Device Info');
    void line(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        buf.writeln('$label: ${value.trim()}');
      }
    }

    buf.writeln();
    buf.writeln('Device');
    line('Model', data.modelName);
    line('Model identifier', data.modelIdentifier);

    buf.writeln();
    buf.writeln('System');
    line('Total memory', data.totalMemoryLabel);
    line('Uptime', data.uptimeLabel);

    buf.writeln();
    buf.writeln('Cellular');
    if (data.cellularInterfacePresent) {
      line('Interface', kCellularInterfaceName);
      if (data.cellularAddresses.isEmpty) {
        line('Address', 'Interface up, no address assigned');
      } else {
        for (final CellularAddress a in data.cellularAddresses) {
          line(a.isIPv4 ? 'IPv4' : 'IPv6', a.ip);
        }
      }
    } else {
      line('Cellular', 'No cellular interface');
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.interfaceInfoSupported) {
      return NetworkUnavailableView(
        toolName: 'Device Info',
        reason:
            NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        return FutureBuilder<DeviceInfoSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingState();
            }
            if (snapshot.hasError) {
              return _ErrorState(onRetry: _load);
            }
            final DeviceInfoSnapshot? data = snapshot.data;
            if (data == null) {
              return _ErrorState(onRetry: _load);
            }
            return _Success(data: data, edge: edge, isDesktop: isDesktop);
          },
        );
      },
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({
    required this.data,
    required this.edge,
    required this.isDesktop,
  });

  final DeviceInfoSnapshot data;
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
              ConceptGraphicBand(toolId: 'device-info', isDesktop: isDesktop),
              if (ToolAssets.hasGraphic('device-info'))
                const SizedBox(height: AppSpacing.md),
              _deviceCard(context),
              const SizedBox(height: AppSpacing.sm),
              _systemCard(context),
              const SizedBox(height: AppSpacing.sm),
              _cellularCard(context),
              ToolHelpFooter(toolId: 'device-info'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceCard(BuildContext context) {
    return _Card(
      title: 'Device',
      child: Column(
        children: [
          ValueRow(
            label: 'Model',
            value: data.modelName,
            emphasize: true,
          ),
          // The raw identifier (e.g. iPhone16,2 / Mac15,3) sits beneath the
          // marketing name as the precise machine string. `identifier` register
          // (Roboto Mono) per GL-003 §8.5 — it is a scanned machine token.
          ValueRow(
            label: 'Identifier',
            value: data.modelIdentifier,
            identifier: true,
          ),
        ],
      ),
    );
  }

  Widget _systemCard(BuildContext context) {
    return _Card(
      title: 'System',
      child: Column(
        children: [
          // Total memory + uptime are computed numerics → DM Mono (`mono`) so
          // the values read as measured quantities, not identifiers.
          ValueRow(
            label: 'Total memory',
            value: data.totalMemoryLabel,
            mono: true,
          ),
          ValueRow(
            label: 'Uptime',
            value: data.uptimeLabel,
            mono: true,
          ),
        ],
      ),
    );
  }

  Widget _cellularCard(BuildContext context) {
    final bool present = data.cellularInterfacePresent;
    return _Card(
      title: 'Cellular',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!present)
            const _NoCellularHint()
          else ...[
            // Name the heuristic honestly: this is the conventional iOS cellular
            // interface name, not a guaranteed-stable role mapping.
            ValueRow(
              label: 'Interface',
              value: '$kCellularInterfaceName (cellular)',
              identifier: true,
            ),
            if (data.cellularAddresses.isEmpty)
              const ValueRow(
                label: 'Address',
                value: null, // → honest "Not available" treatment
              )
            else
              for (final CellularAddress a in data.cellularAddresses)
                ValueRow(
                  label: a.isIPv4 ? 'IPv4' : 'IPv6',
                  value: a.ip,
                  identifier: true,
                ),
          ],
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(AppSpacing.sm),
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

/// The honest "no cellular interface" state shown when `pdp_ip0` is absent —
/// the expected case on a Wi-Fi-only iPhone, in airplane mode, or on macOS
/// (which has no cellular interface). Explains WHY, so an empty card never
/// reads as a bug or a failed read (GL-005).
class _NoCellularHint extends StatelessWidget {
  const _NoCellularHint();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label:
          'Cellular, no cellular interface. None found. This is normal on '
          'Wi-Fi-only devices, in airplane mode, or on a Mac.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No cellular interface',
              style: (text.bodyLarge ?? const TextStyle()).copyWith(
                color: colors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Normal on Wi-Fi-only devices, in airplane mode, or on a Mac. '
              'Detection looks for the $kCellularInterfaceName interface, the '
              'conventional iOS cellular name.',
              style: text.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    // WCAG 4.1.3 — label the spinner so VoiceOver/TalkBack speak the state.
    return Center(
      child: Semantics(
        label: 'Reading device info…',
        liveRegion: true,
        child: CircularProgressIndicator(color: colors.textAccent),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not read device info',
              style: text.headlineSmall?.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
