// The BSS Load files name their contracts. They never NUMBER or COUNT them.
//
// WHY THIS EXISTS. Three gate rounds on `bss_load_decoder.dart` found the same
// defect wearing different clothes: a change applied to the code and to some,
// but not all, of the sentences that depended on it. Round 3 was a RENAME, and
// a rename has a mechanical handle — you grep the old symbol, and the round-4
// gate did exactly that and found it clean. Round 4's two findings were a
// RENUMBERING, and **nothing greps for an ordinal.** Inserting a new outcome
// into the file's central honesty contract turned three numbered cases into
// four, and two sentences elsewhere kept addressing the old scheme. Not one
// character of either sentence changed, and both now assert something false.
//
// So this guard removes the handle-less construct instead of policing it:
//
//   1. The honesty contract is an unnumbered list of NAMED outcomes. A name is
//      greppable; an ordinal is not. Inserting a fifth outcome can no longer
//      silently invalidate a sentence somewhere else in the file.
//   2. No prose anywhere in these two files refers to `case N` or `rule N`, and
//      no prose states how MANY states / outcomes / cases / answers there are.
//      Both are references that go stale in total silence.
//
// WHAT IT DELIBERATELY DOES NOT DO. The precedence list in `decodeBssLoad`'s
// doc STAYS numbered, because there the order is the content — "otherwise" is
// the meaning of each step, and stripping the numbers would lose information
// rather than protect it. What this guard forbids is CROSS-REFERENCING that
// list by ordinal from somewhere else; the fix was to give each rule a short
// upper-case NAME and refer to that instead. Same medicine, applied where an
// ordinal is a label rather than a semantic.
//
// SCOPE, stated so nobody mistakes it for more. Two files. It does not scan
// `ie_parser.dart` (which has no numbered contract), it does not scan the rest
// of the repo, and it cannot tell you whether a NAMED reference is accurate —
// only that a reference cannot go stale through renumbering. It guards the one
// mistake that actually happened, in the two files it happened in.
//
// Build: Felix 2026-08-01, from Vera's round-4 MEDIUM-1 / LOW-1 and her
// graduation candidate "A RENUMBERING IS A RENAME, and nothing greps for an
// ordinal."

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two files that carry the BSS Load honesty contract and the sentences
/// that depend on it.
const List<String> _guardedFiles = <String>[
  'lib/services/network/bss_load_decoder.dart',
  'test/services/network/bss_load_decoder_test.dart',
];

/// A cross-reference to a numbered list by its ordinal: `case 3`, `rule 2`.
///
/// This is the construct with no grep handle. `outcome`/`state` are included so
/// a future author cannot reintroduce the same reference under a new noun.
final RegExp _ordinalReference = RegExp(
  r'\b(case|rule|outcome|state)s?\s+\d+\b',
  caseSensitive: false,
);

/// A stated COUNT of the contract's members: "the three states", "four
/// different answers", "the three-state question".
///
/// `two`..`ten` only, and only in front of one of four contract nouns. "the one
/// place byte order is decided" and "the three numbers a WLAN engineer wants"
/// are prose about other things and must not be flagged — the guard is worth
/// nothing if authors learn to route around it.
final RegExp _statedCount = RegExp(
  r'\b(two|three|four|five|six|seven|eight|nine|ten)[\s-]+'
  r'(\w+[\s-]+)?(states?|outcomes?|cases?|answers?)\b',
  caseSensitive: false,
);

/// A numbered entry inside the honesty-contract block: `//   1. ABSENT`.
final RegExp _numberedContractEntry = RegExp(r'^//\s+\d+\.\s');

/// Opens and closes the honesty-contract block in the decoder's header.
///
/// The close anchor is deliberately the ordinal-free half of the sentence that
/// follows the list, so it resolves both before and after this guard's own fix.
/// An anchor containing "CASE 1" would have been an anchor the fix deletes.
const String _contractOpen = '── HONESTY CONTRACT';
const String _contractClose = 'IS THE ONE THAT KEEPS BEING OVER-CLAIMED';

