// Wake-on-LAN tool — send a magic packet to wake a host by MAC address.
//
// States (SOP-007 §5):
//  - idle     → form only, no result panel yet.
//  - loading  → send in flight; button shows progress, inputs disabled.
//  - success  → "Packet sent" + what was sent (MAC, broadcast, port, bytes,
//               packet hex). Honestly fire-and-forget: NEVER claims the device
//               woke (WoL is unacknowledged).
//  - error    → invalid MAC / invalid broadcast / invalid port / send failure.
//  - disabled → "Send magic packet" disabled until a MAC is entered.
//  - web      → NetworkUnavailableView (UDP broadcast impossible in a browser).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/pi_backend.dart';
import '../../../services/network/pi_backend_client.dart';
import '../../../services/network/wake_on_lan_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class WakeOnLanScreen extends StatefulWidget {
  const WakeOnLanScreen({super.key, this.service});

  final WakeOnLanService? service;

  @override
  State<WakeOnLanScreen> createState() => _WakeOnLanScreenState();
}

class _WakeOnLanScreenState extends State<WakeOnLanScreen> {
  late final WakeOnLanService _service;
  final TextEditingController _macCtrl = TextEditingController();
  final TextEditingController _broadcastCtrl = TextEditingController();
  final FocusNode _macFocus = FocusNode();

  int _port = WakeOnLanService.defaultPort;
  bool _loading = false;
  bool _canRun = false;
  WakeOnLanResult? _result;

  static const List<int> _ports = <int>[9, 7];

  /// True when this build is served FROM a WLAN Pi (Pi-hosted web): the browser
  /// cannot open a UDP broadcast socket, so the magic packet is sent ON the Pi
  /// via POST `/toolboxapi/wol`. Gated on [PiBackend.canServe] (not just
  /// `available`), so the body stays dormant until the tool id is activated in
  /// [PiBackend.servedToolIds] — native and Netlify-web behavior are unchanged.
  late final bool _piBacked;

  @override
  void initState() {
    super.initState();
    _piBacked =
        kIsWeb && PiBackend.canServe('wake-on-lan') && widget.service == null;
    // On the Pi path the native UDP service is never constructed (the browser
    // has no datagram socket); the send runs server-side through the client.
    if (!_piBacked) {
      _service = widget.service ?? WakeOnLanService();
    }
    _macCtrl.addListener(_recomputeCanRun);
  }

