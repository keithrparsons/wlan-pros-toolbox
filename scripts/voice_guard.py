#!/usr/bin/env python3
"""voice_guard.py — fail the build when shipped user-facing copy breaks a HARD
brand-voice rule (em dash, "WiFi", "802.1x", marketing words, "TL;DR").

WHY THIS EXISTS. The brand voice rules have a mechanical linter that has run on
every article, post, and newsletter for months. It was never once pointed at the
PRODUCT. The app's user-facing copy IS published in Keith's voice, and it had
drifted: 249 shipped Dart strings carried an em dash, including the About screen
title and the company description. It was caught only by accident — a graphic
quoted an app string verbatim and we checked whether the GRAPHIC was wrong. It
wasn't. The app was. This guard closes that hole permanently: the same rules that
gate the prose now gate the product, on every `flutter test` and every CI run.

THE HARD RULES (ported from the prose voice linter; keep the two in sync):
  - em dash (— / &mdash; / &#8212; / &#x2014;) — rewrite the sentence, don't swap
    in a hyphen. An em dash means the sentence wants restructuring.
  - a spaced en dash ( – ) — the obvious way to dodge the em-dash rule. Same fix.
  - "WiFi"   -> must be "Wi-Fi"    (third-party BRAND names are carved out, below)
  - "802.1x" -> must be "802.1X"
  - marketing words (utilize / leverage / robust / seamless / ...) -> say it plainly
  - "TL;DR"
  - a sentence starting with "So,"

WHAT IS IN SCOPE — user-facing copy ONLY. This is the whole job of the guard, and
the reason a naive `grep -r "—" lib/` is useless (it returns 4,147 hits, almost
all of them in code comments, which never ship).

  IN:  Dart STRING LITERALS under lib/ (comments stripped by a real tokenizer);
       the help corpus (assets/help/*.json); the guides (assets/guides/*.md);
       and the rendered value keys of the shipped data sets (assets/data/*.json).

  OUT, each verified rather than assumed:
   1. Code comments and doc comments. They do not ship. The tokenizer removes
      them; it does not grep for them.
   2. The NULL MARKER. A literal whose whole body is a dash — `v == null ? '—' :`
      — is the "no value / not applicable" glyph in a results table. It is DATA,
      not prose. Rewriting it would change meaning. 103 of these exist. Left alone.
   3. The GLYPH MENTION. Help text that documents the null marker by quoting it
      (`The result stays blank ("—") until both fields hold valid numbers`) is
      describing the character, not using it as punctuation. Stripping it would
      make the help text factually wrong about its own UI.
   4. RANGES. An en dash between alphanumerics (`0–32`, `A–Z`, `128–255`,
      `10.0.0.1–10.0.0.254`) is correct typography for a range, and the prose
      linter does not ban en dashes at all. Only a SPACED en dash is a dash used
      as punctuation, and only that is flagged.
   5. lib/data/tool_keywords.dart — the search-match vocabulary. Its own contract
      says "Lowercase; the search is case-insensitive (it lower-cases both
      sides)." These are tokens the user TYPES, never strings the app renders
      (tool_search.dart:67 is the only reader; no widget touches .keywords).
      Its deliberate lowercase '802.1x' is correct and must not be "fixed".
   6. Metadata keys in the data sets that no service reads (verified against each
      loader): see _JSON_SKIP_KEYS.
   7. Generated files, tests, fixtures, third_party/.

  CARVE-OUTS inside the rules themselves:
   - Third-party brands officially styled "WiFi" (WiFi Training, WiFiNinjas, ...).
     The brand rule governs OUR prose; it does not rename someone else's product.
     Many style it "WiFi" deliberately to avoid the Wi-Fi Alliance trademark, so
     "correcting" it would misname them. See _BRAND_ALLOW.
   - IEEE proper nouns that contain a banned marketing word: "Robust Management
     Frame(s)" (802.11w) and "Robust Security Network" (RSN) are standard
     terminology, not vendor-speak. See _TERM_ALLOW.

Usage:
  scripts/voice_guard.py                  # scans the default shipped surfaces
  scripts/voice_guard.py <path> [path..]  # scan explicit files/dirs

Exit 0 = clean. Exit 1 = a HARD voice rule is broken in shipped copy. A FAIL does
not ship.
"""

