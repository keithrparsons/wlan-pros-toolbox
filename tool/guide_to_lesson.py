#!/usr/bin/env python3
"""Turn an explainer guide's approved HTML into a Guided Lesson data file.

Writes lib/screens/tools/reference/lessons/<slug>_lesson.dart: one const
GuidedLesson (lib/widgets/lesson/guided_lesson.dart) holding the guide's text
WORD FOR WORD, section by section. Run tool/extract_lesson_figures.py first;
this script reads the same guide for the figures and points each LessonFigure
at assets/lesson-figures/<slug>/fig-NN.svg with the figure's own caption.

    python3 tool/guide_to_lesson.py GUIDE.html SLUG --name kFindMyLesson \\
        --tool-id find-my-explained --route /tools/find-my-explained

What the lesson leaves out, because it only makes sense on paper: the cover
page layout, the contents list ("What's inside"), page footers, and the
small eyebrow over each section. Everything else carries over:

  guide                         lesson
  h2                            a new LessonStep (1, 2 ...; "Appendix" -> A,
                                "Appendix A/B" -> A/B; "Sources" -> arrow)
  p.lede / p / p.small          LessonLede / LessonText / LessonText(small)
  h3                            LessonHeading
  div.fig                       LessonFigure (extracted SVG + caption)
  div.callout[.caution/.danger/.quote]  LessonCallout.note/caution/stop/quote
    (also a bare div.note / .caution / .danger / .quote; title from b.t or
    p.ct; a quote's source line from .who, .attr or its p.small, optional;
    a div.note holding a .q is a quote, its .who the speaker)
  div.myth                      LessonMyth (tap to reveal)
  ol.steps / ul / ul.src(-list) LessonSteps / LessonBullets / LessonSourceList
  ul.tips (li: <b>lead</b>rest) LessonCards, one per tip
  div.two/.three/.cards of .card  LessonCards (title from h3 or b.t)
  div.task (h3 or b.t title)    LessonTask

Inline: <b> -> **bold**, <i> -> __italic__, <span class="path"> and
<span class="ui"> -> {{UI name}}. A quotation's title gets its first letter
capitalized, as the guide's CSS (::first-letter) shows it.

ACTUAL SIZE. A figure drawn to print at actual size (<svg class="actual">)
is not actual size on a screen. When the step's own text says the figure is
at actual size, its caption gets " (actual size on the printed guide)"
appended (Keith, 2026-09-28), and the change is printed with the page ones.

SIBLING LESSONS. --link TOOL_ID="Guide Title, Explained" puts an Open button
(LessonToolLink) after every block that names that guide in italics, in the
order the block names them. The button shows only once TOOL_ID is a live
catalog entry, so a sibling still being built can be linked ahead of time.
No text changes.

THE ONE TEXT CHANGE. A reference to a printed page ("(page 10)", "on page
11") cannot work in a lesson, so it becomes the lesson step that carries that
page ("(step 9)", "in step 10"). Every such change is printed; put them in
your report. Nothing else is reworded. Anything the script does not
recognize stops it (exit 1) rather than being dropped.
"""

from __future__ import annotations

import argparse
import copy
import html
import json
import re
import sys
from pathlib import Path

from lxml import html as lhtml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_lesson_figures as X  # noqa: E402


class ConvertError(Exception):
    pass


def classes(el) -> set[str]:
    return set((el.get("class") or "").split())


# ─────────────────────────────────────────────────────────────────────────────
# Inline text
# ─────────────────────────────────────────────────────────────────────────────


def inline(el, skip=lambda e: False) -> str:
    """The element's inline content as lesson markup."""
    out: list[str] = []
    if el.text:
        out.append(el.text)
    for c in el:
        if not skip(c):
            tag = c.tag if isinstance(c.tag, str) else ""
            inner = inline(c, skip)
            if tag in ("b", "strong"):
                out.append(f"**{inner}**" if inner.strip() else inner)
            elif tag in ("i", "em"):
                out.append(f"__{inner}__" if inner.strip() else inner)
            elif tag == "span" and classes(c) & {"path", "ui"}:
                out.append("{{" + inner.strip() + "}}")
            elif tag == "br":
                out.append(" ")
            elif tag in ("span", "q", "sub", "sup", "a", ""):
                out.append(inner)
            else:
                raise ConvertError(f"unexpected <{tag}> inside text: {lhtml.tostring(c)[:120]!r}")
        if c.tail:
            out.append(c.tail)
    s = "".join(out)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def cap_first(s: str) -> str:
    return s[:1].upper() + s[1:] if s else s


