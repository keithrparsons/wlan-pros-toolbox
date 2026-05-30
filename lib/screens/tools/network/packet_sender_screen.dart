// Packet Sender tool — send a custom payload to host:port over TCP or UDP and
// show the reply (raw byte count + hex + decoded text).
//
// SCOPE: TCP via Socket, UDP via RawDatagramSocket (TICKET-005 / GL-008). No raw
// sockets, no ICMP/IP framing.
//
// States (SOP-007 §5):
//  - idle      → form only.
//  - loading   → send in flight; button shows progress, inputs disabled.
//  - success   → reply panel (bytes received, hex/text view switch).
//  - empty     → TCP connected / UDP sent but NO reply came back. For UDP this
//                is honestly normal (no delivery guarantee); for TCP it means
//                the service accepted and stayed silent. Not an error.
//  - error     → refused / unreachable / timeout / DNS failure / bad input,
//                mapped to a precise message.
//  - disabled  → "Send" disabled until a host is entered.
//  - web       → NetworkUnavailableView (no sockets in a browser).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/packet_sender_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class PacketSenderScreen extends StatefulWidget {
  const PacketSenderScreen({super.key, this.service});

  final PacketSenderService? service;

  @override
  State<PacketSenderScreen> createState() => _PacketSenderScreenState();
}

enum _View { text, hex }

