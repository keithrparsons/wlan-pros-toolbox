// WifiConnectionService — the honest "is this device on Wi-Fi?" probe.
//
// WHY THIS EXISTS (2026-06-25, Keith): a user spent hours debugging "no live
// data" in Wi-Fi Information / Test My Connection when the real cause was simply
// that the iPhone was on CELLULAR, not Wi-Fi. The live surfaces showed nothing
// (or a perpetual "Waiting for the first reading…") and gave no hint. Every
// tester on cellular, or stuck on a half-joined captive portal, hits the same
// wall. This service surfaces a clear, honest "you're not connected to Wi-Fi"
// state so the live tools stop looking broken when the device is off Wi-Fi.
//
// ============================================================================
// ROUND 4 (2026-07-13): ASK iOS THE QUESTION. STOP INFERRING IT FROM ADDRESSES.
// ============================================================================
//
// For three rounds this service answered "is the device on Wi-Fi?" by asking
// `network_info_plus` for an IP ADDRESS and inferring the link from whether one
// came back. That was the wrong question, and EVERY bug in rounds 2 and 3 was a
// consequence of asking it:
//
//   * The plugin's interface filter is `strncmp(name, "en", 2)`. It is not
//     Wi-Fi-specific — it matches ANY `en*` interface, including the `en*` a
//     USB-tethered iPhone brings up — and it returns the FIRST match.
//   * `getWifiIPv6()` therefore hands back the interface's LINK-LOCAL `fe80::`,
//     so round 2's "routable IPv6" check was dead code and declared a phone on an
//     IPv6-only SSID to be off Wi-Fi WHILE ON WI-FI.
//   * Round 3 fixed that by widening the ambiguity, which left three known holes
//     open: IPv6-only SSID, USB tether, and Personal Hotspot.
//
// iOS answers the actual question directly, and has since iOS 12. `NWPathMonitor`
// reports the interface TYPES a network path runs over, and `nw_interface_type_wifi`
// is a DISTINCT type from `nw_interface_type_cellular` and `nw_interface_type_wired`
// (pinned in the SDK: Network.framework/Headers/interface.h:47-52 — "A Wi-Fi
// link"). It requires no entitlement and no Location grant. A USB `en*` is
// `.wiredEthernet`, not `.wifi`, so it cannot be mistaken for a Wi-Fi link. An
// IPv6-only SSID is still a Wi-Fi path, so it reads as Wi-Fi.
//
// So the NATIVE PATH IS NOW THE PRIMARY SIGNAL. The address probe is kept ONLY as
// the FALLBACK for where the native answer is unavailable (every non-iOS platform,
// and an iOS read that times out or fails). The fail-safe `unknown` architecture
// is UNCHANGED and still governs both paths.
//
// WHAT WAS MEASURED, AND WHAT WAS NOT (the last three rounds each shipped a
// comment asserting a property nobody had demonstrated, and each one became the
// finding — so this block is explicit about the line between the two):
//
//   MEASURED (2026-07-13, a live NWPathMonitor run against the real Network
//   framework on macOS 15; the same framework and the same C API iOS uses):
//     * On an ASSOCIATED Wi-Fi link — default path `status = satisfied`,
//       `usesInterfaceType(.wifi) = true`, `availableInterfaces = [en0:wifi]`.
//       This held while `networksetup` simultaneously reported "You are not
//       associated with an AirPort network" (the Location-gated SSID read coming
//       back empty). The path monitor is definitive exactly where the SSID read is
//       blind — which is the whole point.
//     * For an interface that CANNOT CARRY A PATH (`requiredInterfaceType:
//       .wiredEthernet` on a machine with no wired NIC) — `status = unsatisfied`,
//       `usesInterfaceType = false`, `availableInterfaces = []`. That is the shape
//       an iPhone's Wi-Fi path takes with the radio off, and the ONLY shape this
//       service reads as `notOnWifi`.
//
//   NOT MEASURED — no iPhone was in this loop. The behavior on a real device, on a
//   powered-but-unassociated Wi-Fi radio, and while hosting a Personal Hotspot is
//   REASONED, not demonstrated. That is why every ambiguous shape below resolves
//   to `unknown`: an unmeasured shape degrades to the caller's PRIOR behavior (a
//   possible stale reading), never to a false "you have no Wi-Fi". See KNOWN
//   LIMITS.
//
// THE DECISION TABLE (primary — the native path, every platform that answers):
//
//   | Native facts                                          | Verdict     |
//   |-------------------------------------------------------|-------------|
//   | default route runs over Wi-Fi (`usesWifi`)             | `onWifi`    |
//   | a Wi-Fi-required path is satisfied (`wifiSatisfied`)   | `onWifi`    |
//   | no Wi-Fi interface, no Wi-Fi route                     | ↓ ADDRESSES |
//   | a Wi-Fi interface is present but carries no route      | ↓ ADDRESSES |
//   | the platform did not answer (null)                     | ↓ ADDRESSES |
//
// THE NATIVE PATH NEVER ASSERTS A NEGATIVE (round-4 cold review F-4, 2026-07-14).
// It keeps only the two answers it can PROVE — both POSITIVE — and hands every
// other shape to the address probe. The `no Wi-Fi interface` row used to return
// `notOnWifi` outright, and was the ONLY definitive negative in the codebase drawn
// from a signal no iPhone has ever run. It is now a fall-through like the rest.
// Radio-off is still detected (the address probe resolves it: no IPv4 AND no IPv6
// ⇒ `notOnWifi`); the only capability given up is USB-tether discrimination. See
// the long note at the branch itself for why that trade is not close.
//
// THE AMBIGUOUS ROW IS THE ONE THAT MATTERS, AND IT COST A REGRESSION. The first
// cut of round 4 answered it `unknown` and stopped. `unknown` means "keep the
// caller's prior behavior", and the prior behavior is the STALE App Group reading —
// so on a radio that is ON but UNASSOCIATED (the ordinary state of an iPhone on
// cellular with Wi-Fi left switched on) the screen went straight back to
// "It's your Wi-Fi" / "KeithHome" / "29 Mbps". The original bug, reproduced by the
// code written to delete it, because the address probe sits BELOW this block and the
// native monitor always answers. It now FALLS THROUGH instead. See the long note at
// the branch itself.
//
// ============================================================================
// ROUND 4b (2026-07-14): ANDROID. ASK ConnectivityManager. IT KNOWS.
// ============================================================================
//
// Everything above is about iOS. For four rounds this service could not return
// `notOnWifi` OFF iOS AT ALL — the `_platform != TargetPlatform.iOS => unknown`
// guard in the address probe made the negative STRUCTURALLY UNREACHABLE. Both
// consent gates (`net_quality_screen`, `test_my_connection_screen`) read
// `status == notOnWifi` EXACTLY, so on ANDROID — LIVE on Google Play, the platform
// where "on cellular" is the DEFAULT assumption — the gate did not exist. The home
// hero's `autoStart: true` push meant OPENING THE APP on a cellular Android phone
// auto-ran a full-rate ~30 s download plus the RPM load generator, 50 to 500 MB,
// with zero taps, no warning, and nothing to consent to.
//
// A GREEN SUITE SAID OTHERWISE. Every consent test drove `TargetPlatform.iOS`; not
// one drove Android. 4,238 tests passed over a live zero-tap data leak, and one
// test — "an AMBIGUOUS probe must NOT nag" — was actively ASSERTING that the app
// spends the data on exactly the probe shape Android always produces. Read the test
// NAMES before you trust them ([[feedback_tests_that_enshrine_the_bug]]).
//
// THE FIX IS NOT A WIDER INFERENCE. IT IS A MEASUREMENT WE NEVER TOOK.
// `ConnectivityManager.getNetworkCapabilities(activeNetwork).hasTransport(...)`
// reports `TRANSPORT_CELLULAR` / `_WIFI` / `_ETHERNET` definitively, needs only the
// `normal` (install-time, never-prompting) `ACCESS_NETWORK_STATE` permission this
// app already declares, and is NOT Location-gated. See [NetworkTransportProbe] and
// the decision table at the Android block in [status].
//
// THE ASYMMETRY IS DELIBERATE AND IT IS NOT TIMIDITY:
//   * iOS      — negative via the ADDRESS probe (an inference, sound because an
//                iPhone has no wired NIC).
//   * Android  — negative via the TRANSPORT probe (a MEASUREMENT).
//   * macOS /  — NO NEGATIVE, EVER. Not an oversight. A desktop with no Wi-Fi IPv4
//     Windows    is usually a WIRED desktop, and "never nag a wired desktop"
//                genuinely applies there. A laptop on a phone's hotspot ALSO reads
//                as Wi-Fi (a known, documented limitation — the hotspot IS a Wi-Fi
//                link from the laptop's point of view), so the one shape a desktop
//                gate would want to catch is the one shape it cannot. They are out
//                of scope, and they stay `unknown`.
//
// THE DECISION TABLE (fallback — the address probe; iOS-only for the negative):
//
//   | Device state              | IPv4    | IPv6 on en*   | Verdict      |
//   |---------------------------|---------|---------------|--------------|
//   | Normal Wi-Fi              | present | any           | `onWifi`     |
//   | Cellular only / Wi-Fi off | null    | NONE          | `notOnWifi`  |
//   | IPv6-only Wi-Fi, joined   | null    | any (fe80/GUA)| `unknown`    |
//
//   THREE HONEST STATES — never fake a value:
//     * onWifi    — a positive association signal: the native path runs over Wi-Fi,
//                   a caller-supplied native SSID, or a Wi-Fi IPv4 address.
//     * notOnWifi — (iOS only, address probe) the Wi-Fi interface carries NO
//                   ADDRESS OF EITHER FAMILY. This is now the ONLY route to a
//                   negative verdict anywhere in this service: the native path no
//                   longer asserts one (F-4).
//     * unknown   — the state could not be determined: a read threw, the platform
//                   cannot answer, or the evidence is AMBIGUOUS. The caller treats
//                   `unknown` as "carry on as before", NEVER as "not on Wi-Fi".
//
//   GL-005: a null/ambiguous read resolves to [unknown], never to [notOnWifi].
//
// KNOWN LIMITS (stated, not hidden):
//
//   * NO iPHONE WAS IN THIS LOOP. The native path logic is compiled and its API
//     semantics were measured on the same framework on macOS, but it has NOT been
//     executed on an iOS device. The three shapes it is expected to fix — IPv6-only
//     SSID, USB tether, Personal Hotspot — are REASONED from the SDK's interface-type
//     contract, not observed on a phone. Treat them as fixed only after a device run.
//   * A POWERED-BUT-UNASSOCIATED Wi-Fi radio was NOT measured, and it is the shape
//     that broke the first cut of this round. It is handled by NOT DECIDING IT
//     NATIVELY AT ALL: whatever iOS reports for it, an interface with no usable
//     route falls through to the address probe, which resolves it correctly
//     (no IPv4, no IPv6 → `notOnWifi`) exactly as it did before the native path
//     existed. The fix therefore does not depend on a measurement nobody has taken.
//   * HOSTING A PERSONAL HOTSPOT may present a satisfied Wi-Fi path (the phone's own
//     AP interface). If it does, this reads `onWifi`; if it does not, it falls
//     through and the hotspot interface's 172.20.10.1 also reads `onWifi`. Either
//     way it matches the pre-existing behavior, so it is not a regression — but it
//     is not a proven fix either, and it is not claimed as one.
//   * ON AN IPv6-ONLY SSID the address probe alone returns `unknown`, not `onWifi`.
//     That limit is now MOOT on iOS (the native path catches the association before
//     the fallback is reached) but still holds on any platform where the native path
//     is unavailable.
//   * NO ANDROID PHONE WAS IN THIS LOOP EITHER. The transport block is compiled and
//     unit-tested against the four capability bits, but it has NOT been executed on
//     a physical Android device. The API contract it rests on
//     (`NetworkCapabilities.TRANSPORT_CELLULAR` on the ACTIVE network) is far
//     narrower and far better specified than the NWPathMonitor reasoning above —
//     it is a single documented boolean, not an inference from interface lists —
//     but it is READ, not RUN. Say so; do not claim a device run nobody took.
//   * A VPN ON ANDROID CAN HIDE THE TRANSPORT. Android normally merges the
//     underlying network's transports into the VPN network's capabilities, so a VPN
//     over cellular usually still reports `cellular: true`. When a VPN app does not
//     call `setUnderlyingNetworks`, the active network reports ONLY `TRANSPORT_VPN`
//     and the transport block cannot decide the WI-FI question — so it stays
//     `unknown`, which is the honest answer (asserting "cellular" from a bare VPN
//     transport would nag every VPN-on-Wi-Fi user with a false claim).
//
//     THIS NO LONGER SPENDS. Until round 5 the sentence above ended "...which
//     SPENDS THE DATA without a warning... This is the ONE residual cellular-spend
//     path on Android and it is stated, not hidden." STATING A LEAK IS NOT CLOSING
//     IT, and Vera walked straight through it. The Wi-Fi answer is unchanged and
//     still `unknown`; the MONEY answer is now [MeteredRisk.unknown], which ASKS.
//     We never had to claim the user was on cellular in order to ask them.
//   * ANDROID + BOTH TRANSPORTS is ambiguous for the Wi-Fi question in the same way
//     and ALSO no longer spends. If the OS reports Wi-Fi AND cellular on one active
//     network we cannot know which link pays, so we assert neither and ASK.
//   * WIRED ANDROID (`TRANSPORT_ETHERNET`) IS AMBIGUOUS FOR THE WI-FI QUESTION AND
//     PROVEN SAFE FOR THE MONEY QUESTION. It stays `unknown` on the Wi-Fi axis (it
//     genuinely is not on Wi-Fi) and [MeteredRisk.none] on the spend axis (a cable
//     has no meter), so a wired Android TV is never prompted. That row is why the
//     money question needed its own enum instead of being folded into this one.
//
// Web safety: no `dart:io`. Both probes are method-channel calls whose channels are
// absent off the supported native platforms; the calls are guarded and resolve to
// [unknown] there.

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'network_transport_probe.dart';
import 'wifi_path_probe.dart';

