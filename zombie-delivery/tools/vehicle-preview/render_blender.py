"""Render actual exported Part/WedgePart/Cylinder geometry. Run with blender -b --python ... -- fleet.json output [key]."""
import bpy,sys,json,math
from pathlib import Path
from mathutils import Vector,Matrix
args=sys.argv[sys.argv.index('--')+1:]
workbench='--workbench' in args
args=[x for x in args if x!='--workbench']
models=json.loads(Path(args[0]).read_text());out=Path(args[1]);out.mkdir(parents=True,exist_ok=True)
if len(args)>2:models=[m for m in models if f"{m['id']}-{m['stage']}-{'kit' if m['upgraded'] else 'base'}"==args[2]]
T=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
materials={}
def material(p):
    key=tuple(p['color'])+(p['material'],)
    if key in materials:return materials[key]
    mat=bpy.data.materials.new(p['material']);mat.diffuse_color=(*p['color'],1);mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*p['color'],1)
    bs.inputs['Roughness'].default_value=.52 if p['material']=='Rubber' else .32 if p['material']=='Glass' else .4
    bs.inputs['Metallic'].default_value=.7 if p['material']=='Metal' else .2 if p['material']=='CorrodedMetal' else 0
    if p.get('attributes',{}).get('FleetFinish')=='glass':bs.inputs['Transmission Weight'].default_value=.55;bs.inputs['IOR'].default_value=1.45;bs.inputs['Roughness'].default_value=.13
    materials[key]=mat;return mat

def modelparts(model):
    group=[]
    for p in model['parts']:
        if 'size' not in p or p['opacity']<.05:continue
        x,y,z=p['size'];pos=T@Vector(p['position']);r=p['rotation'];rot=T@Matrix((r[0:3],r[3:6],r[6:9]))@T.inverted()
        if p['class']=='WedgePart':
            vs=[(-x/2,-y/2,-z/2),(x/2,-y/2,-z/2),(-x/2,-y/2,z/2),(x/2,-y/2,z/2),(-x/2,y/2,z/2),(x/2,y/2,z/2)]
            mesh=bpy.data.meshes.new(p['name']);mesh.from_pydata([T@Vector(v) for v in vs],[],[(0,1,3,2),(2,3,5,4),(0,4,5,1),(0,2,4),(1,5,3)]);mesh.update();obj=bpy.data.objects.new(p['name'],mesh);bpy.context.collection.objects.link(obj)
        elif p.get('shape')=='Cylinder':
            bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=1,depth=1);obj=bpy.context.object
            obj.data.transform(Matrix.Diagonal((x,z/2,y/2,1))@Matrix.Rotation(math.pi/2,4,'Y'))
        elif p.get('shape')=='Ball':
            bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1);obj=bpy.context.object;obj.scale=(x/2,z/2,y/2);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        else:
            bpy.ops.mesh.primitive_cube_add(size=1);obj=bpy.context.object;obj.scale=(x,z,y);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        obj.name=p['name'];obj.location=pos;obj.rotation_euler=rot.to_euler();obj.data.materials.append(material(p))
        group.append(obj)
    # SurfaceGui labels from the actual model are rendered on the same front-facing plates.
    nodes={p['id']:p for p in model['parts']}
    for p in model['parts']:
        if p['class']!='TextLabel' or not p.get('text'):continue
        gui=nodes[p['parent']];plate=nodes.get(gui.get('parent'))
        if not plate or 'size' not in plate:continue
        curve=bpy.data.curves.new('Fleet label','FONT');curve.body=p['text'];curve.align_x='CENTER';curve.align_y='CENTER';curve.size=1
        obj=bpy.data.objects.new('Fleet label',curve);bpy.context.collection.objects.link(obj)
        r=plate['rotation'];R=Matrix((r[:3],r[3:6],r[6:9]));basis=T@R@Matrix(((-1,0,0),(0,1,0),(0,0,-1)))
        obj.rotation_euler=basis.to_euler();obj.location=T@(Vector(plate['position'])+R@Vector((0,0,-plate['size'][2]/2-.008)))
        bpy.context.view_layer.update();bounds=obj.bound_box; textwidth=max(v[0] for v in bounds)-min(v[0] for v in bounds); textheight=max(v[1] for v in bounds)-min(v[1] for v in bounds); scale=min(plate['size'][0]*.84/max(textwidth,.001),plate['size'][1]*.72/max(textheight,.001));obj.scale=(scale,scale,scale)
        mat=bpy.data.materials.get('Fleet label ink')
        if not mat:mat=bpy.data.materials.new('Fleet label ink');mat.diffuse_color=(.8,.82,.78,1)
        obj.data.materials.append(mat);group.append(obj)
    return group

def setup():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH' if workbench else 'CYCLES'
    if workbench:
        scene.display.shading.light='STUDIO';scene.display.shading.studio_light='paint.sl';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True;scene.display.shading.shadow_intensity=.3;scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH'
    else:scene.cycles.samples=24;scene.cycles.use_denoising=False
    scene.render.resolution_x=960;scene.render.resolution_y=680;scene.render.resolution_percentage=100
    scene.world.color=(.2,.2,.2);scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.34,.38,.4,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
    bpy.ops.mesh.primitive_plane_add(size=240);plane=bpy.context.object
    mat=bpy.data.materials.new('Floor');mat.diffuse_color=(.16,.18,.19,1);mat.use_nodes=True;mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.16,.18,.19,1);mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.7;plane.data.materials.append(mat)
    for loc,power,size in [((-10,12,20),3200,12),((14,8,12),2000,10),((1,-12,18),2600,8)]:
        bpy.ops.object.light_add(type='AREA',location=loc);lamp=bpy.context.object;lamp.data.energy=power;lamp.data.shape='DISK';lamp.data.size=size;lamp.rotation_euler=(Vector((0,0,3))-lamp.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(-18,25,15));cam=bpy.context.object;cam.data.type='ORTHO';scene.camera=cam
    scene.view_settings.view_transform='Standard' if workbench else 'AgX'
    scene.render.image_settings.file_format='PNG'
    return scene,cam
scene,cam=setup()
for m in models:
    objects=modelparts(m);bounds=[o.matrix_world@Vector(c) for o in objects for c in o.bound_box]
    # Explicit framing from model dimensions, including the long freight truck.
    size=max(max(p['size'][2]+abs(p['position'][2])*2 for p in m['parts'] if 'size' in p and p['opacity']>.05),12)
    top=max(p['position'][1]+p['size'][1]/2 for p in m['parts'] if 'size' in p and p['opacity']>.05)
    cam.data.ortho_scale=max(19,size*1.12);cam.location=(-size*1.1,size*1.55,size*.85)
    cam.rotation_euler=(Vector((0,0,top*.45))-cam.location).to_track_quat('-Z','Y').to_euler()
    key=f"{m['id']}-{m['stage']}-{'kit' if m['upgraded'] else 'base'}"
    scene.render.filepath=str(out/(key+'.png'));bpy.ops.render.render(write_still=True)
    # Downloadable real mesh preview for non-Studio inspection.
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out/(key+'.glb')),use_selection=True,export_format='GLB')
    for o in objects:bpy.data.objects.remove(o,do_unlink=True)
    print('MODEL_RENDERED',key,flush=True)
