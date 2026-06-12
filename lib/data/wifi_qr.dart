// Wi-Fi "scan to join" QR payload builder — pure Dart, no Flutter.
//
// Builds the de-facto-standard Wi-Fi network QR string that iOS Camera and
// Android scanners recognize as a "join this network" offer:
//
//   WIFI:T:<auth>;S:<ssid>;P:<password>;H:<true|false>;;
//
// The format originates from the ZXing project's wifi-network barcode and is
// what Apple/Google honor. Two details silently break scanning if wrong, so
// they are the whole reason this lives in a separately unit-tested module:
//
//   1. ESCAPING. The special characters  \ ; , : "  are field/record
//      delimiters in the string, so any of them that appear INSIDE an SSID or
//      password value must be backslash-escaped (`\;`, `\,`, `\:`, `\"`, `\\`).
//      An SSID like `Cafe; Free` would otherwise be read as SSID `Cafe` plus a
//      stray field. We escape per the ZXing rule.
//
//   2. HEX-LOOKING / SPACE-PADDED values. If an SSID or password is composed
//      only of hex digits (so a scanner could mistake it for a raw hex value),
//      or has leading/trailing spaces that a parser might trim, the value is
//      wrapped in double quotes so it is taken verbatim. The quotes are part of
//      the on-wire value, not escaped content.
//
// auth mapping:
//   * WPA / WPA2 / WPA3  → `WPA`   (the scanners treat the WPA family as one)
//   * WEP                → `WEP`
//   * None (open)        → `nopass` and the `P:` field is omitted entirely.
//
// Pure computation, no platform touch — the screen feeds the returned string to
// the QR renderer exactly as it would a URL.

/// Wi-Fi authentication type chosen in the UI. The `WPA` member covers the
/// whole WPA/WPA2/WPA3 family (the QR auth token is `WPA` for all three).
enum WifiAuthType {
  /// WPA / WPA2 / WPA3 — all map to the `WPA` auth token.
  wpa,

  /// WEP — legacy; maps to the `WEP` auth token.
  wep,

  /// Open network, no password — maps to `nopass`, and `P:` is omitted.
  none,
}

/// The auth token written into the `T:` field of the WIFI string.
String wifiAuthToken(WifiAuthType auth) {
  switch (auth) {
    case WifiAuthType.wpa:
      return 'WPA';
    case WifiAuthType.wep:
      return 'WEP';
    case WifiAuthType.none:
      return 'nopass';
  }
}

/// Escape a single SSID / password value for embedding in a WIFI: string.
///
/// Backslash-escapes the five delimiter characters `\ ; , : "` (backslash
/// first, so an already-present backslash is not double-counted), then wraps
/// the whole value in double quotes when it is all-hex or has leading/trailing
/// whitespace, so a scanner takes it verbatim rather than re-interpreting it.
///
/// Exposed (not private) so the unit test can assert the escaping rule directly
/// — escaping is the part that silently breaks scanning when wrong.
String escapeWifiValue(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    final String ch = String.fromCharCode(rune);
    if (ch == '\\' ||
        ch == ';' ||
        ch == ',' ||
        ch == ':' ||
        ch == '"') {
      out.write('\\');
    }
    out.write(ch);
  }
  final String escaped = out.toString();

  // Quote-wrap rule: a value that is ALL hex digits could be misread as a raw
  // hex SSID/password, and a value with leading/trailing spaces could be
  // trimmed by a lenient parser. Quoting forces a verbatim read. The quotes go
  // OUTSIDE the already-escaped body (they are structural, not content).
  if (_needsQuoting(value)) {
    return '"$escaped"';
  }
  return escaped;
}

/// True when [value] should be double-quoted in the WIFI string: it is
/// non-empty and either all hex digits or has a leading/trailing space.
bool _needsQuoting(String value) {
  if (value.isEmpty) return false;
  final bool padded =
      value.startsWith(' ') || value.endsWith(' ');
  if (padded) return true;
  return _isAllHex(value);
}

/// True when every character of [value] is a hex digit (0-9, a-f, A-F).
bool _isAllHex(String value) {
  for (final int rune in value.runes) {
    final bool isDigit = rune >= 0x30 && rune <= 0x39; // 0-9
    final bool isLower = rune >= 0x61 && rune <= 0x66; // a-f
    final bool isUpper = rune >= 0x41 && rune <= 0x46; // A-F
    if (!isDigit && !isLower && !isUpper) return false;
  }
  return true;
}

/// Build the full Wi-Fi "scan to join" QR payload string.
///
///   `WIFI:T:<auth>;S:<ssid>;P:<password>;H:<true|false>;;`
///
/// * [ssid] and [password] are escaped via [escapeWifiValue].
/// * For [WifiAuthType.none] the `P:` field is omitted and the auth token is
///   `nopass`.
/// * The `H:` field is always emitted as `true` / `false`.
/// * The trailing `;;` terminates the record per the format.
String buildWifiQrPayload({
  required String ssid,
  required WifiAuthType auth,
  String password = '',
  bool hidden = false,
}) {
  final String token = wifiAuthToken(auth);
  final String escapedSsid = escapeWifiValue(ssid);

  final StringBuffer buf = StringBuffer('WIFI:');
  buf.write('T:$token;');
  buf.write('S:$escapedSsid;');

  // Open networks carry no password field at all (not an empty P:).
  if (auth != WifiAuthType.none) {
    buf.write('P:${escapeWifiValue(password)};');
  }

  buf.write('H:${hidden ? 'true' : 'false'};');
  buf.write(';'); // record terminator → trailing ";;"
  return buf.toString();
}
