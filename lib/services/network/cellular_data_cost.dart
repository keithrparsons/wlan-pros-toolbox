// THE CELLULAR DATA-COST SENTENCE — ONE HOME, DERIVED, NOT REMEMBERED.
//
// Test My Connection and Network Quality both warn before spending the user's
// cellular data, and they must tell the same truth in the same words. This file
// is that single home (SSOT). Both screens import it; neither restates it.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THE OLD SENTENCE HAD TO GO (Keith, 2026-07-14)
//
// It read: "The speed test downloads at full speed for about 30 seconds, so it
// uses roughly 50 MB on a slow connection and 500 MB or more on fast 5G."
//
// Two separate defects, and the second is the serious one:
//
//   1. STALE. The "about 30 seconds" was exactly TWO 15 s download windows — the
//      throughput stage plus the RPM stage's load generator. The RPM stage no
//      longer runs on cellular, so the app now downloads for about HALF that.
//      The sentence described an app that no longer exists.
//
//   2. HEDGED. "roughly ... or more" is what you write when you do not have a
//      source. On a CONSENT dialog that is not a style nit: the user is being
//      asked to approve a spend, and a fuzzy number cannot be checked, cannot be
//      falsified, and quietly shifts the risk onto them. The figures below are
//      each DERIVED from the named constants, so any of them can be recomputed
//      by hand — and [CellularDataCostGuard] in the tests recomputes them from
//      the LIVE ThroughputProbe defaults, so if a constant moves, the build
//      fails instead of the sentence silently going stale again.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE DERIVATION. Every input is a named constant in
// `packages/net_quality/lib/src/probes/throughput_probe.dart`:
//
//   ThroughputProbe.maxDuration        = 15 s   (the download window)
//   ThroughputProbe.downloadStreamCount = 5     (concurrent, so the link fills)
//   ThroughputProbe.uploadBytes        = 10 * 1000 * 1000 = 10 MB  (a HARD cap)
//
// A cellular run is now DOWNLOAD + UPLOAD. There is no third stage.
//
//   Download: NOT byte-bounded. Five concurrent streams re-request back-to-back
//   until the window closes, so the stage transfers whatever the link can carry
//   in `maxDuration`:
//
//       bytes = rate(bits/s) x 15 s / 8
//             = rate(Mbps) x 1.875 MB per Mbps
//
//   Upload:   byte-bounded at `uploadBytes` = 10 MB (the window can only make it
//   LESS, never more — so 10 MB is a ceiling, and using it keeps every figure
//   below an UPPER bound).
//
//   total(Mbps) = 1.875 x Mbps + 10   MB
//
// Evaluated at three anchors spanning a realistic cellular range:
//
//    10 Mbps  ->  18.75 +  10  =   28.75 MB  -> stated as  30 MB
//   100 Mbps  -> 187.50 +  10  =  197.50 MB  -> stated as 200 MB
//   300 Mbps  -> 562.50 +  10  =  572.50 MB  -> stated as 570 MB
//
// The only rounding is to two significant figures. No hedge, no invented range.
//
// WHAT IS DELIBERATELY *NOT* CLAIMED: `throughputRetries` (= 1) lets a STALLED
// window be retried once. A stalled window is by definition one that moved
// almost no data, so a retry does not double the bytes — but it is why the copy
// says what the test DOES rather than promising a hard ceiling the code does not
// enforce.
//
// AND THE THING THAT DID NOT CHANGE: THE CONSENT TAP STAYS. Less cost is not no
// cost. Download and upload still spend real money. The warning, the decline
// path, and the awaited `spendData` chokepoint are all exactly as they were.
// Only the NUMBER changed — smaller, and true.

/// Megabytes transferred per Mbps of link rate, over one download window.
/// `maxDuration` (15 s) / 8 bits-per-byte = 1.875 MB per Mbps.
const double kMegabytesPerMbps = 1.875;

/// The hard upload cap, in megabytes (`ThroughputProbe.uploadBytes`).
const double kUploadMegabytes = 10;

/// The shared cellular-data warning. Shown before any byte is spent, on every
/// screen that can spend one.
const String kCellularDataWarning =
    "You're on cellular. The speed test downloads at full speed for 15 seconds, "
    'then uploads 10 MB. The faster your connection, the more it uses: about '
    '30 MB at 10 Mbps, 200 MB at 100 Mbps, 570 MB at 300 Mbps.';

/// Network Quality appends this: on that screen the live latency/jitter/loss
/// sparklines keep running whether or not the speed test does, and they cost
/// almost nothing.
const String kCellularDataWarningCheapTail =
    ' Everything else on this screen is cheap.';
