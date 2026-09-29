// A fingerprint of every 802.1X and EAP Ladder sequence, used to prove that
// "Break it: none" draws exactly the ladder v1.11.0 drew (spec 42, Done
// means). The fixture test/fixtures/eap_ladder_v1_11_0_fingerprints.json was
// written from tag v1.11.0 (8197a2c1) BEFORE the failure marker was added,
// by running the capture test in eap_ladder_fault_test.dart with
// WRITE_LADDER_FINGERPRINTS=1.

import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';

/// Every configuration v1.11.0 could build, keyed method|roam|inner|frags.
Map<String, LadderConfig> allV1110Configs() => <String, LadderConfig>{
  for (final LadderMethod m in LadderMethod.values)
    for (final LadderRoam r in LadderRoam.values)
      for (final LadderInner i in LadderInner.values)
        for (int f = kMinCertFragments; f <= kMaxCertFragments; f++)
          '${m.name}|${r.name}|${i.name}|$f': LadderConfig(
            method: m,
            roam: r,
            inner: i,
            certFragments: f,
          ),
};

/// Every field v1.11.0's LadderMessage had, in order, plus the sequence
/// counts and time.
String ladderText(LadderSequence s) {
  final StringBuffer b = StringBuffer()
    ..writeln('${s.airCount}|${s.wireCount}|${s.radiusRoundTrips}')
    ..writeln(s.estimatedMs.toStringAsFixed(3));
  for (final LadderMessage x in s.messages) {
    b.writeln(
      <Object?>[
        x.from.name,
        x.to.name,
        x.kind.name,
        x.phase.name,
        x.label,
        x.detail,
        x.fullDetail,
        x.description,
        x.eapCode,
        x.tunneled,
        x.clientCertificate,
        x.serverCertificate,
        x.milestone?.name,
        x.milestoneText,
      ].join('|'),
    );
  }
  return b.toString();
}

/// 64-bit FNV-1a over the UTF-16 code units, as 16 hex digits.
String fnv1a64(String s) {
  const int prime = 0x100000001b3;
  int h = 0xcbf29ce484222325;
  for (final int u in s.codeUnits) {
    h ^= u;
    h *= prime; // wraps at 64 bits on the Dart VM
  }
  String half(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return '${half(h >>> 32)}${half(h)}';
}
