import Flutter
import UIKit

/// Scene delegate for the UIScene lifecycle. Subclasses FlutterSceneDelegate so
/// the Flutter view attaches normally.
///
/// TWO trigger forms reach Live mode:
///   * STREAMING (the looping monitor) fires a PLAIN, fire-and-forget
///     `shortcuts://run-shortcut?name=…` URL. That form does NOT return control
///     to the app (the looping Shortcut never finishes), so there is nothing to
///     catch here for it. The app passively consumes the App Group + Darwin
///     stream the recursive Shortcut feeds.
///   * ONE-SHOT reads (Get reading, auto-capture, the first read right after
///     install) fire the `x-callback-url` form with
///     `x-success=wlanprostoolbox://live-done`. When that single run FINISHES,
///     iOS opens the return URL, which re-foregrounds the Toolbox and routes
///     here. We re-post the bridge Darwin notification so the foregrounded Live
///     screen re-reads the App Group payload immediately, in case the single
///     delivered sample raced the app's foreground return. We never fabricate a
///     reading — if no payload was stored, the re-post simply finds nothing and
///     the screen's own settle-poll covers it.
class SceneDelegate: FlutterSceneDelegate {
  /// URLs delivered while the scene is already connected (the common one-shot
  /// return path: the app was backgrounded by the Shortcut run and foregrounded
  /// again by the x-success callback).
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    handleCallback(URLContexts.map { $0.url })
    super.scene(scene, openURLContexts: URLContexts)
  }

  /// URLs delivered as part of the scene's connection options (the app was
  /// cold-launched by the callback). Rare for the one-shot return, but handled
  /// so the path is robust.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    handleCallback(connectionOptions.urlContexts.map { $0.url })
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  /// Handles our one-shot x-callback returns, keyed on the URL host:
  ///   * `live-done`  (x-success) — the run FINISHED. Re-post the bridge Darwin
  ///     notification so the foregrounded Live screens re-read the App Group
  ///     payload the just-finished Shortcut delivered.
  ///   * `live-error` (x-error)   — the named "WLAN Pros Live" Shortcut COULD NOT
  ///     RUN (renamed/deleted). Reset install-state and raise the transient
  ///     missing marker via [ShortcutsBridge.markShortcutMissing] (which also
  ///     posts the Darwin notification). The foregrounded screen's resume→load
  ///     then surfaces the honest "Shortcut not found — re-run setup" recovery
  ///     instead of stranding the user on the Shortcuts page.
  /// A no-op for any URL not on our scheme.
  private func handleCallback(_ urls: [URL]) {
    for url in urls where url.scheme?.lowercased() == ShortcutsBridge.callbackScheme {
      switch url.host?.lowercased() {
      case "live-error":
        ShortcutsBridge.markShortcutMissing()
      default:
        // `live-done` and any other return on our scheme: nudge the foregrounded
        // Live screens to re-read the delivered payload.
        ShortcutsBridge.postDarwinNotification()
      }
      return
    }
  }
}
