// ============================================================================
// PLAY CHANGELOG GUARD — every Google Play release note must fit Play's own
// 500-character limit, and must not name a platform this build is not.
// ============================================================================
//
// WHY THIS TEST EXISTS (the miss it closes). `changelogs/26073001.txt` shipped
// at 1,080 characters against Play's documented 500-character ceiling. Play
// rejects an over-length changelog rather than truncating it, so the most
// likely outcome is that the 2026-07-30 Android release went out with NO
// release notes at all — and nothing in the repo, the build log or the console
// would have said so. A silent no-op is the worst failure shape available,
// because the artifact ships and only the words vanish.
//
// The same file also opened with "on iPhone and iPad", copied from the iOS
// notes into a Google Play changelog. Nobody caught it for a month, plausibly
// because nobody ever saw it rendered — the over-length rejection hid the
// second defect behind the first.
//
// TWO RULES, both mechanical:
//   1. <= 500 bytes. Play's limit, and it is bytes, not runes.
//   2. No iOS-only platform noun. An Android user reading about their iPad is
//      being told the notes were written for somebody else.
//
// A green run means every changelog would actually publish, and none of them
// claims to be about a platform Play does not serve.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google Play's per-locale release-note ceiling.
const int _kPlayChangelogLimit = 500;

/// Platform nouns that must never appear in a Google Play changelog. Kept
/// deliberately short: these are unambiguous, and a longer list would start
/// producing false positives on legitimate cross-platform prose.
const List<String> _kForeignPlatforms = <String>[
  'iPhone',
  'iPad',
  'App Store',
  'TestFlight',
];

void main() {
  test('every Play changelog fits the 500-character limit', () {
    final Directory dir = _changelogDir();
    final List<File> files = _changelogs(dir);

    expect(
      files,
      isNotEmpty,
      reason: 'no changelogs found under ${dir.path} — the guard would pass '
          'vacuously, which is the failure it exists to prevent',
    );

    final List<String> over = <String>[];
    for (final File f in files) {
      final int bytes = f.lengthSync();
      if (bytes > _kPlayChangelogLimit) {
        over.add('${f.uri.pathSegments.last}: $bytes bytes '
            '(${bytes - _kPlayChangelogLimit} over)');
      }
    }

    expect(
      over,
      isEmpty,
      reason: 'Play REJECTS an over-length changelog rather than truncating it, '
          'so these releases would ship with no release notes and nothing '
          'would report it:\n  ${over.join("\n  ")}',
    );
  });

  test('no Play changelog names an iOS-only platform', () {
    final List<File> files = _changelogs(_changelogDir());
    final List<String> offenders = <String>[];

    for (final File f in files) {
      final String text = f.readAsStringSync();
      for (final String noun in _kForeignPlatforms) {
        if (text.contains(noun)) {
          offenders.add('${f.uri.pathSegments.last}: "$noun"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'a Google Play changelog is read only by Android users; naming an '
          'Apple platform means the text was copied from the iOS notes:\n  '
          '${offenders.join("\n  ")}',
    );
  });
}

Directory _changelogDir() => Directory(
      '${_packageRoot()}/android/fastlane/metadata/android/en-US/changelogs',
    );

List<File> _changelogs(Directory dir) => dir.existsSync()
    ? dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.txt'))
        .toList(growable: false)
    : <File>[];

/// Resolve the package root whether the test runs from the package dir or a
/// nested working directory.
String _packageRoot() {
  Directory dir = Directory.current;
  for (int i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
