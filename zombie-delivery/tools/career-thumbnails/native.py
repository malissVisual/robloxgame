"""Record real vehicle, bike, mounted gear and gun factories for Career thumbnail renders."""
import argparse
import importlib.util
import json
import re
import subprocess
import tempfile
from pathlib import Path

from inventory import ROOT, ENCODE


def native(luau, output):
    spec = importlib.util.spec_from_file_location("fleet_export", ROOT / "tools/vehicle-preview/export_fleet.py")
    fleet = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fleet)
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        fleet.prepare_modules(tmp)
        prefix = '''local M=require("./roblox-mock")
local Instance,Vector3,Color3,CFrame,Enum=M.Instance,M.Vector3,M.Color3,M.CFrame,M.Enum
'''
        (tmp / "GunModels.luau").write_text(prefix + (ROOT / "src/shared/GunModels.luau").read_text())
        (tmp / "Native.luau").write_text(ENCODE + '''local M=require("./roblox-mock")
local Vehicles=require("./Vehicles")
local Config=require("./Config")
local Economy=require("./Economy")
local Guns=require("./GunModels")
local function triple(v) return {v.X,v.Y,v.Z} end
local function record(root,id)
 local pieces={}
 for _,p in root:GetDescendants() do
  if p:IsA("BasePart") and p.Transparency<0.95 then
   table.insert(pieces,{id=p.uid,name=p.Name,class=p.ClassName,size=triple(p.Size),
    position=triple(p.Position),rotation=p.CFrame.R,color={p.Color.R,p.Color.G,p.Color.B},
    material=p.Material,opacity=1-p.Transparency,shape=p.Shape or "Block"})
  end
 end
 assert(#pieces>0,id..": no visible geometry")
 return {id=id,parts=pieces,source="actual-factory"}
end
local function emit(model,id)
 print(encode(record(model,id)))
 model:Destroy()
end
for _,def in Config.Cars do
 if not def.company then
  local kind=if def.bike then "bike" else "car"
  emit(Vehicles.displayModel(def,M.CFrame.identity,0),kind..":"..def.id)
  if not def.bike then
   for stage=1,Economy.maxStage(def.id) do
    emit(Vehicles.displayModel(def,M.CFrame.identity,stage),"stage:"..def.id..":"..stage)
   end
  end
 end
end
local van=Economy.findCar("van")
local function signature(p)
 return p.Name.."|"..encode({triple(p.Size),triple(p.Position),p.CFrame.R,{p.Color.R,p.Color.G,p.Color.B}})
end
for _,id in {"trolley","straps","cooler","roofrack"} do
 local carrier=if id=="roofrack" then Economy.findCar("courier") else van
 local stage=if id=="roofrack" then 0 else 3
 assert(Economy.gearFits(carrier.id,id))
 local before=Vehicles.displayModel(carrier,M.CFrame.identity,stage,{}, {})
 local original={}
 for _,p in before:GetDescendants() do if p:IsA("BasePart") then original[signature(p)]=true end end
 local after=Vehicles.displayModel(carrier,M.CFrame.identity,stage,{}, {[id]=true})
 local isolated=M.Instance.new("Model")
 local found={}
 for _,p in after:GetDescendants() do
  if p:IsA("BasePart") and not original[signature(p)] and p.Transparency<0.95 then
   table.insert(found,p)
  end
 end
 for _,p in found do p.Parent=isolated end
 emit(isolated,"gear:"..id)
 before:Destroy();after:Destroy()
end
for _,def in Config.Weapons do
 if not def.earned and not def.exclusive then
  local hand=M.Instance.new("Part")
  assert(Guns.has(def.id))
  local gun=Guns.build(def.id,hand,M.CFrame.identity,1)
  for _,p in gun:GetDescendants() do
   if p:IsA("BasePart") then assert(p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch) end
  end
  emit(gun,"gun:"..def.id);hand:Destroy()
 end
end
local armored=Economy.findCar("armorvan")
for _,def in Config.CarGuns do
 local built=Vehicles.__testBuild(armored,M.Color3.fromRGB(unpack(armored.color)),M.CFrame.identity,true,def.id)
 local turret=built.model:FindFirstChild("CarGun")
 assert(turret and turret:GetAttribute("Gun")==def.id)
 print(encode(record(turret,"cargun:"..def.id)))
 built.model:Destroy()
end
for _,paint in Config.Paints do
 if paint.id=="hivis" or paint.id=="legend" then
  emit(Vehicles.displayModel(van,M.CFrame.identity,3,nil,nil,M.Color3.fromRGB(unpack(paint.color))),"paint:"..paint.id)
 end
end
''')
        result = subprocess.run([str(Path(luau).resolve()), "Native.luau"], cwd=tmp,
                                text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(result.stdout[-2000:] + result.stderr)
    models = [json.loads(line) for line in result.stdout.splitlines()]
    assert len({m["id"] for m in models}) == len(models)
    output.write_text(json.dumps(models))
    print("Native actual-factory models:", len(models))
    return models


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("luau")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    native(args.luau, args.output)
