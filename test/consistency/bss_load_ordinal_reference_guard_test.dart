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
// WHY IT WAS REWRITTEN, which is the more useful history. The first version of
// this guard forbade a SYNTAX: a regex per defect, each copied from the way the
// defect happened to be spelled last time. Round 5 defeated four of six
// end-to-end mutations against it. Renumbering the whole honesty contract with
// `1)` instead of `1.` passed every test — one punctuation character. So did
// `step 2` in place of `rule 2`, because the noun was not in the list. So did
// wrapping `precedence rule` / newline / `2 above`, because the scanner worked
// per line. And a sixth mutation turned the build RED on the ordinary English
// sentence "the two test cases below", which is the failure that actually
// matters: a guard authors have to write around is a guard authors delete.
//
// A GUARD THAT FORBIDS A SYNTAX IS DEFEATED BY A SYNONYM. A GUARD THAT ASSERTS A
// PROPERTY IS NOT. That is Vera's finding and it is the shape of this rewrite:
//
//   * The contract check is now a PRESENCE assertion. It reads the honesty
//     contract's entries BY NAME and requires each label to be a bare
//     upper-case name. `1. ABSENT`, `1) ABSENT`, `(1) ABSENT`, `I. ABSENT` and
//     `1 ABSENT` all fail on the same assertion, because none of them is a name
//     — there is no numeral spelling left to enumerate.
//   * The mirror check is set equality. The decoder names the outcomes; the
//     decoder's test file lists them; this guard fails unless the two sets are
//     identical. An absence assertion is satisfied by the absence of everything,
//     including by a scanner that found nothing. A set equality is not.
//   * The count check VERIFIES instead of forbidding. A sentence saying "four
//     outcomes" is true today and is allowed to say so; it goes red when a fifth
//     entry appears in the contract block. The old rule forbade the true
//     sentence and had to hand-carve exceptions for ordinary English, which is
//     how it came to fail on "two test cases".
//   * Prose is scanned per PARAGRAPH, not per line, so a line wrap between the
//     noun and the numeral no longer hides a citation.
//
// SCOPE, STATED SO NOBODY MISTAKES IT FOR MORE. This is a text check over two
// files. It does not read English. What it does NOT catch, enumerated because an
// unbounded claim about a guard is the thing that got flagged last round:
//
//   * a spelled-out ordinal in a shape not listed (`the penultimate rule`, `the
//     last case`, `the one before ABSENT`);
//   * a citation using a noun outside [_listNouns] (`the third bullet`);
//   * a positional citation with no determiner. [_ordinalByPosition] requires
//     `the`/`this`/`that` because without it the pattern fired on "insert a
//     fifth outcome", which ADDS a member rather than citing one and is the most
//     natural way to write the sentence this guard exists to protect;
//   * a bare count over an instance noun. "two readings" is not checked, because
//     `bss_load_decoder_test.dart` legitimately says "Two readings that compare
//     equal cannot be told apart downstream". "four different readings" IS
//     checked — see [_instanceNouns] and [_enumerating];
//   * a stated count using a noun outside [_contractNouns] and [_instanceNouns],
//     or one that happens to equal the contract's size while counting something
//     else entirely;
//   * anything at all in a third file — `ie_parser_test.dart` carries its own
//     numbered list and had a LIVE `Edit 3` citation into it five lines below
//     the list, which round 5 recorded as latent. It was repaired by hand rather
//     than by widening this guard: the count check is about the BSS Load honesty
//     contract specifically, and running it over an unrelated list would be a
//     category error.
//
// It guards the mistake that actually happened, in the two files it happened in,
// and the file it guards says so at the claim rather than only here.
//
// Build: Felix 2026-08-01, round 4 findings. Rewritten 2026-08-01 from Vera's
// round-5 H1 / M1 / M2 / M3 and her graduation candidate, "a guard that forbids
// a syntax is defeated by a synonym; a guard that asserts a property is not."

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The decoder that owns the honesty contract.
const String _decoderPath = 'lib/services/network/bss_load_decoder.dart';

/// Its test file, which mirrors the contract's member names.
const String _decoderTestPath =
    'test/services/network/bss_load_decoder_test.dart';

/// The two files whose prose is scanned. Deliberately not three — see SCOPE.
const List<String> _guardedFiles = <String>[_decoderPath, _decoderTestPath];

// ── Block anchors ────────────────────────────────────────────────────────────
// Each block is opened and closed by a phrase that survives the guard's own fix.
// A missing anchor is a LOUD failure, never a clean scan of an empty range.

