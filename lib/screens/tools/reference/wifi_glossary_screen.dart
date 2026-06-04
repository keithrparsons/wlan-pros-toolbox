// Wi-Fi Glossary — a data-driven, searchable, grouped glossary of 92 Wi-Fi
// terms, fully offline (bundled JSON asset).
//
// Mirrors the app's bundled-JSON reference pattern (Educational Resources /
// Well-Known Ports): bundled asset → GlossaryService.fromJson → grouped list
// screen. The 92 terms render in 8 category groups in curation order (never
// alphabetized), each row showing the term, its companion identifier (abbr) and
// its plain-language definition. A free-text search field filters the rendered
// rows live, matching the app's other list/reference search UX (case-insensitive
// substring across term + abbr + definition, SC 4.1.3 live count announcement).
//
// abbr rendering: the dataset's `abbr` is sometimes a short identifier (CCI,
// DFS, 802.11n, FSPL) and sometimes a multi-word expansion (RSSI →
// "Received Signal Strength Indicator"). A short, space-free identifier renders
// in the Roboto Mono identifier token (§8.5 identifier rule — identifiers are
// scanned glyph-by-glyph); a multi-word expansion renders as plain secondary
// text (it is prose, not an identifier). Both are searchable regardless.
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner + AT announce.
//  - error   → the bundled asset failed to load/parse (should not happen in a
//    shipped build); an honest message card.
//  - success → category groups with term rows, OR the filtered subset.
//  - empty   → a query that matches nothing; an honest "no match" card.
//
// Copy affordance (§8.16): the AppBar carries AppCopyAction — copies the full
// glossary (or the current filtered subset) as plain text, grouped by category.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../services/glossary/glossary_service.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import 'reference_row_semantics.dart';

/// Asset path for the bundled glossary. Overridable in tests so a fixture string
/// can stand in for the bundled asset.
const String kWifiGlossaryAsset = 'assets/data/glossary.json';

class WifiGlossaryScreen extends StatefulWidget {
  const WifiGlossaryScreen({super.key, this.service});

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final GlossaryService? service;

  @override
  State<WifiGlossaryScreen> createState() => _WifiGlossaryScreenState();
}

class _WifiGlossaryScreenState extends State<WifiGlossaryScreen> {
  final TextEditingController _queryCtrl = TextEditingController();

  GlossaryService? _service;
  String? _loadError;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _service = widget.service;
    } else {
      _loadAsset();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAsset() async {
    try {
      final String raw = await rootBundle.loadString(kWifiGlossaryAsset);
      final GlossaryService svc = GlossaryService.fromJson(raw);
      if (!mounted) return;
      setState(() => _service = svc);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the Wi-Fi glossary: $e');
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final GlossaryService? svc = _service;
    if (svc == null) return;
    // SC 4.1.3 — announce the live result count so AT users hear the list change
    // as they type, without focus leaving the field.
    final int n = svc.search(value).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching terms' : '$n matching term${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// §8.16 copy payload — the current view (filtered subset if searching, else
  /// the full glossary) as plain text, grouped by category. `null` until the
  /// service has loaded or when nothing matches the query, so copy renders
  /// disabled in those states (§8.16 empty/no-results rule).
  String? _buildCopyText() {
    final GlossaryService? svc = _service;
    if (svc == null) return null;
    final List<GlossaryGroup> groups = svc.grouped(svc.search(_query));
    if (groups.isEmpty) return null;

    final StringBuffer buf = StringBuffer()..writeln(svc.title);
    if (_query.trim().isNotEmpty) {
      buf.writeln('Filtered by "${_query.trim()}"');
    }
    for (final GlossaryGroup g in groups) {
      buf
        ..writeln()
        ..writeln(g.category);
      for (final GlossaryTerm t in g.terms) {
        final String head =
            t.abbr == null ? t.term : '${t.term} (${t.abbr})';
        buf.writeln('$head: ${t.definition}');
      }
    }
    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Glossary'),
        toolbarHeight: 64,
        // §8.16 — copy the current (grouped) view as plain text. Disabled until
        // results exist; null payload drops it from focus traversal.
        actions: <Widget>[
          AppCopyAction(textBuilder: _buildCopyText),
        ],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;

        if (_loadError != null) {
          return _PaddedMessage(
            edge: edge,
            icon: Icons.error_outline,
            title: 'Glossary unavailable',
            body: _loadError!,
          );
        }

        final GlossaryService? svc = _service;
        if (svc == null) {
          return Padding(
            padding: EdgeInsets.all(edge),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: Semantics(
                  label: 'Loading Wi-Fi glossary',
                  liveRegion: true,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          );
        }

        final AppMonoText mono =
            Theme.of(context).extension<AppMonoText>() ??
                AppMonoText.defaults();
        final List<GlossaryTerm> filtered = svc.search(_query);
        final List<GlossaryGroup> groups = svc.grouped(filtered);

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              children: <Widget>[
                _IntroCard(total: svc.count, categories: svc.categoryCount),
                const SizedBox(height: AppSpacing.sm),
                _SearchField(
                  controller: _queryCtrl,
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (groups.isEmpty)
                  _NoMatch(query: _query.trim())
                else
                  ..._groupWidgets(groups, mono),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _groupWidgets(List<GlossaryGroup> groups, AppMonoText mono) {
    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final GlossaryGroup group = groups[g];
      out.add(_CategoryHeader(category: group.category, count: group.count));
      out.add(const SizedBox(height: AppSpacing.xs));
      for (int i = 0; i < group.terms.length; i++) {
        out.add(_TermRow(term: group.terms[i], mono: mono));
        if (i < group.terms.length - 1) {
          out.add(const SizedBox(height: AppSpacing.xs));
        }
      }
      if (g < groups.length - 1) {
        out.add(const SizedBox(height: AppSpacing.lg));
      }
    }
    return out;
  }
}

/// A short, space-free identifier (CCI, DFS, 802.11n, FSPL) reads as a scanned
/// identifier and renders in the Roboto Mono identifier token (§8.5). A
/// multi-word expansion ("Received Signal Strength Indicator") is prose, not an
/// identifier, and renders as plain secondary text. A single Title-case word
/// ("Decibel", the expansion of dB) is also prose, not an identifier.
bool _abbrIsIdentifier(String abbr) =>
    !abbr.contains(' ') && !RegExp(r'^[A-Z][a-z]+$').hasMatch(abbr);

/// One-line glossary intro + counts.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.total, required this.categories});

  final int total;
  final int categories;

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
      child: Text(
        'Plain-language definitions of $total Wi-Fi terms across $categories '
        'categories. Search by term, abbreviation, or any word in a definition.',
        style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

/// In-screen search field (§8.4 input spec).
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'Search Wi-Fi glossary by term, abbreviation, or definition',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        // 16px field text dodges iOS Safari auto-zoom (§8.4).
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: AppColors.textPrimary),
        cursorColor: AppColors.primary,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search, color: AppColors.textTertiary),
          hintText: 'Search terms…',
        ),
      ),
    );
  }
}

