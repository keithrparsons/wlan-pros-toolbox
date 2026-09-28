#!/usr/bin/env python3
"""Generate the Home Internet, Explained lesson figures.

Source of the drawings: the reviewed print guide
myPKA/Deliverables/2026-09-27-home-internet-guide/home-internet-guide.html
(cover art and Figures 1 to 6). The print figures were drawn for a light page,
so they are re-drawn here DARK-BAKED on the GL-003 §8.20.7 allow-list hexes,
the same convention as tool/find_my_diagrams.py:

  #E5E5E5 scaffold / primary label     -> light #4A4A4A
  #9C9C9C muted label / geometry       -> light #646464
  #A1CC3A lime (canonical)             -> light #5A7A1C
  #3A3A3A panel fill / hairline        -> light #E2E1E2
  rgba(162,204,58,0.08) lime wash      -> light wash

The print guide also uses a blue and an amber for some series. Neither is on
the allow-list (an off-list hex does not swap and reads inverted on light), so
those marks are redrawn in scaffold or muted gray with a distinct dash, and
every series keeps a text label beside it, so no mark is identified by color
alone. The one caption that names a color (Figure 5) is adjusted in the screen.

Rules this file keeps (GL-003 §11.7, §11.8, and the flutter_svg limits):
  - every presentation property is an inline attribute (no <style>, no class=);
  - no full-canvas background rectangle (the band's card is the canvas);
  - no <marker>, no <use>: arrowheads are drawn triangles, shapes are inlined;
  - every label string is identical to the print guide's label. Only line
    breaks and positions change. Label y values are BASELINES (flutter_svg
    ignores dominant-baseline, so the print guide's baselines carry over).
  - Figure 3 stays to scale (618 px for 35,786 km) and Figure 4 keeps the
    print guide's two axes (3.5 px/ms for 0 to 100 ms, 0.375 px/ms for 400 to
    800 ms). The high-orbit bar ends at 680 ms, the measured figure it is
    labeled with (the print guide now does the same).
  - No line crosses an icon or a label (Keith, 2026-09-27: "not have other
    icons or bit's being covered by other lines"). Lines stop short of the
    box they point at and enter the house through a wall opening.

Usage: python3 tool/home_internet_diagrams.py
       (writes assets/tool-diagrams/home-internet/)
"""

from __future__ import annotations

import os
from xml.sax.saxutils import escape

OUT = os.path.join(
    os.path.dirname(__file__), '..', 'assets', 'tool-diagrams', 'home-internet'
)

# Exact bundled family name: flutter_svg passes a CSS fallback list through as
# one family name and misses (see tool/find_my_diagrams.py).
FONT = 'IBM Plex Sans'

T = '#E5E5E5'  # primary label, scaffold
M = '#9C9C9C'  # muted label, secondary geometry
L = '#A1CC3A'  # lime (canonical; #A2CC3A is retired for new work, GL-003)
P = '#3A3A3A'  # panel fill, hairline
WASH = 'rgba(162,204,58,0.08)'


def text(x, y, s, size=13, fill=M, weight=400, anchor='start'):
    """A label with its BASELINE at [y]."""
    return (
        f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" '
        f'fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">'
        f'{escape(s)}</text>'
    )


def bold(x, y, s, size=14, fill=T, anchor='start'):
    return text(x, y, s, size=size, fill=fill, weight=600, anchor=anchor)


def rect(x, y, w, h, rx=6, stroke=None, sw=2, fill='none', opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    o = f' opacity="{opacity}"' if opacity is not None else ''
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}"{s}{o}/>'
    )


def line(x1, y1, x2, y2, stroke=M, sw=2, dash=None, cap='round'):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return (
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" '
        f'stroke-width="{sw}" stroke-linecap="{cap}"{d}/>'
    )


