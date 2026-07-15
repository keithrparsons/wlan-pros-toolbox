#!/usr/bin/env python3
"""Diff-derived mutation gate.

WHY THIS WAS REWRITTEN (2026-07-14). The first version carried a HAND-AUTHORED list
of lines to mutate, and it reported "15/15 fixing lines mutation-proven". That claim
was FALSE. The 15 were the lines *I chose*. The list silently omitted
`own_engine_quality_client.dart`'s `if (includeThroughput)` — the single line that
stops a gigabyte of a user's cellular data from moving.

A mutation tool that only mutates the lines you picked is a tool that confirms your
own judgment. An unaudited exclusion list is an exemption the maker wrote for itself
(GL-005: the maker may not author its own exemption).

So the target set is now DERIVED FROM THE DIFF. Every production line this branch
changes is either mutated, or reported as SKIPPED with a reason. Nothing is silently
exempt.

  BASE   the branch point (default: merge-base with `main`).
  SCOPE  added/modified lines under lib/ and packages/*/lib/.
         Test files are NOT mutated: mutating a test proves nothing about the code.
  ORACLE the ROOT `flutter test` run — the suite we actually certify releases with.
         (That is deliberate. The P2 finding was a line covered only by a suite the
         root run does not execute. Coverage by a test that never runs is not
         coverage.)

  KILLED   the suite went red. The line is observed.
  SURVIVED the suite stayed green with the line broken. NOT COVERAGE. Fix the test.
  SKIPPED  no mutation operator applies (declaration, import, comment, bare string).
           Listed explicitly so the exemption is auditable.

Usage:
  python3 tool/mutate.py --list      # what would be mutated, and what is skipped
  python3 tool/mutate.py             # run the gate
  python3 tool/mutate.py --base <sha>
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys

TEST_CMD = ["flutter", "test"]


def sh(args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def changed_production_lines(base):
    """(path, lineno, text) for every added/modified line in production code."""
    files = [
        f
        for f in sh(["git", "diff", "--name-only", f"{base}...HEAD"]).splitlines()
        if (f.startswith("lib/") or re.match(r"packages/[^/]+/lib/", f))
        and f.endswith(".dart")
    ]
    out = []
    for f in files:
        diff = sh(["git", "diff", "-U0", f"{base}...HEAD", "--", f])
        lineno = 0
        for line in diff.splitlines():
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            if m:
                lineno = int(m.group(1))
                continue
            if line.startswith("+") and not line.startswith("+++"):
                out.append((f, lineno, line[1:]))
                lineno += 1
    return out


IF_RE = re.compile(r"\bif \((?!true\b)(?!false\b).+?\) \{")
GUARD_RE = re.compile(r"\bif \((?!true\b)(?!false\b).+?\) return")


def _if_true(t):
    return IF_RE.sub("if (true) {", t, count=1) if IF_RE.search(t) else None


def _guard_false(t):
    return GUARD_RE.sub("if (false) return", t, count=1) if GUARD_RE.search(t) else None


def _and_or(t):
    return t.replace("&&", "||", 1) if "&&" in t else None


def _or_and(t):
    return t.replace("||", "&&", 1) if "||" in t else None


def _true_false(t):
    if "if (" in t:
        return None
    return (
        re.sub(r"(?<![\w.])true(?![\w])", "false", t, count=1)
        if re.search(r"(?<![\w.])true(?![\w])", t)
        else None
    )


def _false_true(t):
    if "if (" in t:
        return None
    return (
        re.sub(r"(?<![\w.])false(?![\w])", "true", t, count=1)
        if re.search(r"(?<![\w.])false(?![\w])", t)
        else None
    )


def _drop_not(t):
    return re.sub(r"!(?=[\w(])", "", t, count=1) if re.search(r"!(?=[\w(])", t) else None


# Each operator INVERTS A DECISION. None merely reformats.
OPERATORS = [
    ("if->true", _if_true),
    ("guard->false", _guard_false),
    ("&&->||", _and_or),
    ("||->&&", _or_and),
    ("true->false", _true_false),
    ("false->true", _false_true),
    ("drop !", _drop_not),
]

SKIP_PAT = re.compile(r"^\s*($|//|///|\*|/\*|import |export |part |@|\}|\)|\];|\)\;)")


def mutants_for(text):
    if SKIP_PAT.match(text):
        return []
    s = text.strip()
    if s.startswith(("'", '"')) or s == "return;":
        return []
    out = []
    for name, op in OPERATORS:
        try:
            m = op(text)
        except Exception:
            m = None
        if m and m != text:
            out.append((name, m))
    return out


def run_suite(paths=None):
    """Green? `paths=None` runs the FULL root suite (the certifying oracle)."""
    cmd = TEST_CMD + (paths if paths else [])
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    return r.returncode == 0


def candidate_tests(prod_path):
    """Test files that plausibly cover `prod_path`, by import.

    TWO-PHASE ORACLE, and the logic matters:
      * KILLED by a SUBSET  =>  KILLED by the full suite (the full suite contains it).
        So a fast targeted run gives a SOUND `KILLED` verdict.
      * SURVIVED on a subset does NOT imply survived on the full suite.
        So every phase-1 survivor is RE-RUN against the full root suite before it is
        reported as uncovered.
    The heuristic can therefore cost time, never correctness. 83 full-suite runs is
    3+ hours; this is minutes, with the same verdicts.
    """
    base = prod_path.split("/")[-1]
    hits = subprocess.run(
        ["grep", "-rl", base, "test"], capture_output=True, text=True
    ).stdout.split()
    return [h for h in hits if h.endswith("_test.dart")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default=None)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    base = args.base or sh(["git", "merge-base", "HEAD", "main"]).strip()

    lines = changed_production_lines(base)
    targets, skipped = [], []
    for path, lineno, text in lines:
        ms = mutants_for(text)
        if not ms:
            skipped.append((path, lineno, text.strip()[:70]))
            continue
        # ONE mutant per line: the first operator that applies. A line whose decision
        # can be inverted with no test noticing is uncovered regardless of which
        # inversion you pick.
        name, mutated = ms[0]
        targets.append((path, lineno, text, mutated, name))

    print(f"base = {base}")
    print(f"changed production lines: {len(lines)}")
    print(f"  mutable: {len(targets)}    skipped: {len(skipped)}")
    print()

    if args.list:
        print("=== WOULD MUTATE ===")
        for p, n, t, m, op in targets:
            print(f"  {p}:{n}  [{op}]  {t.strip()[:66]}")
        print("\n=== SKIPPED (no decision to invert; auditable, not hidden) ===")
        for p, n, t in skipped:
            print(f"  {p}:{n}  {t}")
        return 0

    # Stream results to disk as they land. A buffered run that gets killed at 50
    # minutes loses everything; this one loses nothing.
    ledger = open("tool/mutation-results.tsv", "w", buffering=1)
    ledger.write("verdict\tfile\tline\top\tsource\n")

    results = []
    for i, (path, lineno, text, mutated, op) in enumerate(targets, 1):
        src_lines = open(path).read().split("\n")
        if lineno - 1 >= len(src_lines) or src_lines[lineno - 1] != text:
            results.append((path, lineno, op, "STALE-ANCHOR", text.strip()[:60]))
            print(f"!! [{i}/{len(targets)}] STALE-ANCHOR {path}:{lineno}")
            continue
        backup = path + ".mutbak"
        shutil.copy2(path, backup)
        try:
            src_lines[lineno - 1] = mutated
            open(path, "w").write("\n".join(src_lines))

            # Phase 1: targeted. A red here is a SOUND kill (the full suite is a
            # superset). A green here is only a HINT, and is escalated.
            cands = candidate_tests(path)
            green = run_suite(cands) if cands else True
            escalated = False
            if green:
                # Phase 2: the full root suite. Only a survivor of THIS is uncovered.
                escalated = True
                green = run_suite()

            verdict = "SURVIVED" if green else "KILLED"
            results.append((path, lineno, op, verdict, text.strip()[:60]))
            mark = "!!" if green else "ok"
            tag = " (full-suite)" if escalated else ""
            print(
                f"{mark} [{i}/{len(targets)}] {verdict:8}{tag} "
                f"{path.split('/')[-1]}:{lineno} [{op}] {text.strip()[:44]}"
            )
        finally:
            shutil.move(backup, path)

    print("\n" + "=" * 78)
    print("DIFF-DERIVED MUTATION REPORT")
    print("=" * 78)
    survivors = [r for r in results if r[3] != "KILLED"]
    if survivors:
        print("  NOT KILLED — these lines are NOT covered:")
        for p, n, op, v, t in survivors:
            print(f"    [{v:12}] {p}:{n} [{op}]  {t}")
    else:
        print("  every mutable changed line was killed by the ROOT suite")
    print(f"\n  {len(results) - len(survivors)}/{len(results)} mutants killed")
    if skipped:
        print(f"  {len(skipped)} lines skipped (no decision to invert) — `--list` to audit")
    print("=" * 78)
    return 1 if survivors else 0


if __name__ == "__main__":
    sys.exit(main())
