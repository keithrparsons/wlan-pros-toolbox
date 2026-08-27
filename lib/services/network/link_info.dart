// LinkInfo — one network interface described by what it IS, not what it is named.
//
// WHY THIS EXISTS ALONGSIDE NetworkInterfaceInfo. Dart's `NetworkInterface.list()`
// hands us a name and some addresses and nothing else, so
// `InterfaceInfoService.classifyInterface` has to guess from the name: `en0` is
// Wi-Fi, every other `en*` is Ethernet, anything starting `wl` is Wi-Fi. That is
// a macOS-shaped guess. It is wrong on Linux in a way that matters: on a WLAN Pi
// it labels `wlanpi0` and `wlanpi1` as Wi-Fi connections when they are radiotap
// MONITOR interfaces, so capture interfaces appear in a list of networks the user
// could be "on". Measured on wlanpi-a02, 2026-08-27.
//
// It also cannot answer the question a wired user actually has. On that same Pi,
// `eth0` and `wlan0` are BOTH up with addresses in 192.168.8.0/24 and the default
// route goes out `eth0`. Addressing alone cannot say which link carries traffic.
//
// So where a backend can tell us the truth, we take the truth. [LinkInfo] is that
// answer: kind, carrier, negotiated speed, driver, bus, and whether this
// interface holds the default route. The name heuristic stays exactly where it is
// as the fallback for platforms that give us nothing better.
//
// NOTHING HERE IS INFERRED CLIENT-SIDE. Every field is reported by the source or
// is null. A speed we were not told is absent, never 0 and never -1: the Pi's
// `pan0` reports -1 in sysfs, which is a sentinel meaning "unknown", and a UI
// that trusts the number renders "-1 Mbps".

/// What an interface actually is, as reported by a source that can tell.
///
/// Distinct from `InterfaceKind`, which is the name-guessed enum. This one adds
/// the two cases a name cannot express and which caused real misclassification:
/// [monitor] and [virtual].
enum LinkKind {
  /// A physical wired port.
  wired,

  /// A managed Wi-Fi station interface.
  wifi,

  /// A radiotap capture interface. NOT a link a user can be on, and never to be
  /// offered as one.
  monitor,

  /// A bridge, bond, VLAN, tunnel or other software interface. The WLAN Pi's
  /// `pan0` (Bluetooth PAN) is one: ARPHRD type 1 with no `wireless/` directory,
  /// so a type-based rule calls it wired. It has no cable and no driver.
  virtual,

  /// Loopback.
  loopback,

  /// Reported by the source but not a kind this app models.
  other,
}

LinkKind linkKindFromString(String? raw) => switch (raw?.toLowerCase()) {
      'wired' => LinkKind.wired,
      'wifi' => LinkKind.wifi,
      'monitor' => LinkKind.monitor,
      'virtual' => LinkKind.virtual,
      'loopback' => LinkKind.loopback,
      _ => LinkKind.other,
    };

/// One address bound to a link.
class LinkAddress {
  const LinkAddress({
    required this.address,
    required this.isIPv4,
    this.prefixLength,
    this.isLinkLocal = false,
    this.isDynamic = false,
  });

  final String address;
  final bool isIPv4;
  final int? prefixLength;

  /// 169.254.0.0/16 or fe80::/10.
  ///
  /// AN IPv4 LINK-LOCAL ADDRESS IS A FINDING, NOT AN ADDRESS. It means the link
  /// came up and DHCP never answered, which is one of the most common wired
  /// faults there is. A screen that prints it under "Your IP address" has turned
  /// a diagnosis into a reassurance.
  final bool isLinkLocal;

  /// Assigned by DHCP rather than statically configured, where the source says.
  final bool isDynamic;
}

/// One interface, described by what it is.
class LinkInfo {
  const LinkInfo({
    required this.name,
    required this.kind,
    this.operState,
    this.carrier,
    this.speedMbps,
    this.duplex,
    this.mtu,
    this.mac,
    this.driver,
    this.bus,
    this.isDefaultRouteV4 = false,
    this.isDefaultRouteV6 = false,
    this.addresses = const <LinkAddress>[],
  });

  final String name;
  final LinkKind kind;

  /// The kernel's own word: UP, DOWN, UNKNOWN. Null when not reported.
  final String? operState;

  /// Is a cable/association actually present. Null when not reported. **Not the
  /// same as [operState]**: an interface can be administratively UP with no
  /// carrier, which is precisely what an unplugged port looks like.
  final bool? carrier;

  /// Negotiated link speed. Null when unknown, never 0 and never negative.
  final int? speedMbps;

  /// "full" / "half". Null when unknown.
  final String? duplex;

  final int? mtu;
  final String? mac;

  /// Kernel driver, e.g. `bcmgenet`, `mt7921u`, `iwlwifi`. Null for virtual
  /// interfaces, which have none.
  final String? driver;

  /// `usb`, `pci`, `platform`, `virtual`. Worth surfacing because a USB NIC and
  /// a built-in port do not behave alike under load.
  final String? bus;

  /// Holds the IPv4 default route: this is the link actually carrying traffic.
  final bool isDefaultRouteV4;

  /// Holds the IPv6 default route. Tracked separately because they can differ.
  final bool isDefaultRouteV6;

