#!/usr/bin/env python3
"""Record the actual BuildingLooks Kit renderer, with a documented cutaway shell for architectural review."""
from pathlib import Path
import argparse,subprocess,tempfile,json
from export import ROOT
PREFIX='local M=require("./mock")\nlocal Instance,Vector3,Color3,CFrame,UDim2,Enum=M.Instance,M.Vector3,M.Color3,M.CFrame,M.UDim2,M.Enum\n'
def export(module,luau,output):
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/'mock.luau').write_text((ROOT/'tools/vehicle-preview/roblox-mock.luau').read_text())
        (tmp/'Kit.luau').write_text(PREFIX+(ROOT/'src/server/BuildingLooks/Kit.luau').read_text())
        (tmp/'Blueprint.luau').write_text(module.read_text().replace('require(script.Parent.Kit)','require("./Kit")'))
        # Use the same tested record/JSON helpers as the moving-prop exporter.
        from export import RUNNER
        helpers=RUNNER[RUNNER.index('local function encode'):RUNNER.index('for _,id in Geometry.ids')]
        (tmp/'run.luau').write_text('local Mock=require("./mock")\nlocal Kit=require("./Kit")\nlocal Blueprint=require("./Blueprint")\n'+helpers+'''
local function part(parent,name,size,cf,color,material)
 local p=Mock.Instance.new("Part");p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,color,material
 p.Anchored,p.Parent=true,parent;return p
end
local function deco(p) p.CanCollide,p.CanQuery,p.CanTouch,p.Massless=false,false,false,true;return p end
local parent=Mock.Instance.new("Folder")
local rendered=Kit.build(parent,Mock.CFrame.new(),Blueprint,{part=part,deco=deco,nightLight=Mock.nightLight})
local parts={}
for _,p in rendered:GetDescendants() do
 if p:IsA("BasePart") then assert(p.Anchored and p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch) end
 if p:IsA("BasePart") or p.ClassName=="SurfaceGui" or p.ClassName=="TextLabel" then table.insert(parts,record(p)) end
end
-- Preview-only floor and rear/right walls: the gameplay shell is Claude's responsibility.
for _,shell in {
 {"ReferenceFloor",{Blueprint.width,.15,Blueprint.depth},{0,-.08,0}},
 {"ReferenceBackWall",{Blueprint.width,Blueprint.height,.2},{0,Blueprint.height/2,Blueprint.depth/2}},
 {"ReferenceRightWall",{.2,Blueprint.height,Blueprint.depth},{Blueprint.width/2,Blueprint.height/2,0}},
} do
 local s,v=shell[2],shell[3]
 local p=part(parent,shell[1],Mock.Vector3.new(s[1],s[2],s[3]),Mock.CFrame.new(v[1],v[2],v[3]),Mock.Color3.fromRGB(65,72,73),"Concrete")
 local row=record(p);row.reference=true;table.insert(parts,row)
end
print(encode({id=Blueprint.id,blueprint=Blueprint,parts=parts}))
''')
        result=subprocess.run([str(Path(luau).resolve()),'run.luau'],cwd=tmp,text=True,capture_output=True)
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    model=json.loads(result.stdout)
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps([model]))
    print('Blueprint renderer PASS:',model['id'],len(model['blueprint']['details']),'details; context ensures massless nonblocking decoration')
    return model
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('module',type=Path);ap.add_argument('luau');ap.add_argument('output',type=Path);a=ap.parse_args();export(a.module,a.luau,a.output)
