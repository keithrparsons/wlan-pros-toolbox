// SslInspectService unit tests — exercise the derived validity logic
// (expired / valid / not-yet-valid + day delta) and the pure PEM-parsing path
// (subject/issuer, SAN, serial, signature algorithm, key size, SHA-256), all
// without opening a socket.
//
// The fixture is a self-signed RSA-2048 certificate generated with OpenSSL:
//   CN=test.wlanpros.example, O=WLAN Pros Test, C=US
//   SAN: DNS:test.wlanpros.example, DNS:alt.wlanpros.example, IP:10.0.0.1
//   notBefore 2026-05-29, notAfter 2036-05-26
//   SHA-256: 16:DA:73:17:5F:5D:F0:E0:39:94:8E:07:D2:E4:D1:69:
//            E2:FC:D4:ED:25:A7:96:C4:37:3B:EE:D7:62:1D:BB:3F

import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/services/network/ssl_inspect_service.dart';

const String _fixturePem = '''
-----BEGIN CERTIFICATE-----
MIIDTzCCAjegAwIBAgIJAM1mGyXDsNKKMA0GCSqGSIb3DQEBCwUAMEYxHjAcBgNV
BAMMFXRlc3Qud2xhbnByb3MuZXhhbXBsZTEXMBUGA1UECgwOV0xBTiBQcm9zIFRl
c3QxCzAJBgNVBAYTAlVTMB4XDTI2MDUyOTE5MjQ0OFoXDTM2MDUyNjE5MjQ0OFow
RjEeMBwGA1UEAwwVdGVzdC53bGFucHJvcy5leGFtcGxlMRcwFQYDVQQKDA5XTEFO
IFByb3MgVGVzdDELMAkGA1UEBhMCVVMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw
ggEKAoIBAQDBWNn6kgzTfCTzOsewkKQGqgV8bHDyqtWecNxowRFk/hPGxxfS3NA3
aveNKyc3xzeg5tF2DLGeEIhNR+Nx0XDA5gxIHwB2w1tkEssjAIq6VqctHwY2qWKu
DIjbBgx07tHQQtjWbnpVuPOGr+UtnSfOkKK1H5rZqfMo/IaegOhNgESGN+jjU8Fu
gDUAryRp13H5A28mdHyD4Sw8UUss3szd9wA7CSsJyuMJNvUHGEjm7v1/c0sXW60D
uQDJyRAzCUo78dCwx80+qi/NjY16lxt1zdEY3K3fZHK0MvmBKqntbaOmRXOD7Gif
97pchtgCT7WJ+4jqOowYJcCs/EanOBoZAgMBAAGjQDA+MDwGA1UdEQQ1MDOCFXRl
c3Qud2xhbnByb3MuZXhhbXBsZYIUYWx0LndsYW5wcm9zLmV4YW1wbGWHBAoAAAEw
DQYJKoZIhvcNAQELBQADggEBAHluTOLHRPbBZCd+phu0xudw+aDr0XZqBGX1hVPc
+5PXiD49fNzMRxT2wNsZFwZaNXJvTLSA7PmVHj2yu6wDqgfMWQeowbWDx9hJF5DD
vwceSi/jUu+NSnLVEq5RCF21lgrLYxcz+yoUx23CcFcyPDpFuBxLgnoX0OUgNSd6
JTvWa3q0/o/AHem6u8r23wwAdbFnoNVOgFujeh5zcyMFnEwUOjtnZGrsi9jtFtHF
1SyWKK0WFgxk11b1LjZYa4Wr1797FQfIhWdcUU3wa3SY0hLiHkkpvn9MnN0xg5qp
GE7upRUiJ3aWE76y7+wlgd10vzM0JCFqnu//x2WB5Y9+WII=
-----END CERTIFICATE-----
''';

