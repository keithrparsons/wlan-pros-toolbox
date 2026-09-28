#!/usr/bin/env python3
"""Generate the Wi-Fi Calling, Explained lesson figures.

Source of the drawings: the reviewed print guide
myPKA/Deliverables/2026-09-27-wifi-calling-guide/wifi-calling-guide.html (cover
art and Figures 1 to 8). The print figures were drawn for a light page, so they
are re-drawn here DARK-BAKED on the GL-003 §8.20.7 allow-list hexes, the same
convention as tool/find_my_diagrams.py:

  #E5E5E5 scaffold / primary label     -> light #4A4A4A
  #9C9C9C muted label / geometry       -> light #646464
  #A2CC3A lime                         -> light #5A7A1C
  #3A3A3A panel fill / hairline        -> light #E2E1E2
  #F26E6E danger, #E0A23A warning      -> light status tokens

Light mode is produced at runtime by ConceptGraphicBand.applyLightSwap, so no
light copy is authored. Rules this file keeps (GL-003 §11.7, §11.8, and the
flutter_svg limits):
  - every presentation property is an inline attribute (no <style>, no class=);
  - no full-canvas background rectangle (the band's card is the canvas);
  - no <marker>: arrowheads are drawn triangles;
  - the font-family is the exact bundled name, never a CSS fallback list;
  - baselines are explicit (flutter_svg ignores dominant-baseline); the y of
    every label here is the print guide's own baseline;
  - every label string is identical to the print guide's label, with ONE
    exception: Figure 7's "(page 6)" reads "(section 5)", because a scrolling
    lesson has no pages and the emergency-calls page is section 5 on screen.
    Only line breaks and positions change otherwise.
  - The guide's blue (#2B5C8A) and ink (#1A1A1A) fills are not on the
    allow-list, so dark boxes become panel fills with a scaffold outline.

Usage: python3 tool/wifi_calling_diagrams.py
       (writes assets/tool-diagrams/wifi-calling/)
"""

from __future__ import annotations

import math
import os
from xml.sax.saxutils import escape

OUT = os.path.join(
    os.path.dirname(__file__), '..', 'assets', 'tool-diagrams', 'wifi-calling'
)

FONT = 'IBM Plex Sans'

T = '#E5E5E5'  # primary label, scaffold
M = '#9C9C9C'  # muted label, secondary geometry
L = '#A2CC3A'  # lime
P = '#3A3A3A'  # panel fill, hairline
W = '#E0A23A'  # warning
D = '#F26E6E'  # danger


def text(x, y, s, size=13, fill=M, weight=400, anchor='start'):
    """[y] is the BASELINE, matching the print guide's own coordinates."""
    return (
        f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" '
        f'fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">'
        f'{escape(s)}</text>'
    )


def title(x, y, s, size=13, fill=T, anchor='start'):
    return text(x, y, s, size=size, fill=fill, weight=600, anchor=anchor)


def rect(x, y, w, h, rx=12, stroke=M, sw=1.5, fill='none', opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    o = f' fill-opacity="{opacity}"' if opacity is not None else ''
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
        f'fill="{fill}"{o}{s}/>'
    )


def line(x1, y1, x2, y2, stroke=M, sw=2):
    return (
        f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{stroke}" '
        f'stroke-width="{sw}" stroke-linecap="round"/>'
    )


def arrow(x1, y1, x2, y2, color=M, sw=2.5, head=10):
    """A line from (x1,y1) to (x2,y2) with a drawn triangle head at the end."""
    ang = math.atan2(y2 - y1, x2 - x1)
    bx, by = x2 - head * math.cos(ang), y2 - head * math.sin(ang)
    half = head * 0.5
    px, py = -math.sin(ang) * half, math.cos(ang) * half
    tri = (
        f'<path d="M{x2:.2f} {y2:.2f} L{bx + px:.2f} {by + py:.2f} '
        f'L{bx - px:.2f} {by - py:.2f} Z" fill="{color}"/>'
    )
    return line(x1, y1, round(bx, 2), round(by, 2), color, sw) + tri


def circle(cx, cy, r, stroke=None, sw=2, fill='none'):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"{s}/>'


