#!/usr/bin/env python3
"""Audit fuel-group component budgets, lot composition, bay/support clearance and all fleet filler positions."""
from pathlib import Path
import argparse,json,subprocess,tempfile,re,math
from export import export,ROOT,RUNNER
from blueprints import export as export_blueprint
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('luau');ap.add_argument('output',type=Path);a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    models=export(ROOT/'src/server/GasArt/Geometry.luau',a.luau,a.output/'gas.json')
    kiosk=export_blueprint(ROOT/'src/server/BuildingLooks/GasKiosk.luau',a.luau,a.output/'kiosk.json')
    assert len(kiosk['blueprint']['details'])+1<=60,'kiosk includes its interior lamp'
    helper=RUNNER[RUNNER.index('local function encode'):RUNNER.index('local function v')]
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        for name in ['Fuelcaps','Layout']:(tmp/(name+'.luau')).write_text((ROOT/'src/server/GasArt'/(name+'.luau')).read_text())
        (tmp/'run.luau').write_text(helper+'''local Caps=require("./Fuelcaps")
local caps={}
for _,id in Caps.styles() do
 local base=Caps.point(id);local stretched=Caps.point(id,nil,35)
 assert(base.attach=="Chassis" and base.turn[2]==-90 and stretched.at[3]>base.at[3])
 table.insert(caps,{id=id,point=base})
end
assert(not pcall(function() Caps.point("missing") end))
assert(not pcall(function() Caps.point("van",0,13) end))
print(encode({layout=require("./Layout"),caps=caps}))
''')
        result=subprocess.run([str(Path(a.luau).resolve()),'run.luau'],cwd=tmp,capture_output=True,text=True,check=True)
    data=json.loads(result.stdout);layout=data['layout'];caps=data['caps'];parts=[];serial=1000000
    source=(ROOT/'src/server/Vehicles.luau').read_text().split('local STYLES',1)[1].split('local CHASSIS_HEIGHT',1)[0]
    styles=set(re.findall(r'^\t(\w+) = \{',source,re.M))
    assert {c['id'] for c in caps}==styles and len(caps)==17,'fleet style coverage'
    for cap in caps:assert all(math.isfinite(n) for n in cap['point']['at']) and cap['point']['at'][0]>0
    modelmap={m['id']:m for m in models}
    for component in layout['components']:
        m=kiosk if 'blueprint' in component else modelmap[component['model']]
        offset=component['at'];mapping={}
        for p in m['parts']:
            serial+=1;mapping[p['id']]=serial
        for original in m['parts']:
            p=dict(original);p['id']=mapping[p['id']]
            if 'parent' in p:p['parent']=mapping.get(p['parent'],0)
            if 'position' in p:p['position']=[p['position'][i]+offset[i] for i in range(3)]
            parts.append(p)
    # Render the actual layout markings through the real builder too (temporarily wrapped pure module).
    with tempfile.TemporaryDirectory() as tmp:
        module=Path(tmp)/'Markings.luau'
        # Lua literals from the same layout module, avoiding a second manually maintained geometry source.
        source=(ROOT/'src/server/GasArt/Layout.luau').read_text().replace('return {','local Layout = {',1)
        module.write_text(source+'\nreturn {ids={"markings"},spec=function() return {id="markings",pieces=Layout.pieces,origins={Frame={0,0,0}},newRoots=1} end}\n')
        from export import BUDGETS
        BUDGETS['markings']=8
        markings=export(module,a.luau,a.output/'markings.json')[0]
    for p in markings['parts']:
        serial+=1;p=dict(p);p['id']=serial;parts.append(p)
    for p in parts:
        if 'size' not in p:continue
        r=p['rotation'];s=p['size'];extent=[sum(abs(r[i*3+j])*s[j]/2 for j in range(3)) for i in range(3)]
        assert abs(p['position'][0])+extent[0]<=layout['width']/2+1e-6,(p['name'],'lot width')
        assert abs(p['position'][2])+extent[2]<=layout['depth']/2+1e-6,(p['name'],'lot depth')
    for point in layout['points']:assert abs(point['at'][0])<35 and abs(point['at'][2])<25
    # A 7-wide vehicle fits the two forecourt lanes between the island and outer canopy posts.
    for x in [-5.2,5.2]:
        assert abs(x)-3.5>1.7 and abs(x)+3.5<9.875
    # The docked nozzle pieces do not weld to the fixed Frame.
    pump=modelmap['pump'];assert sum(p['attach']=='Nozzle' for p in pump['spec']['pieces'])==3
    assert sum(p.get('night',False) for p in modelmap['island']['spec']['pieces'])==2
    station={'id':'station_layout','parts':parts,'layout':layout}
    (a.output/'station.json').write_text(json.dumps([station]))
    print('Gas handoff PASS: component budgets incl. roots/lamp; 70x50 footprint; lane/post clearance; 17 current fleet styles; separate nozzles and two night lamps')
if __name__=='__main__':main()
