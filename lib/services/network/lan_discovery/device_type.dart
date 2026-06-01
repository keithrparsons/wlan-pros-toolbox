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
  webServer('Web server / host'),
  sshHost('SSH host'),
  mdnsDevice('mDNS device'),
  unknown('Unknown');

  const DeviceType(this.label);

  /// Human-readable label for the debug list.
  final String label;
}

/// Pure heuristic: infer a [DeviceType] from the open-port set and the mDNS
/// service-type set. Ordered most-specific-first; first match wins.
///
/// Ordering principle (SPIKE-HSD-01, refined after on-device iOS testing): a
/// specific mDNS service type is a much STRONGER identity signal than a lone
/// open port. A bare SSH (22) or bare web (80/443/8080) port is weak —
/// infrastructure and IoT devices routinely expose SSH for management — so
/// those two rules now sit BELOW every mDNS-identity rule. Genuinely strong
/// port fingerprints (printer IPP/LPD/9100, RTSP camera, iOS lockdownd, SMB)
/// keep their high priority.
///
/// Rules (ordered):
///  1. 631 (IPP) or 515 (LPD) or 9100, OR an `_ipp`/`_printer`/
///     `_pdl-datastream` mDNS service → printer
///  2. 554 (RTSP)       → camera / NVR
///  3. 62078 (iOS lockdownd / "usbmuxd over Wi-Fi") → iOS device
///  4. 445 (SMB)        → Windows / SMB host
///  5. `_sonos` (or `_spotify-connect`) mDNS service → speaker / media.
///     Runs BEFORE the Apple rule because Sonos also advertises `_raop`/AirPlay
///     and would otherwise read as an Apple device.
///  6. `_googlecast` mDNS service → media streamer
///  7. an `_airplay`/`_raop`/`_companion-link` mDNS service → Apple device
///  8. 80 or 443 or 8080 → web server / host  (weak — below mDNS identity)
///  9. 22 (SSH)         → SSH host            (weak — below mDNS identity)
/// 10. any mDNS service at all → generic mDNS device
/// 11. otherwise        → unknown
DeviceType inferDeviceType({
  required Set<int> openPorts,
  required Set<String> mdnsServices,
}) {
  bool hasService(String needle) =>
      mdnsServices.any((String s) => s.toLowerCase().contains(needle));

  // 1. Printer — port fingerprint or printing mDNS service.
  if (openPorts.contains(CuratedPorts.ipp) ||
      openPorts.contains(CuratedPorts.lpd) ||
      openPorts.contains(9100) ||
      hasService('_ipp') ||
      hasService('_printer') ||
      hasService('_pdl-datastream')) {
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

  // --- Weak single-port rules (only after mDNS identity has had its say) ---
  //
  // Access points / infrastructure: NOTE — most access points broadcast no
  // "I am an access point" mDNS service, and the one reliable signal is the
  // OUI vendor from the MAC address, which a sandboxed mobile app cannot read
  // (desktop-only per the spike brief). So we deliberately do NOT fake an
  // access-point rule here. On mobile, an access point with only 22/80/443
  // open correctly falls through to sshHost / webServer / unknown below. That
  // is a documented ceiling, not a bug to paper over.

  // 8. Web server / host — weak; an open web port alone says little.
  if (openPorts.contains(CuratedPorts.http) ||
      openPorts.contains(CuratedPorts.https) ||
      openPorts.contains(CuratedPorts.httpAlt)) {
    return DeviceType.webServer;
  }

  // 9. SSH host — weakest port signal. Infrastructure and IoT expose 22 for
  //    management, so a lone open 22 only earns this low-priority outcome.
  if (openPorts.contains(CuratedPorts.ssh)) {
    return DeviceType.sshHost;
  }

  // 10. Anything that answered mDNS but matched no rule above.
  if (mdnsServices.isNotEmpty || openPorts.contains(CuratedPorts.mdns)) {
    return DeviceType.mdnsDevice;
  }

  // 11. Live (it had an open port) but unclassifiable.
  return DeviceType.unknown;
}
