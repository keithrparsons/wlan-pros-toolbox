// Which link is actually carrying traffic, asked of the operating system.
//
// WHY THIS FILE EXISTS. `network_info_plus` answers "your local IP" on macOS by
// looking for an interface literally NAMED `en0`
// (NetworkInfoPlusPlugin.swift:143). On a MacBook `en0` is Wi-Fi. A Phase 0
// capture on 2026-08-30 had the live 2500Base-T wired link on `en5` with `en0`
// simultaneously up on Wi-Fi, so on a wired Mac that plugin reports the WIRELESS
// subnet and calls it yours. Six screens prefill a target from it and Network
// Discovery derives its entire scan range from it, offering no field to correct.
//
// THERE IS NO PURE-DART ROUTE LOOKUP. `RawDatagramSocket` has no `connect`, so
// the usual "UDP-connect and read back the source address" trick is unavailable,
// and `Socket.connect` needs something listening. Verified 2026-08-31.
//
// SO THIS IS A CAPABILITY BOUNDARY, exactly as Phase 0 concluded for the link
// table itself: where a platform can tell us the truth we ask it, and where it
// cannot we say so rather than guessing from a name. Nothing here infers an
// interface from what it is called.

import 'dart:io';

/// The routing answer for one address family.
class DefaultRoute {
  const DefaultRoute({
    required this.interfaceName,
    this.gateway,
    this.address,
    this.prefixLength,
  });

  /// The interface the OS says carries the default route.
  final String interfaceName;

  /// The next hop, when the OS reported one.
  final String? gateway;

  /// That interface's own IPv4 address.
  final String? address;

  /// Its prefix length, derived from the netmask the OS printed. Null rather
  /// than a guessed /24: a wrong prefix silently changes the size of a scan.
  final int? prefixLength;

  /// Dotted-quad form of [prefixLength], for callers that still speak masks.
  String? get netmask {
    final int? p = prefixLength;
    if (p == null || p < 0 || p > 32) return null;
    final int bits = p == 0 ? 0 : (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF;
    return '${(bits >> 24) & 0xFF}.${(bits >> 16) & 0xFF}.'
        '${(bits >> 8) & 0xFF}.${bits & 0xFF}';
  }
}

/// Runs a command and returns stdout, or null if it could not run.
typedef ShellRunner = Future<String?> Function(String exe, List<String> args);

Future<String?> _runProcess(String exe, List<String> args) async {
  // NEVER SPAWN A PROCESS UNDER `flutter test`. Widget tests run inside
  // FakeAsync, where a real process launch leaves a pending timer the test
  // cannot drain, and six screens call this on their load path. Two
  // ping-plotter tests failed exactly this way when the probe was first wired
  // in. This branch does NOT weaken the probe's own coverage: every parsing
  // path is unit-tested through the injected [ShellRunner] seam against real
  // captured OS output.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  try {
    final ProcessResult r = await Process.run(exe, args);
    if (r.exitCode != 0) return null;
    return r.stdout as String;
  } on Object {
    // A sandbox that refuses Process.run is a legitimate answer of "cannot
    // tell", not an error to surface. The caller falls back.
    //
    // AND THIS IS NOT HYPOTHETICAL ON macOS. The App Store build ships with the
    // App Sandbox enabled, which DENIES launching system binaries; the
    // Developer ID direct-download build does not and launches them fine. The
    // codebase already established this and probes it live rather than
    // hard-coding "macOS = unavailable" (see TracerouteService.isLaunchable,
    // and the note at network_details_service.dart:10).
    //
    // SO ON THE APP STORE BUILD THIS PROBE RETURNS NULL AND THE CALLER FALLS
    // BACK TO `network_info_plus`, WHICH MEANS THE en0 DEFECT PERSISTS THERE.
    // The real fix is a sandbox-safe read of the routing table through the
    // `sysctl(CTL_NET, AF_ROUTE, ...)` FFI seam that `lan_discovery/
    // arp_reader.dart` already uses for the neighbour table. A syscall is not
    // a subprocess and the sandbox permits it.
    return null;
  }
}

/// Reads the default route from the operating system.
///
/// Returns null on every platform that cannot be asked, and null is a REAL
/// ANSWER meaning "we could not tell", never "there is no route". The caller
/// must not treat it as absence (GL-005).
class DefaultRouteProbe {
  DefaultRouteProbe({
    ShellRunner? runner,
    bool? isMacOS,
    bool? isLinux,
    bool? isWindows,
  }) : _run = runner ?? _runProcess,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux,
       _isWindows = isWindows ?? Platform.isWindows;

  final ShellRunner _run;
  final bool _isMacOS;
  final bool _isLinux;
  final bool _isWindows;

  Future<DefaultRoute?> readV4() async {
    if (_isMacOS) return _macos();
    if (_isLinux) return _linux();
    if (_isWindows) return _windows();
    // iOS, Android and web cannot be shelled. Android has a first-class API
    // (ConnectivityManager) that belongs behind a platform channel; iOS and web
    // have no answer at all. Returning null keeps the caller honest.
    return null;
  }

  // ── macOS ────────────────────────────────────────────────────────────────
  //
  // `route -n get default` prints "interface: en0" and "gateway: 192.168.8.1".
  // Verified on this machine 2026-08-31.
  Future<DefaultRoute?> _macos() async {
    final String? out = await _run('route', <String>['-n', 'get', 'default']);
    if (out == null) return null;
    final String? iface = _afterColon(out, 'interface');
    if (iface == null) return null;
    final String? gw = _afterColon(out, 'gateway');
    final ({String? ip, int? prefix}) a = await _macosAddress(iface);
    return DefaultRoute(
      interfaceName: iface,
      gateway: gw,
      address: a.ip,
      prefixLength: a.prefix,
    );
  }

