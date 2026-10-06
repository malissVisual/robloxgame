#!/usr/bin/env python3
"""Run the real Roblox vehicle factory with a property recorder and export audited model data for renders/Studio."""
from pathlib import Path
import argparse,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def prepare_modules(tmp, vehicles_source=None):
    prefix='local Mock = require("./roblox-mock")\nlocal game, workspace, Instance, Vector3, Vector2, Color3, CFrame, Enum, PhysicalProperties, UDim2, typeof = Mock.game, Mock.workspace, Mock.Instance, Mock.Vector3, Mock.Vector2, Mock.Color3, Mock.CFrame, Mock.Enum, Mock.PhysicalProperties, Mock.UDim2, Mock.typeof\n'
    for name in ['Config','Economy','Map','Boarding']:
        s=(ROOT/'src/shared'/f'{name}.luau').read_text()
        s=re.sub(r'require\(script.Parent.(\w+)\)',r'require("./\1")',s)
        (tmp/f'{name}.luau').write_text(s)
    for name in ['Net','World','PlayerData']:(tmp/f'{name}.luau').write_text('return {}\n')
    (tmp/'DayNight.luau').write_text('local Mock=require("./roblox-mock")\nreturn {nightLight=Mock.nightLight}\n')
    for name,source in [('Vehicles',ROOT/'src/server/Vehicles.luau'),('Builder',ROOT/'src/server/VehicleArt/Builder.luau'),('Geometry',ROOT/'src/server/VehicleArt/Geometry.luau')]:
        s=vehicles_source if name=='Vehicles' and vehicles_source is not None else source.read_text()
        s=re.sub(r'require\(Shared.(\w+)\)',r'require("./\1")',s)
        s=re.sub(r'require\(script.Parent.(?:VehicleArt.)?(\w+)\)',r'require("./\1")',s)
        if name=='Vehicles':s=s.replace('return Vehicles','Vehicles.__testBuild = build\nVehicles.__testBuildKit = buildKit\nVehicles.__testStyle = styleFor\nreturn Vehicles')
        (tmp/f'{name}.luau').write_text(prefix+s)
    for name in ['roblox-mock','export']:(tmp/f'{name}.luau').write_text((HERE/f'{name}.luau').read_text())

def export(luau,output,vehicles_source=None):
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        prepare_modules(tmp, vehicles_source)
        result=subprocess.run([str(Path(luau).resolve()),'export.luau'],cwd=tmp,text=True,capture_output=True)
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    models=[json.loads(line) for line in result.stdout.splitlines()]
    assert len({m['id'] for m in models})==9
    output.mkdir(parents=True,exist_ok=True)
    (output/'fleet.json').write_text(json.dumps(models))
    print(f'Actual factory PASS: {len(models)} display builds; moving joints, weld targets, display anchoring and nonblocking skins verified')
    return models
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('luau');ap.add_argument('output',type=Path);args=ap.parse_args();export(args.luau,args.output)
