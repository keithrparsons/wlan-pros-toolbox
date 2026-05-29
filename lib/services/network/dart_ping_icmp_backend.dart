// DartPingIcmpBackend — the real ICMP backend for IcmpService, wrapping the
// `dart_ping` (Android/desktop) + `dart_ping_ios` (iOS SimplePing) packages.
//
// ⚠️ DEVICE-PENDING — UNVERIFIABLE IN THIS ENVIRONMENT (GL-005 honesty bar):
// This adapter calls into a native ICMP stack that cannot be exercised without
// a real iOS/Android device:
//   - iOS:     `dart_ping_ios` (SimplePing/GBPing) needs a provisioned device
//              and the local-network permission prompt. Not testable in CI or
//              on a sandboxed Mac.
//   - Android: `dart_ping` spawns the system `ping` — needs a real device/
//              emulator, not the host test runner.
// Because of that, this file is kept DELIBERATELY THIN: it contains no
// branching logic of its own beyond mapping `dart_ping`'s `PingData` events
// onto IcmpService's `IcmpReply`. All capability gating, TTL sequencing, fold,
// and validation live in icmp_service.dart and ARE unit-tested with a fake
// backend. When the device pass happens, only THIS mapping needs live
// confirmation.
//
// macOS/desktop note (GL-008): `dart_ping` would spawn `/sbin/ping`, which the
// macOS App Sandbox blocks. IcmpService.echoCapability returns
// `sandboxedDesktop` there and the screen never constructs this backend on
// desktop — so the sandbox trap is avoided by gating, not discovered at runtime.
//
// This file is intentionally NOT imported by icmp_service.dart (which stays
// package-free and fully testable). It is wired only at the screen layer on a
// supported native target.
//
// To activate, add to pubspec.yaml:
//   dart_ping: ^9.0.1
//   dart_ping_ios: ^4.0.2          # iOS SimplePing support
// and call `DartPingIOS.register();` once at app start (main.dart) so the iOS
// factory is installed. Until those deps are added this file does not compile;
// it ships commented-out-by-dependency on purpose so the testable foundation
// lands first and the device-pending native layer is added under a real device
// pass. See the session log for the activation checklist.

// ignore_for_file: unused_import
// The dart_ping import is the device-pending dependency. It is referenced in
// the (currently inert) adapter body below; see the file header.

import 'dart:async';

import 'icmp_service.dart';

/// Real ICMP backend over `dart_ping` / `dart_ping_ios`.
///
/// NOT WIRED until the `dart_ping` dependencies are added (see header). The
/// body below shows the exact mapping that the device pass must confirm; it is
/// written against `dart_ping`'s public API (`Ping`, `PingData`,
/// `PingResponse`, `PingError`) so activation is a pubspec change plus
/// uncommenting, not a rewrite.
class DartPingIcmpBackend implements IcmpBackend {
  const DartPingIcmpBackend();

  @override
  Stream<IcmpReply> echo({
    required String host,
    required int count,
    required Duration interval,
    required Duration timeout,
    int? ttl,
    Future<void>? cancel,
  }) {
    // DEVICE-PENDING IMPLEMENTATION — activate with the dart_ping dependency.
    //
    // final controller = StreamController<IcmpReply>();
    // final ping = Ping(
    //   host,
    //   count: count <= 0 ? null : count,
    //   interval: interval.inMilliseconds / 1000.0,
    //   timeout: timeout.inMilliseconds ~/ 1000,
    //   ttl: ttl ?? 255,            // outbound TTL; low value drives TTL-walk
    // );
    // int seq = 0;
    // cancel?.then((_) => ping.stop());
    // final sub = ping.stream.listen((PingData data) {
    //   final r = data.response;
    //   final e = data.error;
    //   if (r != null) {
    //     controller.add(IcmpReply(
    //       sequence: r.seq ?? ++seq,
    //       success: true,
    //       rttMs: r.time?.inMicroseconds == null
    //           ? null
    //           : r.time!.inMicroseconds / 1000.0,
    //       fromIp: r.ip,
    //       ttl: r.ttl,
    //     ));
    //   } else if (e != null) {
    //     controller.add(IcmpReply(
    //       sequence: ++seq,
    //       success: false,
    //       errorLabel: switch (e.error) {
    //         ErrorType.requestTimedOut => 'timeout',
    //         ErrorType.unknownHost => 'unknownHost',
    //         _ => 'error',
    //       },
    //     ));
    //   }
    //   // data.summary arrives last; we close on stream done.
    // }, onDone: controller.close, onError: controller.addError);
    // controller.onCancel = () async {
    //   ping.stop();
    //   await sub.cancel();
    // };
    // return controller.stream;

    throw UnimplementedError(
      'DartPingIcmpBackend is device-pending: add the dart_ping / dart_ping_ios '
      'dependencies and activate the mapping in this file. The IcmpService '
      'foundation and both screens are complete and tested against a fake '
      'backend; only this native adapter awaits a real-device pass.',
    );
  }
}
