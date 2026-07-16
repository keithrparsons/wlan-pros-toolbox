// Speed Test Services — curated reference dataset.
//
// Source of truth: Pax\'s verified research brief
// (myPKA Deliverables/2026-06-09-speedtest-services/RESEARCH-BRIEF.md). Keith
// approved all 12 services. Content ported verbatim-in-substance from that
// brief, condensed to the page\'s columns and held to GL-004 voice (US spelling,
// "Wi-Fi" never "WiFi", no em dashes, conclusion-first, no marketing words).
//
// Compile-time const data — no async load, no network, no parse. Works on every
// platform. The only runtime state is "success": the const lists always render
// (mirrors regulatory_domains_screen — no loading/empty/error path).
//
// HONESTY (load-bearing, GL-005 / the brief):
//  * The data-per-test figure is the weak column: almost no vendor publishes a
//    hard MB number. Every entry carries a [dataConfidence] flag and the figures
//    are phrased as community-measured ESTIMATES ("~", "approx", "adaptive"),
//    NEVER as settled facts. The screen surfaces a persistent caveat band that
//    says so up front, and the per-row data figure renders beside its confidence
//    marker.
//  * Orb is framed as CONTINUOUS MONITORING, not a one-shot test (its own
//    category flag), with the note that our shipped net_quality engine is our
//    OWN analog with deliberately NO composite score (trademark caution).
//  * Where a "test brand" is not its own measurement infrastructure (Waveform on
//    Cloudflare; most ISP tests on Ookla/M-Lab; Fast.com on Netflix\'s own CDN),
//    [backendNote] carries the editorial flag so readers do not treat all 12 as
//    independent.

import 'package:flutter/foundation.dart' show immutable;

/// How the service hits the network on the throughput axis: the brief\'s first
/// teaching axis (single-stream is more diagnostic; multi-stream inflates the
/// headline by filling the pipe like a browser).
enum StreamModel {
  /// One TCP connection — lower numbers, more diagnostic of a real path
  /// bottleneck (M-Lab NDT, SpeedOf.Me).
  single,

  /// Several connections in parallel — maximizes the headline (Ookla, Fast.com,
  /// Cloudflare, LibreSpeed).
  multi,

  /// Light, repeated samples rather than a saturating single run (Orb).
  sampled,
}

extension StreamModelLabel on StreamModel {
  /// Short label for the page and the copy payload.
  String get label {
    switch (this) {
      case StreamModel.single:
        return 'Single-stream';
      case StreamModel.multi:
        return 'Multi-stream';
      case StreamModel.sampled:
        return 'Sampled (light, repeated)';
    }
  }
}

/// The brief\'s second teaching axis: does the test hit a nearby, well-provisioned
/// CDN edge (inflates "gigabit" results) or a distant fixed server that exposes
/// the real path (reads lower, by design)?
enum ServerProximity {
  /// Nearby, well-provisioned CDN edge — Fast.com, Cloudflare, Waveform, ISP
  /// tests. Many "gigabit" results are this proximity, not a true path.
  cdnEdge,

  /// Distant or fixed research server — M-Lab NDT. Exposes the real path; reads
  /// lower than CDN-edge tests by design, not because it is wrong.
  distantServer,

  /// Picks a nearby server by default but lets you choose a distant one (Ookla,
  /// nPerf).
  selectable,

  /// Whatever you point it at — by default your own server, so it isolates YOUR
  /// network rather than CDN proximity (LibreSpeed, OpenSpeedTest, self-hosted).
  selfHosted,
}

extension ServerProximityLabel on ServerProximity {
  String get label {
    switch (this) {
      case ServerProximity.cdnEdge:
        return 'Nearby CDN edge';
      case ServerProximity.distantServer:
        return 'Distant / fixed server';
      case ServerProximity.selectable:
        return 'Nearest by default, selectable';
      case ServerProximity.selfHosted:
        return 'Your own server (self-host)';
    }
  }
}

/// Confidence marker for the data-per-test figure. The brief flags every MB
/// figure as community-measured, not vendor-published, so the page never states
/// these as facts.
enum DataConfidence {
  /// Architecturally certain (e.g. self-hosted LibreSpeed = your own bytes, no
  /// metered cost).
  high,

