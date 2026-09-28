#!/usr/bin/env python3
"""Draw the lattice artwork: the wallpaper, the boot-splash mark, its widgets, deck keys.

The first two are the same triangular lattice of nodes and edges -- the one in the logo --
drawn at different scales. `wallpaper` covers the canvas with it and brightens a
hexagonal mark at the centre; `mark` draws that centre alone, optionally at a point
in the pulse animation, which is what the Plymouth theme flips through. `widget` draws
the pieces of Plymouth's password prompt, shaped like hyprlock's input field so the
passphrase box at boot and the one on the lock screen are the same box. `key` draws one
face of the Stream Deck, sliced out of a lattice laid over the whole deck.

Everything scales off `--spacing`, the distance between two neighbouring nodes, so
`--density` is a zoom rather than a restyle. On top of that `--seed` varies a wallpaper:
which way the background gradient runs, and which ring of the mark is lit brightest.
Naming either of those explicitly overrides it; `--seed 0` varies nothing.

`--rotate` and `--focus-x/y` tilt the lattice and move the mark off centre. The seed
leaves both alone on purpose. The mark is the only thing on the canvas, so it has nothing
to sit off-balance against: a few degrees of tilt reads as a crooked grid rather than a
turned one, and a mark a little off centre reads as a mistake rather than a composition.
They are here for a deliberate hand -- 30 degrees is the tilt that lands the triangular
lattice back on itself, if a variant ever wants to be obviously turned rather than a
little askew.

Colours come from `--palette FILE`, a JSON object of the names in DEFAULT_PALETTE.
Without one this draws in stock Catppuccin Mocha, which is how the assets under
.github/assets are checked in.
"""

import argparse
import json
import math
import random
import re
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
    "label": "#bac2de",  # the word under a deck key's glyph
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

# The wallpaper freezes the pulse at one point rather than animating through it, so a ring
# the bright band has passed stays where it is for good. It floors here instead of at the
# half the boot splash can afford while it is still moving.
GLOW_FLOOR = 0.8

# The Stream Deck Original V2's face: fifteen 72px keys, five across and three down. The
# lattice is laid over the whole face and each key slices its own square out of it, so the
# grid runs on across the physical gaps and the fifteen read as one surface rather than as
# fifteen stickers. Nothing here is centred on a key; everything is centred on the face.
DECK_COLS, DECK_ROWS, DECK_SIZE = 5, 3, 72
DECK_SPACING = 24.0  # three nodes to a key
DECK_NODE_R = 1 / 16  # of the spacing, and so twice the wallpaper's: 72px is not a screen

# Dimmer than the wallpaper's lattice, and floored higher. These keys are 72px of backlit
# LCD a hand's width from the eye: the glyph has to stay the brightest thing on each one,
# and the falloff has to leave the corner keys with a grid on them rather than nothing.
DECK_NODE_FLOOR, DECK_NODE_RANGE = 0.20, 0.35
DECK_EDGE_FLOOR, DECK_EDGE_RANGE = 0.07, 0.13

# Where the glyph sits: above centre when a label is under it, dead centre when not.
DECK_GLYPH_Y, DECK_GLYPH_Y_BARE, DECK_LABEL_Y = 31.0, 36.0, 60.0
# The state bar: along the bottom for a key that is on, down the left edge for the page
# the rail is currently showing.
DECK_BAR_BOTTOM = dict(length=28.0, weight=3.0, inset=7.0)
DECK_BAR_LEFT = dict(length=30.0, weight=3.0, inset=5.0)

# A key's one accent, as a palette role. `plain` is a key that only ever does one thing,
# `accent` one that is currently on, `dim` one whose subject is unreachable, `warn` one
# that is armed and will do something irreversible on the next press.
DECK_TONES = {
    "accent": "accent",
    "alt": "accentAlt",
    "plain": "text",
    "dim": "node",
    "warn": "warn",
}

# Each knob as it is when nothing varies it, which is what `--seed 0` draws.
PLAIN = dict(rotate=0.0, gradient_angle=45.0, focus_x=0.5, focus_y=0.5, glow_phase=None)


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


