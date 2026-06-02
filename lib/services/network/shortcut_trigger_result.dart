// The result of a one-tap Shortcut trigger x-callback (TICKET-03).
//
// When the app fires the `shortcuts://x-callback-url/run-shortcut` URL, iOS runs
// the companion Shortcut and returns control to the app via the custom scheme,
// carrying the originating tool id + status as query items
// (`wlanprostoolbox://reading?tool=wifi-info&status=ok`, `…&status=err` on
// failure / cancellation). The native SceneDelegate parses that return URL and
// pushes a single wire string up the trigger-result event channel in the form
// `"<tool>|<ok|err>"` (the tool segment is empty for a legacy tool-less return).
//
// [ShortcutTriggerEvent.fromNative] decodes that wire string into a typed
// (tool, result) pair so the deep-link router can navigate to the originating
// tool screen — even on a cold relaunch — and the screens never branch on a
// magic string.

/// Outcome of a run-shortcut x-callback return.
enum ShortcutTriggerResult {
  /// The companion Shortcut ran and handed back control via `x-success`. The
  /// screen re-reads the App Group payload to refresh.
  success,

  /// The Shortcut was not found, errored, or the user cancelled (`x-error`).
  /// The screen shows an honest error with the install affordance as fallback.
  error;

  /// Maps the raw status token ("ok" / "err") to the typed result. Anything
  /// other than the error token is treated as success — the App Group payload is
  /// the source of truth and is re-read on resume regardless.
  static ShortcutTriggerResult fromStatus(String status) =>
      status == 'err' ? ShortcutTriggerResult.error : ShortcutTriggerResult.success;

  /// Back-compat alias: maps a bare status token to the typed result. Retained
  /// for callers that still receive only "ok"/"err".
  static ShortcutTriggerResult fromNative(String raw) => fromStatus(raw);
}

/// A decoded one-tap trigger return: WHICH tool fired it and the outcome.
///
/// The native side encodes the return as `"<tool>|<ok|err>"`. The [tool]
/// segment is the originating tool id (e.g. `wifi-info`, `cellular-info`) so the
/// deep-link router can route the return to that tool's screen on both the warm
/// resume and the cold-relaunch paths. A null/empty [tool] means a legacy
/// tool-less return — the router then refreshes whatever trigger screen is
/// already listening instead of navigating.
class ShortcutTriggerEvent {
  const ShortcutTriggerEvent({required this.tool, required this.result});

  /// Originating tool id, or null when the native return carried no tool.
  final String? tool;

  /// Whether the Shortcut run succeeded.
  final ShortcutTriggerResult result;

  /// Decodes the native wire string `"<tool>|<ok|err>"`. A missing separator or
  /// status defaults to success with no tool, so a malformed return never tears
  /// the stream down.
  static ShortcutTriggerEvent fromNative(String raw) {
    final int sep = raw.indexOf('|');
    if (sep < 0) {
      // No separator: treat the whole string as a bare status token.
      return ShortcutTriggerEvent(
        tool: null,
        result: ShortcutTriggerResult.fromStatus(raw),
      );
    }
    final String toolPart = raw.substring(0, sep).trim();
    final String statusPart = raw.substring(sep + 1).trim();
    return ShortcutTriggerEvent(
      tool: toolPart.isEmpty ? null : toolPart,
      result: ShortcutTriggerResult.fromStatus(statusPart),
    );
  }
}
