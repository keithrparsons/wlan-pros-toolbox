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
  'device-info': <String>[
    'model', 'ram', 'memory', 'uptime', 'cellular ip', 'pdp_ip0', 'hardware',
    'system info', 'about this device', 'iphone model', 'mac model',
    'boot time',
  ],
  'dns-lookup': <String>[
    'nslookup', 'dig', 'resolve', 'a record', 'aaaa', 'mx', 'txt', 'cname',
    'ns', 'soa', 'srv', 'caa', 'spf', 'ptr', 'reverse dns', 'rdns',
    'all records', 'doh', 'name resolution',
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
  'my-current-location': <String>[
    'gps', 'where am i', 'my location', 'current location', 'latitude',
    'longitude', 'altitude', 'coordinates', 'lat long', 'elevation', 'fix',
    'accuracy',
  ],
  'mac-oui-lookup': <String>[
    'vendor', 'manufacturer', 'ieee', 'oui', 'who makes', 'mac vendor',
  ],
  'packet-sender': <String>[
    'raw packet', 'tcp', 'udp', 'payload', 'socket', 'send bytes', 'netcat',
  ],
  'ntp-time': <String>[
    'ntp', 'time', 'clock', 'sntp', 'stratum', 'sync', 'time server',
    'clock offset', 'time.apple.com', 'pool.ntp.org', 'rfc 4330',
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
  'channel-frequency': <String>[
    'channel to frequency', 'frequency to channel', 'center frequency',
    'mhz', 'ghz', 'band edges', 'bonding', 'bonded channel', 'channel width',
    '40 mhz', '80 mhz', '160 mhz', '320 mhz', 'psc', 'dfs', 'unii',
    'channel number', 'wi-fi channels',
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
  'architectural-scale': <String>[
    'scale', 'architect scale', 'engineer scale', 'ratio', 'scale factor',
    'drawing scale', 'plan set', 'floor plan', 'blueprint', 'rcp',
    'measure pdf', 'scale ruler', 'aec', 'cad', 'ekahau scale', 'calibrate',
    '1:48', '1:96', '1/4 inch', '1/8 inch', 'drawn to real', 'metric scale',
  ],
  'link-budget': <String>[
    'received signal', 'fade margin', 'rsl', 'ptp', 'system gain', 'path',
  ],
  'enclosure-ratings': <String>[
    'ip rating', 'ip code', 'ip67', 'ip66', 'ip65', 'ip68', 'ip69k',
    'nema', 'nema 250', 'nema 4x', 'iec 60529', 'ingress protection',
    'waterproof', 'weatherproof', 'dust-tight', 'outdoor ap', 'enclosure',
    'washdown', 'corrosion', 'nema to ip', 'water resistance', 'ingress',
  ],
  'hazardous-locations': <String>[
    'hazardous location', 'classified area', 'class division', 'class 1 div 2',
    'class i div 2', 'nec 500', 'nec 505', 'nec 506', 'zone', 'atex', 'iecex',
    'explosion proof', 'intrinsically safe', 'ex d', 'ex i', 'ex p', 'ex e',
    'flammable', 'combustible dust', 'refinery', 'grain elevator', 'spray booth',
    'ignition', 'purged', 'ul 1203', 'explosive atmosphere',
  ],
  'nec-gotchas': <String>[
    'nec', 'national electrical code', 'code violation', 'hoistway',
    'elevator', 'article 620', 'plenum', 'cmp', 'cmr', 'article 300.22',
    'article 800', 'cable rating', 'poe bundle', 'ampacity', 'article 725.144',
    'grounding', 'bonding', 'article 810', 'firestop', 'article 300.21',
    'abandoned cable', 'article 800.25', 'surge arrestor', 'riser',
  ],
  'safety-basics': <String>[
    'ppe', 'personal protective equipment', 'hard hat', 'safety helmet',
    'z89.1', 'safety-toe', 'steel toe', 'astm f2413', 'hi-vis',
    'high visibility', 'ansi 107', 'eye protection', 'z87', 'esd',
    'static discharge', 's20.20', 'wrist strap', 'asbestos', 'lead paint',
    'arc flash', 'nfpa 70e', 'lockout tagout', 'loto', 'confined space',
    'seismic bracing', 'jobsite safety', 'stop work',
  ],
  'plan-set-literacy': <String>[
    'plan set', 'drawing set', 'sheet number', 'discipline designator',
    'national cad standard', 'architectural', 'reflected ceiling plan', 'rcp',
    'ceiling grid', 'title block', 'keynotes', 'revision cloud', 'north arrow',
    'scale', 'engineer scale', 'telecom sheet', 't sheets', 'a-201',
    'ap placement', 'floor plan', 'construction documents', 'blueprint',
  ],
  'site-access': <String>[
    'site access', 'know before you go', 'mobilization', 'credential',
    'background check', 'orientation', 'escort', 'man-lift', 'boom lift',
    'scissor lift', 'railroad', 'erailsafe', 'flagman', 'hospital', 'icra',
    'ilsm', 'maritime', 'twic', 'over-water', 'warehouse', 'data center',
    'correctional', 'school', 'fingerprinting', 'badging', 'tool control',
  ],
  'wavelength': <String>[
    'lambda', 'antenna length', 'quarter wave', 'frequency to wavelength',
  ],
  'antenna-length': <String>[
    'dipole', 'half wave', 'quarter wave', 'vertical', 'element length',
    'velocity factor', '468', '234', 'ham', 'amateur radio', 'cut antenna',
    'wire antenna', 'resonant length',
  ],
  'maidenhead-grid': <String>[
    'grid square', 'locator', 'qth', 'qra', 'iaru', 'gridsquare', 'ham',
    'amateur radio', 'lat lon', 'latitude longitude', 'grid to coordinates',
    'cm87', 'jo62', 'great circle', 'bearing',
  ],
  // Learn / RF intuition (2026-06-28). Keywords describe what the tool DOES
  // (play tones, octaves, harmonics, intervals) - no aspirational claims (GL-005).
  'hear-frequency': <String>[
    'tone', 'tone generator', 'pitch', 'octave', 'audio', 'sound', 'hear',
    'harmonic', 'harmonics', 'overtone', 'equal temperament', 'piano',
    'keyboard', 'semitone', 'hertz', 'sine', 'square', 'triangle', 'waveform',
    'frequency', 'interval', 'ratio', 'a440', 'middle c', 'note', 'cents',
    'spurious emission', 'timbre', 'rf intuition', 'learn',
  ],
  // Ham Radio band references (2026-06-28).
  'ham-band-plan': <String>[
    'amateur', 'ham', 'band plan', 'fcc', 'part 97', 'license class',
    'technician', 'general', 'amateur extra', 'hf', 'vhf', 'uhf', 'shf',
    '60 meter', '60m', '2200m', '630m', 'privileges', 'power limit', 'pep',
    'erp', 'eirp', '20 meters', '40 meters', 'phone', 'cw', 'ssb',
  ],
  'ham-band-wavelengths': <String>[
    'amateur', 'ham', 'wavelength', 'band name', 'meters', 'centimeters',
    '160m', '80m', '40m', '20m', '2m', '70cm', '13cm', 'lambda', '300/f',
    'frequency to band', 'band to frequency',
  ],
  'band-designations': <String>[
    'itu', 'hf', 'vhf', 'uhf', 'shf', 'high frequency', 'very high frequency',
    'ultra high frequency', 'super high frequency', 'airband', 'aviation',
    'military', 'guard frequency', '121.5', '243.0', 'propagation', 'skip',
    'line of sight', 'frequency band',
  ],
  'part15-part97': <String>[
    'part 15', 'part 97', 'amateur', 'ham', 'aredn', 'broadband hamnet',
    'mesh', '13cm', '5cm', '2.4 ghz', '5 ghz', 'unii', 'ism', 'encryption',
    'station id', 'callsign', 'unlicensed', 'eirp', 'power limit', 'license',
  ],
  'ham-study-resources': <String>[
    'amateur', 'ham', 'study', 'exam', 'hamstudy', 'arrl', 'license manual',
    'technician', 'general', 'amateur extra', 'question pool', 'ncvec',
    'test', 'practice test', 'aredn', 'fcc part 97', 'get licensed',
  ],
  // Ham Radio PDF reference cards (2026-06-28).
  'general-license-frequency-chart': <String>[
    'amateur', 'ham', 'general class', 'frequency chart', 'band chart',
    'privileges', 'hf', 'phone band', 'cw', 'data', '60 meter', '60m',
    'power limit', 'pep', 'erp', 'eirp', 'part 97', 'fcc', 'reference card',
  ],
  'ham-radio-general-exam-study-notes': <String>[
    'amateur', 'ham', 'general exam', 'study notes', 'study guide', 'license',
    'element 3', 'question pool', 'rules', 'operating', 'rf safety', 'antennas',
    'propagation', 'fcc part 97', 'get licensed', 'reference card',
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
  'unit-converter': <String>[
    'convert', 'units', 'mbps to mb/s', 'gigabytes', 'gibibytes', 'bytes',
    'bits', 'watts to dbm', 'celsius fahrenheit', 'data rate', 'storage',
  ],
  'qr-generator': <String>[
    'qr code', 'barcode', 'scan', 'url to qr', 'encode', 'share link',
  ],
  'dtmf-generator': <String>[
    'touch tone', 'dial tone', 'keypad', 'telephone', 'tone generator',
    'phone tones', 'blue box', 'red box', 'mf', 'multi-frequency', '2600',
    'coin tones', 'signaling history',
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
  // 'wifi-channels' keywords removed 2026-06-06 (BF6-13): the tool was deleted as
  // a duplicate of Channel Map. Channel Map's keywords now carry the channel/
  // frequency/HaLow search terms below.
  '80211-standards': <String>[
    'wifi 4', 'wifi 5', 'wifi 6', 'wifi 7', 'ac', 'ax', 'be', 'n', 'be',
    'generations', 'phy',
  ],
  'mcs-index': <String>[
    'modulation', 'coding', 'data rate', 'qam', 'spatial streams', 'phy rate',
    'rate table',
  ],
  'modulation': <String>[
    'constellation', 'bpsk', 'qpsk', 'qam', '16-qam', '64-qam', '256-qam',
    '1024-qam', 'evm', 'error vector magnitude', 'iq plane', 'bits per symbol',
    'symbol', 'snr demand',
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
  'antenna-fundamentals': <String>[
    'antenna', 'gain', 'dbi', 'beamwidth', 'polarization', 'downtilt',
    'radiation pattern', 'omni', 'directional', 'dipole', 'azimuth',
    'elevation', 'polar plot',
  ],
  // Spectrum Analysis teaching module. Keywords describe the TOPICS it teaches
  // (GL-005 keyword honesty) — interference recognition and mitigation — not an
  // analyze capability it does not have (the module states a phone cannot
  // capture RF).
  'spectrum-analysis': <String>[
    'spectrum analysis', 'interference', 'interferer', 'non-wifi interference',
    'rf interference', 'waterfall', 'spectrogram', 'duty cycle', 'rbw', 'fft',
    'microwave interference', 'bluetooth interference', 'zigbee', 'fingerprint',
    'signature', 'noise floor', 'rtsa', 'ekahau sidekick', 'wi-spy', 'oscium',
    'netally', 'metageek', 'rf explorer',
  ],
  'port-reference': <String>[
    'tcp', 'udp', 'iana', 'service port', 'port number', 'well known',
    'common ports',
  ],
  'plmn-id-reference': <String>[
    'plmn', 'mcc', 'mnc', 'mobile country code', 'mobile network code',
    'carrier code', 'cellular', 'imsi', 'hni', 'operator code', 'sim',
  ],
  'wifi-exposure-perspective': <String>[
    'wifi', 'exposure', 'safety', 'radiation', 'sun', 'rf', 'emf', 'health',
    'power', 'icnirp', 'fcc', 'non-ionizing',
  ],
  'optical-transceivers': <String>[
    'sfp', 'sfp+', 'qsfp', 'qsfp28', 'qsfp-dd', 'osfp', 'transceiver', 'optic',
    'optics', 'fiber', 'fibre', 'singlemode', 'multimode', 'smf', 'mmf',
    'wavelength', 'reach', 'sr', 'lr', 'er', 'zr', '10gbase', '100gbase',
    '400gbase', 'mpo', 'lc connector', 'gbic', 'pluggable',
  ],
  'wifi-tools-comparison': <String>[
    'tools', 'comparison', 'survey', 'planner', 'spectrum', 'ekahau', 'hamina',
    'netally', 'intuitibits', 'oscium', 'vendor', 'tco', 'cost',
  ],
  'reason-codes': <String>[
    'deauth', 'disassoc', 'status code', '802.11 codes', 'disconnect reason',
  ],
  'http-status-codes': <String>[
    'http', 'status code', 'response code', '404', '403', '500', '301', '302',
    '503', 'captive portal', 'redirect', 'client error', 'server error',
    'web error',
  ],
  'frame-exchange': <String>[
    'association', 'association sequence', 'handshake', '4-way', 'auth',
    'probe', 'beacon', 'frame sequence', 'frame exchange', 'management frames',
  ],
  'db-reference': <String>[
    'decibel', 'ratio', 'rule of 3', 'rule of 10', 'log', 'dbm anchors',
  ],
  'channel-map': <String>[
    'bonding', '40', '80', '160 mhz', 'channel width', '5 ghz', '6 ghz',
    'overlap',
    // Folded in from the removed Wi-Fi Channels table (BF6-13) so those search
    // terms still land on the survivor.
    'frequency', 'dfs', '2.4', 'channel plan', 'non overlapping',
    'center frequency', 'halow', '802.11ah', 'sub-1 ghz', '900 mhz',
  ],
  'spectrum': <String>[
    'band plan', 'unii', 'ism', 'sub band', 'allocation', 'coexistence',
    'frequency plan',
  ],
  'coax-cable': <String>[
    'rg6', 'rg58', 'lmr', 'impedance', 'velocity factor', 'feedline',
  ],
  // ethernet-pinout + cable-connector keyword sets folded in here 2026-06-12
  // when the three tiles consolidated into this one (pinout, T568A/B, wiring,
  // crossover, PoE terms added so searches for the old tiles land here).
  'ethernet-cable': <String>[
    'cat5e', 'cat6', 'cat6a', 'cat7', 'cat8', 'rj45', 'bandwidth', 'distance',
    'twisted pair', 'connector', 't568a', 't568b', 'pinout', 'wiring',
    'crossover', 'poe', 'cat cable',
  ],
  'fiber-optic': <String>[
    'singlemode', 'multimode', 'om3', 'om4', 'os2', 'sfp', 'jacket color',
    'optical',
  ],
  // 'rf-connectors' MERGED into 'antenna-connectors' 2026-06-06 (BF6-18). Its
  // search terms are folded into the antenna-connectors keyword set below.
  'antenna-connectors': <String>[
    'sma', 'rp-sma', 'n type', 'n connector', 'tnc', 'rp-tnc', 'pigtail',
    'antenna connector', 'rf connector', 'impedance', 'dart', 'u.fl', 'ufl',
    'coupling', 'mating', 'coaxial connector',
  ],
  'osi-model': <String>[
    '7 layers', 'layer 2', 'layer 3', 'tcp ip', 'pdu', 'encapsulation',
    'networking model',
  ],
  'top-level-domains': <String>[
    'tld', 'gtld', 'cctld', 'domain', '.com', '.org', '.io', '.ai', 'dns root',
    'iana', 'sponsored domain', 'new gtld',
  ],
  'rj-connectors': <String>[
    'rj11', 'rj14', 'rj25', 'rj45', 'rj48', '8p8c', '6p2c', 'modular plug',
    'registered jack', 'phone connector', 'positions conductors',
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

  // ── Apple Wi-Fi references ──
  'apple-wifi-tips': <String>[
    'apple', 'iphone', 'ipad', 'ios', 'recommended settings', 'router',
    'wireless diagnostics', 'support', 'macbook', 'reset network settings',
  ],
  'macos-menubar-wifi': <String>[
    'macos', 'mac', 'menu bar', 'option click', 'wdutil', 'airport',
    'rssi', 'noise', 'snr', 'bssid', 'wireless diagnostics', 'sudo',
  ],

  // ── Tier-1 references (Pass 2b, 2026-06-12) ──
  'keyboard-shortcuts': <String>[
    'hotkeys', 'shortcut', 'cmd', 'ctrl', 'terminal', 'powershell', 'zsh',
    'option key', 'special characters', 'greek letters', 'symbols', 'lambda',
  ],
  'time-zone-maps': <String>[
    'utc', 'gmt', 'offset', 'time difference', 'world clock', 'dst',
    'daylight saving', 'est', 'pst', 'timezone',
  ],
  'phonetic-alphabet': <String>[
    'nato', 'icao', 'alfa', 'bravo', 'spelling', 'morse code', 'semaphore',
    'signal flags', 'maritime', 'radio',
  ],
  'diffie-hellman': <String>[
    'dh', 'key exchange', 'paint mixing', 'shared secret', 'sae', 'dragonfly',
    'wpa3', 'discrete log', 'crypto', 'cryptography', 'modular exponentiation',
  ],

  // ── Tier-1 references (integration batch, 2026-06-12) ──
  'rf-bands': <String>[
    'frequency', 'spectrum', 'ism', 'lora', 'zigbee', 'z-wave', 'thread',
    'rfid', 'nfc', 'gps', 'gnss', 'cellular', '5g', 'sub-ghz', '900 mhz',
    'band plan', 'wigig', '60 ghz',
  ],
  'wifi-halow': <String>[
    '802.11ah', 'halow', 's1g', 'sub-ghz', 'sub-1 ghz', 'iot', 'long range',
    'morse micro', '900 mhz', 'low power', 'twt', 'mcs', 'lpwan',
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
  'dual-orb-wlanpi': <String>[
    'orb', 'orb.net', 'sensor', 'wlanpi', 'wlan pi', 'r4', 'm4',
    'speed test', 'monitoring', 'deb', 'ferney munoz',
  ],
};
