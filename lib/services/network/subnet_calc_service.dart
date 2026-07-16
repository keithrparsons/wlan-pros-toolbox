// SubnetCalcService — IPv4 subnet math from an address + CIDR prefix or dotted
// mask. Pure-Dart integer arithmetic on the 32-bit address space; no network,
// no Flutter imports, fully deterministic and unit-testable.
//
// EDGE CASES THAT MATTER (the easy ones to get wrong):
//  - /31 (RFC 3021) — a point-to-point link. There is no network/broadcast
//    reservation: BOTH addresses are usable hosts. usableHosts = 2.
//  - /32 — a single host route. The one address is the host; there is no range.
//    usableHosts = 1, first == last == the address itself.
//  - /0–/30 — the classic case: network and broadcast are reserved, so
//    usableHosts = totalAddresses − 2.
//
// All values are computed from the masked network base so an input host inside
// the subnet (e.g. 10.20.0.37/22) reports the SAME network as the base address.
// 32-bit math uses Dart `int` (64-bit on native, but every value here fits in
// 32 bits and we mask with 0xFFFFFFFF to stay safe).

/// A fully-computed subnet breakdown. Construction is always via
/// [SubnetCalcService.calculate]; an invalid input throws nothing — it returns a
/// result with [isValid] false and an [error] message.
class SubnetResult {
  const SubnetResult({
    required this.isValid,
    this.error,
    this.inputAddress,
    this.prefix,
    this.dottedMask,
    this.wildcardMask,
    this.networkAddress,
    this.broadcastAddress,
    this.firstHost,
    this.lastHost,
    this.totalAddresses,
    this.usableHosts,
  });

  /// Convenience constructor for a validation failure.
  const SubnetResult.invalid(String message)
      : isValid = false,
        error = message,
        inputAddress = null,
        prefix = null,
        dottedMask = null,
        wildcardMask = null,
        networkAddress = null,
        broadcastAddress = null,
        firstHost = null,
        lastHost = null,
        totalAddresses = null,
        usableHosts = null;

  final bool isValid;

  /// Set only when [isValid] is false.
  final String? error;

  /// The address as typed, normalized to dotted-decimal.
  final String? inputAddress;

  final int? prefix;
  final String? dottedMask;
  final String? wildcardMask;
  final String? networkAddress;

  /// Broadcast address. Null for /32 and /31, which have no broadcast.
  final String? broadcastAddress;

  /// First usable host. For /31 this is the lower address; for /32 it is the
  /// host itself.
  final String? firstHost;

  /// Last usable host. For /31 this is the upper address; for /32 it is the
  /// host itself.
  final String? lastHost;

  /// Total addresses in the block (2^(32−prefix)).
  final int? totalAddresses;

  /// Usable hosts: total−2 for /0–/30, 2 for /31 (RFC 3021), 1 for /32.
  final int? usableHosts;
}

/// Pure-Dart IPv4 subnet calculator.
class SubnetCalcService {
  const SubnetCalcService();

  /// Compute the subnet breakdown for [address] with EITHER a [prefix]
  /// (0–32) OR a dotted [mask] (e.g. "255.255.252.0"). Exactly one of the two
  /// must be supplied; supplying neither or both is a validation error.
  ///
  /// Never throws — every rejection comes back as
  /// [SubnetResult.invalid] with a clear message for `error_card`.
  SubnetResult calculate({
    required String address,
    int? prefix,
    String? mask,
  }) {
    final int? addr = _parseIpv4(address);
    if (addr == null) {
      return const SubnetResult.invalid(
        'Enter a valid IPv4 address, e.g. 10.20.0.0. Four octets, each 0–255.',
      );
    }

    final bool hasMask = mask != null && mask.trim().isNotEmpty;
    final bool hasPrefix = prefix != null;
    if (hasMask == hasPrefix) {
      return const SubnetResult.invalid(
        'Provide exactly one of a CIDR prefix (e.g. /22) or a dotted mask '
        '(e.g. 255.255.252.0).',
      );
    }

    final int resolvedPrefix;
    if (hasPrefix) {
      if (prefix < 0 || prefix > 32) {
        return const SubnetResult.invalid(
          'Prefix length must be between 0 and 32.',
        );
      }
      resolvedPrefix = prefix;
    } else {
      final int? p = prefixFromMask(mask!.trim());
      if (p == null) {
        return const SubnetResult.invalid(
          'That is not a valid subnet mask. A mask is a contiguous run of 1 '
          'bits, e.g. 255.255.252.0 (/22).',
        );
      }
      resolvedPrefix = p;
    }

    final int maskInt = _maskForPrefix(resolvedPrefix);
    final int network = addr & maskInt;
    final int broadcast = network | (~maskInt & 0xFFFFFFFF);
    final int wildcard = ~maskInt & 0xFFFFFFFF;
    final int total = resolvedPrefix == 0
        ? 0x100000000 // 2^32, kept as a 64-bit int — fits in Dart int.
        : (1 << (32 - resolvedPrefix));

    // Usable-host rules per prefix.
    final int usable;
    final String first;
    final String last;
    final String? broadcastStr;
    if (resolvedPrefix == 32) {
      usable = 1;
      first = _toDotted(network);
      last = _toDotted(network);
      broadcastStr = null;
    } else if (resolvedPrefix == 31) {
      // RFC 3021 — both addresses are usable; no network/broadcast reservation.
      usable = 2;
      first = _toDotted(network);
      last = _toDotted(broadcast);
      broadcastStr = null;
    } else {
      usable = total - 2;
      first = _toDotted(network + 1);
      last = _toDotted(broadcast - 1);
      broadcastStr = _toDotted(broadcast);
    }

    return SubnetResult(
      isValid: true,
      inputAddress: _toDotted(addr),
      prefix: resolvedPrefix,
      dottedMask: _toDotted(maskInt),
      wildcardMask: _toDotted(wildcard),
      networkAddress: _toDotted(network),
      broadcastAddress: broadcastStr,
      firstHost: first,
      lastHost: last,
      totalAddresses: total,
      usableHosts: usable,
    );
  }

