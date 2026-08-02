// BssLoadScreen, widget tests: every state this screen can render, driven.
//
// THE POINT OF THIS FILE IS THAT EACH STATE FAILS SEPARATELY. A screen whose
// seven unavailable readings collapse into one gray wall passes any test that
// only asserts "something rendered", and the collapse is exactly the defect
// `bss_load_decoder.dart` was rewritten twice to prevent
// ([[feedback_tests_that_cannot_fail]]). So the table below pumps every reading
// through the real widget tree and asserts the sentence that reading and no
// other produces.
//
// THE COPY LIVES IN `bss_load_presentation_test.dart`. This file asserts that
// the WIDGET puts it on screen, that the attribution eyebrow travels with it,
// that the numbers appear beside their wire values, and that the interactive
// states behave. Splitting it that way keeps this file from becoming a second
// copy of the vocabulary, which would drift.
//
// Build: Felix 2026-08-02.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/bss_load_presentation.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/bss_load_screen.dart';
import 'package:wlan_pros_toolbox/services/network/bss_load_decoder.dart';
import 'package:wlan_pros_toolbox/services/network/wifi_info_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/app_copy_action.dart';
import 'package:wlan_pros_toolbox/widgets/status_chip.dart';

const BssLoadReadContext _kMacosAuthorized = BssLoadReadContext(
  platformExposesInformationElements: true,
  locationAuth: LocationAuthStatus.authorized,
);

/// A source that answers immediately with whatever the test hands it.
class _FakeSource implements BssLoadSource {
  _FakeSource(this._snapshot);

  final BssLoadSnapshot _snapshot;
  int reads = 0;

  @override
  Future<BssLoadSnapshot> read() async {
    reads++;
    return _snapshot;
  }
}

/// A source that never answers, so the loading state can be held and asserted.
class _HangingSource implements BssLoadSource {
  final Completer<BssLoadSnapshot> completer = Completer<BssLoadSnapshot>();

  @override
  Future<BssLoadSnapshot> read() => completer.future;
}

/// A source that throws. The shipping source swallows its own channel failures,
/// so this is how the error state is reached and why the state exists at all.
class _ThrowingSource implements BssLoadSource {
  @override
  Future<BssLoadSnapshot> read() async {
    throw StateError('channel exploded');
  }
}

BssLoadSnapshot _snapshot(
  BssLoadReading reading, {
  BssLoadReadContext context = _kMacosAuthorized,
  String? bssid,
}) => BssLoadSnapshot(reading: reading, context: context, bssid: bssid);

Widget _wrap(BssLoadSource source, {bool light = false}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: BssLoadScreen(source: source),
);

Future<void> _pump(
  WidgetTester tester,
  BssLoadSource source, {
  bool light = false,
}) async {
  await tester.pumpWidget(_wrap(source, light: light));
  await tester.pumpAndSettle();
}

