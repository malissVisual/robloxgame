#!/usr/bin/env python3
"""Write native Roblox display models from the audited factory export, retaining exact Parts, wedges and welds."""
from pathlib import Path
import json,sys,xml.etree.ElementTree as ET
ENUMS=json.loads((Path(__file__).parent/'enum-values.json').read_text())
def prop(parent,tag,name,value):
    node=ET.SubElement(parent,tag,{'name':name});node.text=str(value).lower() if isinstance(value,bool) else str(value);return node
def triple(parent,tag,name,value,fields=('X','Y','Z')):
    node=ET.SubElement(parent,tag,{'name':name})
    for field,v in zip(fields,value):ET.SubElement(node,field).text=str(v)
def write(models,target):
    root=ET.Element('roblox',{'version':'4'});ET.SubElement(root,'External').text='null';ET.SubElement(root,'External').text='nil'
    fleet=ET.SubElement(root,'Item',{'class':'Folder','referent':'ZDC_FLEET'});props=ET.SubElement(fleet,'Properties');prop(props,'string','Name','Zombie Delivery / Fleet Model Library')
    families={}
    for index,model in enumerate(models):
        if model['id'] not in families:
            family=ET.SubElement(fleet,'Item',{'class':'Folder','referent':'ZDC_FAMILY_'+model['id']})
            prop(ET.SubElement(family,'Properties'),'string','Name',model['id'])
            families[model['id']]=family
        # Spread the static references on a grid; retain every local frame and weld target.
        offset=[(index%5)*40,0,(index//5)*50]
        records=model['parts'];byid={p['id']:p for p in records};items={}
        for p in records:
            if p['class'] in {'Motor6D','SpotLight','PointLight'}:continue
            parent=items.get(p.get('parent'),families[model['id']])
            item=ET.SubElement(parent,'Item',{'class':p['class'],'referent':'ZDC_'+str(p['id'])});items[p['id']]=item;props=ET.SubElement(item,'Properties')
            vehicle_root=p['class']=='Model' and p.get('parent') not in byid
            name=f"{model['name']} / {'Full kit' if model['upgraded'] else 'Stage body'}" if vehicle_root else p['name']
            prop(props,'string','Name',name)
            if vehicle_root:
                chassis=next(v for v in records if v['name']=='Chassis');prop(props,'Ref','PrimaryPart','ZDC_'+str(chassis['id']))
            if 'size' in p:
                triple(props,'Vector3','Size',p['size']);triple(props,'Color3','Color',p['color'],('R','G','B'))
                cf=ET.SubElement(props,'CoordinateFrame',{'name':'CFrame'})
                position=[p['position'][i]+offset[i] for i in range(3)]
                for field,value in zip(['X','Y','Z','R00','R01','R02','R10','R11','R12','R20','R21','R22'],position+p['rotation']):ET.SubElement(cf,field).text=str(value)
                for name,key in [('Anchored',None),('CanCollide','canCollide'),('CanQuery','canQuery'),('CanTouch','canTouch'),('Massless','massless'),('CastShadow','castShadow')]:prop(props,'bool',name,True if key is None else p[key])
                prop(props,'float','Transparency',1-p['opacity']);prop(props,'float','Reflectance',p.get('reflectance',0));prop(props,'token','Material',ENUMS['Material'][p['material']])
                if p['class']=='Part':prop(props,'token','shape',ENUMS['PartType'][p.get('shape','Block')])
            elif p['class']=='WeldConstraint':
                prop(props,'Ref','Part0','ZDC_'+str(p['part0']));prop(props,'Ref','Part1','ZDC_'+str(p['part1']))
            elif p['class']=='SurfaceGui':
                prop(props,'token','Face',ENUMS['NormalId']['Front']);prop(props,'token','SizingMode',ENUMS['SurfaceGuiSizingMode']['PixelsPerStud']);prop(props,'float','PixelsPerStud',60);prop(props,'float','LightInfluence',.2)
            elif p['class']=='TextLabel':
                prop(props,'string','Text',p['text']);prop(props,'bool','TextScaled',True);prop(props,'float','BackgroundTransparency',1);prop(props,'token','Font',ENUMS['Font']['GothamMedium']);triple(props,'Color3','TextColor3',[217/255,218/255,207/255],('R','G','B'))
                size=ET.SubElement(props,'UDim2',{'name':'Size'})
                for key,value in [('XS',1),('XO',0),('YS',1),('YO',0)]:ET.SubElement(size,key).text=str(value)
    ET.ElementTree(root).write(target,encoding='utf-8',xml_declaration=True)
    print('Native model library:',len(models),'models /',target.stat().st_size,'bytes')
if __name__=='__main__':write(json.loads(Path(sys.argv[1]).read_text()),Path(sys.argv[2]))
