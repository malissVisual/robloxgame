#!/usr/bin/env python3
"""Generate compact garage stage snapshots from the audited actual factory export. No asset uploads."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def catalog(models):
    colors=[];cache={};cars={}
    def color_index(c):
        key=tuple(round(n,4) for n in c)
        if key not in cache:cache[key]=len(colors)+1;colors.append(key)
        return cache[key]
    for m in models:
        if m['upgraded']:continue
        nodes={p['id']:p for p in m['parts']};texts={}
        factory=next(p['color'] for p in m['parts'] if p.get('attributes',{}).get('FleetFinish')=='paint')
        for p in m['parts']:
            if p['class']=='TextLabel' and p.get('text'):
                texts[nodes[p['parent']]['parent']]=p['text']
        parts=[]
        for p in m['parts']:
            if 'size' not in p or p['opacity']<.05:continue
            paint=p.get('attributes',{}).get('FleetFinish')=='paint' or (p['name'] in {'CarDoor','BackDoor'} and all(abs(a-b)<1e-6 for a,b in zip(p['color'],factory)))
            kind=2 if p['class']=='WedgePart' else 1 if p.get('shape')=='Cylinder' else 0
            row=[kind,*p['position'],*p['size'],*p['rotation'],color_index(p['color']),p['material'],p['opacity'],paint]
            if p['id'] in texts:row.append(texts[p['id']])
            parts.append([round(x,5) if isinstance(x,float) else x for x in row])
        cars[f"{m['id']}:{m['stage']}"]=parts
    assert len(cars)==20
    return {'colors':colors,'cars':cars}
def write(models,path):
    data=json.dumps(catalog(models),separators=(',',':'))
    path.write_text('''--!strict
-- Generated true stage geometry for garage ViewportFrames. Regenerate with tools/vehicle-preview/make_preview_data.py.
-- Lazy local JSON decode; no network, uploaded assets, remote requests or replicated preview Models.
local HttpService = game:GetService("HttpService")
local Data = {}
local decoded: any = nil
local source = [====['''+data+''']====]
function Data.get(carId: string, stage: number): (any?, any)
    if decoded == nil then decoded = HttpService:JSONDecode(source) end
    return decoded.cars[carId .. ":" .. tostring(stage)], decoded.colors
end
return Data
''')
    print('Garage snapshots:',len(catalog(models)['cars']),'stages;',len(data),'bytes')
if __name__=='__main__':write(json.loads(Path(sys.argv[1]).read_text()),ROOT/'src/shared/VehiclePreviewData.luau')
