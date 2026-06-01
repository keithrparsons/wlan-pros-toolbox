// SPIKE-HSD-01 — OUI → vendor lookup for the LAN Discovery spike (THROWAWAY).
//
// Turns a MAC into a vendor name using the first 3 bytes (the OUI / MA-L /24
// prefix). For the spike this is a SMALL inline table covering the common
// vendors on Keith's network (per the reference-scan oracle in
// FINDINGS-gate1-ios.md: Ubiquiti, Sonos, Apple, HP, Peplink, plus a handful of
// other household IoT makers). When a prefix is not in the table we return the
// raw OUI (e.g. `B8:27:EB`) rather than null, so the debug screen always shows
// something interpretable.
//
// TICKET-HSD-02: the shipping build uses the full bundled IEEE registry already
// in the repo (assets/oui/oui_table.tsv via lib/services/network/
// mac_oui_service.dart, which does longest-prefix MA-L/MA-M/MA-S matching).
// This spike intentionally does NOT couple throwaway code to that asset; it
// ships a tiny inline 24-bit table so the Gate-2 run is self-contained. Swap to
// MacOuiService when the feature is built for real.
//
// Pure Dart — no assets, no dart:io, no Flutter — so the lookup is trivially
// unit-testable.

/// Resolves a MAC address to a vendor name via a small bundled OUI table.
class OuiVendor {
  const OuiVendor._();

  /// 24-bit OUI prefix (upper-case hex, no separators) → vendor name. Small by
  /// design (spike scope). Sourced from the IEEE registry for the vendors that
  /// dominate Keith's reference scans, plus common consumer IoT makers.
  static const Map<String, String> _table = <String, String>{
    // Ubiquiti (the bulk of Keith's network — UniFi gear)
    'FCECDA': 'Ubiquiti',
    '24A43C': 'Ubiquiti',
    '788A20': 'Ubiquiti',
    '687251': 'Ubiquiti',
    'B4FBE4': 'Ubiquiti',
    '802AA8': 'Ubiquiti',
    '74ACB9': 'Ubiquiti',
    '44D9E7': 'Ubiquiti',
    'E063DA': 'Ubiquiti',
    'F09FC2': 'Ubiquiti',
    'DC9FDB': 'Ubiquiti',
    // Sonos
    '5CAAFD': 'Sonos',
    '949F3E': 'Sonos',
    '347E5C': 'Sonos',
    '00E0FC': 'Sonos', // (historical block; included for coverage)
    'B8E937': 'Sonos',
    '542A1B': 'Sonos',
    '38420B': 'Sonos',
    // Apple (a few of the many MA-L blocks)
    'A4B197': 'Apple',
    'F0189E': 'Apple',
    '3C0754': 'Apple',
    '14109F': 'Apple',
    'D4619D': 'Apple',
    'A85C2C': 'Apple',
    'BCD074': 'Apple',
    '8866A5': 'Apple',
    'F0B3EC': 'Apple',
    'ACBC32': 'Apple',
    // HP / Hewlett-Packard (printers)
    '3464A9': 'HP',
    '94570A': 'HP',
    '9C8E99': 'HP',
    'B05CDA': 'HP',
    '2C44FD': 'HP',
    // Peplink
    '003067': 'Peplink',
    '00133D': 'Peplink',
    // Google / Nest
    '3C5AB4': 'Google',
    'F4F5D8': 'Google',
    '1844FD': 'Google',
    'D831CF': 'Google',
    // Amazon (Echo / Fire)
    'FCA183': 'Amazon',
    '44650D': 'Amazon',
    '68543D': 'Amazon',
    'F0272D': 'Amazon',
    // Samsung
    '5001BB': 'Samsung',
    '8CC8CD': 'Samsung',
    'D0176A': 'Samsung',
    // Raspberry Pi
    'B827EB': 'Raspberry Pi',
    'DCA632': 'Raspberry Pi',
    'E45F01': 'Raspberry Pi',
    // Espressif (common ESP32/ESP8266 IoT)
    '240AC4': 'Espressif',
    '3C71BF': 'Espressif',
    '8CAAB5': 'Espressif',
    // Intel (NICs / laptops)
    '3CA067': 'Intel',
    '8C1645': 'Intel',
    '9CB6D0': 'Intel',
  };

  /// The number of vendor prefixes in the bundled spike table — surfaced on the
  /// debug screen so it is obvious this is a small spike table, not the full
  /// IEEE registry.
  static int get prefixCount => _table.length;

  /// The 24-bit OUI of a colon/hyphen/dotted/bare MAC, upper-case hex with
  /// colons (e.g. `b8:27:eb:…` → `B8:27:EB`). Null when the input is not a
  /// valid 6-byte MAC.
  static String? ouiOf(String mac) {
    final String hex = mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 12) return null;
    final String p = hex.substring(0, 6).toUpperCase();
    return '${p.substring(0, 2)}:${p.substring(2, 4)}:${p.substring(4, 6)}';
  }

  /// Resolve [mac] to a vendor name. Returns the registered vendor when the OUI
  /// is in the bundled table, otherwise the raw OUI string (e.g. `B8:27:EB`) so
  /// the result is always interpretable. Returns null only when the MAC is not
  /// a valid 6-byte address.
  ///
  /// Locally-administered / randomized addresses (U/L bit of the first octet
  /// set — common on modern phones) are reported as `Randomized (local)` rather
  /// than misattributed to whatever IEEE block the random bytes happen to hit.
  static String? lookup(String mac) {
    final String hex = mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 12) return null;

    final int firstOctet = int.parse(hex.substring(0, 2), radix: 16);
    // U/L bit (0x02): locally administered — no IEEE vendor exists for it.
    if ((firstOctet & 0x02) != 0) return 'Randomized (local)';

    final String oui = hex.substring(0, 6).toUpperCase();
    final String? vendor = _table[oui];
    if (vendor != null) return vendor;
    // Unknown prefix → show the raw OUI, never null and never invented.
    return '${oui.substring(0, 2)}:${oui.substring(2, 4)}:${oui.substring(4, 6)}';
  }

  /// True when [mac] resolved to a NAMED vendor from the bundled table (not a
  /// raw-OUI fallback and not a randomized address). Useful for the debug
  /// screen to count "named" hits.
  static bool isNamedVendor(String mac) {
    final String hex = mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 12) return false;
    final int firstOctet = int.parse(hex.substring(0, 2), radix: 16);
    if ((firstOctet & 0x02) != 0) return false;
    return _table.containsKey(hex.substring(0, 6).toUpperCase());
  }
}
