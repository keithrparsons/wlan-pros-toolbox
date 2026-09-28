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
  * class, role, aria-* and id attributes that nothing references: dropped.
  * a valueless HTML data attribute (`<g data-nocheck>`, a build-check
    marker) is legal HTML and illegal XML; it is dropped before parsing.

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
    --symbols FILE  an HTML or SVG file holding <symbol id="..."> definitions
                for a guide whose figures <use> an id the guide never defines
                (its sprite was lost in a rebuild). Only ids missing from the
                guide are taken from FILE, and each one is printed per figure;
                put them in your report. Without it, such a <use> stops the
                script.

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


def find_figures(src: str) -> list[dict]:
    """Every <div class="fig ..."> block: its <svg>, caption HTML and number."""
    out = []
    for m in re.finditer(r'<div class="fig\b[^"]*"[^>]*>', src):
        block = src[m.start() : _balanced_div(src, m.start())]
        svgs = re.findall(r"<svg\b.*?</svg>", block, re.S)
        cap = re.search(r'<(div|p) class="cap"[^>]*>(.*?)</\1>', block, re.S)
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
        out.append({"n": int(num.group(1)), "svg": svgs[0], "caption": caption})
    numbers = [f["n"] for f in out]
    if numbers != list(range(1, len(out) + 1)):
        raise ExtractError(f"figure numbers are not 1..{len(out)}: {numbers}")
    return out


def find_cover(src: str) -> str | None:
    # The cover art's div may carry attributes (data-op="1" on some guides).
    m = re.search(r'<div class="art"[^>]*>\s*(<svg\b.*?</svg>)', src, re.S)
    return m.group(1) if m else None


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


_VALUELESS_DATA_ATTR = re.compile(r"(<[^<>]*?)\s+data-[\w-]+(?=[\s/>])(?!\s*=)")


def _drop_valueless_data_attrs(markup: str) -> str:
    """`<g data-nocheck>` is HTML, not XML. Drop every valueless data-*
    attribute (repeat until none is left: a tag may carry two)."""
    while True:
        new = _VALUELESS_DATA_ATTR.sub(r"\1", markup)
        if new == markup:
            return new
        markup = new


def parse_svg(markup: str) -> etree._Element:
    if "xmlns=" not in markup.split(">", 1)[0]:
        markup = markup.replace("<svg", f'<svg xmlns="{SVG_NS}"', 1)
    markup = _drop_valueless_data_attrs(markup)
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


def load_symbols(path: Path) -> dict[str, etree._Element]:
    """Every <symbol id="..."> in an HTML or SVG file, parsed as SVG."""
    src = path.read_text(encoding="utf-8")
    out: dict[str, etree._Element] = {}
    for m in re.finditer(r'<symbol\b[^>]*\bid="([^"]+)"[^>]*>.*?</symbol>', src, re.S):
        wrapped = f'<svg xmlns="{SVG_NS}">{m.group(0)}</svg>'
        out[m.group(1)] = parse_svg(wrapped)[0]
    if not out:
        raise ExtractError(f"--symbols {path.name}: no <symbol id=...> found")
    return out


