// ============================================================================
// STRUCTURAL GUARD — the ANDROID CELLULAR-DATA CONSENT GATE depends on a native
// method channel that NO DART TEST CAN SEE. This is that seam's only guard.
// ============================================================================
//
// WHY THIS FILE EXISTS. It is the answer to Vera's standard, applied to the round-4b
// Android gate: do not ask "does the gate fire?" — a gate fires on the bug you
// already know. Ask "CAN I STILL BUILD THE ARTIFACT IT FORBIDS?" Then actually try.
//
// I tried, and I found a FIFTH PATH to an unconsented throughput measurement on
// Android. It is not in the Dart. It is in the SEAM.
//
// THE PATH, CONCRETELY. `WifiConnectionService`'s Android verdict is driven by
// `MethodChannelNetworkTransportProbe`, which invokes `getTransport` on the channel
// `com.wlanpros.toolbox/network_transport`. That channel is registered in Kotlin, in
// `MainActivity.configureFlutterEngine`. If that registration is ever removed,
// renamed, or the channel-name string drifts by ONE CHARACTER in either file, then
// in production:
//
//     invokeMapMethod('getTransport')  ->  MissingPluginException
//                                      ->  read() returns null      (by design)
//                                      ->  status() falls through   (by design)
//                                      ->  address probe: `_platform != iOS`
//                                      ->  WifiConnectionStatus.unknown
//                                      ->  _notOnWifi == false
//                                      ->  spendData == TRUE, UNCONDITIONALLY
//                                      ->  the home hero's `autoStart: true` runs a
//                                          full ~30 s throughput measure + the RPM
//                                          load generator: 50-500 MB, ZERO TAPS.
//
// THE ORIGINAL ZERO-TAP DATA LEAK, RESTORED IN FULL, ON A STORE-LIVE PLATFORM — and
// EVERY DART TEST STILL PASSES, because a fake probe is injected in all of them.
// This is not hypothetical: the cold review's own EXPLOIT 1, run unmodified against
// the FIXED code, still passes for exactly this reason (it injects no transport
// probe, so it hits MissingPluginException and correctly resolves to `unknown`).
// That behavior is RIGHT — an unanswerable channel must never manufacture a verdict
// (GL-005) — and it is precisely what makes the seam invisible.
//
// Every fall-through above is individually CORRECT. The failure is that they
// COMPOSE into silence, and silence here means "spend the user's money".
//
// SO THE SEAM GETS A MECHANICAL CHECK. A linter cannot be socially deferred to, and
// this rule is expressible as one: the channel-name string the Dart side calls MUST
// appear in the Kotlin file that registers it, and the method name MUST be handled
// there. This test reads both files as TEXT — it is the only thing in the suite that
// can observe the Dart<->Kotlin boundary at all.
//
// WHAT THIS GUARD DOES NOT CATCH (read before trusting a green run). It proves the
// strings MATCH and the handler EXISTS. It does NOT prove the Kotlin returns correct
// values, that `ACCESS_NETWORK_STATE` is still declared (that IS checked below), or
// that the registration is actually reached at runtime. A real Android device run
// remains the only proof of that, and it has NOT been taken — see the KNOWN LIMITS
// in wifi_connection_service.dart. This guard closes the DRIFT path, not the
// device-behavior path.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The channel + method the Dart side calls. Kept as literals HERE, deliberately:
/// importing the constant from the Dart source would make this test pass whenever
/// Dart and itself agree — which is always. The point is to compare Dart to KOTLIN,
/// so at least one side must be pinned independently.
const String kChannel = 'com.wlanpros.toolbox/network_transport';
const String kMethod = 'getTransport';

const String kDartProbe = 'lib/services/network/network_transport_probe.dart';
const String kKotlinMain =
    'android/app/src/main/kotlin/com/wlanpros/wlan_pros_toolbox/MainActivity.kt';
const String kManifest = 'android/app/src/main/AndroidManifest.xml';

String _read(String path) {
  final File f = File(path);
  expect(f.existsSync(), isTrue, reason: 'MISSING FILE: $path');
  return f.readAsStringSync();
}

