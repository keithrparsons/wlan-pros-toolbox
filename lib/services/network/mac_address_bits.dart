// MacAddressBits — decode the two control bits in a MAC address and derive the
// EUI-64 interface identifier a SLAAC address is built from.
//
// WHY THIS IS A WI-FI TOOL, NOT A GENERIC CONVERTER. Both facts a WLAN engineer
// meets weekly live in the first octet of a MAC:
//
//   * The I/G bit (0x01 of the first octet) says unicast or group. A frame
//     addressed to a group address is not addressed to one NIC.
//   * The U/L bit (0x02 of the first octet) says whether the address came out
//     of an IEEE block or was made up by software. It is the bit iOS and
//     Android set when a phone randomizes its Wi-Fi MAC, and it is the bit many
//     APs set on the extra BSSIDs they derive from a radio's base MAC when the
//     radio carries more than one SSID. "Why does this client show no vendor"
//     and "why do these BSSIDs share three octets" are the same bit.
//
// EUI-64 is the other half: RFC 4291 Appendix A builds an IPv6 interface
// identifier from a 48-bit MAC by inserting FF:FE in the middle and INVERTING
// the U/L bit. That inversion is the step people get wrong, so this service
// reports both the plain IEEE EUI-64 (insertion only) and the modified EUI-64
// (insertion plus inversion) rather than collapsing them into one row.
//
// HONESTY: an EUI-64 interface identifier is defined for a unicast interface.
// For a group / multicast / broadcast address there is no NIC identity to
// derive, so this service returns no EUI-64 and says why. It never renders a
// derivation that would be meaningless.
//
// PURE: no Flutter, no I/O, no asset. Every path is deterministic integer math
// over 6 bytes and is unit-testable directly.

import 'ipv6_address.dart';

/// Whether the address targets one NIC or a group of them (the I/G bit).
enum MacCast {
  /// I/G bit clear — a single interface.
  unicast,

  /// I/G bit set — a group / multicast address (broadcast is the all-ones
  /// case of this).
  multicast,
}

/// Where the address came from (the U/L bit).
enum MacAdministration {
  /// U/L bit clear — assigned from an IEEE-registered block.
  global,

  /// U/L bit set — assigned locally by software. Randomized client MACs and
  /// many derived BSSIDs look like this.
  local,
}

/// The decoded control bits and EUI-64 derivation for one MAC address. Always
/// returned, never thrown: an unparseable input comes back with [isValid] false
/// and a user-facing [error].
class MacBitsResult {
  const MacBitsResult({
    required this.isValid,
    this.error,
    this.colonForm,
    this.hyphenForm,
    this.ciscoForm,
    this.bareForm,
    this.firstOctetHex,
    this.firstOctetBinary,
    this.cast,
    this.administration,
    this.isBroadcast = false,
    this.ulFlippedForm,
    this.eui64,
    this.modifiedEui64,
    this.linkLocal,
    this.eui64UnavailableReason,
  });

  /// Convenience constructor for a rejected input.
  const MacBitsResult.invalid(String message)
    : isValid = false,
      error = message,
      colonForm = null,
      hyphenForm = null,
      ciscoForm = null,
      bareForm = null,
      firstOctetHex = null,
      firstOctetBinary = null,
      cast = null,
      administration = null,
      isBroadcast = false,
      ulFlippedForm = null,
      eui64 = null,
      modifiedEui64 = null,
      linkLocal = null,
      eui64UnavailableReason = null;

  final bool isValid;

  /// Set only when [isValid] is false.
  final String? error;

  /// `b8:27:eb:01:23:45` — the app's canonical lower-case colon form.
  final String? colonForm;

  /// `B8-27-EB-01-23-45` — the IEEE / Windows upper-case hyphen form.
  final String? hyphenForm;

  /// `b827.eb01.2345` — the Cisco three-group dotted form.
  final String? ciscoForm;

  /// `b827eb012345` — no separators, the form most capture tools paste.
  final String? bareForm;

  /// The first octet as two upper-case hex digits, e.g. `B8`.
  final String? firstOctetHex;

  /// The first octet as 8 binary digits, most-significant bit first, e.g.
  /// `10111000`. The last two characters are the U/L bit then the I/G bit.
  final String? firstOctetBinary;

  /// Unicast or multicast, from the I/G bit.
  final MacCast? cast;

  /// Global or local, from the U/L bit.
  final MacAdministration? administration;

  /// True only for `ff:ff:ff:ff:ff:ff`.
  final bool isBroadcast;

