// Why won't it associate? The security-compatibility mode of Association,
// Frame by Frame (Wi-Fi Classroom, join-ladder), spec 43.
//
// Pure Dart, no Flutter. [evaluateSecurity] takes what a client can do
// ([ScClient]) and what a network offers ([ScNetwork]) and returns one of four
// outcomes, with the reason in plain words and the source that pins it:
//
//   - associates: the key management (AKM), ciphers and PMF they agree on,
//     and whether it is a Wi-Fi 7 connection or falls back to Wi-Fi 6;
//   - never tries: nothing in the AP's RSN element fits, so the client sends
//     no Authentication and no Association Request frame (Probe Requests can
//     still go out while it scans). The common real case: no status code
//     exists, because nothing was ever refused;
//   - refused: the client tries and the AP says no. Only one case is drawn:
//     a client older than PMF (802.11w), which ignores the MFPC and MFPR
//     bits, against a network that requires PMF: status 31;
//   - not offered: no AP may offer this security in 6 GHz.
//
// [buildSecurityCompat] turns the verdict into the Join ladder, stopped at the
// frame where it fails with the shared failure marker (spec 42), through
// [JrSecurityOverride] in join_roam.dart. The ordinary Join mode never passes
// an override and is unchanged.
//
// CLEAN-ROOM BUILD (2026-09-29) per myPKA Deliverables/2026-09-25-wifi-lab-
// cleanroom/specs/43-security-compat.md. Facts pinned by Pax in
// Deliverables/2026-09-25-wifi-lab-cleanroom/evidence/2026-09-29-facts-
// security-compat-and-rate-set.md (section letters below), read in:
//   - IEEE Std 802.11-2024: RSNE 9.4.2.23 (B1), cipher suite selectors
//     Table 9-188 (B2), AKM suite selectors Table 9-190 (B3), MFPR and MFPC
//     bits 9.4.2.23.4 (B4), RSNA policy selection 12.6.3 (B5) and its PMF
//     table, Table 12-5 (B6), status codes Table 9-80 (B7), BSS membership
//     selector 123, SAE hash-to-element only, Table 9-131 (B8), 6 GHz
//     12.12.2 (B9).
//   - IEEE Std 802.11be-2024 12.12.9: EHT STAs use SAE AKM 24 or 25; 12.6.3.1
//     NOTE 1: MFP is mandatory for EHT STAs that use RSN (B12).
//   - Wi-Fi Alliance WPA3 Specification v3.5: §2.2 to §2.5 and §3.2 to §3.5
//     (modes, B10), §4.1 and §4.2.1 (selection, B5 and B10), §11.2 (6 GHz,
//     B9), §11.3 (Wi-Fi 7, B12).
//
// WHAT IS THE MODEL'S OWN READING, labelled as such on screen:
//   - Which AKM a client picks when several fit: WPA3 v3.5 §4.2.1 order for
//     personal networks; for enterprise, 192-bit, then SHA-256, then SHA-1.
//   - Which pairwise cipher: the strongest both offer.
//   - A client that knows PMF will not use SAE or OWE without it (WPA3 v3.5
//     §2.2 STA notes).
//   - Statuses 42, 43 and 46 are not drawn: they need a client that ignores
//     the AP's advertisement, and no normative trigger for them was found
//     (evidence B7, E2).
//
// Generic device names only. No other lab or author is credited (Keith's
// ruling, 2026-09-29).

import 'package:flutter/foundation.dart' show immutable, setEquals;

import 'join_roam.dart';

// ── Suites ──────────────────────────────────────────────────────────────────

/// Key management (AKM) suites the model draws, with their Table 9-190
/// selector (OUI 00-0F-AC).
enum ScAkm {
  psk(2, 'PSK', 'PSK (WPA2-Personal)'),
  sae(8, 'SAE', 'SAE, type 8 (WPA3-Personal)'),
  saeExt(24, 'SAE', 'SAE, type 24 (WPA3-Personal, needed for Wi-Fi 7)'),
  owe(18, 'OWE', 'OWE (Enhanced Open)'),
  dot1x(1, '802.1X', '802.1X, SHA-1 (WPA2-Enterprise)'),
  dot1xSha256(5, '802.1X-SHA256', '802.1X, SHA-256 (WPA3-Enterprise)'),
  suiteB192(12, '802.1X-192', '802.1X, 192-bit (WPA3-Enterprise 192-bit)');

  const ScAkm(this.selector, this.short, this.label);

  /// Suite type in Table 9-190.
  final int selector;

  /// The short name used in verdicts.
  final String short;

  /// The name on the Client card.
  final String label;

  /// "SAE (8)".
  String get tagged => '$short ($selector)';

  /// The frames the ladder draws for this AKM.
  JrSecurity get flow => switch (this) {
    psk => JrSecurity.psk,
    sae || saeExt => JrSecurity.sae,
    owe => JrSecurity.owe,
    dot1x || dot1xSha256 || suiteB192 => JrSecurity.dot1x,
  };

