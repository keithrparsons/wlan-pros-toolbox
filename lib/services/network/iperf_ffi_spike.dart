// =============================================================================
// EXPERIMENTAL / SPIKE — NOT WIRED INTO THE APP.
//
// Increment 0 of the iperf3-via-FFI feasibility effort. macOS (arm64) only.
//
// Proves that upstream libiperf (v3.18, the post-3.16 multi-threaded rewrite) can
// be driven through Dart FFI *in-process* — no subprocess, satisfying GL-008
// Constraint 1 (no CLI spawn in sandboxed native apps).
//
// This file is deliberately minimal: it binds JUST the C API needed to run an
// iperf3 CLIENT test and pull back the JSON throughput summary. It is hand-written
// rather than generated so the spike stays self-contained (no ffigen dependency
// added to the app's pubspec.yaml). The equivalent ffigen config is documented in
// the spike report.
//
// DO NOT import this from app code. It loads a dylib that only exists after running
//   third_party/iperf3/fetch_and_build.sh
// and that dylib is gitignored.
// =============================================================================

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- Opaque handle: `struct iperf_test *` ------------------------------------
// We never dereference it from Dart; it's an opaque pointer passed back to the C API.
final class IperfTest extends Opaque {}

// --- C function typedefs (native) and Dart-side typedefs ---------------------
// Signatures transcribed verbatim from third_party/iperf3/.../src/iperf_api.h:
//   struct iperf_test *iperf_new_test(void);
//   int   iperf_defaults(struct iperf_test *);
//   void  iperf_set_test_role(struct iperf_test*, char role);
//   void  iperf_set_test_server_hostname(struct iperf_test*, const char*);
//   void  iperf_set_test_server_port(struct iperf_test*, int);
//   void  iperf_set_test_duration(struct iperf_test*, int);
//   void  iperf_set_test_reverse(struct iperf_test*, int);
//   void  iperf_set_test_num_streams(struct iperf_test*, int);
//   void  iperf_set_test_json_output(struct iperf_test*, int);
//   int   iperf_run_client(struct iperf_test*);
//   char *iperf_get_test_json_output_string(struct iperf_test*);
//   void  iperf_free_test(struct iperf_test*);
//   char *iperf_strerror(int);

typedef _NewTestC = Pointer<IperfTest> Function();
typedef _NewTestDart = Pointer<IperfTest> Function();

typedef _DefaultsC = Int32 Function(Pointer<IperfTest>);
typedef _DefaultsDart = int Function(Pointer<IperfTest>);

typedef _SetRoleC = Void Function(Pointer<IperfTest>, Int8 role);
typedef _SetRoleDart = void Function(Pointer<IperfTest>, int role);

typedef _SetHostnameC = Void Function(Pointer<IperfTest>, Pointer<Utf8>);
typedef _SetHostnameDart = void Function(Pointer<IperfTest>, Pointer<Utf8>);

typedef _SetIntC = Void Function(Pointer<IperfTest>, Int32);
typedef _SetIntDart = void Function(Pointer<IperfTest>, int);

typedef _RunClientC = Int32 Function(Pointer<IperfTest>);
typedef _RunClientDart = int Function(Pointer<IperfTest>);

typedef _GetJsonC = Pointer<Utf8> Function(Pointer<IperfTest>);
typedef _GetJsonDart = Pointer<Utf8> Function(Pointer<IperfTest>);

typedef _FreeTestC = Void Function(Pointer<IperfTest>);
typedef _FreeTestDart = void Function(Pointer<IperfTest>);

typedef _StrerrorC = Pointer<Utf8> Function(Int32);
typedef _StrerrorDart = Pointer<Utf8> Function(int);

/// Result of an FFI-driven iperf3 client run.
class IperfSpikeResult {
  const IperfSpikeResult({
    required this.runCode,
    required this.json,
    this.errorText,
  });

  /// Return value of `iperf_run_client` (0 == success, <0 == error).
  final int runCode;

  /// The JSON summary string from `iperf_get_test_json_output_string`, or null.
  final String? json;

  /// Decoded `iperf_strerror(i_errno)` when [runCode] indicates failure.
  final String? errorText;

  bool get ok => runCode == 0 && json != null && json!.isNotEmpty;
}

