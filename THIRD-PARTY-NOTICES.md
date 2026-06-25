# Third-Party Notices

The WLAN Pros Toolbox bundles third-party components that remain governed by their own licenses. The WLAN Pros Toolbox source license (see `LICENSE`) does not limit or modify the rights granted to you under these third-party licenses. For the authoritative license text of each component, see the component's directory in this repository or its upstream project.

## Bundled components

- **iperf3** — BSD 3-Clause License. See `third_party/iperf3/`.
- **PDF.js** (Mozilla) — Apache License 2.0. See `web/pdfjs/`.
- **Speed-test service logos** — used under the terms noted in `assets/speedtest-logos/` (see that directory's README for attribution).
- **IEEE OUI registry data** — the offline MAC vendor lookup data is derived from the public IEEE OUI registry.

## Fonts

Bundled in `assets/fonts/` and rendered offline:

- **IBM Plex Sans** — SIL Open Font License 1.1.
- **DM Mono** — SIL Open Font License 1.1.
- **Roboto Mono** — Apache License 2.0.

## Dart and Flutter packages

The app's Dart and Flutter dependencies (declared in `pubspec.yaml`) are distributed under their respective open-source licenses, predominantly BSD 3-Clause and MIT. A complete, per-package license listing for a given build is produced by the Flutter toolchain at build time (`flutter` aggregates `LICENSE` files from all resolved packages).
