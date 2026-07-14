// SslInspectService — connect to host:port over TLS and report the server's
// certificate as inspectable DATA, including expired / self-signed certs.
//
// WHY THIS SHAPE (deliberate, documented decisions):
//
// 1. The whole point of a cert inspector is to inspect *broken* certs. So the
//    connection uses `onBadCertificate: (cert) => true` — we accept any
//    certificate at the socket layer so an EXPIRED, self-signed, name-mismatch,
//    or untrusted-root cert is still captured and shown as data. We never throw
//    a validation failure away; the validity verdict is computed from the cert
//    dates ourselves (see [CertValidity]) and surfaced as a state, not an error.
//
// 2. Field coverage is split across two sources, by necessity:
//      - Dart's `dart:io` `X509Certificate` (from `socket.peerCertificate`)
//        exposes only: PEM/DER bytes, subject DN string, issuer DN string,
//        notBefore/notAfter dates, and the SHA-1 fingerprint. That is the whole
//        public API — no SAN, no serial, no signature algorithm, no key size,
//        no SHA-256.
//      - So we re-parse the leaf's PEM with `basic_utils` `X509Utils`
//        (already a dependency, MIT) to recover: structured subject/issuer
//        (CN/O/...), SAN list, serial number, signature algorithm + readable
//        name, public-key algorithm + key length, and the SHA-256 thumbprint.
//
// 3. Negotiated TLS protocol version and cipher suite: `dart:io`'s
//    `SecureSocket` does NOT expose either. `selectedProtocol` is the ALPN
//    result only (null unless ALPN was negotiated) — it is NOT the TLS version
//    and NOT the cipher suite. We report this honestly as "not exposed by the
//    platform" rather than inventing a value. (See [SslInspectResult.alpn].)
//
// 4. Chain: `dart:io` hands us only the leaf via `peerCertificate` — there is
//    no public accessor for the intermediate/root chain BoringSSL validated
//    against. We say so plainly ([SslInspectResult.chainNote]) rather than
//    pretend a single-cert chain is the whole story.
//
// Web safety: imports `dart:io` (SecureSocket). Gated behind
// `NetworkSupport.sslInspectSupported` at the UI layer; never reached on web.

import 'dart:async';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';

import 'tcp_probe_classifier.dart';

/// Computed validity verdict for a certificate, derived from notBefore /
/// notAfter against "now". Kept separate from the raw dates so the UI can show
/// a non-color-only status (icon + text) per GL-003 §8.4 / WCAG 1.4.1.
enum CertValidityState {
  /// now is within [notBefore, notAfter].
  valid,

  /// now is after notAfter — the cert has expired.
  expired,

  /// now is before notBefore — the cert is not yet valid.
  notYetValid,
}

/// The derived validity of a certificate plus the day-delta the UI shows.
class CertValidity {
  const CertValidity({
    required this.state,
    required this.notBefore,
    required this.notAfter,
    required this.daysToExpiry,
  });

  final CertValidityState state;
  final DateTime notBefore;
  final DateTime notAfter;

  /// Whole days from `now` to notAfter. Negative once expired (days since
  /// expiry). Used for the "expires in N days" / "expired N days ago" line.
  final int daysToExpiry;

  /// Compute the verdict for [notBefore]/[notAfter] relative to [now].
  /// [now] is injectable so the derived-state logic is unit-testable without
  /// depending on the wall clock.
  factory CertValidity.compute({
    required DateTime notBefore,
    required DateTime notAfter,
    required DateTime now,
  }) {
    final CertValidityState state;
    if (now.isBefore(notBefore)) {
      state = CertValidityState.notYetValid;
    } else if (now.isAfter(notAfter)) {
      state = CertValidityState.expired;
    } else {
      state = CertValidityState.valid;
    }
    // Day delta rounded toward zero on the millisecond difference. notAfter -
    // now: positive while valid, negative once expired.
    final int days = notAfter.difference(now).inDays;
    return CertValidity(
      state: state,
      notBefore: notBefore,
      notAfter: notAfter,
      daysToExpiry: days,
    );
  }
}

/// A name/value pair pulled out of a Distinguished Name map, in a stable order
/// the UI renders top-to-bottom.
class DnField {
  const DnField({required this.label, required this.value});
  final String label;
  final String value;
}

