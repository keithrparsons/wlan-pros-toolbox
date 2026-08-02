// The BSS Load files name their contracts. They never NUMBER or COUNT them.
//
// WHY THIS EXISTS. Gate rounds on `bss_load_decoder.dart` kept finding the same
// defect wearing different clothes: a change applied to the code and to some,
// but not all, of the sentences that depended on it. Round 3 was a RENAME, and a
// rename has a mechanical handle — you grep the old symbol, and the round-4 gate
// did exactly that and found it clean. Round 4's findings were a RENUMBERING,
// and **nothing greps for an ordinal.** Inserting a new outcome into the file's
// central honesty contract turned three numbered cases into four, and two
// sentences elsewhere kept addressing the old scheme. Not one character of
// either sentence changed, and both now asserted something false.
//
// WHY IT WAS REWRITTEN TWICE, which is the more useful history.
//
// The FIRST version forbade a SYNTAX: a regex per defect, each copied from the
// way the defect happened to be spelled last time. Round 5 defeated four of six
// end-to-end mutations against it. Renumbering the whole honesty contract with
// `1)` instead of `1.` passed every test — one punctuation character. So did
// `step 2` in place of `rule 2`, because the noun was not in the list. And a
// sixth mutation turned the build RED on the ordinary English sentence "the two
// test cases below", which is the failure that actually matters: a guard authors
// have to write around is a guard authors delete.
//
// A GUARD THAT FORBIDS A SYNTAX IS DEFEATED BY A SYNONYM. A GUARD THAT ASSERTS A
// PROPERTY IS NOT. That is Vera's round-5 finding, and the second version acted
// on it: the contract check became a PRESENCE assertion over named entries, the
// mirror check became a set equality, and the count check began VERIFYING a
// stated count instead of forbidding it.
//
// ROUND 6 DEFEATED THAT ONE TOO, in a way worth stating exactly, because it is
// the lesson this file now exists to carry:
//
//   A GUARD THAT ASSERTS A PROPERTY STILL HAS TO PARSE THE THING IT ASSERTS THE
//   PROPERTY OF, AND A PARSER IS AN ENUMERATION.
//
// The entry regex read `NAME — prose` at exactly three spaces with exactly an em
// dash. A fifth outcome written with an ASCII hyphen, or at four spaces, was not
// REJECTED — it was never seen. The contract set stayed at four, the mirror set
// stayed at four, the set equality held, and the build was green over a mirror
// that had silently become incomplete. Reformat an EXISTING entry in both files
// and the guard quietly narrowed to three of four outcomes and would then have
// called a true "four outcomes" sentence an error. The precedence block had the
// same hole one layer down: its step regex read `N.`, so a step written `7)` was
// invisible and the decoder's claim that the build fails on an unnamed step was
// false. A PARSER THAT SKIPS SILENTLY CONVERTS EVERY DOWNSTREAM ASSERTION INTO A
// CLAIM ABOUT A SMALLER SET, AND REPORTS IT IN THE SAME GREEN.
//
// ROUND 7 DEFEATED THAT ONE WITH ONE CHARACTER, WHICH IS THE HISTORY REPEATING
// AT THE LEVEL BELOW. The property assertions were sound; the SEPARATOR was not.
// `rule 2`, `rule two` and `the second rule` were all in the fixture table and
// all RED — and `rule-2`, `rule-two` and `the second-rule` were GREEN, because
// the three ordinal patterns joined their parts with `\s+`. The count check had
// already been written with `[\s-]+`, so the file disagreed with itself, and the
// header's own list of blind spots did not mention hyphens at all.
//
// The second half was worse, because it was not hypothetical. The count check
// held its nouns as PLURALS ONLY, so `the three-state question` — a claim of
// three against a contract of four — had no noun to match and passed clean.
// That sentence was really in `bss_load_decoder_test.dart`; it was found by a
// gate and repaired by hand in `1b7c0d5`. The guard written to make that repair
// durable could not see it. A GUARD THAT ASSERTS A PROPERTY STILL HAS TO
// TOKENISE THE SENTENCE, AND A TOKENISER IS ALSO AN ENUMERATION — of separators
// and of word forms, which is where round 7 went in.
//
// Both are closed by ONE definition ([_citationGap]) shared by every pattern,
// and by holding the contract nouns as stems that match `s?`. Widening a guard
// is the dangerous direction, so the negative table grew six hyphenated
// sentences at the same time: `a seven-case switch` really did turn RED under
// the singular nouns, and [_headSaysNotTheContract] exists because of it.
//
// So every check below is built the same way, and the shape is general:
//
//   * PARSE LOOSELY, JUDGE STRICTLY. A line that is shaped like an entry is
//     always READ as one; whether it is well formed is a separate, loud
//     assertion. A regex that refuses to match a malformed entry reports it as
//     MISSING, which is a weaker failure and a more confusing one.
//   * EVERY CANDIDATE LINE IS ACCOUNTED FOR. Inside a block, a line is prose (no
//     indent), an entry (indented, above the continuation level), or a
//     continuation (at the continuation level). An indented line that cannot be
//     read as an entry is a FAILURE, not a skip — and a continuation line that
//     reads like an entry head is one too, which is what closes the
//     re-indentation evasion.
//   * THE FLOOR IS ON WHAT WAS READ, NOT ON WHAT PASSED, and every list has one.
//     [_kContractFloor] and its siblings are LOWER BOUNDS, not a third copy of
//     the list: they exist so that deleting a member is a deliberate edit here
//     rather than a silent shrink there. A round-6 mutation deleted an outcome
//     from BOTH files and the old guard stayed green, because set equality holds
//     over two sets that lost the same member.
//   * THE PATTERNS ARE PROVEN ABLE TO FIRE. All five prose regexes matched ZERO
//     live sites in the guarded files when round 6 measured them, so nothing in
//     the suite demonstrated they could produce a nonzero. The fixture table at
//     the bottom of this file is that demonstration: every phrasing that must
//     fire, and every ordinary-English phrasing that must not, asserted in both
//     directions.
//
// SCOPE, STATED SO NOBODY MISTAKES IT FOR MORE. This is a text check over four
// files. It does not read English. Two halves with two different scopes:
//
//   * THE ORDINAL CHECK runs over all four files in [_ordinalScanned]. It needs
//     no knowledge of the contract, so keeping it on two files was what let a
//     live false ordinal sit in `ie_parser_test.dart` through two gate rounds:
//     "the seventh case below" described the SIXTH. Round 5 repaired one instance
//     of that class by hand without grepping for the class, which is the mistake
//     this widening exists to stop repeating.
//   * THE COUNT CHECK runs only over [_countScanned], the two BSS Load files,
//     because it verifies a stated number against the honesty contract's real
//     size and running that over an unrelated list would be a category error.
//
// What it does NOT catch, enumerated because an unbounded claim about a guard is
// the thing that got flagged in round 5:
//
//   * a spelled-out ordinal in a shape not listed (`the penultimate rule`, `the
//     last case`, `the one before ABSENT`);
//   * a citation using a noun outside [_citableNouns] (`the third bullet`);
//   * `noun + number` over a noun in [_citableNouns] but not [_indexedNouns].
//     The two sets differ deliberately and round 6 measured why: `states four
//     outcomes`, `answers 200`, `point five percent` and `reading two octets`
//     all turned the build RED under one shared set, in a byte decoder whose
//     entire subject is reading octets. Those words are VERBS and MEASUREMENTS
//     here, not list members. `the second state` is still caught, because a
//     determiner and an ordinal in front of it remove the ambiguity;
//   * `reading`/`readings` as a citable noun at all — it names an INSTANCE
//     ([BssLoadReading]), not a contract member. It is still counted by
//     [_statedInstanceCount] when an enumerating word marks the phrase;
//   * a positional citation with no determiner. [_ordinalByPosition] requires
//     one because without it the pattern fired on "insert a fifth outcome",
//     which ADDS a member rather than citing one. The determiner set now
//     includes possessives — round 6 walked "the contract's second outcome" and
//     "its third branch" straight past the round-5 set;
//   * an ordinal inside DOUBLE QUOTES, which is a MENTION rather than a use.
//     `ie_parser_test.dart` documents its own repair with the sentence
//     `the paragraph below used to say "Edit 3"`, and a guard that turns the
//     build red on the record of its own fix is a guard that gets deleted
//     ([[feedback_guard_must_not_penalise_the_trace]]). Backticks are NOT
//     suppressed, so a backticked ordinal still fires;
//   * a citation separated by an EM DASH (`the entry — 3 lines below`).
//     [_citationGap] covers whitespace, the ASCII hyphen and U+2010..U+2013,
//     and stops deliberately short of U+2014: this codebase writes em-dash
//     parentheticals constantly, so covering it would turn the house
//     punctuation style into a build failure. Locked by a fixture;
//   * an attributive singular whose HEAD NOUN is in [_notTheContract] (`a
//     seven-case switch`). That exception is what makes reading `three-state`
//     affordable, and it is a deliberately bought miss: a citation phrased
//     `a three-case test` will not fire;
//   * an INSTANCE noun in its attributive singular (`a four-reading average`).
//     [_instanceNouns] are still plural-only, because they are already the
//     narrower check — they need an [_enumerating] word before they count at
//     all, and no compound of that shape has been written in these files;
//   * a stated count using a noun outside [_contractNouns] and [_instanceNouns],
//     or one that happens to equal the contract's size while counting something
//     else entirely. THIS IS LIVE AND KNOWN: `bss_load_decoder.dart` carries a
//     bullet list of walk outcomes that is a DIFFERENT list from the honesty
//     contract and coincidentally also had four members. Its sentence used to
//     state that count; the count was removed rather than covered, because
//     teaching this check to verify `things` against the contract's size would
//     have made a sentence about one list pass on the size of another;
//   * a stated count with more than four words between the number and the noun;
//     any count whose nearest preceding number word is a different one — "two
//     of the four outcomes" is read as a claim about `four`; and any count with
//     an intervening PLURAL NOUN, because that noun re-heads the phrase. All
//     three exclusions were forced by ordinary sentences, and the third by a
//     sentence in this very file: "a sentence in the two BSS Load files states
//     a count" is `two … states`, and `states` is a verb there;
//   * anything at all in a fifth file.
//
// It guards the mistake that actually happened, in the files it happened in, and
// the files it guards say so at the claim rather than only here.
//
// Build: Felix 2026-08-01, round 4 findings. Rewritten from Vera's round-5
// H1/M1/M2/M3, again from her round-6 H1/H2/H3/M1/M2/M3/L1/L2, and widened
// 2026-08-02 from the round-7 cold-eyes gate's H1/H2/H3.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ── The guarded files ────────────────────────────────────────────────────────

