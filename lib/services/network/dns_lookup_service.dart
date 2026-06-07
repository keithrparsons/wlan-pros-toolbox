// DnsLookupService — resolves DNS records over DNS-over-HTTPS (DoH).
//
// Transport decision: DoH (HTTPS GET to a JSON resolver), via `basic_utils`
// DnsUtils, NOT raw UDP-to-port-53.
//
// Why DoH over raw UDP/53:
//  - Uniform across iOS / Android / macOS / Windows. Raw UDP/53 on iOS sits
//    under the local-network permission gate and is frequently blocked by
//    captive portals and corporate firewalls; DoH rides HTTPS:443 which
//    traverses cleanly.
//  - Needs only the standard network-client entitlement we already add for
//    Port Scan — no extra socket capability.
//  - `basic_utils` is MIT-licensed, actively maintained, pure-Dart, and ships
//    a typed `DnsUtils.lookupRecord` returning structured `RRecord`s.
//  - The resolver is selectable (Google / Cloudflare), so a blocked resolver
//    is a one-line failover, not a redesign.
//
// Tradeoff accepted: DoH resolves against a public recursive resolver
// (Google 8.8.8.8 / Cloudflare 1.1.1.1) rather than the device's configured
// resolver. For a Wi-Fi pro this is usually desirable (authoritative answer,
// not the local cache), and the Interface Information tool already surfaces
// the device's *configured* DNS servers separately. PTR/rDNS is supported by
// converting an IP to its in-addr.arpa / ip6.arpa name before the query.
//
// Web safety: this file does no `dart:io` socket work — it is HTTPS only — but
// it is still gated behind `NetworkSupport.dnsLookupSupported` at the UI layer
// per the §15 native-only product decision. Nothing here imports `dart:io`.

import 'package:basic_utils/basic_utils.dart';

/// DNS record types this tool can query. Mirrors the HE.NET match target
/// (brief §4): SOA, NS, A, AAAA, MX, TXT, plus PTR (rDNS). Extended for the
/// advanced-records pass with SPF (read from TXT), SRV, and CAA.
enum DnsRecordType { a, aaaa, mx, txt, ns, soa, ptr, srv, caa, spf }

extension DnsRecordTypeLabel on DnsRecordType {
  /// Human label for the UI selector.
  String get label {
    switch (this) {
      case DnsRecordType.a:
        return 'A';
      case DnsRecordType.aaaa:
        return 'AAAA';
      case DnsRecordType.mx:
        return 'MX';
      case DnsRecordType.txt:
        return 'TXT';
      case DnsRecordType.ns:
        return 'NS';
      case DnsRecordType.soa:
        return 'SOA';
      case DnsRecordType.ptr:
        return 'PTR (rDNS)';
      case DnsRecordType.srv:
        return 'SRV';
      case DnsRecordType.caa:
        return 'CAA';
      case DnsRecordType.spf:
        return 'SPF';
    }
  }

  /// The `basic_utils` enum value used on the wire for this type.
  ///
  /// SPF is not its own DNS query: RFC 7208 deprecated the type-99 SPF record,
  /// and modern SPF policy lives in a TXT record whose value starts with
  /// `v=spf1`. So SPF queries TXT and the service filters for the policy line.
  RRecordType get rrType {
    switch (this) {
      case DnsRecordType.a:
        return RRecordType.A;
      case DnsRecordType.aaaa:
        return RRecordType.AAAA;
      case DnsRecordType.mx:
        return RRecordType.MX;
      case DnsRecordType.txt:
        return RRecordType.TXT;
      case DnsRecordType.ns:
        return RRecordType.NS;
      case DnsRecordType.soa:
        return RRecordType.SOA;
      case DnsRecordType.ptr:
        return RRecordType.PTR;
      case DnsRecordType.srv:
        return RRecordType.SRV;
      case DnsRecordType.caa:
        return RRecordType.CAA;
      case DnsRecordType.spf:
        return RRecordType.TXT;
    }
  }
}

