// WhoisService — domain/IP registration lookup over WHOIS (TCP port 43).
//
// TRANSPORT DECISION: raw WHOIS over TCP/43 via `Socket.connect`, NOT a
// `Process.run('whois')` subprocess and NOT RDAP-over-HTTPS.
//
// Why TCP/43 over a system `whois` binary:
//  - The macOS App Sandbox blocks subprocess spawning (this is exactly what
//    limited traceroute to desktop). Shelling out to `whois` would break on
//    macOS-sandboxed and iOS builds. A TCP socket needs only the
//    network-client capability we already ship for the port scanner, and it
//    works identically on iOS / Android / macOS / Windows.
//
// Why TCP/43 over RDAP/HTTPS:
//  - RDAP is the modern structured successor and would give parsed JSON
//    natively, but coverage is still uneven across ccTLDs and many registry
//    RDAP endpoints set no CORS headers — so RDAP is no more web-capable than
//    WHOIS, while WHOIS/43 covers essentially every TLD and IP registry today.
//    We chose the path with the widest universal coverage on native and route
//    web to the download-the-app fallback either way.
//
// REFERRAL HANDLING (the two-hop dance):
//  WHOIS is hierarchical. A query to `whois.iana.org` for a TLD or IP returns
//  a `refer:`/`whois:` line naming the authoritative registry server. We:
//    1. Query whois.iana.org with the target.
//    2. Parse the referral server from the response.
//    3. Re-query that authoritative server for the full record.
//  If no referral is found we keep the IANA record (it is still useful for IPs
//  and some TLDs). The UI shows the raw authoritative record plus a few parsed
//  highlights where they are reliably present.
//
// Web safety: imports `dart:io` (Socket). Gated behind
// `NetworkSupport.whoisSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The IANA bootstrap WHOIS server — the root of the referral chain.
const String kIanaWhoisServer = 'whois.iana.org';

/// One parsed highlight extracted from the raw record (registrar, dates,
/// status, name servers). Kept as label/value strings because WHOIS output is
/// free-form and varies by registry — we never coerce a missing field to a
/// fake value.
class WhoisHighlight {
  const WhoisHighlight({required this.label, required this.value});

  final String label;
  final String value;
}

/// Outcome of a WHOIS lookup. Distinguishes success (raw record + highlights),
/// empty (server answered but the object is unregistered / no data), and
/// failure (connection / timeout / bad input) so the UI renders three distinct
/// states per SOP-007 §5.
class WhoisResult {
  const WhoisResult._({
    required this.query,
    required this.rawRecord,
    required this.highlights,
    required this.serversQueried,
    this.errorMessage,
  });

  factory WhoisResult.success({
    required String query,
    required String rawRecord,
    required List<WhoisHighlight> highlights,
    required List<String> serversQueried,
  }) =>
      WhoisResult._(
        query: query,
        rawRecord: rawRecord,
        highlights: highlights,
        serversQueried: serversQueried,
      );

  factory WhoisResult.failure({
    required String query,
    required String message,
    List<String> serversQueried = const <String>[],
  }) =>
      WhoisResult._(
        query: query,
        rawRecord: '',
        highlights: const <WhoisHighlight>[],
        serversQueried: serversQueried,
        errorMessage: message,
      );

  /// The normalized query that was sent.
  final String query;

  /// The full raw text record from the authoritative server (shown mono /
  /// selectable). Empty only on failure.
  final String rawRecord;

  /// A few reliably-parseable fields surfaced above the raw block.
  final List<WhoisHighlight> highlights;

  /// The WHOIS servers consulted, in order (e.g. [whois.iana.org,
  /// whois.verisign-grs.com]). Shown so the path is transparent.
  final List<String> serversQueried;

  final String? errorMessage;

  bool get isError => errorMessage != null;

  /// Success but the record has no meaningful content (e.g. an unregistered
  /// domain whose server returns a "No match" banner only).
  bool get isEmpty => !isError && _looksEmpty(rawRecord);

  static bool _looksEmpty(String record) {
    final String r = record.trim();
    if (r.isEmpty) return true;
    final String lower = r.toLowerCase();
    // Common "not found" banners across registries. Keep conservative — only
    // treat as empty when the body is short AND matches a known no-match
    // phrase, so we never hide a real (if terse) record.
    const List<String> notFound = <String>[
      'no match for',
      'not found',
      'no data found',
      'no entries found',
      'domain not found',
      'no object found',
      'status: free',
    ];
    final bool hasBanner = notFound.any(lower.contains);
    return hasBanner && r.length < 400;
  }
}

