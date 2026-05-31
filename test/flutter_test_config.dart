// Auto-discovered by `flutter test` and run once before the whole suite.
//
// Disables google_fonts runtime network fetching during tests, mirroring what
// main.dart does for the running app (GoogleFonts.config.allowRuntimeFetching =
// false). main() does not run under `flutter test`, so without this a font that
// is not already cached (e.g. the newly added Roboto Mono) is fetched over the
// network on first use; in the test sandbox that throws "There is no current
// invoker", which fails the loading phase and cascades to unrelated tests.
// With fetching off, google_fonts falls back deterministically and font
// availability never gates a test run.

import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
