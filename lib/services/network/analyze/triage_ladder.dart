// TriageLadder, a short "where does the trouble look like it sits" view of a
// Check My Connection run (Keith, 2026-11-12 "Ladder first"; 2026-11-13 approach
// B, compact).
//
// It walks outward from the device: Wi-Fi link, name lookup (DNS), the internet,
// specific services. It is a PRESENTATION of facts the run already has: no probe
// is added and no threshold is forked ([kDnsSlowMs] is the Analyze rule's own
// constant). A rung with no basis on the platform is omitted, never shown as a
// permanent "Not checked" (the router/access point rung exists only on the WLAN
// Pi path, phase 3, and is not built here).
//
// PURE DART, a total function of [TriageInput]: no Flutter, no network, no radio,
// so every rung is unit-testable with plain values (test/services/analyze/
// triage_ladder_test.dart).
//
// HAZARDS THIS FILE EXISTS TO NOT REPEAT (the same wrong-kind-of-null family as
// R-05N / R-31 in the Analyze rules):
//   * Not on Wi-Fi is [TriageStatus.notOnWifi], a neutral state, never a fault.
//   * An iPhone without the Shortcut is [TriageStatus.notChecked], never a fake
//     Poor.
//   * "No cloud app answered" (R-40) and "some did not" (R-41) stay distinct.
//   * A network that wants a sign-in takes priority over every other rung.
//   * DNS has THREE answers (failed, pending, resolved); AnalyzeInput's single
//     nullable millisecond value cannot tell "failed" from "not landed yet".
//
// User-facing words: US spelling, no em dashes, hedged "Looks..." wording, the
// phrase "router/access point" never bare "AP". Status is always a WORD (and a
// glyph in the widget), never color alone.

import '../wifi_grading.dart';
import '../wifi_vs_internet.dart';
import 'analyze_input.dart';
import 'analyze_rules.dart' show kDnsSlowMs;
import 'package:net_quality/net_quality.dart' show QualityGrade;

/// How a rung reads. The word is always shown; the widget adds a glyph and hue.
enum TriageStatus {
  looksFine('Looks fine'),
  looksOff('Looks off'),
  notChecked('Not checked'),

  /// Neutral, not a fault: there was no Wi-Fi link to check (R-05N).
  notOnWifi('Not on Wi-Fi'),

  /// This platform cannot read the field (a wired desktop, for instance).
  cantCheck("Can't check on this device"),

  /// Transient: the answer has not landed yet. Shown on screen only.
  checking('Checking');

  const TriageStatus(this.word);

  final String word;
}

enum TriageRungId { wifiLink, dns, internet, services }

/// The DNS probe's four honest states.
enum TriageDnsState {
  /// The probe was never going to run on this build or test.
  absent,

  /// Running, no answer yet.
  pending,

  /// Ran and no host resolved.
  failed,

  /// A host resolved; the time is [TriageInput.dnsMs].
  resolved,
}

/// Everything the ladder reads, all of it already on the run.
class TriageInput {
  const TriageInput({
    this.verdict,
    this.rssiDbm,
    this.notOnWifi = false,
    this.platformIsIos = false,
    this.wifiSignalCaptured = true,
    this.dns = TriageDnsState.absent,
    this.dnsMs,
    this.evidence = const OnlineEvidence(),
    this.internetMeasured = false,
    this.internetHealth,
    this.speedTestSkipped = false,
    this.cloudPanelPresent = false,
    this.cloudReachableCount,
    this.cloudTotalCount,
  });

  /// Reads the run fields off the [AnalyzeInput] the Analyze rules already use, so
  /// the two cannot disagree. The four arguments are what [AnalyzeInput] cannot
  /// carry: the DNS probe's failed-vs-pending state, the online evidence, the
  /// engine's internet grade gate, and whether the cloud panel is part of the
  /// screen.
  factory TriageInput.fromAnalyzeInput(
    AnalyzeInput a, {
    required TriageDnsState dns,
    required OnlineEvidence evidence,
    required InternetHealth? internetHealth,
    required bool cloudPanelPresent,
  }) => TriageInput(
    verdict: a.verdict,
    rssiDbm: a.rssiDbm,
    notOnWifi: a.notOnWifi,
    platformIsIos: a.platformIsIos,
    wifiSignalCaptured: a.wifiSignalCaptured,
    dns: dns,
    dnsMs: a.dnsResolutionMs,
    evidence: evidence,
    internetMeasured: a.internetMeasured,
    internetHealth: a.internetMeasured ? internetHealth : null,
    speedTestSkipped: a.speedTestSkipped,
    cloudPanelPresent: cloudPanelPresent,
    cloudReachableCount: a.cloudReachableCount,
    cloudTotalCount: a.cloudTotalCount,
  );

  /// Null until a run has produced a verdict; the ladder is empty then.
  final WifiVsInternetVerdict? verdict;
  final int? rssiDbm;
  final bool notOnWifi;
  final bool platformIsIos;