def grid_points(cx, cy, half_w, half_h, spacing):
    """Every lattice point in the box of half-extents (half_w, half_h) about (cx, cy).

    The rows are laid out from that point rather than from a corner, so the mark lands on
    the lattice whatever the canvas size -- and so that moving the mark moves the grid with
    it instead of sliding the two out of register.
    """
    row_h = spacing * ROW_RATIO
    points = []
    kmax = math.floor(half_h / row_h)
    for k in range(-kmax, kmax + 1):
        y = cy + k * row_h
        # Every other row is offset by half a node, which is what makes the grid
        # triangular; the offset rows therefore reach one column further to the left.
        offset = spacing / 2 if k % 2 else 0.0
        j0 = math.ceil((-half_w - offset) / spacing)
        j1 = math.floor((half_w - offset) / spacing)
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


def falloff(x, y, cx, cy, width, height):
    """1 at (cx, cy), approaching 0 at the corners of the canvas."""
    dx = (x - cx) / (FALLOFF_X * width)
    dy = (y - cy) / (FALLOFF_Y * height)
    return math.exp(-(dx * dx + dy * dy))


def gradient_vector(angle):
    """A linear gradient's x1,y1,x2,y2 for `angle`, in degrees clockwise from rightwards.

    Stretched to reach the edge of the box on whichever axis it leans further along, which
    is what makes 45 degrees the corner-to-corner diagonal the plain wallpaper runs on.
    """
    dx, dy = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    reach = 2 * max(abs(dx), abs(dy))
    dx, dy = dx / reach, dy / reach
    return 0.5 - dx, 0.5 - dy, 0.5 + dx, 0.5 + dy


def vary(args):
    """Fill in whatever knob the caller left out: from `--seed` where it varies one, and
    from PLAIN otherwise. Every knob is drawn whether it ends up used or not, so naming
    one on the command line overrides that one alone.
    """
    rng = random.Random(args.seed)
    seeded = dict(
        gradient_angle=rng.uniform(0.0, 360.0),
        glow_phase=rng.random(),
    )
    for knob, value in {**PLAIN, **(seeded if args.seed else {})}.items():
        if getattr(args, knob) is None:
            setattr(args, knob, value)


def fmt(value):
    return f"{value:.1f}"


def num(value):
    """A knob's own value -- an angle, a fraction of the canvas -- written as short as it
    goes. Rounded first, so that a knob left at its default writes as 0 and not as 4e-16."""
    return f"{round(value, 4):g}"


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


