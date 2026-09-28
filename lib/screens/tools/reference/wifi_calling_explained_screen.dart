// Wi-Fi Calling, Explained: a Wi-Fi Classroom Guided Lesson. A read-along
// teaching screen built on the same pattern as Find My, Explained
// (find_my_explained_screen.dart): numbered landmark sections, verbatim copy,
// and dark-baked line figures recolored for light at runtime.
//
// CONTENT IS RENDERED VERBATIM. The literal strings below are the text of the
// reviewed print guide
// myPKA/Deliverables/2026-09-27-wifi-calling-guide/wifi-calling-guide.html
// (carrier details checked 27 September 2026; the OpenAI review's 14 findings
// verified and applied, VERDICTS.md beside it). Only the STRUCTURE is adapted
// for a scrolling screen:
//  - the print-only parts are dropped: the cover page layout, the table of
//    contents ("What's inside"), page footers, and the section eyebrows;
//  - the two boxes headed "Keith's note" (print pages 5 and 8) are LEFT OUT:
//    Keith has not approved them yet (Larry's brief, 2026-09-27). The router
//    checklist's "(page 5)" pointed at the first of them, so it is dropped
//    rather than pointed at a section that no longer carries that text;
//  - every other "page N" cross-reference now names the section ("the section
//    What your Wi-Fi owes a phone call"), and Figure 7's "(page 6)" label
//    reads "(section 5)";
//  - the eight figures and the cover art are re-drawn dark-baked under
//    assets/tool-diagrams/wifi-calling/ (tool/wifi_calling_diagrams.py) with
//    every other label string unchanged;
//  - tables become stacks of cards so a phone can read them, and the two
//    checklists' printed boxes become real checkboxes (not persisted).
// Phone makers and carriers stay named, as the Find My lesson kept Apple and
// Android: this lesson is about those platforms' own settings, and every
// carrier named is a cited source for its own rule.
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
// Table verdicts (can / partly / won't) carry an icon beside the tint, so the
// color is never the only cue.
//
// ACCESSIBILITY: each section header is a Semantics(header: true) landmark.
// Several figures carry facts the prose does not repeat (Figure 6's three
// outcomes, Figure 8's four lanes), so they are NOT decorative: each figure's
// caption node announces the figure's own labels first, then the caption. The
// SVG itself is excluded at the leaf (GL-003 §8.6.2.2) so the zoom button
// stays reachable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/wifi_calling_diagrams.dart';
import '../../../theme/app_color_scheme.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/app_typography.dart';
import '../../../widgets/tool_help_footer.dart';
import '../concept_graphic_band.dart' show ConceptGraphicBand;
import '../zoomable_graphic.dart';

/// Stable catalog tool id: backs the route, the help entry, and the tests.
/// Permanent; never renamed.
const String kWifiCallingExplainedToolId = 'wifi-calling-explained';

