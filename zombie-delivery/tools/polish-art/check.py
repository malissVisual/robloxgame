#!/usr/bin/env python3
"""Run real native art builders, audit brief budgets/clearances, and export exact parts for Blender."""
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
   else assert(p.Anchored and p.Massless) end
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
   for protected=0,3 do
    local normals={{0,-1},{1,0},{0,1},{-1,0}}
    local a=normals[direction];local b=normals[direction%4+1]
    local walls={{nx=a[1],nz=a[2],door=if protected==0 then nil elseif protected==1 then 0 elseif protected==2 then -12 else 12,ladders=if protected==0 then {} elseif protected==1 then {-10} elseif protected==2 then {12} else {-12},zipRoof=protected>0},{nx=b[1],nz=b[2],ladders={}}}
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
        elif mode=="towers":
            sources["Facade"]=server/"TowerArt/Facade.luau"
            for name in ("TowerShopfront","TowerRooftop","TowerFireEscape","TowerBoarded"):sources[name]=server/"BuildingLooks"/(name+".luau")
        else:
            for name in ("Shelter","Dock","ZipPlatform"):sources[name]=server/"StopArt"/(name+".luau")
            sources["BusLivery"]=server/"VehicleArt/BusLivery.luau"
        for name,path in sources.items():
            source=path.read_text()
            source=re.sub(r"require\(script\.Parent(?:\.Parent)?\.(?:PolishArt\.|TowerArt\.|BuildingLooks\.)?(\w+)\)",r'require("./\1")',source)
            (tmp/(name+".luau")).write_text((PREFIX if name in ("Builder","Kit") else "")+source)
        mock=(ROOT/"tools/vehicle-preview/roblox-mock.luau").read_text().replace("Part=true,WedgePart=true","Part=true,TrussPart=true,WedgePart=true")
        (tmp/"mock.luau").write_text(mock)
        (tmp/"run.luau").write_text(RUNTIME+samples(mode))
        result=subprocess.run([str(Path(luau).resolve()),"run.luau"],cwd=tmp,capture_output=True,text=True)
        if result.returncode:raise RuntimeError(result.stderr + "\nLast record: " + (result.stdout.splitlines() or ["no records"])[-1][:1200])
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
            assert not p["shadow"], (model["id"], p["name"], "small art shadows")
            if mode=="street":
                e=extent(p);f=info["footprint"]
                assert abs(p["position"][0])+e[0]<=f[0]/2+1e-5,(model["id"],p["name"],"X envelope")
                assert abs(p["position"][2])+e[2]<=f[2]/2+1e-5,(model["id"],p["name"],"Z envelope")
                assert p["position"][1]-e[1]>=-1e-5 and p["position"][1]+e[1]<=f[1]+1e-5,(model["id"],p["name"],"Y envelope")
            if mode=="towers":tower_check(p,info)
        if mode=="stops":stop_check(model)
    city=next((r["city"] for r in rows if "city" in r),None)
    if city:print("City plan PASS:",city)
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(models,separators=(",",":"))+"\n")
    print(f"PASS: {mode}, {len(models)} cases, real builder flags/mounts/slots/welds/cleanup, finite geometry and part/light budgets")
    return models

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
    parser.add_argument("mode",choices=("street","towers","stops"));parser.add_argument("luau");parser.add_argument("output",type=Path)
    args=parser.parse_args();check(args.mode,args.luau,args.output)