/// Parsed fields of an SRV record (`_service._proto.name` → host:port).
/// RFC 2782 wire form in the resolver's `data` is
/// `<priority> <weight> <port> <target>`.
class SrvData {
  const SrvData({
    required this.priority,
    required this.weight,
    required this.port,
    required this.target,
  });

  final int priority;
  final int weight;
  final int port;
  final String target;

  /// Parse the resolver `data` string. Returns null if it is not the expected
  /// four-field form. The target's trailing root dot is preserved as the
  /// resolver returns it (callers can trim for display).
  static SrvData? parse(String data) {
    final List<String> parts =
        data.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length != 4) return null;
    final int? priority = int.tryParse(parts[0]);
    final int? weight = int.tryParse(parts[1]);
    final int? port = int.tryParse(parts[2]);
    if (priority == null || weight == null || port == null) return null;
    return SrvData(
      priority: priority,
      weight: weight,
      port: port,
      target: parts[3],
    );
  }

  /// Compact one-line display: `host:port  (prio P, weight W)`.
  String get display => '$target:$port  (prio $priority, weight $weight)';
}

/// Parsed fields of a CAA record (RFC 8659). Wire form in the resolver's
/// `data` is `<flags> <tag> "<value>"`, e.g. `0 issue "letsencrypt.org"`.
class CaaData {
  const CaaData({
    required this.flags,
    required this.tag,
    required this.value,
  });

  final int flags;
  final String tag;
  final String value;

  /// Parse the resolver `data` string. Returns null if it is not the expected
  /// `flags tag "value"` form. The quoted value is unquoted.
  static CaaData? parse(String data) {
    final String trimmed = data.trim();
    final Match? m = RegExp(r'^(\d+)\s+(\S+)\s+"?(.*?)"?$').firstMatch(trimmed);
    if (m == null) return null;
    final int? flags = int.tryParse(m.group(1)!);
    if (flags == null) return null;
    return CaaData(
      flags: flags,
      tag: m.group(2)!,
      value: m.group(3)!,
    );
  }

  /// Compact one-line display: `tag "value"  (flags F)`.
  String get display => '$tag "$value"  (flags $flags)';
}

/// Which public DoH resolver to query. Failover target if one is blocked.
///
/// Quad9 (9.9.9.9) is a security/malware-filtering resolver: it refuses to
/// resolve domains on its threat-intel blocklists, so a name that resolves on
/// Google/Cloudflare but comes back empty on Quad9 is a signal the domain is
/// flagged as malicious. That is a feature for a Wi-Fi pro vetting a network,
/// not a bug — the empty state is the honest answer (GL-005), and the help
/// entry documents the filtering so the result is never misread as a lookup
/// failure.
enum DohResolver { google, cloudflare, quad9 }

extension DohResolverProvider on DohResolver {
  /// The `basic_utils` provider for Google/Cloudflare. Quad9 has no
  /// `DnsApiProvider` (the package only ships Google + Cloudflare), so it is
  /// resolved directly against its JSON DoH endpoint — see [DohResolverEndpoint]
  /// and the service's default resolver. Reading `.provider` on Quad9 throws so
  /// a wrong code path fails loud rather than silently querying Google.
  DnsApiProvider get provider {
    switch (this) {
      case DohResolver.google:
        return DnsApiProvider.GOOGLE;
      case DohResolver.cloudflare:
        return DnsApiProvider.CLOUDFLARE;
      case DohResolver.quad9:
        throw StateError(
          'Quad9 has no basic_utils DnsApiProvider; resolve it via its '
          'JSON DoH endpoint instead.',
        );
    }
  }

  String get label {
    switch (this) {
      case DohResolver.google:
        return 'Google (8.8.8.8)';
      case DohResolver.cloudflare:
        return 'Cloudflare (1.1.1.1)';
      case DohResolver.quad9:
        return 'Quad9 (9.9.9.9)';
    }
  }
}

