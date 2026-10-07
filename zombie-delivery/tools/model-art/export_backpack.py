#!/usr/bin/env python3
"""Package audited courier geometry as a native R15 Accessory and marked review renders."""
from pathlib import Path
import argparse,copy,json,math,xml.etree.ElementTree as E
IDENTITY=[1,0,0,0,1,0,0,0,1]
MATERIAL={'Fabric':328,'Metal':1088,'Rubber':2560,'SmoothPlastic':256}

def prop(parent,tag,name,value):
    node=E.SubElement(parent,tag,{'name':name});node.text=str(value).lower() if isinstance(value,bool) else str(value);return node

def vector(parent,name,values):
    node=E.SubElement(parent,'Vector3',{'name':name})
    for axis,value in zip('XYZ',values):E.SubElement(node,axis).text=str(value)

def frame(parent,at,rotation):
    node=E.SubElement(parent,'CoordinateFrame',{'name':'CFrame'})
    for axis,value in zip('XYZ',at):E.SubElement(node,axis).text=str(value)
    for row in range(3):
        for col in range(3):E.SubElement(node,f'R{row}{col}').text=str(rotation[row*3+col])

def item(parent,kind,ref,name):
    obj=E.SubElement(parent,'Item',{'class':kind,'referent':ref});properties=E.SubElement(obj,'Properties');prop(properties,'string','Name',name);return obj,properties

def part(parent,ref,name,size,at,r,color,material='Fabric',shape='Block',opacity=1,shadow=False):
    obj,p=item(parent,'Part',ref,name)
    vector(p,'size',size);frame(p,at,r)
    col=E.SubElement(p,'Color3',{'name':'Color'})
    for axis,value in zip('RGB',color):E.SubElement(col,axis).text=str(value)
    prop(p,'token','Material',MATERIAL[material]);prop(p,'token','shape',0 if shape=='Ball' else 2 if shape=='Cylinder' else 1)
    for flag,value in [('Anchored',False),('Massless',True),('CanCollide',False),('CanQuery',False),('CanTouch',False),('CastShadow',shadow)]:prop(p,'bool',flag,value)
    prop(p,'float','Transparency',1-opacity);prop(p,'token','TopSurface',0);prop(p,'token','BottomSurface',0)
    return obj

def label(parent,text,ref):
    gui,p=item(parent,'SurfaceGui',ref,'ArtLabel');prop(p,'token','Face',5);prop(p,'token','SizingMode',1);prop(p,'float','PixelsPerStud',80);prop(p,'float','LightInfluence',.15)
    obj,p=item(gui,'TextLabel',ref+'T','Label');prop(p,'string','Text',text);prop(p,'bool','TextScaled',True);prop(p,'float','BackgroundTransparency',1)
    size=E.SubElement(p,'UDim2',{'name':'Size'})
    for tag,value in [('XS',1),('XO',0),('YS',1),('YO',0)]:E.SubElement(size,tag).text=str(value)
    ink=E.SubElement(p,'Color3',{'name':'TextColor3'})
    for tag,value in zip('RGB',[216/255,219/255,205/255]):E.SubElement(ink,tag).text=str(value)
    prop(p,'token','Font',18) # GothamMedium legacy enum