def path(d, stroke=M, sw=2, fill='none', dash=None, opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    ds = f' stroke-dasharray="{dash}"' if dash else ''
    o = f' opacity="{opacity}"' if opacity is not None else ''
    return (
        f'<path d="{d}" fill="{fill}"{s}{ds}{o} stroke-linecap="round" '
        f'stroke-linejoin="round"/>'
    )


def circle(cx, cy, r, stroke=None, sw=2, fill='none'):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"{s}/>'


def svg(w, h, label, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}" role="img" '
        f'aria-label="{escape(label, {chr(34): "&quot;"})}">\n'
        + '\n'.join(body)
        + '\n</svg>\n'
    )


def small_house(x, y):
    """The print guide's #hs symbol, inlined (flutter_svg and <use> disagree)."""
    return [
        path(f'M{x - 12} {y} L{x} {y - 10} L{x + 12} {y} Z', stroke=T, sw=2),
        rect(x - 10, y, 20, 14, rx=0, stroke=T, sw=2),
    ]


# The six service lines of the cover and Figure 1, top to bottom. The print
# guide colors them; here each keeps a distinct stroke pattern instead, and in
# Figure 1 each starts at its own text label.
#   (stroke, width, dash)
LINES = [
    (L, 4, None),        # Fiber
    (T, 4, None),        # Cable
    (M, 3, '9 6'),       # DSL
    (T, 3, '2 7'),       # Fixed wireless
    (L, 3, '2 7'),       # Satellite
    (M, 3, '2 7'),       # Phone hotspot
]


def wifi_arcs(cx, top, stroke=L):
    """Two broadcast arcs above a router centered at [cx]."""
    return [
        path(f'M{cx - 15} {top + 10} a18 18 0 0 1 30 0', stroke=stroke, sw=3),
        path(f'M{cx - 23} {top} a30 30 0 0 1 46 0', stroke=stroke, sw=3),
    ]


# ── Cover art: five roads into one house ────────────────────────────────────
def cover():
    # No background rules: they ran through the house. The lines come in
    # through an opening in the left wall and stop short of the provider's
    # box, which now sits inside the house (print guide, 2026-09-27 fix).
    b = []
    curves = [
        'M20 40 C220 40 300 120 490 151',
        'M20 90 C200 90 300 130 490 161.5',
        'M20 140 C200 140 300 142 490 172',
        'M20 190 C200 190 300 160 490 182.5',
        'M20 235 C200 235 320 175 490 193',
    ]
    for d, (stroke, sw, dash) in zip(curves, LINES):
        b.append(path(d, stroke=stroke, sw=sw, dash=dash))
    # The house (print guide: translate(470,60)).
    ox, oy = 470, 60
    b.append(path(f'M{ox} {oy + 70} L{ox + 90} {oy + 10} L{ox + 180} {oy + 70} Z',
                  stroke=T, sw=3))
    # Walls with an opening in the left wall (y 142 to 202) for the lines.
    b.append(path(f'M{ox + 14} {oy + 82} V{oy + 70} H{ox + 166} V{oy + 180} '
                  f'H{ox + 14} V{oy + 142}', stroke=T, sw=3))
    # The provider's box, inside the house.
    b.append(rect(ox + 26, oy + 88, 40, 48, rx=5, stroke=T, sw=2, fill=P))
    b.append(rect(ox + 100, oy + 110, 44, 26, rx=5, stroke=L, sw=2.5, fill=WASH))
    b.append(path(f'M{ox + 108} {oy + 100} a16 16 0 0 1 28 0', stroke=L, sw=3))
    b.append(path(f'M{ox + 102} {oy + 92} a26 26 0 0 1 40 0', stroke=L, sw=3))
    return svg(700, 250, 'Five kinds of line running into one house', b)


