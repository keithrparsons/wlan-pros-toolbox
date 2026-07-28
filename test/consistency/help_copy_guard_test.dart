// ============================================================================
// GUARD: a DO-NOT-PRINT sweep must scan the HELP SHEET too, not just the data.
// ============================================================================
//
// THE DEFECT THIS EXISTS FOR (Vera, 2026-07-25, M-01).
//
// Reference screens carry a DO-NOT-PRINT list from their research brief:
// phrases with no primary source that must never reach a shipped surface. Each
// screen test pinned that list as negative assertions over a hand-written
// `_allProse()` helper, which enumerated the screen's Dart data constants.
//
// `assets/help/tool_help.json` is ALSO shipped user-facing copy - the help
// sheet renders it under every tool - and no test scanned it. The Batteries
// help entry shipped the B-size folklore sentence verbatim while a test three
// files away asserted the sentence was absent from the app. The assertion was
// true about the surface it read and false about the app, which is the worst
// shape a green test can have.
//
// Two halves fix it, and this file is the second:
//   1. test/support/shipped_help_copy.dart gives every screen test the help
//      surface as a flat string list (and throws rather than returning empty,
//      so a renamed id cannot make a sweep vacuous).
//   2. THIS file makes using it mechanical, so screen number three inherits the
//      coverage instead of inheriting the hole.
//
// WHAT THIS GUARD DOES AND DOES NOT CLAIM. It is a lint on test SOURCE TEXT: a
// test file that declares a do-not-print list must also reference
// `shippedHelpProse`. That catches the realistic case (someone copies an
// existing screen test as the template for a new one, which is exactly how both
// current screens were written). It does NOT prove the help surface is swept
// correctly, and it cannot catch a screen that has banned phrases but never
// says so. Do not read it as more than it is - a comment claiming coverage it
// does not have is how the original gap survived review.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/shipped_help_copy.dart';

/// Normalized marker for "this file declares a do-not-print list": the phrase
/// with any separator (hyphen, space, underscore) and any case.
final RegExp _doNotPrintMarker =
    RegExp(r'do[-_ ]?not[-_ ]?print', caseSensitive: false);

/// The symbol a compliant test file must reference.
const String _requiredSymbol = 'shippedHelpProse';

/// This file names the marker in its own prose, and is not a screen test.
const String _selfPath = 'test/consistency/help_copy_guard_test.dart';

List<File> _testDartFiles(String root) {
  final Directory d = Directory('$root/test');
  if (!d.existsSync()) return <File>[];
  return d
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('_test.dart'))
      .toList();
}

String _rel(String root, String path) =>
    path.startsWith('$root/') ? path.substring(root.length + 1) : path;

void main() {
  group('shippedHelpProse collector (proves it can fail)', () {
    test('collects every string VALUE recursively, and no keys', () {
      final List<String> prose = proseFromEntry(<String, dynamic>{
        'name': 'Batteries',
        'howToUse': <String>['first step', 'second step'],
        'inputs': <dynamic>[
          <String, dynamic>{'name': 'nested', 'unit': 'deeper'},
        ],
        'algorithm': null,
        'count': 7,
        'enabled': true,
      });
      expect(prose, <String>[
        'Batteries',
        'first step',
        'second step',
        'nested',
        'deeper',
      ]);
      // Keys are schema names, not copy: none of them may leak into the sweep.
      expect(prose.contains('howToUse'), isFalse);
      expect(prose.contains('algorithm'), isFalse);
    });

    test('a field added to the help schema is picked up with no code change',
        () {
      // The point of the field-blind walk. A named-field collector would go
      // silently blind here, which is the original defect one level down.
      final List<String> prose = proseFromEntry(<String, dynamic>{
        'name': 'X',
        'aFieldNobodyHasWrittenYet': 'banned phrase lives here',
      });
      expect(prose.contains('banned phrase lives here'), isTrue);
    });

    test('an unknown tool id THROWS rather than returning an empty list', () {
      // An empty list would make every caller's absence assertion pass for
      // free. This is the difference between a guard and a decoration.
      expect(() => shippedHelpProse('no-such-tool-id'), throwsStateError);
    });

    test('the two reference screens resolve real, non-trivial help copy', () {
      for (final String id in <String>['batteries', 'sd-cards']) {
        final List<String> prose = shippedHelpProse(id);
        expect(prose.length, greaterThanOrEqualTo(kMinHelpProseStrings));
        expect(prose.any((String s) => s.length > 80), isTrue,
            reason: 'help copy for "$id" is suspiciously short');
      }
    });
  });

  test('a test that declares a DO-NOT-PRINT list must scan the help sheet', () {
    final String root = helpPackageRoot();
    final List<String> offenders = <String>[];

    for (final File f in _testDartFiles(root)) {
      final String rel = _rel(root, f.path);
      if (rel == _selfPath) continue;
      final String src = f.readAsStringSync();
      if (!_doNotPrintMarker.hasMatch(src)) continue;
      if (!src.contains(_requiredSymbol)) offenders.add(rel);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These test files declare a DO-NOT-PRINT list but never scan the '
          'shipped help sheet (assets/help/tool_help.json), which is where the '
          'Batteries folklore sentence shipped past an identical guard on '
          '2026-07-25. Import test/support/shipped_help_copy.dart and run the '
          'negative assertions over the screen data AND '
          '$_requiredSymbol(<tool-id>).\n  ${offenders.join('\n  ')}',
    );
  });

  test('the marker regex matches the spellings a future author might use', () {
    // A source-text lint is only as good as its matcher, so pin it.
    for (final String spelling in <String>[
      'DO-NOT-PRINT list from the brief',
      'do not print this claim',
      'the do_not_print items',
      'DO NOT PRINT',
    ]) {
      expect(_doNotPrintMarker.hasMatch(spelling), isTrue,
          reason: 'unmatched spelling: "$spelling"');
    }
    expect(_doNotPrintMarker.hasMatch('the printer does not print'), isFalse);
  });
}
