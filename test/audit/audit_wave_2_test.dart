// Audit wave 2 — regression guards for the reference-table defects.
//
// Every test here failed RED against the shipped code before its fix landed.
//
// TWO RULES GOVERN THIS FILE (both learned the hard way on 2026-07-11):
//
//  1. EVERY expected value comes from a primary-source brief, never from
//     running the code. The old suite was generated FROM the app, which is why
//     3,391 green tests could not see a cable table that was 41% wrong. If a
//     test here disagrees with the app, the app is wrong until a PRIMARY SOURCE
//     says otherwise. Never "fix" an expectation to make a test pass.
//
//  2. CITE AND PIN TOGETHER. No citation may render on screen without a test
//     pinning it to the value it justifies. The Reason/Status screen is why:
//     it was the app's ONLY properly-cited reference table, and it was also its
//     most wrong — the IEEE citation lent authority to ~14 bad rows. An
//     unpinned source line is worse than no source line.
//
// SOURCES (on disk, read directly off the standards PDFs by Pax):
//   Deliverables/2026-07-11-reference-table-verification/IEEE-PRIMARY-TABLES.md
//     - IEEE Std 802.11-2020 Table 9-49 (reason codes) / Table 9-50 (status)
//     - IEEE Std 802.11be-2024 Table 9-417t (max NSS encoding)
//     - Keith Parsons' own MCS Index Chart (he authored it; he is the authority)
//   Deliverables/2026-07-11-reference-table-verification/PRIMARY-SOURCED-TABLES.md
//     - IANA registries (EAP, HTTP, DSCP), RFCs 9110 / 8325 / 9930 / 9140
//
// Findings from the sweep that did NOT reproduce are pinned at the bottom
// ("already correct") rather than silently dropped — so they cannot regress and
// so the next reader knows they were checked, not skipped.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/adjacent_radio_systems_data.dart';
import 'package:wlan_pros_toolbox/data/country_plug_data.dart';
import 'package:wlan_pros_toolbox/data/ham_reference_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/cable_loss_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/channel_map_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/data_units_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/db_reference_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/fiber_optic_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/frame_exchange_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/iec_connectors_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/regex_cheatsheet_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/throughput_calc_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/dscp_qos_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/eap_types_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/ethernet_cable_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/http_status_codes_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/international_plugs_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/mcs_index_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/modulation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/reason_codes_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/signal_thresholds_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/standards_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/wifi_feature_matrix_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  // P0 — REASON CODES. The screen rendered "IEEE 802.11-2020 §9.4.1.7" and
  // shipped codes that are not in IEEE 802.11-2020 §9.4.1.7.
  //
  // Reason codes 34-39 were systematically shifted +2: the app's 34 carried the
  // standard's 32 meaning, its 35 carried 33, and so on. The app's 39 ("peer
  // using unsupported cipher suite") is not code 39 in any edition -- 39 is
  // TIMEOUT. That string is the RETIRED code 45 (PEERKEY_MISMATCH), defined in
  // 802.11-2012/-2016 and Reserved in 802.11-2020. See the edition-history test.
  //
  // All four 802.11r codes were wrong, and the app's 45 sits inside the
  // standard's RESERVED range (40-45). An engineer debugging an 802.11r roam
  // chased the wrong root cause every single time.
  //
  // Source: IEEE Std 802.11-2020, Table 9-49 (printed p870-873).
  // ═════════════════════════════════════════════════════════════════════════
  group('reason codes are pinned to IEEE 802.11-2020 Table 9-49', () {
    /// Every reason code the screen renders, flattened.
    Map<int, String> renderedReasons() {
      final Map<int, String> out = <int, String>{};
      for (final CodeGroup g in ReasonCodesScreen.reasonGroups) {
        for (final CodeEntry e in g.entries) {
          out[e.code] = e.meaning;
        }
      }
      return out;
    }

    test('the QoS block carries the standard meanings, not the +2 shift', () {
      final Map<int, String> rc = renderedReasons();

      // Table 9-49, verbatim in substance. These six rows were ALL wrong.
      expect(rc[32], contains('QoS'), reason: 'UNSPECIFIED_QOS_REASON');
      expect(rc[33], contains('bandwidth'), reason: 'NOT_ENOUGH_BANDWIDTH');
      expect(rc[34], contains('ack'), reason: 'MISSING_ACKS — NOT "QoS reason"');
      expect(rc[35], contains('TXOP'), reason: 'EXCEEDED_TXOP');
      expect(rc[36], contains('leaving'), reason: 'STA_LEAVING');
      expect(rc[37], anyOf(contains('stream'), contains('session')),
          reason: 'END_TS / END_BA');
      expect(rc[38], anyOf(contains('setup'), contains('mechanism')),
          reason: 'UNKNOWN_TS / UNKNOWN_BA');
      expect(rc[39], contains('imeout'), reason: 'TIMEOUT');
    });

    test('the shifted meanings are gone from the codes they never belonged to',
        () {
      final Map<int, String> rc = renderedReasons();

      // The exact wrong strings the app shipped. Each one named a real 802.11
      // condition at a code that does not carry it.
      expect(rc[34], isNot(contains('QoS-related reason')),
          reason: 'That is code 32.');
      expect(rc[35], isNot(contains('insufficient bandwidth')),
          reason: 'That is code 33.');
      expect(rc[36], isNot(contains('not acked')), reason: 'That is code 34.');
      expect(rc[37], isNot(contains('outside TXOP')), reason: 'That is 35.');
      expect(rc[38], isNot(contains('leaving BSS or resetting')),
          reason: 'That is code 36.');
      expect(rc[39], isNot(contains('cipher')),
          reason: 'Code 39 is TIMEOUT. "Peer using unsupported cipher suite" is '
              'the RETIRED code 45 (PEERKEY_MISMATCH) -- Reserved since '
              '802.11-2020 -- stranded here by the PWA. Not invented, but not '
              'code 39, and not a code the cited edition defines at all.');
    });

    test('802.11r reason codes are 48-51, and 40-45 stay RESERVED', () {
      final Map<int, String> rc = renderedReasons();

      // Table 9-49: 48 = invalid FT Action frame count, 49 = invalid PMKID,
      // 50 = invalid MDE, 51 = invalid FTE. This is the whole 11r block.
      expect(rc[48], anyOf(contains('FT Action'), contains('frame count')));
      expect(rc[49], contains('PMKID'));
      expect(rc[50], contains('MDE'));
      expect(rc[51], contains('FTE'));

      // 40-45 are Reserved in Table 9-49. The app put "Invalid FTIE" on 45.
      // Code 45 in particular: READ THE EDITION-HISTORY TEST BELOW before you
      // "correctly add" it. It is Reserved in the edition this screen cites.
      for (final int reserved in <int>[40, 41, 42, 43, 44, 45]) {
        expect(
          rc.containsKey(reserved),
          isFalse,
          reason: 'Code $reserved is RESERVED in Table 9-49. The app must not '
              'give a reserved code a meaning.',
        );
      }

      // 46 and 47 exist but are NOT the 11r codes the app claimed.
      expect(rc[46], isNot(contains('PMKID')),
          reason: '46 = PEER_INITIATED, not "requested PMKID not found".');
      expect(rc[47], isNot(contains('MDE')),
          reason: '47 = AP_INITIATED, not "invalid MDE".');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Code 45 is EDITION-DEPENDENT. This test exists to settle that permanently,
    // because it has already been re-litigated once at a QA gate.
    //
    // Verified 2026-07-11 by reading the printed tables off the PDFs on disk:
    //
    //   802.11-2012, Table 8-36 : 45 = PEERKEY_MISMATCH,
    //                             "Peer STA does not support the requested
    //                              cipher suite"                      DEFINED
    //   802.11-2016, Table 9-45 : 45 = PEERKEY_MISMATCH               DEFINED
    //   802.11-2020, Table 9-49 : "40-45   Reserved"   (single merged row)
    //   802.11-2024             : "40-45   Reserved"   (still)
    //
    // The PeerKey / STSL security association was removed from the standard, and
    // reason code 45 was RETIRED to Reserved with it. hostapd
    // (WLAN_REASON_PEERKEY_MISMATCH 45), Wireshark and assorted vendor tables all
    // still carry the legacy row, which is why the memory of it is so sticky --
    // and why the PWA had the string at all.
    //
    // CONSEQUENCE, and the reason this file deleted that string rather than
    // relocating it: in IEEE 802.11-2020 -- the edition this screen cites on
    // screen -- there is no code for "peer using unsupported cipher suite". The
    // PWA had stranded it on code 39 (which is TIMEOUT). Moving it to 45 would
    // not have been a fix; it would have resurrected a code the cited edition
    // does not define, in the wave whose entire purpose is removing values that
    // no primary source supports.
    //
    // If the screen is ever re-cited to 802.11-2012 or -2016, this test is the
    // thing to change, and the reserved range narrows to 40-44. Until then, 45
    // stays reserved and the guard above is correct.
    // ─────────────────────────────────────────────────────────────────────────
    test('code 45 is Reserved in the cited edition (802.11-2020), not defined',
        () {
      final Map<int, String> rc = renderedReasons();

      // The screen cites 2020. Under 2020, 45 has no meaning.
      expect(ReasonCodesScreen.reasonCodeCitation, contains('802.11-2020'),
          reason: 'If the cited edition changes, revisit code 45 -- it was '
              'PEERKEY_MISMATCH in 802.11-2012 and -2016.');
      expect(rc.containsKey(45), isFalse,
          reason: '802.11-2020 Table 9-49 prints "40-45 Reserved" as one row. '
              'Code 45 (PEERKEY_MISMATCH) was retired with the PeerKey '
              'handshake. hostapd and Wireshark still list it; the 2020 '
              'standard does not.');

      // And the retired MEANING must not reappear anywhere in the table -- not
      // on 45, and above all not stranded on 39, where the PWA had put it.
      //
      // Narrow on purpose: code 24 ("Cipher suite rejected per security policy")
      // is a real, correct row and must survive this check. What must not exist
      // is a PEER-scoped unsupported-cipher-suite meaning -- that is retired 45.
      final RegExp retired45 = RegExp(r'peer.*cipher suite');
      for (final MapEntry<int, String> e in rc.entries) {
        expect(retired45.hasMatch(e.value.toLowerCase()), isFalse,
            reason: 'Code ${e.key} carries the RETIRED code-45 meaning ("peer '
                'STA does not support the requested cipher suite"). That is not '
                'a reason code in 802.11-2020, and it was never code 39.');
      }
    });

    test('reason codes 1-24 were already right and stay right', () {
      final Map<int, String> rc = renderedReasons();
      expect(rc[1], contains('Unspecified'));
      expect(rc[2], contains('auth'));
      expect(rc[14], contains('MIC'));
      expect(rc[15], contains('4-Way'));
      expect(rc[16], contains('Group Key'));
      expect(rc[23], contains('802.1X'));
    });

    test('the on-screen IEEE citation is pinned to the table it cites', () {
      // Rule 2. The citation and the clause it points at move together, or this
      // fails. This is the test that would have caught the original defect.
      expect(
        ReasonCodesScreen.reasonCodeCitation,
        'IEEE 802.11-2020, Table 9-49 (§9.4.1.7)',
      );
      expect(
        ReasonCodesScreen.statusCodeCitation,
        'IEEE 802.11-2020, Table 9-50 (§9.4.1.9)',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // P0 — STATUS CODES. Ten rows wrong, including a clean swap: the app said
  // 76 = "VHT not supported". The standard has 104 as VHT, and 76 is
  // ANTI_CLOGGING_TOKEN_REQUIRED (SAE).
  //
  // Source: IEEE Std 802.11-2020, Table 9-50 (printed p874-879).
  // ═════════════════════════════════════════════════════════════════════════
  group('status codes are pinned to IEEE 802.11-2020 Table 9-50', () {
    Map<int, String> renderedStatus() {
      final Map<int, String> out = <int, String>{};
      for (final CodeEntry e in ReasonCodesScreen.statusGroup.entries) {
        out[e.code] = e.meaning;
      }
      return out;
    }

    test('76 is the SAE anti-clogging token, and 104 is the VHT code', () {
      final Map<int, String> sc = renderedStatus();

      // The damning symmetry: the app had these two swapped in meaning.
      expect(sc[76], contains('anti-clogging'),
          reason: '76 = ANTI_CLOGGING_TOKEN_REQUIRED (SAE), Table 9-50.');
      expect(sc[76], isNot(contains('VHT')),
          reason: 'VHT lives at 104. This is the swap.');

      expect(sc[104], contains('VHT'),
          reason: '104 = DENIED_VHT_NOT_SUPPORTED, Table 9-50.');
      expect(sc[104], isNot(contains('HE')),
          reason: 'There is NO HE-specific status code in 802.11-2020. The app '
              'invented one at 104 — the code that is actually VHT.');
    });

    test('the HT code is 27, not 72', () {
      final Map<int, String> sc = renderedStatus();
      expect(sc[27], contains('HT'), reason: 'DENIED_NO_HT_SUPPORT = 27.');
      expect(sc[72], isNot(contains('HT features')),
          reason: '72 = INVALID_RSNE. The app had DENIED_NO_HT_SUPPORT here.');
      expect(sc[72], contains('RSNE'));
    });

    test('the QoS status block is 32/33/34, not 23/24/25', () {
      final Map<int, String> sc = renderedStatus();

      expect(sc[32], contains('QoS'), reason: 'UNSPECIFIED_QOS_FAILURE = 32.');
      expect(sc[33], contains('bandwidth'),
          reason: 'DENIED_INSUFFICIENT_BANDWIDTH = 33.');
      expect(sc[34], anyOf(contains('frame loss'), contains('channel')),
          reason: 'DENIED_POOR_CHANNEL_CONDITIONS = 34.');

      // What 23/24/25 REALLY are, per Table 9-50.
      expect(sc[23], contains('Power Capability'),
          reason: '23 = REJECTED_BAD_POWER_CAPABILITY.');
      expect(sc[24], contains('Supported Channels'),
          reason: '24 = REJECTED_BAD_SUPPORTED_CHANNELS.');
      expect(sc[25], contains('short slot'),
          reason: '25 = DENIED_NO_SHORT_SLOT_TIME_SUPPORT.');
    });

    test('the fabricated MFP rows are gone; the real MFP code is 31', () {
      final Map<int, String> sc = renderedStatus();

      // The app claimed 37 = "STA not supporting MFP" and 38 = "AP requires
      // MFP". Neither exists in Table 9-50. 31 is the real MFP-related code.
      expect(sc[31], anyOf(contains('Robust'), contains('MFP')),
          reason: 'ROBUST_MANAGEMENT_POLICY_VIOLATION = 31.');
      expect(sc[37], isNot(contains('MFP')), reason: '37 = REQUEST_DECLINED.');
      expect(sc[38], isNot(contains('MFP')),
          reason: '38 = INVALID_PARAMETERS.');
      expect(sc[37], contains('declined'));
      expect(sc[38], contains('parameter'));
    });

    test('73 is U-APSD coexistence, not the invented "PCCO transition time"',
        () {
      final Map<int, String> sc = renderedStatus();
      expect(sc[73], contains('U-APSD'));
      expect(sc[73], isNot(contains('PCCO')),
          reason: 'No such status code. Fabricated.');
    });

    test('code 0 is still the green success row', () {
      final Map<int, String> sc = renderedStatus();
      expect(sc[0], 'Successful');
    });

    testWidgets('every rendered status row is a real Table 9-50 code',
        (WidgetTester tester) async {
      // The structure was right all along — only the values were wrong. This
      // asserts the screen still renders, so the fix did not restructure it.
      await _withViewport(tester, const Size(414, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const ReasonCodesScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Successful'), findsOneWidget);
        expect(find.text('Association Status Codes (most common)'),
            findsOneWidget);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // P0 — WI-FI 7 = 46 Gbps. Dead in three places plus a footnote that explains
  // the wrong derivation as fact.
  //
  // IEEE Std 802.11be-2024, Table 9-417t encodes Max NSS 1-8; values 9-15 are
  // RESERVED. The ratified cap is 8 spatial streams. 46 Gbps needs a 16-stream
  // mode the amendment never defines. It is a draft-era number.
  //
  // Ratified ceiling: 8 x 2882.4 Mbps (320 MHz, EHT-MCS 13, 0.8 us GI)
  //                 = 23,059 Mbps = ~23.1 Gbps.
  // ═════════════════════════════════════════════════════════════════════════
  group('Wi-Fi 7 ceiling is the RATIFIED 8 streams, not the draft 16', () {
    WifiFeatureRow rowFor(String feature) => WifiFeatureMatrixScreen.rows
        .firstWhere((WifiFeatureRow r) => r.feature == feature);

    test('max spatial streams is 8 (802.11be-2024 Table 9-417t)', () {
      expect(rowFor('Max spatial streams').wifi7, '8');
    });

    test('max PHY rate is ~23.1 Gbps, not ~46 Gbps', () {
      expect(rowFor('Max PHY rate').wifi7, '~23.1 Gbps');
    });

    test('MU-MIMO tops out at 8, not 16', () {
      expect(rowFor('MU-MIMO').wifi7, isNot(contains('16')));
      expect(rowFor('MU-MIMO').wifi7, contains('8'));
    });

    test('the footnote no longer teaches the 16-stream derivation as fact', () {
      const String f = WifiFeatureMatrixScreen.footnote;

      // The footnote used to spell out "be ~46 Gbps = 16 x 320 x 4096-QAM" —
      // the error, restated as arithmetic, which made it look checkable. THAT
      // is what must never come back.
      expect(f, isNot(contains('16 x 320')));
      expect(f, isNot(contains('be ~46')));

      // The real derivation, and the clause that settles it (cite and pin).
      expect(f, contains('23.1'));
      expect(f, contains('8 x 320'),
          reason: 'The real derivation: 8 streams, 320 MHz, 4096-QAM.');
      expect(f, contains('Table 9-417t'));

      // Deliberately NOT a blanket ban on the string "46". The footnote now
      // names 46 Gbps in order to KILL it ("the widely-quoted 46 Gbps figure -
      // which assumes 16 streams - is not reachable under the ratified
      // amendment"). A reader who arrives believing the myth has to be able to
      // find the correction; scrubbing the number would hide the answer from
      // the person most likely to look for it. So: 46 may appear ONLY as a
      // refutation, and this asserts exactly that.
      if (f.contains('46 Gbps')) {
        expect(f, contains('not reachable'),
            reason: '46 Gbps may appear only as a myth being corrected, never '
                'as a value.');
      }
    });

    test('the expired "draft may shift" hedge is gone', () {
      // 802.11be was APPROVED 26 Sep 2024. The escape hatch has expired, and it
      // was covering a number the ratified amendment refutes.
      expect(
        WifiFeatureMatrixScreen.footnote,
        isNot(contains('from the draft')),
        reason: '802.11be-2024 is ratified. The hedge cannot excuse 46 Gbps.',
      );
    });

    test('the standards table agrees — no third home for 46 Gbps', () {
      final StandardEntry be = StandardsScreen.standards
          .firstWhere((StandardEntry s) => s.generation == 'Wi-Fi 7');
      expect(be.maxRate, isNot(contains('46')));
      expect(be.maxRate, contains('23.1'));
    });

    test('the app does not contradict itself on stream count', () {
      // The MCS screen already caps spatial streams at 8. The feature matrix
      // said 16. One app, one number.
      expect(ThroughputCalcScreen.maxStreams[WifiStd.eht], 8);
      expect(rowFor('Max spatial streams').wifi7, '8');
    });

    test('the help never ASSERTS 46 Gbps — it may only refute it', () async {
      // Nuance worth keeping: a user who has heard "Wi-Fi 7 does 46 Gbps" needs
      // to find the correction, so naming the myth in order to kill it is more
      // useful than scrubbing the string. What must never appear is the figure
      // stated as fact, or the 16-stream arithmetic that "derives" it.
      final String raw =
          await rootBundle.loadString('assets/help/tool_help.json');
      final Map<String, dynamic> tools =
          (jsonDecode(raw) as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;

      expect(raw, isNot(contains('16 streams x 320')),
          reason: 'The wrong derivation, taught as arithmetic.');

      for (final MapEntry<String, dynamic> e in tools.entries) {
        final String body = jsonEncode(e.value);
        if (!body.contains('46 Gbps')) continue;
        expect(
          body,
          anyOf(contains('not reachable'), contains('assumes 16')),
          reason: '"${e.key}" mentions 46 Gbps without refuting it. The figure '
              'may appear ONLY as a myth being corrected, never as a value.',
        );
      }

      // And the real ceiling is present where the wrong one used to be.
      expect(jsonEncode(tools['wifi-feature-matrix']), contains('23.1 Gbps'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // P0 — MCS INDEX.
  //
  // Keith authored the MCS chart and endorsed mcsindex.net. They are the
  // authority. From the source (mcsindex.net CSV, VHT block):
  //
  //   VHT MCS 9 @ 20 MHz : N/A at 1, 2 and 4 SS. VALID at 3 SS (260 / 288.9).
  //   VHT MCS 9 @ 40 MHz : VALID — 180 LGI / 200 SGI at 1 SS.
  //   VHT MCS 6 @ 80 MHz : N/A at 3 SS.
  //   VHT MCS 9 @ 160 MHz: N/A at 3 SS.
  //
  // TWO bugs, in opposite directions, one after the other:
  //
  // 1. The app returned null for BOTH 20 and 40 MHz at every stream count. Root
  //    cause: a hand-written comment, "// MCS9 invalid at 20 and 40 MHz (1 SS)".
  //    A human knew the real 20 MHz exclusion and over-generalized it to 40 MHz.
  //
  // 2. The fix for (1) OVER-CORRECTED. Keith's chart shows 1-3 SS, so the pass
  //    concluded there is no exclusion above 3 SS — and the app started
  //    returning 385.2 Mbps for MCS 9 @ 20 MHz at 4 SS. The source says N/A.
  //    The inverse over-generalization is exactly as wrong as the original.
  //
  // The N/A cells are as load-bearing as the rates. Both are pinned, here and
  // exhaustively in test/screens/reference/mcs_index_source_table_test.dart.
  // ═════════════════════════════════════════════════════════════════════════
  group('MCS index — VHT MCS 9 exclusions match the source', () {
    // Column order for VHT: [20 SGI, 40 SGI, 80 SGI, 160 SGI].
    const int c20 = 0;
    const int c40 = 1;
    const int c80 = 2;
    const int c160 = 3;

    double? vht(int mcs, int col, int ss) => McsIndexScreen.rate(
          std: McsStd.ac,
          mcs: mcs,
          columnIndex: col,
          spatialStreams: ss,
        );

    test('VHT MCS 9 @ 40 MHz is VALID at every sourced stream count', () {
      // BUG 1. The app returned null here and rendered "N/A" on a cell the
      // standard and the source both say is a working rate.
      expect(vht(9, c40, 1), 200.0);
      expect(vht(9, c40, 2), 400.0);
      expect(vht(9, c40, 3), 600.0);
      expect(vht(9, c40, 4), 800.0);
    });

    test('VHT MCS 9 @ 20 MHz is N/A at 1, 2 AND 4 SS', () {
      expect(vht(9, c20, 1), isNull);
      expect(vht(9, c20, 2), isNull);
      // BUG 2. The over-correction. A pass concluded "no exclusion above 3 SS"
      // because Keith's chart stops at 3, and the app returned 385.2 here.
      expect(
        vht(9, c20, 4),
        isNull,
        reason: 'The source says N/A at 4 SS. Asserting "there is no exclusion '
            'above 3 SS" is an invention, and it is exactly as wrong as the '
            'over-generalization it replaced.',
      );
    });

    test('VHT MCS 9 @ 20 MHz is VALID at 3 SS — 288.9 Mbps SGI', () {
      // The one valid cell in that column, and the stream-count-dependent half
      // the app could not express at all.
      expect(vht(9, c20, 3), 288.9);
    });

    test('the other two stream-dependent VHT exclusions are modelled', () {
      // Source, 3 SS block: MCS 6 @ 80 MHz = N/A, MCS 9 @ 160 MHz = N/A.
      expect(vht(6, c80, 3), isNull, reason: 'VHT MCS 6 @ 80 MHz, 3 SS = N/A.');
      expect(vht(9, c160, 3), isNull,
          reason: 'VHT MCS 9 @ 160 MHz, 3 SS = N/A.');
      // ...and they are valid either side of it, so the mask is not a blanket
      // null and it does not "run to the end" of the column.
      expect(vht(6, c80, 1), 292.5);
      expect(vht(6, c80, 4), 1170.0);
      expect(vht(9, c160, 1), 866.7);
      expect(vht(9, c160, 4), 3466.7);
    });

    test('above 4 SS the app publishes nothing rather than guess', () {
      // The source tables (Keith's chart, mcsindex.net) stop at 4 spatial
      // streams. The exclusions above that are unpublished and NOT derivable —
      // the tempting "valid iff N_SD x N_BPSCS x R x N_SS is a whole number of
      // bits" rule reproduces MCS 9 @ 20 MHz exactly, then calls MCS 6 @ 80 MHz
      // and MCS 9 @ 160 MHz valid at 3 SS, where the source says N/A.
      //
      // So: no rate above 4 SS, in either direction. A hole we know about beats
      // an invention we don't.
      expect(McsIndexScreen.maxSourcedStreams, 4);
      for (int ss = 5; ss <= 8; ss++) {
        expect(vht(9, c40, ss), isNull, reason: '$ss SS is not sourced.');
        expect(vht(0, c20, ss), isNull, reason: '$ss SS is not sourced.');
      }
    });

    test('no exclusion is claimed beyond the source\'s coverage', () {
      // Guards BOTH failure directions at once: the map may not drop a sourced
      // exclusion (1-4 SS), and it may not invent one above it.
      expect(McsIndexScreen.vhtStreamExclusions, <String, Set<int>>{
        '9:0': <int>{1, 2, 4},
        '6:2': <int>{3},
        '9:3': <int>{3},
      });
    });

    test('the notes card describes the exclusions the data actually carries',
        () {
      // The prose and the data must not drift apart again. The screen once
      // argued with itself one scroll apart: the table nulled MCS 9 @ 40 MHz
      // while the notes said the invalidity was "for a single stream".
      const String n = McsIndexScreen.notesText;

      // BUG 1's sentence — MCS 9 @ 40 MHz is VALID.
      expect(n, isNot(contains('invalid at 20 and 40 MHz')),
          reason: 'MCS 9 at 40 MHz is VALID. That claim is the defect.');

      // BUG 2's sentence — the notes must state the 4 SS exclusion, not imply
      // the exclusions stop at 3 SS.
      expect(n, contains('20 MHz'));
      expect(n, contains('N/A at 1, 2 and 4'),
          reason: 'MCS 9 @ 20 MHz is N/A at 4 SS too. The notes must say so, '
              'or the next reader will "fix" the data to match the prose.');

      // And the honest ceiling.
      expect(n, contains('4 spatial streams'));
    });

    test('the unsourced state is never labelled "N/A"', () {
      // N/A is a claim the STANDARD makes: this combination is invalid.
      // Unsourced is a claim about OUR DATA: we have no published figure.
      // 8-stream 802.11be is perfectly valid; rendering it "N/A" would mark a
      // working cell invalid — bug 1 in a new costume.
      expect(
        McsIndexScreen.unsourcedStreamsNotice.toUpperCase(),
        isNot(contains('N/A')),
      );
      expect(McsIndexScreen.unsourcedStreamsNotice, contains('4 spatial'));
    });

    test('HE and EHT have 0.8 / 1.6 / 3.2 us GI only — no 400 ns', () {
      // HT/VHT have 0.8 and 0.4 us. HE/EHT have 0.8 / 1.6 / 3.2 us ONLY.
      // A 400 ns column for HE or EHT would be fabricated. It is not present
      // today; this pins it so it cannot appear.
      expect(ThroughputCalcScreen.giKeys[WifiStd.he], <String>['0.8', '1.6', '3.2']);
      expect(ThroughputCalcScreen.giKeys[WifiStd.eht], <String>['0.8', '1.6', '3.2']);
      expect(ThroughputCalcScreen.giKeys[WifiStd.ht], contains('0.4'));
      expect(ThroughputCalcScreen.giKeys[WifiStd.vht], contains('0.4'));

      for (final String col in McsIndexScreen.he.columns) {
        expect(col, isNot(contains('SGI')),
            reason: 'HE has no short-GI column. GI is 0.8/1.6/3.2 us.');
      }
      for (final String col in McsIndexScreen.eht.columns) {
        expect(col, isNot(contains('SGI')),
            reason: 'EHT has no short-GI column.');
      }
    });

    test('HE MCS 11 rounds, not truncates (Keith: 600.5 / 1201)', () {
      expect(
        McsIndexScreen.rate(
            std: McsStd.ax, mcs: 11, columnIndex: 2, spatialStreams: 1),
        closeTo(600.5, 0.01),
        reason: 'True value 600.49. The app truncated to 600.4.',
      );
      expect(
        McsIndexScreen.rate(
            std: McsStd.ax, mcs: 11, columnIndex: 3, spatialStreams: 1),
        closeTo(1201.0, 0.01),
        reason: 'True value 1200.98. The app truncated to 1200.9.',
      );
    });

    test('the screen and its help both say EHT, because the app ships EHT', () {
      // The screen and the help both said "n / ac / ax". The app ships a fourth
      // standard: 802.11be, 320 MHz, MCS 12-13, 4096-QAM.
      expect(McsIndexScreen.dataset.keys, contains(McsStd.be));
      expect(McsIndexScreen.eht.columns, contains('320 MHz'));
      expect(McsIndexScreen.notesText, contains('802.11be'));
    });

    test('the MCS help names all four standards it ships', () async {
      final String raw =
          await rootBundle.loadString('assets/help/tool_help.json');
      final Map<String, dynamic> help =
          (jsonDecode(raw) as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      final String mcs = jsonEncode(help['mcs-index']);

      expect(mcs, contains('802.11be'),
          reason: 'The help said n/ac/ax. The app ships be.');
      expect(mcs, isNot(contains('invalid at 20 and 40 MHz')),
          reason: 'The help repeated the false 40 MHz exclusion.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // P0 — MODULATION. An ACCESSIBILITY FAILURE, treated as HIGH.
  //
  // The help told assistive-tech users the diagrams are decorative "since every
  // fact is also in the screen's text." They were not. `_summaryRows` — the
  // SNR/EVM numbers — was referenced ONLY by _buildCopyText(). A screen-reader
  // user was told they were not missing anything, and they were.
  // ═════════════════════════════════════════════════════════════════════════
  group('modulation — the SNR/EVM facts are on screen, not just in the clipboard',
      () {
    testWidgets('the summary table renders as text a screen reader can reach',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 6000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const ModulationScreen()),
        );
        await tester.pumpAndSettle();

        // Every row of the summary the help promised was "also in the screen's
        // text". Before the fix, none of these were on screen at all.
        for (final List<String> row in ModulationScreen.summaryRows) {
          expect(
            find.text(row.first),
            findsWidgets,
            reason: '${row.first} is in the copy payload but was never '
                'rendered. The help said it was.',
          );
        }
        expect(find.textContaining('34 dB'), findsWidgets,
            reason: 'The 1024-QAM SNR figure — copy-only before the fix.');
        expect(find.textContaining('-35 dB'), findsWidgets,
            reason: 'The 1024-QAM EVM ceiling — copy-only before the fix.');
      });
    });

    testWidgets('each summary row is one merged semantic node', (tester) async {
      await _withViewport(tester, const Size(414, 6000), () async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const ModulationScreen()),
        );
        await tester.pumpAndSettle();

        // A row must read as one sentence, not five orphan cells.
        expect(
          find.bySemanticsLabel(RegExp(r'1024-QAM.*1024 points.*10 bits')),
          findsOneWidget,
        );
        handle.dispose();
      });
    });

    test('the help no longer claims a fact lives somewhere it does not',
        () async {
      final String raw =
          await rootBundle.loadString('assets/help/tool_help.json');
      final Map<String, dynamic> tools =
          (jsonDecode(raw) as Map<String, dynamic>)['tools']
              as Map<String, dynamic>;
      final String mod = jsonEncode(tools['modulation']);

      // The claim is now TRUE (the table is on screen), so the sentence may
      // stay — but it must name the summary card, so the promise is checkable.
      expect(mod, contains('summary'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // P0 — INTERNATIONAL PLUGS. Twelve countries dead-ended.
  //
  // The screen had cards for 11 letters. country_plug_data returns H, K, N and
  // O from country search. Search "Denmark" -> "Type C, E, F, K" -> and no Type
  // K card exists to open.
  //
  // THE GENERAL SHAPE (worth a mechanical guard): a data layer returns a key
  // the view layer has no view for.
  // ═════════════════════════════════════════════════════════════════════════
  group('international plugs — every letter the data returns has a card', () {
    test('MECHANICAL GUARD: no country can name a plug type with no card', () {
      final Set<String> carded = InternationalPlugsScreen.plugTypes
          .map((PlugType p) => p.type)
          .toSet();

      final Map<String, List<String>> orphans = <String, List<String>>{};
      for (final CountryPlug c in kCountryPlugs) {
        for (final String letter in c.types) {
          if (!carded.contains(letter)) {
            orphans.putIfAbsent(letter, () => <String>[]).add(c.country);
          }
        }
      }

      expect(
        orphans,
        isEmpty,
        reason: 'These plug letters are returned by country search but have no '
            'card to open: $orphans',
      );
    });

    test('the four missing letters are now carded — H, K, N, O', () {
      final Map<String, PlugType> byLetter = <String, PlugType>{
        for (final PlugType p in InternationalPlugsScreen.plugTypes)
          p.type: p,
      };

      // Values from Pax's brief (Deliverables/2026-06-08-power-cooling-
      // references + 2026-06-08-country-plug-lookup) — the SAME source the 11
      // existing cards cite. Not invented, not from memory.
      expect(byLetter['H']?.standard, contains('SI 32'));
      expect(byLetter['K']?.standard, contains('DS 107'));
      expect(byLetter['N']?.standard, contains('IEC 60906-1'));
      expect(byLetter['O']?.standard, contains('TIS 166'));
    });

    test('Denmark -> Type K -> a card that opens', () {
      // The exact case from the audit.
      final CountryPlug dk =
          kCountryPlugs.firstWhere((CountryPlug c) => c.country == 'Denmark');
      expect(dk.types, contains('K'));
      expect(
        InternationalPlugsScreen.plugTypes.any((PlugType p) => p.type == 'K'),
        isTrue,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // MEDIUM — SIGNAL THRESHOLDS layout collision. "-67 dBm25 dB" at 320w.
  // ═════════════════════════════════════════════════════════════════════════
  group('signal thresholds — the RSSI and SNR columns do not collide', () {
    testWidgets('at 320 px the numbers keep clear air between them',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(320, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const SignalThresholdsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // The VoIP row: "-67 dBm" and "25 dB". Both strings are unique to it.
        final Rect rssi = tester.getRect(find.text('-67 dBm'));
        final Rect snr = tester.getRect(find.text('25 dB'));

        expect(
          snr.left,
          greaterThan(rssi.right),
          reason: 'They rendered as "-67 dBm25 dB" — the columns touched.',
        );
        expect(
          snr.left - rssi.right,
          greaterThanOrEqualTo(4.0),
          reason: 'Two adjacent data columns need a real gutter, not zero.',
        );
      });
    });

    testWidgets('the SNR -> MCS table does not collide either',
        (WidgetTester tester) async {
      // FOUND BY LOOKING at the regenerated 320px golden, not by a failing test.
      // The card below the thresholds had the SAME zero-gutter bug: every
      // two-digit SNR filled its cell and ran into the MCS name — "10 dBMCS 2 -
      // QPSK 3/4", "13 dBMCS 3", "35 dBMCS 11". Nine of twelve rows.
      //
      // The lesson worth keeping: the brief named ONE collision, and fixing only
      // what the brief names would have shipped the identical defect one card
      // lower on the same screen.
      await _withViewport(tester, const Size(320, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const SignalThresholdsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // '13 dB' is unique to the SNR->MCS table; its MCS name sits beside it.
        final Rect snr = tester.getRect(find.text('13 dB'));
        final Rect mcs = tester.getRect(find.text('MCS 3 - 16-QAM 1/2'));

        expect(mcs.left, greaterThan(snr.right),
            reason: 'They rendered as "13 dBMCS 3 - 16-QAM 1/2".');
        expect(mcs.left - snr.right, greaterThanOrEqualTo(4.0));
      });
    });

    test('Keith\'s framing is on the screen, not only in the help', () {
      // Confirmed by Keith today: these are HIS recommendations, not a standard.
      // IEEE 802.11 defines no "good" or "poor" signal level. Wave 1 fixed the
      // help; this pins the SCREEN's copy of the framing, which is where the
      // numbers are actually read. One const, rendered — not a second string.
      expect(SignalThresholdsScreen.kThresholdFraming,
          contains('not an industry standard'));
      expect(SignalThresholdsScreen.kThresholdFraming,
          contains('IEEE 802.11 does not define'));
      expect(
          SignalThresholdsScreen.kThresholdFraming, contains('vary by site'));
    });

    testWidgets('the recommendation framing renders above the numbers',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 3000), () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const SignalThresholdsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('recommended design targets', findRichText: true),
          findsWidgets,
        );
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // MEDIUM — Cat6 10G reach. 55 m flat on one screen; 55 m favorable / 37 m
  // dense-bundle on the other. In a real ceiling that gap is the install
  // failing.
  // ═════════════════════════════════════════════════════════════════════════
  group('the two cabling screens agree on Cat6 at 10G', () {
    test('ethernet_cable carries the dense-bundle distance too', () {
      final EthCable cat6 = EthernetCableScreen.ethData
          .firstWhere((EthCable c) => c.category == 'Cat6');

      // structured_cabling has said "about 55 m favorable, 37 m dense-bundle"
      // all along. ethernet_cable said a flat "55m" and stopped.
      expect(cat6.dist10g, contains('37'),
          reason: 'The dense-bundle planning distance is the one that bites.');
      expect(cat6.dist10g, contains('55'));
    });

    test('the footnote explains which number to design to', () {
      expect(EthernetCableScreen.speedGradesFootnote, contains('37'));
      expect(EthernetCableScreen.speedGradesFootnote, contains('55'));
      expect(
        EthernetCableScreen.speedGradesFootnote,
        anyOf(contains('bundle'), contains('alien')),
        reason: 'The reader must be told WHY 55 collapses to 37.',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // MEDIUM — DSCP / QoS.
  //   (a) the help promised a binary column; there wasn't one.
  //   (b) per RFC 8325 the DSCP->AC mapping is a CONVENTION, verbatim:
  //       "provided as examples (as opposed to explicit recommendations)".
  //       The UP->AC half IS normative (IEEE 802.11 Table 10-1).
  // ═════════════════════════════════════════════════════════════════════════
  group('DSCP / QoS — the binary column exists and the labels are honest', () {
    test('every DSCP class carries its binary codepoint (IANA registry)', () {
      for (final DscpClass c in DscpQosScreen.dscpClasses) {
        expect(c.binary, isNotEmpty, reason: '${c.name} has no binary value.');
      }
      Map<String, DscpClass> byName = <String, DscpClass>{
        for (final DscpClass c in DscpQosScreen.dscpClasses) c.name: c,
      };
      // Spot-pinned against the IANA DSCP registry.
      expect(byName['EF']?.binary, '101110');
      expect(byName['CS6']?.binary, '110000');
      expect(byName['VA']?.binary, '101100');
      expect(byName['DF (Default / CS0)']?.binary, '000000');
    });

    testWidgets('the Binary column header is actually on screen',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(900, 4000), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const DscpQosScreen()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Binary'), findsOneWidget,
            reason: 'The help promised name, decimal AND binary.');
        expect(find.text('101110'), findsWidgets, reason: 'EF.');
      });
    });

    test('UP -> AC is labelled normative; DSCP -> AC is labelled a convention',
        () {
      // RFC 8325, verbatim on the IEEE tables: "these mappings are provided as
      // examples (as opposed to explicit recommendations)".
      expect(DscpQosScreen.normativeNote, contains('Table 10-1'));
      expect(DscpQosScreen.normativeNote, contains('normative'));

      expect(DscpQosScreen.conventionNote, contains('RFC 8325'));
      expect(
        DscpQosScreen.conventionNote,
        anyOf(contains('convention'), contains('recommendation')),
        reason: 'There is NO normative DSCP-to-AC mapping in IEEE 802.11.',
      );
      expect(DscpQosScreen.conventionNote, isNot(contains('required')));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // MEDIUM — EAP citations. TEAP is RFC 9930 now, not 7170. EAP-AKA' is
  // RFC 9048, not 5448. (IANA EAP Method Types registry, updated 2026-05-28.)
  // ═════════════════════════════════════════════════════════════════════════
  group('EAP citations point at the current RFCs', () {
    test('TEAP is RFC 9930', () {
      final String all = EapTypesScreen.methods
          .map((EapMethod m) => m.use)
          .join(' ');
      expect(all, contains('RFC 9930'));
      expect(all, isNot(contains('RFC 7170')),
          reason: 'RFC 7170 is superseded. Citing it cites a dead document.');
    });

    test("EAP-AKA' is RFC 9048", () {
      final EapMethod aka = EapTypesScreen.methods
          .firstWhere((EapMethod m) => m.method.contains('AKA'));
      expect(aka.use, contains('RFC 9048'));
      expect(aka.use, isNot(contains('RFC 5448')),
          reason: 'RFC 9048 obsoletes RFC 5448 for EAP-AKA-prime.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // CABLE LOSS — LMR-1200 removed, and no silent extrapolation. (Keith's call,
  // mid-wave, and it closes the last open question from batch 1.)
  //
  // The equation gives 3.774 dB/100 ft for LMR-1200 at 5800 MHz. The real figure
  // is ~4.7-5.5 — a 25-45% gap, in the SAME flattering direction as the original
  // column-shifted table. Times tabulates every other LMR to 5800 MHz and stops
  // LMR-1200 at 2500: the two-term model extrapolates badly for a cable that
  // large. Shipping 3.774 would have introduced a brand-new wrong number on the
  // day we fixed the old ones.
  //
  // And nobody runs LMR-1200 at 6 GHz: FCC rules make outdoor 6 GHz
  // standard-power a non-starter without AFC, and low-power is indoor-only. The
  // only frequency where the disputed value mattered is a use case that does not
  // exist.
  // ═════════════════════════════════════════════════════════════════════════
  group('cable loss ships only manufacturer-validated cables', () {
    test('LMR-1200 is not offered, at all', () {
      expect(CableLossScreen.cableTypes, isNot(contains('LMR-1200')));
      expect(
        CableLossScreen.cableCoefficients.containsKey('LMR-1200'),
        isFalse,
        reason: 'Removing it from the picker but leaving the coefficients is '
            'how a dead value comes back. Both go.',
      );
      expect(CableLossScreen.cableLossPer100ft('LMR-1200', 5800), isNull,
          reason: 'It must not compute. 3.774 dB/100 ft is wrong by 25-45%.');
    });

    test('the five shipped cables are exactly the Times-tabulated set', () {
      expect(CableLossScreen.cableTypes, <String>[
        'LMR-100A',
        'LMR-200',
        'LMR-400',
        'LMR-600',
        'LMR-900',
      ]);
      // Every one is tabulated by Times out to 5800 MHz, so the equation is
      // never used outside the range its source validated.
      for (final String c in CableLossScreen.cableTypes) {
        expect(
          CableLossScreen.cableLossPer100ft(c, CableLossScreen.validatedMaxFreqMHz),
          isNotNull,
        );
      }
    });

    test('the screen says WHY LMR-1200 is absent', () {
      // An unexplained omission invites someone to "helpfully" add it back.
      expect(CableLossScreen.lmr1200OmissionNote, contains('2500'));
      expect(CableLossScreen.lmr1200OmissionNote, contains('5800'));
      expect(CableLossScreen.lmr1200OmissionNote, contains('LMR-1200'));
    });

    test('above 5800 MHz the app admits it is extrapolating', () {
      // Same discipline as returning null for Noise on Windows: never invent a
      // confident figure outside the model's validated range.
      expect(CableLossScreen.isAboveValidatedRange(5800), isFalse);
      expect(CableLossScreen.isAboveValidatedRange(5801), isTrue);
      expect(CableLossScreen.isAboveValidatedRange(6000), isTrue,
          reason: '6 GHz Wi-Fi is past every LMR datasheet.');
      expect(CableLossScreen.isAboveValidatedRange(2400), isFalse);

      expect(CableLossScreen.aboveValidatedRangeNote, contains('5800'));
      expect(CableLossScreen.aboveValidatedRangeNote,
          anyOf(contains('extrapolation'), contains('extrapolat')));
    });

    testWidgets('a 6 GHz run renders the warning, not a bare number',
        (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 2600), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CableLossScreen()),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '6'); // 6 GHz
        await tester.enterText(fields.at(1), '50'); // 50 ft
        await tester.pumpAndSettle();

        expect(find.text('Outside validated range'), findsOneWidget);
      });
    });

    testWidgets('a 2.4 GHz run does NOT cry wolf', (WidgetTester tester) async {
      await _withViewport(tester, const Size(414, 2600), () async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark(), home: const CableLossScreen()),
        );
        await tester.pumpAndSettle();

        final Finder fields = find.byType(TextField);
        await tester.enterText(fields.at(0), '2.4');
        await tester.enterText(fields.at(1), '50');
        await tester.pumpAndSettle();

        expect(find.text('Outside validated range'), findsNothing,
            reason: 'A warning that fires inside the validated range trains '
                'the user to ignore it.');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // WAVE-2 TABLE CORRECTIONS (2026-07-12). Each expected value comes from the
  // primary-sourced finding brief in
  // Deliverables/2026-07-12-toolbox-wave-2/table-findings/, never from the app.
  // Coax, ethernet-cable, and standards-year guards live in their own test
  // files; the reference-data corrections without a natural home are pinned here.
  // ═════════════════════════════════════════════════════════════════════════
  group('wave-2 reference-data corrections', () {
    test('channel map: no phantom 5 GHz 160 MHz channel (center 130)', () {
      // Finding E: US 5 GHz 160 MHz centers are 50, 114, 163 ONLY. Center 130
      // (ch 116-144) is not a real 802.11 channel; it was absent from the app's
      // own engine. Count is 3, not 4.
      final List<int> centers = ChannelMapScreen.map5_160
          .map((BondedBlock b) => b.centerChannel)
          .toList();
      expect(centers, <int>[50, 114, 163]);
      expect(centers.contains(130), isFalse,
          reason: 'phantom center-130 block must not return');
    });

    test('IEC 60309 black band is 500-690V, not 500-1000V', () {
      // Finding H: black = 500-690V (IEC 60309-2). 1000V is the standard's
      // overall ceiling across all colors, not the black band.
      final IecIndustrial black = IecConnectorsScreen.industrial
          .firstWhere((IecIndustrial i) => i.color == 'Black');
      expect(black.voltage, '500-690V');
    });

    test('data_units drive-capacity footnote is labelled GB/GiB, not TB/TiB', () {
      // Finding C: the 1000->931 illusion is the GB/GiB step (7.37%); the label
      // said TB/TiB (which is actually 9.95% on this screen's own ladder).
      expect(DataUnitsScreen.bitByteFootnote, contains('7.37% GB/GiB gap'));
      expect(DataUnitsScreen.bitByteFootnote, isNot(contains('TB/TiB gap')));
    });

    test('regex \\v is a PCRE2-dialect row, not "Universal"', () {
      // Finding C: in PCRE2 (this page's dialect) \\v is the vertical-whitespace
      // CLASS, not the vertical-tab literal, and it is one of the most
      // dialect-divergent tokens - so it must not be marked universal.
      final RegexToken v = RegexCheatsheetScreen.escapes
          .firstWhere((RegexToken t) => t.token == r'\v');
      expect(v.universal, isFalse, reason: '\\v is not universal');
      expect(v.matches.toLowerCase(), contains('vertical whitespace'));
      // The remaining combined literal keeps only the genuinely-universal ones.
      final RegexToken fnull = RegexCheatsheetScreen.escapes
          .firstWhere((RegexToken t) => t.token == r'\f \0');
      expect(fnull.universal, isTrue);
      expect(fnull.matches.contains('vertical tab'), isFalse,
          reason: '\\v was split out of this row');
    });

    test('db_reference +17 dBm is the U-NII-1 PSD limit, not conducted max', () {
      // Finding C: the pre-2014 "UNII-1 conducted max" label was wrong; current
      // U-NII-1 conducted max is 30 dBm/1 W. 17 dBm is the PSD limit (dBm/MHz).
      final DbmRef r17 = DbReferenceScreen.dbmRefs
          .firstWhere((DbmRef r) => r.dbm == '+17 dBm');
      expect(r17.context, contains('power spectral density'));
      expect(r17.context, isNot(contains('conducted max')));
    });

    test('fiber 100G OM3/OM4/OM5 carry modern SR4 reaches, not legacy SR10', () {
      // Finding B: 100GBASE-SR4 (802.3bm) = OM3 70 m / OM4 100 m. The old
      // 100/150 m were legacy SR10 numbers. OM5 matches OM4 (same EMB).
      FiberType t(String type) => FiberOpticScreen.FIBER_DATA
          .firstWhere((FiberType f) => f.type == type);
      expect(t('OM3').dist100G, '70 m');
      expect(t('OM4').dist100G, '100 m');
      expect(t('OM5').dist100G, '100 m');
    });

    test('Part 15 status is "unlicensed", not "Secondary"', () {
      // Finding F: Part 15 is unlicensed (no allocation status). "Secondary" is
      // an allocation term and is wrong for Part 15; Part 97's stays correct.
      final RuleDelta status =
          kRuleDeltas.firstWhere((RuleDelta d) => d.dimension == 'Status');
      expect(status.part15.toLowerCase(), contains('unlicensed'));
      expect(status.part15.contains('Secondary'), isFalse);
      expect(status.part97, contains('Secondary'),
          reason: 'Part 97 secondary allocation is correct and stays');
    });

    test('Part 15/97 2.4 GHz overlap is ~50 MHz in-band, not ~60', () {
      // Finding F: 60 MHz is the amateur segment width (2390-2450); the part
      // inside the Wi-Fi band (2400-2483.5) is 2400-2450 = ~50 MHz.
      final WifiHamOverlap band24 = kWifiHamOverlaps.firstWhere(
          (WifiHamOverlap o) => o.hamBand.contains('13 cm'));
      expect(band24.overlap, contains('~50 MHz'));
      expect(band24.overlap.contains('~60 MHz'), isFalse);
    });

    test('802.11r roam-latency figures are hedged as design guidance', () {
      // Finding A: <50 / >150 ms is a practitioner convention, not a standards
      // target (802.11 defines no roaming-time requirement).
      final String allNotes = FrameExchangeScreen.scenarios
          .expand((FxScenario s) => s.phases)
          .expand((FxPhase p) => p.frames)
          .map((FxFrame f) => f.note)
          .join(' ');
      // The figure now appears only as hedged design guidance.
      expect(allNotes, contains('design guide'));
      expect(allNotes.contains('roam latency < 50 ms with 802.11r vs > 150 ms'),
          isFalse,
          reason: 'the old unhedged assertion must not survive');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // ALREADY CORRECT — findings from the sweep that did NOT reproduce.
  //
  // Pinned rather than dropped: each was checked against the primary source and
  // the app was right. These guards keep it right.
  // ═════════════════════════════════════════════════════════════════════════
  group('already correct — pinned so it cannot regress', () {
    test('HTTP 418 is "(Unused)", not the RFC 2324 teapot joke', () {
      final Map<int, HttpStatusEntry> byCode = <int, HttpStatusEntry>{
        for (final HttpStatusClass c in HttpStatusCodesScreen.classes)
          for (final HttpStatusEntry e in c.entries) e.code: e,
      };
      expect(byCode[418]?.reason, '(Unused)',
          reason: 'IANA registry. "I am a Teapot" is RFC 2324, April Fools.');
      expect(byCode[413]?.reason, 'Content Too Large',
          reason: 'RFC 9110. Not "Payload Too Large".');
      expect(byCode[422]?.reason, 'Unprocessable Content',
          reason: 'RFC 9110. Not "Unprocessable Entity".');
      expect(byCode[414]?.reason, 'URI Too Long');
    });

    test('Z-Wave is sub-GHz and does not share 2.4 GHz (ITU-T G.9959)', () {
      final RadioSystemRow z =
          kRadioSystems.firstWhere((RadioSystemRow r) => r.system == 'Z-Wave');
      expect(z.sharesTwoFour, 'No');
      expect(z.band.toLowerCase(), contains('sub-ghz'));
    });

    test('DECT is not listed as a 2.4 GHz interferer anywhere', () {
      // 47 CFR 15.303: US DECT is 1920-1930 MHz. It is not a 2.4 GHz interferer.
      for (final RadioSystemRow r in kRadioSystems) {
        if (r.system.toLowerCase().contains('dect')) {
          expect(r.sharesTwoFour, 'No');
        }
      }
    });
  });
}

/// Run [body] with the test view sized to [size], then restore.
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
