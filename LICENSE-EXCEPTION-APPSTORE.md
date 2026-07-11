# App Store Distribution Exception

> **⚠️ DRAFT — NOT YET LEGALLY REVIEWED.** Adapted from [`nextcloud/ios/COPYING.iOS`](https://github.com/nextcloud/ios/blob/master/COPYING.iOS). Have counsel review before relying on it.

## The situation

The WLAN Pros Toolbox is licensed under the **GNU AGPL-3.0** (see `LICENSE`).

The Toolbox is also distributed through the **Apple App Store**, **Google Play**, and the **Microsoft Store**. Apple in particular requires that applications be licensed to end users under terms that include restrictions on copying, modification, and redistribution. Those restrictions are arguably "further restrictions" of the kind prohibited by AGPL-3.0 section 10.

**This is a conflict between two license texts, not a violation of anyone's rights.** Wireless LAN Professionals, Inc. holds copyright in the Toolbox and can therefore distribute its own builds under whatever terms a store requires. A copyright holder is not bound by the license it offers to others.

However, contributors also hold copyright in their contributions. This document, together with the Contributor License Agreement (`CLA.md`), makes the position explicit for everyone.

## The exception

**Wireless LAN Professionals, Inc. grants the following additional permission**, as an exception under GPL-3.0 section 7 (incorporated by AGPL-3.0):

> As a special exception, and in addition to the rights granted by the GNU AGPL-3.0, you are permitted to distribute the WLAN Pros Toolbox, or a derivative work thereof, through the Apple App Store, Google Play, the Microsoft Store, or any comparable application distribution platform, **and to accept the platform's standard end-user license terms for that distribution**, notwithstanding the restrictions of AGPL-3.0 section 10, provided that:
>
> 1. you comply with all other terms of the AGPL-3.0, in particular the obligation to make the Corresponding Source available to all recipients; and
> 2. you do not use the "WLAN Pros" name, the WLAN Pros logo, or the app names, in accordance with `TRADEMARK.md`.

**Wireless LAN Professionals, Inc. will not pursue any claim of AGPL-3.0 violation arising solely from the conflict between the AGPL-3.0 and an application store's mandatory end-user terms**, against any party otherwise complying with the AGPL-3.0.

## What this does not do

This exception does **not**:

- permit you to keep your modifications closed. The AGPL's source obligations remain in full force.
- grant any trademark rights. See `TRADEMARK.md`.
- bind any third party who holds copyright in a contribution and has not signed the CLA. **This is precisely why the CLA exists and why it is required before any contribution is merged.**

## Precedent

- **Nextcloud** ships GPLv3 with an equivalent iOS exception (`COPYING.iOS`).
- **Signal** ships AGPL-3.0 on the iOS App Store and Google Play, with a CLA.
- **Element** (Matrix) ships AGPL-3.0 on the App Store, dual-licensed commercially.

The pattern is well established. The mechanism that makes it work is not the exception text; it is **holding the rights**. The CLA is what preserves that.
