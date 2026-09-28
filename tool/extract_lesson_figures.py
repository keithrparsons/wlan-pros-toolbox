#!/usr/bin/env python3
"""Extract an explainer guide's own figures as flutter_svg-safe SVG assets.

A Guided Lesson shows the guide's OWN figures, not redraws. Each guide keeps
its figures as inline <svg> inside <div class="fig"> blocks, with a
<div class="cap"> caption that starts "Figure N. Title." This script lifts
every one of them out of the guide HTML into

    assets/lesson-figures/<slug>/fig-NN.svg      (NN = the figure number)
    assets/lesson-figures/<slug>/cover.svg       (the cover art, if any)
    assets/lesson-figures/<slug>/figures.json    (number, file, caption, alt)

and rewrites the few SVG features flutter_svg does not draw, so the lesson
shows what the PDF shows:

  * <marker> arrowheads. flutter_svg has no <marker> support and silently
    drops the arrowhead. Every marker-start / marker-end is expanded into an
    inline copy of the marker's own shapes, placed and turned exactly as the
    SVG spec places it (refX/refY, viewBox, markerUnits, orient="auto"), then
    the <marker> defs are removed.
  * <use href="#id">: replaced by a copy of the referenced element.
  * currentColor: resolved to the inherited `color`, starting from the
    guide's CSS text color for a figure (#444444) or the cover (#111111).
  * font-family lists ("IBM Plex Sans, sans-serif"): reduced to the first
    family, which the app bundles.
  * class, role, aria-*, data-* and id attributes that nothing references:
    dropped.

Guides built with the figure kit (2026-09-28: How GPS Works, Where Your
Phone Is) style their figures from the page, so the script also brings the
page along:

  * style="fill:var(--note-ink)": every declaration becomes the matching
    presentation attribute (a declaration beats an attribute, as in CSS),
    and var(--x) resolves against the guide's own :root. font-size "15px"
    loses its unit.
  * the page sprite (<svg class="xsprite">): a marker or <symbol> a figure
    points at is copied in before conversion.
  * <use> of a <symbol viewBox> with width and height: scaled into that box
    per the default preserveAspectRatio (xMidYMid meet).
  * .xf text and .xf .mono: the kit's two font rules, as font-family.

Guides that embed an icon as a nested <svg x y width height viewBox> (Analog
vs Digital, Scales and Ratios) get each one as a group scaled the same way.
A start tag that repeats an attribute keeps the first, as a browser does.

Nothing is recolored and no label is changed, with one exception you ask
for by name: a label that points at a printed page ("(page 6)") means
nothing in a lesson, so the script warns about every one it finds, and
--replace "(page 6)=(step 5)" rewrites that exact label text. Every
replacement is printed; put it in your report. The figures are drawn for a
white page, so the lesson shows them on an always-light card in both themes.

USAGE
    python3 tool/extract_lesson_figures.py GUIDE.html SLUG [--out DIR] [--check]
        [--replace "OLD=NEW" ...]

    GUIDE.html  the guide's approved source, for example
                ~/myPKA/Content/2-Ready/find-my-explained/
                find-my-explained--SOURCE.html
    SLUG        the lesson slug, used as the folder name (find-my)
    --out DIR   the asset root (default assets/lesson-figures)
    --check     extract into memory and report, write nothing
    --replace   OLD=NEW: replace OLD with NEW inside figure <text> labels

Then add `- assets/lesson-figures/<slug>/` to pubspec.yaml and point the
lesson's LessonFigure blocks at `assets/lesson-figures/<slug>/fig-NN.svg`.
figures.json carries each caption in lesson markup (**bold**, __italic__,
{{UI name}}), ready to paste.

The script fails loudly (exit 1) on anything it cannot convert: a caption with
no "Figure N.", a marker on an element it cannot find the end of, a <use>
pointing nowhere. A figure is never written half-converted.
"""

from __future__ import annotations

import argparse
import copy
import html
import html.entities
import json
import math
import re
import sys
from pathlib import Path

from lxml import etree

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
NS = "{%s}" % SVG_NS

# The guide CSS's text color around a figure (body, --color-neutral-4) and
# around the cover art (.cover, --color-neutral-5). currentColor starts here.
FIGURE_COLOR = "#444444"
COVER_COLOR = "#111111"

