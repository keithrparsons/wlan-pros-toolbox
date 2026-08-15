// DhcpPacketService — reads the DHCP options this Mac actually received.
//
// WHY macOS-ONLY, AND WHY SUBPROCESS (deliberate, documented decision):
//
// The full option set a DHCP server sent is not exposed by any Dart or
// Flutter-plugin API. macOS keeps the last DHCP packet per interface and prints
// it via `ipconfig getpacket <iface>`, which needs no root and no entitlement.
// That is the same data Apple's own tooling reads, and it is the mechanism
// behind third-party macOS tools that show option-level DHCP detail.
//
// The honest matrix:
//   - macOS, Developer ID (.dmg) build: WORKS. `ipconfig` is spawnable and the
//     full option list comes back.
//   - macOS, App Store build: BLOCKED. The App Sandbox denies spawning a
//     binary outside the bundle, exactly as it does for the system traceroute.
//     We probe at runtime rather than hard-coding "macOS = no", so one codebase
//     adapts to whichever build it is running in. See [isAvailable].
//   - Windows / Linux: NOT IMPLEMENTED HERE. Both can do this, by other
//     mechanisms entirely (Windows: the DhcpInterfaceOptions registry blob or
//     the DhcpRequestParams API; Linux: dhcpcd/nmcli). Neither is an `ipconfig
//     getpacket` call, so neither is served by this service.
//   - iOS / Android: IMPOSSIBLE and NOT ATTEMPTED. iOS exposes no DHCP option
//     API at any privilege level. Android exposes seven fixed fields through
//     DhcpInfo and nothing else.
//
// HONESTY (GL-005 / GL-008): every value here is transcribed from the packet.
// An option name this service cannot map to an RFC code is shown WITH ITS NAME
// AND NO CODE, never with a guessed number — a wrong option number is worse
// than an absent one to the audience that reads them.
//
// Web safety: imports dart:io (Process/Platform). Callers must gate on
// [isSupportedPlatform]; never reached on web.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// One option as it arrived in the DHCP packet.
class DhcpPacketOption {
  const DhcpPacketOption({
    required this.rawName,
    required this.rawValue,
    this.code,
    this.displayName,
    this.rawType,
  });

  /// The option name exactly as `ipconfig` printed it, e.g. `lease_time`.
  /// Always present. This is the ground truth and is never synthesized.
  final String rawName;

  /// The value exactly as printed, e.g. `0x1fa40` or `{192.168.20.1}`.
  final String rawValue;

  /// The RFC option code, when this service can map [rawName] to one with
  /// confidence. **Null means unmapped, and the UI must then show no code.**
  final int? code;

  /// Human-readable option name from the verified table, when [code] is known.
  /// Null when unmapped; the UI falls back to [rawName].
  final String? displayName;

  /// The type token `ipconfig` printed in parentheses, e.g. `uint32`, `ip`,
  /// `ip_mult`. Null when the line carried none.
  final String? rawType;

  /// True when this option could be tied to an RFC code.
  bool get isMapped => code != null;
}

/// The parsed result of one `ipconfig getpacket` run.
class DhcpPacket {
  const DhcpPacket({
    required this.interfaceName,
    this.options = const <DhcpPacketOption>[],
    this.yiaddr,
    this.chaddr,
  });

  /// The interface the packet was read from, e.g. `en0`.
  final String interfaceName;

  /// Every option in packet order. Empty when the packet carried none.
  final List<DhcpPacketOption> options;

  /// The address the server assigned (`yiaddr`), when the packet carried one.
  final String? yiaddr;

  /// The client hardware address the lease is bound to, when present.
  final String? chaddr;

  /// Convenience lookup by RFC code. Null when the option is absent or unmapped.
  DhcpPacketOption? byCode(int code) {
    for (final DhcpPacketOption o in options) {
      if (o.code == code) return o;
    }
    return null;
  }

