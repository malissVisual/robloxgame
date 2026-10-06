#!/usr/bin/env python3
"""Arrange exact model renders on a restrained review sheet with measured visual part counts."""
from pathlib import Path
import argparse,json
from PIL import Image,ImageDraw,ImageFont
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def sheet(data,renders,target,title):
    columns=2 if len(data)<=8 else 3
    width=1600;margin=40;gap=24;cell=(width-margin*2-gap*(columns-1))//columns;image_h=round(cell*680/960)
    rows=(len(data)+columns-1)//columns
    canvas=Image.new('RGB',(width,150+rows*(image_h+70)+64),'#171d20');draw=ImageDraw.Draw(canvas)
    draw.rectangle((40,34,45,78),fill='#99312b');draw.text((62,30),title,font=ImageFont.truetype(FONT,34),fill='#ecece4')
    draw.text((62,84),'Native Roblox parts / actual geometry / Blender studio-light render',font=ImageFont.truetype(FONT,17),fill='#a6b0b5')
    for i,m in enumerate(data):
        x=margin+(i%columns)*(cell+gap);y=136+(i//columns)*(image_h+70)
        img=Image.open(renders/(m['id']+'.png')).convert('RGB').resize((cell,image_h),Image.Resampling.LANCZOS);canvas.paste(img,(x,y))
        count=len([p for p in m['parts'] if 'size' in p]);draw.text((x,y+image_h+12),m['id'].replace('_',' ').upper(),font=ImageFont.truetype(FONT,22),fill='#ecece4')
        draw.text((x,y+image_h+42),f'{count} decorative parts',font=ImageFont.truetype(FONT,16),fill='#a6b0b5')
    draw.text((40,canvas.height-38),'Art-only handoff / gameplay and in-engine verification belong to integration',font=ImageFont.truetype(FONT,16),fill='#8b989e')
    target.parent.mkdir(parents=True,exist_ok=True);canvas.save(target)
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('data',type=Path);ap.add_argument('renders',type=Path);ap.add_argument('output',type=Path);ap.add_argument('title');a=ap.parse_args();sheet(json.loads(a.data.read_text()),a.renders,a.output,a.title)
