// Why a Long Wi-Fi Password Matters More on WPA2: the pure model for the
// Wi-Fi Classroom tool (wpa2-password).
//
// CLEAN-ROOM BUILD (2026-09-27) per myPKA
// Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md, candidate 6
// and the section 5 anti-patterns, approved by Keith.
//
// THE LESSON. With WPA2-Personal, anyone in range who records one
// association (its 4-way handshake) can test password guesses on their own
// computer, as fast as that computer runs, and the AP never sees a guess.
// With WPA3-Personal (SAE, Simultaneous Authentication of Equals) a recording
// lets no guess be checked: each guess needs a live exchange with the AP,
// which the AP can notice and limit. In WPA3 transition mode the same
// password also admits WPA2 devices, so one recorded WPA2 association
// exposes that password to offline guessing again.
//
// SOURCES. The Wi-Fi Alliance document was read for this build (fetched
// 2026-09-27); the IEEE 802.11 rules were NOT reopened and are the standard's
// well-known pass-phrase rules, the same 8-to-63 limit Join a Network uses:
//   - Wi-Fi Alliance, "WPA3 Security Considerations", November 2019, p. 3:
//     "Unlike PSK, SAE is resistant to offline dictionary attacks. The only
//     way for an attacker to learn a password is through repeated active
//     attacks, each of which tests whether a single guess of the password is
//     correct or not." Same page: the 5,000-password example (WPA2 offline:
//     probability of success 1; WPA3: 0.5 only after 2,500 active attacks),
//     and "implementations should limit authentication attempts".
//   - Same document, p. 6 (WPA3-Personal Transition Mode): "the common
//     password of a WPA3-Personal Transition Mode network can be determined
//     by attacking a WPA2-Personal device using a simple offline dictionary
//     attack", and WPA3 clients "will still benefit from the forward-secrecy
//     that SAE affords".
//   - IEEE 802.11, the pass-phrase-to-PSK mapping: a pass-phrase is 8 to 63
//     characters, each in the ASCII range 32 to 126 (95 characters), and the
//     PMK is derived from the pass-phrase and the SSID alone, so a recorded
//     4-way handshake plus the password gives the session keys (no forward
//     secrecy on WPA2-Personal).
//
// NO TIMES. Crack-time figures depend on the attacker's hardware and are
// precision theater (brief section 5, anti-pattern 2). The model never
// computes a rate or a duration. It computes only the number of possible
// passwords (plain arithmetic: characters ^ length) and, for the WFA example,
// the chance of success after a number of guesses (guesses / possibilities,
// guessing without repeats).
//
// NOT A HOW-TO. No tool names, no commands, no steps: the model names where a
// guess is checked and what sets the pace, nothing more.
//
// Pure Dart, no Flutter imports. ASCII only, no em dashes (GL-004).

import 'dart:math' as math;

/// Stable catalog tool id: backs the route, the help entry and the tests.
const String kWpa2PasswordToolId = 'wpa2-password';

/// The network's security setting: the tool's one main control.
enum WpSecurity {
  wpa2('WPA2-Personal', 'WPA2'),
  wpa3('WPA3-Personal (SAE)', 'WPA3'),
  transition('WPA3 transition mode', 'Transition');

  const WpSecurity(this.label, this.short);

  /// Full name, used in readouts and help.
  final String label;

  /// Segment label on the selector.
  final String short;

  /// A WPA2 association happens on this network, so a recording of one can
  /// be used to check guesses offline.
  bool get exposedOffline => this != WpSecurity.wpa3;

  /// Each guess is checked in a live exchange with the AP.
  bool get guessesAtAp => this == WpSecurity.wpa3;
}

/// Which characters the password is drawn from. The sizes are counts of
/// characters, not settings: 26 letters, 10 digits, and the 95 printable ASCII
/// characters (32 to 126) that IEEE 802.11 allows in a pass-phrase.
enum WpCharset {
  lower(26, 'Lowercase letters (26)', 'lowercase letters'),
  lowerDigits(
    36,
    'Lowercase letters and digits (36)',
    'lowercase letters and digits',
  ),
  mixed(
    62,
    'Upper and lowercase letters and digits (62)',
    'upper and lowercase letters and digits',
  ),
  printable(95, 'Any keyboard character (95)', 'any keyboard character');

  const WpCharset(this.size, this.label, this.phrase);

  /// How many different characters each position can hold.
  final int size;

  /// Menu label.
  final String label;

  /// In a sentence: "a password of 8 lowercase letters".
  final String phrase;
}

/// Where a guess gets checked.
enum WpGuessPlace {
  offline("On the attacker's own computer"),
  atAp('Only at your AP, in a live exchange');

  const WpGuessPlace(this.label);
  final String label;
}

/// One network, one password. Immutable; every change returns a copy.
class WpConfig {
  const WpConfig({
    this.security = WpSecurity.wpa2,
    this.length = defaultLength,
    this.charset = WpCharset.lower,
  });

