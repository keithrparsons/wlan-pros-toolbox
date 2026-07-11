// ChromeOsArc — the single source of truth for "are we the Android build running
// inside ChromeOS's ARC virtual machine?", and for every honest-null reason
// string that fact produces.
//
// WHY THIS EXISTS (2026-07-10, Keith). On a Chromebook, an Android app does NOT
// run on the Chromebook's network stack. It runs inside ARCVM — a virtual
// machine whose network is a small, NAT'd, private network created by ChromeOS
// (`patchpanel`), carved out of the RFC 6598 shared-address block at
// `100.115.92.0/24`. Two consequences, both of which produced CONFIDENTLY WRONG
// output before this file existed:
//
//   1. ADDRESSING IS THE VM'S, NOT THE LAN'S.
//      `WifiManager.getDhcpInfo()` and `ConnectivityManager.getLinkProperties()`
//      describe the ARC VM's virtual adapter: a `100.115.92.x` address, a /30
//      subnet, a `100.115.92.x` gateway, and ChromeOS's own DNS proxy. The
//      user's REAL gateway (say `10.20.0.1`) and REAL resolvers are on the other
//      side of the NAT and are not visible to the app at all. Test My Connection
//      presented these as "your network". A K-12 IT admin troubleshooting a
//      school network was being handed a virtual machine's gateway with no way
//      to know. That is not degraded data — it is wrong data.
//
//   2. THE RF FIELDS HAVE NO TRUSTWORTHY SOURCE.
//      ARC's Wi-Fi bridge is fed from ChromeOS's ONC (Open Network
//      Configuration) vocabulary. ONC defines signal strength as a **0–100
//      percentage** and carries **no dBm field at all**. Any RSSI an Android app
//      reads on a Chromebook is therefore, at best, a lossy reconstruction of a
//      percentage — a number that LOOKS like dBm and is not one. ONC likewise has
//      no vocabulary for channel width, PHY/link rate, the 802.11 generation, or
//      MLO, so those do not arrive either.
//
// THE RULE (GL-005 / GL-008, and Keith's standing line — "a tool that is
// confidently wrong is worse than no tool"): on ChromeOS we suppress every field
// whose value would describe the VM or would be an untrustworthy round-trip, and
// we SAY WHY. Honest-null, exactly as Windows does for Noise/SNR (which the
// Native Wifi API genuinely does not expose) — never a blank, never a zero,
// never a guess.
//
// WHAT WE KEEP, AND WHY. The fields ONC actually defines pass through and stay:
//   * SSID      — the real joined network name (ONC `WiFi.SSID`).
//   * BSSID     — the real AP MAC (ONC `WiFi.BSSID`). Its failure mode is a null
//                 or the `02:00:00:00:00:00` sentinel, both of which the native
//                 side already maps to null — it cannot come back plausibly WRONG.
//   * Channel / band — derived from the real center frequency (ONC
//                 `WiFi.Frequency`). A frequency of 0 already resolves to null.
//   * Security  — ONC `WiFi.Security`.
// Everything measured over the wire (public IP, ISP, ping, DNS resolution time,
// throughput) is also real: ARC's traffic is NAT'd onto the physical network, so
// it genuinely reaches the internet through the user's real path.
//
// DETECTION. `PackageManager.hasSystemFeature("org.chromium.arc")` is the
// canonical ChromeOS/ARC probe and is what MainActivity checks first; it also
// checks `org.chromium.arc.device_management` (present on managed/enterprise
// Chromebooks — the K-12 case) and `PackageManager.FEATURE_PC`
// ("android.hardware.type.pc", which ChromeOS declares), so a device that
// reports any of the three is treated as ChromeOS. The verdict is resolved ONCE
// at startup ([ensureDetected], called from `main()`) and cached, so every
// screen and service can read [isChromeOs] synchronously inside `build()`.
//
// A FAILED DETECTION IS `false`, DELIBERATELY. The channel is absent on
// iOS/macOS/Windows/web (MissingPluginException) and could in principle throw on
// Android. In every one of those cases we resolve to `false` — i.e. "not
// ChromeOS", the status quo — rather than suppressing real data on a real
// phone. The cost of a false NEGATIVE is a Chromebook that keeps the pre-fix
// behavior; the cost of a false POSITIVE is a Pixel that hides its perfectly
// good RSSI. We take the former.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ChromeOS / ARC-VM detection and the honest-null copy that follows from it.
///
/// Static by design: the answer cannot change while the process is alive, every
/// consumer needs it synchronously in `build()`, and there is exactly one right
/// answer per run. See the file header for the full rationale.
class ChromeOsArc {
  ChromeOsArc._();