const String _contractOpen = '── HONESTY CONTRACT';
const String _contractClose = 'IS THE ONE THAT KEEPS BEING OVER-CLAIMED';
const String _mirrorOpen = '── OUTCOMES, MIRRORED FROM THE DECODER';
const String _mirrorClose = 'Only ABSENT says anything about the AP';
const String _precedenceOpen = 'Precedence, in order.';
const String _precedenceClose = 'The blob is walked twice';

// ── Entry shape ──────────────────────────────────────────────────────────────

/// One entry of a named list: a comment marker, exactly three spaces, a label,
/// then an em dash. Prose continuing an entry is indented five, so it cannot be
/// mistaken for a new entry even when it contains an em dash of its own.
///
/// The label is captured LOOSELY on purpose. A renumbered entry
/// (`//   1. ABSENT — …`) still matches here and yields the label `1. ABSENT`,
/// which then fails [_bareName] with a message naming the offender. A regex that
/// refused to match it would instead have reported the entry as MISSING, which
/// is a weaker failure and a more confusing one.
final RegExp _contractEntry = RegExp(r'^\s*//+\s{3}(\S.*?)\s+—\s');

/// A label that is a NAME and nothing else: upper-case words joined by spaces or
/// hyphens. `ABSENT`, `NOTHING TO READ` and `CLIPPED-ELSEWHERE` pass. `1.
/// ABSENT`, `1) ABSENT`, `(1) ABSENT`, `1 ABSENT` and `I. ABSENT` do not, and
/// neither does a sentence.
final RegExp _bareName = RegExp(r'^[A-Z]+(?:[ -][A-Z]+)*$');

/// A first word made only of roman-numeral letters, which is the one numbering
/// scheme [_bareName] would otherwise accept (`II ABSENT`).
final RegExp _romanFirstWord = RegExp(r'^[IVXLCDM]+$');

/// A numbered step of the precedence list, which KEEPS its numbers because there
/// the order is the content. What is enforced is that every step also carries a
/// NAME, so that anything citing it from elsewhere has a handle that survives an
/// insertion.
final RegExp _precedenceStep = RegExp(r'^\s*///\s+\d+\.\s');
final RegExp _namedPrecedenceStep =
    RegExp(r'^\s*///\s+\d+\.\s+([A-Z][A-Z0-9-]*)\s+—\s');

// ── Prose checks ─────────────────────────────────────────────────────────────

/// Nouns that name a member of a numbered list. A citation is one of these
/// followed by a numeral or a spelled-out number.
///
/// `step` is here because the decoder's own precedence paragraph teaches the
/// reader that word, and a guard that forbids `rule 2` while the file itself
/// says "step" has left the door it was built to close standing open.
const List<String> _listNouns = <String>[
  'case', 'rule', 'outcome', 'state', 'step', 'item', 'branch', 'point',
  'entry', 'clause', 'reason', 'answer', 'reading', 'precedence', 'edit',
];

/// Nouns the honesty contract's members have actually been called, across every
/// revision of these two files: `outcomes` today, `states`, `answers` and
/// `cases` in the versions the gate rounds were run against. A count in front of
/// one of these is CHECKED against the contract's real size — not forbidden.
const List<String> _contractNouns = <String>[
  'states', 'outcomes', 'answers', 'cases',
];

/// Nouns that name INSTANCES rather than contract members. `BssLoadReading` is a
/// type, and `bss_load_decoder_test.dart` writes "Two readings that compare
/// equal cannot be told apart downstream" — a true sentence about two objects,
/// not a miscount of the contract.
///
/// Counted only when the phrase carries a word that marks it as an enumeration
/// of the contract ("four DIFFERENT readings"), which is the shape the stale
/// sentences actually took. Bare "two readings" is left alone.
const List<String> _instanceNouns = <String>['readings', 'results', 'branches'];

/// The words that turn an instance noun into an enumeration of the contract.
const List<String> _enumerating = <String>[
  'different', 'distinct', 'separate', 'possible', 'honest', 'named',
];

/// Words that, sitting between the number and the noun, say the phrase is not
/// counting the contract. "the two test cases below" is ordinary English in a
/// test file and must not turn the build red — the guard is worth nothing if
/// authors learn to route around it.
const List<String> _notTheContract = <String>[
  'test', 'tests', 'edge', 'corner', 'switch', 'vector', 'vectors', 'use',
];

