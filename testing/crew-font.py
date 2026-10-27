# Builds AgentValleyCrew.ttf from the faces JSON that CrewFont.facesJSON() writes. Everything
# drawn comes from that file: this script holds no people, poses or colours of its own.
# Each face is ONE wide character from the unassigned end of Plane 3: every terminal and Claude Code
# give it two cells (East Asian Wide), Chrome-based terminals look it up in any installed font
# (they never do for private use), and Ghostty fits a colour glyph to its cells in one piece.
# Usage: crew-font.py faces.json out.ttf
import hashlib, json, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
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
svg = newTable("SVG "); svg.docList = sorted(docs, key=lambda d: d.startGlyphID)
fb.font["SVG "] = svg

fb.save(sys.argv[2])
print(sys.argv[2], len(data["faces"]), "faces", len(data.get("marks", [])), "marks", len(order), "glyphs", len(palette), "colours")