  /// The Android-only native channel that answers the ChromeOS probe. Has NO
  /// handler on iOS / macOS / Windows / web — a call there throws
  /// [MissingPluginException], which [ensureDetected] resolves to `false`.
  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('com.wlanpros.toolbox/platform_env');

  static bool _isChromeOs = false;
  static bool _detected = false;

  /// Whether this process is the Android build running inside ChromeOS's ARC
  /// virtual machine.
  ///
  /// Safe to read synchronously in `build()`. Defaults to `false` until
  /// [ensureDetected] resolves (and stays `false` if the probe fails) — see the
  /// "a failed detection is false, deliberately" note in the file header.
  static bool get isChromeOs => _isChromeOs;

  /// Whether the probe has run to completion. Exposed so a caller can tell
  /// "definitely not ChromeOS" from "not asked yet"; no shipping screen needs
  /// the distinction today (both render the normal Android path), but a future
  /// caller must not mistake the pre-detection default for a real verdict.
  static bool get detected => _detected;

  /// Runs the ChromeOS probe once and caches the verdict. Idempotent; never
  /// throws. Called from `main()` before the first frame so [isChromeOs] is
  /// settled by the time any screen builds.
  static Future<bool> ensureDetected() async {
    if (_detected) return _isChromeOs;
    try {
      final bool? v = await channel.invokeMethod<bool>('isChromeOs');
      _isChromeOs = v ?? false;
    } on MissingPluginException {
      // Not Android (iOS / macOS / Windows / web) — no handler exists. Not
      // ChromeOS.
      _isChromeOs = false;
    } on Object catch (e) {
      // A PlatformException or a malformed payload is ambiguous, and ambiguity
      // must never SUPPRESS data on a device that may be a perfectly ordinary
      // phone. Resolve to "not ChromeOS" (GL-005: no false ceilings from a
      // failed read).
      debugPrint('ChromeOsArc.ensureDetected failed: $e');
      _isChromeOs = false;
    }
    _detected = true;
    return _isChromeOs;
  }

  /// Test-only override. Pass `true`/`false` to pin the verdict, or `null` to
  /// reset to the undetected default so the next [ensureDetected] re-probes.
  @visibleForTesting
  static void debugSetIsChromeOs(bool? value) {
    if (value == null) {
      _isChromeOs = false;
      _detected = false;
      return;
    }
    _isChromeOs = value;
    _detected = true;
  }

  // -------------------------------------------------------------------------
  // The user-facing copy. ONE home for it, so the wording cannot drift between
  // Test My Connection, Wi-Fi Information, Interface Information, Nearby AP
  // Scan, and the per-tool help (SSOT — see the help-file rule).
  //
  // Voice: plain English for a school IT admin, not an engineer. Conclusion
  // first, no apology, no marketing. It names WHAT is hidden, WHY, and — the
  // part that keeps the tool useful — WHAT IS STILL TRUE.
  // -------------------------------------------------------------------------

  /// The notice headline. Leads with the consequence, not the mechanism.
  static const String noticeHeadline = 'Some fields are hidden on ChromeOS';

  /// The notice body. Two facts and their consequence, in that order.
  static const String noticeBody =
      'Android apps run inside a virtual machine on a Chromebook, on a small '
      'private network of its own. The IP address, gateway, subnet, DHCP server, '
      'and DNS servers Android can see here belong to that virtual machine, not '
      'to your real network. ChromeOS also does not hand Android a true signal '
      'level in dBm, a channel width, a link rate, or the 802.11 standard.\n\n'
      'Those fields are hidden rather than shown incorrectly. To read your real '
      'network settings, use the Chromebook itself: Settings > Network > Wi-Fi, '
      'then open the network you are on.';

