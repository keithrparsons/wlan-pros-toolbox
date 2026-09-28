// Voice Priority, End to End: Wi-Fi Classroom model (voice-priority).
//
// One voice packet travels toward a phone on Wi-Fi: from the caller's app,
// through a tunnel gateway, across the internet and your provider, through
// the home router and switch, to the AP, over the air, to the phone. The
// caller's app marks it EF (Expedited Forwarding, DSCP 46). The lesson: the
// call gets the Voice queue on Wi-Fi only if that marking survives every hop
// before the AP, and the AP maps it to the right user priority. Lose it
// anywhere and the packet waits in Best Effort, behind the download.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 3
// and the section 5 anti-patterns. Sources, read for this build:
//   - RFC 8325 (Mapping Diffserv to IEEE 802.11), section 2.3: the common
//     "default DSCP-to-UP mapping" copies the three most significant bits of
//     the DSCP, so EF (101110) lands on UP 5, AC_VI, "rather than the Voice
//     Access Category (AC_VO), for which it is intended". Section 4.2.1: "a
//     non-default DSCP-to-UP mapping is RECOMMENDED, such that EF DSCP is
//     mapped to UP 6". Section 8.1: untrusted markings are "bleached (i.e.,
//     re-marked to DSCP DF and/or UP 0)".
//   - RFC 4301 (IPsec architecture), section 5.1.2.1 and the SPD entry
//     "Bypass DSCP (T/F) or map to unprotected DSCP values": whether a tunnel
//     copies the inner DSCP to the outer header is configuration. The UI says
//     "depends on the device".
//   - RFC 2475 (Differentiated Services architecture): a traffic conditioner
//     at a domain boundary "may re-mark" packets. Your provider's network is
//     a domain you do not run.
//   - UP to access category (UP 1 and 2 BK, 0 and 3 BE, 4 and 5 VI, 6 and 7
//     VO), as the DSCP / QoS Markings card states it.
//
// NOT REBUILT: EDCA. The Wi-Fi hop's wait comes from the Medium Access
// Simulator's own engine (medium_access_engine.dart), unchanged: the same
// clause 10 contention rules, clause 17 OFDM timing and default station EDCA
// parameters, with a voice flow and a saturated best-effort download sharing
// one channel. Its simplifications carry over and are stated in the help:
// legacy 54 Mbps timing, one frame size for every frame, and the download
// and the voice flow contending as two transmitters (inside one AP the
// standard resolves an internal collision in the higher category's favor).
//
// ILLUSTRATIVE, labeled so on screen and in the help: a voice packet every
// 20 ms; the number of download frames already waiting in the best-effort
// queue (the AP's buffer depth is not published and varies); 1,500-byte
// frames at 54 Mbps (the Medium Access Simulator's defaults). Wired hops add
// delay too; the tool does not invent a figure for them.
//
// Pure Dart, deterministic (seeded runs, cached). ASCII only (GL-004).

import 'medium_access_engine.dart';

export 'medium_access_engine.dart' show AccessCategory;

const String kVoicePriorityToolId = 'voice-priority';

/// DSCP EF (Expedited Forwarding, RFC 3246), what a call app marks voice.
const int kDscpEf = 46;

/// DSCP DF / CS0 (default forwarding): no priority asked for.
const int kDscpDefault = 0;

/// Where the voice marking is lost, in the order the control offers.
enum MarkLoss {
  nowhere('Nowhere', 'Nowhere'),
  apMapping('At the AP mapping', 'AP'),
  tunnel('At the tunnel', 'Tunnel'),
  isp('At the internet provider', 'Provider');

  const MarkLoss(this.label, this.short);

  final String label;

  /// For the segmented control.
  final String short;
}

/// How the AP turns a packet's DSCP into an 802.11 user priority (UP).
enum ApMapping {
  rfc8325('RFC 8325 table (recommended)', 'RFC 8325'),
  topThreeBits('Top three bits (older default)', 'top three bits');

  const ApMapping(this.label, this.short);

  final String label;
  final String short;
}

/// 802.11 user priority for [dscp] under [mapping]. Only the two markings
/// this tool uses are accepted: EF (46) and default (0).
int upForDscp(int dscp, ApMapping mapping) {
  if (dscp != kDscpEf && dscp != kDscpDefault) {
    throw ArgumentError.value(dscp, 'dscp', 'this tool uses only 46 and 0');
  }
  switch (mapping) {
    case ApMapping.rfc8325:
      // RFC 8325 section 4.2.1: EF to UP 6; DF to UP 0.
      return dscp == kDscpEf ? 6 : 0;
    case ApMapping.topThreeBits:
      // RFC 8325 section 2.3: the three most significant bits. 101110 -> 5.
      return dscp >> 3;
  }
}

