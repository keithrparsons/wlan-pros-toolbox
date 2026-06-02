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
  /// LIVE: the "WLAN Pros Cellular" Shortcut is published and device-verified
  /// (all five cellular fields confirmed on a real iPhone 2026-06-01).
  /// [isShortcutUrlPlaceholder] is now false, so the Install action is enabled.
  static const String kCompanionShortcutUrl =
      'https://www.icloud.com/shortcuts/f00b34ab4ed5490892cdd90c0c945f3e';

  /// True while [kCompanionShortcutUrl] is still the placeholder. The UI uses
  /// this to disable the Install action so the app never opens a dead link.
  /// Now false: the real published link is wired above.
  static bool get isShortcutUrlPlaceholder =>
      kCompanionShortcutUrl.endsWith('PLACEHOLDER');

  /// Canonical name of the published companion Cellular Shortcut (TICKET-03
  /// one-tap trigger). The app fires `shortcuts://x-callback-url/run-shortcut`
  /// with this exact name; iOS matches it against the user's installed
  /// Shortcuts by name, so the published Shortcut MUST be named exactly this —
  /// confirmed during the device test. Changing this string without renaming
  /// the published Shortcut breaks the "Get Reading" trigger.
  static const String kCompanionShortcutName = 'WLAN Pros Cellular';
}
