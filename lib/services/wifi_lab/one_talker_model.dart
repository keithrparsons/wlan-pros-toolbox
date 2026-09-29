// One Talker per Channel: the sharing model behind the Wi-Fi Classroom Guided
// Lesson `one-talker`. Pure Dart, deterministic, no Flutter imports.
//
// CLEAN ROOM. Built from IEEE Std 802.11-2024 only (Keith's copy, read
// 2026-09-29; printed page numbers):
//  - 10.2.2 DCF (p. 1875): a STA senses the medium before it transmits and,
//    if the medium is busy, defers until the end of the current
//    transmission. On one channel, one talker at a time.
//  - 10.2.3.2 EDCA (p. 1876): each access category runs "an enhanced
//    variant of the DCF", so the rule holds for current devices too.
//  - 10.3.2.1 CS mechanism (p. 1885): physical and virtual carrier sense
//    decide busy or idle.
// Spec: myPKA Deliverables/2026-09-25-wifi-lab-cleanroom/specs/
// 48-one-talker.md. No outside lab's wording or layout is used.
//
// TEACHING APPROXIMATION (the one channel_planner_model.dart:32-33 already
// states): every device always has something to send, turns are shared
// evenly, nothing collides, and a different channel does not leak into this
// one. So each device's share of turns is 1 / (devices on its channel).
//
// SLOW TALKER (illustrative): device A on access point 1 can be made
// kSlowFactor times slower per turn. Turns stay even, so its share of the
// TIME is kSlowFactor / (N - 1 + kSlowFactor). That is plain-DCF packet
// fairness, which the airtime-fairness tool models in full.
//
// ASCII only, no em dashes (GL-004).

/// Where the second access point is, if there is one.
enum SecondAp { none, sameChannel, otherChannel }

/// How many times longer the slow device's turn takes. Illustrative.
const int kSlowFactor = 4;

/// Device-count bounds. Access point 2 stops at 6 so the 18 devices keep 18
/// distinct looks in the Classroom client palette.
const int kMinClients = 1;
const int kMaxClientsA = 12;
const int kMaxClientsB = 6;

/// The opening scene.
const int kDefaultClientsA = 4;
const int kDefaultClientsB = 3;

/// Channel numbers shown on screen (5 GHz, 20 MHz, far apart).
const int kChannelA = 36;
const int kChannelOther = 149;

/// The lesson's inputs. Immutable; counts are clamped on construction.
class OneTalkerConfig {
  OneTalkerConfig({
    int clientsA = kDefaultClientsA,
    this.secondAp = SecondAp.none,
    int clientsB = kDefaultClientsB,
    this.slowTalker = false,
  }) : clientsA = clientsA.clamp(kMinClients, kMaxClientsA),
       clientsB = clientsB.clamp(kMinClients, kMaxClientsB);

  final int clientsA;
  final SecondAp secondAp;
  final int clientsB;
  final bool slowTalker;

  bool get hasSecondAp => secondAp != SecondAp.none;

  OneTalkerConfig copyWith({
    int? clientsA,
    SecondAp? secondAp,
    int? clientsB,
    bool? slowTalker,
  }) => OneTalkerConfig(
    clientsA: clientsA ?? this.clientsA,
    secondAp: secondAp ?? this.secondAp,
    clientsB: clientsB ?? this.clientsB,
    slowTalker: slowTalker ?? this.slowTalker,
  );
}

/// One device.
class OneTalkerClient {
  const OneTalkerClient({
    required this.index,
    required this.ap,
    required this.channel,
    required this.slow,
    required this.turnShare,
    required this.airtimeShare,
  });

  /// 0-based across both access points: the letter and the palette slot.
  final int index;

  /// 1 or 2.
  final int ap;
  final int channel;
  final bool slow;

  /// Share of the turns on its channel: 1 / talkers.
  final double turnShare;

  /// Share of the time on its channel (equals [turnShare] unless a slow
  /// device shares the channel).
  final double airtimeShare;

  String get letter => String.fromCharCode(0x41 + index);
}

/// One channel and the devices taking turns on it.
class OneTalkerChannel {
  const OneTalkerChannel({
    required this.number,
    required this.aps,
    required this.clients,
  });

  final int number;

  /// The access points on this channel (1, 2 or both).
  final List<int> aps;
  final List<OneTalkerClient> clients;

  int get talkers => clients.length;

  /// The device transmitting at [turn]: round robin, one per channel.
  OneTalkerClient talkingAt(int turn) => clients[turn % clients.length];
}

/// The whole scene: channels in order (access point 1's first).
class OneTalkerScene {
  const OneTalkerScene(this.config, this.channels);

  final OneTalkerConfig config;
  final List<OneTalkerChannel> channels;

  List<OneTalkerClient> get clients =>
      <OneTalkerClient>[for (final OneTalkerChannel c in channels) ...c.clients]
        ..sort((OneTalkerClient a, OneTalkerClient b) => a.index - b.index);

  /// Everyone transmitting at [turn]: one per channel.
  List<OneTalkerClient> talkingAt(int turn) => <OneTalkerClient>[
    for (final OneTalkerChannel c in channels) c.talkingAt(turn),
  ];
}

/// Builds the scene for [config].
OneTalkerScene oneTalker(OneTalkerConfig config) {
  final int channelB = config.secondAp == SecondAp.otherChannel
      ? kChannelOther
      : kChannelA;
  // (index, ap, channel, slow) for every device.
  final List<(int, int, int, bool)> raw = <(int, int, int, bool)>[
    for (int i = 0; i < config.clientsA; i++)
      (i, 1, kChannelA, config.slowTalker && i == 0),
    if (config.hasSecondAp)
      for (int j = 0; j < config.clientsB; j++)
        (config.clientsA + j, 2, channelB, false),
  ];
  final List<int> numbers = <int>[
    kChannelA,
    if (config.secondAp == SecondAp.otherChannel) kChannelOther,
  ];
  final List<OneTalkerChannel> channels = <OneTalkerChannel>[];
  for (final int ch in numbers) {
    final List<(int, int, int, bool)> on = raw
        .where(((int, int, int, bool) d) => d.$3 == ch)
        .toList();
    final double weightSum = on.fold<double>(
      0,
      (double s, (int, int, int, bool) d) => s + (d.$4 ? kSlowFactor : 1),
    );
    channels.add(
      OneTalkerChannel(
        number: ch,
        aps: <int>{for (final (int, int, int, bool) d in on) d.$2}.toList()
          ..sort(),
        clients: <OneTalkerClient>[
          for (final (int i, int ap, int c, bool slow) in on)
            OneTalkerClient(
              index: i,
              ap: ap,
              channel: c,
              slow: slow,
              turnShare: 1 / on.length,
              airtimeShare: (slow ? kSlowFactor : 1) / weightSum,
            ),
        ],
      ),
    );
  }
  return OneTalkerScene(config, channels);
}

/// A share as a whole percent ("25%", "8%").
String sharePercent(double share) => '${(share * 100).round()}%';

/// An even share as a fraction ("1/4").
String shareFraction(int talkers) => '1/$talkers';
