// STRUCTURAL GUARD — stops the sixth probe from rediscovering the same bug.
//
// The history: `lib/services/network/lan_discovery/connect_scan.dart` hit the
// "osError != null means the host answered" trap, diagnosed it correctly, and
// fixed it LOCALLY. Four other probes (Ping Sweep, Ping, Port Scan, ARP/NDP)
// went right on shipping the broken shorthand for months, because nothing
// forced them to share the fix. A /24 Ping Sweep reported "254 / 254 · 254
// live" — every dead IP on the subnet counted as a live host.
//
// The fix for the FIX is this test. `osError` is now owned by exactly one file:
//
//     lib/services/network/tcp_probe_classifier.dart
//
// No other file in lib/ or packages/ may reference it — not to decide liveness,
// not to build an error message, not at all. If you need the OS-level reason or
// message, call `classifyTcpFailure(e)` and read `.reason` / `.message`; the
// classifier hands them to you already unwrapped.
//
// Why an outright ban on the identifier rather than a cleverer "is this a
// boolean liveness test?" regex: a regex for `osError != null` is trivially
// evaded by `final os = e.osError; if (os == null) …` — which is exactly the
// shape packet_sender_service was already using. A ban on the token is
// mechanical, has no false negatives, and cannot be sidestepped by aliasing.
//
// If a probe genuinely needs a new distinction, ADD IT TO THE CLASSIFIER and
// give it a test there. That is the whole point.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to touch `osError`, relative to the repo root.
const String kClassifierPath =
    'lib/services/network/tcp_probe_classifier.dart';

/// Roots scanned for violations. `packages/` is included so a future
/// vendored package cannot quietly re-introduce the bug either.
const List<String> kScannedRoots = <String>['lib', 'packages'];

/// Locate the repo root from the test's CWD (flutter test runs at the root, but
/// don't depend on it).
Directory _repoRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/lib').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  fail('could not locate the repo root from ${Directory.current.path}');
}

/// Path of [file] relative to [root], with forward slashes on every platform.
String _relative(File file, Directory root) {
  final String rootPath = root.path.replaceAll(r'\', '/');
  final String filePath = file.path.replaceAll(r'\', '/');
  final String prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  return filePath.startsWith(prefix)
      ? filePath.substring(prefix.length)
      : filePath;
}

void main() {
  group('osError is owned by the shared TCP probe classifier, and only it', () {
    late Directory root;

    setUpAll(() => root = _repoRoot());

    test('no file outside the classifier references osError', () {
      final List<String> offenders = <String>[];

      for (final String rootName in kScannedRoots) {
        final Directory scanned = Directory('${root.path}/$rootName');
        if (!scanned.existsSync()) continue;

        for (final FileSystemEntity entity
            in scanned.listSync(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;

          final String relative = _relative(entity, root);
          if (relative == kClassifierPath) continue;

          final List<String> lines = entity.readAsLinesSync();
          for (int i = 0; i < lines.length; i++) {
            final String line = lines[i];
            if (!line.contains('osError')) continue;
            // A doc comment or an ordinary comment may name the bug — that is
            // documentation, not a decision. Only real code counts.
            final String trimmed = line.trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
            offenders.add('$relative:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '\n'
            '════════════════════════════════════════════════════════════════\n'
            'A file outside the shared classifier is reaching for `osError`.\n'
            '\n'
            'Do NOT decide liveness from `osError != null` / `== null`.\n'
            "Dart's OWN connect-timeout populates osError with a synthetic\n"
            'errno (110). `osError != null` is therefore TRUE for a DEAD host,\n'
            'and using it as a liveness test reports every dead IP as alive.\n'
            'That bug shipped in four tools and produced a /24 sweep reading\n'
            '"254 / 254 · 254 live".\n'
            '\n'
            'Use the single source of truth instead:\n'
            '    import "package:wlan_pros_toolbox/services/network/'
            'tcp_probe_classifier.dart";\n'
            '\n'
            '    classifyTcpError(e)     -> TcpProbeOutcome (open/refused/dead)\n'
            '    classifyTcpFailure(e)   -> reason + message + errno\n'
            '    tcpErrorProvesHostAlive(e)\n'
            '\n'
            'Need a distinction the classifier does not make? ADD IT THERE,\n'
            'with a test. Do not re-derive it locally — that is how this bug\n'
            'survived five probes.\n'
            '\n'
            'Offending lines:\n'
            '  ${offenders.join('\n  ')}\n'
            '════════════════════════════════════════════════════════════════',
      );
    });

    test('the classifier itself exists and is where we say it is', () {
      expect(
        File('${root.path}/$kClassifierPath').existsSync(),
        isTrue,
        reason: '$kClassifierPath is the SSOT for TCP probe classification. '
            'If it moved, update kClassifierPath here and every import.',
      );
    });

    test('the guard can actually catch a violation (it is not vacuous)', () {
      // Guard the guard: prove the detection line would flag the real shape.
      const String violation = '      if (e.osError != null) {';
      const String aliased = '    final OSError? os = e.osError;';
      const String docComment = '  /// a null osError used to mean timeout';

      bool flags(String line) {
        if (!line.contains('osError')) return false;
        final String trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('///');
      }

      expect(flags(violation), isTrue, reason: 'the original bug shape');
      expect(flags(aliased), isTrue,
          reason: 'aliasing through a local must not evade the guard');
      expect(flags(docComment), isFalse,
          reason: 'documentation about the bug is allowed');
    });
  });
}
