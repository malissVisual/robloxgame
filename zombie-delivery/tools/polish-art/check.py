#!/usr/bin/env python3
"""Run real native art builders, audit brief budgets/clearances, and export exact parts for Blender.

6.11, mode "shops": every rooftop shop prop (server/ShopArt/Geometry.luau) through the real PolishArt.Builder and the
real server/ShopProps.place (a stub DayNight records the night colours): budgets, finite geometry, round cylinders and
balls, real materials (a glowing piece's day one that DayNight restores), decorative flags, shadows only on big pieces,
every part (moving ones through their whole motion) inside the prop's envelope, and the envelope on its building
(Art.Mounts): on the roof, behind the name board, clear of the roof units."""
from pathlib import Path
import argparse
import json
import math
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
PREFIX = 'local M=require("./mock")\nlocal Instance,Vector3,Color3,CFrame,UDim2,Enum=M.Instance,M.Vector3,M.Color3,M.CFrame,M.UDim2,M.Enum\n'
RUNTIME = """
local M=require("./mock")
local Builder=require("./Builder")
local Kit=require("./Kit")
local function encode(v)
 if type(v)=="string" then return string.format("%q",v) end
 if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
 if type(v)=="table" then
  local out={}
  if #v>0 then for _,x in v do table.insert(out,encode(x)) end;return "["..table.concat(out,",").."]" end
  for k,x in v do table.insert(out,encode(k)..":"..encode(x)) end;return "{"..table.concat(out,",").."}"
 end
 error("Unsupported geometry export")
end
local function v(a) return {a.X,a.Y,a.Z} end
local function emit(spec,info,bp)
 local parent=M.Instance.new("Folder")
 local root=M.Instance.new("Part");root.Parent=parent
 local seen=0
 local opt={lineColor=M.Color3.fromRGB(73,121,155),nightLight=function(p) seen+=1;p:SetAttribute("NightLight",true) end}
 if info.weld then opt.weldTo=root end
 local model
 if bp then
  model=Kit.build(parent,M.CFrame.identity,bp,{
   part=function(par,name,size,cf,color,material)
    local p=M.Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material
    p.Anchored=true;p.Parent=par;return p
   end,
   deco=function(p) p.CanCollide=false;p.CanQuery=false;return p end,
   nightLight=opt.nightLight,
  })
 else model=Builder.build(parent,M.CFrame.identity,spec,opt) end
 local parts,lights,names={ },0,{}
 for _,p in model:GetDescendants() do
  assert(p.ClassName~="MeshPart" and p.ClassName~="SpecialMesh")
  if p.ClassName=="PointLight" then lights+=1 end
  local record={id=p.uid,name=p.Name,class=p.ClassName,parent=p.Parent.uid}
  if p:IsA("BasePart") then
   assert(not names[p.Name]);names[p.Name]=p
   assert(not p.CanTouch)
   if info.weld then
    assert(not p.Anchored and p.Massless and not p.CanCollide and not p.CanQuery)
    local w=p:FindFirstChild("PolishWeld");assert(w and w.Part0==root and w.Part1==p)
   else assert(p.Anchored) end
   record.position=v(p.Position);record.rotation=p.CFrame.R;record.size=v(p.Size)
   record.color={p.Color.R,p.Color.G,p.Color.B};record.material=p.Material;record.shape=p.Shape or "Block";record.opacity=1-p.Transparency
   record.collide=p.CanCollide;record.query=p.CanQuery;record.shadow=p.CastShadow
  elseif p.ClassName=="TextLabel" then record.text=p.Text
  elseif p.ClassName=="Attachment" then
   record.position=v((p.Parent.CFrame*p.CFrame).Position)
  end
  table.insert(parts,record)
 end
 for _,d in spec.pieces do
  local p=names[d.name];assert(p)
  assert((p.Position-M.Vector3.new(d.at[1],d.at[2],d.at[3])).Magnitude<1e-5)
  if not info.weld then assert(p.CanCollide==(d.solid==true) and p.CanQuery==(d.query==true)) end
  if d.slots then for _,s in d.slots do assert(p:FindFirstChild("PolishLabel"):FindFirstChild(s.name).Text==s.text) end end
 end
 for _,mount in spec.attachments or {} do
  local p=names[mount.attach];local a=p:FindFirstChild(mount.name);assert(a)
  assert(((p.CFrame*a.CFrame).Position-M.Vector3.new(mount.at[1],mount.at[2],mount.at[3])).Magnitude<1e-5)
 end
 assert(lights<=(info.lights or 0))
 print(encode({id=info.id or spec.id,spec=spec,parts=parts,info=info,camera="front"}))
 model:Destroy();assert(model.Parent==nil and #model:GetChildren()==0)
end
"""