/// A file this guard reads, with the evidence that the read produced the RIGHT
/// file. A guard whose finding is partly an absence must first show it was
/// holding something.
class _GuardedFile {
  const _GuardedFile(this.path, this.token, this.minTokenHits);

  /// Repo-relative path.
  final String path;

  /// A substring that any real version of this file contains many times.
  final String token;

  /// How many lines must contain [token] before a zero from this file means
  /// anything.
  final int minTokenHits;
}

const _GuardedFile _decoder = _GuardedFile(
  'lib/services/network/bss_load_decoder.dart',
  'BSS Load',
  3,
);
const _GuardedFile _decoderTest = _GuardedFile(
  'test/services/network/bss_load_decoder_test.dart',
  'BSS Load',
  3,
);
const _GuardedFile _ieParser = _GuardedFile(
  'lib/services/network/ie_parser.dart',
  'nformationElement',
  3,
);
const _GuardedFile _ieParserTest = _GuardedFile(
  'test/services/network/ie_parser_test.dart',
  'nformationElement',
  3,
);

/// Files whose prose may not cite a numbered list by ordinal. Four, because the
/// ordinal check needs nothing from the contract — see SCOPE.
const List<_GuardedFile> _ordinalScanned = <_GuardedFile>[
  _decoder,
  _decoderTest,
  _ieParser,
  _ieParserTest,
];

/// Files whose stated counts are verified against the honesty contract's size.
/// Two, because that check is about THIS contract specifically.
const List<_GuardedFile> _countScanned = <_GuardedFile>[_decoder, _decoderTest];

// ── Block anchors and shapes ─────────────────────────────────────────────────

/// A named list living inside a comment block, with the anchors that bound it
/// and the indentation that separates an entry from the prose continuing it.
///
/// [continuationIndent] is the load-bearing number: below it a line is an ENTRY
/// and must parse as one; at or above it a line is prose continuing the entry
/// above, and must NOT read like an entry head. Both halves are asserted, which
/// is what makes re-indentation loud instead of invisible.
class _NamedBlock {
  const _NamedBlock({
    required this.open,
    required this.close,
    required this.continuationIndent,
    required this.floor,
  });

  final String open;
  final String close;
  final int continuationIndent;

  /// The minimum number of entries this block may contain. A LOWER BOUND, not a
  /// copy of the list. See the header: a shrink must be a deliberate edit here.
  final int floor;
}

