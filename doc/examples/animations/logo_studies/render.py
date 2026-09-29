#!/usr/bin/env python3
"""SVG consumer for Core's logo scenes and already-sampled frame updates.

No animation easing or particle simulation lives here. FontTools outlines the
retained PlotLabels from system fonts so the finished SVGs have no font dependency.
"""
from pathlib import Path
import argparse
import copy
import html
import json
import math
import re
import subprocess
import sys
from functools import lru_cache
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', nargs='?', default='build/logo-studies-2026-09-05')
parser.add_argument('--inline-output', type=Path)
args = parser.parse_args()
OUT = Path(args.output).resolve()
OUT.mkdir(parents=True, exist_ok=True)

def n(x):
    return f'{float(x):.3f}'.rstrip('0').rstrip('.') or '0'

def esc(x):
    return html.escape(str(x), quote=True)

@lru_cache(None)
def font(family, face):
    paths = {
        'Avenir Next': ('/System/Library/Fonts/Avenir Next.ttc', {'Medium': 5, 'Demi Bold': 2, 'Regular': 7}),
        'Futura': ('/System/Library/Fonts/Supplemental/Futura.ttc', {'Medium': 0}),
        'Bodoni 72': ('/System/Library/Fonts/Supplemental/Bodoni 72.ttc', {'Book': 0, 'Book Italic': 1}),
        'DIN Condensed': ('/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf', {'Bold': 0}),
    }
    path, faces = paths[family]
    return TTFont(path, fontNumber=faces[face])

def outline_label(node):
    sty, geo, meta = node['style'], node['geometry'], node['metadata']
    f = font(sty['font_family'], meta.get('face', 'Regular'))
    gs, cmap = f.getGlyphSet(), f.getBestCmap()
    scale = sty['font_size'] / f['head'].unitsPerEm
    glyphs = []
    advance = 0
    for char in geo['text']:
        name = cmap[ord(char)]
        pen = SVGPathPen(gs)
        gs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, 0, 0)))
        path = re.sub(r'-?\d+\.\d+', lambda m: n(float(m[0])), pen.getCommands())
        glyphs.append({'d': path, 'advance': advance})
        advance += f['hmtx'][name][0] * scale
    node['outline'] = {'glyphs': glyphs, 'width': advance}

raw = json.loads((OUT / 'timelines.json').read_text())
assert raw['schema'] == 'tungsten.logo-studies/v1'
DESIGNS = []
for entry in raw['studies']:
    timeline = entry['timeline']
    scene = copy.deepcopy(timeline['scene'])
    for node in scene['nodes']:
        if node['kind'] == 'label':
            outline_label(node)
    # Compact representation. All numbers are sampled by Core before rounding.
    ids = [(t['target'], t['property']) for t in timeline['tracks']]
    frames = [[u['value'] for u in f['updates']] for f in entry['samples']]
    d = {'scene': scene, 'channels': ids, 'frames': frames, 'fps': timeline['fps'], 'duration': timeline['duration']}
    assert frames[0] == frames[-1]
    assert len(frames) == 97
    DESIGNS.append(d)

