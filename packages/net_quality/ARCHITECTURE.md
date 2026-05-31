# net_quality architecture

Pure-Dart network-quality measurement for the WLAN Pros Toolbox. No Flutter, no
plugins. Everything here runs on all five Flutter target platforms because it
depends only on `dart:io` sockets and HTTP.

## The seam

There is exactly one contract between the toolbox UI and any measurement
backend:

```
QualityClient.measure() -> Stream<QualityProgress>, then QualityResult
```

`QualityResult` is a list of individually graded `QualityMetric` objects plus a
source and a timestamp. The UI depends only on `QualityClient`; it never
references a concrete probe. Two implementations ship:

- `MockQualityClient`: deterministic scripted data for tests and previews.
- `OwnEngineQualityClient`: the real engine, composed from the probes below.

### Why graded metrics, not a single score

We grade each dimension on its own (`QualityGrade.excellent/good/fair/poor`)
and deliberately do NOT roll them into one headline number. There is no Orb
measurement SDK, and a single composite "score" invites a trademark and
marketing comparison we cannot make honestly. When a dimension cannot be
measured on a given platform or run, it is reported as
`QualityGrade.unavailable`, shown honestly, never faked.

### What we deliberately omit

- A reliability pillar. Reliability needs continuous monitoring over time
  (sustained loss, dropouts, route changes). A one-shot test cannot provide it
  honestly, so we do not report it.
- A composite score, for the reasons above.

## The two halves of "network quality"

1. Transport engine (THIS package). Latency, jitter, loss, download, upload,
   and a simplified responsiveness/RPM. Pure Dart, works on all five platforms.

2. Wi-Fi radio metrics (an app-layer Flutter service, not in this package).
   RSSI, SNR, TX rate, MCS, channel width. These require platform channels into
   the OS Wi-Fi APIs and are platform-gated. iOS blocks most of them for
   third-party apps, so on iOS they surface as `QualityGrade.unavailable`. Their
   IDs are reserved here in `MetricIds` so both halves share one vocabulary, but
   this package never measures them.

## Why TCP-connect RTT, not ICMP ping

Latency and reachability use a timed TCP connect (SYN/SYN-ACK round trip) to a
real host on port 443, not ICMP echo. The macOS App Sandbox and iOS block raw
sockets for sandboxed apps, so ICMP ping is not available to us (see GL-008,
native app sandbox and network constraints). A TCP-connect RTT is a faithful,
sandbox-legal proxy for round-trip latency.

## Probes

All probes take injectable function-typedef seams, so the entire engine is
unit-testable with no real network.

| Probe                  | Measures                              | Default backend                         |
|------------------------|---------------------------------------|-----------------------------------------|
| `LatencyProbe`         | avg/min/max RTT, jitter, loss         | sequential `Socket.connect` timing      |
| `ThroughputProbe`      | download/upload Mbps                  | Cloudflare speed endpoints via HttpClient |
| `ReachabilityProbe`    | per-site reachable + RTT (concurrent) | `Socket.connect` timing per site        |
| `ResponsivenessProbe`  | loaded-latency RPM                    | injected sampler + load generator       |

- Jitter is RFC 3550-style mean deviation between consecutive successful
  samples.
- Responsiveness RPM is a SIMPLIFIED single-flow loaded-latency estimate
  inspired by RFC 9097 and Apple's networkQuality. It is NOT the full
  multi-flow RPM standard and is not presented as one.

## Scoring

`QualityScoring` maps measured values to `QualityGrade`. Each grader documents
whether its bands are standard-grounded or our own heuristic (GL-005):

- Latency: bands derived from ITU-T G.114.
- Jitter: bands informed by VoIP jitter-buffer guidance (~30 ms).
- Loss: bands informed by ITU/Cisco VoIP guidance (>1% degrades VoIP).
- Responsiveness: bands derived from RFC 9097 / Apple networkQuality.
- Download and upload: EXPLICITLY heuristics, not standards.

The exact cut points are always our own choice; where a standard exists it
grounds the direction and magnitude, not the precise numbers.
