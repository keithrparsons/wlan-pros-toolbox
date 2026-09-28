// Connected, No Internet: the captive-portal walk-through behind the Wi-Fi
// Classroom Guided Lesson `captive-portal`. Pure Dart, deterministic, no
// Flutter imports, so the teaching claims are unit-tested on their own.
//
// CLEAN ROOM. Built only from the sources the lesson cites:
//  - Apple Developer, "How to modernize your captive network" (2020-06-22):
//    iOS and macOS send a probe on first association to detect interception;
//    a network can instead announce it is captive with DHCP option 114, and
//    the device then reads its status from a Captive Portal API over TLS; the
//    experience looks the same to the person either way; an expired session
//    under interception can make a browser load the wrong page or show a
//    security warning.
//  - RFC 8910: DHCPv4 option 114 (replacing RFC 7710's 160), DHCPv6 option
//    103 and an IPv6 Router Advertisement option carry the URI of the API;
//    captive portals will still intercept for older clients, and clients will
//    still probe.
//  - RFC 8908: the API is reached over https and answers whether the device is
//    captive, plus the address of the sign-in page (user-portal-url).
//  - RFC 8952: the Enforcement Device restricts a device's traffic until the
//    captive portal conditions are met.
//
// GUARD (Pax, research brief §3 candidate 2): no single operating system's
// probe address, timing or retry behavior is modeled. The probe is the generic
// step Apple describes: ask for something whose answer is known, and see
// whether the network answered instead.
//
// Both modes walk the same five stages so a teacher can flip the switch at any
// step and compare like with like.

/// How the network tells the device that it must sign in first.
enum CaptiveMode {
  /// The network names its portal in the address reply (DHCP option 114, RFC
  /// 8910) and the device asks the Captive Portal API (RFC 8908).
  announced,

  /// The network announces nothing; it intercepts the device's probe and
  /// answers with its sign-in page instead.
  intercepted,
}

/// The five stages, identical in both modes.
enum CaptiveStage { associate, address, check, signIn, online }

/// Where the device's internet access stands at a step.
enum InternetAccess {
  /// The network passes nothing beyond its own sign-in pages.
  held,

  /// The sign-in is done and the network passes traffic.
  open,
}

/// One step of the walk-through.
class CaptiveStep {
  const CaptiveStep({
    required this.stage,
    required this.title,
    required this.sent,
    required this.reply,
    required this.onScreen,
    required this.explanation,
    required this.internet,
    required this.signInSheetOpen,
    this.replyIsInterception = false,
    this.announcesPortal = false,
  });

  final CaptiveStage stage;

  /// Short step name, shown as "Step n of 5: <title>".
  final String title;

  /// What the device sends to the network.
  final String sent;

  /// What comes back.
  final String reply;

  /// What the person holding the device sees.
  final String onScreen;

  /// One or two sentences on why this step matters.
  final String explanation;

  final InternetAccess internet;

  /// True while the device shows the network's sign-in sheet.
  final bool signInSheetOpen;

  /// True when the reply is the network answering in place of the address the
  /// device asked (the intercepted probe).
  final bool replyIsInterception;

  /// True when this reply carries the portal announcement (option 114).
  final bool announcesPortal;

  /// The Wi-Fi link is up from the first step in both modes: association is
  /// done before anything else happens. "Full bars" is true all along.
  bool get wifiLinkUp => true;

  /// Wi-Fi Calling needs its tunnel to the carrier, and a held network passes
  /// nothing but its own sign-in pages, so the call waits for the sign-in.
  bool get wifiCallingCanConnect => internet == InternetAccess.open;
}

/// The walk-through for [mode]: exactly one step per [CaptiveStage], in order.
List<CaptiveStep> captiveSteps(CaptiveMode mode) =>
    mode == CaptiveMode.announced ? _announced : _intercepted;

