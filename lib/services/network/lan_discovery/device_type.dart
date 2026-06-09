// Heuristic device-type inference — Network Discovery (TICKET-HSD-02).
//
// No OS gives you "this is a printer" (brief §7). Device type is inferred from
// the signals the scan actually collects: the open-port fingerprint and the
// mDNS service types. On mobile there is NO MAC address available to a
// sandboxed app, so this heuristic deliberately uses no MAC anchor — it must
// produce the same result on every platform from ports + mDNS alone.
//
// This is a small, ordered rule table on purpose. The first matching rule
// wins, most-specific first. It is the bit worth unit-testing and locking, so
// it is pure (no dart:io, no Flutter) and fully deterministic.

import 'curated_ports.dart';

/// Coarse device classes the spike can infer. Honest and small — not Fing's
/// MAC-anchored database. `unknown` is a first-class, non-apologetic outcome.
enum DeviceType {
  printer('Printer'),
  camera('Camera / NVR'),
  speaker('Speaker / media'),
  mediaStreamer('Media streamer'),
  appleDevice('Apple device'),
  iosDevice('iOS device'),
  windowsHost('Windows / SMB host'),
  // M1 — networking-gear classes, derived from the OUI vendor (desktop only,
  // where the ARP read supplies a MAC). On mobile there is no MAC anchor, so
  // these never fire there and the host falls through to a port/mDNS guess or
  // Unknown — the documented ceiling, not a bug.
  accessPoint('Access point / Wi-Fi'),
  networkGear('Network gear'),
  webServer('Web server / host'),
  sshHost('SSH host'),
  mdnsDevice('mDNS device'),
  unknown('Unknown');

  const DeviceType(this.label);

  /// Human-readable label for the debug list.
  final String label;
}