def path(d, stroke=M, sw=2, fill='none', dash=None, opacity=None):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
    ds = f' stroke-dasharray="{dash}"' if dash else ''
    o = f' stroke-opacity="{opacity}"' if opacity is not None else ''
    return (
        f'<path d="{d}" fill="{fill}"{s}{ds}{o} stroke-linecap="round" '
        f'stroke-linejoin="round"/>'
    )


def svg(w, h, label, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}" role="img" '
        f'aria-label="{escape(label, {chr(34): "&quot;"})}">\n'
        + '\n'.join(body)
        + '\n</svg>\n'
    )


# ── shared glyphs ────────────────────────────────────────────────────────────
def phone(cx, cy, w=44, h=80, stroke=T):
    return [
        rect(cx - w / 2, cy - h / 2, w, h, rx=8, stroke=stroke, sw=2.5),
        rect(cx - w / 2 + 5, cy - h / 2 + 7, w - 10, h - 16, rx=4, stroke=None, fill=P),
    ]


def tower(cx, cy, s=1.0, arcs=2):
    b = [
        path(
            f'M{cx} {cy - 24 * s}L{cx - 13 * s} {cy + 22 * s}'
            f'M{cx} {cy - 24 * s}L{cx + 13 * s} {cy + 22 * s}'
            # A center mast, not a crossbar: a crossbar reads as the letter A.
            f'M{cx} {cy - 24 * s}V{cy + 22 * s}',
            stroke=T, sw=2.5,
        ),
        path(f'M{cx - 12 * s} {cy - 29 * s}a{16 * s} {16 * s} 0 0 1 {24 * s} 0',
             stroke=M, sw=2.5),
    ]
    if arcs > 1:
        b.append(path(f'M{cx - 19 * s} {cy - 35 * s}a{26 * s} {26 * s} 0 0 1 {38 * s} 0',
                      stroke=M, sw=2.5))
    return b


def wifi(cx, cy, s=1.0, color=L):
    return [
        path(f'M{cx - 20 * s} {cy - 8 * s}a{28 * s} {28 * s} 0 0 1 {40 * s} 0', stroke=color, sw=3),
        path(f'M{cx - 13 * s} {cy - 1 * s}a{18 * s} {18 * s} 0 0 1 {26 * s} 0', stroke=color, sw=3),
        path(f'M{cx - 6 * s} {cy + 6 * s}a{8 * s} {8 * s} 0 0 1 {12 * s} 0', stroke=color, sw=3),
        circle(cx, cy + 12 * s, 3 * s, fill=color),
    ]


def laptop(cx, cy, stroke=T):
    return [
        rect(cx - 45, cy - 32, 90, 58, rx=5, stroke=stroke, sw=2.5),
        rect(cx - 40, cy - 27, 80, 48, rx=2, stroke=None, fill=P),
        rect(cx - 58, cy + 28, 116, 6, rx=3, stroke=None, fill=M),
    ]


def carrier_box(x, y, w, h, lines, size=14):
    b = [rect(x, y, w, h, rx=10, stroke=T, sw=2, fill=P)]
    cx = x + w / 2
    top = y + h / 2 - (len(lines) - 1) * (size + 2) / 2 + size * 0.35
    for i, s in enumerate(lines):
        b.append(title(cx, round(top + i * (size + 2), 1), s, size=size, anchor='middle'))
    return b


# ── Cover art: two roads to the same phone company ──────────────────────────
def cover():
    b = []
    b.append(path('M110 125 C230 40 420 40 560 110', stroke=M, sw=3, dash='2 8'))
    b.append(path('M110 135 C230 220 420 220 560 140', stroke=L, sw=10, opacity=0.3))
    b.append(path('M110 135 C230 220 420 220 560 140', stroke=L, sw=3))
    b += phone(80, 130)
    # handset glyph on the phone's screen
    b.append(path(
        'M72 124c4 6 10 12 16 15l4-4c1-1 3-1 4 0l5 4c1 1 1 3 0 4l-3 3c-3 3-10 1-18-7'
        's-10-15-7-18l3-3c1-1 3-1 4 0l4 5c1 1 1 3 0 4z',
        stroke=None, fill=L,
    ))
    b += tower(330, 52)
    b.append(text(330, 98, 'Cell tower', size=15, fill=T, anchor='middle'))
    b += wifi(330, 200, s=1.0)
    b.append(text(330, 240, 'Wi-Fi and the internet', size=15, fill=T, anchor='middle'))
    b += carrier_box(556, 87, 88, 76, ['Your phone', 'company'])
    b.append(text(600, 187, 'Same call, same number', size=15, fill=T, anchor='middle'))
    return svg(700, 250, 'Two roads, the cell tower and Wi-Fi with the internet, '
               'from your phone to your phone company', b)