  bool get isSae => this == sae || this == saeExt;

  /// A client that knows PMF uses SAE and OWE only with PMF on (WPA3 v3.5
  /// §2.2 STA notes; OWE is WPA3-era and requires PMF).
  bool get needsPmf => isSae || this == owe;

  /// Allowed in a Wi-Fi 7 (EHT or MLO) association: not PSK and not 802.1X
  /// SHA-1 (WPA3 v3.5 §11.3), and SAE only as type 24 (802.11be-2024
  /// 12.12.9; WPA3 v3.5 §2.2 NOTE).
  bool get allowedForWifi7 =>
      this == saeExt || this == owe || this == dot1xSha256 || this == suiteB192;

  /// Selection order, most preferred first: WPA3 v3.5 §4.2.1 for personal
  /// suites (24, then 8, then 2); the enterprise order is the model's own.
  static const List<ScAkm> preference = <ScAkm>[
    saeExt,
    sae,
    psk,
    suiteB192,
    dot1xSha256,
    dot1x,
    owe,
  ];
}

/// Pairwise and group cipher suites (Table 9-188).
enum ScCipher {
  tkip(2, 'TKIP'),
  ccmp128(4, 'CCMP-128'),
  gcmp256(9, 'GCMP-256');

  const ScCipher(this.selector, this.label);

  final int selector;
  final String label;

  /// Strongest first: the model's pick when several fit.
  static const List<ScCipher> strongestFirst = <ScCipher>[
    gcmp256,
    ccmp128,
    tkip,
  ];
}

/// A client's PMF (802.11w) support, as Table 12-5 sees it.
enum ScClientPmf {
  /// Older than PMF: does not know what MFPC and MFPR mean. It sends 0 and 0
  /// and ignores the AP's bits (Table 12-5 NOTE).
  legacy('Older than PMF', 'MFPC and MFPR unknown to it'),
  none('Not capable', 'MFPC 0, MFPR 0'),
  capable('Capable', 'MFPC 1, MFPR 0'),
  required('Required', 'MFPC 1, MFPR 1');

  const ScClientPmf(this.label, this.bits);

  final String label;
  final String bits;

  bool get mfpc => this == capable || this == required;
  bool get mfpr => this == required;

  /// Reads the AP's MFPC and MFPR and follows Table 12-5.
  bool get readsBits => this != legacy;
}

// ── The client ──────────────────────────────────────────────────────────────

/// What a client can do.
@immutable
class ScClient {
  const ScClient({
    required this.akms,
    required this.ciphers,
    required this.pmf,
    required this.h2e,
    required this.bands,
    required this.wifi7,
  });

  final Set<ScAkm> akms;
  final Set<ScCipher> ciphers;
  final ScClientPmf pmf;

  /// Knows SAE hash-to-element (H2E), the newer way to turn the password
  /// into the SAE element. A flag, not a key-management type (evidence B8).
  final bool h2e;

  final Set<JrBand> bands;

  /// Has a Wi-Fi 7 (EHT) radio.
  final bool wifi7;

  ScClient copyWith({
    Set<ScAkm>? akms,
    Set<ScCipher>? ciphers,
    ScClientPmf? pmf,
    bool? h2e,
    Set<JrBand>? bands,
    bool? wifi7,
  }) => ScClient(
    akms: akms ?? this.akms,
    ciphers: ciphers ?? this.ciphers,
    pmf: pmf ?? this.pmf,
    h2e: h2e ?? this.h2e,
    bands: bands ?? this.bands,
    wifi7: wifi7 ?? this.wifi7,
  );

  /// Adds or removes one AKM.
  ScClient withAkm(ScAkm a, bool on) =>
      copyWith(akms: on ? <ScAkm>{...akms, a} : (<ScAkm>{...akms}..remove(a)));

  ScClient withCipher(ScCipher x, bool on) => copyWith(
    ciphers: on
        ? <ScCipher>{...ciphers, x}
        : (<ScCipher>{...ciphers}..remove(x)),
  );

  ScClient withBand(JrBand b, bool on) => copyWith(
    bands: on ? <JrBand>{...bands, b} : (<JrBand>{...bands}..remove(b)),
  );

  @override
  bool operator ==(Object other) =>
      other is ScClient &&
      setEquals(other.akms, akms) &&
      setEquals(other.ciphers, ciphers) &&
      other.pmf == pmf &&
      other.h2e == h2e &&
      setEquals(other.bands, bands) &&
      other.wifi7 == wifi7;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(akms),
    Object.hashAllUnordered(ciphers),
    pmf,
    h2e,
    Object.hashAllUnordered(bands),
    wifi7,
  );
}

/// Generic clients to start from. Illustrative: real devices vary by model,
/// driver and operating system version.
enum ScClientPreset {
  olderLaptop('Older laptop, WPA2 only'),
  printer('Printer, no PMF'),
  phoneWpa3('Phone, WPA3 capable'),
  newLaptop('New laptop, 6 GHz'),
  phoneWifi7('Phone, Wi-Fi 7');