# ── Figure 1: six roads, one handoff point ──────────────────────────────────
def f1():
    b = []
    labels = [
        ('Fiber', 'strand of glass'),
        ('Cable', 'cable TV line (coax)'),
        ('DSL', 'old copper phone line'),
        ('Fixed wireless', '5G tower or local tower'),
        ('Satellite', 'dish, high or low orbit'),
        ('Phone hotspot', 'your cellular plan'),
    ]
    for i, (name, sub) in enumerate(labels):
        y = 44 + 50 * i
        b.append(bold(10, y, name))
        b.append(text(10, y + 16, sub, size=11.5))
    # Each line comes in through the wall opening and ends at x 419, short of
    # the provider's box at x 425.
    curves = [
        'M160 50 C280 50 320 150 419 158',
        'M160 100 C280 100 320 160 419 165',
        'M160 150 C280 150 320 172 419 172',
        'M160 200 C280 200 320 184 419 179',
        'M160 250 C280 250 320 196 419 186',
        'M160 300 C280 300 320 208 419 193',
    ]
    for d, (stroke, sw, dash) in zip(curves, LINES):
        b.append(path(d, stroke=stroke, sw=sw, dash=dash))
    # The house.
    b.append(path('M400 110 L530 40 L660 110', stroke=T, sw=3))
    # Walls with an opening in the left wall (y 150 to 202) for the lines.
    b.append(path('M410 150 V110 H650 V300 H410 V202', stroke=T, sw=3))
    # Provider's box (filled panel) and router (lime).
    b.append(rect(425, 152, 96, 46, rx=6, stroke=T, sw=2, fill=P))
    b.append(bold(473, 172, "Provider's", size=12, anchor='middle'))
    b.append(bold(473, 188, 'box', size=12, anchor='middle'))
    b.append(line(521, 175, 552, 175, stroke=T, sw=3, cap='butt'))
    b.append(rect(552, 152, 86, 46, rx=6, stroke=L, sw=2.5, fill=WASH))
    b.append(bold(595, 180, 'Router', size=13, anchor='middle'))
    b.append(path('M580 142 a18 18 0 0 1 30 0', stroke=L, sw=3))
    b.append(path('M572 132 a30 30 0 0 1 46 0', stroke=L, sw=3))
    # The handoff line.
    # Broken where it meets the box-to-router link, so it never crosses it.
    b.append(line(537, 120, 537, 166, stroke=M, sw=1.5, dash='4 4', cap='butt'))
    b.append(line(537, 184, 537, 292, stroke=M, sw=1.5, dash='4 4', cap='butt'))
    b.append(text(473, 232, 'The service', size=12, anchor='middle'))
    b.append(text(473, 248, 'you pay for', size=12, anchor='middle'))
    b.append(bold(595, 232, 'Your Wi-Fi', size=12, fill=L, anchor='middle'))
    b.append(text(595, 248, 'starts here', size=12, fill=L, anchor='middle'))
    return svg(
        700, 330,
        'Six ways in to one house, ending at the provider\'s box, then the router',
        b,
    )


