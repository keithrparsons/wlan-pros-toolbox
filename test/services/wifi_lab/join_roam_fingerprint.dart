// A fingerprint of every Join and Roam ladder, used to prove that the
// security-compatibility mode (spec 43) leaves the existing Join mode and
// Roam exactly as they were. The fixture
// test/fixtures/join_roam_4d2b460a_fingerprints.json was written from commit
// 4d2b460a (the shared failure marker, before any spec 43 change) by running
// the capture test in join_roam_unchanged_test.dart with
// WRITE_JR_FINGERPRINTS=1.

import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/join_roam.dart';

export 'eap_ladder_fingerprint.dart' show fnv1a64;

/// Every Join configuration that changes the frames, keyed by its settings.
Map<String, JrConfig> allJoinConfigs() {
  final Map<String, JrConfig> out = <String, JrConfig>{};
  for (final JrSecurity s in JrSecurity.values) {
    for (final JrBand b in JrBand.values) {
      for (final JrScanType t in JrScanType.values) {
        for (final JrSixGhzDiscovery d in JrSixGhzDiscovery.values) {
          for (final JrAddressCheck a in JrAddressCheck.values) {
            for (final JrPmf p in JrPmf.values) {
              for (final LadderMethod m in <LadderMethod>[
                LadderMethod.eapTls,
                if (s == JrSecurity.dot1x) LadderMethod.peap,
                if (s == JrSecurity.dot1x) LadderMethod.eapTtls,
              ]) {
                out['join|${s.name}|${b.name}|${t.name}|${d.name}|'
                    '${a.name}|${p.name}|${m.name}'] = JrConfig(
                  security: s,
                  band: b,
                  scanType: t,
                  sixGhz: d,
                  addressCheck: a,
                  pmf: p,
                  eapMethod: m,
                );
              }
            }
          }
        }
      }
    }
  }
  // A passive dwell short enough to miss the beacon.
  out['join|notfound'] = const JrConfig(
    scanType: JrScanType.passive,
    passiveDwellMs: 30,
  );
  return out;
}

/// Every Roam configuration that changes the frames.
Map<String, JrConfig> allRoamConfigs() => <String, JrConfig>{
  for (final JrRoamMethod r in JrRoamMethod.values)
    for (final JrBand b in JrBand.values)
      for (final JrScanType t in JrScanType.values)
        for (final JrPmf p in JrPmf.values)
          for (final LadderMethod m in <LadderMethod>[
            LadderMethod.eapTls,
            LadderMethod.peap,
            LadderMethod.eapTtls,
          ])
            'roam|${r.name}|${b.name}|${t.name}|${p.name}|${m.name}': JrConfig(
              roamMethod: r,
              band: b,
              scanType: t,
              pmf: p,
              eapMethod: m,
            ),
};

/// Every field of every message, the lanes, the counts and the times.
String jrText(JrSequence s) {
  final StringBuffer b = StringBuffer()
    ..writeln(s.lanes.map((JrLane l) => l.name).join(','))
    ..writeln(
      '${s.airCount}|${s.managementCount}|${s.dataCount}|${s.wireCount}|'
      '${s.radiusRoundTrips}|${s.found}|${s.security.name}|${s.pmf.name}',
    )
    ..writeln(s.totalMs.toStringAsFixed(3))
    ..writeln('${s.faultNote}|${s.helpDesk}');
  for (final JrMessage x in s.messages) {
    b.writeln(
      <Object?>[
        x.from.name,
        x.to.name,
        x.via?.name,
        x.kind.name,
        x.phase.name,
        x.clock.name,
        x.label,
        x.detail,
        x.description,
        x.fields.map((JrField f) => '${f.$1}=${f.$2}').join(';'),
        x.ms.toStringAsFixed(3),
        x.encrypted,
        x.pmfProtected,
        x.tunneled,
        x.missed,
        x.failure,
        x.lost,
        x.milestone?.name,
        x.milestoneText,
      ].join('|'),
    );
  }
  for (final JrPhase p in JrPhase.values) {
    b.writeln(s.phaseTitle(p));
  }
  return b.toString();
}
