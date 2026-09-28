// ============================================================================
// LEAKAGE GUARD PATTERN TESTS: false positives the guard must NOT raise, and
// real leaks it must STILL catch.
// ============================================================================
//
// leakage_guard_test.dart runs the guard over the real tree. This file pins
// the guard's patterns against fixed fixtures, so a pattern change that opens a
// hole (or re-closes a fixed false positive) goes red here.
//
// Two false positives, both fixed 2026-09-28:
//
//   1. The product name. The agent-name pattern read every whole-word "Pixel" as
//      the internal specialist, so a verbatim Google citation ("Google Pixel
//      Phone Help ... Pixel phone") failed the ship. Product forms (Pixel
//      preceded by "Google", or followed by a digit or a product word) are
//      allowed; the name used as a person ("Pixel drew", "ask Pixel",
//      "Pixel's") is still caught.
//
//   2. A missing word boundary. The workstream pattern matched the last four
//      characters of the FCC band name "AWS-1". A lesson builder had to split a
//      string literal in code to get past it. A bare workstream reference
//      ("WS-003") is still caught.
//
// Both stages are exercised: the Dart string stage (leakage_guard_dart.py)
// through .dart fixtures, and the asset stage (leakage-guard.sh) through .md
// fixtures. The shell guard is copied into a scratch root with no lib/, so its
// Dart stage is skipped and each result reflects the fixture alone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lines the guard must pass. Each is a real-world use, not internal machinery.
const List<String> _allowed = <String>[
  // The Phone Data Abroad citation, verbatim from Google's help page.
  'Google Pixel Phone Help, Connect to mobile networks on a Pixel phone (2926415)',
  'How to use dual SIMs on your Google Pixel phone (9449293)',
  'A Pixel 9 and an iPhone 16 side by side.',
  'Pixel 8a owners see the same menu.',
  'Pair your Pixel Buds before the flight.',
  'Most Pixel phones support eSIM.',
  'The Pixel Watch keeps its own LTE line.',
  // The FCC band name, the sentence the Weak Cell Signal lesson had to split.
  'the 1900 MHz PCS band and the AWS-1 band (1.7 and 2.1 GHz).',
  'AWS-3 and AWS-4 are later auctions.',
  // The Satellite Texting guide's own heading, verbatim: a phone named with an
  // article before it is the product, never the person (2026-09-28).
  'Try the demo on a Pixel',
  'Hold an iPhone or a Pixel up to the sky.',
];

/// Lines the guard must still fail. Each is a real internal leak.
const List<String> _leaks = <String>[
  'Pixel drew this figure.',
  'Ask Pixel for the icon set.',
  "Pixel's render of the antenna pattern.",
  'Graphics by Pixel.',
  // A product mention on the same line does not shelter the person.
  'Google Pixel phone art, Pixel drew it.',
  // Workstream references with a word boundary before them.
  'See WS-003 for the install steps.',
  '(WS-2) import notes',
  'WS-1',
  // The article rule does not shelter the person either.
  'Ask Pixel, not a Pixel phone, for the figure.',
];

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

String _dartEscape(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');

/// Run the Dart string stage on a one-line fixture. Returns the exit code.
ProcessResult _runDartStage(String root, String line) {
  final Directory tmp =
      Directory.systemTemp.createTempSync('leakage_dart_fixture_');
  try {
    final File f = File('${tmp.path}/fixture.dart');
    f.writeAsStringSync("const String s = '${_dartEscape(line)}';\n");
    return Process.runSync(
      'python3',
      <String>['$root/scripts/leakage_guard_dart.py', f.path],
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// Run the asset stage on a one-line .md fixture, from a scratch root with no
/// lib/, so the shell's own Dart stage is skipped. Returns the exit code.
ProcessResult _runAssetStage(String root, String line) {
  final Directory tmp =
      Directory.systemTemp.createTempSync('leakage_asset_fixture_');
  try {
    Directory('${tmp.path}/scripts').createSync();
    File('$root/scripts/leakage-guard.sh')
        .copySync('${tmp.path}/scripts/leakage-guard.sh');
    File('$root/scripts/leakage_guard_dart.py')
        .copySync('${tmp.path}/scripts/leakage_guard_dart.py');
    Directory('${tmp.path}/fixtures').createSync();
    File('${tmp.path}/fixtures/fixture.md').writeAsStringSync('$line\n');
    return Process.runSync(
      'bash',
      <String>['${tmp.path}/scripts/leakage-guard.sh', '${tmp.path}/fixtures'],
      workingDirectory: tmp.path,
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  final String root = _packageRoot();

  group('leakage guard, Dart string stage', () {
    for (final String line in _allowed) {
      test('allows: $line', () {
        final ProcessResult r = _runDartStage(root, line);
        expect(r.exitCode, 0,
            reason: 'False positive on a legitimate line.\n${r.stdout}');
      });
    }
    for (final String line in _leaks) {
      test('catches: $line', () {
        final ProcessResult r = _runDartStage(root, line);
        expect(r.exitCode, 1,
            reason: 'A real internal reference passed the guard.\n${r.stdout}');
      });
    }
  });

  group('leakage guard, asset stage', () {
    for (final String line in _allowed) {
      test('allows: $line', () {
        final ProcessResult r = _runAssetStage(root, line);
        expect(r.exitCode, 0,
            reason: 'False positive on a legitimate line.\n${r.stdout}');
      });
    }
    for (final String line in _leaks) {
      test('catches: $line', () {
        final ProcessResult r = _runAssetStage(root, line);
        expect(r.exitCode, 1,
            reason: 'A real internal reference passed the guard.\n${r.stdout}');
      });
    }
  });
}