/// A category group header with a count chip (matches the reference
/// section-header register: H3 title + neutral count pill).
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category, required this.count});

  final String category;
  final int count;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: '$category, $count term${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                category,
                style: text.headlineSmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$count',
                style: text.labelLarge?.copyWith(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One glossary entry: the term (with its companion identifier where present)
/// and the definition. Read-only — no tap target, so no focus ring; the row is
/// announced as one coherent screen-reader node via ReferenceRowSemantics.
class _TermRow extends StatelessWidget {
  const _TermRow({required this.term, required this.mono});

  final GlossaryTerm term;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? abbr = term.abbr;

    // Screen-reader summary: term, then abbr (read in full), then definition.
    final String srLabel = rowLabel(term.term, <String?>[abbr, term.definition]);

    return ReferenceRowSemantics(
      label: srLabel,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.rowPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _TermLine(term: term.term, abbr: abbr, text: text, mono: mono),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              term.definition,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The term headline line: the term in semibold body, plus its companion
/// identifier — mono identifier token for a short identifier (CCI / 802.11n),
/// plain secondary text for a multi-word expansion. Wraps cleanly at narrow
/// widths (Wrap) so a long term + abbr never overflows.
class _TermLine extends StatelessWidget {
  const _TermLine({
    required this.term,
    required this.abbr,
    required this.text,
    required this.mono,
  });

  final String term;
  final String? abbr;
  final TextTheme text;
  final AppMonoText mono;

  @override
  Widget build(BuildContext context) {
    final String? a = abbr;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      children: <Widget>[
        Text(
          term,
          style: text.bodyLarge?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (a != null)
          if (_abbrIsIdentifier(a))
            Text(
              a,
              style: mono.robotoMono.copyWith(color: AppColors.textTertiary),
            )
          else
            Text(
              a,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
      ],
    );
  }
}

/// In-screen no-results state when the live filter matches nothing.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.search_off_outlined,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isEmpty
                ? 'No terms loaded.'
                : 'No terms match "$query".',
            style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// An error / message card with leading icon (mirrors the reference message-card
/// register).
class _PaddedMessage extends StatelessWidget {
  const _PaddedMessage({
    required this.edge,
    required this.icon,
    required this.title,
    required this.body,
  });

  final double edge;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(edge),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 20, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
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
      ),
    );
  }
}
