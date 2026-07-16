// Emergency Phrases — a data-driven, searchable, grouped translator of ~124
// travel/emergency phrases for a Wi-Fi pro working on-site internationally.
// English source plus four target translations (Spanish, French, Italian,
// German), fully offline (bundled JSON asset).
//
// Mirrors the app's bundled-JSON reference pattern (Wi-Fi Glossary / Educational
// Resources): bundled asset → EmergencyPhraseService.fromJson → grouped list
// screen. The phrases render in curated situation groups in file order (never
// alphabetized): Basics & courtesy, Medical & help, Directions, Food & lodging,
// Problems & requests, On-site & technical, Numbers & time.
//
// LANGUAGE PICKER (spec): two controls at the top.
//   1. A "Show" toggle (AppToggle): "One language" (EN + one chosen target) or
//      "All languages" (EN + all four). Defaults to one language.
//   2. A target-language AppSelect (Spanish / French / Italian / German), shown
//      only in one-language mode (it has no effect in all-languages mode).
// In one-language mode each row shows EN + the chosen target; in all-languages
// mode each row shows EN + all four targets stacked.
//
// SEARCH (spec): a free-text field filters the rendered rows live, matching the
// app's other list/reference search UX (case-insensitive substring across ALL
// five languages + the id, so a phrase is findable by typing it in any
// language, SC 4.1.3 live count announcement).
//
// COPY (spec — "copy affordance on each"): every phrase row carries an inline
// AppCopyAction that copies that ONE phrase in the currently visible languages
// (EN + the shown target(s), each labeled). The AppBar also carries an
// AppCopyAction that copies the whole current view (filtered subset if
// searching) grouped by category — same as the glossary.
//
// TRANSLATION HONESTY (GL-005): the dataset is flagged
// `translation_status: "draft-needs-review"`. These are DRAFT machine
// translations that have NOT been reviewed by a native or professional
// translator. The screen shows a persistent, dismiss-free §8.13 warning banner
// (statusWarning on statusWarningFill) at the top stating exactly that, so the
// user is never misled into trusting an unverified translation. The banner text
// also rides along in the AppBar's whole-view copy payload.
//
// States (SOP-007 §5):
//  - loading → asset load in flight (one-time, fast); a spinner + AT announce.
//  - error   → the bundled asset failed to load/parse (should not happen in a
//    shipped build); an honest message card.
//  - success → category groups with phrase rows, OR the filtered subset.
//  - empty   → a query that matches nothing; an honest "no match" card.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../services/phrases/emergency_phrase_service.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_copy_action.dart';
import '../../../widgets/app_select.dart';
import '../../../widgets/app_toggle.dart';
import 'reference_row_semantics.dart';

/// Asset path for the bundled Emergency Phrases dataset. Overridable in tests so
/// a fixture string can stand in for the bundled asset.
const String kEmergencyPhrasesAsset = 'assets/data/emergency_phrases.json';

/// Whether the screen shows one target language or all of them.
enum PhraseDisplayMode { one, all }

class EmergencyPhrasesScreen extends StatefulWidget {
  const EmergencyPhrasesScreen({
    super.key,
    this.service,
    this.assetPath = kEmergencyPhrasesAsset,
    this.title = 'Emergency Phrases',
  });

  /// Inject a pre-built service to bypass the asset load in widget tests.
  final EmergencyPhraseService? service;

  /// Bundled JSON asset to load when [service] is not injected.
  final String assetPath;

  /// Screen title and the noun used in load/empty copy and AT labels.
  final String title;

  @override
  State<EmergencyPhrasesScreen> createState() => _EmergencyPhrasesScreenState();
}

class _EmergencyPhrasesScreenState extends State<EmergencyPhrasesScreen> {
  final TextEditingController _queryCtrl = TextEditingController();

  EmergencyPhraseService? _service;
  String? _loadError;
  String _query = '';

