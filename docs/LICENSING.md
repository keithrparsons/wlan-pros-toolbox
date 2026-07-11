# Licensing — decisions, rationale, and what is still open

**Status:** files staged. **The repository is still PRIVATE and must stay private until every gate below is cleared.**
**Decision date:** 2026-07-11 · **Decided by:** Keith
**Research:** `myPKA/Deliverables/2026-07-11-toolbox-open-source-licensing/BRIEF.md`

---

## The decision

**AGPL-3.0 + Contributor License Agreement + trademark policy.** We keep shipping our own store builds under Apple's, Google's, and Microsoft's normal terms.

This is the Signal stack: AGPL-3.0 repo, CLA enforced before merge, apps live on the iOS App Store and Google Play today.

## Why, in one paragraph

Keith's goal was *"share it with the community, but nobody else profits off my work."* **Those two things cannot both be true inside open source** — the Open Source Definition clause 6 forbids restricting use "in a business." More to the point, a "non-commercial" license would have **banned our own audience**: PolyForm Noncommercial permits personal use "without any anticipated commercial application," which excludes a CWNE running a paid site survey. That is everyone we build for.

What Keith actually wants to prevent is **rebrand-and-sell**, and that is achievable. **AGPL** makes a closed-source fork impossible and a commercial fork pointless (they must publish everything, and we can absorb it back). **Trademark** takes the name away, which is what actually stops a copycat: both Apple's and Google's copycat-takedown processes ask for a registration number. The code license removes the profit motive; the trademark removes the brand.

## The myth that nearly cost us the right license

**"Apple bans GPL apps" is folklore.** Apple has never published such a policy. VLC was pulled in 2011 because **a copyright-holding contributor filed a complaint** — not by Apple's hand. The conflict is real in the text (Apple's mandatory EULA imposes terms that AGPL §10 forbids), but it is a **copyright conflict actionable only by a copyright holder**.

Wireless LAN Professionals, Inc. holds the copyright. **We cannot infringe our own license.** Signal-iOS is AGPL-3.0 and on the App Store right now.

**This is exactly why the CLA is load-bearing and not paperwork.** The moment we merge an outside PR without one, that contributor owns copyright in part of the app — and acquires standing to get our iOS app pulled. One contributor, one complaint. That is the VLC fact pattern verbatim.

---

## Gates — ALL must clear before the repo goes public

| # | Gate | Status |
|---|---|---|
| 1 | Dependency audit: no GPL-family deps | ✅ **PASS** — 157 packages: 93 BSD-3, 45 MIT, 7+7 Apache/SDK, 4 MPL-2.0. Zero copyleft. MPL-2.0 packages carry no Exhibit B, so AGPL-compatible under MPL §3.3. |
| 2 | Secret-scan the full git history | ✅ **PASS** — gitleaks, 612 commits, all 37 branches, merge diffs included. One finding: `third_party/iperf3/.../private.pem`, which is iperf3's **upstream test fixture** for `t_auth.c`, not a credential. No metrics creds, no `.env`, no keys. |
| 3 | **CLA Assistant installed and enforcing** | ⬜ **TODO — BLOCKING.** See below. |
| 4 | **Orb `.deb` redistribution rights confirmed** | ⬜ **TODO — BLOCKING.** See below. |
| 5 | CLA text reviewed by counsel | ⬜ **TODO** — a defective CLA is worse than none, because you think you are covered. |
| 6 | Trademark: attorney call | ⬜ **TODO** — not strictly blocking the repo flip, but blocking the *protection* being real. |

### Gate 3 — CLA Assistant (blocking)

Install **before** the repo is public and **before any PR is merged**. The first un-CLA'd merge is a door only that specific contributor can reopen.

1. Go to https://cla-assistant.io and sign in with GitHub.
2. Configure it against `keithrparsons/wlan-pros-toolbox` (and `wlan-pros-toolbox-pi`).
3. Point it at `CLA.md` in this repo as the agreement text.
4. Verify it blocks merge on an unsigned PR **before** trusting it. Open a throwaway PR from a second account and confirm the bot blocks it.

