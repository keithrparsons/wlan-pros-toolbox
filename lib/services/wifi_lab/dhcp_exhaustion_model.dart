// Conference Wi-Fi Runs Out of Addresses: Wi-Fi Classroom model
// (dhcp-exhaustion).
//
// A conference morning, 07:00 to 13:00, minute by minute. People arrive
// (a registration rush, then a trickle), each brings devices onto the Wi-Fi,
// stays a while and leaves. Every device asks the DHCP (Dynamic Host
// Configuration Protocol) server for an address. The lesson (research brief
// candidate 9): the pool has to cover everyone who arrived within one lease
// time, not just everyone in the room, because a device that walks out
// sends nothing and its address stays taken until the lease runs out. With
// a long lease the pool runs dry mid-morning while the hall is half empty;
// with a short one it holds. Devices that rotate their private address come
// back looking like new devices and take a second address.
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 9
// and section 5. Lease mechanics from RFC 2131, read for this build:
//   - section 3.3: a lease is "a fixed period of time"; section 4.4.5: the
//     client renews at T1, before the lease runs out, so a device that stays
//     keeps its address.
//   - section 3.1: the server keys a lease by the 'client identifier'
//     or 'chaddr' (the hardware address), so a device with a new address is
//     a new client to the server.
//   - section 3.2: a client "will not normally relinquish its lease during
//     a graceful shutdown"; only DHCPRELEASE frees an address early. A device
//     that walks out of range sends nothing, so its address stays bound
//     until the lease expires.
// Renewal is modeled at T1 = half the lease (RFC 2131 section 4.4.5: "T1
// defaults to (0.5 * duration_of_lease)"); after a device leaves, its address is free at its last
// renewal plus one lease.
//
// ILLUSTRATIVE, labeled on screen and in help: the crowd (people, devices
// each, average stay), the arrival shape, the addresses reserved, and every
// private-address rotation number. No platform publishes how often it
// rotates (research brief guard on candidates 7 and 9), so the share of
// devices that rotate and how often a rotating device comes back as new are
// ASSUMPTIONS the user sets.
//
// Deterministic: arrivals, stays and rotation follow fixed low-discrepancy
// sequences, no random draws. Pure Dart. ASCII only (GL-004).

import 'dart:math' as math;
import 'dart:typed_data';

const String kDhcpExhaustionToolId = 'dhcp-exhaustion';

/// The morning: 07:00 to 13:00.
const int kDxStartMinute = 7 * 60;
const int kDxMinutes = 6 * 60;

/// Lease choices, minutes, shortest first.
const List<int> kDxLeaseChoices = <int>[
  5,
  10,
  15,
  30,
  60,
  120,
  240,
  480,
  720,
  1440,
  4320,
  11520,
];

/// Subnet prefix lengths offered for the pool.
const List<int> kDxPrefixChoices = <int>[24, 23, 22, 21, 20, 19];

/// Share of the morning's arrivals in each half hour from 07:00
/// (illustrative: a registration rush before a 09:00 keynote, then a
/// trickle). Sums to 100.
const List<int> kDxArrivalShape = <int>[4, 8, 14, 16, 10, 8, 8, 8, 7, 6, 6, 5];

/// "1 day", "30 min", "8 days".
String dxLeaseLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes < 1440) {
    final int h = minutes ~/ 60;
    return h == 1 ? '1 hour' : '$h hours';
  }
  final int d = minutes ~/ 1440;
  return d == 1 ? '1 day' : '$d days';
}

