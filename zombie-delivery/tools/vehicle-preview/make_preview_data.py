#!/usr/bin/env python3
"""Generate compact garage stage snapshots from the audited actual factory export. No asset uploads."""
import json,re,sys
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
def dump(value):
    return json.dumps(value,separators=(',',':'))
def source(data):
    """The Luau module: one JSON string per car stage (decoded only when the garage shows it) and the shared colours."""
    rows=''.join(f'\t["{key}"] = [====[{dump(parts)}]====],\n' for key,parts in data['cars'].items())
    return '''--!strict
-- Generated true stage geometry for garage ViewportFrames. Regenerate with tools/vehicle-preview/make_preview_data.py.
-- One JSON string per car stage, decoded locally only when the garage shows that stage (then kept); no network,
-- uploaded assets, remote requests or replicated preview Models.
local HttpService = game:GetService("HttpService")
local Data = {}
local COLORS = [====['''+dump(data['colors'])+''']====]
local CARS: { [string]: string } = {
'''+rows+'''}
local colors: any = nil
local decoded: { [string]: any } = {}
function Data.get(carId: string, stage: number): (any?, any)
	local key = carId .. ":" .. tostring(stage)
	local text = CARS[key]
	if text == nil then
		return nil, nil
	end
	if colors == nil then
		colors = HttpService:JSONDecode(COLORS)
	end
	local rows = decoded[key]
	if rows == nil then
		rows = HttpService:JSONDecode(text)
		decoded[key] = rows
	end
	return rows, colors
end
return Data
'''
def parse(text):
    """The catalog a generated module holds (for the checker)."""
    colors=json.loads(text.split('local COLORS = [====[',1)[1].split(']====]',1)[0])
    cars={key:json.loads(body) for key,body in re.findall(r'\t\["([^"]+)"\] = \[====\[(.*?)\]====\],\n',text)}
    return {'colors':colors,'cars':cars}
def write(models,path):
    data=catalog(models)
    text=source(data)
    assert parse(text)==json.loads(dump(data)),'generated module does not round-trip'
    path.write_text(text)
    largest=max(len(dump(parts)) for parts in data['cars'].values())
    print('Garage snapshots:',len(data['cars']),'stages;',len(text),'bytes; largest single decode',largest,'bytes')
if __name__=='__main__':write(json.loads(Path(sys.argv[1]).read_text()),ROOT/'src/shared/VehiclePreviewData.luau')