def material_defs(prefix, mono=False, ink='#111111'):
    return f'''<defs>
<linearGradient id="{prefix}-chrome" gradientUnits="userSpaceOnUse" x1="235" y1="72" x2="369" y2="258">
<stop offset="0" stop-color="#444d54"/><stop offset=".14" stop-color="#dfe7ed"/><stop offset=".24" stop-color="#fbfcfc"/><stop offset=".36" stop-color="#7d8993"/><stop offset=".46" stop-color="#252d34"/><stop offset=".49" stop-color="#b8c2cb"/><stop offset=".515" stop-color="#ffffff"/><stop offset=".555" stop-color="#8e9aa3"/><stop offset=".67" stop-color="#424c55"/><stop offset=".81" stop-color="#e5eaf0"/><stop offset=".93" stop-color="#69727b"/><stop offset="1" stop-color="#202931"/>
</linearGradient>
<linearGradient id="{prefix}-edge" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="#fff" stop-opacity=".9"/><stop offset=".4" stop-color="#e9f2f8" stop-opacity=".1"/><stop offset="1" stop-color="#273039" stop-opacity=".6"/></linearGradient>
<linearGradient id="{prefix}-copper" gradientUnits="userSpaceOnUse" x1="235" y1="85" x2="330" y2="255"><stop stop-color="#ffd196"/><stop offset=".27" stop-color="#f89b56"/><stop offset=".52" stop-color="#c86536"/><stop offset="1" stop-color="#662b22"/></linearGradient>
<filter id="{prefix}-metal" x="-.3" y="-.3" width="1.6" height="1.7"><feDropShadow dx="0" dy="7" stdDeviation="7" flood-color="#06090b" flood-opacity=".25"/></filter>
<filter id="{prefix}-heat" x="-.6" y="-.6" width="2.2" height="2.2"><feDropShadow dx="0" dy="0" stdDeviation="2" flood-color="#ffad63" flood-opacity="1"/><feDropShadow dx="0" dy="0" stdDeviation="7" flood-color="#ff6a25" flood-opacity=".85"/><feDropShadow dx="0" dy="0" stdDeviation="17" flood-color="#e84614" flood-opacity=".4"/></filter>
<filter id="{prefix}-heat-fine" filterUnits="userSpaceOnUse" x="175" y="75" width="290" height="220"><feDropShadow dx="0" dy="0" stdDeviation="1.2" flood-color="#ffd3a1" flood-opacity=".9"/><feDropShadow dx="0" dy="0" stdDeviation="4" flood-color="#ff9f4e" flood-opacity=".7"/><feDropShadow dx="0" dy="0" stdDeviation="10" flood-color="#ff721f" flood-opacity=".24"/></filter>
<filter id="{prefix}-heat-brand" filterUnits="userSpaceOnUse" x="175" y="75" width="290" height="220"><feDropShadow dx="0" dy="0" stdDeviation="1.1" flood-color="#ffce91" flood-opacity=".7"/><feDropShadow dx="0" dy="0" stdDeviation="3.4" flood-color="#ffa24b" flood-opacity=".38"/><feDropShadow dx="0" dy="0" stdDeviation="7" flood-color="#ed7c24" flood-opacity=".10"/></filter>
</defs>'''

def state_at(design, frame):
    return {tuple(channel): value for channel, value in zip(design['channels'], design['frames'][frame])}

def label_markup(node, state):
    geo, meta, out = node['geometry'], node['metadata'], node['outline']
    tracking = state.get((node['id'], 'tracking'), meta.get('tracking', 0))
    count = len(out['glyphs'])
    start = geo['position'][0] - (out['width'] + tracking * (count - 1)) / 2
    y = geo['position'][1]
    return ''.join(f'<path data-glyph="{i}" d="{g["d"]}" transform="translate({n(start+g["advance"]+tracking*i)} {n(y)})"/>' for i, g in enumerate(out['glyphs']))

def node_markup(node, state, prefix, mono=False, ink='#111111'):
    id, kind, sty, geo, meta = [node[k] for k in ('id','kind','style','geometry','metadata')]
    if mono and meta.get('role') == 'atmosphere':
        return ''
    fill = sty['fill'] or 'none'
    stroke = sty['stroke'] or 'none'
    width = state.get((id, 'stroke_width'), sty['stroke_width'])
    material = meta.get('material')
    filter_attr = ''
    if mono:
        if fill != 'none': fill = ink
        if stroke != 'none': stroke = ink
    elif material == 'chrome':
        fill = f'url(#{prefix}-chrome)'
        stroke = f'url(#{prefix}-edge)'
        width = 1.2
        filter_attr = f' filter="url(#{prefix}-metal)"'
    elif material == 'copper':
        fill = f'url(#{prefix}-copper)'
        stroke = '#f4b277'
        width = .4
    elif material == 'heat':
        stroke = meta.get('heat_color', '#ffd4a4')
        shader = 'heat-fine' if 'heat_color' in meta else 'heat'
        if meta.get('glow') == 'restrained': shader = 'heat-brand'
        filter_attr = f' filter="url(#{prefix}-{shader})"'
    opacity = state.get((id, 'opacity'), sty['opacity'])
    if material == 'heat' and not mono:
        floor = meta.get('heat_floor', .6)
        opacity *= floor + (1-floor) * state.get((id, 'heat'), 1)
    trans = state.get((id, 'translate'), [0, 0])
    attrs = f'fill="{fill}" stroke="{stroke}" stroke-width="{n(width)}" stroke-linejoin="{meta.get("linejoin", "round")}" stroke-linecap="round"'
    content = ''
    if kind in ('polyline','polygon'):
        points = state.get((id,'points'), geo['points'])
        path = 'M' + ' L'.join(n(x)+' '+n(y) for x,y in points) + (' Z' if kind == 'polygon' else '')
        content = f'<path data-geometry="true" d="{path}"/>'
        if material == 'heat' and not mono and meta.get('heat_core', True):
            content += f'<path data-core="true" d="{path}" stroke="{meta.get("core_color", "#ffedd6")}" stroke-width="{n(width*meta.get("core_fraction", .27))}"/>'
    elif kind == 'points':
        content = ''.join(f'<circle cx="{n(x)}" cy="{n(y)}" r="{n(geo["radius"])}"/>' for x,y in geo['points'])
    elif kind == 'label':
        content = label_markup(node, state)
    else:
        raise ValueError(kind)
    return f'<g data-node="{id}" {attrs} opacity="{n(opacity)}" transform="translate({n(trans[0])} {n(trans[1])})"{filter_attr}>{content}</g>'

