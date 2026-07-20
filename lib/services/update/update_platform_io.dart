// Native (dart:io) half of the update-check platform surface: the Mac App Store
// receipt probe and the single unauthenticated GitHub Releases GET.
//
// Split out behind a conditional import so app_update_service.dart itself stays
// dart:io-free and therefore web-compilable. See windows_wifi_reader.dart for
// why the selector key must be `if (dart.library.io)`.

import 'dart:io';

import '../network/json_http_client.dart';

/// The public release feed the direct-download builds track.
///
/// This is the repo the macOS .dmg is published to by ship_macos.sh (the site
/// repo, NOT the app repo). Pinned as a const so no caller can point the check
/// at an arbitrary host, and deliberately parameter-free: see the privacy note
/// in app_update_service.dart.
const String kLatestReleaseApiUrl =
    'https://api.github.com/repos/walnprosgithub/toolbox-wlanpros-site/releases/latest';

/// True when the running macOS bundle carries a Mac App Store receipt.
///
/// A bundle installed from the Mac App Store (or a macOS TestFlight build)
/// contains `Contents/_MASReceipt/receipt`; a Developer ID bundle distributed
/// as a direct .dmg never does. That asymmetry is the detection: presence is a
/// hard positive for "the store manages this install", so we suppress the
/// GitHub prompt. Verified empirically on a real machine both ways (a Mac App
/// Store app carries the receipt; the notarized Developer ID Toolbox bundle
/// does not).
///
/// `Platform.resolvedExecutable` is `<bundle>.app/Contents/MacOS/<exe>`, so the
/// `Contents` directory is two parents up. Any I/O failure (an unreadable path,
/// a non-bundle layout such as `flutter run` on a bare binary) reports false,
/// which routes to the direct-download branch. That is the safe direction: the
/// worst case is offering a download link to a developer build, never telling a
/// store customer to sideload a .dmg.
bool macHasAppStoreReceipt() {
  if (!Platform.isMacOS) return false;
  try {
    final Directory contents = File(Platform.resolvedExecutable).parent.parent;
    return File('${contents.path}/_MASReceipt/receipt').existsSync();
  } catch (_) {
    return false;
  }
}

/// Issue the one GET this feature makes and return the decoded release JSON.
///
/// Reuses the shared [JsonHttpClient] so the update check inherits the existing
/// https-only guard, connect timeout, bounded body read, and typed error
/// taxonomy rather than growing a second HTTP idiom. Every failure surfaces as
/// a thrown [JsonHttpException]; the service above turns all of them into the
/// same silent "unknown".
Future<Map<String, dynamic>> fetchLatestRelease(Duration timeout) {
  return JsonHttpClient().getJson(kLatestReleaseApiUrl, timeout: timeout);
}