def samples(mode):
    if mode == "street":
        return """
local Art=require("./StreetGeometry")
for _,kind in Art.ids do
 for seed=1,3 do
  local width=if seed==1 then 4 elseif seed==2 then 6 else 8
  emit({id=kind,pieces=Art.pieces(kind,seed,width)}, {id=kind..seed,footprint=if kind=="boarded" then {width,6.5,.6} else Art.Footprints[kind],budget=Art.Budgets[kind],kind=kind,seed=seed})
 end
end
local Plan=require("./StreetProps")
local counts,total,props={},0,0
for _,block in Plan.blocks() do
 for _,prop in block.props do
  local n=#Art.pieces(prop.kind,prop.seed,prop.width)
  counts[prop.kind]=(counts[prop.kind] or 0)+1;total+=n;props+=1
 end
end
print(encode({city={props=props,parts=total,kinds=counts}}))
assert(total<=2500,"Whole-city street art exceeds 2500 parts")
"""
    if mode == "towers":
        return """
local Styles={"Shopfront","Rooftop","FireEscape","Boarded"}
local factories={require("./TowerShopfront"),require("./TowerRooftop"),require("./TowerFireEscape"),require("./TowerBoarded")}
local sizes={{36,43,16},{38,40,43},{43,36,89}}
for n,factory in factories do
 for k,size in sizes do
  for direction=1,4 do
   for protected=0,1 do
    local normals={{0,-1},{1,0},{0,1},{-1,0}}
    local a=normals[direction];local b=normals[direction%4+1]
    local walls={{nx=a[1],nz=a[2],door=if protected==1 then 0 else nil,ladders=if protected==1 then {-10} else {},zipRoof=protected==1},{nx=b[1],nz=b[2],ladders={}}}
    local bp=factory(size[1],size[2],size[3],walls)
    local pieces={}
    for _,d in bp.details do
     table.insert(pieces,{name=d.name,size=d.size,at=d.position,color=d.color,rotation=d.rotation,material=d.material,shape=d.shape,night=d.night})
    end
    emit({id=bp.id,pieces=pieces},{id=bp.id..k..direction..protected,budget=30,lights=1,tower=size,walls=walls,style=Styles[n],sample=k==2 and direction==1 and protected==0},bp)
   end
  end
 end
end
"""
    if mode == "shops":
        return """
local Art=require("./ShopGeometry")
local Props=require("./ShopProps")
local WARM=M.Color3.fromRGB(255,225,187)
local function same(a,b) return math.abs(a.R-b.R)+math.abs(a.G-b.G)+math.abs(a.B-b.B)<1e-6 end
local total=0
for _,id in Art.ids do
 local spec=Art.spec(id)
 assert(spec.id=="ShopProp_"..id and Art.Budgets[id] and Art.Envelopes[id] and Art.Mounts[id])
 emit(spec,{id=id,budget=Art.Budgets[id],lights=1,envelope=Art.Envelopes[id],motion=Art.Motion[id],mount=Art.Mounts[id]})
 total+=#spec.pieces
 -- The real ShopProps.place on a turned, raised roof.
 local parent=M.Instance.new("Folder")
 local roof=M.CFrame.new(40,30,-20)*M.CFrame.Angles(0,math.rad(35),0)
 local model=Props.place(parent,id,roof)
 assert(model.Parent==parent and model.Name=="ShopProp_"..id and model.ModelStreamingMode=="Atomic" and model:GetAttribute("ShopProp")==id)
 assert((model.WorldPivot.Position-roof.Position).Magnitude<1e-9)
 local byName={}
 for _,d in spec.pieces do byName[d.name]=d end
 local count,glowing,moved,lights=0,0,0,0
 for _,p in model:GetDescendants() do
  if p:IsA("BasePart") then
   count+=1
   local d=assert(byName[p.Name],"part not in the spec")
   assert(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch and p.CastShadow==(d.shadow==true))
   assert((p.Position-(roof*M.CFrame.new(d.at[1],d.at[2],d.at[3])).Position).Magnitude<1e-4,"part off its spot")
   if d.night then
    glowing+=1
    local lit=p:GetAttribute("LitColor")
    assert(lit and same(lit,if d.lit then M.Color3.fromRGB(d.lit[1],d.lit[2],d.lit[3]) else WARM),"night colour")
    assert(same(p:GetAttribute("DimColor"),p.Color) and p:GetAttribute("DimMaterial")==d.material)
   else assert(p:GetAttribute("LitColor")==nil and d.lit==nil) end
   if d.moves then moved+=1;assert(p.Parent.Name=="Moving") else assert(p.Parent==model) end
  elseif p.ClassName=="PointLight" then lights+=1;assert(p:GetAttribute("NightLight") and p.Parent:IsA("BasePart"))
  end
 end
 assert(count==#spec.pieces and lights<=1)
 local motion=Art.Motion[id]
 local moving=model:FindFirstChild("Moving")
 if motion then
  assert(moving and moved>0 and moving.ClassName=="Model" and moving:GetAttribute("Tag_ShopPropMotion") and moving:GetAttribute("Motion")==motion.kind)
  assert(moving.PrimaryPart and moving.PrimaryPart.Parent==moving)
  local rest=moving:GetAttribute("Rest")
  assert(rest==moving.WorldPivot and (rest.Position-(roof*M.CFrame.new(motion.pivot[1],motion.pivot[2],motion.pivot[3])).Position).Magnitude<1e-6)
  assert((motion.kind=="spin" and (motion.rate or 0)>0) or (motion.kind=="bob" and (motion.amplitude or 0)>0 and (motion.period or 0)>0))
 else assert(moving==nil and moved==0) end
 print(encode({placed={id=id,parts=count,glowing=glowing,moving=moved,lights=lights}}))
end
print(encode({city={props=#Art.ids,parts=total}}))
"""
    return """
local C=require("./Config")
local Shelter=require("./Shelter");local Dock=require("./Dock");local Zip=require("./ZipPlatform");local Bus=require("./BusLivery")
emit(Shelter.build({73,121,155},"BONE STREET","1 / 3"),{budget=35,lights=1,id="shelter"})
for slots=2,3 do emit(Dock.build(slots,C.Rental.SlotPitch,"DOWNTOWN"),{budget=24,lights=1,id="dock"..slots,slots=slots,pitch=C.Rental.SlotPitch}) end
emit(Zip.platform(C.ZipLines.Platform,C.ZipLines.CableHeight,"BONE ST"),{budget=30,lights=1,id="zip-platform",size=C.ZipLines.Platform,height=C.ZipLines.CableHeight})
for _,height in {9,16,43,89} do emit(Zip.ladder(height),{budget=12,lights=0,id="ladder"..height,height=height}) end
emit(Bus.build(),{budget=40,lights=0,id="bus-livery",weld=true})
"""