# ─────────────────────────────────────────────────────────────────────────────
# Dart emission
# ─────────────────────────────────────────────────────────────────────────────


def dstr(s: str, indent: int) -> str:
    """A Dart single-quoted string literal, split into adjacent literals so
    each source line stays short. Adjacent literals concatenate exactly."""
    esc = s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    width = max(30, 76 - indent)
    if len(esc) + 2 <= width:
        return f"'{esc}'"
    parts: list[str] = []
    cur = ""
    for word in re.findall(r"\S+\s*", esc):
        if cur and len(cur) + len(word) + 2 > width:
            parts.append(cur)
            cur = ""
        cur += word
    if cur:
        parts.append(cur)
    pad = " " * indent
    return ("\n" + pad).join(f"'{p}'" for p in parts)


class Emitter:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def add(self, s: str) -> None:
        self.lines.append(s)


def emit_block(b: dict, ind: int) -> str:
    p = " " * ind
    q = " " * (ind + 2)
    k = b["kind"]
    if k == "lede":
        return f"{p}LessonLede(\n{q}{dstr(b['text'], ind + 2)},\n{p}),"
    if k == "text":
        small = ", small: true" if b.get("small") else ""
        return f"{p}LessonText(\n{q}{dstr(b['text'], ind + 2)}{small},\n{p}),"
    if k == "heading":
        return f"{p}LessonHeading({dstr(b['text'], ind + 16)}),"
    if k == "callout":
        kind = b["callout"]
        fields = []
        if kind == "quote":
            fields.append(f"speaker: {dstr(b['speaker'], ind + 11)}")
        if b.get("title") is not None:
            fields.append(f"title: {dstr(b['title'], ind + 9)}")
        fields.append(f"body: {dstr(b['body'], ind + 8)}")
        if b.get("steps"):
            items = "".join(f"{q}  {dstr(i, ind + 4)},\n" for i in b["steps"])
            fields.append(f"steps: <String>[\n{items}{q}]")
        if kind == "quote" and b.get("attribution"):
            fields.append(f"attribution: {dstr(b['attribution'], ind + 15)}")
        body = "".join(f"{q}{f},\n" for f in fields)
        return f"{p}LessonCallout.{kind}(\n{body}{p}),"
    if k == "figure":
        mw = f"\n{q}maxWidth: {b['maxWidth']:g}," if b.get("maxWidth") else ""
        return (
            f"{p}LessonFigure(\n"
            f"{q}asset: '{b['asset']}',\n"
            f"{q}width: {b['width']:g},\n"
            f"{q}height: {b['height']:g},{mw}\n"
            f"{q}caption: {dstr(b['caption'], ind + 11)},\n"
            f"{p}),"
        )
    if k == "myth":
        return (
            f"{p}LessonMyth(\n"
            f"{q}myth: {dstr(b['myth'], ind + 8)},\n"
            f"{q}fact: {dstr(b['fact'], ind + 8)},\n"
            f"{p}),"
        )
    if k in ("steps", "bullets", "sources"):
        cls = {"steps": "LessonSteps", "bullets": "LessonBullets", "sources": "LessonSourceList"}[k]
        items = "".join(f"{q}  {dstr(i, ind + 4)},\n" for i in b["items"])
        return f"{p}{cls}(<String>[\n{items}{q}]),"
    if k == "cards":
        cards = ""
        for c in b["cards"]:
            t = f"{q}    title: {dstr(c['title'], ind + 11)},\n" if c.get("title") else ""
            cards += f"{q}  LessonCardData(\n{t}{q}    body: {dstr(c['body'], ind + 10)},\n{q}  ),\n"
        return f"{p}LessonCards(<LessonCardData>[\n{cards}{q}]),"
    if k == "link":
        return f"{p}LessonToolLink('{b['toolId']}'),"
    if k == "task":
        s = f"{p}LessonTask(\n{q}title: {dstr(b['title'], ind + 9)},\n"
        if b.get("why"):
            s += f"{q}why: {dstr(b['why'], ind + 7)},\n"
        if b.get("steps"):
            s += f"{q}steps: <String>[\n"
            s += "".join(f"{q}  {dstr(i, ind + 4)},\n" for i in b["steps"])
            s += f"{q}],\n"
        if b.get("after"):
            s += f"{q}after: {dstr(b['after'], ind + 9)},\n"
        return s + f"{p}),"
    raise ConvertError(f"no emitter for {k}")


