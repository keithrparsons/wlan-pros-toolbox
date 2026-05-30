// MacOuiService — turn a MAC address into its registered vendor, fully offline.
//
// WHAT IT DOES: normalizes a MAC in any common notation (colon, hyphen, Cisco
// dot, or no separator; any case) to its hex digits, then resolves the owning
// organization from a bundled IEEE registry table. It honors the three IEEE
// block sizes — MA-L (/24, 6 hex), MA-M (/28, 7 hex), MA-S (/36, 9 hex) — and
// matches most-specific-first so an address inside a /36 sub-allocation names
// the real sub-assignee, not the /24 parent.
//
// HONESTY OVER A WRONG ANSWER: the two low bits of the first octet are control
// bits. The U/L bit (bit 1, mask 0x02) set means the address is
// locally-administered — assigned by software, NOT from an IEEE block — so a
// vendor lookup is meaningless. Modern phones (iOS, Android) randomize their
// Wi-Fi MAC with this bit set, so this is the common real-world case. The I/G
// bit (bit 0, mask 0x01) set means the address is a multicast/group address,
// not a single NIC. In both cases the service flags the condition and does NOT
// invent a vendor.
//
// OFFLINE / NO NETWORK: the registry is a bundled asset
// (assets/oui/oui_table.tsv, declared in pubspec.yaml). It is loaded and parsed
// once, then cached in memory for the process lifetime. No HTTP, no `dart:io`,
// no Flutter imports — the lookup logic is pure Dart and unit-testable by
// constructing the service from an in-memory table.
//
// ASSET SOURCE: IEEE Registration Authority public registries (oui.csv /
// mam.csv / oui36.csv). Retrieval date and refresh steps are documented in the
// asset header (assets/oui/oui_table.tsv).

/// Outcome of a MAC → vendor lookup. Always returned — never thrown — so the
/// UI renders one consistent result surface for every input.
class OuiResult {
  const OuiResult({
    required this.input,
    this.normalizedMac,
    this.oui,
    this.vendor,
    required this.isValid,
    required this.isLocal,
    required this.isMulticast,
    required this.matched,
    required this.registry,
    this.errorMessage,
  });

  /// The raw string the caller passed in (echoed for the UI).
  final String input;

  /// Canonical lower-case colon form (`b8:27:eb:01:23:45`), or null when the
  /// input was not a valid 48-bit MAC.
  final String? normalizedMac;

  /// The matched registry prefix in upper-case hex (e.g. `B827EB` for a /24,
  /// `8C1F64AFA` for a /36), or null when there was no match / invalid input.
  final String? oui;

  /// The registered organization name, or null when unmatched / not applicable
  /// (locally-administered, multicast, or invalid input).
  final String? vendor;

  /// True when the input parsed as a 48-bit MAC (6 octets of hex).
  final bool isValid;

  /// True when the U/L bit (0x02 of the first octet) is set — a
  /// locally-administered / randomized address with no IEEE vendor.
  final bool isLocal;

  /// True when the I/G bit (0x01 of the first octet) is set — a multicast /
  /// group address, not a single NIC.
  final bool isMulticast;

  /// True only when a vendor was resolved from the registry.
  final bool matched;

  /// Which IEEE block the match came from, for display ("MA-L (/24)" etc.), or
  /// null when unmatched.
  final OuiRegistry? registry;

  /// Set only for invalid input — a clear, user-facing rejection message.
  final String? errorMessage;
}

/// The IEEE block a match came from. Block size is encoded by the hex-prefix
/// length in the bundled table (6 → MA-L, 7 → MA-M, 9 → MA-S).
enum OuiRegistry {
  /// MA-L — 24-bit OUI (/24). The common case.
  maL,

  /// MA-M — 28-bit (/28).
  maM,

  /// MA-S — 36-bit (/36).
  maS,
}

extension OuiRegistryLabel on OuiRegistry {
  /// Human label for the UI, e.g. "MA-L (/24)".
  String get label => switch (this) {
        OuiRegistry.maL => 'MA-L (/24)',
        OuiRegistry.maM => 'MA-M (/28)',
        OuiRegistry.maS => 'MA-S (/36)',
      };
}

/// Pure-Dart MAC → vendor resolver over a bundled IEEE registry table.
///
/// Construction is decoupled from asset loading so the lookup is unit-testable:
/// build with [MacOuiService.fromTable] for tests, or call
/// [MacOuiService.loadFromAsset] in app code to parse the bundled `.tsv`.
class MacOuiService {
  /// Build directly from an in-memory prefix→vendor map. The map keys are
  /// UPPER-CASE hex prefixes of length 6, 7, or 9 (MA-L / MA-M / MA-S). Used by
  /// tests and by [parseTable].
  MacOuiService.fromTable(Map<String, String> table) : _table = table;