/// "09:12" for a minute of the morning (0 = 07:00).
String dxClock(int minuteOfMorning) {
  final int m = kDxStartMinute + minuteOfMorning;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// Everything the user sets.
class DxConfig {
  const DxConfig({
    this.leaseMinutes = 1440,
    this.prefix = 24,
    this.reserved = 10,
    this.people = 250,
    this.devicesPerPerson = 1.5,
    this.stayMinutes = 90,
    this.rotation = false,
    this.rotatingShare = 0.5,
    this.rotationMinutes = 60,
  });

  final int leaseMinutes;

  /// Subnet prefix length; the pool is the usable hosts minus [reserved].
  final int prefix;

  /// Addresses kept out of the pool: the gateway, servers, printers,
  /// infrastructure (illustrative).
  final int reserved;

  /// People arriving over the morning (illustrative).
  final int people;

  /// Devices each person brings onto the Wi-Fi (illustrative).
  final double devicesPerPerson;

  /// Average time a person stays, minutes (illustrative). Individual stays
  /// run from half to one and a half times this.
  final int stayMinutes;

  /// Devices rotate their private address on this open network.
  final bool rotation;

  /// Share of devices that rotate, 0 to 1 (assumption).
  final double rotatingShare;

  /// How often a rotating device comes back with a new address, minutes
  /// (assumption; no platform publishes this).
  final int rotationMinutes;

  /// Usable host addresses in the subnet: 2^(32 - prefix) - 2.
  int get usableHosts => (1 << (32 - prefix)) - 2;

  /// Addresses the DHCP server can hand out.
  int get poolSize => math.max(0, usableHosts - reserved);

  /// Devices over the whole morning.
  int get devices => (people * devicesPerPerson).round();

  DxConfig copyWith({
    int? leaseMinutes,
    int? prefix,
    int? reserved,
    int? people,
    double? devicesPerPerson,
    int? stayMinutes,
    bool? rotation,
    double? rotatingShare,
    int? rotationMinutes,
  }) => DxConfig(
    leaseMinutes: leaseMinutes ?? this.leaseMinutes,
    prefix: prefix ?? this.prefix,
    reserved: (reserved ?? this.reserved).clamp(0, kDxMaxReserved),
    people: (people ?? this.people).clamp(kDxMinPeople, kDxMaxPeople),
    devicesPerPerson: (devicesPerPerson ?? this.devicesPerPerson).clamp(
      1.0,
      3.0,
    ),
    stayMinutes: (stayMinutes ?? this.stayMinutes).clamp(15, kDxMinutes),
    rotation: rotation ?? this.rotation,
    rotatingShare: (rotatingShare ?? this.rotatingShare).clamp(0.0, 1.0),
    rotationMinutes: (rotationMinutes ?? this.rotationMinutes).clamp(
      kDxMinRotation,
      kDxMaxRotation,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is DxConfig &&
      other.leaseMinutes == leaseMinutes &&
      other.prefix == prefix &&
      other.reserved == reserved &&
      other.people == people &&
      other.devicesPerPerson == devicesPerPerson &&
      other.stayMinutes == stayMinutes &&
      other.rotation == rotation &&
      other.rotatingShare == rotatingShare &&
      other.rotationMinutes == rotationMinutes;

  @override
  int get hashCode => Object.hash(
    leaseMinutes,
    prefix,
    reserved,
    people,
    devicesPerPerson,
    stayMinutes,
    rotation,
    rotatingShare,
    rotationMinutes,
  );
}

const int kDxMaxReserved = 100;
const int kDxMinPeople = 50;
const int kDxMaxPeople = 5000;
const int kDxMinRotation = 15;
const int kDxMaxRotation = 240;

/// What one address in the pool is doing at a moment.
enum DxCell {
  free,

  /// Bound to a device that is in the hall.
  inUse,

  /// Bound to a device that has left; free when its lease runs out.
  heldLeft,

  /// Bound to an address a device in the hall stopped using when it
  /// rotated; free when its lease runs out.
  heldRotated,
}

/// One minute of the morning.
class DxMinute {
  const DxMinute({
    required this.inUse,
    required this.heldLeft,
    required this.heldRotated,
    required this.devicesHere,
    required this.waiting,
  });

  /// Addresses bound to a device in the hall.
  final int inUse;

  /// Addresses still bound to devices that left.
  final int heldLeft;

  /// Addresses still bound to a device's earlier private address.
  final int heldRotated;

  /// Devices in the hall.
  final int devicesHere;

  /// Devices in the hall with no address: joined the Wi-Fi, no internet.
  final int waiting;

  /// Every address the server has handed out and not got back.
  int get bound => inUse + heldLeft + heldRotated;
}

/// One client identity: a device under one hardware address.
class _Identity {
  _Identity(this.device, this.start, this.end, this.deviceLeaves);

  final int device;
  final int start;
  final int end;

  /// The minute the device itself leaves (after [end] when it rotated).
  final int deviceLeaves;
  int cell = -1;
  int acquired = -1;
}

/// The whole morning for one configuration.
class DxMorning {
  DxMorning(this.config) {
    _run();
  }

  final DxConfig config;
  final List<DxMinute> minutes = <DxMinute>[];
  late final Uint8List _cells;
  int _uniqueIdentities = 0;

  int get poolSize => config.poolSize;

  /// Client identities the server saw: devices, plus each rotation.
  int get identities => _uniqueIdentities;

  /// The state of every pool address at [minute] (0 to [kDxMinutes]).
  List<DxCell> cellsAt(int minute) {
    final int m = minute.clamp(0, kDxMinutes);
    final int n = poolSize;
    return <DxCell>[
      for (int i = 0; i < n; i++) DxCell.values[_cells[m * n + i]],
    ];
  }

  /// The first minute a device in the hall could not get an address, or
  /// null when the pool held all morning.
  int? get firstDryMinute {
    for (int m = 0; m < minutes.length; m++) {
      if (minutes[m].waiting > 0) return m;
    }
    return null;
  }

  bool get held => firstDryMinute == null;

  int get peakBound => minutes.map((DxMinute m) => m.bound).reduce(math.max);
  int get peakHere =>
      minutes.map((DxMinute m) => m.devicesHere).reduce(math.max);
  int get peakWaiting =>
      minutes.map((DxMinute m) => m.waiting).reduce(math.max);

  /// Addresses the morning would have needed with no pool limit.
  int get peakDemand => _peakDemand;
  int _peakDemand = 0;

  // ── Simulation ──────────────────────────────────────────────────────────

  static double _frac(double x) => x - x.floorToDouble();

  /// The identities, in start order: arrivals by the morning's shape,
  /// stays spread from 0.5x to 1.5x the average, rotation as set.
  List<_Identity> _identities() {
    final DxConfig c = config;
    final int total = c.devices;
    final List<int> arrivals = <int>[];
    // Largest-remainder split of the devices over the half hours.
    final List<double> exact = <double>[
      for (final int w in kDxArrivalShape) total * w / 100,
    ];
    final List<int> counts = <int>[for (final double e in exact) e.floor()];
    int left = total - counts.fold(0, (int a, int b) => a + b);
    final List<int> order = List<int>.generate(
      exact.length,
      (int i) => i,
    )..sort((int a, int b) => (_frac(exact[b]) - _frac(exact[a])).sign.toInt());
    for (int k = 0; left > 0; k++, left--) {
      counts[order[k % order.length]]++;
    }
    for (int s = 0; s < counts.length; s++) {
      final int n = counts[s];
      for (int i = 0; i < n; i++) {
        arrivals.add(s * 30 + ((i + 0.5) * 30 / n).floor());
      }
    }
    final List<_Identity> out = <_Identity>[];
    for (int d = 0; d < arrivals.length; d++) {
      final int a = arrivals[d];
      final double f = 0.5 + _frac(d * 0.6180339887);
      final int leave = a + math.max(1, (c.stayMinutes * f).round());
      final bool rotates =
          c.rotation && _frac(d * 0.7548776662) < c.rotatingShare;
      if (!rotates) {
        out.add(_Identity(d, a, leave, leave));
        continue;
      }
      // The first rotation lands somewhere in the first interval, so the
      // hall's devices do not all rotate together.
      int s = a;
      int next =
          a +
          math.max(
            1,
            (c.rotationMinutes * (0.25 + 0.75 * _frac(d * 0.5698402910)))
                .round(),
          );
      while (next < leave) {
        out.add(_Identity(d, s, next, leave));
        s = next;
        next += c.rotationMinutes;
      }
      out.add(_Identity(d, s, leave, leave));
    }
    out.sort((_Identity x, _Identity y) => x.start.compareTo(y.start));
    return out;
  }

  /// When an identity that ends at [end] frees its address: its last
  /// renewal (every half lease from [acquired]) plus one lease.
  static int freeAt(int acquired, int end, int lease) {
    final double half = lease / 2;
    final int renewals = ((end - acquired) / half).floor();
    return (acquired + renewals * half + lease).ceil();
  }

  void _run() {
    final DxConfig c = config;
    final int n = c.poolSize;
    final int lease = c.leaseMinutes;
    final List<_Identity> ids = _identities();
    _uniqueIdentities = ids.length;
    _cells = Uint8List((kDxMinutes + 1) * n);
    final Uint8List cell = Uint8List(n);
    // Lowest free address first.
    final List<int> freeList = List<int>.generate(n, (int i) => n - 1 - i);
    // Waiting identities, first come first served; [head] is the front.
    final List<_Identity> waiting = <_Identity>[];
    int head = 0;
    // Devices in the hall per minute, from arrivals and departures.
    final Int32List hereDelta = Int32List(kDxMinutes + 2);
    final Set<int> seen = <int>{};
    for (final _Identity id in ids) {
      if (seen.add(id.device)) {
        hereDelta[id.start.clamp(0, kDxMinutes + 1)]++;
        hereDelta[id.deviceLeaves.clamp(0, kDxMinutes + 1)]--;
      }
    }
    int hereNow = 0;
    int waitingNow = 0;
    final List<_Identity> active = <_Identity>[];
    // Ended identities still holding an address: (freeAt, cell).
    final List<(int, int)> held = <(int, int)>[];
    int next = 0;
    // Addresses per state, kept as the cells change.
    final List<int> tally = List<int>.filled(DxCell.values.length, 0);
    int unlimitedBound = 0;
    final List<int> unlimitedFree = <int>[];

    for (int t = 0; t <= kDxMinutes; t++) {
      // 1. Leases that ran out.
      bool freed = false;
      held.removeWhere(((int, int) h) {
        if (h.$1 > t) return false;
        tally[cell[h.$2]]--;
        cell[h.$2] = DxCell.free.index;
        freeList.add(h.$2);
        freed = true;
        return true;
      });
      if (freed) freeList.sort((int a, int b) => b.compareTo(a));
      // 2. Identities that end now (left, or rotated away).
      active.removeWhere((_Identity id) {
        if (id.end > t) return false;
        if (id.cell >= 0) {
          tally[DxCell.inUse.index]--;
          cell[id.cell] = id.deviceLeaves > id.end
              ? DxCell.heldRotated.index
              : DxCell.heldLeft.index;
          tally[cell[id.cell]]++;
          held.add((freeAt(id.acquired, id.end, lease), id.cell));
        }
        return true;
      });
      // (identities that end while waiting drop out when they reach the
      // front, and are not counted below)
      // 3. New identities ask for an address.
      while (next < ids.length && ids[next].start <= t) {
        final _Identity id = ids[next++];
        if (id.end <= t) continue;
        active.add(id);
        waiting.add(id);
        unlimitedBound++;
        unlimitedFree.add(freeAt(t, id.end, lease));
      }
      unlimitedFree.removeWhere((int f) {
        if (f > t) return false;
        unlimitedBound--;
        return true;
      });
      if (unlimitedBound > _peakDemand) _peakDemand = unlimitedBound;
      // 4. The server hands out what it has, first come first served.
      while (head < waiting.length && freeList.isNotEmpty) {
        final _Identity id = waiting[head++];
        if (id.end <= t) continue;
        id.cell = freeList.removeLast();
        id.acquired = t;
        cell[id.cell] = DxCell.inUse.index;
        tally[DxCell.inUse.index]++;
      }
      // 5. Record.
      hereNow += hereDelta[t];
      waitingNow = 0;
      for (int k = head; k < waiting.length; k++) {
        if (waiting[k].end > t) waitingNow++;
      }
      minutes.add(
        DxMinute(
          inUse: tally[DxCell.inUse.index],
          heldLeft: tally[DxCell.heldLeft.index],
          heldRotated: tally[DxCell.heldRotated.index],
          devicesHere: hereNow,
          waiting: waitingNow,
        ),
      );
      _cells.setRange(t * n, (t + 1) * n, cell);
    }
  }

  /// One sentence on what happened.
  String get why {
    final int? dry = firstDryMinute;
    final String lease = dxLeaseLabel(config.leaseMinutes);
    if (dry == null) {
      return 'With a lease of $lease, addresses come back soon after people '
          'leave, so the $poolSize-address pool covers everyone who '
          'arrived within one lease time. Peak: $peakBound in use or held.';
    }
    final DxMinute m = minutes[dry];
    return 'At ${dxClock(dry)} every one of the $poolSize addresses was '
        'taken, but only ${m.devicesHere} devices were in the hall. '
        '${m.heldLeft + m.heldRotated} addresses were still held for '
        'devices that had left or changed address, and a lease of $lease '
        'keeps them held.';
  }
}