# Presentation attributes that inherit (SVG 1.1). A marker's content inherits
# from the marker's own ancestors, never from the path it decorates, so the
# expanded copy is wrapped in a group that re-states them.
INHERITED = {
    "fill": "black",
    "fill-opacity": "1",
    "fill-rule": "nonzero",
    "stroke": "none",
    "stroke-width": "1",
    "stroke-linecap": "butt",
    "stroke-linejoin": "miter",
    "stroke-miterlimit": "4",
    "stroke-dasharray": "none",
    "stroke-dashoffset": "0",
    "stroke-opacity": "1",
    "color": None,  # resolved separately
    "font-family": None,
    "font-size": None,
    "font-weight": None,
    "text-anchor": None,
    "visibility": None,
}


class ExtractError(Exception):
    pass


# ─────────────────────────────────────────────────────────────────────────────
# HTML scanning
# ─────────────────────────────────────────────────────────────────────────────


def _balanced_div(src: str, start: int) -> int:
    """Index just past the </div> that closes the <div ...> at [start]."""
    depth = 0
    for m in re.finditer(r"<(/?)div\b[^>]*>", src[start:]):
        depth += -1 if m.group(1) else 1
        if depth == 0:
            return start + m.end()
    raise ExtractError(f"unbalanced <div> at offset {start}")


def outer_svgs(block: str) -> list[str]:
    """Every top-level <svg>...</svg> in [block], nested <svg>s kept inside
    their parent."""
    out, depth, start = [], 0, 0
    for m in re.finditer(r"<(/?)svg\b[^>]*?(/?)>", block):
        if m.group(1):
            depth -= 1
            if depth == 0:
                out.append(block[start : m.end()])
        elif not m.group(2):
            if depth == 0:
                start = m.start()
            depth += 1
    return out


# The gap between two panels of one figure: the guide's
# `.fig svg + svg { margin-top: var(--space-sm) }`, 16 CSS px, in the panels'
# own units. A figure's content box on the 210 mm page is 793.7 px less two
# 0.75 in margins (72 px each), 16 px padding each side and a 1 px border
# each side: 615.7 px.
FIG_CONTENT_PX = 615.7
PANEL_GAP_PX = 16.0


def stack_panels(panels: list[str]) -> tuple[str, str]:
    """Two or more <svg> panels drawn one above the other in one figure
    (Wi-Fi and Health, Figures 2 and 9: (a) and (b)), as one <svg> holding
    each panel as a nested <svg> at its offset. nested_svgs_to_groups then
    places each as a group. Returns the markup and a note for the log."""
    roots = [parse_svg(p) for p in panels]
    sizes = []
    for r in roots:
        vb = r.get("viewBox")
        if not vb:
            raise ExtractError("figure panel <svg> has no viewBox")
        sizes.append(tuple(float(v) for v in re.split(r"[\s,]+", vb.strip())))
    widths = {sz[2] for sz in sizes}
    if len(widths) != 1:
        raise ExtractError(f"stacked panels differ in width: {sorted(widths)}")
    w = widths.pop()
    gap = PANEL_GAP_PX * w / FIG_CONTENT_PX
    top = etree.Element(NS + "svg", nsmap={None: SVG_NS})
    y = 0.0
    labels = []
    for r, (_, _, pw, ph) in zip(roots, sizes):
        if r.get("aria-label"):
            labels.append(r.get("aria-label"))
        for k, v in (("x", "0"), ("y", fmt(y)), ("width", fmt(pw)), ("height", fmt(ph))):
            r.set(k, v)
        top.append(r)
        y += ph + gap
    top.set("viewBox", f"0 0 {fmt(w)} {fmt(y - gap)}")
    if labels:
        top.set("aria-label", " ".join(labels))
    note = (f"{len(panels)} panels stacked into one drawing, {fmt(gap)}-unit gap "
            "(16 CSS px at the printed figure's width)")
    return etree.tostring(top, encoding="unicode"), note


def find_figures(src: str) -> list[dict]:
    """Every <div class="fig ..."> block: its <svg>, caption HTML and number.
    A figure of several stacked <svg> panels is returned as one <svg>."""
    out = []
    for m in re.finditer(r'<div class="fig\b[^"]*"[^>]*>', src):
        block = src[m.start() : _balanced_div(src, m.start())]
        svgs = outer_svgs(block)
        cap = re.search(r'<(div|p) class="cap"[^>]*>(.*?)</\1>', block, re.S)
        stacked = None
        if len(svgs) > 1:
            markup, stacked = stack_panels(svgs)
            svgs = [markup]
        if len(svgs) != 1:
            raise ExtractError(
                f"figure block at {m.start()} has {len(svgs)} <svg>, expected 1"
            )
        if not cap:
            raise ExtractError(f"figure block at {m.start()} has no caption")
        caption = caption_markup(cap.group(2))
        num = re.match(r"\*\*Figure (\d+)\.", caption)
        if not num:
            raise ExtractError(f'caption does not start "Figure N.": {caption!r}')
        out.append({"n": int(num.group(1)), "svg": svgs[0], "caption": caption,
                    "stacked": stacked})
    numbers = [f["n"] for f in out]
    if numbers != list(range(1, len(out) + 1)):
        raise ExtractError(f"figure numbers are not 1..{len(out)}: {numbers}")
    return out