/// `two`..`ten`. `one` is excluded: "the one place byte order is decided" is
/// prose about something else, and a contract with one member is not the failure
/// mode this guards.
const Map<String, int> _numberWords = <String, int>{
  'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
};

/// The alternation used by the citation patterns. Built from the lists above so
/// a noun is added in exactly one place.
final String _listNounsAlt = _listNouns.join('|');
final String _contractNounsAlt = _contractNouns.join('|');
final String _instanceNounsAlt = _instanceNouns.join('|');

/// Every counting word this guard understands, as an alternation.
const String _numbersAlt = 'two|three|four|five|six|seven|eight|nine|ten';

/// Every positional word, as an alternation.
const String _positionsAlt =
    'first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth';

/// `case 3`, `rule 2`, `step 4`.
final RegExp _ordinalByDigit =
    RegExp('\\b($_listNounsAlt)s?\\s+\\d+\\b', caseSensitive: false);

/// `case three`, `rule two` — the same citation spelled out.
final RegExp _ordinalByWord = RegExp(
  '\\b($_listNounsAlt)s?\\s+(one|$_numbersAlt)\\b',
  caseSensitive: false,
);

/// `the second rule`, `that third case` — the same citation inverted.
///
/// THE DETERMINER IS REQUIRED, and the reason is on the record: without it this
/// pattern fired on "insert a fifth outcome over there", which describes ADDING
/// a member rather than citing one, and is the single most natural way to write
/// the sentence this whole guard exists to protect. A citation is definite ("the
/// fifth outcome"); an addition is indefinite ("a fifth outcome"). The residual
/// is a bare "cite fifth rule", which is not English anyone writes.
final RegExp _ordinalByPosition = RegExp(
  '\\b(the|that|this)\\s+($_positionsAlt)\\s+($_listNounsAlt)s?\\b',
  caseSensitive: false,
);

/// A stated count of the contract's members, with up to two words between the
/// number and the noun so "four different answers" is seen.
final RegExp _statedCount = RegExp(
  '\\b($_numbersAlt)[\\s-]+((?:[\\w-]+[\\s-]+){0,2}?)($_contractNounsAlt)\\b',
  caseSensitive: false,
);

/// The same count, over an instance noun, and only when an [_enumerating] word
/// says the phrase is counting the contract. At least one word must sit between
/// the number and the noun, because that word is what does the marking.
final RegExp _statedInstanceCount = RegExp(
  '\\b($_numbersAlt)[\\s-]+((?:[\\w-]+[\\s-]+){1,2}?)($_instanceNounsAlt)\\b',
  caseSensitive: false,
);

/// Real Dart switch syntax, which is code rather than a reference. There is none
/// in either file today; the exclusion exists so adding a switch does not force
/// someone to weaken the rule.
final RegExp _switchCase = RegExp(r'^\s*case\s+\d+\s*:');

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

/// True for a line whose content is a comment.
bool _isComment(String line) => line.trimLeft().startsWith('//');

/// Strips the comment marker so the joined paragraph reads as prose.
String _commentBody(String line) =>
    line.trimLeft().replaceFirst(RegExp(r'^/{2,}'), '').trim();

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
    if (_isComment(line)) {
      final String body = _commentBody(line);
      // An empty comment line is a paragraph break in this codebase's house
      // style, and joining across one would invent adjacencies that are not in
      // the prose.
      if (body.isEmpty) {
        flush();
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      starts.add(_LineStart(buffer.length, i + 1));
      buffer.write(body);
      continue;
    }
    flush();
    if (_switchCase.hasMatch(line)) continue;
    out.add(_Paragraph(line, <_LineStart>[_LineStart(0, i + 1)]));
  }
  flush();
  return out;
}

/// Reads a file and proves the read produced real content before any absence
/// assertion is believed.
///
/// THIS IS NOT CEREMONY. An md5 comparison in this same work stream reported
/// SAME twice, over the digest of an empty string. A guard whose finding is an
/// absence must first show it was holding something.
List<String> _readGuardedFile(String path) {
  final File file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path not found');
  final List<String> lines = file.readAsLinesSync();
  expect(
    lines.length,
    greaterThan(200),
    reason: '$path read as ${lines.length} lines — the guard is looking at the '
        'wrong thing, not at a clean file',
  );
  expect(
    lines.where((String l) => l.contains('BSS Load')).length,
    greaterThan(3),
    reason: '$path does not read like BSS Load source; a zero from this guard '
        'would mean nothing',
  );
  return lines;
}