/// The honesty contract in `bss_load_decoder.dart`: four outcomes today.
const _NamedBlock _contractBlock = _NamedBlock(
  open: '── HONESTY CONTRACT',
  close: 'IS THE ONE THAT KEEPS BEING OVER-CLAIMED',
  continuationIndent: 5,
  floor: _kContractFloor,
);

/// Its mirror in `bss_load_decoder_test.dart`. Same floor, because the two are
/// asserted equal anyway — a floor on only one of them is a floor on neither.
const _NamedBlock _mirrorBlock = _NamedBlock(
  open: '── OUTCOMES, MIRRORED FROM THE DECODER',
  close: 'Only ABSENT says anything about the AP',
  continuationIndent: 5,
  floor: _kContractFloor,
);

/// The precedence list in `decodeBssLoad`'s doc comment: six steps today. It
/// KEEPS its numbers, because there the order is the content — what is enforced
/// is that every step also carries a NAME.
const _NamedBlock _precedenceBlock = _NamedBlock(
  open: 'Precedence, in order.',
  close: 'The blob is walked twice',
  continuationIndent: 6,
  floor: 6,
);

/// Today's contract size. A lower bound on both the contract and its mirror.
const int _kContractFloor = 4;

/// The indentation of ordinary prose inside a comment: one space after the
/// marker, this codebase's house style. Anything indented further, and below the
/// block's continuation level, is an ENTRY and must parse as one.
const int _kProseIndent = 1;

// ── Entry shape ──────────────────────────────────────────────────────────────

/// An entry head, captured LOOSELY on purpose: any non-space run, then a
/// separator, then a space.
///
/// THE SEPARATOR SET IS WIDE AND THE JUDGEMENT IS NARROW. Round 6 added a fifth
/// outcome written `OVERFLOW - …` with an ASCII hyphen and the em-dash-only
/// regex did not reject it, it did not SEE it: the entry dropped out of the set,
/// set equality still held between two equally incomplete sets, and the build
/// was green. A malformed entry must be read and then judged, never skipped.
final RegExp _entryHead = RegExp(r'^(\S.*?)\s+[—–:-]\s');

/// A label that is a NAME and nothing else: upper-case words joined by spaces,
/// with digits allowed only after a hyphen. `ABSENT`, `NOTHING TO READ`,
/// `CLIPPED-ELSEWHERE` and `CLIPPED-11` pass. `1. ABSENT`, `1) ABSENT`,
/// `(1) ABSENT`, `1 ABSENT`, `I. ABSENT`, `ABSENT 2` and a sentence do not.
///
/// ONE DEFINITION FOR BOTH BLOCKS. Round 6 found the contract and the precedence
/// list disagreeing about what a name is — the contract permitted `NOTHING TO
/// READ` while the precedence list rejected `WALK TAIL` as unnamed, and reported
/// a two-word name as no name at all.
final RegExp _bareName = RegExp(r'^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+|\s[A-Z][A-Z0-9]*)*$');

/// A well-formed roman numeral, used to catch the one numbering scheme
/// [_bareName] would otherwise accept (`I ABSENT`, `II NOTHING TO READ`).
///
/// VALIDITY ALONE IS NOT ENOUGH, and round 6 proved it: `ID MISMATCH` was
/// rejected as a roman numeral, and `MID`, `MIX`, `DC` and `CIVIC` collide the
/// same way. A first word is a NUMBERING only when it is a valid numeral AND its
/// value is the entry's own position. `MIX` at position four is a name; `IV` at
/// position four is a number.
final RegExp _romanNumeral =
    RegExp(r'^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$');

const Map<String, int> _romanDigits = <String, int>{
  'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000,
};

/// The value of [word] as a roman numeral, or null when it is not one.
int? _romanValue(String word) {
  if (word.isEmpty || !_romanNumeral.hasMatch(word)) return null;
  int total = 0;
  for (int i = 0; i < word.length; i++) {
    final int current = _romanDigits[word[i]]!;
    final int next =
        i + 1 < word.length ? _romanDigits[word[i + 1]]! : 0;
    total += current < next ? -current : current;
  }
  return total;
}

/// A precedence step head: `N.` then a name. The number is required — order is
/// the content there — and so is the name.
final RegExp _precedenceHead = RegExp(r'^(\d+)\.\s+(.+)$');

// ── Prose checks ─────────────────────────────────────────────────────────────

/// Nouns that can name a member of a numbered list when a determiner and an
/// ordinal sit in front of them: "the second state", "its third branch". The
/// determiner removes the verb reading, so this set can be wide.
const List<String> _citableNouns = <String>[
  'case', 'rule', 'outcome', 'state', 'step', 'item', 'branch', 'point',
  'entry', 'clause', 'reason', 'answer', 'precedence', 'edit', 'bullet',
];

/// The narrower set for `noun + number` citations (`rule 2`, `case three`).
///
/// EVERY WORD MISSING FROM HERE WAS MEASURED, NOT GUESSED. Under one shared set
/// the build went RED on "the paragraph states four outcomes", "the endpoint
/// answers 200", "a point five percent difference" and "reading two octets
/// little-endian" — four ordinary sentences in a byte decoder, none of them
/// citing anything. `state`, `answer`, `point` and `reason` are verbs or
/// measurements in this register; `reading` names an instance. A guard authors
/// have to write around is a guard authors delete.
const List<String> _indexedNouns = <String>[
  'case', 'rule', 'outcome', 'step', 'item', 'branch', 'entry', 'clause',
  'precedence', 'edit', 'bullet',
];

/// Nouns the honesty contract's members have actually been called, across every
/// revision of these files, as SINGULAR STEMS: `outcomes` today, `states`,
/// `answers` and `cases` in the versions the gate rounds were run against. A
/// count in front of one of these is CHECKED against the contract's real size —
/// not forbidden.
///
/// THE STEM IS THE LOAD-BEARING PART, and it was learned on a sentence that was
/// really in this repo. `bss_load_decoder_test.dart` carried
/// `isDecoded answers the three-state question` — three, against a contract of
/// four. That is precisely the false count this check exists to catch, and the
/// round-7 gate found the guard GREEN over it. The set held PLURALS ONLY, so the
/// attributive singular `three-state` had no noun to match and the count check
/// never ran. It was repaired by hand in `1b7c0d5`; the guard that was supposed
/// to make that repair durable would not have found it, and would not find it
/// coming back. [_contractNounsAlt] now closes on `s?`, so the plural and the
/// attributive singular both fire.
const List<String> _contractNouns = <String>[
  'state', 'outcome', 'answer', 'case',
];

