# TICKET-011 — Ping Trend / Latency Chart

**Difficulty:** Moderate (UI/charting work, not new network capability)
**iOS blocker:** None. Uses ping data we already collect.
**Source:** `myPKA/Deliverables/2026-05-29-netscantools-pro-feature-map/brief.md` (NetScanTools Pro "PingTrend / Graphical Ping")

## What it is

Run a continuous ping against a host and chart latency over time: a live line graph
plus rolling min / avg / max / jitter / loss%. NetScanTools Pro ships a graphical
PingTrend; this turns the ping data we already produce into a visual.

## Value

Medium-high and demo-friendly. A latency-over-time chart is the single most legible
"is this link healthy" view, and it reuses our existing ping path rather than adding
a new capability.

## Acceptance criteria

- Continuous ping to a host at a user-set interval; live-updating line chart of RTT.
- Rolling stats panel: min, avg, max, jitter (mean deviation), loss %.
- Start / stop control; chart windows to a sensible recent span (e.g. last N samples)
  so it does not grow unbounded.
- Honest handling of timeouts/loss — a dropped sample shows as loss, not a gap that
  reads as zero latency.
- Reuses the existing ping engine; on iOS this is the **TCP-connect** ping path we
  already ship (raw-ICMP remains unavailable on iOS, per the traceroute constraint).

## Implementation outline

- **Service:** extend the existing ping service with a streaming/continuous mode that
  emits per-sample RTT + outcome (e.g. a `Stream<PingSample>`), plus a small stats
  accumulator. No new transport.
- **Screen:** `lib/screens/tools/network/ping_trend_screen.dart` — host field,
  interval control, start/stop, the chart, the stats panel.
- **Charting:** pick one maintained Flutter chart package (e.g. `fl_chart`) and pin it;
  confirm it builds clean on iOS before wiring. Keep the dependency surface minimal.
- **Catalog:** add `ToolEntry` (`id: 'ping-trend'`, `isLive: true`); route in
  `app_router.dart`.
- **Tests:** feed a synthetic `PingSample` stream into the stats accumulator; assert
  min/avg/max/jitter/loss math; assert the windowing cap.

## Dependencies

One Flutter charting package (to be selected + pinned). Reuses the existing ping
engine for data.

## Notes

This is the one item whose effort is mostly UI + a charting dependency, not protocol
work. Confirm the chart package is iOS-clean and accessibility-labeled (matches the
§8.3 a11y pass) before declaring done.
