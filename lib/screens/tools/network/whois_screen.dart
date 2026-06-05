// WHOIS tool — look up domain / IP registration data over WHOIS (TCP/43).
//
// States (SOP-007 §5):
//  - idle     → form only, no results panel yet.
//  - loading  → query in flight; button shows progress, input disabled.
//  - success  → parsed highlights + raw record (mono, selectable).
//  - empty    → server answered but the object is unregistered / no data.
//  - error    → bad input / connection / timeout with a precise message.
//  - disabled → "Look up" disabled until a query is entered.
//  - web      → NetworkUnavailableView (TCP/43 + RDAP both blocked in a browser).
//
// The lookup walks the referral chain (IANA → registry → optional registrar);
// the consulted servers are shown so the path is transparent.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/tool_assets.dart';
import '../../../services/network/network_support.dart';
import '../../../services/network/whois_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart';
import '../labeled_field.dart';
import 'network_unavailable_view.dart';

class WhoisScreen extends StatefulWidget {
  const WhoisScreen({super.key, this.service});

  final WhoisService? service;

  @override
  State<WhoisScreen> createState() => _WhoisScreenState();
}

class _WhoisScreenState extends State<WhoisScreen> {
  late final WhoisService _service;
  final TextEditingController _queryCtrl = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  bool _loading = false;
  bool _canRun = false;
  WhoisResult? _result;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WhoisService();
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
    final WhoisResult result = await _service.lookup(rawQuery: _queryCtrl.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });

    // WCAG 4.1.3 — announce the outcome without moving focus.
    final String announcement;
    if (result.isError) {
      announcement = 'WHOIS lookup failed';
    } else if (result.isEmpty) {
      announcement = 'No registration record found';
    } else {
      announcement = 'WHOIS record retrieved';
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
        title: const Text('WHOIS'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a record is
        // retrieved; copies the highlights, the consulted-server path, and the
        // raw record. Copy leads; this screen has no help icon.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the WHOIS record as a labeled plain-text block.
  ///
  /// Returns null (→ disabled affordance) while loading, before any lookup, on
  /// an error, or when the registry returned no record — none of those is a
  /// result worth keeping. The highlights are emitted as `Label: value` lines,
  /// the referral path as a "via" line, then the rendered raw record verbatim
  /// (the same text the on-screen raw-record card shows).
  String? _buildCopyText() {
    final WhoisResult? r = _result;
    if (_loading || r == null || r.isError || r.isEmpty) return null;

    final StringBuffer buf = StringBuffer()
      ..writeln('WHOIS')
      ..writeln('Query: ${r.query}');

    for (final WhoisHighlight h in r.highlights) {
      buf.writeln('${h.label}: ${h.value}');
    }
    if (r.serversQueried.isNotEmpty) {
      buf.writeln('Consulted: ${r.serversQueried.join(' → ')}');
    }
    buf
      ..writeln()
      ..writeln('Raw record')
      ..writeln(r.rawRecord.trim());

    return buf.toString().trimRight();
  }

  Widget _body() {
    if (!NetworkSupport.whoisSupported) {
      return NetworkUnavailableView(
        toolName: 'WHOIS',
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
                  ConceptGraphicBand(toolId: 'whois', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('whois'))
                    const SizedBox(height: AppSpacing.md),
                  _queryCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  _resultsSection(context),
                  ToolHelpFooter(toolId: 'whois'),
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
            label: 'Domain or IP address',
            field: TextField(
              controller: _queryCtrl,
              focusNode: _queryFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              cursorColor: colors.textAccent,
              decoration: const InputDecoration(hintText: 'example.com'),
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
                      label: 'Looking up WHOIS…',
                      liveRegion: true,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
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
    final WhoisResult? r = _result;
    if (r == null) return const SizedBox.shrink();
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
        title: 'No record',
        body:
            'No registration record found for ${r.query}. The domain may be '
            'unregistered, or the registry returned no data.',
      );
    }
    return _RecordView(result: r);
  }
}

class _RecordView extends StatelessWidget {
  const _RecordView({required this.result});

  final WhoisResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.highlights.isNotEmpty) ...[
          _HighlightsCard(result: result),
          const SizedBox(height: AppSpacing.sm),
        ],
        _RawRecordCard(result: result),
      ],
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard({required this.result});

  final WhoisResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

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
            'Highlights',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...result.highlights.map((WhoisHighlight h) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      h.label,
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: SelectableText(
                      h.value,
                      style: mono.inlineCode.copyWith(
                        color: AppColors.textPrimary,
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

class _RawRecordCard extends StatelessWidget {
  const _RawRecordCard({required this.result});

  final WhoisResult result;

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
            'Raw record',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (result.serversQueried.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'via ${result.serversQueried.join(' → ')}',
              style: text.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
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
              result.rawRecord,
              style: mono.inlineCode.copyWith(
                color: AppColors.textPrimary,
                fontSize: AppTextSize.caption,
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
