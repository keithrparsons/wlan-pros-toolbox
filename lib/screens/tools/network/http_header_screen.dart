// HTTP Header Inspector — issue a HEAD (default) or GET request, follow and
// SHOW the redirect chain hop-by-hop, then list the final status line and all
// response headers.
//
// States (SOP-007 §5):
//  - idle     → form only.
//  - loading  → request in flight; button progress, inputs disabled.
//  - success  → redirect chain + final status + headers (mono values).
//  - empty    → final response carried zero headers (rare but handled).
//  - error    → connection / protocol failure with a precise message.
//  - disabled → "Inspect" disabled until a URL is entered.
//  - web      → NetworkUnavailableView (CORS blocks reading arbitrary headers).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/http_header_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class HttpHeaderScreen extends StatefulWidget {
  const HttpHeaderScreen({super.key, this.service});

  final HttpHeaderService? service;

  @override
  State<HttpHeaderScreen> createState() => _HttpHeaderScreenState();
}

class _HttpHeaderScreenState extends State<HttpHeaderScreen> {
  late final HttpHeaderService _service;
  final TextEditingController _urlCtrl = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  HttpMethod _method = HttpMethod.head;
  bool _loading = false;
  bool _canRun = false;
  HttpHeaderResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HttpHeaderService();
    _urlCtrl.addListener(_recomputeCanRun);
  }

  void _recomputeCanRun() {
    final bool can = _urlCtrl.text.trim().isNotEmpty;
    if (can != _canRun) setState(() => _canRun = can);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading || !_canRun) return;
    _urlFocus.unfocus();
    setState(() => _loading = true);
    final HttpHeaderResult result = await _service.inspect(
      rawUrl: _urlCtrl.text,
      method: _method,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    final String announcement;
    if (result.isError) {
      announcement = 'Request failed';
    } else {
      final int hops = result.hops.length;
      final HttpHop? last = result.finalHop;
      announcement =
          'Completed with ${last?.statusCode ?? 0} after $hops hop'
          '${hops == 1 ? '' : 's'}';
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
        title: const Text('Inspector (HTTP Header)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a successful
        // request has produced a final hop; copies the status line, redirect
        // chain, and response headers as labeled text. Copy leads; no help icon.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the status line, redirect chain, and final response
  /// headers as a labeled text block (`Header: value` per line, §8.16 mapping
  /// for key:value response headers).
  ///
  /// Returns null (→ disabled affordance) until a successful request holds a
  /// final hop: idle, loading, and a failed request all have nothing to keep.
  /// The status line (`200 OK`) carries the request's outcome WORD into the
  /// clipboard. An empty header set is written honestly, never fabricated.
  String? _buildCopyText() {
    final HttpHeaderResult? r = _result;
    if (_loading || r == null || r.isError || r.finalHop == null) {
      return null;
    }
    final HttpHop last = r.finalHop!;
    final int hops = r.hops.length;
    final List<HttpHop> redirects = r.hops
        .where((HttpHop h) => h.isRedirect)
        .toList();

    final StringBuffer buf = StringBuffer()
      ..writeln('HTTP Header Inspection')
      ..writeln('Status: ${last.statusLine}')
      ..writeln(
        'Summary: $hops hop${hops == 1 ? '' : 's'} · ${r.totalMs} ms total · '
        '${last.method.label}',
      );
    if (r.headFellBackToGet) {
      buf.writeln(
        'Note: the server rejected HEAD (405); retried with GET so headers '
        'could be read.',
      );
    }
    if (r.redirectLimitHit) {
      buf.writeln(
        'Note: stopped after ${HttpHeaderService.defaultMaxRedirects} '
        'redirects — the chain may be a loop.',
      );
    }

    if (redirects.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Redirect chain');
      for (int i = 0; i < r.hops.length; i++) {
        final HttpHop h = r.hops[i];
        buf.writeln(
          '  ${i + 1}. ${h.method.label} · ${h.statusLine} · '
          '${h.elapsedMs} ms — ${h.url}',
        );
        if (h.location != null) buf.writeln('     → ${h.location}');
      }
    }

    buf.writeln();
    if (last.headers.isEmpty) {
      buf.writeln('Response headers: the final response carried no headers.');
    } else {
      buf.writeln('Response headers (${last.headers.length})');
      for (final HeaderEntry h in last.headers) {
        buf.writeln('${h.name}: ${h.value}');
      }
    }

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.httpHeadersSupported) {
      return NetworkUnavailableView(
        toolName: 'HTTP Header Inspector',
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
                    toolId: 'http-headers',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('http-headers'))
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
          LabeledField(
            label: 'URL',
            field: TextField(
              controller: _urlCtrl,
              focusNode: _urlFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _run(),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                hintText: 'https://example.com',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Method',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: HttpMethod.values.map((HttpMethod m) {
              final bool selected = m == _method;
              return ChoiceChip(
                label: Text(m.label),
                selected: selected,
                showCheckmark: false,
                labelStyle: text.labelMedium?.copyWith(
                  color: selected
                      ? AppColors.secondary
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface2,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                // §8.3 — shared resolver: idle/selected/disabled borders + 2px
                // lime keyboard-focus ring.
                side: AppTheme.chipSide(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                onSelected: _loading
                    ? null
                    : (_) => setState(() => _method = m),
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
                      label: 'Requesting…',
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
    final HttpHeaderResult? r = _result;
    if (r == null) return const SizedBox.shrink();
    if (r.isError) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Request failed',
        body: r.errorMessage!,
      );
    }
    return _ResponseView(result: r);
  }
}

class _ResponseView extends StatelessWidget {
  const _ResponseView({required this.result});

  final HttpHeaderResult result;

  @override
  Widget build(BuildContext context) {
    final HttpHop? finalHop = result.finalHop;
    final List<HttpHop> redirects = result.hops
        .where((HttpHop h) => h.isRedirect)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryCard(result: result),
        if (redirects.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _RedirectChainCard(hops: result.hops),
        ],
        if (finalHop != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _HeadersCard(hop: finalHop),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.result});

  final HttpHeaderResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final HttpHop? last = result.finalHop;
    final int hops = result.hops.length;

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
              Icon(
                Icons.swap_horiz_outlined,
                size: 24,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: SelectableText(
                  last?.statusLine ?? '—',
                  style: mono.outputMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$hops hop${hops == 1 ? '' : 's'} · ${result.totalMs} ms total'
            '${last == null ? '' : ' · ${last.method.label}'}',
            style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
          if (result.headFellBackToGet) ...[
            const SizedBox(height: AppSpacing.xs),
            _Note(
              icon: Icons.info_outline,
              text:
                  'The server rejected HEAD (405); retried with GET so '
                  'headers could be read.',
            ),
          ],
          if (result.redirectLimitHit) ...[
            const SizedBox(height: AppSpacing.xs),
            _Note(
              icon: Icons.warning_amber_outlined,
              text:
                  'Stopped after '
                  '${HttpHeaderService.defaultMaxRedirects} redirects — the '
                  'chain may be a loop.',
            ),
          ],
        ],
      ),
    );
  }
}

class _RedirectChainCard extends StatelessWidget {
  const _RedirectChainCard({required this.hops});

  final List<HttpHop> hops;

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Redirect chain',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < hops.length; i++)
            _HopRow(index: i + 1, hop: hops[i], isLast: i == hops.length - 1),
        ],
      ),
    );
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({required this.index, required this.hop, required this.isLast});

  final int index;
  final HttpHop hop;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  style: mono.inlineCode.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${hop.method.label} · ${hop.statusLine}'
                      ' · ${hop.elapsedMs} ms',
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      hop.url,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: AppTextSize.caption,
                      ),
                    ),
                    if (hop.location != null) ...[
                      const SizedBox(height: 2),
                      SelectableText(
                        '→ ${hop.location}',
                        style: mono.inlineCode.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: AppTextSize.caption,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeadersCard extends StatelessWidget {
  const _HeadersCard({required this.hop});

  final HttpHop hop;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    if (hop.headers.isEmpty) {
      return _Shell(
        title: 'Response headers',
        child: Text(
          'The final response carried no headers.',
          style: text.bodyLarge?.copyWith(
            color: AppColors.textTertiary,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    return _Shell(
      title: 'Response headers (${hop.headers.length})',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hop.headers.map((HeaderEntry h) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name,
                  style: text.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  h.value,
                  style: mono.inlineCode.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: AppTextSize.caption,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: t.labelMedium?.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child});

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
