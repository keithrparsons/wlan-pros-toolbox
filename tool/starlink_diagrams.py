#!/usr/bin/env python3
"""Generate the Starlink, Explained lesson figures.

Source of the drawings: the reviewed print guide
myPKA/Deliverables/2026-09-27-starlink-guide/starlink-guide.html (cover art
and Figures 1 to 9). The print figures were drawn for a light page, so they
are re-drawn here DARK-BAKED on the GL-003 §8.20.7 allow-list hexes, the same
convention as tool/find_my_diagrams.py:

  #E5E5E5 scaffold / primary label     -> light #4A4A4A
  #9C9C9C muted label / geometry       -> light #646464
  #A2CC3A lime                         -> light #5A7A1C
  #3A3A3A panel fill / hairline        -> light #E2E1E2
  #F26E6E danger, #E0A23A warning      -> light status tokens
  rgba(162,204,58,0.08) lime wash      -> light wash
  #1A1A1A                              -> unchanged (pass-through)

The print guide also uses a blue (#2B5C8A, #E6EEF6), a bronze (#8A5A00) and a
red (#A3261E). None is on the allow-list, so each is mapped by role:
  blue Earth / Internet cloud   -> panel fill #3A3A3A with a scaffold stroke
  blue Wi-Fi link (Figure 9)    -> scaffold #E5E5E5 (Link 1 stays lime; both
                                   links carry their own text label)
  blue fiber link (Figure 3)    -> muted #9C9C9C, dashed, as printed
  blue sky wedge (Figure 8)     -> lime wash
  bronze Hubble leader, trunk   -> warning #E0A23A
  red blocked satellite, drops  -> danger #F26E6E

Presenter legibility (Keith asked for the altitude comparison to read at
presenter size): label type is 13 to 16 px against a 700 to 760 px viewBox,
up from the print's 10.5 to 13, and Figure 2's labels are re-staggered on two
tiers above and below the axis so none collide at the larger size. Figures 1,
2, 4 and 6 keep the print geometry exactly, because they are to scale.

Rules this file keeps (GL-003 §11.7, §11.8, and the flutter_svg limits):
  - every presentation property is an inline attribute (no <style>, no class=);
  - no full-canvas background rectangle (the band's card is the canvas);
  - no <marker>: arrowheads are drawn triangles;
  - every label string is identical to the print guide's label. Only line
    breaks, positions and sizes change. One exception in form, not wording:
    Figure 5's degree sign is a drawn ring, because GL-003 §8.6.1 bars
    non-ASCII glyphs from <text>;
  - <text> carries ASCII only (GL-003 §8.6.1).

Usage: python3 tool/starlink_diagrams.py   (writes assets/tool-diagrams/starlink/)
"""

from __future__ import annotations

import math
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tool-diagrams', 'starlink')

# Exact bundled family name (see tool/find_my_diagrams.py for why a CSS
# fallback list silently misses in flutter_svg).
FONT = 'IBM Plex Sans'

T = '#E5E5E5'  # primary label, scaffold
M = '#9C9C9C'  # muted label, secondary geometry
L = '#A2CC3A'  # lime
P = '#3A3A3A'  # panel fill, hairline
W = '#E0A23A'  # warning (the print's bronze)
D = '#F26E6E'  # danger (the print's red)
K = '#1A1A1A'  # pass-through ink: identical in dark and light
WASH = 'rgba(162,204,58,0.08)'


def text(x, y, s, size=14, fill=M, weight=400, anchor='start'):
    # [y] is the visual middle of the line. flutter_svg ignores
    # dominant-baseline, so the baseline is placed explicitly (0.35 em below
    # the middle) and both a browser and the app draw it in the same place.
    base = round(y + size * 0.35, 1)
    return (
        f'<text x="{x}" y="{base}" font-family="{FONT}" font-size="{size}" '
        f'fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">'
        f'{escape(s)}</text>'
    )


def title(x, y, s, anchor='start', fill=T, size=15):
    return text(x, y, s, size=size, fill=fill, weight=600, anchor=anchor)