# ─────────────────────────────────────────────────────────────────────────────
# Guide walk
# ─────────────────────────────────────────────────────────────────────────────


def parse_guide(src: str, slug: str, asset_root: str):
    doc = lhtml.fromstring(src)
    figures = {f["n"]: f for f in X.find_figures(src)}
    fig_sizes = {}
    for n, f in figures.items():
        vb = X.parse_svg(f["svg"]).get("viewBox").split()
        fig_sizes[n] = (float(vb[2]), float(vb[3]))

    pages = doc.xpath('//section[contains(concat(" ", @class, " "), " page ")]')
    cover = pages[0]
    if "cover" not in classes(cover):
        raise ConvertError("first page is not the cover")
    title = re.sub(r"\s+", " ", " ".join(cover.xpath(".//h1//text()"))).strip()
    title = re.sub(r"\s+,", ",", title)
    tagline = " ".join(cover.xpath('.//div[@class="tagline"]//text()')).strip() or None
    promise = inline(cover.xpath('.//div[@class="sub"]')[0])
    byline = [
        inline(e)
        for e in cover.xpath('.//div[@class="by"]//div[@class="name" or @class="meta"]')
    ]
    cover_svg = X.find_cover(src)

    steps: list[dict] = []
    page_steps: dict[int, list[int]] = {}
    page_starts: dict[int, list[int]] = {}
    eyebrow = ""
    body_n = 0
    appendix_seen = 0

    def cur() -> dict:
        if not steps:
            raise ConvertError("content before the first h2")
        return steps[-1]

    def add(b: dict) -> None:
        cur()["blocks"].append(b)

    for page in pages[1:]:
        foot = page.xpath('./div[@class="foot"]/span[last()]/text()')
        page_no = int(foot[0]) if foot else None
        kids = [c for c in page if isinstance(c.tag, str)]
        i = 0
        started_here = False
        while i < len(kids):
            el = kids[i]
            tag, cl = el.tag, classes(el)
            nxt = kids[i + 1] if i + 1 < len(kids) else None
            i += 1
            if tag == "div" and cl & {"bar", "foot", "toc"}:
                continue
            if tag == "div" and "eyebrow" in cl:
                eyebrow = el.text_content().strip()
                continue
            if tag == "h2":
                t = inline(el)
                if eyebrow.startswith("Appendix") and not eyebrow.startswith("Appendix,"):
                    appendix_seen += 1
                    m = re.match(r"Appendix ([A-Z])\b", eyebrow)
                    letter = m.group(1) if m else "A"
                    steps.append({"number": letter, "spoken": f"Appendix {letter}" if m else "Appendix", "title": t, "blocks": []})
                elif eyebrow == "Sources":
                    steps.append({"number": "→", "spoken": "Sources", "title": t, "blocks": []})
                else:
                    body_n += 1
                    steps.append({"number": str(body_n), "spoken": None, "title": t, "blocks": []})
                eyebrow = ""
                started_here = True
                if page_no is not None:
                    page_steps.setdefault(page_no, []).append(len(steps) - 1)
                    page_starts.setdefault(page_no, []).append(len(steps) - 1)
                continue
            if page_no is not None and steps and not started_here:
                page_steps.setdefault(page_no, [])
                if len(steps) - 1 not in page_steps[page_no]:
                    page_steps[page_no].insert(0, len(steps) - 1)
            if tag == "h3":
                if nxt is not None and "toc" in classes(nxt):
                    continue  # "What's inside": print only
                add({"kind": "heading", "text": inline(el)})
            elif tag == "p":
                if "lede" in cl:
                    add({"kind": "lede", "text": inline(el)})
                else:
                    add({"kind": "text", "text": inline(el), "small": "small" in cl})
            elif tag == "div" and "fig" in cl:
                cap = el.xpath('.//*[@class="cap"]')[0]
                caption = X.caption_markup(lhtml.tostring(cap, encoding="unicode").split(">", 1)[1].rsplit("<", 1)[0])
                n = int(re.match(r"\*\*Figure (\d+)\.", caption).group(1))
                w, h = fig_sizes[n]
                mw = re.search(r"max-width:\s*(\d+)px", el.get("style") or "")
                actual = bool(el.xpath('.//*[local-name()="svg" and contains(concat(" ", @class, " "), " actual ")]'))
                add({
                    "actual": actual,
                    "kind": "figure",
                    "asset": f"{asset_root}/{slug}/fig-{n:02d}.svg",
                    "width": w,
                    "height": h,
                    "maxWidth": float(mw.group(1)) if mw else None,
                    "caption": caption,
                })
            elif tag == "div" and cl & {"callout", "note", "caution", "danger", "quote"}:
                add(parse_callout(el, cl))
            elif tag == "div" and "myth" in cl:
                m = el.xpath('./div[@class="m"]')[0]
                f = el.xpath('./div[@class="f"]')[0]
                skip = lambda e: "ml" in classes(e)  # noqa: E731
                add({"kind": "myth", "myth": inline(m, skip), "fact": inline(f, skip)})
            elif tag == "ol" and "steps" in cl:
                add({"kind": "steps", "items": [inline(li) for li in el.xpath("./li")]})
            elif tag == "ul" and cl & {"src", "src-list"}:
                add({"kind": "sources", "items": [inline(li) for li in el.xpath("./li")]})
            elif tag == "ul" and "tips" in cl:
                cards = []
                for li in el.xpath("./li"):
                    lead = li.xpath("./b")
                    if not lead or li.text and li.text.strip():
                        raise ConvertError(f"tip does not open with <b>: {lhtml.tostring(li)[:100]!r}")
                    cards.append({
                        "title": inline(lead[0]),
                        "body": inline(li, skip=lambda e, b=lead[0]: e is b),
                    })
                add({"kind": "cards", "cards": cards})
            elif tag == "ul":
                add({"kind": "bullets", "items": [inline(li) for li in el.xpath("./li")]})
            elif tag == "div" and cl & {"two", "three", "cards"}:
                cards = []
                for c in el:
                    if not isinstance(c.tag, str):
                        continue
                    if "card" not in classes(c):
                        raise ConvertError(f"grid holds a non-card: {lhtml.tostring(c)[:100]!r}")
                    h3 = c.xpath("./h3") or c.xpath('./b[@class="t"]')
                    ps = c.xpath("./p")
                    cards.append({
                        "title": inline(h3[0]) if h3 else None,
                        "body": " ".join(inline(p) for p in ps),
                    })
                add({"kind": "cards", "cards": cards})
            elif tag == "div" and "task" in cl:
                heads = el.xpath("./h3") or el.xpath('./b[@class="t"]')
                h3 = heads[0]
                why = el.xpath('./div[@class="why"]')
                ol = el.xpath('./ol[contains(@class,"steps")]')
                after = el.xpath("./p")
                known = {"h3", "ol", "p"}
                for c in el:
                    if c is h3:
                        continue
                    if isinstance(c.tag, str) and c.tag not in known and "why" not in classes(c):
                        raise ConvertError(f"task holds <{c.tag}>")
                loose = (el.text or "") + "".join(c.tail or "" for c in el if isinstance(c.tag, str))
                if loose.strip():
                    raise ConvertError(f"task holds loose text: {loose.strip()[:80]!r}")
                add({
                    "kind": "task",
                    "title": inline(h3),
                    "why": inline(why[0]) if why else None,
                    "steps": [inline(li) for li in ol[0].xpath("./li")] if ol else [],
                    "after": " ".join(inline(p) for p in after) or None,
                })
            else:
                raise ConvertError(f"unrecognized block <{tag} class={sorted(cl)}>: {lhtml.tostring(el)[:120]!r}")

    return {
        "title": title,
        "tagline": tagline,
        "promise": promise,
        "byline": byline,
        "cover": cover_svg,
        "steps": steps,
        "page_steps": page_steps,
        "page_starts": page_starts,
    }