class _PacketSenderScreenState extends State<PacketSenderScreen> {
  late final PacketSenderService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _portCtrl = TextEditingController();
  final TextEditingController _payloadCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  PacketTransport _transport = PacketTransport.tcp;
  _View _view = _View.text;
  bool _sending = false;
  bool _canRun = false;
  String? _inputError;
  PacketResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PacketSenderService();
    _hostCtrl.addListener(_recomputeCanRun);
    _portCtrl.addListener(_recomputeCanRun);
  }

  void _recomputeCanRun() {
    final bool can =
        _hostCtrl.text.trim().isNotEmpty && _portCtrl.text.trim().isNotEmpty;
    if (can != _canRun) setState(() => _canRun = can);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _payloadCtrl.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_canRun) return;
    final int? port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _inputError = 'Port must be a number between 1 and 65535.');
      return;
    }
    final List<int>? payload = PacketSenderService.parsePayload(_payloadCtrl.text);
    if (payload == null) {
      setState(() => _inputError =
          r'Bad hex escape in the payload — \x must be followed by two hex '
          r'digits, e.g. \x00\xff.');
      return;
    }

    _hostFocus.unfocus();
    setState(() {
      _inputError = null;
      _sending = true;
      _result = null;
    });

    final PacketResult result = await _service.send(
      transport: _transport,
      host: _hostCtrl.text,
      port: port,
      payload: payload,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = result;
    });

    // WCAG 4.1.3 — announce the outcome.
    final String announcement;
    if (result.isError) {
      announcement = 'Send failed: ${result.errorMessage}';
    } else if (result.received.isEmpty) {
      announcement = 'Sent, no reply received';
    } else {
      announcement = 'Reply received, ${result.received.length} bytes';
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      announcement,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Packet Sender'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (!NetworkSupport.packetSenderSupported) {
      return NetworkUnavailableView(
        toolName: 'Packet Sender',
        reason: NetworkSupport.unavailableReason ?? NetworkUnavailableReason.web,
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
                    toolId: 'packet-sender',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('packet-sender'))
                    const SizedBox(height: AppSpacing.md),
                  _formCard(context),
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _resultSection(context, _result!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _formCard(BuildContext context) {
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
          // Transport toggle.
          Text(
            'Transport',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _transportChip(context, PacketTransport.tcp, 'TCP'),
              const SizedBox(width: AppSpacing.xs),
              _transportChip(context, PacketTransport.udp, 'UDP'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Host or IP',
            field: TextField(
              controller: _hostCtrl,
              focusNode: _hostFocus,
              enabled: !_sending,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '192.168.1.1'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Port',
            field: TextField(
              controller: _portCtrl,
              enabled: !_sending,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: '80'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Payload',
            semanticLabel: 'Payload, text or hex escapes',
            field: TextField(
              controller: _payloadCtrl,
              enabled: !_sending,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.text,
              minLines: 1,
              maxLines: 4,
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                hintText: r'GET / HTTP/1.0\r\n\r\n  or  \x00\xff',
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            r'Plain text, or hex escapes: \xNN for a byte, plus \r \n \t \0 \\.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          if (_inputError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // WCAG 4.1.3 — the synchronous validation failures (bad port, bad
            // hex payload) return before the async send announcement, so the
            // error text carries its own live region. Only the validation path
            // populates _inputError; the async path clears it, so there is no
            // double-announcement against the _send() sendAnnouncement block.
            Semantics(
              liveRegion: true,
              child: Text(
                _inputError!,
                style:
                    text.labelMedium?.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: (_sending || !_canRun) ? null : _send,
            child: _sending
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: Semantics(
                      label: 'Sending…',
                      liveRegion: true,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                : const Text('Send'),
          ),
        ],
      ),
    );
  }

  Widget _transportChip(
    BuildContext context,
    PacketTransport transport,
    String label,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = _transport == transport;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? AppColors.secondary : AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface2,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      side: AppTheme.chipSide(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected:
          _sending ? null : (_) => setState(() => _transport = transport),
    );
  }

  Widget _resultSection(BuildContext context, PacketResult r) {
    if (r.isError) {
      return _MessageCard(
        icon: _iconForError(r.errorKind!),
        title: _titleForError(r.errorKind!),
        body: r.errorMessage!,
      );
    }
    return _ReplyCard(result: r, view: _view, onViewChanged: (v) {
      setState(() => _view = v);
    });
  }

  IconData _iconForError(PacketErrorKind kind) => switch (kind) {
        PacketErrorKind.timeout => Icons.schedule,
        PacketErrorKind.refused => Icons.do_not_disturb_on_outlined,
        PacketErrorKind.unreachable => Icons.cloud_off,
        PacketErrorKind.dnsFailure => Icons.travel_explore_outlined,
        PacketErrorKind.invalidInput => Icons.edit_outlined,
        PacketErrorKind.other => Icons.error_outline,
      };

  String _titleForError(PacketErrorKind kind) => switch (kind) {
        PacketErrorKind.timeout => 'Timed out',
        PacketErrorKind.refused => 'Connection refused',
        PacketErrorKind.unreachable => 'Host unreachable',
        PacketErrorKind.dnsFailure => 'Name not resolved',
        PacketErrorKind.invalidInput => 'Check your input',
        PacketErrorKind.other => 'Send failed',
      };
}

/// The reply panel — bytes-sent/received summary, a text/hex view switch, and
/// the decoded body. Handles the honest "no reply" outcome too.
class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.result,
    required this.view,
    required this.onViewChanged,
  });

  final PacketResult result;
  final _View view;
  final ValueChanged<_View> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool noReply = result.received.isEmpty;
    final String transportLabel =
        result.transport == PacketTransport.tcp ? 'TCP' : 'UDP';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: noReply ? AppColors.border : AppColors.borderStrong,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                noReply ? Icons.outbox_outlined : Icons.inbox_outlined,
                size: 24,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  noReply ? 'Sent — no reply' : 'Reply received',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (noReply)
            Text(
              result.transport == PacketTransport.udp
                  ? 'The datagram was sent ($transportLabel, '
                      '${result.bytesSent} bytes), but no reply arrived within '
                      'the timeout. UDP has no delivery guarantee, so this is '
                      'expected when the port is closed, filtered, or the '
                      'service simply does not answer.'
                  : 'Connected and sent $transportLabel '
                      '(${result.bytesSent} bytes), but the service returned '
                      'nothing before the read went idle.',
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          const SizedBox(height: AppSpacing.sm),
          _row(context, 'Transport', transportLabel, mono),
          _row(context, 'Target', '${result.host}:${result.port}', mono),
          _row(context, 'Sent', '${result.bytesSent} bytes', mono),
          _row(context, 'Received', '${result.received.length} bytes', mono),
          _row(
            context,
            'Elapsed',
            '${result.elapsed.inMilliseconds} ms',
            mono,
          ),
          if (!noReply) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _viewChip(context, _View.text, 'Text'),
                const SizedBox(width: AppSpacing.xs),
                _viewChip(context, _View.hex, 'Hex'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface0,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: SelectableText(
                view == _View.hex
                    ? PacketSenderService.toHex(result.received)
                    : PacketSenderService.decodeText(result.received),
                style: mono.inlineCode.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: AppTextSize.caption,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _viewChip(BuildContext context, _View v, String label) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool selected = view == v;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: text.labelMedium?.copyWith(
        color: selected ? AppColors.secondary : AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface2,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      side: AppTheme.chipSide(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: (_) => onViewChanged(v),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value,
    AppMonoText mono,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.rowPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              value,
              style: mono.inlineCode.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared neutral message card for error states — color-free per §8.4.
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
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: text.labelMedium
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