class WifiCallingExplainedScreen extends StatelessWidget {
  const WifiCallingExplainedScreen({super.key});

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
      appBar: AppBar(
        title: const Text('Wi-Fi Calling, Explained'),
        toolbarHeight: 64,
      ),
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
                ToolHelpFooter(toolId: kWifiCallingExplainedToolId),
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
        "Wi-Fi Calling is not an app. It is your own phone company's calling "
        'service, reaching your phone over a Wi-Fi network and the internet '
        'instead of over a cell tower. You use the same phone number, the same '
        'dialer and the same text messages.',
      ),
      _Cards(<_CardData>[
        _CardData(
          'Not an app',
          "There is nothing to download. It is a switch in your phone's "
              'settings, and your phone company has to support it on your '
              'phone and your account.',
        ),
        _CardData(
          'Same number',
          'The person you call sees your normal number. You can call almost '
              'any phone number, not just people who use the same app as you.',
        ),
        _CardData(
          'Your carrier decides',
          'Whether it works abroad, whether a call survives walking outside, '
              'and how emergency calls are handled all depend on your phone '
              'company and your country.',
        ),
      ]),
      _Callout(
        title: 'The one idea that explains most of this guide',
        body:
            'When Wi-Fi Calling is on, your phone builds a locked, private '
            'tunnel across the Wi-Fi you are on, through the internet, '
            'straight into your phone company. The hotel, the coffee shop and '
            "your own router carry the tunnel. They can't see inside it, but "
            'they still decide whether it connects and how well the call '
            'sounds.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'A word on the words',
        body:
            '**Carrier** means your mobile phone company, such as AT&T, '
            'Verizon, T-Mobile, EE or Telstra. **Cellular** means the '
            'cell-tower network. **4G calling** (which carriers also call '
            'VoLTE, Voice over LTE) and **5G calling** are ordinary calls over '
            'that network. **Emergency address** is the street address you '
            'give your carrier when you turn Wi-Fi Calling on. In the US it is '
            'often called the E911 address (Enhanced 911).',
      ),
    ],
  ),

  // ── 2. Two roads to the same phone company ───────────────────────────────
  _Section(
    number: '2',
    title: 'Two roads to the same phone company',
    children: <Widget>[
      _P(
        'A normal call travels from your phone to a cell tower, and from there '
        "across your carrier's own network. A Wi-Fi call takes a different "
        'road for the first part of the trip, then ends up in exactly the '
        'same place.',
      ),
      _Figure(
        slug: 'f1-two-roads',
        alt:
            'Your phone. Cellular: 4G or 5G calling, to a cell tower, then '
            "the carrier's own cell network. Wi-Fi Calling: a locked tunnel "
            'through a Wi-Fi network, the public internet, sealed to the '
            'carrier. Your carrier: one calling system for both roads, then '
            'on to anyone.',
        caption:
            '**Figure 1.** Both roads end at the same carrier calling system, '
            'so the call looks the same to the person you call. The '
            'difference is who carries the first part of the trip.',
      ),
      _Sub('The locked tunnel'),
      _P(
        'When Wi-Fi Calling is on and connected, your phone opens an encrypted '
        'tunnel to a gateway your carrier runs for exactly this purpose. '
        'Engineers call the tunnel IPsec (Internet Protocol Security) and the '
        'gateway an ePDG (evolved Packet Data Gateway). AT&T even names its '
        'gateway that way: `epdg.epc.att.net`. The same design is written into '
        "the mobile industry's own standards, so it works the same way on "
        'iPhone and Android and at carriers around the world.',
      ),
      _P(
        'Not every Wi-Fi network works with it, as Apple itself says. Some '
        'block the tunnel, and T-Mobile says satellite internet and a phone\'s '
        'hotspot are not supported. AT&T also lists numbers Wi-Fi Calling '
        "can't reach: 211, 311, 511 and 811.",
        small: true,
      ),
      _Callout(
        title: 'What the Wi-Fi owner sees',
        body:
            'A sealed tunnel going to your carrier. Not who you called, and '
            'not what you said.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'What the Wi-Fi owner controls',
        body:
            'Whether the tunnel is allowed through at all, and how fast and '
            'steady the connection is. That part matters, and the section What '
            'your Wi-Fi owes a phone call covers it.',
      ),
      _P(
        'On the cell network, your carrier manages the connection from your '
        "phone to its core. On Wi-Fi, nobody manages the part between the "
        "router and the carrier's gateway. That is the main practical "
        'difference between the two roads.',
        small: true,
      ),
    ],
  ),

  // ── 3. When your phone uses Wi-Fi ────────────────────────────────────────
  _Section(
    number: '3',
    title: 'When your phone uses Wi-Fi',
    children: <Widget>[
      _P(
        'Turning Wi-Fi Calling on does not send every call over Wi-Fi. It '
        'gives the phone a second road. AT&T describes it as your phone using '
        "Wi-Fi for calls and texts when cellular coverage isn't available. In "
        'practice, the phone decides.',
      ),
      _Figure(
        slug: 'f2-when-wifi',
        alt:
            'Cell signal where you are standing, from none or very weak to '
            'strong. Weak or no cell signal: the call goes over Wi-Fi Calling. '
            'The basement office, the thick-walled house, the cabin with no '
            'cell signal. Good cell signal: the call usually goes over the '
            'cell network, even with Wi-Fi Calling on. Some phones let you '
            'change this.',
        caption:
            '**Figure 2.** Wi-Fi Calling is a fallback road for most people. '
            "The exact switch-over point is the phone's and the carrier's "
            'decision, and no one publishes it.',
      ),
      _Sub('How to tell which road a call is using'),
      _Table(
        columns: <String>['Phone', 'What you see when Wi-Fi Calling is in use'],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('iPhone'),
            _Cell(
              '"Wi-Fi" next to your carrier\'s name. Open Control Center to '
              'see it.',
            ),
          ],
          <_Cell>[
            _Cell('Google Pixel'),
            _Cell(
              '"Internet call" or "Wi-Fi calling" on the notification screen '
              'during the call.',
            ),
          ],
          <_Cell>[
            _Cell('Samsung Galaxy'),
            _Cell(
              'Varies by carrier. Some carriers add their own label; BT, for '
              'example, shows "Wi-Fi Call".',
            ),
          ],
        ],
      ),
      _Sub('iPhone and Android are different here'),
      _Cards(<_CardData>[
        _CardData(
          'Android',
          'Some Android phones, Samsung Galaxy among them, offer a choice: '
              '**Wi-Fi preferred** or **Mobile network preferred**, if your '
              'carrier allows it. Some carriers, Verizon for one, only show a '
              'choice like this for when you are roaming abroad.',
        ),
        _CardData(
          'iPhone',
          'Apple documents no "prefer Wi-Fi" choice for calls at home. Many '
              'people report a **Prefer Wi-Fi While Roaming** switch on some '
              'carriers, under the Wi-Fi Calling setting, for use while '
              "traveling. If you don't see it, your carrier doesn't offer it.",
        ),
      ]),
      _P(
        '**On both kinds of phone,** your carrier decides which switches '
        'appear. The names differ from phone to phone; the service underneath '
        'is the same.',
        small: true,
      ),
    ],
  ),

  // ── 4. Walking out the door mid-call ─────────────────────────────────────
  _Section(
    number: '4',
    title: 'Walking out the door mid-call',
    children: <Widget>[
      _P(
        'You start a call on the Wi-Fi at home, then walk out to the car. '
        'Whether the call keeps going depends on your carrier and on the cell '
        'coverage outside. Carriers say different things, so here are their '
        'own words.',
      ),
      _Figure(
        slug: 'f3-walking-out',
        alt:
            'Call starts on Wi-Fi, then you walk out. Into 4G or 5G calling '
            'coverage: the call can hand over to the cell network and carry '
            'on. Into weak coverage, or no 4G calling: the call drops. There '
            'is nothing for it to hand over to. An emergency call on AT&T: '
            'disconnects either way, even inside 4G calling coverage.',
        caption:
            '**Figure 3.** Hand-over only works toward a network that can '
            "carry a 4G or 5G call. Your carrier's rules decide the rest.",
      ),
      _Table(
        columns: <String>[
          'Carrier',
          'What it says about leaving Wi-Fi during a call',
        ],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('AT&T (US)'),
            _Cell(
              '"If you move in or out of Wi-Fi coverage while on a Wi-Fi call, '
              'your call will disconnect unless you have AT&T HD Voice '
              "coverage **(911 calls will disconnect even if you're within HD "
              'Voice coverage)**."',
            ),
          ],
          <_Cell>[
            _Cell('T-Mobile (US)'),
            _Cell(
              'On supported devices and networks, calls may switch between '
              'Wi-Fi and cellular networks without dropping.',
            ),
          ],
          <_Cell>[
            _Cell('EE (UK)'),
            _Cell(
              'If you move out of Wi-Fi range during a call, the phone '
              'switches to 4G calling to keep the call going.',
            ),
          ],
          <_Cell>[
            _Cell('Orange (France), Telekom (Germany), Telstra (Australia)'),
            _Cell('Each says calls hand over to 4G (LTE).'),
          ],
          <_Cell>[
            _Cell('Vodafone Ireland'),
            _Cell(
              'Calls are disconnected if the Wi-Fi signal is no longer '
              'available.',
            ),
          ],
        ],
      ),
    ],
  ),

  // ── 5. Emergency calls ───────────────────────────────────────────────────
  _Section(
    number: '5',
    title: 'Emergency calls',
    children: <Widget>[
      _P(
        'When you turn Wi-Fi Calling on, you are usually asked for a street '
        'address. That is not paperwork. In some situations it is the '
        'location your carrier gives to emergency services.',
      ),
      _Figure(
        slug: 'f4-emergency-call',
        alt:
            'You dial 911. Any cell network? Yes: the phone uses the cell '
            'network, even in airplane mode, even with Wi-Fi Calling on. No: '
            "the call may go over Wi-Fi Calling. The carrier tries your device's "
            'location. If that fails, it can use the address you registered '
            'when you turned the feature on.',
        caption:
            '**Figure 4.** How Apple, AT&T and Verizon describe an emergency '
            'call when Wi-Fi Calling is on. Outside the US the rules differ; '
            'see the next section.',
      ),
      _Sub('What the companies say'),
      _Table(
        columns: <String>['Source', 'In their words'],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('Apple'),
            _Cell(
              '"When cellular service is available, your iPhone uses it for '
              'emergency calls. If you turn on Wi-Fi Calling and cellular '
              'service isn\'t available, emergency calls might use Wi-Fi '
              'Calling."',
            ),
          ],
          <_Cell>[
            _Cell('Verizon'),
            _Cell(
              '911 calls "always try cellular service first, even when your '
              'device is in Airplane Mode or cellular service is off." '
              'Registering a US address is required to turn the feature on.',
            ),
          ],
          <_Cell>[
            _Cell('AT&T'),
            _Cell(
              '"If you can\'t be located using location information obtained '
              "from your device, we'll route 911 calls based on the address "
              'you provide in your device\'s Wi-Fi Calling settings."',
            ),
          ],
          <_Cell>[
            _Cell('T-Mobile'),
            _Cell('"You must set up an e911 address to use Wi-Fi calling."'),
          ],
        ],
      ),
      _Callout(
        tone: _Tone.danger,
        title: 'Three things to do',
        body:
            '1. When you move house, update the emergency address in your '
            'Wi-Fi Calling settings the same day.\n'
            '2. If you ever call for help over Wi-Fi, **say where you are**. '
            "Don't assume the dispatcher can see it.\n"
            '3. Abroad, the address your carrier holds is still your home '
            'address. Dial the local emergency number, and use a local cell '
            'network if you can.',
      ),
    ],
  ),

  // ── 6. Emergency calls around the world ──────────────────────────────────
  _Section(
    number: '6',
    title: 'Emergency calls around the world',
    children: <Widget>[
      _P(
        'The way Wi-Fi Calling works is the same everywhere. What happens when '
        "you dial for help is not, and some carriers won't send an emergency "
        'call over Wi-Fi at all.',
      ),
      _Table(
        columns: <String>[
          'Carrier',
          'Number',
          "Over Wi-Fi Calling, in the carrier's words",
        ],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('AT&T, Verizon, T-Mobile (US)'),
            _Cell('911'),
            _Cell(
              'Can go over Wi-Fi. The carrier uses device location, or falls '
              'back to the registered address.',
              _Verdict.yes,
            ),
          ],
          <_Cell>[
            _Cell('Rogers (Canada)'),
            _Cell('9-1-1'),
            _Cell(
              'Can go over Wi-Fi, in Canada or the US only: "Wi-Fi Calling '
              'cannot support emergency calls made outside of Canada or the '
              'United States."',
              _Verdict.yes,
            ),
          ],
          <_Cell>[
            _Cell('Telstra (Australia)'),
            _Cell('000'),
            _Cell(
              'Works in Australia. "Calls made to emergency services while '
              'using Wi-Fi Calling outside of Australia are not supported."',
              _Verdict.yes,
            ),
          ],
          <_Cell>[
            _Cell('EE (UK)'),
            _Cell('999'),
            _Cell(
              'Works. "We will try to send them your location, but this is not '
              'guaranteed."',
              _Verdict.partly,
            ),
          ],
          <_Cell>[
            _Cell('BT (UK)'),
            _Cell('999'),
            _Cell(
              '"You can call the emergency services on 999, but they can\'t '
              'identify your location. You should use a landline if you can."',
              _Verdict.partly,
            ),
          ],
          <_Cell>[
            _Cell('Vodafone Ireland'),
            _Cell('999 / 112'),
            _Cell(
              'The phone will try "a normal mobile network only. If there\'s no '
              'mobile network available, the call will not be possible."',
              _Verdict.no,
            ),
          ],
          <_Cell>[
            _Cell('Deutsche Telekom (Germany)'),
            _Cell('110 / 112'),
            _Cell(
              'Emergency calls are not possible when Wi-Fi is the only network '
              'available for calls.',
              _Verdict.no,
            ),
          ],
        ],
      ),
      _P(
        'Green: can go over Wi-Fi with a location or address. Amber: goes '
        "through, location not guaranteed. Red: won't go over Wi-Fi at all. "
        "Checked on each carrier's own page, 27 September 2026.",
        small: true,
      ),
      _Callout(
        tone: _Tone.danger,
        title: 'The rule that holds everywhere',
        body:
            'In an emergency, your phone tries the cell network first. Whether '
            'it can call over Wi-Fi, and what location it sends, depends on '
            'your carrier and your country. Before you rely on it, read your '
            "own carrier's page.",
      ),
      _Callout(
        title: 'Wi-Fi-only places deserve a plan',
        body:
            'If you live or work somewhere with no cell signal at all, a '
            'basement office or a remote cabin, find out now what your carrier '
            'does with an emergency call over Wi-Fi. On some carriers the '
            "answer is that it won't connect. A landline, where there is one, "
            'is the fallback BT itself recommends. And remember that Wi-Fi '
            'Calling needs your internet connection, your Wi-Fi equipment and '
            'usually mains power. In a power or internet outage, it goes down '
            'with them.',
      ),
    ],
  ),

  // ── 7. iPad, Mac and Apple Watch ─────────────────────────────────────────
  _Section(
    number: '7',
    title: 'iPad, Mac and Apple Watch',
    children: <Widget>[
      _P(
        'You can make and answer phone calls on an iPad, a Mac or an Apple '
        'Watch. Two different features do this, and the difference matters '
        'most in an emergency.',
      ),
      _Figure(
        slug: 'f5-other-devices',
        alt:
            '1. Calls from iPhone (relay): Mac or iPad, same Wi-Fi, iPhone, '
            'cell tower. The iPhone places the call. The Mac or iPad is just a '
            'speaker and microphone. The iPhone must be switched on, nearby, '
            'on the same Wi-Fi. 2. Wi-Fi Calling on the device itself: Mac in '
            'a hotel, internet tunnel, your carrier. The iPhone can be off, or '
            'at home. The call goes straight to the carrier. Only some '
            'carriers offer it, and 911 may use your registered home address.',
        caption:
            '**Figure 5.** Who places the call? In the first, the iPhone does. '
            'In the second, the Mac or iPad does, through your carrier.',
      ),
      _Sub('Which carriers offer the second one'),
      _P(
        "Apple's own carrier lists (September 2026) show Wi-Fi Calling on "
        'other devices for **AT&T, Verizon and T-Mobile** and several smaller '
        'US carriers, Metro by T-Mobile, Mint Mobile and Xfinity Mobile among '
        'them, and for **EE** in the UK. Apple lists none in Canada, Ireland, '
        'Germany, France, Australia or India. Everywhere else, the iPhone has '
        'to be on and nearby. On a cellular iPad, Apple says a call can switch '
        "to the carrier's cell network using 4G calling if the Wi-Fi is lost, "
        'where that is available and turned on. An Apple Watch gets the '
        'feature when **Allow Calls on Other Devices** is on. **On an iPad, '
        'Apple also warns that while connected to Wi-Fi Calling, it may not '
        'receive emergency alerts.**',
      ),
      _P(
        'Android has no direct match for the second feature. Samsung\'s "Call '
        '& text on other devices" relays through your phone, like the first; '
        "Samsung says it currently doesn't work with Verizon and AT&T phones. "
        'Google Fi customers can make calls in a web browser with the phone '
        "off, Google's own carrier only.",
        small: true,
      ),
    ],
  ),

  // ── 8. Calling home from abroad ──────────────────────────────────────────
  _Section(
    number: '8',
    title: 'Calling home from abroad',
    children: <Widget>[
      _P(
        'On many carriers, a Wi-Fi call from a hotel abroad back to a number '
        'at home costs nothing extra. Calls to local numbers are a different '
        'story, and in some countries the feature is blocked.',
      ),
      _Figure(
        slug: 'f6-abroad',
        alt:
            'Call home: a Wi-Fi call back to a number in your home country. '
            'Usually free, on many carriers, not all. Call a local number: a '
            "Wi-Fi call to a number in the country you're visiting. Charged, "
            'as an international call, or blocked. Some countries: your '
            "carrier switches the feature off there entirely. Won't work, "
            "check your carrier's list.",
        caption:
            '**Figure 6.** Three outcomes of a Wi-Fi call made abroad. The '
            "table below gives each carrier's own rule.",
      ),
      _Table(
        columns: <String>[
          'Carrier',
          'Wi-Fi Calling abroad, in brief (checked 27 September 2026)',
        ],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('AT&T'),
            _Cell(
              'Wi-Fi calls to US numbers are free. Other calls are billed '
              'under your international plan. Not available in China, Cuba, '
              'North Korea, India, Iran, Israel, Pakistan, Saudi Arabia, '
              'Sudan, Syria, Turkey, the United Arab Emirates or Vietnam.',
            ),
          ],
          <_Cell>[
            _Cell('Verizon'),
            _Cell(
              'Calls to the US at no extra charge; calls to non-US numbers '
              'count as international calls, and a voice prompt warns you. On '
              "an iPhone, Wi-Fi Calling can't be turned on after you leave the "
              'US.',
            ),
          ],
          <_Cell>[
            _Cell('T-Mobile'),
            _Cell(
              'On unlimited plans, no fees for Wi-Fi calls to US numbers; '
              'Canada and Mexico count too only if your plan includes them. '
              'Other plans count against plan limits. Not available where '
              'Wi-Fi Calling is prohibited by law, including North Korea, Iran '
              'and Syria.',
            ),
          ],
          <_Cell>[
            _Cell('EE, BT (UK); Orange (France)'),
            _Cell(
              'Home country only. BT: "Wi-Fi Calling doesn\'t work while '
              'you\'re roaming." Orange: metropolitan France only.',
            ),
          ],
          <_Cell>[
            _Cell('Telekom (Germany)'),
            _Cell(
              "Calls from abroad to Germany are covered by the plan's flat "
              'rate.',
            ),
          ],
          <_Cell>[
            _Cell('Telstra (Australia)'),
            _Cell(
              'Calls to Australia are free; calls to other destinations '
              "aren't enabled while you're overseas.",
            ),
          ],
          <_Cell>[
            _Cell('Jio (India)'),
            _Cell(
              'Needs an international roaming pack; calls to Indian numbers '
              'are ₹1 a minute.',
            ),
          ],
        ],
      ),
      _P(
        'One pair worth noticing: AT&T switches its Wi-Fi Calling off inside '
        "India, while Jio, India's largest carrier, sells the feature. The "
        'rule belongs to your home carrier, not only to the country you are '
        'in.',
        small: true,
      ),
      _Callout(
        tone: _Tone.warning,
        title: 'Set it up before you leave',
        body:
            "Turn it on and register your address at home. Verizon says an "
            "iPhone can't activate it abroad, and it is good practice on every "
            'carrier.',
      ),
    ],
  ),

  // ── 9. Wi-Fi Calling vs WhatsApp and FaceTime ────────────────────────────
  _Section(
    number: '9',
    title: 'Wi-Fi Calling vs WhatsApp and FaceTime',
    children: <Widget>[
      _P(
        'WhatsApp calls and FaceTime Audio also work over Wi-Fi, and they are '
        'often the right choice abroad. They are a different kind of thing. '
        'Wi-Fi Calling is your phone company. An app call is the app company.',
      ),
      _Figure(
        slug: 'f7-vs-apps',
        alt:
            'Carrier Wi-Fi Calling: calls almost any phone number; shows your '
            'own phone number; emergency calls possible (section 5); blocked '
            'in some countries. WhatsApp, FaceTime Audio: only other people '
            'using the app; shows your app account; not for emergencies; not '
            'available everywhere either.',
        caption:
            '**Figure 7.** Both use Wi-Fi. Only one is a phone call on your '
            "phone company's system.",
      ),
      _Table(
        columns: <String>[
          '',
          'Carrier Wi-Fi Calling',
          'WhatsApp or FaceTime Audio',
        ],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('Who carries the call'),
            _Cell('Your carrier'),
            _Cell("The app company's servers"),
          ],
          <_Cell>[
            _Cell('Who you can call'),
            _Cell('Almost any phone number', _Verdict.yes),
            _Cell('Only people using the same app', _Verdict.no),
          ],
          <_Cell>[
            _Cell('Emergency calls'),
            _Cell('Possible, cell network preferred', _Verdict.yes),
            _Cell(
              'WhatsApp: "You can\'t access emergency service numbers through '
              'WhatsApp." For FaceTime, use the Phone app for emergencies.',
              _Verdict.no,
            ),
          ],
          <_Cell>[
            _Cell('Where it works'),
            _Cell(
              'Blocked in some countries (the section Calling home from '
              'abroad)',
            ),
            _Cell(
              'Apple says FaceTime Audio may not be available in all '
              'countries or regions',
            ),
          ],
          <_Cell>[
            _Cell('Cost'),
            _Cell(
              'Free to home on many carriers (the section Calling home from '
              'abroad)',
            ),
            _Cell('Uses data only'),
          ],
        ],
      ),
      _Callout(
        title: 'A sensible travel habit',
        body:
            'Use an app call to reach people who have the app. Use Wi-Fi '
            "Calling for everyone else: the bank, the airline, the doctor's "
            'office, anyone who only has a phone number. Keep the Phone app '
            'for emergencies.',
      ),
    ],
  ),

  // ── 10. What your Wi-Fi owes a phone call ────────────────────────────────
  _Section(
    number: '10',
    title: 'What your Wi-Fi owes a phone call',
    children: <Widget>[
      _P(
        "A phone call doesn't need much speed. It needs every piece to arrive "
        'quickly, steadily and without gaps.',
      ),
      _Figure(
        slug: 'f8-what-wifi-owes',
        alt:
            'The whole trip, mouth to ear: 150 milliseconds or less feels '
            'natural. Your Wi-Fi, your internet line, internet and carrier to '
            'the other phone. Every part of the trip spends from the same '
            'budget. When someone uploads photos on the same connection, the '
            'internet-line slice can grow by hundreds of milliseconds on its '
            "own. Wi-Fi's four lanes (WMM, Wi-Fi Multimedia): Voice, the fast "
            'lane; Video; Best effort, everyday data; Background.',
        caption:
            '**Figure 8.** Top: one delay budget shared by every part of the '
            'trip (slices not to scale; the split varies with every call). '
            'Bottom: the four traffic lanes Wi-Fi can give different priority '
            'to.',
      ),
      _Table(
        columns: <String>['What matters', 'What the sources say'],
        rows: <List<_Cell>>[
          <_Cell>[
            _Cell('Delay'),
            _Cell(
              'The ITU (International Telecommunication Union) says that when '
              'one-way delay stays below 150 ms, most applications feel '
              'instant. That is the whole trip; the Wi-Fi is only one slice.',
            ),
          ],
          <_Cell>[
            _Cell('Lost pieces'),
            _Cell(
              'The FCC (US Federal Communications Commission) calls 1% packet '
              'loss the point where calls and other highly interactive '
              'applications degrade significantly.',
            ),
          ],
          <_Cell>[
            _Cell('A busy line'),
            _Cell(
              'The FCC measured home lines whose delay under load ran to '
              "several hundred milliseconds. One person's upload can ruin "
              "another person's call.",
            ),
          ],
          <_Cell>[
            _Cell('Uneven arrival'),
            _Cell(
              'Called jitter: pieces arriving unevenly. It breaks up a call '
              'too. We found no published threshold to print.',
            ),
          ],
        ],
      ),
      _Sub('The router checklist'),
      _Steps(<String>[
        '**Let the tunnel through.** AT&T asks for IPsec pass-through, ports '
            '500 and 4500 (UDP) and 143 (TCP) open, MTU (maximum packet size) '
            'at 1500, and current router firmware. For exact firewall rules, '
            "use your carrier's page.",
        '**Leave WMM on.** Apple recommends WMM "Enabled" because it '
            'prioritizes voice and video.',
        '**Know the catch.** The call is encrypted, so your router may not '
            'recognize it as voice. Some phones label the encrypted packets as '
            'voice anyway; others may not. The standards leave that to each '
            'maker, and no carrier page we found says which happens.',
        // The print guide ends this step "(page 5)", a pointer to the Keith's
        // note left out of this lesson (not yet approved), so it is dropped.
        '**Make hand-overs quick.** Moving between access points or mesh '
            'units should be fast.',
      ]),
    ],
  ),

  // ── 11. Six things people get wrong ──────────────────────────────────────
  _Section(
    number: '11',
    title: 'Six things people get wrong',
    children: <Widget>[
      _P("Six common beliefs, and what the carriers' own pages say."),
      _Myth(
        myth: '"It\'s on by default, and I don\'t need it anyway."',
        fact:
            'It has to be turned on, per phone line, usually with an emergency '
            'address. Without it, a house with a weak cell signal means missed '
            'calls.',
      ),
      _Myth(
        myth: '"Turning it on means my calls go over Wi-Fi."',
        fact:
            'The phone mostly uses Wi-Fi Calling when the cell signal is weak '
            'or missing. On an iPhone, look for "Wi-Fi" next to the carrier '
            'name.',
      ),
      _Myth(
        myth: '"I\'ll turn it on when I land."',
        fact:
            "Verizon says an iPhone can't activate it once you've left the US, "
            'and some countries block it outright. Set it up at home.',
      ),
      _Myth(
        myth: '"Hotel Wi-Fi works for Wi-Fi Calling."',
        fact:
            "Not until you finish the hotel's sign-in page. Some networks also "
            'block the ports the tunnel needs, and a crowded network breaks up '
            'calls.',
      ),
      _Myth(
        myth: '"My call will carry on when I walk outside."',
        fact:
            "Only if there's 4G or 5G calling coverage outside and your carrier "
            'hands calls over. On AT&T, an emergency call over Wi-Fi '
            'disconnects either way.',
      ),
      _Myth(
        myth: '"I need a VPN to keep my Wi-Fi calls private."',
        fact:
            'The call is already sealed in an encrypted tunnel to your '
            'carrier. A VPN (Virtual Private Network) adds a second tunnel and '
            'can change where the network thinks you are.',
      ),
      _Callout(
        title: 'And one bonus',
        body:
            '"Wi-Fi Calling is the same thing as WhatsApp." It isn\'t. The '
            'section Wi-Fi Calling vs WhatsApp and FaceTime shows why the '
            "difference matters most when you need to call a number that isn't "
            'on the app, or call for help.',
      ),
    ],
  ),

  // ── Appendix A: how to turn it on ────────────────────────────────────────
  _Section(
    number: 'A',
    spokenNumber: 'Appendix A',
    title: 'How to turn it on',
    children: <Widget>[
      _P(
        "From Apple's, Google's and Samsung's help pages, September 2026. "
        'Screens vary by model, software and carrier; a missing switch means '
        "your carrier doesn't support it.",
        small: true,
      ),
      _Task(
        title: 'iPhone',
        steps: <String>[
          'Open `Settings › Cellular`. If you have more than one line, pick '
              'the line.',
          'Tap `Wi-Fi Calling`, then turn on `Wi-Fi Calling on This iPhone`.',
          'Tap `Enable`, then enter or confirm your address for emergency '
              'services.',
        ],
      ),
      _Task(
        title: 'Google Pixel, and phones using the Phone by Google app',
        why:
            "Android 6.0 or later. Google says if you can't find the option, "
            "your carrier doesn't support it.",
        steps: <String>[
          "Open `Settings › Network & internet › SIMs`, then pick your "
              "carrier's SIM.",
          'Turn on `Wi-Fi calling`. If your carrier asks, enter your '
              'emergency address.',
        ],
      ),
      _Task(
        title: 'Samsung Galaxy',
        steps: <String>[
          'Swipe down and tap the `Wi-Fi Calling` tile in Quick settings, or '
              'open the Phone app, tap `More options › Settings › Wi-Fi '
              'Calling`.',
          'If offered, choose `Wi-Fi preferred` or `Mobile network '
              'preferred`, and fill in the emergency information.',
        ],
      ),
      _Task(
        title: 'iPad, Mac and Apple Watch',
        why: 'Same Apple Account for iCloud and FaceTime on every device.',
        steps: <String>[
          'On the iPhone, after turning on Wi-Fi Calling, go back one screen '
              'and tap `Calls on Other Devices`. Turn on `Allow Calls on Other '
              'Devices`, then turn on each device listed under `Allow Calls '
              'On`.',
          'On the iPad: `Settings › Apps › FaceTime › Calls from iPhone`. On '
              'the Mac: `FaceTime › Settings › Calls from iPhone`.',
          'On a Mac, an `Upgrade to Wi-Fi Calling` button appears if your '
              'carrier supports calls with the iPhone off or away.',
        ],
      ),
      _Task(
        title: 'Update your emergency address, every time you move',
        steps: <String>[
          "iPhone and Android: in your phone's Wi-Fi Calling settings, where "
              'you first entered it.',
          'T-Mobile also lets you change it through your My T-Mobile account '
              'or Customer Care. On a Mac, the address is in FaceTime '
              'Settings.',
        ],
      ),
    ],
  ),

  // ── Appendix B: checklists ───────────────────────────────────────────────
  _Section(
    number: 'B',
    spokenNumber: 'Appendix B',
    title: 'Checklists',
    children: <Widget>[
      _Sub('At home, once'),
      _Checklist(_atHome),
      _Sub('Before a trip abroad'),
      _Checklist(_beforeATrip),
      _Callout(
        title: 'Keeping the phone off foreign cell networks',
        body:
            'One way to do it: turn on airplane mode, then turn Wi-Fi and '
            'Wi-Fi Calling back on, so calls go over Wi-Fi Calling instead of '
            'a roaming cell network. T-Mobile recommends exactly this; check '
            "your own carrier's roaming page for charges. Verizon notes that "
            'an emergency call still tries the cell network, even in airplane '
            'mode.',
      ),
      _Callout(
        tone: _Tone.warning,
        title: "Once you're there",
        body:
            "Open a web browser and finish the hotel's sign-in page before you "
            'expect a call to connect. If calls still won\'t connect, the '
            'network may block the tunnel (UDP ports 500 and 4500); ask the '
            'front desk. If the Wi-Fi is crowded and calls break up, try the '
            'cell network, or an app call to people who have the app.',
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
        "Checked against each company's own pages on 27 September 2026. "
        'Carrier rules, prices and country lists change; read your carrier\'s '
        'current page before you travel. Figures no company publishes, such '
        'as battery cost or the exact signal level where a phone switches to '
        'Wi-Fi, are deliberately left out.',
        small: true,
      ),
      _Sources(),
      _Callout(
        title: 'About this guide',
        body:
            "Written for people who aren't technical and want to know what "
            'Wi-Fi Calling does before they need it. Product and company names '
            "are trademarks of their owners. This guide is independent and "
            "isn't affiliated with or endorsed by any carrier or device maker.",
      ),
    ],
  ),
];

