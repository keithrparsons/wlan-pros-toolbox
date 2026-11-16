import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/triage_ladder.dart';
import 'package:wlan_pros_toolbox/services/network/port_check_verdict.dart';

typedef Rule = TargetOutcome? Function(PortCheckTarget t);

/// Every target gets [base] unless [rule] says otherwise.
Map<PortCheckTarget, TargetOutcome> run(
  Rule rule, {
  TargetOutcome base = TargetOutcome.gotOut,
}) => <PortCheckTarget, TargetOutcome>{
  for (final PortCheckTarget t in kPortCheckTargets) t: rule(t) ?? base,
};

bool tcp(PortCheckTarget t, int port) =>
    t.transport == PortCheckTransport.tcp && t.port == port;
bool udp(PortCheckTarget t, int port) =>
    t.transport == PortCheckTransport.udp && t.port == port;

Rule failing(bool Function(PortCheckTarget) which) =>
    (PortCheckTarget t) => which(t) ? TargetOutcome.didNotGetOut : null;

PortCheckGroup groupNamed(PortCheckReport r, String startsWith) =>
    r.groups.firstWhere((PortCheckGroup g) => g.name.startsWith(startsWith));

String allText(PortCheckReport r) => <String>[
  r.summary,
  for (final PortCheckGroup g in r.groups) ...<String>[
    g.name,
    g.status.word,
    ...g.details,
  ],
].join('\n');

