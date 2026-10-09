#!/usr/bin/env python3
"""Run real native art builders, audit brief budgets/clearances, and export exact parts for Blender.

6.11, mode "shops": every rooftop shop prop (server/ShopArt/Geometry.luau) through the real PolishArt.Builder and the
real server/ShopProps.place (a stub DayNight records the night colours): budgets, finite geometry, round cylinders and
balls, real materials (a glowing piece's day one that DayNight restores), decorative flags, shadows only on big pieces,
every part (moving ones through their whole motion) inside the prop's envelope, and the envelope on its building
(Art.Mounts): on the roof, behind the name board, clear of the roof units. 6.12.7: two props on one roof (SHARED_ROOFS:
Dead End Motors' car and the giant bike from Spoke & Chain's old roof) share that roof's mount data and their envelopes
stay apart, each listed in the other's avoid boxes.
6.12.6, the gear stall's two props ("gearvest" over GEAR, "zdcbag" over BAGS): the real server/GearStall.build places
them, next to the real JOBS booth (server/JobsSpot.build round the job board where World stands it) and the depot
hall's look (BuildingLooks/Depot through Kit.build, the hall's shell from World's numbers); in the stall's own frame:
Art.Mounts agrees with the stall it builds, each prop over its counter's prompt, on the roof behind the name board (the
spawn in front of it: nothing of them can cover its text), 7-10.5 studs tall and at least 4.5 of it in sight over the
board from the spawn, clear of the other prop, the hall (its canopy) and the booth by a stud, decoration only.
6.12.14, Lead & Co.'s range ("guns", GUN STORE and the cartridge at the smaller scale): the real server/GunRange.build
places it on the range shop's roof; in the cabin's own frame: Art.Mounts.guns agrees with the cabin it builds (the roof
slab's top and box, the name board's back face and top), the prop on the roof behind the board, over the counter with
the "guns" prompt (Map.Shops.guns its front), its letters in sight over the board from the street in front of the gate
(4th Ave), clear of everything else of the compound by a stud, decoration only; the compound within its part budget."""
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
assert(total<=2600,"Whole-city street art exceeds 2600 parts") -- (6.12.7: 2500; the two gas stations by the safe zone put a few more props on their sidewalks)
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
-- 6.12.6, the gear stall: the real GearStall.build (it places its two props), the real JOBS booth round the job board
-- where World stands it, the depot hall's look (Kit.build, World's frame) and its shell (World buildDepot: 80 wide, 40
-- deep, 22 tall and its roof, the name board on top; its back wall at -BlockSize/2 + 6): every part's box in the
-- stall's frame (GearStall's: its base on the walk, -Z out to the yard, +X to the GEAR counter).
local C=require("./Config");local Map=require("./Map")
local S,D,walk=C.GearStall,Map.Depot,Map.WalkTop
local function tool(parent,name,size,cf,color,material)
 local p=M.Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color or M.Color3.new(0,0,0);p.Material=material or "Plastic"
 p.Anchored=true;p.Parent=parent;return p
end
local tools={part=tool,deco=function(p) p.CanCollide=false;p.CanQuery=false;return p end,
 sign=function(parent,text,size,cf) tool(parent,"Sign",size,cf):SetAttribute("Text",text) end,
 prompt=function(parent,shop) parent:SetAttribute("PromptShop",shop) end,
 nightLight=function(item) item:SetAttribute("NightLight",true) end}
local depot=M.Instance.new("Folder")
require("./GearStall").build(depot,tools)
local backZ=-C.City.BlockSize/2+6
local board=tool(depot,"JobBoard",M.Vector3.new(14,8,1),M.CFrame.new(D.x+C.Goal.BoardSpot[1],walk+5,D.z+C.Goal.BoardSpot[2])*M.CFrame.Angles(0,math.pi,0))
require("./JobsSpot").build(depot,board,tools)
local hall=M.Instance.new("Folder");hall.Name="Hall";hall.Parent=depot
require("./Kit").build(hall,M.CFrame.new(D.x,walk,D.z+backZ+20)*M.CFrame.Angles(0,math.pi,0),require("./DepotLook"),tools)
tool(hall,"HallShell",M.Vector3.new(80,walk+32,40),M.CFrame.new(D.x,(walk+32)/2,D.z+backZ+20))
local base=M.Vector3.new(D.x+S.X,walk,D.z+S.Z)
local frame=M.CFrame.lookAt(base,base+M.Vector3.new(1,0,0))
local rows={}
for _,p in depot:GetDescendants() do
 if p:IsA("BasePart") then
  local cf=frame:ToObjectSpace(p.CFrame);local r,s,o=cf.R,p.Size,cf.Position;local e={}
  for i=0,2 do e[i+1]=(math.abs(r[i*3+1])*s.X+math.abs(r[i*3+2])*s.Y+math.abs(r[i*3+3])*s.Z)/2 end
  local at,prop=p,""
  while at.Parent~=depot do at=at.Parent;if string.sub(at.Name,1,9)=="ShopProp_" then prop=string.sub(at.Name,10) end end
  table.insert(rows,{name=p.Name,group=if at==hall then "hall" elseif at.Name=="GearStall" then "stall" else "jobs",prop=prop,
   box={o.X-e[1],o.Y-e[2],o.Z-e[3],o.X+e[1],o.Y+e[2],o.Z+e[3]},size={s.X,s.Y,s.Z},collide=p.CanCollide,query=p.CanQuery,prompt=p:GetAttribute("PromptShop") or ""})
 end
