# Handoff to Larry (Claude Code on Keith's Mac): learn what's normal per place, and a visible triage ladder

## Paste-in prompt for Keith to give Larry

Keith wants a build spec for two Check My Connection features, learned from Simon Thorpe's octomon (inspiration only; copy no code or assets). Read branch `grokbot/larry-spec-normal-and-triage`, file `docs/handoffs/2026-11-12-larry-spec-normal-per-place-and-triage-ladder.md`, and compare it with any work you may already have started from the ideas list. First: learn what's usual at each place, on this device only. Second: a visible triage ladder on Check My Connection and Analyze. Later phases are in the note. Do not change global grading bands, and leave help text to Toolbox. Coordinate with the iPhone Duo work. Do not merge to main; Keith's open questions in the note still need a yes before shipping.

---

1. **Goal:** "I was thinking more of Grok Bot's Toolbox Bot writing up instructions to Larry, not to sets of coding" (Keith to Lead, 12 Nov 2026, 11:02 AM MT). Keith had already sent Larry the ideas list, and Larry may have started. This yes is for a build spec Larry can follow. It is not a yes to write app code in this repo from Toolbox, and it is not a yes to merge, ship, or change help text yet.

2. **Sources and files:**

   - Ideas report: `/workspace/research/2026-11-12-app-video/TOOLBOX-IDEAS.md` (12 Nov 2026), with the clean transcript in `TRANSCRIPT.md` in the same folder. The ideas were learned from Simon Thorpe's open-source octomon ([video](https://www.youtube.com/watch?v=ECwBaSvUwfk), 25 Oct 2026). Credit it as inspiration only. Copy no code or assets. Say nothing negative about his work, or about any peer's tool.
   - This note is on branch `grokbot/larry-spec-normal-and-triage`, cut from `origin/main` at `cdcf29a4` (1.14.0 release notes, 11 Nov 2026). App version on that commit: `pubspec.yaml` `version: 1.14.0+26111101`.
   - Current code, verified on that commit, is cited in the sections below. Facts I did not re-check against a live device are marked UNVERIFIED.

3. **Decisions already made:**

   - Keith wants instructions for Larry, not a Toolbox coding pass (12 Nov 2026, 11:02 AM MT).
   - Toolbox is the sole owner of help text (Keith, 2 Nov 2026). Larry should not write `assets/help/tool_help.json` or the in-app guides. When the feature lands on a branch, Toolbox drafts the help and guide text on its own `grokbot/...` branch.
   - The privacy promise already in the app and on the site stands: local-only, no account, no tracking, nothing uploaded. Quoted in the Privacy section below.
   - Consumer verdicts stay hedged ("Looks like...", never "your Wi-Fi is broken"). Keith locked that wording. This work adds lines; it does not rewrite those headlines.
   - Global grade bands stay where they are. Do not change `WifiGradingBands.kRssiBands` or `ThroughputBands` as part of this work. The new "usual for this place" line sits beside those grades, it does not replace them.
   - Larry's team is also updating the app for iPhone Duo (Keith, 7 Nov 2026). Coordinate; do not restyle Duo layout files. See the coordination section.

4. **Open questions:** Keith decides, unless noted.

   - Confirm the recommended place key and the first-time "Remember what's usual on [network]?" prompt (recommended in Recommendation 1).
   - How many completed checks at a place before the app says "usual" (recommended starting point: 3).
   - The numeric "slower than usual" thresholds (starting points are proposed below; they are not yet approved).
   - Whether a place history file may be included in the OS device backup (iCloud / equivalent), or should be excluded so it truly never leaves the device. Recommended: exclude.
   - Whether Recommendation 2's first slice uses only data already in a Check My Connection run (recommended), or also adds a short gateway-reachability probe and, later, ISP-path and clock checks.
   - Ship version (1.15 or later). Unknown; Keith decides.
   - What Larry may already have started from the ideas list is unknown. Larry should compare this note with that work and keep whatever already matches, rather than starting over.

5. **Expected result and where it goes:** This note, on this branch, is the deliverable. Larry uses it as a build spec. Keith looks first. Reviewer cold-reads the note. No app code is in this commit. No merge, no pull request, no deploy, no help-text edit, and no site change until Keith says yes. When Larry's feature is on a `grokbot/...` branch (never `main`), Toolbox drafts the help and guide text, then the usual Reviewer path.

