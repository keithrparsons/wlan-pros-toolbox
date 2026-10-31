#!/usr/bin/env python3
"""shadow_webdiff.py: compare a released Flutter web folder with a shadow build.

Usage: scripts/shadow_webdiff.py <reference_dir> <shadow_dir>

Prints file counts, sizes, base href, version.json and every file that is
missing or different. Differences Flutter makes on every build are labeled
EXPECTED; anything else is labeled REAL. Exit 0 = no real differences,
exit 1 = at least one real difference.
"""
import hashlib
import json
import os
import re
import sys

# Written by the build or the deploy step, never by the app source.
EXPECTED_ONLY_IN_REFERENCE = {"_redirects", "BUNDLE-INFO.txt"}
EXPECTED_DIFFERS = {".last_build_id"}
SW_VERSION = re.compile(rb'serviceWorkerVersion: "\d+"')


def walk(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            p = os.path.join(d, f)
            with open(p, "rb") as fh:
                data = fh.read()
            out[os.path.relpath(p, root)] = data
    return out


def digest(name, data):
    # flutter_bootstrap.js carries a random service worker version per build.
    if name == "flutter_bootstrap.js":
        data = SW_VERSION.sub(b'serviceWorkerVersion: "X"', data)
    return hashlib.sha256(data).hexdigest()


def base_href(files):
    m = re.search(rb'<base href="([^"]*)">', files.get("index.html", b""))
    return m.group(1).decode() if m else None


def version(files):
    try:
        return json.loads(files["version.json"])
    except (KeyError, ValueError):
        return None


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ref, sha = walk(sys.argv[1]), walk(sys.argv[2])
    real, expected = [], []

    for f in sorted(set(ref) - set(sha)):
        (expected if f in EXPECTED_ONLY_IN_REFERENCE else real).append(f"only in reference: {f}")
    for f in sorted(set(sha) - set(ref)):
        (expected if f == "BUNDLE-INFO.txt" else real).append(f"only in shadow: {f}")
    for f in sorted(set(ref) & set(sha)):
        if digest(f, ref[f]) != digest(f, sha[f]):
            msg = f"differs: {f} ({len(ref[f])} vs {len(sha[f])} bytes)"
            (expected if f in EXPECTED_DIFFERS else real).append(msg)
        elif f == "flutter_bootstrap.js" and ref[f] != sha[f]:
            expected.append("differs: flutter_bootstrap.js (service worker version only)")

    if base_href(ref) != base_href(sha):
        real.append(f"base href: reference {base_href(ref)!r}, shadow {base_href(sha)!r}")
    if version(ref) != version(sha):
        real.append(f"version.json: reference {version(ref)}, shadow {version(sha)}")

    js = "main.dart.js"
    print(f"reference files {len(ref)}, shadow files {len(sha)}")
    print(f"reference bytes {sum(map(len, ref.values()))}, shadow bytes {sum(map(len, sha.values()))}")
    print(f"base href {base_href(ref)!r} vs {base_href(sha)!r}")
    print(f"version.json {version(ref)} vs {version(sha)}")
    if js in ref and js in sha:
        print(f"main.dart.js {'IDENTICAL' if ref[js] == sha[js] else 'DIFFERENT'}")
    for line in expected:
        print(f"  EXPECTED  {line}")
    for line in real[:60]:
        print(f"  REAL      {line}")
    if len(real) > 60:
        print(f"  ... and {len(real) - 60} more real differences")
    print("RESULT: " + ("MATCH (only expected differences)" if not real else f"{len(real)} REAL DIFFERENCE(S)"))
    sys.exit(1 if real else 0)


if __name__ == "__main__":
    main()