from __future__ import annotations

import json
import os
import re
import sys

# --------------------------------------------------------------------------
# The HARD rules. Ported from the prose voice linter — keep the two in sync.
# (name, pattern, flags, fix hint)
# --------------------------------------------------------------------------
_RULES = [
    (
        "em dash",
        r"—|&mdash;|&#8212;|&#x2014;",
        re.IGNORECASE,
        "Rewrite the sentence. Split it in two, or set the clause off with "
        "commas. Do not swap in a hyphen or a semicolon.",
    ),
    (
        "spaced en dash",
        r"\s–\s",
        0,
        "A spaced en dash is an em dash wearing a hat. Rewrite the sentence. "
        "(An en dash BETWEEN alphanumerics — a range like 0–32 — is correct and "
        "is not flagged.)",
    ),
    (
        "WiFi (bad casing)",
        r"(?<![#\w])WiFi\b",
        0,
        "Always 'Wi-Fi'. If this is a third-party BRAND that styles itself "
        "'WiFi', add it to _BRAND_ALLOW instead of renaming their product.",
    ),
    (
        "802.1x (bad casing)",
        r"802\.1x\b",
        0,
        "Capital X: '802.1X'.",
    ),
    (
        "TL;DR",
        r"\bTL;?DR\b",
        re.IGNORECASE,
        "No 'TL;DR'. Lead with the conclusion instead.",
    ),
    (
        "marketing word",
        r"\b(utiliz(e|es|ing|ed)|leverag(e|es|ing|ed)|robust|seamless(ly)?|"
        r"game[- ]?changer|cutting[- ]edge|revolutioniz\w*|supercharg\w*|"
        r"effortless(ly)?|elevate|best[- ]in[- ]class|world[- ]class|"
        r"next[- ]level|unlock(s|ing)?\s+(the|your))\b",
        re.IGNORECASE,
        "Marketing vocabulary. Say it plainly: 'use' not 'utilize', 'strong' "
        "not 'robust'.",
    ),
    (
        "'So,' sentence-starter",
        r"(?:^|(?<=[.!?]\s))So,\s",
        re.MULTILINE,
        "Cut the 'So,'.",
    ),
]

# Third-party brands officially styled "WiFi". The casing rule governs OUR prose;
# it never renames someone else's product. Matched case-sensitively and removed
# from the text BEFORE the rules run.
_BRAND_ALLOW = (
    "WiFi Analyser",   # Shankar Korukoppula's PCAP tool. Its own spelling.
    "ShankarWiFi",     # same author's reference site.
    "WiFi Training",
    "WiFiTraining.com",
    "WiFiTraining",
    "WiFi Explorer",
    "WiFiNigel",
    "WiFi Ninjas",
    "WiFiNinjas",
    "BadgerWiFi",
    "WiFiman",
)

# IEEE / standards proper nouns that happen to contain a banned marketing word.
# "Robust Management Frames" is 802.11w; "Robust Security Network" is RSN.
# Matched case-insensitively: the reason-code table renders it sentence-cased
# ("Robust management frame policy violation"), which is still the IEEE term.
_TERM_ALLOW = (
    "robust management frame",
    "robust security network",
)

# Dart files that carry no rendered copy. Verified, not assumed.
_DART_SKIP_FILES = {
    # Search-match vocabulary. Lowercase on purpose (the search lower-cases both
    # sides). Read only by tool_search.dart; never rendered by any widget.
    "lib/data/tool_keywords.dart",
}

