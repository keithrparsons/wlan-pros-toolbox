// DNS Lookup tool — a portable `dig`/`nslookup` for the field, over DoH.
//
// Two query modes:
//  - All records (dig-style): one sweep resolves SOA, NS, A, AAAA, MX, TXT,
//    SRV, CAA and presents them grouped/labeled like `dig` output. Default.
//  - Single type: A, AAAA, MX, TXT, NS, SOA, PTR (rDNS), SRV, CAA, SPF — the
//    focused one-type view.
//
// Reverse PTR convenience: when the input parses as an IP literal, a one-tap
// "Reverse lookup (PTR)" action runs the IP→hostname query directly, no need to
// switch the record-type selector first.
//
// `dig +trace` (root → TLD → authoritative delegation walk) was spiked and
// DEFERRED — see the build report. It needs raw UDP/53 to named authoritative
// servers plus a hand-rolled DNS wire codec; the DoH transport this tool rides
// only reaches recursive resolvers (Google/Cloudflare) that return the final
// answer, never the iterative referral chain.
//
// States (SOP-007 §5):
//  - idle     → form only, no results panel yet.
//  - loading  → query in flight; button shows progress, input disabled.
//  - success  → records list (mono values), grouped by type in dig mode.
//  - empty    → resolved but no records of that type (or any type) for the name.
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
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/tool_help_footer.dart';
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

  // Query mode. `_digMode` true → dig-style sweep of all common types.
  // `_digMode` false → the focused single-[_type] query.
  bool _digMode = true;
  DnsRecordType _type = DnsRecordType.a;
  DohResolver _resolver = DohResolver.cloudflare;

  bool _loading = false;
  // At most one of these is non-null at a time, set by the mode that ran.
  DnsLookupResult? _result;
  DnsDigResult? _digResult;

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
    setState(() {
      _loading = true;
      _result = null;
      _digResult = null;
    });

    if (_digMode) {
      final DnsDigResult dig = await _service.lookupAll(
        rawQuery: _hostCtrl.text,
        resolver: _resolver,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _digResult = dig;
      });
      _announce(_digAnnouncement(dig));
      return;
    }

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
    _announce(_singleAnnouncement(result));
  }

  /// One-tap reverse PTR. Runs the IP→hostname query directly without making
  /// the user flip the record-type selector to PTR first. Shown only when the
  /// current input parses as an IP literal.
  Future<void> _runReverse() async {
    if (_loading) return;
    _hostFocus.unfocus();
    setState(() {
      _loading = true;
      _result = null;
      _digResult = null;
    });
    final DnsLookupResult result = await _service.lookup(
      rawQuery: _hostCtrl.text,
      type: DnsRecordType.ptr,
      resolver: _resolver,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
    _announce(_singleAnnouncement(result));
  }

  // WCAG 4.1.3 — announce the outcome so AT users learn results landed without
  // the focus moving. These are one-shot result announcements (not a rapidly
  // updating stream), so a single sendAnnouncement is correct; no liveRegion on
  // the result labels themselves.
  void _announce(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  String _singleAnnouncement(DnsLookupResult result) {
    if (result.isError) return 'Lookup failed';
    if (result.isEmpty) return 'No ${result.type.label} records found';
    final int n = result.records.length;
    return '$n ${result.type.label} record${n == 1 ? '' : 's'} found';
  }

  String _digAnnouncement(DnsDigResult dig) {
    if (dig.isError) return 'Lookup failed';
    if (dig.isAllErrored) {
      final int failed = dig.erroredSections.length;
      return 'Lookup failed. All $failed record '
          'type${failed == 1 ? '' : 's'} failed to resolve';
    }
    if (dig.isAllEmpty) return 'No records found for ${dig.queriedName}';
    final int n = dig.recordCount;
    final int types = dig.nonEmptySections.length;
    final String found = '$n record${n == 1 ? '' : 's'} across $types '
        'record type${types == 1 ? '' : 's'} found';
    // Disclose any per-type failures in the same announcement so the spoken
    // count never overstates completeness (GL-005).
    if (dig.hasPartialFailure) {
      final int failed = dig.erroredSections.length;
      return '$found. $failed record '
          'type${failed == 1 ? '' : 's'} failed to resolve';
    }
    return found;
  }

  /// True when the trimmed input looks like an IPv4 or IPv6 literal, which
  /// unlocks the one-tap reverse-PTR action.
  static bool _looksLikeIp(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return false;
    if (s.contains(':')) {
      // Loose IPv6 gate: hex groups and at least one colon. The service does the
      // strict parse and rejects malformed input honestly.
      return RegExp(r'^[0-9a-fA-F:]+$').hasMatch(s) && s.contains(':');
    }
    final List<String> parts = s.split('.');
    if (parts.length != 4) return false;
    for (final String p in parts) {
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lookup (DNS)'),
        toolbarHeight: 64,
        // §8.16 — shared "Copy results" affordance. Disabled until a lookup has
        // resolved at least one record; copies the record list as TSV (Type,
        // Name, Value, TTL — one row per record). Copy leads; no help icon.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  /// §8.16 copy payload — the resolved record list as TSV.
  ///
  /// Returns null (→ disabled affordance) until a lookup resolves with at least
  /// one record: idle, loading, a failed lookup, and an empty (no-records)
  /// result all have nothing to keep. The header row names the four columns; each
  /// record is one tab-separated row in the same order. The Value column reuses
  /// the on-screen [_displayData] so parsed SRV/CAA rows copy as they render; a
  /// null TTL is written as an empty cell (honest blank, GL-005).
  String? _buildCopyText() {
    if (_loading) return null;

    const String tab = '\t';
    const String header = 'DNS Lookup';
    const List<String> cols = <String>['Type', 'Name', 'Value', 'TTL'];

    String row(DnsRecord rec) => <String>[
          rec.type,
          rec.name,
          _displayData(rec),
          rec.ttl == null ? '' : '${rec.ttl}',
        ].join(tab);

    // Dig-style sweep: copy every non-empty section's records as TSV.
    final DnsDigResult? dig = _digResult;
    if (dig != null) {
      if (dig.isError || dig.recordCount == 0) return null;
      final StringBuffer buf = StringBuffer()
        ..writeln(header)
        ..writeln(cols.join(tab));
      for (final DnsDigSection s in dig.nonEmptySections) {
        for (final DnsRecord rec in s.records) {
          buf.writeln(row(rec));
        }
      }
      return buf.toString().trimRight();
    }

    // Single-type result.
    final DnsLookupResult? r = _result;
    if (r == null || r.isError || r.isEmpty || r.records.isEmpty) {
      return null;
    }
    final StringBuffer buf = StringBuffer()
      ..writeln(header)
      ..writeln(cols.join(tab));
    for (final DnsRecord rec in r.records) {
      buf.writeln(row(rec));
    }
    return buf.toString().trimRight();
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
                  ToolHelpFooter(toolId: 'dns-lookup'),
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
    final bool isPtr = !_digMode && _type == DnsRecordType.ptr;
    final bool showReverse = _looksLikeIp(_hostCtrl.text);

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
            label: isPtr ? 'IP address' : 'Hostname or IP',
            field: TextField(
              controller: _hostCtrl,
              focusNode: _hostFocus,
              enabled: !_loading,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              // Re-evaluate the reverse-PTR affordance as the user types an IP.
              onChanged: (_) => setState(() {}),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: isPtr ? '8.8.8.8' : 'example.com',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Query mode: dig-style all-records sweep vs single record type.
          Text(
            'Query',
            style: _fieldLabelStyle(text),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              _modeChip(
                context,
                label: 'All records',
                selected: _digMode,
                onSelected: () => setState(() => _digMode = true),
              ),
              _modeChip(
                context,
                label: 'Single type',
                selected: !_digMode,
                onSelected: () => setState(() => _digMode = false),
              ),
            ],
          ),
          // Record-type selector only in single-type mode.
          if (!_digMode) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Record type',
              style: _fieldLabelStyle(text),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: DnsRecordType.values.map((DnsRecordType t) {
                return _selectChip(
                  context,
                  label: t.label,
                  selected: t == _type,
                  onSelected: () => setState(() => _type = t),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Resolver',
            style: _fieldLabelStyle(text),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: DohResolver.values.map((DohResolver r) {
              return _selectChip(
                context,
                label: r.label,
                selected: r == _resolver,
                onSelected: () => setState(() => _resolver = r),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _loading ? null : _run,
            child: _loading
                ? const _ButtonSpinner()
                : Text(_digMode ? 'Look up all records' : 'Look up'),
          ),
          // One-tap reverse PTR — appears when the input parses as an IP. Skips
          // making the user flip the selector to PTR. Hidden in single-PTR mode
          // (the main button already does the PTR query there).
          if (showReverse && !isPtr) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: _loading ? null : _runReverse,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Reverse lookup (PTR)'),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle? _fieldLabelStyle(TextTheme text) => text.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w500,
      );

  /// A mode chip (All records / Single type). Same visual resolver as the
  /// type/resolver chips; factored so the three selectors stay identical.
  Widget _modeChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) =>
      _selectChip(
        context,
        label: label,
        selected: selected,
        onSelected: onSelected,
      );

  Widget _selectChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final TextTheme text = Theme.of(context).textTheme;
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
      // WCAG 2.5.8 / §8.3 — guarantee ≥48dp hit region.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // §8.3 — shared resolver: idle/selected/disabled borders plus the 2px
      // lime keyboard-focus ring.
      side: AppTheme.chipSide(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      onSelected: _loading ? null : (_) => onSelected(),
    );
  }

  Widget _resultsSection(BuildContext context) {
    // Dig-style sweep result takes precedence when it ran.
    final DnsDigResult? dig = _digResult;
    if (dig != null) {
      if (dig.isError) {
        return _MessageCard(
          icon: Icons.error_outline,
          title: 'Lookup failed',
          body: dig.errorMessage!,
        );
      }
      // Every queried type failed to resolve. This is a total failure, not an
      // empty result — say so plainly so it never reads as "name exists,
      // nothing here" (GL-005). The per-type failures are itemized below the
      // headline so the user sees exactly which queries broke.
      if (dig.isAllErrored) {
        return _MessageCard(
          icon: Icons.error_outline,
          title: 'Lookup failed',
          body: 'No record type resolved for ${dig.queriedName}. '
              'Every query failed:',
          failedTypes: dig.erroredSections,
        );
      }
      if (dig.isAllEmpty) {
        return _MessageCard(
          icon: Icons.search_off,
          title: 'No records',
          body: 'No records found for ${dig.queriedName}.',
        );
      }
      return _DigCard(result: dig);
    }

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

/// In-button progress spinner. Factored out of `_queryCard` so the button child
/// can be const where possible.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      // The button is disabled while loading; the screen sends a one-shot
      // SemanticsService announcement when results land (no liveRegion here, to
      // avoid double-speaking on the spinner appear/disappear).
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.secondary,
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard({required this.result});

  final DnsLookupResult result;

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
            '${result.records.length} ${result.type.label} '
            'record${result.records.length == 1 ? '' : 's'} '
            '· ${result.resolver.label}',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...result.records.map((DnsRecord rec) => _RecordRow(rec: rec)),
        ],
      ),
    );
  }
}

/// Dig-style sweep card — one labeled group per record type that resolved with
/// records, in `dig` order (SOA, NS, A, AAAA, MX, TXT, SRV, CAA), each header a
/// mono type token + a count with one [_RecordRow] per record. Below the
/// resolved groups, any type that FAILED to resolve mid-sweep is surfaced as a
/// quiet per-type failure note (GL-005) — a failed type is not the same as one
/// that resolved with zero records, so we never let a partial failure read as a
/// clean result. The summary line discloses the failed-type count up front.
///
/// Types that resolved with zero records are the legitimate "no records of this
/// type exist" answer; the sweep does not print an empty group for them (that
/// matches `dig`), and the summary's resolved-type count already excludes them.
class _DigCard extends StatelessWidget {
  const _DigCard({required this.result});

  final DnsDigResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<DnsDigSection> sections = result.nonEmptySections;
    final List<DnsDigSection> errored = result.erroredSections;
    final int types = sections.length;
    final int failed = errored.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${result.recordCount} record'
            '${result.recordCount == 1 ? '' : 's'} · '
            '$types type${types == 1 ? '' : 's'} · ${result.resolver.label}',
            style: text.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          // Partial-failure disclosure — the count above only reflects what
          // resolved, so name the gap here so completeness is never overstated.
          if (failed > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '$failed of ${result.sections.length} types '
              'failed to resolve',
              style: text.labelMedium?.copyWith(
                color: AppColors.statusDanger,
                letterSpacing: 0.4,
              ),
            ),
          ],
          for (int i = 0; i < sections.length; i++) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _DigSectionGroup(section: sections[i]),
          ],
          // Failed types, itemized as quiet per-type notes after the records
          // that did resolve. Text label + danger color (not color-only) so the
          // failure reads under any vision condition.
          if (failed > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            for (final DnsDigSection s in errored) ...<Widget>[
              _DigFailedRow(section: s),
            ],
          ],
        ],
      ),
    );
  }
}

