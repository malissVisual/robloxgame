#!/usr/bin/env python3
"""Make a labeled sheet of independently rendered geometry samples."""
from pathlib import Path
import argparse
from PIL import Image,ImageDraw,ImageFont
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("renders",type=Path);parser.add_argument("output",type=Path)
args=parser.parse_args();files=sorted(args.renders.glob("*.png"))
width,height=420,328
sheet=Image.new("RGB",(width*3,height*((len(files)+2)//3)),(24,27,32))
draw=ImageDraw.Draw(sheet);font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",17)
for i,p in enumerate(files):
    x,y=(i%3)*width,(i//3)*height
    picture=Image.open(p).convert("RGB");picture.thumbnail((width-12,height-34))
    sheet.paste(picture,(x+(width-picture.width)//2,y))
    draw.text((x+14,y+height-29),p.stem,fill=(232,234,226),font=font)
args.output.parent.mkdir(parents=True,exist_ok=True);sheet.save(args.output)
print("Sheet:",len(files),"geometry renders")
