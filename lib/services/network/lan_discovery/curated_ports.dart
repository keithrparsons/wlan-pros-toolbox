// Curated TCP port set for the connect-scan — Network Discovery (TICKET-HSD-02).
//
// The connect-scan is the SPINE (brief anti-pattern #1: do NOT build on an ICMP
// ping sweep — raw ICMP sockets are privileged on both mobile OSes). Each port
// here doubles as liveness evidence AND a device-type fingerprint signal.
//
// The set is deliberately small — a full 65k scan per host across a /24 would
// be far too slow and noisy for discovery. These are the ports that most often
// answer on a LAN and that the device-type heuristic keys off.

/// The curated TCP ports the spike connect-scan probes per host.
class CuratedPorts {
  CuratedPorts._();

  static const int ssh = 22; // SSH host
  static const int http = 80; // web server / host
  static const int https = 443; // web server / host (also routers, APs)
  static const int smb = 445; // Windows / SMB host
  static const int lpd = 515; // printer (LPD)
  static const int rtsp = 554; // camera / NVR (RTSP)
  static const int ipp = 631; // printer (IPP)
  static const int mdns = 5353; // mDNS responder (UDP normally; TCP probe weak)
  static const int httpAlt = 8080; // web server / host (alt HTTP)
  static const int iosLockdown = 62078; // iOS lockdownd over Wi-Fi

  /// The full curated set, in ascending order, as specified by the ticket.
  static const List<int> all = <int>[
    ssh,
    http,
    https,
    smb,
    lpd,
    rtsp,
    ipp,
    mdns,
    httpAlt,
    iosLockdown,
  ];
}
