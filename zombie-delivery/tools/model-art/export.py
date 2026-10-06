#!/usr/bin/env python3
"""Execute pure geometry and the real decorative builder; audit budgets and export exact native pieces for renders."""
from pathlib import Path
import argparse,json,math,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).parent
BUDGETS={'backpack':14,'backpack_loaded':14,'bigpack':18,'shoes':12,'jacket':16,'cart':22,'phone':6,
         'rustbike':70,'citybike':70,'cargobike':70,'cargobike_loaded':70,'ebike':70,'basket':10,'panniers':12,'trailer':25,'bell':3,'light':4,
         'pump':25,'island':70,'pricesign':12,'jerrycan':8}
RUNNER='''local Mock=require("./mock")
local Geometry=require("./Geometry")
local Builder=require("./Builder")
local function encode(v)
 if type(v)=="string" then return string.format("%q",v) end
 if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
 if type(v)=="table" then
  local out={}
  if #v>0 then for _,x in v do table.insert(out,encode(x)) end;return "["..table.concat(out,",").."]" end
  for k,x in v do table.insert(out,encode(k)..":"..encode(x)) end;return "{"..table.concat(out,",").."}"
 end
 error("Unserializable art data")
end
local function v(a) return {a.X,a.Y,a.Z} end
local function record(p)
 local data={id=p.uid,name=p.Name,class=p.ClassName}
 if p.Parent then data.parent=p.Parent.uid end
 if p:IsA("BasePart") then
  data.position=v(p.Position);data.rotation=p.CFrame.R;data.size=v(p.Size);data.color={p.Color.R,p.Color.G,p.Color.B}
  data.material=p.Material;data.shape=p.Shape or "Block";data.opacity=1-p.Transparency
 elseif p.ClassName=="TextLabel" then data.text=p.Text end
 return data
end
for _,id in Geometry.ids do
 local spec=Geometry.spec(id)
 local parent=Mock.Instance.new("Folder");local targets={}
 for name,at in spec.origins do
  local root=Mock.Instance.new("Part");root.Name=name;root.CFrame=Mock.CFrame.new(at[1],at[2],at[3]);root.Parent=parent
  targets[name]=root
 end
 local built=Builder.build(parent,spec,targets)
 assert(#built.parts==#spec.pieces and #built.points==#(spec.attachments or {}))
 for n,p in built.parts do
  local d=spec.pieces[n];local target=targets[d.attach]
  assert(p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch and not p.Anchored)
  assert(p.CastShadow==(d.shadow==true))
  local weld=p:FindFirstChild("ArtWeld");assert(weld and weld.Part0==target and weld.Part1==p)
  assert(p.CFrame.Position.X==target.Position.X+d.at[1] and p.CFrame.Position.Y==target.Position.Y+d.at[2] and p.CFrame.Position.Z==target.Position.Z+d.at[3])
  if d.textSlot then assert(p:FindFirstChild("ArtLabel"):FindFirstChild(d.textSlot).Text==d.text) end
 end
 local parts={}
 for _,p in built.model:GetDescendants() do if p:IsA("BasePart") or p.ClassName=="SurfaceGui" or p.ClassName=="TextLabel" then table.insert(parts,record(p)) end end
 -- Caller roots are not exported as visible parts. Budget checks include the declared number of new hidden roots.
 print(encode({id=id,spec=spec,parts=parts,camera=spec.camera or "front"}))
 Builder.destroy(built)
 assert(built.model.Parent==nil)
 for _,point in built.points do assert(point.Parent==nil) end
 for _,target in targets do assert(#target:GetChildren()==0) end
 -- Anchored review roots hold their welded skin; the skin itself must never freeze a later unanchored rig.
 for _,target in targets do target.Anchored=true end
 local display=Builder.build(parent,spec,targets)
 for _,p in display.parts do assert(not p.Anchored) end
 Builder.destroy(display)
 for _,target in targets do assert(#target:GetChildren()==0 and target.Anchored) end
 -- A missing target fails before any partial art model is created.
 local before=#parent:GetChildren()
 assert(not pcall(function() Builder.build(parent,spec,{}) end))
 assert(#parent:GetChildren()==before)
end
'''
def export(module,luau,output):
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/'Geometry.luau').write_text(module.read_text())
        (tmp/'mock.luau').write_text((ROOT/'tools/vehicle-preview/roblox-mock.luau').read_text())
        prefix='local M=require("./mock")\nlocal Instance,Vector3,Color3,CFrame,UDim2,Enum=M.Instance,M.Vector3,M.Color3,M.CFrame,M.UDim2,M.Enum\n'
        (tmp/'Builder.luau').write_text(prefix+(ROOT/'src/server/ModelArt/Builder.luau').read_text())
        (tmp/'run.luau').write_text(RUNNER)
        run=subprocess.run([str(Path(luau).resolve()),'run.luau'],cwd=tmp,capture_output=True,text=True)
        if run.returncode:raise RuntimeError(run.stdout+run.stderr)
    models=[json.loads(line) for line in run.stdout.splitlines()]
    assert len({m['id'] for m in models})==len(models)
    for m in models:
        spec=m['spec'];pieces=spec['pieces'];count=len(pieces)+spec.get('newRoots',0)+spec.get('reservedParts',0)
        assert count<=BUDGETS[m['id']],(m['id'],count,'part budget')
        assert len({p['name'] for p in pieces})==len(pieces)
        for p in pieces:
            for key in ['size','at']:
                assert len(p[key])==3 and all(isinstance(x,(int,float)) and math.isfinite(x) for x in p[key])
            assert min(p['size'])>=.02 and max(p['size'])<=2048
            assert p.get('shape','Block') in ['Block','Cylinder','Wedge']
            if p.get('shape')=='Cylinder':assert abs(p['size'][1]-p['size'][2])<1e-6,(m['id'],p['name'],'cylinder must have circular cross section; axis X')
            assert p['attach'] in spec['origins']
        points=spec.get('attachments',[])
        if isinstance(points,dict):points=[]
        assert len({p['name'] for p in points})==len(points)
        for p in points:assert p['attach'] in spec['origins'] and all(math.isfinite(x) for x in p['at'])
        if m['id']=='shoes':
            for foot in ['LeftFoot','RightFoot']:assert sum(p['attach']==foot for p in pieces)<=6
        if m['id'] in ['backpack','backpack_loaded','bigpack']:
            for p in pieces:assert abs(p['at'][0])+p['size'][0]/2<=1 and p['at'][1]-p['size'][1]/2>=-1.12,(m['id'],'arm/hip envelope')
        if m['id'] in ['rustbike','citybike','cargobike','cargobike_loaded','ebike']:
            assert spec.get('reservedParts',0)>=2,'bike budget must reserve a seat and stable collider'
            named={p['name']:p for p in points}
            assert {'Saddle','LeftGrip','RightGrip','LeftPedal','RightPedal','FrontAxle','RearAxle','CrankAxis','BasketMount','PannierMount','Hitch'}<=named.keys()
            assert sum(p['name'].endswith('Tyre') for p in pieces)==2
            assert all(named[n]['attach']=='Crank' for n in ['LeftPedal','RightPedal'])
            if m['id'].startswith('cargobike'):assert {'Slot'+str(i) for i in range(1,7)}<=named.keys()
        if m['id'] in ['basket','panniers','trailer']:assert any(p['name']=='Slot1' for p in points)
        if m['id']=='pump':assert any(p['attach']=='Nozzle' for p in pieces) and any(p['name']=='FuelOutlet' for p in points)
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(models))
    print('Art factory PASS:',{m['id']:len(m['spec']['pieces'])+m['spec'].get('newRoots',0)+m['spec'].get('reservedParts',0) for m in models})
    print('Real builder: nonblocking/massless flags, target welds, local frames, labels, missing-target atomicity and cleanup PASS')
    return models
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('module',type=Path);ap.add_argument('luau');ap.add_argument('output',type=Path);a=ap.parse_args();export(a.module.resolve(),a.luau,a.output)