/// Pure heuristic: infer a [DeviceType] from the open-port set, the mDNS
/// service-type set, and (M1) the optional OUI [vendor] + reverse-DNS
/// [hostname]. Ordered most-specific-first; first match wins.
///
/// Ordering principle (SPIKE-HSD-01, refined after on-device iOS testing): a
/// specific mDNS service type is a much STRONGER identity signal than a lone
/// open port. A bare SSH (22) or bare web (80/443/8080) port is weak —
/// infrastructure and IoT devices routinely expose SSH for management — so
/// those two rules now sit BELOW every mDNS-identity rule. Genuinely strong
/// port fingerprints (printer IPP/LPD/9100, RTSP camera, iOS lockdownd, SMB)
/// keep their high priority.
///
/// M1 — vendor/hostname HINTS (Fing/WiFiman lesson). [vendor] is the OUI-derived
/// manufacturer (desktop only, where the ARP read supplied a MAC); [hostname] is
/// the reverse-DNS / mDNS name. They feed the heuristic ONLY where the match is
/// obvious, and they sit BELOW the strong port/mDNS fingerprints so they never
/// override hard evidence. Two honesty rules (GL-005) bind them:
///   * a networking vendor (Ubiquiti/Cisco/Aruba/…) is shown as the GENERIC
///     `networkGear` unless a Wi-Fi/AP keyword also appears — we never promote a
///     wired switch to "Access point" on the vendor alone;
///   * an UNRECOGNIZED vendor contributes NOTHING — the host stays Unknown
///     rather than inventing a class from a name we don't map.
///
/// Rules (ordered):
///  1. 631 (IPP) or 515 (LPD) or 9100, OR an `_ipp`/`_printer`/
///     `_pdl-datastream` mDNS service, OR an obvious printer vendor/hostname
///     → printer
///  2. 554 (RTSP)       → camera / NVR
///  3. 62078 (iOS lockdownd / "usbmuxd over Wi-Fi") → iOS device
///  4. 445 (SMB)        → Windows / SMB host
///  5. `_sonos` (or `_spotify-connect`) mDNS service → speaker / media.
///     Runs BEFORE the Apple rule because Sonos also advertises `_raop`/AirPlay
///     and would otherwise read as an Apple device.
///  6. `_googlecast` mDNS service → media streamer
///  7. an `_airplay`/`_raop`/`_companion-link` mDNS service → Apple device
///  8. obvious AP/Wi-Fi vendor+keyword → access point  (M1, vendor hint)
///  9. obvious networking vendor → network gear         (M1, vendor hint)
/// 10. 80 or 443 or 8080 → web server / host  (weak — below mDNS + vendor hint)
/// 11. 22 (SSH)         → SSH host            (weak — below mDNS + vendor hint)
/// 12. any mDNS service at all → generic mDNS device
/// 13. otherwise        → unknown
DeviceType inferDeviceType({
  required Set<int> openPorts,
  required Set<String> mdnsServices,
  String? vendor,
  String? hostname,
}) {
  bool hasService(String needle) =>
      mdnsServices.any((String s) => s.toLowerCase().contains(needle));

  // M1 — lower-cased identity text from vendor + hostname, scanned for obvious
  // keywords. A raw-OUI fallback string (e.g. "B8:27:EB") carries no English
  // word, so it never trips a keyword — only a real resolved vendor name does.
  final String vendorLc = (vendor ?? '').toLowerCase();
  final String hostLc = (hostname ?? '').toLowerCase();
  bool vendorOrHostHas(String needle) =>
      vendorLc.contains(needle) || hostLc.contains(needle);

  // 1. Printer — port fingerprint, printing mDNS service, OR an obvious printer
  //    vendor/hostname (M1). The printing-vendor keywords are unambiguous —
  //    a host named "brother-…" or with a "Lexmark"/"Kyocera" OUI is a printer
  //    regardless of which ports it left open.
  if (openPorts.contains(CuratedPorts.ipp) ||
      openPorts.contains(CuratedPorts.lpd) ||
      openPorts.contains(9100) ||
      hasService('_ipp') ||
      hasService('_printer') ||
      hasService('_pdl-datastream') ||
      vendorOrHostHas('lexmark') ||
      vendorOrHostHas('kyocera') ||
      vendorOrHostHas('brother') ||
      vendorOrHostHas('printer')) {
    return DeviceType.printer;
  }

  // 2. Camera / NVR — RTSP.
  if (openPorts.contains(CuratedPorts.rtsp)) {
    return DeviceType.camera;
  }

  // 3. iOS device — lockdownd over Wi-Fi.
  if (openPorts.contains(CuratedPorts.iosLockdown)) {
    return DeviceType.iosDevice;
  }

  // 4. Windows / SMB host — a strong port fingerprint, kept high.
  if (openPorts.contains(CuratedPorts.smb)) {
    return DeviceType.windowsHost;
  }

  // --- mDNS service identity (stronger than a lone SSH/web port) ---

  // 5. Sonos / speaker. MUST precede the Apple rule: Sonos also advertises
  //    `_raop`/AirPlay, so checking it first stops a speaker reading as Apple.
  if (hasService('_sonos') || hasService('_spotify-connect')) {
    return DeviceType.speaker;
  }

  // 6. Media streamer — Google Cast / Chromecast.
  if (hasService('_googlecast')) {
    return DeviceType.mediaStreamer;
  }

  // 7. Apple device — AirPlay / AirTunes / companion-link.
  if (hasService('_airplay') ||
      hasService('_raop') ||
      hasService('_companion-link') ||
      hasService('_airport') ||
      hasService('_sleep-proxy')) {
    return DeviceType.appleDevice;
  }

  // --- M1: vendor-hint rules for networking gear (DESKTOP ONLY) ---
  //
  // Access points / infrastructure broadcast no "I am an access point" mDNS
  // service; the one reliable signal is the OUI vendor from the MAC. The spike
  // could not read a MAC on mobile, so it declined an AP rule. M1 now feeds the
  // desktop OUI vendor in, so we CAN classify networking gear — but honestly:
  //   * promote to `accessPoint` ONLY when a Wi-Fi/AP keyword is present
  //     alongside the networking vendor (a wired switch is not an AP);
  //   * otherwise a recognized networking vendor is the generic `networkGear`.
  // On mobile there is no vendor, so vendorOrHostHas(...) is always false here
  // and a host with only 22/80/443 open still falls through to the weak
  // port rules below — the documented ceiling, unchanged.
  final bool networkingVendor = vendorOrHostHas('ubiquiti') ||
      vendorOrHostHas('mikrotik') ||
      vendorOrHostHas('aruba') ||
      vendorOrHostHas('ruckus') ||
      vendorOrHostHas('netgear') ||
      vendorOrHostHas('tp-link') ||
      vendorOrHostHas('zyxel') ||
      vendorOrHostHas('juniper') ||
      vendorOrHostHas('cisco') ||
      vendorOrHostHas('meraki') ||
      vendorOrHostHas('aerohive') ||
      vendorOrHostHas('extreme networks');

  // 8. Access point — networking vendor AND an explicit Wi-Fi/AP keyword.
  if (networkingVendor &&
      (vendorOrHostHas('access point') ||
          vendorOrHostHas('accesspoint') ||
          vendorOrHostHas('-ap') ||
          vendorOrHostHas('wifi') ||
          vendorOrHostHas('wi-fi') ||
          vendorOrHostHas('wlan') ||
          vendorOrHostHas('unifi') ||
          vendorOrHostHas('meraki'))) {
    return DeviceType.accessPoint;
  }

  // 9. Network gear — a recognized networking vendor with no AP keyword. A
  //    switch, router, gateway, or controller from a networking maker. Generic
  //    on purpose: we name the category we can prove, not a specific model.
  if (networkingVendor) {
    return DeviceType.networkGear;
  }

  // --- Weak single-port rules (only after mDNS identity + vendor hints) ---

  // 10. Web server / host — weak; an open web port alone says little.
  if (openPorts.contains(CuratedPorts.http) ||
      openPorts.contains(CuratedPorts.https) ||
      openPorts.contains(CuratedPorts.httpAlt)) {
    return DeviceType.webServer;
  }

  // 11. SSH host — weakest port signal. Infrastructure and IoT expose 22 for
  //    management, so a lone open 22 only earns this low-priority outcome.
  if (openPorts.contains(CuratedPorts.ssh)) {
    return DeviceType.sshHost;
  }

  // 12. Anything that answered mDNS but matched no rule above.
  if (mdnsServices.isNotEmpty || openPorts.contains(CuratedPorts.mdns)) {
    return DeviceType.mdnsDevice;
  }

  // 13. Live (it had an open port) but unclassifiable. Unknown is first-class:
  //     an unrecognized vendor or a bare hostname never invents a class here.
  return DeviceType.unknown;
}
