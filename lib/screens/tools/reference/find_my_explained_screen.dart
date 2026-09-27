// Find My, Explained: a Wi-Fi Classroom Guided Lesson. A read-along teaching
// screen built on the same pattern as Antenna Fundamentals
// (antenna_fundamentals_screen.dart): numbered landmark sections, verbatim copy,
// and dark-baked line figures recolored for light at runtime.
//
// CONTENT IS APPROVED AND RENDERED VERBATIM. The literal strings below are the
// text of the print guide
// myPKA/Deliverables/2026-09-27-find-my-guide/find-my-guide.html (Keith
// approved it 2026-09-27; checked against Apple's iOS 27 support pages). Only
// the STRUCTURE is adapted for a scrolling screen:
//  - the print-only parts are dropped: the cover page layout, the table of
//    contents, page footers, and the section eyebrows;
//  - the two "page 5" cross-references now name the section instead
//    ("the section Three radios, three ranges");
//  - the eight figures and the cover art are re-drawn dark-baked under
//    assets/tool-diagrams/find-my/ (tool/find_my_diagrams.py) with every label
//    string unchanged;
//  - tables become stacks of cards so a phone can read them, and the travel
//    checklist's printed boxes become real checkboxes (not persisted).
// Inline markup in the copy: **bold**, __italic__, and `menu path` (the print
// guide's `.path` spans, rendered in the app's mono style).
//
// States (SOP-007 §5): a static reference screen with no inputs, network or
// async data, so the always-rendered state is success. Each figure degrades
// gracefully: a slug missing from the bundle, or an SVG still loading in light
// mode, renders no figure at all (never a broken-image box) while its caption
// still reads. The interactive elements are the figure zoom buttons, the
// checklist checkboxes (checked / unchecked, theme focus ring) and the
// About this tool footer.
//
// THEME: every color comes from `context.colors`; no raw hex or AppColors.* in
// this file. The figures are dark-baked on the §8.20.7 allow-list and swapped
// for light by ConceptGraphicBand.applyLightSwap, the single source of truth.
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark.
// Unlike the antenna diagrams, several of these figures carry facts the prose
// does not repeat (Figure 6's five and 24 hour windows, for one), so they are
// NOT decorative: each figure's caption node announces the figure's own labels
// first, then the caption. The SVG itself is excluded at the leaf (GL-003
// §8.6.2.2) so the zoom button stays reachable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/find_my_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart' show ConceptGraphicBand;
import '../zoomable_graphic.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kFindMyExplainedToolId = 'find-my-explained';

class FindMyExplainedScreen extends StatelessWidget {
  const FindMyExplainedScreen({super.key});

