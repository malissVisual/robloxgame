#!/usr/bin/env python3
"""Build original outlined SVG signs, transparent PNGs and an HTML review gallery.

Requires fonttools and CairoSVG. No Roblox assets or game modules are modified.
"""
from pathlib import Path
import argparse
import html
import json
import random
import re
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from symbols import draw

ROOT = Path(__file__).resolve().parent


class Lettering:
    def __init__(self, path):
        self.font = TTFont(path)
        self.glyphs = self.font.getGlyphSet()
        self.cmap = self.font.getBestCmap()
        self.units = self.font['head'].unitsPerEm
        self.paths = {}

    def width(self, text, size, tracking):
        return sum(self.glyphs[self.cmap[ord(c)]].width for c in text) / self.units * size + max(0, len(text)-1)*tracking

    def text(self, text, x, y, size, color, width, *, center=False, tracking=0, playful=False):
        size = min(size, size*width/max(1, self.width(text, size, tracking)))
        actual_width = self.width(text, size, tracking)
        if actual_width > width:
            size *= width/actual_width
        actual_width = self.width(text, size, tracking)
        if center:
            x -= actual_width/2
        paths = []
        rnd = random.Random(text)
        scale = size/self.units
        for c in text:
            glyph = self.cmap[ord(c)]
            if glyph not in self.paths:
                pen = SVGPathPen(self.glyphs)
                self.glyphs[glyph].draw(pen)
                self.paths[glyph] = pen.getCommands()
            rotate = rnd.uniform(-1.6,1.6) if playful and c != ' ' else 0
            offset = rnd.uniform(-.7,.7) if playful else 0
            d = self.paths[glyph]
            if d:
                paths.append(f'<path d="{d}" transform="translate({x:.3f} {y+offset:.3f}) rotate({rotate:.3f}) scale({scale:.6f} {-scale:.6f})"/>')
            x += self.glyphs[glyph].width * scale + tracking
        label = html.escape(text, quote=True)
        return f'<g aria-label="{label}" fill="{color}">' + ''.join(paths) + '</g>'


def wide_shape(shape):
    # All silhouettes leave a protected type area. No distressed cuts cross the names.
    shapes = {
        'ticket': 'M48 22H974L1002 47V209L975 234H48L22 210V154Q43 142 22 131V104Q43 91 22 78V47Z',
        'arrow': 'M46 33H909V15L1000 128 909 241V218H46L22 195V62Z',
        'shield': 'M55 43 163 18l73 18H826l64-18 110 36-10 152-104 28-68-16H242l-61 16-153-42 7-92Z',
        'gear': 'M44 22H970l-7 19 24 8-10 22 24 10-10 25 12 12v24l-15 9 9 25-26 9 9 27-25 21H57l-26-23 10-22-24-9 10-26-12-12v-23l18-11-10-22 25-12-12-22 24-10Z',
        'tag': 'M113 23 970 28l29 23-8 157-38 25H110L22 130Z',
        'bridge': 'M25 59 59 30h255l36-14h329l38 14h246l35 29v140l-35 34H62l-37-31Z',
        'pencil': 'M21 128 95 23h862l42 35v141l-42 35H95Z',
        'scallop': 'M47 30Q81 7 114 30H910q33-23 66 0l26 33q-24 28 0 53v32q-24 27 0 52l-29 29q-31 23-64 0H114q-34 23-67 0l-25-28q22-27 0-54v-30q22-26 0-54Z',
        'crate': 'M44 26H980l21 22v51l-9 8v78l9 8v19l-28 22H47l-24-24V49Z',
        'barn': 'M24 64 104 23h826l69 39v153l-28 19H49l-25-25Z',
        'western': 'M66 51 155 20h714l89 31q-7 39 44 41v71q-48 2-44 44l-89 29H155l-89-29q4-44-44-44V92q51-2 44-41Z',
        'medical': 'M62 23H960q40 0 40 37v135q0 38-40 38H62q-40 0-40-38V60q0-37 40-37Z',
        'civic': 'M26 64 128 25h768l102 39v146l-25 24H52l-26-24Z',
        'industrial': 'M50 22H974l27 27v157l-27 28H50l-27-28V49Z',
        'wave': 'M47 30Q87 11 131 25h753q58-14 93 5l24 36q-15 67 0 129l-24 32q-44 19-90 5H131q-42 14-84-5l-24-32q15-64 0-129Z',
        'mountain': 'M26 69 75 24h176l34-9 47 10h593l73 48v136l-24 25H51l-25-25Z',
        'hex': 'M69 22H955l48 106-48 106H69L22 128Z',
        'barred': 'M48 25H976l24 29v147l-24 30H48l-25-30V54Z',
        'stadium': 'M119 25h786q96 0 96 103t-96 103H119q-96 0-96-103T119 25Z',
    }
    return shapes[shape]