// ============================================================================
// ROUND 5 (2026-07-14): `unknown` SPENT THE USER'S MONEY. TWO QUESTIONS, NOT ONE.
// ============================================================================
//
// Vera drove this service with the real decision table and got FIVE separate
// exploits through the consent gate. Every one of them had the same shape: an
// ambiguous read resolved to [WifiConnectionStatus.unknown], and BOTH consent
// gates closed only on a definitive `notOnWifi` —
//
//     spendData = includeThroughput && (!_notOnWifi || _throughputConsented)
//
// so `unknown` SPENT. And because the consent dialog only rendered on `notOnWifi`,
// `_throughputConsented` was still false: THE USER WAS NEVER ASKED AND COULD NOT
// HAVE BEEN. Android VPN-over-cellular, an Android transport channel that threw,
// an iPhone on cellular whose `en0` holds a link-local `fe80::` — all of them
// spent up to 573 MB, silently.
//
// THE HEADER OF THIS FILE DOCUMENTED THE LEAK AND CALLED THAT A DEFENSE:
// "the transport block falls through to `unknown` — which SPENDS THE DATA without
// a warning... This is the ONE residual cellular-spend path on Android and it is
// stated, not hidden." STATING A LEAK IS NOT CLOSING IT.
//
// THE DESIGN ERROR, PRECISELY. The old code defended `unknown → spend` with GL-005
// ("an ambiguous read is never proof of cellular"). That CONFLATES TWO DIFFERENT
// ACTS:
//
//   * ASSERTING A FACT ("You are not on Wi-Fi") — GL-005 is right: never assert
//     from ambiguity. [WifiConnectionStatus] answers this question and STILL fails
//     to `unknown`. Not one of its answers has changed.
//
//   * AUTHORIZING A SPEND — a completely different act, with a completely
//     different safe default. Under uncertainty the safe move is to ASK, not to
//     spend. YOU NEVER HAVE TO CLAIM SOMEONE IS ON CELLULAR IN ORDER TO ASK THEM.
//     GL-005 forbids fabricating a claim; it does not require spending a
//     stranger's money to avoid a prompt.
//
// A spurious prompt to a Wi-Fi user costs ONE TAP. A silent 573 MB spend costs
// REAL MONEY. The old code treated those as symmetric. They are not.
//
// So the service now answers BOTH questions, in one probe pass, and they fail in
// OPPOSITE directions:
//
//   | question                    | type                  | fails to    |
//   |-----------------------------|-----------------------|-------------|
//   | "are you on Wi-Fi?"         | [WifiConnectionStatus]| `unknown`   |
//   | "could this cost money?"    | [MeteredRisk]         | `unknown`   |
//   |                             |                       | → WHICH ASKS|
//
// The Wi-Fi question is UNCHANGED — every honest-Wi-Fi surface Keith verified on
// his phone (the "Not connected" chip, the suppressed stale rate) reads exactly
// what it read before. [MeteredRisk] is a NEW, ORTHOGONAL answer that only the
// consent gates read.
//
// WHY A SECOND ENUM AND NOT "TREAT unknown AS CELLULAR": because the 3-state Wi-Fi
// enum is LOSSY FOR THE MONEY QUESTION, and collapsing them would nag people who
// are provably not paying. A wired Android TV reports `TRANSPORT_ETHERNET` — a
// MEASUREMENT that it is not metered — and still resolves to `unknown` on the Wi-Fi
// axis, because it is genuinely not on Wi-Fi and we refuse to claim it is. Same for
// every macOS and Windows desktop. Those users must not be interrogated about
// cellular data they cannot possibly be spending. `MeteredRisk.none` is what lets
// the gate stay silent for them while still failing closed for a phone.

