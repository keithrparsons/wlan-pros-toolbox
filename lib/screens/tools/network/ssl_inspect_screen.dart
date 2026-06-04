// SSL/TLS Certificate Inspector — connect to host:port over TLS and show the
// server certificate as inspectable data, including EXPIRED / self-signed certs.
//
// States (SOP-007 §5):
//  - idle     → form only, no result panel.
//  - loading  → handshake in flight; button shows progress, inputs disabled.
//  - success  → certificate cards (subject/issuer/validity/SAN/fingerprints).
//  - error    → connection / handshake failure with a precise message.
//  - disabled → "Inspect" disabled until a host is entered.
//  - web      → NetworkUnavailableView (browsers cannot do raw TLS inspection).
//
// A *bad* certificate (expired, self-signed) is NOT an error here — it renders
// as a successful inspection with a clear validity verdict (icon + text, never
// color-only, since status colors are §8.4 v1.1-deferred).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/ssl_inspect_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_action.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class SslInspectScreen extends StatefulWidget {
  const SslInspectScreen({super.key, this.service});

  final SslInspectService? service;

  @override
  State<SslInspectScreen> createState() => _SslInspectScreenState();
}

class _SslInspectScreenState extends State<SslInspectScreen> {
  late final SslInspectService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _portCtrl = TextEditingController(
    text: '${SslInspectService.defaultPort}',
  );
  final FocusNode _hostFocus = FocusNode();