  const ScClientPreset(this.label);

  final String label;

  ScClient get client => switch (this) {
    olderLaptop => const ScClient(
      akms: <ScAkm>{ScAkm.psk, ScAkm.dot1x},
      ciphers: <ScCipher>{ScCipher.tkip, ScCipher.ccmp128},
      pmf: ScClientPmf.capable,
      h2e: false,
      bands: <JrBand>{JrBand.g24, JrBand.g5},
      wifi7: false,
    ),
    printer => const ScClient(
      akms: <ScAkm>{ScAkm.psk},
      ciphers: <ScCipher>{ScCipher.tkip, ScCipher.ccmp128},
      pmf: ScClientPmf.legacy,
      h2e: false,
      bands: <JrBand>{JrBand.g24, JrBand.g5},
      wifi7: false,
    ),
    phoneWpa3 => const ScClient(
      akms: <ScAkm>{
        ScAkm.psk,
        ScAkm.sae,
        ScAkm.owe,
        ScAkm.dot1x,
        ScAkm.dot1xSha256,
      },
      ciphers: <ScCipher>{ScCipher.ccmp128},
      pmf: ScClientPmf.capable,
      h2e: true,
      bands: <JrBand>{JrBand.g24, JrBand.g5},
      wifi7: false,
    ),
    newLaptop => const ScClient(
      akms: <ScAkm>{
        ScAkm.psk,
        ScAkm.sae,
        ScAkm.owe,
        ScAkm.dot1x,
        ScAkm.dot1xSha256,
        ScAkm.suiteB192,
      },
      ciphers: <ScCipher>{ScCipher.ccmp128, ScCipher.gcmp256},
      pmf: ScClientPmf.capable,
      h2e: true,
      bands: <JrBand>{JrBand.g24, JrBand.g5, JrBand.g6},
      wifi7: false,
    ),
    phoneWifi7 => const ScClient(
      akms: <ScAkm>{
        ScAkm.psk,
        ScAkm.sae,
        ScAkm.saeExt,
        ScAkm.owe,
        ScAkm.dot1x,
        ScAkm.dot1xSha256,
      },
      ciphers: <ScCipher>{ScCipher.ccmp128, ScCipher.gcmp256},
      pmf: ScClientPmf.capable,
      h2e: true,
      bands: <JrBand>{JrBand.g24, JrBand.g5, JrBand.g6},
      wifi7: true,
    ),
  };

  /// The preset whose client is exactly [c], or null (edited by hand).
  static ScClientPreset? of(ScClient c) {
    for (final ScClientPreset p in values) {
      if (p.client == c) return p;
    }
    return null;
  }
}

// ── The network ─────────────────────────────────────────────────────────────

/// How the network's security is configured.
enum ScNetSecurity {
  open('Open'),
  owe('OWE (Enhanced Open)'),
  wpa2Personal('WPA2-Personal'),
  wpa3Transition('WPA3-Personal transition'),
  wpa3Personal('WPA3-Personal only'),
  wpa2Enterprise('WPA2-Enterprise'),
  wpa3EnterpriseTransition('WPA3-Enterprise transition'),
  wpa3Enterprise('WPA3-Enterprise only'),
  wpa3Enterprise192('WPA3-Enterprise 192-bit');

  const ScNetSecurity(this.label);

  final String label;

  /// PMF is the network's to choose (WPA2 only); every other mode fixes it.
  bool get pmfChoosable => this == wpa2Personal || this == wpa2Enterprise;

  bool get usesSae => this == wpa3Transition || this == wpa3Personal;

  /// 6 GHz allows only OWE, WPA3-Personal only and WPA3-Enterprise only
  /// (802.11-2024 12.12.2; WPA3 v3.5 §11.2).
  bool get allowedIn6GHz =>
      this == owe ||
      this == wpa3Personal ||
      this == wpa3Enterprise ||
      this == wpa3Enterprise192;

  /// Why 6 GHz does not allow it, with the source; null when it does.
  String? get sixGhzRule => switch (this) {
    open =>
      'Open networks are not allowed in 6 GHz; OWE takes their place '
          '(IEEE 802.11-2024 12.12.2; WPA3 v3.5 section 11.2).',
    wpa2Personal =>
      'PSK is not allowed in 6 GHz, and an AP there must require PMF '
          '(IEEE 802.11-2024 12.12.2; WPA3 v3.5 section 11.2).',
    wpa3Transition =>
      'A 6 GHz AP may not run WPA3-Personal transition mode, because it '
          'would offer PSK (WPA3 v3.5 section 11.2; IEEE 802.11-2024 12.12.2 bans '
          'PSK).',
    wpa2Enterprise =>
      '802.1X with SHA-1 is not allowed in 6 GHz. This is a Wi-Fi Alliance '
          'rule (WPA3 v3.5 section 11.2); IEEE 802.11-2024 12.12.2 does not ban it.',
    wpa3EnterpriseTransition =>
      'WPA3-Enterprise transition mode offers 802.1X with SHA-1, which is '
          'not allowed in 6 GHz. This is a Wi-Fi Alliance rule (WPA3 v3.5 '
          'section 11.2).',
    _ => null,
  };
}

