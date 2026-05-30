// DNS Lookup tool — query A, AAAA, MX, TXT, NS, SOA, PTR (rDNS) over DoH.
//
// States (SOP-007 §5):
//  - idle     → form only, no results panel yet.
//  - loading  → query in flight; button shows progress, input disabled.
//  - success  → records list (mono values).
//  - empty    → resolved but no records of that type for the name.
//  - error    → bad input / lookup failure with the resolver's message.
//  - web       → NetworkUnavailableView (brief §15).
//
// Resolver is selectable (Cloudflare default, Google failover) so a blocked
// resolver is one tap away. PTR auto-detects an IP input.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/dns_lookup_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class DnsLookupScreen extends StatefulWidget {
  const DnsLookupScreen({super.key, this.service});

  final DnsLookupService? service;

  @override
  State<DnsLookupScreen> createState() => _DnsLookupScreenState();
}

class _DnsLookupScreenState extends State<DnsLookupScreen> {
  late final DnsLookupService _service;
  final TextEditingController _hostCtrl = TextEditingController();
  final FocusNode _hostFocus = FocusNode();

  DnsRecordType _type = DnsRecordType.a;
  DohResolver _resolver = DohResolver.cloudflare;

  bool _loading = false;
  DnsLookupResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DnsLookupService();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _hostFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading) return;
    _hostFocus.unfocus();
    setState(() => _loading = true);
    final DnsLookupResult result = await _service.lookup(
      rawQuery: _hostCtrl.text,
      type: _type,
      resolver: _resolver,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    // WCAG 4.1.3 — announce the outcome so AT users learn results landed
    // without the focus moving. Copy mirrors the on-screen result cards.
    final String announcement;
    if (result.isError) {
      announcement = 'Lookup failed';
    } else if (result.isEmpty) {
      announcement = 'No ${result.type.label} records found';
    } else {
      final int n = result.records.length;
      announcement =
          '$n ${result.type.label} record${n == 1 ? '' : 's'} found';
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
      appBar: AppBar(title: const Text('DNS Lookup'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (!NetworkSupport.dnsLookupSupported) {
      return NetworkUnavailableView(
        toolName: 'DNS Lookup',
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
                    toolId: 'dns-lookup',
                    isDesktop: isDesktop,
                  ),
                  if (ToolAssets.hasGraphic('dns-lookup'))
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
    final bool isPtr = _type == DnsRecordType.ptr;

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
            label: isPtr ? 'IP address' : 'Hostname',
            field: TextField(
              controller: _hostCtrl,
              focusNode: _hostFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: isPtr ? '8.8.8.8' : 'example.com',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Record type',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: DnsRecordType.values.map((DnsRecordType t) {
              final bool selected = t == _type;
              return ChoiceChip(
                label: Text(t.label),
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
                // WCAG 2.5.8 / §8.3 — guarantee ≥48dp hit region.
                materialTapTargetSize: MaterialTapTargetSize.padded,
                // §8.3 — shared resolver: idle/selected/disabled borders plus
                // the 2px lime keyboard-focus ring.
                side: AppTheme.chipSide(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                onSelected: _loading
                    ? null
                    : (_) => setState(() => _type = t),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Resolver',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: DohResolver.values.map((DohResolver r) {
              final bool selected = r == _resolver;
              return ChoiceChip(
                label: Text(r.label),
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
                // WCAG 2.5.8 / §8.3 — guarantee ≥48dp hit region.
                materialTapTargetSize: MaterialTapTargetSize.padded,
                // §8.3 — shared resolver: idle/selected/disabled borders plus
                // the 2px lime keyboard-focus ring.
                side: AppTheme.chipSide(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                onSelected: _loading
                    ? null
                    : (_) => setState(() => _resolver = r),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _loading ? null : _run,
            child: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    // WCAG 4.1.3 — announce the in-flight lookup to AT.
                    // `Semantics` is not const, so SizedBox can't be const here.
                    child: Semantics(
                      label: 'Looking up…',
                      liveRegion: true,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.secondary,
                      ),
                    ),
                  )
                : const Text('Look up'),
          ),
        ],
      ),
    );
  }

  Widget _resultsSection(BuildContext context) {
    final DnsLookupResult? r = _result;
    if (r == null) {
      return const SizedBox.shrink();
    }
    if (r.isError) {
      return _MessageCard(
        icon: Icons.error_outline,
        title: 'Lookup failed',
        body: r.errorMessage!,
      );
    }
    if (r.isEmpty) {
      return _MessageCard(
        icon: Icons.search_off,
        title: 'No records',
        body: 'No ${r.type.label} records found for ${r.queriedName}.',
      );
    }
    return _RecordsCard(result: r);
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.result});

  final DnsLookupResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

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
            '${result.records.length} ${result.type.label} '
            'record${result.records.length == 1 ? '' : 's'} '
            '· ${result.resolver.label}',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...result.records.map((DnsRecord rec) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      rec.type,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      _displayData(rec),
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (rec.ttl != null)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xs),
                      child: Text(
                        '${rec.ttl}s',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Render the record payload. SRV and CAA carry structured wire data, so
/// parse them into a readable one-liner; everything else shows the raw value.
String _displayData(DnsRecord rec) {
  if (rec.type == 'SRV') {
    final SrvData? srv = SrvData.parse(rec.data);
    if (srv != null) return srv.display;
  } else if (rec.type == 'CAA') {
    final CaaData? caa = CaaData.parse(rec.data);
    if (caa != null) return caa.display;
  }
  return rec.data;
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
