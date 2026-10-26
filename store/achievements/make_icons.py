"""Draws the 512x512 achievement icons for the Play Console as SVG and PNG.

usage: python3 store/achievements/make_icons.py   (needs rsvg-convert)

Each icon is the game's gold crown on a purple disc, with a symbol or number
below for the achievement. Play Games greys out the locked ones itself.
"""
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
S = 512
PURPLE, PURPLE_DARK = "#5b4a9e", "#3f3278"
GOLD, GOLD_DARK = "#f4c542", "#d9a521"
INK = "#1e1e1e"

# Crown shape from crown_art.gd, in units of its square.
OUTLINE = [(0.22, 0.70), (0.17, 0.32), (0.36, 0.50), (0.50, 0.24), (0.64, 0.50), (0.83, 0.32), (0.78, 0.70)]
TIPS = [(0.17, 0.30), (0.50, 0.21), (0.83, 0.30)]


def crown(x0, y0, s):
    pts = " ".join(f"{x0 + x * s:.1f},{y0 + y * s:.1f}" for x, y in OUTLINE)
    w = s * 0.035
    out = [f'<polygon points="{pts}" fill="{INK}" stroke="{INK}" stroke-width="{2 * w:.1f}" stroke-linejoin="round"/>',
           f'<rect x="{x0 + 0.22 * s - w:.1f}" y="{y0 + 0.74 * s - w:.1f}" width="{0.56 * s + 2 * w:.1f}" '
           f'height="{0.08 * s + 2 * w:.1f}" fill="{INK}"/>']
    out += [f'<circle cx="{x0 + x * s:.1f}" cy="{y0 + y * s:.1f}" r="{0.045 * s + w:.1f}" fill="{INK}"/>' for x, y in TIPS]
    out += [f'<polygon points="{pts}" fill="{GOLD}"/>',
            f'<rect x="{x0 + 0.22 * s:.1f}" y="{y0 + 0.74 * s:.1f}" width="{0.56 * s:.1f}" height="{0.08 * s:.1f}" fill="{GOLD_DARK}"/>']
    out += [f'<circle cx="{x0 + x * s:.1f}" cy="{y0 + y * s:.1f}" r="{0.045 * s:.1f}" fill="{GOLD}"/>' for x, y in TIPS]
    return out


def gold(shape):
    """A shape in gold with the crowns' dark outline."""
    return [shape.replace("/>", f' fill="none" stroke="{INK}" stroke-width="14" stroke-linejoin="round" stroke-linecap="round"/>'),
            shape.replace("/>", f' fill="{GOLD}"/>')]


def line(shape, width=22):
    """An open gold stroke with a dark outline."""
    return [shape.replace("/>", f' fill="none" stroke="{INK}" stroke-width="{width + 14}" stroke-linejoin="round" stroke-linecap="round"/>'),
            shape.replace("/>", f' fill="none" stroke="{GOLD}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>')]


def text(label, size=130, y=420):
    style = f'font-family="Open Sans" font-weight="800" font-size="{size}" text-anchor="middle"'
    return [f'<text x="256" y="{y}" {style} fill="none" stroke="{INK}" stroke-width="14" stroke-linejoin="round">{label}</text>',
            f'<text x="256" y="{y}" {style} fill="{GOLD}">{label}</text>']


def star(cx, cy, r):
    import math
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append(f"{cx + rr * math.cos(a):.1f},{cy + rr * math.sin(a):.1f}")
    return f'<polygon points="{" ".join(pts)}"/>'


def mountain(flag):
    out = gold('<polygon points="136,430 226,300 262,346 300,292 380,430"/>')
    if flag:
        out += line('<polyline points="300,292 300,236"/>', 10)
        out += gold('<polygon points="300,236 346,250 300,266"/>')
    return out


GLYPHS = {
    "first_crown": [],
    "unaided": line('<polyline points="186,372 236,420 330,320"/>', 30),
    "hard": gold(star(166, 372, 52)) + gold(star(256, 372, 52)) + gold(star(346, 372, 52)),
    "big_board": text("10×10", 100, 410),
    "weekly": gold('<rect x="166" y="300" width="180" height="140" rx="18"/>')
    + [f'<rect x="166" y="300" width="180" height="40" rx="18" fill="{GOLD_DARK}"/>']
    + [f'<rect x="{186 + 32 * c}" y="{352 + 28 * r}" width="20" height="18" rx="4" fill="{INK}" opacity="0.55"/>'
       for r in range(3) for c in range(5) if r * 5 + c < 14],
    "streak_7": text("7", 150),
    "streak_30": text("30", 150),
    "climb_10": mountain(False),
    "climb_25": mountain(True),
    "quick": gold('<circle cx="256" cy="372" r="72"/>') + line('<polyline points="256,326 256,372 290,394"/>', 12)
    + gold('<rect x="236" y="282" width="40" height="22" rx="6"/>'),
    "century": text("100", 140),
}


def icon(name):
    big = not GLYPHS[name]
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">',
             '<defs><radialGradient id="bg" cx="50%" cy="40%" r="65%">'
             f'<stop offset="0" stop-color="{PURPLE}"/><stop offset="1" stop-color="{PURPLE_DARK}"/></radialGradient></defs>',
             f'<rect width="{S}" height="{S}" fill="url(#bg)"/>',
             f'<circle cx="256" cy="256" r="232" fill="none" stroke="{GOLD}" stroke-width="10" opacity="0.8"/>']
    parts += crown(96, 70, 320) if big else crown(146, 40, 220)
    parts += GLYPHS[name]
    parts.append("</svg>")
    return "\n".join(parts)


for name in GLYPHS:
    svg_path = os.path.join(HERE, name + ".svg")
    with open(svg_path, "w") as f:
        f.write(icon(name))
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), "-o", os.path.join(HERE, name + ".png"), svg_path], check=True)
    print("wrote", name)
