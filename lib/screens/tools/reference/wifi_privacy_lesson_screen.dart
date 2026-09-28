// Wi-Fi Privacy Myths. A Wi-Fi Classroom Guided Lesson in two parts, each with
// one interactive control, built on the Find My, Explained pattern through
// lesson_parts.dart.
//
// SPEC: Pax's research brief, candidates 7 and 8
// (myPKA/Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md §3),
// merged into one lesson on Keith's approval (2026-09-27), plus the §5
// anti-patterns.
//
// GUARDS
//  - No OS or product names on screen: the device is "your phone". The
//    Sources section keeps Apple's pages as the citations they are.
//  - The rotation interval. Larry's brief and Pax's §3 said Apple does not
//    publish one. Apple 102509 (published 2025-12-05, fetched 2026-09-27)
//    does: Rotating "rotates to a different private address every 2 weeks".
//    The lesson uses it, attributed on screen to "one phone maker", and does
//    not generalize it to other makers (unsourced here). The second scene is
//    two visits a MONTH apart for that reason: on consecutive days a
//    two-week rotation would usually show the same address, so "one router
//    on two days" would have taught the wrong thing.
//  - MAC filtering is weak: CWNA-109 objective 5.1.4 (checked against
//    CWNP's PDF 2026-09-27); SSID hiding is 5.1.3.
//
// States (SOP-007 §5): success is the only reachable state. Nothing is
// disabled. Interactive: two AppToggles, the Predict button and its "Show me"
// button, the help footer.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/wifi_privacy_model.dart';
import '../../../theme/app_tokens.dart';
import 'lesson_parts.dart';
import 'wifi_privacy_stage.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
/// Permanent; never renamed.
const String kWifiPrivacyMythsToolId = 'wifi-privacy-myths';

class WifiPrivacyLessonScreen extends StatefulWidget {
  const WifiPrivacyLessonScreen({super.key});

  @override
  State<WifiPrivacyLessonScreen> createState() =>
      _WifiPrivacyLessonScreenState();
}

class _WifiPrivacyLessonScreenState extends State<WifiPrivacyLessonScreen> {
  final WifiPrivacyController _controller = WifiPrivacyController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LessonScaffold(
      title: 'Wi-Fi Privacy Myths',
      toolId: kWifiPrivacyMythsToolId,
      children: <Widget>[
        const LessonHero(
          eyebrow: 'A plain-English lesson',
          promise:
              'Two Wi-Fi settings people trust for privacy and security, and '
              'what each one does.',
        ),

        // ── 1 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '1',
          title: 'The short answer',
          children: <Widget>[
            LessonP(
              '**A private Wi-Fi address** stops different networks from '
              'matching your phone by its address. **MAC filtering** keeps out '
              'no one who wants in. **Hiding the network name** does not hide '
              'the network, and it makes your phone say the name everywhere it '
              'goes.',
            ),
          ],
        ),

        // ── 2 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '2',
          title: "Your phone's private Wi-Fi address",
          children: <Widget>[
            LessonP(
              'Every Wi-Fi device has a hardware address, its MAC (media '
              'access control) address, and every frame it sends starts with '
              'it, unencrypted. If a phone used that one address everywhere, '
              'any network, or anyone listening nearby, could follow it from '
              'place to place and day to day.',
            ),
            LessonP(
              'So phones can make up a **private address** instead. Where a '
              'phone offers the choice, it has three settings: **Off** (the '
              'hardware address), **Fixed** (a made-up address for each '
              'network, kept for that network), and **Rotating** (a made-up '
              'address for each network that also changes on a schedule).',
            ),
          ],
        ),

