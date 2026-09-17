// Web stub for mac_join_backend.dart.
//
// WHY THIS FILE EXISTS, and it is not ceremony. The real backend imports
// dart:ffi and win32 through windows_wifi_join_ffi.dart. Letting that reach the
// web target breaks `flutter build web` outright. Selected with
// `if (dart.library.io)` in join_backend_selector.dart, so web gets this and
// every native platform gets the real one.
//
// The previous key in this layer was `if (dart.library.html)`, which evaluated
// FALSE on the Flutter 3.44 web build and dragged dart:ffi into web anyway.
// See the note in windows_wifi_reader.dart; do not change the key back.
import 'join_backend.dart';
import 'pi_backend_client.dart' show PiJoinSecurity, PiScanInterface, PiScanNet;

/// Never constructed on web: the selector checks the platform first.
class MacNativeJoinBackend implements JoinBackend {
  const MacNativeJoinBackend();

  @override
  bool get joinsThisDevice => true;

  @override
  Future<List<PiScanInterface>> radios() async => const <PiScanInterface>[];

  @override
  Future<List<PiScanNet>> scan({String? interface}) async =>
      const <PiScanNet>[];

  @override
  Future<JoinOutcome> join({
    required String ssid,
    required PiJoinSecurity security,
    String? psk,
    String? interface,
  }) async => const JoinOutcome(
    connected: false,
    ssid: null,
    failureNote: 'Joining is not available in a browser.',
  );

  @override
  Future<JoinOutcome> disconnect({String? interface}) async =>
      const JoinOutcome(connected: false, ssid: null);
}
