// DnsLookupScreen — widget tests for the dig-style upgrade.
//
// Drives the screen through its injected DnsLookupService seam (a fake DoH
// resolver), so no live network. Covers:
//   * idle → form only, no results panel;
//   * All records (dig) mode → grouped sections render with a summary line;
//   * Single type mode → record-type chips appear and a single-type query runs;
//   * reverse-PTR affordance appears only when the input parses as an IP;
//   * Copy payload carries the dig sweep records as TSV;
//   * no overflow across the standard widths.

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/dns_lookup_screen.dart';
import 'package:wlan_pros_toolbox/services/network/dns_lookup_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';

/// A fake resolver returning per-RRecordType canned answers. Any type not in
/// [byType] resolves empty.
DnsLookupService _svc(Map<RRecordType, List<RRecord>> byType) {
  return DnsLookupService(
    resolver: (name, type, {required resolver}) async =>
        byType[type] ?? <RRecord>[],
  );
}

/// A fake resolver where any [RRecordType] in [throwFor] fails the query (the
/// service catches it and produces a per-section error), while [byType]
/// supplies canned answers for the rest. Lets a test drive a mixed sweep where
/// some types resolve and others fail mid-sweep.
DnsLookupService _svcWithFailures({
  required Set<RRecordType> throwFor,
  Map<RRecordType, List<RRecord>> byType = const {},
}) {
  return DnsLookupService(
    resolver: (name, type, {required resolver}) async {
      if (throwFor.contains(type)) {
        throw const SocketExceptionStub('resolver timed out');
      }
      return byType[type] ?? <RRecord>[];
    },
  );
}

/// Minimal throwing payload so the fake resolver can simulate a per-type
/// failure without depending on dart:io in the test.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub(this.message);
  final String message;
  @override
  String toString() => message;
}

Widget _host(Widget child, {Size size = const Size(390, 844)}) => MaterialApp(
      theme: AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: child,
      ),
    );