def extent(part):
    r,s=part["rotation"],part["size"]
    return [sum(abs(r[i*3+j])*s[j] for j in range(3))/2 for i in range(3)]

def check(mode,luau,output):
    with tempfile.TemporaryDirectory() as folder:
        tmp=Path(folder)
        for path in (ROOT/"src/shared").glob("*.luau"):
            source=re.sub(r"require\(script\.Parent\.(\w+)\)",r'require("./\1")',path.read_text())
            (tmp/path.name).write_text(source)
        server=ROOT/"src/server"
        sources={"Builder":server/"PolishArt/Builder.luau","Kit":server/"BuildingLooks/Kit.luau"}
        if mode=="street":sources["StreetGeometry"]=server/"StreetArt/Geometry.luau"
        elif mode=="shops":
            sources["ShopGeometry"]=server/"ShopArt/Geometry.luau";sources["ShopProps"]=server/"ShopProps.luau"
            (tmp/"DayNight.luau").write_text(DAYNIGHT_STUB)
        elif mode=="towers":
            sources["Facade"]=server/"TowerArt/Facade.luau"
            for name in ("TowerShopfront","TowerRooftop","TowerFireEscape","TowerBoarded"):sources[name]=server/"BuildingLooks"/(name+".luau")
        else:
            for name in ("Shelter","Dock","ZipPlatform"):sources[name]=server/"StopArt"/(name+".luau")
            sources["BusLivery"]=server/"VehicleArt/BusLivery.luau"
        for name,path in sources.items():
            source=path.read_text().replace("require(script.Parent.ShopArt.Geometry)",'require("./ShopGeometry")')
            source=re.sub(r"require\(script\.Parent(?:\.Parent)?\.(?:PolishArt\.|TowerArt\.)?(\w+)\)",r'require("./\1")',source)
            (tmp/(name+".luau")).write_text((PREFIX if name in ("Builder","Kit") else SHOP_PREFIX if name=="ShopProps" else "")+source)
        mock=(ROOT/"tools/vehicle-preview/roblox-mock.luau").read_text().replace("Part=true,WedgePart=true","Part=true,TrussPart=true,WedgePart=true")
        (tmp/"mock.luau").write_text(mock)
        (tmp/"run.luau").write_text(RUNTIME+samples(mode))
        result=subprocess.run([str(Path(luau).resolve()),"run.luau"],cwd=tmp,capture_output=True,text=True)
        if result.returncode:raise RuntimeError(result.stderr + "\nLast record: " + result.stdout.splitlines()[-1][:1200])
    rows=[json.loads(line) for line in result.stdout.splitlines()]
    models=[r for r in rows if "parts" in r]
    for model in models:
        info=model["info"];parts=[p for p in model["parts"] if "size" in p]
        assert len(parts)<=info["budget"],(model["id"],len(parts))
        for p in parts:
            assert all(math.isfinite(x) for key in ("size","position","rotation","color") for x in p[key])
            assert min(p["size"])>=.02 and all(0<=c<=1 for c in p["color"])
            if p["shape"]=="Cylinder":assert abs(p["size"][1]-p["size"][2])<1e-6,(model["id"],p["name"],"noncircular cylinder")
            if not p["collide"]:assert not p["query"]
            if mode=="street":
                e=extent(p);f=info["footprint"]
                assert abs(p["position"][0])+e[0]<=f[0]/2+1e-5,(model["id"],p["name"],"X envelope")
                assert abs(p["position"][2])+e[2]<=f[2]/2+1e-5,(model["id"],p["name"],"Z envelope")
                assert p["position"][1]-e[1]>=-1e-5 and p["position"][1]+e[1]<=f[1]+1e-5,(model["id"],p["name"],"Y envelope")
            if mode=="towers":tower_check(p,info)
        if mode=="stops":stop_check(model)
        if mode=="shops":shop_check(model)
    city=next((r["city"] for r in rows if "city" in r),None)
    if city:print("City plan PASS:",city)
    for row in rows:
        if "placed" in row:
            placed=row["placed"];model=next(m for m in models if m["id"]==placed["id"])
            size=bounds(model)
            print(f"  {placed['id']:9s} {placed['parts']:3d} parts ({placed['glowing']} glow at night, {placed['moving']} moving, {placed['lights']} light), {size[0]:.1f} x {size[1]:.1f} x {size[2]:.1f} studs (w x h x d)")
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(models,separators=(",",":"))+"\n")
    print(f"PASS: {mode}, {len(models)} cases, real builder flags/mounts/slots/welds/cleanup, finite geometry and part/light budgets")
    return models