def svg_markup(design, index, frame=48, mono=False, transparent=False):
    scene = design['scene']
    meta = scene['metadata']
    prefix = f'logo-{index}' + ('-mono' if mono else '')
    ink = meta['ink']
    state = state_at(design,frame)
    bg = scene['viewport']['background']
    nodes = ''.join(node_markup(node,state,prefix,mono,ink) for node in scene['nodes'])
    defs = material_defs(prefix)
    # Poster respects the same gradient offset as the sampled frame.
    for (target,prop),value in state.items():
        if prop == 'sheen':
            node = next(nd for nd in scene['nodes'] if nd['id'] == target)
            material = 'copper' if node['metadata'].get('material') == 'copper' else 'chrome'
            defs = defs.replace(f'id="{prefix}-{material}"', f'id="{prefix}-{material}" gradientTransform="translate(0 {n(value*.35)})"')
    background = '' if transparent else f'<rect data-background="true" width="640" height="420" fill="{bg}"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" data-design="{index}" viewBox="0 0 640 420" role="img" aria-label="{esc(meta["name"])}: {esc(meta["description"])}"><title>{esc(meta["name"])} — Tungsten</title>{defs}{background}{nodes}</svg>'

# Exact sampled-frame SVG animation using discrete keyframe values.
def animated_svg(design,index):
    from xml.etree import ElementTree as ET
    ns='http://www.w3.org/2000/svg'
    ET.register_namespace('',ns)
    root=ET.fromstring(svg_markup(design,index,0))
    by_id={el.attrib.get('data-node'):el for el in root.iter() if el.attrib.get('data-node')}
    def animate(el,tag,attribute,values,extra=None):
        a={'attributeName':attribute,'dur':'4s','repeatCount':'indefinite','calcMode':'discrete',
           'values':';'.join(values),'keyTimes':';'.join(n(i/96) for i in range(97))}
        if extra: a.update(extra)
        ET.SubElement(el,f'{{{ns}}}{tag}',a)
    for ci,(id,prop) in enumerate(design['channels']):
        el=by_id[id]
        values=[frame[ci] for frame in design['frames']]
        if prop=='points':
            closed=el.find(f'{{{ns}}}path').attrib['d'].endswith('Z')
            ds=['M'+' L'.join(n(x)+' '+n(y) for x,y in points)+(' Z' if closed else '') for points in values]
            animate(el.find(f'{{{ns}}}path'),'animate','d',ds)
        elif prop=='translate':
            animate(el,'animateTransform','transform',[' '.join(map(n,v)) for v in values],{'type':'translate'})
        elif prop=='opacity':
            animate(el,'animate','opacity',list(map(n,values)))
        elif prop=='stroke_width':
            animate(el,'animate','stroke-width',list(map(n,values)))
        elif prop=='heat':
            node=next(nd for nd in design['scene']['nodes'] if nd['id']==id)
            floor=node['metadata'].get('heat_floor',.6)
            animate(el,'animate','opacity',[n(floor+(1-floor)*v) for v in values])
        elif prop=='sheen':
            material=next(nd for nd in design['scene']['nodes'] if nd['id']==id)['metadata'].get('material')
            gradient=next(g for g in root.iter() if g.attrib.get('id')==f'logo-{index}-'+('copper' if material=='copper' else 'chrome'))
            animate(gradient,'animateTransform','gradientTransform',['0 '+n(v*.35) for v in values],{'type':'translate'})
        elif prop=='tracking':
            node=next(nd for nd in design['scene']['nodes'] if nd['id']==id)
            glyphs=node['outline']['glyphs']; width=node['outline']['width']; x,y=node['geometry']['position']
            for i,child in enumerate(el):
                positions=[f'{n(x-(width+v*(len(glyphs)-1))/2+glyphs[i]["advance"]+i*v)} {n(y)}' for v in values]
                animate(child,'animateTransform','transform',positions,{'type':'translate'})
        else: raise ValueError(prop)
    return ET.tostring(root,encoding='unicode')

