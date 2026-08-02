// IpBlockMath — the IPv4 block arithmetic that operates on MORE THAN ONE
// network at a time: carving a parent block into right-sized subnets (VLSM),
// summarizing a list of networks into a covering block, and converting a
// start/end range into the minimal set of CIDR blocks that covers it exactly.
//
// The single-subnet math (network, broadcast, mask, host range for ONE
// address + prefix) lives in [SubnetCalcService] and is not duplicated here.
// This file imports that service for the address parser, the dotted formatter
// and the prefix mask, so there is exactly one definition of "a valid IPv4
// address" across both.
//
// WEB SAFETY. `1 << 32` does not do what you want under dart2js, where the
// shift operators use 32-bit semantics. Every size in this file therefore goes
// through [sizeOfPrefix], which returns the /0 case as the literal
// 0x100000000 rather than shifting, and no code path shifts by more than 31.
// Address values stay inside 0..0xFFFFFFFF, where `&`, `|` and `>>` are safe;
// only COUNTS exceed 32 bits, and counts are only ever added and compared.
//
// PURE: no Flutter, no I/O. Every entry point is total, returns a result object
// rather than throwing, and is unit-testable directly.

import 'subnet_calc_service.dart';

/// One CIDR block: a network base address and a prefix length.
class Ipv4Block {
  const Ipv4Block(this.network, this.prefix);

  /// Network base as a 32-bit integer.
  final int network;

  /// Prefix length, 0–32.
  final int prefix;

  /// Number of addresses in the block (2^(32−prefix)).
  int get size => IpBlockMath.sizeOfPrefix(prefix);

  /// Last address in the block, as a 32-bit integer.
  int get lastAddress => network + size - 1;

  /// `10.20.0.0/22`.
  String get cidr => '${SubnetCalcService.toDotted(network)}/$prefix';

  /// Dotted mask for the block, e.g. `255.255.252.0`.
  String get mask => SubnetCalcService.maskForPrefix(prefix);

  /// Usable host count, applying the same rules as the single-subnet
  /// calculator: total−2 for /0–/30, 2 for a /31 (RFC 3021), 1 for a /32.
  int get usableHosts => switch (prefix) {
    32 => 1,
    31 => 2,
    _ => size - 2,
  };

  /// First usable host, or the address itself for a /31 or /32.
  String get firstHost =>
      SubnetCalcService.toDotted(prefix >= 31 ? network : network + 1);

  /// Last usable host, or the upper address for a /31, or the address itself
  /// for a /32.
  String get lastHost =>
      SubnetCalcService.toDotted(prefix >= 31 ? lastAddress : lastAddress - 1);

  /// Broadcast address, or null for a /31 and /32, which have none.
  String? get broadcast =>
      prefix >= 31 ? null : SubnetCalcService.toDotted(lastAddress);

  @override
  bool operator ==(Object other) =>
      other is Ipv4Block && other.network == network && other.prefix == prefix;

  @override
  int get hashCode => Object.hash(network, prefix);

  @override
  String toString() => cidr;
}

/// One parsed line of a network list, or the reason that line was rejected.
class ParsedNetworkLine {
  const ParsedNetworkLine({
    required this.lineNumber,
    required this.raw,
    this.block,
    this.error,
    this.hostBitsWereSet = false,
  });

  /// 1-based line number in the text the user typed, so the UI can say WHICH
  /// line is wrong instead of rejecting the whole box.
  final int lineNumber;

  /// The text of the line, trimmed.
  final String raw;

  /// The parsed block, masked to its network base. Null when [error] is set.
  final Ipv4Block? block;

  /// Why the line was rejected. Null when [block] is set.
  final String? error;

  /// True when the address carried host bits that were masked off, e.g.
  /// `10.0.0.37/24` read as `10.0.0.0/24`. Not an error, but worth saying out
  /// loud so the user is never quietly given a different network than typed.
  final bool hostBitsWereSet;
}

/// One host requirement in a VLSM plan, and what it was given.
class VlsmAllocation {
  const VlsmAllocation({
    required this.name,
    required this.requestedHosts,
    this.block,
    this.unallocatedReason,
  });