  PhraseDisplayMode _mode = PhraseDisplayMode.one;
  String _targetCode = '';

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _service = widget.service;
      _initTarget();
    } else {
      _loadAsset();
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// Default the chosen target to the first target language (Spanish in the
  /// shipped dataset). Guarded so an empty dataset cannot crash.
  void _initTarget() {
    final List<PhraseLanguage> targets = _service?.targetLanguages ?? const [];
    if (targets.isNotEmpty && _targetCode.isEmpty) {
      _targetCode = targets.first.code;
    }
  }

  Future<void> _loadAsset() async {
    try {
      final String raw = await rootBundle.loadString(widget.assetPath);
      final EmergencyPhraseService svc =
          EmergencyPhraseService.fromJson(raw);
      if (!mounted) return;
      setState(() {
        _service = svc;
        _initTarget();
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Could not load the phrases: $e');
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    final EmergencyPhraseService? svc = _service;
    if (svc == null) return;
    // SC 4.1.3 — announce the live result count so AT users hear the list change
    // as they type, without focus leaving the field.
    final int n = svc.search(value).length;
    SemanticsService.sendAnnouncement(
      View.of(context),
      n == 0 ? 'No matching phrases' : '$n matching phrase${n == 1 ? '' : 's'}',
      TextDirection.ltr,
    );
  }

  /// The language codes currently displayed in a row: English first, then the
  /// chosen target (one-language mode) or every target (all-languages mode).
  List<String> _visibleCodes(EmergencyPhraseService svc) {
    if (_mode == PhraseDisplayMode.all) {
      return <String>['en', for (final PhraseLanguage l in svc.targetLanguages) l.code];
    }
    return <String>['en', if (_targetCode.isNotEmpty) _targetCode];
  }

  /// The display label for a language code (English label), for row captions and
  /// copy payloads.
  String _labelFor(EmergencyPhraseService svc, String code) {
    for (final PhraseLanguage l in svc.languages) {
      if (l.code == code) return l.label;
    }
    return code.toUpperCase();
  }

  /// §8.16 whole-view copy payload — the current view (filtered subset if
  /// searching, else everything) as plain text, grouped by category, in the
  /// visible languages. Leads with the draft-translation caveat so the warning
  /// rides along to the clipboard. `null` until the service loads or when
  /// nothing matches the query, so copy renders disabled in those states.
  String? _buildViewCopyText() {
    final EmergencyPhraseService? svc = _service;
    if (svc == null) return null;
    final List<PhraseGroup> groups = svc.grouped(svc.search(_query));
    if (groups.isEmpty) return null;

    final List<String> codes = _visibleCodes(svc);
    final StringBuffer buf = StringBuffer()..writeln(svc.title);
    if (svc.isDraft) {
      buf.writeln('[DRAFT machine translations: not yet reviewed]');
    }
    if (_query.trim().isNotEmpty) {
      buf.writeln('Filtered by "${_query.trim()}"');
    }
    for (final PhraseGroup g in groups) {
      buf
        ..writeln()
        ..writeln(g.category);
      for (final EmergencyPhrase p in g.phrases) {
        buf.writeln(_phraseCopyLine(svc, p, codes));
      }
    }
    return buf.toString().trimRight();
  }

  /// One phrase as a single labeled clipboard line, e.g.
  /// "English: Help! | Spanish: ¡Ayuda!".
  String _phraseCopyLine(
    EmergencyPhraseService svc,
    EmergencyPhrase p,
    List<String> codes,
  ) {
    final List<String> parts = <String>[];
    for (final String code in codes) {
      final String? text = p.forCode(code);
      if (text != null) parts.add('${_labelFor(svc, code)}: $text');
    }
    return parts.join(' | ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        toolbarHeight: 64,
        actions: <Widget>[
          AppCopyAction(
            textBuilder: _buildViewCopyText,
            idleLabel: 'Copy all phrases',
            copiedLabel: 'Phrases copied',
          ),
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
            title: 'Phrases unavailable',
            body: _loadError!,
          );
        }

        final EmergencyPhraseService? svc = _service;
        if (svc == null) {
          return Padding(
            padding: EdgeInsets.all(edge),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: Semantics(
                  label: 'Loading phrases',
                  liveRegion: true,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.textAccent,
                  ),
                ),
              ),
            ),
          );
        }

        final List<EmergencyPhrase> filtered = svc.search(_query);
        final List<PhraseGroup> groups = svc.grouped(filtered);
        final List<String> codes = _visibleCodes(svc);

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
                if (svc.isDraft)
                  _DraftBanner(note: svc.translationNote),
                if (svc.isDraft) const SizedBox(height: AppSpacing.sm),
                _IntroCard(total: svc.count, categories: svc.categoryCount),
                const SizedBox(height: AppSpacing.sm),
                _LanguagePicker(
                  mode: _mode,
                  targetCode: _targetCode,
                  targets: svc.targetLanguages,
                  onModeChanged: (PhraseDisplayMode m) =>
                      setState(() => _mode = m),
                  onTargetChanged: (String code) =>
                      setState(() => _targetCode = code),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SearchField(
                  controller: _queryCtrl,
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (groups.isEmpty)
                  _NoMatch(query: _query.trim())
                else
                  ..._groupWidgets(svc, groups, codes),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _groupWidgets(
    EmergencyPhraseService svc,
    List<PhraseGroup> groups,
    List<String> codes,
  ) {
    final List<Widget> out = <Widget>[];
    for (int g = 0; g < groups.length; g++) {
      final PhraseGroup group = groups[g];
      out.add(_CategoryHeader(category: group.category, count: group.count));
      out.add(const SizedBox(height: AppSpacing.xs));
      for (int i = 0; i < group.phrases.length; i++) {
        final EmergencyPhrase p = group.phrases[i];
        out.add(
          _PhraseRow(
            svc: svc,
            phrase: p,
            codes: codes,
            labelFor: _labelFor,
            copyTextBuilder: () => _phraseCopyLine(svc, p, codes),
          ),
        );
        if (i < group.phrases.length - 1) {
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

/// The persistent draft-translation warning banner (§8.13 warning treatment).
/// Always shown when the dataset is flagged draft; no dismiss — the caveat must
/// stay visible while the user reads any translation. Carries an icon + the
/// word "Draft" so it is never color-only (§8.13 rule 2).
class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    final String body = note.isNotEmpty
        ? note
        : 'These are draft machine translations and have not yet been reviewed '
            'by a native or professional translator. Verify any critical phrase '
            'locally before relying on it.';
    return Semantics(
      container: true,
      label: 'Draft translations notice. $body',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.statusWarningFill,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.statusWarning, width: 1),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_outlined,
              size: 20,
              color: colors.statusWarning,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Draft translations. Review pending',
                    style: text.bodyMedium?.copyWith(
                      color: colors.statusWarning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    body,
                    style: text.labelMedium?.copyWith(
                      color: colors.textSecondary,
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

/// One-line intro + counts.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.total, required this.categories});

  final int total;
  final int categories;

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
      child: Text(
        '$total travel and emergency phrases across $categories situations, in '
        'English with Spanish, French, Italian, and German. Pick one language '
        'or show all four, then search or copy any phrase.',
        style: text.labelMedium?.copyWith(color: colors.textSecondary),
      ),
    );
  }
}

/// The language picker: a Show toggle (one / all) and, in one-language mode, a
/// target-language select.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.mode,
    required this.targetCode,
    required this.targets,
    required this.onModeChanged,
    required this.onTargetChanged,
  });

  final PhraseDisplayMode mode;
  final String targetCode;
  final List<PhraseLanguage> targets;
  final ValueChanged<PhraseDisplayMode> onModeChanged;
  final ValueChanged<String> onTargetChanged;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppToggle<PhraseDisplayMode>(
            label: 'Show',
            value: mode,
            expand: true,
            items: const <AppToggleItem<PhraseDisplayMode>>[
              (PhraseDisplayMode.one, 'One language'),
              (PhraseDisplayMode.all, 'All languages'),
            ],
            onChanged: onModeChanged,
          ),
          if (mode == PhraseDisplayMode.one) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Target language',
              style: text.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSelect<String>(
              value: targetCode,
              semanticLabel: 'Target language',
              items: <AppSelectItem<String>>[
                for (final PhraseLanguage l in targets)
                  (l.code, '${l.label} (${l.native})'),
              ],
              onChanged: onTargetChanged,
            ),
          ],
        ],
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
    final AppColorScheme colors = context.colors;
    return Semantics(
      textField: true,
      label: 'Search phrases in any language',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: false,
        // 16px field text dodges iOS Safari auto-zoom (§8.4).
        style: Theme.of(context)
            .textTheme
            .bodyLarge
            ?.copyWith(color: colors.textPrimary),
        cursorColor: colors.textAccent,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, color: colors.textTertiary),
          hintText: 'Search phrases…',
        ),
      ),
    );
  }
}

