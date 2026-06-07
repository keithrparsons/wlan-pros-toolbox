#!/usr/bin/env python3
"""Convert SVG <marker> arrowheads to inline arrowhead <path>s for flutter_svg.

flutter_svg has incomplete <marker> support on iOS, so concept diagrams that use
marker-start / marker-end render the line but DROP the arrowhead. This rewrites
each marker reference into an explicit, correctly-oriented inline triangle path
at the endpoint, matching the marker's fill color, then deletes the markers.

Scope: antenna-fundamentals g1-g5, g7. g6 is converted in a separate lane — DO
NOT pass g6 to this script.

Marker geometry mirrored from the <defs> in these files:
  arrow/arrowLime/arrowDanger: triangle 8 long x 8 wide, tip at the line end.
  arrowMuted: triangle 7.2 long x 7.2 wide.
Colors: arrow #E5E5E5, arrowLime #A2CC3A, arrowMuted #9C9C9C, arrowDanger #F26E6E.
"""
import math
import re
import sys

MARKER_COLOR = {
    "arrow": "#E5E5E5",
    "arrowLime": "#A2CC3A",
    "arrowMuted": "#9C9C9C",
    "arrowDanger": "#F26E6E",
}
# (length along the line, half-width) per marker id
MARKER_SIZE = {
    "arrow": (8.0, 4.0),
    "arrowLime": (8.0, 4.0),
    "arrowDanger": (8.0, 4.0),
    "arrowMuted": (7.2, 3.6),
}


def arrowhead(tip_x, tip_y, ang, marker_id):
    """Return an inline path string for a filled triangle whose tip is at
    (tip_x, tip_y), pointing in direction `ang` (radians)."""
    length, half = MARKER_SIZE[marker_id]
    color = MARKER_COLOR[marker_id]
    # base center is `length` back along -ang from the tip
    bx = tip_x - length * math.cos(ang)
    by = tip_y - length * math.sin(ang)
    # perpendicular offsets for the two base corners
    px = -math.sin(ang) * half
    py = math.cos(ang) * half
    p1 = (bx + px, by + py)
    p2 = (bx - px, by - py)
    return (
        f'<path d="M{tip_x:.2f} {tip_y:.2f} '
        f'L{p1[0]:.2f} {p1[1]:.2f} L{p2[0]:.2f} {p2[1]:.2f} Z" '
        f'fill="{color}"/>'
    )


def line_attrs(tag):
    def g(name):
        m = re.search(rf'{name}="([-0-9.]+)"', tag)
        return float(m.group(1)) if m else None
    return g("x1"), g("y1"), g("x2"), g("y2")


def bezier_endpoints_and_tangents(d):
    """Parse a simple 'Mx y C ...' cubic-bezier path. Return
    ((startpt, start_tangent_out), (endpt, end_tangent_in)).
    Tangent_out points away from start along the curve; tangent_in points
    into the end (the direction an end-arrow should face)."""
    nums = list(map(float, re.findall(r'[-0-9.]+', d)))
    # M x0 y0 C c1x c1y c2x c2y x1 y1  (single cubic segment expected here)
    x0, y0 = nums[0], nums[1]
    c1x, c1y, c2x, c2y, x1, y1 = nums[2:8]
    start = (x0, y0)
    end = (x1, y1)
    # tangent leaving start = toward first control point
    start_dir = math.atan2(c1y - y0, c1x - x0)
    # tangent arriving at end = from second control point toward end
    end_dir = math.atan2(y1 - c2y, x1 - c2x)
    return (start, start_dir), (end, end_dir)


# Match a <line ...> or <path ...> element carrying at least one marker-* attr.
ELEM_RE = re.compile(r'<(line|path)\b[^>]*\bmarker-(?:start|end)="url\(#[^)]+\)"[^>]*/>')


def convert(svg):
    out_parts = []
    extra_arrowheads = []
    pos = 0
    for m in ELEM_RE.finditer(svg):
        out_parts.append(svg[pos:m.start()])
        tag = m.group(0)
        tagname = m.group(1)
        ms = re.search(r'marker-start="url\(#([^)]+)\)"', tag)
        me = re.search(r'marker-end="url\(#([^)]+)\)"', tag)

        if tagname == "line":
            x1, y1, x2, y2 = line_attrs(tag)
            if me:
                ang = math.atan2(y2 - y1, x2 - x1)
                extra_arrowheads.append(arrowhead(x2, y2, ang, me.group(1)))
            if ms:
                ang = math.atan2(y1 - y2, x1 - x2)
                extra_arrowheads.append(arrowhead(x1, y1, ang, ms.group(1)))
        else:  # path
            dmatch = re.search(r'\bd="([^"]+)"', tag)
            (start, sdir), (end, edir) = bezier_endpoints_and_tangents(dmatch.group(1))
            if me:
                extra_arrowheads.append(arrowhead(end[0], end[1], edir, me.group(1)))
            if ms:
                # start arrow points back out of the curve start
                extra_arrowheads.append(arrowhead(start[0], start[1], sdir + math.pi, ms.group(1)))

        # strip the marker-* attributes from the element itself
        clean = re.sub(r'\s*marker-(?:start|end)="url\(#[^)]+\)"', '', tag)
        out_parts.append(clean)
        pos = m.end()
    out_parts.append(svg[pos:])
    result = "".join(out_parts)

    # remove the now-unused <marker> defs (the whole <defs>...</defs> block's
    # markers); the diagrams use no other defs content.
    result = re.sub(r'<marker\b.*?</marker>\s*', '', result, flags=re.DOTALL)

    # inject the inline arrowheads just before </svg> so they paint on top.
    if extra_arrowheads:
        inject = "\n" + "\n".join(extra_arrowheads) + "\n"
        result = result.replace("</svg>", inject + "</svg>")
    return result


if __name__ == "__main__":
    for path in sys.argv[1:]:
        with open(path, encoding="utf-8") as f:
            svg = f.read()
        if "g6-downtilt" in path:
            print(f"SKIP (other lane): {path}")
            continue
        new = convert(svg)
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
        print(f"converted: {path}")
