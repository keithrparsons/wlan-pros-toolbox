import 'dart:async';
import 'dart:convert';

import 'package:net_quality/net_quality.dart';
import 'package:test/test.dart';

/// A fake [Ndt7Socket] driven entirely from memory: it replays a scripted list
/// of incoming messages (binary `List<int>` frames + text JSON frames) and
/// records every frame the client sends, so the NDT7 protocol logic is exercised
/// with no real network.
class FakeSocket implements Ndt7Socket {
  final StreamController<dynamic> _in = StreamController<dynamic>();
  final List<List<int>> sent = <List<int>>[];
  int _buffered;
  bool closed = false;

  FakeSocket({int bufferedAmount = 0}) : _buffered = bufferedAmount;

  /// Enqueues [messages] then closes the incoming stream so the download read
  /// loop terminates on `onDone`.
  void scriptAndClose(Iterable<Object> messages) {
    for (final m in messages) {
      _in.add(m);
    }
    _in.close();
  }

  /// Enqueues [messages] but leaves the stream open (used for the upload path,
  /// which terminates on the clock deadline, not on stream close).
  void script(Iterable<Object> messages) {
    for (final m in messages) {
      _in.add(m);
    }
  }

  int get totalSentBytes => sent.fold<int>(0, (a, b) => a + b.length);

  @override
  Stream<dynamic> get messages => _in.stream;

  @override
  void send(List<int> data) => sent.add(data);

  @override
  int get bufferedAmount => _buffered;

  set bufferedAmount(int v) => _buffered = v;

  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }
}

/// A monotonic fake clock: each call returns [base] + n·[step] and advances,
/// so the upload window's soft/hard deadlines are reached deterministically.
DateTime Function() advancingClock({
  Duration step = const Duration(milliseconds: 50),
  DateTime? base,
}) {
  final origin = base ?? DateTime.fromMillisecondsSinceEpoch(0);
  var n = 0;
  return () => origin.add(step * n++);
}

/// A timer seam that runs the body but returns a FIXED elapsed, so the download
/// rate math is deterministic. Mirrors how `ThroughputProbe` tests inject
/// `windowTimer`.
Ndt7ElapsedTimer fixedTimer(Duration elapsed) {
  return (body) async {
    await body();
    return elapsed;
  };
}

String serverUploadMeasurement({required int numBytes, required int elapsedMicros}) {
  return jsonEncode(<String, dynamic>{
    'AppInfo': <String, dynamic>{
      'NumBytes': numBytes,
      'ElapsedTime': elapsedMicros,
    },
    'TCPInfo': <String, dynamic>{'BytesReceived': numBytes, 'MinRTT': 12000},
    'Origin': 'server',
    'Test': 'upload',
  });
}

String locateBodyFor({
  String machine = 'mlab1-lga00.mlab-oti.measurement-lab.org',
}) {
  return jsonEncode(<String, dynamic>{
    'results': <dynamic>[
      <String, dynamic>{
        'machine': machine,
        'location': <String, dynamic>{'city': 'New York', 'country': 'US'},
        'urls': <String, dynamic>{
          'ws:///ndt/v7/download': 'ws://$machine/ndt/v7/download?access_token=t',
          'wss:///ndt/v7/download':
              'wss://$machine/ndt/v7/download?access_token=tok',
          'ws:///ndt/v7/upload': 'ws://$machine/ndt/v7/upload?access_token=t',
          'wss:///ndt/v7/upload': 'wss://$machine/ndt/v7/upload?access_token=tok',
        },
      },
    ],
  });
}

Ndt7LocateFetcher locateReturning(int status, String body) {
  return (url) async => Ndt7LocateResponse(status, body);
}