void main() {
  late List<String> clipboardWrites;

  setUp(() {
    clipboardWrites = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        clipboardWrites.add(args['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('idle: form only, dig mode default, no results panel',
      (tester) async {
    await tester.pumpWidget(
      _host(DnsLookupScreen(service: _svc(const {}))),
    );

    expect(find.text('All records'), findsOneWidget);
    expect(find.text('Single type'), findsOneWidget);
    // Dig mode default → button reads "Look up all records".
    expect(find.text('Look up all records'), findsOneWidget);
    // Single-type record chips are hidden in dig mode.
    expect(find.text('Record type'), findsNothing);
    // No results panel yet (no summary line / message card).
    expect(find.textContaining('records ·'), findsNothing);
    expect(find.text('No records'), findsNothing);
  });

  testWidgets('All records sweep renders grouped sections + summary',
      (tester) async {
    final DnsLookupService svc = _svc(<RRecordType, List<RRecord>>{
      RRecordType.A: <RRecord>[
        RRecord(name: 'example.com', rType: 1, ttl: 300, data: '93.184.216.34'),
      ],
      RRecordType.MX: <RRecord>[
        RRecord(
            name: 'example.com',
            rType: 15,
            ttl: 3600,
            data: '10 mail.example.com'),
      ],
    });
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('Look up all records'));
    await tester.pumpAndSettle();

    // Summary line: 2 records across 2 types.
    expect(find.textContaining('2 records'), findsOneWidget);
    expect(find.textContaining('2 types'), findsOneWidget);
    // Group headers (TYPE (n)) and a value render.
    expect(find.textContaining('A  (1)'), findsOneWidget);
    expect(find.textContaining('MX  (1)'), findsOneWidget);
    expect(find.text('93.184.216.34'), findsOneWidget);
  });

  testWidgets('All records: name with nothing → No records state',
      (tester) async {
    await tester.pumpWidget(
      _host(DnsLookupScreen(service: _svc(const {}))),
    );

    await tester.enterText(find.byType(TextField), 'empty.example');
    await tester.tap(find.text('Look up all records'));
    await tester.pumpAndSettle();

    expect(find.text('No records'), findsOneWidget);
  });

  testWidgets(
      'All records: partial failure is surfaced (summary + per-type note)',
      (tester) async {
    // A/MX resolve; AAAA and CAA fail mid-sweep. The records that resolved must
    // show, AND the failed types must be disclosed — never a clean-looking
    // result that hides the failures (GL-005).
    final DnsLookupService svc = _svcWithFailures(
      throwFor: <RRecordType>{RRecordType.AAAA, RRecordType.CAA},
      byType: <RRecordType, List<RRecord>>{
        RRecordType.A: <RRecord>[
          RRecord(
              name: 'example.com', rType: 1, ttl: 300, data: '93.184.216.34'),
        ],
        RRecordType.MX: <RRecord>[
          RRecord(
              name: 'example.com',
              rType: 15,
              ttl: 3600,
              data: '10 mail.example.com'),
        ],
      },
    );
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('Look up all records'));
    await tester.pumpAndSettle();

    // Resolved records still render.
    expect(find.text('93.184.216.34'), findsOneWidget);
    expect(find.textContaining('A  (1)'), findsOneWidget);

    // Summary discloses the failure count (8 types swept: SOA, NS, A, AAAA, MX,
    // TXT, SRV, CAA → 2 failed).
    expect(find.textContaining('2 of 8 types failed to resolve'),
        findsOneWidget);

    // Each failed type is itemized as a per-type "Lookup failed" note (the
    // failed type tokens AAAA and CAA appear with a failure label).
    expect(find.textContaining('Lookup failed'), findsWidgets);
    expect(find.text('AAAA'), findsOneWidget);
    expect(find.text('CAA'), findsOneWidget);
  });

  testWidgets(
      'All records: every type fails → reads as Lookup failed, not empty',
      (tester) async {
    // Every queried type fails. This must NOT render as "No records" — it is a
    // total failure and must say so (GL-005).
    final DnsLookupService svc = _svcWithFailures(
      throwFor: RRecordType.values.toSet(),
    );
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    await tester.enterText(find.byType(TextField), 'broken.example');
    await tester.tap(find.text('Look up all records'));
    await tester.pumpAndSettle();

    // Headline is a failure, not the empty state.
    expect(find.text('Lookup failed'), findsOneWidget);
    expect(find.text('No records'), findsNothing);
    expect(
      find.textContaining('Every query failed'),
      findsOneWidget,
    );
  });

  testWidgets('Single type mode exposes record-type chips and runs one type',
      (tester) async {
    final DnsLookupService svc = _svc(<RRecordType, List<RRecord>>{
      RRecordType.TXT: <RRecord>[
        RRecord(name: 'example.com', rType: 16, ttl: 60, data: 'hello'),
      ],
    });
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    await tester.tap(find.text('Single type'));
    await tester.pumpAndSettle();
    expect(find.text('Record type'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'example.com');
    // Pick TXT (chip), then look up.
    await tester.tap(find.widgetWithText(ChoiceChip, 'TXT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 TXT record'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('Quad9 is a selectable resolver and a query runs against it',
      (tester) async {
    DohResolver? ranWith;
    final DnsLookupService svc = DnsLookupService(
      resolver: (name, type, {required resolver}) async {
        ranWith = resolver;
        return <RRecord>[
          RRecord(name: 'example.com', rType: 1, ttl: 300, data: '93.184.216.34'),
        ];
      },
    );
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    // The three resolver chips are present, Quad9 included.
    expect(find.widgetWithText(ChoiceChip, 'Cloudflare (1.1.1.1)'),
        findsOneWidget);
    expect(
        find.widgetWithText(ChoiceChip, 'Google (8.8.8.8)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Quad9 (9.9.9.9)'), findsOneWidget);

    // Select Quad9, run a single-type query, confirm it resolved against Quad9.
    await tester.tap(find.text('Single type'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quad9 (9.9.9.9)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();

    expect(ranWith, DohResolver.quad9);
    // The result summary line names the resolver that ran (alongside the chip,
    // so "Quad9 (9.9.9.9)" now appears twice: the chip + the summary).
    expect(find.textContaining('Quad9 (9.9.9.9)'), findsNWidgets(2));
    expect(find.textContaining('1 A record · Quad9 (9.9.9.9)'), findsOneWidget);
    expect(find.text('93.184.216.34'), findsOneWidget);
  });

  testWidgets('reverse-PTR button appears only for an IP input',
      (tester) async {
    final DnsLookupService svc = _svc(<RRecordType, List<RRecord>>{
      RRecordType.PTR: <RRecord>[
        RRecord(
            name: '8.8.8.8.in-addr.arpa',
            rType: 12,
            ttl: 60,
            data: 'dns.google'),
      ],
    });
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    // Hostname → no reverse affordance.
    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.pump();
    expect(find.text('Reverse lookup (PTR)'), findsNothing);

    // IP literal → affordance appears.
    await tester.enterText(find.byType(TextField), '8.8.8.8');
    await tester.pump();
    expect(find.text('Reverse lookup (PTR)'), findsOneWidget);

    await tester.tap(find.text('Reverse lookup (PTR)'));
    await tester.pumpAndSettle();
    expect(find.text('dns.google'), findsOneWidget);
  });

  testWidgets('Copy payload carries the dig sweep as TSV', (tester) async {
    final DnsLookupService svc = _svc(<RRecordType, List<RRecord>>{
      RRecordType.A: <RRecord>[
        RRecord(name: 'example.com', rType: 1, ttl: 300, data: '93.184.216.34'),
      ],
    });
    await tester.pumpWidget(_host(DnsLookupScreen(service: svc)));

    await tester.enterText(find.byType(TextField), 'example.com');
    await tester.tap(find.text('Look up all records'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppCopyAction));
    await tester.pump();

    expect(clipboardWrites, isNotEmpty);
    final String copied = clipboardWrites.last;
    expect(copied, contains('DNS Lookup'));
    expect(copied, contains('Type\tName\tValue\tTTL'));
    expect(copied, contains('93.184.216.34'));

    // Drain the AppCopyAction confirm-window timer (§8.16, 1500ms) so the test
    // tears down with no pending timer.
    await tester.pump(const Duration(milliseconds: 1600));
  });

  testWidgets('no overflow across standard widths', (tester) async {
    final DnsLookupService svc = _svc(<RRecordType, List<RRecord>>{
      RRecordType.A: <RRecord>[
        RRecord(name: 'example.com', rType: 1, ttl: 300, data: '93.184.216.34'),
      ],
    });
    for (final double width in <double>[360, 768, 1280]) {
      await tester.pumpWidget(
        _host(DnsLookupScreen(service: svc), size: Size(width, 900)),
      );
      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.text('Look up all records'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow at width $width');
    }
  });
}