  /// Community-measured estimate or inferred from published mechanics — the
  /// common case. Phrased with "~" / "approx" on the page.
  estimate,

  /// Weakly inferred (e.g. from test duration, or a shared backend). Phrased as
  /// "rough estimate".
  low,
}

extension DataConfidenceMarker on DataConfidence {
  /// Short marker shown beside the data figure so the hedge is always visible.
  String get marker {
    switch (this) {
      case DataConfidence.high:
        return 'measured';
      case DataConfidence.estimate:
        return 'est.';
      case DataConfidence.low:
        return 'rough est.';
    }
  }
}

/// One speed-test (or, for Orb, monitoring) service entry.
@immutable
class SpeedtestService {
  const SpeedtestService({
    required this.slug,
    required this.name,
    required this.operator,
    required this.url,
    required this.what,
    required this.how,
    required this.streamModel,
    required this.proximity,
    required this.dataPerTest,
    required this.dataConfidence,
    required this.openSource,
    this.isMonitor = false,
    this.backendNote,
  });

  /// Stable kebab-case slug — keys the logo resolver
  /// (`assets/speedtest-logos/<slug>.svg|png`) and the row semantics.
  final String slug;

  /// Service name as the operator writes it (e.g. "Ookla Speedtest").
  final String name;

  /// Company / operator behind the service.
  final String operator;

  /// Canonical site URL, opened via url_launcher.
  final String url;

  /// What it measures, in one line (download / upload / latency / loaded
  /// latency / bufferbloat grade / etc.).
  final String what;

  /// How it measures — the mechanics that matter (stream count, server choice,
  /// adaptive duration, percentile reporting).
  final String how;

  /// Single vs multi-stream (or sampled) — the brief\'s first axis.
  final StreamModel streamModel;

  /// CDN-edge-next-door vs true-distant-server (or selectable / self-host) — the
  /// brief\'s second axis.
  final ServerProximity proximity;

  /// Data consumed per test, phrased as an estimate (the weak column).
  final String dataPerTest;

  /// Confidence flag for [dataPerTest] — always surfaced so the hedge is visible.
  final DataConfidence dataConfidence;

  /// Open-source / self-hostable note ("Yes — LGPLv3", "No (proprietary)").
  final String openSource;

  /// `true` for Orb only — it is continuous monitoring, not a one-shot test.
  /// The screen flags it with its own badge and an explicit framing note.
  final bool isMonitor;

  /// Editorial flag where a "test brand" is NOT its own measurement
  /// infrastructure (Waveform on Cloudflare, ISP tests on Ookla/M-Lab,
  /// Fast.com on Netflix\'s own production CDN). `null` when the service runs its
  /// own backend. Surfaced so readers do not treat all 12 as independent.
  final String? backendNote;
}

