// Chooses which radio this device can actually join with.
//
// THE PLATFORM CHECK IS THE WHOLE FILE. Everything else is a one-line
// constructor call. It is separate from join_backend.dart so that file stays
// free of any conditional import, and separate from the screen so the rule is
// testable and stated once.
// defaultTargetPlatform, NOT dart:io. The web stub behind a conditional import
// does not define Platform.isIOS / isAndroid / isMacOS, and guarding the call
// with !kIsWeb is NOT enough: the compiler still needs the members to EXIST on
// the web target. `flutter build web` failed outright on 2026-09-17 for exactly
// that. defaultTargetPlatform is web-safe by construction and is already what
// the rest of this codebase uses.
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'join_backend.dart';
import 'pi_backend_client.dart' show PiBackendClient;
// Web gets the stub, every native target gets the real FFI-backed one. The key
// is `dart.library.io` and not `dart.library.html`; see the stub's own note.
import 'mac_join_backend_web_stub.dart'
    if (dart.library.io) 'mac_join_backend.dart'
    show MacNativeJoinBackend;
import 'windows_join_backend_web_stub.dart'
    if (dart.library.io) 'windows_join_backend.dart'
    show WindowsNativeJoinBackend;

/// True when THIS device can join with its own radio.
///
/// **macOS AND WINDOWS. Keith ruled the scope 2026-09-06:** *"Join a network is
/// macOS, Windows, and on a WLAN Pi - lets leave it off"*.
///
/// iOS is out because the OS does not let an app enumerate nearby networks, so
/// there is no list to pick from; that is a platform fact, not a gap in this
/// app. Android is out because Keith scoped it out, NOT because it cannot be
/// done, and the copy must keep those two apart.
///
/// **THE ADMIN-PASSWORD QUESTION IS SETTLED AND THE ANSWER IS NO.** An earlier
/// note here said macOS "may demand an administrator password". Tested on
/// Keith's own Mac 2026-09-17 with him watching: two joins between real SSIDs,
/// no prompt in either direction. Copy warning users about that dialog was
/// written and then deleted.
bool get deviceCanJoinNatively {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// The backend this device should use.
///
/// Falls back to the WLAN Pi everywhere the device cannot join for itself,
/// which is what every platform did before native join existed.
JoinBackend selectJoinBackend(PiBackendClient client) {
  if (kIsWeb) return PiJoinBackend(client);
  if (defaultTargetPlatform == TargetPlatform.windows)
    return const WindowsNativeJoinBackend();
  if (defaultTargetPlatform == TargetPlatform.macOS)
    return MacNativeJoinBackend();
  // iOS, Android and anything else: the WLAN Pi, which is what every platform
  // did before a native path existed.
  return PiJoinBackend(client);
}

/// Title for the screen a device sees when it cannot join for itself.
///
/// PURE, AND THAT IS THE POINT. The copy it replaces was branched on
/// `Platform.isIOS` inside a widget, which cannot be exercised on a Mac, so the
/// only platform whose wording could be checked was the one nobody would ship
/// wrong. Taking the platform as arguments means all three cases are testable
/// on any machine.
String joinUnavailableTitle({
  required bool isWeb,
  required bool isIOS,
  required bool isAndroid,
}) {
  if (isWeb) return 'Open this from a WLAN Pi';
  if (isIOS) return 'Not available on iPhone or iPad';
  if (isAndroid) return 'Not in this Android release';
  return 'Open this from a WLAN Pi';
}

/// Body copy for the same screen.
///
/// REPLACES A PROMISE THAT WAS FALSE IN 1.9.0. The screen said "Coming to this
/// device" on every platform. On macOS and Windows that came true. On iOS it
/// never will, and on Android it is not coming in this release, so shipping
/// that sentence again would have been a promise known to be wrong as it was
/// made.
///
/// THE TWO CASES ARE DIFFERENT SENTENCES AND MUST NOT COLLAPSE INTO ONE. A user
/// reading "not available" on iOS should not wait for a release that is never
/// coming; a user reading it on Android should not conclude the thing is
/// impossible. iOS is a platform decision and is NOT described as a limitation
/// of this app, because it is not one.
String joinUnavailableBody({
  required bool isWeb,
  required bool isIOS,
  required bool isAndroid,
}) {
  const String piFallback =
      'The tool works from a WLAN Pi today: open the Toolbox from a Pi in your '
      'browser and it joins the Pi\'s radio. Every other tool works normally '
      'here.';
  if (!isWeb && isIOS) {
    return 'iOS does not let an app list the Wi-Fi networks around it, so there '
        'is no list here to pick from. That is how iOS works rather than '
        'something this app is waiting to add, and it is not expected to '
        'change.\n\n$piFallback';
  }
  if (!isWeb && isAndroid) {
    return 'Joining from this device is not part of this release. It is '
        'possible on Android and it has not been ruled out, it simply is not '
        'built yet.\n\n$piFallback';
  }
  return 'Join a Network points a radio at a Wi-Fi network. On this device it '
      'needs a WLAN Pi, and there it joins the Pi\'s own radio rather than this '
      'one.\n\n$piFallback';
}