  final List<LinkAddress> addresses;

  /// True when this link routes either family.
  bool get isDefaultRoute => isDefaultRouteV4 || isDefaultRouteV6;

  /// A link a user can meaningfully be "on". Monitor, loopback and virtual
  /// interfaces are excluded by construction rather than by filtering on name.
  bool get isUsable => kind == LinkKind.wired || kind == LinkKind.wifi;

  /// First routable (non-link-local) IPv4, or null.
  ///
  /// Deliberately skips link-local: see [LinkAddress.isLinkLocal].
  String? get firstRoutableIPv4 {
    for (final LinkAddress a in addresses) {
      if (a.isIPv4 && !a.isLinkLocal) return a.address;
    }
    return null;
  }

  /// True when the link is up and carrying, but every IPv4 it has is link-local.
  ///
  /// This is the honest name for "the cable is in and DHCP did not answer", and
  /// it is a state the app currently cannot express at all.
  bool get hasOnlyLinkLocalIPv4 {
    final Iterable<LinkAddress> v4 = addresses.where((LinkAddress a) => a.isIPv4);
    return v4.isNotEmpty && v4.every((LinkAddress a) => a.isLinkLocal);
  }

  static LinkInfo? fromJson(Map<String, dynamic> j) {
    final String name = (j['name'] as String?) ?? '';
    if (name.isEmpty) return null;
    int? speed = (j['speed_mbps'] as num?)?.toInt();
    if (speed != null && speed <= 0) speed = null; // sentinel, not a measurement
    final String? duplex = _blank(j['duplex'] as String?);
    return LinkInfo(
      name: name,
      kind: linkKindFromString(j['kind'] as String?),
      operState: _blank(j['operstate'] as String?),
      carrier: j['carrier'] as bool?,
      speedMbps: speed,
      duplex: duplex == 'unknown' ? null : duplex,
      mtu: (j['mtu'] as num?)?.toInt(),
      mac: _blank(j['mac'] as String?),
      driver: _blank(j['driver'] as String?),
      bus: _blank(j['bus'] as String?),
      isDefaultRouteV4: j['is_default_route_v4'] == true,
      isDefaultRouteV6: j['is_default_route_v6'] == true,
      addresses: <LinkAddress>[
        for (final dynamic raw in (j['addresses'] as List<dynamic>? ?? const <dynamic>[]))
          if (raw is Map<dynamic, dynamic>)
            if (_address(raw.cast<String, dynamic>()) case final LinkAddress a) a,
      ],
    );
  }

  static LinkAddress? _address(Map<String, dynamic> j) {
    final String? ip = _blank(j['address'] as String?);
    if (ip == null) return null;
    return LinkAddress(
      address: ip,
      isIPv4: (j['family'] as String?) != 'inet6',
      prefixLength: (j['prefixlen'] as num?)?.toInt(),
      isLinkLocal: j['link_local'] == true,
      isDynamic: j['dynamic'] == true,
    );
  }

  static String? _blank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}

/// The whole link table plus the default route, as one reading.
class LinkTable {
  const LinkTable({
    required this.links,
    this.defaultRouteInterfaceV4,
    this.defaultGatewayV4,
    this.defaultRouteInterfaceV6,
    this.defaultGatewayV6,
    this.source,
  });

  final List<LinkInfo> links;
  final String? defaultRouteInterfaceV4;
  final String? defaultGatewayV4;
  final String? defaultRouteInterfaceV6;
  final String? defaultGatewayV6;

  /// Where the reading came from, in words a user could read.
  final String? source;

  /// Links a user could be on, monitor/virtual/loopback excluded.
  List<LinkInfo> get usable =>
      links.where((LinkInfo l) => l.isUsable).toList(growable: false);

  /// The link actually carrying traffic, or null when nothing routes.
  ///
  /// THE POINT OF THE WHOLE FILE. Two interfaces can both be up with addresses
  /// on the same subnet; only one of them is the answer to "what am I on".
  LinkInfo? get primary {
    for (final LinkInfo l in links) {
      if (l.isDefaultRouteV4) return l;
    }
    for (final LinkInfo l in links) {
      if (l.isDefaultRouteV6) return l;
    }
    return null;
  }

  /// True when a usable link exists but none of them routes: plugged in, no way
  /// out. Distinct from having no link at all, and the two need different words.
  bool get hasLinkButNoRoute => usable.isNotEmpty && primary == null;

  static LinkTable fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> route =
        (j['default_route'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    Map<String, dynamic>? fam(String k) =>
        (route[k] as Map<dynamic, dynamic>?)?.cast<String, dynamic>();
    return LinkTable(
      links: <LinkInfo>[
        for (final dynamic raw in (j['links'] as List<dynamic>? ?? const <dynamic>[]))
          if (raw is Map<dynamic, dynamic>)
            if (LinkInfo.fromJson(raw.cast<String, dynamic>()) case final LinkInfo l) l,
      ],
      defaultRouteInterfaceV4: fam('inet')?['dev'] as String?,
      defaultGatewayV4: fam('inet')?['gateway'] as String?,
      defaultRouteInterfaceV6: fam('inet6')?['dev'] as String?,
      defaultGatewayV6: fam('inet6')?['gateway'] as String?,
      source: j['source'] as String?,
    );
  }
}