extension DohResolverEndpoint on DohResolver {
  /// Quad9's JSON DoH endpoint (Google/Cloudflare-compatible `application/
  /// dns-json` GET API). Port 5053 serves the JSON API; the 443 `/dns-query`
  /// path is RFC 8484 wireformat, which this tool does not speak. HTTPS only,
  /// keyless — satisfies GL-008 (no cleartext, no key to leak). Null for the
  /// resolvers that `basic_utils` already routes via [DnsApiProvider].
  String? get jsonEndpoint =>
      this == DohResolver.quad9 ? 'https://dns.quad9.net:5053/dns-query' : null;
}

/// One resolved record row.
class DnsRecord {
  const DnsRecord({
    required this.type,
    required this.name,
    required this.ttl,
    required this.data,
  });

  /// Record type as the resolver reported it (numeric → label resolved here).
  final String type;

  /// The owner name the record is bound to.
  final String name;

  /// Time-to-live in seconds, or null if the resolver omitted it.
  final int? ttl;

  /// The record payload (IP, mail exchanger, text, nameserver, etc.).
  final String data;
}

/// Outcome of a lookup — distinguishes "resolved, here are the records",
/// "resolved, but the name has no records of this type", and "the query
/// failed" so the UI can render three distinct states (success / empty /
/// error) per SOP-007 §5.
class DnsLookupResult {
  const DnsLookupResult._({
    required this.records,
    required this.queriedName,
    required this.type,
    required this.resolver,
    this.errorMessage,
  });

  factory DnsLookupResult.success({
    required List<DnsRecord> records,
    required String queriedName,
    required DnsRecordType type,
    required DohResolver resolver,
  }) =>
      DnsLookupResult._(
        records: records,
        queriedName: queriedName,
        type: type,
        resolver: resolver,
      );

  factory DnsLookupResult.failure({
    required String queriedName,
    required DnsRecordType type,
    required DohResolver resolver,
    required String message,
  }) =>
      DnsLookupResult._(
        records: const <DnsRecord>[],
        queriedName: queriedName,
        type: type,
        resolver: resolver,
        errorMessage: message,
      );

  final List<DnsRecord> records;
  final String queriedName;
  final DnsRecordType type;
  final DohResolver resolver;
  final String? errorMessage;

  bool get isError => errorMessage != null;
  bool get isEmpty => !isError && records.isEmpty;
}

/// One record type's slice of a dig-style multi-type lookup: the type asked
/// for, the records that came back, and (if the query failed) why. Empty
/// `records` with a null `errorMessage` is the honest "resolved, no records of
/// this type" state — distinct from a failure (GL-005).
class DnsDigSection {
  const DnsDigSection({
    required this.type,
    required this.records,
    this.errorMessage,
  });

  final DnsRecordType type;
  final List<DnsRecord> records;
  final String? errorMessage;

  bool get isError => errorMessage != null;
  bool get isEmpty => !isError && records.isEmpty;
}

/// Outcome of a dig-style "all records" lookup — one [DnsDigSection] per
/// queried type, in display order. Distinguishes a name that resolved with at
/// least one record somewhere from one where every section came back empty,
/// and from a whole-query validation failure (e.g. blank input).
class DnsDigResult {
  const DnsDigResult({
    required this.queriedName,
    required this.resolver,
    required this.sections,
    this.errorMessage,
  });

  final String queriedName;
  final DohResolver resolver;
  final List<DnsDigSection> sections;

  /// Set only for a whole-query failure (validation), not a per-section error.
  final String? errorMessage;

  bool get isError => errorMessage != null;

  /// Sections that returned at least one record, in order.
  List<DnsDigSection> get nonEmptySections =>
      sections.where((DnsDigSection s) => s.records.isNotEmpty).toList();

  /// Sections whose query failed mid-sweep, in order. These carry an
  /// [DnsDigSection.errorMessage] and must be surfaced honestly (GL-005) — a
  /// failed type is NOT the same as a type that resolved with zero records.
  List<DnsDigSection> get erroredSections =>
      sections.where((DnsDigSection s) => s.isError).toList();

  /// True when at least one queried type failed to resolve. The summary, the
  /// card body, and the SR announcement must all disclose this so the success
  /// count never overstates completeness.
  bool get hasPartialFailure => erroredSections.isNotEmpty;