/// Nouns that name INSTANCES rather than contract members. `BssLoadReading` is a
/// type, and `bss_load_decoder_test.dart` writes "Two readings that compare
/// equal cannot be told apart downstream" — a true sentence about two objects,
/// not a miscount of the contract.
///
/// Counted only when the phrase carries a word that marks it as an enumeration
/// of the contract ("four DIFFERENT readings"). Bare "two readings" is left
/// alone.
const List<String> _instanceNouns = <String>['readings', 'results', 'branches'];

/// The words that turn an instance noun into an enumeration of the contract.
const List<String> _enumerating = <String>[
  'different', 'distinct', 'separate', 'possible', 'honest', 'named',
];

/// Words that, sitting between the number and the noun, say the phrase is not
/// counting the contract. "the two test cases below" is ordinary English in a
/// test file and must not turn the build red.
///
/// This is the one hand-authored exception list left in the guard, and it is
/// old-shaped. It sits on a VERIFY rule, so abusing it costs a missed check
/// rather than a false block — which is the only reason it is tolerable.
const List<String> _notTheContract = <String>[
  'test', 'tests', 'edge', 'corner', 'switch', 'vector', 'vectors', 'use',
];

/// `two`..`ten`. `one` is excluded from COUNTS: "the one place byte order is
/// decided" is prose about something else, and a contract with one member is not
/// the failure mode this guards.
const Map<String, int> _numberWords = <String, int>{
  'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
};

/// Determiners that make a positional phrase a CITATION rather than an addition.
/// A citation is definite ("the fifth outcome", "the contract's second
/// outcome"); an addition is indefinite ("a fifth outcome"). `a` and `an` are
/// deliberately absent.
const String _determinersAlt =
    "the|that|this|these|those|its|our|their|his|her|my|your|said|[A-Za-z]+'s";

final String _citableNounsAlt = _citableNouns.join('|');
final String _indexedNounsAlt = _indexedNouns.join('|');
/// The contract nouns as an alternation that matches the plural AND the
/// attributive singular: `four outcomes`, `three-state`. See [_contractNouns].
final String _contractNounsAlt = '(?:${_contractNouns.join('|')})s?';
final String _instanceNounsAlt = _instanceNouns.join('|');

/// Every counting word this guard understands, as an alternation.
const String _numbersAlt = 'two|three|four|five|six|seven|eight|nine|ten';

/// Every positional word, as an alternation.
const String _positionsAlt =
    'first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth';

/// What may sit between the parts of a citation: whitespace, an ASCII hyphen,
/// or the typographic dashes U+2010..U+2013 (hyphen, non-breaking hyphen,
/// figure dash, en dash).
///
/// A HYPHEN IS A SEPARATOR, NOT AN ESCAPE HATCH. The round-7 gate defeated all
/// three ordinal patterns with one character: `rule 2`, `rule two` and `the
/// second rule` were already in [_mustFire] and RED, while `rule-2`,
/// `rule-two` and `the second-rule` were green. The patterns joined their parts
/// with `\s+`, which cannot match a hyphen — and [_statedCount] below had
/// already been written with the wider class, so the file disagreed with itself.
/// One definition now, used by every one of them.
///
/// THE UNICODE DASHES WERE MEASURED, NOT ASSUMED. The gate listed them as
/// "likely open, but that is an inference, not a measurement". They were open:
/// `rule‑2` with a non-breaking hyphen and `rule–2` with an en dash both sat
/// green after the ASCII widening, and all four are now fixtures.
///
/// THE EM DASH IS EXCLUDED DELIBERATELY, and it is the one dash that must be.
/// This codebase writes em-dash parentheticals everywhere — including this
/// comment — so `the entry — 3 lines below` is ordinary prose here, not a
/// citation. Including U+2014 would turn the house punctuation style into a
/// build failure, which is how a guard gets deleted. Locked by a fixture in
/// [_mustNotFire].
const String _citationGap = '[\\s\\u2010-\\u2013-]+';

/// `case 3`, `rule 2`, `step 4`, `rule-2`.
final RegExp _ordinalByDigit =
    RegExp('\\b($_indexedNounsAlt)s?$_citationGap\\d+\\b', caseSensitive: false);

/// `case three`, `rule two`, `rule-two` — the same citation spelled out.
final RegExp _ordinalByWord = RegExp(
  '\\b($_indexedNounsAlt)s?$_citationGap(one|$_numbersAlt)\\b',
  caseSensitive: false,
);

/// `the second rule`, `that third case`, `the contract's second outcome`,
/// `the second-rule`.
final RegExp _ordinalByPosition = RegExp(
  '\\b($_determinersAlt)$_citationGap($_positionsAlt)$_citationGap'
  '($_citableNounsAlt)s?\\b',
  caseSensitive: false,
);

/// The maximum number of words allowed between the number and the noun it
/// counts. Round 6 walked "seven clearly quite distinct outcomes" past a bound
/// of two. Widening is safe only because of [_nearestNumberWins].
const int _kCountGap = 4;

/// A stated count of the contract's members. Shares [_citationGap], which is
/// what lets `three-state` and `three–state` be read the same way as
/// `three states`.
final RegExp _statedCount = RegExp(
  '\\b($_numbersAlt)$_citationGap'
  '((?:[\\w-]+$_citationGap){0,$_kCountGap}?)($_contractNounsAlt)\\b',
  caseSensitive: false,
);

/// The same count over an instance noun, and only when an [_enumerating] word
/// says the phrase is counting the contract. At least one word must sit between
/// the number and the noun, because that word is what does the marking.
final RegExp _statedInstanceCount = RegExp(
  '\\b($_numbersAlt)$_citationGap'
  '((?:[\\w-]+$_citationGap){1,$_kCountGap}?)($_instanceNounsAlt)\\b',
  caseSensitive: false,
);

/// Real Dart switch syntax, which is code rather than a reference.
final RegExp _switchCase = RegExp(r'^\s*case\s+\d+\s*:');

/// Closed-class words that end in `s` without being plural nouns. English
/// function words are a closed class, which is what makes listing them a rule
/// rather than a whitelist of bug spellings.
const Set<String> _functionWordsEndingInS = <String>{
  'these', 'those', 'this', 'its', 'his', 'hers', 'ours', 'theirs', 'yours',
  'as', 'is', 'was', 'has', 'thus', 'plus', 'less', 'always', 'perhaps',
};

/// True when [word], sitting between a number and a counted noun, is itself the
/// plural noun the number is really counting.
///
/// WHY THIS EXISTS, and it was learned on a sentence written three minutes
/// earlier. Widening the word gap to four made "a sentence in the two BSS Load
/// files states a count" match as `two … states`, because `states` is one of
/// the nouns the contract's members have been called AND a third-person verb.
/// The head of that phrase is `files`. An intervening plural noun re-heads the
/// phrase, so the counted noun after it is not what the number counts.
bool _reHeadsThePhrase(String word) {
  if (word.length < 4) return false;
  if (!word.endsWith('s')) return false;
  if (word.endsWith('ss') || word.endsWith('ous')) return false;
  if (_functionWordsEndingInS.contains(word)) return false;
  return !_enumerating.contains(word);
}