def square_shape(shape):
    shapes = {
        'padlock': 'M50 139h63V98q0-74 143-74t143 74v41h64l27 28v285l-38 38H59l-35-35V166Z',
        'garage': 'M26 148 91 47h331l65 101v306l-36 35H61l-35-35Z',
        'shield': 'M46 58 256 24l211 34 16 311-59 63-168 58-168-58-60-63Z',
        'route': 'M74 27h364l49 88v269l-49 102H73L25 385V115Z',
        'ticket': 'M61 25h390l37 37v166q-31 21 0 42v180l-37 37H61l-36-37V270q30-21 0-42V62Z',
        'civic': 'M30 107 98 35h317l68 72v343l-33 36H63l-33-36Z',
        'scallop': 'M70 35q35-20 60 0h252q33-20 60 0l43 52v339l-44 58q-31-15-59 0H129q-30-15-59 0l-42-58V87Z',
        'mailbox': 'M31 148q0-121 225-121t225 121v302l-33 36H65l-34-36Z',
        'barn': 'M26 139 256 27l230 112v311l-34 37H61l-35-37Z',
    }
    return shapes[shape]


def bolts(coords, p):
    return ''.join(f'<g transform="translate({x} {y})"><circle r="8" fill="{p["tape"]}" stroke="{p["ink"]}" stroke-width="3"/><path d="M-3 3 3-3" stroke="{p["ink"]}" stroke-width="2"/></g>' for x,y in coords)


def wear(sign, p, size):
    rnd = random.Random(sign['id'])
    width, height = size
    pieces = []
    # A few painted chips, clipped into the board. Main lettering stays untouched.
    for i in range(7):
        x = rnd.randrange(100,width-100)
        y = 25 if i % 2 == 0 else height-27
        n = rnd.randrange(9,22)
        pieces.append(f'<path d="M{x} {y}l{n} 1-4 5-9-2-5 6-5-2Z" fill="{p["rust"]}" opacity=".8"/>')
    x = width - 190
    pieces.append(f'<g transform="translate({x} 22) rotate(-8)"><path d="M0 0 11 3 23 0 33 3 48 0v24l-14-3-12 3-11-2L0 25Z" fill="{p["tape"]}" stroke="{p["ink"]}" stroke-width="1.5"/><path d="m9 3-4 19m37-20-4 18" stroke="{p["paper"]}" stroke-width="2" opacity=".6"/></g>')
    return ''.join(pieces)