def inline_uses(root: etree._Element, symbols=None, notes=None, where="") -> int:
    ids = _ids(root)
    n = 0
    supplied: set[str] = set()
    for use in list(root.iter(NS + "use")):
        ref = _ref(use.get("href") or use.get("{%s}href" % XLINK_NS))
        target = ids.get(ref) if ref else None
        if target is None and ref and symbols and ref in symbols:
            target = symbols[ref]
            supplied.add(ref)
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
        clone = copy.deepcopy(target)
        for el in clone.iter():
            if isinstance(el.tag, str) and "id" in el.attrib:
                del el.attrib["id"]
        if local(clone) == "symbol":
            vb = clone.attrib.pop("viewBox", None)
            par = clone.attrib.pop("preserveAspectRatio", "xMidYMid meet").split()
            clone.tag = NS + "g"
            uw, uh = use.get("width"), use.get("height")
            if vb and uw is not None and uh is not None:
                # SVG 2 §5.6.1: the <use> width/height is the symbol's
                # viewport, and its viewBox maps into it per
                # preserveAspectRatio (default xMidYMid meet).
                vx, vy, vw, vh = (float(v) for v in re.split(r"[\s,]+", vb.strip()))
                w, h = num(uw), num(uh)
                align = par[0] if par else "xMidYMid"
                if align == "none":
                    sx, sy, ox, oy = w / vw, h / vh, 0.0, 0.0
                elif align == "xMidYMid" and (len(par) < 2 or par[1] == "meet"):
                    sx = sy = min(w / vw, h / vh)
                    ox, oy = (w - vw * sx) / 2, (h - vh * sy) / 2
                else:
                    raise ExtractError(f"<symbol> preserveAspectRatio {' '.join(par)!r} not supported")
                t = (t + " " if t else "") + (
                    f"translate({fmt(ox - vx * sx)},{fmt(oy - vy * sy)}) "
                    f"scale({fmt(sx)}" + ("" if sx == sy else f",{fmt(sy)}") + ")"
                )
        if t:
            g.set("transform", t)
        g.append(clone)
        use.getparent().replace(use, g)
        n += 1
    if supplied and notes is not None:
        notes.append(
            f"{where}: <symbol> not in the guide, taken from --symbols: "
            + ", ".join(sorted(supplied))
        )
    return n


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


def expand_markers(root: etree._Element) -> int:
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
            if k in ("class", "role", "overflow") or k.startswith("aria-"):
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


def convert(markup: str, base_color: str, replacements=(), where="", symbols=None) -> tuple[str, dict]:
    root = parse_svg(markup)
    notes = replace_labels(root, list(replacements), where)
    alt = root.get("aria-label")
    vb = root.get("viewBox")
    if not vb:
        raise ExtractError("figure <svg> has no viewBox")
    _, _, w, h = (float(v) for v in re.split(r"[\s,]+", vb.strip()))
    uses = inline_uses(root, symbols, notes, where)
    markers = expand_markers(root)
    colors = resolve_current_color(root, base_color)
    tidy(root)
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
        "notes": notes,
    }


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────


def extract(guide: Path, slug: str, replacements=(), symbols=None) -> tuple[dict[str, str], list[dict]]:
    src = guide.read_text(encoding="utf-8")
    files: dict[str, str] = {}
    manifest: list[dict] = []
    cover = find_cover(src)
    if cover:
        svg, info = convert(cover, COVER_COLOR, replacements, "cover", symbols)
        files["cover.svg"] = svg
        manifest.append({"n": 0, "file": "cover.svg", "caption": None, "alt": info["ariaLabel"], **info})
    for f in find_figures(src):
        name = f"fig-{f['n']:02d}.svg"
        try:
            svg, info = convert(f["svg"], FIGURE_COLOR, replacements, f"Figure {f['n']}", symbols)
        except ExtractError as e:
            raise ExtractError(f"Figure {f['n']}: {e}") from e
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
    ap.add_argument("--symbols", type=Path, metavar="FILE")
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
        symbols = load_symbols(a.symbols) if a.symbols else None
        files, manifest = extract(a.guide, a.slug, pairs, symbols)
    except ExtractError as e:
        print(f"extract_lesson_figures: {a.guide.name}: {e}", file=sys.stderr)
        return 1
    figs = sum(1 for m in manifest if m["n"])
    markers = sum(m["markersExpanded"] for m in manifest)
    uses = sum(m["usesInlined"] for m in manifest)
    print(
        f"{a.slug}: {figs} figures{' + cover' if 'cover.svg' in files else ''}, "
        f"{markers} arrowheads expanded, {uses} <use> inlined"
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
