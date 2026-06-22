// Time Server (NTP) tool — query an NTP server over SNTP and report the
// server's time, the device clock's offset, and the round-trip delay.
//
// States (SOP-007 §5):
//  - idle     → form only, no results panel yet.
//  - loading  → query in flight; button shows progress, input disabled.
//  - success  → results card: server, resolved IP, stratum (+ meaning), server
//               time (UTC + local), device time, signed clock offset with a
//               plain-language StatusChip verdict, and round-trip delay.
//  - error    → timeout / DNS / short-reply / kiss-o'-death with a clear message
//               (GL-005 — never a fabricated offset).
//  - disabled → "Check time" disabled while a query is in flight.
//  - web      → NetworkUnavailableView (UDP/123 cannot run in a browser).
//
// Offset sign convention is hidden from the reader: the StatusChip states it in
// plain language ("Your clock is 42 ms behind" / "in sync"), so nobody has to
// remember which sign means fast vs slow.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../services/network/network_support.dart';
import '../../../services/network/ntp_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/tool_help_footer.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class NtpScreen extends StatefulWidget {
  const NtpScreen({super.key, this.service});

  /// Injectable for tests — a fake [NtpService] drives the screen with no live
  /// network. Production uses the default UDP transport.
  final NtpService? service;

  @override
  State<NtpScreen> createState() => _NtpScreenState();
}

class _NtpScreenState extends State<NtpScreen> {
  late final NtpService _service;
  final TextEditingController _serverCtrl =
      TextEditingController(text: kDefaultNtpServer);
  final FocusNode _serverFocus = FocusNode();

  bool _loading = false;
  NtpResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NtpService();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _serverFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading) return;
    _serverFocus.unfocus();
    setState(() {
      _loading = true;
      _result = null;
    });

    final NtpResult result = await _service.query(server: _serverCtrl.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
    _announce(_announcement(result));
  }

  /// One-tap switch to the documented public fallback server.
  void _useFallback() {
    _serverCtrl.text = kFallbackNtpServer;
    setState(() {});
  }

  // WCAG 4.1.3 — announce the outcome so AT users learn results landed without
  // the focus moving. One-shot announcement (not a stream), so a single
  // sendAnnouncement is correct.
  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  String _announcement(NtpResult result) {
    if (result.isError) return 'Time check failed';
    final NtpReading r = result.reading!;
    return '${_offsetVerdict(r.offsetMs).word}. '
        'Round-trip delay ${r.delayMs} milliseconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Server (NTP)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a reading
        // resolves; copies a plain-text report including the offset verdict WORD
        // (the on-screen color is the carrier on screen; the word in the text).
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the reading as a labeled plain-text report. Null
  /// (→ disabled affordance) while loading, before any query, or on a failure
  /// (nothing trustworthy to keep).
  String? _buildCopyText() {
    if (_loading) return null;
    final NtpResult? res = _result;
    if (res == null || res.isError || res.reading == null) return null;
    final NtpReading r = res.reading!;

    final StringBuffer buf = StringBuffer()
      ..writeln('Time Server (NTP)')
      ..writeln('Server: ${res.server}');
    if (res.resolvedIp != null) {
      buf.writeln('Resolved IP: ${res.resolvedIp}');
    }
    buf
      ..writeln('Stratum: ${r.stratum} — ${_stratumMeaning(r.stratum)}')
      ..writeln('Server time (UTC): ${_fmtUtc(r.serverUtc)}')
      ..writeln('Server time (local): ${_fmtLocal(r.serverUtc.toLocal())}')
      ..writeln('Your device time: ${_fmtLocal(r.deviceTime.toLocal())}')
      ..writeln(
          'Clock offset: ${_signedMs(r.offsetMs)} — ${_offsetVerdict(r.offsetMs).word}')
      ..writeln('Round-trip delay: ${r.delayMs} ms');
    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.ntpSupported) {
      return NetworkUnavailableView(
        toolName: 'Time Server (NTP)',
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
                children: <Widget>[
                  _queryCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _resultsSection(context),
                  ToolHelpFooter(toolId: 'ntp-time'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _queryCard(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final bool onFallback = _serverCtrl.text.trim() == kFallbackNtpServer;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LabeledField(
            label: 'NTP server',
            field: TextField(
              controller: _serverCtrl,
              focusNode: _serverFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              onChanged: (_) => setState(() {}),
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(
                hintText: kDefaultNtpServer,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _loading ? null : _run,
            child: _loading
                ? const _ButtonSpinner()
                : const Text('Check time'),
          ),
          // One-tap switch to the documented public fallback. Hidden once the
          // field already holds it.
          if (!onFallback) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: _loading ? null : _useFallback,
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Use $kFallbackNtpServer'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    final NtpResult? res = _result;
    if (res == null) return const SizedBox.shrink();
    if (res.isError) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Time check failed',
        body: res.errorMessage!,
      );
    }
    return _ReadingCard(result: res);
  }

  // ── Formatting + verdict helpers (shared by the card and the copy payload) ──

  /// Signed milliseconds with an explicit sign, e.g. "+42 ms" / "-7 ms".
  static String _signedMs(int ms) => '${ms >= 0 ? '+' : ''}$ms ms';

  /// The plain-language clock-offset verdict. Positive offset = the device is
  /// BEHIND the server (server ahead); negative = device AHEAD. A small window
  /// around zero reads as "in sync" so sub-perceptible jitter is not alarmed.
  static _OffsetVerdict _offsetVerdict(int offsetMs) {
    final int mag = offsetMs.abs();
    if (mag <= 50) {
      return _OffsetVerdict(
        kind: StatusChipKind.good,
        word: 'Your clock is in sync',
      );
    }
    // Behind/ahead wording + heads-up vs issue by magnitude. >2 s is a real
    // problem (TLS, Kerberos, 802.1X EAP can all break); <=2 s is a heads-up.
    final String dir = offsetMs > 0 ? 'behind' : 'ahead';
    final StatusChipKind kind =
        mag > 2000 ? StatusChipKind.issue : StatusChipKind.headsUp;
    return _OffsetVerdict(
      kind: kind,
      word: 'Your clock is ${_humanMs(mag)} $dir',
    );
  }

  /// Render a magnitude in ms as a compact human string: "42 ms", "1.3 s".
  static String _humanMs(int ms) {
    if (ms < 1000) return '$ms ms';
    final double s = ms / 1000.0;
    return '${s.toStringAsFixed(s >= 10 ? 0 : 1)} s';
  }

  /// Stratum → human meaning. Mirrors the NtpStratum reference data in
  /// datetime_standards_screen.dart (RFC 5905 §7.3), condensed to one line each
  /// so the row stays compact; kept local to avoid a cross-screen data import.
  static String _stratumMeaning(int stratum) {
    if (stratum == 0) return 'Unspecified / kiss-o\'-death (not a usable sync)';
    if (stratum == 1) return 'Primary server (synced to a reference clock)';
    if (stratum == 2) return 'Secondary server (synced to a stratum-1 server)';
    if (stratum >= 3 && stratum <= 15) {
      return 'Synced to a stratum-${stratum - 1} server';
    }
    if (stratum == 16) return 'Unsynchronized';
    return 'Reserved';
  }

  static String _fmtUtc(DateTime utc) =>
      '${_isoDate(utc)} ${_isoTime(utc)} UTC';

  static String _fmtLocal(DateTime local) =>
      '${_isoDate(local)} ${_isoTime(local)}';

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _isoTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}:'
      '${d.second.toString().padLeft(2, '0')}.'
      '${d.millisecond.toString().padLeft(3, '0')}';
}

/// A resolved offset verdict: the StatusChip kind + the plain-language word.
class _OffsetVerdict {
  const _OffsetVerdict({required this.kind, required this.word});
  final StatusChipKind kind;
  final String word;
}

/// In-button progress spinner. Factored out so the button child can be const
/// where possible.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: colors.onPrimary,
      ),
    );
  }
}