# ── Figure 1: two roads to the same phone company ───────────────────────────
def f1():
    b = []
    b += phone(55, 150, w=48, h=88)
    b.append(title(55, 216, 'Your phone', anchor='middle'))
    # top road
    b.append(title(95, 20, 'CELLULAR: 4G or 5G calling', size=12, fill=T))
    b.append(arrow(85, 120, 230, 70))
    b += tower(260, 68, s=0.95, arcs=1)
    b.append(text(260, 110, 'Cell tower', fill=T, anchor='middle'))
    b.append(arrow(290, 70, 545, 120))
    b.append(text(375, 66, "the carrier's own cell network", size=11.5))
    # bottom road: the tunnel
    b.append(title(95, 290, 'WI-FI CALLING: a locked tunnel', size=12, fill=L))
    b.append(rect(120, 205, 420, 36, rx=18, stroke=None, fill=L, opacity=0.2))
    b.append(rect(120, 205, 420, 36, rx=18, stroke=L, sw=2.5))
    b.append(line(85, 180, 118, 215, stroke=L, sw=2.5))
    b.append(path('M171 219a19 19 0 0 1 28 0M177 225a10 10 0 0 1 16 0', stroke=L, sw=2.5))
    b.append(circle(185, 230, 2.5, fill=L))
    b.append(text(185, 262, 'a Wi-Fi network', size=11.5, anchor='middle'))
    b.append(circle(320, 223, 12, stroke=L, sw=2.2))
    b.append(path('M308 223H332M320 211C314 217 314 229 320 235M320 211C326 217 326 229 320 235',
                  stroke=L, sw=1.6))
    b.append(text(320, 262, 'the public internet', size=11.5, anchor='middle'))
    b.append(rect(445, 218, 20, 16, rx=3, stroke=None, fill=L))
    b.append(path('M449 218v-5a6 6 0 0 1 12 0v5', stroke=L, sw=2.5))
    b.append(text(455, 262, 'sealed to the carrier', size=11.5, anchor='middle'))
    b.append(arrow(540, 223, 560, 185, color=L))
    # carrier
    b.append(rect(560, 95, 190, 110, rx=12, stroke=T, sw=2, fill=P))
    b.append(title(655, 130, 'Your carrier', size=14, anchor='middle'))
    b.append(text(655, 152, 'One calling system', size=12, fill=T, anchor='middle'))
    b.append(text(655, 170, 'for both roads', size=12, fill=T, anchor='middle'))
    b.append(text(655, 190, 'then on to anyone', size=12, fill=L, anchor='middle'))
    return svg(760, 300, 'Two roads from your phone to your carrier: a cell tower, '
               'or a locked tunnel over Wi-Fi and the internet', b)


# ── Figure 2: when your phone uses Wi-Fi ────────────────────────────────────
def f2():
    b = [
        '<defs><linearGradient id="wc-signal" x1="0" x2="1" y1="0" y2="0">'
        f'<stop offset="0" stop-color="{D}"/>'
        f'<stop offset="0.5" stop-color="{W}"/>'
        f'<stop offset="1" stop-color="{L}"/>'
        '</linearGradient></defs>',
    ]
    b.append(title(30, 30, 'Cell signal where you are standing'))
    b.append('<rect x="30" y="45" width="700" height="22" rx="11" fill="url(#wc-signal)"/>')
    b.append(text(30, 88, 'None or very weak', size=12))
    b.append(text(730, 88, 'Strong', size=12, anchor='end'))
    b.append(rect(30, 105, 330, 110, stroke=L, sw=2))
    b.append(title(50, 132, 'Weak or no cell signal'))
    for i, s in enumerate([
        'The call goes over Wi-Fi Calling.',
        'The basement office, the thick-walled',
        'house, the cabin with no cell signal.',
    ]):
        b.append(text(50, 154 + 18 * i, s, size=12))
    b.append(rect(400, 105, 330, 110, stroke=M, sw=2))
    b.append(title(420, 132, 'Good cell signal'))
    for i, s in enumerate([
        'The call usually goes over the cell',
        'network, even with Wi-Fi Calling on.',
        'Some phones let you change this.',
    ]):
        b.append(text(420, 154 + 18 * i, s, size=12))
    return svg(760, 230, 'A cell-signal scale from none to strong, and which road the '
               'call takes at each end', b)