  bool _loading = false;
  bool _canRun = false;
  SslInspectResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SslInspectService();
    _hostCtrl.addListener(_recomputeCanRun);
  }

  void _recomputeCanRun() {
    final bool can = _hostCtrl.text.trim().isNotEmpty;
    if (can != _canRun) setState(() => _canRun = can);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading || !_canRun) return;
    _hostFocus.unfocus();
    final int port =
        int.tryParse(_portCtrl.text.trim()) ?? SslInspectService.defaultPort;
    setState(() => _loading = true);
    final SslInspectResult result = await _service.inspect(
      rawHost: _hostCtrl.text,
      port: port,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    // WCAG 4.1.3 — announce the outcome so AT users learn the result landed.
    final String announcement;
    if (result.isError) {
      announcement = 'Inspection failed';
    } else {
      final CertValidity v = result.certificate!.validity;
      announcement = switch (v.state) {
        CertValidityState.valid => 'Certificate retrieved, currently valid',
        CertValidityState.expired => 'Certificate retrieved, expired',
        CertValidityState.notYetValid => 'Certificate retrieved, not yet valid',
      };
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
      appBar: AppBar(
        title: const Text('Inspector (SSL/TLS)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a successful
        // inspection has produced a certificate; copies the cert as a labeled
        // text block. Copy leads; this screen has no help icon.
        // §8.16 order: copy LEADS, help TRAILS.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
          const ToolHelpAction(toolId: 'ssl-inspect'),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the inspected certificate as a labeled text block.
  ///
  /// Returns null (→ disabled affordance) until a successful inspection holds a
  /// certificate: idle, loading, and a failed handshake all have nothing to
  /// keep. The validity VERDICT word (Currently valid / EXPIRED / Not yet valid)
  /// leads the block — it is the on-screen status the §8.16 content contract
  /// requires in the clipboard, since the screen carries it with an icon + word
  /// and the plain text must keep the word. Missing optional fields are written
  /// as "Unavailable" (never blank/fabricated, GL-005).
  String? _buildCopyText() {
    final SslInspectResult? r = _result;
    if (_loading || r == null || r.isError || r.certificate == null) {
      return null;
    }
    final InspectedCertificate cert = r.certificate!;
    final CertValidity v = cert.validity;

    String val(String? s) =>
        (s == null || s.trim().isEmpty) ? 'Unavailable' : s;
    String fmtUtc(DateTime d) {
      final DateTime u = d.toUtc();
      String p2(int n) => n.toString().padLeft(2, '0');
      return '${u.year}-${p2(u.month)}-${p2(u.day)} '
          '${p2(u.hour)}:${p2(u.minute)} UTC';
    }

    final (String verdictWord, String validityDetail) = switch (v.state) {
      CertValidityState.valid => (
        'Currently valid',
        v.daysToExpiry == 0
            ? 'Expires today'
            : 'Expires in ${v.daysToExpiry} day'
                  '${v.daysToExpiry == 1 ? '' : 's'}',
      ),
      CertValidityState.expired => (
        'EXPIRED',
        'Expired ${v.daysToExpiry.abs()} day'
            '${v.daysToExpiry.abs() == 1 ? '' : 's'} ago',
      ),
      CertValidityState.notYetValid => (
        'Not yet valid',
        'Becomes valid ${fmtUtc(v.notBefore)}',
      ),
    };

    final String? keyLine =
        (cert.publicKeyAlgorithm == null && cert.publicKeyBits == null)
        ? null
        : (cert.publicKeyAlgorithm != null && cert.publicKeyBits != null)
        ? '${cert.publicKeyAlgorithm} · ${cert.publicKeyBits}-bit'
        : (cert.publicKeyAlgorithm ?? '${cert.publicKeyBits}-bit');

    final StringBuffer buf = StringBuffer()
      ..writeln('SSL/TLS Certificate')
      // The VERDICT word leads (§8.16 content contract).
      ..writeln('Validity: $verdictWord ($validityDetail)')
      ..writeln('Not before: ${fmtUtc(v.notBefore)}')
      ..writeln('Not after: ${fmtUtc(v.notAfter)}')
      ..writeln()
      ..writeln('Subject')
      ..writeln('  Common name: ${val(cert.subjectCommonName)}')
      ..writeln('  Organization: ${val(cert.subjectOrg)}');
    for (final DnField f in cert.subjectFields) {
      buf.writeln('  ${f.label}: ${f.value}');
    }
    buf
      ..writeln()
      ..writeln('Issuer')
      ..writeln('  Common name: ${val(cert.issuerCommonName)}')
      ..writeln('  Organization: ${val(cert.issuerOrg)}');
    for (final DnField f in cert.issuerFields) {
      buf.writeln('  ${f.label}: ${f.value}');
    }

    buf.writeln();
    if (cert.subjectAltNames.isEmpty) {
      buf.writeln('Subject alternative names: None listed');
    } else {
      buf.writeln('Subject alternative names (${cert.subjectAltNames.length})');
      for (final String s in cert.subjectAltNames) {
        buf.writeln('  $s');
      }
    }

    buf
      ..writeln()
      ..writeln('Key and signature')
      ..writeln('  Public key: ${val(keyLine)}')
      ..writeln('  Signature: ${val(cert.signatureAlgorithm)}')
      ..writeln('  Serial: ${val(cert.serialNumber)}')
      ..writeln()
      ..writeln('Fingerprints')
      ..writeln('  SHA-256: ${val(cert.sha256Fingerprint)}')
      ..writeln('  SHA-1: ${val(cert.sha1Fingerprint)}')
      ..writeln()
      ..writeln('Connection')
      ..writeln('  Host: ${r.host}')
      ..writeln('  Port: ${r.port}')
      ..writeln(
        '  Handshake: ${r.handshakeMs == null ? 'Unavailable' : '${r.handshakeMs} ms'}',
      )
      ..writeln('  ALPN: ${val(r.alpn)}')
      ..writeln()
      ..writeln(SslInspectResult.chainNote);

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.sslInspectSupported) {
      return NetworkUnavailableView(
        toolName: 'SSL/TLS Certificate Inspector',
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
                    toolId: 'ssl-inspect',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('ssl-inspect'))
                    const SizedBox(height: AppSpacing.md),
                  _queryCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _resultsSection(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _queryCard(BuildContext context) {
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
          LabeledField(
            label: 'Host',
            field: TextField(
              controller: _hostCtrl,
              focusNode: _hostFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(hintText: 'example.com'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Port',
            field: SizedBox(
              width: 120,
              child: TextField(
                controller: _portCtrl,
                enabled: !_loading,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _run(),
                cursorColor: AppColors.primary,
                decoration: const InputDecoration(hintText: '443'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: (_loading || !_canRun) ? null : _run,
            child: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: Semantics(
                      label: 'Inspecting certificate…',
                      liveRegion: true,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                : const Text('Inspect'),
          ),
        ],
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    final SslInspectResult? r = _result;
    if (r == null) return const SizedBox.shrink();
    if (r.isError) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Inspection failed',
        body: r.errorMessage!,
      );
    }
    return _CertificateView(result: r);
  }
}

class _CertificateView extends StatelessWidget {
  const _CertificateView({required this.result});

  final SslInspectResult result;

  @override
  Widget build(BuildContext context) {
    final InspectedCertificate cert = result.certificate!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ValidityCard(validity: cert.validity),
        const SizedBox(height: AppSpacing.sm),
        _DnCard(
          title: 'Subject',
          commonName: cert.subjectCommonName,
          organization: cert.subjectOrg,
          fields: cert.subjectFields,
        ),
        const SizedBox(height: AppSpacing.sm),
        _DnCard(
          title: 'Issuer',
          commonName: cert.issuerCommonName,
          organization: cert.issuerOrg,
          fields: cert.issuerFields,
        ),
        const SizedBox(height: AppSpacing.sm),
        _SanCard(sans: cert.subjectAltNames),
        const SizedBox(height: AppSpacing.sm),
        _SectionCard(
          title: 'Key and signature',
          children: <Widget>[
            ValueRow(
              label: 'Public key',
              value: _keyLine(cert.publicKeyAlgorithm, cert.publicKeyBits),
            ),
            ValueRow(label: 'Signature', value: cert.signatureAlgorithm),
            ValueRow(
              label: 'Serial',
              value: cert.serialNumber,
              identifier: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _FingerprintCard(
          sha256: cert.sha256Fingerprint,
          sha1: cert.sha1Fingerprint,
        ),
        const SizedBox(height: AppSpacing.sm),
        _ConnectionCard(result: result),
        if (cert.pem.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _PemCard(pem: cert.pem),
        ],
        const SizedBox(height: AppSpacing.sm),
        _ChainNoteCard(),
      ],
    );
  }

  static String? _keyLine(String? alg, int? bits) {
    if (alg == null && bits == null) return null;
    if (alg != null && bits != null) return '$alg · $bits-bit';
    return alg ?? '$bits-bit';
  }
}

/// Validity verdict — icon + text, never color-only (WCAG 1.4.1; status colors
/// are §8.4 v1.1-deferred, so the surface uses neutral tokens + an explicit
/// icon and word for "expired" / "valid" / "not yet valid").
class _ValidityCard extends StatelessWidget {
  const _ValidityCard({required this.validity});

  final CertValidity validity;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    final (
      IconData icon,
      String verdict,
      String detail,
    ) = switch (validity.state) {
      CertValidityState.valid => (
        Icons.verified_outlined,
        'Currently valid',
        validity.daysToExpiry == 0
            ? 'Expires today'
            : 'Expires in ${validity.daysToExpiry} day'
                  '${validity.daysToExpiry == 1 ? '' : 's'}',
      ),
      CertValidityState.expired => (
        Icons.report_gmailerrorred_outlined,
        'EXPIRED',
        'Expired ${validity.daysToExpiry.abs()} day'
            '${validity.daysToExpiry.abs() == 1 ? '' : 's'} ago',
      ),
      CertValidityState.notYetValid => (
        Icons.schedule_outlined,
        'Not yet valid',
        'Becomes valid ${_fmtDate(validity.notBefore)}',
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Neutral icon color; meaning carried by icon shape + the word.
              Icon(icon, size: 24, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  verdict,
                  style: text.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget notBefore = _DatePair(
                label: 'Not before',
                value: _fmtDateTime(validity.notBefore),
                mono: mono,
              );
              final Widget notAfter = _DatePair(
                label: 'Not after',
                value: _fmtDateTime(validity.notAfter),
                mono: mono,
              );
              // Each "YYYY-MM-DD HH:MM UTC" value needs room to render in DM
              // Mono without truncating. Below this width the side-by-side Row
              // crowds them, so stack vertically (LOW-2 fix).
              const double sideBySideFloor = 280;
              if (constraints.maxWidth < sideBySideFloor) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    notBefore,
                    const SizedBox(height: AppSpacing.xs),
                    notAfter,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: notBefore),
                  Expanded(child: notAfter),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final DateTime u = d.toUtc();
    return '${u.year}-${_pad2(u.month)}-${_pad2(u.day)} UTC';
  }

  static String _fmtDateTime(DateTime d) {
    final DateTime u = d.toUtc();
    return '${u.year}-${_pad2(u.month)}-${_pad2(u.day)} '
        '${_pad2(u.hour)}:${_pad2(u.minute)} UTC';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

class _DatePair extends StatelessWidget {
  const _DatePair({
    required this.label,
    required this.value,
    required this.mono,
  });

  final String label;
  final String value;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: mono.inlineCode.copyWith(
            color: AppColors.textPrimary,
            fontSize: AppTextSize.caption,
          ),
        ),
      ],
    );
  }
}

/// Subject / Issuer card. The default view shows the two headline fields
/// (Common name, Organization) exactly as before; the full structured DN
/// (CN, O, OU, L, ST, C, and any other parsed attributes) is one tap away
/// behind a "Show full subject"/"Show full issuer" disclosure so the card
/// stays clean.
class _DnCard extends StatefulWidget {
  const _DnCard({
    required this.title,
    required this.commonName,
    required this.organization,
    required this.fields,
  });

  final String title;
  final String? commonName;
  final String? organization;
  final List<DnField> fields;

  @override
  State<_DnCard> createState() => _DnCardState();
}

class _DnCardState extends State<_DnCard> {
  bool _expanded = false;

  /// Fields beyond the CN/O already shown in the summary rows. We still render
  /// the full DN in the detail block (including CN/O) so the disclosure is a
  /// complete, copyable record, not a partial one.
  bool get _hasDetail => widget.fields.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return _SectionShell(
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ValueRow(label: 'Common name', value: widget.commonName),
          ValueRow(label: 'Organization', value: widget.organization),
          if (_hasDetail) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _DisclosureButton(
              expanded: _expanded,
              // The detail is the full Distinguished Name for this section.
              semanticsLabel: _expanded
                  ? 'Hide full ${widget.title.toLowerCase()} details'
                  : 'Show full ${widget.title.toLowerCase()} details',
              label: _expanded
                  ? 'Hide full ${widget.title.toLowerCase()}'
                  : 'Show full ${widget.title.toLowerCase()}',
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            if (_expanded) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.xs),
              ...widget.fields.map(
                (DnField f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 48,
                        child: Text(
                          f.label,
                          style: text.labelMedium?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: SelectableText(
                          f.value,
                          style: mono.inlineCode.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: AppTextSize.caption,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A tertiary-text disclosure toggle (chevron + label) with a real semantics
/// label and a 48dp-minimum hit region. Used to expand the full DN detail.
class _DisclosureButton extends StatelessWidget {
  const _DisclosureButton({
    required this.expanded,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final bool expanded;
  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.control),
        // §8.9 — the app-wide §8.3 pass cleared the global `focusColor` to
        // transparent, which removed the ambient keyboard-focus affordance
        // from this bare InkWell. This row is a chevron + label with no
        // bordered container to swap a ring onto, so restore a visible focus
        // overlay locally with an explicit lime focusColor (16% alpha — the
        // §8.3 pressed-overlay value). Keeps SC 2.4.7 without re-introducing a
        // global non-transparent focusColor.
        focusColor: AppColors.primary.withValues(alpha: 0.16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: text.bodyLarge?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Raw leaf certificate in PEM, with a Copy-to-clipboard affordance. The PEM is
/// long, so it renders in a bounded, vertically scrollable DM Mono block that
/// wraps without horizontal overflow at 375px. Copy feedback flips the button
/// to a "Copied" state and announces via SemanticsService for AT users.
class _PemCard extends StatefulWidget {
  const _PemCard({required this.pem});

  final String pem;

  @override
  State<_PemCard> createState() => _PemCardState();
}

class _PemCardState extends State<_PemCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.pem));
    if (!mounted) return;
    setState(() => _copied = true);
    // WCAG 4.1.3 — announce the status change for screen-reader users.
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Certificate PEM copied to clipboard',
      TextDirection.ltr,
    );
    // Revert the inline "Copied" affordance after a moment so a later copy
    // reads as a fresh action.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return _SectionShell(
      title: 'PEM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Bounded, scrollable mono block — long PEM stays contained and wraps
          // at narrow widths without horizontal overflow.
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.surface0,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.pem.trim(),
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: AppTextSize.caption,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            // A single accessible name on the button (no nested Semantics) —
            // the visible label IS the affordance text, and it flips to
            // "Copied" on success. Theme gives it a 48dp minimum target.
            child: OutlinedButton.icon(
              onPressed: _copy,
              icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 20),
              label: Text(
                _copied ? 'Copied' : 'Copy PEM',
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
                semanticsLabel: _copied
                    ? 'Certificate PEM copied to clipboard'
                    : 'Copy certificate PEM to clipboard',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SanCard extends StatelessWidget {
  const _SanCard({required this.sans});

  final List<String> sans;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return _SectionShell(
      title:
          'Subject alternative names'
          '${sans.isEmpty ? '' : ' (${sans.length})'}',
      child: sans.isEmpty
          ? Text(
              'None listed on this certificate.',
              style: text.bodyLarge?.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sans
                  .map(
                    (String s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SelectableText(
                        s,
                        // SANs are DNS-name / IP identifiers → Roboto Mono
                        // (GL-003 §8.5 identifier rule), not DM Mono.
                        style: mono.robotoMono.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _FingerprintCard extends StatelessWidget {
  const _FingerprintCard({required this.sha256, required this.sha1});

  final String? sha256;
  final String? sha1;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: 'Fingerprints',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Fingerprint(label: 'SHA-256', value: sha256),
          const SizedBox(height: AppSpacing.xs),
          _Fingerprint(label: 'SHA-1', value: sha1),
        ],
      ),
    );
  }
}

class _Fingerprint extends StatelessWidget {
  const _Fingerprint({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final bool available = value != null && value!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: 2),
        SelectableText(
          available ? value! : 'Not available on this platform',
          style: available
              // Hex fingerprint (SHA-256 / SHA-1) is an identifier → Roboto
              // Mono (GL-003 §8.5), not DM Mono.
              ? mono.robotoMono.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: AppTextSize.caption,
                )
              : (text.bodyLarge ?? const TextStyle()).copyWith(
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.result});

  final SslInspectResult result;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Connection',
      children: <Widget>[
        ValueRow(label: 'Host', value: result.host, identifier: true),
        ValueRow(label: 'Port', value: '${result.port}', mono: true),
        ValueRow(
          label: 'Handshake',
          value: result.handshakeMs == null ? null : '${result.handshakeMs} ms',
          mono: true,
        ),
        ValueRow(
          label: 'ALPN',
          // dart:io exposes only the ALPN result — NOT the TLS version or
          // cipher suite. Labeled precisely so it is never mistaken for either.
          value: result.alpn,
        ),
      ],
    );
  }
}

class _ChainNoteCard extends StatelessWidget {
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
          Icon(Icons.info_outline, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leaf certificate only',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  SslInspectResult.chainNote,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'TLS protocol version and cipher suite are not exposed by '
                  'the platform TLS API and are therefore not shown.',
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
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

/// A titled surface card whose body is a list of [ValueRow]s.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// A titled surface card with arbitrary [child] body. Shared shell so every
/// card matches the network-tool card pattern (surface1 + decorative border).
class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.title, required this.child});

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
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
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
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
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