  /// IEEE 802.11 pass-phrase limits.
  static const int minLength = 8;
  static const int maxLength = 63;

  /// "The same short password": the shortest a WPA pass-phrase may be.
  static const int defaultLength = 8;

  final WpSecurity security;
  final int length;
  final WpCharset charset;

  WpConfig withSecurity(WpSecurity s) =>
      WpConfig(security: s, length: length, charset: charset);

  WpConfig withLength(int n) => WpConfig(
    security: security,
    length: n.clamp(minLength, maxLength),
    charset: charset,
  );

  WpConfig withCharset(WpCharset c) =>
      WpConfig(security: security, length: length, charset: c);

  /// Possible passwords: characters ^ length. Exact.
  BigInt get possiblePasswords => wpPossible(charset.size, length);

  /// How many times one more character multiplies the count.
  int get perExtraCharacter => charset.size;

  WpGuessPlace get guessPlace =>
      security.guessesAtAp ? WpGuessPlace.atAp : WpGuessPlace.offline;

  /// What sets the pace of guessing.
  String get paceLabel => security.guessesAtAp
      ? 'One guess per live exchange with the AP'
      : "Only the attacker's computer";

  /// Whether the AP records anything while the guessing goes on.
  bool get apSeesGuesses => security.guessesAtAp;

  /// Failed attempts the AP logs after [guesses] wrong guesses.
  int apFailedAttempts(int guesses) => apSeesGuesses ? guesses : 0;

  /// Traffic recorded earlier, if the password becomes known later.
  String get recordedTraffic => switch (security) {
    WpSecurity.wpa2 =>
      'Readable: the password and the recorded 4-way '
          'handshake give the keys',
    WpSecurity.wpa3 => 'Stays unreadable: SAE gives forward secrecy',
    WpSecurity.transition =>
      'Readable for WPA2 devices; WPA3 devices keep '
          'forward secrecy',
  };

  @override
  bool operator ==(Object other) =>
      other is WpConfig &&
      other.security == security &&
      other.length == length &&
      other.charset == charset;

  @override
  int get hashCode => Object.hash(security, length, charset);
}

/// characters ^ length, exact.
BigInt wpPossible(int characters, int length) =>
    BigInt.from(characters).pow(length);

/// The chance a guesser has found a randomly chosen password after
/// [guesses] different guesses out of [possible]: guesses / possible, capped
/// at 1. The Wi-Fi Alliance's own arithmetic (5,000 passwords: 0.5 after
/// 2,500 attempts).
double wpChanceFound(int guesses, BigInt possible) {
  if (guesses <= 0 || possible <= BigInt.zero) return 0;
  final BigInt g = BigInt.from(guesses);
  if (g >= possible) return 1;
  return g / possible;
}

/// The Wi-Fi Alliance's worked example (WPA3 Security Considerations, 2019,
/// p. 3): a password chosen at random from 5,000, and the attacker knows the
/// list.
abstract final class WpWfaExample {
  static const int passwords = 5000;
  static const int halfwayAttempts = 2500;
}

/// Number formatting for the readouts. No times, anywhere.
abstract final class WpFormat {
  /// Digits in [n], for "a 12-digit number".
  static int digits(BigInt n) => n.abs().toString().length;

  /// Exact with thousands separators up to 18 digits; beyond that,
  /// "about 3.9 x 10^124".
  static String count(BigInt n) {
    final String s = n.toString();
    if (s.length <= 18) return group(s);
    final int exp = s.length - 1;
    final double mant = double.parse('${s[0]}.${s.substring(1, 4)}');
    // Round to one decimal; 9.96 rounds up to 10.0, so carry.
    double m = (mant * 10).round() / 10;
    int e = exp;
    if (m >= 10) {
      m /= 10;
      e += 1;
    }
    return 'about ${m.toStringAsFixed(1)} x 10^$e';
  }

  /// "1234567" -> "1,234,567".
  static String group(String digits) {
    final StringBuffer b = StringBuffer();
    final int n = digits.length;
    for (int i = 0; i < n; i++) {
      b.write(digits[i]);
      final int left = n - 1 - i;
      if (left > 0 && left % 3 == 0) b.write(',');
    }
    return b.toString();
  }

  static String integer(int n) => group(n.toString());

  /// "50%" or "0.5" style probability, as a percentage with no false
  /// precision: whole percent from 1% up, "less than 1%" below.
  static String chance(double p) {
    if (p <= 0) return '0%';
    if (p >= 1) return '100%';
    final double pct = p * 100;
    if (pct < 1) return 'less than 1%';
    return '${pct.round()}%';
  }

  /// log10 of a BigInt, for scaling bars; exact enough for drawing.
  static double log10(BigInt n) {
    if (n <= BigInt.zero) return 0;
    final String s = n.toString();
    if (s.length <= 15) return math.log(n.toDouble()) / math.ln10;
    final double lead = double.parse('${s[0]}.${s.substring(1, 15)}');
    return (s.length - 1) + math.log(lead) / math.ln10;
  }
}
