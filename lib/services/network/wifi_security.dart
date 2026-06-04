// Wi-Fi security-type classifier — maps the COARSE iOS and the FINER macOS
// native security enums into one honest, cross-platform label set.
//
// TICKET-BATCH7 (item #6). The two platforms expose different fidelity, and the
// Truthfulness-Audit rule (GL-005) forbids over-claiming:
//
//   * iOS  — NEHotspotNetwork.securityType (iOS 15+) is COARSE:
//            open / WEP / personal / enterprise / unknown. `.personal` does NOT
//            distinguish WPA2 from WPA3, and there is NO `.owe` case. So on iOS
//            we report "Personal (WPA/WPA2/WPA3-PSK)" — never a specific "WPA3"
//            the API cannot confirm.
//   * macOS — CoreWLAN CWInterface.security() returns the FINER CWSecurity:
//            WPA2 Personal, WPA3 Personal, WPA3 Transition, WPA2/WPA3
//            Enterprise, Open, WEP, etc. We map each to a precise label.
//
// The native side hands Dart a STRING TOKEN (not a raw OS enum int), so this
// classifier is pure, web-safe, and unit-testable without a platform channel.
// Both channels emit tokens from the [kSecurityToken*] set below; an unknown or
// null token maps to [WifiSecurity.unknown] (honest), never to a guessed value.

/// A normalized Wi-Fi security classification, independent of the platform that
/// produced it. The [label] is what the UI shows; [isPersonalCoarse] marks the
/// iOS case where the API cannot tell WPA2 from WPA3.
enum WifiSecurity {
  /// Open / no encryption.
  open('Open (no encryption)'),

  /// Legacy WEP.
  wep('WEP'),

  /// iOS coarse Personal: WPA/WPA2/WPA3-PSK — the OS will not say which.
  personalCoarse('Personal (WPA/WPA2/WPA3-PSK)'),

  /// macOS WPA Personal (WPA1-PSK / TKIP era).
  wpaPersonal('WPA Personal'),

  /// macOS WPA2 Personal (WPA2-PSK).
  wpa2Personal('WPA2 Personal'),

  /// macOS WPA3 Personal (SAE).
  wpa3Personal('WPA3 Personal'),

  /// macOS WPA3 Transition (WPA2/WPA3 mixed-mode PSK).
  wpa3Transition('WPA2/WPA3 Transition'),

  /// iOS coarse Enterprise, or a platform that only says "Enterprise".
  enterpriseCoarse('Enterprise (802.1X)'),

  /// macOS WPA Enterprise (802.1X).
  wpaEnterprise('WPA Enterprise (802.1X)'),

  /// macOS WPA2 Enterprise (802.1X).
  wpa2Enterprise('WPA2 Enterprise (802.1X)'),

  /// macOS WPA3 Enterprise (802.1X).
  wpa3Enterprise('WPA3 Enterprise (802.1X)'),

  /// Opportunistic Wireless Encryption (Enhanced Open). Not an explicit case on
  /// either platform today — surfaced only if a native enum confirms it.
  owe('OWE (Enhanced Open)'),

  /// The platform returned a value but it maps to no known scheme.
  unknown('Unknown');

  const WifiSecurity(this.label);

  /// Human-readable label for the UI.
  final String label;

  /// True for the iOS coarse-Personal case, where the API cannot distinguish
  /// WPA2 from WPA3. Drives the honest "iOS reports only Personal vs Enterprise"
  /// footnote so the screen never implies a precision the OS did not give.
  bool get isPersonalCoarse => this == WifiSecurity.personalCoarse;

  /// True for the iOS coarse-Enterprise case (same honesty footnote applies).
  bool get isEnterpriseCoarse => this == WifiSecurity.enterpriseCoarse;
}

/// Maps the native security TOKENS into a [WifiSecurity]. Pure and web-safe so
/// it is unit-tested without a platform channel. The native channels are the
/// SSOT for these token strings:
///
///   * iOS  (NEHotspotNetworkSecurityType): open, wep, personal, enterprise,
///          unknown.
///   * macOS (CWSecurity): open, wep, wpaPersonal, wpaPersonalMixed,
///          wpa2Personal, personal, dynamicWEP, wpaEnterprise,
///          wpaEnterpriseMixed, wpa2Enterprise, enterprise, wpa3Personal,
///          wpa3Enterprise, wpa3Transition, owe, oweTransition, unknown, none.
///
/// Any token outside the known set (a future OS case, a typo) resolves to
/// [WifiSecurity.unknown] — the honest answer, never a guess.
abstract final class WifiSecurityClassifier {
  /// Classify a native security [token]. Case-insensitive; null/blank → null
  /// (no row to render). A recognized-but-unmapped token → [WifiSecurity.unknown].
  static WifiSecurity? classify(String? token) {
    if (token == null) return null;
    final String t = token.trim().toLowerCase();
    if (t.isEmpty) return null;
    return switch (t) {
      // Shared.
      'open' || 'none' => WifiSecurity.open,
      'wep' || 'dynamicwep' => WifiSecurity.wep,
      'owe' || 'owetransition' => WifiSecurity.owe,
      'unknown' => WifiSecurity.unknown,
      // iOS coarse.
      'personal' => WifiSecurity.personalCoarse,
      'enterprise' => WifiSecurity.enterpriseCoarse,
      // macOS fine — Personal.
      'wpapersonal' || 'wpapersonalmixed' => WifiSecurity.wpaPersonal,
      'wpa2personal' => WifiSecurity.wpa2Personal,
      'wpa3personal' => WifiSecurity.wpa3Personal,
      'wpa3transition' => WifiSecurity.wpa3Transition,
      // macOS fine — Enterprise.
      'wpaenterprise' || 'wpaenterprisemixed' => WifiSecurity.wpaEnterprise,
      'wpa2enterprise' => WifiSecurity.wpa2Enterprise,
      'wpa3enterprise' => WifiSecurity.wpa3Enterprise,
      _ => WifiSecurity.unknown,
    };
  }

  /// The label for a native [token], or null when there is nothing to show.
  static String? label(String? token) => classify(token)?.label;
}