/// The next whole word after [offset] in [text], lower-cased; empty when the
/// match ends the paragraph.
String _wordAfter(String text, int offset) {
  final RegExpMatch? m = RegExp('^(?:$_citationGap)?([A-Za-z][\\w-]*)')
      .firstMatch(text.substring(offset));
  return m == null ? '' : m.group(1)!.toLowerCase();
}

/// True when a count matched an ATTRIBUTIVE SINGULAR whose head noun says the
/// phrase is not counting the contract.
///
/// WHY THIS EXISTS, and it is the price of reading `three-state`. An attributive
/// singular does not stand alone — it modifies the noun after it, and THAT noun
/// is the head of the phrase. `a seven-case switch` counts SWITCH ARMS, and
/// `switch` is already in [_notTheContract] for the mirror-image phrasing `seven
/// switch cases`. Teaching the check to read the singular without this taught it
/// to fail on every such compound, which was measured, not feared: adding
/// `A seven-case switch covers every reason the decoder can return.` to
/// [_mustNotFire] turned it RED before this existed. `three-state question`
/// still fires, because `question` is not one of those words.
///
/// Plurals are excluded because they head their own phrase; only the singular
/// borrows one.
bool _headSaysNotTheContract(String noun, String next) =>
    !noun.endsWith('s') && _notTheContract.contains(next);

// ── Machinery ────────────────────────────────────────────────────────────────

/// A run of consecutive comment lines joined into one string, keeping enough
/// bookkeeping to report the SOURCE line a match landed on.
///
/// Scanning per paragraph rather than per line is what closes the line-wrap
/// evasion: `precedence rule` at the end of one line and `2 above` at the start
/// of the next is one citation, and a per-line scanner cannot see it.
class _Paragraph {
  _Paragraph(this.text, this._starts);

  final String text;
  final List<_LineStart> _starts;

  int lineAt(int offset) {
    int line = _starts.first.lineNumber;
    for (final _LineStart s in _starts) {
      if (s.offset > offset) break;
      line = s.lineNumber;
    }
    return line;
  }
}

class _LineStart {
  const _LineStart(this.offset, this.lineNumber);
  final int offset;
  final int lineNumber;
}

/// The comment marker at the head of a line, if there is one.
final RegExp _commentMarker = RegExp(r'^/{2,}');

/// A comment line split into the indentation INSIDE the comment and its body.
/// Returns null for a line that is not a comment.
///
/// The indent is what separates an entry from the prose continuing it, so it is
/// measured after the marker, not before it.
({int indent, String body})? _commentParts(String line) {
  final String trimmed = line.trimLeft();
  final Match? marker = _commentMarker.matchAsPrefix(trimmed);
  if (marker == null) return null;
  final String rest = trimmed.substring(marker.end);
  int indent = 0;
  while (indent < rest.length && rest[indent] == ' ') {
    indent++;
  }
  return (indent: indent, body: rest.trim());
}

/// Splits [lines] into scannable units: each run of consecutive non-empty
/// comment lines becomes one paragraph; every other line stands alone, so a
/// `group('…')` name or a `reason:` string is still scanned. Those are prose a
/// reader trusts exactly as much as a comment.
List<_Paragraph> _paragraphs(List<String> lines) {
  final List<_Paragraph> out = <_Paragraph>[];
  final StringBuffer buffer = StringBuffer();
  List<_LineStart> starts = <_LineStart>[];

  void flush() {
    if (starts.isEmpty) return;
    out.add(_Paragraph(buffer.toString(), starts));
    buffer.clear();
    starts = <_LineStart>[];
  }

  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final ({int indent, String body})? parts = _commentParts(line);
    if (parts != null) {
      // An empty comment line is a paragraph break in this codebase's house
      // style, and joining across one would invent adjacencies that are not in
      // the prose.
      if (parts.body.isEmpty) {
        flush();
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      starts.add(_LineStart(buffer.length, i + 1));
      buffer.write(parts.body);
      continue;
    }
    flush();
    if (_switchCase.hasMatch(line)) continue;
    out.add(_Paragraph(line, <_LineStart>[_LineStart(0, i + 1)]));
  }
  flush();
  return out;
}

/// The `[start, end)` spans of double-quoted runs in [text].
///
/// A citation inside quotation marks is a MENTION, not a use — the sentence is
/// reporting what some other text said, which is exactly what the record of a
/// repair looks like. Unpaired quotes yield no span, so nothing is suppressed by
/// accident.
List<({int start, int end})> _quotedSpans(String text) {
  final List<({int start, int end})> spans = <({int start, int end})>[];
  int? open;
  for (int i = 0; i < text.length; i++) {
    if (text[i] != '"') continue;
    if (open == null) {
      open = i;
    } else {
      spans.add((start: open, end: i + 1));
      open = null;
    }
  }
  return spans;
}

bool _isQuoted(List<({int start, int end})> spans, int start, int end) =>
    spans.any((({int start, int end}) s) => start >= s.start && end <= s.end);

/// Reads a file and proves the read produced real content before any absence
/// assertion is believed.
///
/// THIS IS NOT CEREMONY. An md5 comparison in this same work stream reported
/// SAME twice, over the digest of an empty string. A guard whose finding is an
/// absence must first show it was holding something.
List<String> _readGuardedFile(_GuardedFile file) {
  final File handle = File(file.path);
  expect(handle.existsSync(), isTrue, reason: '${file.path} not found');
  final List<String> lines = handle.readAsLinesSync();
  expect(
    lines.length,
    greaterThan(200),
    reason: '${file.path} read as ${lines.length} lines — the guard is looking '
        'at the wrong thing, not at a clean file',
  );
  expect(
    lines.where((String l) => l.contains(file.token)).length,
    greaterThan(file.minTokenHits),
    reason: '${file.path} does not read like the file this guard was written '
        'for ("${file.token}" is nearly absent); a zero from it would mean '
        'nothing',
  );
  return lines;
}