/// What the network's AP advertises, derived from its configuration.
@immutable
class ScNetwork {
  const ScNetwork({
    required this.security,
    this.pmf = JrPmf.optional,
    this.band = JrBand.g5,
    this.wifi7 = false,
    this.h2eOnly = false,
  });

  final ScNetSecurity security;

  /// The PMF setting, for WPA2-Personal and WPA2-Enterprise.
  final JrPmf pmf;

  final JrBand band;

  /// A Wi-Fi 7 AP: it enables SAE type 24 and GCMP-256 as well (WPA3 v3.5
  /// §2.5, §3.4).
  final bool wifi7;

  /// The SAE hash-to-element only selector (123, Table 9-131), for the SAE
  /// modes.
  final bool h2eOnly;

  bool get isOpen => security == ScNetSecurity.open;

  /// MFPC and MFPR as advertised.
  JrPmf get pmfBits => switch (security) {
    ScNetSecurity.open => JrPmf.off,
    ScNetSecurity.wpa2Personal || ScNetSecurity.wpa2Enterprise => pmf,
    ScNetSecurity.wpa3Transition ||
    ScNetSecurity.wpa3EnterpriseTransition => JrPmf.optional,
    _ => JrPmf.required,
  };

  /// The AKM suites in the RSN element (WPA3 v3.5 §2.2 to §3.5).
  Set<ScAkm> get akms => switch (security) {
    ScNetSecurity.open => const <ScAkm>{},
    ScNetSecurity.owe => const <ScAkm>{ScAkm.owe},
    ScNetSecurity.wpa2Personal => const <ScAkm>{ScAkm.psk},
    ScNetSecurity.wpa3Transition => <ScAkm>{
      ScAkm.psk,
      ScAkm.sae,
      if (wifi7) ScAkm.saeExt,
    },
    ScNetSecurity.wpa3Personal => <ScAkm>{ScAkm.sae, if (wifi7) ScAkm.saeExt},
    ScNetSecurity.wpa2Enterprise => const <ScAkm>{ScAkm.dot1x},
    ScNetSecurity.wpa3EnterpriseTransition => const <ScAkm>{
      ScAkm.dot1x,
      ScAkm.dot1xSha256,
    },
    ScNetSecurity.wpa3Enterprise => const <ScAkm>{ScAkm.dot1xSha256},
    ScNetSecurity.wpa3Enterprise192 => const <ScAkm>{ScAkm.suiteB192},
  };

  /// Pairwise cipher suites: CCMP-128, plus GCMP-256 on a Wi-Fi 7 AP; only
  /// GCMP-256 for 192-bit (WPA3 v3.5 §3.5).
  Set<ScCipher> get pairwise => switch (security) {
    ScNetSecurity.open => const <ScCipher>{},
    ScNetSecurity.wpa3Enterprise192 => const <ScCipher>{ScCipher.gcmp256},
    _ => <ScCipher>{ScCipher.ccmp128, if (wifi7) ScCipher.gcmp256},
  };

  ScCipher get group => security == ScNetSecurity.wpa3Enterprise192
      ? ScCipher.gcmp256
      : ScCipher.ccmp128;

  /// The BIP cipher for protected group management frames.
  String get groupManagementCipher =>
      security == ScNetSecurity.wpa3Enterprise192
      ? 'BIP-GMAC-256'
      : 'BIP-CMAC-128';

  /// SAE must use hash-to-element: the selector is set, or the band is 6 GHz
  /// (a Wi-Fi Alliance rule, WPA3 v3.5 §11.2).
  bool get h2eRequired => security.usesSae && (h2eOnly || band == JrBand.g6);

  ScNetwork copyWith({
    ScNetSecurity? security,
    JrPmf? pmf,
    JrBand? band,
    bool? wifi7,
    bool? h2eOnly,
  }) => ScNetwork(
    security: security ?? this.security,
    pmf: pmf ?? this.pmf,
    band: band ?? this.band,
    wifi7: wifi7 ?? this.wifi7,
    h2eOnly: h2eOnly ?? this.h2eOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is ScNetwork &&
      other.security == security &&
      other.pmf == pmf &&
      other.band == band &&
      other.wifi7 == wifi7 &&
      other.h2eOnly == h2eOnly;

  @override
  int get hashCode => Object.hash(security, pmf, band, wifi7, h2eOnly);
}

// ── The verdict ─────────────────────────────────────────────────────────────

enum ScOutcome {
  associates('Associates'),
  neverTries('Never tries to associate'),
  refused('Refused'),
  notOffered('Not offered');

  const ScOutcome(this.label);

  final String label;