def find_cover(src: str) -> str | None:
    m = re.search(r'<div class="art">\s*(?=<svg\b)', src)
    if not m:
        return None
    svgs = outer_svgs(src[m.end() :])
    return svgs[0] if svgs else None


def root_vars(src: str) -> dict[str, str]:
    """The guide CSS's :root custom properties, var() references resolved."""
    raw: dict[str, str] = {}
    for block in re.findall(r":root\s*\{([^}]*)\}", src):
        for name, value in re.findall(r"(--[\w-]+)\s*:\s*([^;]+)", block):
            raw[name] = value.strip()

    def resolve(v: str, seen=()) -> str:
        def sub(m: re.Match) -> str:
            n = m.group(1)
            if n in seen or n not in raw:
                if m.group(2):
                    return resolve(m.group(2).strip(), seen)
                raise ExtractError(f"var({n}) is not defined in :root")
            return resolve(raw[n], seen + (n,))

        return re.sub(r"var\(\s*(--[\w-]+)\s*(?:,\s*([^)]*))?\)", sub, v)

    return {k: resolve(v) for k, v in raw.items()}


def find_sprite(src: str) -> dict[str, str]:
    """id -> markup of every marker and symbol in the page sprite."""
    out: dict[str, str] = {}
    for m in re.finditer(r'<svg class="xsprite"[^>]*>', src):
        root = parse_svg(outer_svgs(src[m.start() :])[0])
        for el in root.iter():
            if isinstance(el.tag, str) and local(el) in ("marker", "symbol") and el.get("id"):
                out[el.get("id")] = etree.tostring(el, encoding="unicode")
    return out


