// Phase C PiBackendClient coverage — the 12 new model-mapping methods plus the
// LAN-perf timing legs.
//
// Every fixture below is the REAL JSON captured live from the deployed Pi
// backend (10.0.10.252:8080, 2026-07-09) — not a hand-written guess — so these
// tests pin the exact wire shapes the app parses. A MockClient stands in for the
// browser fetch so no Pi is needed. The load-bearing checks per tool: the shape
// bridges into the right native model, honest-null fields stay null (never
// zero-/fake-filled, GL-005), and error/400 bodies surface as the state the
// screens render.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wlan_pros_toolbox/services/network/arp_ndp_service.dart';
import 'package:wlan_pros_toolbox/services/network/bgp_asn_service.dart';
import 'package:wlan_pros_toolbox/services/network/http_header_service.dart';
import 'package:wlan_pros_toolbox/services/network/ip_geo_service.dart';
import 'package:wlan_pros_toolbox/services/network/lan_discovery/lan_discovery_engine.dart';
import 'package:wlan_pros_toolbox/services/network/packet_sender_service.dart';
import 'package:wlan_pros_toolbox/services/network/ping_plot_controller.dart';
import 'package:wlan_pros_toolbox/services/network/pi_backend_client.dart';
import 'package:wlan_pros_toolbox/services/network/port_scan_service.dart';
import 'package:wlan_pros_toolbox/services/network/ping_sweep_service.dart';
import 'package:wlan_pros_toolbox/services/network/ssl_inspect_service.dart';
import 'package:wlan_pros_toolbox/services/network/wake_on_lan_service.dart';
import 'package:wlan_pros_toolbox/services/network/whois_service.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: <String, String>{'content-type': 'application/json'});

PiBackendClient _client(MockClient mock) =>
    PiBackendClient(httpClient: mock, base: Uri.parse('http://pi.local/'));

