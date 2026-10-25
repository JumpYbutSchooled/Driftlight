"""Renders a contact sheet of exported GLB models so they can be checked by eye.

Run:  blender --background --python preview.py -- out.png model1.glb model2.glb ...
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out, files = argv[0], argv[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

cols = max(1, math.ceil(math.sqrt(len(files))))
cell = 0.0
roots = []
for path in files:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    top = [o for o in new if o.parent is None]
    pts = []
    for o in new:
        if o.type == "MESH":
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = max(hi - lo)
    cell = max(cell, size)
    roots.append((top, (lo + hi) / 2, size, os.path.splitext(os.path.basename(path))[0]))

spacing = cell * 1.25
for i, (top, centre, size, name) in enumerate(roots):
    gx, gy = i % cols, i // cols
    for o in top:
        o.location += Vector((gx * spacing, -gy * spacing, 0)) - centre
    txt = bpy.data.curves.new(name + "_label", "FONT")
    txt.body = name
    txt.size = cell * 0.09
    t = bpy.data.objects.new(name + "_label", txt)
    t.location = (gx * spacing - cell * 0.45, -gy * spacing - cell * 0.62, 0)
    scene.collection.objects.link(t)

rows = math.ceil(len(roots) / cols)
centre = Vector(((cols - 1) * spacing / 2, -(rows - 1) * spacing / 2, 0))
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = max(cols, rows) * spacing * 1.08
cam_data.clip_start = cell * 0.5
cam_data.clip_end = cell * 60.0
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
d = Vector((0.55, -0.85, 0.75)).normalized()
cam.location = centre + d * (cell * 20)
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam

sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 4.0
s = bpy.data.objects.new("sun", sun)
s.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
scene.collection.objects.link(s)
fill = bpy.data.lights.new("fill", "SUN")
fill.energy = 1.2
f = bpy.data.objects.new("fill", fill)
f.rotation_euler = (math.radians(-60), 0, math.radians(200))
scene.collection.objects.link(f)

world = bpy.data.worlds.new("w")
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (0.02, 0.025, 0.05, 1)
bg.inputs[1].default_value = 1.0

for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        continue
try:
    scene.eevee.use_bloom = True
except Exception:
    pass
scene.render.resolution_x = 1600
scene.render.resolution_y = int(1600 * rows / cols)
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
print("RENDERED", out, scene.render.engine)