end
local spawn=frame:PointToObjectSpace(M.Vector3.new(D.x,walk,D.z+26)) -- (World.DepotSpawn)
print(encode({stall={parts=rows,spawn={spawn.X,spawn.Z},config={Width=S.Width,Depth=S.Depth,Height=S.Height,Counter=S.Counter},
 mounts={gearvest=Art.Mounts.gearvest,zdcbag=Art.Mounts.zdcbag},envelopes={gearvest=Art.Envelopes.gearvest,zdcbag=Art.Envelopes.zdcbag}}}))
-- 6.12.14, Lead & Co.'s range: the real GunRange.build (it places the guns prop on its cabin's roof); every part's box
-- in the cabin's frame (its middle on the walk, -Z out of its door toward 4th Ave).
local R,G=C.GunRange,Map.GunRange
local range=M.Instance.new("Folder")
local rangeTools={part=tool,deco=tools.deco,nightLight=tools.nightLight,
 sign=function(parent,text,size,cf,color,background,art) local p=tool(parent,"Sign",size,cf);p:SetAttribute("Text",text);if art then p:SetAttribute("Art",art) end end,
 prompt=function(parent,shop) parent:SetAttribute("PromptShop",shop) end,
 sidewalk=function(parent,cx,cz) tool(parent,"Sidewalk",M.Vector3.new(C.City.BlockSize,walk,C.City.BlockSize),M.CFrame.new(cx,walk/2,cz)) end}
require("./GunRange").build(range,rangeTools)
local rbase=M.Vector3.new(G.x,walk,G.z)
local cabin=M.CFrame.lookAt(rbase,rbase+M.Vector3.new(G.fx,0,G.fz))*M.CFrame.new(R.Cabin.X,0,R.Cabin.Z)
local rrows={}
for _,p in range:GetDescendants() do
 if p:IsA("BasePart") then
  local cf=cabin:ToObjectSpace(p.CFrame);local r,s,o=cf.R,p.Size,cf.Position;local e={}
  for i=0,2 do e[i+1]=(math.abs(r[i*3+1])*s.X+math.abs(r[i*3+2])*s.Y+math.abs(r[i*3+3])*s.Z)/2 end
  local at,prop=p,""
  while at.Parent~=range do at=at.Parent;if string.sub(at.Name,1,9)=="ShopProp_" then prop=string.sub(at.Name,10) end end
  table.insert(rrows,{name=p.Name,prop=prop,box={o.X-e[1],o.Y-e[2],o.Z-e[3],o.X+e[1],o.Y+e[2],o.Z+e[3]},collide=p.CanCollide,query=p.CanQuery,
   prompt=p:GetAttribute("PromptShop") or "",art=p:GetAttribute("Art") or "",text=p:GetAttribute("Text") or ""})
 end
