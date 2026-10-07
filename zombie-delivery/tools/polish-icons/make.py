#!/usr/bin/env python3
"""Draw the brief's 29 white transparent SVG/PNG icons and audit their upload-ready pixels."""
from pathlib import Path
import hashlib
import io
import json
import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
def rect(x,y,w,h,rx=0): return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}"/>'
def circle(x,y,r): return f'<circle cx="{x}" cy="{y}" r="{r}"/>'
def path(d): return f'<path d="{d}"/>'
def stroke(d,w=6): return f'<path d="{d}" fill="none" stroke="white" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'
def cut(s): return '<g fill="black">'+s.replace('stroke="white"', 'stroke="black"')+'</g>'

def render(shape, size):
    # CairoSVG masks use alpha, while these editable SVGs use luminance. Render the black/white stencil explicitly.
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" fill="black"/><g fill="white">{shape}</g></svg>'
    mask=Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(),output_width=size,output_height=size))).convert("L")
    image=Image.new("RGBA",(size,size),(255,255,255,0));image.putalpha(mask)
    return image

DRAW = {
 "map_bus": rect(23,10,54,73,8)+rect(25,79,11,13,3)+rect(64,79,11,13,3)+cut(rect(30,19,40,8,2)+rect(29,33,42,29,2))+circle(34,73,4)+circle(66,73,4),
 "map_zip": stroke("M12 21 Q50 48 88 21",5)+rect(9,17,6,66)+rect(85,17,6,66)+circle(48,31,7)+rect(45,34,6,13)+path("M30 48H64L57 62H38Z")+stroke("M48 61V75M37 84L48 75L61 84",6),
 "map_rental": circle(25,81,10)+circle(63,81,10)+stroke("M26 77H60L56 31H42",6)+rect(78,38,10,47,3)+rect(74,34,18,7,2)+rect(72,81,22,6,2)+stroke("M51 69H78",5),
 "map_shortcut": path("M10 16H35V38H21V88H10ZM65 16H90V88H79V38H65Z")+stroke("M44 86V63Q44 48 56 48V23",6)+path("M43 31L56 13L69 31Z")+cut(rect(41,68,7,8)+rect(42,47,7,8)),
 "map_bank": path("M10 31L50 9L90 31Z")+rect(14,35,72,7)+rect(15,82,70,8)+rect(9,91,82,4)+''.join(rect(x,44,10,35) for x in (20,45,70)),
 "map_clinic": rect(15,32,70,56,3)+rect(31,12,38,30,3)+cut(rect(47,16,7,20)+rect(40,22,21,7)+rect(40,65,20,23)+rect(23,44,13,12)+rect(65,44,13,12)),
 "map_pharmacy": path("M18 17H59V30H72V71H59V84H18V71H5V30H18Z")+cut(rect(23,35,31,31))+stroke("M68 39L84 55",15)+stroke("M76 47L85 56",7)+cut(stroke("M74 43L78 47",3)),
 "map_warehouse": path("M8 36L50 12L92 36V88H8Z")+cut(rect(22,46,56,42))+rect(25,69,22,17)+rect(52,58,23,28)+cut(rect(35,71,4,14)+rect(61,60,4,24)),
 "map_firestation": path("M48 8C58 29 72 31 77 50C83 74 65 91 48 91C22 91 14 70 27 48L32 37L37 51C46 35 39 25 48 8Z")+cut(path("M48 53C70 80 42 91 35 76C32 70 43 62 48 53Z")),
 "map_police": path("M50 8L84 20V53C84 76 62 88 50 94C38 88 16 76 16 53V20Z")+cut(path("M50 26L56 42L74 43L60 54L65 72L50 62L35 72L40 54L26 43L44 42Z")),
 "map_waterworks": path("M50 8C40 27 23 45 23 61C23 81 39 88 50 88C66 88 79 76 77 60C74 43 58 26 50 8Z")+cut(stroke("M34 66Q50 55 65 67M34 76Q50 65 65 77",5)),
 "map_lab": path("M35 9H65V17H60V39L85 78Q92 91 76 91H24Q8 91 15 78L40 39V17H35Z")+cut(path("M47 17H53V43L66 63H34L47 43Z"))+cut(circle(37,77,4)+circle(55,72,6)+circle(65,83,3)),
 "map_camp": path("M50 13L91 83H9Z")+cut(path("M50 38L73 83H29Z"))+stroke("M24 92H76",5)+rect(12,27,6,38)+path("M18 28L31 38L18 45Z"),
 "map_stadium": '<ellipse cx="50" cy="50" rx="42" ry="31"/>'+cut('<ellipse cx="50" cy="47" rx="29" ry="19"/>')+rect(13,49,7,34)+rect(80,49,7,34)+rect(24,70,53,17)+cut(rect(33,74,8,13)+rect(46,74,8,13)+rect(60,74,8,13)),
 "map_luigis": path("M16 27Q52 5 85 27L50 92Z")+cut(circle(39,37,6)+circle(62,42,6)+circle(49,64,5))+stroke("M20 27Q50 12 80 27",9),
 "map_dailybread": path("M15 40Q15 13 35 16Q49 7 63 17Q85 15 85 40V80Q85 90 72 90H28Q15 90 15 80Z")+cut(stroke("M31 35L38 47M48 30L55 42M65 35L72 47",6)),
 "map_lastbite": path("M16 42Q16 14 50 14Q84 14 84 42Z")+rect(11,47,78,10,4)+path("M14 62L33 70L49 62L65 70L85 62V79Q85 89 73 89H27Q14 89 14 79Z")+cut(circle(36,30,3)+circle(54,23,3)+circle(67,31,3)),
 "map_wokdead": path("M11 49H89Q83 80 57 82V91H43V82Q17 80 11 49Z")+stroke("M29 17Q21 28 30 38M49 10Q41 22 50 34M69 17Q61 28 70 38",5)+stroke("M74 47L89 18",4),
 "map_grindhouse": rect(19,35,52,47,5)+stroke("M71 43H78Q96 58 78 73H71",8)+rect(13,88,64,5,2)+stroke("M33 11Q25 21 34 28M53 9Q45 20 54 27",5)+cut('<ellipse cx="45" cy="58" rx="8" ry="13"/>'),
 "map_postoffice": rect(14,23,71,47,4)+rect(45,68,10,23)+rect(33,89,34,5)+cut(stroke("M22 33L50 52L77 33",6)+stroke("M22 61L37 48M77 61L63 48",4)),
 "map_dailyundead": rect(17,12,66,77,3)+rect(8,35,10,53,3)+cut(rect(24,20,52,9)+rect(24,36,23,23)+rect(54,36,22,4)+rect(54,46,22,4)+rect(54,56,22,4)+rect(24,68,52,4)+rect(24,78,52,4)),
 "map_boltnail": path("M18 14H63V29H46V88H34V29H18Z")+path("M63 37L82 42L78 59L65 63L56 84L47 80L56 59L55 44Z")+cut(circle(70,50,5)),
 "map_volt": rect(14,18,71,71,4)+cut(rect(21,25,57,57))+path("M52 27L32 55H49L42 76L68 47H53L62 27Z")+rect(26,10,10,10)+rect(63,10,10,10),
 "map_secondlife": rect(14,23,72,57,4)+cut(rect(21,30,58,43))+rect(36,78,28,9)+rect(26,87,49,5)+stroke("M42 41Q61 35 65 51M65 51L61 41M65 51L74 45M59 63Q40 67 34 53M34 53L37 65M34 53L26 59",5),
 "map_bloom": path("M31 62H69L62 92H38Z")+stroke("M50 65V43",6)+circle(50,31,9)+circle(35,30,10)+circle(42,17,10)+circle(58,17,10)+circle(65,30,10)+circle(57,41,10)+circle(42,41,10)+cut(circle(50,29,6))+path("M49 61Q23 65 26 48Q46 47 49 61ZM53 56Q75 43 80 52Q71 68 53 56Z"),
 "weapon_reyes": path("M8 45H53L61 39H77L92 49L89 66L65 57H54L48 73H40L45 56H8Z")+rect(7,40,31,5)+rect(39,34,15,7)+cut(stroke("M78 47L75 58M84 48L81 60",4))+stroke("M52 57Q62 69 65 58",4),
 "weapon_lever": rect(7,44,47,9)+path("M48 48H68L89 57L85 70L63 58H54Z")+rect(9,39,39,3)+stroke("M51 55Q47 72 63 67Q68 62 61 56",4)+rect(40,34,9,7),
 "weapon_goldpistol": path("M10 34H77L84 41V51H64L78 82H61L45 53H20V46H10Z")+cut(rect(19,39,43,4)+rect(63,60,4,12))+stroke("M38 52Q42 68 53 60",4),
 "weapon_deadend": rect(8,43,48,9)+path("M48 48H64L91 56L88 69L62 58H52L46 72H38L44 54H8Z")+rect(32,26,36,8,3)+rect(40,33,5,10)+rect(58,33,5,10)+stroke("M75 57V72",3)+circle(75,80,8)+rect(70,85,10,5)+cut(circle(72,79,2)+circle(78,79,2)),
}

