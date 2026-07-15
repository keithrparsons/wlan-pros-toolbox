// Targeted regression guard (Fix B, 2026-07-15).
//
// Live em dashes shipped in the ICMP Ping and Mobile Traceroute user-facing
// copy in 1.7.4 and reached Keith's device screenshots, even though the global
// voice_guard suite was green. The guard does not scan these inline widget
// string literals, so the P0 no-em-dash rule (GL-004) had a hole exactly here.
//
// This test closes that hole for these two screens specifically. It is a
// SOURCE scan: it reads each screen file, strips comments (where em dashes are
// allowed) and the null-value placeholder glyph literal (which means "not
// applicable" and is data, not prose), then asserts no U+2014 remains anywhere
// in the code, i.e. in any user-facing string literal.
//
// Scope is deliberately narrow (these two files). It does NOT enable full-app
// em-dash scanning; the separate ~357-string app-wide backlog is out of scope.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The em dash (U+2014). Built from its code point so this source file itself
/// stays em-dash-free and cannot false-positive against its own text.
const String emDash = '\u2014';

/// The exact null-value placeholder literal used in numeric display
/// (`v == null ? '<glyph>' : ...`). Exempt: it is a data glyph meaning "not
/// applicable", never prose.
final String nullGlyphLiteral = "'$emDash'";

/// Strip `//` line comments (this covers the `///` doc comments and the
/// `// ──` header art too). Neither of these two screens contains `://` inside
/// a string literal, so cutting at the first `//` never truncates real copy.
String _stripLineComments(String source) => source
    .split('\n')
    .map((String line) {
      final int idx = line.indexOf('//');
      return idx >= 0 ? line.substring(0, idx) : line;
    })
    .join('\n');

void _assertNoProseEmDash(String path) {
  final File file = File(path);
  expect(file.existsSync(), isTrue, reason: 'missing source file: $path');

  final String code = _stripLineComments(file.readAsStringSync())
      // Allow the null-value placeholder glyph literal (data, not prose).
      .replaceAll(nullGlyphLiteral, '');

  expect(
    code.contains(emDash),
    isFalse,
    reason: 'A user-facing em dash (U+2014) is present in $path. Per GL-004 the '
        'no-em-dash rule extends to app UI strings. Restructure into two '
        'sentences or use a colon/period. (Comments and the null glyph literal '
        'are exempt and already excluded by this test.)',
  );
}

void main() {
  group('ICMP screens: no em dash in user-facing copy (Fix B guard)', () {
    test('icmp_ping_screen.dart has no prose em dash', () {
      _assertNoProseEmDash(
        'lib/screens/tools/network/icmp_ping_screen.dart',
      );
    });

    test('mobile_traceroute_screen.dart has no prose em dash', () {
      _assertNoProseEmDash(
        'lib/screens/tools/network/mobile_traceroute_screen.dart',
      );
    });
  });
}