  void _recomputeCanRun() {
    final bool can = _macCtrl.text.trim().isNotEmpty;
    if (can != _canRun) setState(() => _canRun = can);
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _broadcastCtrl.dispose();
    _macFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading || !_canRun) return;
    _macFocus.unfocus();
    setState(() => _loading = true);
    final WakeOnLanResult result = _piBacked
        ? await _wakePi()
        : await _service.wake(
            rawMac: _macCtrl.text,
            rawBroadcast: _broadcastCtrl.text,
            port: _port,
          );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    // WCAG 4.1.3 — announce the outcome. Honest copy: "sent", not "awake".
    final String announcement = result.isError
        ? 'Send failed'
        : 'Magic packet sent to ${result.normalizedMac}';
    SemanticsService.sendAnnouncement(
      View.of(context),
      announcement,
      TextDirection.ltr,
    );
  }

  /// Pi-hosted send: the magic packet is broadcast FROM the Pi hosting this page
  /// (POST `/toolboxapi/wol`), returning the SAME [WakeOnLanResult] the native
  /// UDP path builds so the result renders identically. The MAC is normalized
  /// locally first (same inline validation as the native service), so an invalid
  /// MAC fails immediately without a round-trip. A transport failure surfaces the
  /// [PiBackendException] message through the existing failure card. Never throws.
  Future<WakeOnLanResult> _wakePi() async {
    final String? mac = WakeOnLanService.normalizeMac(_macCtrl.text);
    if (mac == null) {
      return WakeOnLanResult.failure(
        message: 'Enter a valid MAC address — 6 bytes, e.g. '
            'AA:BB:CC:DD:EE:FF (colons, hyphens, or no separators all work).',
      );
    }
    final String broadcast = _broadcastCtrl.text.trim().isEmpty
        ? WakeOnLanService.defaultBroadcast
        : _broadcastCtrl.text.trim();
    try {
      return await PiBackendClient().wakeOnLan(
        mac: mac,
        broadcast: broadcast,
        port: _port,
      );
    } on PiBackendException catch (e) {
      return WakeOnLanResult.failure(
        message: e.message,
        normalizedMac: mac,
        broadcast: broadcast,
        port: _port,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wake-on-LAN'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. No help icon on this
        // screen, so copy is the only action. Disabled until a send has
        // produced a result (sent OR failed).
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the magic-packet send outcome as a labeled plain-text
  /// block, mirroring the on-screen `_SentCard` / failure card. The send STATUS
  /// WORD always leads ("Sent" / "Failed") so the verdict survives to the
  /// clipboard color-independent (§8.16). Honest about Wake-on-LAN being
  /// fire-and-forget: this records that the packet left the device, never that
  /// the target woke.
  ///
  /// Returns null (→ disabled affordance) until a send completes; a send in
  /// flight has no result to keep.
  String? _buildCopyText() {
    final WakeOnLanResult? r = _result;
    if (_loading || r == null) return null;

    final StringBuffer buf = StringBuffer()..writeln('Wake-on-LAN');

    if (r.isError) {
      buf
        ..writeln('Status: Failed')
        ..writeln('  ${r.errorMessage}');
      if (r.normalizedMac.isNotEmpty) {
        buf.writeln('  Target MAC: ${r.normalizedMac}');
      }
      if (r.broadcast.isNotEmpty) buf.writeln('  Broadcast: ${r.broadcast}');
      buf.writeln('  Port: ${r.port}');
      return buf.toString().trimRight();
    }

    buf
      ..writeln(
        _piBacked
            ? 'Status: Sent (the packet left the WLAN Pi hosting this page; '
                  'Wake-on-LAN is unacknowledged, so this is not confirmation '
                  'the target woke)'
            : 'Status: Sent (the packet left this device; Wake-on-LAN is '
                  'unacknowledged, so this is not confirmation the target woke)',
      )
      ..writeln('  Target MAC: ${r.normalizedMac}')
      ..writeln('  Broadcast: ${r.broadcast}')
      ..writeln('  Port: ${r.port}')
      ..writeln('  Bytes sent: ${r.bytesSent}');
    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.wakeOnLanSupported) {
      return NetworkUnavailableView(
        toolName: 'Wake-on-LAN',
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
                  ConceptGraphicBand(
                    toolId: 'wake-on-lan',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('wake-on-lan'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _resultsSection(context),
                  ToolHelpFooter(toolId: 'wake-on-lan'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
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
          LabeledField(
            label: 'Target MAC address',
            field: TextField(
              controller: _macCtrl,
              focusNode: _macFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                // Allow only hex, separators, dots — nothing that could not be
                // part of a MAC. Validation still happens in the service.
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F:\-.\s]')),
              ],
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: 'AA:BB:CC:DD:EE:FF'),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Colons, hyphens, dots, or no separators all work.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Broadcast address (optional)',
            field: TextField(
              controller: _broadcastCtrl,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _run(),
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(
                hintText: '255.255.255.255 (default)',
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Use a subnet broadcast (e.g. 192.168.1.255) to reach a host '
            'behind a router that drops the all-ones broadcast.',
            style: text.labelSmall?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Port',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: _ports.map((int p) {
              final bool selected = p == _port;
              return ChoiceChip(
                label: Text('$p'),
                selected: selected,
                showCheckmark: false,
                labelStyle: text.labelMedium?.copyWith(
                  color: selected
                      ? colors.onPrimary
                      : colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                selectedColor: colors.primary,
                backgroundColor: colors.surface2,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                // §8.3 — shared resolver: idle/selected/disabled borders + 2px
                // lime keyboard-focus ring.
                side: AppTheme.chipSide(Theme.of(context).brightness),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                onSelected: _loading ? null : (_) => setState(() => _port = p),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: (_loading || !_canRun) ? null : _run,
            child: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: Semantics(
                      label: 'Sending magic packet…',
                      liveRegion: true,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    ),
                  )
                : const Text('Send magic packet'),
          ),
        ],
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    final WakeOnLanResult? r = _result;
    if (r == null) return const SizedBox.shrink();
    if (r.isError) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Send failed',
        body: r.errorMessage!,
      );
    }
    return _SentCard(result: r, piBacked: _piBacked);
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({required this.result, this.piBacked = false});

  final WakeOnLanResult result;

  /// True on the Pi-hosted path: the packet was broadcast from the WLAN Pi, not
  /// this device, so the honesty copy attributes it to the Pi (GL-005 /
  /// feedback_screenshot_text_match).
  final bool piBacked;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final String hex = WakeOnLanService.packetHex(
      WakeOnLanService.buildMagicPacket(result.normalizedMac),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // §8.4 status colors are v1.1-deferred — neutral icon + text, no
              // color-only meaning.
              Icon(
                Icons.send_outlined,
                size: 24,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Magic packet sent',
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Honesty: WoL is fire-and-forget. State exactly what is and isn't
          // verifiable — and, on the Pi path, WHERE it was sent from.
          Text(
            piBacked
                ? 'Wake-on-LAN is fire-and-forget — there is no acknowledgement, '
                      'so this confirms the packet left the WLAN Pi hosting this '
                      'page, not that the target woke. The Pi broadcasts on its '
                      'own segment, so a target on a different segment than the '
                      "Pi will not receive it. If it does not wake, check that "
                      "WoL is enabled in the target's BIOS/OS."
                : 'Wake-on-LAN is fire-and-forget — there is no acknowledgement, '
                      'so this confirms the packet left this device, not that '
                      'the target woke. If it does not wake, check that WoL is '
                      "enabled in the target's BIOS/OS and that the broadcast "
                      'reaches its segment.',
            style: text.labelMedium?.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _row(
            context,
            'Target MAC',
            result.normalizedMac,
            mono,
            identifier: true,
          ),
          _row(context, 'Broadcast', result.broadcast, mono, identifier: true),
          _row(context, 'Port', '${result.port}', mono),
          _row(context, 'Bytes sent', '${result.bytesSent}', mono),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Magic packet (102 bytes)',
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.surface0,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: colors.border, width: 1),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: SelectableText(
              hex,
              // Magic-packet hex dump is a hex identifier → Roboto Mono (§8.5).
              style: mono.robotoMono.copyWith(
                color: colors.textPrimary,
                fontSize: AppTextSize.caption,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value,
    AppMonoText mono, {
    bool identifier = false,
  }) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppColorScheme colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              value,
              style: (identifier ? mono.robotoMono : mono.inlineCode).copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
        children: [
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium?.copyWith(
                    color: colors.textTertiary,
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
