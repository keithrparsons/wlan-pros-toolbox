// NetworkTarget — one shared validator for any user-supplied host/IP that
// reaches a network primitive (a subprocess argument, a socket target).
//
// WHY THIS EXISTS (security choke point):
//  Two tools take a string and hand it to something dangerous:
//   - Traceroute passes the host as a positional argument to the system
//     traceroute/tracert binary. `Process.start` uses an argument vector (no
//     shell), so classic shell-metacharacter injection is structurally
//     impossible — but a host that *begins with* `-`/`--` is parsed by the
//     binary as a FLAG, not a hostname (argument injection). The fix is a
//     syntax allow-list plus a literal `--` argument terminator before the host.
//   - WHOIS reads a `refer:` server out of an untrusted server response and
//     opens a new socket to it. A faked referral pointing at an internal
//     address (e.g. `169.254.169.254`, `127.0.0.1`, `10.0.0.1`) is the SSRF
//     pattern. The fix is to reject RFC-1918 / loopback / link-local targets
//     before connecting.
//
// Two checks, deliberately different strictness:
//   - [validateHostOrIp]  — syntax only. Accepts valid hostname / IPv4 / IPv6,
//     rejects empty / malformed / flag-leading input. Used by traceroute, where
//     tracing to a LAN host (192.168.x.x) is a legitimate diagnostic, so we do
//     NOT block private ranges here.
//   - [validateReferralTarget] — syntax PLUS a refusal of private / loopback /
//     link-local addresses. Used for WHOIS referral follow, to kill the
//     SSRF-shaped redirect.
//
// Pure Dart, no `dart:io`, no Flutter — directly unit-testable.

/// Outcome of validating a user/response-supplied network target.
///
/// A sealed result (not an exception) so callers branch on it explicitly and
/// the malicious/invalid path is visible in the type, matching the codebase's
/// honest-failure style.
sealed class NetworkTargetResult {
  const NetworkTargetResult();

  /// True for [ValidNetworkTarget].
  bool get isValid => this is ValidNetworkTarget;
}

/// The input is a syntactically valid host/IP and (for the referral check)
/// not an internal address. [value] is the normalized target safe to use.
class ValidNetworkTarget extends NetworkTargetResult {
  const ValidNetworkTarget(this.value);

  /// The accepted target, trimmed. (Not lower-cased — IPv6 zone ids and
  /// hostnames are passed through as-is; DNS is case-insensitive downstream.)
  final String value;
}

/// The input was rejected. [reason] is machine-branchable; [message] is a
/// short human-readable explanation suitable for surfacing in the UI.
class InvalidNetworkTarget extends NetworkTargetResult {
  const InvalidNetworkTarget({required this.reason, required this.message});

  final NetworkTargetRejection reason;
  final String message;
}

/// Why a target was rejected.
enum NetworkTargetRejection {
  /// Empty or whitespace-only input.
  empty,

  /// Does not parse as a valid hostname, IPv4, or IPv6 literal — including a
  /// value that begins with `-`/`--` (argument-injection guard).
  malformedSyntax,

  /// Syntactically valid, but a private / loopback / link-local / unspecified
  /// address that a WHOIS referral must not be followed to (SSRF guard).
  privateOrInternal,
}

/// Shared host/IP validation. Static-only; no instances.
abstract final class NetworkTarget {
  /// Maximum length of a DNS name per RFC 1035.
  static const int _maxLength = 253;

  /// Syntax-only validation for a user-supplied target.
  ///
  /// Accepts: a valid IPv4 literal, a valid IPv6 literal (optionally with a
  /// `%zone` id), or a valid hostname (dot-separated labels, or a single label
  /// like `localhost`). Rejects: empty input, anything containing whitespace,
  /// and — critically for the traceroute argument-injection guard — anything
  /// that begins with `-` (so a `-foo` / `--help` "host" can never reach the
  /// binary in flag position).
  ///
  /// Does NOT reject private ranges: tracing to a LAN host is legitimate. Use
  /// [validateReferralTarget] when private targets must also be blocked.
  static NetworkTargetResult validateHostOrIp(String input) {
    final String value = input.trim();
    if (value.isEmpty) {
      return const InvalidNetworkTarget(
        reason: NetworkTargetRejection.empty,
        message: 'Enter a host or IP address.',
      );
    }
    if (value.length > _maxLength || _hasWhitespace(value)) {
      return _malformed();
    }
    // Argument-injection guard: a leading dash makes the binary parse the
    // "host" as a flag. No legitimate hostname/IP starts with '-'.
    if (value.startsWith('-')) {
      return const InvalidNetworkTarget(
        reason: NetworkTargetRejection.malformedSyntax,
        message: 'A host or IP cannot start with "-".',
      );
    }
    if (isIpv4(value) || isIpv6(value) || _isHostname(value)) {
      return ValidNetworkTarget(value);
    }
    return _malformed();
  }

  /// Stricter validation for a WHOIS referral target parsed out of an untrusted
  /// response. Runs the full [validateHostOrIp] syntax check AND, when the
  /// value is an IP literal, rejects private / loopback / link-local /
  /// unspecified addresses to close the SSRF-shaped referral follow.
  ///
  /// A referral that resolves (via DNS) to an internal address is out of scope
  /// here — we only have the literal at this layer — but blocking IP-literal
  /// referrals to internal ranges removes the direct, no-DNS SSRF vector the
  /// audit flagged (`refer: 169.254.169.254`, `refer: 127.0.0.1`, etc.).
  static NetworkTargetResult validateReferralTarget(String input) {
    final NetworkTargetResult base = validateHostOrIp(input);
    if (base is! ValidNetworkTarget) return base;

    final String value = base.value;
    if (isIpv4(value) && _isPrivateIpv4(value)) {
      return _internal();
    }
    if (isIpv6(value) && _isPrivateIpv6(value)) {
      return _internal();
    }
    return base;
  }