  /// Lease duration in seconds, decoded from option 51.
  ///
  /// `ipconfig` prints this as hex (`0x1fa40`). Returns null when the option is
  /// absent or unparseable — never a guessed or zero duration.
  int? get leaseSeconds {
    final DhcpPacketOption? o = byCode(51);
    if (o == null) return null;
    final int? v = DhcpPacketService._parseIntLoose(o.rawValue);
    return (v != null && v > 0) ? v : null;
  }

  /// True when the packet carried at least one option.
  bool get hasOptions => options.isNotEmpty;
}

/// Why a read produced nothing. Each maps to a distinct, honest UI message.
enum DhcpPacketUnavailable {
  /// Not macOS. Windows and Linux need entirely different mechanisms.
  unsupportedPlatform,

  /// macOS, but this build cannot spawn `ipconfig` — the App Sandbox denies it.
  /// The Developer ID (.dmg) build can.
  sandboxed,

  /// `ipconfig` ran but reported no packet for the interface: no DHCP lease,
  /// a static address, or the link is down.
  noLease,

  /// `ipconfig` ran and printed something this parser could not read. Kept
  /// distinct from [noLease] so a format change is visible rather than silently
  /// reported as "no lease".
  unparseable,
}

/// Result of a read: either a packet, or a reason there is none.
class DhcpPacketResult {
  const DhcpPacketResult.success(this.packet)
      : unavailable = null;
  const DhcpPacketResult.unavailable(this.unavailable) : packet = null;

  final DhcpPacket? packet;
  final DhcpPacketUnavailable? unavailable;

  bool get isSuccess => packet != null;
}

/// Reads the last DHCP packet macOS received on an interface.
class DhcpPacketService {
  DhcpPacketService({
    Future<ProcessResult> Function(String, List<String>)? runProcess,
    bool? isMacOsOverride,
  })  : _run = runProcess ?? Process.run,
        _isMacOsOverride = isMacOsOverride;

  final Future<ProcessResult> Function(String, List<String>) _run;

  /// Test seam: forces the platform answer so gating is testable off macOS.
  final bool? _isMacOsOverride;

  bool get _isMacOs =>
      _isMacOsOverride ?? (!kIsWeb && Platform.isMacOS);

  /// Whether this platform could ever serve this data by this mechanism.
  /// Answers the coarse question; [isAvailable] answers the sharp one.
  bool get isSupportedPlatform => _isMacOs;

  /// Whether THIS BUILD can actually spawn `ipconfig` right now.
  ///
  /// The App Store build ships sandboxed and cannot; the Developer ID build
  /// can. Probing beats hard-coding, so one binary adapts to either. The probe
  /// is side-effect-free: `ipconfig getiflist` only lists interface names.
  /// Never throws.
  Future<bool> isAvailable() async {
    if (!_isMacOs) return false;
    try {
      await _run('ipconfig', const <String>['getiflist'])
          .timeout(const Duration(seconds: 3));
      return true;
    } on Object {
      // ProcessException (sandbox denial / missing binary) or a timeout.
      return false;
    }
  }

  /// Reads the DHCP packet for [interfaceName], or for the default-route
  /// interface when none is given.
  Future<DhcpPacketResult> read({String? interfaceName}) async {
    if (!_isMacOs) {
      return const DhcpPacketResult.unavailable(
        DhcpPacketUnavailable.unsupportedPlatform,
      );
    }

    final String? iface = interfaceName ?? await _defaultInterface();
    if (iface == null || iface.isEmpty) {
      return const DhcpPacketResult.unavailable(DhcpPacketUnavailable.noLease);
    }

    final ProcessResult result;
    try {
      result = await _run('ipconfig', <String>['getpacket', iface])
          .timeout(const Duration(seconds: 5));
    } on Object {
      return const DhcpPacketResult.unavailable(
        DhcpPacketUnavailable.sandboxed,
      );
    }

    final String out = (result.stdout is String)
        ? result.stdout as String
        : '';

    // `ipconfig getpacket` on an interface with no lease prints nothing (or a
    // bare "not found"-ish line) and exits non-zero.
    if (out.trim().isEmpty) {
      return const DhcpPacketResult.unavailable(DhcpPacketUnavailable.noLease);
    }

    final DhcpPacket? parsed = parsePacket(out, interfaceName: iface);
    if (parsed == null) {
      return const DhcpPacketResult.unavailable(
        DhcpPacketUnavailable.unparseable,
      );
    }
    return DhcpPacketResult.success(parsed);
  }