/// The WMM access category for 802.11 user priority [up] (0 to 7).
AccessCategory accessCategoryForUp(int up) {
  if (up < 0 || up > 7) throw ArgumentError.value(up, 'up', '0 to 7');
  switch (up) {
    case 1:
    case 2:
      return AccessCategory.background;
    case 4:
    case 5:
      return AccessCategory.video;
    case 6:
    case 7:
      return AccessCategory.voice;
    default:
      return AccessCategory.bestEffort;
  }
}

/// The user priorities an access category holds, for labels ("UP 6 and 7").
String upsLabel(AccessCategory ac) => switch (ac) {
  AccessCategory.voice => 'UP 6 and 7',
  AccessCategory.video => 'UP 4 and 5',
  AccessCategory.bestEffort => 'UP 0 and 3',
  AccessCategory.background => 'UP 1 and 2',
};

/// "AC_VO" and so on.
String acCode(AccessCategory ac) => 'AC_${ac.shortLabel}';

/// A DSCP value in words, for labels: "EF (46)" or "0 (default)".
String dscpLabel(int dscp) => dscp == kDscpEf ? 'EF (46)' : '0 (default)';

/// The same, short enough for a narrow hop tile: "EF 46" or "0".
String dscpShort(int dscp) => dscp == kDscpEf ? 'EF 46' : '0';

/// The hops, in the order the packet travels them.
enum VpHopId {
  caller('Caller\'s app'),
  tunnel('Tunnel gateway'),
  internet('Internet and your provider'),
  home('Home router and switch'),
  ap('Access point (AP)'),
  air('The air'),
  phone('Phone');

  const VpHopId(this.label);

  final String label;
}

/// What one hop does to the packet.
class VpHop {
  const VpHop({
    required this.id,
    required this.dscpOut,
    required this.note,
    required this.lostHere,
  });

  final VpHopId id;

  /// The DSCP the next hop can see as the packet leaves this one. For the AP,
  /// the air and the phone it is the DSCP carried, unchanged.
  final int dscpOut;

  /// One sentence: what this hop did.
  final String note;

  /// True at the one hop where the marking was lost.
  final bool lostHere;
}

/// One run of the Wi-Fi hop, from the Medium Access Simulator's engine.
class VpAirStat {
  const VpAirStat({required this.meanAccessUs, required this.frames});

  /// Mean time from the head of its queue to the ACK, us.
  final double meanAccessUs;

  /// Voice frames the mean is over.
  final int frames;
}

/// Everything the user sets.
class VpConfig {
  const VpConfig({
    this.loss = MarkLoss.nowhere,
    this.mapping = ApMapping.rfc8325,
    this.downloadRunning = true,
    this.framesAhead = kVpDefaultFramesAhead,
  });

  final MarkLoss loss;
  final ApMapping mapping;
  final bool downloadRunning;

  /// Download frames already waiting in the best-effort queue (illustrative).
  final int framesAhead;

