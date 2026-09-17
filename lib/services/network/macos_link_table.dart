// The macOS link table, reconstructed from what the OS will tell us.
//
// Linux hands over carrier, speed_mbps, duplex and is_default_route_v4 as typed
// fields. macOS makes us derive every one of them, which is why Phase 0
// concluded the platform layer is a CAPABILITY boundary and not a parsing one:
// this file exists to raise macOS UP to the Linux shape, never to drag Linux
// down to this one.
//
// THREE COMMANDS, EACH ANSWERING SOMETHING THE OTHERS CANNOT:
//   networksetup -listallhardwareports   what each device IS (Wi-Fi, a bridge,
//                                        a USB LAN adapter)
//   ifconfig -a                          addresses, media, and the real carrier
//   route -n get default                 which one is carrying traffic
//
// THE TWO TRAPS PHASE 0 MEASURED, AND BOTH ARE HANDLED HERE:
//
// 1. `IFF_RUNNING` LIES. `en2` on Keith's M5 is named "Ethernet Adapter", is
//    always present, carries the RUNNING flag, and has `media: none` /
//    `status: inactive` with no cable and no addresses. Any code reaching for
//    the conventional BSD carrier flag gets a live-looking interface that has
//    never had a cable in it. CARRIER COMES FROM `status: active`, nothing else.
//
// 2. A CABLE INTO A DEAD SWITCH IS BYTE-IDENTICAL TO NO CABLE. Both produce
//    `media: autoselect (none)` / `status: inactive`. That is not a fourth
//    state to model; it is a genuine limit, and the UI has to say "no link"
//    and let the user check both ends.
//
// THE MEDIA STRING IS THE FRAGILE PART AND IS TREATED AS SUCH. We have only
// ever observed ONE live format, `autoselect (2500Base-T <full-duplex>)`,
// because that is what both the MUDI and the switch negotiated. macOS is
// inconsistent about capitalisation and spacing across drivers. So the parser
// matches loosely and an UNRECOGNISED string means "link up, speed unknown"
// rather than "no link" - failing toward the honest half.

import 'link_info.dart';

/// Parsed pieces of a media string.
class MediaReading {
  const MediaReading({this.speedMbps, this.duplex, this.hasLink});

  final int? speedMbps;

  /// "full" or "half". Null when the string did not say.
  final String? duplex;

  /// True when the media string positively indicates a link, false when it
  /// positively indicates none, null when it said nothing either way.
  final bool? hasLink;
}

/// Parse an ifconfig `media:` value.
///
/// Handles `2500Base-T`, `1000baseT`, `100baseTX` and `10Gbase-T` alike,
/// because case and spacing vary by driver and we have only ever seen one of
/// them in the wild.
MediaReading parseMediaString(String raw) {
  final String s = raw.trim();
  final String lower = s.toLowerCase();

  if (lower == 'none' || lower.contains('(none)')) {
    return const MediaReading(hasLink: false);
  }

  String? duplex;
  if (lower.contains('full-duplex') || lower.contains('full duplex')) {
    duplex = 'full';
  } else if (lower.contains('half-duplex') || lower.contains('half duplex')) {
    duplex = 'half';
  }

  // "2500Base-T", "1000baseT", "10Gbase-T". The optional G multiplies by 1000.
  final RegExpMatch? m = RegExp(
    r'(\d+)\s*(g?)base',
    caseSensitive: false,
  ).firstMatch(lower);
  int? speed;
  if (m != null) {
    final int? n = int.tryParse(m.group(1)!);
    if (n != null) speed = m.group(2) == 'g' ? n * 1000 : n;
  }

  // A bare "autoselect" with no media type is what an associated Wi-Fi radio
  // reports. It says nothing about link, so it returns null rather than false:
  // `status:` is the authority and the caller has it.
  return MediaReading(
    speedMbps: speed,
    duplex: duplex,
    hasLink: speed != null ? true : null,
  );
}

/// Classify a device from the hardware-port label macOS gives it.
///
/// THIS IS NOT THE THING PHASE 0 BANNED. The banned move is deciding WHICH link
/// is carrying traffic from its name. Asking the OS what a port IS, and being
/// told "Wi-Fi" or "Thunderbolt Bridge", is the OS reporting a fact about the
/// hardware. Carrier and default route still decide everything that matters.
LinkKind kindFromHardwarePort(String? portLabel, String device) {
  final String p = (portLabel ?? '').toLowerCase();
  if (p.contains('wi-fi') || p.contains('wifi') || p.contains('airport')) {
    return LinkKind.wifi;
  }
  if (p.contains('bridge') || p.contains('vlan') || p.contains('vpn')) {
    return LinkKind.virtual;
  }
  if (device == 'lo0' || device.startsWith('lo')) return LinkKind.loopback;
  if (p.isEmpty) {
    // No hardware port at all: a software interface macOS did not list, such as
    // utun*, awdl*, llw*, gif*, stf*. Never a wired port.
    return LinkKind.virtual;
  }
  return LinkKind.wired;
}

