"""Generates the Offgrid brand kit as pure SVG (text converted to outlines)."""
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONTS = Path("node_modules/@fontsource")
OUT = Path("out")
OUT.mkdir(exist_ok=True)

# Palette
FOREST = "#183c2e"
DEEP = "#0e261d"
CREAM = "#f2eee3"
SIGNAL = "#e9a23b"
SAGE = "#8db59d"
INK = "#13221b"


class Text:
    """Lays out a string in a font and returns an SVG path, with kerning-free advance widths."""

    def __init__(self, font_path):
        self.font = TTFont(font_path)
        self.glyphs = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.upm = self.font["head"].unitsPerEm
        hhea = self.font["hhea"]
        self.ascent = hhea.ascent
        os2 = self.font["OS/2"]
        self.cap = getattr(os2, "sCapHeight", 0) or self.ascent * 0.7
        self.xh = getattr(os2, "sxHeight", 0) or self.ascent * 0.5

    def width(self, text, size, tracking=0.0):
        scale = size / self.upm
        total = 0
        for i, ch in enumerate(text):
            g = self.cmap[ord(ch)]
            total += self.glyphs[g].width * scale
            if i < len(text) - 1:
                total += tracking * size
        return total

    def path(self, text, size, x, baseline, tracking=0.0):
        scale = size / self.upm
        pen = SVGPathPen(self.glyphs)
        cursor = x
        for ch in text:
            g = self.cmap[ord(ch)]
            tpen = TransformPen(pen, (scale, 0, 0, -scale, cursor, baseline))
            self.glyphs[g].draw(tpen)
            cursor += self.glyphs[g].width * scale + tracking * size
        return pen.getCommands()


SANS = Text(FONTS / "inter-tight/files/inter-tight-latin-600-normal.woff2")
SANS_MED = Text(FONTS / "inter-tight/files/inter-tight-latin-500-normal.woff2")
SERIF_IT = Text(FONTS / "instrument-serif/files/instrument-serif-latin-400-italic.woff2")
MONO = Text(FONTS / "jetbrains-mono/files/jetbrains-mono-latin-500-normal.woff2")


def mark(x, y, size, dot=CREAM, signal=SIGNAL, dim=None):
    """The 'off-grid' mark: a 3x3 grid of dots with one escaping the top-right corner.
    Drawn in a 100x100 box at (x, y) scaled to `size`."""
    s = size / 100
    r = 7.2 * s
    parts = []
    xs = [22, 44, 66]
    ys = [38, 60, 82]
    for j, cy in enumerate(ys):
        for i, cx in enumerate(xs):
            if i == 2 and j == 0:
                continue  # this dot has left the grid
            parts.append(f'<circle cx="{x + cx * s:.2f}" cy="{y + cy * s:.2f}" r="{r:.2f}" fill="{dot}"/>')
    # ghost of where it used to be
    if dim:
        parts.append(f'<circle cx="{x + 66 * s:.2f}" cy="{y + 38 * s:.2f}" r="{r:.2f}" fill="none" '
                     f'stroke="{dim}" stroke-width="{1.6 * s:.2f}" stroke-dasharray="{2.4 * s:.2f} {2.2 * s:.2f}"/>')
    parts.append(f'<circle cx="{x + 86 * s:.2f}" cy="{y + 16 * s:.2f}" r="{r:.2f}" fill="{signal}"/>')
    return "\n".join(parts)


def svg(w, h, body, bg=None):
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f"{rect}{body}</svg>\n")


def save(name, content):
    (OUT / name).write_text(content)


# ---------------------------------------------------------------- mark only
save("offgrid-mark.svg", svg(100, 100, mark(0, 0, 100, dot=FOREST)))
save("offgrid-mark-light.svg", svg(100, 100, mark(0, 0, 100, dot=CREAM)))