/// Minimal FFI binding + driver for a single iperf3 client test.
///
/// EXPERIMENTAL. Construct with the absolute path to `libiperf.dylib`.
class IperfFfiSpike {
  IperfFfiSpike(String dylibPath) : _lib = DynamicLibrary.open(dylibPath) {
    _newTest = _lib.lookupFunction<_NewTestC, _NewTestDart>('iperf_new_test');
    _defaults =
        _lib.lookupFunction<_DefaultsC, _DefaultsDart>('iperf_defaults');
    _setRole =
        _lib.lookupFunction<_SetRoleC, _SetRoleDart>('iperf_set_test_role');
    _setHostname = _lib.lookupFunction<_SetHostnameC, _SetHostnameDart>(
        'iperf_set_test_server_hostname');
    _setPort = _lib.lookupFunction<_SetIntC, _SetIntDart>(
        'iperf_set_test_server_port');
    _setDuration = _lib.lookupFunction<_SetIntC, _SetIntDart>(
        'iperf_set_test_duration');
    _setReverse =
        _lib.lookupFunction<_SetIntC, _SetIntDart>('iperf_set_test_reverse');
    _setNumStreams = _lib.lookupFunction<_SetIntC, _SetIntDart>(
        'iperf_set_test_num_streams');
    _setJsonOutput = _lib.lookupFunction<_SetIntC, _SetIntDart>(
        'iperf_set_test_json_output');
    _runClient =
        _lib.lookupFunction<_RunClientC, _RunClientDart>('iperf_run_client');
    _getJson = _lib.lookupFunction<_GetJsonC, _GetJsonDart>(
        'iperf_get_test_json_output_string');
    _freeTest =
        _lib.lookupFunction<_FreeTestC, _FreeTestDart>('iperf_free_test');
    _strerror =
        _lib.lookupFunction<_StrerrorC, _StrerrorDart>('iperf_strerror');
  }

  final DynamicLibrary _lib;

  late final _NewTestDart _newTest;
  late final _DefaultsDart _defaults;
  late final _SetRoleDart _setRole;
  late final _SetHostnameDart _setHostname;
  late final _SetIntDart _setPort;
  late final _SetIntDart _setDuration;
  late final _SetIntDart _setReverse;
  late final _SetIntDart _setNumStreams;
  late final _SetIntDart _setJsonOutput;
  late final _RunClientDart _runClient;
  late final _GetJsonDart _getJson;
  late final _FreeTestDart _freeTest;
  late final _StrerrorDart _strerror;

  /// `i_errno` lives at a fixed-ish offset in `struct iperf_test`. Rather than
  /// model the whole struct, we read the error via `iperf_strerror` against the
  /// negated run code where the API exposes it; for the spike we surface the run
  /// code and the strerror of the last i_errno that the library prints itself.
  ///
  /// Runs a blocking iperf3 client test. BLOCKING — see threading notes in the
  /// spike report. For the spike, callers should wrap this in `Isolate.run`.
  IperfSpikeResult runClientTest({
    required String host,
    int port = 5201,
    int durationSeconds = 5,
    bool reverse = false,
    int numStreams = 1,
  }) {
    final test = _newTest();
    if (test == nullptr) {
      return const IperfSpikeResult(
        runCode: -1,
        json: null,
        errorText: 'iperf_new_test returned NULL',
      );
    }

    final hostPtr = host.toNativeUtf8();
    try {
      _defaults(test);
      _setRole(test, 'c'.codeUnitAt(0)); // 'c' == client
      _setHostname(test, hostPtr);
      _setPort(test, port);
      _setDuration(test, durationSeconds);
      _setReverse(test, reverse ? 1 : 0);
      _setNumStreams(test, numStreams);
      _setJsonOutput(test, 1); // emit JSON instead of human text

      final rc = _runClient(test); // <-- blocks until the test completes

      String? json;
      final jsonPtr = _getJson(test);
      if (jsonPtr != nullptr) {
        json = jsonPtr.toDartString();
      }

      String? errText;
      if (rc != 0) {
        // iperf exposes i_errno globally; iperf_strerror(i_errno) decodes it.
        // We import it as a global int symbol below for a precise message.
        final ie = _iErrno();
        final p = _strerror(ie);
        if (p != nullptr) errText = p.toDartString();
      }

      return IperfSpikeResult(runCode: rc, json: json, errorText: errText);
    } finally {
      malloc.free(hostPtr);
      _freeTest(test);
    }
  }

  /// Reads the global `int i_errno` symbol that libiperf sets on failure.
  int _iErrno() {
    try {
      final p = _lib.lookup<Int32>('i_errno');
      return p.value;
    } catch (_) {
      return 0;
    }
  }
}

/// Resolves the spike dylib path relative to the repo root, with override.
String resolveSpikeDylibPath() {
  const fromEnv =
      String.fromEnvironment('IPERF_DYLIB', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv;
  // Default to the build-script output location.
  final cwd = Directory.current.path;
  return '$cwd/third_party/iperf3/iperf-3.18/src/.libs/libiperf.dylib';
}