end
local shopAt=cabin:PointToObjectSpace(M.Vector3.new(Map.Shops.guns.x,walk,Map.Shops.guns.z))
local street=cabin:PointToObjectSpace(M.Vector3.new(Map.gunRangeAt(R.Gate.X,-(C.City.BlockSize/2+C.City.RoadWidth/2))))
print(encode({range={parts=rrows,shop={shopAt.X,shopAt.Z},street={street.X,street.Z},config={Width=R.Cabin.Width,Depth=R.Cabin.Depth,Height=R.Cabin.Height,
 Counter=R.Counter,Board=R.Board},mount=Art.Mounts.guns,envelope=Art.Envelopes.guns}}))
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
            sources["GearStall"]=server/"GearStall.luau";sources["JobsSpot"]=server/"JobsSpot.luau";sources["DepotLook"]=server/"BuildingLooks/Depot.luau"
            sources["GunRange"]=server/"GunRange.luau" # (6.12.14)
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
            source=re.sub(r"require\(Shared\.(\w+)\)",r'require("./\1")',source) # (GearStall: Config, Map)
            (tmp/(name+".luau")).write_text((PREFIX if name in ("Builder","Kit","JobsSpot") else SHOP_PREFIX if name in ("ShopProps","GearStall") else RANGE_PREFIX if name=="GunRange" else "")+source)
        mock=(ROOT/"tools/vehicle-preview/roblox-mock.luau").read_text().replace("Part=true,WedgePart=true","Part=true,TrussPart=true,WedgePart=true")
        # (6.12.6: a CFrame's Rotation, for JobsSpot)
        assert "local F={}; F.__index=F" in mock
        mock=mock.replace("local F={}; F.__index=F","local F={}; F.__index=function(f,k) if k=='Rotation' then return setmetatable({Position=Mock.Vector3.zero,R=f.R},F) end; return F[k] end")
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
    if mode=="shops":shared_roofs(models)
    city=next((r["city"] for r in rows if "city" in r),None)
    if city:print("City plan PASS:",city)
    if mode=="shops":stall_check(next(r["stall"] for r in rows if "stall" in r))
    if mode=="shops":range_check(next(r["range"] for r in rows if "range" in r))
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
# (6.12.14: server/GunRange.luau draws its targets' rings with a Vector2 anchor and a UDim corner)
RANGE_PREFIX = SHOP_PREFIX + 'local Vector2,UDim=M.Vector2,{new=function(a,b) return {a,b} end}\n'
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

def box_gap(a,b):
    """How far apart two boxes { x0, y0, z0, x1, y1, z1 } are (0 when they touch or overlap)."""
    return math.sqrt(sum(max(b[i]-a[i+3],a[i]-b[i+3],0)**2 for i in range(3)))

def stall_check(stall):
    """6.12.6, the gear stall's props in the stall's frame (-Z out to the yard, +X to GEAR; y 0 on the walk)."""
    S=stall["config"];c=S["Counter"];parts=stall["parts"]
    def one(name,test=lambda p:True):
        found=[p for p in parts if p["group"]=="stall" and not p["prop"] and p["name"]==name and test(p)]
        assert len(found)==1,("stall",name,len(found));return found[0]
    roof=one("Roof");top=roof["box"][4]
    board=one("Sign",lambda p:abs(p["size"][0]-S["Width"])<1e-6)
    front,back,boardTop=board["box"][2],board["box"][5],board["box"][4]
    desks={p["prompt"]:p["box"] for p in parts if p["group"]=="stall" and p["name"]=="Counter"}
    assert set(desks)=={"supplies","bags"},desks.keys()
    # Nothing else of the stall over its roof but its name board (and the props).
    for p in parts:
        if p["group"]=="stall" and not p["prop"] and p["name"]!="Sign":assert p["box"][4]<=top+1e-6,("stall",p["name"],"over the roof")
    others=[p for p in parts if p["group"] in ("hall","jobs")]
    assert any(p["name"]=="DispatchCanopy" for p in others) and any(p["name"]=="Canopy" for p in others),"the hall's and the booth's canopies"
    sx,sz=stall["spawn"];eye=5 # (a courier's eyes over the walk, at the spawn)
    assert sz<front-10,"the spawn in front of the stall's name board"
    boxes={}
    for id,shop,side in (("gearvest","supplies",1),("zdcbag","bags",-1)):
        mine=[p for p in parts if p["prop"]==id]
        assert mine and all(p["group"]=="stall" for p in mine),(id,"not placed by GearStall.build")
        assert all(not p["collide"] and not p["query"] for p in mine),(id,"decoration only (the prompts reach through)")
        lo=[min(p["box"][i] for p in mine) for i in range(3)];hi=[max(p["box"][i+3] for p in mine) for i in range(3)]
        # Art.Mounts is the stall GearStall builds: over its counter, on the roof's top, the roof and the board's back.
        mount=stall["mounts"][id];ax,ay,az=mount["at"];W,H,D=stall["envelopes"][id]
        assert abs(ax-side*c)<1e-6 and abs(ay-top)<1e-6,(id,"mount: over its counter, on the roof")
        r=roof["box"];assert all(abs(u-v)<1e-6 for u,v in zip(mount["roof"],(r[0],r[2],r[3],r[5]))),(id,"mount: the roof",mount["roof"])
        assert abs(mount["sign"][0]-back)<1e-6 and abs(mount["sign"][1]-(boardTop-top))<1e-6,(id,"mount: the name board",mount["sign"])
        # Over its counter's prompt, on the roof behind the board, on its own half.
        desk=desks[shop];assert abs((lo[0]+hi[0])/2-(desk[0]+desk[3])/2)<0.75,(id,"not over its counter")
        assert lo[1]>=top-1e-6 and lo[2]>=back+0.25-1e-6,(id,"on the roof, behind the board")
        env=(ax-W/2,top,az-D/2,ax+W/2,top+H,az+D/2)
        assert (env[0]>=-1e-6 if side>0 else env[3]<=1e-6) and W<=desk[3]-desk[0],(id,"wider than its counter")
        # Sized to the stall, and in sight over the board from the spawn (its top at least 4.5 over the line of sight).
        height=hi[1]-top;assert 7<=height<=10.5,(id,"height",height)
        px,pz=(lo[0]+hi[0])/2,(lo[2]+hi[2])/2
        t=(front-sz)/(pz-sz);hidden=eye+(boardTop-eye)/t
        assert hi[1]-hidden>=4.5,(id,"hidden behind the board from the spawn",hi[1]-hidden)
        # Clear of the depot hall (its canopy), the JOBS booth, by a stud through the whole turn.
        near=min(others,key=lambda p:box_gap(env,p["box"]))
        assert box_gap(env,near["box"])>=1,(id,"against",near["group"],near["name"])
        boxes[id]=env
        print(f"  stall     {id:9s} over {shop:8s} (x {ax:+.1f}, z {az:+.1f}, y {top:.1f}): {height:.1f} tall, "
              f"{hi[0]-lo[0]:.1f} x {hi[2]-lo[2]:.1f} at rest, {hi[1]-hidden:.1f} in sight from the spawn, "
              f"{box_gap(env,near['box']):.1f} from the {near['group']}'s {near['name']}")
    assert box_gap(boxes["gearvest"],boxes["zdcbag"])>=1,"the two props apart"