/// The success card: the SNTP reading laid out as labeled rows. Identifiers
/// (IP) render in Roboto Mono and numerics (offset, delay, timestamps) in
/// DM Mono per GL-003 §8.5. The offset row carries a StatusChip verdict
/// (word + glyph + hue, never color-only — §8.13).
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.result});

  final NtpResult result;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final NtpReading r = result.reading!;
    final _OffsetVerdict verdict = _NtpScreenState._offsetVerdict(r.offsetMs);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            result.server,
            style: text.labelMedium?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (result.resolvedIp != null)
            _IdentifierRow(label: 'Resolved IP', value: result.resolvedIp!),
          _PlainRow(
            label: 'Stratum',
            value:
                '${r.stratum} — ${_NtpScreenState._stratumMeaning(r.stratum)}',
          ),
          _NumericRow(
            label: 'Server time (UTC)',
            value: _NtpScreenState._fmtUtc(r.serverUtc),
          ),
          _NumericRow(
            label: 'Server time (local)',
            value: _NtpScreenState._fmtLocal(r.serverUtc.toLocal()),
          ),
          _NumericRow(
            label: 'Your device time',
            value: _NtpScreenState._fmtLocal(r.deviceTime.toLocal()),
          ),
          const Divider(height: AppSpacing.md),
          // Clock offset — the headline verdict. The signed number stays in
          // DM Mono; the StatusChip beside it carries the plain-language word so
          // the verdict is never color-only (§8.13 / WCAG 1.4.1).
          _OffsetRow(
            signed: _NtpScreenState._signedMs(r.offsetMs),
            verdict: verdict,
          ),
          _NumericRow(
            label: 'Round-trip delay',
            value: '${r.delayMs} ms',
          ),
        ],
      ),
    );
  }
}

/// A label/value row whose value is an IDENTIFIER (IP) → Roboto Mono, selectable
/// (GL-003 §8.5).
class _IdentifierRow extends StatelessWidget {
  const _IdentifierRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono.robotoMono.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value row whose value is a NUMERIC readout (timestamps, delay) →
/// DM Mono inline (GL-003 §8.5), selectable.
class _NumericRow extends StatelessWidget {
  const _NumericRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono.inlineCode.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value row whose value is plain prose (stratum meaning).
class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: text.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The clock-offset row: the signed magnitude (DM Mono) plus the plain-language
/// StatusChip verdict. The chip itself is decorative at the semantics layer
/// (ExcludeSemantics inside StatusChip), so the row carries the spoken label.
class _OffsetRow extends StatelessWidget {
  const _OffsetRow({required this.signed, required this.verdict});

  final String signed;
  final _OffsetVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Semantics(
      // Spoken once, plain-language, sign-free: the verdict word carries it.
      label: '${verdict.word}, offset $signed',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 140,
              child: Text(
                'Clock offset',
                style:
                    text.labelMedium?.copyWith(color: colors.textSecondary),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    signed,
                    style: mono.outputMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  StatusChip(kind: verdict.kind, word: verdict.word),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The error / message card (timeout, DNS, short reply, kiss-o'-death).
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
        children: <Widget>[
          Icon(icon, size: 20, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
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
