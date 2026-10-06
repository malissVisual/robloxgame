#!/usr/bin/env python3
"""Rasterize editable SVG UI assets at their declared dimensions; audit 256px white glyphs and transparency."""
from pathlib import Path
import argparse,xml.etree.ElementTree as ET
import cairosvg
from PIL import Image
def rasterize(path):
    root=ET.fromstring(path.read_text());width=int(root.get('width'));height=int(root.get('height'))
    target=path.with_suffix('.png');cairosvg.svg2png(url=str(path),write_to=str(target),output_width=width,output_height=height)
    image=Image.open(target).convert('RGBA');assert image.size==(width,height)
    if width==height==256:
        pixels=list(image.getdata());assert any(p[3]==255 for p in pixels) and any(p[3]==0 for p in pixels)
        assert all(p[:3]==(255,255,255) for p in pixels if p[3]>0),'icons must be white glyphs'
        assert image.getpixel((0,0))[3]==0
    print('SVG/PNG PASS:',path.name,f'{width}x{height}')
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('files',nargs='+',type=Path);args=ap.parse_args()
    for path in args.files:rasterize(path)