### Gate 4 — the Orb `.deb` (blocking)

`assets/downloads/wlanpi-dual-orb_1.1.3_all.deb.b64` is an **Orb** Debian package, base64-encoded and committed to this repo. Publishing the repo would redistribute Orb's software publicly.

**We do not currently have confirmed redistribution rights.** Email drafted to Doug Suttles (Orb CEO), cc Ferney, 2026-07-11.

**Default plan if Orb says no, or does not reply:** remove the `.b64` from the repo and have the installer fetch the package from an Orb-hosted URL at install time. That keeps distribution under Orb's control and is arguably better engineering anyway. **Do not go public with the blob still committed and rights unconfirmed.**

Note: removing it from the working tree is not enough. It is in the **git history**, and a public repo exposes history. If Orb says no, the blob must be purged from history (`git-filter-repo`) or the repo published from a squashed fresh start.

### Gate 6 — trademark

The single highest-leverage legal spend in this whole exercise. 30 minutes with a US trademark attorney. Ask exactly three things:

1. Is **"WLAN Pros"** registrable, or will it draw a **"merely descriptive"** refusal? ("WLAN" is the field, "Pros" are the customers. This is a live risk.)
2. If descriptive, do we have **§2(f) acquired distinctiveness** from years of continuous use? (We plausibly do, in spades.)
3. Do we file the **words**, the **stylized/composite mark with the logo**, or both? Which classes? (Class 9 software, Class 41 education, Class 42 consulting — each ~$350.)

Until this is registered, we rely on **common-law rights**, which we do have from use in commerce, but which are slower and harder to enforce — and which the App Store copycat process does not accept a number for.

---

## Files in this kit

| File | Purpose |
|---|---|
| `LICENSE` | GNU AGPL-3.0, verbatim from gnu.org. **Do not edit it.** Replaces the previous all-rights-reserved notice. |
| `TRADEMARK.md` | Code is AGPL. The WLAN Pros name and logo are **not**. Forks must rebrand. Grounded in GPL-3.0 §7(e), which expressly anticipates this. |
| `CLA.md` | Contributor License Agreement (Apache ICLA-derived). **The `sublicense` right in §2 is the clause that preserves App Store distribution.** ⚠️ Needs counsel. |
| `CONTRIBUTING.md` | How to contribute + why the CLA is required, in plain English. |
| `LICENSE-EXCEPTION-APPSTORE.md` | Nextcloud-style store exception. Belt-and-braces alongside the CLA. ⚠️ Needs counsel. |
| `THIRD-PARTY-LICENSES.md` | Generated from `dart pub deps`. **Regenerate on every dependency change.** |
| `THIRD-PARTY-NOTICES.md` | Pre-existing, hand-maintained. Covers bundled non-pub components. Keep both. |

## Standing rules created by this decision

1. **No GPL-family dependencies, ever.** One would make the app undistributable on the App Store. Enforce in review; consider wiring `license_checker` into CI to hard-fail.
2. **No PR merges without a signed CLA.** No exceptions, including for people we know well.
3. **Regenerate `THIRD-PARTY-LICENSES.md` whenever `pubspec.yaml` changes.**
4. **Do not bundle third-party binaries without confirmed redistribution rights.** The Orb `.deb` is the cautionary tale; it was committed before anyone asked the question.
5. **The app has no telemetry. That is permanent.** Reject contributions that add any.

## Still true, and worth remembering

**AGPL does not stop someone selling this.** They may fork it, charge for it, and be entirely within their rights — *provided they publish their complete source and do not use our brand.* What AGPL destroys is the business case: no proprietary secret sauce, no durable differentiation, and everything they build comes straight back to us. It is not a wall. It is a policy that makes the fork not worth doing.

**The brand is the moat.** Not the license.
