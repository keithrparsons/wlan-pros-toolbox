// Top 30 Emoji — read-only reference for the 30 most-used emoji, ranked 1 to
// 30, with the Unicode CLDR official name and a descriptive "common use" note.
//
// Data source of truth (embedded verbatim, nothing invented):
//   Deliverables/2026-06-01-emoji-top-30/emoji-top-30.json (`emoji` array) and
//   the framing in emoji-top-30.md. Ranking is MESSAGING-WEIGHTED (Keith's
//   decision, 2026-05-31): private-messaging keyboard frequency, where the
//   face-with-tears-of-joy glyph leads — NOT social-listening-weighted.
//
// Columns rendered (Keith's instruction): Rank, Emoji, Official name, Common
// use. The `literal` field from the dataset is OMITTED entirely — there is no
// Literal column and no codepoint column (matching the .md layout). The CLDR
// `name` is what screen readers announce and what search indexes, so it is the
// row's spoken key, not the glyph.
//
// Fully offline: the dataset is a bundled compile-time const, not fetched and
// not computed. No network, no OS-data calls — GL-008 network/subprocess rules
// do not apply (nothing to fabricate, nothing to shell out to).
//
// States (SOP-007 §5):
//  - success → the 30 rows rendered as cards (the default; data is always
//    present because it is a const).
//  - loading / empty / error → none. There is no async load, no filter, and
//    nothing can fail to parse, so a spinner, empty card, or error card would
//    be theatre. Omitted deliberately. (Contrast standards_screen, which has a
//    band filter and therefore a reachable empty state; this screen has no
//    filter, so no empty path exists.)
//
// Pattern: mirrors standards_screen / db_reference_screen — Scaffold + AppBar
// (toolbarHeight 64), SafeArea(top: false), LayoutBuilder isDesktop @720,
// ConstrainedBox to calculatorMaxWidth, SingleChildScrollView, surface-1 cards
// from app_tokens / app_typography, ReferenceRowSemantics per row.
//
// Glyph note: the emoji glyph renders via the platform color-emoji font (Apple
// Color Emoji on iOS/macOS). The glyph is laid out at a readable size and is
// excluded from the row's screen-reader label (the official name carries the
// meaning; readers already announce the glyph's own name if focused). The long
// commonUse text wraps freely and is never clipped, so the card is overflow-safe
// down to 320 px.

import 'package:flutter/material.dart';

import '../../../data/tool_assets.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/app_copy_action.dart';
import '../concept_graphic_band.dart';
import 'reference_row_semantics.dart';

/// One row of the Top 30 Emoji table. Fields mirror the dataset's `emoji[]`
/// schema MINUS `literal` and `codepoint` (omitted by Keith's instruction):
/// rank, emoji (glyph), name (CLDR short name), commonUse.
@immutable
class EmojiEntry {
  const EmojiEntry({
    required this.rank,
    required this.emoji,
    required this.name,
    required this.commonUse,
  });

  /// Frequency rank, 1 (most-used) to 30.
  final int rank;

  /// The glyph itself, one character or a sequence, exactly as shown in the
  /// dataset (variation selectors / ZWJ preserved).
  final String emoji;

  /// Unicode CLDR short name, lowercase — what screen readers announce.
  final String name;

  /// Descriptive note on what people usually mean by it. "Commonly read as,"
  /// not an official Unicode definition; meanings drift by audience and
  /// generation. Reused verbatim from the dataset.
  final String commonUse;
}

/// Top 30 Emoji reference screen (route `/tools/emoji`).
class EmojiReferenceScreen extends StatelessWidget {
  const EmojiReferenceScreen({super.key});