// Appendix B, "At home, once". The Where column's "page N" pointers name the
// section instead.
const List<_Check> _atHome = <_Check>[
  _Check('Wi-Fi Calling is on for every line that needs it', 'Appendix A'),
  _Check(
    'The emergency address is your current address',
    'Wi-Fi Calling settings',
  ),
  _Check(
    'You know what your carrier does with an emergency call over Wi-Fi',
    "Emergency calls around the world, then your carrier's page",
  ),
  _Check(
    'Calls on your iPad, Mac or Watch are set up, if you want them',
    'Appendix A',
  ),
  _Check(
    'WMM is on in your router, and IPsec pass-through is allowed',
    'Router settings, What your Wi-Fi owes a phone call',
  ),
];

// Appendix B, "Before a trip abroad".
const List<_Check> _beforeATrip = <_Check>[
  _Check(
    'Wi-Fi Calling is turned on and working before you leave',
    'Appendix A',
  ),
  _Check(
    "The country you're visiting isn't on your carrier's blocked list",
    "Your carrier's Wi-Fi Calling page",
  ),
  _Check(
    'You know which calls are free (usually to home) and which are charged',
    'Calling home from abroad',
  ),
  _Check(
    "You know the local emergency number where you're going",
    'Local information',
  ),
  _Check(
    'WhatsApp or FaceTime is set up for the people who use it',
    'Wi-Fi Calling vs WhatsApp and FaceTime',
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
  final TextStyle base =
      (small ? t.bodySmall : t.bodyMedium) ?? const TextStyle();
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
        // Decorative: Figure 1 in section 2 carries the same two roads with
        // every label, and its caption reads them to a screen reader.
        const _FigureBand(slug: 'cover-two-roads', zoomable: false),
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
          'What happens when your phone makes a call over Wi-Fi instead of the '
          'cell tower, when it helps, when it drops, what it means for '
          'emergency calls, and what to set up before your next trip.',
          style: (t.titleMedium ?? const TextStyle()).copyWith(
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Carrier details checked 27 September 2026',
          style: _body(context, small: true, color: colors.textSecondary),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tables, as one card per row.
// ─────────────────────────────────────────────────────────────────────────────

/// The print guide's colored cells: green "can", amber "partly", red "won't".
/// [none] is an uncolored cell.
enum _Verdict { none, yes, partly, no }

@immutable
class _Cell {
  const _Cell(this.text, [this.verdict = _Verdict.none]);

  final String text;
  final _Verdict verdict;
}

/// A print table rendered as a stack of cards, one per row. The first column
/// is the card's title. A two-column table shows the second cell as the card
/// body; a wider one labels each cell with its column header. Each card reads
/// as one screen-reader node: "Column: value." for every cell.
class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<_Cell>> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _RowCard(columns: columns, cells: rows[i]),
        ],
      ],
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.columns, required this.cells});

  final List<String> columns;
  final List<_Cell> cells;

  static String _say(String column, String value) =>
      column.isEmpty ? '${_plain(value)}.' : '$column: ${_plain(value)}.';

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextTheme t = Theme.of(context).textTheme;
    final bool labelled = columns.length > 2;
    return Semantics(
      label: <String>[
        for (int i = 0; i < cells.length; i++) _say(columns[i], cells[i].text),
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
              cells.first.text,
              style: (t.titleSmall ?? const TextStyle()).copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (int i = 1; i < cells.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: labelled
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            columns[i],
                            style: (t.bodySmall ?? const TextStyle()).copyWith(
                              color: colors.textTertiary,
                              height: 1.4,
                            ),
                          ),
                          _VerdictText(cell: cells[i]),
                        ],
                      )
                    : _VerdictText(cell: cells[i]),
              ),
          ],
        ),
      ),
    );
  }
}

