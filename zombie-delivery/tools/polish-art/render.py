"""Blender entry point: select audited polish samples and add explicitly marked caller-shell/Truss references."""
import json
from pathlib import Path
import runpy
import sys
import tempfile

args=sys.argv[sys.argv.index("--")+1:]
mode,source,out=args[:3]
models=json.loads(Path(source).read_text())
if mode=="street":models=[m for m in models if m["info"]["seed"]==1]
if mode=="towers":models=[m for m in models if m["info"].get("sample")]
def reference(name,size,position,color):
    return {"id":-1,"name":name,"class":"Part","size":size,"position":position,
            "rotation":[1,0,0,0,1,0,0,0,1],"color":color,"material":"Concrete","shape":"Block","opacity":1,"reference":True}
for model in models:
    if mode=="towers":
        w,d,h=model["info"]["tower"]
        model["parts"].append(reference("Caller tower shell",[w,h,d],[0,h/2,0],[.26,.28,.29]))
        for wall in model["info"]["walls"]:
            nx,nz=wall["nx"],wall["nz"]
            for floor in range(1,int((h-4)//9)+1):
                model["parts"].append(reference("Existing window strip",
                    [.08,3,d-4] if nx else [w-4,3,.08],
                    [nx*(w/2+.06),9*floor,nz*(d/2+.06)],[.16,.22,.25]))
        model["id"]=model["spec"]["id"]
    if mode=="stops":
        for p in list(model["parts"]):
            if p["class"]!="TrussPart":continue
            p["opacity"]=0
            x,y,z=p["position"];height=p["size"][1];bottom=y-height/2
            for side in (-1,1):
                model["parts"].append(reference("Truss reference rail",[.14,height,.14],[x+side*.9,y,z],p["color"]))
            for rung in range(1,int(height)+1):
                model["parts"].append(reference("Truss reference rung",[1.8,.1,.14],[x,bottom+rung,z],p["color"]))
with tempfile.TemporaryDirectory() as folder:
    data=Path(folder)/"render.json";data.write_text(json.dumps(models))
    sys.argv=["render.py","--",str(data),out,"--workbench"]
    runpy.run_path(str(Path(__file__).resolve().parents[1]/"model-art/render.py"),run_name="__main__")