# 6.11, the shop props: a stub DayNight that records what the real one would be handed.
DAYNIGHT_STUB = """
local DayNight={}
function DayNight.nightLight(item,lit,dim,material)
 item:SetAttribute("NightLight",true)
 if lit then item:SetAttribute("LitColor",lit) end
 if dim then item:SetAttribute("DimColor",dim) end
 if material then item:SetAttribute("DimMaterial",material) end
end
return DayNight
"""
SHOP_PREFIX = PREFIX + 'local game=M.game\nlocal warn=function(...) error(table.concat({...}," ")) end\n'
MATERIALS = {"Asphalt","Basalt","Brick","Cardboard","Carpet","CeramicTiles","ClayRoofTiles","Cobblestone","Concrete",
    "CorrodedMetal","CrackedLava","DiamondPlate","Fabric","Foil","ForceField","Glacier","Glass","Granite","Grass","Ground",
    "Ice","LeafyGrass","Leather","Limestone","Marble","Metal","Mud","Neon","Pavement","Pebble","Plaster","Plastic","Rock",
    "RoofShingles","Rubber","Salt","Sand","Sandstone","Slate","SmoothPlastic","Snow","Wood","WoodPlanks"}
DIM_MATERIALS = {"Glass","SmoothPlastic","Metal","Plastic"} # (what DayNight / client WorldFx restore by day)