/// Index range `[open, close)` of an anchored block, with a loud failure at each
/// way the anchors can fail to resolve.
({int open, int close}) _blockRange(
  List<String> lines,
  String path,
  _NamedBlock block,
) {
  final int start = lines.indexWhere((String l) => l.contains(block.open));
  expect(
    start,
    isNot(-1),
    reason: '$path: the block anchored to "${block.open}" was not found. '
        'Without it this check would scan an empty range and report clean.',
  );
  final int end =
      lines.indexWhere((String l) => l.contains(block.close), start + 1);
  expect(
    end,
    isNot(-1),
    reason: '$path: no closing anchor ("${block.close}") after "${block.open}"; '
        'scanning to EOF would make this check meaningless.',
  );
  expect(
    end - start,
    greaterThan(4),
    reason: '$path: the block between "${block.open}" and "${block.close}" read '
        'as ${end - start} lines — too short to be the real list',
  );
  return (open: start, close: end);
}

/// One parsed entry, and everything the guard could not parse alongside it.
class _BlockReading {
  _BlockReading(this.entries, this.unreadable);

  /// `(line, label)` for every entry that was READ. Whether each label is
  /// well formed is judged separately and loudly.
  final List<({int line, String label})> entries;

  /// Lines inside the block that are shaped like an entry and could not be read
  /// as one, or that sit at continuation indent while reading like an entry
  /// head. Each one is a hole in every downstream assertion.
  final List<String> unreadable;
}

/// Reads every line of an anchored block and accounts for ALL of them.
///
/// This is the round-6 fix and the reason the file's header says a parser is an
/// enumeration. The old reader ran one regex per line and silently skipped
/// whatever did not match, so an entry written with the wrong dash or the wrong
/// indent was not rejected — it was never seen, and every assertion downstream
/// became a claim about a smaller set.
_BlockReading _readBlock(
  List<String> lines,
  String path,
  _NamedBlock block,
  ({int open, int close}) range,
) {
  final List<({int line, String label})> entries =
      <({int line, String label})>[];
  final List<String> unreadable = <String>[];

  for (int i = range.open; i < range.close; i++) {
    final ({int indent, String body})? parts = _commentParts(lines[i]);
    if (parts == null || parts.body.isEmpty) continue;
    // Prose introducing or closing the block sits one space off the marker.
    if (parts.indent <= _kProseIndent) continue;

    if (parts.indent < block.continuationIndent) {
      final RegExpMatch? head = _entryHead.firstMatch(parts.body);
      if (head == null) {
        unreadable.add(
          'L${i + 1}: "${parts.body}" is indented like an entry but could not '
          'be read as one. An entry is "LABEL — prose"; a separator this parser '
          'does not know means the entry is INVISIBLE, not rejected.',
        );
        continue;
      }
      entries.add((line: i + 1, label: head.group(1)!));
      continue;
    }

    // At or past the continuation level: prose continuing the entry above. It
    // must not read like an entry head, or an author can hide a member by
    // pressing space twice.
    final RegExpMatch? head = _entryHead.firstMatch(parts.body);
    if (head != null && _bareName.hasMatch(head.group(1)!)) {
      unreadable.add(
        'L${i + 1}: "${parts.body}" sits at continuation indent '
        '(${parts.indent} spaces) but reads as an entry head. Entries live '
        'above ${block.continuationIndent} spaces; at or below that they are '
        'invisible to every check in this file.',
      );
    }
  }

  return _BlockReading(entries, unreadable);
}

/// Reads a block and asserts it was read COMPLETELY, then returns its entries.
_BlockReading _readBlockOrFail(
  List<String> lines,
  _GuardedFile file,
  _NamedBlock block,
) {
  final ({int open, int close}) range = _blockRange(lines, file.path, block);
  final _BlockReading reading = _readBlock(lines, file.path, block, range);

  expect(
    reading.unreadable,
    isEmpty,
    reason: 'Lines inside the block anchored to "${block.open}" in '
        '${file.path} could not be accounted for. This is the round-6 defect: '
        'what a parser cannot read, it passes in silence, and every assertion '
        'below it quietly becomes a claim about a smaller list:\n  '
        '${reading.unreadable.join('\n  ')}',
  );
  expect(
    reading.entries.length,
    greaterThanOrEqualTo(block.floor),
    reason: '${file.path}: only ${reading.entries.length} entries were read '
        'from the block anchored to "${block.open}" (lines '
        '${range.open + 1}..${range.close + 1}), and the floor is '
        '${block.floor}. Either a member was deleted — which set equality '
        'CANNOT see when both copies lose it — or the block was reformatted. '
        'If the list genuinely got shorter, lower the floor here deliberately.',
  );
  return reading;
}

/// The contract's member names, derived from the decoder rather than restated
/// here. This guard must not become a third place the list lives.
Set<String> _contractNames(List<String> decoderLines) =>
    _readBlockOrFail(decoderLines, _decoder, _contractBlock)
        .entries
        .map((({int line, String label}) e) => e.label)
        .toSet();

/// Every label that is not a bare NAME, with the reason.
List<String> _malformedLabels(List<({int line, String label})> entries) {
  final List<String> out = <String>[];
  for (int i = 0; i < entries.length; i++) {
    final ({int line, String label}) e = entries[i];
    if (!_bareName.hasMatch(e.label)) {
      out.add('L${e.line}: "${e.label}" is not a bare upper-case NAME');
      continue;
    }
    final String first = e.label.split(RegExp(r'[ -]')).first;
    final int? roman = _romanValue(first);
    if (roman != null && roman == i + 1) {
      out.add(
        'L${e.line}: "${e.label}" starts with the roman numeral for its own '
        'position ($roman), which is a numbering scheme wearing a name',
      );
    }
  }
  return out;
}

