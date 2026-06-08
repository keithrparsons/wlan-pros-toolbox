// Tests for the DNS Record Types reference screen.
//
// The dataset is reproduced verbatim from the verified protocols dataset
// (Deliverables/2026-06-08-reference-batch/protocols-data.md, Page 1): IANA
// TYPE codes + defining RFCs. These tests assert the load-bearing anchor rows
// (the corrected RFCs: CAA -> RFC 8659, HTTPS/SVCB -> RFC 9460) so a future
// edit cannot silently drift a value, plus phone/tablet/desktop widget tests
// confirming the read-only screen renders without a RenderFlex overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/dns_record_types_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  group('DNS record types — match the verified dataset', () {
    DnsRecordType recFor(String type) => DnsRecordTypesScreen.records
        .firstWhere((DnsRecordType r) => r.type == type);

    test('A = code 1, RFC 1035', () {
      final DnsRecordType r = recFor('A');
      expect(r.code, 1);
      expect(r.rfc, 'RFC 1035');
    });

    test('AAAA = code 28, RFC 3596', () {
      final DnsRecordType r = recFor('AAAA');
      expect(r.code, 28);
      expect(r.rfc, 'RFC 3596');
    });

    test('CAA = code 257, RFC 8659 (obsoletes RFC 6844)', () {
      final DnsRecordType r = recFor('CAA');
      expect(r.code, 257);
      expect(r.rfc, 'RFC 8659');
    });

    test('HTTPS = code 65, RFC 9460; SVCB = code 64, RFC 9460', () {
      expect(recFor('HTTPS').code, 65);
      expect(recFor('HTTPS').rfc, 'RFC 9460');
      expect(recFor('SVCB').code, 64);
      expect(recFor('SVCB').rfc, 'RFC 9460');
    });

    test('eighteen records, no em dash in any field', () {
      expect(DnsRecordTypesScreen.records.length, 18);
      for (final DnsRecordType r in DnsRecordTypesScreen.records) {
        expect(r.purpose.contains('—'), isFalse, reason: 'no em dash');
        expect(r.rfc.startsWith('RFC '), isTrue);
      }
    });
  });

  group('DnsRecordTypesScreen widget', () {
    testWidgets('renders title and the table heading in a phone viewport',
        (tester) async {
      await _withViewport(tester, const Size(375, 1200), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const DnsRecordTypesScreen(),
          ),
        );
        expect(find.text('DNS Record Types'), findsWidgets);
        expect(find.text('Resource record types'), findsOneWidget);
        expect(find.text('CNAME'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      });
    });

    testWidgets('renders without overflow at 320/375/768/1280 widths',
        (tester) async {
      for (final double width in <double>[320, 375, 768, 1280]) {
        await _withViewport(tester, Size(width, 1400), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: const DnsRecordTypesScreen(),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'overflow at ${width}px');
        });
      }
    });
  });
}

/// Helper — run [body] with the test view sized to [size], then restore.
Future<void> _withViewport(
  WidgetTester tester,
  Size size,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await body();
}