/// The 12 Keith-approved services, in the brief\'s order (9 core + 3 add-ons).
const List<SpeedtestService> kSpeedtestServices = <SpeedtestService>[
  SpeedtestService(
    slug: 'ookla',
    name: 'Ookla Speedtest',
    operator: 'Ookla, LLC (Ziff Davis)',
    url: 'https://www.speedtest.net',
    what: 'Download, upload, idle latency, jitter, packet loss; loaded latency '
        'in newer clients.',
    how: 'Multi-stream TCP, scaling up to 8 connections at higher round-trip '
        'time. Samples throughput across time slices and discards outliers. '
        'Picks a nearby server by default; distant servers selectable. The '
        'current slice math is not public.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.selectable,
    dataPerTest: '~200 MB at 100 Mbps; approaches ~1 GB on a gigabit link',
    dataConfidence: DataConfidence.estimate,
    openSource: 'No (proprietary; separate SDK and CLI sold)',
  ),
  SpeedtestService(
    slug: 'fast-com',
    name: 'Fast.com',
    operator: 'Netflix',
    url: 'https://fast.com',
    what: 'Download headline; upload plus unloaded and loaded latency under '
        '"Show more info".',
    how: 'Runs against Netflix Open Connect appliances, the same CDN that '
        'streams Netflix video. Opens several connections, varies the count by '
        'conditions, and ends the test adaptively once results are stable.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.cdnEdge,
    dataPerTest: 'Adaptive; depends on link speed and run length (no fixed '
        'figure)',
    dataConfidence: DataConfidence.estimate,
    openSource: 'No',
    backendNote: 'Runs on Netflix\'s own production CDN (Open Connect), the '
        'cleanest example of measuring the CDN next door. Netflix states it is '
        'not for enterprise or third-party certification.',
  ),
  SpeedtestService(
    slug: 'cloudflare',
    name: 'Cloudflare Speed Test',
    operator: 'Cloudflare',
    url: 'https://speed.cloudflare.com',
    what: 'Download, upload, idle and loaded latency, idle and loaded jitter, '
        'packet loss, plus AIM scores for streaming / gaming / video-chat.',
    how: 'Runs on Cloudflare Workers at the edge nearest you. Sends '
        'progressively larger payloads to mimic real loading rather than only '
        'saturating the pipe, and reports the 90th percentile, not peak. '
        'Interleaves empty requests to measure loaded latency.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.cdnEdge,
    dataPerTest: 'Up to ~200 MB (caps near there; varies with measured speed)',
    dataConfidence: DataConfidence.estimate,
    openSource: 'Client component open-source (cloudflare/speedtest); edge '
        'backend is Cloudflare\'s, not self-hostable',
  ),
  SpeedtestService(
    slug: 'mlab-ndt',
    name: 'M-Lab NDT (Google "speed test")',
    operator: 'Measurement Lab (M-Lab) consortium; surfaced by Google Search',
    url: 'https://speed.measurementlab.net',
    what: 'Download, upload, minimum round-trip latency, loss rate, plus '
        'fine-grained transport metrics.',
    how: 'Single-stream TCP over a WebSocket, about 10 seconds each direction; '
        'current ndt7 uses TCP BBR. Single stream is a deliberate choice to '
        'diagnose path problems, and it hits a fixed M-Lab research server, not '
        'a hyper-local edge, so numbers read lower by design.',
    streamModel: StreamModel.single,
    proximity: ServerProximity.distantServer,
    dataPerTest: 'Bounded by the ~10 s x 2 transfers; scales with link, shorter '
        'than saturating tests',
    dataConfidence: DataConfidence.low,
    openSource: 'Yes (Go server; JS / Swift / Kotlin / Java clients on GitHub)',
    backendNote: 'M-Lab is the measurement platform; Google merely surfaces it '
        'in search. Credit Measurement Lab (M-Lab), not Google, as the service.',
  ),
  SpeedtestService(
    slug: 'nperf',
    name: 'nPerf',
    operator: 'nPerf SAS (Lyon, France)',
    url: 'https://www.nperf.com',
    what: 'Download, upload, latency, plus a browsing test (web-page load) and '
        'a streaming test (360p / 720p / 1080p video buffering).',
    how: 'Proprietary algorithm against a worldwide dedicated server network '
        'sized to saturate the link; server auto- or manually selected. '
        'Distinctive for combining raw speed with browse and stream quality in '
        'one run. Methodology is largely vendor-stated.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.selectable,
    dataPerTest: 'Saturating run plus a 10 s video at three resolutions; more '
        'than a speed-only test (no published figure)',
    dataConfidence: DataConfidence.low,
    openSource: 'No',
  ),
  SpeedtestService(
    slug: 'waveform',
    name: 'Waveform Bufferbloat Test',
    operator: 'Waveform',
    url: 'https://www.waveform.com/tools/bufferbloat',
    what: 'Download, upload, and the headline bufferbloat grade (A+ to F) = '
        'latency increase under load, across unloaded / downlink-saturated / '
        'uplink-saturated stages.',
    how: 'Adds a bufferbloat grading layer on top of Cloudflare\'s test '
        'backend. Measures latency during the saturated phases and compares it '
        'to idle.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.cdnEdge,
    dataPerTest: 'Comparable to a Cloudflare run (~up to ~200 MB), scales with '
        'link',
    dataConfidence: DataConfidence.low,
    openSource: 'No (front-end tool; backend is Cloudflare\'s)',
    backendNote: 'Built on Cloudflare\'s test backend. Best example that '
        'the same bytes can be graded for latency-under-load, and that two '
        '"different" tests can share one backend.',
  ),
  SpeedtestService(
    slug: 'librespeed',
    name: 'LibreSpeed',
    operator: 'Open-source project',
    url: 'https://librespeed.org',
    what: 'Download, upload, ping (latency), jitter, packet loss; optional '
        'IP / ISP.',
    how: 'Lightweight vanilla JavaScript using XHR and Web Workers (no Flash, '
        'Java, or WebSocket). Multi-stream; the server generates garbage chunks '
        'on the fly and discards them.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.selfHosted,
    dataPerTest: 'No metered cost when self-hosted (your own client to your own '
        'server); scales with link over WAN',
    dataConfidence: DataConfidence.high,
    openSource: 'Yes, LGPLv3 (PHP, Go, Rust, Node backends; Docker images), '
        'the standout self-hostable option',
  ),
  SpeedtestService(
    slug: 'speedof-me',
    name: 'SpeedOf.Me',
    operator: 'SpeedOf.Me, LLC',
    url: 'https://speedof.me',
    what: 'Download, upload, latency, jitter.',
    how: 'Pure HTML5 / JavaScript. Single connection. Downloads progressively '
        'larger samples (128 KB up to 128 MB) and accepts the last sample that '
        'took over 8 seconds. Positioned as closer to real single-file browsing '
        'than multi-thread tests.',
    streamModel: StreamModel.single,
    proximity: ServerProximity.distantServer,
    dataPerTest: 'Bounded by the sample ladder; up to ~128 MB on a fast link, '
        'far less on a slow one',
    dataConfidence: DataConfidence.estimate,
    openSource: 'No',
  ),
  SpeedtestService(
    slug: 'orb',
    name: 'Orb',
    operator: 'Orb (from the original creators of Speedtest and Downdetector)',
    url: 'https://orb.net',
    isMonitor: true,
    what: 'Continuous monitoring, not a one-shot test. An Orb Score (0 to 100) '
        'built from Responsiveness, Reliability, and Speed.',
    how: 'A lightweight always-on agent on hardware you own. Responsiveness is '
        'sampled twice per second; reliability tracks drops, recovery, and '
        'outage duration; speed uses a small ~10 MB file on a cadence (default '
        'hourly). It answers "how is my connection over time", catching '
        'dropouts a one-shot test misses.',
    streamModel: StreamModel.sampled,
    proximity: ServerProximity.distantServer,
    dataPerTest: 'Speed sampling is light (~10 MB file) but runs repeatedly; '
        'cumulative-per-day is the relevant figure, not per-test',
    dataConfidence: DataConfidence.estimate,
    openSource: 'Agent free-tier installable (Pi / Docker); Cloud API paid; not '
        'open-source',
  ),
  SpeedtestService(
    slug: 'openspeedtest',
    name: 'OpenSpeedTest',
    operator: 'Open-source project',
    url: 'https://openspeedtest.com',
    what: 'Download, upload, ping, jitter.',
    how: 'Open-source HTML5 test that needs no server-side language; runs in '
        'the browser with a Node or Docker server. A direct LibreSpeed '
        'alternative and a second self-host option for testing a LAN.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.selfHosted,
    dataPerTest: 'No metered cost when self-hosted; scales with link over WAN',
    dataConfidence: DataConfidence.high,
    openSource: 'Yes (browser plus Node / Docker; no server-side language)',
  ),
  SpeedtestService(
    slug: 'speedtest-cli-iperf3',
    name: 'Speedtest CLI / iperf3',
    operator: 'Ookla (CLI) / open-source (iperf3)',
    url: 'https://iperf.fr',
    what: 'Command-line throughput. iperf3 measures true point-to-point '
        'throughput with no CDN in the path at all.',
    how: 'Not a website. Professionals run Ookla\'s CLI for scripted '
        'speedtests and iperf3 for point-to-point throughput between two hosts '
        'you control, which removes server choice and CDN proximity from the '
        'result entirely.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.selfHosted,
    dataPerTest: 'You set it (duration / parallel streams); iperf3 traffic is '
        'between your own two hosts',
    dataConfidence: DataConfidence.high,
    openSource: 'iperf3 is open-source (BSD); Ookla CLI is proprietary',
  ),
  SpeedtestService(
    slug: 'isp-branded',
    name: 'ISP-branded tests (Xfinity, AT&T, Google Fiber)',
    operator: 'Individual ISPs',
    url: 'https://speedtest.net',
    what: 'Download, upload, latency on the ISP\'s own test page.',
    how: 'Most are a skinned Ookla or M-Lab / SamKnows backend. An ISP\'s '
        'own test measures to the ISP\'s own well-placed server, the '
        'friendliest possible path, so treat the result with that bias in mind.',
    streamModel: StreamModel.multi,
    proximity: ServerProximity.cdnEdge,
    dataPerTest: 'Inherits the underlying backend\'s cost (often Ookla, so '
        'scales with link)',
    dataConfidence: DataConfidence.low,
    openSource: 'No (the visible page; the backend is usually a third party)',
    backendNote: 'Usually skinned Ookla or M-Lab / SamKnows, not the ISP\'s '
        'own measurement infrastructure. The test points at the ISP\'s own '
        'server, the friendliest path.',
  ),
];

