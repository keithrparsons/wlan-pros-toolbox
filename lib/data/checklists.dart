// Checklist content for the Checklists category.
//
// The two real checklists' data, rendered verbatim by the reusable
// ChecklistScreen type (lib/screens/tools/checklists/checklist_screen.dart).
// Both are Keith Parsons / WLAN Pros original cards (© 2024 WLAN Pros),
// transcribed by Pax (pax-research-7-additions.md) with obvious typos fixed.
//
// Keith's decisions applied (2026-05-30):
//   - "How to NOT Have a Wireless Problem" — the "After Installing" list is
//     renumbered a clean 1-11 (the original card was gap-numbered, with no
//     item 2, so the eleven items now read 1 through 11). ChecklistScreen
//     numbers items by render order, so the model
//     just lists them in order; no explicit `order` field is needed.
//   - "Install Access Point" is kept as its own one-item phase, as on the card.
//
// These are content consts only — the screen type, model, interaction, and
// accessibility all live in checklist_screen.dart. The route wires each const
// into a ChecklistScreen with the matching catalog `toolId` so a bundled
// concept graphic resolves by convention (and degrades gracefully when absent).

import '../screens/tools/checklists/checklist_screen.dart';

/// Catalog id `checklist-ap-install`. AP install pre/post-check phases.
const Checklist kApInstallChecklist = Checklist(
  title: 'How to NOT Have a Wireless Problem',
  intro:
      'Many wireless problems are not wireless problems. Work these checks '
      'before, during, and after the access point install. Use a LinkSprinter, '
      'LinkRunner AT, EtherScope, or CyberScope, or just a laptop with a '
      'command window and the right commands.',
  phases: <ChecklistPhase>[
    ChecklistPhase(
      label: 'Before Installing Access Point',
      items: <ChecklistItem>[
        ChecklistItem('Cable meets or exceeds Cat5e specs'),
        ChecklistItem('Total cable distance with patch cords < 100 m'),
        ChecklistItem('PoE meets the AP\'s specific requirements'),
        ChecklistItem('Check 802.3 af, at, or bt'),
        ChecklistItem('Confirm DHCP address & VLAN'),
        ChecklistItem('Confirm correct VLAN assignment'),
        ChecklistItem('Confirm access or trunk port as required'),
        ChecklistItem('Confirm default gateway'),
        ChecklistItem('Ping default gateway'),
        ChecklistItem('Confirm target IP addresses reachable'),
        ChecklistItem('Confirm DNS reachable'),
        ChecklistItem('Confirm target DNS addresses reachable'),
        ChecklistItem('Management VLAN assigned & available'),
      ],
    ),
    ChecklistPhase(
      label: 'Install Access Point',
      items: <ChecklistItem>[
        ChecklistItem('Install access point'),
      ],
    ),
    ChecklistPhase(
      label: 'After Installing Access Point',
      items: <ChecklistItem>[
        ChecklistItem('Document AP\'s MAC & assigned name'),
        ChecklistItem('Document AP\'s location'),
        ChecklistItem('Document AP\'s switch / port used'),
        ChecklistItem('Document AP\'s IP address'),
        ChecklistItem('Confirm AP installed in proper orientation'),
        ChecklistItem('Confirm external antennas installed correctly'),
        ChecklistItem('Wait for access point to receive configuration'),
        ChecklistItem('Wait for a 2nd reboot of the AP if needed'),
        ChecklistItem('Listen in air for all SSIDs being broadcast'),
        ChecklistItem('Connect client to each SSID'),
        ChecklistItem('Check each SSID for proper VLAN & IP pool'),
      ],
    ),
  ],
);

/// Catalog id `checklist-client-test`. 12 client-side connectivity tests, one
/// ordered list (no phases) — modeled as a single null-labeled phase so the
/// heading is dropped.
const Checklist kClientTestChecklist = Checklist(
  title: 'Wi-Fi Client Testing Checklist',
  intro:
      'Use a client device to test the following, in order, after an install '
      'or when triaging a connectivity complaint.',
  phases: <ChecklistPhase>[
    ChecklistPhase(
      items: <ChecklistItem>[
        ChecklistItem('Can see all SSIDs being broadcast'),
        ChecklistItem('Associate to target SSID'),
        ChecklistItem('Complete SSID authentication'),
        ChecklistItem('Receive an IP address via DHCP'),
        ChecklistItem('Receive default gateway & DNS'),
        ChecklistItem('Ping default gateway'),
        ChecklistItem('Ping DNS'),
        ChecklistItem('Ping remote IP address'),
        ChecklistItem('Ping remote DNS address'),
        ChecklistItem('Check client MCS'),
        ChecklistItem('Check client Tx data rate'),
        ChecklistItem('Complete network speed test'),
      ],
    ),
  ],
);