_DART_SKIP_SUFFIXES = (".g.dart", ".freezed.dart", ".gen.dart")

# JSON keys that no service reads — verified against each asset's loader. A key
# NOT listed here is scanned, so a newly-added prose key is caught by default.
_JSON_SKIP_KEYS = {
    # educational_resources_service.dart reads: approval, cost, description, id,
    # level, summary, tags, title, topic, topics, url. It never reads these:
    "assets/data/educational_resources.json": {"notes", "source", "approval_note"},
    # plmn_reference_service.dart reads only the `plmn` array (mcc, mnc,
    # plmn_id, carrier, country, region, operator, status). `_meta` is a
    # maintainer block and is never surfaced.
    "assets/data/plmn_us.json": {"_meta"},
}

_DEFAULT_DART_DIRS = ("lib",)
_DEFAULT_ASSET_GLOBS = (
    "assets/help",
    "assets/guides",
    "assets/data",
)

_DASH_ONLY = re.compile(r"^\s*[—–]\s*$")
# A quoted mention of the dash glyph: "—" or '—' or （—）— the help text
# documenting the app's own null marker.
_GLYPH_MENTION = re.compile(r"""["'（(]\s*[—–]\s*["'）)]""")


def _repo_root() -> str:
    d = os.path.dirname(os.path.abspath(__file__))
    for _ in range(6):
        if os.path.isfile(os.path.join(d, "pubspec.yaml")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.getcwd()


def dart_string_literals(src: str):
    """Yield (body, line) for every Dart string literal, comments removed.

    A real tokenizer, not a regex: it walks the source so that a `//` inside a
    string is text and a quote inside a comment is not a string. Handles normal,
    triple-quoted, and raw (r'...') literals.
    """
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":                      # line comment
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and nxt == "*":                      # block comment
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                i += 1
            i += 2
            continue
        start = i
        raw = False
        if c in "rR" and nxt in "'\"":                    # raw string prefix
            raw = True
            i += 1
            c = src[i]
        if c in "'\"":                                   # string literal
            triple = src[i:i + 3] in ("'''", '"""')
            delim = src[i:i + 3] if triple else c
            body_start = i + len(delim)
            j = body_start
            while j < n:
                if not raw and src[j] == "\\":
                    j += 2
                    continue
                if src[j:j + len(delim)] == delim:
                    break
                j += 1
            yield src[body_start:j], src.count("\n", 0, start) + 1
            i = min(j + len(delim), n)
            continue
        i += 1


def _mask_allowed(text: str) -> str:
    """Blank out brand names and standards terms so the rules never see them."""
    # Brands are matched exactly: the owner's own spelling is the proper noun.
    for term in _BRAND_ALLOW:
        text = text.replace(term, " " * len(term))
    # Standards terms are matched case-insensitively (tables sentence-case them).
    for term in _TERM_ALLOW:
        text = re.sub(
            re.escape(term),
            lambda m: " " * len(m.group(0)),
            text,
            flags=re.IGNORECASE,
        )
    # A quoted glyph mention is a reference TO the character, not a use of it.
    text = _GLYPH_MENTION.sub(lambda m: " " * len(m.group(0)), text)
    return text


def check_text(text: str):
    """Return [(rule, match, hint)] for a single user-facing string."""
    if _DASH_ONLY.match(text):          # the null marker. Data, not prose.
        return []
    masked = _mask_allowed(text)
    out = []
    for name, pat, flags, hint in _RULES:
        for m in re.finditer(pat, masked, flags):
            out.append((name, m.group(0).strip(), hint))
    return out


def scan_dart(root: str, paths):
    findings = []
    scanned = 0
    for base in paths:
        for dirpath, dirnames, files in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in ("third_party", ".git")]
            for f in sorted(files):
                if not f.endswith(".dart") or f.endswith(_DART_SKIP_SUFFIXES):
                    continue
                path = os.path.join(dirpath, f)
                rel = os.path.relpath(path, root)
                if rel in _DART_SKIP_FILES:
                    continue
                scanned += 1
                with open(path, encoding="utf-8", errors="replace") as fh:
                    src = fh.read()
                for body, line in dart_string_literals(src):
                    for rule, hit, hint in check_text(body):
                        findings.append((rel, line, rule, hit, body.strip()[:90], hint))
    return findings, scanned


