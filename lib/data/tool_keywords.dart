// Search keyword vocabulary — one Keith-reviewable map, keyed by tool id.
//
// THIS FILE IS THE SEARCH VOCABULARY. It is deliberately separate from the
// catalog (lib/data/tool_catalog.dart) so the terms can be iterated without
// touching the catalog structure. The catalog builder folds these into each
// ToolEntry.keywords at startup; the search engine (lib/data/tool_search.dart)
// matches against title + description + these keywords.
//
// What belongs here: the synonyms, abbreviations, and domain terms a junior
// Wi-Fi engineer would TYPE to find a tool that are NOT already in its title or
// description (matching the title/description is already covered — no need to
// repeat those words here). Think "what would someone type who doesn't know our
// exact tool name?":
//   - abbreviations / expansions (fspl ↔ "free space path loss", "path loss")
//   - the problem the tool solves ("slow", "is it my wifi")
//   - alternate names for the same concept ("oui" ↔ "vendor", "manufacturer")
//
// RULES:
//   * Keywords describe what a tool ACTUALLY does — never aspirational
//     capability (GL-005). Do not add "spectrum analyzer" to a tool that does
//     not analyze spectrum.
//   * Lowercase; the search is case-insensitive (it lower-cases both sides).
//   * 3–6 terms is the target. More is fine where the domain genuinely has many
//     synonyms; do not pad.
//   * A tool id absent from this map simply has no extra keywords (search still
//     matches its title + description). Adding a key here is the only step to
//     enrich a tool's discoverability.
//
// FIRST-PASS BACKFILL (Felix, 2026-06-03) — domain judgment, KEITH-REVIEWABLE.
// Keith can edit any list here without recompiling anything else.