void main() {
  group('Ndt7Client.mbpsFor', () {
    test('25 MB over 2.0s is 100.0 Mbps', () {
      final mbps =
          Ndt7Client.mbpsFor(25 * 1000 * 1000, const Duration(seconds: 2));
      expect(mbps, closeTo(100.0, 0.0001));
    });

    test('divide-by-zero guard returns 0.0', () {
      expect(Ndt7Client.mbpsFor(1000000, Duration.zero), 0.0);
    });

    test('zero bytes returns 0.0', () {
      expect(Ndt7Client.mbpsFor(0, const Duration(seconds: 5)), 0.0);
    });
  });

  group('Ndt7Measurement.tryParse', () {
    test('parses AppInfo + TCPInfo + origin/test', () {
      final m = Ndt7Measurement.tryParse(
        serverUploadMeasurement(numBytes: 12345, elapsedMicros: 1000000),
      )!;
      expect(m.appNumBytes, 12345);
      expect(m.appElapsedMicros, 1000000);
      expect(m.appElapsed, const Duration(seconds: 1));
      expect(m.tcpBytesReceived, 12345);
      expect(m.origin, 'server');
      expect(m.test, 'upload');
      expect(m.hasAppByteCount, isTrue);
    });

    test('malformed JSON yields null (never aborts a measurement)', () {
      expect(Ndt7Measurement.tryParse('not json {'), isNull);
      expect(Ndt7Measurement.tryParse('[1,2,3]'), isNull);
    });

    test('missing AppInfo means no usable byte count', () {
      final m = Ndt7Measurement.tryParse('{"Origin":"server"}')!;
      expect(m.hasAppByteCount, isFalse);
    });
  });

  group('Ndt7Target.tryParse', () {
    test('extracts wss download/upload URLs and machine host', () {
      final decoded = jsonDecode(locateBodyFor()) as Map<String, dynamic>;
      final entry = (decoded['results'] as List).first;
      final target = Ndt7Target.tryParse(entry)!;
      expect(target.host, 'mlab1-lga00.mlab-oti.measurement-lab.org');
      expect(target.downloadUrl.scheme, 'wss');
      expect(target.downloadUrl.path, '/ndt/v7/download');
      expect(target.uploadUrl.scheme, 'wss');
      expect(target.downloadUrl.queryParameters['access_token'], 'tok');
    });

    test('entry without wss urls returns null', () {
      final target = Ndt7Target.tryParse(<String, dynamic>{
        'machine': 'x',
        'urls': <String, dynamic>{'ws:///ndt/v7/download': 'ws://x/d'},
      });
      expect(target, isNull);
    });
  });

  group('Ndt7Client.locate', () {
    test('parses results into ordered targets', () async {
      final client = Ndt7Client(
        locateFetcher: locateReturning(200, locateBodyFor()),
      );
      final targets = await client.locate();
      expect(targets, hasLength(1));
      expect(targets.first.downloadUrl.scheme, 'wss');
    });

    test('empty results -> Ndt7NoServerAvailable (not a fake 0)', () async {
      final client = Ndt7Client(
        locateFetcher: locateReturning(200, '{"results":[]}'),
      );
      expect(client.locate(), throwsA(isA<Ndt7NoServerAvailable>()));
    });

    test('HTTP 500 -> Ndt7NoServerAvailable', () async {
      final client = Ndt7Client(
        locateFetcher: locateReturning(500, 'upstream error'),
      );
      expect(client.locate(), throwsA(isA<Ndt7NoServerAvailable>()));
    });

    test('API error object -> Ndt7NoServerAvailable', () async {
      final client = Ndt7Client(
        locateFetcher:
            locateReturning(200, '{"error":{"title":"no capacity"}}'),
      );
      expect(client.locate(), throwsA(isA<Ndt7NoServerAvailable>()));
    });

    test('fetcher throwing -> Ndt7NoServerAvailable', () async {
      final client = Ndt7Client(
        locateFetcher: (url) => throw Exception('DNS failure'),
      );
      expect(client.locate(), throwsA(isA<Ndt7NoServerAvailable>()));
    });
  });

  group('Ndt7Client.measure — download', () {
    test('sums all received binary bytes over the injected elapsed', () async {
      // Two 1.25 MB binary frames = 2.5 MB total; over 0.2s => 100 Mbps.
      final dl = FakeSocket()
        ..scriptAndClose(<Object>[
          List<int>.filled(1250000, 1),
          List<int>.filled(1250000, 1),
        ]);
      final ul = FakeSocket()
        ..script(<Object>[
          serverUploadMeasurement(numBytes: 50000000, elapsedMicros: 10000000),
        ]);

      final client = Ndt7Client(
        measurementDuration: const Duration(milliseconds: 200),
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            url.path.contains('download') ? dl : ul,
        downloadTimer: fixedTimer(const Duration(milliseconds: 200)),
        clock: advancingClock(),
      );

      final result = await client.measure();
      expect(result.downloadBytes, 2500000);
      expect(result.downloadMbps, closeTo(100.0, 0.0001));
      expect(result.serverHost, 'mlab1-lga00.mlab-oti.measurement-lab.org');
    });

    test('counts text measurement bytes toward the honest total', () async {
      // A download stream carrying a binary frame plus a TEXT measurement frame:
      // "all received bytes" includes the text frame's bytes on the wire.
      final measurement =
          serverUploadMeasurement(numBytes: 1, elapsedMicros: 1);
      final textBytes = utf8.encode(measurement).length;
      final dl = FakeSocket()
        ..scriptAndClose(<Object>[List<int>.filled(1000, 7), measurement]);
      final ul = FakeSocket()
        ..script(<Object>[
          serverUploadMeasurement(numBytes: 10, elapsedMicros: 10),
        ]);

      final client = Ndt7Client(
        measurementDuration: const Duration(milliseconds: 200),
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            url.path.contains('download') ? dl : ul,
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: advancingClock(),
      );

      final result = await client.measure();
      expect(result.downloadBytes, 1000 + textBytes);
    });

    test('zero bytes -> Ndt7Unmeasurable (never a fake 0)', () async {
      final dl = FakeSocket()..scriptAndClose(<Object>[]);
      final client = Ndt7Client(
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async => dl,
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(client.measure(), throwsA(isA<Ndt7Unmeasurable>()));
    });

    test('download socket error -> Ndt7Unmeasurable', () async {
      final client = Ndt7Client(
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            throw Exception('connection refused'),
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: () => DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(client.measure(), throwsA(isA<Ndt7Unmeasurable>()));
    });
  });

  group('Ndt7Client.measure — upload', () {
    test('authoritative rate uses the SERVER byte count, not client sends',
        () async {
      // Server says it received 50 MB in 10s => 40 Mbps, regardless of how many
      // bytes the client actually pushed into the fake socket.
      final dl = FakeSocket()
        ..scriptAndClose(<Object>[List<int>.filled(1000000, 1)]);
      final ul = FakeSocket()
        ..script(<Object>[
          serverUploadMeasurement(numBytes: 20000000, elapsedMicros: 5000000),
          serverUploadMeasurement(numBytes: 50000000, elapsedMicros: 10000000),
        ]);

      final client = Ndt7Client(
        measureUpload: true,
        measurementDuration: const Duration(milliseconds: 300),
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            url.path.contains('download') ? dl : ul,
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: advancingClock(step: const Duration(milliseconds: 40)),
      );

      final result = await client.measure();
      expect(result.uploadBytes, 50000000);
      expect(result.elapsedUpload, const Duration(seconds: 10));
      expect(result.uploadMbps, closeTo(40.0, 0.0001));
      // The client did send frames, and the reported count is the server's, not
      // the client's raw send total.
      expect(ul.totalSentBytes, greaterThan(0));
      expect(result.uploadBytes, isNot(ul.totalSentBytes));
    });

    test('respects backpressure: stops queuing when bufferedAmount is high',
        () async {
      final dl = FakeSocket()
        ..scriptAndClose(<Object>[List<int>.filled(1000, 1)]);
      // bufferedAmount pinned above the per-turn budget so the send loop must
      // not enqueue anything, yet the measurement still completes from the
      // server frame.
      final ul = FakeSocket(bufferedAmount: 10 * 1024 * 1024)
        ..script(<Object>[
          serverUploadMeasurement(numBytes: 8000000, elapsedMicros: 1000000),
        ]);

      final client = Ndt7Client(
        measureUpload: true,
        measurementDuration: const Duration(milliseconds: 200),
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            url.path.contains('download') ? dl : ul,
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: advancingClock(step: const Duration(milliseconds: 40)),
      );

      final result = await client.measure();
      expect(ul.sent, isEmpty, reason: 'backpressure should block all sends');
      expect(result.uploadBytes, 8000000);
      expect(result.uploadMbps, closeTo(64.0, 0.0001));
    });

    test('upload failure is non-fatal: download returns, upload stays null',
        () async {
      final dl = FakeSocket()
        ..scriptAndClose(<Object>[List<int>.filled(1000, 1)]);
      final ul = FakeSocket()..script(<Object>[]); // server stays silent

      final client = Ndt7Client(
        measureUpload: true,
        measurementDuration: const Duration(milliseconds: 200),
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            url.path.contains('download') ? dl : ul,
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: advancingClock(step: const Duration(milliseconds: 40)),
      );

      final result = await client.measure();
      expect(result.downloadBytes, greaterThan(0),
          reason: 'the download still stands on its own');
      expect(result.uploadMbps, isNull,
          reason: 'a silent upload server must not fail the whole test');
    });

    test('upload is OFF by default: uploadMbps null even if a server would answer',
        () async {
      final dl = FakeSocket()
        ..scriptAndClose(<Object>[List<int>.filled(1000, 1)]);
      final ul = FakeSocket()
        ..script(<Object>[
          serverUploadMeasurement(numBytes: 8000000, elapsedMicros: 1000000),
        ]);

      final client = Ndt7Client(
        // measureUpload defaults to false
        measurementDuration: const Duration(milliseconds: 200),
        locateFetcher: locateReturning(200, locateBodyFor()),
        connector: (url, protocol) async =>
            url.path.contains('download') ? dl : ul,
        downloadTimer: fixedTimer(const Duration(seconds: 1)),
        clock: advancingClock(step: const Duration(milliseconds: 40)),
      );

      final result = await client.measure();
      expect(result.uploadMbps, isNull);
      expect(ul.sent, isEmpty,
          reason: 'the upload socket must not be driven when upload is off');
    });
  });

  group('Ndt7Client.measure — no server', () {
    test('empty Locate results surface before any socket is opened', () async {
      var connectorCalled = false;
      final client = Ndt7Client(
        locateFetcher: locateReturning(200, '{"results":[]}'),
        connector: (url, protocol) async {
          connectorCalled = true;
          return FakeSocket();
        },
      );
      await expectLater(
        client.measure(),
        throwsA(isA<Ndt7NoServerAvailable>()),
      );
      expect(connectorCalled, isFalse);
    });
  });
}
