// Medium Access Simulator engine tests (Wi-Fi Classroom spec 02, "Done means").
//
// Pure Dart: no widgets. Every scenario is deterministic, either under a fixed
// seed or with scripted backoff draws, so each expected microsecond below is
// worked out by hand in the comment beside it.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/medium_access_engine.dart';

/// Scripted backoff draws, per station, consumed in order. Records every CW a
/// draw was made from so tests can check the doubling sequence.
class _Script {
  _Script(Map<int, List<int>> draws)
    : _draws = <int, List<int>>{
        for (final MapEntry<int, List<int>> e in draws.entries)
          e.key: List<int>.of(e.value),
      };

  final Map<int, List<int>> _draws;
  final Map<int, List<int>> cwSeen = <int, List<int>>{};

  int draw(int station, int cw) {
    cwSeen.putIfAbsent(station, () => <int>[]).add(cw);
    final List<int> q = _draws[station] ?? <int>[];
    return q.isEmpty ? cw : q.removeAt(0);
  }
}

MediumAccessEngine _engine(
  int stations, {
  AccessMode mode = AccessMode.dcf,
  bool hidden = false,
  bool rts = false,
  int seed = 1,
  EdcaParams? params,
  BackoffDraw? draw,
}) {
  return MediumAccessEngine(
    MediumAccessConfig(
      stations: List<StationConfig>.filled(stations, const StationConfig()),
      mode: mode,
      hiddenNode: hidden,
      rtsCts: rts,
      seed: seed,
      paramsOverride: params,
    ),
    backoffDraw: draw,
    retentionUs: 1 << 30,
  );
}

/// Advance until simulated time is at least [us].
void _runTo(MediumAccessEngine e, int us) {
  while (e.nowUs < us) {
    e.stepSlot();
  }
}

List<AirFrame> _dataFrom(MediumAccessEngine e, int station) => <AirFrame>[
  for (final AirFrame f in e.airFrames)
    if (f.source == station && f.kind == FrameKind.data) f,
];