  /// The label the user typed, or a generated `Subnet N`.
  final String name;

  /// Usable hosts asked for.
  final int requestedHosts;

  /// The block assigned. Null when the request could not be met.
  final Ipv4Block? block;

  /// Why nothing was assigned. Null when [block] is set.
  final String? unallocatedReason;

  bool get isAllocated => block != null;
}

/// The outcome of a VLSM carve.
class VlsmResult {
  const VlsmResult({
    required this.isValid,
    this.error,
    this.parent,
    this.allocations = const <VlsmAllocation>[],
    this.freeBlocks = const <Ipv4Block>[],
    this.lineErrors = const <ParsedNetworkLine>[],
    this.usedAddresses = 0,
    this.freeAddresses = 0,
    this.notes = const <String>[],
  });

  const VlsmResult.invalid(String message)
    : isValid = false,
      error = message,
      parent = null,
      allocations = const <VlsmAllocation>[],
      freeBlocks = const <Ipv4Block>[],
      lineErrors = const <ParsedNetworkLine>[],
      usedAddresses = 0,
      freeAddresses = 0,
      notes = const <String>[];

  final bool isValid;
  final String? error;

  /// The block being carved.
  final Ipv4Block? parent;

  /// One entry per requirement, in ALLOCATION order (largest first), which is
  /// the order the blocks actually sit in the parent.
  final List<VlsmAllocation> allocations;

  /// What is left over, expressed as the largest aligned CIDR blocks that
  /// cover it exactly.
  final List<Ipv4Block> freeBlocks;

  /// Requirement lines that could not be parsed, with their line numbers.
  final List<ParsedNetworkLine> lineErrors;

  final int usedAddresses;
  final int freeAddresses;

  /// Teaching notes raised by THIS input (a 2-host request, a 1-host request),
  /// so the screen only says the thing when it applies.
  final List<String> notes;
}

/// The outcome of a summarization.
class SummaryResult {
  const SummaryResult({
    required this.isValid,
    this.error,
    this.supernet,
    this.exactBlocks = const <Ipv4Block>[],
    this.inputs = const <ParsedNetworkLine>[],
    this.lineErrors = const <ParsedNetworkLine>[],
    this.coveredAddresses = 0,
    this.supernetAddresses = 0,
    this.extraAddresses = 0,
    this.extraBlocks = const <Ipv4Block>[],
  });

  const SummaryResult.invalid(String message)
    : isValid = false,
      error = message,
      supernet = null,
      exactBlocks = const <Ipv4Block>[],
      inputs = const <ParsedNetworkLine>[],
      lineErrors = const <ParsedNetworkLine>[],
      coveredAddresses = 0,
      supernetAddresses = 0,
      extraAddresses = 0,
      extraBlocks = const <Ipv4Block>[];

  final bool isValid;
  final String? error;

  /// The single smallest CIDR block that contains every input.
  final Ipv4Block? supernet;

  /// The minimal set of CIDR blocks that covers the inputs EXACTLY, with no
  /// address included that was not asked for. Overlaps and adjacencies in the
  /// input are merged.
  final List<Ipv4Block> exactBlocks;

  /// The accepted input lines, in the order typed.
  final List<ParsedNetworkLine> inputs;

  /// Input lines that could not be parsed.
  final List<ParsedNetworkLine> lineErrors;

  /// Addresses actually covered by the inputs (the union, so an overlap is
  /// counted once).
  final int coveredAddresses;

  /// Addresses inside [supernet].
  final int supernetAddresses;

  /// [supernetAddresses] − [coveredAddresses]. The addresses the single
  /// supernet would advertise that nobody asked for. This is the number that
  /// decides whether a route summary is safe.
  final int extraAddresses;

  /// The gaps, as CIDR blocks: what the supernet covers that the inputs do
  /// not. Empty when [extraAddresses] is 0.
  final List<Ipv4Block> extraBlocks;
}

/// Multi-network IPv4 block arithmetic: VLSM, summarization, range ⇄ CIDR.
class IpBlockMath {
  const IpBlockMath._();