  /// What the user CAN still trust on the Wi-Fi surfaces. Appended to the notice
  /// so it never reads as "this tool is broken here" — most of it still works.
  static const String stillTrueWifi =
      'Still accurate: the network name, the BSSID, the channel, the band, and '
      'the security type.';

  /// What the user CAN still trust on Test My Connection. The measured results
  /// are real — ARC's traffic is carried out onto the physical network, so the
  /// speed, latency, and public-IP figures are your real path to the internet.
  static const String stillTrueConnection =
      'Still accurate: everything measured over the internet — download and '
      'upload speed, latency, jitter, DNS resolution time, your public IP, and '
      'your ISP.';

  /// What the user CAN still trust on Interface Information, where the addresses
  /// ARE shown (labeled) rather than suppressed — see the note on the screen.
  static const String stillTrueInterface =
      'The public IP address below is real. The interface addresses are the '
      "virtual machine's own, and are labeled as such.";

  // -------------------------------------------------------------------------
  // Per-field reasons. Each names the true cause in one line, so a row reads as
  // an honest fact rather than a bare "Unavailable" the user cannot interpret.
  // -------------------------------------------------------------------------

  /// RSSI. ChromeOS's ONC vocabulary carries a 0–100 percentage and NO dBm, so
  /// any dBm we could show would be a reconstruction, not a measurement. We do
  /// not have the percentage either (Android has no ONC access), so the honest
  /// answer is nothing plus this reason — never a converted number.
  static const String signalReason =
      'ChromeOS does not give Android a signal level in dBm';

  /// Noise floor / SNR. Already null on Android everywhere; on ChromeOS the
  /// reason names ChromeOS rather than Android so a Chromebook user is not told
  /// about a phone limitation.
  static const String noiseReason =
      'ChromeOS does not give Android a noise-floor reading';

  /// SNR. Follows the noise floor.
  static const String snrReason =
      'Needs the noise floor, which ChromeOS does not give Android';

  /// Tx / Rx link rate. ONC has no PHY-rate field.
  static const String rateReason =
      'ChromeOS does not give Android the link rate';

  /// Channel width. ONC has no channel-width field.
  static const String channelWidthReason =
      'ChromeOS does not give Android the channel width';

  /// 802.11 standard / PHY generation. ONC has no PHY-generation field.
  static const String standardReason =
      'ChromeOS does not give Android the 802.11 standard';

  /// Local IP / subnet mask / default gateway / DHCP server / DNS servers. All
  /// five describe the ARC virtual machine's private, NAT'd network.
  static const String addressingReason =
      "Describes the Chromebook's virtual machine, not your network";

  /// Nearby-AP scan. The scan's headline datum is signal, which is not
  /// trustworthy here, and the per-BSS channel width has no ONC vocabulary — so
  /// the tool is shown as unavailable rather than as a half-trustworthy list.
  static const String scanUnavailableHeadline = 'Not reliable on ChromeOS';
  static const String scanUnavailableBody =
      'Android apps run inside a virtual machine on a Chromebook, and ChromeOS '
      'does not pass it a real signal level. A scan list without trustworthy '
      'signal readings would be misleading, so it is not shown here. Run the '
      'Toolbox on a phone, a Mac, or a Windows laptop for a nearby-AP scan.';

  /// LAN discovery / subnet-derived scans. The app's own address is inside the
  /// VM's /30, so a subnet sweep seeded from it scans the virtual machine, finds
  /// nothing, and reports an empty LAN — a confidently-wrong "no devices found".
  static const String lanScanUnavailableHeadline =
      'Not reliable on ChromeOS';
  static const String lanScanUnavailableBody =
      'Android apps run inside a virtual machine on a Chromebook, with a private '
      'network of their own. A scan of "my subnet" would scan that virtual '
      "machine, not your real network, and would report no devices — which isn't "
      'true. It is not shown here rather than shown wrong. Run the Toolbox on a '
      'phone, a Mac, or a Windows laptop to scan the real LAN.';
}
