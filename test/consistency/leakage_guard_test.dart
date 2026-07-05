// ============================================================================
// LEAKAGE GUARD (SOP-061 Check 1) — nothing about HOW the content was made may
// appear in shipped output. Internal team/process language, agent names, SOP/GL
// refs, repo paths (Deliverables/, myPKA, /Developer/, Team Knowledge), and
// wikilinks must never reach the app stores. Authorship (Keith Parsons / WLAN
// Pros) is KEPT on purpose — a reader may know WHO, never HOW.
// ============================================================================
//
// This wires scripts/leakage-guard.sh + scripts/leakage_guard_dart.py into
// `flutter test` so the gate runs every suite, not just when someone remembers
// to invoke the script by hand. It is the durable, loop-until-clean fix for the
// class of leak where an internal attribution rode inside a SHIPPED string.
//
// WHY THIS TEST EXISTS (the miss it closes). The original guard only scanned
// bundled ASSETS (json/md/txt/html). It could not see lib/data/*.dart, so the
// LED / vendor-model decoder `source:` fields that ended ", Pax <date>." shipped
// clean past it. The Dart stage strips comments (which legitimately carry
// provenance and never ship) and scans only string-literal content — the strings
// that compile into the app. Both stages now run here.
//
// A green run means: zero internal references in any shipped asset OR any shipped
// Dart string. A red run prints the offending file:line and blocks the ship.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SOP-061 leakage guard: no internal references in shipped content', () {
    final String root = _packageRoot();
    final String script = '$root/scripts/leakage-guard.sh';

    expect(
      File(script).existsSync(),
      isTrue,
      reason: 'leakage-guard.sh missing at $script',
    );

    final ProcessResult r = Process.runSync(
      'bash',
      <String>[script],
      workingDirectory: root,
    );

    // Exit 0 = clean; exit 1 = internal references found (fix before shipping).
    expect(
      r.exitCode,
      0,
      reason: 'Leakage guard FAILED — internal references in shipped content.\n'
          'STDOUT:\n${r.stdout}\nSTDERR:\n${r.stderr}',
    );
  });
}

/// Resolve the package root whether the test runs from the package dir or a
/// nested working directory.
String _packageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/scripts/leakage-guard.sh').existsSync()) {
      return dir.path;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