  /// Total addresses in a prefix. The /0 case is a literal rather than a shift,
  /// because `1 << 32` is not 2^32 under dart2js.
  static int sizeOfPrefix(int prefix) =>
      prefix <= 0 ? 0x100000000 : (1 << (32 - prefix));

  /// The smallest prefix whose block holds [hosts] usable addresses, applying
  /// the classic reservation (network + broadcast) rather than RFC 3021, so a
  /// 2-host request returns a /30 and not a /31. Returns null for a request of
  /// zero or fewer, or for more hosts than IPv4 has.
  ///
  /// A request of exactly 1 returns /32: a single host route. The caller
  /// surfaces a note for that, since a /32 leaves no room for a gateway.
  static int? prefixForHosts(int hosts) {
    if (hosts < 1) return null;
    if (hosts == 1) return 32;
    for (int p = 30; p >= 0; p--) {
      final int usable = sizeOfPrefix(p) - 2;
      if (usable >= hosts) return p;
    }
    return null;
  }

  /// The minimal set of CIDR blocks that covers [start]..[end] EXACTLY.
  ///
  /// Greedy and aligned: at each step take the largest block that starts at
  /// the cursor, is aligned to its own size, and does not run past [end].
  /// A range that is not CIDR-aligned simply yields more than one block, which
  /// is the honest answer, not an error.
  ///
  /// Returns an empty list when [start] exceeds [end]; callers validate the
  /// order and produce the user-facing message.
  static List<Ipv4Block> rangeToCidr(int start, int end) {
    if (start > end) return const <Ipv4Block>[];
    final List<Ipv4Block> out = <Ipv4Block>[];
    int cur = start;
    while (cur <= end) {
      int chosen = 32;
      // Walk to LARGER blocks (smaller prefix). Both conditions are monotone,
      // so the first failure ends the walk.
      for (int p = 31; p >= 0; p--) {
        final int mask = SubnetCalcService.maskIntForPrefix(p);
        if ((cur & mask) != cur) break; // cursor is not on this boundary
        if (cur + sizeOfPrefix(p) - 1 > end) break; // would overshoot
        chosen = p;
      }
      out.add(Ipv4Block(cur, chosen));
      cur += sizeOfPrefix(chosen);
    }
    return out;
  }

  /// The smallest single block containing both [low] and [high].
  static Ipv4Block coveringBlock(int low, int high) {
    for (int p = 32; p >= 0; p--) {
      final int mask = SubnetCalcService.maskIntForPrefix(p);
      if ((low & mask) == (high & mask)) return Ipv4Block(low & mask, p);
    }
    return const Ipv4Block(0, 0); // unreachable: /0 always matches
  }

  // ─── Parsing ──────────────────────────────────────────────────────────────

