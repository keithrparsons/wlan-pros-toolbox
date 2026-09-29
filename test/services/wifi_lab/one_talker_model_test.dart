// One Talker per Channel model (spec 48, "Done means" 1): the even split per
// channel, one waiting line versus two, the slow device, clamps, and one
// talker per channel at every turn.

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/one_talker_model.dart';

void main() {
  test('one access point: N devices get 1/N each, N = 1 to 12', () {
    for (int n = 1; n <= kMaxClientsA; n++) {
      final OneTalkerScene s = oneTalker(OneTalkerConfig(clientsA: n));
      expect(s.channels, hasLength(1));
      expect(s.channels.single.number, kChannelA);
      expect(s.clients, hasLength(n));
      for (final OneTalkerClient k in s.clients) {
        expect(k.turnShare, closeTo(1 / n, 1e-12), reason: 'n=$n');
        expect(k.airtimeShare, closeTo(1 / n, 1e-12), reason: 'n=$n');
      }
    }
  });

  test('two access points on the same channel: 1/(N+M) each, one line', () {
    for (int n = 1; n <= kMaxClientsA; n++) {
      for (int m = 1; m <= kMaxClientsB; m++) {
        final OneTalkerScene s = oneTalker(
          OneTalkerConfig(
            clientsA: n,
            clientsB: m,
            secondAp: SecondAp.sameChannel,
          ),
        );
        expect(s.channels, hasLength(1));
        expect(s.channels.single.aps, <int>[1, 2]);
        expect(s.channels.single.talkers, n + m);
        for (final OneTalkerClient k in s.clients) {
          expect(k.airtimeShare, closeTo(1 / (n + m), 1e-12));
          expect(k.channel, kChannelA);
        }
      }
    }
  });

  test('two access points on different channels: 1/N and 1/M', () {
    for (int n = 1; n <= kMaxClientsA; n++) {
      for (int m = 1; m <= kMaxClientsB; m++) {
        final OneTalkerScene s = oneTalker(
          OneTalkerConfig(
            clientsA: n,
            clientsB: m,
            secondAp: SecondAp.otherChannel,
          ),
        );
        expect(s.channels.map((OneTalkerChannel c) => c.number), <int>[
          kChannelA,
          kChannelOther,
        ]);
        for (final OneTalkerClient k in s.clients) {
          final int on = k.ap == 1 ? n : m;
          expect(k.airtimeShare, closeTo(1 / on, 1e-12), reason: '$n $m');
          expect(k.channel, k.ap == 1 ? kChannelA : kChannelOther);
        }
      }
    }
  });

  test('shares on every channel sum to 1, every mode, slow on or off', () {
    for (final SecondAp ap in SecondAp.values) {
      for (final bool slow in <bool>[false, true]) {
        for (int n = 1; n <= kMaxClientsA; n++) {
          final OneTalkerScene s = oneTalker(
            OneTalkerConfig(
              clientsA: n,
              clientsB: 5,
              secondAp: ap,
              slowTalker: slow,
            ),
          );
          for (final OneTalkerChannel c in s.channels) {
            double air = 0;
            double turns = 0;
            for (final OneTalkerClient k in c.clients) {
              air += k.airtimeShare;
              turns += k.turnShare;
            }
            expect(air, closeTo(1, 1e-12));
            expect(turns, closeTo(1, 1e-12));
          }
        }
      }
    }
  });

  test('slow device A: turns stay 1/N, time is 4/(N+3) and 1/(N+3)', () {
    for (int n = 2; n <= kMaxClientsA; n++) {
      final OneTalkerScene s = oneTalker(
        OneTalkerConfig(clientsA: n, slowTalker: true),
      );
      final OneTalkerClient a = s.clients.first;
      expect(a.slow, isTrue);
      expect(a.letter, 'A');
      expect(a.turnShare, closeTo(1 / n, 1e-12));
      expect(
        a.airtimeShare,
        closeTo(kSlowFactor / (n + kSlowFactor - 1), 1e-12),
      );
      for (final OneTalkerClient k in s.clients.skip(1)) {
        expect(k.slow, isFalse);
        expect(k.airtimeShare, closeTo(1 / (n + kSlowFactor - 1), 1e-12));
      }
    }
    // The lesson's worked number: 4 devices, A slow, 57%.
    final OneTalkerClient a4 = oneTalker(
      OneTalkerConfig(clientsA: 4, slowTalker: true),
    ).clients.first;
    expect(sharePercent(a4.airtimeShare), '57%');
    // Alone, slow or not, a device has all the time.
    expect(
      oneTalker(
        OneTalkerConfig(clientsA: 1, slowTalker: true),
      ).clients.single.airtimeShare,
      1,
    );
  });

  test('a slow device on access point 1 slows only its own channel', () {
    final OneTalkerScene s = oneTalker(
      OneTalkerConfig(
        clientsA: 4,
        clientsB: 3,
        secondAp: SecondAp.otherChannel,
        slowTalker: true,
      ),
    );
    for (final OneTalkerClient k in s.channels[1].clients) {
      expect(k.airtimeShare, closeTo(1 / 3, 1e-12));
    }
  });

  test('counts clamp to 1..12 and 1..6', () {
    expect(OneTalkerConfig(clientsA: 0).clientsA, 1);
    expect(OneTalkerConfig(clientsA: 40).clientsA, kMaxClientsA);
    expect(OneTalkerConfig(clientsB: -3).clientsB, 1);
    expect(OneTalkerConfig(clientsB: 9).clientsB, kMaxClientsB);
  });

  test('letters run A on across both access points', () {
    final OneTalkerScene s = oneTalker(
      OneTalkerConfig(
        clientsA: 12,
        clientsB: 6,
        secondAp: SecondAp.sameChannel,
      ),
    );
    expect(
      s.clients.map((OneTalkerClient k) => k.letter).join(),
      'ABCDEFGHIJKLMNOPQR',
    );
    expect(s.clients.where((OneTalkerClient k) => k.ap == 2).first.letter, 'M');
  });

  test('one talker per channel at every turn; two only on two channels', () {
    for (final SecondAp ap in SecondAp.values) {
      final OneTalkerScene s = oneTalker(
        OneTalkerConfig(clientsA: 4, clientsB: 3, secondAp: ap),
      );
      for (int turn = 0; turn < 30; turn++) {
        final List<OneTalkerClient> now = s.talkingAt(turn);
        expect(now, hasLength(s.channels.length));
        expect(
          now.map((OneTalkerClient k) => k.channel).toSet(),
          hasLength(now.length),
          reason: 'never two talkers on one channel',
        );
      }
    }
    // Same channel: the turn goes round all 7 devices, one at a time.
    final OneTalkerChannel same = oneTalker(
      OneTalkerConfig(clientsA: 4, clientsB: 3, secondAp: SecondAp.sameChannel),
    ).channels.single;
    expect(
      <String>[for (int t = 0; t < 8; t++) same.talkingAt(t).letter].join(),
      'ABCDEFGA',
    );
  });

  test('percent and fraction words', () {
    expect(sharePercent(1 / 4), '25%');
    expect(sharePercent(1 / 3), '33%');
    expect(sharePercent(1 / 12), '8%');
    expect(shareFraction(7), '1/7');
  });
}
