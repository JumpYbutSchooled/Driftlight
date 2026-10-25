"""Renders close-ups of exported GLB models (front three-quarter and rear views) to check detail by eye.

Run:  blender --background --python closeup.py -- out_dir [frame] model1.glb model2.glb ...
Writes out_dir/<model>_front.png and out_dir/<model>_rear.png. frame (an int) picks the animation frame.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_dir = argv.pop(0)
frame = 1
if argv and argv[0].isdigit():
    frame = int(argv.pop(0))


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 760
    world = bpy.data.worlds.new("w")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.012, 0.016, 0.03, 1)
    bg.inputs[1].default_value = 1.0
    for name, energy, rot in (("key", 3.5, (50, 10, 30)), ("fill", 0.8, (-60, 0, 200)), ("rim", 2.0, (120, 0, 140))):
        l = bpy.data.lights.new(name, "SUN")
        l.energy = energy
        o = bpy.data.objects.new(name, l)
        o.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(o)
    return scene


for path in argv:
    scene = setup_scene()
    bpy.ops.import_scene.gltf(filepath=path)
    scene.frame_set(frame)
    pts = []
    for o in bpy.data.objects:
        if o.type == "MESH":
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    size = (hi - lo).length
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam_data.clip_start = size * 0.01
    cam_data.clip_end = size * 20
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    name = os.path.splitext(os.path.basename(path))[0]
    # the glTF importer turns Godot's -Z forward back into Blender +Y, so +Y is the nose
    for view, d in (("front", Vector((0.75, 0.9, 0.6))), ("rear", Vector((-0.8, -0.85, 0.45)))):
        d.normalize()
        cam.location = centre + d * size * 1.25
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    print("RENDERED", name)