# ---------------------------------------------------------------- app icon (1024, no transparency, iOS masks corners)
icon_body = (
    f'<defs><radialGradient id="g" cx="30%" cy="18%" r="95%">'
    f'<stop offset="0" stop-color="#21503d"/><stop offset="1" stop-color="{DEEP}"/></radialGradient></defs>'
    f'<rect width="1024" height="1024" fill="url(#g)"/>'
    + mark(480 - 44 * 6.6, 548 - 60 * 6.6, 660, dot=CREAM, dim="#4f7d68")
)
save("app-icon.svg", svg(1024, 1024, icon_body))


# ---------------------------------------------------------------- horizontal logo
def lockup(mark_color, word_color, height=120):
    size = height * 0.62
    word = "offgrid"
    mark_size = height
    gap = height * 0.06
    # Align the wordmark's x-height band with the grid's lower two rows.
    baseline = height * 0.80
    path = SANS.path(word, size, mark_size + gap, baseline, tracking=-0.035)
    w = mark_size + gap + SANS.width(word, size, tracking=-0.035) + 4
    body = mark(0, 0, mark_size, dot=mark_color) + f'<path d="{path}" fill="{word_color}"/>'
    return w, height, body


w, h, body = lockup(FOREST, INK)
save("offgrid-logo.svg", svg(round(w), h, body))
w, h, body = lockup(CREAM, CREAM)
save("offgrid-logo-light.svg", svg(round(w), h, body))


# ---------------------------------------------------------------- banners
def banner(W, H, name, tagline_size, show_meta=True):
    pad = H * 0.16
    body = []
    body.append(f'<rect width="{W}" height="{H}" fill="{FOREST}"/>')
    # faint dot grid texture, with a single amber dot that broke free
    step = H / 9
    dots = []
    cols = int(W / step) + 2
    rows = int(H / step) + 2
    for j in range(rows):
        for i in range(cols):
            cx, cy = i * step + step * 0.5, j * step + step * 0.5
            dots.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{H * 0.0042:.2f}" fill="#2f5a47"/>')
    body.append(f'<g>{"".join(dots)}</g>')
    # soft vignette so text sits on calm ground
    body.append('<defs><linearGradient id="fade" x1="0" x2="1"><stop offset="0" stop-color="#183c2e" stop-opacity="0.96"/>'
                '<stop offset="0.62" stop-color="#183c2e" stop-opacity="0.75"/><stop offset="1" stop-color="#183c2e" stop-opacity="0"/></linearGradient></defs>')
    body.append(f'<rect width="{W}" height="{H}" fill="url(#fade)"/>')

    # big mark on the right, bleeding off the grid
    big = H * 0.78
    mx = W - big - pad * 0.7
    my = (H - big) / 2 + H * 0.04
    body.append(mark(mx, my, big, dot=CREAM, dim="#5d8a74"))

    # logo lockup, top-left
    lh = H * 0.13
    lw, _, lbody = lockup(CREAM, CREAM, height=lh)
    body.append(f'<g transform="translate({pad:.1f},{pad * 0.9:.1f})">{lbody}</g>')

    # tagline: two lines, second in italic serif accent
    t1, t2 = "Your AI.", "No signal needed."
    ts = tagline_size
    y1 = H * 0.60
    y2 = y1 + ts * 1.02
    body.append(f'<path d="{SANS.path(t1, ts, pad, y1, tracking=-0.03)}" fill="{CREAM}"/>')
    body.append(f'<path d="{SERIF_IT.path(t2, ts * 1.12, pad, y2, tracking=-0.01)}" fill="{SIGNAL}"/>')

    if show_meta:
        meta = "ON-DEVICE  ·  PRIVATE  ·  WORKS IN AIRPLANE MODE"
        ms = H * 0.028
        body.append(f'<path d="{MONO.path(meta, ms, pad, H - pad * 0.75, tracking=0.06)}" fill="{SAGE}"/>')
    save(name, svg(W, H, "".join(body)))


banner(1500, 500, "banner-x-1500x500.svg", 70)
banner(1280, 640, "banner-github-1280x640.svg", 84)
banner(1600, 520, "banner-readme-1600x520.svg", 74)
print("svgs written:", sorted(p.name for p in OUT.glob("*.svg")))