  static InvalidNetworkTarget _malformed() => const InvalidNetworkTarget(
        reason: NetworkTargetRejection.malformedSyntax,
        message: 'Not a valid host or IP address.',
      );

  static InvalidNetworkTarget _internal() => const InvalidNetworkTarget(
        reason: NetworkTargetRejection.privateOrInternal,
        message: 'Refusing to follow a referral to an internal address.',
      );

  static bool _hasWhitespace(String s) => RegExp(r'\s').hasMatch(s);

  /// A dotted-quad IPv4 literal with each octet in 0..255.
  static bool isIpv4(String q) {
    final List<String> parts = q.split('.');
    if (parts.length != 4) return false;
    for (final String p in parts) {
      if (p.isEmpty || p.length > 3) return false;
      // Reject non-digit characters (int.tryParse accepts leading +/- which we
      // do not want here).
      if (!RegExp(r'^\d+$').hasMatch(p)) return false;
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// An IPv6 literal, optionally with a `%zone` scope id. Validates the hextet
  /// shape (groups of 1-4 hex digits, at most one `::` compression) rather than
  /// the loose "any hex and colons" check, so malformed input is rejected.
  static bool isIpv6(String q) {
    if (!q.contains(':')) return false;
    String addr = q;
    final int pct = addr.indexOf('%');
    if (pct >= 0) {
      final String zone = addr.substring(pct + 1);
      if (zone.isEmpty || !RegExp(r'^[0-9a-zA-Z]+$').hasMatch(zone)) {
        return false;
      }
      addr = addr.substring(0, pct);
    }
    if (addr.isEmpty) return false;

    // Three-or-more consecutive colons are never valid (`:::`).
    if (addr.contains(':::')) return false;
    // At most one '::' compression group.
    if (RegExp('::').allMatches(addr).length > 1) return false;

    final bool compressed = addr.contains('::');
    final List<String> groups = addr.split(':');

    // A trailing IPv4 (e.g. ::ffff:1.2.3.4) counts as two groups.
    int ipv4Tail = 0;
    if (groups.isNotEmpty && groups.last.contains('.')) {
      if (!isIpv4(groups.last)) return false;
      groups.removeLast();
      ipv4Tail = 2;
    }

    for (final String g in groups) {
      if (g.isEmpty) continue; // empty from a '::' split
      if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(g)) return false;
    }

    final int hextets =
        groups.where((String g) => g.isNotEmpty).length + ipv4Tail;
    if (compressed) {
      // '::' fills at least one zero group, so the explicit count must leave room.
      return hextets <= 7;
    }
    return hextets == 8;
  }

  /// A hostname: dot-separated labels of alphanumerics + hyphen, each label
  /// 1-63 chars and not hyphen-bounded; or a single label (e.g. `localhost`).
  static bool _isHostname(String q) {
    if (q.length > _maxLength) return false;
    if (q.endsWith('.')) {
      // Allow one trailing dot (FQDN root) but validate the rest.
      q = q.substring(0, q.length - 1);
      if (q.isEmpty) return false;
    }
    final List<String> labels = q.split('.');
    final RegExp label = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$');
    for (final String l in labels) {
      if (!label.hasMatch(l)) return false;
    }
    // The top-level label (TLD) is never purely numeric. This rejects
    // dotted-numeric strings that aren't valid IPv4 (e.g. `999.1.1.1`,
    // `1.2.3`, `1.2.3.4.5`) which would otherwise pass the per-label regex.
    // A bare single all-numeric label (e.g. `12345`) is likewise not a host.
    if (RegExp(r'^\d+$').hasMatch(labels.last)) {
      return false;
    }
    return true;
  }

  /// RFC-1918 / loopback / link-local / unspecified / CGNAT IPv4 ranges that a
  /// WHOIS referral must not be followed to.
  static bool _isPrivateIpv4(String ip) {
    final List<int> o = ip.split('.').map(int.parse).toList();
    final int a = o[0], b = o[1];
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 127) return true; // 127.0.0.0/8 loopback
    if (a == 0) return true; // 0.0.0.0/8 unspecified / "this network"
    if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
    return false;
  }

  /// Loopback (`::1`), unspecified (`::`), link-local (`fe80::/10`), and
  /// unique-local (`fc00::/7`) IPv6 ranges. Also catches IPv4-mapped addresses
  /// (`::ffff:a.b.c.d`) whose embedded IPv4 is private.
  static bool _isPrivateIpv6(String ip) {
    String addr = ip;
    final int pct = addr.indexOf('%');
    if (pct >= 0) addr = addr.substring(0, pct);
    final String lower = addr.toLowerCase();

    if (lower == '::1') return true; // loopback
    if (lower == '::') return true; // unspecified

    // IPv4-mapped / -compatible: defer to the embedded IPv4 check.
    final int lastColon = lower.lastIndexOf(':');
    if (lastColon >= 0 && lower.substring(lastColon + 1).contains('.')) {
      final String tail = lower.substring(lastColon + 1);
      if (isIpv4(tail) && _isPrivateIpv4(tail)) return true;
    }

    if (lower.startsWith('fe8') ||
        lower.startsWith('fe9') ||
        lower.startsWith('fea') ||
        lower.startsWith('feb')) {
      return true; // fe80::/10 link-local
    }
    if (lower.startsWith('fc') || lower.startsWith('fd')) {
      return true; // fc00::/7 unique-local
    }
    return false;
  }
}
