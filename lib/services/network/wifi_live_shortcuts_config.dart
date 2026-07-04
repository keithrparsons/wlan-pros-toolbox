// Companion-Shortcut distribution config for LIVE streaming.
//
// ONE combined companion Shortcut, "WLAN Pros Live", drives Live mode for BOTH
// the Wi-Fi Information and Cellular Information screens. Each cycle it gathers
// Wi-Fi + cellular details and hands BOTH to the native `ReceiveLiveDetailsIntent`
// as one JSON payload; the app splits that payload into the two App Group keys
// the existing bridges parse and posts one Darwin notification, so both Live
// screens update from a single delivery. The Shortcut loops while the native
// `ShouldContinueMonitoringIntent` returns the app's monitoring-active flag, and
// stops cleanly the moment in-app Stop clears that flag.
//
// The canonical name and the install link each live in exactly one place so the
// streaming trigger and the install affordance never drift, and swapping Keith's
// real iCloud link is a one-line change.

/// Configuration for installing and linking the combined LIVE companion iOS
/// Shortcut.
class WifiLiveShortcutsConfig {
  WifiLiveShortcutsConfig._();

  /// Canonical name of the combined LIVE companion Shortcut. The app fires the
  /// PLAIN `shortcuts://run-shortcut?name=<this>` URL; iOS matches it against the
  /// user's installed Shortcuts BY NAME, so the published Shortcut MUST be named
  /// exactly this. Both the Wi-Fi and Cellular Live screens trigger this one
  /// Shortcut. Changing this string without renaming the published Shortcut
  /// breaks Live streaming.
  static const String kLiveShortcutName = 'WLAN Pros Live';

  /// iCloud share link that installs the combined LIVE companion Shortcut.
  ///
  /// Published "WLAN Pros Live" Shortcut (Keith; re-shared FIXED link 2026-07-04).
  /// This is the link users tap to install the one combined Shortcut that drives
  /// Live streaming on both screens.
  static const String kLiveShortcutUrl =
      'https://www.icloud.com/shortcuts/73a342c0120b4777b2f0085776e9fd6f';

  /// True while [kLiveShortcutUrl] is still the placeholder. The Live UI uses
  /// this to disable the "get the Live Shortcut" action so the app never opens a
  /// dead link.
  static bool get isLiveShortcutUrlPlaceholder =>
      kLiveShortcutUrl.endsWith('PLACEHOLDER');

  /// App Store link for Apple's free Shortcuts app (Tom Hollingsworth: many users
  /// do not have it installed, so they fail before they can add our companion
  /// Shortcut). Surfaced FIRST in onboarding when the best-effort presence check
  /// reports Shortcuts is absent. One home so it never drifts.
  static const String kShortcutsAppStoreUrl =
      'https://apps.apple.com/app/shortcuts/id915249334';
}
