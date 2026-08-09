#!/usr/bin/env python3
"""Flatten CSS in a bundled SVG into inline presentation attributes.

WHY THIS EXISTS. flutter_svg drops CSS outright. It says so itself, logging
`unhandled element <style/>` while it renders. A vendor mark authored as
`<style>.a{fill:#CA992C}</style>` plus `class="a"` therefore renders perfectly
in a browser and BROKEN on the device: the classed fills never apply, so every
classed shape falls back to the SVG default fill, which is black. Measured
2026-08-09 on the real macOS embedder: the FCC seal rendered as a featureless
black disc at 78.2% black on its #2A2A2A chip.

Eight of the eleven CSS-carrying vendor marks in this bundle were broken that
way. Keith ruled on 2026-08-09 that the remedy is a bundling-time flatten
rather than eight hand edits, so that nobody maintains an edited copy of
somebody else's logo by hand and the twelfth mark that arrives cannot arrive
broken. He also ruled that we ship the modified copy and keep the pristine
original alongside, unbundled, in assets/vendor-src/.

WHAT IT DOES. Reads the <style> rules, writes each declaration onto the
elements that carried the matching class as an ordinary presentation attribute,
deletes the class attributes and the <style> blocks, and leaves every other byte
alone. CSS property names and SVG presentation attribute names are the same
strings, so no translation table is needed or wanted.

WHAT IT REFUSES TO DO, and this is the important half. It handles exactly one
CSS shape: a list of bare class selectors with a flat declaration block. Given
anything else it EXITS NON-ZERO AND WRITES NOTHING. A flatten that guesses at a
descendant selector, a media query or a specificity conflict is worse than no
flatten, because the output looks finished and renders wrong, and nobody
re-derives a vendor's intent from a diff. Measured across the eleven marks in
this bundle on 2026-08-09: every selector is a bare simple class, the declared
properties are nine ordinary presentation attributes, two elements carry
multiple classes, and ZERO elements carry both a class and an inline fill or
stroke. That last count is what makes this safe, because it means there is no
specificity conflict to resolve anywhere in the set.

THE ONE DIVERGENCE THAT WOULD BE A TRAP IF IT EVER APPEARED. In CSS a
stylesheet rule outranks a presentation attribute, so `<path class="a"
fill="red">` with `.a{fill:blue}` is BLUE in a browser and RED in flutter_svg.
A "faithful" flatten would have to pick one, and either choice silently changes
an existing render. No such element exists in this bundle. The tool refuses
rather than choosing, so the day one appears a human decides.

USAGE
    tool/flatten_vendor_svg_css.py <file.svg> [<file.svg> ...]
    tool/flatten_vendor_svg_css.py --check <file.svg> [...]

--check writes nothing and exits non-zero if any named file is not already
flat. That is the reproducibility half: re-running the tool over a committed
asset must be a no-op, which is what makes a committed generated file
trustworthy.
"""

from __future__ import annotations

import re
import sys

# A rule block: everything up to '{', then everything up to the matching '}'.
_RULE = re.compile(r"([^{}]+)\{([^{}]*)\}")
# A bare class selector and nothing else. Anything that fails this is refused.
_SIMPLE_CLASS = re.compile(r"^\.([A-Za-z_][\w-]*)$")
# <style ...> ... </style>, wherever it sits, including inside <defs>.
_STYLE_BLOCK = re.compile(r"[ \t]*<style\b[^>]*>.*?</style>\s*", re.DOTALL)
# An element's class attribute, captured with its surrounding whitespace so the
# replacement can put the presentation attributes exactly where it stood.
_CLASS_ATTR = re.compile(r'\s+class="([^"]*)"')
# Any start tag.
_START_TAG = re.compile(r"<[A-Za-z][\w:-]*\b[^>]*>", re.DOTALL)


class Refused(Exception):
    """The file is outside the shape this tool is willing to rewrite."""


