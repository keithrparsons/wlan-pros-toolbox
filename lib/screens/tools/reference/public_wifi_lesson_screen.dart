// Public Wi-Fi: what the person next to you can see. A Wi-Fi Classroom
// Guided Lesson with one interactive control, built on the Find My, Explained
// pattern (numbered landmark sections, callouts, myth/fact pairs, a sources
// list) through lesson_parts.dart.
//
// SPEC: Pax's research brief, candidate 5
// (myPKA/Deliverables/2026-09-27-classroom-candidates/RESEARCH-BRIEF.md §3),
// plus §5 anti-pattern 3: no scare framing. The Federal Trade Commission's
// consumer page, checked 27 September 2026, says "Because of the widespread
// use of encryption, connecting through a public Wi-Fi network is usually
// safe", and the lesson leads with that rather than against it.
//
// GUARD (Pax): never claim a shared password hides you from others who know
// it on WPA2-Personal. The lesson says the opposite, because it is true; WPA3
// (SAE) gives each device its own key.
//
// THE BYSTANDER is fixed: someone nearby on the same network, listening to the
// air. On a password network they were given the same password. The lesson
// says so above the control.
//
// States (SOP-007 §5): success is the only reachable state (compiled-in copy,
// a bounded control, pure model). Disabled: the WPA2 / WPA3 toggle until
// Password is picked, with the reason in words. Interactive: the controls,
// the Predict button and its "Show me" button, the help footer.

import 'package:flutter/material.dart';

import '../../../services/wifi_lab/public_wifi_model.dart';
import '../../../theme/app_tokens.dart';
import 'lesson_parts.dart';
import 'public_wifi_stage.dart';

/// Stable catalog tool id: backs the route, the help entry and the tests.
/// Permanent; never renamed.
const String kPublicWifiToolId = 'public-wifi';

class PublicWifiLessonScreen extends StatefulWidget {
  const PublicWifiLessonScreen({super.key});

  @override
  State<PublicWifiLessonScreen> createState() => _PublicWifiLessonScreenState();
}