const CaptiveStep _associate = CaptiveStep(
  stage: CaptiveStage.associate,
  title: 'Association',
  sent: 'Association Request to the access point',
  reply: 'Association Response: success',
  onScreen: 'The Wi-Fi icon, full bars',
  explanation:
      'The Wi-Fi link is up. The network is already holding everything except '
      'its own sign-in pages, but nothing on the device says so yet.',
  internet: InternetAccess.held,
  signInSheetOpen: false,
);

const CaptiveStep _signIn = CaptiveStep(
  stage: CaptiveStage.signIn,
  title: 'Sign in',
  sent: 'The completed sign-in page: terms accepted, room number or code',
  reply: 'Accepted. The network lets this device through',
  onScreen: 'The sign-in sheet shows Done',
  explanation:
      'This is the step the person has to do. Until it is finished, no '
      'amount of signal strength gets the device to the internet.',
  internet: InternetAccess.open,
  signInSheetOpen: true,
);

const List<CaptiveStep> _announced = <CaptiveStep>[
  _associate,
  CaptiveStep(
    stage: CaptiveStage.address,
    title: 'Get an address',
    sent: 'DHCP request, asking for option 114',
    reply:
        'An IP address, plus option 114: the secure address of the '
        "network's Captive Portal API",
    onScreen: 'The Wi-Fi icon, full bars',
    explanation:
        'The network announces its portal in the same reply that hands out '
        'the address. The device learns it has to sign in before it tries '
        'anything else (RFC 8910).',
    internet: InternetAccess.held,
    signInSheetOpen: false,
    announcesPortal: true,
  ),
  CaptiveStep(
    stage: CaptiveStage.check,
    title: 'Ask the network',
    sent: 'A secure (HTTPS) request to the Captive Portal API: am I captive?',
    reply: 'Captive: yes. Sign in at this page',
    onScreen: 'The sign-in sheet opens',
    explanation:
        'The device asks the network directly and gets a straight answer, '
        'including where the sign-in page is (RFC 8908). Nothing had to be '
        'intercepted.',
    internet: InternetAccess.held,
    signInSheetOpen: true,
  ),
  _signIn,
  CaptiveStep(
    stage: CaptiveStage.online,
    title: 'Online',
    sent: 'The same secure request to the Captive Portal API',
    reply: 'Captive: no. The API can also say how much time is left',
    onScreen: 'The sign-in sheet closes. Connected',
    explanation:
        'The device checks again and marks the network as working. Wi-Fi '
        'Calling can now build its tunnel to the carrier.',
    internet: InternetAccess.open,
    signInSheetOpen: false,
  ),
];

const List<CaptiveStep> _intercepted = <CaptiveStep>[
  _associate,
  CaptiveStep(
    stage: CaptiveStage.address,
    title: 'Get an address',
    sent: 'DHCP request',
    reply: 'An IP address. Nothing about a portal',
    onScreen: 'The Wi-Fi icon, full bars',
    explanation:
        'The network says nothing about signing in. The device has to find '
        'out for itself.',
    internet: InternetAccess.held,
    signInSheetOpen: false,
  ),
  CaptiveStep(
    stage: CaptiveStage.check,
    title: 'Probe',
    sent: 'A probe: a request to a known test address with a known answer',
    reply: 'The sign-in page, sent in place of the known answer',
    onScreen: 'The sign-in sheet opens',
    explanation:
        'The device expected one answer and got a different one, so it knows '
        'the network stepped in. That is how a probe detects a captive '
        'network.',
    internet: InternetAccess.held,
    signInSheetOpen: true,
    replyIsInterception: true,
  ),
  _signIn,
  CaptiveStep(
    stage: CaptiveStage.online,
    title: 'Online',
    sent: 'The probe again',
    reply: 'The known answer, untouched',
    onScreen: 'The sign-in sheet closes. Connected',
    explanation:
        'The answer matches, so the device marks the network as working. '
        'Wi-Fi Calling can now build its tunnel to the carrier.',
    internet: InternetAccess.open,
    signInSheetOpen: false,
  ),
];