void main() {
  group('interframe spaces', () {
    test('DIFS = SIFS + 2 x slot = 34 us', () {
      expect(OfdmTiming.slotUs, 9);
      expect(OfdmTiming.sifsUs, 16);
      expect(OfdmTiming.difsUs, 34);
      expect(kLegacyDcfParams.aifsUs, 34);
    });

    test('AIFS per access category = SIFS + AIFSN x slot', () {
      expect(AccessCategory.voice.params.aifsUs, 34); // 16 + 2 x 9
      expect(AccessCategory.video.params.aifsUs, 34); // 16 + 2 x 9
      expect(AccessCategory.bestEffort.params.aifsUs, 43); // 16 + 3 x 9
      expect(AccessCategory.background.params.aifsUs, 79); // 16 + 7 x 9
    });

    test('EDCA table matches the 802.11 non-AP defaults', () {
      expect(
        AccessCategory.voice.params,
        const EdcaParams(aifsn: 2, cwMin: 3, cwMax: 7),
      );
      expect(
        AccessCategory.video.params,
        const EdcaParams(aifsn: 2, cwMin: 7, cwMax: 15),
      );
      expect(
        AccessCategory.bestEffort.params,
        const EdcaParams(aifsn: 3, cwMin: 15, cwMax: 1023),
      );
      expect(
        AccessCategory.background.params,
        const EdcaParams(aifsn: 7, cwMin: 15, cwMax: 1023),
      );
    });

    test('EIFS = SIFS + DIFS + ACK at 6 Mbps = 16 + 34 + 44 = 94 us', () {
      expect(OfdmTiming.frameDurationUs(14, 6), 44); // 20 + 4 x ceil(134/24)
      expect(OfdmTiming.eifsUs, 94);
    });
  });

  group('OFDM airtime formula', () {
    test('ACK: 14 bytes at 24 Mbps = 20 + 4 x ceil(134/96) = 28 us', () {
      expect(OfdmTiming.frameDurationUs(14, 24), 28);
      expect(OfdmTiming.ackUs, 28);
    });

    test('1500 bytes at 54 Mbps = 20 + 4 x ceil(12022/216) = 244 us', () {
      expect(OfdmTiming.frameDurationUs(1500, 54), 244);
    });

    test('RTS (20 bytes) and CTS (14 bytes) at 24 Mbps are 28 us each', () {
      expect(OfdmTiming.rtsUs, 28); // 20 + 4 x ceil(182/96)
      expect(OfdmTiming.ctsUs, 28);
    });

    test('lower rates stretch the same frame', () {
      // 12022 bits / 24 bits per symbol = 500.9 -> 501 symbols.
      expect(OfdmTiming.frameDurationUs(1500, 6), 20 + 4 * 501);
    });
  });

  group('contention window', () {
    test('doubles 15 -> 31 -> 63 ... and caps at CWmax 1023', () {
      final List<int> seq = <int>[15];
      while (seq.length < 10) {
        seq.add(nextContentionWindow(seq.last, 1023));
      }
      expect(seq, <int>[15, 31, 63, 127, 255, 511, 1023, 1023, 1023, 1023]);
    });

    test('voice caps at 7', () {
      expect(nextContentionWindow(3, 7), 7);
      expect(nextContentionWindow(7, 7), 7);
    });

    test('in the simulation, each collision doubles CW for both stations', () {
      // Both draw 0 three times running: three collisions in a row. The draw
      // after collision k is made from the doubled window.
      final _Script script = _Script(<int, List<int>>{
        0: <int>[0, 0, 0, 0],
        1: <int>[0, 0, 0, 0],
      });
      final MediumAccessEngine e = _engine(2, draw: script.draw);
      _runTo(e, 1500);
      expect(script.cwSeen[0]!.take(4), <int>[15, 31, 63, 127]);
      expect(script.cwSeen[1]!.take(4), <int>[15, 31, 63, 127]);
      expect(e.stats.failedAttempts, greaterThanOrEqualTo(6));
      expect(e.stats.delivered, 0);
    });

    test('success resets CW to CWmin', () {
      // One collision (CW 31), then A draws 0 and B 20: A delivers.
      final _Script script = _Script(<int, List<int>>{
        0: <int>[0, 0, 30],
        1: <int>[0, 20],
      });
      final MediumAccessEngine e = _engine(2, draw: script.draw);
      _runTo(e, 1000);
      expect(e.stations[0].delivered, 1);
      expect(e.stations[0].cw, 15);
      expect(script.cwSeen[0], <int>[15, 31, 15]);
    });
  });

  group('freeze and resume', () {
    test('a frozen count resumes where it stopped and is never redrawn', () {
      // A draws 2, B draws 5, medium idle from t = 0.
      //   AIFS ends at 34. Boundaries at 43 and 52 decrement both stations.
      //   A reaches 0 at 52 and transmits data 52..296. B is at 3 and freezes.
      //   ACK 312..340. Idle again from 340; AIFS to 374; B counts 3 more
      //   slots: 383 (2), 392 (1), 401 (0) and transmits at 401.
      // A's second draw is 10, so A cannot win before B.
      final _Script script = _Script(<int, List<int>>{
        0: <int>[2, 10],
        1: <int>[5, 30],
      });
      final MediumAccessEngine e = _engine(2, draw: script.draw);

      _runTo(e, 207); // inside A's frame
      expect(_dataFrom(e, 0).single.startUs, 52);
      expect(_dataFrom(e, 0).single.endUs, 296);
      final StationSnapshot b = e.stations[1];
      expect(b.phase, StationPhase.contending);
      expect(b.backoff, 3, reason: 'B froze at 3 when A took the medium');
      final LaneSegment frozen = e.segments.lastWhere(
        (LaneSegment s) => s.lane == 1,
      );
      expect(frozen.activity, LaneActivity.frozen);
      expect(frozen.count, 3);

      _runTo(e, 450);
      expect(_dataFrom(e, 1).first.startUs, 401);
      expect(
        script.cwSeen[1]!.length,
        1,
        reason: 'B drew once; the frozen count resumed instead of a redraw',
      );
    });
  });

  group('retry limit', () {
    test('a frame is dropped after 7 failed attempts and CW resets', () {
      // CWmin = CWmax = 0: both stations always draw 0 and always collide.
      final MediumAccessEngine e = _engine(
        2,
        params: const EdcaParams(aifsn: 2, cwMin: 0, cwMax: 0),
      );
      // One attempt cycle is 296 us (data 244 + SIFS + ACK timeout + slot
      // alignment); run enough for two full drops.
      _runTo(e, 6000);
      for (final StationSnapshot s in e.stations) {
        expect(s.delivered, 0);
        expect(s.dropped, greaterThanOrEqualTo(2));
        expect(s.failedAttempts ~/ 7, s.dropped);
        expect(s.cw, 0);
      }
    });

    test('with the default table, a drop puts CW back to CWmin', () {
      // Script 7 straight collisions, then separate the two stations.
      final _Script script = _Script(<int, List<int>>{
        0: <int>[0, 0, 0, 0, 0, 0, 0, 0],
        1: <int>[0, 0, 0, 0, 0, 0, 0, 40],
      });
      final MediumAccessEngine e = _engine(2, draw: script.draw);
      _runTo(
        e,
        3000,
      ); // 7 collisions end near 2106 us; stop before a second run of them could start
      expect(e.stations[0].dropped, 1);
      expect(e.stations[1].dropped, 1);
      // Draws 1..7 came from 15, 31, 63, 127, 255, 511, 1023; the eighth, for
      // the next frame, from CWmin again.
      expect(script.cwSeen[0]!.take(8), <int>[
        15,
        31,
        63,
        127,
        255,
        511,
        1023,
        15,
      ]);
    });
  });

  group('one station alone', () {
    test('never collides, and its throughput matches the hand arithmetic', () {
      final MediumAccessEngine e = _engine(1);
      _runTo(e, 500000);
      final MediumAccessStats s = e.stats;
      expect(s.failedAttempts, 0);
      expect(s.dataFramesCorrupted, 0);
      expect(s.delivered, greaterThan(1000));
      // Mean cycle = DIFS 34 + 7.5 x 9 + data 244 + SIFS 16 + ACK 28
      // = 389.5 us for 12000 bits: about 30.8 Mbps.
      expect(s.throughputMbps, closeTo(30.8, 1.0));
    });

    test('EDCA voice alone never collides either', () {
      final MediumAccessEngine e = MediumAccessEngine(
        const MediumAccessConfig(
          stations: <StationConfig>[
            StationConfig(accessCategory: AccessCategory.voice),
          ],
        ),
      );
      e.advanceSlots(20000);
      expect(e.stats.failedAttempts, 0);
    });
  });

  group('EIFS', () {
    test('a bystander that heard a collision waits EIFS, labeled', () {
      // A and B draw 0: both transmit at 34 and collide, 34..278. C drew 5
      // and freezes. C heard two overlapping frames it could not decode, so
      // from 278 it waits EIFS - DIFS + DIFS = 94 us (to 372), then counts 5
      // slots: 381, 390, 399, 408, 417 -> transmits at 417.
      final _Script script = _Script(<int, List<int>>{
        0: <int>[0, 30],
        1: <int>[0, 30],
        2: <int>[5, 30],
      });
      final MediumAccessEngine e = _engine(3, draw: script.draw);
      _runTo(e, 500);
      final LaneSegment eifs = e.segments.firstWhere(
        (LaneSegment s) => s.lane == 2 && s.activity == LaneActivity.eifs,
      );
      expect(eifs.startUs, 278);
      expect(eifs.endUs, 372);
      expect(_dataFrom(e, 2).first.startUs, 417);
      // The colliders themselves take no EIFS: they were transmitting.
      expect(
        e.segments.where(
          (LaneSegment s) => s.lane < 2 && s.activity == LaneActivity.eifs,
        ),
        isEmpty,
      );
    });

    test('the collided frames are marked failed on their lanes', () {
      final _Script script = _Script(<int, List<int>>{
        0: <int>[0, 30],
        1: <int>[0, 40],
      });
      final MediumAccessEngine e = _engine(2, draw: script.draw);
      _runTo(e, 400);
      final Iterable<LaneSegment> tx = e.segments.where(
        (LaneSegment s) => s.activity == LaneActivity.transmit,
      );
      expect(tx, hasLength(2));
      expect(tx.every((LaneSegment s) => s.failed), isTrue);
      expect(e.airFrames.every((AirFrame f) => f.corruptedAtAp), isTrue);
    });
  });

  group('hidden node and RTS/CTS', () {
    MediumAccessStats run({required bool rts, required int seed}) {
      final MediumAccessEngine e = _engine(
        2,
        hidden: true,
        rts: rts,
        seed: seed,
      );
      e.advanceSlots(500000 ~/ OfdmTiming.slotUs);
      return e.stats;
    }

    test('hidden stations collide at the AP without RTS/CTS', () {
      for (final int seed in <int>[1, 2, 3]) {
        final MediumAccessStats s = run(rts: false, seed: seed);
        expect(
          s.dataFramesCorrupted / s.dataFrames,
          greaterThan(0.2),
          reason: 'seed $seed',
        );
      }
    });

    test('RTS/CTS makes the data-frame collisions all but disappear', () {
      // Measured at 1 s on seeds 1 to 3: 981 / 1012 / 1115 corrupt data frames
      // without RTS/CTS, 26 / 31 / 30 with it. The residue is the real 802.11
      // corner case: a hidden station whose own RTS overlaps the AP's CTS never
      // hears that CTS, so it has no NAV for the data that follows.
      for (final int seed in <int>[1, 2, 3]) {
        final MediumAccessStats off = run(rts: false, seed: seed);
        final MediumAccessStats on = run(rts: true, seed: seed);
        expect(
          on.dataFramesCorrupted / on.dataFrames,
          lessThan(0.05),
          reason: 'seed $seed',
        );
        expect(
          on.dataFramesCorrupted,
          lessThan(off.dataFramesCorrupted / 10),
          reason: 'seed $seed',
        );
        expect(on.throughputMbps, greaterThan(off.throughputMbps));
      }
    });

    test('with everyone in range, RTS/CTS leaves no data collisions', () {
      final MediumAccessEngine e = _engine(4, rts: true);
      e.advanceSlots(200000 ~/ OfdmTiming.slotUs);
      expect(e.stats.dataFramesCorrupted, 0);
      expect(e.stats.failedAttempts, greaterThan(0)); // RTS collisions only
    });

    test('with everyone in range, stations defer to each other', () {
      final MediumAccessEngine hiddenOff = _engine(2, seed: 4);
      hiddenOff.advanceSlots(200000 ~/ OfdmTiming.slotUs);
      final MediumAccessEngine hiddenOn = _engine(2, hidden: true, seed: 4);
      hiddenOn.advanceSlots(200000 ~/ OfdmTiming.slotUs);
      expect(
        hiddenOff.stats.collisionPercent,
        lessThan(hiddenOn.stats.collisionPercent),
      );
    });
  });

  group('EDCA priority', () {
    test('voice gets the medium sooner than best effort', () {
      final MediumAccessEngine e = MediumAccessEngine(
        const MediumAccessConfig(
          stations: <StationConfig>[
            StationConfig(accessCategory: AccessCategory.voice),
            StationConfig(accessCategory: AccessCategory.bestEffort),
          ],
        ),
      );
      e.advanceSlots(300000 ~/ OfdmTiming.slotUs);
      final List<StationSnapshot> s = e.stations;
      expect(s[0].delivered, greaterThan(s[1].delivered));
      final double vo = e.stats.accessDelay[AccessCategory.voice]!.meanUs!;
      final double be = e.stats.accessDelay[AccessCategory.bestEffort]!.meanUs!;
      expect(vo, lessThan(be));
    });
  });

  group('determinism and bounds', () {
    test('same config and seed give the identical run', () {
      MediumAccessStats go() {
        final MediumAccessEngine e = MediumAccessEngine(
          const MediumAccessConfig(
            stations: <StationConfig>[
              StationConfig(accessCategory: AccessCategory.video),
              StationConfig(framesPerSecond: 800),
              StationConfig(accessCategory: AccessCategory.background),
            ],
            seed: 42,
          ),
        );
        e.advanceSlots(20000);
        return e.stats;
      }

      final MediumAccessStats a = go();
      final MediumAccessStats b = go();
      expect(a.delivered, b.delivered);
      expect(a.failedAttempts, b.failedAttempts);
      expect(a.busyUs, b.busyUs);
      expect(a.deliveredBits, b.deliveredBits);
    });

    test('a different seed gives a different run', () {
      int deliveredFor(int seed) {
        final MediumAccessEngine e = _engine(5, seed: seed);
        e.advanceSlots(20000);
        return e.stats.failedAttempts * 100000 + e.stats.delivered;
      }

      expect(deliveredFor(1), isNot(deliveredFor(2)));
    });

    test('the clock only moves in whole 9 us slots', () {
      final MediumAccessEngine e = _engine(1);
      e.stepSlot();
      expect(e.nowUs, 9);
      e.advanceSlots(10);
      expect(e.nowUs, 99);
    });

    test('a light offered load leaves the medium mostly idle', () {
      final MediumAccessEngine e = MediumAccessEngine(
        const MediumAccessConfig(
          stations: <StationConfig>[StationConfig(framesPerSecond: 100)],
        ),
      );
      e.advanceSlots(1000000 ~/ OfdmTiming.slotUs);
      // About 100 exchanges of ~290 us in a second: under 5 percent busy.
      expect(e.stats.utilizationPercent, lessThan(5));
      expect(e.stats.delivered, inInclusiveRange(70, 130));
    });

    test('station count is bounded to 1..10', () {
      expect(() => _engine(0), throwsArgumentError);
      expect(() => _engine(11), throwsArgumentError);
      expect(() => _engine(10), returnsNormally);
    });
  });
}
