// The existing Join mode and Roam are unchanged by the security-
// compatibility mode (spec 43, Done means): every configuration builds the
// same ladder, field for field, as commit 4d2b460a did.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';

import 'join_roam_fingerprint.dart';

const String _fixture = 'test/fixtures/join_roam_4d2b460a_fingerprints.json';

Map<String, String> _current() => <String, String>{
  for (final MapEntry<String, JrConfig> e in allJoinConfigs().entries)
    e.key: fnv1a64(jrText(buildJoin(e.value))),
  for (final MapEntry<String, JrConfig> e in allRoamConfigs().entries)
    e.key: fnv1a64(jrText(buildRoam(e.value))),
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
}