/// Records what `SemanticsService.sendAnnouncement` puts on the platform
/// accessibility channel, in order.
///
/// THIS IS THE ONLY WAY TO SEE A WCAG 4.1.3 STATUS MESSAGE FROM A TEST. A
/// one-shot announcement leaves no trace in the semantics tree — it is a
/// message, not a node — so a test that inspected the tree would pass on a
/// build that never spoke ([[feedback_tests_that_cannot_fail]]). Install it
/// BEFORE pumping: this screen reads once on open.
List<String> _captureAnnouncements(WidgetTester tester) {
  final List<String> spoken = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
    SystemChannels.accessibility,
    (Object? message) async {
      final Map<Object?, Object?> event = message! as Map<Object?, Object?>;
      if (event['type'] == 'announce') {
        final Map<Object?, Object?> data =
            event['data']! as Map<Object?, Object?>;
        spoken.add(data['message']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return spoken;
}

void main() {
  group('every unavailable reading renders its own sentence', () {
    // ONE ROW PER RENDERED OUTCOME. Eight rows over seven enum members, because
    // malformedLength renders two ways on `availableLength`. Delete a row and
    // the coverage assertion at the bottom of this group fails.
    final List<(String, BssLoadUnavailable, String, String)> cases =
        <(String, BssLoadUnavailable, String, String)>[
          (
            'absent',
            const BssLoadUnavailable(BssLoadUnavailableReason.absent),
            'About this access point',
            'This access point does not advertise BSS Load.',
          ),
          (
            'noInformationElementsProvided',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.noInformationElementsProvided,
            ),
            'About this read',
            'This device gave us no information elements.',
          ),
          (
            'clippedWithoutSeeingElement11',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.clippedWithoutSeeingElement11,
            ),
            'About this read',
            'Our capture was cut short, and we saw no BSS Load element.',
          ),
          (
            'blobCompletenessNotStated',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.blobCompletenessNotStated,
            ),
            'About what we were told',
            'We were not told whether the capture was whole.',
          ),
          (
            'truncated',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.truncated,
              valueLength: 5,
              availableLength: 2,
            ),
            'About this read',
            'Our capture cut a BSS Load element short.',
          ),
          (
            'ciscoQbssVersion1',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.ciscoQbssVersion1,
              valueLength: 4,
            ),
            'About this read',
            'This build does not decode the Cisco QBSS variant.',
          ),
          (
            'malformedLength complete',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.malformedLength,
              valueLength: 7,
            ),
            'About this access point',
            'This access point sent a BSS Load element with a length it cannot '
                'have.',
          ),
          (
            'malformedLength clipped',
            const BssLoadUnavailable(
              BssLoadUnavailableReason.malformedLength,
              valueLength: 200,
              availableLength: 3,
            ),
            'About this read',
            'Our capture cut short an element we would have refused.',
          ),
        ];

    for (final (String name, BssLoadUnavailable reading, String eyebrow, String
        headline) in cases) {
      testWidgets('$name shows "$eyebrow" and its own headline', (
        WidgetTester tester,
      ) async {
        await _pump(tester, _FakeSource(_snapshot(reading)));

        expect(find.text(headline), findsOneWidget, reason: name);
        expect(find.text(eyebrow), findsOneWidget, reason: name);

        // AND NO OTHER READING'S HEADLINE. This is the assertion that fails when
        // the seven collapse into one: a screen rendering a generic sentence
        // would satisfy the two expects above for exactly one row and fail the
        // rest, but a screen rendering the WRONG specific sentence would pass
        // them and fail here.
        for (final (String other, BssLoadUnavailable r, _, String h)
            in cases) {
          if (other == name) continue;
          if (h == headline) continue;
          expect(
            find.text(h),
            findsNothing,
            reason: '$name also rendered the headline for $other '
                '(reason ${r.reason.name})',
          );
        }
      });
    }

    test('the table covers every decoder reason', () {
      final Set<BssLoadUnavailableReason> covered = cases
          .map(
            ((String, BssLoadUnavailable, String, String) c) => c.$2.reason,
          )
          .toSet();
      expect(
        covered,
        BssLoadUnavailableReason.values.toSet(),
        reason: 'a decoder reason is never pumped through the widget tree',
      );
      expect(
        cases.length,
        greaterThan(BssLoadUnavailableReason.values.length),
        reason: 'malformedLength must render two ways',
      );
    });

    test('every eyebrow in the table is a real attribution label', () {
      // The eyebrows above are literals. Without this they could drift into
      // strings no attribution actually produces, and the widget assertions
      // would then be checking the test's imagination.
      final Set<String> real = BssLoadAttribution.values
          .map((BssLoadAttribution a) => a.label)
          .toSet();
      for (final (String name, _, String eyebrow, _) in cases) {
        expect(real, contains(eyebrow), reason: name);
      }
      expect(
        cases.map(((String, BssLoadUnavailable, String, String) c) => c.$3)
            .toSet(),
        real,
        reason: 'the widget table must exercise all three attributions',
      );
    });
  });

  group('a decoded reading', () {
    testWidgets('renders each number beside the wire value it came from', (
      WidgetTester tester,
    ) async {
      // 120/255 -> 47.1%; 8000 raw -> 25.6% and 256000 us/s.
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 10,
                rawChannelUtilization: 120,
                rawAdmissionCapacity: 8000,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Associated stations'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);

      expect(find.text('Channel utilization'), findsOneWidget);
      expect(find.text('47.1%'), findsOneWidget);
      // [[feedback_a_derived_value_in_quotation_position]]: the conversion is
      // ours, the octet is theirs, and both are on screen.
      expect(find.text('120 of 255 on the wire'), findsOneWidget);

      expect(find.text('Available admission capacity'), findsOneWidget);
      expect(find.text('25.6%'), findsOneWidget);
      expect(find.text('256000 µs/s, raw 8000'), findsOneWidget);

      // No unavailable furniture anywhere near a real reading.
      expect(find.text('About this read'), findsNothing);
      expect(find.text('About this access point'), findsNothing);
    });

    testWidgets('an all-zero reading renders zeros, never an absence', (
      WidgetTester tester,
    ) async {
      // An idle access point on a quiet channel is a REAL measurement. This is
      // the test that fails if somebody "helpfully" treats 0 as missing.
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 0,
                rawChannelUtilization: 0,
                rawAdmissionCapacity: 0,
              ),
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('0.0%'), findsNWidgets(2));
      expect(find.text('0 of 255 on the wire'), findsOneWidget);
      expect(find.text('0 µs/s, raw 0'), findsOneWidget);

      // The canonical missing-value treatments must be absent.
      expect(find.text('Not available on this platform'), findsNothing);
      expect(find.textContaining('does not advertise'), findsNothing);
    });

    testWidgets('an out-of-range admission capacity is flagged, not capped', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 1,
                rawChannelUtilization: 10,
                rawAdmissionCapacity: 31251,
              ),
            ),
          ),
        ),
      );

      // A verdict WORD, never color alone (WCAG 2.2 SC 1.4.1).
      expect(find.byType(StatusChip), findsOneWidget);
      expect(find.text('Above full scale'), findsOneWidget);
      // Shown as read: 31251 * 32, not clamped to a round million.
      expect(find.text('1000032 µs/s, raw 31251'), findsOneWidget);
    });

    testWidgets('an in-range admission capacity carries no chip', (
      WidgetTester tester,
    ) async {
      // The counterweight. Without it the chip could render always and the test
      // above would still pass.
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 1,
                rawChannelUtilization: 10,
                rawAdmissionCapacity: 31250,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(StatusChip), findsNothing);
      expect(find.text('Above full scale'), findsNothing);
    });

    testWidgets('no verdict is computed about the load itself', (
      WidgetTester tester,
    ) async {
      // The decoder returns numbers and one out-of-range flag. A busy-channel
      // grade would be a judgement wearing a measurement's clothes, so a
      // saturated channel with many stations must still show no verdict word.
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 250,
                rawChannelUtilization: 255,
                rawAdmissionCapacity: 0,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(StatusChip), findsNothing);
      for (final String word in const <String>[
        'Good',
        'Issue',
        'Worth a look',
        'Poor',
        'Congested',
        'Busy',
      ]) {
        expect(find.text(word), findsNothing, reason: 'invented verdict "$word"');
      }
      expect(find.text('100.0%'), findsOneWidget);
    });
  });

  group('the BSSID line', () {
    testWidgets('shows which BSS the bytes belonged to when one is known', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 1,
                rawChannelUtilization: 1,
                rawAdmissionCapacity: 1,
              ),
            ),
            bssid: 'aa:bb:cc:dd:ee:ff',
          ),
        ),
      );
      expect(find.text('BSSID aa:bb:cc:dd:ee:ff'), findsOneWidget);
    });

    testWidgets('is absent, never invented, when no match was made', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadUnavailable(BssLoadUnavailableReason.absent),
          ),
        ),
      );
      expect(find.textContaining('BSSID'), findsNothing);
    });
  });

  group('the octet diagnostic is labeled as ours', () {
    testWidgets('a truncated reading prints declared and arrived counts', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadUnavailable(
              BssLoadUnavailableReason.truncated,
              valueLength: 5,
              availableLength: 2,
            ),
          ),
        ),
      );
      expect(
        find.textContaining('What our read saw: Element 11 declared 5 value '
            'octets, and 2 octets arrived'),
        findsOneWidget,
      );
    });

    testWidgets('a reading that saw no element 11 prints no counts', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadUnavailable(
              BssLoadUnavailableReason.clippedWithoutSeeingElement11,
            ),
          ),
        ),
      );
      expect(find.textContaining('What our read saw'), findsNothing);
    });
  });

  group('the Location remedy', () {
    BssLoadSnapshot noIes(LocationAuthStatus? auth, {bool exposes = true}) =>
        _snapshot(
          const BssLoadUnavailable(
            BssLoadUnavailableReason.noInformationElementsProvided,
          ),
          context: BssLoadReadContext(
            platformExposesInformationElements: exposes,
            locationAuth: auth,
          ),
        );

    testWidgets('notDetermined offers the prompt', (WidgetTester tester) async {
      await _pump(
        tester,
        _FakeSource(noIes(LocationAuthStatus.notDetermined)),
      );
      expect(find.text('Grant Location access'), findsOneWidget);
      expect(find.text('Open Location settings'), findsNothing);
    });

    for (final LocationAuthStatus blocked in <LocationAuthStatus>[
      LocationAuthStatus.denied,
      LocationAuthStatus.restricted,
    ]) {
      testWidgets('${blocked.name} offers settings, never a dead prompt', (
        WidgetTester tester,
      ) async {
        // macOS raises no prompt after a denial. A Grant button here would be a
        // control guaranteed to do nothing
        // ([[feedback_ui_rendered_a_decision_it_lacked]]).
        await _pump(tester, _FakeSource(noIes(blocked)));
        expect(find.text('Open Location settings'), findsOneWidget);
        expect(find.text('Grant Location access'), findsNothing);
      });
    }

    testWidgets('authorized offers nothing to press', (
      WidgetTester tester,
    ) async {
      await _pump(tester, _FakeSource(noIes(LocationAuthStatus.authorized)));
      expect(find.text('Grant Location access'), findsNothing);
      expect(find.text('Open Location settings'), findsNothing);
    });

    testWidgets('a platform without information elements says so, and offers '
        'no Location action', (WidgetTester tester) async {
      await _pump(
        tester,
        _FakeSource(noIes(null, exposes: false)),
      );
      expect(find.textContaining('macOS is the only platform'), findsOneWidget);
      expect(find.text('Grant Location access'), findsNothing);
      expect(find.text('Open Location settings'), findsNothing);
    });
  });

  group('loading, error and the disabled affordances', () {
    testWidgets('a read in flight shows progress and disables Read again', (
      WidgetTester tester,
    ) async {
      final _HangingSource source = _HangingSource();
      await tester.pumpWidget(_wrap(source));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Read again'),
      );
      expect(button.onPressed, isNull, reason: 'a second read would race');

      // Let it finish so the test tears down cleanly.
      source.completer.complete(
        _snapshot(const BssLoadUnavailable(BssLoadUnavailableReason.absent)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a settled read re-enables Read again and reads again', (
      WidgetTester tester,
    ) async {
      final _FakeSource source = _FakeSource(
        _snapshot(const BssLoadUnavailable(BssLoadUnavailableReason.absent)),
      );
      await _pump(tester, source);
      expect(source.reads, 1, reason: 'the screen snapshots on open');

      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Read again'),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Read again'));
      await tester.pumpAndSettle();
      expect(source.reads, 2);
    });

    testWidgets('a throwing source renders the error state, not a false '
        'reading', (WidgetTester tester) async {
      await _pump(tester, _ThrowingSource());
      expect(find.text('The read did not complete'), findsOneWidget);
      expect(find.textContaining('channel exploded'), findsOneWidget);
      // AND NOT AN ANSWER. A failed read is the absence of a finding, never a
      // finding of absence ([[feedback_blanking_reads_as_absence]]).
      expect(find.text('This access point does not advertise BSS Load.'),
          findsNothing);
      expect(find.text('About this access point'), findsNothing);
    });

    testWidgets('copy is disabled until a read produces something', (
      WidgetTester tester,
    ) async {
      final _HangingSource source = _HangingSource();
      await tester.pumpWidget(_wrap(source));
      await tester.pump();
      expect(
        tester.widget<AppCopyAction>(find.byType(AppCopyAction))
            .textBuilder(),
        isNull,
      );

      source.completer.complete(
        _snapshot(const BssLoadUnavailable(BssLoadUnavailableReason.absent)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AppCopyAction>(find.byType(AppCopyAction))
            .textBuilder(),
        isNotNull,
      );
    });
  });

  group('the copied text keeps the attribution', () {
    testWidgets('an unavailable reading exports its eyebrow and headline', (
      WidgetTester tester,
    ) async {
      // A paste that dropped the attribution would be the collapse this screen
      // refuses, happening one clipboard later.
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadUnavailable(
              BssLoadUnavailableReason.clippedWithoutSeeingElement11,
            ),
          ),
        ),
      );
      final String? text = tester
          .widget<AppCopyAction>(find.byType(AppCopyAction))
          .textBuilder();
      expect(text, contains('About this read'));
      expect(
        text,
        contains(
          'Our capture was cut short, and we saw no BSS Load element.',
        ),
      );
      expect(text, isNot(contains('does not advertise')));
    });

    testWidgets('a decoded reading exports the numbers and their wire values', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 10,
                rawChannelUtilization: 120,
                rawAdmissionCapacity: 8000,
              ),
            ),
            bssid: 'aa:bb:cc:dd:ee:ff',
          ),
        ),
      );
      final String? text = tester
          .widget<AppCopyAction>(find.byType(AppCopyAction))
          .textBuilder();
      expect(text, contains('BSSID: aa:bb:cc:dd:ee:ff'));
      expect(text, contains('Associated stations: 10'));
      expect(text, contains('47.1% (120 of 255 on the wire)'));
      expect(text, contains('256000 µs/s, raw 8000'));
    });
  });

  group('the finished read is announced (WCAG 2.2 SC 4.1.3)', () {
    // THE PROGRESS BAR'S LIVE REGION LEAVES THE TREE WHEN THE READ LANDS, so
    // without a one-shot announcement an assistive-technology user hears the
    // read begin and then hears nothing: no result, no error, and above all no
    // attribution, which is the entire product of this screen. Every assertion
    // below fails on a build with no `SemanticsService.sendAnnouncement`.

    testWidgets('an unavailable reading speaks its attribution and headline', (
      WidgetTester tester,
    ) async {
      final List<String> spoken = _captureAnnouncements(tester);
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadUnavailable(
              BssLoadUnavailableReason.clippedWithoutSeeingElement11,
            ),
          ),
        ),
      );
      expect(spoken, hasLength(1));
      expect(spoken.single, contains('About this read'));
      expect(
        spoken.single,
        contains('Our capture was cut short, and we saw no BSS Load element.'),
      );
      // An announcement that dropped the attribution and kept only the sentence
      // would let the spoken screen claim more than the printed one.
      expect(spoken.single, isNot(contains('does not advertise')));
    });

    testWidgets('the one access-point claim is spoken as such', (
      WidgetTester tester,
    ) async {
      final List<String> spoken = _captureAnnouncements(tester);
      await _pump(
        tester,
        _FakeSource(
          _snapshot(const BssLoadUnavailable(BssLoadUnavailableReason.absent)),
        ),
      );
      expect(spoken, hasLength(1));
      expect(spoken.single, startsWith('About this access point.'));
      expect(
        spoken.single,
        contains('This access point does not advertise BSS Load.'),
      );
    });

    testWidgets('a decoded reading speaks the three numbers', (
      WidgetTester tester,
    ) async {
      final List<String> spoken = _captureAnnouncements(tester);
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 10,
                rawChannelUtilization: 120,
                rawAdmissionCapacity: 8000,
              ),
            ),
          ),
        ),
      );
      expect(spoken, hasLength(1));
      expect(spoken.single, contains('Advertised by this access point'));
      expect(spoken.single, contains('Associated stations 10'));
      expect(spoken.single, contains('Channel utilization 47.1%'));
      expect(spoken.single, contains('Available admission capacity 25.6%'));
      expect(spoken.single, isNot(contains('above full scale')));
    });

    testWidgets('an above-full-scale reading says so out loud too', (
      WidgetTester tester,
    ) async {
      // The chip is the only thing that carries this on screen, and a chip is
      // not spoken by a result announcement unless it is put there.
      final List<String> spoken = _captureAnnouncements(tester);
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 0,
                rawChannelUtilization: 0,
                rawAdmissionCapacity: 65535,
              ),
            ),
          ),
        ),
      );
      expect(spoken, hasLength(1));
      expect(
        spoken.single,
        contains('Admission capacity is above full scale'),
      );
    });

    testWidgets('a failed read is announced, not left silent', (
      WidgetTester tester,
    ) async {
      final List<String> spoken = _captureAnnouncements(tester);
      await _pump(tester, _ThrowingSource());
      expect(spoken, hasLength(1));
      expect(spoken.single, startsWith('The read did not complete.'));
      expect(spoken.single, contains('channel exploded'));
    });

    testWidgets('Read again announces a second time', (
      WidgetTester tester,
    ) async {
      // The finding was raised against this exact interaction: activate the
      // button, hear the read start, hear nothing after.
      final List<String> spoken = _captureAnnouncements(tester);
      await _pump(
        tester,
        _FakeSource(
          _snapshot(const BssLoadUnavailable(BssLoadUnavailableReason.absent)),
        ),
      );
      expect(spoken, hasLength(1));
      await tester.tap(find.widgetWithText(FilledButton, 'Read again'));
      await tester.pumpAndSettle();
      expect(spoken, hasLength(2));
      expect(spoken.last, spoken.first);
    });
  });

  group('accessibility and layout', () {
    testWidgets('headlines are exposed as headers to assistive tech', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadUnavailable(BssLoadUnavailableReason.absent),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('This access point does not advertise BSS Load.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a number row is announced with its label and wire value', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        _FakeSource(
          _snapshot(
            const BssLoadDecoded(
              BssLoad(
                stationCount: 10,
                rawChannelUtilization: 120,
                rawAdmissionCapacity: 8000,
              ),
            ),
          ),
        ),
      );
      // A screen-reader user gets the conversion AND the evidence, which is the
      // same contract the sighted layout keeps.
      expect(
        find.bySemanticsLabel(
          'Channel utilization, 47.1%, 120 of 255 on the wire',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('no overflow across breakpoints, dark and light', (
      WidgetTester tester,
    ) async {
      // The longest copy on the screen: the malformedLength complete headline
      // plus its paragraph plus an octet diagnostic.
      final _FakeSource source = _FakeSource(
        _snapshot(
          const BssLoadUnavailable(
            BssLoadUnavailableReason.malformedLength,
            valueLength: 7,
          ),
          bssid: 'aa:bb:cc:dd:ee:ff',
        ),
      );
      for (final bool light in const <bool>[false, true]) {
        for (final Size size in const <Size>[
          Size(320, 720), // narrow phone stress
          Size(390, 844), // iPhone
          Size(768, 1024), // tablet
          Size(1280, 900), // desktop
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          await _pump(tester, source, light: light);
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at $size (light=$light)',
          );
        }
      }
    });

    testWidgets('the decoded card also survives every breakpoint', (
      WidgetTester tester,
    ) async {
      final _FakeSource source = _FakeSource(
        _snapshot(
          const BssLoadDecoded(
            BssLoad(
              stationCount: 65535,
              rawChannelUtilization: 255,
              rawAdmissionCapacity: 65535,
            ),
          ),
          bssid: 'aa:bb:cc:dd:ee:ff',
        ),
      );
      for (final bool light in const <bool>[false, true]) {
        for (final Size size in const <Size>[
          Size(320, 720),
          Size(390, 844),
          Size(768, 1024),
          Size(1280, 900),
        ]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          await _pump(tester, source, light: light);
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at $size (light=$light)',
          );
        }
      }
    });
  });
}
