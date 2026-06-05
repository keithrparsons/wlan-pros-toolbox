// WlanPiHomeScreen — the entry to the EXPERIMENTAL "WLAN Pi companion" mode.
//
// EXPERIMENTAL / COMPANION MODE. This is the discovery + connection surface
// (design spec §1.1, §2.5). It renders the discovery state machine
// ([WlanPiConnPhase]) as a sequence of FRIENDLY, first-class screens — never an
// error dump. Every phase has a clear next action.
//
// What is REAL here: the full UI/state shell, the manual-IP entry, the version
// gate copy, and the navigation into the system/profiler scaffolds (rendering
// sample data, clearly labeled). What is STUBBED: mDNS browse and the auth
// handshake — both surface honest "searching… / pending on-device spike" states
// rather than fake success. Wired Monday.
//
// Attribution (design spec §0/§6, BSD-3): the mode credits the open-source WLAN
// Pi project and makes clear WLAN Pros built a CLIENT, not the device.
//
// Tokens: GL-003 §8.1 surface stack, §4 spacing, §8.5 type, §8.11 card radius,
// theme-aware via context.colors (Light/Dark).

import 'package:flutter/material.dart';

import '../../data/wlanpi/wlanpi_connection_state.dart';
import '../../theme/app_color_scheme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/centered_content.dart';
import 'wlanpi_profiler_screen.dart';
import 'wlanpi_system_screen.dart';

class WlanPiHomeScreen extends StatefulWidget {
  const WlanPiHomeScreen({super.key});

  @override
  State<WlanPiHomeScreen> createState() => _WlanPiHomeScreenState();
}

class _WlanPiHomeScreenState extends State<WlanPiHomeScreen> {
  WlanPiConnState _state = const WlanPiConnState.initial();
  final TextEditingController _manualHost = TextEditingController();

  @override
  void dispose() {
    _manualHost.dispose();
    super.dispose();
  }

  // ── Discovery actions (mDNS STUBBED; manual entry REAL shell) ──────────────