/// Whether running the data-hungry stages could cost the user real money.
///
/// THE MONEY QUESTION, KEPT SEPARATE FROM THE WI-FI QUESTION ON PURPOSE, AND IT
/// FAILS CLOSED. [WifiConnectionStatus] exists to state a FACT and so it fails to
/// `unknown`; this exists to authorize a SPEND and so its ambiguous case ASKS.
///
/// The asymmetry is the whole point: an unnecessary prompt costs one tap, and an
/// unasked-for 573 MB download costs money. See the round-5 note above.
enum MeteredRisk {
  /// PROVEN SAFE — spend without asking. Reached ONLY from a positive measurement:
  /// a confirmed Wi-Fi association, a confirmed WIRED (`TRANSPORT_ETHERNET`) link,
  /// or a platform that cannot be billed per byte at all (macOS / Windows / Linux /
  /// web — see [WifiConnectionService.isMeteredCapable]).
  none,

  /// PROVEN COSTLY — ask, and say plainly that the link is cellular. The OS named
  /// the mobile radio as the active link (`TRANSPORT_CELLULAR` on Android; a Wi-Fi
  /// interface carrying no address of either family on iOS).
  metered,

  /// WE CANNOT TELL — ask, and SAY SO. This is the state that used to spend.
  ///
  /// THE PROMPT MUST NOT LIE ABOUT CERTAINTY HERE. Do not tell this user "You're on
  /// cellular" — we do not know that, and asserting it would be the same disease
  /// from the other side. Say what is true: we cannot tell what link you are on,
  /// here is what it may cost, continue? See [kUnknownLinkDataWarning].
  unknown,
}

/// The service's full answer: the Wi-Fi fact AND the money risk, from ONE probe
/// pass. They are deliberately independent — see the round-5 note above.
@immutable
class LinkVerdict {
  const LinkVerdict({required this.status, required this.meteredRisk});

