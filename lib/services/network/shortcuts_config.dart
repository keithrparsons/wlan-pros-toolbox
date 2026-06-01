// Companion-Shortcut distribution config (TICKET-03).
//
// The companion iOS Shortcut is the data source for the Wi-Fi Details tool. It
// harvests the connected AP's RF metrics with the stock "Get Network Details"
// action -- with NO Location permission required (confirmed TICKET-01) -- and
// hands them to the app via the App Group transport.
//
// The install link lives in exactly one place so swapping Keith's real iCloud
// link is a one-line change.

/// Configuration for installing and linking the companion iOS Shortcut.
class ShortcutsConfig {
  ShortcutsConfig._();

  /// iCloud share link that installs the companion Shortcut.
  ///
  /// Set 2026-05-31 (TICKET-03 Part B) after Keith published and device-verified
  /// the "WLAN Pros Toolbox Wi-Fi" Shortcut (live streaming + in-app Stop
  /// confirmed on iPhone 17 Pro).
  static const String kCompanionShortcutUrl =
      'https://www.icloud.com/shortcuts/eac19bfd8ce6465482e54c034e23eb45';

  /// True while [kCompanionShortcutUrl] is still the placeholder. The UI uses
  /// this to disable the Install action so the app never opens a dead link.
  static bool get isShortcutUrlPlaceholder =>
      kCompanionShortcutUrl.endsWith('PLACEHOLDER');
}
