// TriageLadder, pure unit tests (no Flutter, no network, no radio).
//
// The ladder is a view of facts the run already has. Each test names one
// behavior. The hazards it guards are the project's recurring "wrong kind of
// null" bugs: not on Wi-Fi must never read as a Wi-Fi fault (R-05N), an iPhone
// without the Shortcut must never get a fake Poor (R-31), none-vs-mixed cloud
// apps stay distinct (R-40 / R-41), and a sign-in network takes priority.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_input.dart';
import 'package:wlan_pros_toolbox/services/network/analyze/analyze_rules.dart'
    show kDnsSlowMs;
import 'package:wlan_pros_toolbox/services/network/analyze/triage_ladder.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_vs_internet.dart';

const OnlineEvidence _online = OnlineEvidence(
  dnsResolved: true,
  publicIpObtained: true,
  cloudReachable: true,
);

/// A healthy native run: every probe present and answering.
TriageInput healthy({
  WifiVsInternetVerdict verdict = WifiVsInternetVerdict.bothHealthy,
  int? rssiDbm = -55,
  bool notOnWifi = false,
  bool platformIsIos = false,
  bool wifiSignalCaptured = true,
  TriageDnsState dns = TriageDnsState.resolved,
  int? dnsMs = 20,
  OnlineEvidence evidence = _online,
  bool internetMeasured = true,
  InternetHealth? internetHealth = InternetHealth.good,
  bool speedTestSkipped = false,
  bool cloudPanelPresent = true,
  int? cloudReachable = 14,
  int? cloudTotal = 14,
}) => TriageInput(
  verdict: verdict,
  rssiDbm: rssiDbm,
  notOnWifi: notOnWifi,
  platformIsIos: platformIsIos,
  wifiSignalCaptured: wifiSignalCaptured,
  dns: dns,
  dnsMs: dnsMs,
  evidence: evidence,
  internetMeasured: internetMeasured,
  internetHealth: internetHealth,
  speedTestSkipped: speedTestSkipped,
  cloudPanelPresent: cloudPanelPresent,
  cloudReachableCount: cloudReachable,
  cloudTotalCount: cloudTotal,
);

TriageRung rung(TriageLadder l, TriageRungId id) =>
    l.rungs.firstWhere((TriageRung r) => r.id == id);

TriageStatus status(TriageLadder l, TriageRungId id) => rung(l, id).status;