  /// Whether the association fails.
  bool get fails => this != associates;
}

/// The status codes the model can draw or names (Table 9-80, evidence B7).
/// The name is the standard's description, in plain words so it wraps at
/// phone width; the identifier is ROBUST_MANAGEMENT_POLICY_VIOLATION.
const (int, String) kStatusRobustMgmtPolicy = (
  31,
  'robust management frame policy violation',
);

@immutable
class ScVerdict {
  const ScVerdict({
    required this.outcome,
    required this.headline,
    required this.why,
    required this.source,
    this.helpDesk,
    this.akm,
    this.pairwise,
    this.group,
    this.pmfOn = false,
    this.wifi7 = false,
    this.wifi6Because,
    this.status,
  });

  final ScOutcome outcome;

  /// One line: "Associates with SAE (8), CCMP-128, PMF on".
  final String headline;

  /// The reason, in plain words.
  final String why;

  /// The documents that pin it.
  final String source;

  /// What the help desk sees, when it fails.
  final String? helpDesk;

  /// What the pair agreed on, when it associates.
  final ScAkm? akm;
  final ScCipher? pairwise;
  final ScCipher? group;
  final bool pmfOn;

  /// A Wi-Fi 7 connection (EHT negotiated).
  final bool wifi7;

  /// Both sides have Wi-Fi 7 but the association falls back to Wi-Fi 6:
  /// why; null otherwise.
  final String? wifi6Because;

  /// The refusal, when refused.
  final (int, String)? status;
}

/// A verdict and the ladder override that draws it.
@immutable
class ScResult {
  const ScResult({required this.verdict, required this.override});

