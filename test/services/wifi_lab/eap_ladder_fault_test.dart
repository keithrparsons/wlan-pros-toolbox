// Break it (spec 42, myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 42-eap-break-it.md): the shared failure marker, and every fault's cut.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';

import 'eap_ladder_fingerprint.dart';

const String _fixture = 'test/fixtures/eap_ladder_v1_11_0_fingerprints.json';

void main() {
  test(
    'capture (only with WRITE_LADDER_FINGERPRINTS=1)',
    () {
      final Map<String, String> out = <String, String>{
        for (final MapEntry<String, LadderConfig> e
            in allV1110Configs().entries)
          e.key: fnv1a64(ladderText(buildLadder(e.value))),
      };
      File(_fixture).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(out)}\n',
      );
    },
    skip: Platform.environment['WRITE_LADDER_FINGERPRINTS'] != '1',
  );

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

  group('Break it: each fault stops at the right message', () {
    Iterable<LadderConfig> eapConfigs() sync* {
      for (final LadderMethod m in <LadderMethod>[
        LadderMethod.eapTls,
        LadderMethod.peap,
        LadderMethod.eapTtls,
      ]) {
        for (final LadderInner inner in LadderInner.values) {
          for (int f = kMinCertFragments; f <= kMaxCertFragments; f++) {
            yield LadderConfig(method: m, inner: inner, certFragments: f);
          }
        }
      }
    }

    String name(LadderConfig c) =>
        '${c.method.name}/${c.inner.name}/${c.certFragments}';

    for (final LadderConfig base in eapConfigs()) {
      test('untrusted certificate: ${name(base)}', () {
        final LadderSequence s = buildLadder(
          base.copyWith(fault: LadderFault.untrustedServerCert),
        );
        final LadderMessage at = s.messages[s.failedAt];
        expect(at.from, LadderLane.client);
        expect(at.detail, 'TLS alert: unknown_ca');
        expect(at.failure, isTrue);
        // The client ACKs every certificate fragment but the last.
        final int acks = s.messages
            .take(s.failedAt)
            .where(
              (LadderMessage m) =>
                  m.from == LadderLane.client && m.detail == 'ACK (empty)',
            )
            .length;
        expect(acks, base.certFragments - 1);
        expect(s.messages.any((LadderMessage m) => m.clientCertificate), false);
        expect(
          s.messages.map((LadderMessage m) => m.label),
          isNot(contains('Access-Accept')),
        );
        expect(
          s.messages.map((LadderMessage m) => m.eapCode),
          isNot(contains('EAP-Success')),
        );
        expect(
          s.messages.where(
            (LadderMessage m) => m.kind == LadderFrameKind.eapolKey,
          ),
          isEmpty,
        );
        expect(s.messages[s.length - 3].label, 'Access-Reject');
        expect(s.messages[s.length - 2].label, 'EAP-Failure');
        expect(s.messages.last.label, 'Deauthentication');
        expect(s.messages.last.detail, contains('Reason 23'));
        // The AP's relays carry no X; it only relays.
        expect(s.messages[s.failedAt + 1].label, 'Access-Request');
        expect(s.messages[s.failedAt + 1].failure, isFalse);
        expect(s.messages[s.length - 2].failure, isFalse);
      });

      test('wrong RADIUS secret: ${name(base)}', () {
        for (int r = kMinFaultRetries; r <= kMaxFaultRetries; r++) {
          final LadderSequence s = buildLadder(
            base.copyWith(
              fault: LadderFault.wrongRadiusSecret,
              faultRetries: r,
              faultWaitS: 4,
            ),
          );
          expect(
            s.messages.where((LadderMessage m) => m.from == LadderLane.radius),
            isEmpty,
            reason: 'the server never answers',
          );
          final List<LadderMessage> requests = s.messages
              .where((LadderMessage m) => m.to == LadderLane.radius)
              .toList();
          expect(requests.length, r + 1);
          expect(requests.every((LadderMessage m) => m.lost), isTrue);
          expect(s.messages.last.lost, isTrue);
          expect(s.messages[s.failedAt].detail, 'EAP-Response / Identity');
          expect(s.radiusRoundTrips, 0);
          expect(
            s.messages.fold(0.0, (double t, LadderMessage m) => t + m.waitMs),
            r * 4000,
          );
        }
      });

      if (base.method.isTunneled) {
        test('wrong password: ${name(base)}', () {
          final LadderSequence s = buildLadder(
            base.copyWith(fault: LadderFault.wrongPassword),
          );
          final LadderMessage at = s.messages[s.failedAt];
          final bool pap =
              base.method == LadderMethod.eapTtls &&
              base.inner == LadderInner.pap;
          if (pap) {
            expect(at.label, 'Access-Reject');
            expect(s.messages[s.failedAt - 1].label, 'Access-Request');
            expect(
              s.messages[s.failedAt - 1].detail,
              '{User-Name, User-Password}',
            );
          } else {
            expect(at.from, LadderLane.radius);
            expect(at.label, 'Access-Challenge');
            expect(at.contents, contains('E=691'));
            expect(at.tunneled, isTrue);
          }
          expect(
            s.messages.map((LadderMessage m) => m.label),
            contains('Access-Reject'),
          );
          expect(
            s.messages.map((LadderMessage m) => m.label),
            isNot(contains('Access-Accept')),
          );
          expect(
            s.messages.where(
              (LadderMessage m) => m.kind == LadderFrameKind.eapolKey,
            ),
            isEmpty,
          );
          expect(s.messages.last.detail, contains('Reason 23'));
        });
      }
    }

    test('wrong password does not apply to EAP-TLS', () {
      const LadderConfig c = LadderConfig(fault: LadderFault.wrongPassword);
      expect(c.effectiveFault, LadderFault.none);
      expect(
        ladderText(buildLadder(c)),
        ladderText(buildLadder(const LadderConfig())),
      );
    });

    test('wrong passphrase: only messages 1 and 2, then reason 15', () {
      for (int r = kMinFaultRetries; r <= kMaxFaultRetries; r++) {
        final LadderSequence s = buildLadder(
          LadderConfig(
            method: LadderMethod.psk,
            fault: LadderFault.wrongPsk,
            faultRetries: r,
          ),
        );
        final List<LadderMessage> keys = s.messages
            .where((LadderMessage m) => m.kind == LadderFrameKind.eapolKey)
            .toList();
        expect(
          keys.where((LadderMessage m) => m.detail!.startsWith('Message 1')),
          hasLength(r + 1),
        );
        expect(
          keys.where((LadderMessage m) => m.detail!.startsWith('Message 2')),
          hasLength(r + 1),
        );
        expect(keys.length, 2 * (r + 1));
        expect(
          keys
              .where((LadderMessage m) => m.detail!.startsWith('Message 2'))
              .every((LadderMessage m) => m.failure),
          isTrue,
        );
        expect(s.messages.last.label, 'Deauthentication');
        expect(s.messages.last.detail, contains('Reason 15'));
        expect(s.usesRadius, isFalse);
        expect(s.indexOfMilestone(LadderMilestone.keysAvailable), -1);
      }
    });

    test('wrong SAE password: no AP Confirm, no Association', () {
      final LadderSequence s = buildLadder(
        const LadderConfig(
          method: LadderMethod.sae,
          fault: LadderFault.wrongSaePassword,
          faultRetries: 3,
        ),
      );
      expect(s.inPhase(LadderPhase.association), isEmpty);
      expect(
        s.messages.where(
          (LadderMessage m) =>
              m.label == 'SAE Confirm' && m.from == LadderLane.ap,
        ),
        isEmpty,
      );
      final List<LadderMessage> confirms = s.messages
          .where((LadderMessage m) => m.label == 'SAE Confirm')
          .toList();
      expect(confirms, hasLength(4));
      expect(confirms.every((LadderMessage m) => m.failure), isTrue);
      expect(
        s.failedAt,
        s.messages.indexWhere((LadderMessage m) => m.label == 'SAE Confirm'),
      );
      expect(s.usesRadius, isFalse);
    });

    test('no fault reaches Traffic protected or an Access-Accept', () {
      for (final LadderMethod m in LadderMethod.values) {
        for (final LadderInner inner in LadderInner.values) {
          for (final LadderFault f in LadderFault.values) {
            if (f == LadderFault.none || !f.appliesToMethod(m)) continue;
            final LadderSequence s = buildLadder(
              LadderConfig(method: m, inner: inner, fault: f),
            );
            final String what = '${m.name} ${inner.name} ${f.name}';
            expect(s.failed, isTrue, reason: what);
            expect(s.faultNote, isNotNull, reason: what);
            expect(s.helpDesk, isNotNull, reason: what);
            expect(
              s.indexOfMilestone(LadderMilestone.trafficProtected),
              -1,
              reason: what,
            );
            expect(
              s.messages.map((LadderMessage x) => x.label),
              isNot(contains('Access-Accept')),
              reason: what,
            );
            expect(neverHappened(s), isNotEmpty, reason: what);
          }
        }
      }
    });

    test('a fault is dropped when the method or roam mode rules it out', () {
      const LadderConfig c = LadderConfig(
        method: LadderMethod.peap,
        fault: LadderFault.wrongPassword,
      );
      expect(c.copyWith(method: LadderMethod.eapTls).fault, LadderFault.none);
      expect(c.copyWith(roam: LadderRoam.ftOverAir).fault, LadderFault.none);
      expect(c.copyWith(method: LadderMethod.eapTtls).fault, c.fault);
      for (final LadderRoam r in <LadderRoam>[
        LadderRoam.pmkCaching,
        LadderRoam.ftOverAir,
      ]) {
        expect(LadderFault.optionsFor(LadderMethod.peap, r), <LadderFault>[
          LadderFault.none,
        ]);
        // Built directly (not via copyWith), it still draws the fault-free
        // ladder.
        final LadderConfig direct = LadderConfig(
          method: LadderMethod.peap,
          roam: r,
          fault: LadderFault.wrongPassword,
        );
        expect(direct.effectiveFault, LadderFault.none);
        expect(buildLadder(direct).failed, isFalse);
      }
    });

    test('options per method', () {
      expect(
        LadderFault.optionsFor(LadderMethod.eapTls, LadderRoam.full),
        <LadderFault>[
          LadderFault.none,
          LadderFault.untrustedServerCert,
          LadderFault.wrongRadiusSecret,
        ],
      );
      expect(
        LadderFault.optionsFor(LadderMethod.peap, LadderRoam.full),
        <LadderFault>[
          LadderFault.none,
          LadderFault.untrustedServerCert,
          LadderFault.wrongPassword,
          LadderFault.wrongRadiusSecret,
        ],
      );
      expect(
        LadderFault.optionsFor(LadderMethod.psk, LadderRoam.full),
        <LadderFault>[LadderFault.none, LadderFault.wrongPsk],
      );
      expect(
        LadderFault.optionsFor(LadderMethod.sae, LadderRoam.full),
        <LadderFault>[LadderFault.none, LadderFault.wrongSaePassword],
      );
    });

    test('retries and wait clamp', () {
      const LadderConfig c = LadderConfig();
      expect(c.copyWith(faultRetries: 0).faultRetries, kMinFaultRetries);
      expect(c.copyWith(faultRetries: 99).faultRetries, kMaxFaultRetries);
      expect(c.copyWith(faultWaitS: 0).faultWaitS, kMinFaultWaitS);
      expect(c.copyWith(faultWaitS: 99).faultWaitS, kMaxFaultWaitS);
    });

    // Vera gate A, 2026-09-29: two Stopped-band sentences were false.
    test('wrong RADIUS secret: the note does not say EAP never started', () {
      const Map<LadderMethod, String> named = <LadderMethod, String>{
        LadderMethod.eapTls: 'EAP-TLS',
        LadderMethod.peap: 'PEAP',
        LadderMethod.eapTtls: 'EAP-TTLS',
      };
      for (final MapEntry<LadderMethod, String> e in named.entries) {
        final LadderSequence s = buildLadder(
          LadderConfig(method: e.key, fault: LadderFault.wrongRadiusSecret),
        );
        // The EAP identity exchange is drawn above the Stopped band.
        final List<String?> before = s.messages
            .take(s.failedAt)
            .map((LadderMessage m) => m.eapCode)
            .toList();
        expect(before, contains('EAP-Request/Identity'));
        expect(before, contains('EAP-Response/Identity'));
        final String note = s.faultNote!;
        // Word boundary: 'PEAP never started' is true and must pass.
        expect(
          RegExp(r'(^|[^A-Z])EAP never started').hasMatch(note),
          isFalse,
          reason: note,
        );
        expect(note, contains('${e.value} never started'), reason: note);
      }
    });

    test('untrusted certificate: EAP-TLS never mentions a password', () {
      for (final LadderInner inner in LadderInner.values) {
        final LadderSequence tls = buildLadder(
          LadderConfig(
            method: LadderMethod.eapTls,
            inner: inner,
            fault: LadderFault.untrustedServerCert,
          ),
        );
        final String text = '${tls.faultNote}\n${tls.helpDesk}'.toLowerCase();
        expect(text, isNot(contains('password')), reason: text);
        expect(
          tls.faultNote,
          contains('The client certificate was never sent.'),
        );
        for (final LadderMethod m in <LadderMethod>[
          LadderMethod.peap,
          LadderMethod.eapTtls,
        ]) {
          final LadderSequence s = buildLadder(
            LadderConfig(
              method: m,
              inner: inner,
              fault: LadderFault.untrustedServerCert,
            ),
          );
          expect(s.faultNote, contains('The password was never sent.'));
          expect(s.faultNote, isNot(contains('asked for')));
        }
      }
    });

    test('fault wording: ASCII, no em dashes, 802.1X casing', () {
      final StringBuffer all = StringBuffer();
      for (final LadderMethod m in LadderMethod.values) {
        for (final LadderInner inner in LadderInner.values) {
          for (final LadderFault f in LadderFault.values) {
            final LadderSequence s = buildLadder(
              LadderConfig(method: m, inner: inner, fault: f),
            );
            all
              ..writeln(ladderText(s))
              ..writeln(s.faultNote)
              ..writeln(s.helpDesk)
              ..writeln(neverHappened(s).join('\n'))
              ..writeln(f.label);
          }
        }
      }
      final String text = all.toString();
      expect(text.runes.every((int r) => r < 128), isTrue);
      expect(text.contains('—'), isFalse);
      expect(RegExp('802\\.1x').hasMatch(text), isFalse);
    });
  });
}