_CALLOUT_SKIP = {"lbl", "lab", "who", "attr", "ct", "spk"}


def _callout_body(el) -> str:
    """The callout's running text: its own text and inline children, plus
    the inside of any body <p>, <q> or div.q. Title, label, source line,
    procedure and a quote's p.small are taken separately."""
    parts: list[str] = [el.text or ""]
    for c in el:
        if not isinstance(c.tag, str):
            continue
        cc = classes(c)
        if (c.tag == "b" and "t" in cc) or (c.tag == "ol" and "steps" in cc) or cc & _CALLOUT_SKIP \
                or (c.tag == "p" and "small" in cc):
            pass
        elif c.tag == "p" or (c.tag == "div" and "q" in cc):
            parts.append(" " + inline(c) + " ")
        else:
            # An inline element: render it in place through inline().
            wrap = lhtml.Element("span")
            wrap.append(copy.deepcopy(c))
            wrap[0].tail = None
            parts.append(inline(wrap))
        parts.append(c.tail or "")
    return re.sub(r"\s+", " ", "".join(parts)).strip()


def parse_callout(el, cl: set[str]) -> dict:
    is_quote = "quote" in cl or bool(el.xpath('./div[@class="q"]'))
    kind = "stop" if "danger" in cl else "caution" if "caution" in cl else "quote" if is_quote else "note"
    t = el.xpath('./b[@class="t"]') or el.xpath('./p[@class="ct"]')
    title = inline(t[0]) if t else None
    ol = el.xpath('./ol[contains(@class,"steps")]')
    if any(c.tag == "p" or "q" in classes(c) for c in el if isinstance(c.tag, str)):
        body = _callout_body(el)
    else:
        body = inline(
            el,
            skip=lambda e: (e.tag == "b" and "t" in classes(e))
            or (e.tag == "ol" and "steps" in classes(e))
            or bool(classes(e) & {"lbl", "lab", "who"}),
        )
    b = {"kind": "callout", "callout": kind, "title": title, "body": body}
    if ol:
        b["steps"] = [inline(li) for li in ol[0].xpath("./li")]
    if kind == "quote":
        # The speaker label: div.lab, or p.spk / span.spk (the figure-kit
        # guides of 2026-09-28: Travel Routers, Captive Portals).
        lab = el.xpath('./div[@class="lab"]') or el.xpath('./*[@class="spk"]')
        who = el.xpath('./*[@class="who"]')
        attr = el.xpath('./*[@class="attr"]')
        small = el.xpath('./p[@class="small"]')
        if lab:
            speaker, source = lab[0], (who or attr or small)
        elif who and el.xpath('./div[@class="q"]'):
            speaker, source = who[0], (attr or small)
        else:
            raise ConvertError(f"quote with no speaker: {lhtml.tostring(el)[:120]!r}")
        b["speaker"] = inline(speaker, skip=lambda e: e.tag == "svg")
        b["attribution"] = " ".join(inline(x) for x in source) or None
        b["title"] = cap_first(title) if title else None
    if kind in ("caution", "stop") and not title:
        raise ConvertError(f"{kind} callout with no title")
    return b