  final Map<String, String> _table;

  /// U/L bit of the first octet — set ⇒ locally administered (no IEEE vendor).
  static const int _ulBit = 0x02;

  /// I/G bit of the first octet — set ⇒ multicast / group address.
  static const int _igBit = 0x01;

  /// Parse the bundled `.tsv` (header `#` lines + `<HEXPREFIX>\t<org>` rows)
  /// into the prefix→vendor map. Tolerant of blank lines and comments. Pure —
  /// no I/O — so it is unit-testable with a literal string.
  static Map<String, String> parseTable(String raw) {
    final Map<String, String> table = <String, String>{};
    for (final String line in raw.split('\n')) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final int tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final String prefix = line.substring(0, tab).trim().toUpperCase();
      final String org = line.substring(tab + 1).trim();
      if (prefix.isEmpty || org.isEmpty) continue;
      // Only 6/7/9-hex prefixes are meaningful registry blocks.
      if (prefix.length != 6 && prefix.length != 7 && prefix.length != 9) {
        continue;
      }
      table[prefix] = org;
    }
    return table;
  }

  /// Normalize a user-entered MAC to canonical lower-case colon form
  /// (`aa:bb:cc:dd:ee:ff`). Accepts colon, hyphen, Cisco dot (`aabb.ccdd.eeff`),
  /// and no-separator forms in any case. Returns null when the input is not
  /// exactly 6 hex bytes.
  static String? normalizeMac(String raw) {
    final String hex = raw.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 12) return null;
    final List<String> bytes = <String>[];
    for (int i = 0; i < 12; i += 2) {
      bytes.add(hex.substring(i, i + 2));
    }
    return bytes.join(':');
  }

  /// The 24-bit OUI (first 3 octets, upper-case hex, no separators) of a
  /// normalized MAC — e.g. `b8:27:eb:…` → `B827EB`. Returns null on invalid
  /// input. Exposed for the UI and tests.
  static String? ouiOf(String mac) {
    final String? norm = normalizeMac(mac);
    if (norm == null) return null;
    return norm.split(':').take(3).join('').toUpperCase();
  }

  /// Resolve [mac] to its vendor. Never throws; an invalid MAC returns an
  /// [OuiResult] with `isValid == false` and a clear [OuiResult.errorMessage].
  OuiResult lookup(String mac) {
    final String input = mac.trim();
    final String? norm = normalizeMac(input);
    if (norm == null) {
      return OuiResult(
        input: input,
        isValid: false,
        isLocal: false,
        isMulticast: false,
        matched: false,
        registry: null,
        errorMessage: 'Enter a valid MAC address — 6 hex bytes, e.g. '
            'B8:27:EB:01:23:45 (colons, hyphens, dots, or no separators all '
            'work).',
      );
    }

    final List<int> octets =
        norm.split(':').map((String b) => int.parse(b, radix: 16)).toList();
    final int first = octets[0];
    final bool isLocal = (first & _ulBit) != 0;
    final bool isMulticast = (first & _igBit) != 0;

    final String hex12 =
        octets.map((int o) => o.toRadixString(16).padLeft(2, '0')).join();
    final String oui24 = hex12.substring(0, 6).toUpperCase();

    // Locally-administered or multicast addresses are not issued from an IEEE
    // block, so a registry hit would be a coincidence, not a vendor. Flag and
    // stop — never invent a vendor for these.
    if (isLocal || isMulticast) {
      return OuiResult(
        input: input,
        normalizedMac: norm,
        oui: oui24,
        vendor: null,
        isValid: true,
        isLocal: isLocal,
        isMulticast: isMulticast,
        matched: false,
        registry: null,
      );
    }

    // Match most-specific-first: /36 (9 hex), then /28 (7 hex), then /24 (6).
    final String key36 = hex12.substring(0, 9).toUpperCase();
    final String key28 = hex12.substring(0, 7).toUpperCase();

    String? vendor;
    OuiRegistry? registry;
    if (_table.containsKey(key36)) {
      vendor = _table[key36];
      registry = OuiRegistry.maS;
    } else if (_table.containsKey(key28)) {
      vendor = _table[key28];
      registry = OuiRegistry.maM;
    } else if (_table.containsKey(oui24)) {
      vendor = _table[oui24];
      registry = OuiRegistry.maL;
    }

    return OuiResult(
      input: input,
      normalizedMac: norm,
      oui: oui24,
      vendor: vendor,
      isValid: true,
      isLocal: false,
      isMulticast: false,
      matched: vendor != null,
      registry: registry,
    );
  }
}