void main() {
  group('sslInspect()', () {
    test('bridges the cert JSON into SslInspectResult + InspectedCertificate', () async {
      late Uri seen;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        seen = req.url;
        return _json(<String, dynamic>{
          'host': 'cloudflare.com',
          'port': 443,
          'handshake_ms': 24.2,
          'alpn': 'h2',
          'certificate': <String, dynamic>{
            'subject_cn': 'cloudflare.com',
            'subject_org': null,
            'issuer_cn': 'WE1',
            'issuer_org': 'Google Trust Services',
            'not_before': '2026-07-08T21:47:39Z',
            'not_after': '2026-10-06T22:47:27Z',
            'days_to_expiry': 89,
            'serial': '5BB0F0AA84C8FECE0E72D805BA7A5D2B',
            'sig_algo': 'ecdsa-with-SHA256',
            'pubkey_algo': 'id-ecPublicKey',
            'pubkey_bits': 256,
            'sha256': '6a7041850081b32dbe52400df0a2842c32d55e80ffa40e339f7c1508a913d3f4',
            'sha1': '868b692c5ded0ea40cb860de746eea19d0be2e7c',
            'sans': <String>['cloudflare.com', 'ns.cloudflare.com'],
            'pem': '-----BEGIN CERTIFICATE-----\nMIID...\n-----END CERTIFICATE-----\n',
          },
          'error': null,
        });
      }));

      final SslInspectResult r =
          await client.sslInspect(host: 'cloudflare.com');

      expect(seen.path, '/toolboxapi/ssl');
      expect(seen.queryParameters['host'], 'cloudflare.com');
      expect(seen.queryParameters['port'], '443');
      expect(r.isError, isFalse);
      expect(r.alpn, 'h2');
      expect(r.handshakeMs, 24);
      final InspectedCertificate c = r.certificate!;
      expect(c.subjectCommonName, 'cloudflare.com');
      expect(c.subjectOrg, isNull); // honest-null passed through
      expect(c.issuerOrg, 'Google Trust Services');
      expect(c.publicKeyBits, 256);
      expect(c.subjectAltNames, contains('ns.cloudflare.com'));
      // Fingerprint/serial normalized to uppercase colon-grouped hex.
      expect(c.sha1Fingerprint, startsWith('86:8B:'));
      expect(c.serialNumber, startsWith('5B:B0:'));
      // Validity is derived from the dates, not the Pi's days_to_expiry field.
      expect(c.validity.notAfter.toUtc().year, 2026);
    });

    test('a null certificate is a failure carrying the Pi error', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'host': 'nope.invalid',
          'port': 443,
          'certificate': null,
          'error': 'could not connect',
        });
      }));
      final SslInspectResult r = await client.sslInspect(host: 'nope.invalid');
      expect(r.isError, isTrue);
      expect(r.errorMessage, 'could not connect');
      expect(r.certificate, isNull);
    });
  });

  group('httpHeaders()', () {
    test('maps the hop chain + headers into HttpHeaderResult', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.path, '/toolboxapi/httphead');
        return _json(<String, dynamic>{
          'requested_url': 'https://example.com',
          'head_fell_back_to_get': false,
          'redirect_limit_hit': false,
          'hops': <dynamic>[
            <String, dynamic>{
              'method': 'HEAD',
              'url': 'https://example.com',
              'status': 200,
              'reason': 'OK',
              'location': null,
              'elapsed_ms': 69.6,
              'headers': <dynamic>[
                <String, dynamic>{'name': 'Server', 'value': 'cloudflare'},
                <String, dynamic>{'name': 'Content-Type', 'value': 'text/html'},
              ],
            },
          ],
          'error': null,
        });
      }));
      final HttpHeaderResult r =
          await client.httpHeaders(url: 'https://example.com');
      expect(r.isError, isFalse);
      expect(r.hops, hasLength(1));
      final HttpHop hop = r.hops.first;
      expect(hop.method, HttpMethod.head);
      expect(hop.statusCode, 200);
      expect(hop.elapsedMs, 70);
      expect(hop.headers.map((HeaderEntry h) => h.name), contains('Server'));
    });

    test('an error body is a failure', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'requested_url': 'https://x',
          'hops': <dynamic>[],
          'error': 'blocked',
        });
      }));
      final HttpHeaderResult r = await client.httpHeaders(url: 'https://x');
      expect(r.isError, isTrue);
      expect(r.errorMessage, 'blocked');
    });
  });

  group('whois()', () {
    test('maps raw + highlights + servers into WhoisResult', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.path, '/toolboxapi/whois');
        return _json(<String, dynamic>{
          'query': 'cloudflare.com',
          'raw': 'Domain Name: CLOUDFLARE.COM\nRegistrar: Cloudflare, Inc.\n',
          'servers_queried': <String>['whois.iana.org', 'whois.verisign-grs.com'],
          'highlights': <dynamic>[
            <String, dynamic>{'label': 'Registrar', 'value': 'Cloudflare, Inc.'},
            <String, dynamic>{'label': 'Created', 'value': '2009-02-17T22:07:54Z'},
          ],
          'error': null,
        });
      }));
      final WhoisResult r = await client.whois(query: 'cloudflare.com');
      expect(r.isError, isFalse);
      expect(r.serversQueried, contains('whois.verisign-grs.com'));
      expect(r.highlights.first.label, 'Registrar');
      expect(r.rawRecord, contains('CLOUDFLARE.COM'));
    });
  });

  group('ipGeo()', () {
    test('maps ipinfo flattened JSON, honest-null on utc_offset/isp', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.path, '/toolboxapi/ipgeo');
        return _json(<String, dynamic>{
          'query': '1.1.1.1',
          'provider': 'ipinfo',
          'ip': '1.1.1.1',
          'ip_version': '4',
          'country': 'AU',
          'country_code': 'AU',
          'region': 'Queensland',
          'city': 'Brisbane',
          'postal': '9010',
          'latitude': -27.4679,
          'longitude': 153.0281,
          'timezone': 'Australia/Brisbane',
          'utc_offset': null,
          'isp': null,
          'org': 'AS13335 Cloudflare, Inc.',
          'asn': 'AS13335',
          'asn_name': 'Cloudflare, Inc.',
          'error': null,
        });
      }));
      final IpGeoResult r = await client.ipGeo(query: '1.1.1.1');
      expect(r.isError, isFalse);
      expect(r.provider, IpGeoProvider.ipinfo);
      expect(r.ipVersion, 'IPv4');
      expect(r.city, 'Brisbane');
      expect(r.latitude, closeTo(-27.4679, 1e-9));
      expect(r.utcOffset, isNull);
      expect(r.isp, isNull);
      expect(r.asn, 'AS13335');
      expect(r.hasCoordinates, isTrue);
    });
  });

  group('bgpAsn()', () {
    test('IP path carries the announced prefix', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'query': '1.1.1.1',
          'kind': 'ip',
          'asn': 'AS13335',
          'holder': 'CLOUDFLARENET - Cloudflare, Inc.',
          'announced_prefix': '1.1.1.0/24',
          'is_announced': true,
          'country': null,
          'registry': null,
          'related_asns': <String>['AS13335'],
          'error': null,
        });
      }));
      final BgpAsnResult r = await client.bgpAsn(query: '1.1.1.1');
      expect(r.kind, BgpQueryKind.ip);
      expect(r.announcedPrefix, '1.1.1.0/24');
      expect(r.country, isNull);
      expect(r.isAnnounced, isTrue);
    });

    test('ASN path may return a null announced_prefix (honest-null, Mack)', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'query': 'AS13335',
          'kind': 'asn',
          'asn': 'AS13335',
          'holder': 'CLOUDFLARENET - Cloudflare, Inc.',
          'announced_prefix': null,
          'is_announced': true,
          'related_asns': <String>[],
          'error': null,
        });
      }));
      final BgpAsnResult r = await client.bgpAsn(query: 'AS13335');
      expect(r.kind, BgpQueryKind.asn);
      expect(r.announcedPrefix, isNull); // not fabricated
      expect(r.holder, contains('Cloudflare'));
    });
  });

  group('neighbors()', () {
    test('reads the table into Neighbor entries (fromArpTable, null RTT)', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.path, '/toolboxapi/neigh');
        return _json(<String, dynamic>{
          'neighbors': <dynamic>[
            <String, dynamic>{
              'ip': '10.0.10.1',
              'mac': '0c:ea:14:32:91:c4',
              'state': 'REACHABLE',
              'dev': 'eth0',
              'is_ipv6': false,
            },
            <String, dynamic>{'ip': '', 'mac': null}, // dropped
          ],
          'source': 'ip neigh (live table on the WLAN Pi)',
        });
      }));
      final List<Neighbor> ns = await client.neighbors();
      expect(ns, hasLength(1));
      expect(ns.first.ip, '10.0.10.1');
      expect(ns.first.mac, '0c:ea:14:32:91:c4');
      expect(ns.first.fromArpTable, isTrue);
      expect(ns.first.rttMs, isNull);
    });
  });

  group('portScan()', () {
    test('maps open/closed/filtered into PortResult', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.queryParameters['ports'], '22,80,443');
        return _json(<String, dynamic>{
          'host': 'scanme.nmap.org',
          'scanned': 3,
          'results': <dynamic>[
            <String, dynamic>{'port': 22, 'status': 'open', 'service': 'ssh', 'elapsed_ms': 21.7},
            <String, dynamic>{'port': 443, 'status': 'closed', 'service': 'https', 'elapsed_ms': 21.6},
          ],
        });
      }));
      final List<PortResult> ports =
          await client.portScan(host: 'scanme.nmap.org', ports: '22,80,443');
      expect(ports, hasLength(2));
      expect(ports.first.port, 22);
      expect(ports.first.status, PortStatus.open);
      expect(ports.first.serviceName, 'ssh');
      expect(ports[1].status, PortStatus.closed);
    });
  });

  group('pingSweep()', () {
    test('returns only responders as SweepHostResult', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'cidr': '10.0.10.0/28',
          'total': 14,
          'live': 1,
          'hosts': <dynamic>[
            <String, dynamic>{'host': '10.0.10.1', 'responded': true, 'rtt_ms': 1.5},
          ],
        });
      }));
      final List<SweepHostResult> hosts =
          await client.pingSweep(cidr: '10.0.10.0/28');
      expect(hosts, hasLength(1));
      expect(hosts.first.host, '10.0.10.1');
      expect(hosts.first.responded, isTrue);
      expect(hosts.first.rttMs, closeTo(1.5, 1e-9));
    });

    test('a 400 too-large surfaces the server message via PiBackendException', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'error': 'range too large for the Pi path; use the native app',
        }, status: 400);
      }));
      expect(
        () => client.pingSweep(cidr: '10.0.0.0/8'),
        throwsA(isA<PiBackendException>().having(
          (PiBackendException e) => e.message,
          'message',
          contains('range too large'),
        )),
      );
    });
  });

  group('discovery()', () {
    test('maps hosts into DiscoveryResult / LanHost', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.path, '/toolboxapi/discovery');
        return _json(<String, dynamic>{
          'subnet_label': '10.0.10.0/24',
          'self_ip': '10.0.10.252',
          'gateway': '10.0.10.1',
          'hosts': <dynamic>[
            <String, dynamic>{
              'ip': '10.0.10.1',
              'mac': '0c:ea:14:32:91:c4',
              'vendor': null,
              'hostname': null,
              'open_ports': <dynamic>[80, 443, 8080],
              'device_type': 'unknown',
            },
          ],
          'error': null,
        });
      }));
      final DiscoveryResult r = await client.discovery();
      expect(r.subnetLabel, '10.0.10.0/24');
      expect(r.selfIp, '10.0.10.252');
      expect(r.hosts, hasLength(1));
      expect(r.hosts.first.ip, '10.0.10.1');
      expect(r.hosts.first.openPorts, containsAll(<int>[80, 443, 8080]));
      expect(r.hosts.first.vendor, isNull);
    });
  });

  group('pingSeries()', () {
    test('folds the whole series into a static PingPlotState', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.queryParameters['count'], '6');
        return _json(<String, dynamic>{
          'host': '1.1.1.1',
          'count': 6,
          'samples': <dynamic>[
            <String, dynamic>{'seq': 1, 'rtt_ms': 4.9, 'lost': false},
            <String, dynamic>{'seq': 2, 'rtt_ms': 2.6, 'lost': false},
            <String, dynamic>{'seq': 3, 'rtt_ms': null, 'lost': true},
          ],
          'sent': 6,
          'received': 5,
          'min_ms': 2.6,
          'max_ms': 4.9,
          'avg_ms': 3.1,
          'jitter_ms': 0.6,
        });
      }));
      final PingPlotState s = await client.pingSeries(host: '1.1.1.1', count: 6);
      expect(s.samples, hasLength(3));
      expect(s.samples[2].lost, isTrue);
      expect(s.samples[2].rttMs, isNull); // gap, never a faked 0
      expect(s.totalSent, 6);
      expect(s.totalReceived, 5);
      expect(s.avgMs, closeTo(3.1, 1e-9));
      expect(s.jitterMs, closeTo(0.6, 1e-9));
    });
  });

  group('throughput()', () {
    test('honest-null download leg with an error', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'download_mbps': null,
          'upload_mbps': 80.2,
          'server': 'speed.cloudflare.com',
          'method': 'multi-stream aggregate capacity, measured from the Pi\'s uplink',
          'download_error': 'download failed',
          'upload_error': null,
        });
      }));
      final PiThroughputResult r = await client.throughput();
      expect(r.downloadMbps, isNull); // never fabricated
      expect(r.uploadMbps, closeTo(80.2, 1e-9));
      expect(r.downloadError, 'download failed');
      expect(r.server, 'speed.cloudflare.com');
    });
  });

  group('wakeOnLan()', () {
    test('POSTs the body and maps a sent result', () async {
      late http.Request captured;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        captured = req;
        return _json(<String, dynamic>{
          'mac': 'AA:BB:CC:DD:EE:FF',
          'broadcast': '255.255.255.255',
          'port': 9,
          'bytes_sent': 102,
          'error': null,
        });
      }));
      final WakeOnLanResult r =
          await client.wakeOnLan(mac: 'aa:bb:cc:dd:ee:ff');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/toolboxapi/wol');
      final Map<String, dynamic> body =
          jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['mac'], 'aa:bb:cc:dd:ee:ff');
      expect(r.isError, isFalse);
      expect(r.bytesSent, 102);
      expect(r.normalizedMac, 'AA:BB:CC:DD:EE:FF');
    });

    test('an error body maps to a failure', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        return _json(<String, dynamic>{
          'mac': 'AA:BB:CC:DD:EE:FF',
          'broadcast': '255.255.255.255',
          'port': 9,
          'bytes_sent': 0,
          'error': 'broadcast blocked',
        });
      }));
      final WakeOnLanResult r =
          await client.wakeOnLan(mac: 'aa:bb:cc:dd:ee:ff');
      expect(r.isError, isTrue);
      expect(r.errorMessage, 'broadcast blocked');
    });
  });

  group('packetSend()', () {
    test('hex-encodes the payload and hex-decodes the reply', () async {
      late http.Request captured;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        captured = req;
        return _json(<String, dynamic>{
          'transport': 'tcp',
          'host': 'scanme.nmap.org',
          'port': 80,
          'bytes_sent': 4,
          'received_hex': '48454144', // "HEAD"
          'elapsed_ms': 12,
          'timed_out': false,
          'error': null,
        });
      }));
      final PacketResult r = await client.packetSend(
        transport: PacketTransport.tcp,
        host: 'scanme.nmap.org',
        port: 80,
        payload: <int>[0xde, 0xad, 0xbe, 0xef],
      );
      final Map<String, dynamic> body =
          jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['payload_hex'], 'deadbeef');
      expect(body['transport'], 'tcp');
      expect(r.isError, isFalse);
      expect(r.bytesSent, 4);
      expect(r.received, <int>[0x48, 0x45, 0x41, 0x44]);
      expect(r.elapsed.inMilliseconds, 12);
    });
  });

  group('LAN-perf legs', () {
    test('deviceToPiDownloadMbps times the garbage stream', () async {
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        expect(req.url.path, '/toolboxapi/garbage');
        expect(req.url.queryParameters['size'], isNotNull);
        // 1 MB of body → a positive Mbps figure.
        return http.Response.bytes(
            List<int>.filled(1024 * 1024, 0), 200);
      }));
      final double mbps = await client.deviceToPiDownloadMbps(bytes: 1024 * 1024);
      expect(mbps, greaterThan(0));
    });

    test('deviceToPiUploadMbps POSTs to perfsink and times it', () async {
      late http.Request captured;
      final PiBackendClient client = _client(MockClient((http.Request req) async {
        captured = req;
        return _json(<String, dynamic>{'received_bytes': 4096, 'elapsed_ms': 4});
      }));
      final double mbps = await client.deviceToPiUploadMbps(bytes: 4096);
      expect(captured.method, 'POST');
      expect(captured.url.path, '/toolboxapi/perfsink');
      expect(mbps, greaterThanOrEqualTo(0));
    });
  });
}
