// Teaching claims of the shared frame model behind Down the Stack
// (down-the-stack) and A Frame's Journey (frame-journey). Sources: Pax's
// brief, myPKA Deliverables/2026-09-27-classroom-interferer-and-ds-sources/
// RESEARCH-BRIEF.md Part 2.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/frame_journey_model.dart';

FjStep _airStep(List<FjStep> j) =>
    j.firstWhere((FjStep s) => s.medium == FjMedium.air);

List<FjStep> _wireSteps(List<FjStep> j) =>
    j.where((FjStep s) => s.medium == FjMedium.wire).toList();

List<AddressField> _wifi(FjStep s) => (s.link! as FjWifiLink).fields;
FjEthLink _eth(FjStep s) => s.link! as FjEthLink;

void main() {
  group('address fields by To DS / From DS (clause 9.3.2.1)', () {
    test('the roles in all four cases', () {
      expect(addressRoles(DsCase.none), <List<AddrRole>>[
        <AddrRole>[AddrRole.ra, AddrRole.da],
        <AddrRole>[AddrRole.ta, AddrRole.sa],
        <AddrRole>[AddrRole.bssid],
      ]);
      expect(addressRoles(DsCase.fromDs), <List<AddrRole>>[
        <AddrRole>[AddrRole.ra, AddrRole.da],
        <AddrRole>[AddrRole.ta, AddrRole.bssid],
        <AddrRole>[AddrRole.sa],
      ]);
      expect(addressRoles(DsCase.toDs), <List<AddrRole>>[
        <AddrRole>[AddrRole.ra, AddrRole.bssid],
        <AddrRole>[AddrRole.ta, AddrRole.sa],
        <AddrRole>[AddrRole.da],
      ]);
      expect(addressRoles(DsCase.both), <List<AddrRole>>[
        <AddrRole>[AddrRole.ra],
        <AddrRole>[AddrRole.ta],
        <AddrRole>[AddrRole.da],
        <AddrRole>[AddrRole.sa],
      ]);
    });

    test('Address 1 is always the receiver, Address 2 the transmitter', () {
      for (final DsCase c in DsCase.values) {
        expect(addressRoles(c)[0].first, AddrRole.ra, reason: '$c');
        expect(addressRoles(c)[1].first, AddrRole.ta, reason: '$c');
      }
    });

    test('only both bits set carries a fourth address', () {
      for (final DsCase c in DsCase.values) {
        expect(addressRoles(c).length, c == DsCase.both ? 4 : 3);
        expect(c.fourAddress, c == DsCase.both);
      }
    });

    test('the bits of each case', () {
      expect(DsCase.of(toDs: false, fromDs: false), DsCase.none);
      expect(DsCase.of(toDs: false, fromDs: true), DsCase.fromDs);
      expect(DsCase.of(toDs: true, fromDs: false), DsCase.toDs);
      expect(DsCase.of(toDs: true, fromDs: true), DsCase.both);
    });

    test('worked scene, To DS 0 From DS 0: tablet, laptop, BSSID', () {
      final List<AddressField> f = dsExample(DsCase.none).fields;
      expect(f.map((AddressField a) => a.mac).toList(), <Mac>[
        FjScene.tablet.mac,
        FjScene.laptop.mac,
        FjScene.ap.mac,
      ]);
      expect(f[0].roleText, 'RA = DA');
    });

    test('worked scene, To DS 0 From DS 1: laptop, BSSID, router', () {
      final List<AddressField> f = dsExample(DsCase.fromDs).fields;
      expect(f.map((AddressField a) => a.mac).toList(), <Mac>[
        FjScene.laptop.mac,
        FjScene.ap.mac,
        FjScene.routerLan.mac,
      ]);
      expect(f[1].roleText, 'TA = BSSID');
    });

    test('worked scene, To DS 1 From DS 0: BSSID, laptop, ROUTER (not the '
        'server)', () {
      final List<AddressField> f = dsExample(DsCase.toDs).fields;
      expect(f.map((AddressField a) => a.mac).toList(), <Mac>[
        FjScene.ap.mac,
        FjScene.laptop.mac,
        FjScene.routerLan.mac,
      ]);
      expect(f[2].mac, isNot(FjScene.server.mac));
      expect(f[0].roleText, 'RA = BSSID');
      expect(f[2].roleText, 'DA');
    });

    test('worked scene, To DS 1 From DS 1: root AP, mesh AP, router, laptop; '
        'a 32-byte QoS header', () {
      final DsExample e = dsExample(DsCase.both);
      expect(e.fields.map((AddressField a) => a.mac).toList(), <Mac>[
        FjScene.rootAp.mac,
        FjScene.meshAp.mac,
        FjScene.routerLan.mac,
        FjScene.laptop.mac,
      ]);
      expect(e.fields.map((AddressField a) => a.roleText).toList(), <String>[
        'RA',
        'TA',
        'DA',
        'SA',
      ]);
      expect(e.macHeader, 32);
      // Neither radio on the hop is the source or the destination: that is
      // why the fourth address exists.
      final DsParties p = e.parties;
      expect(p.transmitter.mac, isNot(p.source.mac));
      expect(p.receiver.mac, isNot(p.destination.mac));
    });

    test('a party list that contradicts the case is refused', () {
      expect(
        () => addressFields(
          DsCase.toDs,
          const DsParties(
            receiver: FjScene.server,
            transmitter: FjScene.laptop,
            source: FjScene.laptop,
            destination: FjScene.server,
            bssid: FjScene.ap,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('header sizes', () {
    test('TCP 1460 B: 1500 packet, 1508 MSDU, 1538 MPDU, 1518 on Ethernet', () {
      const FjSizes s = FjSizes(
        payload: 1460,
        transport: FjTransport.tcp,
        qos: true,
        fourAddress: false,
      );
      expect(s.transportHeader, 20);
      expect(s.ipHeader, 20);
      expect(s.llcSnap, 8);
      expect(s.macHeader, 26);
      expect(s.fcs, 4);
      expect(s.segment, 1480);
      expect(s.packet, 1500);
      expect(s.msdu, 1508);
      expect(s.mpdu, 1538);
      expect(s.ethernetFrame, 1518);
      expect(s.mpduBits, 12304);
    });

    test('UDP header is 8 bytes', () {
      const FjSizes s = FjSizes(
        payload: 1460,
        transport: FjTransport.udp,
        qos: true,
        fourAddress: false,
      );
      expect(s.packet, 1488);
      expect(s.mpdu, 1526);
    });

    test('MAC header: 24 textbook, 26 QoS, 30 four-address, 32 both', () {
      expect(macHeaderBytes(qos: false, fourAddress: false), 24);
      expect(macHeaderBytes(qos: true, fourAddress: false), 26);
      expect(macHeaderBytes(qos: false, fourAddress: true), 30);
      expect(macHeaderBytes(qos: true, fourAddress: true), 32);
    });

    test('the built frame is exactly the sum of its parts, every case', () {
      for (final DsCase c in DsCase.values) {
        for (final FjTransport t in FjTransport.values) {
          for (final bool qos in <bool>[true, false]) {
            for (final int n in kFjPayloadChoices) {
              final DsExample e = dsExample(c);
              final AirFrame f = AirFrame.build(
                c: c,
                p: e.parties,
                ip: FjIp(
                  src: FjScene.laptop.ip!,
                  dst: FjScene.server.ip!,
                  ttl: 64,
                  totalLength: 20 + t.headerBytes + n,
                  protocol: t.ipProtocol,
                ),
                ports: const FjPorts(51000, 443),
                transport: t,
                payload: n,
                qos: qos,
              );
              final FjSizes s = FjSizes(
                payload: n,
                transport: t,
                qos: qos,
                fourAddress: c.fourAddress,
              );
              expect(f.length, s.mpdu, reason: '$c $t qos=$qos $n');
              final FjField hdrEnd = f.fields.firstWhere(
                (FjField x) => x.name == 'LLC/SNAP',
              );
              expect(hdrEnd.start, s.macHeader);
            }
          }
        }
      }
    });

    test('the journey reports the same sizes at every layer', () {
      final List<FjStep> j = buildJourney(const FjConfig());
      int bytesAt(FjNode n, FjLayer l) =>
          j.firstWhere((FjStep s) => s.node == n && s.layer == l).pduBytes;
      expect(bytesAt(FjNode.laptop, FjLayer.application), 1460);
      expect(bytesAt(FjNode.laptop, FjLayer.transport), 1480);
      expect(bytesAt(FjNode.laptop, FjLayer.network), 1500);
      expect(bytesAt(FjNode.laptop, FjLayer.dataLink), 1538);
      expect(_airStep(j).pieces.single.label, '12304 bits');
    });
  });

  group('laptop on Wi-Fi to a wired server through an AP and a router', () {
    final List<FjStep> j = buildJourney(const FjConfig());

    test('on the air: To DS 1, A1 the BSSID, A2 the laptop, A3 the ROUTER', () {
      final FjStep air = _airStep(j);
      expect((air.link! as FjWifiLink).dsCase, DsCase.toDs);
      final List<AddressField> f = _wifi(air);
      expect(f[0].mac, FjScene.ap.mac);
      expect(f[1].mac, FjScene.laptop.mac);
      expect(f[2].mac, FjScene.routerLan.mac);
      expect(f[2].mac, isNot(FjScene.server.mac));
    });

    test(
      'the laptop resolves the gateway because the server is off-subnet',
      () {
        expect(sameSubnet('192.0.2.10', '198.51.100.20', 24), isFalse);
        expect(sameSubnet('192.0.2.10', '192.0.2.20', 24), isTrue);
        expect(
          layer2NextHop(
            srcIp: '192.0.2.10',
            prefix: 24,
            dstIp: '198.51.100.20',
            dstMac: FjScene.server.mac,
            gatewayMac: FjScene.routerLan.mac,
          ),
          FjScene.routerLan.mac,
        );
      },
    );

    test('wire, AP to router: source is the laptop (the AP is a bridge), '
        'destination the router LAN interface', () {
      final FjEthLink e = _eth(_wireSteps(j)[0]);
      expect(e.src.mac, FjScene.laptop.mac);
      expect(e.dst.mac, FjScene.routerLan.mac);
    });

    test('wire, router to server: both MACs are new', () {
      final FjEthLink e = _eth(_wireSteps(j)[1]);
      expect(e.src.mac, FjScene.routerOther.mac);
      expect(e.dst.mac, FjScene.server.mac);
    });

    test('the AP never appears as an Ethernet address', () {
      for (final FjStep s in j) {
        if (s.link is FjEthLink) {
          expect(_eth(s).src.mac, isNot(FjScene.ap.mac));
          expect(_eth(s).dst.mac, isNot(FjScene.ap.mac));
        }
      }
    });

    test('IP addresses stay end to end; TTL drops by one at the router and '
        'the checksum is recomputed', () {
      for (final FjStep s in j) {
        expect(s.ip.src, FjScene.laptop.ip);
        expect(s.ip.dst, FjScene.server.ip);
      }
      final int routerNet = j.indexWhere(
        (FjStep s) => s.node == FjNode.router && s.layer == FjLayer.network,
      );
      expect(j[routerNet - 1].ip.ttl, 64);
      expect(j[routerNet].ip.ttl, 63);
      expect(j.last.ip.ttl, 63);
      expect(j[routerNet].ip.checksum, isNot(j[routerNet - 1].ip.checksum));
      // A header with its checksum filled in sums to zero.
      for (final FjIp ip in <FjIp>[j[routerNet - 1].ip, j[routerNet].ip]) {
        expect(internetChecksum(ip.headerBytes()), 0);
      }
    });

    test('each device climbs only as far as it needs', () {
      FjLayer highest(FjNode n) => j
          .where((FjStep s) => s.node == n)
          .map((FjStep s) => s.layer!)
          .reduce((FjLayer a, FjLayer b) => a.osi > b.osi ? a : b);
      expect(highest(FjNode.laptop), FjLayer.application);
      expect(highest(FjNode.ap), FjLayer.dataLink);
      expect(highest(FjNode.router), FjLayer.network);
      expect(highest(FjNode.server), FjLayer.application);
    });

    test('same data arrives as was sent', () {
      expect(j.first.pieces.single.part, FjPart.data);
      expect(j.last.pieces.single.part, FjPart.data);
      expect(j.last.pduBytes, j.first.pduBytes);
      expect(j.last.node, FjNode.server);
    });

    test(
      'the reply: From DS 1, A1 the laptop, A2 the BSSID, A3 the router',
      () {
        final List<FjStep> r = buildJourney(
          const FjConfig(direction: FjDirection.reply),
        );
        final FjStep air = _airStep(r);
        expect((air.link! as FjWifiLink).dsCase, DsCase.fromDs);
        final List<AddressField> f = _wifi(air);
        expect(f[0].mac, FjScene.laptop.mac);
        expect(f[1].mac, FjScene.ap.mac);
        expect(f[2].mac, FjScene.routerLan.mac);
        expect(air.ip.src, FjScene.server.ip);
        expect(air.ip.dst, FjScene.laptop.ip);
        expect(air.ip.ttl, 63);
        expect(r.first.node, FjNode.server);
        expect(r.last.node, FjNode.laptop);
      },
    );

    test('same subnet, no router: A3 is the server itself and TTL never '
        'drops', () {
      final List<FjStep> s = buildJourney(
        const FjConfig(server: FjServerLocation.sameSubnet),
      );
      expect(_wifi(_airStep(s))[2].mac, FjScene.serverSameLan.mac);
      expect(s.any((FjStep x) => x.node == FjNode.router), isFalse);
      expect(s.last.ip.ttl, 64);
      expect(_wireSteps(s), hasLength(1));
    });
  });

  group('FCS (clause 9.2.4.8)', () {
    test('CRC-32 check value', () {
      expect(crc32(ascii.encode('123456789')), 0xCBF43926);
    });

    test('a clean frame passes', () {
      final AirFrame f = airFrameFor(const FjConfig());
      expect(FcsCheck(f.bytes).pass, isTrue);
      expect(FcsCheck(f.bytes).computed, f.fcsSent);
    });

    test('every single flipped bit fails, including bits in the FCS', () {
      final AirFrame f = airFrameFor(const FjConfig(payload: 100));
      for (int bit = 0; bit < f.bitCount; bit++) {
        expect(
          FcsCheck(f.withBitFlipped(bit)).pass,
          isFalse,
          reason: 'bit $bit in ${f.fieldAtBit(bit).name}',
        );
      }
    });

    test('the field a bit lands in', () {
      final AirFrame f = airFrameFor(const FjConfig());
      expect(f.fieldAtBit(0).name, startsWith('Frame Control'));
      expect(f.fieldAtBit(4 * 8).name, 'Address 1 (RA = BSSID)');
      expect(f.fieldAtBit(f.bitCount - 1).name, 'FCS');
    });

    test('FCS fail: no ACK, the sender retries with the Retry bit set', () {
      final List<FhStep> h = buildHop(
        const FhConfig(corrupt: true, flipBit: 200),
      );
      final List<FhStep> first = h.where((FhStep s) => s.attempt == 1).toList();
      expect(first.any((FhStep s) => s.stage == FjHopStage.ack), isFalse);
      expect(first.any((FhStep s) => s.stage == FjHopStage.sifs), isFalse);
      expect(
        first.firstWhere((FhStep s) => s.stage == FjHopStage.fcs).check!.pass,
        isFalse,
      );
      expect(first.map((FhStep s) => s.stage), contains(FjHopStage.noAck));
      expect(first.last.stage, FjHopStage.retry);

      final List<FhStep> second = h
          .where((FhStep s) => s.attempt == 2)
          .toList();
      expect(second, isNotEmpty);
      expect(second.first.frame.retry, isTrue);
      expect(second.first.frame.bytes[1] & 0x08, 0x08);
      expect(second.first.frame.fcsSent, isNot(first.first.frame.fcsSent));
      expect(
        second.firstWhere((FhStep s) => s.stage == FjHopStage.fcs).check!.pass,
        isTrue,
      );
      expect(second.map((FhStep s) => s.stage), contains(FjHopStage.ack));
      expect(h.last.stage, FjHopStage.done);
    });

    test('a clean hop: FCS pass, then SIFS, then ACK, one attempt', () {
      final List<FhStep> h = buildHop(const FhConfig());
      final List<FjHopStage> order = h.map((FhStep s) => s.stage).toList();
      expect(h.every((FhStep s) => s.attempt == 1), isTrue);
      final int fcs = order.indexOf(FjHopStage.fcs);
      expect(order.indexOf(FjHopStage.sifs), fcs + 1);
      expect(order.indexOf(FjHopStage.ack), fcs + 2);
      expect(order, isNot(contains(FjHopStage.noAck)));
    });

    test('A Frame\'s Journey carries the same frame as Down the Stack\'s air '
        'hop', () {
      final AirFrame stack = airFrameFor(const FjConfig());
      final AirFrame hop = buildHop(const FhConfig()).first.frame;
      expect(hop.bytes, stack.bytes);
    });
  });

  group('SIFS by band', () {
    test('16 us at 5 and 6 GHz', () {
      expect(sifsFor(FjBand.ghz5).sifsUs, 16);
      expect(sifsFor(FjBand.ghz5).signalExtensionUs, 0);
      expect(sifsFor(FjBand.ghz6).sifsUs, 16);
      expect(sifsFor(FjBand.ghz6).signalExtensionUs, 0);
    });

    test('10 us plus a 6 us signal extension at 2.4 GHz', () {
      expect(sifsFor(FjBand.ghz24).sifsUs, 10);
      expect(sifsFor(FjBand.ghz24).signalExtensionUs, 6);
      expect(sifsFor(FjBand.ghz24).gapUs, 16);
    });
  });

  group('radiotap', () {
    test('added only when the receiver captures, and never sent', () {
      final List<FhStep> on = buildHop(const FhConfig());
      final List<FhStep> off = buildHop(const FhConfig(capturing: false));
      expect(on.any((FhStep s) => s.stage == FjHopStage.radiotap), isTrue);
      expect(off.any((FhStep s) => s.stage == FjHopStage.radiotap), isFalse);
      expect(off.every((FhStep s) => s.radiotap == null), isTrue);
      // The frame on the air is the same either way.
      expect(on.first.frame.bytes, off.first.frame.bytes);
    });

    test('its fields: channel frequency by band, signal from distance', () {
      final RadiotapView rt = buildHop(
        const FhConfig(band: FjBand.ghz24),
      ).firstWhere((FhStep s) => s.stage == FjHopStage.radiotap).radiotap!;
      expect(rt.freqMHz, 2437);
      expect(rt.channel, 6);
      expect(rt.signalDbm, fjSignalDbm(8, FjBand.ghz24).round());
    });

    test('RF crosses 10 m in about 33 ns', () {
      expect(fjFlightNs(10), closeTo(33.36, 0.01));
    });
  });
}