void main() {
  group('the Android transport channel seam cannot silently drift', () {
    test('the DART side still calls the pinned channel and method', () {
      final String dart = _read(kDartProbe);
      expect(dart, contains("'$kChannel'"),
          reason: 'the Dart probe no longer names the pinned channel. If this was '
              'a deliberate rename, rename it in MainActivity.kt AND here, in the '
              'same commit — or the Android cellular consent gate dies silently '
              'and every test still passes.');
      expect(dart, contains("'$kMethod'"),
          reason: 'the Dart probe no longer invokes the pinned method');
    });

    test('the KOTLIN side still REGISTERS that exact channel', () {
      final String kotlin = _read(kKotlinMain);
      expect(kotlin, contains('"$kChannel"'),
          reason: 'THE ANDROID CONSENT GATE IS DEAD. MainActivity.kt does not '
              'register "$kChannel". In production the Dart probe will throw '
              'MissingPluginException, resolve to `unknown`, and the home hero '
              'will auto-spend 50-500 MB of a cellular user\'s data with ZERO '
              'TAPS — with a fully green Dart suite, because every Dart test '
              'injects a fake probe.');
    });

    test('the KOTLIN side still HANDLES the pinned method', () {
      final String kotlin = _read(kKotlinMain);
      expect(kotlin, contains('"$kMethod"'),
          reason: 'MainActivity.kt registers the channel but no longer handles '
              '"$kMethod" — the call resolves to notImplemented(), the probe reads '
              'null, and the gate falls open exactly as if the channel were absent.');
      // The handler must actually be wired to a reader, not left as a stub.
      expect(kotlin, contains('readTransport()'),
          reason: 'the "$kMethod" case is no longer wired to readTransport()');
    });

    test('the KOTLIN reader still reads the THREE transports the table depends on',
        () {
      final String kotlin = _read(kKotlinMain);
      // The decision table in WifiConnectionService reads cellular / wifi to decide,
      // and ethernet to stay honest about a wired box. If any of these stops being
      // reported, the corresponding row of the table silently becomes unreachable —
      // the exact class of bug this whole change exists to remove (a verdict that
      // cannot be returned is a gate that cannot fire).
      for (final String transport in <String>[
        'TRANSPORT_CELLULAR',
        'TRANSPORT_WIFI',
        'TRANSPORT_ETHERNET',
        'TRANSPORT_VPN',
      ]) {
        expect(kotlin, contains('NetworkCapabilities.$transport'),
            reason: 'MainActivity.kt no longer reads $transport. A row of the '
                'Android decision table just became unreachable.');
      }
      // And it must report them under the keys the Dart payload parser reads.
      for (final String key in <String>[
        '"available"',
        '"cellular"',
        '"wifi"',
        '"ethernet"',
        '"vpn"',
      ]) {
        expect(kotlin, contains(key),
            reason: 'the Kotlin payload no longer carries the $key key the Dart '
                'probe parses. A missing key parses as `false` — SILENTLY, because '
                '`payload[k] == true` cannot tell absent from false.');
      }
    });

    test('ACCESS_NETWORK_STATE is still declared — the gate\'s only permission', () {
      final String manifest = _read(kManifest);
      expect(manifest, contains('android.permission.ACCESS_NETWORK_STATE'),
          reason: 'getNetworkCapabilities() requires ACCESS_NETWORK_STATE. Without '
              'it the read throws SecurityException, readTransport() returns '
              'available:false, and the consent gate falls open. It is a `normal` '
              '(install-time) permission and it must never be removed as "unused".');
    });

    test('the Dart probe still fails CLOSED to null, never to a verdict', () {
      final String dart = _read(kDartProbe);
      // The one shape that would turn a channel failure into a LIE rather than a
      // silence: a catch block that returns a fabricated verdict.
      expect(dart, contains('return null;'),
          reason: 'the probe must resolve an unreadable channel to null (→ '
              '`unknown`), never to a manufactured cellular or Wi-Fi verdict '
              '(GL-005).');
      expect(dart, isNot(contains('cellular: true,\n        wifi: false')),
          reason: 'the probe must never hard-code a transport verdict');
    });

    // ========================================================================
    // THE SIXTH PATH. Found by asking "can I still build the artifact it forbids?"
    // on an axis that has nothing to do with the channel.
    //
    // Test My Connection's ENTIRE consent gate reads `_notOnWifi`, which is
    // `_sampler?.notOnWifi ?? false` — and `_sampler` is ONLY constructed when
    // `widget.enableLiveSampling` is true (test_my_connection_screen.dart:523).
    //
    // So `enableLiveSampling: false` is a SILENT KILL-SWITCH for the gate: the
    // sampler is null, `_notOnWifi` collapses to the `?? false` literal, `spendData`
    // goes unconditionally true, and the zero-tap 50-500 MB leak is back — with a
    // FULLY GREEN SUITE, because every consent test injects a sampler.
    //
    // It is NOT exploitable today: the flag defaults to `true` and BOTH production
    // routes (`testMyConnection`, `wifiVsInternet`) take the default. It is used
    // only by render/screenshot tests. But nothing STOPS a future route from
    // passing `false` — and nothing would fail if one did. That is precisely the
    // shape of every bug in this file's history.
    // ========================================================================
    test('NO PRODUCTION ROUTE may disable live sampling — it kills the TMC gate',
        () {
      final String router = _read('lib/router/app_router.dart');
      expect(router, isNot(contains('enableLiveSampling: false')),
          reason: 'A route that mounts TestMyConnectionScreen with '
              '`enableLiveSampling: false` builds NO WifiSignalSampler, so '
              '`_notOnWifi` collapses to its `?? false` literal and the '
              'cellular-data consent gate is DEAD on that route — zero-tap, '
              '50-500 MB, fully green suite. If a route genuinely needs live '
              'sampling off, the gate must first be decoupled from the sampler.');
    });
  });
}