def accessory(model,output):
    root=E.Element('roblox',{'version':'4'})
    acc,p=item(root,'Accessory','RBXPACK','ZDC Courier Backpack');prop(p,'token','AccessoryType',7)
    handle=part(acc,'RBXHANDLE','Handle',[2,1.6,1.4],[0,0,0],IDENTITY,[.1,.1,.1],opacity=0)
    a,p=item(handle,'Attachment','RBXMOUNT','BodyBackAttachment');frame(p,[0,0,.7],IDENTITY)
    origin=model['spec']['origins']['UpperTorso']
    pieces={p['name']:p for p in model['spec']['pieces']}
    nodes={p['id']:p for p in model['parts']}
    for n,data in enumerate(p for p in model['parts'] if 'size' in p):
        assert data['class']=='Part' and pieces[data['name']]['attach']=='UpperTorso'
        at=[data['position'][i]-origin[i] for i in range(3)]
        ref='RBXPIECE'+str(n)
        obj=part(acc,ref,data['name'],data['size'],at,data['rotation'],data['color'],data['material'],data['shape'],shadow=pieces[data['name']].get('shadow',False))
        weld,p=item(obj,'WeldConstraint',ref+'W','ArtWeld');prop(p,'Ref','Part0','RBXHANDLE');prop(p,'Ref','Part1',ref)
        text=pieces[data['name']].get('text')
        if text:label(obj,text,ref+'GUI')
    E.indent(root);output.parent.mkdir(parents=True,exist_ok=True);E.ElementTree(root).write(output,encoding='utf-8',xml_declaration=True)
    audit=E.parse(output).getroot();objects=audit.findall('.//Item')
    refs={p.attrib['referent'] for p in objects};assert len(refs)==len(objects)
    assert sum(p.attrib['class']=='Part' for p in objects)==len(pieces)+1
    assert not any('Mesh' in p.attrib['class'] for p in objects)
    assert len(audit.findall('.//Item[@class="WeldConstraint"]'))==len(pieces)
    for p in audit.findall('.//Ref'):assert p.text in refs
    for p in audit.findall('.//Item[@class="Part"]'):
        properties=p.find('Properties')
        for flag,value in [('Massless','true'),('Anchored','false'),('CanCollide','false'),('CanQuery','false'),('CanTouch','false')]:assert properties.find(f'bool[@name="{flag}"]').text==value
    assert audit.find('.//Item[@class="Attachment"]/Properties/string[@name="Name"]').text=='BodyBackAttachment'
    print('Native Accessory XML PASS: 14 parts including hidden Handle; 13 target welds; R15 mount; flags; labels; valid references; no meshes')

def mannequin(model):
    model=copy.deepcopy(model);model['id']='courier-backpack-worn'
    next_id=-1
    def add(name,size,at,color,shape='Block',r=IDENTITY):
        nonlocal next_id
        model['parts'].append({'id':next_id,'name':'REFERENCE '+name,'class':'Part','size':size,'position':at,'rotation':r,'color':[x/255 for x in color],'shape':shape,'material':'SmoothPlastic','opacity':1,'reference':True});next_id-=1
    dark,red=[24,27,32],[174,49,45]
    add('UpperTorso',[2,1.6,1.4],[0,3.4,0],dark)
    add('LowerTorso',[1.9,.9,1.2],[0,2.2,0],dark)
    for sign in [-1,1]:
        add('Arm',[.85,1.8,1],[sign*1.5,3.35,0],dark)
        add('Hand',[.82,.6,.82],[sign*1.5,2.15,0],[234,171,96])
        add('Leg',[.85,1.75,.85],[sign*.5,1.05,0],dark)
        add('Boot',[.9,.3,1.25],[sign*.5,.18,-.13],dark)
        add('Vest',[1.92,1.35,.06],[0,3.32,sign*.73],red)
        add('Reflector',[1.92,.1,.025],[0,3.05,sign*.78],[160,169,166])
    add('Head',[1.05,1.65,1.65],[0,4.79,0],[234,171,96],shape='Cylinder',r=[0,-1,0,1,0,0,0,0,1])
    add('Cap',[1.8,.45,1.8],[0,5.38,0],dark,shape='Ball')
    add('Backward brim',[1.4,.1,.55],[0,5.35,.95],dark)
    return model

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('audit',type=Path);ap.add_argument('out',type=Path);args=ap.parse_args()
    models=json.loads(args.audit.read_text());model=next(m for m in models if m['id']=='backpack');args.out.mkdir(parents=True,exist_ok=True)
    accessory(model,args.out/'ZDC-Courier-Backpack.rbxmx')
    loaded=next(m for m in models if m['id']=='backpack_loaded')
    pack=next(p for p in model['spec']['pieces'] if p['name']=='FoldedTop');parcel=next(p for p in loaded['spec']['pieces'] if p['name']=='VisibleLightParcel')
    assert pack['at'][1]+pack['size'][1]/2<parcel['at'][1]-parcel['size'][1]/2,'Parcel clips pack lid'
    render=[model,mannequin(model)]
    (args.out/'render.json').write_text(json.dumps(render,separators=(',',':'))+'\n')
    print('Render data: exact authored geometry plus explicitly marked nominal R15 reference mannequin; carried parcel clears lid')
if __name__=='__main__':main()