# ── Figure 3: walking out the door mid-call ─────────────────────────────────
def f3():
    b = []
    b.append(path('M40 150 L120 85 L200 150 V225 H40 Z', stroke=T, sw=2.5))
    b.append(path('M104 146a22 22 0 0 1 32 0M111 153a12 12 0 0 1 18 0', stroke=L, sw=3))
    b.append(circle(120, 159, 3, fill=L))
    b.append(text(120, 200, 'Call starts', size=12, anchor='middle'))
    b.append(text(120, 216, 'on Wi-Fi', size=12, anchor='middle'))
    b.append(arrow(205, 150, 300, 150))
    b.append(text(252, 140, 'you walk out', size=11.5, anchor='middle'))
    b.append(rect(310, 20, 430, 62, rx=10, stroke=L, sw=2))
    b.append(title(330, 45, 'Into 4G or 5G calling coverage', fill=L))
    b.append(text(330, 66, 'The call can hand over to the cell network and carry on.', size=12))
    b.append(rect(310, 96, 430, 62, rx=10, stroke=D, sw=2))
    b.append(title(330, 121, 'Into weak coverage, or no 4G calling', fill=D))
    b.append(text(330, 142, 'The call drops. There is nothing for it to hand over to.', size=12))
    b.append(rect(310, 172, 430, 62, rx=10, stroke=None, fill=D, opacity=0.12))
    b.append(rect(310, 172, 430, 62, rx=10, stroke=D, sw=2))
    b.append(title(330, 197, 'An emergency call on AT&T', fill=D))
    b.append(text(330, 218, 'Disconnects either way, even inside 4G calling coverage.', size=12))
    return svg(760, 250, 'A call that starts on Wi-Fi at home, and three outcomes when '
               'you walk out', b)


# ── Figure 4: an emergency call with Wi-Fi Calling on ───────────────────────
def f4():
    b = []
    b.append(rect(20, 100, 150, 70, rx=12, stroke=None, fill=D, opacity=0.15))
    b.append(rect(20, 100, 150, 70, rx=12, stroke=D, sw=2))
    b.append(title(95, 132, 'You dial', size=14, anchor='middle'))
    b.append(title(95, 152, '911', size=14, anchor='middle'))
    b.append(arrow(170, 135, 215, 135))
    b.append(path('M300 88 L375 135 L300 182 L225 135 Z', stroke=T, sw=2))
    b.append(title(300, 131, 'Any cell', size=12, anchor='middle'))
    b.append(title(300, 147, 'network?', size=12, anchor='middle'))
    b.append(path('M300 88 V60', stroke=M, sw=2.5))
    b.append(arrow(300, 60, 440, 60))
    b.append(title(340, 52, 'Yes', size=12, fill=L))
    b.append(rect(445, 25, 295, 70, rx=10, stroke=L, sw=2))
    b.append(title(462, 52, 'The phone uses the cell network'))
    b.append(text(462, 74, 'even in airplane mode, even with Wi-Fi Calling on', size=12))
    b.append(path('M300 182 V210', stroke=M, sw=2.5))
    b.append(arrow(300, 210, 440, 210))
    b.append(title(340, 228, 'No', size=12, fill=D))
    b.append(rect(445, 160, 295, 100, rx=10, stroke=W, sw=2))
    b.append(title(462, 186, 'The call may go over Wi-Fi Calling'))
    for i, s in enumerate([
        "The carrier tries your device's location.",
        'If that fails, it can use the address you',
        'registered when you turned the feature on.',
    ]):
        b.append(text(462, 208 + 18 * i, s, size=12))
    return svg(760, 270, 'An emergency call: is any cell network there? Yes, the phone '
               'uses it. No, the call may go over Wi-Fi Calling', b)