  /// The same address with the U/L bit inverted. For a locally-administered
  /// address this is the globally-administered form whose first three octets
  /// may be a real OUI; for a global address it is the local form. Always
  /// present for a valid input, because the flip is defined either way.
  final String? ulFlippedForm;

  /// The IEEE EUI-64: FF:FE inserted between octets 3 and 4, U/L bit UNCHANGED.
  /// Null for a group address.
  final String? eui64;

  /// The modified EUI-64 interface identifier of RFC 4291 Appendix A: the
  /// EUI-64 with the U/L bit inverted, in four 4-hex-digit groups
  /// (`ba27:ebff:fe01:2345`). Null for a group address.
  final String? modifiedEui64;

  /// The link-local address SLAAC builds from [modifiedEui64], canonically
  /// compressed (`fe80::ba27:ebff:fe01:2345`). Null for a group address.
  final String? linkLocal;

  /// Why there is no EUI-64, when there is none. Null when [eui64] is set.
  final String? eui64UnavailableReason;
}

/// Pure decoder for the MAC control bits and the EUI-64 derivation.
class MacAddressBits {
  const MacAddressBits._();

  /// I/G bit — set means a group (multicast) address.
  static const int igBit = 0x01;

  /// U/L bit — set means locally administered.
  static const int ulBit = 0x02;

  /// Decode [raw]. Accepts colon, hyphen, Cisco-dot, space-separated and
  /// bare-hex notations in any case; anything that is not exactly 6 hex bytes
  /// is rejected with a message the UI can render as-is.
  static MacBitsResult decode(String raw) {
    final String hex = raw.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (hex.length != 12) {
      return const MacBitsResult.invalid(
        'Enter a 48-bit MAC address. 6 hex bytes, e.g. B8:27:EB:01:23:45. '
        'Colons, hyphens, Cisco dots, spaces, or no separators all work.',
      );
    }

    final List<int> octets = <int>[
      for (int i = 0; i < 12; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final int first = octets[0];

    final bool igSet = (first & igBit) != 0;
    final bool ulSet = (first & ulBit) != 0;
    final bool broadcast = octets.every((int o) => o == 0xFF);

    final List<int> flipped = <int>[first ^ ulBit, ...octets.sublist(1)];

    String? eui64;
    String? modified;
    String? linkLocal;
    String? unavailable;

    if (igSet) {
      unavailable = broadcast
          ? 'The broadcast address is not one interface, so there is no '
                'interface identifier to derive from it.'
          : 'EUI-64 is defined for a unicast interface. This is a group '
                '(multicast) address, so there is no single NIC identity to '
                'derive an interface identifier from.';
    } else {
      // RFC 4291 Appendix A: insert FF:FE between octet 3 and octet 4.
      final List<int> ieee = <int>[
        ...octets.sublist(0, 3),
        0xFF,
        0xFE,
        ...octets.sublist(3),
      ];
      // The MODIFIED form inverts the U/L bit — the step that gets skipped.
      final List<int> modBytes = <int>[ieee[0] ^ ulBit, ...ieee.sublist(1)];

      eui64 = _colon(ieee);
      modified = _groups(modBytes);
      linkLocal = Ipv6Address.compress(
        Ipv6Address.expand('fe80:0000:0000:0000:$modified'),
      );
    }

    return MacBitsResult(
      isValid: true,
      colonForm: _colon(octets),
      hyphenForm: _colon(octets).toUpperCase().replaceAll(':', '-'),
      ciscoForm:
          '${hex.substring(0, 4)}.${hex.substring(4, 8)}.'
          '${hex.substring(8, 12)}',
      bareForm: hex,
      firstOctetHex: first.toRadixString(16).padLeft(2, '0').toUpperCase(),
      firstOctetBinary: first.toRadixString(2).padLeft(8, '0'),
      cast: igSet ? MacCast.multicast : MacCast.unicast,
      administration: ulSet
          ? MacAdministration.local
          : MacAdministration.global,
      isBroadcast: broadcast,
      ulFlippedForm: _colon(flipped),
      eui64: eui64,
      modifiedEui64: modified,
      linkLocal: linkLocal,
      eui64UnavailableReason: unavailable,
    );
  }

  /// Lower-case colon form of an arbitrary-length byte list.
  static String _colon(List<int> bytes) =>
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(':');

  /// Four 4-hex-digit groups from 8 bytes — the interface-identifier rendering.
  /// Leading zeros are KEPT here (`0000:00ff:fe00:0001`) because the groups are
  /// being read as a bit pattern, not as a compressed address.
  static String _groups(List<int> bytes) {
    final String hex = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return <String>[
      hex.substring(0, 4),
      hex.substring(4, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
    ].join(':');
  }
}
