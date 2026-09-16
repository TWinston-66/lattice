#!/usr/bin/env python3
"""Draw the lattice artwork: the desktop wallpaper, the boot-splash mark and its widgets.

The first two are the same triangular lattice of nodes and edges -- the one in the logo --
drawn at different scales. `wallpaper` covers the canvas with it and brightens a
hexagonal mark at the centre; `mark` draws that centre alone, optionally at a point
in the pulse animation, which is what the Plymouth theme flips through. `widget` draws
the pieces of Plymouth's password prompt, shaped like hyprlock's input field so the
passphrase box at boot and the one on the lock screen are the same box.

Everything scales off `--spacing`, the distance between two neighbouring nodes, so
`--density` is the only knob a wallpaper variant needs: it is a zoom, not a restyle.

Colours come from `--palette FILE`, a JSON object of the names in DEFAULT_PALETTE.
Without one this draws in stock Catppuccin Mocha, which is how the assets under
.github/assets are checked in.
"""

import argparse
import json
import math
import sys

# Catppuccin Mocha, blue accent. lattice.theme passes the live palette instead.
DEFAULT_PALETTE = {
    "accent": "#89b4fa",  # nodes on the mark's outer ring, and its edges
    "accentAlt": "#b4befe",  # nodes on the mark's inner ring
    "text": "#cdd6f4",  # the one node at the centre
    "line": "#45475a",  # the background grid's edges
    "node": "#6c7086",  # the background grid's nodes
    "base": "#1e1e2e",  # background gradient, bottom right
    "mantle": "#181825",  # inside of the password field
    "crust": "#11111b",  # background gradient, top left
    "warn": "#fab387",  # the caps-lock indicator
}

ROW_RATIO = math.sqrt(3) / 2  # row height, as a fraction of the node spacing

# Ratios to the node spacing, measured off the checked-in assets.
GRID_NODE_R = 1 / 30
GRID_EDGE_W = 1 / 48
MARK_NODE_R = 1 / 6
MARK_EDGE_W = 1 / 14.4
MARK_CENTRE_R = 1.417  # of a mark node
MARGIN = 2 / 3  # how far past the canvas edge the grid keeps going

# Opacity: a Gaussian falloff from the centre of the canvas, with these widths as
# fractions of the canvas. Edges fall off faster than nodes, by the 1.5 exponent.
FALLOFF_X = 0.2794
FALLOFF_Y = 0.3888
NODE_FLOOR, NODE_RANGE = 0.070, 0.450
EDGE_SCALE, EDGE_BIAS = 0.218, 0.004
# An edge dimmer than this is dropped rather than drawn: at the corners of the canvas the
# grid thins out to nothing instead of fading to an even wash of near-invisible lines.
EDGE_CUTOFF, EDGE_FLOOR = 0.0082, 0.010

# The mark: a hexagon of radius 2, so a centre, a ring of 6 and a ring of 12.
MARK_RADIUS = 2
# Edges inside the inner ring carry the accent at full strength; the rest is scaffolding.
MARK_EDGE_BRIGHT, MARK_EDGE_DIM = 0.75, 0.32


def neighbours(x, y, spacing):
    """The six lattice points one edge away from (x, y)."""
    dx, dy = spacing / 2, spacing * ROW_RATIO
    return [
        (x + spacing, y),
        (x - spacing, y),
        (x + dx, y + dy),
        (x - dx, y + dy),
        (x + dx, y - dy),
        (x - dx, y - dy),
    ]


def key(point):
    """Lattice points are compared at the precision they are written out with."""
    return (round(point[0], 1), round(point[1], 1))


def mark_rings(cx, cy, spacing):
    """The mark's points, as a list of rings outwards from the centre."""
    rings = [[(cx, cy)]]
    seen = {key((cx, cy))}
    for _ in range(MARK_RADIUS):
        ring = []
        for x, y in rings[-1]:
            for point in neighbours(x, y, spacing):
                if key(point) not in seen:
                    seen.add(key(point))
                    ring.append(point)
        # Sorted so a ring is drawn in a stable order, whatever the walk found first.
        rings.append(sorted(ring, key=lambda p: (round(p[1], 1), round(p[0], 1))))
    return rings


def grid_points(width, height, spacing):
    """Every lattice point covering the canvas, in rows out from the centre. The rows are
    laid out from the centre so the mark lands on the lattice whatever the canvas size."""
    cx, cy = width / 2, height / 2
    row_h = spacing * ROW_RATIO
    margin = spacing * MARGIN
    points = []
    k0 = math.ceil((-margin - cy) / row_h)
    for k in range(k0, -k0 + 1):
        y = cy + k * row_h
        # Every other row is offset by half a node, which is what makes the grid
        # triangular; the offset rows therefore reach one column further to the left.
        offset = spacing / 2 if k % 2 else 0.0
        j0 = math.ceil((-margin - cx - offset) / spacing)
        j1 = math.floor((width + margin - cx - offset) / spacing)
        for j in range(j0, j1 + 1):
            points.append((cx + offset + j * spacing, y))
    return points


