// SPIKE-HSD-01 — heuristic device-type inference (THROWAWAY spike).
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
/// Rules (ordered):
///  1. 631 (IPP) or 515 (LPD) or 9100, OR an `_ipp`/`_pdl-datastream` mDNS
///     service          → printer
///  2. 554 (RTSP)       → camera / NVR
///  3. 62078 (iOS lockdownd / "usbmuxd over Wi-Fi") → iOS device
///  4. an `_airplay`/`_raop`/`_companion-link` mDNS service → Apple device
///  5. 445 (SMB)        → Windows / SMB host
///  6. 80 or 443 or 8080 → web server / host
///  7. 22 (SSH)         → SSH host
///  8. any mDNS service at all → generic mDNS device
///  9. otherwise        → unknown
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

  // 4. Apple device — AirPlay / AirTunes / companion-link.
  if (hasService('_airplay') ||
      hasService('_raop') ||
      hasService('_companion-link') ||
      hasService('_airport') ||
      hasService('_sleep-proxy')) {
    return DeviceType.appleDevice;
  }

  // 5. Windows / SMB host.
  if (openPorts.contains(CuratedPorts.smb)) {
    return DeviceType.windowsHost;
  }

  // 6. Web server / host.
  if (openPorts.contains(CuratedPorts.http) ||
      openPorts.contains(CuratedPorts.https) ||
      openPorts.contains(CuratedPorts.httpAlt)) {
    return DeviceType.webServer;
  }

  // 7. SSH host.
  if (openPorts.contains(CuratedPorts.ssh)) {
    return DeviceType.sshHost;
  }

  // 8. Anything that answered mDNS but matched no port rule.
  if (mdnsServices.isNotEmpty || openPorts.contains(CuratedPorts.mdns)) {
    return DeviceType.mdnsDevice;
  }

  // 9. Live (it had an open port) but unclassifiable.
  return DeviceType.unknown;
}
