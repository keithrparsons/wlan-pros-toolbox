// Builds the WLAN profile XML Windows needs in order to join a network.
//
// WHY THIS FILE IS SEPARATE FROM THE FFI, AND IT IS THE WHOLE POINT. Everything
// here is pure Dart over strings, so it is testable on any platform. The FFI
// call that consumes it can only be exercised on Windows against a real radio.
// Splitting them means the part where the bugs actually live -- escaping, and
// the mapping from our security model to Microsoft's vocabulary -- is covered by
// tests that run everywhere, and the untestable part stays as thin as possible.
//
// Same split that `rsn_security_parser.dart` uses for the scan direction.
import 'pi_backend_client.dart' show PiJoinSecurity;

/// Thrown when a network cannot be expressed as a Windows profile at all.
///
/// This is NOT a failure state. Enterprise and OWE networks are the majority of
/// what a scan returns on a real site, and "we cannot join this yet" is an
/// honest answer. The caller must say so rather than offer a passphrase box
/// that cannot work.
class JoinProfileUnsupported implements Exception {
  const JoinProfileUnsupported(this.message);
  final String message;
  @override
  String toString() => 'JoinProfileUnsupported: $message';
}

/// XML-escapes a value destined for a text node.
///
/// NOT COSMETIC. An SSID is attacker-controlled text that we are about to place
/// inside a document Windows will parse. `Bob & Alice` produces malformed XML
/// and `WlanConnect` rejects the whole profile with a generic error, which would
/// read to a user as "this network cannot be joined" when the truth is "we built
/// a broken document". Apostrophes in SSIDs are common enough to hit this.
///
/// Escapes all five predefined entities rather than the three that are strictly
/// required in a text node, because the same helper is used for attribute values
/// and a partial escape that is correct in one position is wrong in the other.
String escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Microsoft's `<authentication>` value for one of our security kinds.
///
/// `wpa3Psk` maps to WPA3SAE, which Windows understands from 10 build 2004
/// onward. On anything older `WlanConnect` fails, and that failure is reported
/// as itself rather than silently retried as WPA2PSK.
///
/// THERE IS DELIBERATELY NO TRANSITION-MODE FALLBACK. A WPA2/WPA3 transition AP
/// advertises both, so a WPA3SAE profile that fails could be retried as WPA2PSK
/// and would probably succeed. Doing that automatically would downgrade the
/// user's own connection without telling them, which is exactly the class of
/// silent-downgrade defect the scan side exists to prevent.
String windowsAuthenticationFor(PiJoinSecurity security) {
  switch (security) {
    case PiJoinSecurity.open:
      return 'open';
    case PiJoinSecurity.owe:
      // Windows profile XML has no OWE authentication value. An OWE BSS is
      // joinable as open and the encryption is negotiated without us, so the
      // profile says open and carries no key.
      return 'open';
    case PiJoinSecurity.wpa2Psk:
      return 'WPA2PSK';
    case PiJoinSecurity.wpa3Psk:
      return 'WPA3SAE';
    case PiJoinSecurity.unsupported:
      throw const JoinProfileUnsupported(
        'This network advertises 802.1X or OWE. Joining it needs credentials '
        'this tool does not collect.',
      );
  }
}

/// Microsoft's `<encryption>` value for one of our security kinds.
String windowsEncryptionFor(PiJoinSecurity security) {
  switch (security) {
    case PiJoinSecurity.open:
    case PiJoinSecurity.owe:
      return 'none';
    case PiJoinSecurity.wpa2Psk:
    case PiJoinSecurity.wpa3Psk:
      return 'AES';
    case PiJoinSecurity.unsupported:
      throw const JoinProfileUnsupported(
        'This network advertises 802.1X or OWE. Joining it needs credentials '
        'this tool does not collect.',
      );
  }
}

/// Builds the profile XML for one network.
///
/// Passed to `WlanConnect` as a TEMPORARY profile, which Windows holds in memory
/// for the connection and never writes to disk. That is not an implementation
/// detail, it is the requirement: Keith, on this tool, *"this is a TEST tool"* --
/// credentials are never stored. A persisted profile would leave the passphrase
/// in the machine's profile store after the app exits.
///
/// `connectionMode` is `manual` so Windows does not auto-reconnect to this
/// network later. A test tool that quietly turns every network it touches into a
/// preferred network is a surprise the user did not ask for.
String buildWindowsJoinProfileXml({
  required String ssid,
  required PiJoinSecurity security,
  String? passphrase,
}) {
  if (ssid.isEmpty) {
    throw const JoinProfileUnsupported(
      'A hidden network has no SSID to build a profile from.',
    );
  }
  final String auth = windowsAuthenticationFor(security);
  final String enc = windowsEncryptionFor(security);
  // OWE joins like an open network: nothing is typed and nothing is sent.
  final bool needsKey =
      security != PiJoinSecurity.open && security != PiJoinSecurity.owe;

  if (needsKey && (passphrase == null || passphrase.isEmpty)) {
    throw const JoinProfileUnsupported(
      'This network needs a passphrase and none was supplied.',
    );
  }
  // Windows rejects a WPA passphrase outside 8..63 characters, and it rejects it
  // with the same generic error it uses for a malformed document. Checking here
  // means the user is told which of those two things went wrong.
  if (needsKey && (passphrase!.length < 8 || passphrase.length > 63)) {
    throw const JoinProfileUnsupported(
      'A WPA passphrase must be between 8 and 63 characters.',
    );
  }

  final String name = escapeXml(ssid);
  final StringBuffer b = StringBuffer()
    ..writeln('<?xml version="1.0"?>')
    ..writeln(
      '<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">',
    )
    ..writeln('  <name>$name</name>')
    ..writeln('  <SSIDConfig>')
    ..writeln('    <SSID>')
    ..writeln('      <name>$name</name>')
    ..writeln('    </SSID>')
    ..writeln('  </SSIDConfig>')
    ..writeln('  <connectionType>ESS</connectionType>')
    ..writeln('  <connectionMode>manual</connectionMode>')
    ..writeln('  <MSM>')
    ..writeln('    <security>')
    ..writeln('      <authEncryption>')
    ..writeln('        <authentication>$auth</authentication>')
    ..writeln('        <encryption>$enc</encryption>')
    ..writeln('        <useOneX>false</useOneX>')
    ..writeln('      </authEncryption>');
  if (needsKey) {
    b
      ..writeln('      <sharedKey>')
      ..writeln('        <keyType>passPhrase</keyType>')
      ..writeln('        <protected>false</protected>')
      ..writeln('        <keyMaterial>${escapeXml(passphrase!)}</keyMaterial>')
      ..writeln('      </sharedKey>');
  }
  b
    ..writeln('    </security>')
    ..writeln('  </MSM>')
    ..write('</WLANProfile>');
  return b.toString();
}
