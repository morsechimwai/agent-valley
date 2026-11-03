# Builds AgentValleyCrew.ttf from the faces JSON that CrewFont.facesJSON() writes. Everything
# drawn comes from that file: this script holds no people, poses or colours of its own.
# Each face is ONE wide character from the unassigned end of Plane 3: every terminal and Claude Code
# give it two cells (East Asian Wide), Chrome-based terminals look it up in any installed font
# (they never do for private use), and Ghostty fits a colour glyph to its cells in one piece.
# Usage: crew-font.py faces.json out.ttf
import functools, hashlib, json, math, os, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.basePen import BasePen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._g_l_y_f import flagOverlapSimple
from fontTools.ttLib.tables.S_V_G_ import SVGDocument

PX = 100            # font units per picture pixel
TOP = 1000          # the face's top edge; bottom edge is TOP - 12 * PX
WIDE = 1440         # two monospace cells of 0.6 em
LEFT = (WIDE - 12 * PX) // 2

raw = open(sys.argv[1], "rb").read()
data = json.loads(raw)
FAMILY = data["family"]
PS = FAMILY.replace(" ", "")

palette, index = [], {}
def pal(hexrgb, alpha):
    rgb = int(hexrgb, 16)
    if (rgb, alpha) not in index:
        index[(rgb, alpha)] = len(palette)
        palette.append((((rgb >> 16) & 255) / 255, ((rgb >> 8) & 255) / 255, (rgb & 255) / 255, alpha))
    return index[(rgb, alpha)]

def outline(runs, frame=False):
    """Runs are (x0, x1, y) in pixels, x1 not included, y counted down from the top."""
    pen = TTGlyphPen(None)
    if frame:  # zero-area marks: bounds are the whole two cells, which Ghostty fits to the cells
        for x, y in ((0, TOP - 12 * PX), (WIDE, TOP)):
            pen.moveTo((x, y)); pen.lineTo((x, y)); pen.closePath()
    for x0, x1, y in runs:
        x0, x1, y0 = LEFT + x0 * PX, LEFT + x1 * PX, TOP - (y + 1) * PX
        pen.moveTo((x0, y0)); pen.lineTo((x0, y0 + PX)); pen.lineTo((x1, y0 + PX)); pen.lineTo((x1, y0)); pen.closePath()
    return pen.glyph()

def merged(runs):
    """Runs that touch along a row become one, whatever their colours."""
    out = []
    for x0, x1, y in sorted(runs, key=lambda r: (r[2], r[0])):
        if out and out[-1][2] == y and out[-1][1] == x0:
            out[-1] = (out[-1][0], x1, y)
        else:
            out.append((x0, x1, y))
    return out

# A colour's cells are one layer glyph. The same cells come back across hundreds of faces (a
# hair, a shirt, a thing in hand), so each shape is drawn once and every face that has it points
# at it with its own colour.
order, glyphs, cmap, colr, svg_src, shapes = [".notdef"], {".notdef": TTGlyphPen(None).glyph()}, {}, {}, {}, {}
for face in data["faces"]:
    key, alpha = f"u{face['codepoint']:X}", face["opacity"]
    by_colour = {}
    for x0, x1, y, c in face["rects"]:
        by_colour.setdefault(c, []).append((x0, x1, y))
    # The plain outline under the colours, for a renderer that draws no colour.
    order.append(key); glyphs[key] = outline(merged(r for runs in by_colour.values() for r in runs), frame=True)
    cmap[face["codepoint"]] = key
    layers = []
    for c, runs in by_colour.items():
        shape = tuple(runs)
        if shape not in shapes:
            shapes[shape] = f"s{len(shapes)}"
            order.append(shapes[shape]); glyphs[shapes[shape]] = outline(runs)
        layers.append((shapes[shape], pal(c, alpha)))
    colr[key] = layers
    svg_src[key] = (by_colour, alpha)