/// Resolves WHOIS records over TCP/43. The [connector] seam keeps the referral
/// logic and parsing unit-testable without opening real sockets.
class WhoisService {
  WhoisService({WhoisConnector? connector})
      : _connect = connector ?? _defaultConnect;

  final WhoisConnector _connect;

  /// One TCP/43 round-trip: connect, send `query\r\n`, read the full text
  /// response until the server closes the connection.
  static Future<String> _defaultConnect(
    String server,
    String query, {
    required Duration timeout,
  }) async {
    final Socket socket = await Socket.connect(server, 43, timeout: timeout);
    try {
      socket.add(utf8.encode('$query\r\n'));
      await socket.flush();
      // WHOIS servers stream the record then close. Decode leniently —
      // some registries emit latin1 / non-UTF8 bytes.
      final List<int> bytes = await socket
          .expand<int>((List<int> chunk) => chunk)
          .toList()
          .timeout(timeout);
      return _decode(bytes);
    } finally {
      socket.destroy();
    }
  }

  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return latin1.decode(bytes);
    }
  }

  /// Look up [rawQuery] (a domain or IP). Performs the IANA referral hop, then
  /// queries the authoritative server, parses highlights, and returns the raw
  /// record.
  ///
  /// - [timeout] bounds each individual TCP round-trip (default 8s).
  Future<WhoisResult> lookup({
    required String rawQuery,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final String query = rawQuery.trim();
    if (query.isEmpty) {
      return WhoisResult.failure(
        query: query,
        message: 'Enter a domain or IP address to look up.',
      );
    }

    final List<String> serversQueried = <String>[];
    try {
      // Hop 1: ask IANA who is authoritative for this object.
      serversQueried.add(kIanaWhoisServer);
      final String ianaRecord =
          await _connect(kIanaWhoisServer, query, timeout: timeout);

      final String? referral = parseReferralServer(ianaRecord);

      // No referral → the IANA record is what we have (common for some IPs and
      // ccTLDs that IANA answers directly).
      if (referral == null || referral.toLowerCase() == kIanaWhoisServer) {
        return WhoisResult.success(
          query: query,
          rawRecord: ianaRecord.trim(),
          highlights: parseHighlights(ianaRecord),
          serversQueried: serversQueried,
        );
      }

      // Hop 2: query the authoritative registry for the full record.
      serversQueried.add(referral);
      String record = await _connect(referral, query, timeout: timeout);

      // Some registrars publish a thin record pointing at a registrar WHOIS
      // server (`Registrar WHOIS Server:`). Follow ONE more hop if present and
      // distinct, to surface the full registrant-facing record.
      final String? registrarServer = parseRegistrarServer(record);
      if (registrarServer != null &&
          registrarServer.toLowerCase() != referral.toLowerCase() &&
          registrarServer.toLowerCase() != kIanaWhoisServer) {
        try {
          final String deep =
              await _connect(registrarServer, query, timeout: timeout);
          if (deep.trim().length > record.trim().length) {
            serversQueried.add(registrarServer);
            record = deep;
          }
        } on Object {
          // Registrar server optional — keep the registry record on failure.
        }
      }

      return WhoisResult.success(
        query: query,
        rawRecord: record.trim(),
        highlights: parseHighlights(record),
        serversQueried: serversQueried,
      );
    } on SocketException catch (e) {
      return WhoisResult.failure(
        query: query,
        serversQueried: serversQueried,
        message: 'Could not reach the WHOIS server: ${_short(e.message)}.',
      );
    } on TimeoutException {
      return WhoisResult.failure(
        query: query,
        serversQueried: serversQueried,
        message: 'WHOIS lookup timed out after ${timeout.inSeconds}s.',
      );
    } on Object catch (e) {
      return WhoisResult.failure(
        query: query,
        serversQueried: serversQueried,
        message: 'Lookup failed: ${_short(e.toString())}.',
      );
    }
  }

  /// Parse the authoritative server from an IANA/registry WHOIS response.
  /// IANA uses `refer:`; some registries use `whois:`. Case-insensitive,
  /// tolerant of leading whitespace. Returns null when no referral is present.
  ///
  /// Exposed (static) for unit tests — referral parsing is the linchpin.
  static String? parseReferralServer(String record) {
    return _firstField(record, <String>['refer', 'whois']);
  }

  /// Parse `Registrar WHOIS Server:` from a registry record (the optional
  /// third hop to the registrar's own WHOIS). Returns null when absent.
  static String? parseRegistrarServer(String record) {
    return _firstField(record, <String>['registrar whois server']);
  }

  /// Find the first `key: value` line whose key matches one of [keys]
  /// (case-insensitive, exact key match after trimming). Returns the trimmed
  /// value (host only — strips any port / scheme), or null.
  static String? _firstField(String record, List<String> keys) {
    final Set<String> wanted = keys.map((String k) => k.toLowerCase()).toSet();
    for (final String line in const LineSplitter().convert(record)) {
      final int colon = line.indexOf(':');
      if (colon <= 0) continue;
      final String key = line.substring(0, colon).trim().toLowerCase();
      if (!wanted.contains(key)) continue;
      String value = line.substring(colon + 1).trim();
      if (value.isEmpty) continue;
      // Strip a scheme and any trailing port — we want a bare hostname for
      // Socket.connect.
      value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
      final int slash = value.indexOf('/');
      if (slash >= 0) value = value.substring(0, slash);
      final int port = value.indexOf(':');
      if (port >= 0) value = value.substring(0, port);
      value = value.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// Field labels we surface as highlights, mapped from the common WHOIS keys
  /// that carry them. Each maps to a display label; the first matching key in
  /// the record wins (registries vary in casing/wording).
  static const List<(String, List<String>)> _highlightSpec =
      <(String, List<String>)>[
    ('Registrar', <String>['registrar']),
    (
      'Created',
      <String>['creation date', 'created', 'registered on', 'domain_dateregistered'],
    ),
    (
      'Updated',
      <String>['updated date', 'last updated', 'last modified', 'changed'],
    ),
    (
      'Expires',
      <String>['registry expiry date', 'expiry date', 'expiration date', 'expires', 'paid-till'],
    ),
    (
      'Status',
      <String>['domain status', 'status'],
    ),
  ];

  /// Extract a small set of reliably-parseable highlights from the raw record.
  /// Name servers are collected separately (a record lists several). Anything
  /// not found is simply omitted — never shown as a blank or a zero.
  ///
  /// Exposed (static) for unit tests.
  static List<WhoisHighlight> parseHighlights(String record) {
    final List<WhoisHighlight> out = <WhoisHighlight>[];
    final List<String> lines = const LineSplitter().convert(record);

    for (final (String label, List<String> keys) in _highlightSpec) {
      final String? value = _firstValueForKeys(lines, keys);
      if (value != null) out.add(WhoisHighlight(label: label, value: value));
    }

    // Name servers — there can be several; collect, de-dupe, join.
    final List<String> ns = _allValuesForKeys(
      lines,
      <String>['name server', 'nserver', 'nameservers', 'name servers'],
    );
    if (ns.isNotEmpty) {
      final List<String> unique = ns
          .map((String s) => s.toLowerCase())
          .toSet()
          .toList(growable: false);
      out.add(
        WhoisHighlight(label: 'Name servers', value: unique.join('\n')),
      );
    }
    return out;
  }

  static String? _firstValueForKeys(List<String> lines, List<String> keys) {
    final Set<String> wanted = keys.map((String k) => k.toLowerCase()).toSet();
    for (final String line in lines) {
      final int colon = line.indexOf(':');
      if (colon <= 0) continue;
      final String key = line.substring(0, colon).trim().toLowerCase();
      if (!wanted.contains(key)) continue;
      final String value = line.substring(colon + 1).trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static List<String> _allValuesForKeys(List<String> lines, List<String> keys) {
    final Set<String> wanted = keys.map((String k) => k.toLowerCase()).toSet();
    final List<String> out = <String>[];
    for (final String line in lines) {
      final int colon = line.indexOf(':');
      if (colon <= 0) continue;
      final String key = line.substring(0, colon).trim().toLowerCase();
      if (!wanted.contains(key)) continue;
      // A name-server line can carry "ns1.example.com 192.0.2.1" — keep just
      // the host token.
      final String value = line.substring(colon + 1).trim().split(RegExp(r'\s+')).first;
      if (value.isNotEmpty) out.add(value);
    }
    return out;
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}

/// The injectable network seam: one WHOIS round-trip, returns the raw record.
typedef WhoisConnector = Future<String> Function(
  String server,
  String query, {
  required Duration timeout,
});