  /// "Are you on Wi-Fi?" — fails to [WifiConnectionStatus.unknown] (GL-005).
  final WifiConnectionStatus status;

  /// "Could this cost money?" — fails to [MeteredRisk.unknown], WHICH ASKS.
  final MeteredRisk meteredRisk;

  @override
  String toString() => 'LinkVerdict(status: $status, meteredRisk: $meteredRisk)';
}

/// The one-line consent rule, so no caller can spell it wrong.
///
/// FAIL CLOSED: anything that is not PROVEN safe requires an explicit tap. This is
/// the inversion of the round-4 gate, which required proof of DANGER before it
/// would ask — and therefore never asked on any of the five shapes Vera exploited.
extension MeteredRiskConsent on MeteredRisk {
  /// True when the app must ASK before it spends a byte.
  bool get requiresConsent => this != MeteredRisk.none;
}

/// The honest three-way Wi-Fi connection verdict. See [WifiConnectionService].
///
/// UNCHANGED BY ROUND 5. This answers "are you on Wi-Fi?" and it still fails to
/// [unknown] on any ambiguity, exactly as GL-005 requires. The consent gate no
/// longer reads it — it reads [MeteredRisk], which fails the other way.
enum WifiConnectionStatus {
  /// The device is connected to a Wi-Fi network. The live read should proceed.
  onWifi,

  /// The device is demonstrably NOT on Wi-Fi. Drives the "Connect to a Wi-Fi
  /// network to see live Wi-Fi data" state AND the cellular-data consent gate.
  ///
  /// REACHED ON EXACTLY TWO PLATFORMS, BY TWO DIFFERENT SIGNALS, AND ON NEITHER IS
  /// IT A GUESS:
  ///   * iOS — the address probe found NO address of EITHER family on the Wi-Fi
  ///     interface (an inference, but a sound one: an iPhone has no wired NIC to
  ///     confuse the read).
  ///   * Android — `ConnectivityManager` reports the ACTIVE network's transport is
  ///     `TRANSPORT_CELLULAR` and NOT `TRANSPORT_WIFI` (a MEASUREMENT: the OS
  ///     naming the radio it is routing over).
  ///
  /// It is UNREACHABLE on macOS and Windows, deliberately. There, an absent Wi-Fi
  /// address is genuinely ambiguous (a wired desktop), and a laptop tethered to a
  /// phone hotspot presents as Wi-Fi — so no honest negative exists to assert. Do
  /// not "fix" that by inferring one; see KNOWN LIMITS in [WifiConnectionService].
  notOnWifi,

  /// The probe could not determine the state. Treated by callers as "carry on as
  /// before" — NEVER as "not on Wi-Fi" (GL-005: no false negatives from missing
  /// data).
  unknown,
}

