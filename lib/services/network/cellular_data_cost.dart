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
//    10 Mbps  ->  18.75 +  10  =   28.75 MB  -> stated as  29 MB
//   100 Mbps  -> 187.50 +  10  =  197.50 MB  -> stated as 198 MB
//   300 Mbps  -> 562.50 +  10  =  573 MB     -> stated as 573 MB
//
// Each figure is the derived value rounded UP to the whole megabyte, so all three
// stay at or above the true cost and the "keeps every figure below an UPPER bound"
// claim above actually holds.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY NOT "about 30 / 200 / 570" (round 5, 2026-07-14)
//
// It used to say exactly that, and TWO things were wrong with it:
//
//   1. THE HEDGE. "about 30 MB" is the shape of a number with no source
//      (voice-lint's `hedged quantity` rule FAILED this string). And the hedge was
//      only there to cover the ROUNDING — so it was a hedge on a figure we can
//      derive exactly. `cellular_data_cost_test.dart` even asserted "the warning
//      carries NO hedge words (it is a consent dialog)" and PASSED, because its
//      hedge list enumerated six words the string did not contain and OMITTED THE
//      ONE IT DID. A test named after banning the hedge was defending it.
//
//   2. "570" UNDERSTATED 572.5. Small (0.4%), and it erred in the one direction
//      that matters: it spent more of the user's money than the sentence promised,
//      on a screen whose entire job is to tell them what a tap will cost. The
//      header three lines up claimed the method "keeps every figure below an UPPER
//      bound" while the copy broke it.
//
// State the derived figures and BOTH defects vanish at once. 29 / 198 / 573 is
// simultaneously MORE PRECISE and MORE HONEST than "about 30 / 200 / 570", and it
// needs no hedge because it has a source: the two constants above.
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

import 'wifi_connection_service.dart' show MeteredRisk;

/// Megabytes transferred per Mbps of link rate, over one download window.
/// `maxDuration` (15 s) / 8 bits-per-byte = 1.875 MB per Mbps.
const double kMegabytesPerMbps = 1.875;

/// The hard upload cap, in megabytes (`ThroughputProbe.uploadBytes`).
const double kUploadMegabytes = 10;

/// The shared warning for a CONFIRMED cellular link. Shown before any byte is
/// spent, on every screen that can spend one.
///
/// It opens by ASSERTING the link ("You're on cellular"), so it may ONLY be shown
/// on [MeteredRisk.metered] — a MEASURED cellular transport, never an inference.
/// For an ambiguous link use [kUnknownLinkDataWarning], which asks the same
/// question without the false claim. [dataCostWarningFor] picks between them.
const String kCellularDataWarning =
    "You're on cellular. The speed test downloads at full speed for 15 seconds, "
    'then uploads 10 MB. The faster your connection, the more it uses: '
    '29 MB at 10 Mbps, 198 MB at 100 Mbps, 573 MB at 300 Mbps.';

/// The warning for a link we CANNOT IDENTIFY (round 5, 2026-07-14).
///
/// THE CONSENT PROMPT MUST NOT LIE ABOUT CERTAINTY, IN EITHER DIRECTION. The old
/// gate spent silently on an ambiguous link, defending itself with GL-005 ("an
/// ambiguous read is never proof of cellular"). That was true, and it was not a
/// reason to spend — it was a reason not to CLAIM. The fix is to ask WITHOUT
/// claiming, and a prompt that opened "You're on cellular" on a link we could not
/// read would be the identical error committed from the other side: asserting a
/// fact we do not have, to a user we are about to charge for it.
///
/// So this states exactly what is true — we cannot tell — and then states the cost
/// CONDITIONALLY, with the same derived figures and the same absence of hedging.
/// The uncertainty is in the LINK, which is honest, and never in the NUMBERS,
/// which are derived.
const String kUnknownLinkDataWarning =
    "We can't tell whether this device is on Wi-Fi or cellular. If it's cellular, "
    'the speed test costs real data: it downloads at full speed for 15 seconds, '
    'then uploads 10 MB. The faster your connection, the more it uses: '
    '29 MB at 10 Mbps, 198 MB at 100 Mbps, 573 MB at 300 Mbps.';

/// Network Quality appends this: on that screen the live latency/jitter/loss
/// sparklines keep running whether or not the speed test does, and they cost
/// almost nothing.
const String kCellularDataWarningCheapTail =
    ' Everything else on this screen is cheap.';

/// THE ONE PLACE THAT DECIDES WHICH TRUTH TO TELL.
///
/// Both screens read this rather than branching on the risk themselves, so neither
/// can accidentally assert "You're on cellular" to a user whose link we never
/// identified. Returns null on [MeteredRisk.none] — there is nothing to warn about,
/// and a warning shown to a Wi-Fi user is noise that trains them to ignore the one
/// that matters.
String? dataCostWarningFor(MeteredRisk risk) {
  switch (risk) {
    case MeteredRisk.metered:
      return kCellularDataWarning;
    case MeteredRisk.unknown:
      return kUnknownLinkDataWarning;
    case MeteredRisk.none:
      return null;
  }
}
