#!/usr/bin/env python3
"""version_guard.py — fail if a hardcoded app-version literal in shipped prose
disagrees with pubspec.yaml.

WHY THIS EXISTS. The app's own version must never be baked into user-facing prose
as a hand-typed literal. It rots: the "How this app works" guide shipped
`app v1.5.4` while the build was 1.7.0 — the string drifted silently across
several releases because nothing checked it. The guides now render
`app v{{app_version}}`, a placeholder the reader fills at runtime from the actual
package version (see lib/screens/guides/guide_reader_screen.dart). This guard is
the mechanical backstop: it scans shipped prose for an app-version CLAIM and
FAILS the build if any literal is not the current pubspec version. Wired into
`flutter test` via test/consistency/version_consistency_guard_test.dart, so a
drifted version can never ship again.

WHAT IS AN "app-version claim". Only the app's own self-reference idiom:
`app v1.7.0` / `app version 1.7.0` (case-insensitive, optional dot after v).
The pattern anchors on the word "app" ON PURPOSE. Shipped prose is full of
dotted triples that are NOT the app's version — IPv4 addresses (10.20.0.0,
192.168.1.255, 255.255.252.0), IEEE clauses (802.15.4, 9.4.1.7), DNS
(9.9.9.9), and third-party version strings (PCI DSS v4.0.1, a Debian package
wlanpi-dual-orb_1.1.3). None of those are preceded by "app", so none are
matched. The runtime placeholder `{{app_version}}` carries no digits, so a
correctly-dynamic guide is clean.

WHAT ELSE COVERS THE VERSION. The Dart fallback constants
(AppVersion.fallbackVersion / fallbackBuildNumber) are pinned to pubspec by
test/data/app_version_fallback_matches_pubspec_test.dart. This guard covers the
prose surface those constants don't reach.

Usage:
  scripts/version_guard.py                 # scans the default prose globs
  scripts/version_guard.py <file> [file..] # scan explicit files

Exit 0 = clean (no drifted app-version literal). Exit 1 = a literal disagrees
with pubspec (fix before shipping — use {{app_version}} or the correct version).
"""

from __future__ import annotations

import glob
import os
import re
import sys

# The app-version claim: `app v1.7.0` / `app version 1.7.0`. Anchored on "app"
# so IPs, IEEE clauses, DNS, and third-party "v4.0.1" strings are never matched.
_CLAIM = re.compile(r"app\s+v(?:ersion)?\.?\s*(\d+\.\d+\.\d+)", re.IGNORECASE)

# pubspec `version: 1.7.0+57` — capture the marketing (X.Y.Z) part only.
_PUBSPEC_VERSION = re.compile(
    r"^version:\s*(\d+\.\d+\.\d+)(?:\+\S+)?\s*$", re.MULTILINE
)

# Prose surfaces that ship to users and can carry an app-version claim.
_DEFAULT_GLOBS = ("assets/guides/*.md", "assets/help/*.json")


def _repo_root() -> str:
    """Walk up from this script until a dir with pubspec.yaml is found."""
    d = os.path.dirname(os.path.abspath(__file__))
    for _ in range(6):
        if os.path.isfile(os.path.join(d, "pubspec.yaml")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.getcwd()


def _pubspec_version(root: str) -> str:
    with open(os.path.join(root, "pubspec.yaml"), encoding="utf-8") as fh:
        m = _PUBSPEC_VERSION.search(fh.read())
    if not m:
        print("version-guard: FAIL — no `version:` line in pubspec.yaml")
        sys.exit(1)
    return m.group(1)


def _targets(root: str, argv: list[str]) -> list[str]:
    if argv:
        return argv
    files: list[str] = []
    for pattern in _DEFAULT_GLOBS:
        files.extend(sorted(glob.glob(os.path.join(root, pattern))))
    return files


def main(argv: list[str]) -> int:
    root = _repo_root()
    expected = _pubspec_version(root)
    files = _targets(root, argv)

    scanned = 0
    failures: list[str] = []
    for path in files:
        if not os.path.isfile(path):
            continue
        scanned += 1
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                for m in _CLAIM.finditer(line):
                    found = m.group(1)
                    if found != expected:
                        rel = os.path.relpath(path, root)
                        failures.append(
                            f"  {rel}:{lineno}: app version '{found}' "
                            f"!= pubspec '{expected}'  ->  {m.group(0).strip()}"
                        )

    if failures:
        print("VERSION GUARD: FAIL — hardcoded app-version literal(s) disagree "
              f"with pubspec {expected}:")
        print("\n".join(failures))
        print("Fix: render the version dynamically with the {{app_version}} "
              "placeholder (preferred), or correct the literal to "
              f"{expected}. A FAIL does not ship.")
        return 1

    print(f"VERSION GUARD: clean — no drifted app-version literal in "
          f"{scanned} shipped prose file(s) (pubspec {expected}).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