  /// Resolves the interface carrying the default route, e.g. `en0`.
  /// Returns null when it cannot be determined; the caller then reports
  /// [DhcpPacketUnavailable.noLease] rather than guessing `en0`.
  Future<String?> _defaultInterface() async {
    try {
      final ProcessResult r = await _run(
        'route',
        const <String>['-n', 'get', 'default'],
      ).timeout(const Duration(seconds: 3));
      final String out = (r.stdout is String) ? r.stdout as String : '';
      for (final String line in out.split('\n')) {
        final String t = line.trim();
        if (t.startsWith('interface:')) {
          final String v = t.substring('interface:'.length).trim();
          if (v.isNotEmpty) return v;
        }
      }
    } on Object {
      // fall through
    }
    return null;
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Parses `ipconfig getpacket` output. Returns null when the text carries no
  /// recognizable options block, which the caller reports as
  /// [DhcpPacketUnavailable.unparseable].
  ///
  /// Expected shape:
  /// ```
  /// op = BOOTREPLY
  /// yiaddr = 192.168.20.52
  /// chaddr = 66:22:dd:41:a9:d5
  /// options:
  /// Options count is 7
  /// dhcp_message_type (uint8): ACK 0x5
  /// lease_time (uint32): 0x1fa40
  /// router (ip_mult): {192.168.20.1}
  /// end (none):
  /// ```
  @visibleForTesting
  static DhcpPacket? parsePacket(String output, {required String interfaceName}) {
    final List<String> lines = output.split('\n');
    String? yiaddr;
    String? chaddr;
    bool inOptions = false;
    final List<DhcpPacketOption> options = <DhcpPacketOption>[];

    for (final String raw in lines) {
      final String line = raw.trim();
      if (line.isEmpty) continue;

      if (!inOptions) {
        if (line.startsWith('yiaddr')) {
          yiaddr = _afterEquals(line);
          continue;
        }
        if (line.startsWith('chaddr')) {
          chaddr = _afterEquals(line);
          continue;
        }
        if (line == 'options:') {
          inOptions = true;
        }
        continue;
      }

      // Inside the options block.
      if (line.startsWith('Options count')) continue;
      // `end (none):` terminates the list and is not an option.
      if (line.startsWith('end ')) break;
      if (line == 'end') break;

      final DhcpPacketOption? opt = _parseOptionLine(line);
      if (opt != null) options.add(opt);
    }

    if (!inOptions) return null;
    return DhcpPacket(
      interfaceName: interfaceName,
      options: List<DhcpPacketOption>.unmodifiable(options),
      yiaddr: yiaddr,
      chaddr: chaddr,
    );
  }

  /// Parses one option line: `name (type): value`, or `name: value`.
  static DhcpPacketOption? _parseOptionLine(String line) {
    final int colon = line.indexOf(':');
    if (colon <= 0) return null;

    String head = line.substring(0, colon).trim();
    final String value = line.substring(colon + 1).trim();

    String? type;
    final int open = head.indexOf('(');
    if (open > 0 && head.endsWith(')')) {
      type = head.substring(open + 1, head.length - 1).trim();
      head = head.substring(0, open).trim();
    }
    if (head.isEmpty) return null;

    final int? code = optionCodeForName(head);
    return DhcpPacketOption(
      rawName: head,
      rawValue: value,
      rawType: type,
      code: code,
      displayName: code == null ? null : optionNames[code],
    );
  }

  static String? _afterEquals(String line) {
    final int eq = line.indexOf('=');
    if (eq < 0) return null;
    final String v = line.substring(eq + 1).trim();
    return v.isEmpty ? null : v;
  }

  /// Parses `0x1fa40` or `86400` into an int. Null when neither.
  static int? _parseIntLoose(String s) {
    final String t = s.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('0x') || t.startsWith('0X')) {
      return int.tryParse(t.substring(2), radix: 16);
    }
    return int.tryParse(t);
  }