  /// True when every queried section failed to resolve (no records anywhere and
  /// no section resolved cleanly). This is a total lookup failure that must NOT
  /// read as a clean empty result.
  bool get isAllErrored =>
      !isError &&
      sections.isNotEmpty &&
      sections.every((DnsDigSection s) => s.isError);

  /// Total records across all sections.
  int get recordCount =>
      sections.fold(0, (int sum, DnsDigSection s) => sum + s.records.length);

  /// True when the name resolved but every queried type came back empty (no
  /// per-section had records) and no section errored. The honest "name exists,
  /// nothing here" state.
  bool get isAllEmpty =>
      !isError &&
      recordCount == 0 &&
      sections.every((DnsDigSection s) => !s.isError);
}

/// Resolves DNS records via DoH. Injectable resolver function keeps it
/// unit-testable without a live network.
class DnsLookupService {
  DnsLookupService({
    Future<List<RRecord>?> Function(
      String name,
      RRecordType type, {
      required DohResolver resolver,
    })? resolver,
  }) : _resolve = resolver ?? _defaultResolve;

  // The injected seam routes by the app's own [DohResolver] (not the package's
  // [DnsApiProvider]) so all three resolvers — including Quad9, which has no
  // DnsApiProvider — share one path that tests can fake. The default
  // implementation maps each resolver to its transport.
  final Future<List<RRecord>?> Function(
    String name,
    RRecordType type, {
    required DohResolver resolver,
  }) _resolve;

  static Future<List<RRecord>?> _defaultResolve(
    String name,
    RRecordType type, {
    required DohResolver resolver,
  }) {
    // Quad9 isn't a basic_utils DnsApiProvider, so issue the same JSON DoH GET
    // the package makes (name/type/dnssec params, Accept: application/dns-json),
    // then parse with the package's own ResolveResponse so the RRecord shape is
    // identical to the Google/Cloudflare path. HTTPS only, keyless (GL-008).
    final String? endpoint = resolver.jsonEndpoint;
    if (endpoint != null) {
      return _resolveViaJson(name, type, endpoint);
    }
    return DnsUtils.lookupRecord(name, type, provider: resolver.provider);
  }

  /// Direct JSON-DoH resolve for resolvers `basic_utils` does not ship (Quad9).
  /// Mirrors `DnsUtils.lookupRecord`'s request exactly so the answer parses the
  /// same way.
  static Future<List<RRecord>?> _resolveViaJson(
    String name,
    RRecordType type,
    String endpoint,
  ) async {
    final Map<String, dynamic> body = await HttpUtils.getForJson(
      endpoint,
      queryParameters: <String, dynamic>{
        'name': name,
        'type': DnsUtils.rRecordTypeToInt(type).toString(),
        'dnssec': 'false',
      },
      headers: <String, String>{'Accept': 'application/dns-json'},
    );
    return ResolveResponse.fromJson(body).answer;
  }

  /// Resolve [rawQuery] for [type] against [resolver].
  ///
  /// For [DnsRecordType.ptr] the input is treated as an IP literal and
  /// rewritten to its reverse-DNS name (in-addr.arpa / ip6.arpa) before the
  /// query. For all other types the input is treated as a hostname.
  Future<DnsLookupResult> lookup({
    required String rawQuery,
    required DnsRecordType type,
    DohResolver resolver = DohResolver.cloudflare,
  }) async {
    final String trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return DnsLookupResult.failure(
        queriedName: trimmed,
        type: type,
        resolver: resolver,
        message: 'Enter a hostname to look up.',
      );
    }

    String queryName = trimmed;
    if (type == DnsRecordType.ptr) {
      final String? arpa = _toReverseName(trimmed);
      if (arpa == null) {
        return DnsLookupResult.failure(
          queriedName: trimmed,
          type: type,
          resolver: resolver,
          message: 'PTR lookup needs a valid IPv4 or IPv6 address.',
        );
      }
      queryName = arpa;
    }