void main() {
  group('BSS Load contracts are named, never numbered', () {
    for (final String path in _guardedFiles) {
      test('$path — no ordinal cross-reference and no stated count', () {
        final File file = File(path);

        // THE INSTRUMENT CHECK, and it is not ceremony. This guard's finding is
        // an ABSENCE, and an absence assertion is satisfied by the absence of
        // everything — including by a file that failed to open. An md5
        // comparison in this same work stream reported SAME twice over the
        // digest of an empty string. So prove the scanner is holding real
        // content before believing its zero.
        expect(file.existsSync(), isTrue, reason: '$path not found');
        final List<String> lines = file.readAsLinesSync();
        expect(
          lines.length,
          greaterThan(200),
          reason: '$path read as ${lines.length} lines — the guard is looking '
              'at the wrong thing, not at a clean file',
        );
        expect(
          lines.where((String l) => l.contains('BSS Load')).length,
          greaterThan(3),
          reason: '$path does not read like the BSS Load source; a zero from '
              'this guard would mean nothing',
        );

        final List<String> offences = <String>[];
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          // EVERY line, not just comment lines — and the first draft of this
          // guard got that wrong in a way worth recording. Scanning only lines
          // starting with `//` produced a clean result on the test file's two
          // stale `group('… three …')` names, which are string literals in
          // CODE. The guard would have reported six of eight known defects and
          // called it a pass. An instrument that cannot express the syntax the
          // defect is written in cannot prove the fix (GL-013). A test's NAME
          // and a `reason:` string are prose a reader trusts exactly as much as
          // a comment, so they are in scope.
          //
          // The one construct excluded is real Dart switch syntax (`case 3:`),
          // which is code rather than a reference. There is none in either file
          // today; the exclusion is there so adding a switch does not force
          // someone to weaken the rule.
          if (RegExp(r'^\s*case\s+\d+\s*:').hasMatch(line)) continue;

          for (final RegExpMatch m in _ordinalReference.allMatches(line)) {
            offences.add(
              'L${i + 1} ordinal cross-reference "${m[0]}" — '
              'name the thing instead: ${line.trim()}',
            );
          }
          for (final RegExpMatch m in _statedCount.allMatches(line)) {
            offences.add(
              'L${i + 1} stated count "${m[0]}" — the count changes when a '
              'member is added and this sentence will not: ${line.trim()}',
            );
          }
        }

        expect(
          offences,
          isEmpty,
          reason: 'These sentences address a numbered list by ordinal, or '
              'state how many members it has. Both go stale in silence when a '
              'member is inserted, because nothing greps for an ordinal — '
              'which is exactly how round 4 shipped two false sentences '
              'without changing a character of either:\n  '
              '${offences.join('\n  ')}',
        );
      });
    }

    test('the honesty contract itself is an unnumbered list of named outcomes',
        () {
      final File file = File(_guardedFiles.first);
      expect(file.existsSync(), isTrue);
      final List<String> lines = file.readAsLinesSync();

      final int open = lines.indexWhere((String l) => l.contains(_contractOpen));
      expect(
        open,
        isNot(-1),
        reason: 'the honesty-contract block was not found — this guard is '
            'anchored to "$_contractOpen" and would otherwise scan an empty '
            'range and report clean',
      );
      final int close = lines.indexWhere(
        (String l) => l.contains(_contractClose),
        open + 1,
      );
      expect(
        close,
        isNot(-1),
        reason: 'the contract block has no end anchor ("$_contractClose"); '
            'scanning to EOF would make this check meaningless',
      );
      expect(close - open, greaterThan(10),
          reason: 'the contract block read as ${close - open} lines — too '
              'short to be the real contract');

      final List<String> numbered = <String>[];
      for (int i = open; i < close; i++) {
        if (_numberedContractEntry.hasMatch(lines[i])) {
          numbered.add('L${i + 1}: ${lines[i].trim()}');
        }
      }
      expect(
        numbered,
        isEmpty,
        reason: 'The honesty contract is numbered again. The ordinals are the '
            'defect: they are labels, not semantics, the outcomes already have '
            'names, and every ordinal is a cross-reference waiting to go stale '
            'the next time an outcome is inserted:\n  ${numbered.join('\n  ')}',
      );
    });
  });
}