/// Index range `[open, close)` of an anchored block, with a loud failure at each
/// way the anchors can fail to resolve.
({int open, int close}) _blockRange(
  List<String> lines,
  String path,
  String open,
  String close,
) {
  final int start = lines.indexWhere((String l) => l.contains(open));
  expect(
    start,
    isNot(-1),
    reason: '$path: the block anchored to "$open" was not found. Without it '
        'this check would scan an empty range and report clean.',
  );
  final int end = lines.indexWhere((String l) => l.contains(close), start + 1);
  expect(
    end,
    isNot(-1),
    reason: '$path: no closing anchor ("$close") after "$open"; scanning to EOF '
        'would make this check meaningless.',
  );
  expect(
    end - start,
    greaterThan(4),
    reason: '$path: the block between "$open" and "$close" read as '
        '${end - start} lines — too short to be the real list',
  );
  return (open: start, close: end);
}

/// Every `NAME — …` entry inside an anchored block, in order.
List<({int line, String label})> _entriesIn(
  List<String> lines,
  ({int open, int close}) range,
) {
  final List<({int line, String label})> out = <({int line, String label})>[];
  for (int i = range.open; i < range.close; i++) {
    final RegExpMatch? m = _contractEntry.firstMatch(lines[i]);
    if (m != null) out.add((line: i + 1, label: m.group(1)!));
  }
  return out;
}

/// The contract's member names, derived from the decoder rather than restated
/// here. This guard must not become a third place the list lives.
Set<String> _contractNames(List<String> decoderLines) => _entriesIn(
      decoderLines,
      _blockRange(decoderLines, _decoderPath, _contractOpen, _contractClose),
    ).map((({int line, String label}) e) => e.label).toSet();