def edges(points, spacing):
    """Each point joined to the three neighbours to its right and below, where both ends
    exist. Taking half the six directions is what keeps an edge from being drawn twice."""
    present = {key(p) for p in points}
    out = []
    for x, y in points:
        east, _, south_east, south_west, _, _ = neighbours(x, y, spacing)
        for point in (east, south_east, south_west):
            if key(point) in present:
                out.append(((x, y), point))
    return out


def falloff(x, y, width, height):
    """1 at the centre of the canvas, approaching 0 at the corners."""
    dx = (x - width / 2) / (FALLOFF_X * width)
    dy = (y - height / 2) / (FALLOFF_Y * height)
    return math.exp(-(dx * dx + dy * dy))


def fmt(value):
    return f"{value:.1f}"


def alpha(opacity):
    """Opacity as an attribute, or nothing at all when the element is fully opaque."""
    if opacity >= 0.9995:
        return ""
    return ' opacity="{}"'.format(f"{opacity:.3f}".rstrip("0"))


def line(p1, p2, colour, opacity, extra=""):
    return (
        f'    <line x1="{fmt(p1[0])}" y1="{fmt(p1[1])}" x2="{fmt(p2[0])}" y2="{fmt(p2[1])}"'
        f' stroke="{colour}"{extra}{alpha(opacity)}/>'
    )


def circle(point, r, colour, opacity=1.0):
    return (
        f'    <circle cx="{fmt(point[0])}" cy="{fmt(point[1])}" r="{r:g}"'
        f' fill="{colour}"{alpha(opacity)}/>'
    )


def draw_mark(rings, spacing, palette, glow=None):
    """The hexagonal mark: edges first, then nodes, brightest at the centre.

    `glow` is an optional ring -> brightness multiplier, which is how the boot splash
    animates: the geometry never moves, only how brightly each ring is lit.
    """
    node_r = spacing * MARK_NODE_R
    ring_of = {key(p): r for r, ring in enumerate(rings) for p in ring}
    lit = (lambda ring: 1.0) if glow is None else glow

    out = [f'  <g stroke-linecap="round" stroke-width="{spacing * MARK_EDGE_W:g}">']
    for p1, p2 in edges([p for ring in rings for p in ring], spacing):
        ring = max(ring_of[key(p1)], ring_of[key(p2)])
        base = MARK_EDGE_BRIGHT if ring <= 1 else MARK_EDGE_DIM
        out.append(line(p1, p2, palette["accent"], min(1.0, base * lit(ring))))
    for ring, ring_points in enumerate(rings):
        colour = [palette["text"], palette["accentAlt"], palette["accent"]][min(ring, 2)]
        r = node_r * MARK_CENTRE_R if ring == 0 else node_r
        for point in ring_points:
            out.append(circle(point, round(r, 1), colour, min(1.0, lit(ring))))
    out.append("  </g>")
    return out


def wallpaper(args, palette):
    width, height = args.width, args.height
    spacing = args.spacing / args.density
    cx, cy = width / 2, height / 2

    rings = mark_rings(cx, cy, spacing)
    mark = {key(p) for ring in rings for p in ring}
    # The mark replaces the grid where it sits, rather than being drawn over it.
    points = [p for p in grid_points(width, height, spacing) if key(p) not in mark]

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"'
        f' viewBox="0 0 {width} {height}">',
        "  <defs>",
        '    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">',
        f'      <stop offset="0" stop-color="{palette["crust"]}"/>',
        f'      <stop offset="0.55" stop-color="{palette["mantle"]}"/>',
        f'      <stop offset="1" stop-color="{palette["base"]}"/>',
        "    </linearGradient>",
        '    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.32">',
        f'      <stop offset="0" stop-color="{palette["accent"]}" stop-opacity="0.10"/>',
        f'      <stop offset="1" stop-color="{palette["accent"]}" stop-opacity="0"/>',
        "    </radialGradient>",
        "  </defs>",
        f'  <rect width="{width}" height="{height}" fill="url(#bg)"/>',
        f'  <rect width="{width}" height="{height}" fill="url(#glow)"/>',
        '  <g stroke-linecap="round">',
    ]

    edge_w = f' stroke-width="{spacing * GRID_EDGE_W:g}"'
    for p1, p2 in edges(points, spacing):
        f = falloff((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, width, height)
        opacity = EDGE_SCALE * f**1.5 - EDGE_BIAS
        if opacity < EDGE_CUTOFF:
            continue
        out.append(line(p1, p2, palette["line"], max(EDGE_FLOOR, opacity), extra=edge_w))
    out += ["  </g>", "  <g>"]

    node_r = round(spacing * GRID_NODE_R, 1)
    for point in points:
        f = falloff(point[0], point[1], width, height)
        out.append(circle(point, node_r, palette["node"], NODE_FLOOR + NODE_RANGE * f))
    out.append("  </g>")

    out += draw_mark(rings, spacing, palette)
    out.append("</svg>")
    return "\n".join(out) + "\n"


def pulse(phase, ring):
    """A ring's brightness at a point in the animation loop.

    One bright band travels out from the centre and starts again, so the mark reads as
    something charging rather than blinking: every ring is always at least half lit.
    """
    RING_DELAY, WIDTH, FLOOR = 0.26, 0.15, 0.5
    u = (phase - ring * RING_DELAY) % 1.0
    u = min(u, 1.0 - u)  # the band wraps, so distance is measured around the loop
    return FLOOR + (1.0 - FLOOR) * math.exp(-((u / WIDTH) ** 2))


def mark(args, palette):
    """The mark alone on a transparent canvas, at one point in the pulse."""
    spacing = args.spacing
    reach = spacing * MARK_RADIUS + spacing * MARK_NODE_R * MARK_CENTRE_R + args.padding
    width = 2 * reach
    height = 2 * (spacing * ROW_RATIO * MARK_RADIUS + spacing * MARK_NODE_R + args.padding)

    rings = mark_rings(width / 2, height / 2, spacing)
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:g}" height="{height:g}"'
        f' viewBox="0 0 {width:g} {height:g}">'
    ]
    out += draw_mark(rings, spacing, palette, glow=lambda ring: pulse(args.phase, ring))
    out.append("</svg>")
    return "\n".join(out) + "\n"


