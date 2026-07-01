// Drift guard: AppVersion's synchronous fallback constants MUST mirror pubspec.
//
// WHY THIS EXISTS: [AppVersion.fallbackVersion] / [fallbackBuildNumber] are not
// only a rare failure-case value — they render unconditionally on the license
// page (`showLicensePage`, via AppVersion.display) and as the pre-resolve copy
// fallback. When they drift from pubspec, a user sees a WRONG version. They had
// already silently drifted to 1.1.0 while pubspec shipped 1.5.9 (pre-launch
// accuracy audit, 2026-06-30). This test reads pubspec.yaml directly and fails
// the build if the constants and pubspec ever disagree, so the honest value
// can't rot again.
//
// Runs with the repo root as cwd (Flutter's default for `flutter test`).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/app_version.dart';

void main() {
  test('AppVersion fallback constants mirror pubspec version+build', () {
    final File pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue,
        reason: 'pubspec.yaml must be readable from the test cwd (repo root)');

    // Match e.g. `version: 1.5.9+44` (build part optional). Anchored to a
    // line-start `version:` key so a `version:` inside a dependency block can't
    // match.
    final RegExp versionLine =
        RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+(\S+))?\s*$',
            multiLine: true);
    final Match? m = versionLine.firstMatch(pubspec.readAsStringSync());
    expect(m, isNotNull, reason: 'pubspec.yaml must declare a `version:` line');

    final String pubspecVersion = m!.group(1)!;
    final String pubspecBuild = m.group(2) ?? '';

    expect(
      AppVersion.fallbackVersion,
      pubspecVersion,
      reason: 'AppVersion.fallbackVersion drifted from pubspec version — update '
          'the constant in lib/data/app_version.dart to $pubspecVersion',
    );
    expect(
      AppVersion.fallbackBuildNumber,
      pubspecBuild,
      reason: 'AppVersion.fallbackBuildNumber drifted from pubspec build — '
          'update the constant in lib/data/app_version.dart to $pubspecBuild',
    );

    // And the composed legacy display can never be a fabricated version again.
    expect(AppVersion.display, '$pubspecVersion ($pubspecBuild)');
  });
}