def draw_mark(rings, spacing, palette, glow=None, extra=""):
    """The hexagonal mark: edges first, then nodes, brightest at the centre.

    `glow` is an optional ring -> brightness multiplier, which is how the boot splash
    animates: the geometry never moves, only how brightly each ring is lit.
    """
    node_r = spacing * MARK_NODE_R
    ring_of = {key(p): r for r, ring in enumerate(rings) for p in ring}
    lit = (lambda ring: 1.0) if glow is None else glow

    out = [f'  <g stroke-linecap="round" stroke-width="{spacing * MARK_EDGE_W:g}"{extra}>']
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
    # Where the mark sits, which is also where the falloff and the glow are brightest and
    # the point the tilt turns about: the whole composition hangs off this one spot.
    cx, cy = width * args.focus_x, height * args.focus_y

    rings = mark_rings(cx, cy, spacing)
    mark = {key(p) for ring in rings for p in ring}
    # The grid is laid out from the mark, so how far it has to reach is measured from there
    # to the furthest edge rather than out from the centre of the canvas.
    half_w = max(cx, width - cx) + spacing * MARGIN
    half_h = max(cy, height - cy) + spacing * MARGIN
    if args.rotate:
        # A tilted grid has to start further out still, or the corners the tilt swings in
        # from come up empty. This is the box that still covers the canvas once turned.
        turn = abs(math.radians(args.rotate))
        half_w, half_h = (
            half_w * math.cos(turn) + half_h * math.sin(turn),
            half_w * math.sin(turn) + half_h * math.cos(turn),
        )
    # The mark replaces the grid where it sits, rather than being drawn over it.
    points = [
        p for p in grid_points(cx, cy, half_w, half_h, spacing) if key(p) not in mark
    ]

    # The background keeps square to the canvas; only the lattice drawn over it turns, so
    # the tilt rides on each of its groups rather than on one wrapper around the lot.
    x1, y1, x2, y2 = gradient_vector(args.gradient_angle)
    spin = ""
    if args.rotate:
        spin = f' transform="rotate({num(args.rotate)} {fmt(cx)} {fmt(cy)})"'

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"'
        f' viewBox="0 0 {width} {height}">',
        "  <defs>",
        f'    <linearGradient id="bg" x1="{num(x1)}" y1="{num(y1)}"'
        f' x2="{num(x2)}" y2="{num(y2)}">',
        f'      <stop offset="0" stop-color="{palette["crust"]}"/>',
        f'      <stop offset="0.55" stop-color="{palette["mantle"]}"/>',
        f'      <stop offset="1" stop-color="{palette["base"]}"/>',
        "    </linearGradient>",
        f'    <radialGradient id="glow" cx="{num(args.focus_x)}"'
        f' cy="{num(args.focus_y)}" r="0.32">',
        f'      <stop offset="0" stop-color="{palette["accent"]}" stop-opacity="0.10"/>',
        f'      <stop offset="1" stop-color="{palette["accent"]}" stop-opacity="0"/>',
        "    </radialGradient>",
        "  </defs>",
        f'  <rect width="{width}" height="{height}" fill="url(#bg)"/>',
        f'  <rect width="{width}" height="{height}" fill="url(#glow)"/>',
        f'  <g stroke-linecap="round"{spin}>',
    ]

    edge_w = f' stroke-width="{spacing * GRID_EDGE_W:g}"'
    for p1, p2 in edges(points, spacing):
        f = falloff((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, cx, cy, width, height)
        opacity = EDGE_SCALE * f**1.5 - EDGE_BIAS
        if opacity < EDGE_CUTOFF:
            continue
        out.append(line(p1, p2, palette["line"], max(EDGE_FLOOR, opacity), extra=edge_w))
    out += ["  </g>", f"  <g{spin}>"]

    node_r = round(spacing * GRID_NODE_R, 1)
    for point in points:
        f = falloff(point[0], point[1], cx, cy, width, height)
        out.append(circle(point, node_r, palette["node"], NODE_FLOOR + NODE_RANGE * f))
    out.append("  </g>")

    # The same pulse the boot splash flips through, held still at one point in the loop:
    # the wallpaper's mark gets one ring lit brighter than the rest instead of all of them.
    phase = args.glow_phase
    glow = None if phase is None else (lambda r: pulse(phase, r, GLOW_FLOOR))

    out += draw_mark(rings, spacing, palette, glow=glow, extra=spin)
    out.append("</svg>")
    return "\n".join(out) + "\n"


def pulse(phase, ring, floor=0.5):
    """A ring's brightness at a point in the animation loop.

    One bright band travels out from the centre and starts again, so the mark reads as
    something charging rather than blinking: every ring is always at least `floor` lit.
    The boot splash takes the default and swings the whole way, because it is moving; the
    wallpaper holds one frame of it forever, and a ring left at half is just a dim ring.
    """
    RING_DELAY, WIDTH = 0.26, 0.15
    u = (phase - ring * RING_DELAY) % 1.0
    u = min(u, 1.0 - u)  # the band wraps, so distance is measured around the loop
    return floor + (1.0 - floor) * math.exp(-((u / WIDTH) ** 2))


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


def esc(text):
    """The three characters that cannot go into an SVG text node as they stand."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def embed(handle, cx, cy, box):
    """Another SVG's drawing, scaled to fit a `box` square centred on (cx, cy).

    For the web-app keys: an app's own mark belongs on its key rather than a Nerd Font
    stand-in, and .github/assets already holds the two marks no icon theme carries. The
    file is inlined rather than referenced, because rsvg-convert resolves an <image> href
    against the cwd of whoever runs it, and a key is rasterised in a build sandbox.
    """
    svg = handle.read()
    open_tag = re.search(r"<svg\b[^>]*>", svg)
    if not open_tag:
        raise SystemExit(f"{handle.name}: no <svg> element")
    view_box = re.search(r'viewBox="([-\d.eE\s]+)"', open_tag.group(0))
    if not view_box:
        raise SystemExit(f"{handle.name}: <svg> has no viewBox to scale from")
    vx, vy, vw, vh = (float(v) for v in view_box.group(1).split())
    body = svg[open_tag.end() : svg.rindex("</svg>")].strip()

    # Uniform, and centred on the box rather than on the source's own origin: the two
    # marks are square, but a later one need not be.
    scale = box / max(vw, vh)
    tx, ty = cx - scale * (vx + vw / 2), cy - scale * (vy + vh / 2)
    return [
        f'  <g transform="translate({num(tx)} {num(ty)}) scale({num(scale)})">',
        body,
        "  </g>",
    ]


def deck_key(args, palette):
    """One key of the Stream Deck: its slice of the lattice, a glyph, and a label."""
    face_w, face_h = DECK_COLS * DECK_SIZE, DECK_ROWS * DECK_SIZE
    ox = (args.index % DECK_COLS) * DECK_SIZE
    oy = (args.index // DECK_COLS) * DECK_SIZE
    cx, cy = face_w / 2, face_h / 2
    spacing = DECK_SPACING / args.density
    colour = palette[DECK_TONES[args.tone]]

    # The same corner-to-corner gradient the wallpaper's background runs on, over the
    # whole face: the rect is the face, so the key shows whichever part of it it covers.
    x1, y1, x2, y2 = gradient_vector(45.0)
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{DECK_SIZE}"'
        f' height="{DECK_SIZE}" viewBox="{ox:g} {oy:g} {DECK_SIZE} {DECK_SIZE}">',
        "  <defs>",
        f'    <linearGradient id="bg" x1="{num(x1)}" y1="{num(y1)}"'
        f' x2="{num(x2)}" y2="{num(y2)}">',
        f'      <stop offset="0" stop-color="{palette["crust"]}"/>',
        f'      <stop offset="0.55" stop-color="{palette["mantle"]}"/>',
        f'      <stop offset="1" stop-color="{palette["base"]}"/>',
        "    </linearGradient>",
        "  </defs>",
        f'  <rect width="{face_w}" height="{face_h}" fill="url(#bg)"/>',
    ]

    half_w, half_h = cx + spacing * MARGIN, cy + spacing * MARGIN
    points = grid_points(cx, cy, half_w, half_h, spacing)

    edge_w = f' stroke-width="{spacing * GRID_EDGE_W:g}"'
    out.append(f'  <g stroke-linecap="round"{edge_w}>')
    for p1, p2 in edges(points, spacing):
        f = falloff((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2, cx, cy, face_w, face_h)
        out.append(
            line(p1, p2, palette["line"], DECK_EDGE_FLOOR + DECK_EDGE_RANGE * f)
        )
    out.append("  </g>")

    out.append("  <g>")
    node_r = round(spacing * DECK_NODE_R, 1)
    for point in points:
        f = falloff(point[0], point[1], cx, cy, face_w, face_h)
        out.append(
            circle(point, node_r, palette["node"], DECK_NODE_FLOOR + DECK_NODE_RANGE * f)
        )
    out.append("  </g>")

    glyph_y = oy + (DECK_GLYPH_Y if args.label else DECK_GLYPH_Y_BARE)
    if args.embed:
        out += embed(args.embed, ox + DECK_SIZE / 2, glyph_y, args.glyph_size)
    elif args.glyph:
        # dominant-baseline rather than a measured offset: the glyph boxes in a Nerd Font
        # are not a uniform height, and centring on the box is what lines a row of
        # different glyphs up with each other.
        out.append(
            f'  <text x="{ox + DECK_SIZE / 2:g}" y="{glyph_y:g}" fill="{colour}"'
            f' font-family="{esc(args.glyph_font)}" font-size="{num(args.glyph_size)}"'
            f' text-anchor="middle" dominant-baseline="central">{esc(args.glyph)}</text>'
        )

    if args.label:
        out.append(
            f'  <text x="{ox + DECK_SIZE / 2:g}" y="{oy + DECK_LABEL_Y:g}"'
            f' fill="{palette["label"]}" font-family="{esc(args.label_font)}"'
            f' font-size="{num(args.label_size)}" letter-spacing="0.8"'
            f' text-anchor="middle">{esc(args.label.upper())}</text>'
        )

    if args.bar != "none":
        bar = DECK_BAR_BOTTOM if args.bar == "bottom" else DECK_BAR_LEFT
        if args.bar == "bottom":
            w, h = bar["length"], bar["weight"]
            x, y = ox + (DECK_SIZE - w) / 2, oy + DECK_SIZE - bar["inset"] - h
        else:
            w, h = bar["weight"], bar["length"]
            x, y = ox + bar["inset"], oy + (DECK_SIZE - h) / 2
        out.append(
            f'  <rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}"'
            f' rx="{h / 2 if args.bar == "bottom" else w / 2:g}" fill="{colour}"/>'
        )

    out.append("</svg>")
    return "\n".join(out) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--palette", type=argparse.FileType("r"), help="JSON colour map")
    sub = parser.add_subparsers(dest="drawing", required=True)

    w = sub.add_parser("wallpaper", help="the desktop wallpaper")
    w.add_argument("--width", type=int, default=1920)
    w.add_argument("--height", type=int, default=1200)
    w.add_argument("--spacing", type=float, default=72.0)
    w.add_argument("--density", type=float, default=1.0, help="grid scale; >1 is finer")
    w.add_argument("--seed", type=int, default=0, help="vary the composition; 0 does not")
    w.add_argument("--rotate", type=float, help="tilt of the lattice; not seeded")
    w.add_argument("--gradient-angle", type=float, help="background gradient, in degrees")
    w.add_argument("--focus-x", type=float, help="the mark, 0..1 across; not seeded")
    w.add_argument("--focus-y", type=float, help="the mark, 0..1 down; not seeded")
    w.add_argument("--glow-phase", type=float, help="0..1 through the pulse, as in `mark`")
    w.set_defaults(draw=wallpaper)

    m = sub.add_parser("mark", help="the hexagonal mark, for the boot splash")
    m.add_argument("--spacing", type=float, default=72.0)
    m.add_argument("--padding", type=float, default=8.0)
    m.add_argument("--phase", type=float, default=0.0, help="0..1 through the pulse")
    m.set_defaults(draw=mark)

    g = sub.add_parser("widget", help="a piece of the boot splash's password prompt")
    g.add_argument("name", choices=["entry", "bullet", "lock", "capslock"])
    g.set_defaults(draw=widget)

    k = sub.add_parser("key", help="one face of the Stream Deck")
    k.add_argument(
        "--index", type=int, required=True, choices=range(DECK_COLS * DECK_ROWS),
        metavar="0..14", help="which key, counted across and then down",
    )
    k.add_argument("--glyph", default="", help="a character to draw, usually a Nerd Font one")
    k.add_argument("--glyph-font", default="Symbols Nerd Font")
    k.add_argument("--glyph-size", type=float, default=30.0)
    k.add_argument("--embed", type=argparse.FileType("r"), help="an SVG to draw instead")
    k.add_argument("--label", default="", help="a word under the glyph; drawn upper-case")
    k.add_argument("--label-font", default="JetBrains Mono")
    k.add_argument("--label-size", type=float, default=9.0)
    k.add_argument("--tone", choices=sorted(DECK_TONES), default="plain")
    k.add_argument("--bar", choices=["none", "bottom", "left"], default="none")
    k.add_argument("--density", type=float, default=1.0, help="grid scale; >1 is finer")
    k.set_defaults(draw=deck_key)

    args = parser.parse_args(argv)
    if args.drawing == "wallpaper":
        vary(args)
    palette = dict(DEFAULT_PALETTE)
    if args.palette:
        palette.update(json.load(args.palette))
    sys.stdout.write(args.draw(args, palette))


if __name__ == "__main__":
    main()
