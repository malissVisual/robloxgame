"""Assemble 47 factory exports and eight representative reward illustrations for Blender.
Reward primitives are review art, not new game factories. No gameplay sources are changed.
"""
import argparse
import json
from pathlib import Path

IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1]

def representative(key):
    return {'id': key, 'parts': [], 'source': 'representative-art'}

def part(model, name, size, at, color, shape='Block', material='SmoothPlastic'):
    model['parts'].append({'id': len(model['parts'])+1, 'name': name, 'class': 'Part',
        'size': size, 'position': at, 'rotation': IDENTITY, 'color': [v/255 for v in color],
        'shape': shape, 'material': material, 'opacity': 1})


def rewards():
    red=(176,46,43); steel=(145,151,151); black=(25,28,31); cream=(222,226,215)
    out=[]
    m=representative('cash:money')
    for i in range(6): part(m,'Banknotes',(2.9,.075,1.4),(0,.1+i*.083,0),(107+i*3,130+i*3,107))
    part(m,'Paper band',(.48,.52,1.46),(0,.32,0),cream)
    out.append(m)
    m=representative('item:medkit')
    part(m,'Case',(2.1,1.4,.75),(0,.7,0),red)
    part(m,'Cross vertical',(.27,.84,.025),(0,.73,-.388),cream)
    part(m,'Cross horizontal',(.8,.27,.025),(0,.73,-.39),cream)
    part(m,'Handle',(1.1,.17,.28),(0,1.55,0),black)
    for x in [-.47,.47]:part(m,'Handle base',(.16,.3,.28),(x,1.45,0),black)
    out.append(m)
    m=representative('item:repair')
    part(m,'Toolbox',(2.25,1,1.05),(0,.5,0),red)
    part(m,'Lid',(2.3,.2,1.12),(0,1.1,0),black)
    part(m,'Handle',(1.2,.14,.18),(0,1.43,0),steel,material='Metal')
    for x in [-.55,.55]:part(m,'Handle feet',(.12,.25,.18),(x,1.31,0),steel,material='Metal')
    for x in [-.64,.64]:part(m,'Latches',(.22,.35,.08),(x,.98,-.58),steel,material='Metal')
    out.append(m)
    m=representative('item:molotov')
    # Cylinder axis is Roblox local X; rotate upright.
    part(m,'Bottle',(1.9,.75,.75),(0,1,0),(99,74,38),'Cylinder')
    m['parts'][-1]['rotation']=[0,-1,0,1,0,0,0,0,1]
    part(m,'Bottle neck',(.42,.68,.42),(0,2.19,0),(103,77,42))
    part(m,'Unlit cloth',(.27,.8,.12),(.1,2.7,0),cream)
    part(m,'Label',(.63,.57,.035),(0,1.12,-.39),(155,136,98))
    out.append(m)
    m=representative('item:mine')
    part(m,'Body',(.35,1.7,1.7),(0,.23,0),(73,82,57),'Cylinder',material='Metal')
    m['parts'][-1]['rotation']=[0,-1,0,1,0,0,0,0,1]
    part(m,'Pressure cap',(.2,.75,.75),(0,.5,0),(92,104,72),'Cylinder',material='Metal')
    m['parts'][-1]['rotation']=[0,-1,0,1,0,0,0,0,1]
    out.append(m)
    m=representative('item:nitro')
    part(m,'Nitro tank',(2.05,.8,.8),(0,1.08,0),(36,92,154),'Cylinder',material='Metal')
    m['parts'][-1]['rotation']=[0,-1,0,1,0,0,0,0,1]
    part(m,'Valve',(.28,.4,.28),(0,2.23,0),steel,material='Metal')
    part(m,'Valve cross',(.66,.1,.1),(0,2.46,0),red)
    part(m,'Strap',(.84,.22,.84),(0,.84,0),black)
    out.append(m)
    for title in ['Iron Courier','Legend of the Last Road']:
        m=representative('title:'+title)
        part(m,'Credential',(3.2,1.9,.1),(0,1,0),black)
        part(m,'Dispatch red stripe',(.12,1.9,.025),(-1.48,1,-.065),red)
        m['texts']=[{'text':'ZDC / CAREER','at':[0,1.5,-.073],'size':.17},
                    {'text':title.upper().replace(' OF THE ','\nOF THE '),'at':[0,1,-.073],'size':.21}]
        out.append(m)
    return out


def assemble(native, kit, gear):
    models=json.loads(native.read_text())
    for path,prefix,wanted in [(kit,'kit',{'backpack','shoes','bigpack','jacket'}),(gear,'gear',{'basket','panniers','trailer'})]:
        for m in json.loads(path.read_text()):
            if m['id'] in wanted:
                m['id']=prefix+':'+m['id'];m['source']='actual-factory';models.append(m)
    models.extend(rewards())
    assert len(models)==55 and len({m['id'] for m in models})==55
    return models

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for key in ['native','kit','gear','output']:p.add_argument(key,type=Path)
    a=p.parse_args();a.output.write_text(json.dumps(assemble(a.native,a.kit,a.gear)))