  /// False on iOS until the companion Shortcut has captured the RF block.
  final bool wifiSignalCaptured;

  final TriageDnsState dns;
  final int? dnsMs;

  /// DNS resolved, public IP obtained, cloud reachable: the engine's own
  /// "you are online" evidence, independent of the throughput measurement.
  final OnlineEvidence evidence;

  /// Any of download, upload, latency, loss, jitter, responsiveness was read.
  final bool internetMeasured;

  /// The engine's grade gate; null when the internet was not measured.
  final InternetHealth? internetHealth;

  /// The speed test was not run because the user declined cellular data.
  final bool speedTestSkipped;

  /// Whether the cloud-apps panel is part of this result at all.
  final bool cloudPanelPresent;
  final int? cloudReachableCount;
  final int? cloudTotalCount;
}

class TriageRung {
  const TriageRung({
    required this.id,
    required this.name,
    required this.status,
    this.reason,
  });

  final TriageRungId id;
  final String name;
  final TriageStatus status;

  /// A short plain reason, shown in Analyze and the Copy payloads.
  final String? reason;
}

class TriageLadder {
  const TriageLadder._(this.rungs, this.summary);

  final List<TriageRung> rungs;

  /// A hedged sentence naming where the trouble looks like it sits, or null when
  /// nothing looks off.
  final String? summary;

  bool get isEmpty => rungs.isEmpty;

  /// A frozen copy for surfaces that do not update (Analyze, Copy): a rung still
  /// [TriageStatus.checking] becomes Not checked, so "Checking" never sits on a
  /// page that will not change.
  TriageLadder settled() => TriageLadder._(
    rungs
        .map(
          (TriageRung r) => r.status == TriageStatus.checking
              ? TriageRung(
                  id: r.id,
                  name: r.name,
                  status: TriageStatus.notChecked,
                  reason: 'No answer yet when this was captured.',
                )
              : r,
        )
        .toList(growable: false),
    summary,
  );

  static TriageLadder compute(TriageInput input) {
    final WifiVsInternetVerdict? verdict = input.verdict;
    if (verdict == null) return const TriageLadder._(<TriageRung>[], null);

    final List<TriageRung> rungs = <TriageRung>[
      _wifiLink(input, verdict),
      ?_dns(input),
      _internet(input, verdict),
      ?_services(input),
    ];
    return TriageLadder._(rungs, _summary(rungs, verdict));
  }
}

TriageRung _wifiLink(TriageInput i, WifiVsInternetVerdict verdict) {
  const String name = 'Wi-Fi link';
  TriageRung rung(TriageStatus s, String reason) => TriageRung(
    id: TriageRungId.wifiLink,
    name: name,
    status: s,
    reason: reason,
  );

  if (i.notOnWifi) {
    return rung(
      TriageStatus.notOnWifi,
      'This device is not on Wi-Fi, so there was no Wi-Fi link to check.',
    );
  }
  if (i.platformIsIos && !i.wifiSignalCaptured) {
    return rung(
      TriageStatus.notChecked,
      'The Wi-Fi signal is read with the companion Shortcut, which has not '
      'captured it yet.',
    );
  }
  if (verdict == WifiVsInternetVerdict.wifiLimiter) {
    return rung(TriageStatus.looksOff, 'The Wi-Fi link is the limit here.');
  }
  if (verdict == WifiVsInternetVerdict.bothContributing) {
    return rung(
      TriageStatus.looksOff,
      'The Wi-Fi link is part of the slowdown.',
    );
  }
  if (verdict == WifiVsInternetVerdict.wifiUnknown) {
    return rung(
      TriageStatus.cantCheck,
      'This device did not report a Wi-Fi link. It may be wired, or the '
      'platform does not expose it.',
    );
  }
  if (verdict != WifiVsInternetVerdict.upstream &&
      WifiGrading.gradeRssi(i.rssiDbm) == QualityGrade.poor) {
    return rung(TriageStatus.looksOff, 'The Wi-Fi signal is weak.');
  }
  return rung(TriageStatus.looksFine, 'The Wi-Fi link looks healthy.');
}

TriageRung? _dns(TriageInput i) {
  const String name = 'Name lookup (DNS)';
  TriageRung rung(TriageStatus s, String? reason) =>
      TriageRung(id: TriageRungId.dns, name: name, status: s, reason: reason);

  switch (i.dns) {
    case TriageDnsState.absent:
      return null;
    case TriageDnsState.pending:
      return rung(TriageStatus.checking, null);
    case TriageDnsState.failed:
      return rung(TriageStatus.looksOff, 'Website names did not resolve.');
    case TriageDnsState.resolved:
      final int? ms = i.dnsMs;
      if (ms != null && ms >= kDnsSlowMs) {
        return rung(
          TriageStatus.looksOff,
          'Names are resolving slowly ($ms ms).',
        );
      }
      return rung(
        TriageStatus.looksFine,
        ms == null ? 'Names resolved.' : 'Names resolved in $ms ms.',
      );
  }
}