/// Hero line for the page (the brief\'s suggested hero, GL-004 voice).
const String kSpeedtestHeroLine =
    'A speed test measures the path to one server, right now, not your '
    'Wi-Fi. A bad result can be the server, the time of day, the wired uplink, '
    'or the test\'s own server choice.';

/// The persistent honesty caveat for the data-per-test column and the teaching
/// layer. Surfaced as a warning band so the hedge travels with the page and the
/// copy payload.
const String kSpeedtestDataCaveat =
    'Data-per-test figures are community-measured estimates, not vendor-'
    'published numbers. Almost no vendor publishes a hard MB figure, so read '
    'every value here as approximate, and note that saturating tests scale with '
    'your link, a gigabit Ookla run can burn close to 1 GB. On metered '
    'cellular, prefer adaptive or bounded tests, or a self-hosted test on your '
    'own LAN.';

/// The Orb framing note (load-bearing, GL-005): Orb is a monitor, and our own
/// net_quality engine is the in-app analog with deliberately NO composite score.
const String kSpeedtestOrbNote =
    'Orb is continuous monitoring, not a one-shot test. Our app does not run '
    'Orb measurements (there is no third-party way to trigger an Orb test). Our '
    'own net_quality engine and Network Quality tool are the in-app analog: '
    'per-dimension grades for latency, jitter, loss, download, upload, and '
    'responsiveness, with deliberately no composite score, our own '
    'measurements, not a third-party score.';