class _PublicWifiLessonScreenState extends State<PublicWifiLessonScreen> {
  final PublicWifiController _controller = PublicWifiController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LessonScaffold(
      title: 'Public Wi-Fi',
      toolId: kPublicWifiToolId,
      children: <Widget>[
        const LessonHero(
          eyebrow: 'A plain-English lesson',
          promise:
              'What the person next to you on public Wi-Fi can see, and why '
              "your bank's website is not on the list.",
        ),

        // ── 1 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '1',
          title: 'The short answer',
          children: <Widget>[
            LessonP(
              '**HTTPS protects what you send on any network.** HTTPS '
              '(Hypertext Transfer Protocol Secure) seals a page and everything '
              'you type into it, from your device all the way to the website. '
              '**Wi-Fi encryption protects the air**, the stretch between your '
              'device and the access point (AP). An Open network adds no Wi-Fi '
              'encryption, so it still shows which sites you visit, and '
              'anything an app sends without encryption.',
            ),
            LessonCallout(
              title: 'What the Federal Trade Commission (FTC) says',
              body:
                  'Most websites now use encryption. "Because of the '
                  'widespread use of encryption, connecting through a public '
                  'Wi-Fi network is usually safe." Look for the lock or https '
                  'in the address bar. (FTC consumer advice, checked 27 '
                  'September 2026.)',
            ),
          ],
        ),

        // ── 2 ──────────────────────────────────────────────────────────────
        LessonSection(
          number: '2',
          title: 'Try it: pick the network',
          children: <Widget>[
            const LessonP(
              'The person next to you is on the same network, with a free '
              'capture tool that records the air. On a password network, they '
              'were given the same password you were, as everyone at a cafe '
              'is. Pick the network type and watch what they can see.',
            ),
            LessonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const LessonLabel('Try it'),
                  const SizedBox(height: AppSpacing.xs),
                  PublicWifiControls(controller: _controller),
                  const SizedBox(height: AppSpacing.sm),
                  PublicWifiStage(controller: _controller),
                ],
              ),
            ),
          ],
        ),

        // ── 3 ──────────────────────────────────────────────────────────────
        LessonSection(
          number: '3',
          title: 'Predict, then reveal',
          children: <Widget>[
            LessonPredict(
              question:
                  "You're at a cafe on its Open network, signing in to your "
                  "bank's website. What can the person at the next table "
                  'read?',
              answer:
                  "The bank's name, from the lookup your device makes, and "
                  'that your device is busy. **Not your password and not your '
                  "balance.** The bank's site uses HTTPS, which seals both "
                  'from your device to the bank on any network. That is why '
                  'the FTC says public Wi-Fi is usually safe.',
              after: TextButton.icon(
                onPressed: () => _controller.kind = PwKind.open,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Show me on Open'),
              ),
            ),
          ],
        ),

        // ── 4 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '4',
          title: 'The four networks',
          children: <Widget>[
            LessonSub('Open'),
            LessonP(
              'No password and no Wi-Fi encryption. Secure sites stay sealed '
              'by HTTPS. Anyone listening sees the site names, and can read '
              'anything an app sends without encryption.',
            ),
            LessonSub('Enhanced Open'),
            LessonP(
              'Still no password to type, but each device and the AP agree a '
              'key of their own as it joins. The standard is Opportunistic '
              'Wireless Encryption (OWE, RFC 8110), and Wi-Fi Alliance '
              'certifies it as Enhanced Open. Your network list shows it with '
              'no lock, the same as Open, so the lock icon undersells it.',
            ),
            LessonSub('WPA2-Personal'),
            LessonP(
              'A shared password, and a lock in the network list. WPA stands '
              "for Wi-Fi Protected Access. Every device's key is worked out "
              'from the password plus numbers exchanged in the clear when it '
              'joins. A stranger without the password reads nothing. Someone '
              'who has it, and records you joining, can work out your key.',
            ),
            LessonSub('WPA3-Personal'),
            LessonP(
              'A shared password and a lock, but the join is a password '
              'exchange called SAE (Simultaneous Authentication of Equals). '
              'Each device ends up with its own key, and a recording of the '
              'exchange does not give it away, even to someone who knows the '
              'password.',
            ),
          ],
        ),

        // ── 5 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '5',
          title: 'Three things people get wrong',
          children: <Widget>[
            LessonMyth(
              myth: 'Never use public Wi-Fi.',
              fact:
                  'The FTC says connecting through public Wi-Fi is usually '
                  'safe, because most sites and apps encrypt what they send. '
                  'The lock or https in the address bar is the one to look '
                  'for.',
            ),
            LessonMyth(
              myth:
                  'No lock next to the network name means anyone can read my '
                  'banking.',
              fact:
                  'The lock that protects your banking is HTTPS, in the '
                  'browser or the app, and it works on every network. '
                  'Enhanced Open encrypts the air and still shows no lock.',
            ),
            LessonMyth(
              myth: 'A password on the Wi-Fi means nobody else can see my '
                  'traffic.',
              fact:
                  'It keeps out people who do not have the password. On '
                  'WPA2-Personal, anyone who has it and records you joining '
                  'can read the air as if it were Open. WPA3-Personal closes '
                  'that gap.',
            ),
          ],
        ),

        // ── 6 ──────────────────────────────────────────────────────────────
        const LessonSection(
          number: '6',
          title: 'Where Wi-Fi encryption stops',
          children: <Widget>[
            LessonP(
              'Wi-Fi encryption ends at the AP. Past it, the network owner, '
              'and the internet provider behind it, see the site names and '
              'anything sent without encryption, on every one of the four '
              'types. HTTPS is the seal that goes the whole way.',
            ),
            LessonCallout(
              title: 'What this lesson leaves out',
              body:
                  'It covers someone who only listens. A fake network set up '
                  'with a familiar name, and sign-in pages, are separate '
                  'topics. Some devices and sites can '
                  'hide the site names too, with encrypted DNS and Encrypted '
                  'Client Hello, but the address of the server still shows.',
            ),
          ],
        ),

        // ── Sources ────────────────────────────────────────────────────────
        const LessonSection(
          number: '→',
          spokenNumber: 'Sources',
          title: 'Where these facts come from',
          children: <Widget>[
            LessonSources(<String>[
              'Federal Trade Commission, "Are Public Wi-Fi Networks Safe? What '
                  'You Need To Know", consumer.ftc.gov, checked 27 September '
                  '2026',
              'Wi-Fi Alliance, Wi-Fi CERTIFIED Enhanced Open; Dan Harkins, Wi-Fi '
                  'Alliance blog: Enhanced Open networks are shown without a '
                  'lock icon',
              'IETF RFC 8110, Opportunistic Wireless Encryption',
              'IEEE 802.11-2020: the four-way handshake (WPA2-Personal) and '
                  'SAE (WPA3-Personal)',
              'IETF RFC 6066, section 3: Server Name Indication',
              'CWNP CWNA-109 exam objectives 5.2.2, 5.3.3 and 5.3.4',
            ]),
          ],
        ),
      ],
    );
  }
}