void main() {
  group('CertValidity.compute', () {
    final DateTime notBefore = DateTime.utc(2026, 1, 1);
    final DateTime notAfter = DateTime.utc(2026, 12, 31);

    test('within the window → valid with positive day delta', () {
      final CertValidity v = CertValidity.compute(
        notBefore: notBefore,
        notAfter: notAfter,
        now: DateTime.utc(2026, 6, 1),
      );
      expect(v.state, CertValidityState.valid);
      expect(v.daysToExpiry, greaterThan(0));
    });

    test('after notAfter → expired with negative day delta', () {
      final CertValidity v = CertValidity.compute(
        notBefore: notBefore,
        notAfter: notAfter,
        now: DateTime.utc(2027, 1, 10),
      );
      expect(v.state, CertValidityState.expired);
      expect(v.daysToExpiry, lessThan(0));
      // 10 days past expiry.
      expect(v.daysToExpiry, -10);
    });

    test('before notBefore → not yet valid', () {
      final CertValidity v = CertValidity.compute(
        notBefore: notBefore,
        notAfter: notAfter,
        now: DateTime.utc(2025, 12, 1),
      );
      expect(v.state, CertValidityState.notYetValid);
    });

    test('exactly one day to expiry', () {
      final CertValidity v = CertValidity.compute(
        notBefore: notBefore,
        notAfter: DateTime.utc(2026, 6, 2, 12),
        now: DateTime.utc(2026, 6, 1, 12),
      );
      expect(v.state, CertValidityState.valid);
      expect(v.daysToExpiry, 1);
    });
  });

  group('parsePeerCertificate (PEM path)', () {
    InspectedCertificate parse({DateTime? now}) =>
        SslInspectService.parsePeerCertificate(
          pem: _fixturePem,
          ioSubject: 'CN=test.wlanpros.example, O=WLAN Pros Test, C=US',
          ioIssuer: 'CN=test.wlanpros.example, O=WLAN Pros Test, C=US',
          ioNotBefore: DateTime.utc(2026, 5, 29),
          ioNotAfter: DateTime.utc(2036, 5, 26),
          ioSha1: const <int>[0xAB, 0xCD, 0xEF],
          now: now ?? DateTime.utc(2026, 6, 1),
        );

    test('subject CN and O parsed from the cert', () {
      final InspectedCertificate c = parse();
      expect(c.subjectCommonName, 'test.wlanpros.example');
      expect(c.subjectOrg, 'WLAN Pros Test');
    });

    test('issuer CN and O parsed (self-signed → same as subject)', () {
      final InspectedCertificate c = parse();
      expect(c.issuerCommonName, 'test.wlanpros.example');
      expect(c.issuerOrg, 'WLAN Pros Test');
    });

    test('SAN list recovered from the extension', () {
      final InspectedCertificate c = parse();
      expect(c.subjectAltNames, contains('test.wlanpros.example'));
      expect(c.subjectAltNames, contains('alt.wlanpros.example'));
      expect(c.subjectAltNames, contains('10.0.0.1'));
    });

    test('SHA-256 fingerprint grouped as uppercase colon-hex', () {
      final InspectedCertificate c = parse();
      expect(
        c.sha256Fingerprint,
        '16:DA:73:17:5F:5D:F0:E0:39:94:8E:07:D2:E4:D1:69:'
            'E2:FC:D4:ED:25:A7:96:C4:37:3B:EE:D7:62:1D:BB:3F',
      );
    });

    test('SHA-1 falls back to the dart:io bytes when grouping', () {
      final InspectedCertificate c = parse();
      expect(c.sha1Fingerprint, 'AB:CD:EF');
    });

    test('serial rendered as uppercase colon-hex (even-length)', () {
      final InspectedCertificate c = parse();
      expect(c.serialNumber, isNotNull);
      // Decimal 14800547074410599050 == hex CD661B25C3B0D28A.
      expect(c.serialNumber, 'CD:66:1B:25:C3:B0:D2:8A');
    });

    test('signature algorithm resolved to its readable name', () {
      final InspectedCertificate c = parse();
      expect(c.signatureAlgorithm, 'sha256WithRSAEncryption');
    });

    test('public-key algorithm and size', () {
      final InspectedCertificate c = parse();
      expect(c.publicKeyAlgorithm, 'rsaEncryption');
      expect(c.publicKeyBits, 2048);
    });

    test('validity computed from the certs own dates, valid in 2026', () {
      final InspectedCertificate c = parse(now: DateTime.utc(2026, 6, 1));
      expect(c.validity.state, CertValidityState.valid);
    });

    test('same cert reads as expired when now is past notAfter', () {
      final InspectedCertificate c = parse(now: DateTime.utc(2040, 1, 1));
      expect(c.validity.state, CertValidityState.expired);
    });

    test('malformed PEM degrades to dart:io values, never throws', () {
      final InspectedCertificate c = SslInspectService.parsePeerCertificate(
        pem: 'not a real pem',
        ioSubject: 'CN=fallback.example, O=Fallback Org',
        ioIssuer: 'CN=Root CA',
        ioNotBefore: DateTime.utc(2026, 1, 1),
        ioNotAfter: DateTime.utc(2026, 12, 31),
        ioSha1: const <int>[0x01, 0x02],
        now: DateTime.utc(2026, 6, 1),
      );
      expect(c.subjectCommonName, 'fallback.example');
      expect(c.subjectOrg, 'Fallback Org');
      expect(c.issuerCommonName, 'Root CA');
      expect(c.sha256Fingerprint, isNull);
      expect(c.sha1Fingerprint, '01:02');
      expect(c.validity.state, CertValidityState.valid);
    });
  });

  group('inspect input validation (no socket)', () {
    test('blank host → failure before any connect', () async {
      bool connected = false;
      final SslInspectService svc = SslInspectService(
        connector: (host, port, {required timeout}) async {
          connected = true;
          throw StateError('should not connect');
        },
      );
      final SslInspectResult r = await svc.inspect(rawHost: '   ');
      expect(r.isError, isTrue);
      expect(connected, isFalse);
    });

    test('out-of-range port → failure before any connect', () async {
      bool connected = false;
      final SslInspectService svc = SslInspectService(
        connector: (host, port, {required timeout}) async {
          connected = true;
          throw StateError('should not connect');
        },
      );
      final SslInspectResult r =
          await svc.inspect(rawHost: 'example.com', port: 70000);
      expect(r.isError, isTrue);
      expect(connected, isFalse);
    });
  });
}