  // ── Name → RFC code mapping ───────────────────────────────────────────────

  /// macOS `ipconfig` option name to RFC option code.
  ///
  /// **Only codes this project has verified are listed.** The values mirror the
  /// IANA-sourced table already shipped in the DHCP Options reference screen,
  /// plus the standard RFC 2132 assignments for names macOS prints that the
  /// reference table does not enumerate. A name absent from this map is
  /// reported with its raw name and NO code — see the honesty note at the top.
  static const Map<String, int> nameToCode = <String, int>{
    'subnet_mask': 1,
    'time_offset': 2,
    'router': 3,
    'domain_name_server': 6,
    'host_name': 12,
    'domain_name': 15,
    'interface_mtu': 26,
    'broadcast_address': 28,
    'network_time_protocol_servers': 42,
    'vendor_specific': 43,
    'requested_ip_address': 50,
    'lease_time': 51,
    'dhcp_message_type': 53,
    'server_identifier': 54,
    'parameter_request_list': 55,
    'dhcp_message': 56,
    'max_dhcp_message_size': 57,
    'renewal_t1_time_value': 58,
    'rebinding_t2_time_value': 59,
    'vendor_class_identifier': 60,
    'client_identifier': 61,
    'tftp_server_name': 66,
    'bootfile_name': 67,
    'domain_search': 119,
  };

  /// Human-readable names for the codes above, matching the reference screen's
  /// wording so one option reads identically in both places.
  static const Map<int, String> optionNames = <int, String>{
    1: 'Subnet Mask',
    2: 'Time Offset',
    3: 'Router',
    6: 'Domain Name Server',
    12: 'Host Name',
    15: 'Domain Name',
    26: 'Interface MTU',
    28: 'Broadcast Address',
    42: 'NTP Servers',
    43: 'Vendor-Specific Information',
    50: 'Requested IP Address',
    51: 'IP Address Lease Time',
    53: 'DHCP Message Type',
    54: 'Server Identifier',
    55: 'Parameter Request List',
    56: 'DHCP Message',
    57: 'Max DHCP Message Size',
    58: 'Renewal (T1) Time Value',
    59: 'Rebinding (T2) Time Value',
    60: 'Vendor Class Identifier',
    61: 'Client Identifier',
    66: 'TFTP Server Name',
    67: 'Bootfile Name',
    119: 'Domain Search List',
  };

  /// Code for a macOS option name, or null when unmapped.
  static int? optionCodeForName(String rawName) => nameToCode[rawName];

  /// Formats a lease duration as `86400 s (1 d)`. Null for null or <= 0 so the
  /// caller renders the honest unavailable reason rather than `0 s`.
  ///
  /// NOTE: this is the duration the server GRANTED, not the time remaining.
  /// `ipconfig getpacket` reports the packet as received; it carries no
  /// remaining-time field. Label accordingly.
  static String? formatLeaseDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final int d = seconds ~/ 86400;
    final int h = (seconds % 86400) ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    final int s = seconds % 60;
    final List<String> parts = <String>[];
    if (d > 0) parts.add('$d d');
    if (h > 0) parts.add('$h h');
    if (m > 0) parts.add('$m m');
    if (s > 0 && d == 0 && h == 0) parts.add('$s s');
    if (parts.isEmpty) parts.add('$seconds s');
    return '$seconds s (${parts.join(' ')})';
  }
}
