// Web stub for the update-check platform surface.
//
// Selected by the `if (dart.library.io)` conditional import in
// app_update_service.dart on the web target ONLY. Web never checks for updates
// (the browser always serves the current build), so both entry points here are
// inert: the receipt probe reports "no receipt" and the fetcher is never
// reached because the channel resolver returns UpdateChannel.none on web before
// any fetch is attempted.
//
// Keeping this file free of dart:io is the whole point — see the sibling
// windows_wifi_reader.dart note on `if (dart.library.io)` being the correct
// selector key (an `if (dart.library.html)` key evaluates FALSE on the current
// web target and silently drags dart:io into the web build).

/// Web has no application bundle, so there is never a Mac App Store receipt.
bool macHasAppStoreReceipt() => false;

/// Never called on web (the channel resolver short-circuits first). Throws so a
/// wiring mistake fails loudly in a test rather than silently returning a
/// fabricated "up to date".
Future<Map<String, dynamic>> fetchLatestRelease(Duration timeout) {
  throw UnsupportedError('Update checks are not performed on web.');
}