  /// Parse a multi-line network list. Accepts, per line:
  ///   `10.0.0.0/24`, `10.0.0.0 255.255.255.0`, `10.0.0.0/255.255.255.0`,
  ///   or a bare `10.0.0.5` (read as a /32).
  /// Blank lines and lines beginning with `#` are skipped. A line may hold
  /// several networks separated by commas or semicolons.
  ///
  /// Every line comes back as a [ParsedNetworkLine] carrying either a block or
  /// a reason, with its 1-based line number, so the UI can point at the bad
  /// line instead of rejecting the whole paste.
  static List<ParsedNetworkLine> parseNetworkList(String text) {
    final List<ParsedNetworkLine> out = <ParsedNetworkLine>[];
    final List<String> lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      for (final String token in line.split(RegExp(r'[,;]'))) {
        final String t = token.trim();
        if (t.isEmpty) continue;
        out.add(_parseOneNetwork(t, i + 1));
      }
    }
    return out;
  }

  static ParsedNetworkLine _parseOneNetwork(String token, int lineNumber) {
    String addrPart = token;
    String? maskPart;

    if (token.contains('/')) {
      final List<String> halves = token.split('/');
      if (halves.length != 2) {
        return ParsedNetworkLine(
          lineNumber: lineNumber,
          raw: token,
          error: 'More than one "/". Write a network as 10.0.0.0/24.',
        );
      }
      addrPart = halves[0].trim();
      maskPart = halves[1].trim();
    } else if (token.contains(RegExp(r'\s'))) {
      final List<String> halves = token.split(RegExp(r'\s+'));
      if (halves.length != 2) {
        return ParsedNetworkLine(
          lineNumber: lineNumber,
          raw: token,
          error:
              'Expected an address and one mask, e.g. '
              '10.0.0.0 255.255.255.0.',
        );
      }
      addrPart = halves[0];
      maskPart = halves[1];
    }

    final int? addr = SubnetCalcService.parseIpv4ToInt(addrPart);
    if (addr == null) {
      return ParsedNetworkLine(
        lineNumber: lineNumber,
        raw: token,
        error: '"$addrPart" is not a valid IPv4 address.',
      );
    }

    int prefix;
    if (maskPart == null || maskPart.isEmpty) {
      prefix = 32; // a bare address is a single host
    } else if (maskPart.contains('.')) {
      final int? p = SubnetCalcService.prefixFromMask(maskPart);
      if (p == null) {
        return ParsedNetworkLine(
          lineNumber: lineNumber,
          raw: token,
          error:
              '"$maskPart" is not a valid subnet mask. A mask is a '
              'contiguous run of 1 bits, e.g. 255.255.255.0.',
        );
      }
      prefix = p;
    } else {
      final int? p = int.tryParse(maskPart);
      if (p == null || p < 0 || p > 32) {
        return ParsedNetworkLine(
          lineNumber: lineNumber,
          raw: token,
          error: 'Prefix must be a number 0 to 32.',
        );
      }
      prefix = p;
    }

    final int mask = SubnetCalcService.maskIntForPrefix(prefix);
    final int base = addr & mask;
    return ParsedNetworkLine(
      lineNumber: lineNumber,
      raw: token,
      block: Ipv4Block(base, prefix),
      hostBitsWereSet: base != addr,
    );
  }

  /// Parse a multi-line requirements list for the VLSM planner. Accepts, per
  /// line: `Staff 500`, `Staff,500`, `Staff: 500`, or a bare `500`. Blank
  /// lines and `#` comments are skipped. An unnamed line is given
  /// `Subnet <n>`, numbered by its position among the accepted lines.
  static List<
    ({int lineNumber, String raw, String? name, int? hosts, String? error})
  >
  parseRequirements(String text) {
    final List<
      ({int lineNumber, String raw, String? name, int? hosts, String? error})
    >
    out =
        <
          ({
            int lineNumber,
            String raw,
            String? name,
            int? hosts,
            String? error,
          })
        >[];
    final List<String> lines = text.split('\n');
    int accepted = 0;
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // The host count is the LAST number on the line; everything before it is
      // the name. That reads "Floor 3 AV 40" the way a person means it.
      final RegExpMatch? m = RegExp(
        r'^(.*?)[\s,:=]*(\d+)\s*$',
      ).firstMatch(line);
      if (m == null) {
        out.add((
          lineNumber: i + 1,
          raw: line,
          name: null,
          hosts: null,
          error: 'Expected a host count, e.g. "Staff 500" or just "500".',
        ));
        continue;
      }
      final int hosts = int.parse(m.group(2)!);
      accepted++;
      final String rawName = m.group(1)!.trim();
      if (hosts < 1) {
        out.add((
          lineNumber: i + 1,
          raw: line,
          name: null,
          hosts: null,
          error: 'A subnet needs at least 1 host.',
        ));
        accepted--;
        continue;
      }
      out.add((
        lineNumber: i + 1,
        raw: line,
        name: rawName.isEmpty ? 'Subnet $accepted' : rawName,
        hosts: hosts,
        error: null,
      ));
    }
    return out;
  }

  // ─── VLSM ─────────────────────────────────────────────────────────────────

  /// Carve [parentCidr] into blocks sized for [requirementsText].
  ///
  /// Allocation is the classic greedy VLSM order: sort by size descending and
  /// place each block at the next free address. Because every block size is a
  /// power of two and the list is descending, each placement lands on its own
  /// boundary with no padding, which is what makes VLSM efficient.
  ///
  /// A requirement that does not fit is reported as unallocated WITH ITS
  /// REASON and the rest of the plan still computes. Failing the whole carve
  /// because the last VLAN overflowed would hide the four that fit.
  static VlsmResult vlsm({
    required String parentCidr,
    required String requirementsText,
  }) {
    final List<ParsedNetworkLine> parentParse = parseNetworkList(parentCidr);
    if (parentParse.isEmpty) {
      return const VlsmResult.invalid(
        'Enter the block you are carving up, e.g. 10.20.0.0/22.',
      );
    }
    if (parentParse.length > 1) {
      return const VlsmResult.invalid(
        'Enter one parent block. To summarize several networks, switch to '
        'Summarize.',
      );
    }
    final ParsedNetworkLine p = parentParse.first;
    if (p.error != null) return VlsmResult.invalid(p.error!);
    final Ipv4Block parent = p.block!;

    final List<
      ({int lineNumber, String raw, String? name, int? hosts, String? error})
    >
    reqs = parseRequirements(requirementsText);
    final List<ParsedNetworkLine> lineErrors = <ParsedNetworkLine>[
      for (final r in reqs)
        if (r.error != null)
          ParsedNetworkLine(
            lineNumber: r.lineNumber,
            raw: r.raw,
            error: r.error,
          ),
    ];
    final List<({String name, int hosts})> good = <({String name, int hosts})>[
      for (final r in reqs)
        if (r.error == null) (name: r.name!, hosts: r.hosts!),
    ];
    if (good.isEmpty) {
      return VlsmResult(
        isValid: true,
        parent: parent,
        lineErrors: lineErrors,
        freeBlocks: <Ipv4Block>[parent],
        freeAddresses: parent.size,
        notes: const <String>[],
      );
    }

    // Largest first. A stable tie-break on the original order keeps the output
    // predictable when two VLANs ask for the same size.
    final List<({String name, int hosts, int order})> sorted =
        <({String name, int hosts, int order})>[
          for (int i = 0; i < good.length; i++)
            (name: good[i].name, hosts: good[i].hosts, order: i),
        ]..sort((a, b) {
          final int byHosts = b.hosts.compareTo(a.hosts);
          return byHosts != 0 ? byHosts : a.order.compareTo(b.order);
        });

    final List<VlsmAllocation> allocations = <VlsmAllocation>[];
    int cursor = parent.network;
    final int parentEnd = parent.lastAddress;
    int used = 0;

    for (final ({String name, int hosts, int order}) r in sorted) {
      final int? prefix = prefixForHosts(r.hosts);
      if (prefix == null) {
        allocations.add(
          VlsmAllocation(
            name: r.name,
            requestedHosts: r.hosts,
            unallocatedReason:
                'IPv4 has no block that large. The biggest possible is a /0.',
          ),
        );
        continue;
      }
      if (prefix < parent.prefix) {
        allocations.add(
          VlsmAllocation(
            name: r.name,
            requestedHosts: r.hosts,
            unallocatedReason:
                '${r.hosts} hosts needs a /$prefix, and the parent block is '
                'only a /${parent.prefix}.',
          ),
        );
        continue;
      }
      final int size = sizeOfPrefix(prefix);
      if (cursor > parentEnd || cursor + size - 1 > parentEnd) {
        allocations.add(
          VlsmAllocation(
            name: r.name,
            requestedHosts: r.hosts,
            unallocatedReason:
                'Needs a /$prefix ($size addresses); the parent block ran out.',
          ),
        );
        continue;
      }
      allocations.add(
        VlsmAllocation(
          name: r.name,
          requestedHosts: r.hosts,
          block: Ipv4Block(cursor, prefix),
        ),
      );
      cursor += size;
      used += size;
    }

    final List<Ipv4Block> free = cursor > parentEnd
        ? const <Ipv4Block>[]
        : rangeToCidr(cursor, parentEnd);

    final List<String> notes = <String>[];
    if (good.any((({String name, int hosts}) r) => r.hosts == 2)) {
      notes.add(
        'A 2-host request gets a /30 here, which reserves a network and a '
        'broadcast address. If your gear supports RFC 3021, a /31 carries the '
        'same two hosts in half the space on a point-to-point link.',
      );
    }
    if (good.any((({String name, int hosts}) r) => r.hosts == 1)) {
      notes.add(
        'A 1-host request gets a /32, a single host route. It leaves no room '
        'for a gateway, so ask for 2 if you meant a device plus its router.',
      );
    }

    return VlsmResult(
      isValid: true,
      parent: parent,
      allocations: allocations,
      freeBlocks: free,
      lineErrors: lineErrors,
      usedAddresses: used,
      freeAddresses: parent.size - used,
      notes: notes,
    );
  }

  // ─── Summarization ────────────────────────────────────────────────────────

  /// Summarize a list of networks.
  ///
  /// Returns BOTH answers, because they are different questions and confusing
  /// them is how a summary route black-holes traffic:
  ///   * [SummaryResult.supernet] — the one block that covers everything. It
  ///     usually covers MORE than was asked for.
  ///   * [SummaryResult.exactBlocks] — the minimal set that covers exactly the
  ///     union of the inputs and nothing else.
  /// The difference between them is reported as
  /// [SummaryResult.extraAddresses] and enumerated as
  /// [SummaryResult.extraBlocks].
  static SummaryResult summarize(String networksText) {
    final List<ParsedNetworkLine> parsed = parseNetworkList(networksText);
    final List<ParsedNetworkLine> errors = <ParsedNetworkLine>[
      for (final ParsedNetworkLine l in parsed)
        if (l.error != null) l,
    ];
    final List<ParsedNetworkLine> good = <ParsedNetworkLine>[
      for (final ParsedNetworkLine l in parsed)
        if (l.block != null) l,
    ];
    if (good.isEmpty) {
      return SummaryResult(
        isValid: false,
        error: errors.isEmpty
            ? 'Enter one network per line, e.g. 10.0.0.0/24.'
            : 'No valid network on any line yet.',
        lineErrors: errors,
      );
    }

    // Merge the input ranges into disjoint, sorted ranges so an overlap is
    // counted once and two adjacent blocks become one range.
    final List<({int start, int end})> ranges =
        <({int start, int end})>[
          for (final ParsedNetworkLine l in good)
            (start: l.block!.network, end: l.block!.lastAddress),
        ]..sort((({int start, int end}) a, ({int start, int end}) b) {
          final int byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.end.compareTo(b.end);
        });

    final List<({int start, int end})> merged = <({int start, int end})>[];
    for (final ({int start, int end}) r in ranges) {
      if (merged.isEmpty || r.start > merged.last.end + 1) {
        merged.add(r);
      } else if (r.end > merged.last.end) {
        merged[merged.length - 1] = (start: merged.last.start, end: r.end);
      }
    }

    int covered = 0;
    final List<Ipv4Block> exact = <Ipv4Block>[];
    for (final ({int start, int end}) r in merged) {
      covered += r.end - r.start + 1;
      exact.addAll(rangeToCidr(r.start, r.end));
    }

    final int low = merged.first.start;
    final int high = merged.last.end;
    final Ipv4Block supernet = coveringBlock(low, high);

    // The gaps: what the supernet covers that the inputs do not. Walk the
    // supernet from its first address, emitting the holes between merged
    // ranges plus any lead-in and tail.
    final List<Ipv4Block> gaps = <Ipv4Block>[];
    int cur = supernet.network;
    for (final ({int start, int end}) r in merged) {
      if (r.start > cur) gaps.addAll(rangeToCidr(cur, r.start - 1));
      cur = r.end + 1;
    }
    if (cur <= supernet.lastAddress) {
      gaps.addAll(rangeToCidr(cur, supernet.lastAddress));
    }

    return SummaryResult(
      isValid: true,
      supernet: supernet,
      exactBlocks: exact,
      inputs: good,
      lineErrors: errors,
      coveredAddresses: covered,
      supernetAddresses: supernet.size,
      extraAddresses: supernet.size - covered,
      extraBlocks: gaps,
    );
  }
}