/// Tool id → extra search keywords. See file header for the contract.
const Map<String, List<String>> kToolKeywords = <String, List<String>>{
  // ───────────────────────── Test Network ────────────────────────
  // Wave 4 (2026-06-04): `test-my-connection` and `wifi-vs-internet` merged into
  // one tool reached via the home hero card. Both were removed from the catalog
  // (not tiled, not searchable per Keith), so their keyword entries are gone too
  // — a keyword fold only reads ids that exist in the catalog.
  'net-quality': <String>[
    'speed test', 'bufferbloat', 'responsiveness', 'lag', 'ping',
    'packet loss', 'quality',
  ],
  'wifi-info': <String>[
    'rssi', 'bssid', 'ssid', 'snr', 'noise', 'phy', 'mcs', 'link rate',
    'signal', 'connected ap', 'wlan',
  ],
  'cellular-info': <String>[
    'lte', '5g', 'carrier', 'signal bars', 'mobile', 'sim', 'roaming',
  ],

  // ──────────────────────── Networking Tools ─────────────────────
  'interface-info': <String>[
    'ip address', 'gateway', 'dns', 'nic', 'adapter', 'my ip', 'local ip',
    'default gateway',
  ],
  'dns-lookup': <String>[
    'nslookup', 'dig', 'resolve', 'a record', 'mx', 'txt', 'cname', 'ptr',
    'doh', 'name resolution',
  ],
  'port-scan': <String>[
    'nmap', 'open ports', 'tcp', 'service scan', 'firewall', 'listening',
  ],
  'ping': <String>[
    'latency', 'rtt', 'reachability', 'round trip', 'connectivity', 'tcp',
  ],
  'icmp-ping': <String>[
    'latency', 'rtt', 'echo', 'round trip', 'packet loss', 'real ping',
  ],
  'ping-plotter': <String>[
    'latency graph', 'latency trend', 'rtt over time', 'jitter', 'live graph',
    'performance graph', 'continuous ping', 'monitor', 'chart', 'packet loss',
    'pingplotter',
  ],
  'ping-sweep': <String>[
    'host discovery', 'scan subnet', 'live hosts', 'who is on my network',
    'lan scan',
  ],
  'network-discovery': <String>[
    'lan scan', 'mdns', 'bonjour', 'service discovery', 'devices on network',
    'who is on my network', 'arp', 'host discovery',
  ],
  'traceroute': <String>[
    'tracert', 'hops', 'path', 'route', 'where does traffic go',
  ],
  'mobile-traceroute': <String>[
    'tracert', 'hops', 'ttl', 'path', 'route',
  ],
  'ssl-inspect': <String>[
    'certificate', 'cert', 'tls', 'https', 'x509', 'expiry', 'san',
    'fingerprint', 'chain',
  ],
  'http-headers': <String>[
    'curl', 'response headers', 'redirect', 'status code', 'cache-control',
    'cors', 'web',
  ],
  'whois': <String>[
    'domain owner', 'registrar', 'registration', 'ip owner', 'rdap',
  ],
  'wake-on-lan': <String>[
    'wol', 'magic packet', 'power on', 'remote wake', 'boot',
  ],
  'arp-ndp': <String>[
    'arp table', 'neighbor', 'mac address', 'ipv6 neighbor', 'cache',
  ],
  'bgp-asn': <String>[
    'autonomous system', 'as number', 'prefix', 'peering', 'ripestat',
    'routing',
  ],
  'ip-geo': <String>[
    'geolocation', 'where is this ip', 'location', 'country', 'isp lookup',
    'maxmind',
  ],
  'mac-oui-lookup': <String>[
    'vendor', 'manufacturer', 'ieee', 'oui', 'who makes', 'mac vendor',
  ],
  'packet-sender': <String>[
    'raw packet', 'tcp', 'udp', 'payload', 'socket', 'send bytes', 'netcat',
  ],
  'ipv4-subnet': <String>[
    'cidr', 'netmask', 'subnet mask', 'vlsm', 'wildcard', 'broadcast',
    'host range', 'subnetting',
  ],
  'ipv6-subnet': <String>[
    'cidr', 'prefix', 'expand address', 'subnetting', 'address count',
  ],

  // ─────────────────────── Calculators & Tools ───────────────────
  'dbm-watt-converter': <String>[
    'milliwatt', 'mw', 'power conversion', 'eirp units', 'log scale',
    'dbm to watts',
  ],
  'fspl': <String>[
    'free space path loss', 'path loss', 'attenuation', 'distance loss',
    'propagation', 'range',
  ],
  'eirp': <String>[
    'effective isotropic radiated power', 'tx power', 'antenna gain',
    'regulatory', 'power limit',
  ],
  'fresnel': <String>[
    'clearance', 'line of sight', 'los', 'obstruction', 'zone', 'ptp',
    'bridge',
  ],
  'cable-loss': <String>[
    'coax loss', 'feedline', 'attenuation', 'insertion loss', 'db loss',
  ],
  'link-budget': <String>[
    'received signal', 'fade margin', 'rsl', 'ptp', 'system gain', 'path',
  ],
  'wavelength': <String>[
    'lambda', 'antenna length', 'quarter wave', 'frequency to wavelength',
  ],
  'downtilt': <String>[
    'tilt angle', 'antenna aim', 'mechanical tilt', 'coverage angle',
  ],
  'earth-curvature': <String>[
    'bulge', 'k factor', 'line of sight', 'long path', 'horizon',
  ],
  'rain-fade': <String>[
    'rain attenuation', 'itu', 'weather', 'microwave', 'availability',
    'mmwave',
  ],
  'downtilt-coverage': <String>[
    'coverage radius', 'beamwidth', 'footprint', 'cell edge', 'aim',
  ],
  'metric-conversion': <String>[
    'unit converter', 'feet to meters', 'miles', 'km', 'nautical', 'length',
  ],
  'noise-floor': <String>[
    'thermal noise', 'noise figure', 'sensitivity', 'snr', 'kt b',
    'channel width',
  ],
  'rf-attenuation': <String>[
    'wall loss', 'material loss', 'penetration', 'building', 'obstruction',
    'drywall', 'concrete',
  ],
  'lat-long': <String>[
    'coordinates', 'gps', 'decimal degrees', 'dms', 'degrees minutes seconds',
    'convert coordinates',
  ],
  'dist-bearing': <String>[
    'haversine', 'great circle', 'azimuth', 'heading', 'gps distance',
    'how far',
  ],
  'midpoint': <String>[
    'halfway', 'center point', 'gps', 'between two points', 'great circle',
  ],
  'final-point': <String>[
    'destination', 'projection', 'gps', 'dead reckoning', 'from bearing',
  ],
  'hex-ascii': <String>[
    'decimal', 'binary', 'base converter', 'number base', 'hexadecimal',
    'char code',
  ],
  'poe-budget': <String>[
    'power over ethernet', 'watts', 'switch budget', 'pse', 'pd', '802.3bt',
    'power draw',
  ],
  'throughput-calc': <String>[
    'data rate', 'phy rate', 'mcs', 'goodput', 'speed estimate', 'capacity',
  ],
  'capacity-planner': <String>[
    'ap count', 'how many aps', 'density', 'users per ap', 'airtime',
    'design',
  ],
  'ptp-link': <String>[
    'point to point', 'bridge', 'backhaul', 'fade margin', 'link budget',
    'wireless bridge',
  ],

  // ──────────────────────── Quick Reference ──────────────────────
  'poe-reference': <String>[
    'power over ethernet', '802.3af', '802.3at', '802.3bt', 'wattage',
    'class', 'pse pd',
  ],
  'wifi-channels': <String>[
    'frequency', 'dfs', '2.4', '5', '6 ghz', 'channel plan', 'non overlapping',
    'center frequency',
  ],
  '80211-standards': <String>[
    'wifi 4', 'wifi 5', 'wifi 6', 'wifi 7', 'ac', 'ax', 'be', 'n', 'be',
    'generations', 'phy',
  ],
  'mcs-index': <String>[
    'modulation', 'coding', 'data rate', 'qam', 'spatial streams', 'phy rate',
    'rate table',
  ],
  'signal-thresholds': <String>[
    'rssi', 'snr', 'how strong', 'good signal', 'dbm targets', 'minimum signal',
    'coverage',
  ],
  'wpa-security': <String>[
    'wpa2', 'wpa3', 'encryption', 'psk', 'sae', 'enterprise', '802.1x',
    'security matrix',
  ],
  'roaming': <String>[
    '802.11r', '802.11k', '802.11v', 'fast transition', 'ft', 'sticky client',
    'handoff', 'thresholds',
  ],
  'ap-placement': <String>[
    'mounting', 'spacing', 'cell overlap', 'where to put aps', 'ceiling',
    'design', 'survey',
  ],
  'port-reference': <String>[
    'tcp', 'udp', 'iana', 'service port', 'port number', 'well known',
    'common ports',
  ],
  'reason-codes': <String>[
    'deauth', 'disassoc', 'status code', '802.11 codes', 'disconnect reason',
  ],
  'frame-exchange': <String>[
    'association', 'handshake', '4-way', 'auth', 'probe', 'beacon',
    'frame sequence', 'management frames',
  ],
  'db-reference': <String>[
    'decibel', 'ratio', 'rule of 3', 'rule of 10', 'log', 'dbm anchors',
  ],
  'channel-map': <String>[
    'bonding', '40', '80', '160 mhz', 'channel width', '5 ghz', '6 ghz',
    'overlap',
  ],
  'spectrum': <String>[
    'band plan', 'unii', 'ism', 'sub band', 'allocation', 'coexistence',
    'frequency plan',
  ],
  'ethernet-pinout': <String>[
    't568a', 't568b', 'rj45', 'wiring', 'crossover', 'pinout', 'cat cable',
  ],
  'coax-cable': <String>[
    'rg6', 'rg58', 'lmr', 'impedance', 'velocity factor', 'feedline',
  ],
  'ethernet-cable': <String>[
    'cat5e', 'cat6', 'cat6a', 'cat8', 'rj45', 'bandwidth', 'distance',
    'twisted pair',
  ],
  'fiber-optic': <String>[
    'singlemode', 'multimode', 'om3', 'om4', 'os2', 'sfp', 'jacket color',
    'optical',
  ],
  'rf-connectors': <String>[
    'sma', 'rp-sma', 'n type', 'tnc', 'pigtail', 'antenna connector',
    'impedance',
  ],
  'osi-model': <String>[
    '7 layers', 'layer 2', 'layer 3', 'tcp ip', 'pdu', 'encapsulation',
    'networking model',
  ],
  'ascii-reference': <String>[
    'character codes', 'hex', 'binary', 'octal', 'control codes', 'char table',
  ],
  'emoji-reference': <String>[
    'emoticons', 'symbols', 'unicode', 'smiley',
  ],

  // ── PDF reference cards (interim Reference Cards section) ──
  'bubble-diagram': <String>[
    'design', 'decision', 'coverage', 'laminated card', 'workflow', 'planning',
  ],
  'troubleshooting-causes': <String>[
    'root cause', 'problems', 'debug', 'laminated card', 'common issues',
  ],
  'channel-allocations-24ghz': <String>[
    '2.4', '1 6 11', 'channel plan', 'laminated card', 'non overlapping',
  ],
  'channel-allocations-5ghz': <String>[
    '5', 'unii', 'dfs', 'channel plan', 'laminated card', 'bonding',
  ],
  'channel-allocations-6ghz': <String>[
    '6e', 'unii-5', 'unii-8', 'psc', 'channel plan', 'laminated card',
  ],
  'mcs-index-card': <String>[
    'modulation', 'coding', 'data rate', 'qam', 'laminated card', 'rate table',
  ],
  'top-20-checklist': <String>[
    'design checklist', 'best practices', 'laminated card', 'survey',
    'validation',
  ],
  'extended-checklist': <String>[
    'design checklist', 'validation', 'laminated card', 'full checklist',
  ],
  'extended-checklist-nonadvertised': <String>[
    'hidden', 'design checklist', 'laminated card', 'validation', 'advanced',
  ],
  'connection-checklist': <String>[
    'association', 'client', 'laminated card', 'connect sequence',
    'troubleshoot',
  ],

  // ── CLI & Capture sheets ──
  'cli-commands': <String>[
    'ipconfig', 'ifconfig', 'netsh', 'terminal', 'command line', 'windows',
    'macos', 'cheat sheet',
  ],
  'linux-wlan-commands': <String>[
    'iw', 'iwconfig', 'monitor mode', 'airmon', 'terminal', 'cheat sheet',
    'wireless',
  ],
  'wireshark-80211-filters': <String>[
    'display filter', 'capture filter', 'pcap', 'packet capture', 'tshark',
    'sniffer', 'wlan filter',
  ],

  // ── Interactive checklists ──
  'checklist-ap-install': <String>[
    'install', 'deployment', 'pre check', 'post check', 'mounting',
    'best practices',
  ],
  'checklist-client-test': <String>[
    'connectivity test', 'client side', 'validation', 'roaming test',
    'troubleshoot',
  ],
};