        // ── 3 ──────────────────────────────────────────────────────────────
        LessonSection(
          number: '3',
          title: 'Try it: what the routers record',
          children: <Widget>[
            LessonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const LessonLabel('Try it'),
                  const SizedBox(height: AppSpacing.xs),
                  AddressControls(controller: _controller),
                  const SizedBox(height: AppSpacing.sm),
                  AddressStage(controller: _controller),
                ],
              ),
            ),
          ],
        ),

        // ── 4 ──────────────────────────────────────────────────────────────
        LessonSection(
          number: '4',
          title: 'Predict, then reveal',
          children: <Widget>[
            LessonPredict(
              question:
                  'Your phone is set to Fixed. It joins your home network, and '
                  'the same cafe today and again next month. Which routers can '
                  'tell it is the same phone?',
              answer:
                  'The cafe can match its own two visits: Fixed keeps the '
                  "same address for that network. **The cafe can't match your "
                  'phone to your home router**, because each network gets its '
                  'own address.',
              after: TextButton.icon(
                onPressed: () => _controller.mode = PmAddressMode.fixed,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Show me on Fixed'),
              ),
            ),
          ],
        ),

        // ── 5 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '5',
          title: 'Why MAC filtering keeps no one out',
          children: <Widget>[
            LessonP(
              'A MAC filter is a list on the router of the addresses allowed '
              'to join. The trouble is that the address travels unencrypted '
              'at the start of every frame. Anyone listening can copy an '
              'allowed one and use it as their own. CWNP lists MAC filtering '
              'among the weak security options that should not be used in '
              'enterprise networks.',
            ),
            LessonP(
              'Private addresses make the list harder to keep, too. A phone on '
              'Rotating comes back with an address the list has never seen. '
              'The setting that protects a network is its security: a strong '
              'password, or one login per person.',
            ),
          ],
        ),

        // ── 6 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '6',
          title: 'Hiding the network name',
          children: <Widget>[
            LessonP(
              'An access point (AP) announces its network many times a second '
              'in frames called beacons, and the network name, or SSID '
              '(service set identifier), is in each one. That is how your '
              'phone lists the networks around you without asking.',
            ),
            LessonP(
              'A router can be set to leave the name out. The network does '
              'not go away: its beacons still go out, just with a blank name. '
              'Your phone can no longer listen for the name, so it has to ask '
              'for it by name, in a **probe request**, wherever it is.',
            ),
          ],
        ),

        // ── 7 ──────────────────────────────────────────────────────────────
        LessonSection(
          number: '7',
          title: 'Try it: hide the name',
          children: <Widget>[
            LessonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const LessonLabel('Try it'),
                  const SizedBox(height: AppSpacing.xs),
                  HiddenNameControls(controller: _controller),
                  const SizedBox(height: AppSpacing.sm),
                  HiddenNameStage(controller: _controller),
                ],
              ),
            ),
          ],
        ),

        // ── 8 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '8',
          title: 'Three things people get wrong',
          children: <Widget>[
            LessonMyth(
              myth: 'MAC filtering keeps strangers off my network.',
              fact:
                  'Addresses cross the air unencrypted, so an allowed one is '
                  "easy to copy. Use the network's password security instead.",
            ),
            LessonMyth(
              myth: "The router's device list shows my phone's real address.",
              fact:
                  'With a private address on, it shows the address your phone '
                  'made up for that network. With Rotating, that changes too.',
            ),
            LessonMyth(
              myth: 'Hiding the network name is a security setting.',
              fact:
                  'The network is still on the air, and its name crosses the '
                  'air whenever a device joins. Meanwhile your phone names it '
                  'at the airport, the cafe and everywhere else it goes.',
            ),
          ],
        ),

        // ── Sources ────────────────────────────────────────────────────────
        const LessonSection(
          number: '→',
          spokenNumber: 'Sources',
          title: 'Where these facts come from',
          children: <Widget>[
            LessonP(
              'Checked 27 September 2026. The two-week rotation is the one '
              'phone maker that publishes a figure; the lesson does not assume '
              'other phones do the same.',
              small: true,
            ),
            LessonSources(<String>[
              'Apple 102509, Use private Wi-Fi addresses on Apple devices (Off, '
                  'Fixed, Rotating; Rotating "rotates to a different private '
                  'address every 2 weeks"), published 5 December 2025',
              'Apple Platform Security guide, Wi-Fi privacy with Apple devices '
                  '(the three modes and their defaults; hidden networks and '
                  'probe requests)',
              'Apple 102766, Recommended settings for Wi-Fi routers and access '
                  'points (hidden network, MAC address filtering)',
              'CWNP CWNA-109 exam objectives 5.1.3 (SSID hiding) and 5.1.4 '
                  '(MAC filtering)',
              'IETF RFC 7042, the documentation address range used for the '
                  'hardware address shown',
            ]),
          ],
        ),
      ],
    );
  }
}
