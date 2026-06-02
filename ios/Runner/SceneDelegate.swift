import Flutter
import UIKit

/// Scene delegate for the UIScene lifecycle. Subclasses FlutterSceneDelegate so
/// the Flutter view attaches normally.
///
/// The Live streaming trigger fires a PLAIN, fire-and-forget
/// `shortcuts://run-shortcut?name=…` URL. That form does NOT return control to
/// the app via a custom URL scheme (the looping Shortcut never finishes), so
/// there is no x-callback to catch here. The app passively consumes the App
/// Group + Darwin stream the recursive Shortcut feeds. The former
/// `wlanprostoolbox://reading?…` x-callback handling was removed with the
/// snapshot one-tap trigger.
class SceneDelegate: FlutterSceneDelegate {}