def svg_for(sign, p, heading, small):
    square = sign.get('square',False)
    width, height = (512,512) if square else (1024,256)
    d = square_shape(sign['shape']) if square else wide_shape(sign['shape'])
    fill = p[sign['color']]
    ink = p['paper'] if sign.get('light') else p['ink']
    metadata = html.escape(json.dumps({'building_id':sign['id'],'name':sign['name'],'lines':sign['lines'],'slogan':sign['slogan']}))
    pieces = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title description">',f'<title id="title">{html.escape(sign["name"])}</title>',f'<desc id="description">Original {sign["shape"]} building sign. {html.escape(sign["slogan"])} Text is outlined for portable rendering.</desc>',f'<metadata>{metadata}</metadata>',f'<defs><clipPath id="board"><path d="{d}"/></clipPath></defs>',f'<path d="{d}" fill="{fill}" stroke="{p["ink"]}" stroke-width="9" stroke-linejoin="round"/>','<g clip-path="url(#board)">',wear(sign,p,(width,height))]
    if square:
        pieces.append(bolts([(62,174),(450,174),(67,452),(445,452)],p))
        if sign.get('number'):
            pieces.append(f'<circle cx="256" cy="186" r="100" fill="{p[sign["accent"]]}" stroke="{p["ink"]}" stroke-width="5"/>')
            pieces.append(heading.text(sign['number'],256,228,134,p['ink'],164,center=True))
            pieces.append(f'<g transform="translate(406 251) rotate(17) scale(.29)">{draw(sign["symbol"],p)}</g>')
        else:
            pieces.append(f'<path d="M155 90q102-23 203 0l-8 177q-94 25-191 0Z" fill="{p[sign["accent"]]}" opacity=".65"/>')
            pieces.append(f'<g transform="translate(176 98)">{draw(sign["symbol"],p)}</g>')
        for text,y in zip(sign['lines'],[347,404]):
            pieces.append(heading.text(text,256,y,57,ink,370,center=True,tracking=.5,playful=True))
        pieces.append(f'<path d="M142 425h228" stroke="{ink}" stroke-width="3"/>')
        pieces.append(small.text(sign['slogan'],256,452,12,ink,345,center=True,tracking=1))
    else:
        right = sign['id'] in ('depot','dealer','supplies','ranch','icecream','lodge','lighthouse','radio')
        text_left = 86 if right else 241
        text_width = 682 if right else 684
        icon_x = (792 if sign['shape']=='arrow' else 815) if right else 48
        icon_scale = .95 if right and sign['shape']=='arrow' else 1.05
        if sign['shape'] in ('ticket','tag') and right:
            text_left, text_width = 157,613
            if sign['shape']=='ticket':
                pieces.append(f'<path d="M125 36v184" stroke="{p["ink"]}" stroke-width="3" stroke-dasharray="8 7" opacity=".55"/>')
                for n in range(14):
                    pieces.append(f'<rect x="63" y="{61+n*9}" width="38" height="{3 if n%3 else 5}" fill="{p["ink"]}"/>')
            else:
                pieces.append(f'<circle cx="78" cy="127" r="20" fill="{p["ink"]}"/><circle cx="78" cy="127" r="10" fill="{p["tape"]}"/>')
        pieces.append(bolts([(52,54),(972,202)],p))
        if not right:
            pieces.append(f'<path d="M226 55v138" stroke="{ink}" stroke-width="2" opacity=".32" stroke-dasharray="4 6"/>')
        symbol_palette = {**p, 'ink':p['paper']} if sign.get('light') and sign['symbol']=='anchor' else p
        pieces.append(f'<g transform="translate({icon_x} 42) scale({icon_scale})">{draw(sign["symbol"],symbol_palette)}</g>')
        if len(sign['lines'])==1:
            pieces.append(heading.text(sign['lines'][0],text_left,147,92,ink,text_width,playful=True))
        else:
            sizes=[80,80]
            if sign['lines'][-1] in ('9','13'): sizes=[66,84]
            for line,y,sz in zip(sign['lines'],[104,180],sizes):
                pieces.append(heading.text(line,text_left,y,sz,ink,text_width,playful=True))
        pieces.append(small.text(sign['slogan'],text_left,208,16,ink,text_width,tracking=.8))
        if sign['shape']=='industrial':
            for x in [36,976]: pieces.append(f'<path d="M{x} 69v111" stroke="{p["ink"]}" stroke-width="9" stroke-dasharray="10 10"/>')
        if sign['shape']=='crate': pieces.append(f'<path d="M40 42h{width-82}M42 217h{width-84}" stroke="{p["ink"]}" stroke-width="2" opacity=".25"/>')
        if sign['shape']=='barred': pieces.append(f'<path d="M25 38h{width-48}M25 219h{width-48}" stroke="{ink}" stroke-width="3" opacity=".4"/>')
    pieces.extend(['</g>','</svg>'])
    return '\n'.join(pieces)+'\n'


def gallery(signs):
    groups = list(dict.fromkeys(s['group'] for s in signs))
    sections = []
    for group in groups:
        cards = []
        for s in signs:
            if s['group'] != group: continue
            name, id_ = html.escape(s['name']),s['id']
            dims = '512 × 512' if s.get('square') else '1024 × 256'
            cards.append(f'<article class="{"square" if s.get("square") else "wide"}"><a href="sign_{id_}.png"><img src="sign_{id_}.png" alt="{name}"></a><footer><b>{name}</b><span>{dims} · <a href="sign_{id_}.svg">SVG</a> · <a href="sign_{id_}.png">PNG</a></span></footer></article>')
        sections.append(f'<section><h2>{html.escape(group)}</h2><div class="grid">'+''.join(cards)+'</div></section>')
    return '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Zombie Delivery: building signs</title><style>
*{box-sizing:border-box}body{margin:0;background:#f6f0e6;color:#493750;font:16px system-ui,sans-serif}main{max-width:1440px;margin:auto;padding:36px}h1{font-size:42px;letter-spacing:-1.5px;margin:10px 0}p{max-width:850px;line-height:1.6}h2{font-size:22px;margin:45px 0 20px;border-bottom:2px dashed #cdbed6;padding-bottom:12px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:22px}article{border:1px solid #d6c7d7;background:repeating-conic-gradient(#e9e0e7 0% 25%,#f5edf2 0% 50%) 50% / 24px 24px;padding:20px;border-radius:8px;overflow:hidden}img{width:100%;height:auto;display:block}article.square img{height:290px;width:auto;max-width:100%;margin:auto;object-fit:contain}footer{background:#faf4e4;padding:14px;margin:16px -20px -20px;display:flex;justify-content:space-between;gap:12px;align-items:center;font-size:12px}a{color:inherit}a:focus-visible{outline:3px solid #846699;outline-offset:4px}.dark article{background:repeating-conic-gradient(#26232b 0% 25%,#312d37 0% 50%) 50% / 24px 24px}button{font:inherit;border:2px solid #493750;background:#e5edce;color:#493750;padding:10px 16px;cursor:pointer;border-radius:4px}small{color:#74617d}@media(max-width:800px){main{padding:20px}.grid{grid-template-columns:1fr}h1{font-size:30px}footer{flex-wrap:wrap}}
</style><main><small>ZOMBIE DELIVERY / POSTAGE & TROUBLE</small><h1>Signs of life.</h1><p>54 original signboards for the courier city. Transparent PNGs, outlined SVG sources and full names. Click a sign to view the upload image. Decorative boards do not replace JOBS / WORK HERE / GARAGE prompts or dynamic FOR SALE information.</p><button onclick="document.body.classList.toggle('dark')">Switch transparency background</button>'''+''.join(sections)+'</main></html>\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--font-dir',type=Path,default=Path('/usr/share/fonts/truetype/dejavu'))
    args = parser.parse_args()
    import cairosvg
    catalog = json.loads((ROOT/'catalog.json').read_text())
    signs, p = catalog['signs'],catalog['palette']
    ids = [s['id'] for s in signs]
    assert len(ids)==len(set(ids))==54, 'Brief requires 54 unique building entries'
    heading = Lettering(args.font_dir/'DejaVuSansCondensed-Bold.ttf')
    small = Lettering(args.font_dir/'DejaVuSansMono-Bold.ttf')
    assets = []
    for sign in signs:
        assert re.fullmatch(r'[a-z][a-z0-9_]*',sign['id'])
        name = 'sign_'+sign['id']
        svg = svg_for(sign,p,heading,small)
        (ROOT/(name+'.svg')).write_text(svg)
        cairosvg.svg2png(bytestring=svg.encode(),write_to=str(ROOT/(name+'.png')))
        size = [512,512] if sign.get('square') else [1024,256]
        assets.append({'name':name,'file':name+'.png','source':name+'.svg','size':size,'intended_use':f'{sign["group"]}: {sign["name"]} building name board','building_id':sign['id'],'aliases':sign.get('aliases',[]),'label':sign['name']})
    (ROOT/'assets.json').write_text(json.dumps({'assets':assets},indent=2)+'\n')
    (ROOT/'index.html').write_text(gallery(signs))
    print(f'Built {len(assets)} PNG/SVG pairs and review gallery in {ROOT}')


if __name__ == '__main__':
    main()