for i, design in enumerate(DESIGNS):
    slug=f'{i+1:02d}-'+re.sub(r'[^a-z0-9]+', '-', design['scene']['metadata']['name'].lower()).strip('-')
    for suffix,content in [('',svg_markup(design,i)),('-transparent',svg_markup(design,i,transparent=True)),('-mono',svg_markup(design,i,mono=True)),('-animated',animated_svg(design,i))]:
        (OUT/(slug+suffix+'.svg')).write_text(content)
    subprocess.run(['rsvg-convert','-w','1280','-h','840','-o',str(OUT/(slug+'.png')),str(OUT/(slug+'.svg'))],check=True)

# A compact poster board, with path-based logo typography and light captions.
board_width = 768 if len(DESIGNS) == 1 else 1440
board_height = 220 + math.ceil(len(DESIGNS)/2) * 490
board=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{board_width}" height="{board_height}" viewBox="0 0 {board_width} {board_height}">',
       f'<rect width="{board_width}" height="{board_height}" fill="#f3f0e9"/>',
       '<text x="64" y="62" font-family="Helvetica,Arial,sans-serif" font-size="15" letter-spacing="3" fill="#77766f">TUNGSTEN / IDENTITY STUDIES</text>',
       f'<text x="64" y="118" font-family="Helvetica,Arial,sans-serif" font-size="38" fill="#282a27">{esc(raw.get("title", "Eight directions. One element."))}</text>']
for i,d in enumerate(DESIGNS):
    x=64+(i%2)*672; y=162+(i//2)*490
    svg=svg_markup(d,i)
    svg=svg.replace('<svg ',f'<svg x="{x}" y="{y}" width="640" height="420" ',1)
    board.append(svg)
    m=d['scene']['metadata']
    board.append(f'<text x="{x}" y="{y+452}" font-family="Helvetica,Arial,sans-serif" font-size="18" fill="#30342f">{i+1:02d} / {esc(m["name"])}</text>')
    board.append(f'<text x="{x+640}" y="{y+452}" text-anchor="end" font-family="Helvetica,Arial,sans-serif" font-size="14" fill="#71786f">{esc(m["bucket"])}</text>')
board.append(f'<text x="64" y="{board_height-28}" font-family="Helvetica,Arial,sans-serif" font-size="13" letter-spacing="1" fill="#6d756e">ORIGINAL STUDIES · CORE/ANIMATION · SEPTEMBER 2026</text></svg>')
(OUT/'contact-sheet.svg').write_text('\n'.join(board))
subprocess.run(['rsvg-convert','-o',str(OUT/'contact-sheet.png'),str(OUT/'contact-sheet.svg')],check=True)

def rounded(v):
    if isinstance(v,float): return round(v,3)
    if isinstance(v,list): return [rounded(x) for x in v]
    if isinstance(v,dict): return {k:rounded(x) for k,x in v.items()}
    return v
payload=json.dumps(rounded(DESIGNS),separators=(',',':'))
(OUT/'designs.json').write_text(payload)
# Literal template is authored separately and placeholders receive parsed data.
template=(HERE/'gallery.html').read_text()
sections=[]
for i,d in enumerate(DESIGNS):
    m=d['scene']['metadata']
    sections.append(f'<figure><div class="logo-stage" data-stage="{i}">{svg_markup(d,i)}</div><figcaption><span>{i+1:02d} / {esc(m["name"])}</span><span class="text-small">{esc(m["bucket"])}</span></figcaption></figure>')
fragment=template.replace('<!-- LOGO_STUDIES -->','\n'.join(sections)).replace('/* LOGO_DATA */',payload)
if len(DESIGNS) == 1:
    fragment = fragment.replace('grid-template-columns:repeat(2,minmax(0,1fr))', 'grid-template-columns:1fr')
    fragment = fragment.replace('Play motion', 'Energize')
    fragment = fragment.replace('const frame=(48+Math.floor(elapsed*24))%96;', 'const frame=Math.min(96,Math.floor(elapsed*24));')
fragment = fragment.replace('tungsten-logo-studies', raw.get('slug', 'tungsten-logo-studies'))
(OUT/(raw.get('slug', 'tungsten-logos')+'.html')).write_text(fragment)
inline_bytes = len(fragment.encode())
assert inline_bytes < 1_000_000, inline_bytes
if args.inline_output:
    args.inline_output.write_text(fragment)
print(json.dumps({'designs':len(DESIGNS),'frames_per_design':97,'svg_exports':4*len(DESIGNS),'inline_bytes':inline_bytes,'output':str(OUT)},indent=2))
