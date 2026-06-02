// Companion-Shortcut distribution config for Wi-Fi Information LIVE mode
// (TICKET-01).
//
// Snapshot mode uses the existing SINGLE-SHOT companion Shortcut (run once →
// one update). LIVE mode needs the LOOPING companion Shortcut: it repeats while
// the native `ShouldContinueMonitoringIntent` returns the app's
// monitoring-active flag, sending one `ReceiveWiFiDetailsIntent` sample per
// pass, and stops cleanly the moment the in-app Stop button clears that flag.
//
// The looping Shortcut is published during device testing. Until then the link
// below is a clearly-marked PLACEHOLDER; the UI gates the Live "get the looping
// Shortcut" affordance on [isLoopShortcutUrlPlaceholder] exactly the way the
// cellular tool gated its Install action while its link was a placeholder
// (see [CellularShortcutsConfig]). The app never opens a dead link.
//
// The install link lives in exactly one place so swapping Keith's real iCloud
// link is a one-line change.

/// Configuration for installing and linking the LOOPING companion iOS Wi-Fi
/// Shortcut used by Live mode.
class WifiLiveShortcutsConfig {
  WifiLiveShortcutsConfig._();

  /// iCloud share link that installs the LOOPING companion Wi-Fi Shortcut.
  ///
  /// TODO(keith): PLACEHOLDER — replace with the real iCloud link once the
  /// looping Shortcut is published during device testing. Must end in a value
  /// that does NOT match the placeholder sentinel below to enable the Live
  /// "get the looping Shortcut" affordance. The single-shot Snapshot link is
  /// separate and unaffected.
  static const String kLoopShortcutUrl =
      'https://www.icloud.com/shortcuts/LOOP_SHORTCUT_PLACEHOLDER';

  /// True while [kLoopShortcutUrl] is still the placeholder. The Live UI uses
  /// this to disable the "get the looping Shortcut" action so the app never
  /// opens a dead link (mirrors [CellularShortcutsConfig.isShortcutUrlPlaceholder]).
  static bool get isLoopShortcutUrlPlaceholder =>
      kLoopShortcutUrl.endsWith('PLACEHOLDER');
}
