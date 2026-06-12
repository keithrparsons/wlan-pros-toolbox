// Diffie-Hellman reference data — compile-time const, source of truth for the
// data-driven Diffie-Hellman screen (Tier-1, Pass 2b 2026-06-12).
//
// Mostly visual: the staged paint-mixing diagram is embedded; this data backs a
// short native explainer (the paint analogy paired with the real modular-
// exponentiation math) tied to WPA3 SAE.
//
// Glyph note: math tokens use ASCII (g^a mod p); no em dash in prose.

/// One stage of the exchange: the paint analogy and the math beside it.
class DhStage {
  const DhStage({
    required this.stage,
    required this.analogy,
    required this.math,
  });

  /// Stage label, e.g. `Alice mixes & sends`.
  final String stage;

  /// Paint-mixing analogy for the stage.
  final String analogy;

  /// The matching math, e.g. `A = g^a mod p (public)`.
  final String math;
}

/// The exchange stages, paint analogy + math.
const List<DhStage> kDhStages = <DhStage>[
  DhStage(
    stage: 'Public parameters',
    analogy: 'Common public paint, shared and known to all',
    math: 'base g, modulus p (public)',
  ),
  DhStage(
    stage: "Alice's private",
    analogy: "Alice's secret color",
    math: 'private exponent a (never sent)',
  ),
  DhStage(
    stage: "Bob's private",
    analogy: "Bob's secret color",
    math: 'private exponent b (never sent)',
  ),
  DhStage(
    stage: 'Alice mixes & sends',
    analogy: "Common + Alice's secret = Alice's mixture",
    math: 'A = g^a mod p (public)',
  ),
  DhStage(
    stage: 'Bob mixes & sends',
    analogy: "Common + Bob's secret = Bob's mixture",
    math: 'B = g^b mod p (public)',
  ),
  DhStage(
    stage: 'Alice computes secret',
    analogy: "Bob's mixture + Alice's secret",
    math: 's = B^a mod p',
  ),
  DhStage(
    stage: 'Bob computes secret',
    analogy: "Alice's mixture + Bob's secret",
    math: 's = A^b mod p',
  ),
  DhStage(
    stage: 'They match',
    analogy: 'Both reach the same blended color',
    math: '(g^a)^b mod p = (g^b)^a mod p',
  ),
  DhStage(
    stage: 'Eavesdropper',
    analogy: 'Sees the common paint and both mixtures, cannot un-mix',
    math: 'recovering a or b = discrete-log problem (hard)',
  ),
];

/// The plain-language summary paragraph.
const String kDhSummary =
    'Two parties derive a shared secret over a public channel without ever '
    'transmitting their private values. Mixing paint is easy (one-way); '
    'un-mixing is hard. The math equivalent: computing g^a mod p is fast, but '
    'recovering a from it (the discrete-logarithm problem) is hard, so an '
    'eavesdropper who sees the common paint and both mixtures still cannot '
    'recover either secret.';

/// The eavesdropper verdict, carried as a danger callout (paired with the word).
const String kDhEavesdropperVerdict =
    'A passive listener captures the public base, the modulus, and both '
    'mixtures, yet still cannot recover either private exponent. That is the '
    'discrete-logarithm hardness the exchange rests on.';

/// The WLAN relevance note (Wi-Fi tie-in).
const String kDhWlanRelevance =
    'Diffie-Hellman is the basis of SAE (Simultaneous Authentication of Equals), '
    'the Dragonfly handshake in WPA3. It replaced WPA2 pre-shared-key 4-way '
    'exchange and resists offline dictionary attacks, because the password is '
    'never exposed to a passive listener.';
