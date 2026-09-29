// The existing Join mode and Roam are unchanged by the security-
// compatibility mode (spec 43, Done means): every configuration builds the
// same ladder, field for field, as commit 4d2b460a did.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';

import 'join_roam_fingerprint.dart';

const String _fixture = 'test/fixtures/join_roam_4d2b460a_fingerprints.json';

// 2026-09-29, the merge into wifi-lab/preview-1.12: six-ghz-race (spec 40,
// 7913f9f0, gated by Vera, gate A) deliberately reworded ONE caption, the
// FILS Discovery frame's in a 6 GHz passive scan, to say the standard
// requires it only of a 6 GHz-only AP. That rewording changes 129 of the 775
// fingerprints (every 6 GHz passive Join and Roam ladder) and nothing else.
// The fixture stays pinned to 4d2b460a so this test keeps proving what it
// was written for, that Why won't it associate? leaves Join and Roam alone:
// the race's new caption is mapped back to the 4d2b460a wording before
// hashing, and any other change still fails.
const String _raceFilsCaption =
    'This AP sends a short discovery frame every 20 TU (the standard '
    'requires it of a 6 GHz-only AP that wants to be found), so a passive '
    'scanner finds it long before the next beacon. ';
const String _pinnedFilsCaption =
    'A 6 GHz AP sends a short discovery frame every 20 TU, so a passive '
    'scanner finds it long before the next beacon. ';

String _asPinned(String text) =>
    text.replaceAll(_raceFilsCaption, _pinnedFilsCaption);

Map<String, String> _current() => <String, String>{
  for (final MapEntry<String, JrConfig> e in allJoinConfigs().entries)
    e.key: fnv1a64(_asPinned(jrText(buildJoin(e.value)))),
  for (final MapEntry<String, JrConfig> e in allRoamConfigs().entries)
    e.key: fnv1a64(_asPinned(jrText(buildRoam(e.value)))),
};

void main() {
  test(
    'capture (only with WRITE_JR_FINGERPRINTS=1)',
    () {
      final Map<String, String> now = _current();
      File(
        _fixture,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(now));
    },
    skip: Platform.environment['WRITE_JR_FINGERPRINTS'] != '1',
  );

  test('every Join and Roam ladder matches the 4d2b460a fingerprint', () {
    final Map<String, dynamic> want =
        jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, String> now = _current();
    expect(now.keys.toSet(), want.keys.toSet());
    final List<String> changed = <String>[
      for (final String k in want.keys)
        if (now[k] != want[k]) k,
    ];
    expect(changed, isEmpty, reason: 'changed: ${changed.take(10)}');
    expect(want.length, greaterThan(600));
  });

  test('the only mapping applied is the race\'s FILS caption, and it is '
      'still the caption the model draws', () {
    // If the caption is reworded again, the mapping above goes stale and
    // this fails first, rather than the fingerprints failing for no stated
    // reason.
    const JrConfig sixPassive = JrConfig(
      band: JrBand.g6,
      scanType: JrScanType.passive,
    );
    final String text = jrText(buildJoin(sixPassive));
    expect(text, contains(_raceFilsCaption));
    expect(text, isNot(contains(_pinnedFilsCaption)));
  });
}
