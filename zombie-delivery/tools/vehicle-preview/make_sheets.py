#!/usr/bin/env python3
"""Make review sheets from renders of the actual fleet geometry, without inventing extra model detail."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFont

FONT=Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
def font(size):return ImageFont.truetype(str(FONT),size)
def sheet(renders, target, title, subtitle, entries, columns, footer):
    width=1800; margin=48; gap=24; cell=(width-2*margin-gap*(columns-1))//columns
    picture_h=round(cell*680/960); cell_h=picture_h+68; rows=(len(entries)+columns-1)//columns
    canvas=Image.new('RGB',(width,170+rows*cell_h+(rows-1)*gap+74),'#171d20');draw=ImageDraw.Draw(canvas)
    draw.rectangle((margin,42,margin+5,91),fill='#a32f28')
    draw.text((margin+22,38),title,font=font(36),fill='#ecece4')
    draw.text((margin+22,96),subtitle,font=font(18),fill='#a6b0b5')
    for i,(key,name,note) in enumerate(entries):
        x=margin+(i%columns)*(cell+gap);y=154+(i//columns)*(cell_h+gap)
        picture=Image.open(renders/(key+'.png')).convert('RGB').resize((cell,picture_h),Image.Resampling.LANCZOS)
        canvas.paste(picture,(x,y));draw.text((x,y+picture_h+12),name,font=font(21),fill='#ecece4')
        draw.text((x,y+picture_h+42),note,font=font(15),fill='#a6b0b5')
    draw.text((margin,canvas.height-42),footer,font=font(16),fill='#8b989e')
    canvas.save(target)

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('renders',type=Path);ap.add_argument('output',type=Path);args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    entries=[('van-3-base','LONG CARGO VAN','Raised roof / cargo rack'),('courier-1-base','EXPRESS COURIER','Compact delivery / roof pod'),('highroof-1-base','TALL HAULER','High cargo shell / ladder'),('pickup-1-base','RANCH PICKUP','Open bed / roll bar'),('boxtruck-2-base','FREIGHT HAULER','Box body / liftgate'),('muscle-1-base','STREET MACHINE','Low cab / blower'),('freight-0-base','FREIGHT TRUCK','Long box / roof deflector'),('armorvan-1-base','FORTRESS VAN','Modular protection / field lockers'),('rallyvan-1-base','WORKS RALLY','Lamp pod / spare / rear wing')]
    sheet(args.renders,args.output/'fleet-preview.png','ZOMBIE DELIVERY / FLEET','Nine owned vehicles. Their final body stages, before optional upgrade kits.',entries,3,'Actual game factory geometry / Roblox Parts, WedgeParts and Cylinders / Blender render')
    stages=[('van-0-base','01 / RUSTY VAN','Patchwork / cracked glass / steel wheels'),('van-1-base','02 / PATCHED VAN','Repaired panels / primer patches'),('van-2-base','03 / WORK VAN','Longer body / roof gear / + cargo space'),('van-3-base','04 / LONG CARGO VAN','Raised roof / stretched cargo body')]
    sheet(args.renders,args.output/'van-stages.png','THE OLD VAN / FOUR STAGES','The starter vehicle changes its body as its existing stages are purchased.',stages,2,'Exact stage dimensions from the game / boarding, cargo points and moving joints retained')
    kits=[('van-3-base','LONG CARGO / BODY','Original driving hull underneath'),('van-3-kit','LONG CARGO / FULL KIT','Bull bar / armor / intake / alloys and tread'),('armorvan-1-base','FORTRESS / BODY','Stage-specific modular body'),('armorvan-1-kit','FORTRESS / FULL KIT','Additional purchased protection and equipment')]
    sheet(args.renders,args.output/'upgrade-preview.png','UPGRADES / VISIBLE EQUIPMENT','Body stage versus maximum installed cosmetic kit. Upgrade effects and prices stay in the game.',kits,2,'Rendered from real model builds / no uploaded meshes or texture ids required')
if __name__=='__main__':main()