/// A cell's text, tinted by its verdict and led by a verdict icon so the tint
/// is never the only cue (tick: can; alert: partly; block: won't).
class _VerdictText extends StatelessWidget {
  const _VerdictText({required this.cell});

  final _Cell cell;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle base = _body(context, small: true);
    final (Color, IconData)? mark = switch (cell.verdict) {
      _Verdict.none => null,
      _Verdict.yes => (colors.statusSuccess, Icons.check_circle_outline),
      _Verdict.partly => (colors.statusWarning, Icons.error_outline),
      _Verdict.no => (colors.statusDanger, Icons.block),
    };
    if (mark == null) return _Rich(cell.text, style: base);
    final TextStyle tinted = base.copyWith(
      color: mark.$1,
      fontWeight: FontWeight.w600,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2, right: AppSpacing.xxs),
          child: Icon(mark.$2, size: 16, color: mark.$1),
        ),
        Expanded(child: _Rich(cell.text, style: tinted)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Appendix B: the two checklists. Real checkboxes, held in memory only.
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _Check {
  const _Check(this.check, this.where);

  final String check;
  final String where;
}

class _Checklist extends StatefulWidget {
  const _Checklist(this.items);

  final List<_Check> items;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  late final List<bool> _done = List<bool>.filled(widget.items.length, false);

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
          for (int i = 0; i < widget.items.length; i++) ...<Widget>[
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
              title: Text(widget.items[i].check, style: _body(context)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text('Where: ${widget.items[i].where}', style: where),
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
    '3GPP TS 33.402 (ETSI TS 133 402): IKEv2 and IPsec between the phone and '
        'the ePDG',
    'GSMA IR.51: IMS profile for voice, video and SMS over untrusted Wi-Fi '
        'access',
    'Apple 108066, make a call with Wi-Fi Calling; Apple iPhone User Guide, '
        'make calls using Wi-Fi',
    'Apple 102405, calls on iPad and Mac from iPhone; Apple FaceTime User '
        'Guide for Mac, set up phone calls',
    'Apple 109526, 108048, 109510 and 118609, carrier feature lists by region',
    'Apple, Wi-Fi Calling & Privacy '
        '(apple.com/legal/privacy/data/en/wi-fi-calling)',
    'Apple 102766, recommended Wi-Fi router settings (WMM)',
    'Apple 105088, FaceTime availability',
    'Google Phone app Help 2811843, Wi-Fi calling; Google Fi Help 16710124, '
        'web calls',
    'Samsung UK, activate Wi-Fi Calling on a Galaxy; Samsung US '
        'ANS10001614, Call & text on other devices',
    'AT&T KM1063258 and Wi-Fi Calling legal terms; KM1401809, international; '
        'KM1114459, LAN and VPN configuration',
    'Verizon Wi-Fi Calling FAQs; Verizon international and Wi-Fi Calling '
        'terms',
    'T-Mobile, Wi-Fi Calling from T-Mobile; Wi-Fi calling troubleshooting; '
        'international roaming',
    'EE, Wi-Fi Calling help page; BT, using Wi-Fi Calling',
    'Vodafone Ireland, terms and conditions for Wi-Fi Calling',
    'Telekom Deutschland, VoLTE and WLAN Call (business help)',
    'Orange, Appels Wi-Fi; Telstra, Wi-Fi Calling; Rogers, 9-1-1 emergency '
        'service; Jio, Wi-Fi Calling',
    'WhatsApp Help Center, emergency calls',
    'ITU-T G.114, one-way transmission time',
    'FCC, 13th Measuring Broadband America report (FCC 24-136)',
    'Wi-Fi Alliance, Wi-Fi CERTIFIED WMM',
    'IETF RFC 4301, Security Architecture for the Internet Protocol '
        '(markings inside a tunnel)',
  ];

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final TextStyle s = _body(
      context,
      small: true,
      color: colors.textSecondary,
    );
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
                  child: Text(
                    '•  ',
                    style: s.copyWith(color: colors.textAccent),
                  ),
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

enum _Tone { accent, warning, danger }

/// A titled callout with a filled rail (lime, §8.13 warning, or danger for
/// the print guide's red "stop" boxes). The title carries the meaning, so the
/// rail color is never the only cue.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.title,
    required this.body,
    this.tone = _Tone.accent,
  });

  final String title;
  final String body;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme colors = context.colors;
    final Color rail = switch (tone) {
      _Tone.accent => colors.primary,
      _Tone.warning => colors.statusWarning,
      _Tone.danger => colors.statusDanger,
    };
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
                    style:
                        (Theme.of(context).textTheme.labelSmall ??
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

/// One Appendix A task: title, optional "why" line, numbered steps.
class _Task extends StatelessWidget {
  const _Task({required this.title, required this.steps, this.why});

  final String title;
  final String? why;
  final List<String> steps;

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
              style:
                  (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
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
        if (WifiCallingDiagrams.has(slug))
          const SizedBox(height: AppSpacing.xs),
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
    'cover-two-roads': 700 / 250,
    'f1-two-roads': 760 / 300,
    'f2-when-wifi': 760 / 230,
    'f3-walking-out': 760 / 250,
    'f4-emergency-call': 760 / 270,
    'f5-other-devices': 760 / 290,
    'f6-abroad': 760 / 170,
    'f7-vs-apps': 760 / 250,
    'f8-what-wifi-owes': 760 / 250,
  };

  // Memoized swapped-light sources, so a rebuild reuses one Future per slug
  // and the string replace runs once.
  static final Map<String, Future<String>> _light = <String, Future<String>>{};

  Future<String> _lightSource() => _light.putIfAbsent(
    slug,
    () async => ConceptGraphicBand.applyLightSwap(
      await rootBundle.loadString(WifiCallingDiagrams.path(slug)),
    ),
  );

  Widget _svg(bool light, {double? width, double? height}) {
    if (!light) {
      return SvgPicture.asset(
        WifiCallingDiagrams.path(slug),
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
    if (!WifiCallingDiagrams.has(slug)) return const SizedBox.shrink();
    final AppColorScheme colors = context.colors;
    final bool light = colors.isLight;
    final Widget inPage = _svg(light, width: double.infinity);
    return Container(
      key: ValueKey<String>('wifi-calling-figure-$slug'),
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
            return SizedBox(
              height: drawing,
              child: Center(child: inPage),
            );
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
