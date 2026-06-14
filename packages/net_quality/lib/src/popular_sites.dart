/// A well-known cloud service the toolbox can probe for reachability.
class PopularSite {
  /// Display name (the recognizable cloud-app / service name).
  final String name;

  /// Hostname to connect to.
  final String host;

  /// Port to connect to. Defaults to 443 (HTTPS).
  final int port;

  /// Creates a cloud-service endpoint.
  const PopularSite({
    required this.name,
    required this.host,
    this.port = 443,
  });

  @override
  String toString() => 'PopularSite($name, $host:$port)';
}

/// A curated list of recognizable, high-availability CLOUD-APP endpoints for
/// reachability checks.
///
/// Recurated 2026-06-13 (Felix, per Pax's gap brief) from the prior web/DNS mix
/// toward the consumer-app framing a non-technical user recognizes — "can my
/// device reach Google / iCloud / Microsoft 365 / Zoom / Slack / YouTube /
/// Netflix?" Every host was verified reachable on TCP 443 at recuration time and
/// is a long-lived, globally anycast/CDN-fronted edge, so a probe failure points
/// at the user's connection, not a flaky destination.
///
/// HONESTY (GL-005): a TCP-connect to e.g. `slack.com:443` proves the service
/// EDGE is reachable and times that hop. It is NOT a measure of in-app call /
/// stream quality. The UI caption says exactly that.
const List<PopularSite> kCloudApps = <PopularSite>[
  // Core platforms.
  PopularSite(name: 'Google', host: 'www.google.com'),
  PopularSite(name: 'iCloud', host: 'www.icloud.com'),
  PopularSite(name: 'Microsoft 365', host: 'www.office.com'),
  PopularSite(name: 'Cloudflare', host: 'www.cloudflare.com'),
  PopularSite(name: 'Amazon AWS', host: 'aws.amazon.com'),

  // Communication / collaboration.
  PopularSite(name: 'Zoom', host: 'zoom.us'),
  PopularSite(name: 'Slack', host: 'slack.com'),

  // Streaming / content.
  PopularSite(name: 'YouTube', host: 'www.youtube.com'),
  PopularSite(name: 'Netflix', host: 'www.netflix.com'),

  // Developer / platform health.
  PopularSite(name: 'GitHub', host: 'github.com'),

  // Public DNS resolver (a fast, stable liveness anchor).
  PopularSite(name: 'Cloudflare DNS', host: 'one.one.one.one'),
];

/// Backwards-compatible alias. The default reachability target list is now the
/// recurated cloud-app set; existing call sites and tests that referenced
/// `kPopularSites` keep resolving to the same (curated) list without churn.
const List<PopularSite> kPopularSites = kCloudApps;