# Plymouth's password prompt, at the size and roundness hyprlock's input-field uses.
FIELD = dict(width=320, height=56, radius=14, outline=2)


def widget(args, palette):
    """One piece of the password prompt: the field, a typed dot, or an indicator."""
    if args.name == "entry":
        w, h, r, o = (FIELD[k] for k in ("width", "height", "radius", "outline"))
        body = (
            f'  <rect x="{o / 2}" y="{o / 2}" width="{w - o}" height="{h - o}" rx="{r}"'
            f' fill="{palette["mantle"]}" stroke="{palette["accent"]}" stroke-width="{o}"/>'
        )
    elif args.name == "bullet":
        # A quarter of the field's height, like hyprlock's dots_size.
        w = h = round(FIELD["height"] / 4)
        body = f'  <circle cx="{w / 2}" cy="{h / 2}" r="{w / 2 - 1}" fill="{palette["text"]}"/>'
    elif args.name == "lock":
        w, h = 34, 40
        body = (
            f'  <path d="M11 18 V13 a7 7 0 0 1 14 0 V18" fill="none"'
            f' stroke="{palette["accent"]}" stroke-width="4"/>\n'
            f'  <rect x="4" y="17" width="26" height="20" rx="4" fill="{palette["accent"]}"/>\n'
            f'  <circle cx="17" cy="27" r="3.5" fill="{palette["mantle"]}"/>'
        )
    elif args.name == "capslock":
        # Drawn in the warning colour, since it is only ever shown to stop a failed login.
        w, h = 28, 28
        body = (
            f'  <path d="M14 5 L24 15 H19 V22 H9 V15 H4 Z" fill="{palette["warn"]}"/>\n'
            f'  <rect x="9" y="24" width="10" height="3" rx="1.5" fill="{palette["warn"]}"/>'
        )
    else:  # unreachable: argparse restricts the choices
        raise SystemExit(f"unknown widget {args.name}")

    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}"'
        f' viewBox="0 0 {w:g} {h:g}">\n{body}\n</svg>\n'
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--palette", type=argparse.FileType("r"), help="JSON colour map")
    sub = parser.add_subparsers(dest="drawing", required=True)

    w = sub.add_parser("wallpaper", help="the desktop wallpaper")
    w.add_argument("--width", type=int, default=1920)
    w.add_argument("--height", type=int, default=1200)
    w.add_argument("--spacing", type=float, default=72.0)
    w.add_argument("--density", type=float, default=1.0, help="grid scale; >1 is finer")
    w.set_defaults(draw=wallpaper)

    m = sub.add_parser("mark", help="the hexagonal mark, for the boot splash")
    m.add_argument("--spacing", type=float, default=72.0)
    m.add_argument("--padding", type=float, default=8.0)
    m.add_argument("--phase", type=float, default=0.0, help="0..1 through the pulse")
    m.set_defaults(draw=mark)

    g = sub.add_parser("widget", help="a piece of the boot splash's password prompt")
    g.add_argument("name", choices=["entry", "bullet", "lock", "capslock"])
    g.set_defaults(draw=widget)

    args = parser.parse_args(argv)
    palette = dict(DEFAULT_PALETTE)
    if args.palette:
        palette.update(json.load(args.palette))
    sys.stdout.write(args.draw(args, palette))


if __name__ == "__main__":
    main()