# ── Figure 5: iPad, Mac and Apple Watch ─────────────────────────────────────
def f5():
    b = []
    b.append(rect(10, 10, 360, 270, stroke=P, sw=1.5))
    b.append(title(30, 40, '1. Calls from iPhone (relay)', size=14))
    b += laptop(85, 130)
    b.append(text(85, 188, 'Mac or iPad', size=12, fill=T, anchor='middle'))
    b.append(arrow(140, 130, 200, 130, color=L))
    b.append(text(170, 120, 'same Wi-Fi', size=11, fill=L, anchor='middle'))
    b += phone(228, 130, w=34, h=64)
    b.append(text(228, 182, 'iPhone', size=12, fill=T, anchor='middle'))
    b.append(arrow(250, 130, 300, 130))
    b += tower(328, 128, s=0.8)
    b.append(text(328, 166, 'cell tower', size=11, fill=T, anchor='middle'))
    for i, s in enumerate([
        'The iPhone places the call. The Mac or iPad is',
        'just a speaker and microphone. The iPhone must',
        'be switched on, nearby, on the same Wi-Fi.',
    ]):
        b.append(text(30, 215 + 18 * i, s, size=12))
    b.append(rect(390, 10, 360, 270, stroke=P, sw=1.5))
    b.append(title(410, 40, '2. Wi-Fi Calling on the device itself', size=14))
    b += laptop(460, 130)
    b.append(text(460, 188, 'Mac in a hotel', size=12, fill=T, anchor='middle'))
    b.append(path('M515 130 H630', stroke=L, sw=6, opacity=0.4))
    b.append(arrow(515, 130, 640, 130, color=L))
    b.append(text(578, 118, 'internet tunnel', size=11, fill=L, anchor='middle'))
    b += carrier_box(645, 105, 90, 50, ['Your', 'carrier'], size=12)
    for i, s in enumerate([
        'The iPhone can be off, or at home. The call goes',
        'straight to the carrier. Only some carriers offer',
        'it, and 911 may use your registered home address.',
    ]):
        b.append(text(410, 215 + 18 * i, s, size=12))
    return svg(760, 290, 'Two ways to call from a Mac or iPad: relayed through a '
               'nearby iPhone, or Wi-Fi Calling straight to the carrier', b)


# ── Figure 6: calling home from abroad ──────────────────────────────────────
def f6():
    b = []
    cards = [
        (10, L, False, 'Call home', ['A Wi-Fi call back to a', 'number in your home country'],
         'Usually free', 'on many carriers, not all'),
        (262, W, False, 'Call a local number',
         ['A Wi-Fi call to a number', "in the country you're visiting"],
         'Charged', 'as an international call, or blocked'),
        (515, D, True, 'Some countries', ['Your carrier switches the', 'feature off there entirely'],
         "Won't work", "check your carrier's list"),
    ]
    for x, c, tint, head, lines, big, foot in cards:
        cx = x + 117.5
        if tint:
            b.append(rect(x, 15, 235, 150, stroke=None, fill=c, opacity=0.12))
        b.append(rect(x, 15, 235, 150, stroke=c, sw=2.5))
        b.append(title(cx, 48, head, size=15, fill=c, anchor='middle'))
        b.append(text(cx, 78, lines[0], size=12, anchor='middle'))
        b.append(text(cx, 96, lines[1], size=12, anchor='middle'))
        b.append(text(cx, 126, big, size=20, fill=c, weight=700, anchor='middle'))
        b.append(text(cx, 150, foot, size=11, anchor='middle'))
    return svg(760, 170, 'Three outcomes of a Wi-Fi call made abroad: call home, call a '
               'local number, some countries', b)


# ── Figure 7: Wi-Fi Calling vs WhatsApp and FaceTime ────────────────────────
def _tick(cx, cy):
    return [circle(cx, cy, 11, stroke=L, sw=2), path(f'M{cx - 6} {cy}l4 4 8-8', stroke=L, sw=2.5)]


def _cross(cx, cy):
    return [circle(cx, cy, 11, stroke=D, sw=2),
            path(f'M{cx - 5} {cy - 5}l10 10M{cx + 5} {cy - 5}l-10 10', stroke=D, sw=2.5)]


def _bang(cx, cy):
    return [circle(cx, cy, 11, stroke=W, sw=2),
            line(cx, cy - 5, cx, cy + 1, stroke=W, sw=2.5), circle(cx, cy + 5.5, 1.5, fill=W)]


