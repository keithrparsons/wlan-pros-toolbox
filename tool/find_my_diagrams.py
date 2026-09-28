#!/usr/bin/env python3
"""Generate the Find My, Explained lesson figures.

Source of the drawings: the approved print guide
myPKA/Deliverables/2026-09-27-find-my-guide/find-my-guide.html (cover art and
Figures 1 to 8). The print figures were drawn for a light page, so they are
re-drawn here DARK-BAKED on the GL-003 §8.20.7 allow-list hexes, the same
convention as assets/tool-diagrams/antenna-fundamentals/:

  #E5E5E5 scaffold / primary label     -> light #4A4A4A
  #9C9C9C muted label / geometry       -> light #646464
  #A2CC3A lime                         -> light #5A7A1C
  #3A3A3A panel fill / hairline        -> light #E2E1E2
  #F26E6E danger, #E0A23A warning      -> light status tokens
  rgba(162,204,58,0.08) lime wash      -> light wash

Light mode is produced at runtime by ConceptGraphicBand.applyLightSwap, so no
light copy is authored. Rules this file keeps (GL-003 §11.7, §11.8, and the
flutter_svg limits):
  - every presentation property is an inline attribute (no <style>, no class=);
  - no full-canvas background rectangle (the band's card is the canvas);
  - no <marker>: arrowheads are drawn triangles;
  - every label string is identical to the print guide's label. Only line
    breaks and positions change. Two exceptions in form, not wording:
    Figure 2's ellipses and Figure 7's menu chevrons are drawn as geometry;
  - <text> carries ASCII only (GL-003 §8.6.1: a non-ASCII glyph draws as a
    missing-glyph box on the web path). test/graphics/
    lesson_figure_ascii_text_test.dart checks it.

Usage: python3 tool/find_my_diagrams.py   (writes assets/tool-diagrams/find-my/)
"""

from __future__ import annotations

import math
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tool-diagrams', 'find-my')

# Exact bundled family names, not a CSS fallback list: flutter_svg hands the
# whole font-family attribute to the text engine as ONE family name
# (vector_graphics listener.dart), so a list like
# "'IBM Plex Sans','Helvetica Neue',Arial" matches nothing and the labels fall
# back to the platform font. These two names match pubspec `flutter: fonts:`.
FONT = 'IBM Plex Sans'
MONO = 'DM Mono'

T = '#E5E5E5'  # primary label, scaffold
M = '#9C9C9C'  # muted label, secondary geometry
L = '#A2CC3A'  # lime
P = '#3A3A3A'  # panel fill, hairline
W = '#E0A23A'  # warning
D = '#F26E6E'  # danger
WASH = 'rgba(162,204,58,0.08)'


def text(x, y, s, size=14, fill=M, weight=400, anchor='start', family=FONT):
    # [y] is the visual middle of the line. flutter_svg ignores
    # dominant-baseline, so the baseline is placed explicitly (0.35 em below
    # the middle) and both a browser and the app draw it in the same place.
    base = round(y + size * 0.35, 1)
    return (
        f'<text x="{x}" y="{base}" font-family="{family}" font-size="{size}" '
        f'fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">'
        f'{escape(s)}</text>'
    )


# Advance widths from the bundled font files (assets/fonts, read with
# fontTools), so drawn glyphs sit against text the same way in a browser and
# in flutter_svg. DM Mono is fixed-pitch: 0.6 em per character.
MONO_ADVANCE = 0.6
PLEX_14 = {'Items': 37.24, 'your tag': 51.0, 'paste': 35.01}


def truncated_code(cx, y, code, size=16, fill=T):
    """A mono code followed by a drawn ellipsis, centered on [cx].

    GL-003 §8.6.1: a non-ASCII glyph in SVG <text> draws as a missing-glyph
    box on the web path, so the print guide's "7F3A…" keeps its wording but
    the ellipsis is three dots of geometry.
    """
    tw = len(code) * size * MONO_ADVANCE
    dots = 3 * 4.0
    x0 = round(cx - (tw + 2 + dots) / 2, 2)
    base = round(y + size * 0.35, 1)
    out = [text(x0, y, code, size=size, fill=fill, family=MONO)]
    for k in range(3):
        out.append(circle(round(x0 + tw + 1.5 + 2 + 4.0 * k, 2), round(base - 1.4, 1), 1.4, fill=fill))
    return out