6. **Rules that apply:** Ask first. Never write to or push to `main`. No pull request unless Keith asks. Never deploy (Larry does, and only with Keith's yes). Never put a secret in chat or a file. Never send, post, or publish without Keith's yes. Never delete user-visible place history without a user action, and never delete repo files without Keith's yes. Public-facing text must not name litigious speed-test vendors, must not mention internal team members, bots, or process, and must say nothing negative about other people's tools. US spelling, no em dashes. RSSI grades on screen must keep following `WifiGradingBands.kRssiBands`. The minimum rate is 6 Mbps; never mention 802.11b in new copy. The device term is "router/access point", never a bare "AP" in user-facing words. Help text is Toolbox's to draft. Privacy: local-only, no tracking, no analytics, nothing leaves the device.

7. **Deadline:** none.

---

## Privacy (non-negotiable)

The feature stays inside the existing promise. Quote these as the bar, and update them only to say more clearly that a local place history exists and can be deleted (see the fix-it-everywhere list).

- About screen (`lib/screens/about_screen.dart`, Privacy section): "We don't collect your data." and "This app measures your network on your device. It isn't built to track you, profile you, or ship your information off somewhere. Data not collected, exactly as stated on the App Store listing."
- README (`README.md`, "Local-first and private"): "The Toolbox collects no personal data. There is no account, no login, and no analytics or telemetry in the build." and "Live network tools reach the network only to do their job (a ping reaches its target, a speed test reaches the throughput endpoint). The connection analyzer ("Analyze") runs on-device; nothing is uploaded." and "Location is used only to read the connected Wi-Fi SSID (a platform requirement on recent macOS and on Android) and for the optional GPS tools. It is never stored or shared."
- User guide (`assets/guides/user-guide.md`): "It does not collect your personal data. It reads your own connection to answer your own questions, and that stays on your device."
- Site (`toolbox.wlanpros.com`, checked from the local site tree): "No ads. No tracking. No account. No data collected." and "WLAN Pros runs no server that receives your data." Full policy: [wlanprofessionals.com/toolbox-privacy](https://wlanprofessionals.com/toolbox-privacy).
- Store listing (`ios/fastlane/metadata/en-US/description.txt`): "Free. No account. No ads. No data collected."
- Favorites already follow the same rule (`lib/favorites/my_tools_controller.dart`): "it lives on THIS DEVICE ONLY, in shared_preferences... No account, nothing synced, nothing sent."
- Analyze already states (`lib/screens/tools/network/analyze_results_screen.dart`): "LOCALLY, no network call, nothing stored, nothing leaves the device."

Consequences for this work:

- No GPS and no public-IP geolocation in the place key. Location permission stays what it is today: a way to read the network name, never a place stamp.
- Nothing is uploaded. No account, no analytics event, no "sync my places."
- A network name stored as a place label is new persistence. The README line "It is never stored or shared" talks about Location, but readers could take it more broadly. When this ships, that sentence and the About / site / policy wording must say: the network name may be kept on this device as a place you chose to remember, you can forget it, and it is never uploaded. Toolbox will draft that wording.
- The check still reaches the network only to measure it, the same as today.

---

## Recommendation 1: Learn what's usual at this place (on this device)

**Fairly sure.** High value, medium-high effort. This is the first slice to build.

octomon remembers each place a device has used and colors the live numbers against a learned baseline for that place, so a plane connection can still read healthy when it is normal for a plane (video [4:49](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=289s)-[5:59](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=359s), also [16:03](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=963s)). Check My Connection today grades against fixed bands only (download Strong at 100 Mbps and up, from `ThroughputBands` in `packages/net_quality/lib/src/scoring.dart`). A local baseline, never uploaded, would make hotel, cafe, and travel Wi-Fi less confusing, and would give a pro an "is this worse than this office usually is?" test.

The Toolbox should learn from the checks the user already runs, not from a continuous background sample. That is a deliberate product choice: it stays inside the privacy promise and does not leave a monitor running.

### User-facing behavior and proposed wording

These strings are proposed starting copy, in Keith's voice (plain, hedged, US spelling, no em dashes). They are not yet Keith-approved. Toolbox will finalize them with the help text when the feature lands.

After a Check My Connection run, under the existing two chips and the existing headline ("Looks like your Wi-Fi", "Both look fine", and the other `ConsumerVerdictMapper` headlines in `lib/services/network/consumer_verdict.dart`), add one short place line. The global grade (Excellent / Good / Fair / Poor, or Strong / Moderate / Weak on the chips) does not change.

- First time this network name is seen, a one-time prompt (not a dark pattern; dismissing is easy):

  > Remember what's usual on "FrontOffice"? The app will learn a baseline for this network and keep it on this device only. You can forget it any time.

  Buttons: **Remember** and **Not now**. A quieter follow-up: **Don't ask again for this network**.

- After they tap Remember, but before three completed checks at that place:

  > Still learning what's usual at FrontOffice. Run Check My Connection a few more times here.

- Once a baseline is trusted (recommended: 3 completed checks; median of the last 20):

  > About usual for FrontOffice.

  > Slower than usual for FrontOffice. Download here is usually about 180 Mbps.

  > Faster than usual for FrontOffice.

- A plane or cafe can be Poor (or Weak) on the global scale and still "About usual for United Wi-Fi". Show both, for example:

  > Internet: Weak. About usual for United Wi-Fi.

- If they chose Not now, no baseline is stored, and the extra line is omitted.

- A "Places this device remembers" list, reached from a text button on the result screen ("Places on this device") and from About, near Privacy. Each row: the name, how many checks, last checked. Actions: **Rename**, **Forget this place**. At the bottom: **Forget all places**. Forgetting is immediate, on-device, and asks one confirm: "Forget FrontOffice? This cannot be undone."

- Rename prompt: **Name this place**, with the SSID as the starting text, so "MyNet_5G" can become "Home" or "Office 3rd floor."

- Copied report ("Copy these details") gains a short Places section with the same words that were on screen, so support sees "About usual for FrontOffice" too.

Do not auto-start learning on a declined cellular speed test in a way that pretends a skipped download is a sample. A run that skipped throughput can still contribute DNS and latency samples if those were measured; it must not write a zero download as "usual." Same rule as today's "Not measured" chips.

### Where it fits in the current 1.14 code

New work should be a new, pure, injectable service (suggested name `PlaceBaselineStore` plus a small comparison helper), not a rewrite of the verdict engine. Hook it into the existing result path.

Verified files and modules:

- Front door: home "Check My Connection" button opens Test My Connection (`lib/screens/tools/network/test_my_connection_screen.dart`, 7,118 lines on this commit). Auto-start, cellular-data consent, Copy, and Analyze already live here. This is the main UI hook. The file is large; add a small widget rather than weaving logic through the screen.
- Verdict copy: `lib/services/network/consumer_verdict.dart` (`ConsumerVerdictMapper`). Do not change existing headlines or `AxisStatusThresholds` (Strong = 100 Mbps and up, Moderate = 25 to under 100, Weak = under 25; same `ThroughputBands` as Network Quality).
- Comparison sentence already on screen: `lib/services/network/connection_comparison.dart` (Wi-Fi vs internet, not vs a place). Leave it; the place line is a separate sentence.
- Measurement glue: `lib/services/network/connection_check.dart` and `lib/services/network/wifi_vs_internet.dart`. Reuse their results; add no new throughput math.
- Internet grades: `packages/net_quality/lib/src/scoring.dart` (`QualityScoring`, `ThroughputBands`: download Excellent >= 100, Good >= 25, Fair >= 5; upload Excellent >= 20, Good >= 5, Fair >= 1; latency Excellent < 20 ms, Good < 50, Fair < 100; jitter Excellent < 5, Good < 15, Fair < 30; loss Excellent == 0, Good < 1, Fair < 2.5; responsiveness Excellent >= 1000 RPM, Good >= 500, Fair >= 100). Do not edit these bands.
- RSSI grades: `lib/services/network/wifi_grading.dart`, `WifiGradingBands.kRssiBands`. On this commit they are Excellent `> -60 dBm`, Good `-60 to -67`, Fair `-68 to -72`, Poor `-73 or weaker`, confirmed Keith 12 Jul 2026, with "-67 is Good only" (Keith, 27 Oct 2026). `WifiGrading.gradeRssi` and the Signal Thresholds screen both read this list. Do not change it here.
- Link read (SSID, BSSID, RSSI, rates): the same path Wi-Fi Information uses. `lib/services/network/wifi_info_adapter.dart` (`WifiInfoSourceResolver`), `lib/services/network/connected_ap.dart`, `lib/services/network/wifi_details.dart`, iOS Shortcut stack (`WiFiDetailsBridge` / `WifiMonitorController`), iOS native BSSID + security via `WifiSecurityService` (`NEHotspotNetwork`, entitlement `com.apple.developer.networking.wifi-info` plus Location When In Use, already in `ios/Runner/Runner.entitlements`).
- Default gateway and local addressing: `lib/services/network/network_details_service.dart` (already called from Test My Connection). Local IP, subnet, and gateway via `network_info_plus`. DHCP and configured DNS servers only on Android. VLAN never visible.
- "Are we on Wi-Fi?": `lib/services/network/wifi_connection_service.dart` and, on iOS, `lib/services/network/wifi_path_probe.dart` (permission-free `NWPathMonitor`). This is how a phone hotspot vs Wi-Fi vs cellular vs wired should be told apart. A new SSID (including a phone's hotspot name) is a new place candidate.
- Persistence pattern today: `shared_preferences` for small prefs (theme, My Tools, units, live-onboarding, transport preference). A place history with many samples will outgrow that. Use a JSON file in the app documents directory via `path_provider` (already a dependency), behind an injectable store so tests use memory. Do not use iCloud, Drive, or any network store.
- Analyze: `lib/services/network/analyze/analyze_input.dart`, `analyze_engine.dart`, `analyze_rules.dart`, `lib/screens/tools/network/analyze_results_screen.dart`. If Analyze should also show "About usual for FrontOffice", pass the already-computed comparison in; do not make the rule engine the store.

WLAN Pi: when the page is served from a Pi, Test My Connection already runs `/toolboxapi/conntest` on the Pi (`_PiConnectionBody` in the same screen file; `lib/services/network/pi_backend_client.dart`). A place learned there is a place on that Pi, labeled as the Pi's network, not the visitor's phone.

Web (Netlify, no Pi): the browser cannot read the visitor's Wi-Fi. Do not pretend to learn a Wi-Fi place. An optional user-named "this cafe" internet-only baseline is possible later; it is not in the first slice.

### Data model

A **place** is a user-accepted, locally stored baseline for a network this device has checked.

**Recommended key (fairly sure):** do not silently key on BSSID, and do not silently key on SSID plus gateway alone.

- BSSID as the key would split a home mesh into many places, one per radio.
- SSID plus gateway looks unique, but many cafes and homes share names like "Guest" and gateways like `192.168.1.1`, so two real places would merge. Public-IP geo would distinguish them, and must not be used (tracking).
- Recommended behavior: the first time a new network name is seen, ask. If the user taps Remember, subsequent checks on the same SSID (case-insensitive trim) update that one place, including every BSSID of that SSID (a mesh stays one place). The user can say "This is a different place" and give it another name; those are two records that happen to share an SSID.
- Internal identifier: a random local ID, plus `ssid` (nullable), `userName`, `kind` (`wifi` / `cellular` / `wired` / `unknown`). Store recent BSSIDs and the last gateway as attributes, not as the identity.
- Cellular: one "Cellular" place, optionally labeled with the carrier when the OS provides it, after the same Remember prompt. Do not subdivide by tower.
- Wired: "Wired", after the same prompt, optionally distinguished by gateway if the user splits it.
- If the SSID cannot be read (iOS without Location / without a name, or a hidden network): do not auto-merge. Offer "Name this place" or skip learning. Never invent a name.

**What is stored, all local:**

- Place ID, user-facing name, kind, SSID if known, last BSSIDs, last gateway (optional attribute).
- Samples: timestamp, download Mbps, upload Mbps, latency ms, jitter ms, loss percent, responsiveness RPM, RSSI dBm, DNS resolution ms. Each field nullable. A "Not measured" field is omitted, never stored as zero.
- Recommended retention: last 20 completed samples per place. No automatic expiry. The user deletes.
- Schema version in the file, so a later format can migrate.

**Delete and reset:** Forget this place; Forget all places; both only on an explicit tap. Uninstalling the app removes the file with the app sandbox, which is expected.

**Backup (open question):** on iOS the documents directory can go into an iCloud device backup. That is the user's backup, not our server, but it does leave the device. Recommended: mark the file excluded from backup so "on this device only" stays strict. Keith decides.

### Platform limits (say what each platform can and cannot read, the same way the app already does)

| Platform | Network name (SSID) | BSSID | RSSI and rates | Gateway address | What Recommendation 1 can do |
| --- | --- | --- | --- | --- | --- |
| macOS | CoreWLAN; Location permission required on macOS 14+ to show the name (`MacWifiInfoAdapter`). Verdict itself is rate-based and does not need Location. | Same Location gate | Tx, RSSI, SNR yes; public CoreWLAN does not expose Rx | `network_info_plus`; App Store sandbox may limit some shell fallbacks | Full, once Location has been granted so the name is known; if the name is hidden, prompt to name the place or grant Location |
| iOS | Companion Shortcut for the RF set (SSID, RSSI, noise, channel, Tx, Rx). Security type and BSSID also come from `NEHotspotNetwork` without the Shortcut, given the Access Wi-Fi Information entitlement and Location When In Use. Channel width is never available (`Analyze` rule R-30). | Native, entitlement + Location | RSSI and rates: Shortcut. Without it, do not invent RSSI. | `network_info_plus`; subnet is often null (already shown as Unavailable) | Learn by SSID when the name is known (Shortcut or a later name entry). Without a name, "Name this place." Without the Shortcut, internet-only samples are still valid; RSSI samples are not. On-Wi-Fi vs cellular vs wired uses `WifiPathProbe` (no Location needed). |
| Android | WifiManager; `ACCESS_FINE_LOCATION` gates SSID and BSSID on Android 8.0+ | Same Location gate | RSSI and Tx yes; noise / SNR not exposed; Rx on API 30+ when the device returns it | Yes, plus DHCP and DNS servers | Full, once Location is granted so the name is known |
| Windows | Native Wifi (`wlanapi.dll`); no Location grant needed for SSID and BSSID | Yes | RSSI and rates as Wi-Fi Information already shows; no noise / SNR | Address yes; DHCP and DNS servers "Not available on this device" (same as iOS/macOS in today's help) | Full |
| Web (no Pi) | Cannot read Wi-Fi | No | No | No | No Wi-Fi place in the first slice. Leave it empty and say why. |
| WLAN Pi | Pi's own radio via `/toolboxapi/wifi` | Pi's BSSID | Pi's RSSI | Pi conntest already probes the Pi's gateway | Learn the Pi's places, labeled as measured on the Pi |
| Desktop Linux | Wi-Fi Information is a "coming later" seam | Unverified / unavailable today | Unverified | Unverified | Unavailable until that seam is filled, and say so |

For the iOS user: keep the existing Shortcut offer. Never say a missing RSSI is a failed test. Never use Location for anything except reading the network name (and the optional GPS tools already in the app).

### Tests to add

Pure unit tests, no live network:

- Place key and consent: same SSID (different BSSID, a mesh) updates one place after Remember; "This is a different place" creates a second; hidden or missing SSID does not auto-merge; cellular is not filed under the last Wi-Fi place; a hotspot SSID is a new candidate; Not now stores nothing.
- Samples: skipped throughput is not stored as 0 Mbps; null fields stay null; only the last 20 samples are kept; median math is stable.
- Wording: the "Still learning" / "About usual" / "Slower than usual" / "Faster than usual" strings are a pure function of sample count and the comparison, exhaustively tested, same style as `consumer_verdict_test.dart` and `connection_comparison` tests.
- Forget and rename.
- File-store fake (injected memory) plus a schema-version migration test.

Widget tests:

- The prompt appears once for a new SSID and does not block the verdict already on screen.
- The place line renders next to the existing chips without replacing them.
- Places list: rename, forget, forget all (with confirm).
- iOS-without-name and web paths show the empty / "Name this place" states, and say why.

Do not add untagged goldens. If a golden is truly needed, tag it `golden` so Linux CI (`flutter test --exclude-tags "capture || golden"`) stays as it is. The baseline already has known Linux pixel failures on other screens; do not add to that list.

Existing tests that must stay green: `test/services/consumer_verdict_test.dart`, `test/services/network/wifi_grading_test.dart`, `test/services/network/signal_grading_cross_check_test.dart`, `test/services/analyze/analyze_engine_test.dart`, and the Test My Connection widget suite under `test/screens/tools/network/`.

### Fix-it-everywhere (Toolbox drafts the words)

When the feature lands, Toolbox (not Larry) drafts copy on its own branch and searches for every old claim. The list to update:

- `assets/help/tool_help.json`: `test-my-connection` (purpose, howToUse, fieldNotes, including platform differences) and `analyze-results`.
- `assets/guides/user-guide.md`: "Start here: Check My Connection" and the privacy bullets.
- `assets/guides/field-manual.md`: Test My Connection and Analyze Results sections. (The Field Manual on this commit still describes an older headline set in places; new sentences must match the shipping screen.)
- `lib/screens/about_screen.dart` Privacy section, and the copied About text.
- `README.md` "Local-first and private," especially the Location / "never stored" sentence.
- The Copy payload builder in `test_my_connection_screen.dart`, and the Connection Report guide PDF on toolbox.wlanpros.com (`WLAN-Pros-Toolbox-Connection-Report-Guide.pdf`).
- toolbox.wlanpros.com lead text and [the privacy policy](https://wlanprofessionals.com/toolbox-privacy) if it needs a "place history stays on the device" sentence. Site changes go on a site branch, then Reviewer, then Keith's yes.
- Library tool-guide pages for Test My Connection and Analyze, when those guides are rebuilt (Library's process; Toolbox hands them the approved help).
- Store listing text only if the "what's new" blurb mentions the feature; "No data collected" remains true if nothing leaves the device.

### Acceptance criteria

- After Remember, three completed checks at the same SSID (mesh BSSIDs included) produce an "About usual" or "Slower / Faster than usual" line. Before that, "Still learning."
- A Poor or Weak global grade can appear next to "About usual for [place]" without contradiction.
- Not now stores nothing. Forget removes the data on the device. Forget all clears every place.
- No place data is uploaded; no GPS is stored; no analytics event is fired. A test or code comment should make that inspectable.
- Missing SSID, missing RSSI, skipped speed test, web, and iOS-without-Shortcut show the real reason, and never fabricate a number.
- Existing Check My Connection headlines, chips, and Analyze rules are unchanged in wording and thresholds.
- New unit and widget tests as above are green. Analyze (`scripts/analyze.sh`) is no worse than the current baseline on this branch.
- Help text is not written by Larry; a note in the PR-less branch points Toolbox at the shipping strings.

---

## Recommendation 2: A visible triage ladder on Check My Connection and Analyze

**Fairly sure.** High value, medium effort. Build this in the same release slice if it stays a presentation of data the run already has. Extra probes are a later slice.

When you press Y, octomon walks outward: machine, link, gateway, DNS, ISP path (the hops just past the default gateway), internet, web, and destinations, and marks where the trouble appears to sit ([16:11](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=971s)-[18:26](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=1106s)). Check My Connection already answers "Wi-Fi or internet?" with two chips and a headline. Analyze already explains the verdict and next steps on the device (`kAnalyzeRules` in `lib/services/network/analyze/analyze_rules.dart`, 35 ratified rules, R-01 through R-42, fired only on fields that were measured). What is missing is a short, visible ladder that shows the work behind the headline, including "only this destination is unhappy."

### User-facing behavior and proposed wording

Place a short vertical ladder on the Test My Connection result, between the existing headline (and the new place line, if any) and the self-help / "Analyze" actions. Show the same ladder at the top of Analyze Results, above the finding cards. Do not replace the chips or the headlines. Do not reuse the running `PacketFlowProgress` animation (`You` → `AP` → `Internet` in `test_my_connection_screen.dart`); that is a loading graphic over `_phase`, not a measurement of gateway health.

Each rung has a plain name, a status word (never color alone), and a short reason when it looks off.

Proposed rung names (first slice):

1. **This device**
2. **Wi-Fi link**
3. **Your router**
4. **Name lookup (DNS)**
5. **The internet**
6. **Specific services**

Proposed status words: **Looks fine**, **Looks off**, **Not checked**, **Can't check on this device**. Hedge with "Looks," consistent with "Looks like your Wi-Fi."

Proposed summary line under the ladder, only when something looks off (otherwise omit, and let "Both look fine" carry the good news):

> It looks like the trouble sits at your Wi-Fi link.

> It looks like the trouble sits at name lookup (DNS).

> It looks like only some services are unhappy, not the whole internet.

> It looks like this network wants a sign-in.

If several rungs look off, name the first one outward from the device that failed, and let Analyze explain the rest. That matches today's "start with the easy win" advice (R-03).

Recommended first-slice mapping, using data already in a Test My Connection run (no new long probe):

| Rung | Already measured in today's run | "Looks off" when | "Can't check" / "Not checked" when |
| --- | --- | --- | --- |
| This device | `notOnWifi`, path facts (`WifiConnectionService`), captive-portal and "no internet" verdicts | Wi-Fi is off or the path is gone, when that is the story; do not call cellular "off" a fault (R-05N already says "You are not connected to Wi-Fi, so there was no Wi-Fi link to check") | CPU / memory are not measured today. Do not add a machine-load rung in this slice. |
| Wi-Fi link | RSSI, SNR, Tx/Rx rates, usable Wi-Fi capacity; Analyze R-01, R-10, R-11, R-15 to R-24 | Existing Wi-Fi-limiter verdict, or RSSI Poor, or a low rate with a strong signal (R-18) | iOS without the Shortcut (R-31); wired; platform does not expose the field |
| Your router | Gateway *address* is already read (`NetworkDetails.gateway`) and shown on the Network card and in Copy. On a WLAN Pi, `/toolboxapi/conntest` already measures gateway reachability and latency. On native, the address is not pinged as part of this run | Pi: conntest says the gateway is unreachable. Native, first slice: do not guess. See the open question on a short gateway probe | Native first slice: **Not checked** (address may still be shown as context). If the platform cannot probe, **Can't check on this device** |
| Name lookup (DNS) | `DnsProbeService` already times a lookup of cloudflare.com, then google.com, then apple.com, through the device's own resolver. Analyze R-32 fires at `kDnsSlowMs` (200 ms) | DNS failed, or resolution time is at or above 200 ms (same constant; do not invent a second threshold) | Lookup marked "Not available" |
| The internet | net_quality download, upload, latency, jitter, loss, responsiveness; public IP / ISP via `IpGeoService` (keyless, fail-open); Analyze R-02, R-25 to R-29; "No internet" and "You are online" outcomes | Existing upstream / internet-down / poor latency, jitter, loss, or responsiveness | Speed test skipped (cellular decline): **Not checked** for speed, but reachability can still "Look fine" if DNS, public IP, and cloud apps answered |
| Specific services | `CloudAppsPanel` and `kCloudApps` in `packages/net_quality/lib/src/popular_sites.dart` (Facebook, Instagram, TikTok, YouTube, Netflix, Google, iCloud, Microsoft 365, Cloudflare, Amazon AWS, Zoom, Slack, GitHub, Cloudflare DNS). Analyze R-40 (none reachable), R-41 (mixed). R-42 (slow but reachable) is in the file but held false (`_alwaysFalse`) until per-service latency is threaded through | R-41 mixed, or R-40 none reachable (then this rung and "The internet" should agree, and the sign-in outcome takes priority when it applies) | Panel error: **Not checked** |

Caption under the ladder, proposed:

> This uses the same check you just ran. A green "Looks fine" is not a certificate; it is what this device could see.

Two rungs from the octomon ladder are **deferred** (later slice, still in this product area):

- **Your internet provider's path.** The app has Traceroute (System) on desktop (`lib/services/network/traceroute_service.dart`: macOS, Windows, Linux; App Store sandbox may block the binary, probed at runtime with `isLaunchable`). Traceroute (Mobile) is an ICMP TTL-walk on Android only, marked device-pending; "not available on iOS," never faked (`lib/screens/tools/network/mobile_traceroute_screen.dart`, `lib/services/network/icmp_service.dart`). These are not part of today's Test My Connection run. Do not auto-run a full traceroute on every check (time, and iOS cannot name hops). First slice: omit the rung rather than show a permanent "Can't check" on every iPhone. Later: a short, optional "first hops" probe on platforms that can, and on iOS the rung stays unavailable, never faked.
- **Clock.** Time Server (NTP) already exists (`lib/services/network/ntp_service.dart`), works on iOS, macOS, Android, and Windows (not web), and is not in Check My Connection or Analyze today. Folding one on-device NTP check into Analyze is a small later add. Proposed later wording: "This device's clock is off by more than a few seconds, which can break secure websites." Threshold is not agreed (unknown).

**This device** as a CPU / RAM bottleneck is also deferred (Recommendation 5's neighborhood). Device Info is not a live performance view.

### Where it fits in the current 1.14 code

New pure module (suggested: `TriageLadder` in `lib/services/network/analyze/` or a sibling), a total function of an input built from the existing run: `AnalyzeInput` plus `NetworkDetails`, cloud-app results, `ConsumerVerdict`, `notOnWifi`, captive-portal, and (on a Pi) `PiConntestResult`. Unit-test every rung the way `AnalyzeEngine` and `ConsumerVerdictMapper` are tested.

- Input already on `AnalyzeInput`: verdict, RSSI, SNR, link rate, band, standard, channel, width, security, download, upload, latency, jitter, loss, responsiveness, DNS ms, cloud reachable/total counts, `internetMeasured`, `wifiSignalCaptured`, `platformIsIos`, `notOnWifi`, `speedTestSkipped`.
- Extend that input (or a wrapper) for gateway reachability when it exists (Pi today; native only if Keith says yes to a probe).
- UI: a small widget used by `test_my_connection_screen.dart` and `analyze_results_screen.dart`. Keep Analyze's "If the platform didn't measure a field, no rule fires on it" (`assets/help/tool_help.json`, `analyze-results` fieldNotes). The ladder must follow the same rule.
- Do not rewrite `kAnalyzeRules` prose to mention the ladder. The ladder is a view of the same facts. New advice sentences still belong in the rule file, in Keith-ratified voice, if a new rule is truly needed. Prefer zero new rules in the first slice.
- Copy: extend `analyze_report_text.dart` and the Test My Connection Copy builder so the ladder words appear in the pasted report.
- Constants: reuse `kDnsSlowMs = 200` and `kCloudSlowMs = 250` in `analyze_rules.dart`. Do not fork them.

Optional short gateway probe (open question): `IcmpService` can echo on iOS (SimplePing; the file itself says this path is UNVERIFIED without a real device) and on Android (system ping). On sandboxed macOS, ICMP spawn is blocked; the desktop Ping tool uses a TCP handshake, which a typical router admin page may or may not answer. If this probe is added, it must be bounded (a few echoes, a short timeout), must not delay the main verdict, and must fail to "Can't check on this device" or "Not checked," never to a fabricated down. Fairly sure it should wait for a later slice so the first ladder can ship on data that is already there.

### Tests to add

- Pure rung tests: every combination of verdict, missing fields, skipped speed test, not-on-Wi-Fi (R-05N must not mark the Wi-Fi link as a failed read), captive portal, mixed cloud apps, DNS slow, Pi gateway down, native gateway "Not checked."
- Wording tests for the summary line and status words.
- Widget tests: ladder on Test My Connection and on Analyze; color is never the only signal (word + glyph, same as today's chips, WCAG 2.2 SC 1.4.1); 320 px width still fits (the screen already claims overflow-safety at 320).
- Existing Analyze and TMC tests stay green. No untagged goldens.

### Fix-it-everywhere (Toolbox drafts the words)

Same list as Recommendation 1, plus:

- `assets/help/tool_help.json` `test-my-connection` howToUse (a step to read the ladder) and `analyze-results`.
- Field Manual and user guide: describe the ladder as "where it looks like the trouble sits," and say a rung is omitted or marked "Can't check" when this device cannot measure it, especially iOS path hops.
- Connection Report guide: a ladder section in the copied report.
- Do not mention octomon, bots, or process in any of that public copy. A short "inspired by work in the open-source community" is optional and only if Keith wants a credit; default is to say nothing and just ship the behavior.

### Acceptance criteria

- After a finished check, both Check My Connection and Analyze show the same six-rung ladder (or fewer if a rung is omitted on purpose), with a status word on every visible rung.
- The two chips and existing headlines are still there and still match `ConsumerVerdictMapper`.
- A mixed cloud-app result marks "Specific services" as Looks off and does not claim the whole internet is down (R-41).
- A cellular-only phone does not get "Wi-Fi link: Looks off" (R-05N).
- iOS without Shortcut: Wi-Fi link is "Can't check on this device" or "Not checked," with the existing capture offer, not a fake Poor.
- iOS does not show a fake ISP-path result.
- Copied report includes the ladder words.
- Help text left for Toolbox.
- Tests as above are green.

---

## Later phases (3 to 5), brief

These are not in the first build. They are here so Larry does not have to rediscover them, and so the first slice does not paint them into a corner. Each stays local-only until the user chooses to share.

**3. Watch the connection for a few minutes, then send a support bundle.** octomon records a CSV (L) and dumps a dated zip (Shift+D) after a 10 to 15 minute watch ([18:32](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=1112s)-[19:29](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=1169s)). The Toolbox already has Copy on Check My Connection and Analyze (paste-ready text, the right shape for email and chat). The idea to learn: a "record for a few minutes, then share" bundle that includes the trend and the ladder, still on the device until the user shares it. Natural follow-on once Recommendations 1 and 2 exist, because a bundle should include the place baseline and the ladder. Privacy: nothing is sent until the user shares; redaction of BSSID / public IP should be a Keith decision. Effort: medium.

**4. Add a real destination and watch every hop to it.** octomon adds a target, traces, and watches every responsive hop ([4:12](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=252s)-[4:40](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=280s), Zoom-style walkthrough [14:23](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=863s)-[15:19](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=919s)). The Toolbox already has Traceroute (System) on desktop, Traceroute (Mobile) where the OS allows it (not iOS), and Ping Plotter (one host over time). The idea to learn is joining those: a custom target with hop-by-hop quality over time. Highest value for pros. iOS stays unavailable for intermediate hops, never faked. Effort: medium-high. This is also how the deferred "ISP path" ladder rung would get real data.

**5. On the desktop app, show which programs and remote addresses are using the path.** octomon graphs live upload and download and attributes traffic by process or remote address ([8:23](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=503s)-[11:04](https://www.youtube.com/watch?v=ECwBaSvUwfk&t=664s)). The Toolbox has no talkers view today. Worth doing on macOS, Windows, and Linux. Leave it out, or mark it unavailable, on iOS: the OS will not give a third-party app this data. Bigger and more platform-specific than 1 to 4. Effort: high. Coordinate with desktop sandbox limits already documented for ICMP and traceroute.

---

## iPhone Duo coordination

Larry's team is updating the app for iPhone Duo (Keith, 7 Nov 2026, and 1.14.0 already includes two-pane and fold work). This spec must not fight that work.

Leave these areas alone unless the Duo work itself requires a touch, and then do it on the same agreed branch:

- `lib/services/device/fold_state.dart`
- `lib/theme/app_tokens.dart` (the one big-screen breakpoint; `test/consistency/wide_layout_breakpoint_guard_test.dart` guards it)
- `lib/main.dart` fold updates
- Category two-pane: `lib/screens/category_screen.dart` and `test/screens/category_split_view_test.dart`, `test/screens/iphone_duo_layout_sweep_test.dart`

Test My Connection is a 7,118-line screen on this commit. If Duo layout work also lands there, sequence the edits: keep Recommendation 1 and 2 UI in small, dedicated widgets that follow the existing `AppTokens` breakpoints (including the Duo open widths already in those tests, 951×669 and 669×951) instead of adding a new breakpoint. New cards should remain overflow-safe at 320 px and readable on the Duo's closed 466×678.

---

## What this note does not authorize

- No app code from Toolbox in this commit. No merge to `main`, no pull request, no deploy, no store submission.
- No copy of octomon code or assets.
- No change to `WifiGradingBands.kRssiBands` or `ThroughputBands`.
- No help-text or Field Manual edit in this commit (Toolbox drafts those later).
- No background sampling, no tracking, no upload of places.
- No purchase and no new entitlement request. iOS already has `com.apple.developer.networking.wifi-info` and Location When In Use for the current name and BSSID read. This feature must not need a new privacy-sensitive entitlement.