  void _startMdnsSearch() {
    // STUBBED: mDNS browse for wlanpi-*.local:31415 is wired Monday with the
    // multicast_dns/nsd package. For now, surface the honest searching → then
    // no-Pi-found path so the friendly states are real and QA-able.
    setState(() {
      _state = _state.copyWith(
        phase: WlanPiConnPhase.searching,
        message: 'Looking for wlanpi-*.local on port 31415…',
      );
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(
          phase: WlanPiConnPhase.noPiFound,
          message:
              'mDNS discovery is not wired yet (lands Monday). On enterprise '
              'or guest Wi-Fi, mDNS is often filtered — use manual entry below.',
        );
      });
    });
  }

  void _connectManual() {
    final String host = _manualHost.text.trim();
    if (host.isEmpty) return;
    final WlanPiCandidate candidate = WlanPiCandidate(host: host, port: 31415);
    // STUBBED: real flow validates /openapi.json (version gate) then runs the
    // token handshake. Until Monday, land on the honest authNeeded state.
    setState(() {
      _state = _state.copyWith(
        phase: WlanPiConnPhase.authNeeded,
        selected: candidate,
        candidates: <WlanPiCandidate>[candidate],
        message:
            'Reached the address you entered. The authenticated handshake with '
            'wlanpi-core is pending the on-device spike — see what is captured '
            'Monday. You can still preview the result layouts below with sample '
            'data.',
      );
    });
  }

  void _reset() {
    setState(() => _state = const WlanPiConnState.initial());
  }

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Scaffold(
      backgroundColor: colors.surface0,
      appBar: AppBar(
        title: const Text('WLAN Pi'),
        bottom: const _ExperimentalBanner(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: CenteredContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _intro(colors),
                const SizedBox(height: AppSpacing.md),
                _phaseCard(colors),
                const SizedBox(height: AppSpacing.md),
                _previewSection(colors),
                const SizedBox(height: AppSpacing.md),
                _attribution(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(AppColorScheme colors) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'See what your phone won’t show you',
            style: TextStyle(
              fontSize: AppTextSize.h3,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'iOS and macOS hide a client’s channel width, MCS, spatial streams, '
            '802.11k/r/v/w and WPA3 support. Point this at a WLAN Pi on the same '
            'network and its profiler decodes them for you.',
            style: TextStyle(
              fontSize: AppTextSize.body,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseCard(AppColorScheme colors) {
    switch (_state.phase) {
      case WlanPiConnPhase.initial:
        return _initialCard(colors);
      case WlanPiConnPhase.searching:
        return _statusCard(
          colors,
          icon: Icons.wifi_find,
          title: 'Searching…',
          body: _state.message ?? '',
          showSpinner: true,
        );
      case WlanPiConnPhase.found:
        return _initialCard(colors); // candidate-list UI lands with real mDNS
      case WlanPiConnPhase.wrongVersion:
        return _statusCard(
          colors,
          icon: Icons.update,
          title: 'This WLAN Pi’s software is older than this mode supports',
          body: _state.message ??
              'The companion mode targets WLAN Pi OS 3.x (the wlanpi-core API). '
                  'Older software has no compatible API.',
          accent: colors.statusWarning,
        );
      case WlanPiConnPhase.authNeeded:
        return _statusCard(
          colors,
          icon: Icons.lock_outline,
          title: 'Authentication pending',
          body: _state.message ?? '',
          accent: colors.statusInfo,
          trailing: TextButton(onPressed: _reset, child: const Text('Start over')),
        );
      case WlanPiConnPhase.connected:
        return _statusCard(
          colors,
          icon: Icons.check_circle_outline,
          title: 'Connected to ${_state.selected?.label ?? 'WLAN Pi'}',
          body: 'Authenticated session active.',
          accent: colors.statusSuccess,
        );
      case WlanPiConnPhase.noPiFound:
        return _noPiFoundCard(colors);
    }
  }

  Widget _initialCard(AppColorScheme colors) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Find your WLAN Pi',
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _startMdnsSearch,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Search the network'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Or enter the address',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _manualEntryRow(colors),
        ],
      ),
    );
  }

  Widget _manualEntryRow(AppColorScheme colors) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _manualHost,
            decoration: const InputDecoration(
              hintText: 'e.g. 192.168.1.42 or wlanpi-cda.local',
              prefixText: 'http://',
              suffixText: ':31415',
            ),
            onSubmitted: (_) => _connectManual(),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        FilledButton(onPressed: _connectManual, child: const Text('Connect')),
      ],
    );
  }

  Widget _noPiFoundCard(AppColorScheme colors) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.search_off, color: colors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'No WLAN Pi found',
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _state.message ?? '',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Checklist: same Wi-Fi as the Pi? Pi powered on? mDNS allowed on this '
            'SSID? If unsure, enter the IP directly.',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: colors.textTertiary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _manualEntryRow(colors),
        ],
      ),
    );
  }

  Widget _statusCard(
    AppColorScheme colors, {
    required IconData icon,
    required String title,
    required String body,
    Color? accent,
    bool showSpinner = false,
    Widget? trailing,
  }) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (showSpinner)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon, color: accent ?? colors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.body,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: TextStyle(
                fontSize: AppTextSize.caption,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ],
      ),
    );
  }

  Widget _previewSection(AppColorScheme colors) {
    return _Card(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Preview the views (sample data)',
            style: TextStyle(
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These render placeholder data so the layout is ready. Live device '
            'reads land Monday.',
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: colors.textTertiary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WlanPiProfilerScreen(useSampleData: true),
              ),
            ),
            icon: const Icon(Icons.insights),
            label: const Text('Client capabilities (profiler)'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WlanPiSystemScreen(useSampleData: true),
              ),
            ),
            icon: const Icon(Icons.dns_outlined),
            label: const Text('System & network status'),
          ),
        ],
      ),
    );
  }

  Widget _attribution(AppColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        'Powered by the open-source WLAN Pi project (wlanpi-core, BSD-3). '
        'WLAN Pros built this client; it is not the WLAN Pi device and is not '
        'endorsed by the WLAN Pi project. Learn more at wlanpi.com.',
        style: TextStyle(
          fontSize: AppTextSize.caption,
          color: colors.textTertiary,
          height: 1.4,
        ),
      ),
    );
  }
}

/// A surface1 card with the standard §8.11 radius + §4 padding.
class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.child});

  final AppColorScheme colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

/// The persistent "experimental / companion" label under the AppBar so the mode
/// is always clearly marked as not-yet-final.
class _ExperimentalBanner extends StatelessWidget implements PreferredSizeWidget {
  const _ExperimentalBanner();

  @override
  Size get preferredSize => const Size.fromHeight(28);

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Container(
      width: double.infinity,
      color: colors.statusInfoFill,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: AppSpacing.sm),
      child: Text(
        'EXPERIMENTAL · companion mode · live device wiring lands Monday',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppTextSize.caption,
          color: colors.statusInfo,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