def caption_markup(fragment: str) -> str:
    """Caption HTML to lesson markup: **bold**, __italic__, {{UI name}}."""
    s = re.sub(r'<span class="path">(.*?)</span>', r"{{\1}}", fragment, flags=re.S)
    s = re.sub(r"<(b|strong)\b[^>]*>(.*?)</\1>", r"**\2**", s, flags=re.S)
    s = re.sub(r"<(i|em)\b[^>]*>(.*?)</\1>", r"__\2__", s, flags=re.S)
    s = re.sub(r"<br\s*/?>", " ", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip()


def plain(markup: str) -> str:
    return re.sub(r"\*\*|__|\{\{|\}\}", "", markup)


# ─────────────────────────────────────────────────────────────────────────────
# SVG parsing helpers
# ─────────────────────────────────────────────────────────────────────────────

_XML_ENTITIES = {"amp", "lt", "gt", "quot", "apos"}


def _entities_to_numeric(s: str) -> str:
    def sub(m: re.Match) -> str:
        name = m.group(1)
        if name in _XML_ENTITIES:
            return m.group(0)
        cp = html.entities.name2codepoint.get(name)
        if cp is None:
            raise ExtractError(f"unknown entity &{name};")
        return f"&#{cp};"

    return re.sub(r"&([A-Za-z][A-Za-z0-9]*);", sub, s)


def _first_attribute_wins(markup: str) -> str:
    """Drop any attribute a start tag repeats, keeping the first, which is
    what an HTML parser does with the guide's own markup."""

    def tag(m: re.Match) -> str:
        seen: set[str] = set()

        def attr(a: re.Match) -> str:
            if a.group(2) in seen:
                return ""
            seen.add(a.group(2))
            return a.group(0)

        return re.sub(r'(\s+)([\w:.-]+)="[^"]*"', attr, m.group(0))

    return re.sub(r"<[A-Za-z][^<>]*>", tag, markup)


def parse_svg(markup: str) -> etree._Element:
    markup = _first_attribute_wins(markup)
    if "xmlns=" not in markup.split(">", 1)[0]:
        markup = markup.replace("<svg", f'<svg xmlns="{SVG_NS}"', 1)
    try:
        return etree.fromstring(_entities_to_numeric(markup).encode("utf-8"))
    except etree.XMLSyntaxError as e:
        raise ExtractError(f"SVG does not parse as XML: {e}") from e


def local(el: etree._Element) -> str:
    return etree.QName(el).localname if isinstance(el.tag, str) else ""


def num(v: str | None, default: float = 0.0) -> float:
    if v is None or v == "":
        return default
    m = re.match(r"\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)", v)
    if not m:
        raise ExtractError(f"not a number: {v!r}")
    return float(m.group(1))


def inherited(el: etree._Element, name: str) -> str | None:
    e = el
    while e is not None:
        v = e.get(name)
        if v is not None and v != "inherit":
            return v
        e = e.getparent()
    return None


def fmt(v: float) -> str:
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ─────────────────────────────────────────────────────────────────────────────
# Path geometry: start and end points and tangents, for marker placement.
# ─────────────────────────────────────────────────────────────────────────────

_CMD = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
_ARGS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def path_segments(d: str) -> list[tuple[str, list[tuple[float, float]]]]:
    """Absolute segments as (kind, points): each segment's point list starts
    at its start point and ends at its end point, with control points between.
    Arcs are recorded as ("A", [start, end]); their end tangent is taken from
    the chord, which is what the guides' few arcs need (none carry markers)."""
    toks = _CMD.findall(d)
    i, cmd = 0, None
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    last_ctrl = None
    segs: list[tuple[str, list[tuple[float, float]]]] = []

    def take(n: int) -> list[float]:
        nonlocal i
        vals = [float(t) for t in toks[i : i + n]]
        if len(vals) != n or any(re.match(r"[A-Za-z]", t) for t in toks[i : i + n]):
            raise ExtractError(f"bad path data near token {i}: {d[:80]!r}")
        i += n
        return vals

    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
        elif cmd is None:
            raise ExtractError(f"path data does not start with a command: {d[:40]!r}")
        up = cmd.upper()
        rel = cmd != up
        if up == "Z":
            if cur != start:
                segs.append(("L", [cur, start]))
            cur = start
            last_ctrl = None
            continue
        a = take(_ARGS[up])
        ox, oy = cur if rel else (0.0, 0.0)
        if up == "M":
            cur = start = (a[0] + ox, a[1] + oy)
            cmd = "l" if rel else "L"  # implicit lineto after moveto
            last_ctrl = None
        elif up == "L" or up == "T":
            p = (a[0] + ox, a[1] + oy)
            segs.append(("L", [cur, p]))
            cur, last_ctrl = p, None
        elif up == "H":
            p = (a[0] + ox if rel else a[0], cur[1])
            segs.append(("L", [cur, p]))
            cur, last_ctrl = p, None
        elif up == "V":
            p = (cur[0], a[0] + oy if rel else a[0])
            segs.append(("L", [cur, p]))
            cur, last_ctrl = p, None
        elif up == "C":
            c1 = (a[0] + ox, a[1] + oy)
            c2 = (a[2] + ox, a[3] + oy)
            p = (a[4] + ox, a[5] + oy)
            segs.append(("C", [cur, c1, c2, p]))
            cur, last_ctrl = p, c2
        elif up == "S":
            c1 = (2 * cur[0] - last_ctrl[0], 2 * cur[1] - last_ctrl[1]) if last_ctrl else cur
            c2 = (a[0] + ox, a[1] + oy)
            p = (a[2] + ox, a[3] + oy)
            segs.append(("C", [cur, c1, c2, p]))
            cur, last_ctrl = p, c2
        elif up == "Q":
            c = (a[0] + ox, a[1] + oy)
            p = (a[2] + ox, a[3] + oy)
            segs.append(("Q", [cur, c, p]))
            cur, last_ctrl = p, None
        elif up == "A":
            p = (a[5] + ox, a[6] + oy)
            segs.append(("A", [cur, p]))
            cur, last_ctrl = p, None
    return segs


def _direction(pts: list[tuple[float, float]], at_end: bool) -> float:
    """Tangent angle (radians) at the end (or start) of one segment: the first
    control point that differs from the endpoint, per the SVG marker rules."""
    seq = pts if not at_end else list(reversed(pts))
    p0 = seq[0]
    for q in seq[1:]:
        if abs(q[0] - p0[0]) > 1e-9 or abs(q[1] - p0[1]) > 1e-9:
            ang = math.atan2(q[1] - p0[1], q[0] - p0[0])
            return ang + math.pi if at_end else ang
    return 0.0


def element_ends(el: etree._Element):
    """((start point, start angle), (end point, end angle)) of a shape."""
    kind = local(el)
    if kind == "line":
        a = (num(el.get("x1")), num(el.get("y1")))
        b = (num(el.get("x2")), num(el.get("y2")))
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        return (a, ang), (b, ang)
    if kind in ("polyline", "polygon"):
        vals = [float(v) for v in re.findall(r"[-+]?(?:\d+\.?\d*|\.\d+)", el.get("points", ""))]
        pts = list(zip(vals[0::2], vals[1::2]))
        if len(pts) < 2:
            raise ExtractError("polyline with fewer than two points carries a marker")
        return (pts[0], _direction(pts[:2], False)), (pts[-1], _direction(pts[-2:], True))
    if kind == "path":
        segs = [s for s in path_segments(el.get("d", "")) if s[1][0] != s[1][-1]]
        if not segs:
            raise ExtractError("path with no drawn segment carries a marker")
        first, last = segs[0][1], segs[-1][1]
        return (first[0], _direction(first, False)), (last[-1], _direction(last, True))
    raise ExtractError(f"marker on unsupported element <{kind}>")


# ─────────────────────────────────────────────────────────────────────────────
# Rewrites
# ─────────────────────────────────────────────────────────────────────────────


def _ids(root: etree._Element) -> dict[str, etree._Element]:
    return {el.get("id"): el for el in root.iter() if isinstance(el.tag, str) and el.get("id")}


def _ref(value: str | None) -> str | None:
    if not value:
        return None
    m = re.fullmatch(r"\s*url\(\s*#([^)\s]+)\s*\)\s*", value) or re.fullmatch(r"#(.+)", value)
    return m.group(1) if m else None


def inline_uses(root: etree._Element) -> int:
    ids = _ids(root)
    n = 0
    for use in list(root.iter(NS + "use")):
        ref = _ref(use.get("href") or use.get("{%s}href" % XLINK_NS))
        target = ids.get(ref) if ref else None
        if target is None:
            raise ExtractError(f"<use> points at a missing id: {ref!r}")
        g = etree.Element(NS + "g")
        for k, v in use.attrib.items():
            if k in ("x", "y", "href", "{%s}href" % XLINK_NS, "width", "height"):
                continue
            g.set(k, v)
        tx, ty = num(use.get("x")), num(use.get("y"))
        t = use.get("transform", "")
        if tx or ty:
            t = (t + " " if t else "") + f"translate({fmt(tx)},{fmt(ty)})"
        if t:
            g.set("transform", t)
        clone = copy.deepcopy(target)
        for el in clone.iter():
            if isinstance(el.tag, str) and "id" in el.attrib:
                del el.attrib["id"]
        if local(clone) == "symbol":
            clone.tag = NS + "g"
            vb = clone.attrib.pop("viewBox", None)
            if vb and use.get("width") and use.get("height"):
                fit = _viewbox_fit(vb, num(use.get("width")), num(use.get("height")))
                if fit:
                    clone.set("transform", fit)
        g.append(clone)
        use.getparent().replace(use, g)
        n += 1
    return n


def _viewbox_fit(viewbox: str, w: float, h: float) -> str | None:
    """The transform that draws [viewbox] into a w x h box at the origin, per
    the default preserveAspectRatio, xMidYMid meet."""
    vx, vy, vw, vh = (float(v) for v in re.split(r"[\s,]+", viewbox.strip()))
    s = min(w / vw, h / vh)
    ox = (w - vw * s) / 2 - vx * s
    oy = (h - vh * s) / 2 - vy * s
    parts = []
    if abs(ox) > 1e-9 or abs(oy) > 1e-9:
        parts.append(f"translate({fmt(ox)},{fmt(oy)})")
    if abs(s - 1) > 1e-9:
        parts.append(f"scale({fmt(s)})")
    return " ".join(parts) or None


def nested_svgs_to_groups(root: etree._Element) -> int:
    """A nested <svg x y width height viewBox> (an embedded icon) becomes a
    group translated to x, y and scaled into its box. It keeps every other
    attribute. The viewport clip is not reproduced: the icons draw inside
    their own viewBox."""
    n = 0
    for el in list(root.iter(NS + "svg")):
        if el is root:
            continue
        x, y = num(el.get("x")), num(el.get("y"))
        parts = []
        if x or y:
            parts.append(f"translate({fmt(x)},{fmt(y)})")
        vb = el.get("viewBox")
        if vb and el.get("width") and el.get("height"):
            fit = _viewbox_fit(vb, num(el.get("width")), num(el.get("height")))
            if fit:
                parts.append(fit)
        for k in ("x", "y", "width", "height", "viewBox", "preserveAspectRatio"):
            el.attrib.pop(k, None)
        el.tag = NS + "g"
        if parts:
            el.set("transform", " ".join(parts))
        n += 1
    return n


# Style declarations that map to an SVG presentation attribute of the same
# name. Anything else in a style attribute (width, display) is layout for the
# PDF page and is dropped.
_PRESENTATION = {
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width",
    "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
    "stroke-dasharray", "stroke-dashoffset", "stroke-opacity", "opacity",
    "color", "font-family", "font-size", "font-weight", "font-style",
    "text-anchor", "letter-spacing", "visibility", "stop-color",
    "stop-opacity", "dominant-baseline",
}


def apply_page_css(root: etree._Element, variables: dict[str, str]) -> int:
    """Style attributes to presentation attributes, var() resolved, plus the
    figure kit's two font rules (.xf text, .xf .mono)."""
    n = 0

    def resolve(v: str) -> str:
        def sub(m: re.Match) -> str:
            if m.group(1) in variables:
                return variables[m.group(1)]
            if m.group(2):
                return m.group(2).strip()
            raise ExtractError(f"var({m.group(1)}) is not defined in :root")

        return re.sub(r"var\(\s*(--[\w-]+)\s*(?:,\s*([^)]*))?\)", sub, v)

    kit = "xf" in (root.get("class") or "").split()
    if kit and not root.get("font-family"):
        root.set("font-family", "IBM Plex Sans")
    for el in root.iter():
        if not isinstance(el.tag, str):
            continue
        if kit and "mono" in (el.get("class") or "").split() and not el.get("font-family"):
            el.set("font-family", "DM Mono")
        style = el.attrib.pop("style", None)
        if style:
            for decl in style.split(";"):
                if ":" not in decl:
                    continue
                name, value = (t.strip() for t in decl.split(":", 1))
                if name in _PRESENTATION:
                    value = resolve(value)
                    if name == "font-size":
                        value = re.sub(r"px$", "", value)
                    el.set(name, value)
                    n += 1
        for k, v in list(el.attrib.items()):
            if "var(" in v:
                el.set(k, resolve(v))
                n += 1
    return n


def bring_in_sprite(root: etree._Element, sprite: dict[str, str]) -> int:
    """Copy each page-sprite marker or symbol the figure points at (and any
    they point at in turn) into the figure's own <defs>."""
    have = set(_ids(root))
    n = 0
    while True:
        wanted = set()
        for el in root.iter():
            if not isinstance(el.tag, str):
                continue
            for k, v in el.attrib.items():
                if k in ("href", "{%s}href" % XLINK_NS) or k.startswith("marker"):
                    r = _ref(v)
                    if r and r not in have and r in sprite:
                        wanted.add(r)
        if not wanted:
            return n
        defs = root.find(NS + "defs")
        if defs is None:
            defs = etree.Element(NS + "defs")
            root.insert(0, defs)
        for r in sorted(wanted):
            defs.append(parse_svg(sprite[r]))
            have.add(r)
            n += 1


def _marker_context(marker: etree._Element) -> dict[str, str]:
    """The inheritable properties a marker's content sees: its own and its
    ancestors' attributes, else the SVG initial value."""
    out = {}
    for name, initial in INHERITED.items():
        v = inherited(marker, name)
        if v is None:
            v = initial
        if v is not None:
            out[name] = v
    return out


# Every id="..." in the guide being extracted: an arrowhead reference to an
# id that exists somewhere must still fail loudly if it cannot be resolved.
_GUIDE_IDS: set[str] = set()


def expand_markers(root: etree._Element, notes: list[str] | None = None,
                   where: str = "") -> int:
    ids = _ids(root)
    n = 0
    for el in list(root.iter()):
        if not isinstance(el.tag, str):
            continue
        for attr, at_end in (("marker-start", False), ("marker-end", True)):
            ref = _ref(el.get(attr))
            if el.get(attr) is None:
                continue
            del el.attrib[attr]
            if ref is None:  # "none"
                continue
            marker = ids.get(ref)
            if marker is None and notes is not None and ref not in _GUIDE_IDS:
                # No element anywhere in the guide has this id (Satellite
                # Texting, Figure 3, 'ah-8A5A00'), so the PDF draws no
                # arrowhead here either. Match it, and say so.
                notes.append(f"{where}: WARNING {attr} points at {ref!r}, which the guide "
                             "never defines; the PDF draws no arrowhead there, nor does the lesson")
                continue
            if marker is None or local(marker) != "marker":
                raise ExtractError(f"{attr} points at a missing marker: {ref!r}")
            (sp, sa), (ep, ea) = element_ends(el)
            point, angle = (ep, ea) if at_end else (sp, sa)
            orient = marker.get("orient", "0")
            if orient == "auto":
                deg = math.degrees(angle)
            elif orient == "auto-start-reverse":
                deg = math.degrees(angle) + (0 if at_end else 180)
            else:
                deg = num(orient)
            units = marker.get("markerUnits", "strokeWidth")
            k = num(inherited(el, "stroke-width"), 1.0) if units == "strokeWidth" else 1.0
            mw = num(marker.get("markerWidth"), 3.0)
            mh = num(marker.get("markerHeight"), 3.0)
            s = 1.0
            vb = marker.get("viewBox")
            if vb:
                _, _, vw, vh = (float(v) for v in re.split(r"[\s,]+", vb.strip()))
                s = min(mw / vw, mh / vh)
            rx, ry = num(marker.get("refX")), num(marker.get("refY"))
            g = etree.Element(NS + "g")
            for name, value in _marker_context(marker).items():
                g.set(name, value)
            parts = []
            if el.get("transform"):
                parts.append(el.get("transform"))
            parts.append(f"translate({fmt(point[0])},{fmt(point[1])})")
            if abs(deg) > 1e-9:
                parts.append(f"rotate({fmt(deg)})")
            if abs(k * s - 1) > 1e-9:
                parts.append(f"scale({fmt(k * s)})")
            if rx or ry:
                parts.append(f"translate({fmt(-rx)},{fmt(-ry)})")
            g.set("transform", " ".join(parts))
            for child in marker:
                c = copy.deepcopy(child)
                for d in c.iter():
                    if isinstance(d.tag, str) and "id" in d.attrib:
                        del d.attrib["id"]
                g.append(c)
            el.addnext(g)
            n += 1
    for marker in list(root.iter(NS + "marker")):
        marker.getparent().remove(marker)
    return n


def drop_symbols(root: etree._Element) -> None:
    """A <symbol> never draws on its own; once every <use> is inlined it is
    dead weight flutter_svg would trip on."""
    for sym in list(root.iter(NS + "symbol")):
        sym.getparent().remove(sym)


def resolve_current_color(root: etree._Element, base: str) -> int:
    n = 0

    def walk(el: etree._Element, color: str) -> None:
        nonlocal n
        c = el.get("color")
        if c and c not in ("inherit", "currentColor"):
            color = c
        for name in ("fill", "stroke", "stop-color"):
            if el.get(name) == "currentColor":
                el.set(name, color)
                n += 1
        if "color" in el.attrib:
            del el.attrib["color"]
        for child in el:
            if isinstance(child.tag, str):
                walk(child, color)

    walk(root, base)
    return n


def tidy(root: etree._Element) -> None:
    referenced = set()
    for el in root.iter():
        if not isinstance(el.tag, str):
            continue
        for v in el.attrib.values():
            r = re.findall(r"url\(\s*#([^)\s]+)\s*\)", v)
            referenced.update(r)
    for el in root.iter():
        if not isinstance(el.tag, str):
            continue
        for k in list(el.attrib):
            if k in ("class", "role", "overflow") or k.startswith(("aria-", "data-")):
                del el.attrib[k]
            elif k == "id" and el.get("id") not in referenced:
                del el.attrib[k]
        ff = el.get("font-family")
        if ff:
            el.set("font-family", ff.split(",")[0].strip().strip("'\""))
    for d in list(root.iter(NS + "defs")):
        if len(d) == 0:
            d.getparent().remove(d)


def replace_labels(root, replacements: list[tuple[str, str]], where: str) -> list[str]:
    """Apply --replace pairs to <text>/<tspan> content; warn on any printed
    page reference left."""
    notes = []
    for el in root.iter():
        if not isinstance(el.tag, str) or local(el) not in ("text", "tspan"):
            continue
        for attr in ("text", "tail") if local(el) == "tspan" else ("text",):
            v = getattr(el, attr)
            if not v:
                continue
            for old, new in replacements:
                if old in v:
                    v = v.replace(old, new)
                    notes.append(f"{where}: label {old!r} -> {new!r}")
            setattr(el, attr, v)
            if re.search(r"\bpages? \d", v):
                notes.append(f"{where}: WARNING printed page reference left in label {v.strip()!r}")
    return notes


def convert(
    markup: str,
    base_color: str,
    replacements=(),
    where="",
    variables: dict[str, str] | None = None,
    sprite: dict[str, str] | None = None,
) -> tuple[str, dict]:
    root = parse_svg(markup)
    notes = replace_labels(root, list(replacements), where)
    alt = root.get("aria-label")
    vb = root.get("viewBox")
    if not vb:
        raise ExtractError("figure <svg> has no viewBox")
    _, _, w, h = (float(v) for v in re.split(r"[\s,]+", vb.strip()))
    brought = bring_in_sprite(root, sprite or {})
    styled = apply_page_css(root, variables or {})
    nested = nested_svgs_to_groups(root)
    uses = inline_uses(root)
    drop_symbols(root)
    markers = expand_markers(root, notes, where)
    colors = resolve_current_color(root, base_color)
    tidy(root)
    # The same numbers, written the one way the lesson data writes them
    # (Wi-Fi and Health, Figure 4, has viewBox="0 0 760 384.0").
    root.set("viewBox", " ".join(fmt(float(v)) for v in re.split(r"[\s,]+", vb.strip())))
    root.set("width", fmt(w))
    root.set("height", fmt(h))
    for leftover in ("marker", "use", "symbol"):
        if root.find(".//" + NS + leftover) is not None:
            raise ExtractError(f"<{leftover}> left after conversion")
    if "currentColor" in etree.tostring(root, encoding="unicode"):
        raise ExtractError("currentColor left after conversion")
    etree.cleanup_namespaces(root)
    out = etree.tostring(root, encoding="unicode")
    return out + "\n", {
        "viewBox": [w, h],
        "ariaLabel": alt,
        "markersExpanded": markers,
        "usesInlined": uses,
        "currentColorResolved": colors,
        "spriteCopied": brought,
        "styleResolved": styled,
        "nestedSvgs": nested,
        "notes": notes,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────


def extract(guide: Path, slug: str, replacements=()) -> tuple[dict[str, str], list[dict]]:
    src = guide.read_text(encoding="utf-8")
    files: dict[str, str] = {}
    manifest: list[dict] = []
    variables = root_vars(src)
    sprite = find_sprite(src)
    _GUIDE_IDS.clear()
    _GUIDE_IDS.update(re.findall(r'\bid="([^"]+)"', src))
    cover = find_cover(src)
    if cover:
        svg, info = convert(cover, COVER_COLOR, replacements, "cover", variables, sprite)
        files["cover.svg"] = svg
        manifest.append({"n": 0, "file": "cover.svg", "caption": None, "alt": info["ariaLabel"], **info})
    for f in find_figures(src):
        name = f"fig-{f['n']:02d}.svg"
        try:
            svg, info = convert(
                f["svg"], FIGURE_COLOR, replacements, f"Figure {f['n']}", variables, sprite
            )
        except ExtractError as e:
            raise ExtractError(f"Figure {f['n']}: {e}") from e
        if f.get("stacked"):
            info["notes"].insert(0, f"Figure {f['n']}: {f['stacked']}")
        files[name] = svg
        manifest.append(
            {
                "n": f["n"],
                "file": name,
                "caption": f["caption"],
                "alt": info["ariaLabel"] or plain(f["caption"]),
                **info,
            }
        )
    return files, manifest


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("guide", type=Path)
    ap.add_argument("slug")
    ap.add_argument("--out", type=Path, default=Path("assets/lesson-figures"))
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--replace", action="append", default=[], metavar="OLD=NEW")
    a = ap.parse_args(argv)
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", a.slug):
        print(f"slug must be lowercase-hyphenated: {a.slug!r}", file=sys.stderr)
        return 1
    pairs = []
    for r in a.replace:
        if "=" not in r:
            print(f"--replace needs OLD=NEW: {r!r}", file=sys.stderr)
            return 1
        pairs.append(tuple(r.split("=", 1)))
    try:
        files, manifest = extract(a.guide, a.slug, pairs)
    except ExtractError as e:
        print(f"extract_lesson_figures: {a.guide.name}: {e}", file=sys.stderr)
        return 1
    figs = sum(1 for m in manifest if m["n"])
    markers = sum(m["markersExpanded"] for m in manifest)
    uses = sum(m["usesInlined"] for m in manifest)
    extra = ""
    for key, label in (
        ("spriteCopied", "sprite defs copied in"),
        ("styleResolved", "style/var() declarations resolved"),
        ("nestedSvgs", "nested <svg> made groups"),
    ):
        total = sum(m[key] for m in manifest)
        if total:
            extra += f", {total} {label}"
    print(
        f"{a.slug}: {figs} figures{' + cover' if 'cover.svg' in files else ''}, "
        f"{markers} arrowheads expanded, {uses} <use> inlined{extra}"
    )
    for m in manifest:
        for n in m["notes"]:
            print(f"  {n}")
    if a.check:
        return 0
    out = a.out / a.slug
    out.mkdir(parents=True, exist_ok=True)
    for name, svg in files.items():
        (out / name).write_text(svg, encoding="utf-8")
    (out / "figures.json").write_text(
        json.dumps(
            {
                "source": a.guide.name,
                "figures": [
                    {k: m[k] for k in ("n", "file", "viewBox", "caption", "alt")}
                    for m in manifest
                ],
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(files)} SVGs and figures.json to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