/// The parsed, display-ready certificate. Every field is nullable where the
/// platform or the parser could not supply it, so the UI shows the canonical
/// "not available" treatment instead of a blank or a zero.
class InspectedCertificate {
  const InspectedCertificate({
    required this.subjectCommonName,
    required this.subjectOrg,
    required this.issuerCommonName,
    required this.issuerOrg,
    required this.subjectFields,
    required this.issuerFields,
    required this.validity,
    required this.serialNumber,
    required this.signatureAlgorithm,
    required this.publicKeyAlgorithm,
    required this.publicKeyBits,
    required this.sha256Fingerprint,
    required this.sha1Fingerprint,
    required this.subjectAltNames,
    required this.pem,
  });

  final String? subjectCommonName;
  final String? subjectOrg;
  final String? issuerCommonName;
  final String? issuerOrg;

  /// Full subject / issuer DN broken into ordered fields for the detail view.
  final List<DnField> subjectFields;
  final List<DnField> issuerFields;

  final CertValidity validity;

  /// Serial as uppercase colon-grouped hex (e.g. "0A:2B:..."), or null.
  final String? serialNumber;

  /// Signature algorithm — readable name when basic_utils resolved one, else
  /// the OID, else null.
  final String? signatureAlgorithm;

  /// Public-key algorithm (e.g. "RSA", "EC"), or null.
  final String? publicKeyAlgorithm;

  /// Public-key size in bits, or null when the parser could not derive it.
  final int? publicKeyBits;

  /// SHA-256 fingerprint as uppercase colon-grouped hex. Null only if parsing
  /// failed entirely.
  final String? sha256Fingerprint;

  /// SHA-1 fingerprint as uppercase colon-grouped hex. Sourced from dart:io's
  /// X509Certificate.sha1 when basic_utils omitted it.
  final String? sha1Fingerprint;

  /// Subject Alternative Names, or empty when the cert carried none.
  final List<String> subjectAltNames;

  /// The leaf certificate in PEM, for copy-out.
  final String pem;
}

/// Outcome of an inspection — success carries the cert; failure carries a
/// precise message. Connection problems (DNS, refused, timeout) are failures;
/// a *bad cert* is NOT a failure — it is a successful inspection of an invalid
/// cert, which is the entire point of the tool.
class SslInspectResult {
  const SslInspectResult._({
    required this.host,
    required this.port,
    this.certificate,
    this.alpn,
    this.handshakeMs,
    this.errorMessage,
  });

  factory SslInspectResult.success({
    required String host,
    required int port,
    required InspectedCertificate certificate,
    required String? alpn,
    required int handshakeMs,
  }) =>
      SslInspectResult._(
        host: host,
        port: port,
        certificate: certificate,
        alpn: alpn,
        handshakeMs: handshakeMs,
      );

  factory SslInspectResult.failure({
    required String host,
    required int port,
    required String message,
  }) =>
      SslInspectResult._(host: host, port: port, errorMessage: message);

  final String host;
  final int port;
  final InspectedCertificate? certificate;

  /// The ALPN protocol the platform reported, or null. NOT the TLS version and
  /// NOT the cipher suite — those are not exposed by dart:io. The UI labels
  /// this precisely so it is never mistaken for the negotiated TLS version.
  final String? alpn;

  /// TLS handshake duration in milliseconds, or null on failure.
  final int? handshakeMs;

  final String? errorMessage;

  bool get isError => errorMessage != null;

  /// Honest note about chain availability — dart:io exposes only the leaf.
  static const String chainNote =
      'The platform TLS stack exposes only the leaf (server) certificate to '
      'the app, not the intermediate or root certificates it validated '
      'against. Only the leaf is shown.';
}

/// Inspects a server certificate over TLS. The [connector] seam keeps the
/// orchestration testable; the pure parsing logic ([parsePeerCertificate]) and
/// the derived validity ([CertValidity.compute]) are directly unit-tested
/// without any socket.
class SslInspectService {
  SslInspectService({
    Future<SecureSocket> Function(
      String host,
      int port, {
      required Duration timeout,
    })? connector,
  }) : _connect = connector ?? _defaultConnect;

  final Future<SecureSocket> Function(
    String host,
    int port, {
    required Duration timeout,
  }) _connect;

  static const int defaultPort = 443;

