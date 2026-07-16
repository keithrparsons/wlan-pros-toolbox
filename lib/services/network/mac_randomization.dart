// MAC randomization classifier — reads the locally-administered bit of a Wi-Fi
// MAC address and reports whether it is a randomized (locally administered) or a
// universal (burned-in, vendor-assigned) address.
//
// WHY: modern OSes rotate a randomized per-network MAC for privacy. The second
// least-significant bit of the first octet (the U/L bit, mask 0x02) distinguishes
// the two: set => locally administered (randomized); clear => universally
// administered (the real burned-in NIC address).
//
// HONESTY (GL-005 / GL-008): on iOS apps cannot read the device's own Wi-Fi MAC
// at all — the OS returns either nothing or the well-known sentinel
// `02:00:00:00:00:00`. Classifying that sentinel as "randomized" would be a
// meaningless, misleading flag, so [classify] returns [MacRandomization.unreadable]
// for it (and for a null/blank input) and the UI says so plainly rather than
// computing a verdict from a value the platform refused to give.

/// The platform a MAC reading came from, so the honest "unreadable" note names
/// the RIGHT OS limitation instead of leaking one platform's wording onto
/// another. iOS hands back the `02:00:00:00:00:00` sentinel because Apple does
/// not expose the device Wi-Fi MAC at all; Android returns the same sentinel
/// because it randomizes the per-network MAC by default and hides the real
/// device MAC; macOS reads the real burned-in MAC directly (so unreadable there
/// is rare and stays generic).
enum MacAddressPlatform {
  /// iOS — Apple does not expose the device Wi-Fi MAC to apps.
  ios,

  /// Android — randomized per-network MAC by default; the real device MAC is
  /// hidden and the OS returns the `02:00:00:00:00:00` placeholder.
  android,

  /// macOS / other — no platform-specific wording; a generic honest note.
  other,
}

/// The classification of a Wi-Fi MAC address by its locally-administered bit.
enum MacRandomization {
  /// Locally administered (U/L bit set) — a randomized / software-assigned MAC.
  randomized,

  /// Universally administered (U/L bit clear) — the burned-in vendor address.
  universal,

  /// The MAC could not be read (null/blank) or is the iOS sentinel
  /// `02:00:00:00:00:00` the OS hands back instead of the real device MAC. No
  /// honest verdict is possible, so the UI shows the platform-limitation note.
  unreadable,
}

/// Classifies a Wi-Fi MAC address. Pure, side-effect-free, web-safe.
abstract final class MacRandomizationClassifier {
  /// The iOS sentinel returned in place of a device's real Wi-Fi MAC. Apps on
  /// iOS cannot read the burned-in Wi-Fi MAC; the OS substitutes this constant.
  static const String iosSentinel = '02:00:00:00:00:00';

  /// Classifies [mac]. Returns [MacRandomization.unreadable] when [mac] is null,
  /// blank, the iOS sentinel, or not a parseable MAC (so the caller never shows
  /// a verdict derived from an unreadable value).
  static MacRandomization classify(String? mac) {
    final int? firstOctet = _firstOctet(mac);
    if (firstOctet == null) return MacRandomization.unreadable;
    // Bit 0x02 of the first octet is the U/L (universal/local) bit.
    return (firstOctet & 0x02) != 0
        ? MacRandomization.randomized
        : MacRandomization.universal;
  }

  /// The human-readable label for [mac], honest about the unreadable case.
  ///
  /// [platform] selects the PLATFORM-CORRECT reason for an unreadable MAC so a
  /// note never leaks one OS's wording onto another (the S24 bug: the iOS
  /// "Apple does not expose…" reason showing on Android). The two readable
  /// verdicts (Randomized / Universal) are platform-independent. Defaults to
  /// [MacAddressPlatform.ios] for backward compatibility with the iOS callers
  /// that predate this parameter.
  static String label(
    String? mac, {
    MacAddressPlatform platform = MacAddressPlatform.ios,
  }) {
    switch (classify(mac)) {
      case MacRandomization.randomized:
        return 'Randomized (locally administered)';
      case MacRandomization.universal:
        return 'Universal (burned-in)';
      case MacRandomization.unreadable:
        return 'Not available: ${unreadableReason(platform)}';
    }
  }

  /// The platform-correct reason an unreadable MAC could not be read, WITHOUT
  /// the leading "Not available — " (so callers that already render their own
  /// "Unavailable" value can use just the reason as a row note). Honest per
  /// GL-005/GL-008: each platform names its own real limitation.
  static String unreadableReason(MacAddressPlatform platform) {
    switch (platform) {
      case MacAddressPlatform.ios:
        return "Apple does not expose this device's Wi-Fi MAC to apps";
      case MacAddressPlatform.android:
        return 'Android returns a randomized placeholder MAC; the real device '
            'MAC is hidden from apps';
      case MacAddressPlatform.other:
        return 'this platform does not expose the device Wi-Fi MAC';
    }
  }

  /// Parses the first octet of a MAC, or null when [mac] is null/blank, the iOS
  /// sentinel, or not a recognizable MAC. Accepts `:`- or `-`-separated and
  /// bare-hex forms; case-insensitive.
  static int? _firstOctet(String? mac) {
    if (mac == null) return null;
    final String trimmed = mac.trim();
    if (trimmed.isEmpty) return null;
    // The iOS sentinel is never a real device MAC — treat as unreadable.
    if (trimmed.toLowerCase() == iosSentinel) return null;

    // Strip separators, require an even count of hex digits and at least one
    // octet. Anything else is not a MAC we will classify.
    final String hex = trimmed.replaceAll(RegExp(r'[:\-\.\s]'), '');
    if (hex.length < 2 || hex.length.isOdd) return null;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;

    return int.parse(hex.substring(0, 2), radix: 16);
  }
}
