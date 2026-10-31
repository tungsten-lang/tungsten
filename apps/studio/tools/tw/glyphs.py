#!/usr/bin/env python3
"""Font-file-selected SVG outlines. No CoreText/Pango fallback or missing-glyph boxes.

Single-glyph glyph_path(ch, font=None) is compatible with the film helpers.
text_svg uses HarfBuzz positioning, including Avestan/Hebrew RTL and combining
marks, and fontTools outlines. Install requirements.txt in the toolkit venv.
"""
import argparse
import functools
import html
import pathlib

FONTS = {
    'cuneiform': '/System/Library/Fonts/Supplemental/NotoSansCuneiform-Regular.ttf',
    'hieroglyphs': '/System/Library/Fonts/Supplemental/NotoSansEgyptianHieroglyphs-Regular.ttf',
}


def font_for(ch):
    cp = ord(ch)
    kind = 'cuneiform' if 0x12000 <= cp <= 0x1254f else 'hieroglyphs' if 0x13000 <= cp <= 0x1345f else None
    if not kind:
        raise ValueError(f'U+{cp:04X}: supply an explicit font file (Avestan/Old Persian included)')
    return FONTS[kind]


@functools.lru_cache(maxsize=16)
def load_font(path):
    from fontTools.ttLib import TTFont
    f = TTFont(path)
    return f, f.getBestCmap(), f.getGlyphSet(), f['head'].unitsPerEm


def glyph_path(ch, font=None):
    if len(ch) != 1:
        raise ValueError('glyph_path expects one Unicode code point; use text_svg for shaped text')
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    path = str(pathlib.Path(font or font_for(ch)).expanduser().resolve())
    f,cmap,gs,upm = load_font(path)
    name = cmap.get(ord(ch))
    if not name or name == '.notdef':
        raise ValueError(f'U+{ord(ch):04X} missing from {path}')
    pen = SVGPathPen(gs)
    gs[name].draw(TransformPen(pen,(1/upm,0,0,-1/upm,0,0)))
    return pen.getCommands(), gs[name].width/upm


def text_svg(text, font, size=64, color='#ffffff', direction=None):
    import uharfbuzz as hb
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    path = pathlib.Path(font).expanduser().resolve()
    f,cmap,gs,upm = load_font(str(path))
    face = hb.Face(path.read_bytes())
    hfont = hb.Font(face)
    hfont.scale = (upm,upm)
    hb.ot_font_set_funcs(hfont)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    if direction: buf.direction = direction
    hb.shape(hfont,buf)
    if any(info.codepoint == 0 for info in buf.glyph_infos):
        raise ValueError(f'{path.name}: text contains missing glyphs')
    x=y=0
    paths=[]
    bounds=[]
    from fontTools.pens.boundsPen import BoundsPen
    for info,pos in zip(buf.glyph_infos,buf.glyph_positions):
        name = f.getGlyphOrder()[info.codepoint]
        scale = size/upm
        matrix = (scale,0,0,-scale,(x+pos.x_offset)*scale,-(y+pos.y_offset)*scale)
        pen = SVGPathPen(gs)
        gs[name].draw(TransformPen(pen,matrix))
        paths.append(f'<path d="{html.escape(pen.getCommands(),quote=True)}"/>')
        bp = BoundsPen(gs)
        gs[name].draw(TransformPen(bp,matrix))
        if bp.bounds: bounds.append(bp.bounds)
        x += pos.x_advance; y += pos.y_advance
    if not bounds: raise ValueError('text has no visible ink')
    x0=min(b[0] for b in bounds)-2; y0=min(b[1] for b in bounds)-2
    w=max(b[2] for b in bounds)-x0+2; h=max(b[3] for b in bounds)-y0+2
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x0} {y0} {w} {h}">'
            f'<g fill="{html.escape(color,quote=True)}">'+''.join(paths)+'</g></svg>')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('text'); p.add_argument('--font',required=True); p.add_argument('--out',type=pathlib.Path,required=True)
    p.add_argument('--size',type=float,default=64); p.add_argument('--color',default='#ffffff')
    p.add_argument('--direction',choices=['rtl','ltr'])
    a=p.parse_args()
    a.out.write_text(text_svg(a.text,a.font,a.size,a.color,a.direction))

if __name__ == '__main__': main()
