"""The DELIVEROS logo: a chunky 3D wordmark (a gold face, red sides, arched a little), rendered on a transparent
background; post.py gives it its outline, its shadow and its glints (post.py logo …)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # (first: bmesh comes with it)
import zdk
from mathutils import Vector

o = zdk.args()
sc = zdk.reset(o["res"], o["samples"])
sc.render.film_transparent = True
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"  # (a logo's colours as picked: AgX would wash the gold out)
sc.view_settings.look = "None"
zdk.sky(zenith=(255, 255, 255), horizon=(255, 250, 240), strength=0.8)

WORD = os.environ.get("ZDC_LOGO_WORD", "DELIVEROS")

# the letters: extruded, bevelled
cu = bpy.data.curves.new("Word", "FONT")
cu.body = WORD
cu.font = bpy.data.fonts.load(os.path.join(zdk.HERE, "fonts", "LuckiestGuy-Regular.ttf"), check_existing=True)
cu.size = 4.0
cu.extrude = 0.55
cu.bevel_depth = 0.09
cu.bevel_resolution = 3
cu.align_x = "CENTER"
cu.align_y = "CENTER"
cu.space_character = 1.0
txt = bpy.data.objects.new("Word", cu)
sc.collection.objects.link(txt)
bpy.context.view_layer.update()
me = bpy.data.meshes.new_from_object(txt.evaluated_get(bpy.context.evaluated_depsgraph_get()))
sc.collection.objects.unlink(txt)
word = bpy.data.objects.new("Logo", me)
sc.collection.objects.link(word)

# the face: a gold gradient (top bright), a little light of its own; the sides and the bevel: ZDC red, darker behind
face = bpy.data.materials.new("Face")
face.use_nodes = True
nt = face.node_tree
p = nt.nodes["Principled BSDF"]
tc = nt.nodes.new("ShaderNodeTexCoord")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
mr = nt.nodes.new("ShaderNodeMapRange")
ys = [v.co.y for v in me.vertices]
mr.inputs["From Min"].default_value = min(ys)
mr.inputs["From Max"].default_value = max(ys)
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].color = zdk.lin((250, 120, 10))
ramp.color_ramp.elements[1].color = zdk.lin((255, 236, 70))
mid = ramp.color_ramp.elements.new(0.62)
mid.color = zdk.lin((255, 196, 30))
ramp.color_ramp.elements[0].position = 0.08
ramp.color_ramp.elements[1].position = 0.86
nt.links.new(tc.outputs["Object"], sep.inputs[0])
nt.links.new(sep.outputs["Y"], mr.inputs["Value"])
nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
nt.links.new(ramp.outputs["Color"], p.inputs["Emission Color"])
p.inputs["Emission Strength"].default_value = 0.25
p.inputs["Roughness"].default_value = 0.32
side = zdk.mat("Side", (204, 32, 38), 0.45)
me.materials.append(face)
me.materials.append(side)
for poly in me.polygons:
    poly.material_index = 0 if poly.normal.z > 0.75 else 1
    poly.use_smooth = poly.material_index == 1

# arched a little, tilted back so the red sides show under the letters
bend = word.modifiers.new("Arch", "SIMPLE_DEFORM")
bend.deform_method = "BEND"
bend.deform_axis = "Z"
bend.angle = math.radians(-16)
word.rotation_euler = (math.radians(-22), 0, 0)

zdk.sun(direction_from=(-0.3, -0.6, 1.0), strength=3.2, color=(255, 248, 236))
zdk.light("AREA", (0, -14, 14), 900, (255, 244, 230), size=20, look=(0, 0, 0))
zdk.light("AREA", (14, 10, 6), 300, (255, 210, 170), size=8, look=(0, 0, 0))

lo, hi = zdk.bounds([word])
mid = (lo + hi) / 2
width = hi.x - lo.x
cam = zdk.camera((mid.x, mid.y - 2.0, mid.z + 60), (mid.x, mid.y, mid.z), lens=85)
cam.data.sensor_fit = "HORIZONTAL"
cam.data.lens = 36 * 60 / (width * 1.16)  # (the word fills the width, a margin for the outline)
zdk.render(o["out"])
