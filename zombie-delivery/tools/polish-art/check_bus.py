#!/usr/bin/env python3
"""Attach the livery to the actual Vehicles.buildBus factory; audit boarding/seat/hull invariants and weld frames."""
from pathlib import Path
import argparse, subprocess, tempfile, sys, json
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/vehicle-preview'))
from export_fleet import prepare_modules
RUNTIME='''
local M=require("./roblox-mock")
local Vehicles=require("./Vehicles")
local Config=require("./Config")
local Builder=require("./PolishBuilder")
local Art=require("./BusLivery")
local def
for _,d in Config.Cars do if d.style=="bus" then def=d end end
assert(def)
local function xyz(v) return {v.X,v.Y,v.Z} end
local function encode(v)
 if type(v)=="string" then return string.format("%q",v) end
 if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
 local out={}
 if #v>0 then for _,x in v do table.insert(out,encode(x)) end;return "["..table.concat(out,",").."]" end
 for k,x in v do table.insert(out,encode(k)..":"..encode(x)) end;return "{"..table.concat(out,",").."}"
end
local function equal(a,b) for i,x in a do assert(x==b[i], "Existing body geometry changed") end end
for _,angle in {0,90,180,270} do
 local ground=M.CFrame.new(70,3,-110)*M.CFrame.Angles(0,math.rad(angle),0)
 local bus,board=Vehicles.buildBus(def,ground,M.Color3.fromRGB(226,228,222),M.Color3.fromRGB(73,121,155))
 local before={}
 local count=0
 for _,p in bus.model:GetDescendants() do
  if p:IsA("BasePart") then
   before[p]={size=xyz(p.Size),at=xyz(p.Position),r=table.clone(p.CFrame.R),collide=p.CanCollide,query=p.CanQuery,touch=p.CanTouch,anchored=p.Anchored,massless=p.Massless,parent=p.Parent}
  end
  if p.ClassName=="Motor6D" then before[p]={part0=p.Part0,part1=p.Part1,c0=p.C0,c1=p.C1,parent=p.Parent} end
 end
 local size=xyz(bus.size)
 local seats=table.clone(bus.seats)
 local top=bus.chassis.CFrame*M.CFrame.new(0,.6,0)
 if angle==0 then
  local reference={}
  for _,p in bus.model:GetDescendants() do
   if p:IsA("BasePart") then
    local cf=top:ToObjectSpace(p.CFrame)
    table.insert(reference,{id=-p.uid,name="Caller bus / "..p.Name,class=p.ClassName,size=xyz(p.Size),position=xyz(cf.Position),rotation=cf.R,color={p.Color.R,p.Color.G,p.Color.B},material=p.Material,shape=p.Shape or "Block",opacity=1-p.Transparency,reference=true})
   end
  end
  print(encode(reference))
 end
 local spec=Art.build()
 local model=Builder.build(bus.model,top,spec,{weldTo=bus.chassis,lineColor=M.Color3.fromRGB(73,121,155)})
 for p,old in before do
  assert(p.Parent==old.parent)
  if p:IsA("BasePart") then
   equal(old.size,xyz(p.Size));equal(old.at,xyz(p.Position));equal(old.r,p.CFrame.R)
   assert(p.CanCollide==old.collide and p.CanQuery==old.query and p.CanTouch==old.touch and p.Anchored==old.anchored and p.Massless==old.massless)
  else assert(p.Part0==old.part0 and p.Part1==old.part1 and p.C0==old.c0 and p.C1==old.c1) end
 end
 equal(size,xyz(bus.size));assert(board.Parent==bus.model and #bus.seats==#seats)
 for i,seat in seats do assert(bus.seats[i]==seat and seat.Parent==bus.model) end
 for _,d in spec.pieces do
  local p=model:FindFirstChild(d.name)
  assert(p and p.Massless and not p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
  local target=top*M.CFrame.new(d.at[1],d.at[2],d.at[3])
  assert((p.Position-target.Position).Magnitude<1e-5)
  local weld=p:FindFirstChild("PolishWeld");assert(weld and weld.Part0==bus.chassis and weld.Part1==p)
  count+=1
  if d.lineColor then assert(p.Color.B==155/255) end
  local r=p.CFrame.R
  -- Projected bounds in the chassis-top frame; keep the existing 8.6-wide wheel / 25-long bumper envelope.
  local localCf=top:ToObjectSpace(p.CFrame)
  local e={}
  for i=1,3 do e[i]=0;for j=1,3 do e[i]+=math.abs(localCf.R[(i-1)*3+j])*d.size[j]/2 end end
  assert(math.abs(d.at[1])+e[1]<=4.3 and math.abs(d.at[3])+e[3]<=12.5 and d.at[2]+e[2]<=7, d.name.." expands bus")
  -- The right doorway is below y4.5 at z-9.6 ±1.5. No fixed art covers that space.
  if d.at[1]+e[1]>3.8 and d.at[2]-e[2]<4.5 then assert(math.abs(d.at[3]+9.6)>=1.5+e[3], d.name.." crosses boarding bay") end
 end
 assert(count<=40)
 model:Destroy();assert(model.Parent==nil)
 for _,seat in seats do assert(seat.Parent==bus.model) end
 bus.model:Destroy()
end
print("Bus livery compatibility PASS: actual bus hull, five seats, joints, size and boarding bay unchanged; four translated/rotated welded installations and cleanup")
'''
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('luau');ap.add_argument('--reference',type=Path);args=ap.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        tmp=Path(folder);prepare_modules(tmp)
        p=tmp/'Vehicles.luau';s=p.read_text();s='local Random={new=function() return {NextInteger=function(_,low,high) return low end} end}\n'+s;p.write_text(s)
        prefix='local M=require("./roblox-mock")\nlocal Instance,Vector3,Color3,CFrame,Enum,UDim2=M.Instance,M.Vector3,M.Color3,M.CFrame,M.Enum,M.UDim2\n'
        (tmp/'PolishBuilder.luau').write_text(prefix+(ROOT/'src/server/PolishArt/Builder.luau').read_text())
        (tmp/'BusLivery.luau').write_text((ROOT/'src/server/VehicleArt/BusLivery.luau').read_text().replace('require(script.Parent.Parent.PolishArt.Builder)','require("./PolishBuilder")'))
        (tmp/'bus-check.luau').write_text(RUNTIME)
        result=subprocess.run([str(Path(args.luau).resolve()),'bus-check.luau'],cwd=tmp,capture_output=True,text=True)
        assert result.returncode==0,result.stdout+result.stderr
        rows=result.stdout.splitlines()
        reference=json.loads(rows[0])
        if args.reference:
            args.reference.parent.mkdir(parents=True,exist_ok=True);args.reference.write_text(json.dumps(reference,separators=(',',':'))+'\n')
        print('\n'.join(rows[1:]))
if __name__=='__main__':main()