  final ScVerdict verdict;
  final JrSecurityOverride override;
}

String _list(Iterable<String> xs) {
  final List<String> l = xs.toList();
  if (l.isEmpty) return 'nothing';
  if (l.length == 1) return l.first;
  return '${l.sublist(0, l.length - 1).join(', ')} and ${l.last}';
}

String _akms(Iterable<ScAkm> a) =>
    _list(ScAkm.preference.where(a.contains).map((ScAkm x) => x.tagged));

String _ciphers(Iterable<ScCipher> c) => _list(
  ScCipher.strongestFirst.where(c.contains).map((ScCipher x) => x.label),
);

const String _neverTriesHelpDesk =
    'The device says it can\'t connect, or never lists the network as one it '
    'can use. The AP has no log entry for it at all: it never sent an '
    'Authentication or Association Request. Only the device\'s own log, or a '
    'capture of its Probe Requests, shows it was there.';

/// Decides what happens when [client] meets [network].
ScVerdict evaluateSecurityVerdict(ScClient client, ScNetwork net) {
  final String band = net.band.label;

  // 1. Not allowed in this band at all.
  if (net.band == JrBand.g6 && !net.security.allowedIn6GHz) {
    return ScVerdict(
      outcome: ScOutcome.notOffered,
      headline: 'Not offered: 6 GHz does not allow ${net.security.label}',
      why:
          'No AP may offer ${net.security.label} in 6 GHz, so there is no '
          'such network to associate with. It is not swapped for WPA3 '
          'quietly: the AP has to be set up for WPA3 or OWE there.',
      source: net.security.sixGhzRule!,
      helpDesk:
          'The network does not appear in 6 GHz at all. The AP\'s '
          'configuration is refused or the 6 GHz radio stays off for this '
          'SSID, depending on the vendor.',
    );
  }

  // 2. No radio in the band.
  if (!client.bands.contains(net.band)) {
    return ScVerdict(
      outcome: ScOutcome.neverTries,
      headline: 'Never tries to associate: no $band radio',
      why:
          'The client has no $band radio, so it never hears this network. '
          'Nothing else matters until it can.',
      source: 'The client\'s own radio; nothing in 802.11 applies.',
      helpDesk:
          'The network never appears in the device\'s list. The AP has no '
          'record of it.',
    );
  }

  final bool bothWifi7 = client.wifi7 && net.wifi7;
  const String wifi7Source =
      'WPA3 v3.5 sections 11.3, 2.5 and 3.4; IEEE 802.11be-2024 12.12.9 '
      'and 12.6.3.1 NOTE 1.';

  // 3. Open: no RSN element.
  if (net.isOpen) {
    return ScVerdict(
      outcome: ScOutcome.associates,
      headline: bothWifi7
          ? 'Associates as Wi-Fi 6, open: nothing is encrypted'
          : 'Associates, open: nothing is encrypted',
      why:
          'An open network has no RSN element, so there is nothing to agree '
          'on. Anyone can associate, and nothing is encrypted.',
      source: bothWifi7
          ? 'Open networks are not allowed in a Wi-Fi 7 connection ($wifi7Source)'
          : 'IEEE 802.11-2024 12.6.3.',
      wifi6Because: bothWifi7
          ? 'A Wi-Fi 7 connection is not allowed on an open network (OWE '
                'is).'
          : null,
    );
  }

  // 4. Key management in common.
  final Set<ScAkm> common = client.akms.intersection(net.akms);
  if (common.isEmpty) {
    return ScVerdict(
      outcome: ScOutcome.neverTries,
      headline: 'Never tries to associate: no key management in common',
      why:
          'The network offers ${_akms(net.akms)}. The client knows '
          '${_akms(client.akms)}. Nothing matches, so the client declines '
          'before it sends a single Authentication or Association Request '
          'frame. No status code: nothing was refused.',
      source:
          'IEEE 802.11-2024 12.6.3 ("shall decline to associate"); WPA3 v3.5 '
          'section 4.1. AKM numbers from Table 9-190.',
      helpDesk: _neverTriesHelpDesk,
    );
  }

  // 5. Ciphers in common.
  final Set<ScCipher> pairwise = client.ciphers.intersection(net.pairwise);
  if (pairwise.isEmpty || !client.ciphers.contains(net.group)) {
    return ScVerdict(
      outcome: ScOutcome.neverTries,
      headline: 'Never tries to associate: no cipher in common',
      why:
          'The network encrypts with ${_ciphers(net.pairwise)} (group '
          '${net.group.label}). The client can do ${_ciphers(client.ciphers)}. '
          'Nothing matches, so it declines without sending a frame.',
      source: 'IEEE 802.11-2024 12.6.3; cipher suites from Table 9-188.',
      helpDesk: _neverTriesHelpDesk,
    );
  }

  // 6. PMF, for a client that reads the bits (Table 12-5).
  final JrPmf ap = net.pmfBits;
  final bool apMfpc = ap != JrPmf.off;
  final bool apMfpr = ap == JrPmf.required;
  if (client.pmf.readsBits) {
    if (apMfpr && !client.pmf.mfpc) {
      return const ScVerdict(
        outcome: ScOutcome.neverTries,
        headline: 'Never tries to associate: the network requires PMF',
        why:
            'The network requires PMF (MFPR 1) and the client cannot do it '
            '(MFPC 0). The client reads the bits and does not try, so the '
            'AP never has to refuse it.',
        source:
            'IEEE 802.11-2024 Table 12-5: "The STA shall not associate with '
            'the AP".',
        helpDesk: _neverTriesHelpDesk,
      );
    }
    if (client.pmf.mfpr && !apMfpc) {
      return const ScVerdict(
        outcome: ScOutcome.neverTries,
        headline: 'Never tries to associate: the client requires PMF',
        why:
            'The client requires PMF (MFPR 1) and the network does not offer '
            'it (MFPC 0), so the client does not try.',
        source:
            'IEEE 802.11-2024 Table 12-5: "The STA shall not associate with '
            'the AP".',
        helpDesk: _neverTriesHelpDesk,
      );
    }
  }
  final bool pmfOn = client.pmf.mfpc && apMfpc;

  // 7. What the client will actually use.
  bool droppedForPmf = false;
  bool droppedForH2e = false;
  final Set<ScAkm> usable = <ScAkm>{};
  for (final ScAkm a in common) {
    if (a.needsPmf && !pmfOn) {
      droppedForPmf = true;
      continue;
    }
    if (a.isSae && net.h2eRequired && !client.h2e) {
      droppedForH2e = true;
      continue;
    }
    usable.add(a);
  }

  // 8. A client older than PMF against PMF required: it tries, and is
  //    refused (Table 12-5, the AP's column).
  if (!client.pmf.readsBits && apMfpr && usable.isNotEmpty) {
    final ScAkm pick = ScAkm.preference.firstWhere(usable.contains);
    return ScVerdict(
      outcome: ScOutcome.refused,
      headline: 'Refused: status 31 at the Association Response',
      why:
          'This client is older than PMF. It does not know what the '
          'network\'s "PMF required" bit means, so it ignores it and tries '
          'with ${pick.tagged} and PMF off. The AP refuses the Association '
          'Request with status 31, "Robust management frame policy '
          'violation."',
      source:
          'IEEE 802.11-2024 Table 12-5 and its NOTE ("STAs conformant with a '
          'previous revision ... might not ascribe a meaning to the MFPC and '
          'MFPR subfields"); status 31, Table 9-80.',
      helpDesk:
          'The device says it can\'t connect, often with no reason. The AP '
          'log shows an association rejected with status 31 (robust '
          'management frame policy). Set PMF to optional on this SSID, or '
          'give the old device its own SSID.',
      akm: pick,
      status: kStatusRobustMgmtPolicy,
    );
  }

  if (usable.isEmpty) {
    if (droppedForH2e) {
      final bool six = net.band == JrBand.g6;
      return ScVerdict(
        outcome: ScOutcome.neverTries,
        headline: 'Never tries to associate: the network requires SAE H2E',
        why:
            'The network accepts SAE only with hash-to-element (H2E), and '
            'this client knows only the older hunting-and-pecking method. It '
            'does not try.',
        source: six
            ? 'In 6 GHz this is a Wi-Fi Alliance rule: WPA3 v3.5 section 11.2 bans '
                  'hunting-and-pecking. IEEE 802.11-2024 12.12.2 does not '
                  'mention H2E.'
            : 'BSS membership selector 123, "SAE Hash to Element Only", IEEE '
                  '802.11-2024 Table 9-131.',
        helpDesk: _neverTriesHelpDesk,
      );
    }
    return ScVerdict(
      outcome: ScOutcome.neverTries,
      headline: 'Never tries to associate: WPA3 needs PMF',
      why: droppedForPmf
          ? 'The only key management in common is '
                '${_akms(common)}, and that needs PMF, which this pair will '
                'not turn on. The client does not try.'
          : 'Nothing in common can be used.',
      source:
          'WPA3 v3.5 section 2.2 (a WPA3 client will not connect without PMF); IEEE '
          '802.11-2024 Table 12-5.',
      helpDesk: _neverTriesHelpDesk,
    );
  }

  // 9. It associates. Wi-Fi 7, or not.
  final bool gcmpBoth = pairwise.contains(ScCipher.gcmp256);
  bool wifi7Ok(ScAkm a) => a.allowedForWifi7 && (a == ScAkm.owe || gcmpBoth);
  final List<ScAkm> ordered = ScAkm.preference.where(usable.contains).toList();
  ScAkm pick = ordered.first;
  bool wifi7 = false;
  String? wifi6Because;
  if (bothWifi7) {
    final List<ScAkm> eht = ordered.where(wifi7Ok).toList();
    if (pmfOn && eht.isNotEmpty) {
      pick = eht.first;
      wifi7 = true;
    } else if (!pmfOn) {
      wifi6Because = 'PMF is off, and a Wi-Fi 7 connection requires it.';
    } else if (ordered.any((ScAkm a) => a.allowedForWifi7)) {
      wifi6Because =
          'GCMP-256 is not on both sides, and a Wi-Fi 7 connection needs it.';
    } else if (usable.contains(ScAkm.sae)) {
      wifi6Because =
          'SAE is available only as type 8. A Wi-Fi 7 connection needs SAE '
          'type 24.';
    } else if (usable.contains(ScAkm.psk)) {
      wifi6Because = 'PSK is not allowed in a Wi-Fi 7 connection.';
    } else {
      wifi6Because =
          '802.1X with SHA-1 (type 1) is not allowed in a Wi-Fi 7 '
          'connection.';
    }
  }
  final ScCipher cipher = wifi7 && pick != ScAkm.owe
      ? ScCipher.gcmp256
      : ScCipher.strongestFirst.firstWhere(pairwise.contains);
  final String agreed =
      '${pick.tagged}, ${cipher.label}, PMF ${pmfOn ? 'on' : 'off'}';
  final String headline = wifi7
      ? 'Associates: a Wi-Fi 7 connection with $agreed'
      : wifi6Because != null
      ? 'Associates as Wi-Fi 6 with $agreed'
      : 'Associates with $agreed';

  final List<String> why = <String>[];
  if (net.akms.length > 1) {
    why.add(
      'The network offers ${_akms(net.akms)}. The client picks '
      '${pick.tagged}, the ${common.length > 1 ? 'strongest it can use' : 'only one it knows'}.',
    );
  } else {
    why.add('Both sides know ${pick.tagged}.');
  }
  if (pairwise.length > 1) {
    why.add('Pairwise cipher ${cipher.label}, the strongest both offer.');
  }
  why.add(
    pmfOn
        ? 'PMF is on: both sides set MFPC.'
        : 'PMF is off: ${client.pmf.readsBits ? (client.pmf.mfpc ? 'the network does not offer it' : 'the client cannot do it') : 'the client is older than PMF'}.',
  );
  if (wifi6Because != null) {
    why.add('Not a Wi-Fi 7 connection: $wifi6Because');
  } else if (net.wifi7 && !client.wifi7) {
    why.add('The client has no Wi-Fi 7 radio.');
  }
  if (droppedForH2e) {
    why.add(
      'SAE is not used: the network requires H2E and the client lacks it.',
    );
  }
  return ScVerdict(
    outcome: ScOutcome.associates,
    headline: headline,
    why: why.join(' '),
    source: bothWifi7
        ? '$wifi7Source Selection: IEEE 802.11-2024 12.6.3.'
        : 'IEEE 802.11-2024 12.6.3 and Table 12-5; WPA3 v3.5 section 4.2.1 for the '
              'order. Cipher choice is the model\'s own reading.',
    akm: pick,
    pairwise: cipher,
    group: net.group,
    pmfOn: pmfOn,
    wifi7: wifi7,
    wifi6Because: wifi6Because,
  );
}

/// The verdict and the Join ladder override for [client] and [net].
ScResult evaluateSecurity(ScClient client, ScNetwork net) {
  final ScVerdict v = evaluateSecurityVerdict(client, net);
  final JrPmf apPmf = net.pmfBits;
  final String apAkm = net.isOpen ? 'none' : _akms(net.akms);
  final String apCiphers = net.isOpen
      ? 'none'
      : 'pairwise ${_ciphers(net.pairwise)}; group ${net.group.label}';
  final List<JrField> apExtra = <JrField>[
    if (net.h2eRequired && net.h2eOnly)
      ('BSS membership selector', '123: SAE hash-to-element only'),
    if (net.h2eRequired && !net.h2eOnly)
      ('SAE password method', 'hash-to-element only (6 GHz)'),
    if (net.wifi7) ('EHT Operation', 'a Wi-Fi 7 AP'),
  ];

  // The frames: what the pair uses, or for a failure what the network is.
  final ScAkm? akm = v.akm;
  final JrSecurity flow =
      akm?.flow ??
      switch (net.security) {
        ScNetSecurity.open => JrSecurity.open,
        ScNetSecurity.owe => JrSecurity.owe,
        ScNetSecurity.wpa2Personal => JrSecurity.psk,
        ScNetSecurity.wpa3Transition ||
        ScNetSecurity.wpa3Personal => JrSecurity.sae,
        _ => JrSecurity.dot1x,
      };
  final JrPmf pmf = v.outcome == ScOutcome.associates && v.pmfOn
      ? (client.pmf.mfpr && apPmf == JrPmf.required
            ? JrPmf.required
            : JrPmf.optional)
      : JrPmf.off;
  final String clientPmf = client.pmf.readsBits
      ? client.pmf.bits
      : 'MFPC 0, MFPR 0 (older than PMF: it does not know these bits)';
  final String clientCiphers = v.pairwise == null
      ? 'pairwise ${_ciphers(client.ciphers.intersection(net.pairwise))}, '
            'group ${net.group.label}'
      : 'pairwise ${v.pairwise!.label}, group ${net.group.label}';

  final JrStop stop = switch (v.outcome) {
    ScOutcome.associates => JrStop.none,
    ScOutcome.refused => JrStop.refusedAtAssociation,
    ScOutcome.notOffered => JrStop.notOffered,
    ScOutcome.neverTries =>
      client.bands.contains(net.band) ? JrStop.afterScan : JrStop.noBand,
  };

  final String band = net.band.label;
  final (String?, String?) stopText = switch (stop) {
    JrStop.none => (null, null),
    JrStop.noBand => (
      'Channel ${targetChannelFor(net.band)}, $band: no $band radio',
      'The AP beacons on channel ${targetChannelFor(net.band)} in $band, but '
          'the client has no $band radio. It never hears the network, so it '
          'never starts to associate.',
    ),
    JrStop.notOffered => (
      'No answer: no $band AP may offer this',
      'The client probes on channel ${targetChannelFor(net.band)}, and no AP '
          'answers for this network: no AP may offer '
          '${net.security.label} in $band. (A passive scan simply hears '
          'nothing; the probe is drawn so there is something to see.)',
    ),
    JrStop.afterScan => (
      'RSN: $apAkm; nothing this client can use',
      'The client reads the security this frame advertises and finds '
          'nothing it can use, so this is the last frame. It sends no '
          'Authentication and no Association Request; Probe Requests may '
          'still go out while it keeps scanning.',
    ),
    JrStop.refusedAtAssociation => (
      'Status 31, no AID',
      'Status 31, "Robust management frame policy violation" (Table '
          '9-80). The '
          'network requires PMF; the client asked with PMF off. No '
          'association, no keys, nothing encrypted.',
    ),
  };

  final String? faultNote = switch (stop) {
    JrStop.none => null,
    JrStop.noBand =>
      'The client never hears the network: it has no $band radio.',
    JrStop.notOffered =>
      'Nothing to associate with: no AP may offer ${net.security.label} in '
          '$band.',
    JrStop.afterScan =>
      '${v.headline}. No Authentication or Association Request is ever '
          'sent.',
    JrStop.refusedAtAssociation =>
      'The AP refused the association with status 31: the network requires '
          'PMF and the client is older than PMF.',
  };

  return ScResult(
    verdict: v,
    override: JrSecurityOverride(
      security: flow,
      pmf: pmf,
      apAkm: apAkm,
      apCiphers: apCiphers,
      apPmf: apPmf.bits,
      apExtra: apExtra,
      clientAkm: akm?.tagged ?? 'none in common',
      clientCiphers: clientCiphers,
      clientPmf: clientPmf,
      groupManagementCipher: net.groupManagementCipher,
      eht: v.wifi7,
      stop: stop,
      statusCode: v.status,
      stopDetail: stopText.$1,
      stopDescription: stopText.$2,
      faultNote: faultNote,
      helpDesk: v.helpDesk,
    ),
  );
}

/// The Join ladder for [client] and [net], with the scan and timing
/// settings of [base]. [base]'s band and PMF must match [net]'s.
JrSequence buildSecurityCompat(JrConfig base, ScClient client, ScNetwork net) =>
    buildJoin(base, security: evaluateSecurity(client, net).override);
