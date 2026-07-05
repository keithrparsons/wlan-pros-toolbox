// ============================================================================
// VERSION CONSISTENCY GUARD — no hardcoded app-version literal in shipped prose
// may drift from pubspec.yaml. The app's own version renders dynamically in the
// guides (`app v{{app_version}}`, filled at runtime from the package version);
// this test is the mechanical backstop that fails the build if a literal ever
// reappears and disagrees with pubspec.
// ============================================================================
//
// WHY THIS TEST EXISTS (the miss it closes). The "How this app works" guide
// shipped `app v1.5.4` while the build was 1.7.0 — a hand-typed version string
// that rotted silently across several releases because nothing checked it. The
// fix made the version dynamic; this test makes the rule mechanical, running on
// every `flutter test` (exactly like leakage_guard_test.dart) so a drifted
// version can never ship again — "always check with each update," enforced by
// the build itself.
//
// It shells out to scripts/version-guard.sh → scripts/version_guard.py, which
// scans the shipped prose surfaces (assets/guides/*.md, assets/help/*.json) for
// an app-version CLAIM (`app v1.7.0` / `app version 1.7.0`) and fails if any
// literal is not the current pubspec version. The claim pattern anchors on the
// word "app", so IPs, IEEE clauses (802.15.4), DNS, and third-party version
// strings (PCI DSS v4.0.1) are not false-positives.
//
// A green run means: every app-version reference in shipped prose is either the
// runtime {{app_version}} placeholder or an exact match to pubspec. A red run
// prints the offending file:line and blocks the ship.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app-version literals in shipped prose match pubspec (no drift)', () {
    final String root = _packageRoot();
    final String script = '$root/scripts/version-guard.sh';

    expect(
      File(script).existsSync(),
      isTrue,
      reason: 'version-guard.sh missing at $script',
    );

    final ProcessResult r = Process.runSync(
      'bash',
      <String>[script],
      workingDirectory: root,
    );

    // Exit 0 = clean; exit 1 = a hardcoded app-version literal drifted from
    // pubspec (make it dynamic with {{app_version}} or correct the literal).
    expect(
      r.exitCode,
      0,
      reason: 'Version guard FAILED — a hardcoded app-version literal in shipped '
          'prose disagrees with pubspec.\nSTDOUT:\n${r.stdout}\n'
          'STDERR:\n${r.stderr}',
    );
  });
}

/// Resolve the package root whether the test runs from the package dir or a
/// nested working directory.
String _packageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/scripts/version-guard.sh').existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
