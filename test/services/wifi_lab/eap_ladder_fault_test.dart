// Break it (spec 42, myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 42-eap-break-it.md): the shared failure marker, and every fault's cut.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';

import 'eap_ladder_fingerprint.dart';

const String _fixture = 'test/fixtures/eap_ladder_v1_11_0_fingerprints.json';

void main() {
  test('capture (only with WRITE_LADDER_FINGERPRINTS=1)', () {
    final Map<String, String> out = <String, String>{
      for (final MapEntry<String, LadderConfig> e in allV1110Configs().entries)
        e.key: fnv1a64(ladderText(buildLadder(e.value))),
    };
    File(
      _fixture,
    ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  }, skip: Platform.environment['WRITE_LADDER_FINGERPRINTS'] != '1');

  group('no fault: identical to v1.11.0', () {
    final Map<String, dynamic> want =
        jsonDecode(File(_fixture).readAsStringSync()) as Map<String, dynamic>;

    test('the fixture covers every configuration', () {
      expect(want.keys.toSet(), allV1110Configs().keys.toSet());
      expect(want.length, 180);
    });

    for (final MapEntry<String, LadderConfig> e in allV1110Configs().entries) {
      test(e.key, () {
        final LadderSequence s = buildLadder(e.value);
        expect(fnv1a64(ladderText(s)), want[e.key], reason: ladderText(s));
        expect(s.failed, isFalse);
        expect(s.failedAt, -1);
        expect(s.faultNote, isNull);
        expect(s.helpDesk, isNull);
        expect(
          s.messages.any((LadderMessage m) => m.marksFailure || m.waitMs > 0),
          isFalse,
        );
      });
    }
  });

  group('the shared failure marker on a hand-built sequence', () {
    const LadderMessage ok = LadderMessage(
      from: LadderLane.ap,
      to: LadderLane.radius,
      kind: LadderFrameKind.radius,
      phase: LadderPhase.eapIdentity,
      label: 'Access-Request',
      description: 'answered',
    );
    const LadderMessage lost = LadderMessage(
      from: LadderLane.ap,
      to: LadderLane.radius,
      kind: LadderFrameKind.radius,
      phase: LadderPhase.eapIdentity,
      label: 'Access-Request',
      description: 'never answered',
      lost: true,
      waitMs: 3000,
    );
    const LadderMessage fail = LadderMessage(
      from: LadderLane.ap,
      to: LadderLane.client,
      kind: LadderFrameKind.eapol,
      phase: LadderPhase.eapResult,
      label: 'EAP-Failure',
      description: 'refused',
      failure: true,
    );

    test('defaults: no failure, not lost, no wait', () {
      expect(ok.failure, isFalse);
      expect(ok.lost, isFalse);
      expect(ok.waitMs, 0);
      expect(ok.marksFailure, isFalse);
    });

    test('failedAt is the first failure or lost message', () {
      final LadderSequence s = LadderSequence.forTest(
        const LadderConfig(),
        const <LadderMessage>[ok, lost, fail],
        faultNote: 'note',
        helpDesk: 'desk',
      );
      expect(s.failed, isTrue);
      expect(s.failedAt, 1);
      expect(s.faultNote, 'note');
      expect(s.helpDesk, 'desk');
    });

    test('a lost Access-Request is not a round trip; its wait is timed', () {
      final LadderSequence s = LadderSequence.forTest(
        const LadderConfig(radiusRttMs: 10),
        const <LadderMessage>[ok, lost, lost],
      );
      expect(s.wireCount, 3);
      expect(s.radiusRoundTrips, 1);
      expect(s.estimatedMs, 10 + 3000 + 3000);
    });
  });
}
