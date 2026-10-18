#!/usr/bin/env python3
"""Run the real Roblox vehicle factory with a property recorder and export audited model data for renders/Studio.

10.6 (only the sandbox is the game): the factory builds one van, the ZDC Sprinter (Config.Sandbox.Van); fleet.json holds
its display build (tools/sandbox-map/render.py, tools/countryside/views.py draw it)."""
from pathlib import Path
import argparse,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def prepare_modules(tmp, vehicles_source=None):
    prefix='local Mock = require("./roblox-mock")\nlocal game, workspace, Instance, Vector3, Vector2, Color3, CFrame, Enum, PhysicalProperties, UDim2, typeof = Mock.game, Mock.workspace, Mock.Instance, Mock.Vector3, Mock.Vector2, Mock.Color3, Mock.CFrame, Mock.Enum, Mock.PhysicalProperties, Mock.UDim2, Mock.typeof\n'
    for name in ['Config','RenderBudget','CarUpright','SpawnSpot','SprinterLooks']: # (6.13.1: RenderBudget, the van's shadows; 6.26: SpawnSpot, the spawn's room, and its CarUpright; 8.0: SprinterLooks, the ZDC Sprinter's look)
        s=(ROOT/'src/shared'/f'{name}.luau').read_text()
        s=re.sub(r'require\(script.Parent.(\w+)\)',r'require("./\1")',s)
        (tmp/f'{name}.luau').write_text(s)
    for name in ['Net','PlayerData']:(tmp/f'{name}.luau').write_text('return {}\n')
    (tmp/'DayNight.luau').write_text('local Mock=require("./roblox-mock")\nreturn {nightLight=Mock.nightLight}\n')
    s=vehicles_source if vehicles_source is not None else (ROOT/'src/server/Vehicles.luau').read_text()
    s=re.sub(r'require\(Shared.(\w+)\)',r'require("./\1")',s)
    s=re.sub(r'require\(script.Parent.(\w+)\)',r'require("./\1")',s)
    s=re.sub(r'^return Vehicles$','Vehicles.__testBuild = build\nVehicles.__testStyle = STYLE\nVehicles.__testWheels = wheelsOf\nreturn Vehicles',s,flags=re.M)
    (tmp/'Vehicles.luau').write_text(prefix+s)
    for name in ['roblox-mock','export']:(tmp/f'{name}.luau').write_text((HERE/f'{name}.luau').read_text())

def export(luau,output,vehicles_source=None):
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        prepare_modules(tmp, vehicles_source)
        result=subprocess.run([str(Path(luau).resolve()),'export.luau'],cwd=tmp,text=True,capture_output=True)
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    models=[json.loads(line) for line in result.stdout.splitlines()]
    assert [m['id'] for m in models]==['sprinter'] # (10.6: the one van)
    output.mkdir(parents=True,exist_ok=True)
    (output/'fleet.json').write_text(json.dumps(models))
    print(f'Actual factory PASS: {len(models)} display build; moving joints, weld targets, display anchoring and nonblocking skins verified')
    return models
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('luau');ap.add_argument('output',type=Path);args=ap.parse_args();export(args.luau,args.output)