/// One record-type group inside the dig card: a `TYPE  (n)` header followed by
/// the records of that type.
class _DigSectionGroup extends StatelessWidget {
  const _DigSectionGroup({required this.section});

  final DnsDigSection section;

  @override
  Widget build(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    final int n = section.records.length;

    return Semantics(
      // Group header read once; the rows below carry their own values.
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(
              '${section.type.label}  ($n)',
              style: mono.inlineCode.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ...section.records.map((DnsRecord rec) => _RecordRow(rec: rec)),
        ],
      ),
    );
  }
}

/// A failed-type note inside the dig card: the type token (danger color) plus a
/// "lookup failed" label and the resolver's message when it adds signal. This
/// is visually distinct from a resolved group AND from a zero-record type — a
/// failure is a failure, stated honestly (GL-005), never silently dropped.
class _DigFailedRow extends StatelessWidget {
  const _DigFailedRow({required this.section});

  final DnsDigSection section;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              section.type.label,
              style: mono.inlineCode.copyWith(
                color: AppColors.statusDanger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              // Lead with the plain-language failure so it is not color-only,
              // then add the resolver's message when it carries detail.
              _failureText(section),
              style: text.labelMedium?.copyWith(
                color: AppColors.statusDanger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _failureText(DnsDigSection s) {
    final String? msg = s.errorMessage?.trim();
    if (msg == null || msg.isEmpty) return 'Lookup failed';
    return 'Lookup failed. $msg';
  }
}

/// A single record row: type token (left, DM Mono, lime) · value (Roboto Mono,
/// selectable) · TTL (right, tertiary). Shared by the single-type and dig
/// cards so a record renders identically in both views.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.rec});

  final DnsRecord rec;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
              // Record DATA is the resolved address/identifier (IP for A/AAAA,
              // hostname for CNAME/MX/NS) → Roboto Mono (GL-003 §8.5). The type
              // token (left) stays DM Mono.
              style: mono.robotoMono.copyWith(
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
    this.failedTypes = const <DnsDigSection>[],
  });

  final IconData icon;
  final String title;
  final String body;

  /// When non-empty (the all-errored sweep), each failed type is itemized below
  /// the body so a total failure names exactly which queries broke rather than
  /// presenting as empty-but-fine (GL-005).
  final List<DnsDigSection> failedTypes;

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
                if (failedTypes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  for (final DnsDigSection s in failedTypes)
                    _DigFailedRow(section: s),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