def range_check(rng):
    """6.12.14, Lead & Co.'s range: the guns prop on the range shop's roof (the cabin's frame: -Z out of its door, y 0
    on the walk), as server/GunRange.build places it."""
    parts=rng["parts"];cfg=rng["config"];mount=rng["mount"];W,H,D=rng["envelope"]
    def one(test,what):
        found=[p for p in parts if not p["prop"] and test(p)]
        assert len(found)==1,("range",what,len(found));return found[0]
    roof=one(lambda p:p["name"]=="CabinRoof","the roof");top=roof["box"][4]
    board=one(lambda p:p["name"]=="Sign" and p["art"]=="guns","the name board")
    desk=one(lambda p:p["name"]=="Counter","the counter")
    assert desk["prompt"]=="guns" and board["text"]==cfg["Board"],("range","the counter's prompt, the board's words")
    front,back,boardTop=board["box"][2],board["box"][5],board["box"][4]
    # Art.Mounts.guns is the cabin GunRange builds: on the roof slab's top, its box, the board's back face and top.
    ax,ay,az=mount["at"];r=roof["box"]
    assert abs(ay-top)<1e-6 and abs(ax)<1e-6,("range","mount: on the roof's top",ay,top)
    assert all(abs(u-v)<1e-6 for u,v in zip(mount["roof"],(r[0],r[2],r[3],r[5]))),("range","mount: the roof",mount["roof"],r)
    assert abs(mount["sign"][0]-back)<1e-6 and abs(mount["sign"][1]-(boardTop-top))<1e-6,("range","mount: the name board",mount["sign"])
    assert abs(top-(cfg["Height"]+0.5))<1e-6 and abs((r[3]-r[0])-(cfg["Width"]+1))<1e-6 and abs((r[5]-r[2])-(cfg["Depth"]+1))<1e-6,("range","the roof: the cabin's")
    # The prop: placed by GunRange.build, decoration only, on the roof behind the board, over the counter.
    mine=[p for p in parts if p["prop"]=="guns"]
    assert mine and all(not p["collide"] and not p["query"] for p in mine),("range","the prop: decoration only")
    lo=[min(p["box"][i] for p in mine) for i in range(3)];hi=[max(p["box"][i+3] for p in mine) for i in range(3)]
    assert lo[1]>=top-1e-6 and lo[2]>=back+0.25-1e-6 and lo[0]>=r[0]-1e-6 and hi[0]<=r[3]+1e-6 and hi[2]<=r[5]+1e-6,("range","the prop: on the roof, behind the board")
    assert desk["box"][0]<=(lo[0]+hi[0])/2<=desk["box"][3],("range","the prop: over the counter")
    sx,sz=rng["shop"];assert abs(sz-desk["box"][2])<1e-6 and desk["box"][0]<=sx<=desk["box"][3],("range","Map.Shops.guns: the counter's front")
    # Smaller than on the old 60-wide roof, but the letters (the marquee) read over the board from the street in front
    # of the gate (4th Ave, a courier's eyes 5 over the walk): at least 2 studs of them in sight.
    height=hi[1]-top;assert 7<=height<=10.5 and hi[0]-lo[0]<=cfg["Width"]+1,("range","the prop's size",height)
    letters=[p for p in mine if p["name"].startswith("Front")]
    assert letters,("range","the street side's letters")
    l0=min(p["box"][1] for p in letters);l1=max(p["box"][4] for p in letters);lz=min(p["box"][2] for p in letters)
    ex,ez=rng["street"];eye=5
    hidden=eye+(boardTop-eye)*(lz-ez)/(front-ez)
    assert l1-max(l0,hidden)>=2,("range","the letters hidden behind the board from the street",hidden,l0,l1)
    # Clear of everything else of the compound that stands over the roof's top (the masts, the pavilion, the gate) by a
    # stud, the cabin's own board and roof unit aside (Art.Mounts.guns: the board, the avoid box).
    env=(ax-W/2,top,az-D/2,ax+W/2,top+H,az+D/2)
    others=[p for p in parts if not p["prop"] and p["box"][4]>top+1e-6 and not (p["name"]=="Sign" and p["art"]=="guns") and p["name"]!="RoofUnit"]
    near=min(others,key=lambda p:box_gap(env,p["box"]))
    assert box_gap(env,near["box"])>=1,("range","the prop against",near["name"])
    count=len([p for p in parts if not p["prop"]])
    assert count<=320,("range","parts",count)
    print(f"  range     guns over the counter (x {ax:+.1f}, z {az:+.1f}, y {top:.1f}): {height:.1f} tall, {hi[0]-lo[0]:.1f} x {hi[2]-lo[2]:.1f}, "
          f"its letters {l1-max(l0,hidden):.1f} of {l1-l0:.1f} in sight from 4th Ave, {box_gap(env,near['box']):.1f} from the {near['name']}; "
          f"the compound {count} parts, {len(mine)} in the prop")