def main():
    records=[]
    fingerprints=set()
    for name, shape in DRAW.items():
        folder="weapons" if name.startswith("weapon_") else "map"
        size=256 if folder=="weapons" else 128
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100"><defs><mask id="shape" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"><g fill="white">{shape}</g></mask></defs><rect width="100" height="100" fill="white" mask="url(#shape)"/></svg>'
        dest=ROOT/"art"/folder
        (dest/(name+".svg")).write_text(svg+"\n")
        image=render(shape,size)
        image.save(dest/(name+".png"))
        assert image.size==(size,size)
        visible=[px for px in image.getdata() if px[3]>0]
        assert visible and all(px[:3]==(255,255,255) for px in visible)
        bounds=image.getchannel("A").getbbox()
        assert bounds and min(bounds)>0 and bounds[2]<size and bounds[3]<size, (name,bounds)
        digest=hashlib.sha256(image.tobytes()).hexdigest()
        assert digest not in fingerprints,name
        fingerprints.add(digest)
        records.append({"id":name,"folder":folder,"size":size,"sha256":digest})
    out=ROOT/"design/polish-icons";out.mkdir(parents=True,exist_ok=True)
    (out/"assets.json").write_text(json.dumps(records,indent=2)+"\n")
    # A generated contact sheet; white assets themselves keep transparent backgrounds.
    sheet=Image.new("RGB",(900,((len(records)+5)//6)*160),(24,27,32))
    draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",11)
    for i, record in enumerate(records):
        x,y=(i%6)*150,(i//6)*160
        icon=render(DRAW[record["id"]],104)
        sheet.paste(icon,(x+23,y+10),icon)
        label=record["id"];box=draw.textbbox((0,0),label,font=font)
        draw.text((x+(150-box[2])/2,y+124),label,fill=(236,238,232),font=font)
    sheet.save(out/"sheet.png")
    print(f"PASS: {len(records)} distinct white SVG/PNG silhouettes, alpha, dimensions and margins")

if __name__=="__main__":main()