/// A category group header with a count chip.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category, required this.count});

  final String category;
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: '$category, $count phrase${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                category,
                style: text.headlineSmall?.copyWith(
                  color: colors.textPrimary,
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
                color: colors.surface2,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$count',
                style: text.labelLarge?.copyWith(
                  fontSize: AppTextSize.caption,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One phrase: the English source on top, then the visible target translation(s)
/// each with its language label, and an inline copy affordance for that one
/// phrase. The text content is announced as one coherent screen-reader node; the
/// copy button is a separate focusable node after it.
class _PhraseRow extends StatelessWidget {
  const _PhraseRow({
    required this.svc,
    required this.phrase,
    required this.codes,
    required this.labelFor,
    required this.copyTextBuilder,
  });

  final EmergencyPhraseService svc;
  final EmergencyPhrase phrase;
  final List<String> codes;
  final String Function(EmergencyPhraseService, String) labelFor;
  final String Function() copyTextBuilder;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;

    // Screen-reader summary: each visible language announced as "label: text".
    final List<String> srParts = <String>[
      for (final String code in codes)
        if (phrase.forCode(code) != null)
          '${labelFor(svc, code)}: ${phrase.forCode(code)}',
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.rowPadding,
        AppSpacing.xs,
        AppSpacing.rowPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ReferenceRowSemantics(
              label: srParts.join('. '),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < codes.length; i++)
                    if (phrase.forCode(codes[i]) != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 0 : AppSpacing.xs,
                        ),
                        child: _LangLine(
                          label: labelFor(svc, codes[i]),
                          value: phrase.forCode(codes[i])!,
                          isSource: codes[i] == 'en',
                          text: text,
                          colors: colors,
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          // §8.16 per-phrase copy. Compact inline action; copies just this
          // phrase in the visible languages.
          AppCopyAction(
            textBuilder: copyTextBuilder,
            idleLabel: 'Copy this phrase',
            copiedLabel: 'Phrase copied',
          ),
        ],
      ),
    );
  }
}

/// One language line within a phrase row: a small language label above the
/// phrase text. The English source phrase is weighted as the primary line; the
/// targets read as secondary.
class _LangLine extends StatelessWidget {
  const _LangLine({
    required this.label,
    required this.value,
    required this.isSource,
    required this.text,
    required this.colors,
  });

  final String label;
  final String value;
  final bool isSource;
  final TextTheme text;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: text.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontSize: AppTextSize.caption,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: isSource
              ? text.bodyLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                )
              : text.bodyMedium?.copyWith(color: colors.textSecondary),
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.search_off_outlined,
            size: 48,
            color: colors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            query.isEmpty
                ? 'No phrases loaded.'
                : 'No phrases match "$query".',
            style: text.bodyLarge?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// An error / message card with leading icon.
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
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(edge),
      child: Container(
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
                  const SizedBox(height: AppSpacing.xxs),
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
      ),
    );
  }
}