    try {
      final List<RRecord>? raw = await _resolve(
        queryName,
        type.rrType,
        resolver: resolver,
      );

      if (raw == null || raw.isEmpty) {
        return DnsLookupResult.success(
          records: const <DnsRecord>[],
          queriedName: queryName,
          type: type,
          resolver: resolver,
        );
      }

      // SPF is read from TXT (RFC 7208). Keep only the SPF policy line(s) so a
      // domain with unrelated TXT records (verification tokens, DKIM, etc.)
      // does not pollute the SPF view. An SPF policy is a TXT value starting
      // with `v=spf1`.
      Iterable<RRecord> source = raw;
      if (type == DnsRecordType.spf) {
        source = raw.where((RRecord r) => _isSpfTxt(r.data));
        if (source.isEmpty) {
          // Resolved a TXT set, but none of it was SPF: that is the empty
          // state for an SPF query, not an error.
          return DnsLookupResult.success(
            records: const <DnsRecord>[],
            queriedName: queryName,
            type: type,
            resolver: resolver,
          );
        }
      }

      final List<DnsRecord> records = source
          .map(
            (RRecord r) => DnsRecord(
              // For an SPF query the wire type is TXT; label it SPF so the row
              // reads true to what the user asked for.
              type: type == DnsRecordType.spf
                  ? 'SPF'
                  : _recordTypeLabel(r.rType),
              name: r.name,
              ttl: r.ttl,
              data: type == DnsRecordType.spf ? _unquoteTxt(r.data) : r.data,
            ),
          )
          .toList(growable: false);

      return DnsLookupResult.success(
        records: records,
        queriedName: queryName,
        type: type,
        resolver: resolver,
      );
    } on Object catch (e) {
      return DnsLookupResult.failure(
        queriedName: queryName,
        type: type,
        resolver: resolver,
        message: 'Lookup failed: ${_friendlyError(e)}',
      );
    }
  }

  /// The record types a dig-style "all records" sweep queries, in the order
  /// `dig` itself presents them: identity/authority first (SOA, NS), then the
  /// address and routing records, then policy/text. PTR is excluded — it is an
  /// IP→name query that does not belong in a hostname sweep (it has its own
  /// one-tap path in the UI). SPF is excluded as a top-level section because it
  /// is a filtered view of TXT, which the sweep already shows in full.
  static const List<DnsRecordType> digTypeOrder = <DnsRecordType>[
    DnsRecordType.soa,
    DnsRecordType.ns,
    DnsRecordType.a,
    DnsRecordType.aaaa,
    DnsRecordType.mx,
    DnsRecordType.txt,
    DnsRecordType.srv,
    DnsRecordType.caa,
  ];

  /// Dig-style sweep: resolve every type in [digTypeOrder] for [rawQuery] in a
  /// single call and return one section per type. Each type is resolved with
  /// the existing single-type [lookup] path (same DoH transport, same parsing),
  /// so a per-type failure becomes a per-section error rather than failing the
  /// whole sweep — the user still sees the records that did resolve.
  ///
  /// The queries fan out concurrently (`Future.wait`) so a sweep costs roughly
  /// one round-trip, not eight in series. Order is restored to [digTypeOrder]
  /// before returning.
  Future<DnsDigResult> lookupAll({
    required String rawQuery,
    DohResolver resolver = DohResolver.cloudflare,
  }) async {
    final String trimmed = rawQuery.trim();
    if (trimmed.isEmpty) {
      return DnsDigResult(
        queriedName: trimmed,
        resolver: resolver,
        sections: const <DnsDigSection>[],
        errorMessage: 'Enter a hostname to look up.',
      );
    }

    final List<DnsLookupResult> results = await Future.wait(
      digTypeOrder.map(
        (DnsRecordType t) => lookup(
          rawQuery: trimmed,
          type: t,
          resolver: resolver,
        ),
      ),
    );

    final List<DnsDigSection> sections = <DnsDigSection>[
      for (final DnsLookupResult r in results)
        DnsDigSection(
          type: r.type,
          records: r.records,
          errorMessage: r.errorMessage,
        ),
    ];

    return DnsDigResult(
      queriedName: trimmed,
      resolver: resolver,
      sections: sections,
    );
  }

  /// Map the numeric DNS type code the resolver returns to a readable label.
  static String _recordTypeLabel(int code) {
    switch (code) {
      case 1:
        return 'A';
      case 2:
        return 'NS';
      case 5:
        return 'CNAME';
      case 6:
        return 'SOA';
      case 12:
        return 'PTR';
      case 15:
        return 'MX';
      case 16:
        return 'TXT';
      case 28:
        return 'AAAA';
      case 33:
        return 'SRV';
      case 99:
        return 'SPF';
      case 257:
        return 'CAA';
      default:
        return 'TYPE$code';
    }
  }

  /// True when a TXT value carries an SPF policy (`v=spf1 ...`), case- and
  /// quote-insensitive.
  static bool _isSpfTxt(String txt) =>
      _unquoteTxt(txt).trimLeft().toLowerCase().startsWith('v=spf1');

  /// DoH JSON returns TXT values wrapped in double quotes (and long records
  /// split into multiple quoted chunks). Strip the wrapping quotes and join
  /// adjacent chunks so the SPF policy reads as one string.
  static String _unquoteTxt(String txt) {
    final String t = txt.trim();
    if (!t.contains('"')) return t;
    final Iterable<Match> chunks = RegExp(r'"([^"]*)"').allMatches(t);
    if (chunks.isEmpty) return t;
    return chunks.map((m) => m.group(1)!).join();
  }

  static String _friendlyError(Object e) {
    final String s = e.toString();
    // Keep it short — the screen shows this inline.
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  /// Convert an IP literal to its reverse-DNS name. Returns null if [ip] is
  /// not a parseable IPv4 or (uncompressed/compressed) IPv6 literal.
  static String? _toReverseName(String ip) {
    if (ip.contains(':')) {
      return _ipv6ToArpa(ip);
    }
    return _ipv4ToArpa(ip);
  }

  static String? _ipv4ToArpa(String ip) {
    final List<String> parts = ip.split('.');
    if (parts.length != 4) return null;
    for (final String p in parts) {
      final int? n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
    }
    return '${parts.reversed.join('.')}.in-addr.arpa';
  }

  static String? _ipv6ToArpa(String ip) {
    final List<int>? bytes = _parseIPv6(ip);
    if (bytes == null) return null;
    final StringBuffer hex = StringBuffer();
    for (final int b in bytes) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    final String nibbles = hex.toString();
    final StringBuffer out = StringBuffer();
    for (int i = nibbles.length - 1; i >= 0; i--) {
      out.write(nibbles[i]);
      out.write('.');
    }
    out.write('ip6.arpa');
    return out.toString();
  }

  /// Minimal IPv6 literal parser → 16 bytes. Handles `::` compression. Returns
  /// null on malformed input.
  static List<int>? _parseIPv6(String ip) {
    final String s = ip.trim();
    if (!s.contains(':')) return null;

    final List<String> halves = s.split('::');
    if (halves.length > 2) return null;

    List<int> bytesFromGroups(String segment) {
      if (segment.isEmpty) return <int>[];
      final List<String> groups = segment.split(':');
      final List<int> out = <int>[];
      for (final String g in groups) {
        if (g.isEmpty) return <int>[-1]; // signal malformed
        final int? v = int.tryParse(g, radix: 16);
        if (v == null || v < 0 || v > 0xFFFF) return <int>[-1];
        out.add((v >> 8) & 0xFF);
        out.add(v & 0xFF);
      }
      return out;
    }

    if (halves.length == 2) {
      final List<int> head = bytesFromGroups(halves[0]);
      final List<int> tail = bytesFromGroups(halves[1]);
      if (head.contains(-1) || tail.contains(-1)) return null;
      final int fill = 16 - head.length - tail.length;
      if (fill < 0) return null;
      return <int>[...head, ...List<int>.filled(fill, 0), ...tail];
    } else {
      final List<int> all = bytesFromGroups(s);
      if (all.contains(-1) || all.length != 16) return null;
      return all;
    }
  }
}
