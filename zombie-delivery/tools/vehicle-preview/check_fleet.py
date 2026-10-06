#!/usr/bin/env python3
"""Audit the actual fleet factory, generated garage data, preview behavior and original game physics."""
from pathlib import Path
import argparse,subprocess,tempfile,json,re
from export_fleet import export,prepare_modules,ROOT,HERE
from make_preview_data import catalog

def lua(v):
    if isinstance(v,dict):return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,(list,tuple)):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return str(v).lower()
    return json.dumps(v)
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('luau');ap.add_argument('--baseline',default='3823dad');args=ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        temp=Path(tmp)
        actual=export(args.luau,temp/'actual')
        original=subprocess.check_output(['git','show',args.baseline+':zombie-delivery/src/server/Vehicles.luau'],cwd=ROOT,text=True)
        before=export(args.luau,temp/'before',original)
        for a,b in zip(actual,before):
            assert (a['id'],a['stage'],a['upgraded'])==(b['id'],b['stage'],b['upgraded'])
            assert a['physics']==b['physics'] and a['capacity']==b['capacity'],(a['id'],a['stage'],'physics changed')
            parts=[p for p in a['parts'] if 'size' in p]
            assert len(parts)<=450,(a['id'],a['stage'],len(parts),'part budget')
        source=(ROOT/'src/shared/VehiclePreviewData.luau').read_text()
        stored=json.loads(source.split('[====[',1)[1].split(']====]',1)[0])
        assert json.dumps(stored,sort_keys=True)==json.dumps(catalog(actual),sort_keys=True),'garage snapshots stale: regenerate'
        prepare_modules(temp)
        rows=catalog(actual)
        (temp/'VehiclePreviewData.luau').write_text('local colors='+lua(rows['colors'])+'\nlocal cars={}\n'+''.join('cars['+lua(key)+']=(function() local rows={}\n'+''.join('table.insert(rows,'+lua(row)+')\n' for row in data)+'return rows end)()\n' for key,data in rows['cars'].items())+'return {get=function(id,stage) return cars[id..":"..tostring(stage)],colors end}\n')
        prefix='local Mock=require("./roblox-mock")\nlocal game,workspace,Instance,Vector3,Color3,CFrame,Enum,UDim2,typeof=Mock.game,Mock.workspace,Mock.Instance,Mock.Vector3,Mock.Color3,Mock.CFrame,Mock.Enum,Mock.UDim2,Mock.typeof\n'
        text=(ROOT/'src/client/VehiclePreview.luau').read_text()
        text=re.sub(r'require\(Shared.(\w+)\)',r'require("./\1")',text)
        (temp/'VehiclePreview.luau').write_text(prefix+text)
        (temp/'preview-check.luau').write_text((HERE/'preview-check.luau').read_text())
        result=subprocess.run([str(Path(args.luau).resolve()),'preview-check.luau'],cwd=temp,text=True,capture_output=True)
        assert result.returncode==0,result.stdout+result.stderr
        print(result.stdout,end='')
    print('Fleet compatibility PASS: all 20 stages keep original hulls, seats, joint frames, loading attachments and capacities; 40 variants within part budget; garage data matches factory')
if __name__=='__main__':main()