# ─────────────────────────────────────────────────────────────────────────────
# Page references
# ─────────────────────────────────────────────────────────────────────────────

_PAGE = re.compile(r"\b(on |at )?page (\d+)\b")

# A page named by where it sits rather than by number. In a lesson the next
# page is the next step and this page is this step, as long as the guide
# starts each section on a page of its own; every use is printed, so check
# each one against the guide (Wi-Fi and Health: "as the next page shows" in
# step 1 points at step 2; Figure 7's "the math on this page" is step 5's).
_PAGE_WORD = re.compile(r"\b(on |in )?(the next|this) page\b")


def add_links(g: dict, links: list[tuple[str, str]]) -> list[str]:
    """After each block that names a linked guide as __Title__, an Open
    button for that lesson, in the order the block names them."""
    notes: list[str] = []
    for st in g["steps"]:
        out = []
        for b in st["blocks"]:
            out.append(b)
            text = " ".join(
                v for k, v in b.items() if isinstance(v, str) and k not in ("kind", "asset")
            )
            found = sorted(
                (text.find(f"__{title}__"), tid, title)
                for tid, title in links
                if f"__{title}__" in text
            )
            for _, tid, title in found:
                out.append({"kind": "link", "toolId": tid})
                notes.append(f"link to {tid} after the block naming {title} (step {st['number']})")
        st["blocks"] = out
    named = {n.split(" ")[2] for n in notes}
    for tid, title in links:
        if tid not in named:
            raise ConvertError(f"--link {tid}: the guide never names __{title}__")
    return notes


