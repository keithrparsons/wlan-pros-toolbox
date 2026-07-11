// STRUCTURAL GUARD #2 — bans the fictional DEAD-HOST FAKE from test/.
//
// Guard #1 (os_error_liveness_guard_test.dart) bans the wrong INFERENCE in
// production code: no file outside the classifier may read `osError`.
//
// That is only half the trap, and Vera caught the half I missed. What actually
// hid this bug for months was not in lib/ — it was in test/. Every probe HAD a
// green timeout test. They stayed green because every fake threw:
//
//     throw const SocketException('timed out');   // osError == null
//
// which is a shape NO PLATFORM PRODUCES. Dart's own connect-timeout carries a
// NON-null osError with the synthetic errno 110 (measured on macOS: 607ms,
// errno 110). The fakes were written from the same wrong mental model as the
// code, so they CONFIRMED the bug instead of falsifying it. They were green and
// vacuous: they exercised a branch real hardware never takes.
//
// A fake that encodes the assumption under test cannot falsify it.
//
// So: if a test constructs a SocketException whose message claims a timeout, a
// refusal, or an unreachable host, it MUST carry an osError. Anything else is
// fiction, and fiction is what shipped "254 / 254 · 254 live".
//
// THE ONE EXEMPTION: tcp_probe_classifier_test.dart. The classifier's own
// message-fallback path (for platforms/locales that surface no errno) can only
// be tested by constructing exactly these null-osError exceptions. That branch
// is real and needs coverage — but it belongs to the classifier alone, and no
// service test may lean on it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only file allowed to construct a dead-host SocketException with a null
/// osError — it owns the message-fallback branch and must test it.
const String kClassifierTestPath =
    'test/services/network/tcp_probe_classifier_test.dart';

/// Messages that assert a probe OUTCOME. If a fake claims one of these, it is
/// standing in for a real platform error and must carry the real errno.
final RegExp kOutcomeClaiming = RegExp(
  r'tim(e|ed)\s*out|timeout|refus|reset|unreach|no route|host is down',
  caseSensitive: false,
);

Directory _repoRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/test').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  fail('could not locate the repo root from ${Directory.current.path}');
}

/// One `SocketException(...)` construction found in real code (not in a comment,
/// not inside a string literal).
class SocketExceptionLiteral {
  const SocketExceptionLiteral({required this.line, required this.args});

  final int line;
  final String args;

  bool get carriesOsError => args.contains('osError');
  bool get claimsAnOutcome => kOutcomeClaiming.hasMatch(args);

  /// Fiction: it asserts a platform outcome but carries no platform errno.
  bool get isFictional => claimsAnOutcome && !carriesOsError;
}

/// Scan Dart source for `SocketException(` constructions, skipping comments and
/// string literals.
///
/// Being comment- and quote-aware is not fussiness — without it this guard
/// fires on its own documentation and on test NAMES like
/// 'a non-SocketException (TimeoutException…) is dead'. A guard that cries wolf
/// gets muted, and a muted guard is no guard.
List<SocketExceptionLiteral> findSocketExceptionLiterals(String source) {
  final List<SocketExceptionLiteral> out = <SocketExceptionLiteral>[];
  const String token = 'SocketException';

  int i = 0;
  int line = 1;
  while (i < source.length) {
    final String c = source[i];
    final String next = i + 1 < source.length ? source[i + 1] : '';

    if (c == '\n') {
      line++;
      i++;
      continue;
    }

    // Line comment.
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }

    // Block comment.
    if (c == '/' && next == '*') {
      i += 2;
      while (i < source.length && !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        if (source[i] == '\n') line++;
        i++;
      }
      i += 2;
      continue;
    }

    // String literal — skip it wholesale (handles escapes and TRIPLE-quoted
    // strings). This is the conservative direction: we never scan INSIDE a
    // string, so we can never fire on prose.
    //
    // Triple quotes matter: this very file quotes the old fake inside a '''…'''
    // fixture, and an earlier version of this tokenizer flagged ITSELF. A guard
    // that reports its own documentation as a violation gets muted.
    if (c == "'" || c == '"') {
      final String triple = c * 3;
      final bool isTriple = source.startsWith(triple, i);
      final String terminator = isTriple ? triple : c;
      i += terminator.length;
      while (i < source.length) {
        if (source[i] == r'\') {
          i += 2;
          continue;
        }
        if (source.startsWith(terminator, i)) {
          i += terminator.length;
          break;
        }
        if (source[i] == '\n') line++;
        i++;
      }
      continue;
    }

    // A real SocketException( construction in code.
    if (source.startsWith(token, i)) {
      int j = i + token.length;
      while (j < source.length && (source[j] == ' ' || source[j] == '\n')) {
        j++;
      }
      if (j < source.length && source[j] == '(') {
        final int startLine = line;
        // Walk to the matching close paren, tracking strings so a ')' inside a
        // message does not end the argument list early.
        int depth = 0;
        int k = j;
        final StringBuffer args = StringBuffer();
        while (k < source.length) {
          final String ch = source[k];
          if (ch == "'" || ch == '"') {
            final String quote = ch;
            args.write(ch);
            k++;
            while (k < source.length) {
              args.write(source[k]);
              if (source[k] == r'\') {
                k++;
                if (k < source.length) args.write(source[k]);
                k++;
                continue;
              }
              if (source[k] == quote) {
                k++;
                break;
              }
              if (source[k] == '\n') line++;
              k++;
            }
            continue;
          }
          if (ch == '(') depth++;
          if (ch == ')') {
            depth--;
            if (depth == 0) {
              k++;
              break;
            }
          }
          if (ch == '\n') line++;
          args.write(ch);
          k++;
        }
        out.add(SocketExceptionLiteral(
          line: startLine,
          args: args.toString(),
        ));
        i = k;
        continue;
      }
    }

    i++;
  }
  return out;
}