def round_extent(part):
    """The world half-extents of a part, exact for a cylinder (its axis: local X) and a ball, its box's otherwise."""
    r,s=part["rotation"],part["size"]
    if part["shape"]=="Ball":return [s[0]/2]*3
    if part["shape"]=="Cylinder":
        return [abs(r[i*3])*s[0]/2+s[1]/2*math.sqrt(max(0,1-r[i*3]**2)) for i in range(3)]
    return extent(part)

def bounds(model):
    lo,hi=[math.inf]*3,[-math.inf]*3
    for p in model["parts"]:
        if "size" not in p:continue
        e=round_extent(p)
        for i in range(3):lo[i]=min(lo[i],p["position"][i]-e[i]);hi[i]=max(hi[i],p["position"][i]+e[i])
    return [hi[i]-lo[i] for i in range(3)]

def shop_check(model):
    info=model["info"];spec=model["spec"];name=info["id"]
    W,H,D=info["envelope"]
    pieces={d["name"]:d for d in spec["pieces"]}
    motion=info.get("motion")
    for p in model["parts"]:
        if "size" not in p:continue
        d=pieces[p["name"]];x,y,z=p["position"];ex,ey,ez=round_extent(p);size=sorted(p["size"])
        assert d["material"] in MATERIALS,(name,p["name"],"material")
        assert p["shape"]!="Ball" or size[2]-size[0]<1e-6,(name,p["name"],"a ball is round")
        assert not p["collide"] and not p["query"],(name,p["name"],"decoration only")
        if p["shadow"]:assert size[2]>=4 and size[1]>=3,(name,p["name"],"shadow on a small piece")
        if d.get("night"):
            assert d["material"] in DIM_MATERIALS,(name,p["name"],"a glowing piece's day material")
            assert all(0<=c<=255 for c in d.get("lit",[0,0,0])),(name,p["name"],"night colour")
        else:assert "lit" not in d and "light" not in d,(name,p["name"],"lit but not glowing")
        if d.get("moves"):
            assert motion,(name,p["name"],"moves without a motion")
            px,py,pz=motion["pivot"]
            reach=math.hypot(abs(x-px)+ex,abs(z-pz)+ez) # its farthest corner from the pivot's axis
            if motion["kind"]=="spin":
                assert reach<=min(W,D)/2+1e-5,(name,p["name"],"spins out of the envelope")
                rise=0
            else:
                sway=math.radians(motion.get("sway",0));rise=motion["amplitude"]
                swing=reach*math.sin(sway)+reach*(1-math.cos(sway))
                assert abs(x)+ex+swing<=W/2+1e-5 and abs(z)+ez+swing<=D/2+1e-5,(name,p["name"],"sways out of the envelope")
            assert y-ey-rise>=-1e-5 and y+ey+rise<=H+1e-5,(name,p["name"],"moves out of the envelope")
        else:
            assert abs(x)+ex<=W/2+1e-5 and abs(z)+ez<=D/2+1e-5,(name,p["name"],"X/Z envelope")
            assert y-ey>=-1e-5 and y+ey<=H+1e-5,(name,p["name"],"Y envelope")
    assert H<=20.5 and W<=60,(name,"a set piece, not a building")
    # On its building: on the roof, behind the name board, clear of what stands there.
    mount=info["mount"];ax,ay,az=mount["at"];x0,z0,x1,z1=mount["roof"]
    box=(ax-W/2,az-D/2,ax+W/2,az+D/2)
    assert x0<=box[0] and box[2]<=x1 and z0<=box[1] and box[3]<=z1,(name,"off the roof")
    if mount.get("sign"):assert box[1]>=mount["sign"][0]+0.25,(name,"in front of the name board")
    for r in mount.get("avoid") or []:
        assert box[2]<=r[0] or r[2]<=box[0] or box[3]<=r[1] or r[3]<=box[1],(name,"on a roof unit",r)