def parse_rules(css: str) -> list[tuple[str, list[tuple[str, str]]]]:
    """Return [(class_name, [(prop, value), ...]), ...] in stylesheet order.

    Stylesheet order is load-bearing. All selectors here have equal
    specificity, so when two rules set the same property on the same element
    the LATER rule wins, exactly as a browser resolves it.
    """
    css = css.replace("<![CDATA[", "").replace("]]>", "")
    # Strip CSS comments before parsing; an unstripped comment containing a
    # brace would desynchronise the rule regex.
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.DOTALL)
    rules: list[tuple[str, list[tuple[str, str]]]] = []
    consumed = 0
    for m in _RULE.finditer(css):
        gap = css[consumed:m.start()].strip()
        if gap:
            raise Refused(f"unparsed CSS between rules: {gap[:80]!r}")
        consumed = m.end()
        decls: list[tuple[str, str]] = []
        for decl in m.group(2).split(";"):
            decl = decl.strip()
            if not decl:
                continue
            if ":" not in decl:
                raise Refused(f"declaration without a colon: {decl[:80]!r}")
            prop, value = decl.split(":", 1)
            prop, value = prop.strip(), value.strip()
            if not prop or not value:
                raise Refused(f"empty declaration: {decl[:80]!r}")
            if "!important" in value:
                raise Refused("!important changes the cascade; refusing")
            # A presentation attribute cannot carry a quoted font stack the way
            # CSS can. Strip the quoting CSS requires and SVG does not.
            value = value.strip("'\"")
            if '"' in value:
                raise Refused(f"value contains a quote: {value[:80]!r}")
            decls.append((prop, value))
        for sel in m.group(1).split(","):
            sel = sel.strip()
            if not sel:
                continue
            hit = _SIMPLE_CLASS.match(sel)
            if not hit:
                raise Refused(
                    f"selector {sel!r} is not a bare class selector. This tool "
                    "rewrites exactly one CSS shape and refuses the rest.")
            rules.append((hit.group(1), decls))
    tail = css[consumed:].strip()
    if tail:
        raise Refused(f"trailing CSS outside any rule: {tail[:80]!r}")
    return rules


def attrs_for(classes: list[str],
              rules: list[tuple[str, list[tuple[str, str]]]]) -> list[tuple[str, str]]:
    """Resolve one element's classes to an ordered attribute list.

    Iterates the stylesheet in source order, not the order the classes appear
    in the attribute, because that is how the cascade resolves equal-specificity
    rules. A later rule setting the same property replaces an earlier one and
    keeps the earlier one's position, so the output attribute order is stable.
    """
    resolved: dict[str, str] = {}
    for name, decls in rules:
        if name not in classes:
            continue
        for prop, value in decls:
            resolved[prop] = value
    return list(resolved.items())


def flatten(src: str) -> str:
    styles = re.findall(r"<style\b[^>]*>(.*?)</style>", src, re.DOTALL)
    rules = parse_rules(" ".join(styles)) if styles else []
    known = {name for name, _ in rules}

    def rewrite_tag(m: re.Match[str]) -> str:
        tag = m.group(0)
        cls = _CLASS_ATTR.search(tag)
        if not cls:
            return tag
        classes = cls.group(1).split()
        unknown = [c for c in classes if c not in known]
        if unknown and rules:
            # A class with no rule paints nothing, in a browser and here alike.
            # Dropping it is correct, but say so rather than doing it silently.
            print(f"    note: class(es) {unknown} have no rule; dropping",
                  file=sys.stderr)
        pairs = attrs_for(classes, rules)
        for prop, _ in pairs:
            if re.search(rf'(?:^|\s){re.escape(prop)}="', tag):
                raise Refused(
                    f"element already carries an inline {prop!r} that the "
                    f"stylesheet also sets. A browser applies the stylesheet "
                    f"and flutter_svg applies the attribute, so the two render "
                    f"differently today and flattening would silently pick a "
                    f"winner. Refusing: {tag[:120]!r}")
        rendered = "".join(f' {p}="{v}"' for p, v in pairs)
        return tag[:cls.start()] + rendered + tag[cls.end():]

    out = _START_TAG.sub(rewrite_tag, src)
    out = _STYLE_BLOCK.sub("", out)
    if "class=" in out:
        raise Refused("a class attribute survived the rewrite")
    if "<style" in out:
        raise Refused("a <style> block survived the rewrite")
    return out


def read_utf8(path: str) -> str:
    data = open(path, "rb").read()
    if data[:3] == b"\xef\xbb\xbf" or data[:2] in (b"\xff\xfe", b"\xfe\xff"):
        raise Refused(
            f"{path} starts with a byte-order mark. flutter_svg throws "
            "XmlParserException on it and renders nothing; transcode to UTF-8 "
            "first. Guarded by test/assets/bundled_svg_encoding_guard_test.dart.")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as e:
        raise Refused(f"{path} is not valid UTF-8: {e}")


def main(argv: list[str]) -> int:
    check_only = "--check" in argv
    paths = [a for a in argv[1:] if not a.startswith("--")]
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2

    failures = 0
    for path in paths:
        try:
            src = read_utf8(path)
            out = flatten(src)
        except Refused as e:
            print(f"REFUSED {path}: {e}", file=sys.stderr)
            failures += 1
            continue
        if out == src:
            print(f"    flat  {path} (already inline, nothing to do)")
            continue
        if check_only:
            print(f"NOT FLAT {path}: still carries CSS", file=sys.stderr)
            failures += 1
            continue
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(out)
        print(f"    wrote {path} ({len(src)} -> {len(out)} bytes)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
