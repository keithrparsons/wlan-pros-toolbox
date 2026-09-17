// Chooses which radio this device can actually join with.
//
// THE PLATFORM CHECK IS THE WHOLE FILE. Everything else is a one-line
// constructor call. It is separate from join_backend.dart so that file stays
// free of any conditional import, and separate from the screen so the rule is
// testable and stated once.
import 'dart:io'
    if (dart.library.html) 'wifi_info_service_web_stub.dart'
    as platform_io;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'join_backend.dart';
import 'pi_backend_client.dart' show PiBackendClient;
// Web gets the stub, every native target gets the real FFI-backed one. The key
// is `dart.library.io` and not `dart.library.html`; see the stub's own note.
import 'windows_join_backend_web_stub.dart'
    if (dart.library.io) 'windows_join_backend.dart'
    show WindowsNativeJoinBackend;

/// True when THIS device can join with its own radio.
///
/// **WINDOWS ONLY, AND DELIBERATELY SO FOR 1.10.0.** Our own research says
/// macOS can join too, though it may demand an administrator password, and that
/// is a user-experience question rather than a capability one. iOS and Android
/// are the genuinely restricted pair. Adding macOS here is a one-line change
/// once that question is answered.
bool get deviceCanJoinNatively {
  if (kIsWeb) return false;
  return platform_io.Platform.isWindows;
}

/// The backend this device should use.
///
/// Falls back to the WLAN Pi everywhere the device cannot join for itself,
/// which is what every platform did before native join existed.
JoinBackend selectJoinBackend(PiBackendClient client) => deviceCanJoinNatively
    ? const WindowsNativeJoinBackend()
    : PiJoinBackend(client);