  /// The Top 30 dataset — embedded verbatim from emoji-top-30.json (`emoji`
  /// array). Public + const so tests assert against the same single source the
  /// UI renders. The `literal` field is intentionally not modeled. Do not edit
  /// values here without reconciling the Deliverables source.
  static const List<EmojiEntry> emoji = <EmojiEntry>[
    EmojiEntry(
      rank: 1,
      emoji: '😂',
      name: 'face with tears of joy',
      commonUse:
          '"That is hilarious." Reads as dated or "boomer" to many under-25 '
          'users now',
    ),
    EmojiEntry(
      rank: 2,
      emoji: '❤️',
      name: 'red heart',
      commonUse: 'Love, "I love this," strong like. The default heart',
    ),
    EmojiEntry(
      rank: 3,
      emoji: '😭',
      name: 'loudly crying face',
      commonUse:
          'Sobbing OR laughing so hard you cry; also "I love this so much" in '
          'fandom. Context decides',
    ),
    EmojiEntry(
      rank: 4,
      emoji: '🙏',
      name: 'folded hands',
      commonUse:
          'Thanks or please; also prayer/hope. Sometimes joked as a "high '
          'five." Cultural roots in Asian gratitude/respect gestures',
    ),
    EmojiEntry(
      rank: 5,
      emoji: '😍',
      name: 'smiling face with heart-eyes',
      commonUse: 'Strong like or love, "I want this"',
    ),
    EmojiEntry(
      rank: 6,
      emoji: '🥰',
      name: 'smiling face with hearts',
      commonUse: 'Love, adoration, "this is so sweet"',
    ),
    EmojiEntry(
      rank: 7,
      emoji: '👍',
      name: 'thumbs up',
      commonUse:
          'Approval, "yes," "ok," "got it." Read as curt or dismissive by some '
          'younger users',
    ),
    EmojiEntry(
      rank: 8,
      emoji: '💕',
      name: 'two hearts',
      commonUse: 'Love, affection, cuteness',
    ),
    EmojiEntry(
      rank: 9,
      emoji: '😊',
      name: 'smiling face with smiling eyes',
      commonUse: 'Warm, sincere, thankful',
    ),
    EmojiEntry(
      rank: 10,
      emoji: '🔥',
      name: 'fire',
      commonUse:
          'Literally fire, BUT mostly "lit / excellent," "hot / attractive," '
          '"on fire / killing it"',
    ),
    EmojiEntry(
      rank: 11,
      emoji: '🥺',
      name: 'pleading face',
      commonUse: 'Begging, "please," puppy-dog eyes; also cuteness',
    ),
    EmojiEntry(
      rank: 12,
      emoji: '😘',
      name: 'face blowing a kiss',
      commonUse: 'Affection, "love you," goodbye kiss',
    ),
    EmojiEntry(
      rank: 13,
      emoji: '💖',
      name: 'sparkling heart',
      commonUse: 'Love plus excitement, "adorable"',
    ),
    EmojiEntry(
      rank: 14,
      emoji: '💯',
      name: 'hundred points',
      commonUse: '"Keep it 100" (be real), full agreement, "perfect score"',
    ),
    EmojiEntry(
      rank: 15,
      emoji: '✨',
      name: 'sparkles',
      commonUse:
          'Magic, excellence, "clean," "amazing," new; also ironic air-quotes '
          'around a word',
    ),
    EmojiEntry(
      rank: 16,
      emoji: '🤣',
      name: 'rolling on the floor laughing',
      commonUse: 'Extreme laughter; replaced 😂 for many younger users',
    ),
    EmojiEntry(
      rank: 17,
      emoji: '💔',
      name: 'broken heart',
      commonUse: 'Heartbreak, sadness, "this hurts"',
    ),
    EmojiEntry(
      rank: 18,
      emoji: '😅',
      name: 'grinning face with sweat',
      commonUse: 'Nervous relief, "that was close," awkward laugh',
    ),
    EmojiEntry(
      rank: 19,
      emoji: '🎉',
      name: 'party popper',
      commonUse: 'Party, congrats, "yay," celebration',
    ),
    EmojiEntry(
      rank: 20,
      emoji: '😁',
      name: 'beaming face with smiling eyes',
      commonUse: 'Pleased, "this is great"',
    ),
    EmojiEntry(
      rank: 21,
      emoji: '💜',
      name: 'purple heart',
      commonUse: 'Love, support; strong in K-pop fandom (BTS "I purple you")',
    ),
    EmojiEntry(
      rank: 22,
      emoji: '💀',
      name: 'skull',
      commonUse:
          'Literally death, BUT commonly "I\'m dead = that\'s hilarious." A '
          'core Gen Z laugh marker',
    ),
    EmojiEntry(
      rank: 23,
      emoji: '😎',
      name: 'smiling face with sunglasses',
      commonUse: 'Cool, confident, "no big deal"',
    ),
    EmojiEntry(
      rank: 24,
      emoji: '👀',
      name: 'eyes',
      commonUse: '"I\'m watching," "look at this," interest, suspicion',
    ),
    EmojiEntry(
      rank: 25,
      emoji: '😉',
      name: 'winking face',
      commonUse: 'Joking, flirting, "you know what I mean"',
    ),
    EmojiEntry(
      rank: 26,
      emoji: '🙌',
      name: 'raising hands',
      commonUse: 'Celebration, praise, "yay," relief',
    ),
    EmojiEntry(
      rank: 27,
      emoji: '💪',
      name: 'flexed biceps',
      commonUse: 'Strength, "you got this," gym, determination',
    ),
    EmojiEntry(
      rank: 28,
      emoji: '🫶',
      name: 'heart hands',
      commonUse: 'Love, gratitude, "I appreciate you"',
    ),
    EmojiEntry(
      rank: 29,
      emoji: '🥹',
      name: 'face holding back tears',
      commonUse: 'Touched, proud, "I\'m gonna cry" (happy or moved)',
    ),
    EmojiEntry(
      rank: 30,
      emoji: '😏',
      name: 'smirking face',
      commonUse: 'Smug, flirty, "I know something"',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top 30 Emoji'),
        toolbarHeight: 64,
        // §8.16 — copy the ranked table as TSV. Static data, always enabled.
        actions: <Widget>[AppCopyAction(textBuilder: _buildCopyText)],
      ),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  /// §8.16 copy payload — the Top 30 table as TSV: a title, a four-column
  /// header (Rank / Emoji / Name / Common use — the `literal` field is omitted
  /// here too, matching the screen), one row per entry. Always non-null: the
  /// dataset is static, so copy is never disabled.
  String _buildCopyText() {
    const String tab = '\t';
    final StringBuffer buf = StringBuffer()
      ..writeln('Top 30 Emoji')
      ..writeln(<String>['Rank', 'Emoji', 'Name', 'Common use'].join(tab));
    for (final EmojiEntry e in emoji) {
      buf.writeln(
        <String>['${e.rank}', e.emoji, e.name, e.commonUse].join(tab),
      );
    }
    return buf.toString().trimRight();
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
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
                  ConceptGraphicBand(toolId: 'emoji', isDesktop: isDesktop),
                  if (ToolAssets.hasGraphic('emoji'))
                    const SizedBox(height: AppSpacing.md),
                  _introCard(context),
                  const SizedBox(height: AppSpacing.sm),
                  ...emoji.map(
                    (EmojiEntry e) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _EmojiCard(entry: e),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _introCard(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return _Card(
      child: Text(
        'The 30 most-used emoji, ranked by private-messaging frequency (the '
        'Unicode canon). "Common use" is how people usually read each one '
        'today, not an official Unicode definition — meanings drift by '
        'audience, region, and generation.',
        style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

/// One emoji card: a header (rank badge + glyph + official name) over the
/// common-use note. The official name and the common-use text wrap freely so
/// the long descriptions never clip at 320 px.
class _EmojiCard extends StatelessWidget {
  const _EmojiCard({required this.entry});

  final EmojiEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ReferenceRowSemantics(
      // The row reads as one node keyed by rank + official name + common use.
      // The glyph itself is NOT in the spoken label — screen readers already
      // announce the glyph's own name, and the CLDR name carries the meaning.
      label: rowLabel('Rank ${entry.rank}, ${entry.name}', <String?>[
        entry.commonUse,
      ]),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _RankBadge(rank: entry.rank),
                const SizedBox(width: AppSpacing.sm),
                // ExcludeSemantics: the glyph is decorative for the reader; the
                // name (below) is the meaningful label. Keeps the row's spoken
                // node from emitting a second, redundant glyph announcement.
                ExcludeSemantics(
                  child: Text(
                    entry.emoji,
                    style: const TextStyle(fontSize: 30, height: 1.0),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.name,
                    style: text.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: AppSpacing.xs),
            Text(
              entry.commonUse,
              style: text.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lime pill carrying the frequency rank (e.g. "#1"). Mirrors the generation
/// badge idiom in standards_screen.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final AppMonoText mono =
        Theme.of(context).extension<AppMonoText>() ?? AppMonoText.defaults();
    return Container(
      constraints: const BoxConstraints(minWidth: 36),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.borderStrong, width: 1),
      ),
      child: Text(
        '#$rank',
        style: mono.inlineCode.copyWith(
          fontSize: AppTextSize.caption,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Shared surface-1 card with the standard border, radius, and padding.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}
