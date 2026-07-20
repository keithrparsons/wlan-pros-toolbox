// Every public type in the AP-scan files carries its own doc comment.
//
// WHY: while editing ap_scan_service.dart I inserted a new top-level function
// BETWEEN `ScannedAp`'s doc comment and the class itself. The doc silently
// re-attached to the function, `ScannedAp` was left undocumented, and nothing
// in the suite noticed. I found it by eye, reading an unrelated diff.
//
// `public_member_api_docs` catches this exactly (it fires on the orphaned
// declaration and gives zero hits once fixed), but it cannot be scoped to two
// files — Dart applies lints per directory at finest, and enabling it over
// lib/ produces ~1954 pre-existing hits that would bury the signal. So this is
// the same check, narrowed to the files that earned it: a top-level `class` or
// `enum` in these files must be immediately preceded by a `///` line.
//
// It is deliberately narrow. It does not check members, and it does not check
// the rest of the repo. It guards the one mistake that actually happened, in
// the one place it happened, and it will fail the moment someone repeats it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _guardedFiles = <String>[
  'lib/services/network/ap_scan_service.dart',
  'lib/screens/tools/network/ap_scan_screen.dart',
];

void main() {
  group('AP-scan public types keep their doc comments', () {
    for (final String path in _guardedFiles) {
      test('$path — every top-level class/enum is documented', () {
        final File file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path not found');
        final List<String> lines = file.readAsLinesSync();

        final List<String> undocumented = <String>[];
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          // Top-level declarations only: no leading whitespace.
          // PUBLIC types only, matching `public_member_api_docs`' own scope: a
          // name starting with an uppercase letter, not `_Private`. Widening
          // this to private classes would demand docs on eleven pre-existing
          // private widgets in ap_scan_screen.dart — unrelated churn that would
          // dilute what this guard is for.
          //
          // Every Dart 3 class modifier is accepted, in any legal combination
          // (`final class`, `sealed class`, `abstract interface class`, …).
          // The first version of this regex allowed only `abstract`, so
          // `final class ScannedAp` carrying the identical orphaned-doc defect
          // reported "All tests passed" — a guard with a hole exactly the shape
          // of the modifier someone would plausibly add later.
          if (!RegExp(
            r'^(abstract\s+|base\s+|final\s+|interface\s+|sealed\s+|mixin\s+)*'
            r'(class|enum|mixin|extension\s+type(\s+const)?)\s+[A-Z]',
          ).hasMatch(line)) {
            continue;
          }
          // Walk back over annotations (@immutable etc.) to the line that
          // should carry the doc.
          int j = i - 1;
          while (j >= 0 && lines[j].trimLeft().startsWith('@')) {
            j--;
          }
          if (j < 0 || !lines[j].trimLeft().startsWith('///')) {
            undocumented.add('L${i + 1}: ${line.trim()}');
          }
        }

        expect(
          undocumented,
          isEmpty,
          reason: 'These public types have no doc comment immediately above '
              'them. The usual cause is a declaration inserted BETWEEN a doc '
              'comment and the type it described, which silently re-attaches '
              'the doc to the newcomer:\n  ${undocumented.join('\n  ')}',
        );
      });
    }
  });
}
