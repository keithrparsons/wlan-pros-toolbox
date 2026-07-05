#!/usr/bin/env python3
"""leakage_guard_dart.py — scan Dart *string-literal content* for internal refs.

Companion to scripts/leakage-guard.sh. The shell guard scans human-readable
bundled assets (json/md/txt/html/arb). It cannot safely scan .dart source because
those files legitimately carry internal provenance in *code comments* (which never
ship) — grepping raw .dart would false-positive on every provenance header.

This scanner strips Dart comments (// , /// , /* */) with a small tokenizer that
respects string literals (normal, triple-quoted, and raw), then applies the same
internal-term patterns SOP-061 forbids to what remains — i.e. the string literals
and code that actually compile into the shipped app. It exits 1 on any hit.

This is the durable fix for the class of leak where an internal attribution lived
inside a *shipped Dart string* (e.g. a decoder `source:` field ending ", Pax ...")
rather than in tool_help.json — the surface the original guard missed.

Usage:
  leakage_guard_dart.py <file-or-dir> [more...]
Exit 0 = clean, 1 = internal reference found in shipped Dart string content.
"""
import os
import re
import sys

# Case-insensitive team/process language + internal review stamps.
CI_PAT = re.compile(
    r"by the team|by our team|reviewed by the team|"
    r"keith-(reviewed|approved|confirmed)|per a keith decision|"
    r"transcribed by the team|verified and expanded by|"
    r"voice-gated|voice-lint|cold-eyes|rendered verbatim|the treatment",
    re.IGNORECASE,
)
# Case-sensitive internal machinery: SOP/GL/WS refs, wikilinks, repo paths,
# and whole-word agent names.
CS_PAT = re.compile(
    r"SOP-[0-9]|GL-[0-9]|WS-[0-9]|\[\[(?!:)|session-log|"
    r"Deliverables/|Team Knowledge|myPKA|/Developer/|"
    r"(^|[^A-Za-z])(Larry|Penn|Pax|Nolan|Mack|Silas|Felix|Vera|Iris|Charta|Pixel|Vex)([^A-Za-z]|$)"
)


def strip_comments(src):
    """Return src with // /// and /* */ comments replaced by spaces (newlines
    preserved so line numbers are stable), while keeping string-literal content.
    Handles normal, triple-quoted, and raw (r'...') Dart strings."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        # line comment
        if c == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        # block comment
        if c == "/" and nxt == "*":
            out.append("  ")
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
            continue
        # raw string prefix
        raw = False
        if c in "rR" and nxt in "'\"":
            out.append(c)
            i += 1
            c = src[i]
            nxt = src[i + 1] if i + 1 < n else ""
            raw = True
        # string literal (triple or single)
        if c in "'\"":
            triple = src[i:i + 3] in ("'''", '"""')
            delim = src[i:i + 3] if triple else c
            out.append(delim)
            i += len(delim)
            while i < n:
                if not raw and src[i] == "\\":
                    out.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i:i + len(delim)] == delim:
                    out.append(delim)
                    i += len(delim)
                    break
                out.append(src[i])
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def iter_dart_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, _, files in os.walk(p):
                for f in sorted(files):
                    if f.endswith(".dart"):
                        yield os.path.join(root, f)
        elif p.endswith(".dart"):
            yield p


def scan(paths):
    hits = 0
    scanned = 0
    for path in iter_dart_files(paths):
        scanned += 1
        with open(path, encoding="utf-8", errors="replace") as fh:
            src = fh.read()
        stripped = strip_comments(src)
        file_hits = []
        for lineno, line in enumerate(stripped.splitlines(), 1):
            # import/export/part directives reference *_screen.dart filenames as
            # code paths — legitimate, not user-facing. Skip them.
            if re.match(r"\s*(import|export|part)\b", line):
                continue
            if CI_PAT.search(line) or CS_PAT.search(line):
                file_hits.append((lineno, line.strip()[:160]))
        if file_hits:
            hits += 1
            print("── %s" % path)
            for lineno, text in file_hits:
                print("   %d: %s" % (lineno, text))
    return hits, scanned


def main(argv):
    paths = argv[1:]
    if not paths:
        print("usage: leakage_guard_dart.py <file-or-dir> [more...]", file=sys.stderr)
        return 2
    hits, scanned = scan(paths)
    print("")
    if hits:
        print("LEAKAGE GUARD (dart strings): FAIL — %d file(s) with internal "
              "references (scanned %d)." % (hits, scanned))
        print("Internal machinery in a shipped Dart string. SOP-061 Check 1. A FAIL does not ship.")
        return 1
    print("LEAKAGE GUARD (dart strings): clean — no internal references in "
          "%d Dart files." % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
