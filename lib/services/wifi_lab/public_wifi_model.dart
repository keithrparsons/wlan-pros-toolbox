// Public Wi-Fi: what the person next to you can see. The deterministic model
// behind the Guided Lesson (lib/screens/tools/reference/public_wifi_*.dart).
//
// One input, the network type, and one fixed bystander: someone nearby on the
// SAME network, listening to the air with a free capture tool. On a password
// network they were given the same password you were, which is the ordinary
// case at a cafe. The model answers, for each kind of traffic, what that
// person can read.
//
// The teaching claims, each pinned by test/services/wifi_lab/
// public_wifi_model_test.dart:
//  1. HTTPS seals what you read and type on a secure site on EVERY network
//     type (FTC consumer advice, "Because of the widespread use of
//     encryption, connecting through a public Wi-Fi network is usually safe").
//  2. On an Open network, the site names (from DNS lookups and the TLS Server
//     Name Indication) and anything an app sends unencrypted are readable.
//  3. Enhanced Open (OWE, RFC 8110) gives each device its own key with no
//     password, so a listener reads nothing inside the frames, yet the network
//     list shows no lock (Wi-Fi Alliance: Enhanced Open networks "will
//     continue to be displayed without a 'lock' icon").
//  4. WPA2-Personal derives every device's key from the one shared password:
//     someone who has the password and records your device joining can work
//     out your key, so to them the air reads as if it were Open. A shared
//     password does NOT hide you from others who know it.
//  5. WPA3-Personal (SAE) gives each device its own key; knowing the password
//     does not let someone who only listens work out yours.
//  6. The device's presence and how much it sends are always visible: the
//     802.11 frame header is never encrypted.
//  7. Wi-Fi encryption ends at the access point. The network's owner sees
//     site names on every type; that is independent of the choice here.
//
// Pure Dart. No Flutter import, no I/O, no randomness.

/// The four network types the lesson's control offers. The control shows
/// Open / Enhanced Open / Password, and Password splits into WPA2 and WPA3.
enum PwNetwork { open, enhancedOpen, wpa2Personal, wpa3Personal }

/// The top-level choice on the lesson's control.
enum PwKind { open, enhancedOpen, password }

/// The second choice, shown only for [PwKind.password].
enum PwPassword { wpa2, wpa3 }

/// Resolves the two controls into one network type.
PwNetwork pwNetworkFor(PwKind kind, PwPassword password) => switch (kind) {
  PwKind.open => PwNetwork.open,
  PwKind.enhancedOpen => PwNetwork.enhancedOpen,
  PwKind.password => password == PwPassword.wpa2
      ? PwNetwork.wpa2Personal
      : PwNetwork.wpa3Personal,
};

/// What the bystander gets from one kind of traffic.
enum PwExposure {
  /// They can read the content itself.
  readable,

  /// They can see that it happened (a name, a size, a time), not what is in
  /// it.
  visible,

  /// Encrypted end to end on the air: nothing to read.
  sealed,
}

/// The kinds of traffic the lesson lays out, top to bottom.
enum PwTraffic {
  /// That the device is here, and how much and when it sends.
  presence,

  /// Which sites the device visits: the DNS lookups and the TLS server name.
  siteNames,

  /// What you read and type on a secure (HTTPS) site.
  httpsContent,

  /// Anything an app or page sends without encryption.
  unencrypted,
}

/// True when Wi-Fi encrypts the air between the device and the AP.
bool pwAirEncrypted(PwNetwork n) => n != PwNetwork.open;

/// True when each device gets a key the bystander cannot work out.
bool pwOwnKey(PwNetwork n) =>
    n == PwNetwork.enhancedOpen || n == PwNetwork.wpa3Personal;

/// True when a device's network list shows a lock for this network.
bool pwShowsLock(PwNetwork n) =>
    n == PwNetwork.wpa2Personal || n == PwNetwork.wpa3Personal;

/// True when the bystander needs a password to be on this network at all.
bool pwNeedsPassword(PwNetwork n) =>
    n == PwNetwork.wpa2Personal || n == PwNetwork.wpa3Personal;

/// What the person next to you gets from [traffic] on network [n].
PwExposure pwExposure(PwNetwork n, PwTraffic traffic) {
  // The frame header is never encrypted, on any type.
  if (traffic == PwTraffic.presence) return PwExposure.visible;
  // HTTPS seals content between the device and the website, on any type.
  if (traffic == PwTraffic.httpsContent) return PwExposure.sealed;
  // Everything else depends on whether the bystander can undo the Wi-Fi
  // layer: never on Open (there is none), always on WPA2-Personal when they
  // hold the shared password, never with a key of your own.
  if (pwOwnKey(n)) return PwExposure.sealed;
  return traffic == PwTraffic.siteNames
      ? PwExposure.visible
      : PwExposure.readable;
}

/// Every traffic kind's exposure on [n], in display order.
Map<PwTraffic, PwExposure> pwView(PwNetwork n) => <PwTraffic, PwExposure>{
  for (final PwTraffic t in PwTraffic.values) t: pwExposure(n, t),
};