def fix_page_refs(g: dict) -> list[str]:
    changes: list[str] = []

    def step_for(page: int) -> dict:
        idx = g["page_steps"].get(page)
        if not idx:
            raise ConvertError(f"a reference to page {page}, which has no step")
        # A page that starts a new section belongs to the first section that
        # starts on it; a page that only continues one belongs to the one it
        # continues. (Until 2026-09-28 this took the page's second entry
        # whenever it had two, which picks the wrong step for a page that
        # opens with a heading and starts another lower down: Travel
        # Routers' "the VPN note on page 13".)
        starts = g["page_starts"].get(page)
        return g["steps"][starts[0] if starts else idx[0]]

    def fix(s: str) -> str:
        def sub(m: re.Match) -> str:
            st = step_for(int(m.group(2)))
            pre = {"on ": "in ", "at ": "in "}.get(m.group(1) or "", "")
            new = f"{pre}step {st['number']}"
            changes.append(f'"{m.group(0)}" -> "{new}" ({st["title"]})')
            return new

        def sub_word(m: re.Match) -> str:
            pre = "in " if m.group(1) else ""
            new = f"{pre}{m.group(2)} step"
            changes.append(f'"{m.group(0)}" -> "{new}"')
            return new

        return _PAGE_WORD.sub(sub_word, _PAGE.sub(sub, s))

    for st in g["steps"]:
        claims = any(
            re.search(r"(?<!not )\bactual size\b", b.get("text", ""))
            for b in st["blocks"]
            if b["kind"] in ("text", "lede")
        )
        for b in st["blocks"]:
            if b["kind"] == "figure" and b.pop("actual", False) and claims:
                note = " (actual size on the printed guide)"
                b["caption"] += note
                changes.append(f'caption + "{note.strip()}" ({b["caption"].split(".", 1)[0].strip("*")})')
        for b in st["blocks"]:
            for key in ("text", "body", "title", "caption", "why", "after", "myth", "fact"):
                if isinstance(b.get(key), str):
                    b[key] = fix(b[key])
            for key in ("items", "steps"):
                if isinstance(b.get(key), list):
                    b[key] = [fix(x) for x in b[key]]
            for c in b.get("cards", []):
                c["body"] = fix(c["body"])
    return changes


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────