def _walk_json(node, skip_keys, keypath=""):
    """Yield (keypath, string_value) for every string in a JSON tree, skipping
    any subtree under a key this asset's loader never reads."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k in skip_keys:
                continue
            yield from _walk_json(v, skip_keys, f"{keypath}.{k}" if keypath else k)
    elif isinstance(node, list):
        for idx, v in enumerate(node):
            yield from _walk_json(v, skip_keys, f"{keypath}[{idx}]")
    elif isinstance(node, str):
        yield keypath, node


def scan_assets(root: str, paths):
    findings = []
    scanned = 0
    for base in paths:
        for dirpath, _dirnames, files in os.walk(base):
            for f in sorted(files):
                path = os.path.join(dirpath, f)
                rel = os.path.relpath(path, root)
                if f.endswith(".json"):
                    scanned += 1
                    skip = _JSON_SKIP_KEYS.get(rel.replace(os.sep, "/"), set())
                    try:
                        with open(path, encoding="utf-8") as fh:
                            data = json.load(fh)
                    except (OSError, ValueError):
                        continue
                    for keypath, value in _walk_json(data, skip):
                        for rule, hit, hint in check_text(value):
                            findings.append(
                                (rel, keypath, rule, hit, value.strip()[:90], hint)
                            )
                elif f.endswith(".md"):
                    scanned += 1
                    with open(path, encoding="utf-8", errors="replace") as fh:
                        for lineno, line in enumerate(fh, 1):
                            for rule, hit, hint in check_text(line.rstrip("\n")):
                                findings.append(
                                    (rel, lineno, rule, hit, line.strip()[:90], hint)
                                )
    return findings, scanned


def main(argv):
    root = _repo_root()
    os.chdir(root)

    if argv:
        dart_paths = [p for p in argv if os.path.isdir(p) or p.endswith(".dart")]
        asset_paths = [p for p in argv if p not in dart_paths]
        dart_findings, dart_n = scan_dart(root, [p for p in dart_paths if os.path.isdir(p)])
        asset_findings, asset_n = scan_assets(root, [p for p in asset_paths if os.path.isdir(p)])
    else:
        dart_findings, dart_n = scan_dart(root, _DEFAULT_DART_DIRS)
        asset_findings, asset_n = scan_assets(root, _DEFAULT_ASSET_GLOBS)

    findings = dart_findings + asset_findings
    if not findings:
        print(
            f"VOICE GUARD: clean — no HARD voice-rule violation in user-facing "
            f"copy ({dart_n} Dart files, {asset_n} shipped asset files)."
        )
        return 0

    by_rule = {}
    for rel, loc, rule, hit, ctx, hint in findings:
        by_rule.setdefault(rule, []).append((rel, loc, hit, ctx, hint))

    print("VOICE GUARD: FAIL — HARD voice-rule violation(s) in shipped, "
          "user-facing copy:\n")
    for rule in sorted(by_rule, key=lambda r: -len(by_rule[r])):
        rows = by_rule[rule]
        print(f"  {rule} — {len(rows)} hit(s)")
        print(f"      fix: {rows[0][4]}")
        for rel, loc, hit, ctx, _hint in rows[:12]:
            print(f"      {rel}:{loc}  [{hit}]  {ctx}")
        if len(rows) > 12:
            print(f"      (+{len(rows) - 12} more)")
        print("")
    print(f"Total: {len(findings)} violation(s). A FAIL does not ship.")
    print("Rewrite the sentence — do not find-and-replace the character.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