def tower_check(p,info):
    w,d,h=info["tower"];x,y,z=p["position"];ex,ey,ez=extent(p)
    if y-ey>=h-1e-5:
        assert y+ey<=h+3+1e-5 and abs(x)+ex<=w/2+.1 and abs(z)+ez<=d/2+.1
        assert not any(wall.get("zipRoof") for wall in info["walls"]),"Zip roof must remain empty"
        return
    for wall in info["walls"]:
        nx,nz=wall["nx"],wall["nz"]
        half=w/2 if nx else d/2
        outward=nx*x+nz*z
        if outward<half-.5:continue
        along=z if nx else x;reach=ez if nx else ex;out=ex if nx else ez
        if y-ey<6:assert outward+out-half<=.8+1e-5
        if outward+out-half>.8:assert y-ey>=7-1e-5 and outward+out-half<=3+1e-5
        if "door" in wall and y-ey<12:assert abs(along-wall["door"])>=reach+6-1e-5,(p["name"],"door")
        for ladder in wall["ladders"]:assert abs(along-ladder)>=reach+6-1e-5,(p["name"],"ladder")
        # Window strips at floor*9 ±1.5 stay visible, except deliberate plywood in boarded style.
        if info["style"]!="Boarded":
            for f in range(1,math.floor((h-4)/9)+1):
                if y-ey<9*f+1.5 and y+ey>9*f-1.5:
                    assert abs(along)-reach>=(d/2 if nx else w/2)-2-1e-5,(p["name"],"window strip")
        return
    raise AssertionError((p["name"],"detail not on supplied street wall"))

def stop_check(model):
    info=model["info"];spec=model["spec"]
    named={p["name"]:p for p in spec["pieces"]}
    mounts={p["name"]:p for p in spec.get("attachments",[]) or []}
    slots={s["name"] for p in spec["pieces"] for s in p.get("slots",[])}
    id=info["id"]
    if id=="shelter":
        assert "ArrivalsBoard" in named and {"Arrivals","StopName","Lines"}<=slots
        for p in model["parts"]:
            if "size" in p and p["name"]!="KerbLine":assert p["position"][2]+extent(p)[2]<=3+1e-5,"shelter blocks walk line"
        assert any(p.get("lineColor") for p in spec["pieces"])
    elif id.startswith("dock"):
        assert "DockName" in slots
        for i in range(1,info["slots"]+1):
            assert "Clamp"+str(i) in named and "Slot"+str(i) in mounts
            assert abs(mounts["Slot"+str(i)]["at"][0]-(i-(info["slots"]+1)/2)*info["pitch"])<1e-6
            assert abs(mounts["Slot"+str(i)]["at"][2]-1.6)<1e-6
    elif id=="zip-platform":
        assert named["Platform"]["size"][0]==info["size"]==named["Platform"]["size"][2]
        assert mounts["CableAnchor"]["at"]==[0,info["height"],0] and "ZipName" in slots
        assert not any(p["name"]=="FrontRail" for p in spec["pieces"])
    elif id.startswith("ladder"):
        assert mounts["ClimbTop"]["at"][1]==info["height"]
        assert sum(p.get("shape")=="Truss" for p in spec["pieces"])==1
        if info["height"]>10:assert any(p["name"].startswith("Cage") for p in spec["pieces"])
    elif id=="bus-livery":
        assert {"LineNumber","LineName"}<=slots and any(p.get("lineColor") for p in spec["pieces"])
        assert all(not p.get("solid") for p in spec["pieces"])

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",choices=("street","towers","stops","shops"));parser.add_argument("luau");parser.add_argument("output",type=Path)
    args=parser.parse_args();check(args.mode,args.luau,args.output)