/// Every ordinal citation and false count in [lines].
///
/// Factored out so the fixture table at the bottom of this file can drive it
/// directly. All five patterns matched ZERO live sites when round 6 measured
/// them, and a check with no live subject and no fixture is a check nobody has
/// ever seen produce a nonzero.
List<String> _proseOffences(
  List<String> lines, {
  required int contractSize,
  required bool checkCounts,
}) {
  final List<String> offences = <String>[];

  for (final _Paragraph p in _paragraphs(lines)) {
    final List<({int start, int end})> quoted = _quotedSpans(p.text);

    for (final RegExp r in <RegExp>[
      _ordinalByDigit,
      _ordinalByWord,
      _ordinalByPosition,
    ]) {
      for (final RegExpMatch m in r.allMatches(p.text)) {
        if (_isQuoted(quoted, m.start, m.end)) continue;
        offences.add(
          'L${p.lineAt(m.start)} cites a list by ordinal: "${m[0]}" — name the '
          'member instead. An ordinal has no grep handle, so an insertion '
          'falsifies this sentence in silence.',
        );
      }
    }

    if (!checkCounts) continue;

    // VERIFY, DO NOT FORBID. "four outcomes" is true today and is allowed to
    // say so; it turns red the moment a fifth entry appears in the contract
    // block. The predecessor forbade the true sentence outright, which meant
    // hand-carving exceptions for ordinary English — and it was one of those
    // carve-outs that made it fail on "two test cases".
    for (final RegExpMatch m in <RegExpMatch>[
      ..._statedCount.allMatches(p.text),
      ..._statedInstanceCount.allMatches(p.text),
    ]) {
      if (_isQuoted(quoted, m.start, m.end)) continue;
      final List<String> between = (m.group(2) ?? '')
          .toLowerCase()
          .split(RegExp(_citationGap))
          .where((String w) => w.isNotEmpty)
          .toList();
      if (between.any(_notTheContract.contains)) continue;
      // THE NEAREST NUMBER WINS. Widening the gap to four words made "two of
      // the four outcomes" match twice — once truthfully on `four`, once
      // falsely on `two`. The number that counts a noun is the one closest to
      // it, so a match with another number word in between is not a count.
      if (between.any(_numberWords.containsKey) ||
          between.any((String w) => RegExp(r'^\d+$').hasMatch(w))) {
        continue;
      }
      // An intervening plural noun is the real head of the phrase — see
      // [_reHeadsThePhrase]. Without this, widening the gap turns `states` and
      // `answers` back into the verbs they also are.
      if (between.any(_reHeadsThePhrase)) continue;
      // AN ATTRIBUTIVE SINGULAR BORROWS THE HEAD AFTER IT — see
      // [_headSaysNotTheContract]. This is the mirror of the rule above: there
      // an intervening plural re-heads the phrase, here a following noun does.
      if (_headSaysNotTheContract(
        m.group(3)!.toLowerCase(),
        _wordAfter(p.text, m.end),
      )) {
        continue;
      }
      if (_instanceNouns.contains(m.group(3)!.toLowerCase()) &&
          !between.any(_enumerating.contains)) {
        continue;
      }
      final int stated = _numberWords[m.group(1)!.toLowerCase()]!;
      if (stated == contractSize) continue;
      offences.add(
        'L${p.lineAt(m.start)} states a count that is not the contract\'s '
        'size: "${m[0]}" says $stated, the honesty contract has $contractSize '
        'entries.',
      );
    }
  }

  return offences;
}

/// [_proseOffences] over a single sentence, for the fixture table.
List<String> _scanSentence(String sentence) => _proseOffences(
      <String>['// $sentence'],
      contractSize: 4,
      checkCounts: true,
    );

// ── Fixtures ─────────────────────────────────────────────────────────────────

/// Sentences that MUST turn the build red, each one an end-to-end mutation that
/// defeated some version of this guard.
///
/// The last nine are round 7's, and they are the same three citations the first
/// eleven already caught, respelled with a hyphen or a typographic dash, plus
/// the false count `three-state` that was really written in
/// `bss_load_decoder_test.dart` and had to be repaired by hand. Every one of
/// them was verified GREEN against the unwidened patterns before the widening
/// landed — a fixture nobody has watched fail is a claim, not a guard
/// ([[feedback_red_green_is_not_coverage]]).
const List<String> _mustFire = <String>[
  'See precedence rule 2 above for the ordering.',
  'See precedence step 2 above for the ordering.',
  'The second rule is the one that matters.',
  "This is the contract's second outcome, restated.",
  'The decoder reaches its third branch here.',
  'The third case below is the one that matters.',
  'See case 3 above for the shape.',
  'There are seven outcomes in the contract above.',
  'There are seven clearly quite distinct outcomes in the contract above.',
  'The decoder produces seven different readings in all.',
  'Rule two is where the order is decided.',
  'See precedence rule-2 above for that ordering.',
  'See precedence rule-two above for that ordering.',
  'The second-rule here is the one that matters most.',
  'isDecoded answers the three-state question in both directions.',
  'The three state question is answered in both directions.',
  'See precedence rule‑2 above for that ordering.',
  'See precedence rule–2 above for that ordering.',
  'The second–rule here is the one that matters most.',
  'isDecoded answers the three–state question in both directions.',
];

/// Sentences that MUST NOT turn the build red. Every one of these was either
/// written by hand in these files or produced a false red in a gate round; a
/// guard authors have to write around is a guard authors delete.
const List<String> _mustNotFire = <String>[
  'The two test cases below are ordinary prose about this file.',
  'Insert a fifth outcome over there and this list goes red.',
  'Two readings that compare equal cannot be told apart downstream.',
  'Reading two octets little-endian is the whole of it.',
  'The first reading of the field is the one that counts.',
  'The paragraph above states four outcomes and is right to.',
  'Two of the four outcomes are about our own read.',
  'The endpoint answers 200 for a healthy host.',
  'A point five percent difference is below the noise floor.',
  'A sentence in the two BSS Load files states a count of these outcomes.',
  'There are four outcomes in the contract above.',
  'The four outcomes are named, never numbered.',
  'Three edge cases cover the boundary.',
  'The list used to say "Edit 3", which is a reference with no grep handle.',
  'The one place byte order is decided is here.',
  // ROUND 7. Six hyphenated sentences, because the widening to `[\s-]+` and the
  // typographic dashes had to be provable against ordinary hyphenated English,
  // and a negative table with one hyphen in it could not do that. The
  // `seven-case switch` line is not decoration: it turned the build RED when
  // the singular contract nouns first landed, and [_headSaysNotTheContract]
  // exists because of it. The em-dash line locks the one dash [_citationGap]
  // deliberately does not include.
  'A first-class citizen of the parser is the element header.',
  'The second-order effect is well below the noise floor.',
  'A three-byte header precedes the payload.',
  'The two-step handshake is out of scope for this decoder.',
  'A seven-case switch covers every reason the decoder can return.',
  'The entry — 3 lines below — explains how the tail is walked.',
];