def rect(x, y, w, h, rx=0, stroke=None, sw=1.5, fill='none', opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    o = f' opacity="{opacity}"' if opacity is not None else ''
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{s}{o}/>'


def line(x1, y1, x2, y2, stroke=M, sw=2, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return (
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" '
        f'stroke-width="{sw}" stroke-linecap="round"{d}/>'
    )


def arrow(x1, y1, x2, y2, color=M, sw=2, head=12, dash=None):
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


def path(d, stroke=M, sw=2, fill='none', dash=None, opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    ds = f' stroke-dasharray="{dash}"' if dash else ''
    o = f' opacity="{opacity}"' if opacity is not None else ''
    return (
        f'<path d="{d}" fill="{fill}"{s}{ds}{o} stroke-linecap="round" '
        f'stroke-linejoin="round"/>'
    )


def svg(w, h, label, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}" role="img" aria-label="{escape(label, {chr(34): "&quot;"})}">\n'
        + '\n'.join(body)
        + '\n</svg>\n'
    )


def satellite(cx, cy, span=44, body=(20, 16), panel_h=10):
    """Body plus two lime solar panels, centered on (cx, cy)."""
    bw, bh = body
    pw = span - bw / 2 - 3
    return [
        rect(cx - span, cy - panel_h / 2, pw, panel_h, fill=L),
        rect(cx + bw / 2 + 3, cy - panel_h / 2, pw, panel_h, fill=L),
        rect(cx - bw / 2, cy - bh / 2, bw, bh, rx=2, fill=M),
    ]


def dish(foot, center, target, w, h, fill=T, mount=M, reach=4):
    """A flat panel on a short mount, square to its beam (Keith, 2026-09-27:
    "the Starlink thick line to tilt TOWARD the satellite").

    [foot] is where the mount meets the roof, [center] the middle of the
    panel, [target] where the beam points. The panel is rotated 90 degrees
    from the beam, so its face looks along it, and the beam leaves from the
    middle of the panel. Returns (marks, beam_start); the caller draws the
    beam from beam_start so it never starts inside the mount or the roof.
    """
    cx, cy = center
    ang = math.degrees(math.atan2(target[1] - cy, target[0] - cx))
    rot = round(ang + 90, 1)
    marks = [
        line(foot[0], foot[1], cx, cy, stroke=mount, sw=2),
        f'<rect x="{cx - w / 2}" y="{cy - h / 2}" width="{w}" height="{h}" rx="1" '
        f'fill="{fill}" transform="rotate({rot} {cx} {cy})"/>',
    ]
    r = math.radians(ang)
    start = (round(cx + reach * math.cos(r), 1), round(cy + reach * math.sin(r), 1))
    return marks, start


def house(x, y, w, h, roof, stroke=M, fill='none', sw=2):
    """A house outline, (x, y) the bottom-left corner."""
    return path(
        f'M{x} {y} V{y - h} L{x + w / 2} {y - h - roof} L{x + w} {y - h} V{y} Z',
        stroke=stroke, sw=sw, fill=fill,
    )


# ── Cover art: dish, satellite, gateway ─────────────────────────────────────
def cover():
    b = []
    b.append(path('M-20 250 Q350 150 720 250', stroke=M, sw=2, fill=P))
    for cx, cy in ((120, 60), (560, 45), (640, 95), (60, 120)):
        b.append(circle(cx, cy, 3, fill=M))
    b += satellite(360, 60, span=52)
    # house and dish
    b.append(house(250, 222, 56, 26, 20, stroke=T, sw=2))
    # Dish on a short mount above the roof (the print's (288,182) foot and
    # (290,170) panel), square to its beam.
    marks, (bx, by) = dish((288, 182), (290, 170), (352, 72), 20, 4, fill=T, mount=T)
    b += marks
    # gateway domes
    b.append(path('M458 212 A14 14 0 0 1 482 212 Z', stroke=T, sw=2))
    b.append(path('M480 214 A14 14 0 0 1 504 214 Z', stroke=T, sw=2))
    b.append(path(f'M{bx} {by} L352 72', stroke=L, sw=3, dash='6 6'))
    # Stops short of the domes (print: ends at (460,175)), so the line never
    # runs into the gateway it points at.
    b.append(path('M368 72 L460 177', stroke=L, sw=3, dash='6 6'))
    b.append(text(308, 122, 'your dish', size=16, fill=T, anchor='end'))
    b.append(text(432, 122, 'a gateway', size=16, fill=T))
    b.append(text(360, 24, 'about 480 km up', size=16, fill=T, anchor='middle'))
    return svg(700, 250, 'A dish on a house, a satellite about 480 km up, and a gateway', b)


# ── Figure 1: Earth and its satellites, to scale ────────────────────────────
# Print geometry kept exactly: Earth r = 70 px for 6,371 km (0.01099 px/km),
# GPS at r = 292 (20,200 km up), geostationary at r = 463 (35,786 km up), and
# the low-orbit ring at r = 76. The viewBox is widened from 700 to 740 only so
# the larger geostationary labels fit; nothing is rescaled.
def f1():
    b = []
    cx, cy = 82, 150
    b.append(circle(cx, cy, 70, stroke=T, sw=2, fill=P))
    b.append(title(cx, cy, 'Earth', anchor='middle', size=15))
    b.append(circle(cx, cy, 76, stroke=L, sw=3))
    b.append(path('M346.6 26.6 A292 292 0 0 1 346.6 273.4', stroke=M, sw=2, dash='5 5'))
    b.append(path('M522.3 6.9 A463 463 0 0 1 522.3 293.1', stroke=M, sw=2))
    b.append(line(138, 98, 170, 70, stroke=L, sw=2))
    b.append(title(176, 30, 'Low Earth orbit', size=16))
    b.append(text(176, 52, 'Space Station, Hubble,', size=15, fill=T))
    b.append(text(176, 72, 'Starlink and others,', size=15, fill=T))
    b.append(text(176, 92, 'all inside this thin line', size=15, fill=T))
    b.append(title(386, 140, 'GPS', size=16))
    b.append(text(386, 162, '20,200 km', size=15, fill=T))
    b.append(title(556, 132, 'Geostationary', size=16))
    b.append(text(556, 154, '35,786 km', size=15, fill=T))
    b.append(text(556, 176, 'satellite TV and older', size=15, fill=T))
    b.append(text(556, 196, 'satellite internet', size=15, fill=T))
    return svg(740, 300, 'Earth and its satellites, to scale: low Earth orbit, GPS and geostationary', b)


# ── Figure 2: the first 1,300 km, stretched out ─────────────────────────────
# To scale on the axis: x = 40 + 0.4769 px per km (0 km at 40, 1,000 km at
# 516.9, 1,300 km at 660), exactly the print's positions. Labels move onto
# two tiers above and two below the axis so they read at 15 px.
KM = 0.4769


def kx(km):
    return round(40 + KM * km, 1)


def f2():
    b = []
    ay = 110  # axis
    # Starlink: every FCC-approved height (340 to 535 km), main shell 480 km.
    # The caption calls the main shell "the dark tick": it is drawn in the
    # pass-through #1A1A1A, inside the lime band, so it reads as a dark tick on
    # the band in both themes.
    b.append(line(40, ay, 660, ay, stroke=M, sw=2))
    b.append(rect(kx(340), ay - 14, round(kx(535) - kx(340), 1), 28, fill=L, opacity=0.6))
    b.append(line(kx(480), ay - 13, kx(480), ay + 13, stroke=K, sw=5))
    for km, lab in ((0, '0 km'), (500, None), (1000, '1,000 km')):
        b.append(line(kx(km), ay - 5, kx(km), ay + 5, stroke=M, sw=2))
        if lab:
            b.append(text(kx(km), ay + 26, lab, size=13, fill=M, anchor='middle'))
    # Above the axis: Space Station, Iridium, OneWeb.
    for km, lab, col in ((410, 'Space Station, 400 to 420 km', T),
                         (780, 'Iridium, 780 km', M),
                         (1200, 'OneWeb, 1,200 km', M)):
        b.append(line(kx(km), 44, kx(km), ay - 6, stroke=col, sw=1.5))
        b.append(circle(kx(km), ay, 5, fill=col))
        b.append(text(kx(km), 30, lab, size=15, fill=T, anchor='middle'))
    # Below the axis, three rows: Amazon Leo, Starlink, Hubble. Each leader
    # drops to its own row and the text starts beside it, so no leader crosses
    # another label.
    b.append(rect(kx(590), ay - 7, round(kx(630) - kx(590), 1), 14, fill=M))
    b.append(line(kx(610), ay + 7, kx(610), 158, stroke=M, sw=1.5))
    b.append(text(kx(610) + 8, 158, 'Amazon Leo, 590 to 630 km', size=15, fill=T))
    b.append(line(212, 164, kx(400), ay + 14, stroke=L, sw=1.5))
    b.append(text(206, 164, 'Starlink: 340 to 535 km,', size=15, fill=L, weight=600, anchor='end'))
    b.append(text(206, 184, 'main shell 480 km', size=15, fill=L, weight=600, anchor='end'))
    # Starts below the band, clear of the main-shell tick at 480 km.
    b.append(line(kx(483), ay + 22, kx(483), 212, stroke=W, sw=1.5))
    b.append(text(kx(483) + 8, 212, 'Hubble, 483 km (NASA, June 2026)', size=15, fill=T))
    return svg(700, 228, 'Heights from 0 to 1,300 km: Space Station, Starlink, Hubble, Amazon Leo, Iridium, OneWeb', b)


# ── Figure 3: the usual path from a house ───────────────────────────────────
def f3():
    b = []
    b.append(line(0, 232, 700, 232, stroke=P, sw=2))
    b += satellite(270, 60)
    b.append(title(270, 26, 'Satellite, about 480 km up', anchor='middle', size=16))
    # house and dish
    b.append(house(40, 232, 80, 32, 28, stroke=M))
    # Dish on a short mount (print: foot (98,184), panel (100,163)), square to
    # the up-link arrow.
    marks, (ux, uy) = dish((98, 184), (100, 163), (250, 71), 24, 5)
    b += marks
    b.append(text(80, 254, 'Your dish', size=14, fill=T, anchor='middle'))
    # gateway
    b.append(path('M388 232 A22 22 0 0 1 432 232 Z', stroke=M, sw=2))
    b.append(path('M428 232 A22 22 0 0 1 472 232 Z', stroke=M, sw=2))
    b.append(text(430, 254, 'Starlink gateway', size=14, fill=T, anchor='middle'))
    # PoP
    b.append(rect(535, 198, 60, 34, rx=4, stroke=M, sw=2))
    b.append(text(565, 215, 'PoP', size=13, fill=M, anchor='middle'))
    b.append(text(565, 254, 'Point of Presence', size=14, fill=T, anchor='middle'))
    # internet
    for ccx, ccy, r in ((641, 140, 18), (663, 132, 20), (677, 146, 15)):
        b.append(circle(ccx, ccy, r, fill=P))
    b.append(title(660, 140, 'Internet', anchor='middle', size=14))
    # links
    b.append(arrow(ux, uy, 250, 71, color=L, sw=3))
    # Ends about 30 px above the dome (print: (398,178)), not on it.
    b.append(arrow(290, 74, 398, 178, color=L, sw=3))
    b.append(line(478, 222, 530, 222, stroke=M, sw=3, dash='3 5'))
    b.append(line(598, 208, 636, 164, stroke=M, sw=3, dash='3 5'))
    b.append(text(152, 104, '1. Up to', size=14, fill=L, anchor='end'))
    b.append(text(152, 122, 'the satellite', size=14, fill=L, anchor='end'))
    b.append(text(368, 120, '2. Down to', size=14, fill=L))
    b.append(text(368, 138, 'a gateway', size=14, fill=L))
    b.append(text(503, 204, '3. Fiber', size=14, fill=M, anchor='middle'))
    return svg(700, 270, 'Dish to satellite to gateway, then fiber to a Point of Presence and the internet', b)


# ── Figure 4: latency, Starlink against geostationary ───────────────────────
# To scale on the top chart: 0.7167 px per ms (0 at 140, 600 ms at 570).
def f4():
    b = []
    # Short ticks under the axis labels, not full-height gridlines: a
    # gridline ran through the Starlink label and the geostationary bar.
    for x, lab in ((140, '0 ms'), (355, '300 ms'), (570, '600 ms')):
        b.append(line(x, 23, x, 31, stroke=M, sw=1.5))
        b.append(text(x, 14, lab, size=13, fill=M, anchor='middle'))
    b.append(text(130, 50, 'Starlink', size=14, fill=T, anchor='end'))
    b.append(rect(140, 38, 18, 24, fill=L))
    b.append(rect(158, 38, 25, 24, fill=L, opacity=0.45))
    b.append(text(192, 50, 'about 25 ms typical, 25 to 60 ms range', size=14, fill=L))
    b.append(text(130, 98, 'Geostationary', size=14, fill=T, anchor='end'))
    b.append(rect(140, 86, 430, 24, fill=P, stroke=M, sw=1.5))
    b.append(rect(570, 86, 72, 24, fill=P, stroke=M, sw=1.5, opacity=0.5))
    b.append(text(355, 98, 'about 600 to 700 ms', size=14, fill=T, anchor='middle'))
    # zoom
    b.append(title(20, 156, "Zoomed in: inside Starlink's 25 ms (not to the scale above)", size=15))
    b.append(rect(20, 172, 264, 36, fill=WASH, stroke=L, sw=2))
    b.append(rect(284, 172, 396, 36, fill=P))
    b.append(text(152, 190, 'Radio trip, under 10 ms', size=14, fill=T, anchor='middle'))
    b.append(text(482, 190, 'Ground network, scheduling, waiting in line', size=14, fill=T, anchor='middle'))
    b.append(text(20, 234, 'SpaceX: each leg between dish, satellite and gateway takes 1.8 to 3.6 ms at the speed of light,', size=13, fill=M))
    b.append(text(20, 254, 'usually under 10 ms for the whole round trip. The rest is spent on the ground and in queues.', size=13, fill=M))
    return svg(700, 268, 'Latency bars: Starlink about 25 ms against geostationary about 600 to 700 ms, and what fills the 25 ms', b)


# ── Figure 5: a phased array ────────────────────────────────────────────────
def f5():
    b = []
    b.append(path('M350 190 L180 80 A200 200 0 0 1 520 80 Z', stroke=None, fill=WASH))
    b.append(line(350, 190, 180, 80, stroke=M, sw=1.5, dash='4 4'))
    b.append(line(350, 190, 520, 80, stroke=M, sw=1.5, dash='4 4'))
    b.append(path('M350 190 L250 40 L275 36 Z', stroke=None, fill=L, opacity=0.35))
    b.append(path('M350 190 L345 25 L372 26 Z', stroke=None, fill=L, opacity=0.7))
    b.append(path('M350 190 L452 42 L474 50 Z', stroke=None, fill=L, opacity=0.35))
    for sx, sy in ((262, 34), (358, 20), (464, 42)):
        b.append(circle(sx, sy, 5, fill=T))
    b.append(rect(290, 190, 120, 16, rx=3, fill=P, stroke=T, sw=1.5))
    for i in range(9):
        b.append(rect(296 + 12 * i, 195, 6, 6, fill=L))
    b.append(text(350, 226, 'Many small antennas, one flat panel. The panel stays still.', size=14, fill=T, anchor='middle'))
    # "110° field of view": the degree sign is drawn as a ring, never as a
    # <text> glyph (GL-003 §8.6.1: non-ASCII in <text> tofus on the web
    # path). "110" is anchored at its END so the ring sits against it in any
    # renderer, whatever the font's digit widths.
    b.append(title(569, 104, '110', anchor='end', size=15))
    b.append(circle(573.5, 97, 2.6, stroke=T, sw=1.6))
    b.append(title(582, 104, 'field of view', size=15))
    b.append(text(540, 124, 'the part of the sky', size=14, fill=M))
    b.append(text(540, 142, 'the dish can use', size=14, fill=M))
    b.append(text(214, 112, 'The beam swings', size=14, fill=M, anchor='end'))
    b.append(text(214, 130, 'from satellite to', size=14, fill=M, anchor='end'))
    b.append(text(214, 148, 'satellite electronically', size=14, fill=M, anchor='end'))
    return svg(700, 240, 'A flat panel of small antennas steering one beam between satellites across a 110 degree field of view', b)


# ── Figure 6: the current dishes, to scale ──────────────────────────────────
# To scale: about 3.0 px per cm (Standard 4 59 x 38 cm = 178 x 115 px), with
# the 20 cm bar at 60 px, exactly as printed.
def f6():
    b = []
    b.append(rect(40, 10, 178, 115, rx=6, fill=P, stroke=T, sw=2))
    b.append(rect(290, 33, 115, 92, rx=6, fill=P, stroke=T, sw=2))
    b.append(rect(480, 47, 90, 78, rx=6, fill=P, stroke=T, sw=2))
    b.append(title(129, 146, 'Standard 4 X and Standard 4', anchor='middle', size=14))
    b.append(text(129, 166, '59 x 38 cm, 2.9 kg', size=13, fill=M, anchor='middle'))
    b.append(title(347, 146, 'Starlink V5', anchor='middle', size=14))
    b.append(text(347, 166, '38 x 31 cm, 1.1 kg', size=13, fill=M, anchor='middle'))
    b.append(title(525, 146, 'Mini', anchor='middle', size=14))
    b.append(text(525, 166, '30 x 26 cm, 1.1 kg', size=13, fill=M, anchor='middle'))
    b.append(line(610, 125, 670, 125, stroke=M, sw=2))
    b.append(line(610, 119, 610, 131, stroke=M, sw=2))
    b.append(line(670, 119, 670, 131, stroke=M, sw=2))
    b.append(text(640, 110, '20 cm', size=13, fill=M, anchor='middle'))
    return svg(700, 180, 'Three dishes to scale: Standard 4 X and Standard 4, Starlink V5, Mini, with a 20 cm scale bar', b)


# ── Figure 7: neighbors share the capacity overhead ─────────────────────────
def f7():
    b = []
    b.append(title(175, 16, 'Quiet morning', anchor='middle', size=15))
    b.append(title(525, 16, 'Busy evening', anchor='middle', size=15))
    b.append(line(350, 8, 350, 242, stroke=P, sw=2))
    for cx in (175, 525):
        b += satellite(cx, 48, span=30, body=(16, 12), panel_h=8)
        # Cone base sits above the roofs (roof peaks at y 149), so the wash
        # never covers a house.
        b.append(path(f'M{cx} 58 L{cx - 89} 140 L{cx + 89} 140 Z', stroke=None, fill=L, opacity=0.15))
    # left: 2 of 6 homes online (filled); right: all 6 online
    left = [(90, False), (120, True), (150, False), (180, False), (210, False), (240, True)]
    for x, on in left:
        b.append(house(x, 172, 24, 14, 9, stroke=M, sw=1.5, fill=L if on else 'none'))
    for x in (440, 470, 500, 530, 560, 590):
        b.append(house(x, 172, 24, 14, 9, stroke=M, sw=1.5, fill=L))
    b.append(text(175, 192, '2 homes online share the capacity', size=14, fill=T, anchor='middle'))
    b.append(text(525, 192, '6 homes online share the same capacity', size=14, fill=T, anchor='middle'))
    b.append(text(30, 224, 'each home', size=13, fill=M))
    b.append(rect(110, 216, 190, 16, fill=L))
    b.append(text(380, 224, 'each home', size=13, fill=M))
    b.append(rect(460, 216, 64, 16, fill=L))
    return svg(700, 248, 'Quiet morning, 2 homes online share the capacity; busy evening, 6 homes share the same capacity', b)


# ── Figure 8: one tree, repeated short drops ────────────────────────────────
def f8():
    b = []
    b.append(path('M350 200 L170 80 A216 216 0 0 1 530 80 Z', stroke=None, fill=WASH))
    # The blocked wedge's edge meets the end of the sky arc (530,80), so no
    # sliver of clear sky shows outside it.
    b.append(path('M350 200 L475 24 A216 216 0 0 1 530 80 Z', stroke=None, fill=M, opacity=0.35))
    # tree
    b.append(rect(434, 145, 12, 62, fill=W))
    b.append(circle(440, 125, 30, fill=L))
    # satellite path
    b.append(path('M200 70 Q350 -10 520 62', stroke=T, sw=1.5, dash='3 5'))
    b.append(circle(250, 44, 5, fill=T))
    b.append(circle(350, 30, 5, fill=T))
    b.append(circle(505, 57, 7, fill=D))
    b.append(text(540, 44, 'blocked here', size=14, fill=D, weight=600))
    # dish
    b.append(rect(325, 200, 50, 8, rx=2, fill=T))
    b.append(text(350, 226, 'Your dish', size=14, fill=T, anchor='middle'))
    b.append(text(166, 146, 'Clear sky the', size=14, fill=M, anchor='end'))
    b.append(text(166, 164, 'dish can use', size=14, fill=M, anchor='end'))
    # timeline
    b.append(rect(120, 248, 460, 14, fill=L))
    for x in (240, 390, 540):
        b.append(rect(x, 248, 14, 14, fill=D))
    b.append(text(110, 255, 'Service', size=13, fill=M, anchor='end'))
    b.append(text(590, 255, 'short drops', size=13, fill=D, weight=600))
    return svg(700, 272, 'A tree hides part of the sky, so each satellite that passes behind it causes a short drop', b)


# ── Figure 9: two networks in one house ─────────────────────────────────────
def f9():
    b = []
    b.append(path('M60 200 V90 L200 20 L340 90 V200 Z', stroke=M, sw=2))
    # Dish on a short mount (print: foot (248,45), panel (250,26)), square to
    # the Link 1 beam.
    marks, (bx, by) = dish((248, 45), (250, 26), (286, 2), 26, 6)
    b += marks
    b.append(line(bx, by, 286, 2, stroke=L, sw=4))
    # The cable drops from the mount, crosses ABOVE the Wi-Fi arcs and enters
    # the top of the router, so it never runs through the arcs.
    b.append(path('M248 45 V110 H130 V140', stroke=M, sw=2))
    b.append(rect(110, 140, 40, 22, rx=4, fill=P, stroke=T, sw=1.5))
    # Under the router, inside the wall and below the lowest arc end
    # (172,180). The print right-aligns it at 11.5 px; at the app's 14 px a
    # right-aligned label would touch the wall at x 60.
    b.append(text(70, 185, 'Starlink router', size=14, fill=T))
    b.append(path('M156 140 q12 12 0 24 M164 132 q20 20 0 40 M172 124 q28 28 0 56', stroke=T, sw=2))
    b.append(rect(280, 128, 14, 24, rx=3, stroke=T, sw=2))
    b.append(text(287, 170, 'phone in the', size=14, fill=T, anchor='middle'))
    b.append(text(287, 188, 'back room', size=14, fill=T, anchor='middle'))
    b.append(title(376, 36, 'Link 1: the Starlink link', fill=L, size=16))
    b.append(text(376, 58, 'dish to satellite and back', size=14, fill=M))
    b.append(title(376, 122, 'Link 2: your Wi-Fi', fill=T, size=16))
    b.append(text(376, 144, 'router to phone, through walls,', size=14, fill=M))
    b.append(text(376, 162, "cabinets, or an RV's metal body", size=14, fill=M))
    return svg(700, 210, 'Link 1, dish to satellite; Link 2, the Wi-Fi from the Starlink router to a phone in the back room', b)


FIGURES = {
    'cover-dish-satellite-gateway': cover,
    'f1-orbits-to-scale': f1,
    'f2-first-1300-km': f2,
    'f3-data-path': f3,
    'f4-latency': f4,
    'f5-phased-array': f5,
    'f6-dishes-to-scale': f6,
    'f7-shared-capacity': f7,
    'f8-tree-drops': f8,
    'f9-two-links': f9,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for slug, fn in FIGURES.items():
        with open(os.path.join(OUT, f'{slug}.svg'), 'w', encoding='utf-8') as fh:
            fh.write(fn())
    print(f'wrote {len(FIGURES)} figures to {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
