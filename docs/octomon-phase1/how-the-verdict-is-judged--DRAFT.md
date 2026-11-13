# How the verdict is judged (DRAFT)

Draft for Keith's review, from octomon review recommendation 6(b). Not published. Every number below is pinned to the code that applies it; the pins are for the reviewer and come out before publishing.

---

## The question Check My Connection answers

Is the slowdown your Wi-Fi, or the internet behind it? Check My Connection measures both sides in one run and compares them. It gives you one verdict, the numbers behind it, and what to try first.

There is no single score. Each measurement is graded on its own, and the verdict comes from comparing the two sides.

## Step 1: What gets measured

**Your Wi-Fi link.** The data rate your device and the access point agreed on, in Mbps, in both directions where the system reports both. Signal strength (RSSI) and signal-to-noise ratio (SNR) are shown too, but they only explain why the rate is what it is. The rate decides the verdict.

**Your internet.** Download, upload, latency, jitter, loss and responsiveness, measured against public test servers.

**Three quick reachability checks.** Did a name resolve in DNS? Did we get a public IP address? Did at least one well-known service answer? These run alongside the speed test, so they still count when the speed test itself stalls.

## Step 2: How much of your Wi-Fi rate you can use

Real throughput over Wi-Fi runs about half to 60% of the link rate, because of protocol overhead and sharing the air. The app uses 55% of the link rate as your usable Wi-Fi capacity.

Pin: `kUsableWifiFactor = 0.55`, `lib/services/network/wifi_vs_internet.dart:47`.

## Step 3: Is the internet good?

The internet counts as good only when download, upload, latency and loss **all** grade good or excellent. If any one of them misses, or could not be measured, it does not count as good.

| Measurement | Excellent | Good | Fair | Poor |
|---|---|---|---|---|
| Download | 100 Mbps or more | 25 or more | 5 or more | under 5 |
| Upload | 20 Mbps or more | 5 or more | 1 or more | under 1 |
| Latency | under 20 ms | under 50 | under 100 | 100 or more |
| Loss | 0% | under 1% | under 2.5% | 2.5% or more |

These bands are the app's own choices. The speed bands are round numbers that match common broadband plans and household needs; they are not a standard. The latency band leans on ITU-T G.114 voice guidance, and the loss band on ITU and Cisco guidance that loss above about 1% hurts voice calls.

Pins: `packages/net_quality/lib/src/scoring.dart:14-48` (latency, loss), `:105-114` (`ThroughputBands`); the all-four gate is `ConnectionCheck.internetHealth`, `lib/services/network/connection_check.dart:71-85`.

**If the internet is good, the verdict is "Both look fine"**, no matter how the Wi-Fi rate compares. A fast link in front of a fast internet is never called a fault. If something still feels slow, the likely cause is the app or website you are using.

## Step 4: If the internet is not good, which side is the ceiling?

The app divides your internet download speed by your usable Wi-Fi capacity.

| Ratio | Verdict | What it means |
|---|---|---|
| 0.70 or more | Looks like your Wi-Fi | Your internet is close to what your Wi-Fi can carry. The Wi-Fi link is the limit. |
| 0.40 to 0.70 | Mostly your Wi-Fi | Both sides are a little slow. The Wi-Fi fixes come first because they are easy and free. |
| under 0.40 | Looks like your Internet | Your Wi-Fi has plenty of room left over. The slow part is upstream. |

Example: your link rate is 400 Mbps, so usable Wi-Fi is about 220 Mbps. The internet measured 30 Mbps down with 3% loss, so it is not good. 30 divided by 220 is 0.136, well under 0.40: "Looks like your Internet."

Pins: `kWifiLimiterRatio = 0.70`, `kUpstreamRatio = 0.40`, `lib/services/network/wifi_vs_internet.dart:50-53`; headlines in `lib/services/network/consumer_verdict.dart:469-510`.

## When the app cannot measure everything

The app says what it could not measure instead of guessing.

- **Sign in to this network.** Names resolve and services answer, but no public IP address came back. Something is holding you short of the internet, and on a hotel, airport or conference network that is usually a sign-in page. This one is an inference from that pattern, which is why the wording says a sign-in page "should" appear.
- **No internet.** All three reachability checks answered, and all three said no. Your Wi-Fi link is working; the internet behind it is not reachable.
- **You are online.** The speed test stalled, but all three reachability checks said yes. You are online; the speed just could not be measured this time.
- **Couldn't check everything.** The Wi-Fi link rate could not be read (a wired computer, or an iPhone without the companion Shortcut). You get the internet result with that caveat.
- **Not on Wi-Fi.** The device was on cellular or a wired connection, so there was no Wi-Fi link to judge.

Pins: `OnlineEvidence.isOnline`, `isOffline`, `isCaptivePortal`, `lib/services/network/wifi_vs_internet.dart:194-227`; verdict order `:476-575`.

## What the verdict does not cover

- **It is one moment.** A single run cannot tell you about drops that come and go. Run it again when the problem is happening.
- **It does not judge the access point's coverage.** It judges the one link your device has right now, where you are standing.
- **It does not test for calls or video quality.** Loss and latency are shown, but there is no call-quality score.