void main() {
  group('shape', () {
    test('no verdict yet: no rungs, no summary, no throw', () {
      final TriageLadder l = TriageLadder.compute(const TriageInput());
      expect(l.rungs, isEmpty);
      expect(l.summary, isNull);
      expect(l.isEmpty, isTrue);
    });

    test('healthy run: four rungs, all Looks fine, no summary', () {
      final TriageLadder l = TriageLadder.compute(healthy());
      expect(l.rungs.map((TriageRung r) => r.id), <TriageRungId>[
        TriageRungId.wifiLink,
        TriageRungId.dns,
        TriageRungId.internet,
        TriageRungId.services,
      ]);
      expect(
        l.rungs.every((TriageRung r) => r.status == TriageStatus.looksFine),
        isTrue,
      );
      expect(l.summary, isNull);
    });

    test('there is no router/access point rung on native input', () {
      for (final WifiVsInternetVerdict v in WifiVsInternetVerdict.values) {
        final TriageLadder l = TriageLadder.compute(healthy(verdict: v));
        expect(
          l.rungs.map((TriageRung r) => r.name).join(),
          isNot(contains('router')),
        );
        expect(l.rungs.length, lessThanOrEqualTo(4));
      }
    });

    test('rung names', () {
      final TriageLadder l = TriageLadder.compute(healthy());
      expect(l.rungs.map((TriageRung r) => r.name), <String>[
        'Wi-Fi link',
        'Name lookup (DNS)',
        'The internet',
        'Services',
      ]);
    });
  });

  group('Wi-Fi link', () {
    test('Looks off for wifiLimiter', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          evidence: const OnlineEvidence(),
        ),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksOff);
    });

    test('Looks off for bothContributing', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.bothContributing),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksOff);
    });

    test('Looks off for a Poor RSSI when the verdict is not upstream', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.onlineUnmeasured, rssiDbm: -85),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksOff);
    });

    test('not blamed for an upstream verdict with a middling signal', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.upstream, rssiDbm: -65),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksFine);
    });

    test('R-05N: not on Wi-Fi is neutral, never a Wi-Fi fault', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          notOnWifi: true,
          platformIsIos: true,
          wifiSignalCaptured: false,
          rssiDbm: null,
        ),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.notOnWifi);
      expect(l.summary ?? '', isNot(contains('Wi-Fi')));
    });

    test('R-31: iOS on Wi-Fi without the Shortcut is Not checked', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          platformIsIos: true,
          wifiSignalCaptured: false,
          rssiDbm: null,
        ),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.notChecked);
      expect(l.summary ?? '', isNot(contains('Wi-Fi link')));
    });

    test('wired macOS or Windows (wifiUnknown, not iOS) is Can\'t check', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.wifiUnknown, rssiDbm: null),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.cantCheck);
    });
  });

  group('Name lookup (DNS)', () {
    test('Looks off at exactly kDnsSlowMs, Looks fine one below', () {
      expect(
        status(
          TriageLadder.compute(healthy(dnsMs: kDnsSlowMs)),
          TriageRungId.dns,
        ),
        TriageStatus.looksOff,
      );
      expect(
        status(
          TriageLadder.compute(healthy(dnsMs: kDnsSlowMs - 1)),
          TriageRungId.dns,
        ),
        TriageStatus.looksFine,
      );
    });

    test('failed, pending and absent are three different answers', () {
      final TriageLadder failed = TriageLadder.compute(
        healthy(dns: TriageDnsState.failed, dnsMs: null),
      );
      final TriageLadder pending = TriageLadder.compute(
        healthy(dns: TriageDnsState.pending, dnsMs: null),
      );
      final TriageLadder absent = TriageLadder.compute(
        healthy(dns: TriageDnsState.absent, dnsMs: null),
      );
      expect(status(failed, TriageRungId.dns), TriageStatus.looksOff);
      expect(status(pending, TriageRungId.dns), TriageStatus.checking);
      expect(
        absent.rungs.any((TriageRung r) => r.id == TriageRungId.dns),
        isFalse,
      );
    });
  });

  group('The internet', () {
    test(
      'Looks off for upstream, bothContributing and internetUnreachable',
      () {
        for (final WifiVsInternetVerdict v in <WifiVsInternetVerdict>[
          WifiVsInternetVerdict.upstream,
          WifiVsInternetVerdict.bothContributing,
          WifiVsInternetVerdict.internetUnreachable,
        ]) {
          expect(
            status(
              TriageLadder.compute(healthy(verdict: v)),
              TriageRungId.internet,
            ),
            TriageStatus.looksOff,
            reason: '$v',
          );
        }
      },
    );

    test('skipped speed test with reachability confirmed is Looks fine', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.onlineUnmeasured,
          speedTestSkipped: true,
          internetMeasured: false,
          internetHealth: null,
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.looksFine);
      expect(rung(l, TriageRungId.internet).reason, contains('skipped'));
    });

    test('skipped speed test with no other evidence is Not checked', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          notOnWifi: true,
          speedTestSkipped: true,
          internetMeasured: false,
          internetHealth: null,
          evidence: const OnlineEvidence(),
          dns: TriageDnsState.pending,
          dnsMs: null,
          cloudReachable: null,
          cloudTotal: null,
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.notChecked);
    });

    test('wired desktop with a Poor internet read is Looks off', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          rssiDbm: null,
          internetHealth: InternetHealth.marginal,
          evidence: const OnlineEvidence(),
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.looksOff);
    });

    test('a weak Wi-Fi link does not make the internet read Looks fine off '
        'its own throughput', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          evidence: const OnlineEvidence(),
          internetHealth: InternetHealth.marginal,
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.notChecked);
    });

    test('independent evidence (DNS, public IP, services) still counts when '
        'the Wi-Fi link is the limit', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          internetHealth: InternetHealth.marginal,
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.looksFine);
    });
  });

  group('Services', () {
    test('R-40: none reachable while the internet was measured is off', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(cloudReachable: 0, cloudTotal: 14),
      );
      expect(status(l, TriageRungId.services), TriageStatus.looksOff);
    });

    test('none reachable with nothing measured is Not checked', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          cloudReachable: 0,
          cloudTotal: 14,
          internetMeasured: false,
          internetHealth: null,
        ),
      );
      expect(status(l, TriageRungId.services), TriageStatus.notChecked);
    });

    test('R-41: mixed is off, and the summary says only some services', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(cloudReachable: 9, cloudTotal: 14),
      );
      expect(status(l, TriageRungId.services), TriageStatus.looksOff);
      expect(
        l.summary,
        'It looks like only some services are unhappy, not the whole '
        'internet.',
      );
    });

    test('panel present but not answered is Checking; absent is omitted', () {
      final TriageLadder pending = TriageLadder.compute(
        healthy(cloudReachable: null, cloudTotal: null),
      );
      final TriageLadder absent = TriageLadder.compute(
        healthy(
          cloudPanelPresent: false,
          cloudReachable: null,
          cloudTotal: null,
        ),
      );
      expect(status(pending, TriageRungId.services), TriageStatus.checking);
      expect(
        absent.rungs.any((TriageRung r) => r.id == TriageRungId.services),
        isFalse,
      );
    });
  });

  group('summary', () {
    test('captive portal: internet Looks off with the sign-in reason, and the '
        'sign-in sentence beats every other rung', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.captivePortal,
          rssiDbm: -85,
          dnsMs: 900,
          cloudReachable: 0,
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.looksOff);
      expect(
        rung(l, TriageRungId.internet).reason,
        'This network wants a sign-in.',
      );
      expect(l.summary, 'It looks like this network wants a sign-in.');
    });

    test('names the first rung outward that looks off', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiLimiter,
          dnsMs: 900,
          evidence: const OnlineEvidence(),
        ),
      );
      expect(l.summary, 'It looks like the trouble sits at your Wi-Fi link.');
    });

    test('DNS is named when it is the first rung that looks off', () {
      final TriageLadder l = TriageLadder.compute(healthy(dnsMs: 900));
      expect(l.summary, 'It looks like the trouble sits at name lookup (DNS).');
    });

    test('internet is named when nothing nearer looks off', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.upstream),
      );
      expect(l.summary, 'It looks like the trouble sits with the internet.');
    });

    test('no summary when only unchecked or neutral rungs remain', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          platformIsIos: true,
          wifiSignalCaptured: false,
          rssiDbm: null,
        ),
      );
      expect(l.summary, isNull);
    });
  });

  group('words and totality', () {
    test('every status has a distinct word, and none uses an em dash', () {
      final Set<String> words = TriageStatus.values
          .map((TriageStatus s) => s.word)
          .toSet();
      expect(words.length, TriageStatus.values.length);
      expect(words, contains('Looks fine'));
      expect(words, contains('Looks off'));
      expect(words, contains('Not on Wi-Fi'));
      expect(words, contains('Checking'));
      for (final String w in words) {
        expect(w, isNot(contains('—')));
      }
    });

    test('all copy is clean: no em dash, no bare AP, no internal process', () {
      final List<String> all = <String>[];
      for (final WifiVsInternetVerdict v in WifiVsInternetVerdict.values) {
        for (final bool off in <bool>[false, true]) {
          for (final bool ios in <bool>[false, true]) {
            for (final bool skipped in <bool>[false, true]) {
              final TriageLadder l = TriageLadder.compute(
                healthy(
                  verdict: v,
                  notOnWifi: off,
                  platformIsIos: ios,
                  wifiSignalCaptured: !ios,
                  speedTestSkipped: skipped,
                  dnsMs: off ? 900 : 20,
                  cloudReachable: skipped ? 3 : 14,
                ),
              );
              all.add(l.summary ?? '');
              for (final TriageRung r in l.rungs) {
                all
                  ..add(r.name)
                  ..add(r.reason ?? '');
              }
            }
          }
        }
      }
      final String text = all.join('\n');
      expect(text, isNot(contains('—')));
      expect(RegExp(r'\bAP\b').hasMatch(text), isFalse);
      expect(text.toLowerCase(), isNot(contains('octomon')));
      expect(RegExp(r'\bbots?\b').hasMatch(text.toLowerCase()), isFalse);
    });

    test('total: every verdict and flag combination returns without '
        'throwing, and a rung only ever appears once', () {
      for (final WifiVsInternetVerdict v in WifiVsInternetVerdict.values) {
        for (final bool off in <bool>[false, true]) {
          for (final bool ios in <bool>[false, true]) {
            for (final bool captured in <bool>[false, true]) {
              for (final bool skipped in <bool>[false, true]) {
                for (final TriageDnsState d in TriageDnsState.values) {
                  final TriageLadder l = TriageLadder.compute(
                    healthy(
                      verdict: v,
                      notOnWifi: off,
                      platformIsIos: ios,
                      wifiSignalCaptured: captured,
                      speedTestSkipped: skipped,
                      dns: d,
                      rssiDbm: captured ? -60 : null,
                    ),
                  );
                  final Set<TriageRungId> ids = l.rungs
                      .map((TriageRung r) => r.id)
                      .toSet();
                  expect(ids.length, l.rungs.length);
                }
              }
            }
          }
        }
      }
    });
  });

  group('plain text', () {
    test('serializes every rung with its word, reason and the summary', () {
      final TriageLadder l = TriageLadder.compute(healthy(dnsMs: 900));
      final String text = triageLadderToPlainText(l);
      expect(text, startsWith('Where it looks off'));
      expect(text, contains('Wi-Fi link: Looks fine'));
      expect(text, contains('Name lookup (DNS): Looks off'));
      expect(text, contains(l.summary!));
      expect(text, isNot(contains('—')));
    });

    test('a healthy ladder is headed Nothing looks off', () {
      final TriageLadder l = TriageLadder.compute(healthy());
      expect(l.heading, 'Nothing looks off');
      expect(triageLadderToPlainText(l), startsWith('Nothing looks off'));
    });

    test('a ladder with a Looks off row is headed Where it looks off', () {
      final TriageLadder l = TriageLadder.compute(healthy(dnsMs: 900));
      expect(l.heading, 'Where it looks off');
    });

    test('empty ladder serializes to an empty string', () {
      expect(
        triageLadderToPlainText(TriageLadder.compute(const TriageInput())),
        '',
      );
    });
  });

  group('settled and fromAnalyzeInput', () {
    test('settled turns Checking into Not checked, leaves the rest alone', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          dns: TriageDnsState.pending,
          dnsMs: null,
          cloudReachable: null,
          cloudTotal: null,
        ),
      ).settled();
      expect(status(l, TriageRungId.dns), TriageStatus.notChecked);
      expect(status(l, TriageRungId.services), TriageStatus.notChecked);
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksFine);
      expect(
        l.rungs.any((TriageRung r) => r.status == TriageStatus.checking),
        isFalse,
      );
    });

    test('fromAnalyzeInput carries the run\'s own fields across', () {
      const AnalyzeInput a = AnalyzeInput(
        verdict: WifiVsInternetVerdict.upstream,
        rssiDbm: -60,
        notOnWifi: false,
        platformIsIos: true,
        wifiSignalCaptured: true,
        dnsResolutionMs: 250,
        internetMeasured: true,
        speedTestSkipped: false,
        cloudReachableCount: 2,
        cloudTotalCount: 5,
      );
      final TriageInput t = TriageInput.fromAnalyzeInput(
        a,
        dns: TriageDnsState.resolved,
        evidence: _online,
        internetHealth: InternetHealth.marginal,
        cloudPanelPresent: true,
      );
      expect(t.verdict, WifiVsInternetVerdict.upstream);
      expect(t.rssiDbm, -60);
      expect(t.platformIsIos, isTrue);
      expect(t.dnsMs, 250);
      expect(t.internetMeasured, isTrue);
      expect(t.cloudReachableCount, 2);
      expect(t.cloudTotalCount, 5);
      expect(t.internetHealth, InternetHealth.marginal);
    });
  });

  group('review fixes', () {
    test('wired desktop with online evidence: a measured Poor internet is '
        'still Looks off (grade beats reachability)', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          rssiDbm: null,
          internetHealth: InternetHealth.marginal,
        ),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.looksOff);
      expect(
        rung(l, TriageRungId.internet).reason,
        'The internet measurements were below the Good range.',
      );
    });

    test('wired desktop with online evidence and a Good grade reads the '
        'grade, not "speed could not be measured"', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.wifiUnknown, rssiDbm: null),
      );
      expect(status(l, TriageRungId.internet), TriageStatus.looksFine);
      expect(
        rung(l, TriageRungId.internet).reason,
        'Speed and response look healthy.',
      );
    });

    test('Wi-Fi link has no reading behind it for a verdict that never '
        'inspects Wi-Fi: Can\'t check, not Looks fine', () {
      for (final WifiVsInternetVerdict v in <WifiVsInternetVerdict>[
        WifiVsInternetVerdict.internetUnreachable,
        WifiVsInternetVerdict.captivePortal,
        WifiVsInternetVerdict.onlineUnmeasured,
      ]) {
        final TriageLadder l = TriageLadder.compute(
          healthy(verdict: v, rssiDbm: null),
        );
        expect(
          status(l, TriageRungId.wifiLink),
          TriageStatus.cantCheck,
          reason: '$v',
        );
      }
    });

    test('Wi-Fi link is Looks fine for those verdicts once an RSSI grades', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.captivePortal, rssiDbm: -55),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksFine);
    });

    test('Wi-Fi link is still Looks fine for a verdict that measured the '
        'link rate, with no RSSI', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.bothHealthy, rssiDbm: null),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksFine);
    });

    test('a cloud panel that errored is Not checked, never Checking', () {
      final TriageLadder l = TriageLadder.compute(
        const TriageInput(
          verdict: WifiVsInternetVerdict.bothHealthy,
          cloudPanelPresent: true,
          cloudFailed: true,
        ),
      );
      expect(status(l, TriageRungId.services), TriageStatus.notChecked);
      expect(
        rung(l, TriageRungId.services).reason,
        'The services check did not complete.',
      );
      expect(
        l.settled().rungs.last.reason,
        rung(l, TriageRungId.services).reason,
      );
    });

    test(
      'wifiUnknown with a Poor RSSI is Looks off, never "did not report"',
      () {
        final TriageLadder l = TriageLadder.compute(
          healthy(verdict: WifiVsInternetVerdict.wifiUnknown, rssiDbm: -85),
        );
        expect(status(l, TriageRungId.wifiLink), TriageStatus.looksOff);
        expect(
          rung(l, TriageRungId.wifiLink).reason,
          'The Wi-Fi signal is weak.',
        );
      },
    );

    test('wifiUnknown with a healthy RSSI is Looks fine, and says signal, '
        'not link (the rate was not read)', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(verdict: WifiVsInternetVerdict.wifiUnknown, rssiDbm: -55),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.looksFine);
      expect(
        rung(l, TriageRungId.wifiLink).reason,
        'The Wi-Fi signal looks healthy.',
      );
    });

    test('wifiUnknown on iOS without the Shortcut stays Not checked even '
        'with a stale RSSI (R-31)', () {
      final TriageLadder l = TriageLadder.compute(
        healthy(
          verdict: WifiVsInternetVerdict.wifiUnknown,
          platformIsIos: true,
          wifiSignalCaptured: false,
          rssiDbm: -55,
        ),
      );
      expect(status(l, TriageRungId.wifiLink), TriageStatus.notChecked);
    });
  });
}