TriageRung _internet(TriageInput i, WifiVsInternetVerdict verdict) {
  const String name = 'The internet';
  TriageRung rung(TriageStatus s, String reason) => TriageRung(
    id: TriageRungId.internet,
    name: name,
    status: s,
    reason: reason,
  );

  switch (verdict) {
    case WifiVsInternetVerdict.captivePortal:
      return rung(TriageStatus.looksOff, 'This network wants a sign-in.');
    case WifiVsInternetVerdict.internetUnreachable:
      return rung(TriageStatus.looksOff, 'The internet did not answer.');
    case WifiVsInternetVerdict.upstream:
    case WifiVsInternetVerdict.bothContributing:
      return rung(
        TriageStatus.looksOff,
        'The internet connection is slow past your router/access point.',
      );
    case WifiVsInternetVerdict.bothHealthy:
      return rung(TriageStatus.looksFine, 'Speed and response look healthy.');
    case WifiVsInternetVerdict.wifiLimiter:
    case WifiVsInternetVerdict.wifiUnknown:
    case WifiVsInternetVerdict.onlineUnmeasured:
      break;
  }

  // The throughput below is only a fair read of the internet when the Wi-Fi link
  // is not the thing limiting it, so reachability evidence (which does not
  // depend on throughput) is checked first.
  if (i.evidence.isOnline) {
    if (i.speedTestSkipped) {
      return rung(
        TriageStatus.looksFine,
        'Reachable. The speed test was skipped to save cellular data.',
      );
    }
    return rung(
      TriageStatus.looksFine,
      verdict == WifiVsInternetVerdict.wifiLimiter
          ? 'Sites answered, so the internet path is working.'
          : 'Reachable. The speed could not be measured.',
    );
  }
  if (verdict == WifiVsInternetVerdict.wifiUnknown &&
      i.internetMeasured &&
      i.internetHealth != null) {
    return i.internetHealth == InternetHealth.good
        ? rung(TriageStatus.looksFine, 'Speed and response look healthy.')
        : rung(
            TriageStatus.looksOff,
            'The internet measurements were below the Good range.',
          );
  }
  return rung(
    TriageStatus.notChecked,
    i.speedTestSkipped
        ? 'The speed test was skipped to save cellular data.'
        : verdict == WifiVsInternetVerdict.wifiLimiter
        ? 'The slow Wi-Fi link makes the internet speed hard to separate out.'
        : 'Not enough answered to say.',
  );
}

const String _noServicesAnswered = 'None of the test services answered.';

TriageRung? _services(TriageInput i) {
  const String name = 'Services';
  TriageRung rung(TriageStatus s, String? reason) => TriageRung(
    id: TriageRungId.services,
    name: name,
    status: s,
    reason: reason,
  );

  if (!i.cloudPanelPresent) return null;
  final int? reachable = i.cloudReachableCount;
  final int? total = i.cloudTotalCount;
  if (reachable == null || total == null) {
    return rung(TriageStatus.checking, null);
  }
  if (total == 0) return rung(TriageStatus.notChecked, null);
  if (reachable == 0) {
    return i.internetMeasured
        ? rung(TriageStatus.looksOff, _noServicesAnswered)
        : rung(
            TriageStatus.notChecked,
            'None of the test services answered, and nothing else was '
            'measured to compare.',
          );
  }
  if (reachable < total) {
    return rung(
      TriageStatus.looksOff,
      '$reachable of $total test services answered.',
    );
  }
  return rung(TriageStatus.looksFine, 'All $total test services answered.');
}

String? _summary(List<TriageRung> rungs, WifiVsInternetVerdict verdict) {
  if (verdict == WifiVsInternetVerdict.captivePortal) {
    return 'It looks like this network wants a sign-in.';
  }
  for (final TriageRung r in rungs) {
    if (r.status != TriageStatus.looksOff) continue;
    switch (r.id) {
      case TriageRungId.wifiLink:
        return 'It looks like the trouble sits at your Wi-Fi link.';
      case TriageRungId.dns:
        return 'It looks like the trouble sits at name lookup (DNS).';
      case TriageRungId.internet:
        return 'It looks like the trouble sits with the internet.';
      case TriageRungId.services:
        return r.reason == _noServicesAnswered
            ? 'It looks like none of the test services answered.'
            : 'It looks like only some services are unhappy, not the whole '
                  'internet.';
    }
  }
  return null;
}

/// The Copy-payload form: every rung as `Name: Status word`, its reason, then the
/// summary. Plain text, no markdown, so no state survives as color-only.
String triageLadderToPlainText(TriageLadder ladder) {
  if (ladder.isEmpty) return '';
  final StringBuffer buf = StringBuffer('Where it looks off\n');
  for (final TriageRung r in ladder.rungs) {
    buf.writeln('${r.name}: ${r.status.word}');
    if (r.reason != null) buf.writeln(r.reason);
  }
  if (ladder.summary != null) buf.writeln(ladder.summary);
  return buf.toString().trimRight();
}