  static Future<SecureSocket> _defaultConnect(
    String host,
    int port, {
    required Duration timeout,
  }) {
    // Accept ANY certificate at the socket layer — expired, self-signed,
    // name-mismatch, untrusted root. We are inspecting, not trusting. The
    // validity verdict is computed from the cert itself afterward.
    return SecureSocket.connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: (X509Certificate _) => true,
    );
  }

  /// Connect to [rawHost]:[port] over TLS and return the parsed certificate.
  ///
  /// [port] defaults to 443. [timeout] bounds the connect+handshake so a black
  /// hole host yields a clear timeout state instead of hanging the UI.
  Future<SslInspectResult> inspect({
    required String rawHost,
    int port = defaultPort,
    Duration timeout = const Duration(seconds: 8),
    DateTime? now,
  }) async {
    final String host = _cleanHost(rawHost);
    if (host.isEmpty) {
      return SslInspectResult.failure(
        host: host,
        port: port,
        message: 'Enter a hostname or IP to inspect.',
      );
    }
    if (port < 1 || port > 65535) {
      return SslInspectResult.failure(
        host: host,
        port: port,
        message: 'Port must be between 1 and 65535.',
      );
    }

    final Stopwatch sw = Stopwatch()..start();
    SecureSocket? socket;
    try {
      socket = await _connect(host, port, timeout: timeout);
      sw.stop();
      final X509Certificate? peer = socket.peerCertificate;
      final String? alpn = socket.selectedProtocol;
      if (peer == null) {
        return SslInspectResult.failure(
          host: host,
          port: port,
          message:
              'Connected, but the platform did not expose a peer certificate.',
        );
      }
      final InspectedCertificate cert = parsePeerCertificate(
        pem: peer.pem,
        ioSubject: peer.subject,
        ioIssuer: peer.issuer,
        ioNotBefore: peer.startValidity,
        ioNotAfter: peer.endValidity,
        ioSha1: peer.sha1,
        now: now ?? DateTime.now(),
      );
      return SslInspectResult.success(
        host: host,
        port: port,
        certificate: cert,
        alpn: (alpn != null && alpn.isNotEmpty) ? alpn : null,
        handshakeMs: sw.elapsedMilliseconds,
      );
    } on SocketException catch (e) {
      sw.stop();
      return SslInspectResult.failure(
        host: host,
        port: port,
        message: _socketMessage(e, timeout),
      );
    } on HandshakeException catch (e) {
      sw.stop();
      return SslInspectResult.failure(
        host: host,
        port: port,
        message: 'TLS handshake failed: ${_short(e.message)}',
      );
    } on TlsException catch (e) {
      sw.stop();
      return SslInspectResult.failure(
        host: host,
        port: port,
        message: 'TLS error: ${_short(e.message)}',
      );
    } on Object catch (e) {
      sw.stop();
      return SslInspectResult.failure(
        host: host,
        port: port,
        message: _short(e.toString()),
      );
    } finally {
      socket?.destroy();
    }
  }

  /// Parse a leaf certificate from its [pem], falling back to the dart:io
  /// accessor values for anything basic_utils omits. Pure and synchronous so
  /// it is directly unit-testable with a fixed [now] and a fixture PEM.
  static InspectedCertificate parsePeerCertificate({
    required String pem,
    required String ioSubject,
    required String ioIssuer,
    required DateTime ioNotBefore,
    required DateTime ioNotAfter,
    required List<int> ioSha1,
    required DateTime now,
  }) {
    // Defaults come from dart:io; basic_utils refines them where it can.
    DateTime notBefore = ioNotBefore;
    DateTime notAfter = ioNotAfter;
    List<DnField> subjectFields = _dnFromDartString(ioSubject);
    List<DnField> issuerFields = _dnFromDartString(ioIssuer);
    String? subjectCn = _cnFromFields(subjectFields);
    String? subjectOrg = _orgFromFields(subjectFields);
    String? issuerCn = _cnFromFields(issuerFields);
    String? issuerOrg = _orgFromFields(issuerFields);
    String? serial;
    String? sigAlg;
    String? keyAlg;
    int? keyBits;
    String? sha256;
    List<String> sans = const <String>[];

    try {
      final X509CertificateData data = X509Utils.x509CertificateFromPem(pem);
      final TbsCertificate? tbs = data.tbsCertificate;

      final Map<String, String?> subjectMap =
          tbs?.subject ?? const <String, String?>{};
      final Map<String, String?> issuerMap =
          tbs?.issuer ?? const <String, String?>{};
      if (subjectMap.isNotEmpty) {
        subjectFields = _dnFromMap(subjectMap);
        subjectCn = subjectMap['2.5.4.3'] ?? subjectCn;
        subjectOrg = subjectMap['2.5.4.10'] ?? subjectOrg;
      }
      if (issuerMap.isNotEmpty) {
        issuerFields = _dnFromMap(issuerMap);
        issuerCn = issuerMap['2.5.4.3'] ?? issuerCn;
        issuerOrg = issuerMap['2.5.4.10'] ?? issuerOrg;
      }

      final validity = tbs?.validity;
      if (validity != null) {
        notBefore = validity.notBefore;
        notAfter = validity.notAfter;
      }

      final BigInt? sn = tbs?.serialNumber;
      if (sn != null) serial = _formatSerial(sn);

      sigAlg = tbs?.signatureAlgorithmReadableName ??
          tbs?.signatureAlgorithm ??
          data.signatureAlgorithmReadableName ??
          data.signatureAlgorithm;

      final spki = tbs?.subjectPublicKeyInfo;
      keyAlg = spki?.algorithmReadableName ?? spki?.algorithm;
      keyBits = spki?.length;

      sha256 = _normalizeFingerprint(data.sha256Thumbprint);

      final List<String>? sanList = tbs?.extensions?.subjectAlternativNames;
      if (sanList != null && sanList.isNotEmpty) {
        sans = List<String>.unmodifiable(sanList);
      }
    } on Object {
      // Parsing the DER details failed (malformed/unsupported extension). We
      // still return everything dart:io gave us rather than throwing away the
      // whole inspection — degraded, but honest.
    }

    final String sha1Hex = _bytesToFingerprint(ioSha1);

    return InspectedCertificate(
      subjectCommonName: _blankToNull(subjectCn),
      subjectOrg: _blankToNull(subjectOrg),
      issuerCommonName: _blankToNull(issuerCn),
      issuerOrg: _blankToNull(issuerOrg),
      subjectFields: subjectFields,
      issuerFields: issuerFields,
      validity: CertValidity.compute(
        notBefore: notBefore,
        notAfter: notAfter,
        now: now,
      ),
      serialNumber: _blankToNull(serial),
      signatureAlgorithm: _blankToNull(sigAlg),
      publicKeyAlgorithm: _blankToNull(keyAlg),
      publicKeyBits: keyBits,
      sha256Fingerprint: _blankToNull(sha256),
      sha1Fingerprint: _blankToNull(sha1Hex),
      subjectAltNames: sans,
      pem: pem,
    );
  }

  // ── Helpers (all pure; some used by tests) ──────────────────────────────

  /// Strip a scheme, path, and surrounding whitespace from a host the user may
  /// have pasted as a URL (e.g. "https://example.com/path" → "example.com").
  static String _cleanHost(String raw) {
    String s = raw.trim();
    if (s.isEmpty) return '';
    final int scheme = s.indexOf('://');
    if (scheme >= 0) s = s.substring(scheme + 3);
    // Drop any path / query.
    final int slash = s.indexOf('/');
    if (slash >= 0) s = s.substring(0, slash);
    // Drop a trailing :port if the user typed one in the host box (the port is
    // a separate field) — but keep IPv6 bracket literals intact.
    if (!s.startsWith('[')) {
      final int colon = s.indexOf(':');
      if (colon >= 0) s = s.substring(0, colon);
    }
    return s.trim();
  }

  /// Parse a dart:io DN string like "CN=example.com, O=Example Inc, C=US" into
  /// ordered fields. dart:io gives a comma-joined RFC-2253-ish string; we split
  /// on top-level commas and `=`.
  static List<DnField> _dnFromDartString(String dn) {
    if (dn.trim().isEmpty) return const <DnField>[];
    final List<DnField> out = <DnField>[];
    // Split only on a comma that introduces a new `KEY=` attribute (optionally
    // preceded by whitespace), so a value that itself contains a comma (e.g.
    // "O=Example, Inc") stays intact.
    final List<String> parts =
        dn.split(RegExp(r',(?=\s*[A-Za-z][A-Za-z0-9.]*=)'));
    for (final String partRaw in parts) {
      final String part = partRaw.trim();
      final int eq = part.indexOf('=');
      if (eq <= 0) continue;
      final String key = part.substring(0, eq).trim();
      final String value = part.substring(eq + 1).trim();
      if (value.isEmpty) continue;
      out.add(DnField(label: _dnLabel(key), value: value));
    }
    return out;
  }

  /// Build ordered DN fields from a basic_utils OID→value map.
  static List<DnField> _dnFromMap(Map<String, String?> map) {
    const List<String> order = <String>[
      '2.5.4.3', // CN
      '2.5.4.10', // O
      '2.5.4.11', // OU
      '2.5.4.7', // L
      '2.5.4.8', // ST
      '2.5.4.6', // C
    ];
    final List<DnField> out = <DnField>[];
    for (final String oid in order) {
      final String? v = map[oid];
      if (v != null && v.trim().isNotEmpty) {
        out.add(DnField(label: _oidLabel(oid), value: v.trim()));
      }
    }
    // Append any remaining fields not in the preferred order.
    for (final MapEntry<String, String?> e in map.entries) {
      if (order.contains(e.key)) continue;
      final String? v = e.value;
      if (v != null && v.trim().isNotEmpty) {
        out.add(DnField(label: _oidLabel(e.key), value: v.trim()));
      }
    }
    return out;
  }

  static String? _cnFromFields(List<DnField> fields) {
    for (final DnField f in fields) {
      if (f.label == 'CN') return f.value;
    }
    return null;
  }

  static String? _orgFromFields(List<DnField> fields) {
    for (final DnField f in fields) {
      if (f.label == 'O') return f.value;
    }
    return null;
  }

  static String _dnLabel(String key) {
    // dart:io uses short attribute names already (CN, O, OU...). Pass through,
    // upper-casing the common ones for consistency with the OID path.
    final String up = key.toUpperCase();
    const Set<String> known = <String>{'CN', 'O', 'OU', 'L', 'ST', 'C', 'E'};
    return known.contains(up) ? up : key;
  }

  static String _oidLabel(String oid) {
    switch (oid) {
      case '2.5.4.3':
        return 'CN';
      case '2.5.4.10':
        return 'O';
      case '2.5.4.11':
        return 'OU';
      case '2.5.4.7':
        return 'L';
      case '2.5.4.8':
        return 'ST';
      case '2.5.4.6':
        return 'C';
      default:
        return oid;
    }
  }

  /// Format a serial BigInt as uppercase colon-grouped hex byte pairs.
  static String _formatSerial(BigInt serial) {
    String hex = serial.toRadixString(16).toUpperCase();
    if (hex.length.isOdd) hex = '0$hex';
    return _groupHex(hex);
  }

  /// Normalize a basic_utils thumbprint (may be `AA:BB:..`, `aabb..`, or have
  /// spaces) to uppercase colon-grouped hex. Returns null for null input.
  static String? _normalizeFingerprint(String? raw) {
    if (raw == null) return null;
    final String hex =
        raw.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    if (hex.isEmpty) return null;
    return _groupHex(hex);
  }

  /// Render raw bytes as uppercase colon-grouped hex (for the dart:io SHA-1).
  static String _bytesToFingerprint(List<int> bytes) {
    final StringBuffer sb = StringBuffer();
    for (final int b in bytes) {
      sb.write((b & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
    return _groupHex(sb.toString());
  }

  static String _groupHex(String hex) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < hex.length; i += 2) {
      if (i > 0) out.write(':');
      out.write(hex.substring(i, (i + 2).clamp(0, hex.length)));
    }
    return out.toString();
  }

  static String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// Turn a failed connect into precise user-facing copy.
  ///
  /// The reason comes from the shared classifier — this service never inspects
  /// `osError` itself. It used to guess a timeout from `osError == null &&
  /// elapsed >= timeout - 100ms`, which never fired (Dart's connect-timeout DOES
  /// carry an osError), so a genuine timeout showed the generic "Could not
  /// connect" line instead of the timeout guidance. The errno is authoritative.
  static String _socketMessage(SocketException e, Duration timeout) {
    final TcpProbeFailure failure = classifyTcpFailure(e);
    return switch (failure.reason) {
      TcpFailureReason.timedOut =>
        'Connection timed out after ${timeout.inSeconds}s. The host may be '
            'unreachable or not listening on this port.',
      TcpFailureReason.refused =>
        'Connection refused. The host answered, but nothing is listening on '
            'this port.',
      TcpFailureReason.unreachable =>
        'Host unreachable. No route to this host.',
      TcpFailureReason.lookupFailure =>
        'Could not resolve that host name. Check the spelling.',
      TcpFailureReason.unknown =>
        'Could not connect: ${_short(failure.message)}.',
    };
  }

  static String _short(String s) {
    final String t = s.trim();
    return t.length > 140 ? '${t.substring(0, 140)}…' : t;
  }
}