void main() {
  group('BSS Load contracts are named, never numbered', () {
    test('the honesty contract is a list of NAMES, and ALL of them were read',
        () {
      final List<String> lines = _readGuardedFile(_decoder);
      final _BlockReading reading =
          _readBlockOrFail(lines, _decoder, _contractBlock);

      expect(
        _malformedLabels(reading.entries),
        isEmpty,
        reason: 'These contract entries are not bare upper-case NAMES. A '
            'numeral, a parenthesis or a positional roman numeral in front of '
            'the name reintroduces the one handle nothing can grep: insert an '
            'outcome and every later ordinal changes, silently falsifying any '
            'sentence that cited one. The outcomes already have names; cite '
            'those:\n  ${_malformedLabels(reading.entries).join('\n  ')}',
      );

      final Set<String> unique = reading.entries
          .map((({int line, String label}) e) => e.label)
          .toSet();
      expect(
        unique.length,
        reading.entries.length,
        reason: 'two contract entries share a name, so a citation of that name '
            'is ambiguous: '
            '${reading.entries.map((({int line, String label}) e) => e.label).toList()}',
      );
    });

    test('the decoder test file mirrors the contract member for member', () {
      final List<String> decoder = _readGuardedFile(_decoder);
      final List<String> tests = _readGuardedFile(_decoderTest);

      final Set<String> contract = _contractNames(decoder);
      final _BlockReading mirrorReading =
          _readBlockOrFail(tests, _decoderTest, _mirrorBlock);
      final Set<String> mirror = mirrorReading.entries
          .map((({int line, String label}) e) => e.label)
          .toSet();

      expect(contract, isNotEmpty, reason: 'no contract names were derived');
      expect(
        _malformedLabels(mirrorReading.entries),
        isEmpty,
        reason: 'the mirror carries a label that is not a bare NAME:\n  '
            '${_malformedLabels(mirrorReading.entries).join('\n  ')}',
      );

      // SET EQUALITY, which is what closes the hole a naming convention alone
      // leaves open. Naming protects a REFERENCE — grep the name and you find
      // every mention. It does not protect an ENUMERATION: a list of four names
      // stays syntactically perfect when a fifth outcome is added, and simply
      // becomes incomplete. Only comparing the two sets catches that.
      //
      // What it does NOT catch is both copies losing the SAME member, which is
      // why both blocks carry a floor.
      expect(
        mirror,
        contract,
        reason: 'The outcome list in ${_decoderTest.path} no longer matches the '
            'honesty contract in ${_decoder.path}.\n'
            '  only in the contract: ${contract.difference(mirror)}\n'
            '  only in the mirror:   ${mirror.difference(contract)}\n'
            'Add the new outcome to the mirror, or fix the name. An '
            'enumeration that quietly loses a member is the defect this pair '
            'exists to make loud.',
      );
    });

    test('every precedence step is numbered in order AND named', () {
      final List<String> lines = _readGuardedFile(_decoder);
      final _BlockReading reading =
          _readBlockOrFail(lines, _decoder, _precedenceBlock);

      final List<String> malformed = <String>[];
      final List<int> numbers = <int>[];
      for (final ({int line, String label}) e in reading.entries) {
        final RegExpMatch? head = _precedenceHead.firstMatch(e.label);
        if (head == null) {
          malformed.add(
            'L${e.line}: "${e.label}" is not "N. NAME". The precedence list '
            'KEEPS its numbers — order is the content there — so the number is '
            'required and so is the shape: `7)` is a step this guard cannot '
            'read, which is how an unnamed step passed round 6.',
          );
          continue;
        }
        numbers.add(int.parse(head.group(1)!));
        final String name = head.group(2)!;
        if (!_bareName.hasMatch(name)) {
          malformed.add(
            'L${e.line}: step ${head.group(1)} has no NAME ("$name"). The name '
            'is the only handle another paragraph can cite that survives an '
            'insertion. Give it a short upper-case one; two words are fine.',
          );
        }
      }

      expect(
        malformed,
        isEmpty,
        reason: 'The precedence list in ${_decoder.path} is malformed:\n  '
            '${malformed.join('\n  ')}',
      );
      expect(
        numbers,
        List<int>.generate(numbers.length, (int i) => i + 1),
        reason: 'the precedence steps are numbered $numbers, which is not '
            '1..${numbers.length}. Order is the content in that block, so a '
            'gap or a repeat there is a real defect, not a typo.',
      );
    });

    for (final _GuardedFile file in _ordinalScanned) {
      final bool counts = _countScanned.contains(file);
      test(
        '${file.path} — no ordinal citation'
        '${counts ? ', and every stated count is true' : ''}',
        () {
          final List<String> lines = _readGuardedFile(file);
          final int contractSize = _contractNames(_readGuardedFile(_decoder))
              .length;
          expect(
            contractSize,
            greaterThanOrEqualTo(_kContractFloor),
            reason: 'the contract size could not be derived, so no count in '
                '${file.path} can be checked against it',
          );

          expect(
            _proseOffences(
              lines,
              contractSize: contractSize,
              checkCounts: counts,
            ),
            isEmpty,
            reason: 'Sentences in ${file.path} address a numbered list by '
                'ordinal, or miscount the honesty contract. Both go stale in '
                'silence when a member is inserted, because nothing greps for '
                'an ordinal — which is exactly how round 4 shipped two false '
                'sentences without changing a character of either:\n  '
                '${_proseOffences(lines, contractSize: contractSize, checkCounts: counts).join('\n  ')}',
          );
        },
      );
    }

    // TWO TESTS, NOT ONE, AND THE SPLIT IS THE POINT. These were a single test
    // with two `expect`s, and round 7 walked straight into what that costs: the
    // widened separator was applied, `_mustFire` still had a miss, the first
    // `expect` threw, and THE ENTIRE `_mustNotFire` TABLE WENT UNEVALUATED —
    // the precise table the gate had asked to see the widening proven against.
    // A compound assertion reports the first half and hides the second, so the
    // half that answers "did this change make the guard too wide?" is exactly
    // the half that goes silent while the guard is being changed. Separate
    // tests both run, always.

    test('the prose checks can produce a nonzero', () {
      // A ZERO FROM AN AUDIT IS ONLY MEANINGFUL IF THE AUDIT CAN PRODUCE A
      // NONZERO. Round 6 measured all five patterns against both guarded files
      // and found zero live subjects, so nothing in the suite had ever seen one
      // fire.
      final List<String> missed = _mustFire
          .where((String s) => _scanSentence(s).isEmpty)
          .toList();
      expect(
        missed,
        isEmpty,
        reason: 'these sentences must turn the build RED and did not — every '
            'one of them is an end-to-end mutation that defeated some version '
            'of this guard:\n  ${missed.join('\n  ')}',
      );
    });

    test('the prose checks stay quiet on ordinary English', () {
      // A pattern that fires on everything is as useless as one that fires on
      // nothing, and this table is where a WIDENING shows up as a false red.
      // Five of these carry hyphens, because round 7 widened every separator to
      // `[\s-]+` and a negative table with no hyphens in it could not have
      // caught the over-fire that widening actually produced.
      final List<String> overFired = _mustNotFire
          .where((String s) => _scanSentence(s).isNotEmpty)
          .map((String s) => '$s\n      -> ${_scanSentence(s).join('; ')}')
          .toList();
      expect(
        overFired,
        isEmpty,
        reason: 'these sentences are ordinary English and must NOT turn the '
            'build red. A guard authors have to write around is a guard '
            'authors delete:\n  ${overFired.join('\n  ')}',
      );
    });
  });
}