# 6.12.7, the props that stand on one roof together (World buildDealer: Dead End Motors' car and, since the bikes are
# sold there, the giant bike from Spoke & Chain's old roof): one building (the same roof, name board and roof height),
# their envelopes apart, and each one's envelope among the other's avoid boxes (what already stands there).
SHARED_ROOFS=(("dealer","bikes"),)

def envelope_box(info):
    W,H,D=info["envelope"];ax,ay,az=info["mount"]["at"]
    return (ax-W/2,az-D/2,ax+W/2,az+D/2)

def shared_roofs(models):
    infos={m["info"]["id"]:m["info"] for m in models}
    for a,b in SHARED_ROOFS:
        A,B=infos[a],infos[b];ma,mb=A["mount"],B["mount"]
        assert ma["roof"]==mb["roof"] and ma.get("sign")==mb.get("sign") and ma["at"][1]==mb["at"][1],(a,b,"not on one roof")
        ba,bb=envelope_box(A),envelope_box(B)
        assert ba[2]<=bb[0] or bb[2]<=ba[0] or ba[3]<=bb[1] or bb[3]<=ba[1],(a,b,"the props overlap")
        def covered(box,avoid):
            return any(r[0]<=box[0]+1e-6 and r[1]<=box[1]+1e-6 and box[2]<=r[2]+1e-6 and box[3]<=r[3]+1e-6 for r in avoid)
        assert covered(bb,ma.get("avoid") or []) and covered(ba,mb.get("avoid") or []),(a,b,"each in the other's avoid boxes")
        gap=max(bb[0]-ba[2],ba[0]-bb[2],bb[1]-ba[3],ba[1]-bb[3])
        print(f"  {a} + {b}: one roof, their envelopes {gap:.1f} studs apart, each clear of the other")

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