# ── Figure 2: what each option shares ───────────────────────────────────────
def f2():
    b = []
    # Four panels. Panel frames are hairlines, not a canvas rectangle.
    for x, w in ((4, 166), (180, 166), (356, 166), (532, 164)):
        b.append(rect(x, 4, w, 242, rx=10, stroke=P, sw=1.5))

    # Panel 1: fiber.
    b.append(bold(87, 28, 'Fiber', size=13, anchor='middle'))
    b.append(line(87, 42, 87, 90, stroke=L, sw=4, cap='butt'))
    b.append(circle(87, 104, 9, stroke=T, sw=2))
    b.append(text(104, 98, 'splitter', size=10.5))
    # Drops start below the splitter and stop above each roof.
    for sx, ex, hx in ((85, 32, 30), (86, 69, 68), (88, 105, 106), (89, 142, 144)):
        b.append(line(sx, 117, ex, 164, stroke=L, sw=2.5))
        b += small_house(hx, 180)
    b.append(text(87, 220, 'one strand split', size=11, anchor='middle'))
    b.append(text(87, 235, 'among a group of homes', size=11, anchor='middle'))

    # Panel 2: cable.
    b.append(bold(263, 28, 'Cable', size=13, anchor='middle'))
    b.append(line(263, 42, 263, 87, stroke=L, sw=4, cap='butt'))
    b.append(rect(245, 92, 36, 22, rx=4, stroke=T, sw=2, fill=P))
    b.append(text(290, 108, 'node', size=10.5))
    b.append(line(200, 140, 326, 140, stroke=T, sw=3))
    b.append(line(263, 118, 263, 140, stroke=T, sw=3, cap='butt'))
    for hx in (206, 244, 282, 320):
        b.append(line(hx, 140, hx, 164, stroke=T, sw=2, cap='butt'))
        b += small_house(hx, 180)
    b.append(text(263, 220, 'one coax line', size=11, anchor='middle'))
    b.append(text(263, 235, 'shared along the street', size=11, anchor='middle'))

    # Panel 3: 5G home.
    b.append(bold(439, 28, '5G home', size=13, anchor='middle'))
    b.append(path('M439 50 L425 118 M439 50 L453 118 M430 92 H448', stroke=T, sw=2.5))
    # Broadcast arc lifted clear of the tower's apex (y 50); drawn at y 52 it
    # sat on the apex and the mast poked through it.
    b.append(path('M427 46 a16 16 0 0 1 24 0', stroke=M, sw=2))
    # Start below the tower's legs, stop above each roof and phone.
    for sx, ex, ey in ((437, 384, 162), (438, 421, 163), (440, 459, 162), (441, 496, 163)):
        b.append(line(sx, 124, ex, ey, stroke=M, sw=2, dash='2 5'))
    b += small_house(380, 180)
    b.append(rect(413, 170, 14, 24, rx=3, stroke=T, sw=2))
    b += small_house(460, 180)
    b.append(rect(493, 170, 14, 24, rx=3, stroke=T, sw=2))
    b.append(text(439, 220, 'one tower serves', size=11, anchor='middle'))
    b.append(text(439, 235, 'phones and homes', size=11, anchor='middle'))

    # Panel 4: satellite.
    b.append(bold(614, 28, 'Satellite', size=13, anchor='middle'))
    # The beam ends above the roofs (they peak at y 170).
    b.append(path('M614 62 L552 162 L676 162 Z', stroke=None, fill=WASH))
    b.append(path('M614 62 L552 162 M614 62 L676 162', stroke=L, sw=1.5, dash='3 4'))
    b.append(rect(602, 44, 24, 14, rx=2, stroke=T, sw=2, fill=P))
    b.append(rect(584, 47, 16, 8, rx=0, fill=M))
    b.append(rect(628, 47, 16, 8, rx=0, fill=M))
    for hx in (562, 598, 634, 668):
        b += small_house(hx, 180)
    b.append(text(614, 220, 'one beam covers', size=11, anchor='middle'))
    b.append(text(614, 235, 'an area of homes', size=11, anchor='middle'))
    return svg(
        700, 250,
        'Four panels: fiber, cable, 5G home and satellite, each shared by a '
        'group of homes',
        b,
    )


# ── Figure 3: height above the Earth, to scale ──────────────────────────────
def f3():
    # 618 px for 35,786 km, from x = 46 (the surface) to x = 664.
    def at(km):
        return round(46 + km / 35786 * 618, 1)

    b = []
    b.append(rect(40, 70, 6, 60, rx=0, fill=L))
    b.append(text(40, 150, "Earth's surface; ticks mark each height", size=11.5))
    # The scale is a line below the dots, with a tick at each true height,
    # so no dot sits on the line or on another dot.
    b.append(line(46, 124, 664, 124, stroke=M, sw=1.5, cap='butt'))
    for km in (480, 610, 20200):
        b.append(line(at(km), 124, at(km), 130, stroke=M, sw=1.5, cap='butt'))
    b.append(line(664, 124, 664, 130, stroke=M, sw=1.5, cap='butt'))
    # Low orbit: Starlink (~480 km) and Amazon Leo (590 to 630 km). At this
    # scale their ticks are 2 px apart, so the dots are drawn one above the
    # other, each over its own tick.
    b.append(circle(at(480), 94, 4, stroke=T, sw=1.5, fill=L))
    b.append(circle(at(610), 108, 4, stroke=T, sw=1.5, fill=M))
    b.append(line(58, 90, 118, 40, stroke=M, sw=1))
    b.append(bold(124, 40, 'Starlink, about 480 km (300 miles)', size=12.5))
    b.append(line(61, 106, 118, 62, stroke=M, sw=1))
    b.append(bold(124, 66, 'Amazon Leo, 590 to 630 km (370 to 390 miles)', size=12.5))
    # GPS, 20,200 km.
    b.append(circle(at(20200), 101, 5, stroke=T, sw=1.5, fill=M))
    b.append(text(at(20200), 88, 'GPS, 20,200 km', size=12.5, fill=T, anchor='middle'))
    # High orbit, 35,786 km.
    b.append(circle(664, 101, 7, stroke=T, sw=2, fill=P))
    b.append(bold(664, 72, 'High-orbit satellite', size=12.5, anchor='end'))
    b.append(text(664, 88, '35,786 km (22,236 miles)', size=12.5, fill=T, anchor='end'))
    return svg(
        700, 170,
        'Height above the Earth to scale: low-orbit satellites near the '
        'surface, GPS partway, high orbit at the far end',
        b,
    )


