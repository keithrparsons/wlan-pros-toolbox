import Flutter
import UIKit

/// Scene delegate for the UIScene lifecycle. Subclasses FlutterSceneDelegate so
/// the Flutter view attaches normally, and adds the TICKET-03 one-tap trigger
/// x-callback handling on top.
///
/// When the app fires
/// `shortcuts://x-callback-url/run-shortcut?…&x-success=wlanprostoolbox://reading?tool=wifi-info&status=ok`,
/// iOS runs the companion Shortcut (which stores its payload to the App Group)
/// and then returns control to the app via the `wlanprostoolbox://reading`
/// scheme, carrying the originating tool id + ok/err status as query items.
///
/// Two delivery paths, both handled here under the scene lifecycle:
///   * WARM resume — the app stayed alive; the return URL arrives on
///     `scene(_:openURLContexts:)`. We hand it to `AppDelegate.shared`, which
///     deep-links to the tool and refreshes.
///   * COLD launch — iOS killed the backgrounded app during the Shortcuts run
///     and relaunched it for the callback; the return URL rides in on
///     `connectionOptions` in `scene(_:willConnectTo:options:)`. The Flutter
///     engine + router are not up yet, so `AppDelegate` BUFFERS the callback and
///     replays it the moment the Dart deep-link listener attaches. This is the
///     case that used to dump the user on the home screen.
class SceneDelegate: FlutterSceneDelegate {

  /// Warm path: the app is alive and Shortcuts hands control back to it.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    handleCallbackURLs(URLContexts.map { $0.url })
    super.scene(scene, openURLContexts: URLContexts)
  }

  /// Cold path: the app was relaunched by the callback. The return URL rides in
  /// on the connection options before the Flutter engine is ready, so the
  /// AppDelegate buffers it until the Dart listener attaches.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    handleCallbackURLs(connectionOptions.urlContexts.map { $0.url })
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  /// Routes any `wlanprostoolbox://…` callback to the AppDelegate, which either
  /// delivers it to a live Dart listener (warm) or buffers it for replay on
  /// listen (cold). Non-matching schemes pass through to super for the normal
  /// Flutter path.
  private func handleCallbackURLs(_ urls: [URL]) {
    for url in urls {
      guard let callback = ShortcutsBridge.parseCallback(url) else { continue }
      AppDelegate.shared?.deliverTriggerCallback(callback)
    }
  }
}