# The panel's marks: plain outlines with no colour, so the terminal draws them in the text's
# colour. Their parts overlap, and the overlap flag tells a renderer to fill the union.
for mark in data.get("marks", []):
    key = f"u{mark['codepoint']:X}"
    pen = TTGlyphPen(None)
    for c in mark["contours"]:
        pen.moveTo((c[0], c[1]))
        for i in range(2, len(c), 2):
            pen.lineTo((c[i], c[i + 1]))
        pen.closePath()
    glyph = pen.glyph()
    glyph.flags[0] |= flagOverlapSimple
    order.append(key); glyphs[key] = glyph; cmap[mark["codepoint"]] = key

# Name badges: the face on a round pill one wide character across, its edge and fill in the
# shirt's dyes. Claude writes the name after it as text. One character, so no terminal can leave
# a seam inside it: Ghostty draws each colour glyph 2.5% narrower than its frame and centred, and
# draws none wider than two cells.
PLEX = TTFont(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts", "IBMPlexMono-SemiBold.woff2"))
PLEX_GLYPHS, PLEX_CMAP = PLEX.getGlyphSet(), PLEX.getBestCmap()
CY, R_OUT, R_IN = TOP - 600, 600, 500            # the pill fills the face's height; its edge is 100 thick
TPX, FACE_TOP = 75, TOP - 150                    # the face, 900 square
FACE_X = (WIDE - 12 * TPX) // 2                  # centred on the pill
SEAM = 12                                       # how far a badge part's colours reach into its neighbours

def capsule(r, steps=24, left=30 + R_OUT, right=WIDE - 30 - R_OUT, cy=CY):
    """The pill's outline, clockwise as TrueType fills it. 30 clear at each end, so two side by side don't touch."""
    pts = [(right + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in [90 - 180 * i / steps for i in range(steps + 1)]]
    pts += [(left + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in [270 - 180 * i / steps for i in range(steps + 1)]]
    return pts

def clip(poly, lo, hi):
    """The part of a closed outline between x = lo and x = hi, moved so lo is 0. A concave outline
    may come back with edges along the cut, which add nothing to the fill."""
    for keep, at in ((lambda p: p[0] >= lo, lo), (lambda p: p[0] <= hi, hi)):
        out = []
        for i, p in enumerate(poly):
            q = poly[i - 1]
            if keep(p) != keep(q):
                t = (at - q[0]) / (p[0] - q[0])
                out.append((at, q[1] + t * (p[1] - q[1])))
            if keep(p):
                out.append(p)
        poly = out
    return [(round(x - lo), round(y)) for x, y in poly]

def cut(polys, lo, reach=0):
    """`polys` across several characters, as the one starting at `lo` holds them: cut `reach` past its edges, `lo` at 0."""
    out = [[(x - reach, y) for x, y in clip(p, lo - reach, lo + WIDE + reach)] for p in polys]
    return [p for p in out if len(p) > 2]

def polygons_glyph(polys):
    pen = TTGlyphPen(None)
    for poly in polys:
        pen.moveTo(poly[0])
        for p in poly[1:]:
            pen.lineTo(p)
        pen.closePath()
    return pen.glyph()

class FlatPen(BasePen):
    """A glyph's contours as polygons, each curve as eight straight steps."""
    def __init__(self, glyphs, matrix):
        super().__init__(glyphs); self.m, self.polys = matrix, []
    def _point(self, p):
        a, b, c, d, e, f = self.m
        return (a * p[0] + c * p[1] + e, b * p[0] + d * p[1] + f)
    def _moveTo(self, p): self.polys.append([self._point(p)]); self.at = p
    def _lineTo(self, p): self.polys[-1].append(self._point(p)); self.at = p
    def _qCurveToOne(self, p1, p2):
        p0 = self.at
        for i in range(1, 9):
            t = i / 8; u = 1 - t
            self.polys[-1].append(self._point((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])))
        self.at = p2
    def _curveToOne(self, p1, p2, p3):
        p0 = self.at
        for i in range(1, 9):
            t = i / 8; u = 1 - t
            self.polys[-1].append(self._point(tuple(u**3 * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t**3 * p3[k] for k in (0, 1))))
        self.at = p3
    def _closePath(self): pass

def frame_glyph(polys):
    """A plain outline with the frame that tells Ghostty the glyph's two cells."""
    pen = TTGlyphPen(None)
    for x, y in ((0, TOP - 12 * PX), (WIDE, TOP)):
        pen.moveTo((x, y)); pen.lineTo((x, y)); pen.closePath()
    for poly in polys:
        pen.moveTo(poly[0])
        for p in poly[1:]:
            pen.lineTo(p)
        pen.closePath()
    glyph = pen.glyph()
    glyph.flags[0] |= flagOverlapSimple
    return glyph

tag_svg = []
def shared(name, polys):
    """One glyph per shape, drawn as a layer by every character that has it."""
    if name not in shapes:
        shapes[name] = f"s{len(shapes)}"
        order.append(shapes[name]); glyphs[shapes[name]] = polygons_glyph(polys)
    return shapes[name]

def d(polys):
    """Polygons as an SVG path: font units, y turned down."""
    return "".join("M" + "L".join(f"{x} {-y}" for x, y in p) + "Z" for p in polys)

outer, inner = capsule(R_OUT), capsule(R_IN)
for tag in data.get("tags", []):
    key = f"u{tag['codepoint']:X}"
    runs = [(x0, x1, y) for x0, x1, y, _ in tag["rects"]]

    def face_runs(runs):
        return [[(FACE_X + x0 * TPX, FACE_TOP - (y + 1) * TPX), (FACE_X + x0 * TPX, FACE_TOP - y * TPX),
                 (FACE_X + x1 * TPX, FACE_TOP - y * TPX), (FACE_X + x1 * TPX, FACE_TOP - (y + 1) * TPX)] for x0, x1, y in runs]

    # The plain outline, for a renderer that draws no colour: the edge as a ring and the face's shape.
    order.append(key); glyphs[key] = frame_glyph([outer, inner[::-1]] + face_runs(merged(runs))); cmap[tag["codepoint"]] = key

    by_colour = {}
    for x0, x1, y, c in tag["rects"]:
        by_colour.setdefault(c, []).append((x0, x1, y))
    layers = [(shared("edge", [outer]), pal(tag["edge"], 1)), (shared("fill", [inner]), pal(tag["fill"], 1))]
    layers += [(shared(("face", tuple(cruns)), face_runs(cruns)), pal(c, 1)) for c, cruns in by_colour.items()]
    colr[key] = layers

    faces_svg = "".join(f'<path fill="#{c}" d="' + "".join(f"M{x0} {y}h{x1 - x0}v1H{x0}z" for x0, x1, y in cruns) + '"/>'
                        for c, cruns in by_colour.items())
    tag_svg.append((key, f'<path fill="#{tag["edge"]}" d="{d([outer])}"/><path fill="#{tag["fill"]}" d="{d([inner])}"/>'
                         f'<g transform="matrix({TPX} 0 0 {TPX} {FACE_X} {-FACE_TOP})">{faces_svg}</g>'))

# Plan badges: the plan's name on a pill in Claude's orange, `parts` characters wide, the fill
# faint over the terminal's background and the letters a lighter orange, in IBM Plex Mono SemiBold, the same
# size on every badge. The fill is not carried past the parts' edges: two faint layers over each
# other would show as a darker line.
# The solid set is iTerm's, which leaves a hairline between wide characters: the fill is solid and
# runs on under the next part, which draws over it, and each letter is drawn whole on the last part
# it touches, over the part before. Ghostty would shrink such parts, so it keeps the first set.
B_R = 540                                       # the pill a little under the line's height
BLEED = 600                                     # how far a solid part's fill runs on; short of the end cap

@functools.cache
def badge_letters(name, parts):
    """`name` centred on its pill, as big as fits up to 0.95: only a long name with a letter
    below the line comes out smaller. One list of outlines per letter."""
    left, right = 30 + B_R, parts * WIDE - 30 - B_R
    for size in range(950, 600, -25):
        s = size / 1000
        base = CY - PLEX["OS/2"].sCapHeight * s / 2
        each = []
        for i, c in enumerate(name):
            pen = FlatPen(PLEX_GLYPHS, (s, 0, 0, s, i * 600 * s, base))
            PLEX_GLYPHS[PLEX_CMAP[ord(c)]].draw(pen)
            each.append(pen.polys)
        xs = [x for l in each for p in l for x, _ in p]
        shift = parts * WIDE / 2 - (min(xs) + max(xs)) / 2
        each = [[[(round(x + shift), round(y)) for x, y in p] for p in l] for l in each]
        if all(math.hypot(x - min(max(x, left), right), y - CY) <= B_R - 80 for l in each for p in l for x, y in p):
            return each
    raise SystemExit(f"no room for {name} on its badge")

for badge in data.get("badges", []):
    key, part, parts, name = f"u{badge['codepoint']:X}", badge["part"], badge["parts"], badge["name"]
    lo = part * WIDE
    pill = capsule(B_R, left=30 + B_R, right=parts * WIDE - 30 - B_R)
    ring = cut([pill], lo) + [p[::-1] for p in cut([capsule(B_R - 50, left=30 + B_R, right=parts * WIDE - 30 - B_R)], lo)]
    each, solid = badge_letters(name, parts), badge.get("solid")
    flat = [p for l in each for p in l]
    if solid:
        fill = [p for p in [clip(pill, lo, lo + WIDE + BLEED)] if len(p) > 2]
        letters = [[(x - lo, y) for x, y in p] for l in each if (max(x for p in l for x, _ in p) - 1) // WIDE == part for p in l]
        colour, opacity = solid, 1
    else:
        fill, letters, colour, opacity = cut([pill], lo), cut(flat, lo, SEAM), badge["colour"], badge["fill"]
    order.append(key); glyphs[key] = frame_glyph(ring + cut(flat, lo)); cmap[badge["codepoint"]] = key
    layers = [(shared(("badge-fill", parts, part, solid), fill), pal(colour, opacity))]
    if letters:
        layers.append((shared(("badge-letters", name, part, solid), letters), pal(badge["ink"], 1)))
    colr[key] = layers
    tag_svg.append((key, f'<path fill="#{colour}" fill-opacity="{opacity:g}" d="{d(fill)}"/>'
                         + (f'<path fill="#{badge["ink"]}" d="{d(letters)}"/>' if letters else "")))

# Limit rings: one character per step, filled clockwise from the top. The used arc is in the
# text's colour (palette index 0xFFFF), so it reads on a light background as on a dark one; the
# rest is a faint grey over either. No SVG copy: Ghostty, which draws colour only from SVG, draws
# the plain outline in the text's colour, the used arc full and the rest a thin line.
RING_X, RING_OUT, RING_IN, RING_LINE = WIDE // 2, 540, 330, 40

def arc(r0, r1, a0, a1):
    """The ring between radii r0 < r1 from angle a0 down to a1 (clockwise), as one outline."""
    steps = max(2, round((a0 - a1) / 5))
    angles = [a0 - (a0 - a1) * i / steps for i in range(steps + 1)]
    out = [(round(RING_X + r1 * math.cos(math.radians(a))), round(CY + r1 * math.sin(math.radians(a)))) for a in angles]
    return out + [(round(RING_X + r0 * math.cos(math.radians(a))), round(CY + r0 * math.sin(math.radians(a)))) for a in reversed(angles)]

def ring(r0, r1, a0, a1):
    """`arc`, or the whole ring as two outlines when it goes all the way round."""
    if a0 - a1 < 360:
        return [arc(r0, r1, a0, a1)]
    full = lambda r: [(round(RING_X + r * math.cos(math.radians(90 - 5 * i))), round(CY + r * math.sin(math.radians(90 - 5 * i)))) for i in range(72)]
    return [full(r1), full(r0)[::-1]]

for bar in data.get("bars", []):
    key, level, steps = f"u{bar['codepoint']:X}", bar["level"], bar["levels"] - 1
    turn = 360 * level / steps
    used = ring(RING_IN, RING_OUT, 90, 90 - turn) if level else []
    rest = ring(RING_IN, RING_OUT, 90 - turn, -270) if level < steps else []
    mid = (RING_IN + RING_OUT) / 2
    line = ring(mid - RING_LINE / 2, mid + RING_LINE / 2, 90 - turn, -270) if level < steps else []
    order.append(key); glyphs[key] = frame_glyph(used + line); cmap[bar["codepoint"]] = key
    layers = []
    if rest:
        layers.append((shared(("ring-rest", level), rest), pal(bar["track"], bar["opacity"])))
    if used:
        layers.append((shared(("ring-used", level), used), 0xFFFF))
    colr[key] = layers

fb = FontBuilder(1200, isTTF=True)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)
fb.setupGlyf(glyphs)
glyf = fb.font["glyf"]
def lsb(name):  # a glyph's left side bearing must be its own left edge, or each layer slides
    g = glyf[name]; g.recalcBounds(glyf)
    return getattr(g, "xMin", 0) if g.numberOfContours else 0
fb.setupHorizontalMetrics({g: (WIDE, lsb(g)) for g in order})
fb.setupHorizontalHeader(ascent=1000, descent=-200)
fb.setupNameTable({"familyName": FAMILY, "styleName": "Regular",
                   "copyright": "The crew's faces: AgentValley. The letters of the plan badges: IBM Plex Mono, Copyright 2017 IBM Corp. with Reserved Font Name \"Plex\".",
                   "licenseDescription": "This Font Software is licensed under the SIL Open Font License, Version 1.1.",
                   "licenseInfoURL": "https://openfontlicense.org",
                   "uniqueFontIdentifier": f"AgentValleyCrew-{hashlib.sha256(raw).hexdigest()}",
                   "fullName": f"{FAMILY} Regular", "psName": f"{PS}-Regular", "version": "Version 1.0"})
fb.setupOS2(sTypoAscender=1000, sTypoDescender=-200, usWinAscent=1000, usWinDescent=200, sxHeight=660, sCapHeight=876)
fb.setupPost(keepGlyphNames=False)  # names would only add weight: tables point at glyphs by number
fb.setupCOLR(colr, version=0)
fb.setupCPAL([palette])

# OpenType-SVG copy of each face: Ghostty draws colour only from sbix or SVG, not COLR. One path
# per colour in picture pixels, scaled into font units by the group around them.
docs = []
for name, (by_colour, a) in svg_src.items():
    gid = order.index(name)
    paths = "".join(f'<path fill="#{c}" d="' + "".join(f"M{x0} {y}h{x1 - x0}v1H{x0}z" for x0, x1, y in runs) + '"/>'
                    for c, runs in by_colour.items())
    fade = "" if a == 1 else f' fill-opacity="{a:g}"'
    frame = f'<rect y="{-TOP}" width="{WIDE}" height="{12 * PX}" fill-opacity="0"/>'
    docs.append(SVGDocument(f'<svg xmlns="http://www.w3.org/2000/svg"><g id="glyph{gid}">{frame}'
                            f'<g transform="matrix({PX} 0 0 {PX} {LEFT} {-TOP})"{fade}>{paths}</g></g></svg>', gid, gid, False))
for name, body in tag_svg:
    gid = order.index(name)
    frame = f'<rect y="{-TOP}" width="{WIDE}" height="{12 * PX}" fill-opacity="0"/>'
    docs.append(SVGDocument(f'<svg xmlns="http://www.w3.org/2000/svg"><g id="glyph{gid}">{frame}{body}</g></svg>', gid, gid, False))
svg = newTable("SVG "); svg.docList = sorted(docs, key=lambda d: d.startGlyphID)
fb.font["SVG "] = svg

fb.save(sys.argv[2])
print(sys.argv[2], len(data["faces"]), "faces", len(data.get("marks", [])), "marks", len(data.get("tags", [])), "tags", len(data.get("badges", [])), "badge parts", len(data.get("bars", [])), "rings", len(order), "glyphs", len(palette), "colours")