# ── Figure 4: delay with nothing else running ───────────────────────────────
def f4():
    # Axis A: 0 to 100 ms at x = 150..500 (3.5 px/ms).
    # Axis B: 400 to 800 ms at x = 540..690 (0.375 px/ms), after a break.
    def a(ms):
        return round(150 + ms * 3.5, 1)

    def bx(ms):
        return round(540 + (ms - 400) * 0.375, 1)

    b = []
    b.append(line(150, 210, 500, 210, stroke=M, sw=1, cap='butt'))
    b.append(text(150, 226, '0', size=11, anchor='middle'))
    b.append(text(325, 226, '50', size=11, anchor='middle'))
    b.append(text(500, 226, '100 ms', size=11, anchor='middle'))
    b.append(line(540, 210, 690, 210, stroke=M, sw=1, cap='butt'))
    b.append(text(540, 226, '400', size=11, anchor='middle'))
    b.append(text(690, 226, '800 ms', size=11, anchor='end'))
    b.append(path('M512 204 l8 12 M522 204 l8 12', stroke=M, sw=1.5))

    rows = [
        (37, 'Fiber', 7, 14, '7 to 14 ms', L),
        (75, 'Cable', 12, 24, '12 to 24 ms', L),
        (113, 'DSL', 23, 34, '23 to 34 ms', L),
        (151, 'Low-orbit satellite', 25, 60, "25 to 60 ms (Starlink's figure)", T),
    ]
    for base, name, lo, hi, label, fill in rows:
        b.append(bold(10, base, name, size=13))
        b.append(rect(a(lo), base - 13, round(a(hi) - a(lo), 1), 18, rx=3, fill=fill))
        b.append(text(round(a(hi) + 7, 1), base + 1, label, size=13, fill=T))

    b.append(bold(10, 189, 'High-orbit satellite', size=13))
    floor, measured = bx(480), bx(680)
    # No dashed floor marker: it ran through the bar. The bar starts at the
    # 480 ms floor and its label names it.
    b.append(rect(floor, 176, round(measured - floor, 1), 18, rx=3, fill=M))
    b.append(text(floor - 8, 190, 'physics alone: about 480 ms', size=11.5, fill=T, anchor='end'))
    b.append(text(round((floor + measured) / 2, 1), 170, 'measured: about 680 ms',
                  size=11.5, fill=T, anchor='middle'))
    return svg(
        700, 250,
        'Idle delay by service on a broken axis: fiber, cable, DSL and '
        'low-orbit satellite under 60 ms, high-orbit satellite 480 to 680 ms',
        b,
    )