void main() {
  group('BSS Load contracts are named, never numbered', () {
    test('the honesty contract is a list of NAMES', () {
      final List<String> lines = _readGuardedFile(_decoderPath);
      final ({int open, int close}) range =
          _blockRange(lines, _decoderPath, _contractOpen, _contractClose);
      final List<({int line, String label})> entries = _entriesIn(lines, range);

      // POSITIVE, and this is the whole point of the rewrite. The old check
      // asserted the block LACKED a numeral, which one punctuation character
      // defeated. This asserts the block CONTAINS named entries, and an empty
      // or mis-anchored scan fails here instead of passing as clean.
      expect(
        entries.length,
        greaterThanOrEqualTo(3),
        reason: 'only ${entries.length} entries found in the honesty contract '
            '(lines ${range.open + 1}..${range.close + 1}). Either an outcome '
            'was deleted, or the block was reformatted and its entries are no '
            'longer "NAME — prose" at three spaces. Reformatting is the likelier '
            'one, and it is exactly how an absence check comes to pass over a '
            'block it can no longer read.',
      );

      final List<String> notNames = <String>[];
      for (final ({int line, String label}) e in entries) {
        final String first = e.label.split(RegExp(r'[ -]')).first;
        if (!_bareName.hasMatch(e.label) || _romanFirstWord.hasMatch(first)) {
          notNames.add('L${e.line}: "${e.label}"');
        }
      }
      expect(
        notNames,
        isEmpty,
        reason: 'These contract entries are not bare upper-case NAMES. A '
            'numeral, a parenthesis or a roman numeral in front of the name '
            'reintroduces the one handle nothing can grep: insert an outcome '
            'and every later ordinal changes, silently falsifying any sentence '
            'that cited one. The outcomes already have names; cite those:\n  '
            '${notNames.join('\n  ')}',
      );

      final Set<String> unique =
          entries.map((({int line, String label}) e) => e.label).toSet();
      expect(
        unique.length,
        entries.length,
        reason: 'two contract entries share a name, so a citation of that name '
            'is ambiguous: ${entries.map((({int line, String label}) e) => e.label).toList()}',
      );
    });

    test('the decoder test file mirrors the contract member for member', () {
      final List<String> decoder = _readGuardedFile(_decoderPath);
      final List<String> tests = _readGuardedFile(_decoderTestPath);

      final Set<String> contract = _contractNames(decoder);
      final Set<String> mirror = _entriesIn(
        tests,
        _blockRange(tests, _decoderTestPath, _mirrorOpen, _mirrorClose),
      ).map((({int line, String label}) e) => e.label).toSet();

      expect(contract, isNotEmpty, reason: 'no contract names were derived');

      // SET EQUALITY, which is what closes the hole a naming convention alone
      // leaves open. Naming protects a REFERENCE — grep the name and you find
      // every mention. It does not protect an ENUMERATION: a list of four names
      // stays syntactically perfect when a fifth outcome is added, and simply
      // becomes incomplete. Only comparing the two sets catches that.
      expect(
        mirror,
        contract,
        reason: 'The outcome list in $_decoderTestPath no longer matches the '
            'honesty contract in $_decoderPath.\n'
            '  only in the contract: ${contract.difference(mirror)}\n'
            '  only in the mirror:   ${mirror.difference(contract)}\n'
            'Add the new outcome to the mirror, or fix the name. An '
            'enumeration that quietly loses a member is the defect this pair '
            'exists to make loud.',
      );
    });

    test('every precedence step carries a NAME', () {
      final List<String> lines = _readGuardedFile(_decoderPath);
      final ({int open, int close}) range = _blockRange(
        lines,
        _decoderPath,
        _precedenceOpen,
        _precedenceClose,
      );

      final List<String> unnamed = <String>[];
      int steps = 0;
      for (int i = range.open; i < range.close; i++) {
        if (!_precedenceStep.hasMatch(lines[i])) continue;
        steps++;
        if (!_namedPrecedenceStep.hasMatch(lines[i])) {
          unnamed.add('L${i + 1}: ${lines[i].trim()}');
        }
      }

      expect(
        steps,
        greaterThanOrEqualTo(4),
        reason: 'only $steps numbered steps found in the precedence list — the '
            'anchors resolved but the list did not, so this check proved '
            'nothing',
      );
      expect(
        unnamed,
        isEmpty,
        reason: 'The precedence list KEEPS its numbers, because there the order '
            'is the content. What it may not do is leave a step without a NAME: '
            'the name is the only handle another paragraph can cite that '
            'survives an insertion. Give each step a short upper-case name:\n  '
            '${unnamed.join('\n  ')}',
      );
    });

    for (final String path in _guardedFiles) {
      test('$path — no ordinal citation, and every stated count is true', () {
        final List<String> lines = _readGuardedFile(path);
        final int contractSize = _contractNames(_readGuardedFile(_decoderPath))
            .length;
        expect(contractSize, greaterThanOrEqualTo(3),
            reason: 'the contract size could not be derived, so no count in '
                '$path can be checked against it');

        final List<String> offences = <String>[];
        for (final _Paragraph p in _paragraphs(lines)) {
          for (final RegExp r in <RegExp>[
            _ordinalByDigit,
            _ordinalByWord,
            _ordinalByPosition,
          ]) {
            for (final RegExpMatch m in r.allMatches(p.text)) {
              offences.add(
                'L${p.lineAt(m.start)} cites a list by ordinal: "${m[0]}" — '
                'name the member instead. An ordinal has no grep handle, so an '
                'insertion falsifies this sentence in silence.',
              );
            }
          }

          // VERIFY, DO NOT FORBID. "four outcomes" is true today and is allowed
          // to say so; it turns red the moment a fifth entry appears in the
          // contract block. The predecessor forbade the true sentence outright,
          // which meant hand-carving exceptions for ordinary English — and it
          // was one of those carve-outs that made it fail on "two test cases".
          for (final RegExpMatch m in <RegExpMatch>[
            ..._statedCount.allMatches(p.text),
            ..._statedInstanceCount.allMatches(p.text),
          ]) {
            final List<String> between = (m.group(2) ?? '')
                .toLowerCase()
                .split(RegExp(r'[\s-]+'))
                .where((String w) => w.isNotEmpty)
                .toList();
            if (between.any(_notTheContract.contains)) continue;
            if (_instanceNouns.contains(m.group(3)!.toLowerCase()) &&
                !between.any(_enumerating.contains)) {
              continue;
            }
            final int stated = _numberWords[m.group(1)!.toLowerCase()]!;
            if (stated == contractSize) continue;
            offences.add(
              'L${p.lineAt(m.start)} states a count that is not the contract\'s '
              'size: "${m[0]}" says $stated, the honesty contract has '
              '$contractSize entries.',
            );
          }
        }

        expect(
          offences,
          isEmpty,
          reason: 'Sentences in $path address a numbered list by ordinal, or '
              'miscount the honesty contract. Both go stale in silence when a '
              'member is inserted, because nothing greps for an ordinal — which '
              'is exactly how round 4 shipped two false sentences without '
              'changing a character of either:\n  ${offences.join('\n  ')}',
        );
      });
    }
  });
}
