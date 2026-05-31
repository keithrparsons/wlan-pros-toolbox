/// A well-known host the toolbox can probe for reachability.
class PopularSite {
  /// Display name.
  final String name;

  /// Hostname to connect to.
  final String host;

  /// Port to connect to. Defaults to 443 (HTTPS).
  final int port;

  /// Creates a popular site.
  const PopularSite({
    required this.name,
    required this.host,
    this.port = 443,
  });

  @override
  String toString() => 'PopularSite($name, $host:$port)';
}

/// A curated list of stable, globally reachable hosts for reachability checks.
///
/// These are long-lived, high-availability endpoints chosen so a probe failure
/// points at the user's connection, not at a flaky destination.
const List<PopularSite> kPopularSites = <PopularSite>[
  // Major web destinations.
  PopularSite(name: 'Google', host: 'www.google.com'),
  PopularSite(name: 'YouTube', host: 'www.youtube.com'),
  PopularSite(name: 'Facebook', host: 'www.facebook.com'),
  PopularSite(name: 'Amazon', host: 'www.amazon.com'),
  PopularSite(name: 'Apple', host: 'www.apple.com'),
  PopularSite(name: 'Microsoft', host: 'www.microsoft.com'),
  PopularSite(name: 'Netflix', host: 'www.netflix.com'),

  // Public DNS resolvers (good liveness signals, low latency).
  PopularSite(name: 'Cloudflare', host: 'one.one.one.one'),
  PopularSite(name: 'Cloudflare DNS', host: '1.1.1.1'),
  PopularSite(name: 'Google DNS', host: '8.8.8.8'),

  // CDNs (proxy for general content delivery health).
  PopularSite(name: 'Cloudflare CDN', host: 'cdnjs.cloudflare.com'),
  PopularSite(name: 'Akamai', host: 'www.akamai.com'),
];