def source_rev(guide: Path) -> str:
    """The guide's last commit, and whether the file differs from it, so the
    generated file says exactly which text it carries."""
    import subprocess

    d = str(guide.resolve().parent)
    try:
        rev = subprocess.run(
            ["git", "-C", d, "log", "-1", "--format=%h %ad", "--date=short", "--", guide.name],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        dirty = subprocess.run(
            ["git", "-C", d, "status", "--porcelain", "--", guide.name],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "(not in a git repository)"
    if not rev:
        return "(not committed)"
    return f"myPKA commit {rev}" + (", with uncommitted changes" if dirty else "")


def render(g: dict, a) -> str:
    out: list[str] = []
    w = out.append
    w(f"// {g['title']}: Guided Lesson content, generated by")
    w("// tool/guide_to_lesson.py from the guide's approved source,")
    w(f"//   {a.guide.name}")
    w(f"//   {source_rev(a.guide)}")
    w("// The text is the guide's own, word for word. See the tool's header for")
    w("// what a lesson leaves out and the one change it makes (a printed page")
    w("// number becomes a step number). Regenerate rather than hand-edit.")
    w("")
    w("import '../../../../widgets/lesson/guided_lesson.dart';")
    w("")
    w(f"const GuidedLesson {a.name} = GuidedLesson(")
    w(f"  toolId: '{a.tool_id}',")
    w(f"  route: '{a.route}',")
    w(f"  title: {dstr(g['title'], 9)},")
    w(f"  guideTitle: {dstr(g['title'], 14)},")
    if g["tagline"]:
        w(f"  tagline: {dstr(g['tagline'], 11)},")
    w(f"  promise:\n      {dstr(g['promise'], 6)},")
    if g["byline"]:
        w("  byline: <String>[")
        for line in g["byline"]:
            w(f"    {dstr(line, 4)},")
        w("  ],")
    if g["cover"]:
        vb = X.parse_svg(g["cover"]).get("viewBox").split()
        w("  cover: LessonFigure(")
        w(f"    asset: '{a.asset_root}/{a.slug}/cover.svg',")
        w(f"    width: {float(vb[2]):g},")
        w(f"    height: {float(vb[3]):g},")
        w("  ),")
    w("  steps: <LessonStep>[")
    for st in g["steps"]:
        w(f"    // ── {st['number']}. {st['title']} ".ljust(78, "─"))
        w("    LessonStep(")
        w(f"      number: '{st['number']}',")
        if st["spoken"]:
            w(f"      spoken: '{st['spoken']}',")
        w(f"      title: {dstr(st['title'], 13)},")
        w("      blocks: <LessonBlock>[")
        for b in st["blocks"]:
            w(emit_block(b, 8))
        w("      ],")
        w("    ),")
    w("  ],")
    w(");")
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("guide", type=Path)
    ap.add_argument("slug")
    ap.add_argument("--name", required=True, help="Dart const name, e.g. kFindMyLesson")
    ap.add_argument("--tool-id", required=True)
    ap.add_argument("--route", required=True)
    ap.add_argument("--asset-root", default="assets/lesson-figures")
    ap.add_argument("--out", type=Path, default=Path("lib/screens/tools/reference/lessons"))
    ap.add_argument("--json", action="store_true", help="also print the parsed lesson as JSON")
    ap.add_argument("--link", action="append", default=[], metavar="TOOL_ID=TITLE",
                    help="Open button after each block naming the guide TITLE")
    a = ap.parse_args(argv)
    try:
        g = parse_guide(a.guide.read_text(encoding="utf-8"), a.slug, a.asset_root)
        changes = fix_page_refs(g)
        links = add_links(g, [tuple(x.split("=", 1)) for x in a.link])
    except (ConvertError, X.ExtractError) as e:
        print(f"guide_to_lesson: {a.guide.name}: {e}", file=sys.stderr)
        return 1
    a.out.mkdir(parents=True, exist_ok=True)
    path = a.out / f"{a.slug.replace('-', '_')}_lesson.dart"
    path.write_text(render(g, a), encoding="utf-8")
    nblocks = sum(len(s["blocks"]) for s in g["steps"])
    print(f"{a.slug}: {len(g['steps'])} steps, {nblocks} blocks -> {path}")
    for c in changes:
        print(f"  text change: {c}")
    for n in links:
        print(f"  {n}")
    if a.json:
        print(json.dumps(g["steps"], indent=1, ensure_ascii=False, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