  /// `ifconfig en0` prints `inet 192.168.8.134 netmask 0xffffff00 broadcast ...`.
  /// The mask is HEX on macOS, which is the detail a dotted-quad parser gets
  /// wrong silently.
  Future<({String? ip, int? prefix})> _macosAddress(String iface) async {
    final String? out = await _run('ifconfig', <String>[iface]);
    if (out == null) return (ip: null, prefix: null);
    final RegExp re = RegExp(
      r'inet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+(0x[0-9a-fA-F]{8}|\d+\.\d+\.\d+\.\d+)',
    );
    final RegExpMatch? m = re.firstMatch(out);
    if (m == null) return (ip: null, prefix: null);
    return (ip: m.group(1), prefix: parseNetmask(m.group(2)!));
  }

  // ── Linux ────────────────────────────────────────────────────────────────
  //
  // `ip -o -4 route show default` prints:
  //   default via 192.168.8.1 dev eth0 proto dhcp ...
  // and `ip -o -4 addr show dev eth0` prints:
  //   2: eth0    inet 192.168.8.176/24 brd ...
  //
  // NOTE: on a WLAN Pi this path is not normally taken, because the Pi's own
  // `/toolboxapi/links` already hands over `is_default_route_v4` as a typed
  // field. That is the better source and should be preferred wherever it exists.
  Future<DefaultRoute?> _linux() async {
    final String? route = await _run('ip', <String>[
      '-o',
      '-4',
      'route',
      'show',
      'default',
    ]);
    if (route == null) return null;
    final RegExpMatch? m = RegExp(
      r'default\s+via\s+(\S+)\s+dev\s+(\S+)',
    ).firstMatch(route);
    if (m == null) return null;
    final String iface = m.group(2)!;
    final String? addrOut = await _run('ip', <String>[
      '-o',
      '-4',
      'addr',
      'show',
      'dev',
      iface,
    ]);
    String? ip;
    int? prefix;
    if (addrOut != null) {
      final RegExpMatch? a = RegExp(
        r'inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)',
      ).firstMatch(addrOut);
      ip = a?.group(1);
      prefix = a == null ? null : int.tryParse(a.group(2)!);
    }
    return DefaultRoute(
      interfaceName: iface,
      gateway: m.group(1),
      address: ip,
      prefixLength: prefix,
    );
  }

  // ── Windows ──────────────────────────────────────────────────────────────
  //
  // UNVERIFIED. No Windows capture of any kind exists yet, which is why it is
  // the one platform Keith named as still owing evidence. The shape below is
  // written to fail closed: if the output does not parse, this returns null and
  // the caller falls back rather than inventing an interface.
  Future<DefaultRoute?> _windows() async {
    final String? out = await _run('powershell', <String>[
      '-NoProfile',
      '-Command',
      r'(Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1 | ForEach-Object { $ifa = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1; "{0}`t{1}`t{2}`t{3}" -f $_.InterfaceAlias, $_.NextHop, $ifa.IPAddress, $ifa.PrefixLength })',
    ]);
    if (out == null) return null;
    final List<String> parts = out.trim().split('\t');
    if (parts.length < 4 || parts[0].isEmpty) return null;
    return DefaultRoute(
      interfaceName: parts[0].trim(),
      gateway: parts[1].trim().isEmpty ? null : parts[1].trim(),
      address: parts[2].trim().isEmpty ? null : parts[2].trim(),
      prefixLength: int.tryParse(parts[3].trim()),
    );
  }
}

String? _afterColon(String text, String key) {
  for (final String line in text.split('\n')) {
    final int i = line.indexOf(':');
    if (i < 0) continue;
    if (line.substring(0, i).trim() != key) continue;
    final String v = line.substring(i + 1).trim();
    if (v.isEmpty) return null;
    return v;
  }
  return null;
}

/// Netmask to prefix length, accepting BOTH forms an OS may print.
///
/// macOS prints hex (`0xffffff00`); Linux and Windows print a prefix or a
/// dotted quad. A NON-CONTIGUOUS mask returns null rather than a popcount: a
/// mask with holes is not a prefix, and counting its bits would produce a
/// plausible number describing a network that does not exist.
int? parseNetmask(String raw) {
  final String s = raw.trim();
  int? value;
  if (s.toLowerCase().startsWith('0x')) {
    value = int.tryParse(s.substring(2), radix: 16);
  } else if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(s)) {
    final List<int> o = s.split('.').map(int.parse).toList();
    if (o.any((int b) => b > 255)) return null;
    value = (o[0] << 24) | (o[1] << 16) | (o[2] << 8) | o[3];
  } else {
    final int? p = int.tryParse(s);
    return (p != null && p >= 0 && p <= 32) ? p : null;
  }
  if (value == null) return null;
  // Contiguity check: the complement + 1 must be a power of two.
  final int inverted = (~value) & 0xFFFFFFFF;
  if ((inverted & (inverted + 1)) != 0) return null;
  int bits = 0;
  int v = value;
  while (v & 0x80000000 != 0) {
    bits++;
    v = (v << 1) & 0xFFFFFFFF;
  }
  return bits;
}