  VpConfig copyWith({
    MarkLoss? loss,
    ApMapping? mapping,
    bool? downloadRunning,
    int? framesAhead,
  }) => VpConfig(
    loss: loss ?? this.loss,
    mapping: mapping ?? this.mapping,
    downloadRunning: downloadRunning ?? this.downloadRunning,
    framesAhead: (framesAhead ?? this.framesAhead).clamp(
      kVpMinFramesAhead,
      kVpMaxFramesAhead,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is VpConfig &&
      other.loss == loss &&
      other.mapping == mapping &&
      other.downloadRunning == downloadRunning &&
      other.framesAhead == framesAhead;

  @override
  int get hashCode => Object.hash(loss, mapping, downloadRunning, framesAhead);
}

/// Illustrative: download frames waiting ahead in the best-effort queue.
const int kVpDefaultFramesAhead = 64;
const int kVpMinFramesAhead = 0;
const int kVpMaxFramesAhead = 256;

/// Illustrative: one voice packet every 20 ms.
const double kVpVoicePacketsPerSecond = 50;

/// Every frame on the air, as in the Medium Access Simulator's defaults.
const int kVpFrameBytes = 1500;
const int kVpPhyRateMbps = 54;

/// Simulated air time per engine run, us (100 voice packets at 50 per s).
const int kVpRunUs = 2000000;

/// The queues the comparison shows, top to bottom.
const List<AccessCategory> kVpComparedQueues = <AccessCategory>[
  AccessCategory.voice,
  AccessCategory.video,
  AccessCategory.bestEffort,
];

/// The Wi-Fi hop, computed with the Medium Access Simulator's engine.
///
/// Seven seeded engine runs take about a second, too long for the UI thread,
/// so the screen reads [VpAirTable], which holds these runs' output. A unit
/// test reruns the engine through this class and requires the table to
/// match, so the table cannot drift from the engine.
class VpAirEngine {
  VpAirEngine._();

  /// A voice flow in [ac], alone or beside a saturated best-effort download,
  /// each in its own queue. Seeded, so the same answer every time.
  static VpAirStat voiceAccess(AccessCategory ac, {required bool download}) {
    final MediumAccessEngine e = MediumAccessEngine(
      MediumAccessConfig(
        stations: <StationConfig>[
          StationConfig(
            accessCategory: ac,
            framesPerSecond: kVpVoicePacketsPerSecond,
          ),
          if (download)
            const StationConfig(accessCategory: AccessCategory.bestEffort),
        ],
        frameBytes: kVpFrameBytes,
        phyRateMbps: kVpPhyRateMbps,
        seed: kVpSeed,
      ),
      retentionUs: 0,
    );
    _run(e);
    final AccessDelayStat? s = e.stats.accessDelay[ac];
    return VpAirStat(meanAccessUs: s?.meanUs ?? 0, frames: s?.frames ?? 0);
  }

  /// Mean time per frame for a best-effort queue that always has a frame,
  /// alone on the channel, us: the pace at which the frames ahead of the
  /// call leave the queue.
  static double bestEffortServiceUs() {
    final MediumAccessEngine e = MediumAccessEngine(
      const MediumAccessConfig(
        stations: <StationConfig>[
          StationConfig(accessCategory: AccessCategory.bestEffort),
        ],
        frameBytes: kVpFrameBytes,
        phyRateMbps: kVpPhyRateMbps,
        seed: kVpSeed,
      ),
      retentionUs: 0,
    );
    _run(e);
    final MediumAccessStats s = e.stats;
    return s.delivered == 0 ? 0 : s.elapsedUs / s.delivered;
  }

  /// Runs [e] for [kVpRunUs] in chunks, so the engine prunes as it goes.
  static void _run(MediumAccessEngine e) {
    const int total = kVpRunUs ~/ OfdmTiming.slotUs;
    const int chunk = 5000;
    for (int done = 0; done < total; done += chunk) {
      e.advanceSlots(done + chunk > total ? total - done : chunk);
    }
  }
}

/// Seed for every engine run.
const int kVpSeed = 7;

/// [VpAirEngine]'s output for the configurations the screen shows, us.
/// Regenerate by running the engine (the model test prints and checks it).
class VpAirTable {
  VpAirTable._();

  /// Mean voice access delay, keyed by (queue, download running).
  static const Map<(AccessCategory, bool), double> voiceAccessUs =
      <(AccessCategory, bool), double>{
        (AccessCategory.voice, false): 299.85087719298247,
        (AccessCategory.video, false): 315.4035087719298,
        (AccessCategory.bestEffort, false): 356.37719298245617,
        (AccessCategory.voice, true): 478.2696629213483,
        (AccessCategory.video, true): 586.5046728971963,
      };

  /// [VpAirEngine.bestEffortServiceUs].
  static const double bestEffortServiceUs = 398.247311827957;
}

/// The call's wait on the Wi-Fi hop if it lands in [ac], us.
///
/// Voice and Video: their own queue, so the wait is the engine's access delay
/// beside the download (or alone). Best effort: the same queue as the
/// download, so the call first waits for the [framesAhead] frames in front
/// of it to leave, one service time each, and then for its own access.
double vpWaitUs(AccessCategory ac, VpConfig c) {
  if (ac != AccessCategory.bestEffort || !c.downloadRunning) {
    final double? v = VpAirTable.voiceAccessUs[(ac, c.downloadRunning)];
    if (v == null) throw ArgumentError.value(ac, 'ac', 'not in the table');
    return v;
  }
  const double service = VpAirTable.bestEffortServiceUs;
  return c.framesAhead * service + service;
}

/// The whole trip for one configuration.
class VpTrip {
  VpTrip(this.config) : hops = _hops(config);

  final VpConfig config;
  final List<VpHop> hops;

  /// The DSCP the AP sees.
  int get dscpAtAp => hops[VpHopId.home.index].dscpOut;

  /// The user priority the AP gives the frame.
  int get up => config.loss == MarkLoss.apMapping
      ? 0
      : upForDscp(dscpAtAp, config.mapping);

  /// The queue the call lands in on the air.
  AccessCategory get queue => accessCategoryForUp(up);

  /// True when the call gets the Voice queue.
  bool get inVoiceQueue => queue == AccessCategory.voice;

  /// The call's wait on the Wi-Fi hop, us.
  double get waitUs => vpWaitUs(queue, config);

  /// The wait it would have in each compared queue, us.
  Map<AccessCategory, double> get waitsByQueue => <AccessCategory, double>{
    for (final AccessCategory ac in kVpComparedQueues) ac: vpWaitUs(ac, config),
  };

  /// True when the frames-ahead setting changes anything.
  bool get framesAheadMatters =>
      config.downloadRunning && queue == AccessCategory.bestEffort;

  /// One sentence on why the call is in [queue].
  String get why {
    switch (config.loss) {
      case MarkLoss.tunnel:
        return 'The tunnel gateway did not copy EF to the outer header, so '
            'every hop after it saw 0 and the AP gave the call UP 0: '
            'Best effort.';
      case MarkLoss.isp:
        return 'The internet provider reset the marking to 0, so the AP saw '
            '0 and gave the call UP 0: Best effort.';
      case MarkLoss.apMapping:
        return 'The marking arrived as EF, but the AP ignores DSCP and sends '
            'everything as UP 0: Best effort.';
      case MarkLoss.nowhere:
        return config.mapping == ApMapping.rfc8325
            ? 'EF survived every hop and the AP mapped it to UP 6 (RFC 8325): '
                  'Voice.'
            : 'EF survived every hop, but the top three bits of 46 (101110) '
                  'are 5, so the AP gave the call UP 5: Video, not Voice.';
    }
  }

  static List<VpHop> _hops(VpConfig c) {
    int dscp = kDscpEf;
    final List<VpHop> out = <VpHop>[
      const VpHop(
        id: VpHopId.caller,
        dscpOut: kDscpEf,
        note: 'Marks the voice packet EF (46).',
        lostHere: false,
      ),
    ];
    final bool tunnelLoses = c.loss == MarkLoss.tunnel;
    if (tunnelLoses) dscp = kDscpDefault;
    out.add(
      VpHop(
        id: VpHopId.tunnel,
        dscpOut: dscp,
        note: tunnelLoses
            ? 'Wraps the packet and leaves the outer marking at 0. EF is '
                  'still inside, where no hop can see it.'
            : 'Wraps the packet and copies EF to the outer header. Whether '
                  'it does depends on the device.',
        lostHere: tunnelLoses,
      ),
    );
    final bool ispLoses = c.loss == MarkLoss.isp;
    if (ispLoses) dscp = kDscpDefault;
    out.add(
      VpHop(
        id: VpHopId.internet,
        dscpOut: dscp,
        note: ispLoses
            ? 'Resets the marking to 0. A network you do not run may re-mark '
                  'or ignore it.'
            : dscp == kDscpEf
            ? 'Passes EF through unchanged.'
            : 'Passes the packet through; the marking is already 0.',
        lostHere: ispLoses,
      ),
    );
    out.add(
      VpHop(
        id: VpHopId.home,
        dscpOut: dscp,
        note: 'Passes the marking through unchanged.',
        lostHere: false,
      ),
    );
    final bool apLoses = c.loss == MarkLoss.apMapping;
    final int up = apLoses ? 0 : upForDscp(dscp, c.mapping);
    final AccessCategory ac = accessCategoryForUp(up);
    out.add(
      VpHop(
        id: VpHopId.ap,
        dscpOut: dscp,
        note: apLoses
            ? 'Ignores the DSCP and sends the frame as UP 0.'
            : 'Maps ${dscpLabel(dscp)} to UP $up with the '
                  '${c.mapping.short} mapping.',
        lostHere: apLoses,
      ),
    );
    out.add(
      VpHop(
        id: VpHopId.air,
        dscpOut: dscp,
        note: 'Waits in the ${ac.label} queue (${acCode(ac)}).',
        lostHere: false,
      ),
    );
    out.add(
      VpHop(
        id: VpHopId.phone,
        dscpOut: dscp,
        note: 'Plays the voice.',
        lostHere: false,
      ),
    );
    return out;
  }
}

/// Formats a wait in us as "0.29 ms" or "25.1 ms".
String vpMs(double us) {
  final double ms = us / 1000;
  if (ms < 10) return '${ms.toStringAsFixed(2)} ms';
  if (ms < 100) return '${ms.toStringAsFixed(1)} ms';
  return '${ms.toStringAsFixed(0)} ms';
}
