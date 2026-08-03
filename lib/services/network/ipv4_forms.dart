// Ipv4Forms — the same 32-bit address written the other ways it turns up:
// as an integer, as hex, and as binary with the prefix boundary drawn ON the
// bits.
//
// WHY THE BINARY FORM EARNS ITS ROW. Every sentence written about masking says
// "the prefix marks where the network part ends and the host part begins", and
// the sentence teaches less than the picture. Rendering the address and the
// mask as 32 bits with a separator sitting exactly at the prefix, mid-octet
// when the prefix is mid-octet, makes a /22 obvious in a way "255.255.252.0"
// never does.
//
// THE SEPARATOR RULE. The boundary character is `/`, and it REPLACES the octet
// dot when the two coincide, so there is exactly one separator at any position
// and the eye can trust it:
//     /22 → 00001010.00010100.000000/00.00000000
//     /24 → 00001010.00010100.00000000/00000000
//     /0  → /00001010.00010100.00000000.00000000   (no network bits)
//     /32 → 00001010.00010100.00000000.00000000/   (no host bits)
//
// The integer form is what an ACL generator, a database column, or a log line
// often carries, and it is the form nothing else in the app produced.
//
// PURE: no Flutter, no I/O.

/// Alternate renderings of one IPv4 address.
class Ipv4Forms {
  const Ipv4Forms._();

  /// The unsigned 32-bit integer value, e.g. `10.20.0.0` → 169082880.
  static int toInteger(int addr) => addr & 0xFFFFFFFF;

  /// Zero-padded hex with an `0x` prefix, e.g. `0x0A140000`.
  static String toHex(int addr) =>
      '0x${(addr & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0')}';

  /// Dotted hex, one byte per octet, e.g. `0A.14.00.00`. The form a packet
  /// decoder shows.
  static String toDottedHex(int addr) {
    final int v = addr & 0xFFFFFFFF;
    return <String>[
      for (int shift = 24; shift >= 0; shift -= 8)
        ((v >> shift) & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0'),
    ].join('.');
  }

  /// 32 bits, dotted per octet. When [boundary] is given (0–32), a `/` is
  /// placed after that many bits and REPLACES the octet dot if they coincide.
  /// A boundary of 0 renders as a leading `/`; a boundary of 32 as a trailing
  /// one.
  static String toBinary(int addr, {int? boundary}) {
    final int v = addr & 0xFFFFFFFF;
    final StringBuffer out = StringBuffer();
    if (boundary == 0) out.write('/');
    for (int i = 0; i < 32; i++) {
      out.write((v >> (31 - i)) & 1);
      final int emitted = i + 1;
      if (boundary != null && emitted == boundary) {
        out.write('/');
      } else if (emitted % 8 == 0 && i < 31) {
        out.write('.');
      }
    }
    return out.toString();
  }
}