# ── Figure 5: download and upload ───────────────────────────────────────────
def f5():
    # Each arrowhead stands clear of its bar (a 4 px gap), so it reads as its
    # own glyph: the legend line names the arrows, not the colors.
    def down(cx, tip):
        return path(f'M{cx} {tip} l-10 -10 h20 z', stroke=None, fill=L)

    def up(cx, tip):
        return path(f'M{cx} {tip} l-10 10 h20 z', stroke=None, fill=T)

    b = [text(20, 20, 'Down arrow: download. Up arrow: upload. Widths show the '
                      'usual balance, not exact speeds.', size=11.5)]
    # (center, name, note, download top, upload top)
    cols = [
        (95, 'Fiber', 'often equal', 45, 45),
        (275, 'Cable', 'upload much smaller', 45, 135),
        (455, '5G home', 'about a tenth', 45, 151),
        (620, 'DSL', 'low both ways', 115, 148),
    ]
    for cx, name, note, dtop, utop in cols:
        dx, ux = cx - 40, cx + 10
        b.append(rect(dx, dtop, 30, 165 - dtop, rx=4, fill=L))  # ends at 165
        b.append(down(dx + 15, 181))
        b.append(rect(ux, utop, 30, 165 - utop, rx=4, fill=T))
        b.append(up(ux + 15, utop - 14))
        b.append(text(cx, 198, note, size=11.5, anchor='middle'))
        b.append(bold(cx, 216, name, size=13, anchor='middle'))
    return svg(
        700, 226,
        'Download and upload bars for fiber, cable, 5G home and DSL',
        b,
    )


# ── Figure 6: where the FCC measures, and where you do ──────────────────────
def f6():
    b = []
    b.append(f'<ellipse cx="70" cy="120" rx="58" ry="34" fill="{P}" '
             f'stroke="{T}" stroke-width="2"/>')
    b.append(bold(70, 125, 'Internet', size=13, anchor='middle'))
    b.append(line(128, 120, 232, 120, stroke=T, sw=4, cap='butt'))
    b.append(text(180, 110, "provider's line", size=11.5, anchor='middle'))
    b.append(rect(232, 98, 86, 44, rx=6, stroke=T, sw=2, fill=P))
    b.append(bold(275, 124, "Provider's box", size=11, anchor='middle'))
    b.append(line(318, 120, 360, 120, stroke=T, sw=3, cap='butt'))
    b.append(rect(360, 98, 86, 44, rx=6, stroke=L, sw=2.5, fill=WASH))
    b.append(bold(403, 125, 'Router', size=13, anchor='middle'))
    # Starts past the Wi-Fi arcs (they reach x 508) and stops short of the
    # phone, so it crosses neither.
    b.append(line(516, 120, 598, 120, stroke=L, sw=3, dash='2 7'))
    b.append(path('M470 102 a14 14 0 0 1 0 36', stroke=L, sw=2.5))
    b.append(path('M484 94 a24 24 0 0 1 0 52', stroke=L, sw=2.5))
    b.append(text(545, 84, 'Wi-Fi, through walls', size=11.5, anchor='middle'))
    b.append(rect(605, 96, 30, 50, rx=5, stroke=T, sw=2.5))
    b.append(text(620, 164, 'your phone,', size=11.5, anchor='middle'))
    b.append(text(620, 178, 'back bedroom', size=11.5, anchor='middle'))
    # The two brackets. Each is named in words, so neither relies on its color.
    b.append(path('M20 60 V48 H446 V60', stroke=T, sw=2))
    b.append(bold(233, 38, 'What the FCC measures: the service, up to the router',
                  size=13, anchor='middle'))
    b.append(path('M20 200 V212 H660 V200', stroke=L, sw=2))
    b.append(bold(340, 232, 'What a speed test on your phone measures: the '
                            'service plus your Wi-Fi', size=13, fill=L, anchor='middle'))
    return svg(
        700, 240,
        'The FCC measures up to the router; a phone speed test measures the '
        'service plus the Wi-Fi',
        b,
    )


FIGURES = {
    'cover-roads-to-the-house': cover,
    'f1-six-roads': f1,
    'f2-every-road-is-shared': f2,
    'f3-orbit-heights': f3,
    'f4-idle-latency': f4,
    'f5-download-upload': f5,
    'f6-where-the-fcc-measures': f6,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for slug, fn in FIGURES.items():
        with open(os.path.join(OUT, f'{slug}.svg'), 'w', encoding='utf-8') as fh:
            fh.write(fn())
    print(f'wrote {len(FIGURES)} figures to {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
