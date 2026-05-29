// BGP / ASN Lookup tool — resolve an IP or ASN to its routing/registry data
// via the RIPEstat Data API (keyless, HTTPS — see BgpAsnService).
//
// States (SOP-007 §5):
//  - idle     → form only, no results panel yet.
//  - loading  → query in flight; button shows progress, input disabled.
//  - success  → ASN, holder, prefix, registry, type, neighbour counts.
//  - empty    → API answered but resolved no ASN (e.g. a bogon/private IP).
//  - error    → bad input / timeout / rate-limit / transport, precise message.
//  - disabled → "Look up" disabled until a query is entered.
//  - web      → NetworkUnavailableView (native-only; CORS unverified).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../services/network/bgp_asn_service.dart';
import '../../../services/network/network_support.dart';
import '../../../theme/app_tokens.dart';
import '../labeled_field.dart';
import 'error_card.dart';
import 'network_unavailable_view.dart';
import 'value_row.dart';

class BgpAsnScreen extends StatefulWidget {
  const BgpAsnScreen({super.key, this.service});

  final BgpAsnService? service;

  @override
  State<BgpAsnScreen> createState() => _BgpAsnScreenState();
}

class _BgpAsnScreenState extends State<BgpAsnScreen> {
  late final BgpAsnService _service;
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  bool _loading = false;
  bool _canRun = false;
  BgpAsnResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BgpAsnService();
    _queryCtrl.addListener(_recomputeCanRun);
  }

  void _recomputeCanRun() {
    final bool can = _queryCtrl.text.trim().isNotEmpty;
    if (can != _canRun) setState(() => _canRun = can);
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading || !_canRun) return;
    _queryFocus.unfocus();
    setState(() => _loading = true);
    final BgpAsnResult result = await _service.lookup(rawQuery: _queryCtrl.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    final String announcement;
    if (result.isError) {
      announcement = 'BGP lookup failed';
    } else if (result.isEmpty) {
      announcement = 'No routing data found';
    } else {
      announcement = 'Routing data retrieved';
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
      appBar: AppBar(title: const Text('BGP / ASN'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (!NetworkSupport.bgpAsnSupported) {
      return NetworkUnavailableView(
        toolName: 'BGP / ASN Lookup',
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
            label: 'IP address or ASN',
            field: TextField(
              controller: _queryCtrl,
              focusNode: _queryFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              cursorColor: AppColors.primary,
              decoration:
                  const InputDecoration(hintText: '8.8.8.8  or  AS15169'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Data from the RIPEstat API. No account or key required.',
            style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: (_loading || !_canRun) ? null : _run,
            child: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: Semantics(
                      label: 'Looking up routing data…',
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
    final BgpAsnResult? r = _result;
    if (r == null) return const SizedBox.shrink();
    if (r.isError) {
      return LookupErrorCard(
        errorKind: r.errorKind,
        message: r.errorMessage!,
        onRetry: _run,
      );
    }
    if (r.isEmpty) {
      return _MessageCard(
        icon: Icons.search_off,
        title: 'No routing data',
        body: 'RIPEstat returned no ASN or prefix for ${r.query}. The address '
            'may be private, reserved, or not currently announced in the global '
            'routing table.',
      );
    }
    return _ResultCard(result: r);
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final BgpAsnResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final BgpAsnResult r = result;
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
          Text(
            r.kind == BgpQueryKind.asn ? 'AS overview' : 'Routing for ${r.query}',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ValueRow(label: 'ASN', value: r.asn, mono: true, emphasize: true),
          ValueRow(label: 'Holder', value: r.holder),
          ValueRow(
            label: 'Announced prefix',
            value: r.announcedPrefix,
            mono: true,
          ),
          ValueRow(label: 'Registry', value: r.registry),
          ValueRow(label: 'AS type', value: r.asnType),
          ValueRow(
            label: 'In routing table',
            value: r.isAnnounced == null
                ? null
                : (r.isAnnounced! ? 'Yes — announced' : 'No — not announced'),
          ),
          if (r.kind == BgpQueryKind.asn) ...[
            ValueRow(
              label: 'Upstreams',
              value: r.upstreamCount?.toString(),
              mono: true,
            ),
            ValueRow(
              label: 'Peers',
              value: r.peerCount?.toString(),
              mono: true,
            ),
            ValueRow(
              label: 'Downstreams',
              value: r.downstreamCount?.toString(),
              mono: true,
            ),
          ],
          if (r.relatedAsns.isNotEmpty)
            ValueRow(
              label: 'Other ASNs',
              value: r.relatedAsns.join(', '),
              mono: true,
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