void main() {
  group('no test may fake a dead host with a null osError', () {
    late Directory root;
    setUpAll(() => root = _repoRoot());

    test('every outcome-claiming SocketException fake carries a real errno', () {
      final List<String> offenders = <String>[];
      final Directory testDir = Directory('${root.path}/test');

      for (final FileSystemEntity entity
          in testDir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;

        final String relative = entity.path
            .replaceAll(r'\', '/')
            .replaceFirst('${root.path.replaceAll(r'\', '/')}/', '');
        if (relative == kClassifierTestPath) continue;

        for (final SocketExceptionLiteral lit
            in findSocketExceptionLiterals(entity.readAsStringSync())) {
          if (!lit.isFictional) continue;
          final String snippet =
              lit.args.replaceAll(RegExp(r'\s+'), ' ').trim();
          offenders.add('$relative:${lit.line}: SocketException($snippet)');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '\n'
            '════════════════════════════════════════════════════════════════\n'
            'A test is faking a dead/refused host with a NULL osError.\n'
            '\n'
            'No platform throws that. Dart\'s OWN connect-timeout carries a\n'
            'NON-null osError with the synthetic errno 110 (measured: 607ms,\n'
            'errno 110). A fake with a null osError passes through the\n'
            'classifier\'s MESSAGE fallback — so the test goes green while\n'
            'exercising a branch real hardware never takes.\n'
            '\n'
            'That is exactly how this bug hid for months: every probe HAD a\n'
            'green timeout test, and every one of those fakes was fiction. The\n'
            'fakes encoded the same false belief as the code, so they confirmed\n'
            'the bug instead of catching it. A /24 sweep shipped reading\n'
            '"254 / 254 · 254 live".\n'
            '\n'
            'Throw what the platform actually throws:\n'
            '\n'
            '  DEAD host (timeout):\n'
            '    const SocketException(\n'
            '      \'Connection timed out\',\n'
            '      osError: OSError(\'Connection timed out\', 110),\n'
            '    );\n'
            '\n'
            '  LIVE host, closed port (RST — still ALIVE):\n'
            '    const SocketException(\n'
            '      \'Connection refused\',\n'
            '      osError: OSError(\'Connection refused\', 61),\n'
            '    );\n'
            '\n'
            'Only $kClassifierTestPath may build null-osError exceptions: it\n'
            'owns the message-fallback branch and must cover it.\n'
            '\n'
            'Offending fakes:\n'
            '  ${offenders.join('\n  ')}\n'
            '════════════════════════════════════════════════════════════════',
      );
    });

    test('the classifier test (the one exemption) actually exists', () {
      expect(File('${root.path}/$kClassifierTestPath').existsSync(), isTrue,
          reason: 'the exemption must point at a real file, or it is a hole');
    });
  });

  group('the guard is not vacuous', () {
    test('it flags the exact fake that hid this bug', () {
      const String source = '''
        connector: (host, port, {required timeout}) async {
          throw const SocketException('timed out'); // osError == null
        },
      ''';
      final List<SocketExceptionLiteral> found =
          findSocketExceptionLiterals(source);
      expect(found, hasLength(1));
      expect(found.single.isFictional, isTrue,
          reason: 'THE fake. If this ever stops flagging, the guard is dead.');
    });

    test('it flags a multi-line null-osError refusal too', () {
      const String source = '''
        throw const SocketException(
          'Connection refused',
        );
      ''';
      expect(findSocketExceptionLiterals(source).single.isFictional, isTrue);
    });

    test('it PASSES the real platform shape (errno present)', () {
      const String source = '''
        throw const SocketException(
          'Connection timed out',
          osError: OSError('Connection timed out', 110),
        );
      ''';
      final SocketExceptionLiteral lit =
          findSocketExceptionLiterals(source).single;
      expect(lit.carriesOsError, isTrue);
      expect(lit.isFictional, isFalse);
    });

    test('it does NOT fire on prose — comments and test names', () {
      // The false-positive cases that would get this guard muted. The old fake
      // is quoted verbatim in documentation across the repo; a guard that
      // cannot tell code from a comment is worse than no guard.
      const String source = '''
        // The fake used to throw SocketException('timed out') with a null osError.
        /* Block: SocketException('Connection refused') is fiction. */
        test('a non-SocketException (TimeoutException) is dead', () {});
      ''';
      expect(findSocketExceptionLiterals(source), isEmpty,
          reason: 'comments and string literals are prose, not fakes');
    });

    test('it ignores a SocketException that claims no outcome', () {
      // e.g. const SocketException('mDNS unavailable in test') — a setup stub,
      // not a claim about how a host responded. Not this guard's business.
      const String source = '''
        throw const SocketException('mDNS unavailable in test');
      ''';
      expect(findSocketExceptionLiterals(source).single.isFictional, isFalse);
    });
  });
}
