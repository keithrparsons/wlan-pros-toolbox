// Companion-Shortcut distribution config for the Cellular Information tool
// (TICKET-02).
//
// The companion iOS Shortcut is the data source for the Cellular Information
// tool. It harvests the device's cellular details (carrier, radio technology,
// signal bars, country code, roaming) with the cellular branch of the stock
// "Get Network Details" action and hands them to the app via the App Group
// transport.
//
// The install link lives in exactly one place so swapping Keith's real iCloud
// link is a one-line change.

/// Configuration for installing and linking the companion iOS cellular
/// Shortcut.
class CellularShortcutsConfig {
  CellularShortcutsConfig._();

  /// iCloud share link that installs the companion cellular Shortcut.
  ///
  /// TODO(device-testing): replace this PLACEHOLDER with Keith's real iCloud
  /// link once the "WLAN Pros Toolbox Cellular" Shortcut is published and
  /// device-verified (the same flow as the Wi-Fi Shortcut in TICKET-03 Part B).
  /// Until then [isShortcutUrlPlaceholder] is true and the Install action is
  /// disabled so the app never opens a dead link.
  static const String kCompanionShortcutUrl =
      'https://www.icloud.com/shortcuts/CELLULAR_PLACEHOLDER';

  /// True while [kCompanionShortcutUrl] is still the placeholder. The UI uses
  /// this to disable the Install action so the app never opens a dead link.
  static bool get isShortcutUrlPlaceholder =>
      kCompanionShortcutUrl.endsWith('PLACEHOLDER');
}