/// Probes whether the device is connected to a Wi-Fi network, honestly.
///
/// Pure I/O, no UI. The [networkInfo] and [pathProbe] seams keep it unit-testable
/// without a live network.
class WifiConnectionService {
  WifiConnectionService({
    NetworkInfo? networkInfo,
    TargetPlatform? platformOverride,
    WifiPathProbe? pathProbe,
    NetworkTransportProbe? transportProbe,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _platform = platformOverride ?? defaultTargetPlatform,
        _pathProbe = pathProbe ?? const MethodChannelWifiPathProbe(),
        _transportProbe =
            transportProbe ?? const MethodChannelNetworkTransportProbe();

  final NetworkInfo _networkInfo;
  final TargetPlatform _platform;
  final WifiPathProbe _pathProbe;
  final NetworkTransportProbe _transportProbe;

  /// Whether THIS PLATFORM can bill the user per byte at all.
  ///
  /// The phones, and only the phones. A macOS / Windows / Linux desktop or laptop
  /// has no cellular plan this app can detect, so an ambiguous link there is not a
  /// money question and must never raise a prompt: "never nag a wired desktop" is
  /// still right, and it is enforced HERE rather than by hoping the probe stays
  /// silent.
  ///
  /// STATED RESIDUAL: a Windows laptop on a built-in WWAN modem, and any desktop
  /// tethered to a phone's hotspot, ARE metered and are NOT caught by this. The
  /// hotspot case is unfixable in principle from the client's side (the hotspot IS
  /// a Wi-Fi link from the laptop's point of view — see KNOWN LIMITS), and the WWAN
  /// case has no probe. Both spend, both spent before, and neither is claimed fixed.
  bool get isMeteredCapable =>
      _platform == TargetPlatform.iOS || _platform == TargetPlatform.android;

  /// Reads the current Wi-Fi connection status. A thin wrapper over [read] for the
  /// callers that only care about the Wi-Fi fact (the live-RF surfaces).
  ///
  /// [nativeSsid] is an optional caller-supplied SSID from a native read
  /// (NEHotspotNetwork on iOS, CoreWLAN on macOS). A non-empty value is a
  /// DEFINITIVE [WifiConnectionStatus.onWifi] — a resolved SSID can only come
  /// from an active Wi-Fi association. Its ABSENCE is NOT used to assert
  /// `notOnWifi` (it can be null because Location is ungranted, not because Wi-Fi
  /// is off).
  Future<WifiConnectionStatus> status({String? nativeSsid}) async =>
      (await read(nativeSsid: nativeSsid)).status;

  /// Reads BOTH answers in ONE probe pass: the Wi-Fi fact and the money risk.
  ///
  /// Every `return` below carries both. They are decided by the SAME evidence and
  /// they fail in OPPOSITE directions — the Wi-Fi fact to [WifiConnectionStatus
  /// .unknown] (never assert from ambiguity), the money risk to [MeteredRisk
  /// .unknown] (which ASKS). See the round-5 note at the top of this file.
  Future<LinkVerdict> read({String? nativeSsid}) async {
    // ========================================================================
    // THE FAIL-CLOSED DEFAULT. On a phone, we assume the run COULD cost money
    // until something PROVES otherwise. Every ambiguous fall-through below leaves
    // this untouched, so a new branch added tomorrow cannot silently spend: it has
    // to positively earn `MeteredRisk.none`.
    //
    // On a desktop the default is `none` and nothing can raise it — see
    // [isMeteredCapable].
    // ========================================================================
    MeteredRisk risk =
        isMeteredCapable ? MeteredRisk.unknown : MeteredRisk.none;

    // ========================================================================
    // iOS WI-FI ASSIST — THE OS's OWN ROUTING ANSWER, HELD FOR THE MONEY AXIS.
    // (Keith's ruling, 2026-07-14.)
    //
    // Wi-Fi Assist keeps the Wi-Fi interface UP (en0 holds a valid IPv4) while iOS
    // routes traffic over CELLULAR when the Wi-Fi signal is weak. `NWPathMonitor`
    // reports this precisely: the default path does NOT use Wi-Fi and the
    // Wi-Fi-required path is UNSATISFIED. The address probe below, left to itself,
    // reads the raw en0 IPv4 and returns `MeteredRisk.none` — spending cellular data
    // silently. That is the address probe OVERRIDING the OS's routing answer on the
    // money axis.
    //
    // So when the iOS path monitor ANSWERS "the active route is not Wi-Fi", remember
    // it. A raw en0 IPv4 must NOT downgrade the spend risk to `none` after that: the
    // SPEND axis stays ambiguous and ASKS. This does NOT touch the FACT axis — Wi-Fi
    // Assist genuinely has a Wi-Fi association, so `status` still reads `onWifi` on
    // that path (the raw IPv4 proves the join). Two axes, kept separate (round 5).
    bool iosRouteNotWifi = false;

    // A resolved native SSID proves an active Wi-Fi join — strongest positive.
    if (nativeSsid != null && nativeSsid.trim().isNotEmpty) {
      return const LinkVerdict(
        status: WifiConnectionStatus.onWifi,
        meteredRisk: MeteredRisk.none,
      );
    }

    // ========================================================================
    // PRIMARY: ask iOS what interface the path actually runs over.
    //
    // iOS ONLY, because the channel is iOS-only: `WifiSecurityChannel` is
    // registered in ios/Runner/AppDelegate.swift and NOWHERE else. On every other
    // platform the call is a guaranteed MissingPluginException, so skipping it is
    // not an optimization, it is the removal of a round-trip that cannot succeed.
    // (When macOS gains a path channel, widen this gate — and delete this note.)
    // ========================================================================
    final WifiPathFacts? path =
        _platform == TargetPlatform.iOS ? await _pathProbe.read() : null;
    if (path != null) {
      // The default route runs over Wi-Fi, or a Wi-Fi-required path has a usable
      // route. Either is a definitive association — a device cannot route over a
      // Wi-Fi interface it is not joined to. This is where an IPv6-only SSID is
      // caught, so it NEVER reaches the address probe below (which is blind to it).
      if (path.usesWifi || path.wifiSatisfied) {
        return const LinkVerdict(
          status: WifiConnectionStatus.onWifi,
          meteredRisk: MeteredRisk.none,
        );
      }
      // THE PATH ANSWERED AND THE ACTIVE ROUTE IS NOT WI-FI. Hold that for the money
      // axis: a raw en0 IPv4 from the address probe below must not be read as "safe
      // to spend" when iOS has already said the bytes are not going over Wi-Fi
      // (Wi-Fi Assist). See the note at the declaration of [iosRouteNotWifi].
      iosRouteNotWifi = true;
      // AND EVERYTHING ELSE THE PATH REPORTS LEAVES `risk` AT ITS FAIL-CLOSED
      // DEFAULT. A Wi-Fi interface that is present but carries no usable route —
      // the ordinary state of an iPhone sitting on cellular with Wi-Fi left
      // switched on — is exactly Vera's exploit #5, and it now ASKS instead of
      // spending. The Wi-Fi verdict for it is still an honest `unknown`.
      //
      // ====================================================================
      // "NO WI-FI INTERFACE AT ALL" IS AMBIGUOUS TOO, AND IT ALSO FALLS THROUGH.
      // (Round-4 cold review, F-4, 2026-07-14.)
      //
      // This used to be the ONE branch in the codebase that asserted a DEFINITIVE
      // NEGATIVE — "you have no Wi-Fi" — from native data alone:
      //
      //     if (!path.wifiInterfacePresent) return WifiConnectionStatus.notOnWifi;
      //
      // The header called that shape MEASURED. What was measured was macOS:
      // `NWPathMonitor(requiredInterfaceType: .wiredEthernet)` on a machine with no
      // wired NIC. That establishes exactly nothing about an iPhone mid-roam, mid
      // network-transition, or backgrounded — and NO iPHONE HAS EVER RUN THIS CODE.
      //
      // If iOS ever reports empty `availableInterfaces` on both paths while the
      // device is genuinely associated, that branch told a user who IS on Wi-Fi
      // that they had none and BLANKED THEIR LIVE LINK. That is the R2 bug class,
      // which this project has now shipped and fixed twice. Round 3 was
      // structurally incapable of it, because it consulted addresses. So round 4
      // was not "strictly better in every shape": in this one shape — the shape
      // nobody has ever run — it was strictly worse, and it was the only shape
      // where a single unverified native answer could silence a real link.
      //
      // WHAT THE FALL-THROUGH COSTS: only USB-tether discrimination (a tethered
      // `en*` carries an address, so the probe below reads it as Wi-Fi — which is
      // exactly what shipped before round 4). WHAT IT KEEPS: radio-off detection,
      // in full — no IPv4 AND no IPv6 on the interface resolves to `notOnWifi`
      // below, on its own, without help from this branch. So the honest
      // not-on-Wi-Fi state Keith verified on his own phone is untouched.
      //
      // Blanking a genuinely-connected user's Wi-Fi is a vastly worse failure than
      // failing to tell a tether from a link. We do not buy a small capability with
      // a large silent lie. The invariant round 4 was supposed to establish, and
      // did not, now holds everywhere: NO DEFINITIVE NEGATIVE FROM AN UNVERIFIED
      // SIGNAL. The native path keeps every answer it can PROVE (both POSITIVES,
      // above) and hands everything else to the signal that has actually been
      // verified in the field.
      //
      // The remaining shapes that land here — a captive portal mid-join, a phone
      // HOSTING a hotspot, a radio that is on but unassociated — were already
      // falling through, and are resolved by the address probe exactly as before.
      // ====================================================================
      //
      // A Wi-Fi interface is present but carries no usable route. That covers a
      // captive portal mid-join, a phone HOSTING a hotspot, and — the one that
      // matters — A RADIO THAT IS ON BUT NOT ASSOCIATED, which is the ordinary
      // state of an iPhone sitting on cellular with Wi-Fi left switched on.
      //
      // The first cut of round 4 returned `unknown` here and stopped. That made
      // `notOnWifi` UNREACHABLE for that state, because the address probe below
      // sits outside this block and the native monitor always answers (it starts
      // at app launch). `unknown` means "keep prior behavior", and the prior
      // behavior is the stale App Group reading — so the screen went back to
      // "It's your Wi-Fi", "KeithHome", "29 Mbps". THAT IS THE ORIGINAL BUG,
      // rendered by the code written to remove it. I dismissed the cost in a
      // comment as "a stale reading". The stale reading IS the bug.
      //
      // Falling through is strictly better than BOTH earlier designs in every
      // shape we can enumerate:
      //   * IPv6-only Wi-Fi   — never gets here (caught above). Round 2's blocker
      //                         stays fixed.
      //   * Radio on, idle    — no IPv4 and no IPv6 on the interface → the probe
      //                         below returns `notOnWifi`. The bug stays fixed,
      //                         exactly as it was before the native path existed.
      //   * Captive portal    — DHCP has handed out an IPv4 → `onWifi`. Better
      //                         than the `unknown` this used to return.
      //   * Anything definite — already answered above; never reaches here.
      //
      // The native path keeps every answer it can PROVE, and hands the rest to the
      // signal that has actually been verified in the field, instead of discarding
      // it. Nothing is guessed in either layer.
      // ====================================================================
    }

    // ========================================================================
    // PRIMARY (ANDROID): ASK ConnectivityManager WHAT TRANSPORT THE ACTIVE
    // NETWORK RUNS OVER. (Round-4 cold review, THE ANDROID GATE, 2026-07-14.)
    //
    // WHY THIS BLOCK EXISTS. Everything below this point is the ADDRESS PROBE, and
    // the address probe REFUSES to assert a negative off iOS (see the
    // `_platform != TargetPlatform.iOS => unknown` guard). That refusal is correct
    // FOR THE ADDRESS PROBE — an absent Wi-Fi IPv4 on a desktop means nothing —
    // but it had one catastrophic consequence: `notOnWifi` was STRUCTURALLY
    // UNREACHABLE ON ANDROID. Both consent gates read `status == notOnWifi`
    // exactly, so on Android — LIVE on Google Play, and the one platform where
    // "on cellular" is the DEFAULT assumption — `spendData` was UNCONDITIONALLY
    // TRUE. No warning. No cost sentence. No decline path. Nothing to consent to.
    // And the home hero pushes Test My Connection with `autoStart: true`, so the
    // app's PRIMARY ENTRY POINT ran a full ~30 s throughput measurement plus the
    // RPM load generator — 50 to 500 MB of a metered plan — with ZERO TAPS.
    //
    // THAT WAS "WE NEVER ASKED", NOT "WE CANNOT KNOW", AND THE DIFFERENCE IS THE
    // WHOLE DESIGN. The GL-005 rationale this service is built on — an ambiguous
    // read is never proof of cellular; never nag a wired desktop — was written for
    // platforms where the transport GENUINELY CANNOT BE TOLD from an IP address.
    // IT DOES NOT COVER ANDROID. Android answers the actual question directly:
    // `NetworkCapabilities.hasTransport(TRANSPORT_CELLULAR)` on the ACTIVE network
    // is a MEASURED fact from the OS about the link that is carrying the bytes.
    // Declining to read a knowable fact and then citing the resulting silence as
    // ambiguity is the two-kinds-of-null error pointed the wrong way
    // ([[feedback_unsourced_is_not_invalid]]) — "unsourced" is not "invalid", and
    // "we never asked" is not "we cannot know".
    //
    // IT COSTS NO PERMISSION AND NO PROMPT. `ACCESS_NETWORK_STATE` is a `normal`
    // (install-time) permission, already declared in AndroidManifest.xml, and the
    // transport TYPE is not Location-gated the way SSID/BSSID are — so this
    // answers even on a device that has denied Location outright.
    //
    // THE DECISION TABLE (Android, the transport probe):
    //
    //   | Transport bits on the ACTIVE network      | Verdict     | Why          |
    //   |-------------------------------------------|-------------|--------------|
    //   | wifi, and NOT cellular                    | `onWifi`    | definitive + |
    //   | cellular, and NOT wifi                    | `notOnWifi` | MEASURED —   |
    //   |                                           |             | the user IS  |
    //   |                                           |             | paying/byte  |
    //   | wifi AND cellular (a VPN over both)       | ↓ AMBIGUOUS | cannot tell  |
    //   |                                           |             | which pays   |
    //   | ethernet (wired TV / dock), no cellular   | ↓ AMBIGUOUS | NOT cellular |
    //   | nothing (airplane mode), or exotic (BT/USB)| ↓ AMBIGUOUS | NOT cellular |
    //   | the probe did not answer (null)           | ↓ ADDRESSES | no verdict   |
    //
    // "↓ AMBIGUOUS" falls through to the address probe, which returns `unknown` on
    // Android (the `!= iOS` guard below). `unknown` means "carry on as before": NO
    // NAG, and NO false claim of Wi-Fi. That is exactly what a wired Android TV and
    // a tablet on Wi-Fi require, and it is why over-suppression is impossible here:
    // the ONLY row that can raise the gate is a MEASURED cellular transport with no
    // Wi-Fi alongside it.
    //
    // THE SAME INVARIANT THE NATIVE iOS PATH JUST LEARNED (F-4) HOLDS HERE: NO
    // DEFINITIVE NEGATIVE FROM AN UNVERIFIED SIGNAL. The difference — the ONLY
    // difference, and it is the one that licenses the negative — is that on Android
    // the signal IS verified. `TRANSPORT_CELLULAR` is not an inference from a
    // missing address; it is the OS naming the radio it is routing over. That is
    // the one place in this codebase where a negative is earned.
    // ========================================================================
    if (_platform == TargetPlatform.android) {
      final NetworkTransportFacts? t = await _transportProbe.read();
      if (t != null) {
        // DEFINITIVE POSITIVE: the active network runs over Wi-Fi and nothing is
        // billing us per byte. A device cannot route over a Wi-Fi interface it is
        // not joined to.
        if (t.wifi && !t.cellular) {
          return const LinkVerdict(
            status: WifiConnectionStatus.onWifi,
            meteredRisk: MeteredRisk.none,
          );
        }
        // DEFINITIVE NEGATIVE — AND THE ONLY ONE ANDROID MAY ASSERT. The OS says
        // the active network is the mobile radio, and says no Wi-Fi is carrying it.
        // The user is paying per byte, and we know it. This is the line that makes
        // the consent gate reachable on Android at all.
        if (t.cellular && !t.wifi) {
          return const LinkVerdict(
            status: WifiConnectionStatus.notOnWifi,
            meteredRisk: MeteredRisk.metered,
          );
        }
        // ====================================================================
        // AMBIGUOUS FOR THE WI-FI QUESTION. NOT ALWAYS AMBIGUOUS FOR THE MONEY
        // QUESTION — AND THAT DISTINCTION IS THE REASON [MeteredRisk] EXISTS.
        //
        // WIRED IS A MEASUREMENT, NOT AN ABSENCE. `TRANSPORT_ETHERNET` with no
        // cellular alongside it is the OS telling us the bytes run over a CABLE.
        // That is not "we could not tell" — it is proof there is no meter. The
        // Wi-Fi verdict stays an honest `unknown` (a wired Android TV is genuinely
        // not on Wi-Fi and we will not claim it is), but the SPEND is provably free,
        // so the gate stays silent. Collapsing these two questions into one enum is
        // exactly what would have nagged every wired Android box in the field.
        if (!t.cellular && t.ethernet) {
          risk = MeteredRisk.none;
        }
        // EVERYTHING ELSE LEAVES `risk` AT `unknown` — WHICH NOW ASKS:
        //
        //   * BOTH wifi AND cellular — a VPN whose underlying networks include
        //     both. We cannot tell which link pays, so we assert NEITHER on the
        //     Wi-Fi axis. WAS VERA'S EXPLOIT #2: the old code let this SPEND,
        //     because it only closed on a definitive `notOnWifi`. It now ASKS.
        //   * VPN WITH NO UNDERLYING TRANSPORT — the VPN app never called
        //     `setUnderlyingNetworks`, so the OS reports only `TRANSPORT_VPN`.
        //     WAS VERA'S EXPLOIT #1. The old header called this "the ONE residual
        //     cellular-spend path on Android" and shipped it. It now ASKS. Note we
        //     still do not CLAIM cellular — asserting that would nag every
        //     VPN-on-Wi-Fi user with a false statement. We ask WITHOUT claiming.
        //   * NO ACTIVE NETWORK (airplane mode) or an EXOTIC transport (Bluetooth
        //     tether, USB, LoWPAN) — all four bits false. This shape is genuinely
        //     ambiguous between "nothing is connected" (spending is impossible) and
        //     "a Bluetooth/USB tether to a phone" (spending is METERED, and it is
        //     the phone's plan paying). So it asks. A pointless prompt in airplane
        //     mode costs one tap; a silent tethered spend costs money.
      }
      // A NULL READ LEAVES `risk` AT `unknown` — WHICH NOW ASKS. The channel is
      // absent, the call threw, or the 3 s deadline fired. WAS VERA'S EXPLOIT #3.
      // It is NOT a verdict in either direction for the Wi-Fi question, and the
      // address probe below still resolves Android's STATUS to `unknown` — but a
      // read we could not make is not permission to spend a stranger's money.
    }

    // ========================================================================
    // THE ADDRESS PROBE. Reached when the native path did not answer (every
    // non-iOS platform, and an iOS read that timed out or failed) OR when it
    // answered AMBIGUOUSLY (above). Its limits are real and documented in KNOWN
    // LIMITS — but on the shapes that reach it, it is the better signal.
    // ========================================================================
    final ({String? ip, bool threw}) v4 = await _readWifiIp();
    if (v4.threw) {
      // The read FAILED (denied permission / unsupported platform). Ambiguous,
      // never a positive not-on-Wi-Fi signal (GL-005) — and, on a phone, never
      // permission to spend either: `risk` is still `unknown`, so the gate asks.
      return LinkVerdict(
        status: WifiConnectionStatus.unknown,
        meteredRisk: risk,
      );
    }
    if (v4.ip != null) {
      // An active Wi-Fi interface has an IPv4 address: on Wi-Fi (the FACT axis).
      //
      // THE MONEY AXIS SPLITS ON WHETHER THE iOS PATH MONITOR ALREADY ANSWERED
      // "NOT WI-FI" (Keith's Wi-Fi Assist ruling, 2026-07-14):
      //
      //   * [iosRouteNotWifi] == true — the path probe ANSWERED and the active
      //     route is NOT Wi-Fi, yet en0 still holds this IPv4. That is exactly
      //     Wi-Fi Assist: iOS moved the bytes to CELLULAR while leaving the Wi-Fi
      //     interface up. The raw address must NOT override the OS's routing answer
      //     on the spend axis, so the money risk stays AMBIGUOUS and ASKS
      //     (`unknown`). This was the "STATED RESIDUAL" the prior comment named and
      //     shipped: `onWifi`/`none` — a silent cellular spend. Keith ruled it shut.
      //     The tap stays; ambiguity asks. Less cost is not no cost.
      //
      //   * [iosRouteNotWifi] == false — the native path probe did NOT answer (or
      //     this is a non-iOS platform), so the address alone decides. An iOS
      //     ASSOCIATED interface can still hold an IPv4 while routing over cellular,
      //     but with no OS routing answer to honor we keep the pre-existing,
      //     DOCUMENTED behavior (`none`): closing it here, blind to the path, would
      //     mean refusing to trust a Wi-Fi address at all and nagging every phone
      //     with both radios up. That residual is unchanged.
      //
      // The FACT axis is `onWifi` in BOTH: a real IPv4 proves a real association,
      // and the money axis asking never licenses claiming the device is off Wi-Fi.
      return LinkVerdict(
        status: WifiConnectionStatus.onWifi,
        meteredRisk: iosRouteNotWifi ? MeteredRisk.unknown : MeteredRisk.none,
      );
    }

    // No Wi-Fi IPv4 from a SUCCESSFUL read. Whether that can EVER prove "not on
    // Wi-Fi" depends on the platform:
    //   * iOS: no wired Ethernet exists to confuse the read, so an empty Wi-Fi
    //     interface is meaningful — but see the IPv6 check below, because the
    //     IPv4 read alone is blind to an IPv6-only SSID.
    //   * Everywhere else: an empty Wi-Fi IPv4 is AMBIGUOUS (a wired-only Mac, a
    //     desktop with Wi-Fi off, a platform that does not report the Wi-Fi IP),
    //     so we resolve to `unknown` rather than falsely tell a wired user to
    //     "connect to Wi-Fi" (GL-005).
    //
    // ANDROID REACHES THIS LINE ONLY WHEN THE TRANSPORT PROBE COULD NOT DECIDE (it
    // did not answer, or it answered ambiguously — a VPN over both radios, a wired
    // TV, airplane mode). `unknown` is the RIGHT answer for every one of those, so
    // this guard stays exactly as it is. The Android gate does NOT live here; it
    // lives in the transport block ABOVE, where the signal is MEASURED. Widening
    // this guard to let the ADDRESS probe assert a negative on Android would
    // reintroduce, on a platform that genuinely has wired Ethernet, the exact false
    // negative this guard was written to prevent.
    if (_platform != TargetPlatform.iOS) {
      // ANDROID lands here carrying whatever `risk` the transport block settled:
      // `none` for a MEASURED wired link, `unknown` for a VPN / both-transports /
      // airplane / unreadable channel. macOS and Windows land here with `none`,
      // because [isMeteredCapable] is false and no branch can raise it — so a wired
      // desktop is still never nagged, which was the whole reason this guard exists.
      return LinkVerdict(
        status: WifiConnectionStatus.unknown,
        meteredRisk: risk,
      );
    }

    // iOS, no Wi-Fi IPv4, and the native path did not answer. The IPv6 read
    // answers exactly one question, and only its NEGATIVE answer is trustworthy:
    // "does the Wi-Fi interface carry ANY address at all?"
    //
    //   * NO  → the interface has no active link. That is the cellular-only /
    //           radio-off device, and the ONLY shape that may assert `notOnWifi`.
    //   * YES → SOMETHING is on the interface, but an IPv6-only association cannot
    //           be told from an idle interface holding a link-local. Refuse to
    //           guess: `unknown` keeps the caller's prior Wi-Fi behavior — but it
    //           NO LONGER keeps the prior SPENDING behavior. See below.
    final ({bool present, bool threw}) v6 = await _readWifiIpv6();
    if (v6.threw) {
      // The IPv6 read failed, so "no Wi-Fi address at all" is unproven.
      return LinkVerdict(
        status: WifiConnectionStatus.unknown,
        meteredRisk: risk,
      );
    }
    if (v6.present) {
      // VERA'S EXPLOITS #4 AND #5 LIVED HERE, AND THEY WERE THE WHOLE POINT.
      //
      // `network_info_plus` filters interfaces with `strncmp(name, "en", 2)` and
      // returns the FIRST match's IPv6 — which is the LINK-LOCAL `fe80::`. An
      // iPhone on CELLULAR, with Wi-Fi switched on but unassociated, carries a
      // `fe80::` on `en0` and NOTHING ELSE. So this branch fired, resolved to
      // `unknown`, and the old gate SPENT — up to 573 MB, with no prompt, on a
      // phone that was demonstrably not using its Wi-Fi.
      //
      // The Wi-Fi verdict is STILL `unknown`, and it must be: a link-local cannot
      // tell an IPv6-only association from an idle radio, and claiming "not on
      // Wi-Fi" here would blank a genuinely-connected user's link (the R2 bug this
      // project has already shipped twice). We refuse to CLAIM. We do not refuse
      // to ASK. `risk` is still `unknown`, so the gate asks — without asserting a
      // single thing we cannot prove.
      return LinkVerdict(
        status: WifiConnectionStatus.unknown,
        meteredRisk: risk,
      );
    }

    // No IPv4 and NO IPv6 anywhere on the Wi-Fi interface: it has no active link.
    // On an iPhone that means the bytes are going over the mobile radio, and the
    // user is paying for them. Both answers are definitive, and they agree.
    return const LinkVerdict(
      status: WifiConnectionStatus.notOnWifi,
      meteredRisk: MeteredRisk.metered,
    );
  }

  /// Reads the Wi-Fi IPv4 address, normalizing the "no address" placeholders to
  /// null.
  ///
  /// Returns a record so the caller can tell a CLEAN null (the read succeeded but
  /// there is no Wi-Fi IPv4 address) apart from a FAILED read ([threw] == true:
  /// denied permission / absent method channel). A failed read is always
  /// `unknown` (GL-005: a denied/errored read is never a false negative).
  Future<({String? ip, bool threw})> _readWifiIp() async {
    try {
      final String? v = await _networkInfo.getWifiIP();
      if (v == null) return (ip: null, threw: false);
      final String t = v.trim();
      // Guard against the all-zeros placeholder some platforms return for "no
      // address" — treat it as null (no Wi-Fi IP), never as a real address.
      if (t.isEmpty || t == '0.0.0.0') return (ip: null, threw: false);
      return (ip: t, threw: false);
    } on Object catch (e) {
      debugPrint('WifiConnectionService.getWifiIP failed: $e');
      return (ip: null, threw: true);
    }
  }

  /// Whether the Wi-Fi interface carries ANY IPv6 address.
  ///
  /// DELIBERATELY UNCLASSIFIED. The plugin returns the FIRST AF_INET6 address on
  /// `en*`, which is the LINK-LOCAL, so classifying it cannot prove association.
  /// This reports PRESENCE only, and the caller uses only the negative: no address
  /// of either family ⇒ no active link ⇒ `notOnWifi`. Any address ⇒ `unknown`.
  ///
  /// The all-zeros IPv6 placeholder (`::`, and its `0:0:0:0:0:0:0:0` long form) is
  /// normalized to "absent", exactly as [_readWifiIp] normalizes `0.0.0.0` — an
  /// unspecified address is not an address, and reading it as one would suppress a
  /// legitimate `notOnWifi` on a cellular-only phone.
  ///
  /// [present] is false for a null/blank/all-zeros read. [threw] == true means the
  /// read itself failed, which the caller must resolve to `unknown` — never
  /// `notOnWifi`.
  Future<({bool present, bool threw})> _readWifiIpv6() async {
    try {
      final String? v = await _networkInfo.getWifiIPv6();
      if (v == null) return (present: false, threw: false);
      final String t = v.trim();
      if (t.isEmpty || _isUnspecifiedIpv6(t)) {
        return (present: false, threw: false);
      }
      return (present: true, threw: false);
    } on Object catch (e) {
      debugPrint('WifiConnectionService.getWifiIPv6 failed: $e');
      return (present: false, threw: true);
    }
  }

  /// True for the IPv6 unspecified address in any spelling: `::`, the fully
  /// expanded `0:0:0:0:0:0:0:0`, and zero-padded forms. Case-insensitive, and any
  /// zone suffix (`%en0`) is stripped first.
  static bool _isUnspecifiedIpv6(String raw) {
    final String addr = raw.split('%').first.trim();
    if (addr.isEmpty) return false;
    if (addr == '::') return true;
    // Every group must be present and zero. `::` shorthand anywhere else (e.g.
    // `::1`, the loopback) has a non-zero group and is correctly NOT unspecified.
    final List<String> groups = addr.split(':');
    bool sawDigit = false;
    for (final String g in groups) {
      if (g.isEmpty) continue; // the `::` elision
      sawDigit = true;
      if (int.tryParse(g, radix: 16) != 0) return false;
    }
    return sawDigit;
  }
}