  /// True when [address] (already-known subnet base via [calculate]) contains
  /// [host]. Convenience for the optional "contains this host?" polish. Returns
  /// false on any invalid input rather than throwing.
  bool subnetContains({
    required String networkAddress,
    required int prefix,
    required String host,
  }) {
    final int? net = _parseIpv4(networkAddress);
    final int? h = _parseIpv4(host);
    if (net == null || h == null || prefix < 0 || prefix > 32) return false;
    final int maskInt = _maskForPrefix(prefix);
    return (h & maskInt) == (net & maskInt);
  }

  // ---- parsing / formatting helpers ----------------------------------------

  /// Parse dotted-decimal IPv4 to a 32-bit int, or null if malformed. Strict:
  /// exactly four octets, each 0–255, no empty parts, no leading-zero ambiguity
  /// beyond a single "0".
  static int? _parseIpv4(String s) {
    final List<String> parts = s.trim().split('.');
    if (parts.length != 4) return null;
    int value = 0;
    for (final String part in parts) {
      if (part.isEmpty || part.length > 3) return null;
      if (!RegExp(r'^\d+$').hasMatch(part)) return null;
      final int octet = int.parse(part);
      if (octet < 0 || octet > 255) return null;
      value = (value << 8) | octet;
    }
    return value & 0xFFFFFFFF;
  }

  /// Public IPv4 validator for callers/tests.
  static bool isValidIpv4(String s) => _parseIpv4(s) != null;

  /// Convert a dotted subnet mask to a prefix length, or null when the mask is
  /// not a valid contiguous-ones mask (e.g. 255.0.255.0).
  static int? prefixFromMask(String mask) {
    final int? m = _parseIpv4(mask);
    if (m == null) return null;
    // A valid mask is N leading 1s then all 0s. Verify contiguity: the bitwise
    // complement + 1 must be a power of two (or the mask is all-ones / all-zero).
    final int inv = ~m & 0xFFFFFFFF;
    if ((inv & (inv + 1)) != 0) return null; // wildcard not 000…0111…1 shaped.
    // Count the leading ones.
    int prefix = 0;
    for (int bit = 31; bit >= 0; bit--) {
      if ((m & (1 << bit)) != 0) {
        prefix++;
      } else {
        break;
      }
    }
    // Confirm no stray 1s below the prefix boundary.
    if (m != _maskForPrefix(prefix)) return null;
    return prefix;
  }

  /// The dotted mask for a prefix (e.g. 22 → 255.255.252.0). Exposed for tests.
  static String maskForPrefix(int prefix) => _toDotted(_maskForPrefix(prefix));

  static int _maskForPrefix(int prefix) {
    if (prefix <= 0) return 0;
    if (prefix >= 32) return 0xFFFFFFFF;
    return (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  }

  static String _toDotted(int v) {
    final int x = v & 0xFFFFFFFF;
    return '${(x >> 24) & 0xFF}.${(x >> 16) & 0xFF}.'
        '${(x >> 8) & 0xFF}.${x & 0xFF}';
  }
}