def _dash(cx, cy):
    return [circle(cx, cy, 11, stroke=M, sw=2), line(cx - 5, cy, cx + 5, cy, stroke=M, sw=2.5)]


def f7():
    b = []
    b.append(rect(10, 10, 360, 230, stroke=L, sw=2.5))
    b.append(title(190, 42, 'Carrier Wi-Fi Calling', size=15, anchor='middle'))
    rows_l = [
        (_tick, 'Calls almost any phone number'),
        (_tick, 'Shows your own phone number'),
        # The one label changed from the print guide: "(page 6)" -> "(section 5)".
        (_tick, 'Emergency calls possible (section 5)'),
        (_bang, 'Blocked in some countries'),
    ]
    for i, (icon, s) in enumerate(rows_l):
        y = 80 + 40 * i
        b += icon(40, y)
        b.append(text(62, y + 5, s, fill=T))
    b.append(rect(390, 10, 360, 230, stroke=M, sw=2.5))
    b.append(title(570, 42, 'WhatsApp, FaceTime Audio', size=15, anchor='middle'))
    rows_r = [
        (_cross, 'Only other people using the app'),
        (_dash, 'Shows your app account'),
        (_cross, 'Not for emergencies'),
        (_bang, 'Not available everywhere either'),
    ]
    for i, (icon, s) in enumerate(rows_r):
        y = 80 + 40 * i
        b += icon(420, y)
        b.append(text(442, y + 5, s, fill=T))
    return svg(760, 250, 'Carrier Wi-Fi Calling beside WhatsApp and FaceTime Audio, '
               'four points each', b)


# ── Figure 8: what your Wi-Fi owes a phone call ─────────────────────────────
def f8():
    b = []
    b.append(title(20, 28, 'The whole trip, mouth to ear: 150 milliseconds or less feels natural'))
    b.append(rect(20, 42, 150, 40, rx=8, stroke=None, fill=L, opacity=0.35))
    b.append(rect(170, 42, 220, 40, rx=0, stroke=None, fill=P))
    b.append(rect(20, 42, 720, 40, rx=8, stroke=T, sw=1.5))
    b.append(line(170, 42, 170, 82, stroke=T, sw=1.5))
    b.append(line(390, 42, 390, 82, stroke=T, sw=1.5))
    b.append(title(95, 67, 'Your Wi-Fi', size=12, anchor='middle'))
    b.append(title(280, 67, 'Your internet line', size=12, anchor='middle'))
    b.append(title(565, 67, 'Internet and carrier, to the other phone', size=12, anchor='middle'))
    b.append(text(20, 104, 'Every part of the trip spends from the same budget. When someone '
                  'uploads photos on the same connection,', size=11.5))
    b.append(text(20, 120, 'the internet-line slice can grow by hundreds of milliseconds on '
                  'its own.', size=11.5))
    b.append(title(20, 152, "Wi-Fi's four lanes (WMM, Wi-Fi Multimedia)"))
    lanes = [
        (162, 'Voice: the fast lane', L, 0.5, L),
        (184, 'Video', L, 0.22, None),
        (206, 'Best effort: everyday data', P, None, None),
        (228, 'Background', None, None, P),
    ]
    for y, s, fill, op, stroke in lanes:
        if fill:
            b.append(rect(20, y, 720, 18, rx=4, stroke=None, fill=fill, opacity=op))
        if stroke:
            b.append(rect(20, y, 720, 18, rx=4, stroke=stroke, sw=1.2))
        b.append(title(30, y + 13, s, size=12))
    return svg(760, 250, 'One delay budget shared by Wi-Fi, the internet line and the '
               "rest of the trip, and Wi-Fi's four traffic lanes", b)


FIGURES = {
    'cover-two-roads': cover,
    'f1-two-roads': f1,
    'f2-when-wifi': f2,
    'f3-walking-out': f3,
    'f4-emergency-call': f4,
    'f5-other-devices': f5,
    'f6-abroad': f6,
    'f7-vs-apps': f7,
    'f8-what-wifi-owes': f8,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for slug, fn in FIGURES.items():
        with open(os.path.join(OUT, f'{slug}.svg'), 'w', encoding='utf-8') as fh:
            fh.write(fn())
    print(f'wrote {len(FIGURES)} figures to {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