/// Build a [LinkTable] from the three command outputs.
///
/// [defaultRouteInterface] comes from `route -n get default`; pass null when it
/// could not be read, and NO interface is then marked as the default route.
/// Marking one anyway would be exactly the guess this whole module exists to
/// stop.
LinkTable parseMacosLinkTable({
  required String hardwarePorts,
  required String ifconfigAll,
  String? defaultRouteInterface,
  String? defaultGateway,
}) {
  final Map<String, String> portOf = _hardwarePorts(hardwarePorts);
  final List<LinkInfo> links = <LinkInfo>[];

  for (final _RawInterface raw in _splitIfconfig(ifconfigAll)) {
    final MediaReading media = raw.media == null
        ? const MediaReading()
        : parseMediaString(raw.media!);

    // CARRIER IS `status: active` AND NOTHING ELSE. Not IFF_RUNNING, which is
    // set on an adapter with nothing plugged in.
    final bool? carrier = raw.status == null
        ? (raw.name.startsWith('lo') ? true : null)
        : raw.status!.toLowerCase() == 'active';

    links.add(
      LinkInfo(
        name: raw.name,
        kind: kindFromHardwarePort(portOf[raw.name], raw.name),
        operState: raw.flagsUp ? 'UP' : 'DOWN',
        carrier: carrier,
        // Only report a speed on a link that is actually up. A negotiated rate
        // printed beside a dead port is the kind of true-but-misplaced fact that
        // has caused every problem this project has had.
        speedMbps: carrier == true ? media.speedMbps : null,
        duplex: carrier == true ? media.duplex : null,
        mtu: raw.mtu,
        mac: raw.mac,
        isDefaultRouteV4:
            defaultRouteInterface != null && raw.name == defaultRouteInterface,
        addresses: raw.addresses,
      ),
    );
  }

  return LinkTable(
    links: links,
    defaultRouteInterfaceV4: defaultRouteInterface,
    defaultGatewayV4: defaultGateway,
    source: 'macos ifconfig + networksetup + route',
  );
}

Map<String, String> _hardwarePorts(String text) {
  final Map<String, String> out = <String, String>{};
  String? port;
  for (final String line in text.split('\n')) {
    final String t = line.trim();
    if (t.startsWith('Hardware Port:')) {
      port = t.substring('Hardware Port:'.length).trim();
    } else if (t.startsWith('Device:')) {
      final String dev = t.substring('Device:'.length).trim();
      if (dev.isNotEmpty && port != null) out[dev] = port;
      port = null;
    }
  }
  return out;
}

class _RawInterface {
  _RawInterface(this.name);
  final String name;
  bool flagsUp = false;
  int? mtu;
  String? mac;
  String? media;
  String? status;
  final List<LinkAddress> addresses = <LinkAddress>[];
}

List<_RawInterface> _splitIfconfig(String text) {
  final List<_RawInterface> out = <_RawInterface>[];
  _RawInterface? cur;

  for (final String line in text.split('\n')) {
    final RegExpMatch? head = RegExp(
      r'^([a-zA-Z0-9_.]+):\s+flags=(\d+)<([^>]*)>(?:.*mtu\s+(\d+))?',
    ).firstMatch(line);
    if (head != null) {
      cur = _RawInterface(head.group(1)!);
      cur.flagsUp = head.group(3)!.split(',').contains('UP');
      cur.mtu = int.tryParse(head.group(4) ?? '');
      out.add(cur);
      continue;
    }
    if (cur == null) continue;
    final String t = line.trim();

    if (t.startsWith('ether ')) {
      cur.mac = t.substring(6).trim();
    } else if (t.startsWith('media:')) {
      cur.media = t.substring(6).trim();
    } else if (t.startsWith('status:')) {
      cur.status = t.substring(7).trim();
    } else if (t.startsWith('inet ')) {
      final RegExpMatch? m = RegExp(
        r'inet\s+(\d+\.\d+\.\d+\.\d+)(?:\s+netmask\s+(0x[0-9a-fA-F]+|\d+\.\d+\.\d+\.\d+))?',
      ).firstMatch(t);
      if (m != null) {
        final String ip = m.group(1)!;
        cur.addresses.add(
          LinkAddress(
            address: ip,
            isIPv4: true,
            prefixLength: m.group(2) == null ? null : _mask(m.group(2)!),
            isLinkLocal: ip.startsWith('169.254.'),
          ),
        );
      }
    } else if (t.startsWith('inet6 ')) {
      final RegExpMatch? m = RegExp(
        r'inet6\s+([0-9a-fA-F:]+)(?:%\w+)?(?:\s+prefixlen\s+(\d+))?',
      ).firstMatch(t);
      if (m != null) {
        final String ip = m.group(1)!;
        cur.addresses.add(
          LinkAddress(
            address: ip,
            isIPv4: false,
            prefixLength: int.tryParse(m.group(2) ?? ''),
            isLinkLocal: ip.toLowerCase().startsWith('fe80'),
          ),
        );
      }
    }
  }
  return out;
}

int? _mask(String raw) {
  int? v;
  if (raw.toLowerCase().startsWith('0x')) {
    v = int.tryParse(raw.substring(2), radix: 16);
  } else {
    final List<String> o = raw.split('.');
    if (o.length != 4) return null;
    int acc = 0;
    for (final String part in o) {
      final int? b = int.tryParse(part);
      if (b == null || b > 255) return null;
      acc = (acc << 8) | b;
    }
    v = acc;
  }
  if (v == null) return null;
  final int inv = (~v) & 0xFFFFFFFF;
  if ((inv & (inv + 1)) != 0) return null;
  int bits = 0;
  int x = v;
  while (x & 0x80000000 != 0) {
    bits++;
    x = (x << 1) & 0xFFFFFFFF;
  }
  return bits;
}
