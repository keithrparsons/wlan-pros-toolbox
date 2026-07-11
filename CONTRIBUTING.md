# Contributing to the WLAN Pros Toolbox

The Toolbox exists because Wi-Fi professionals kept needing the same tools and kept not having them. If you have found a bug, or you have a tool the profession needs, we want it.

## The short version

1. Open an issue first for anything non-trivial, so we can agree on the approach before you spend your evening on it.
2. Fork, branch, and open a pull request.
3. **Sign the CLA.** A bot will prompt you on your first pull request. It takes one comment.
4. Tests pass, `flutter analyze` is clean.

## You will need to sign the CLA before your pull request can be merged

We use a **Contributor License Agreement** ([`CLA.md`](CLA.md)), administered by [CLA Assistant](https://cla-assistant.io). On your first pull request, a bot comments with a link. You sign by commenting. You will never be asked again.

**You keep the copyright to your work.** The CLA grants us a license, including the right to sublicense.

**Why we ask, in plain English:** the Toolbox is AGPL-3.0, but it also ships on the **Apple App Store**, **Google Play**, and the **Microsoft Store**. Those platforms impose end-user terms that are not compatible with the AGPL. We can distribute there *only* because we hold the necessary rights across the whole codebase.

If we merged your contribution without a CLA, you would own copyright in part of the app, and we would no longer have the right to ship it to the App Store. Anyone in that position could have the app pulled. **This is not hypothetical: it is exactly how VLC was removed from the App Store in 2011.** The CLA is what keeps the Toolbox in the hands of the people who use it.

This is the same arrangement used by Signal, Grafana, and Element.

## Licensing of your contribution

By contributing, you agree your work is licensed under the **GNU AGPL-3.0** (see [`LICENSE`](LICENSE)), with the additional grant described in [`CLA.md`](CLA.md).

If your contribution adds a **new dependency**, say so explicitly in the pull request. We check every dependency's license, and **anything in the GPL family will be rejected** because it would make the app undistributable on the App Store. Permissive licenses (MIT, BSD, Apache-2.0) and MPL-2.0 are fine.

## Trademark

The AGPL covers the code. It does **not** grant any right to the **WLAN Pros** name or logo. See [`TRADEMARK.md`](TRADEMARK.md). If you fork and distribute, you must rebrand.

## What makes a good contribution

**Yes, please:**

- Bug fixes, with a test that fails before and passes after.
- New tools that a working Wi-Fi professional would actually reach for on a site survey.
- Accuracy fixes. If a calculation is wrong, that matters more than anything else here.
- Platform parity. Something works on macOS but not Windows? That is a real bug.
- Accessibility and localization.

**Please discuss first:**

- Anything that adds a dependency.
- Anything that changes the tool catalog structure or the router.
- Anything that phones home. **The Toolbox has no telemetry and that is a deliberate, permanent design decision.** Do not add any.

## Standards

- **Accuracy above all.** This app is used to make real decisions about real networks. A tool that is confidently wrong is worse than no tool. Cite your source for any formula or constant.
- **Every tool needs a help file.** See the existing `tool_help.json` pattern.
- **Offline first.** Tools should work with no internet connection wherever physically possible.
- **"Wi-Fi", never "WiFi". "802.1X", never "802.1x".** An access point is not a router.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos      # or ios, android, chrome, windows
```

## Questions

Open an issue, or reach us at keith@wlanpros.com.