void main() {
  group('target table', () {
    test('no target is a wlanpros.com host (Keith, 13 NOV)', () {
      for (final PortCheckTarget t in kPortCheckTargets) {
        expect(t.host.toLowerCase(), isNot(contains('wlanpros')));
      }
    });

    test(
      'every target names an operator; no port has two from one operator',
      () {
        final Set<String> seen = <String>{};
        for (final PortCheckTarget t in kPortCheckTargets) {
          expect(t.operator, isNotEmpty);
          expect(t.port, inInclusiveRange(1, 65535));
          final String key = '${t.transport.name}/${t.port}/${t.operator}';
          expect(
            seen.add(key),
            isTrue,
            reason: '${t.host}:${t.port} repeats an operator on one port',
          );
        }
      },
    );

    test('UDP targets say how they are probed; TCP targets do not', () {
      for (final PortCheckTarget t in kPortCheckTargets) {
        expect(
          t.udp != null,
          t.transport == PortCheckTransport.udp,
          reason: '${t.host}:${t.port}',
        );
      }
    });

    test('two baseline hosts, both on 443', () {
      final List<PortCheckTarget> b = kPortCheckTargets
          .where((PortCheckTarget t) => t.baseline)
          .toList();
      expect(b.length, 2);
      expect(b.every((PortCheckTarget t) => tcp(t, 443)), isTrue);
    });
  });

  group('baseline', () {
    test(
      'nothing answers: every group is Not checked, summary says no internet',
      () {
        final PortCheckReport r = judgePortCheck(
          run((_) => null, base: TargetOutcome.didNotGetOut),
        );
        expect(r.groups, isNotEmpty);
        for (final PortCheckGroup g in r.groups) {
          expect(g.status, TriageStatus.notChecked, reason: g.name);
        }
        expect(r.summary, contains('No internet got through'));
      },
    );

    test('a sign-in network skips the run and says to sign in first', () {
      final PortCheckReport r = judgePortCheck(
        run((_) => null),
        signInNeeded: true,
      );
      for (final PortCheckGroup g in r.groups) {
        expect(g.status, TriageStatus.notChecked, reason: g.name);
      }
      expect(r.summary, contains('Sign in'));
    });

    test('one 443 target fails, the other completes: Websites Looks fine', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => tcp(t, 443) && t.host == 'example.com')),
      );
      expect(groupNamed(r, 'Websites').status, TriageStatus.looksFine);
    });
  });

  group('remote login', () {
    test('both 22 targets fail: Looks off, both named', () {
      final PortCheckReport r = judgePortCheck(run(failing((t) => tcp(t, 22))));
      final PortCheckGroup g = groupNamed(r, 'Remote login');
      expect(g.status, TriageStatus.looksOff);
      for (final PortCheckTarget t in kPortCheckTargets.where(
        (t) => tcp(t, 22),
      )) {
        expect(g.details.join(' '), contains(t.host));
      }
    });

    test(
      'one 22 target fails, the other completes: Looks fine, no warning',
      () {
        final PortCheckReport r = judgePortCheck(
          run(failing((t) => tcp(t, 22) && t.host == 'github.com')),
        );
        final PortCheckGroup g = groupNamed(r, 'Remote login');
        expect(g.status, TriageStatus.looksFine);
        expect(g.details.join(' '), isNot(contains('did not')));
      },
    );

    test('a lookup failure on one target is never blamed on the port', () {
      final PortCheckReport r = judgePortCheck(
        run(
          (t) => tcp(t, 22)
              ? (t.host == 'github.com'
                    ? TargetOutcome.noVerdict
                    : TargetOutcome.didNotGetOut)
              : null,
        ),
      );
      expect(groupNamed(r, 'Remote login').status, TriageStatus.notChecked);
    });
  });

  group('email sending', () {
    test(
      '587 gets out, 25 and 465 fail: Looks fine, 25 mentioned as common',
      () {
        final PortCheckReport r = judgePortCheck(
          run(failing((t) => tcp(t, 25) || tcp(t, 465))),
        );
        final PortCheckGroup g = groupNamed(r, 'Email sending');
        expect(g.status, TriageStatus.looksFine);
        final String text = g.details.join(' ');
        expect(text, contains('25'));
        expect(text, contains('common'));
      },
    );

    test('587 and 465 fail on both operators: Looks off', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => tcp(t, 587) || tcp(t, 465))),
      );
      expect(groupNamed(r, 'Email sending').status, TriageStatus.looksOff);
    });

    test(
      '25 alone gets out: Looks off, 587 and 465 are what mail apps use',
      () {
        final PortCheckReport r = judgePortCheck(
          run(failing((t) => tcp(t, 587) || tcp(t, 465))),
        );
        final PortCheckGroup g = groupNamed(r, 'Email sending');
        expect(g.status, TriageStatus.looksOff);
        expect(g.details.join(' '), contains('587'));
      },
    );
  });

  group('name lookups', () {
    test('UDP 53 replies but 853 is blocked: Looks fine', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => tcp(t, 853))),
      );
      expect(groupNamed(r, 'Name lookups').status, TriageStatus.looksFine);
    });

    // Keith, 16 NOV, picked "Looks fine, with a note (Recommended)": the
    // baseline hosts resolved, so this network's own DNS works even when
    // outside DNS servers are blocked.
    test('UDP 53 and 853 both blocked: Looks fine, with a note that outside '
        'DNS is blocked and this network\'s own DNS answers', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => tcp(t, 853) || udp(t, 53))),
      );
      final PortCheckGroup dns = groupNamed(r, 'Name lookups');
      expect(dns.status, TriageStatus.looksFine);
      expect(
        dns.details,
        contains(
          'Outside DNS servers are blocked. This network\'s own DNS answers.',
        ),
      );
    });

    test('outside DNS answering: no blocked note', () {
      final PortCheckReport r = judgePortCheck(run((_) => null));
      expect(
        groupNamed(r, 'Name lookups').details.join(' '),
        isNot(contains('Outside DNS servers are blocked')),
      );
    });
  });

  group('UDP', () {
    test('one silent and one replying target in a pair: gets out', () {
      final PortCheckReport r = judgePortCheck(
        run(
          failing(
            (t) => t.udp == UdpProbeKind.stun && t.host.contains("cloudflare"),
          ),
        ),
      );
      // Cloudflare STUN silent, Google STUN replies.
      expect(groupNamed(r, 'Calls').status, TriageStatus.looksFine);
    });

    test('QUIC has one target, so its silence alone is no verdict', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => t.udp == UdpProbeKind.quic)),
      );
      final String websites = groupNamed(r, 'Websites').details.join(' ');
      expect(websites, contains('QUIC (UDP 443) was not checked.'));
      expect(websites, isNot(contains('either test server')));
    });

    test('all UDP silent while TCP passes: No UDP got through at all', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => t.transport == PortCheckTransport.udp)),
      );
      final PortCheckGroup calls = groupNamed(r, 'Calls');
      expect(calls.status, TriageStatus.looksOff);
      expect(calls.details.join(' '), contains('No UDP got through at all'));
      expect(
        groupNamed(r, 'Name lookups').details.join(' '),
        contains('No UDP got through at all'),
      );
    });

    test('STUN silent but DNS and NTP replied: Calls off, other UDP got out; '
        'VPN stays Not checked', () {
      final PortCheckReport r = judgePortCheck(
        run(failing((t) => t.udp == UdpProbeKind.stun)),
      );
      final PortCheckGroup calls = groupNamed(r, 'Calls');
      expect(calls.status, TriageStatus.looksOff);
      expect(calls.details.join(' '), contains('Other UDP did get out'));
      final PortCheckGroup vpn = groupNamed(r, 'VPN');
      expect(vpn.status, TriageStatus.notChecked);
      expect(vpn.details.join(' '), contains('Other UDP did get out'));
    });

    test('VPN is Not checked on a clean run, with a plain reason', () {
      final PortCheckReport r = judgePortCheck(run((_) => null));
      final PortCheckGroup vpn = groupNamed(r, 'VPN');
      expect(vpn.status, TriageStatus.notChecked);
      expect(vpn.details.join(' '), contains('500'));
      expect(vpn.details.join(' '), contains('4500'));
    });

    test('a device that cannot open UDP says so; nothing is faked', () {
      final PortCheckReport r = judgePortCheck(
        run(
          (t) => t.transport == PortCheckTransport.udp
              ? TargetOutcome.unavailable
              : null,
        ),
      );
      expect(groupNamed(r, 'Calls').status, TriageStatus.cantCheck);
      expect(groupNamed(r, 'Name lookups').status, TriageStatus.looksFine);
    });
  });

  group('words', () {
    test('a clean run says everything got out', () {
      final PortCheckReport r = judgePortCheck(run((_) => null));
      for (final PortCheckGroup g in r.groups.where(
        (g) => !g.name.startsWith('VPN'),
      )) {
        expect(g.status, TriageStatus.looksFine, reason: g.name);
      }
      expect(r.summary, isNotEmpty);
    });

    test('a blocked run explains Looks off is the network, not the device', () {
      final PortCheckReport r = judgePortCheck(run(failing((t) => tcp(t, 22))));
      expect(r.summary, contains('blocked on this network'));
    });

    test('no em dash, no bare AP, no octomon, every word from the ladder', () {
      final Set<String> ladder = TriageStatus.values
          .map((TriageStatus s) => s.word)
          .toSet();
      final List<PortCheckReport> reports = <PortCheckReport>[
        judgePortCheck(run((_) => null)),
        judgePortCheck(run((_) => null, base: TargetOutcome.didNotGetOut)),
        judgePortCheck(run(failing((t) => tcp(t, 22) || tcp(t, 587)))),
        judgePortCheck(
          run(failing((t) => t.transport == PortCheckTransport.udp)),
        ),
        judgePortCheck(run((_) => null), signInNeeded: true),
      ];
      for (final PortCheckReport r in reports) {
        final String text = allText(r);
        expect(text, isNot(contains('—')));
        expect(text, isNot(contains('–')));
        expect(RegExp(r'\bAPs?\b').hasMatch(text), isFalse);
        expect(text.toLowerCase(), isNot(contains('octomon')));
        for (final PortCheckGroup g in r.groups) {
          expect(ladder, contains(g.status.word));
          expect(g.status, isNot(TriageStatus.checking));
          expect(g.status, isNot(TriageStatus.notOnWifi));
        }
      }
    });

    test(
      'totality: every outcome for every target returns without throwing',
      () {
        for (final TargetOutcome o in TargetOutcome.values) {
          for (final TargetOutcome b in TargetOutcome.values) {
            for (int i = 0; i < kPortCheckTargets.length; i++) {
              final Map<PortCheckTarget, TargetOutcome> m = run(
                (_) => null,
                base: b,
              );
              m[kPortCheckTargets[i]] = o;
              expect(() => judgePortCheck(m), returnsNormally);
            }
          }
        }
      },
    );
  });
}