/// The independence caveat (load-bearing): several "different" tests share a
/// backend, so they are not independent measurements.
const String kSpeedtestBackendNote =
    'Not all of these are independent measurements. Waveform runs on '
    'Cloudflare\'s backend, most ISP tests are skinned Ookla or M-Lab, and '
    'Fast.com uses Netflix\'s own production CDN. Where that is true, the '
    'service shows a "runs on" note so two "different" tests are not read as two '
    'independent results.';

/// The three teaching callouts (brief\'s suggested cards).
const List<({String title, String body})> kSpeedtestCallouts =
    <({String title, String body})>[
  (
    title: 'The CDN next door vs. the real internet',
    body: 'Many "gigabit" results are proximity to a well-provisioned CDN edge. '
        'Fast.com, Cloudflare, Waveform, and ISP tests all hit a nearby edge. '
        'M-Lab NDT and a distant Ookla server expose the real path and read '
        'lower, by design, not because they are wrong.',
  ),
  (
    title: 'Why bufferbloat beats peak speed',
    body: 'Latency under load predicts felt quality, not peak download. A line '
        'that benchmarks at 900 Mbps but jumps to 300 ms under load feels worse '
        'on a video call than a 100 Mbps line that holds 20 ms. Cloudflare AIM, '
        'the Waveform grade, and Orb Responsiveness all target this.',
  ),
  (
    title: 'Single-stream vs. multi-stream',
    body: 'Multi-stream inflates the headline by filling the pipe like a '
        'browser. Single-stream reads lower and is more diagnostic of a real '
        'path bottleneck. Same connection, different number, both honest.',
  ),
];