  /// Test-only: drops the memoized light-mode figure sources. Each widget test
  /// runs in its own fake-async zone, and a Future created in an earlier
  /// test's zone never delivers to a later one, so tests that render light
  /// mode more than once clear this first. The running app has one zone and
  /// never needs it.
  @visibleForTesting
  static void debugClearFigureCache() => _FigureBand._light.clear();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find My, Explained'), toolbarHeight: 64),
      body: SafeArea(top: false, child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= 720;
        final double edge = isDesktop
            ? AppSpacing.screenEdgeDesktop
            : AppSpacing.screenEdgeMobile;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.calculatorMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                edge,
                AppSpacing.sm,
                edge,
                edge + AppSpacing.sm,
              ),
              children: <Widget>[
                const _Hero(),
                const SizedBox(height: AppSpacing.lg),
                ..._sections,
                ToolHelpFooter(toolId: kFindMyExplainedToolId),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The lesson body, section by section, in the print guide's order. Each
/// section is one list child so the ListView builds it lazily.
const List<Widget> _sections = <Widget>[
  // ── 1. The short answer ──────────────────────────────────────────────────
  _Section(
    number: '1',
    title: 'The short answer',
    children: <Widget>[
      _P(
        'Find My is one app that finds three kinds of things: **people** who '
        'choose to share where they are, **devices** like your iPhone, iPad, '
        'Mac, Apple Watch and AirPods, and **items** like AirTags. It works on '
        'your iPhone, iPad, Mac and Apple Watch. Your devices, but not '
        'AirTags, can also be found at icloud.com/find.',
      ),
      _Cards(<_CardData>[
        _CardData(
          'People',
          'Friends and family who have agreed to share their location with '
              'you. Nobody is ever shared without saying yes, and sharing can '
              'end at any time.',
        ),
        _CardData(
          'Devices',
          'Your Apple gear. A phone with a signal reports where it is by '
              'itself. One without a signal, or even switched off for a while, '
              'can still be found.',
        ),
        _CardData(
          'Items',
          "AirTags and other tags built for Apple's network. They have no GPS "
              'and no internet of their own. Other people\'s iPhones find them '
              'for you, without knowing it.',
        ),
      ]),
      _Callout(
        title: 'The one idea that explains most of this guide',
        body:
            'An AirTag cannot tell anyone where it is. It only whispers "I\'m '
            'here" over a short-range radio. Any Apple device that happens to '
            'pass by hears the whisper and quietly reports __its own__ '
            'location, sealed so that only you can read it. Apple says more '
            'than a billion iPhones, iPads and Macs take part (Apple, 2026). '
            'That crowd is the Find My network.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'A word on the words',
        body:
            '**Bluetooth** is the short-range radio your earbuds use. **Ultra '
            'Wideband**, or UWB, is a newer short-range radio that can measure '
            'distance and direction precisely. **NFC** is the tap-to-read '
            'radio that makes Apple Pay work. Each gets its own job in Find '
            'My, and the section Three radios, three ranges shows which.',
      ),
    ],
  ),

  // ── 2. How a stranger's phone finds your bag ─────────────────────────────
  _Section(
    number: '2',
    title: "How a stranger's phone finds your bag",
    children: <Widget>[
      _P(
        'Your suitcase is on a baggage cart. It has an AirTag inside. Here is '
        'what happens next, and none of it needs you, the stranger, or Apple '
        'to do anything.',
      ),
      _Figure(
        slug: 'f1-find-my-network',
        alt:
            '1. Your AirTag sends a short Bluetooth "I\'m here". 2. A '
            "stranger's iPhone walks past and hears it. 3. Seals its own "
            'location in an envelope only your devices can open. 4. Your '
            'iPhone opens it and puts a dot on your map. The stranger is never '
            'told: it happens in the background, anonymously. Apple\'s servers '
            "pass the sealed envelope along: Apple can't open it, and doesn't "
            'know who found what.',
        caption:
            '**Figure 1.** The Find My network. The AirTag has no GPS, no '
            'Wi-Fi and no cellular radio. It borrows the location of whoever '
            'passes by. Source: Apple Platform Security Guide.',
      ),
      _Sub('Why this is private'),
      _P(
        'Three design choices keep the finder, the owner and Apple from '
        'learning more than they should:',
      ),
      _Figure(
        slug: 'f2-rotating-ids',
        alt:
            "The tag's ID changes about every 15 minutes: 7F3A at 9:00, C019 "
            'at 9:15, 5B8E at 9:30, E24D at 9:45. An eavesdropper sees four '
            'unrelated codes. Only your devices know they are the same tag.',
        caption:
            '**Figure 2.** Rotating IDs. Source: Apple Platform Security '
            'Guide.',
      ),
      _Steps(<String>[
        '**The key stays with you.** The key that opens the envelope lives '
            'only on your own devices, synced through iCloud Keychain.',
        '**The finder stays anonymous.** The report carries no identity. '
            "Apple doesn't know who found the item or whose it is.",
        '**The tag keeps no history.** Nothing about where it has been is '
            'stored on the AirTag itself.',
      ]),
      _P(
        "Apple cannot hand an AirTag's location to police, because it cannot "
        'read it. Given a serial number, it can identify the account the tag '
        'is paired to.',
        small: true,
      ),
    ],
  ),

  // ── 3. Where the dot on the map comes from ───────────────────────────────
  _Section(
    number: '3',
    title: 'Where the dot on the map comes from',
    children: <Widget>[
      _P(
        'When you see your bag on the map, you are looking at **the location '
        'of the phone that heard it**, not a reading from the tag. So the dot '
        "is only as good as that phone's own sense of where it is.",
      ),
      _P(
        'An iPhone works out its location from several sources at once: GPS '
        'satellites, nearby Wi-Fi networks and cell towers. Outdoors, GPS does '
        'most of the work. **Indoors, and in airports especially, GPS is '
        'weak, and the phone leans on the Wi-Fi networks around it.** Apple '
        'keeps a crowdsourced map of where Wi-Fi access points are, built from '
        'iPhones reporting what they can see.',
      ),
      _Figure(
        slug: 'f3-where-the-dot-comes-from',
        alt:
            'GPS satellites: strong outdoors. Wi-Fi access points: does the '
            'work indoors. Cell towers: a rough fix anywhere. All three feed '
            "the stranger's iPhone, which knows where it is. Your AirTag, "
            'nearby, reaches it over Bluetooth. Its location, sealed, becomes '
            'the dot you see: where that phone was.',
        caption:
            '**Figure 3.** The tag has no Wi-Fi. The finder\'s phone uses GPS, '
            'Wi-Fi and cell positioning to know where it is, and that becomes '
            'your dot. Sources: Apple 102515 (Location Services), Apple 126203 '
            '(AirTag specifications). How the two combine is our explanation, '
            "not Apple's wording.",
      ),
      _Callout(
        title: 'What this means in practice',
        body:
            'In a busy airport, a tag is heard often and the dot moves in near '
            'real time. In a quiet field, or in the hold of a plane, there may '
            'be no Apple device nearby, and the dot can sit still for hours. '
            "Apple publishes no update rate, because there isn't one: it "
            'depends on who walks by.',
      ),
      _Callout(
        title: 'A Mac finds itself by Wi-Fi',
        body:
            'A Mac has no GPS. When you look up your MacBook in Find My, its '
            'location comes from the Wi-Fi networks around it (Apple, Mac User '
            'Guide). If it has no Wi-Fi connection, it can still be heard over '
            'Bluetooth by passing Apple devices, like an AirTag.',
      ),
    ],
  ),

  // ── 4. Three radios, three ranges ────────────────────────────────────────
  _Section(
    number: '4',
    title: 'Three radios, three ranges',
    children: <Widget>[
      _P(
        'Each radio in an AirTag has one job. The farther away the item is, '
        'the less precise the answer, and the more it relies on other '
        "people's devices.",
      ),
      _Figure(
        slug: 'f4-three-radios',
        alt:
            "Anywhere, eventually: the Find My network. Other people's Apple "
            'devices report it, if they pass by. Nearby: Bluetooth. Your own '
            'iPhone connects and can play a sound. Close by: Ultra Wideband '
            '(Precision Finding). An arrow and distance on screen. AirTag 2: '
            'about 1.5x farther. Touching: NFC. A phone with NFC that taps a '
            "lost tag sees the owner's contact info.",
        caption:
            '**Figure 4.** Not to scale. Apple publishes no distances in feet '
            'or meters for Bluetooth or UWB, only that AirTag 2 finds precisely '
            'up to 50% farther than the first model. Sources: Apple 126203, '
            'Apple 109512, Apple Newsroom 2026-01-26.',
      ),
    ],
  ),

  // ── 5. Which of your devices can do what ─────────────────────────────────
  _Section(
    number: '5',
    title: 'Which of your devices can do what',
    children: <Widget>[
      _P(
        'Precision Finding, the on-screen arrow, needs Ultra Wideband in both '
        'the phone and the tag. Some budget iPhones leave it out.',
        small: true,
      ),
      _DeviceTable(),
      _P(
        'Every model above can still see items on the map and play a sound. '
        'Ultra Wideband is switched off in some countries (including Russia, '
        'Ukraine and much of Central Asia) and limited in Indonesia, Nepal and '
        'Japan. Sources: Apple 109512, Apple 120373, Apple 105104.',
        small: true,
      ),
    ],
  ),

  // ── 6. The four parts of the app ─────────────────────────────────────────
  _Section(
    number: '6',
    title: 'The four parts of the app',
    children: <Widget>[
      _P(
        'Find My on iPhone has four tabs along the bottom. On Apple Watch, '
        'watchOS 27 folds the old Find People, Find Devices and Find Items '
        'apps into a single Find My app.',
      ),
      _Figure(
        slug: 'f5-app-parts',
        alt:
            'People: friends and family sharing with you. Get directions, '
            'notifications, Find. Devices: your iPhone, iPad, Mac, Watch, '
            'AirPods. Play sound, Lost Mode, erase. Items: AirTags and other '
            'network tags. Up to 32 per Apple Account. Me: turn Share My '
            'Location on or off. Apple Watch, watchOS 27: one Find My app. The '
            'button at top left switches Devices, People, Items.',
        caption:
            '**Figure 5.** A simplified drawing of the app, not a screenshot. '
            "Button names are from Apple's guides for iOS 27 and watchOS 27 "
            '(Apple 120373, Apple 105104).',
      ),
      _Cards(<_CardData>[
        _CardData(
          'Items can be shared',
          'One AirTag can be shared with up to five people, so a whole family '
              'can see the car keys. People in the share group don\'t get '
              '"tracker found moving with you" alerts for that tag.',
        ),
        _CardData(
          'Not only AirTags',
          'Tags from Chipolo, Pebblebee, Belkin, Knog and others work in the '
              'same network, show up under Items, and can be shared with an '
              'airline the same way.',
        ),
      ]),
    ],
  ),

  // ── 7. Sharing with family and friends ───────────────────────────────────
  _Section(
    number: '7',
    title: 'Sharing with family and friends',
    children: <Widget>[
      _P(
        'Location sharing is always something a person chooses. The person '
        'you share with can see where you are on their map, and you choose how '
        'long.',
      ),
      _Cards(<_CardData>[
        _CardData(
          'How long',
          'New in iOS 27: a Custom choice, anywhere from 15 minutes to 30 '
              'days, or until a set date and time.',
        ),
        _CardData(
          'Pause for one person',
          'New in iOS 27: Hide Location pauses your location for one chosen '
              'person for a while. They see "No Location Found" and aren\'t '
              'notified.',
        ),
        _CardData(
          'Check In',
          "In Messages, tell someone you're heading home. If you don't arrive, "
              'they get your location, battery and signal. Both people need iOS '
              '17 or later.',
        ),
      ]),
      _Callout(
        title: 'Families',
        body:
            'With Family Sharing, the family organizer turns on location '
            'sharing for the group. Each member still decides for themselves '
            'whether to share. If you carry an Apple Watch and an iPhone, pick '
            'which one counts as "you" in Settings, under Find My, `Use this '
            'iPhone as My Location`.',
      ),
    ],
  ),

  // ── 8. Your phone, even when it dies ─────────────────────────────────────
  _Section(
    number: '8',
    title: 'Your phone, even when it dies',
    children: <Widget>[
      _P(
        'A phone with a signal reports its own location. A phone without one, '
        "or one that's been switched off, can still be found for a while, "
        'because it keeps sending the same Bluetooth "I\'m here" as an AirTag.',
      ),
      _Figure(
        slug: 'f6-phone-dies',
        alt:
            'On, with signal: reports itself directly, GPS, Wi-Fi and cell. '
            'Battery flat: power reserve, findable for up to 5 hours. Switched '
            'off: findable for up to 24 hours through the Find My network.',
        caption:
            '**Figure 6.** Applies to supported iPhones with the Find My '
            "network turned on; Apple doesn't list the models. **Send Last "
            "Location** also sends Apple your phone's position when the "
            'battery is about to die. Source: Apple iPhone User Guide, Apple '
            '102648.',
      ),
    ],
  ),

  // ── 9. Lost luggage, step by step ────────────────────────────────────────
  _Section(
    number: '9',
    title: 'Lost luggage, step by step',
    children: <Widget>[
      _P(
        "Since iOS 18.2 you can hand an airline a live link to your AirTag's "
        'location. Apple says more than 50 airlines accept it, including '
        "Delta, United, Lufthansa and Singapore Airlines. Apple doesn't "
        "publish a full list, so check your airline's lost-baggage page.",
      ),
      _Figure(
        slug: 'f7-lost-luggage',
        alt:
            "Bag didn't arrive: check the map first. File the airline's "
            'baggage report. Share Item Location: Items, your tag, paste the '
            'link in their form. Airline staff see a live map. The link stops '
            "by itself when you're reunited, after 7 days, or when you end it. "
            'Separate switch, Show Contact Info: sharing the link does NOT mark '
            'the tag as lost. Also turn on Show Contact Info (once called Lost '
            'Mode) with a phone number and message. Anyone who taps the tag '
            'with an NFC phone sees them. Keep a device online: updates need '
            'one of your devices online.',
        caption:
            '**Figure 7.** Share Item Location and Show Contact Info are two '
            'separate settings. People viewing the link sign in with an Apple '
            'Account or their airline email, and the map only updates while at '
            'least one of your Apple devices signed in to your account is '
            'online. Sources: Apple Newsroom 2024-11-13, Apple 104978, Apple '
            'iPhone User Guide.',
      ),
      _Sub('Before you fly'),
      _Steps(<String>[
        '**Put the tag deep inside the bag,** not on an outside luggage tag '
            'where it can be torn off.',
        '**Turn off Notify When Left Behind for the checked-bag tag.** '
            'Otherwise your phone alerts you every time you hand the bag over '
            'at check-in.',
        '**Decide what a finder should see.** If you mark the tag as lost, '
            'Show Contact Info displays your phone number and message to '
            "anyone who taps it, so use a number you're comfortable sharing.",
        '**Check the battery** in Find My. A CR2032 coin cell lasts more than '
            "a year, and it's cheap to replace before a big trip.",
      ]),
      _Callout(
        tone: _Tone.warning,
        title: 'If a device is lost or stolen',
        body:
            'Mark it as lost in Find My, from another device or at '
            'icloud.com/find. That locks it with your passcode and suspends '
            'Apple Pay. Erasing it is a separate step, and the last resort. The '
            "app shows a device's last known location for up to seven days. "
            '**Apple will never contact you to say your device has been '
            'found.** Never share your passcode, password or verification codes '
            'with anyone who says they have it.',
      ),
    ],
  ),

  // ── 10. A tracker that isn't yours ───────────────────────────────────────
  _Section(
    number: '10',
    title: "A tracker that isn't yours",
    children: <Widget>[
      _P(
        "AirTags are built to warn people if someone else's tag is traveling "
        'with them. Since May 2024, Apple and Google share one standard for '
        'this, so **both iPhone and Android phones** raise the alert, without '
        'installing an app.',
      ),
      _Figure(
        slug: 'f8-unwanted-tracker',
        alt:
            '"AirTag Found Moving With You" on iPhone, or an unknown tracker '
            'alert on Android. Find it: tap the alert, then Play Sound, or Find '
            "Nearby if offered. Identify it: hold your phone's top to the white "
            'side. Screenshot the page. Feel unsafe? Go somewhere public and '
            'contact police first. Otherwise, disable it: follow "Instructions '
            'to Disable": take the battery out.',
        caption:
            '**Figure 8.** What to do when you get an alert. Source: Apple '
            '119874, Apple Personal Safety User Guide, Google Android Help.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'Why "police first" matters',
        body:
            'When you pull the battery, the owner stops getting updates and may '
            'notice. If you think someone is following you on purpose, keep the '
            'tag as evidence and get help before you disable it. That is our '
            'advice, not an Apple instruction.',
      ),
      _Callout(
        title: 'iPhone has no "scan now" button',
        body:
            'The `Unknown Items Detected with You` list in Find My shows only '
            'tags that have __already__ set off an alert. Android has a real '
            'manual scan: `Settings › Safety & emergency › Unknown tracker '
            'alerts › Scan now`.',
      ),
      _P(
        'A tag that has been away from its owner for a while also plays a '
        'sound when moved. For the alerts to reach you, keep `Tracking '
        'Notifications` allowed in Settings › Notifications, keep Bluetooth, '
        'Location Services and `Significant Locations` (under Location '
        'Services › System Services) on, and Airplane Mode off. Find Nearby '
        'only appears on an iPhone with Ultra Wideband; without it, play the '
        'sound and search your belongings.',
        small: true,
      ),
    ],
  ),

  // ── 11. Six things people get wrong ──────────────────────────────────────
  _Section(
    number: '11',
    title: 'Six things people get wrong',
    children: <Widget>[
      _P(
        'Each of these shows up often, and each one leads people to expect the '
        'wrong thing when something goes missing.',
      ),
      _Myth(
        myth: 'An AirTag is a GPS tracker.',
        fact:
            'It has no GPS, no Wi-Fi and no cellular radio. Its location comes '
            'from Apple devices that pass within Bluetooth range.',
      ),
      _Myth(
        myth: 'AirTags connect to Wi-Fi.',
        fact:
            "The tag never uses Wi-Fi. The __finder's__ phone often uses Wi-Fi "
            'to work out its own position, and that becomes your dot.',
      ),
      _Myth(
        myth: 'Apple can see where my AirTag is.',
        fact:
            'Reports are sealed with a key only your devices hold. Apple '
            "doesn't know who found the tag or whose it is.",
      ),
      _Myth(
        myth: 'The map updates every few seconds.',
        fact:
            'It updates when an Apple device passes. That can be constant in a '
            'busy terminal and never in an empty field.',
      ),
      _Myth(
        myth: 'My iPhone can scan the room for hidden trackers.',
        fact:
            'iPhone alerts you automatically but has no manual scan. Android '
            'phones do have one.',
      ),
      _Myth(
        myth: 'Every iPhone can point an arrow at my AirTag.',
        fact:
            "Precision Finding needs Ultra Wideband. iPhone SE, 16e and 17e don't "
            'have it. They can still play a sound and show the map.',
      ),
      _Callout(
        title: 'What changed with AirTag 2 (January 2026)',
        body:
            'Same size, same coin-cell battery, same \$29 price. It adds a '
            'second-generation Ultra Wideband chip (precision finding up to 50% '
            'farther with an iPhone 15 or later), an upgraded Bluetooth chip, a '
            'speaker Apple says is 50% louder, and precision finding from a '
            'recent Apple Watch. It needs iOS 26.2.1 or later.',
      ),
    ],
  ),

  // ── Appendix A: step-by-step settings ────────────────────────────────────
  _Section(
    number: 'A',
    spokenNumber: 'Appendix A',
    title: 'Step-by-step settings',
    children: <Widget>[
      _P(
        'Written for iOS 27 and watchOS 27. The › symbol means "then tap". '
        'Button names can shift slightly between software updates.',
        small: true,
      ),
      _Sub('Get your devices ready'),
      _Task(
        title: '1. Turn on Find My for your iPhone',
        why:
            'Do this first. Without it, nothing else in this guide works for '
            'your phone.',
        steps: <String>[
          'Open `Settings › [your name] › Find My`.',
          'Tap `Find My iPhone` and turn it on.',
          'Turn on `Find My network`, so the phone can be found while it\'s '
              'offline or switched off.',
          'Turn on `Send Last Location`.',
          'Check `Settings › Privacy & Security › Location Services` is on.',
        ],
      ),
      _Task(
        title: '2. Set up an AirTag',
        why: 'Needs Bluetooth on, and iOS 26.2.1 or later for an AirTag 2.',
        steps: <String>[
          'Pull the plastic tab out of the AirTag. It chimes.',
          'Hold it next to your unlocked iPhone and tap `Connect`.',
          'Pick a name, or `Custom Name` and an emoji, then `Continue`.',
          'Agree to link it to your Apple Account, then `Done`.',
        ],
        note:
            "If the prompt doesn't appear: `Find My › Items › Add › AirTag`. If "
            'setup still fails, check that Location Services (with Precise '
            'Location for Find My), the Find My network and iCloud Keychain are '
            "on, and that you're signed in to your Apple Account.",
      ),
      _Task(
        title: "3. Change an AirTag's name or emoji",
        steps: <String>[
          '`Find My › Items` › tap the tag, then tap the More button (•••).',
          'Tap `Change Name and Emoji`, choose `Custom Name`, type the name '
              'and pick an emoji.',
        ],
      ),
      _Task(
        title: '4. Share an AirTag with up to five people',
        why:
            'Handy for family keys or a shared car. Everyone needs iOS 17 or '
            'later.',
        steps: <String>[
          '`Find My › Items` › tap the tag, then tap the More button (•••).',
          'Tap `Add Person` below `Share AirTag`, choose the person and their '
              'Apple Account, and send.',
          "To stop: tap the person's name › `Remove`.",
        ],
        note:
            "If it won't share: you need two-factor authentication on; the "
            'other person needs their own Apple Account (not a child account) '
            'with iCloud; and both of you need iCloud Keychain on.',
      ),
      _Sub('Travel and lost items'),
      _Task(
        title: '5. Get an alert if you leave something behind',
        why: 'Leave this off for the tag in your checked bag.',
        steps: <String>[
          '`Find My › Items` › tap the tag (or `Devices` › a device), then tap '
              'the More button (•••).',
          'Tap `When Left Behind`, then turn on `Notify When Left Behind`.',
          "Add places where it's fine to leave it, like home: pick a "
              'suggestion or tap `New Location`, then `Done`.',
        ],
      ),
      _Task(
        title: "6. Share a lost item's location with an airline",
        steps: <String>[
          "File the airline's lost-baggage report first.",
          '`Find My › Items` › tap the tag › `Share Item Location`.',
          "Paste the link into the airline's form, or send it to the agent.",
          '`Visited By` shows who opened it, and `Expiration` shows when it '
              'ends. Stop sharing from the same screen.',
          'Keep at least one of your Apple devices online, or the link stops '
              'updating.',
          "Know what you're sharing: the page can show the tag's serial "
              'number and your phone number or email to the people you send it '
              'to.',
        ],
      ),
      _Task(
        title: '7. Mark an AirTag as lost (Show Contact Info)',
        steps: <String>[
          '`Find My › Items` › tap the tag, then tap the More button (•••).',
          'Below `Lost AirTag`, tap `Show Contact Info`.',
          'Follow the prompts to enter a phone number and a short message.',
          'Turn it off in the same place once you have the item back.',
        ],
      ),
      _Task(
        title: '8. Use the on-screen arrow (Precision Finding)',
        why: 'iPhone 11 or later, except SE, 16e and 17e.',
        steps: <String>[
          '`Find My › Items` › tap the tag › `Find`.',
          'Move slowly and follow the arrow and distance. Tap `Play Sound` if '
              "you're close.",
          'On Apple Watch Series 9 or later with an AirTag 2: open `Find My`, '
              'tap the button at top left › `Items` › the tag › `Find`.',
        ],
      ),
      _Sub('People'),
      _Task(
        title: '9. Share your location with someone',
        steps: <String>[
          '`Find My › Me` › turn on `Share My Location`.',
          '`People › Add › Share My Location` › choose the person.',
          'Choose how long. In iOS 27, `Custom` lets you pick anything from 15 '
              'minutes to 30 days, or an end time.',
          'For a family group: `Settings › Family › Location Sharing`.',
        ],
      ),
      _Task(
        title: '10. Use Check In when you head home',
        steps: <String>[
          'In Messages, open the conversation with the person › `+` › `Check '
              'In`.',
          'Tap `Edit` and choose `When I arrive` (pick the destination) or '
              '`After a timer`.',
          'Tap Send. It ends by itself when you arrive.',
        ],
      ),
      _Task(
        title: '11. Pause your location for one person (iOS 27)',
        steps: <String>[
          '`Find My › People` › tap your own card.',
          'Tap `Hide Location` and choose the person. It turns itself back on '
              'later.',
        ],
      ),
      _Sub('Safety and upkeep'),
      _Task(
        title: '12. If you get "AirTag Found Moving With You"',
        steps: <String>[
          'Tap the alert › `Continue`.',
          'Tap `Play Sound`, or `Find Nearby` if your iPhone offers it.',
          'Hold the top of your iPhone to the white side of the tag and '
              'screenshot what appears.',
          'If you feel unsafe, go somewhere public and contact police. '
              'Otherwise tap `Instructions to Disable` and remove the battery.',
        ],
      ),
      _Task(
        title: "13. Change an AirTag's battery",
        steps: <String>[
          'Press the steel cover and turn it counterclockwise until it stops, '
              'then lift it off.',
          'Put in a CR2032 coin cell, + side up. Buy packs marked "Compatible '
              'with Apple AirTag".',
          'Line up the three tabs, press and turn clockwise until it stops.',
        ],
      ),
    ],
  ),

  // ── Appendix B: travel checklist ─────────────────────────────────────────
  _Section(
    number: 'B',
    spokenNumber: 'Appendix B',
    title: 'Travel checklist',
    children: <Widget>[
      _P('Ten minutes before a trip. Tick them off in order.'),
      _Checklist(),
      _Callout(
        title: "If the bag doesn't show up",
        body:
            'Check the map before you leave the baggage hall. File the airline '
            'report. Share Item Location from the tag, turn on Show Contact '
            'Info separately, and keep your phone charged and online: the link '
            'only updates while one of your devices is online, for up to seven '
            "days. You can't create the link while the item is right next to "
            "you, so there's no rehearsing it at home.",
      ),
    ],
  ),

  // ── Sources ──────────────────────────────────────────────────────────────
  _Section(
    number: '→',
    spokenNumber: 'Sources',
    title: 'Where these facts come from',
    children: <Widget>[
      _P(
        "Checked against Apple's pages on 27 September 2026. Many Apple "
        'support articles were republished for iOS 27 between 14 and 24 '
        'September 2026. Figures Apple does not publish, such as Bluetooth '
        "range and how often a tag's location updates, are deliberately left "
        'out.',
        small: true,
      ),
      _Sources(),
      _Callout(
        title: 'About this guide',
        body:
            "Written for people who aren't technical and want to know what "
            'Find My does before they need it. Apple, AirTag, iPhone, Apple '
            'Watch and Find My are trademarks of Apple Inc. This guide is '
            "independent and isn't affiliated with or endorsed by Apple.",
      ),
    ],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Inline markup: **bold**, __italic__, `menu path`.
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _markup = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`(.+?)`');

/// Parses the copy's inline markup into spans over [base]. Mono runs use the
/// app's inline-code face (DM Mono, GL-003 §8.5) on the recessed input fill,
/// the in-app equivalent of the print guide's `.path` chip.
List<InlineSpan> _spans(BuildContext context, String source, TextStyle base) {
  final AppColorScheme colors = context.colors;
  final TextStyle mono =
      (Theme.of(context).extension<AppMonoText>()?.inlineCode ??
              const TextStyle(fontFamily: 'DM Mono'))
          .copyWith(
            fontSize: (base.fontSize ?? AppTextSize.body) * 0.92,
            color: base.color,
            height: base.height,
            backgroundColor: colors.inputFill,
          );
  final List<InlineSpan> out = <InlineSpan>[];
  int at = 0;
  for (final RegExpMatch m in _markup.allMatches(source)) {
    if (m.start > at) out.add(TextSpan(text: source.substring(at, m.start)));
    if (m.group(1) != null) {
      out.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (m.group(2) != null) {
      out.add(
        TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else {
      out.add(TextSpan(text: m.group(3), style: mono));
    }
    at = m.end;
  }
  if (at < source.length) out.add(TextSpan(text: source.substring(at)));
  return out;
}

/// The copy with its markup removed: what a screen reader should say, and
/// what the tests look up.
String _plain(String source) => source.replaceAllMapped(
  _markup,
  (Match m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? '',
);

/// Rich text over [source]'s markup. Semantics carry the plain string so a
/// screen reader never meets a stray marker.
class _Rich extends StatelessWidget {
  const _Rich(this.source, {required this.style});

  final String source;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans(context, source, style)),
      style: style,
      semanticsLabel: _plain(source),
    );
  }
}

TextStyle _body(BuildContext context, {bool small = false, Color? color}) {
  final TextTheme t = Theme.of(context).textTheme;
  final TextStyle base = (small ? t.bodySmall : t.bodyMedium) ?? const TextStyle();
  return base.copyWith(
    color: color ?? context.colors.textPrimary,
    height: small ? 1.45 : 1.5,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// The hero: the guide's cover art, tagline and subtitle.
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Decorative: the three words it carries open section 1 as cards.
        const _FigureBand(
          slug: 'cover-people-devices-items',
          zoomable: false,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'A plain-English guide',
          style: (t.labelMedium ?? const TextStyle()).copyWith(
            color: colors.textAccent,
            fontFamily: 'DM Mono',
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'How Apple finds your people, your phone and your things, including '
          'the AirTag in your suitcase, and what you should turn on before your '
          'next trip.',
          style: (t.titleMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Current for iOS 27 and watchOS 27 · September 2026',
          style: _body(context, small: true, color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section scaffolding.
// ─────────────────────────────────────────────────────────────────────────────

/// A numbered section: landmark header, then its blocks with even spacing.
class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.children,
    this.spokenNumber,
  });

  final String number;
  final String title;
  final List<Widget> children;

  /// What a screen reader says for the badge, when the glyph alone would not
  /// read well ("Appendix A" rather than "A", "Sources" rather than an arrow).
  final String? spokenNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionHeader(
            number: number,
            title: title,
            spoken: spokenNumber ?? 'Section $number',
          ),
          for (final Widget c in children) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            c,
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.number,
    required this.title,
    required this.spoken,
  });

  final String number;
  final String title;
  final String spoken;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      header: true,
      label: '$spoken. $title',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(minWidth: 28),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Text(
              number,
              textAlign: TextAlign.center,
              style: (text.labelMedium ?? const TextStyle()).copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: (text.titleMedium ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A subheading inside a section (the print guide's h3).
class _Sub extends StatelessWidget {
  const _Sub(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: (t.titleSmall ?? const TextStyle()).copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// A body paragraph. [small] is the print guide's small-type register (notes
/// and source lines), rendered in secondary text.
class _P extends StatelessWidget {
  const _P(this.source, {this.small = false});

  final String source;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return _Rich(
      source,
      style: _body(
        context,
        small: small,
        color: small ? context.colors.textSecondary : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards and callouts.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _CardData {
  const _CardData(this.title, this.body);

  final String title;
  final String body;
}

/// Side-by-side cards on a wide screen, stacked on a narrow one.
class _Cards extends StatelessWidget {
  const _Cards(this.cards);

  final List<_CardData> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool row = c.maxWidth >= 180.0 * cards.length + AppSpacing.xs;
        final List<Widget> tiles = <Widget>[
          for (final _CardData d in cards) _Card(data: d),
        ];
        if (!row) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.data});

  final _CardData data;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              data.title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _Rich(
            data.body,
            style: _body(context, small: true, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

enum _Tone { accent, warning }

/// A titled callout with a filled rail (lime, or §8.13 warning). The title
/// carries the meaning, so the rail color is never the only cue.
class _Callout extends StatelessWidget {
  const _Callout({required this.title, required this.body, this.tone = _Tone.accent});

  final String title;
  final String body;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color rail = tone == _Tone.warning ? colors.statusWarning : colors.primary;
    final TextStyle base = _body(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(width: colors.isLight ? 4 : 3, color: rail),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: base.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    _Rich(body, style: base),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numbered steps, task cards, myth/fact pairs.
// ─────────────────────────────────────────────────────────────────────────────

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle base = _body(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surface3,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: (Theme.of(context).textTheme.labelSmall ??
                            const TextStyle())
                        .copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  label: 'Step ${i + 1}.',
                  child: _Rich(steps[i], style: base),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One Appendix A task: title, optional "why" line, numbered steps, optional
/// note.
class _Task extends StatelessWidget {
  const _Task({required this.title, required this.steps, this.why, this.note});

  final String title;
  final String? why;
  final List<String> steps;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              title,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (why != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              why!,
              style: _body(context, small: true, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          _Steps(steps),
          if (note != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            _P(note!, small: true),
          ],
        ],
      ),
    );
  }
}

class _Myth extends StatelessWidget {
  const _Myth({required this.myth, required this.fact});

  final String myth;
  final String fact;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    Widget half(String label, Color labelColor, String body, Color fill) {
      return Container(
        color: fill,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
                  .copyWith(
                    color: labelColor,
                    fontFamily: 'DM Mono',
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            _Rich(body, style: _body(context)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          half('Myth', colors.statusDanger, myth, colors.statusDangerFill),
          half('Fact', colors.textAccent, fact, colors.surface1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The devices table (section 5), as one card per device.
// ─────────────────────────────────────────────────────────────────────────────

enum _Verdict { yes, no, neutral }

@immutable
class _Cell {
  const _Cell(this.text, this.verdict);

  final String text;
  final _Verdict verdict;
}

@immutable
class _DeviceRow {
  const _DeviceRow(this.device, this.cells);

  final String device;
  final List<_Cell> cells;
}

class _DeviceTable extends StatelessWidget {
  const _DeviceTable();

  static const List<String> _columns = <String>[
    'Arrow to a 1st-gen AirTag',
    'Arrow to an AirTag 2, longer range',
    'Arrow to a friend',
  ];

  static const _Cell _yes = _Cell('Yes', _Verdict.yes);
  static const _Cell _no = _Cell('No', _Verdict.no);

  static const List<_DeviceRow> _rows = <_DeviceRow>[
    _DeviceRow('iPhone 15, 16, 17 or iPhone Air', <_Cell>[
      _yes,
      _yes,
      _Cell('Yes, if they have iPhone 15 or later too', _Verdict.yes),
    ]),
    _DeviceRow('iPhone 11 to 14', <_Cell>[
      _yes,
      _Cell('Standard range only', _Verdict.neutral),
      _no,
    ]),
    _DeviceRow('iPhone SE, 16e, 17e', <_Cell>[_no, _no, _no]),
    _DeviceRow('Apple Watch Series 9 or later, Ultra 2 or later', <_Cell>[
      _no,
      _Cell('Yes (AirTag 2 only)', _Verdict.yes),
      _Cell('Not covered here', _Verdict.neutral),
    ]),
    _DeviceRow('Apple Watch SE', <_Cell>[
      _no,
      _no,
      _Cell('Not covered here', _Verdict.neutral),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < _rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _DeviceCard(row: _rows[i]),
        ],
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.row});

  final _DeviceRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    Color tint(_Verdict v) => switch (v) {
      _Verdict.yes => colors.statusSuccess,
      _Verdict.no => colors.statusDanger,
      _Verdict.neutral => colors.textSecondary,
    };
    return Semantics(
      label: <String>[
        'Your device: ${row.device}.',
        for (int i = 0; i < row.cells.length; i++)
          '${_DeviceTable._columns[i]}: ${row.cells[i].text}.',
      ].join(' '),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: colors.border),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              row.device,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            for (int i = 0; i < row.cells.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: Text(
                        _DeviceTable._columns[i],
                        style: (t.bodySmall ?? const TextStyle()).copyWith(
                          color: colors.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      flex: 2,
                      child: Text(
                        row.cells[i].text,
                        style: (t.bodySmall ?? const TextStyle()).copyWith(
                          color: tint(row.cells[i].verdict),
                          fontWeight: row.cells[i].verdict == _Verdict.neutral
                              ? FontWeight.w400
                              : FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appendix B: the travel checklist. Real checkboxes, held in memory only.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _Check {
  const _Check(this.check, this.where, {this.mono = true});

  final String check;
  final String where;

  /// The print guide sets menu paths in mono and plain places ("Your
  /// suitcase") in body type.
  final bool mono;
}

class _Checklist extends StatefulWidget {
  const _Checklist();

  static const List<_Check> items = <_Check>[
    _Check(
      'Find My, Find My network and Send Last Location are on for your iPhone',
      'Settings › [name] › Find My',
    ),
    _Check(
      'Find My is on for your iPad, Mac and AirPods too',
      'Find My › Devices',
    ),
    _Check(
      'An AirTag is inside each checked bag, not clipped to the outside',
      'Your suitcase',
      mono: false,
    ),
    _Check(
      'Each tag is named clearly, like "Blue suitcase"',
      'Items › tag › ••• › Change Name and Emoji',
    ),
    _Check('No tag shows a low-battery warning', 'Find My › Items'),
    _Check(
      'Notify When Left Behind is OFF for checked-bag tags and ON for your '
          'carry-on and laptop',
      'Items › tag › ••• › When Left Behind',
    ),
    _Check(
      'A travel companion is sharing location with you for the length of the '
          'trip',
      'People › Add',
    ),
    _Check(
      "Tracking Notifications are allowed and Significant Locations is on, so "
          "you'd know about a stranger's tag",
      'Settings › Notifications',
    ),
    _Check(
      "You know your airline's lost-baggage page accepts Share Item Location",
      'Airline website',
      mono: false,
    ),
    _Check(
      'Where Ultra Wideband is switched off, expect the map and sound only. '
          'In Japan, Indonesia and Nepal, it depends on your device',
      'Three radios, three ranges',
      mono: false,
    ),
  ];

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  late final List<bool> _done = List<bool>.filled(
    _Checklist.items.length,
    false,
  );

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle where = _body(
      context,
      small: true,
      color: colors.textSecondary,
    );
    // A Material, not a decorated Container, so each row's pressed and hover
    // ink paints on the card instead of underneath it.
    return Material(
      color: colors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < _Checklist.items.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: colors.border),
            CheckboxListTile(
              value: _done[i],
              onChanged: (bool? v) => setState(() => _done[i] = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: colors.primary,
              checkColor: colors.onPrimary,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
              ),
              title: Text(_Checklist.items[i].check, style: _body(context)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: _Rich(
                  _Checklist.items[i].mono
                      ? 'Where: `${_Checklist.items[i].where}`'
                      : 'Where: ${_Checklist.items[i].where}',
                  style: where,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sources.
// ─────────────────────────────────────────────────────────────────────────────

class _Sources extends StatelessWidget {
  const _Sources();

  static const List<String> _items = <String>[
    'Apple Platform Security Guide, Find My: '
        'support.apple.com/guide/security/sec6cbc80fd0',
    'Apple 102648, Find My network and Send Last Location',
    'Apple 102515, Location Services and privacy (GPS, Wi-Fi and cellular '
        'positioning)',
    'Apple 126203, AirTag (2nd generation) technical specifications; Apple '
        '111847, AirTag (1st generation)',
    'Apple 109512, Precision Finding and Ultra Wideband availability by device '
        'and country',
    'Apple 120373, Find My on Apple Watch (watchOS 27)',
    'Apple 105104, share your location; Apple 105107, Family Sharing location',
    'Apple 104978, if your device or item is lost',
    'Apple 102414, Notify When Left Behind',
    'Apple 119874, unwanted tracking alerts',
    'Apple 101602, set up AirTag (32-item limit, iOS 26.2.1 for AirTag 2)',
    'Apple 102600, replace the AirTag battery',
    'Apple Newsroom, 2024-05-13: cross-platform unwanted tracking alerts',
    'Apple Newsroom, 2024-11-13: Share Item Location',
    'Apple Newsroom, 2026-01-26: AirTag (2nd generation)',
    'apple.com/airtag and apple.com/icloud/find-my (network size, "over a '
        'billion" devices)',
    'Apple Personal Safety User Guide: Check In, Find My and location sharing',
    'Google Android Help 13658562: unknown tracker alerts and Scan now',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle s = _body(context, small: true, color: colors.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final String item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExcludeSemantics(
                  child: Text('•  ', style: s.copyWith(color: colors.textAccent)),
                ),
                Expanded(child: Text(item, style: s)),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Figures: the band (gated on the manifest, recolored for light, tap to zoom)
// and its caption.
// ─────────────────────────────────────────────────────────────────────────────

/// A figure and its caption. The caption always renders (it carries sources
/// and limits the prose does not repeat); the band renders only when the SVG
/// is bundled. The caption's semantics node reads the figure's own labels
/// ([alt]) first, so a screen reader gets what the drawing says.
class _Figure extends StatelessWidget {
  const _Figure({required this.slug, required this.alt, required this.caption});

  final String slug;
  final String alt;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _FigureBand(slug: slug),
        if (FindMyDiagrams.has(slug)) const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: '${_plain(caption)} The figure shows: $alt',
          excludeSemantics: true,
          child: _Rich(
            caption,
            style: _body(context, small: true, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Renders one figure at its intrinsic aspect ratio inside a card-styled band.
/// Dark renders the asset as authored; light loads the source and applies the
/// §8.20.7 swap (ConceptGraphicBand.applyLightSwap). A slug missing from the
/// bundle renders nothing.
class _FigureBand extends StatelessWidget {
  const _FigureBand({required this.slug, this.zoomable = true});

  final String slug;
  final bool zoomable;

  // viewBox width / height of each figure, so the band reserves the true shape
  // before the light source finishes loading (no layout jump).
  static const Map<String, double> _aspect = <String, double>{
    'cover-people-devices-items': 700 / 250,
    'f1-find-my-network': 640 / 584,
    'f2-rotating-ids': 640 / 204,
    'f3-where-the-dot-comes-from': 760 / 320,
    'f4-three-radios': 760 / 302,
    'f5-app-parts': 640 / 570,
    'f6-phone-dies': 760 / 160,
    'f7-lost-luggage': 760 / 424,
    'f8-unwanted-tracker': 760 / 388,
  };

  // Memoized swapped-light sources, so a rebuild reuses one Future per slug
  // and the string replace runs once.
  static final Map<String, Future<String>> _light = <String, Future<String>>{};

  Future<String> _lightSource() => _light.putIfAbsent(
    slug,
    () async => ConceptGraphicBand.applyLightSwap(
      await rootBundle.loadString(FindMyDiagrams.path(slug)),
    ),
  );

  Widget _svg(bool light, {double? width, double? height}) {
    if (!light) {
      return SvgPicture.asset(
        FindMyDiagrams.path(slug),
        fit: BoxFit.contain,
        width: width,
        height: height,
        excludeFromSemantics: true,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      );
    }
    return FutureBuilder<String>(
      future: _lightSource(),
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String? data = snap.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        return SvgPicture.string(
          data,
          fit: BoxFit.contain,
          width: width,
          height: height,
          excludeFromSemantics: true,
          placeholderBuilder: (_) => const SizedBox.shrink(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!FindMyDiagrams.has(slug)) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final bool light = colors.isLight;
    final Widget inPage = _svg(light, width: double.infinity);
    return Container(
      key: ValueKey<String>('find-my-figure-$slug'),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double drawing = c.maxWidth / (_aspect[slug] ?? 1.6);
          if (!zoomable) {
            return SizedBox(height: drawing, child: Center(child: inPage));
          }
          // The zoom badge sits in the bottom-right corner of its child. A
          // clear strip under the drawing keeps it off the figure's labels.
          return SizedBox(
            height: drawing + AppSpacing.lg,
            child: ZoomableGraphic(
              semanticLabel: 'Zoom figure',
              svgBuilder: (BuildContext _, Size canvas) =>
                  _svg(light, width: canvas.width, height: canvas.height),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: inPage,
              ),
            ),
          );
        },
      ),
    );
  }
}
