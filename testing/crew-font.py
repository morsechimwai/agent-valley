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

# Name tags: a pill three characters wide, its edge and fill in the shirt's dyes, the face at its
# left end and the name in IBM Plex Mono SemiBold (OFL, testing/fonts) in the middle of the room
# right of it. Every shape is cut at the parts' edges: the plain outline exactly, the colours a
# little past them so no hairline shows where two parts meet, wherever a terminal draws a glyph.
PLEX = TTFont(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts", "IBMPlexMono-SemiBold.woff2"))
PLEX_GLYPHS, PLEX_CMAP = PLEX.getGlyphSet(), PLEX.getBestCmap()
TAG_W = 3 * WIDE
CY, R_OUT, R_IN = TOP - 600, 600, 500            # the pill fills the face's height; its edge is 100 thick
CX_L, CX_R = 30 + R_OUT, TAG_W - 30 - R_OUT     # 30 clear at each end, so tags side by side don't touch
TPX, FACE_X, FACE_TOP = 75, 420, TOP - 150      # the face, 900 square, clear of the round end's edge
FACE_RIGHT = FACE_X + 12 * TPX
SEAM = 12                                       # how far a part's colours reach into its neighbours

def capsule(r, steps=24, left=CX_L, right=CX_R, cy=CY):
    """The pill's outline, clockwise as TrueType fills it."""
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
    """`polys` in tag units, as part `lo` holds them: cut `reach` past its edges, `lo` at 0."""
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

@functools.cache
def name_polys(name):
    """`name` set in the room right of the face, as polygons in tag units: as big as fits inside
    the fill, its ink centred between the face and the pill's right end."""
    def setting(s):
        base = CY - PLEX["OS/2"].sCapHeight * s / 2   # capitals centred on the pill
        polys = []
        for i, c in enumerate(name):
            pen = FlatPen(PLEX_GLYPHS, (s, 0, 0, s, i * 600 * s, base))
            PLEX_GLYPHS[PLEX_CMAP[ord(c)]].draw(pen)
            polys += pen.polys
        return polys
    for size in range(800, 600, -20):
        polys = setting(size / 1000)
        xs = [x for p in polys for x, _ in p]
        shift = (FACE_RIGHT + CX_R + R_IN) / 2 - (min(xs) + max(xs)) / 2
        polys = [[(x + shift, y) for x, y in p] for p in polys]
        def inside(x, y):
            return math.hypot(x - min(max(x, CX_L), CX_R), y - CY) <= R_IN - 60
        if min(xs) + shift >= FACE_RIGHT + 120 and all(inside(x, y) for p in polys for x, y in p):
            return [[(round(x), round(y)) for x, y in p] for p in polys]
    raise SystemExit(f"no room for {name} on its tag")

tag_svg = []
outer, inner = capsule(R_OUT), capsule(R_IN)
for tag in data.get("tags", []):
    key, part = f"u{tag['codepoint']:X}", tag["part"]
    lo = part * WIDE
    runs = [(x0, x1, y) for x0, x1, y, _ in tag["rects"]]

    def face_runs(runs):
        return [[(FACE_X + x0 * TPX, FACE_TOP - (y + 1) * TPX), (FACE_X + x0 * TPX, FACE_TOP - y * TPX),
                 (FACE_X + x1 * TPX, FACE_TOP - y * TPX), (FACE_X + x1 * TPX, FACE_TOP - (y + 1) * TPX)] for x0, x1, y in runs]

    # The plain outline, for a renderer that draws no colour: the edge as a ring, the face's
    # shape and the letters in it, and the frame that tells Ghostty the glyph's two cells.
    plain = cut([outer], lo) + [p[::-1] for p in cut([inner], lo)] + face_runs(merged(runs)) + cut(name_polys(tag["name"]), lo)
    pen = TTGlyphPen(None)
    for x, y in ((0, TOP - 12 * PX), (WIDE, TOP)):
        pen.moveTo((x, y)); pen.lineTo((x, y)); pen.closePath()
    for poly in plain:
        pen.moveTo(poly[0])
        for p in poly[1:]:
            pen.lineTo(p)
        pen.closePath()
    order.append(key); glyphs[key] = pen.glyph(); cmap[tag["codepoint"]] = key

    # The colour layers, each shape drawn once for every tag that has it.
    edge, fill, ink = cut([outer], lo, SEAM), cut([inner], lo, SEAM), cut(name_polys(tag["name"]), lo, SEAM)
    def shared(name, polys):
        if name not in shapes:
            shapes[name] = f"s{len(shapes)}"
            order.append(shapes[name]); glyphs[shapes[name]] = polygons_glyph(polys)
        return shapes[name]
    by_colour = {}
    for x0, x1, y, c in tag["rects"]:
        by_colour.setdefault(c, []).append((x0, x1, y))
    layers = [(shared(("edge", part), edge), pal(tag["edge"], 1)), (shared(("fill", part), fill), pal(tag["fill"], 1))]
    layers += [(shared(("face", tuple(cruns)), face_runs(cruns)), pal(c, 1)) for c, cruns in by_colour.items()]
    if ink:
        layers.append((shared(("letters", tag["name"], part), ink), pal(tag["ink"], 1)))
    colr[key] = layers

    # The same for Ghostty's SVG: font units, y turned down.
    def d(polys):
        return "".join("M" + "L".join(f"{x} {-y}" for x, y in p) + "Z" for p in polys)
    faces_svg = "".join(f'<path fill="#{c}" d="' + "".join(f"M{x0} {y}h{x1 - x0}v1H{x0}z" for x0, x1, y in cruns) + '"/>'
                        for c, cruns in by_colour.items())
    tag_svg.append((key, f'<path fill="#{tag["edge"]}" d="{d(edge)}"/><path fill="#{tag["fill"]}" d="{d(fill)}"/>'
                         f'<g transform="matrix({TPX} 0 0 {TPX} {FACE_X} {-FACE_TOP})">{faces_svg}</g>'
                         + (f'<path fill="#{tag["ink"]}" d="{d(ink)}"/>' if ink else "")))

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

# Plan badges: the plan's name on a pill in Claude's orange, `parts` characters wide, the fill
# faint over the terminal's background and the letters a lighter orange, in IBM Plex Mono SemiBold, the same
# size on every badge. The fill is not carried past the parts' edges: two faint layers over each
# other would show as a darker line.
B_R = 540                                       # the pill a little under the line's height

@functools.cache
def badge_letters(name, parts):
    """`name` centred on its pill, as big as fits up to 0.95: only a long name with a letter
    below the line comes out smaller."""
    left, right = 30 + B_R, parts * WIDE - 30 - B_R
    for size in range(950, 600, -25):
        s = size / 1000
        base = CY - PLEX["OS/2"].sCapHeight * s / 2
        polys = []
        for i, c in enumerate(name):
            pen = FlatPen(PLEX_GLYPHS, (s, 0, 0, s, i * 600 * s, base))
            PLEX_GLYPHS[PLEX_CMAP[ord(c)]].draw(pen)
            polys += pen.polys
        xs = [x for p in polys for x, _ in p]
        shift = parts * WIDE / 2 - (min(xs) + max(xs)) / 2
        polys = [[(round(x + shift), round(y)) for x, y in p] for p in polys]
        if all(math.hypot(x - min(max(x, left), right), y - CY) <= B_R - 80 for p in polys for x, y in p):
            return polys
    raise SystemExit(f"no room for {name} on its badge")

for badge in data.get("badges", []):
    key, part, parts, name = f"u{badge['codepoint']:X}", badge["part"], badge["parts"], badge["name"]
    lo = part * WIDE
    pill = capsule(B_R, left=30 + B_R, right=parts * WIDE - 30 - B_R)
    ring = cut([pill], lo) + [p[::-1] for p in cut([capsule(B_R - 50, left=30 + B_R, right=parts * WIDE - 30 - B_R)], lo)]
    letters, fill = cut(badge_letters(name, parts), lo, SEAM), cut([pill], lo)
    order.append(key); glyphs[key] = frame_glyph(ring + cut(badge_letters(name, parts), lo)); cmap[badge["codepoint"]] = key
    def shared(name, polys):
        if name not in shapes:
            shapes[name] = f"s{len(shapes)}"
            order.append(shapes[name]); glyphs[shapes[name]] = polygons_glyph(polys)
        return shapes[name]
    layers = [(shared(("badge-fill", parts, part), fill), pal(badge["colour"], badge["fill"]))]
    if letters:
        layers.append((shared(("badge-letters", name, part), letters), pal(badge["ink"], 1)))
    colr[key] = layers
    def d(polys):
        return "".join("M" + "L".join(f"{x} {-y}" for x, y in p) + "Z" for p in polys)
    tag_svg.append((key, f'<path fill="#{badge["colour"]}" fill-opacity="{badge["fill"]:g}" d="{d(fill)}"/>'
                         + (f'<path fill="#{badge["ink"]}" d="{d(letters)}"/>' if letters else "")))

# Limit bars: one track with round ends from the first character's left to the last one's right,
# about as thick as the panel's bar beside its text and centred on the capitals. The used part is
# in the text's colour (palette index 0xFFFF), so the bar reads on a light background as on a
# dark one; the track is a faint grey over either. No SVG copy: Ghostty, which draws colour only
# from SVG, draws the plain outline in the text's colour, the used part full and the rest a line.
BAR_MID, BAR_R, BAR_PAD, BAR_LINE = 420, 170, 60, 30

def bar_track(place, r, reach=0):
    """The track's part in a character, its ends at the joins carried `reach` past the edges."""
    steps = 16
    pts = []
    if place == 2:
        cx = WIDE - BAR_PAD - BAR_R
        pts += [(cx + r * math.cos(math.radians(a)), BAR_MID + r * math.sin(math.radians(a))) for a in [90 - 180 * i / steps for i in range(steps + 1)]]
    else:
        pts += [(WIDE + reach, BAR_MID + r), (WIDE + reach, BAR_MID - r)]
    if place == 0:
        cx = BAR_PAD + BAR_R
        pts += [(cx + r * math.cos(math.radians(a)), BAR_MID + r * math.sin(math.radians(a))) for a in [270 - 180 * i / steps for i in range(steps + 1)]]
    else:
        pts += [(-reach, BAR_MID - r), (-reach, BAR_MID + r)]
    return pts

def between(poly, lo, hi):
    return [(x + lo, y) for x, y in clip(poly, lo, hi)] if hi > lo else []

for bar in data.get("bars", []):
    key, place, level = f"u{bar['codepoint']:X}", bar["place"], bar["level"]
    end = WIDE * level // 8
    # The used part is solid, so it reaches into its neighbours where it goes on, and no hairline
    # shows where two characters meet. The faint track is only where the bar is not used, and
    # reaches nowhere: drawn over the used part, or twice over itself, it would show darker.
    track = between(bar_track(place, BAR_R), end, WIDE)
    used = between(bar_track(place, BAR_R, SEAM), -SEAM if place else 0, end + (SEAM if level == 8 and place != 2 else 0)) if level else []
    line = between(bar_track(place, BAR_LINE), end, WIDE)
    order.append(key); glyphs[key] = frame_glyph([p for p in (used, line) if len(p) > 2]); cmap[bar["codepoint"]] = key
    layers = []
    if len(track) > 2:
        if ("bar-track", place, level) not in shapes:
            shapes[("bar-track", place, level)] = f"s{len(shapes)}"
            order.append(shapes[("bar-track", place, level)]); glyphs[shapes[("bar-track", place, level)]] = polygons_glyph([track])
        layers.append((shapes[("bar-track", place, level)], pal(bar["track"], bar["opacity"])))
    if len(used) > 2:
        if ("bar-used", place, level) not in shapes:
            shapes[("bar-used", place, level)] = f"s{len(shapes)}"
            order.append(shapes[("bar-used", place, level)]); glyphs[shapes[("bar-used", place, level)]] = polygons_glyph([used])
        layers.append((shapes[("bar-used", place, level)], 0xFFFF))
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
                   "copyright": "The crew's faces: AgentValley. The letters of the name tags and plan badges: IBM Plex Mono, Copyright 2017 IBM Corp. with Reserved Font Name \"Plex\".",
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
print(sys.argv[2], len(data["faces"]), "faces", len(data.get("marks", [])), "marks", len(data.get("tags", [])), "tag parts", len(data.get("badges", [])), "badge parts", len(data.get("bars", [])), "bar parts", len(order), "glyphs", len(palette), "colours")