def menu_path(cx, y, parts, widths, size=14, fill=M):
    """Menu steps joined by drawn chevrons, centered on [cx] (the print
    guide's "Items › your tag › paste"; the chevron is geometry, not a glyph,
    per GL-003 §8.6.1). Each part is start-anchored at its own x."""
    slot = 14
    total = sum(widths[p] for p in parts) + slot * (len(parts) - 1)
    x = cx - total / 2
    out = []
    for i, part in enumerate(parts):
        out.append(text(round(x, 2), y, part, size=size, fill=fill))
        x += widths[part]
        if i < len(parts) - 1:
            mx, my = x + slot / 2, y + 1
            out.append(path(f'M{round(mx - 2, 2)} {my - 3.5} L{round(mx + 2, 2)} {my} '
                            f'L{round(mx - 2, 2)} {my + 3.5}', stroke=fill, sw=1.5))
            x += slot
    return out


def title(x, y, s, anchor='start', fill=T, size=16):
    return text(x, y, s, size=size, fill=fill, weight=600, anchor=anchor)


def rect(x, y, w, h, rx=12, stroke=M, sw=1.5, fill='none', extra=''):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{s}{extra}/>'


def line(x1, y1, x2, y2, stroke=M, sw=2, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return (
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" '
        f'stroke-width="{sw}" stroke-linecap="round"{d}/>'
    )


def arrow(x1, y1, x2, y2, color=M, sw=2, head=10, dash=None):
    """A line from (x1,y1) to (x2,y2) with a drawn triangle head at the end."""
    ang = math.atan2(y2 - y1, x2 - x1)
    bx, by = x2 - head * math.cos(ang), y2 - head * math.sin(ang)
    half = head * 0.5
    px, py = -math.sin(ang) * half, math.cos(ang) * half
    tri = (
        f'<path d="M{x2:.2f} {y2:.2f} L{bx + px:.2f} {by + py:.2f} '
        f'L{bx - px:.2f} {by - py:.2f} Z" fill="{color}"/>'
    )
    return line(x1, y1, round(bx, 2), round(by, 2), color, sw, dash) + tri


def circle(cx, cy, r, stroke=None, sw=2, fill='none', opacity=None, dash=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    o = f' opacity="{opacity}"' if opacity is not None else ''
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"{s}{o}{d}/>'


def path(d, stroke=M, sw=2, fill='none', dash=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    ds = f' stroke-dasharray="{dash}"' if dash else ''
    return (
        f'<path d="{d}" fill="{fill}"{s}{ds} stroke-linecap="round" '
        f'stroke-linejoin="round"/>'
    )


def svg(w, h, label, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}" role="img" aria-label="{escape(label, {chr(34): "&quot;"})}">\n'
        + '\n'.join(body)
        + '\n</svg>\n'
    )


def phone(x, y, w=40, h=72, stroke=T):
    return [
        rect(x, y, w, h, rx=8, stroke=stroke, sw=2.5),
        rect(x + 5, y + 7, w - 10, h - 16, rx=4, stroke=None, fill=P),
    ]


def airtag(cx, cy, r=12):
    return [circle(cx, cy, r, stroke=L, sw=3), circle(cx, cy, 3.5, fill=L)]


# ── Cover art: People / Devices / Items on a map ────────────────────────────
def _cubic_pieces(seg, holes, n=1200):
    """The parts of cubic [seg] outside every circular hole (cx, cy, r),
    each returned as an exact cubic (de Casteljau)."""
    def at(t):
        (x0, y0), (x1, y1), (x2, y2), (x3, y3) = seg
        u = 1 - t
        return (u ** 3 * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x3,
                u ** 3 * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y3)

    def split(q, t):
        lerp = lambda m, k: (m[0] + (k[0] - m[0]) * t, m[1] + (k[1] - m[1]) * t)
        a_, b_, c_, d_ = q
        ab, bc, cd = lerp(a_, b_), lerp(b_, c_), lerp(c_, d_)
        abc, bcd = lerp(ab, bc), lerp(bc, cd)
        m = lerp(abc, bcd)
        return (a_, ab, abc, m), (m, bcd, cd, d_)

    def sub(t0, t1):
        _, right = split(seg, t0)
        left, _ = split(right, (t1 - t0) / (1 - t0))
        return left

    out_mask = [all(math.hypot(at(i / n)[0] - hx, at(i / n)[1] - hy) > hr
                    for hx, hy, hr in holes) for i in range(n + 1)]
    pieces, start = [], None
    for i, ok in enumerate(out_mask + [False]):
        if ok and start is None:
            start = i
        elif not ok and start is not None:
            if i - 1 > start:
                pieces.append(sub(start / n, (i - 1) / n))
            start = None
    return pieces


def cover():
    b = []
    pins = ((175, 150), (350, 140), (525, 95))
    # The map grid and the route stop at each pin's halo (r 34, gap to 37),
    # so no line runs through a pin (Keith, 2026-09-27: "not have other icons
    # or bit's being covered by other lines").
    hole_r = 37
    grid = 'M0 30H700M0 220H700M90 0V250M260 0V250M440 0V250M610 0V250'
    b.append(path(grid, stroke=P, sw=1))
    # The y 125 grid line crosses all three halos: drawn in pieces.
    xs = [0]
    for cx, cy in pins:
        dx = math.sqrt(max(hole_r ** 2 - (125 - cy) ** 2, 0))
        xs += [round(cx - dx, 1), round(cx + dx, 1)]
    xs.append(700)
    b.append(path(''.join(f'M{xs[i]} 125H{xs[i + 1]}' for i in range(0, len(xs), 2)),
                  stroke=P, sw=1))
    # The route, 'M30 215 C120 190 150 170 175 150 S300 150 350 140
    # S470 100 525 95 S640 60 680 55', with each S written out as its C.
    route = [
        ((30, 215), (120, 190), (150, 170), (175, 150)),
        ((175, 150), (200, 130), (300, 150), (350, 140)),
        ((350, 140), (400, 130), (470, 100), (525, 95)),
        ((525, 95), (580, 90), (640, 60), (680, 55)),
    ]
    holes = [(cx, cy, hole_r) for cx, cy in pins]
    f = lambda v: f'{round(v[0], 1)} {round(v[1], 1)}'
    d = ''
    for seg in route:
        for q in _cubic_pieces(seg, holes):
            d += f'M{f(q[0])} C{f(q[1])} {f(q[2])} {f(q[3])}'
    b.append(path(d, stroke=M, sw=3, dash='2 8'))
    for cx, cy in pins:
        b.append(circle(cx, cy, 34, fill=L, opacity=0.15))
        b.append(circle(cx, cy, 20, fill=L, opacity=0.3))
    b.append(circle(175, 150, 11, fill=L))
    b.append(rect(342, 127, 16, 26, rx=3, stroke=None, fill=L))
    b.append(circle(525, 95, 11, stroke=L, sw=3))
    b.append(circle(525, 95, 5, fill=L))
    b.append(title(175, 200, 'People', anchor='middle', size=18))
    b.append(title(350, 190, 'Devices', anchor='middle', size=18))
    b.append(title(525, 145, 'Items', anchor='middle', size=18))
    return svg(700, 250, 'Three pins on a map: People, Devices, Items', b)


# ── Figure 1: the Find My network, four steps ───────────────────────────────
def f1():
    b = []
    boxes = {1: (10, 20), 2: (340, 20), 3: (340, 240), 4: (10, 240)}
    bw, bh = 290, 180
    for n, (x, y) in boxes.items():
        b.append(rect(x, y, bw, bh))
        b.append(circle(x + 24, y, 15, stroke=L, sw=2, fill=P))
        b.append(title(x + 24, y + 1, str(n), anchor='middle', size=15))

    def labels(x, y, t, l1, l2):
        cx = x + bw / 2
        return [
            title(cx, y + 118, t, anchor='middle'),
            text(cx, y + 142, l1, anchor='middle'),
            text(cx, y + 162, l2, anchor='middle'),
        ]

    # 1: AirTag in a suitcase, sending
    x, y = boxes[1]
    cx = x + bw / 2
    b.append(rect(cx - 40, y + 40, 80, 56, rx=8, stroke=M, sw=3))
    b.append(rect(cx - 12, y + 30, 24, 12, rx=3, stroke=M, sw=3))
    b += airtag(cx, y + 68)
    b.append(path(f'M{cx + 50} {y + 58} a16 16 0 0 1 0 20', stroke=L, sw=2.5))
    b.append(path(f'M{cx + 58} {y + 51} a26 26 0 0 1 0 34', stroke=L, sw=2.5))
    b += labels(x, y, 'Your AirTag', 'sends a short', 'Bluetooth "I\'m here"')

    # 2: a stranger's iPhone
    x, y = boxes[2]
    cx = x + bw / 2
    b += phone(cx - 20, y + 26)
    b += labels(x, y, "A stranger's iPhone", 'walks past and', 'hears it')

    # 3: sealed envelope
    x, y = boxes[3]
    cx = x + bw / 2
    b.append(rect(cx - 40, y + 36, 72, 48, rx=4, stroke=T, sw=2.5))
    b.append(path(f'M{cx - 40} {y + 36} l36 26 36 -26', stroke=T, sw=2.5))
    b.append(rect(cx + 14, y + 62, 24, 22, rx=3, stroke=None, fill=L))
    b.append(path(f'M{cx + 19} {y + 62} v-6 a7 7 0 0 1 14 0 v6', stroke=L, sw=3))
    b += labels(x, y, 'Seals its own location', 'in an envelope only', 'your devices can open')

    # 4: your iPhone shows the dot
    x, y = boxes[4]
    cx = x + bw / 2
    b += phone(cx - 20, y + 26)
    b.append(circle(cx, y + 60, 7, fill=L))
    b += labels(x, y, 'Your iPhone', 'opens it and puts', 'a dot on your map')

    # flow: 1 -> 2 -> 3 -> 4
    b.append(arrow(304, 110, 336, 110))
    b.append(arrow(485, 204, 485, 236))
    b.append(arrow(336, 330, 304, 330))

    # bands
    b.append(rect(10, 440, 620, 60))
    b.append(title(320, 460, 'The stranger is never told', anchor='middle'))
    b.append(text(320, 482, 'It happens in the background, anonymously', anchor='middle'))
    b.append(rect(10, 512, 620, 60, stroke=None, fill=P))
    b.append(title(320, 532, "Apple's servers pass the sealed envelope along", anchor='middle'))
    b.append(text(320, 554, "Apple can't open it, and doesn't know who found what",
                  anchor='middle', fill=T))
    return svg(640, 584, 'The Find My network in four steps', b)


# ── Figure 2: rotating IDs ──────────────────────────────────────────────────
def f2():
    b = [title(10, 22, "The tag's ID changes about every 15 minutes")]
    ids = ['7F3A', 'C019', '5B8E', 'E24D']  # each followed by a drawn ellipsis
    times = ['9:00', '9:15', '9:30', '9:45']
    for i, (code, t) in enumerate(zip(ids, times)):
        x = 10 + i * 155
        b.append(rect(x, 52, 130, 34, rx=6, stroke=None, fill=P))
        b += truncated_code(x + 65, 70, code)
        b.append(line(x, 100, x, 112, stroke=M, sw=2))
        b.append(text(x, 128, t))
    b.append(line(10, 106, 630, 106, stroke=M, sw=2))
    b.append(text(10, 162, 'An eavesdropper sees four unrelated codes.'))
    b.append(text(10, 188, 'Only your devices know they are the same tag.',
                  size=15, fill=L, weight=600))
    return svg(640, 204, 'Four rotating IDs over one hour', b)


# ── Figure 3: where the dot comes from ──────────────────────────────────────
def f3():
    b = []
    rows = [
        (20, 'GPS satellites', 'strong outdoors', False),
        (130, 'Wi-Fi access points', 'does the work indoors', True),
        (240, 'Cell towers', 'a rough fix anywhere', False),
    ]
    for y, t, s, hi in rows:
        if hi:
            b.append(rect(10, y, 250, 70, stroke=L, sw=2, fill=WASH))
        else:
            b.append(rect(10, y, 250, 70))
        b.append(title(82, y + 25, t))
        b.append(text(82, y + 48, s, fill=L if hi else M, weight=600 if hi else 400))
    # icons
    gx, gy = 46, 55  # satellite
    b.append(rect(gx - 9, gy - 6, 18, 12, rx=2, stroke=None, fill=M))
    b.append(rect(gx - 25, gy - 4, 12, 8, rx=1, stroke=M, sw=1.5))
    b.append(rect(gx + 13, gy - 4, 12, 8, rx=1, stroke=M, sw=1.5))
    wx, wy = 46, 172  # wi-fi
    b.append(path(f'M{wx - 15} {wy - 8} a21 21 0 0 1 30 0', stroke=L, sw=3))
    b.append(path(f'M{wx - 8} {wy - 1} a11 11 0 0 1 16 0', stroke=L, sw=3))
    b.append(circle(wx, wy + 6, 3, fill=L))
    tx, ty = 46, 275  # tower
    b.append(path(f'M{tx} {ty - 16} V{ty + 18} M{tx - 9} {ty + 18} L{tx} {ty - 6} L{tx + 9} {ty + 18}',
                  stroke=M, sw=3))
    b.append(path(f'M{tx - 12} {ty - 18} a14 14 0 0 0 0 10 M{tx + 12} {ty - 18} a14 14 0 0 1 0 10',
                  stroke=M, sw=2.5))
    # arrows into the finder phone
    b.append(arrow(262, 55, 356, 132))
    b.append(arrow(262, 165, 356, 165))
    b.append(arrow(262, 275, 356, 196))
    # finder phone
    b += phone(360, 110, w=56, h=100)
    b.append(title(388, 236, "Stranger's iPhone", anchor='middle'))
    b.append(text(388, 258, 'knows where it is', anchor='middle'))
    # the tag
    b += airtag(530, 64, r=18)
    b.append(text(530, 24, 'your AirTag, nearby', anchor='middle'))
    b.append(arrow(514, 76, 424, 120, color=L, dash='5 5'))
    b.append(text(482, 110, 'Bluetooth', fill=L, weight=600))
    # to the map
    b.append(arrow(424, 162, 590, 162))
    b.append(text(507, 146, 'its location, sealed', anchor='middle'))
    b.append(rect(596, 97, 150, 130, rx=10))
    b.append(path('M596 140H746M596 184H746M646 97V227M696 97V227', stroke=P, sw=1.5))
    # Halo r 20 keeps it inside its map cell (grid lines 22 px above and
    # below); at r 26 the grid ran through it.
    b.append(circle(671, 162, 20, fill=L, opacity=0.25))
    b.append(circle(671, 162, 9, fill=L))
    b.append(title(671, 252, 'The dot you see', anchor='middle'))
    b.append(text(671, 274, '= where that phone was', anchor='middle'))
    return svg(760, 320, 'Three location sources feed the finder phone, which reports the dot', b)


# ── Figure 4: three radios, three ranges ────────────────────────────────────
def f4():
    b = []
    cx, cy = 140, 150
    b.append(circle(cx, cy, 125, fill=L, opacity=0.07))
    b.append(circle(cx, cy, 125, stroke=M, sw=1.2, dash='3 5'))
    b.append(circle(cx, cy, 80, fill=L, opacity=0.12))
    b.append(circle(cx, cy, 80, stroke=M, sw=1.2, dash='3 5'))
    b.append(circle(cx, cy, 40, fill=L, opacity=0.2))
    b.append(circle(cx, cy, 40, stroke=L, sw=2, dash='5 4'))
    b.append(circle(cx, cy, 52, stroke=L, sw=1.5, dash='2 4'))
    b += airtag(cx, cy - 4, r=11)
    b.append(text(cx, cy + 20, 'tap', size=13, fill=T, anchor='middle', weight=600))

    def leader(x1, y1, y2):
        return [circle(x1, y1, 3, fill=M), line(x1, y1, 290, y2, stroke=M, sw=1.2)]

    b += leader(202, 42, 30)
    b.append(title(300, 30, 'Anywhere, eventually: the Find My network'))
    b.append(text(300, 52, "Other people's Apple devices report it, if they pass by."))
    b += leader(212, 116, 102)
    b.append(title(300, 102, 'Nearby: Bluetooth'))
    b.append(text(300, 124, 'Your own iPhone connects and can play a sound.'))
    b += leader(178, 164, 174)
    b.append(title(300, 174, 'Close by: Ultra Wideband (Precision Finding)'))
    b.append(text(300, 196, 'An arrow and distance on screen. AirTag 2: about 1.5x farther.'))
    b.append(line(152, 156, 290, 244, stroke=M, sw=1.2))
    b.append(title(300, 246, 'Touching: NFC'))
    b.append(text(300, 268, 'A phone with NFC that taps a lost tag'))
    b.append(text(300, 288, "sees the owner's contact info."))
    return svg(760, 302, 'Nested ranges around a tag: network, Bluetooth, Ultra Wideband, NFC', b)


# ── Figure 5: the four parts of the app ─────────────────────────────────────
def f5():
    b = []
    # phone
    b.append(rect(20, 10, 220, 334, rx=28, stroke=T, sw=2.5))
    b.append(path('M32 96H228M32 176H228M85 22V272M160 22V272', stroke=P, sw=1.5))
    b.append(circle(70, 70, 8, fill=T))
    b.append(rect(130, 124, 12, 18, rx=2, stroke=None, fill=M))
    b.append(circle(190, 214, 9, stroke=L, sw=3))
    b.append(line(32, 272, 228, 272, stroke=M, sw=1))
    tabs = ['People', 'Devices', 'Items', 'Me']
    for i, t in enumerate(tabs):
        tx = 32 + 196 * (i + 0.5) / 4
        if t == 'Devices':
            b.append(rect(tx - 6, 282, 12, 16, rx=2, stroke=None, fill=M))
        else:
            b.append(circle(tx, 290, 7, fill=M))
        b.append(text(tx, 316, t, size=13, fill=T, anchor='middle'))
    # legend cards, same order as the tabs
    cards = [
        ('People', ['Friends and family sharing with you.', 'Get directions, notifications, Find.']),
        ('Devices', ['Your iPhone, iPad, Mac, Watch, AirPods.', 'Play sound, Lost Mode, erase.']),
        ('Items', ['AirTags and other network tags.', 'Up to 32 per Apple Account.']),
        ('Me', ['Turn Share My Location on or off.']),
    ]
    y = 10
    for t, lines in cards:
        h = 36 + 22 * len(lines)
        b.append(rect(270, y, 360, h, rx=10))
        b.append(title(286, y + 22, t))
        for j, ln in enumerate(lines):
            b.append(text(286, y + 44 + 22 * j, ln))
        y += h + 12
    # watch
    wy = 376
    b.append(rect(40, wy, 150, 180, rx=40, stroke=T, sw=2.5))
    b.append(rect(192, wy + 60, 10, 34, rx=4, stroke=None, fill=M))
    b.append(rect(62, wy + 26, 86, 26, rx=13, stroke=M, sw=1.2, fill=P))
    b.append(text(76, wy + 39, 'Items', size=13, fill=T))
    b.append(path(f'M124 {wy + 35} L134 {wy + 35} L129 {wy + 43} Z', stroke=None, fill=T))
    b.append(circle(115, wy + 110, 9, stroke=L, sw=3))
    b.append(title(230, wy + 60, 'Apple Watch, watchOS 27'))
    b.append(text(230, wy + 84, 'One Find My app. The button at top left'))
    b.append(text(230, wy + 106, 'switches Devices, People, Items.'))
    return svg(640, 570, 'A simplified Find My app with People, Devices, Items and Me tabs, and an Apple Watch', b)


# ── Figure 6: your phone, even when it dies ─────────────────────────────────
def f6():
    b = []
    cards = [
        (10, 'full', 'On, with signal', ['Reports itself directly,', 'GPS, Wi-Fi and cell.']),
        (262, 'flat', 'Battery flat', ['Power reserve: findable', 'for up to 5 hours.']),
        (514, 'off', 'Switched off', ['Findable for up to 24 hours', 'through the Find My network.']),
    ]
    for x, kind, t, lines in cards:
        b.append(rect(x, 10, 236, 140))
        if kind == 'off':
            b.append(circle(x + 42, 47, 15, stroke=T, sw=2.5))
            b.append(line(x + 42, 29, x + 42, 45, stroke=T, sw=2.5))
        else:
            b.append(rect(x + 20, 32, 70, 30, rx=5, stroke=T, sw=2.5))
            b.append(rect(x + 90, 41, 5, 12, rx=1, stroke=None, fill=T))
            if kind == 'full':
                b.append(rect(x + 24, 36, 62, 22, rx=2, stroke=None, fill=L))
            else:
                b.append(rect(x + 24, 36, 8, 22, rx=2, stroke=None, fill=D))
        b.append(title(x + 20, 90, t))
        b.append(text(x + 20, 112, lines[0]))
        b.append(text(x + 20, 132, lines[1]))
    return svg(760, 160, 'A phone with signal, with a flat battery, and switched off', b)


# ── Figure 7: lost luggage, step by step ────────────────────────────────────
# The print guide's "Items › your tag › paste", drawn with chevron paths.
MENU = ('Items', 'your tag', 'paste')


def f7():
    b = []
    steps = [
        (10, D, 'none', [('Bag didn\'t arrive', True), ('Check the map first', False)]),
        (118, M, 'none', [("File the airline's baggage report", True)]),
        (226, L, WASH, [('Share Item Location', True), (MENU, False),
                        ('the link in their form', False)]),
        (334, M, 'none', [('Airline staff see a live map', True)]),
    ]
    for i, (y, stroke, fill, rows) in enumerate(steps):
        b.append(rect(10, y, 320, 80, stroke=stroke, sw=2 if stroke != M else 1.5, fill=fill))
        n = len(rows)
        top = y + 40 - (n - 1) * 11
        for j, (s, bold) in enumerate(rows):
            yy = top + j * 22
            if s is MENU:
                b += menu_path(170, yy, MENU, PLEX_14)
            else:
                b.append(title(170, yy, s, anchor='middle') if bold else text(170, yy, s, anchor='middle'))
        if i < 3:
            b.append(arrow(170, y + 84, 170, y + 104))
    # the link stops by itself
    b.append(rect(360, 10, 390, 92, stroke=None, fill=P))
    b.append(circle(398, 56, 18, stroke=L, sw=3))
    b.append(path('M398 45 V56 L406 61', stroke=L, sw=3))
    b.append(title(436, 34, 'The link stops by itself'))
    b.append(text(436, 58, "when you're reunited, after 7 days,", fill=T))
    b.append(text(436, 80, 'or when you end it', fill=T))
    # separate switch
    b.append(rect(360, 118, 390, 180, stroke=W, sw=2))
    b.append(title(378, 146, 'Separate switch: Show Contact Info'))
    for j, s in enumerate([
        'Sharing the link does NOT mark the tag as lost.',
        'Also turn on Show Contact Info (once called',
        'Lost Mode) with a phone number and message.',
        'Anyone who taps the tag with an NFC phone',
        'sees them.',
    ]):
        b.append(text(378, 176 + 24 * j, s))
    # keep a device online
    b.append(rect(360, 314, 390, 72))
    b.append(title(378, 340, 'Keep a device online'))
    b.append(text(378, 364, 'Updates need one of your devices online.'))
    return svg(760, 424, 'Four steps to share a lost bag with an airline, and two separate settings', b)


# ── Figure 8: a tracker that isn't yours ────────────────────────────────────
def f8():
    b = []
    b.append(rect(130, 10, 500, 62, stroke=None, fill=P))
    b.append(title(380, 32, '"AirTag Found Moving With You"', anchor='middle'))
    b.append(text(380, 55, 'on iPhone, or an unknown tracker alert on Android', anchor='middle', fill=T))
    b.append(arrow(380, 76, 380, 98))
    b.append(rect(130, 102, 500, 62))
    b.append(title(380, 124, 'Find it', anchor='middle'))
    b.append(text(380, 147, 'Tap the alert, then Play Sound, or Find Nearby if offered', anchor='middle'))
    b.append(arrow(380, 168, 380, 190))
    b.append(rect(130, 194, 500, 62))
    b.append(title(380, 216, 'Identify it', anchor='middle'))
    b.append(text(380, 239, "Hold your phone's top to the white side. Screenshot the page.", anchor='middle'))
    b.append(arrow(300, 260, 200, 288))
    b.append(arrow(460, 260, 560, 288))
    b.append(rect(10, 292, 360, 86, stroke=D, sw=2))
    b.append(title(190, 318, 'Feel unsafe?', anchor='middle'))
    b.append(text(190, 344, 'Go somewhere public and contact police first', anchor='middle'))
    b.append(rect(390, 292, 360, 86))
    b.append(title(570, 318, 'Otherwise, disable it', anchor='middle'))
    b.append(text(570, 342, 'Follow "Instructions to Disable":', anchor='middle'))
    b.append(text(570, 362, 'take the battery out', anchor='middle'))
    return svg(760, 388, 'What to do when you get an unknown tracker alert', b)


FIGURES = {
    'cover-people-devices-items': cover,
    'f1-find-my-network': f1,
    'f2-rotating-ids': f2,
    'f3-where-the-dot-comes-from': f3,
    'f4-three-radios': f4,
    'f5-app-parts': f5,
    'f6-phone-dies': f6,
    'f7-lost-luggage': f7,
    'f8-unwanted-tracker': f8,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for slug, fn in FIGURES.items():
        with open(os.path.join(OUT, f'{slug}.svg'), 'w', encoding='utf-8') as fh:
            fh.write(fn())
    print(f'wrote {len(FIGURES)} figures to {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
