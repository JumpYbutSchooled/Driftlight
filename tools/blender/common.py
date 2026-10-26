"""Shared helpers for the Driftlight Blender model scripts (run with Blender in --background mode).

Conventions: Blender Z is up and a model's nose points +Y. The glTF exporter turns that into
Godot's Y-up with the nose pointing -Z, which is Godot's "forward".
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

OUT = r"C:\My stuff\Driftlight\models"
LOOP = 1200  # every animation in a model loops over this many frames (50 s at 24 fps); periods must divide it
_mats = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    # new keyframes should be linear so looping spins don't ease in and out
    try:
        bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    except Exception:
        pass


def hexcol(h):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # Blender colour inputs are linear
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb) + (1.0,)


def mat(name, color, metallic=0.4, rough=0.5, emit=0.0):
    """A Principled material. emit > 0 makes it glow in its own colour."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col = hexcol(color) if isinstance(color, str) else color

    def put(names, value):
        for nm in names:
            if nm in bsdf.inputs:
                bsdf.inputs[nm].default_value = value
                return

    put(["Base Color"], col)
    put(["Metallic"], metallic)
    put(["Roughness"], rough)
    if emit > 0:
        put(["Emission Color", "Emission"], col)
        put(["Emission Strength"], emit)
    _mats[name] = m
    return m


def _link(obj, parent=None):
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def _finish(name, bm, material, loc, rot, parent, bevel, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    if material is not None:
        for m in (material if isinstance(material, (list, tuple)) else [material]):
            mesh.materials.append(m)
    if smooth:
        for p in mesh.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    obj.location = loc
    obj.rotation_euler = rot
    _link(obj, parent)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    return obj


def box(name, size, loc=(0, 0, 0), material=None, bevel=0.0, rot=(0, 0, 0), parent=None, taper=None):
    """A box of size (x, y, z). taper=(sx, sz) narrows the +Y (front) end, for wedge shapes."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
        if taper and v.co.y > 0:
            v.co.x *= taper[0]
            v.co.z *= taper[1]
    return _finish(name, bm, material, loc, rot, parent, bevel)


def cyl(name, r, depth, loc=(0, 0, 0), material=None, rot=(0, 0, 0), parent=None, segs=12, r2=None, bevel=0.0, caps=True):
    """A cylinder (or cone, with r2) along local Z. caps=False leaves it an open tube (engine bells)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    return _finish(name, bm, material, loc, rot, parent, bevel)


def along_y(r, depth, loc, material, parent=None, segs=12, r2=None, caps=True):
    """A cylinder lying along +Y (barrels, nozzles); r is the radius at the back (-Y) end, r2 at the front."""
    return cyl("cyl", r, depth, loc, material, (math.radians(-90), 0, 0), parent, segs, r2, caps=caps)


def slab(name, pts, t, offset=0.0, plane="xy", material=None, parent=None, rot=(0, 0, 0), loc=(0, 0, 0), bevel=0.0):
    """A flat plate of thickness t cut to any outline (wings, fins, blades). pts are (u, v) corners in order.
    plane "xy": u = x, v = y, lying flat at height `offset`. plane "yz": u = y, v = z, standing upright at
    x = `offset` (tail fins). The outline may be concave."""
    bm = bmesh.new()

    def co(u, v, w):
        return (u, v, w) if plane == "xy" else (w, u, v)

    bot = [bm.verts.new(co(u, v, offset - t / 2)) for u, v in pts]
    top = [bm.verts.new(co(u, v, offset + t / 2)) for u, v in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(pts)
    for i in range(n):
        bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _finish(name, bm, material, loc, rot, parent, bevel)


def ico(name, r, loc=(0, 0, 0), material=None, subdiv=2, parent=None, smooth=False):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    return _finish(name, bm, material, loc, (0, 0, 0), parent, 0.0, smooth)


def octa(name, r, height, loc=(0, 0, 0), material=None, rot=(0, 0, 0), parent=None):
    """A crystal: an octahedron stretched along Z."""
    bm = bmesh.new()
    pts = [(r, 0, 0), (-r, 0, 0), (0, r, 0), (0, -r, 0), (0, 0, height), (0, 0, -height)]
    vs = [bm.verts.new(p) for p in pts]
    for a, b in [(0, 2), (2, 1), (1, 3), (3, 0)]:
        bm.faces.new((vs[a], vs[b], vs[4]))
        bm.faces.new((vs[b], vs[a], vs[5]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _finish(name, bm, material, loc, rot, parent, 0.0)


def torus(name, major, minor, loc=(0, 0, 0), material=None, rot=(0, 0, 0), parent=None, seg=48, ring=10):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        out = Vector((math.cos(a), math.sin(a), 0))
        rr = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            rr.append(bm.verts.new(c + out * (math.cos(b) * minor) + Vector((0, 0, math.sin(b) * minor))))
        rings.append(rr)
    for i in range(seg):
        a, b = rings[i], rings[(i + 1) % seg]
        for j in range(ring):
            bm.faces.new((a[j], b[j], b[(j + 1) % ring], a[(j + 1) % ring]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _finish(name, bm, material, loc, rot, parent, 0.0, smooth=True)


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.3
    e.location = loc
    return _link(e, parent)


def root(name):
    r = bpy.data.objects.new(name, None)
    return _link(r)


def merge(children_of, name):
    """Apply modifiers and join every mesh directly under `children_of` into one object (fewer draw calls)."""
    meshes = [o for o in children_of.children if o.type == "MESH"]
    if not meshes:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.convert(target="MESH")
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    return obj


def _keyed(interp):
    """Context for inserting keyframes with a given interpolation (CONSTANT for blinking, BEZIER for sways)."""
    class _K:
        def __enter__(self):
            bpy.context.preferences.edit.keyframe_new_interpolation_type = interp

        def __exit__(self, *a):
            bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    return _K()


def spin(obj, axis, period, turns=1.0):
    """Keyframe a looping linear spin around a local axis ('X', 'Y' or 'Z'): `turns` turns every `period` frames."""
    assert LOOP % period == 0, period
    idx = "XYZ".index(axis)
    base = obj.rotation_euler[idx]
    obj.keyframe_insert("rotation_euler", index=idx, frame=1)
    obj.rotation_euler[idx] = base + 2 * math.pi * turns * (LOOP // period)
    obj.keyframe_insert("rotation_euler", index=idx, frame=LOOP + 1)
    obj.rotation_euler[idx] = base


def sway(obj, axis, amp, period, phase=0):
    """A smooth back-and-forth turn (scanning turrets, nodding dishes). phase is in quarter periods."""
    q = period // 4
    assert LOOP % q == 0 and period % 4 == 0, period
    idx = "XYZ".index(axis)
    base = obj.rotation_euler[idx]
    with _keyed("BEZIER"):
        for k in range(LOOP // q + 1):
            obj.rotation_euler[idx] = base + amp * (0, 1, 0, -1)[(k + phase) % 4]
            obj.keyframe_insert("rotation_euler", index=idx, frame=1 + k * q)
    obj.rotation_euler[idx] = base


def blink(obj, period, on, phase=0):
    """Hard on/off blinking (by scale): lit for `on` frames of every `period`, offset by `phase`."""
    assert LOOP % period == 0, period
    last = None
    with _keyed("CONSTANT"):
        for f in range(1, LOOP + 2):
            lit = (f - 1 - phase) % period < on
            if lit != last or f == LOOP + 1:
                s = 1.0 if lit else 0.001
                obj.scale = (s, s, s)
                obj.keyframe_insert("scale", frame=f)
                last = lit
    obj.scale = (1, 1, 1)


def light(name, loc, r, material, parent, period=0, on=6, phase=0):
    """A small glowing bulb; blinks if a period is given (its own object, so it can scale about its centre)."""
    o = ico(name, r, loc, material, 1, parent)
    if period:
        blink(o, period, on, phase)
    return o


# ---------------------------------------------------------------- hull detail

def frame(origin, u, v, n):
    """Matrix taking local (x, y, z) onto a surface: x along u, y along v, z out along the normal n."""
    m = Matrix((Vector(u), Vector(v), Vector(n))).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def to_frame(objs, F):
    for o in objs:
        o.matrix_basis = F @ o.matrix_basis
    return objs


def plated(name, size, loc=(0, 0, 0), mats=None, parent=None, rot=(0, 0, 0), taper=None, cell=1.4, rng=None,
           depth=0.05, seam=0.045, chamfer=0.0, faces=None):
    """A box clad in armour plates. The faces are cut into an uneven grid, every panel is inset with a dark seam
    (mats[1]) and pushed in or out a touch; some panels take the second plate colour (mats[2]).
    taper=(sx, sz) narrows the +Y end like box(). faces: only plate faces whose normal is in this list of axes,
    e.g. ['+Z', '-X']."""
    rng = rng or random.Random(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    if chamfer > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=chamfer, segments=1, affect="EDGES", profile=0.5)
    for axis in range(3):
        half = size[axis] / 2
        step = max(cell, size[axis] / 40.0)
        p = -half + step * rng.uniform(0.55, 1.3)
        while p < half - step * 0.4:
            co = [0.0, 0.0, 0.0]
            no = [0.0, 0.0, 0.0]
            co[axis] = p
            no[axis] = 1.0
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=0.0001, plane_co=co, plane_no=no)
            p += step * rng.uniform(0.55, 1.6)
    if taper:
        for v in bm.verts:
            t = v.co.y / size[1] + 0.5
            v.co.x *= 1 + (taper[0] - 1) * t
            v.co.z *= 1 + (taper[1] - 1) * t
    bm.normal_update()
    want = None
    if faces:
        want = [Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[a[1]]) * (1 if a[0] == "+" else -1) for a in faces]
    groups = {}
    nmat = len(mats) if isinstance(mats, (list, tuple)) else 1
    for fc in list(bm.faces):
        if fc.calc_area() / max(1e-6, fc.calc_perimeter()) < seam * 1.6:
            continue
        if want and not any(fc.normal.dot(w) > 0.9 for w in want):
            continue
        roll = rng.random()
        d = depth if roll < 0.3 else (-depth * 0.6 if roll < 0.45 else 0.0)
        groups.setdefault(d, []).append(fc)
        if nmat > 2 and rng.random() < 0.22:
            fc.material_index = 2
    for d, fs in groups.items():
        res = bmesh.ops.inset_individual(bm, faces=fs, thickness=seam, depth=d, use_even_offset=True)
        if nmat > 1:
            for nf in res["faces"]:
                nf.material_index = 1
    return _finish(name, bm, mats, loc, rot, parent, 0.0)


def sleek_ends(size, nose=None, tail=None):
    """How far back from each end a sleek() part starts rounding off: (nose, tail) in metres."""
    w, l, h = size
    m = min(w, h)
    return (min(l * 0.5, m * 1.4) if nose is None else nose, min(l * 0.2, m * 0.25) if tail is None else tail)


def sleek_k(y, l, nose, tail):
    """A sleek() part's size at y (as a share of its full cross-section): drawn in to a point over the last
    `nose` metres of the front (+Y), an ogive like a fighter's nose, and rounded off over `tail` metres at the
    back down to a flat end 70% the size (engines meet it)."""
    if nose > 0 and y > l / 2 - nose:
        s = min(1.0, (y - (l / 2 - nose)) / nose)
        return max(0.0, 1.0 - s ** 1.8)
    if tail > 0 and y < -l / 2 + tail:
        s = min(1.0, (-l / 2 + tail - y) / tail)
        return 1.0 - 0.3 * (1.0 - math.sqrt(max(0.0, 1.0 - s * s)))
    return 1.0


def sleek(name, size, loc=(0, 0, 0), mats=None, parent=None, rot=(0, 0, 0), taper=None, p=3.4, nose=None, tail=None,
          rings=22, segs=32, droop=0.45):
    """A smooth hull piece, size (x, y, z), nose to +Y: rounded-rectangle cross-sections (a superellipse: p 2 is an
    ellipse, higher is squarer) lofted along Y, drawn in at the ends (see sleek_k), smooth shaded with a crisp
    edge round the flat back. The nose dips (`droop`): its top slopes down to a point low on the front, like a
    fighter's. taper=(sx, sz) narrows the +Y end like box()."""
    w, l, h = size
    nose, tail = sleek_ends(size, nose, tail)
    tx, tz = taper or (1.0, 1.0)
    bm = bmesh.new()
    ys = [-l / 2 + l * (1 - math.cos(math.pi * i / rings)) / 2 for i in range(rings + 1)]  # closer together at the ends
    ring_verts = []
    for y in ys:
        t = y / l + 0.5
        k = sleek_k(y, l, nose, tail)
        b0 = h / 2 * (1 + (tz - 1) * t)
        a = w / 2 * (1 + (tx - 1) * t) * k
        b = b0 * k
        zc = -b0 * (1 - k) * droop if y > 0 else 0.0  # (only the nose dips)
        if k < 1e-3:
            ring_verts.append([bm.verts.new((0.0, y, zc))])
            continue
        ring = []
        for j in range(segs):
            th = 2 * math.pi * j / segs
            c, s = math.cos(th), math.sin(th)
            ring.append(bm.verts.new((a * math.copysign(abs(c) ** (2 / p), c), y, zc + b * math.copysign(abs(s) ** (2 / p), s))))
        ring_verts.append(ring)
    for r0, r1 in zip(ring_verts, ring_verts[1:]):
        if len(r1) == 1:
            for j in range(segs):
                bm.faces.new((r0[j], r0[(j + 1) % segs], r1[0]))
        else:
            for j in range(segs):
                bm.faces.new((r0[j], r0[(j + 1) % segs], r1[(j + 1) % segs], r1[j]))
    back = bm.faces.new(list(reversed(ring_verts[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if isinstance(mats, (list, tuple)) and len(mats) > 2:
        for f in bm.faces:  # two-tone: the underside a shade darker
            if f.calc_center_median().z < -h * 0.12:
                f.material_index = 2
    for e in back.edges:
        e.smooth = False  # a crisp rim round the flat back
    return _finish(name, bm, mats, loc, rot, parent, 0.0, smooth=True)


def box_batch(name, mats, material, parent=None):
    """Many small boxes in one mesh (window rows, rivet lines). mats: list of 4x4 matrices placing a unit cube."""
    bm = bmesh.new()
    for M in mats:
        bmesh.ops.create_cube(bm, size=1.0, matrix=M)
    return _finish(name, bm, material, (0, 0, 0), (0, 0, 0), parent, 0.0)


def windows(F, w, l, rows, material, rng, parent, cell=(0.32, 0.18), gap=0.5, lit=0.72, name="windows"):
    """Rows of small lit windows over a w x l patch of the surface frame F (rows run along local x)."""
    out = []
    for r in range(rows):
        y = -l / 2 + (r + 0.5) * l / rows
        n = int(w / gap)
        run = rng.random() < 0.5
        for k in range(n):
            if rng.random() < 0.12:
                run = not run
            if not run or rng.random() > lit:
                continue
            x = -w / 2 + (k + 0.5) * w / n
            out.append(F @ Matrix.Translation((x, y, 0.015)) @ Matrix.Diagonal((cell[0], cell[1], 0.05, 1.0)))
    if out:
        return box_batch(name, out, material, parent)
    return None


class Greebler:
    """Scatters small hull details over a flat patch: blocks, stacks, pipe runs, vents, tanks, domes, hatches,
    radiator fins and antennas."""
    KINDS = ("block", "block", "stack", "stack", "pipes", "vent", "tank", "dome", "hatch", "radiator", "antenna")

    def __init__(self, parent, rng, metal, dark, accent=None, lamp=None):
        self.parent = parent
        self.rng = rng
        self.metal = metal
        self.dark = dark
        self.accent = accent or metal
        self.lamp = lamp

    def patch(self, F, w, l, count, scale=1.0, lift=None, kinds=None):
        """`count` greebles inside a w x l rectangle of frame F. lift(x, y) raises a greeble off the surface."""
        rng = self.rng
        made = []
        for _ in range(count):
            a = min(w * 0.9, rng.uniform(0.3, 0.75) * scale)
            b = min(l * 0.9, a * rng.uniform(0.7, 2.6))
            if a <= 0.05 or b <= 0.05:
                continue
            x = rng.uniform(-w / 2 + a / 2, w / 2 - a / 2)
            y = rng.uniform(-l / 2 + b / 2, l / 2 - b / 2)
            z = lift(x, y) if lift else 0.0
            made += self.one(rng.choice(kinds or self.KINDS), x, y, z, a, b)
        return to_frame(made, F)

    def one(self, kind, x, y, z, a, b):
        rng, P = self.rng, self.parent
        out = []
        if kind == "block":
            h = rng.uniform(0.1, 0.4) * min(a, b) + 0.05
            out.append(box("g", (a, b, h), (x, y, z + h / 2), self.metal, 0.0, parent=P))
        elif kind == "stack":
            h = rng.uniform(0.1, 0.3) * min(a, b) + 0.05
            out.append(box("g", (a, b, h), (x, y, z + h / 2), self.dark, 0.0, parent=P))
            h2 = h * rng.uniform(0.6, 1.4)
            out.append(box("g", (a * 0.6, b * 0.55, h2), (x + a * 0.1, y, z + h + h2 / 2), self.metal, 0.0, parent=P))
            if rng.random() < 0.5:
                out.append(cyl("g", a * 0.12, h2 * 0.8, (x - a * 0.25, y + b * 0.25, z + h + h2 * 0.4), self.accent, parent=P, segs=8))
        elif kind == "pipes":
            n = rng.randint(2, 4)
            r = min(a / (n * 2.4), 0.12)
            for k in range(n):
                px = x - a / 2 + (k + 0.5) * a / n
                out.append(along_y(r, b, (px, y, z + r), self.accent if k % 2 else self.metal, parent=P, segs=8))
            for e in (-1, 1):
                out.append(box("g", (a, 0.08, r * 2.6), (x, y + e * b * 0.42, z + r * 1.3), self.dark, 0.0, parent=P))
        elif kind == "vent":
            out.append(box("g", (a, b, 0.05), (x, y, z + 0.025), self.dark, 0.0, parent=P))
            n = max(2, int(b / 0.14))
            for k in range(n):
                out.append(box("g", (a * 0.86, 0.035, 0.09), (x, y - b / 2 + (k + 0.5) * b / n, z + 0.07), self.metal, 0.0,
                               rot=(math.radians(30), 0, 0), parent=P))
        elif kind == "tank":
            r = min(a / 2, 0.45)
            out.append(along_y(r, b * 0.8, (x, y, z + r), self.metal, parent=P, segs=12))
            for e in (-1, 1):
                c = cyl("g", r, b * 0.1, (x, y + e * b * 0.45, z + r), self.metal, parent=P, segs=12, r2=r * 0.55)
                c.rotation_euler = (math.radians(-90 * e), 0, 0)
                out.append(c)
            out.append(box("g", (r * 2.3, 0.06, r * 0.9), (x, y, z + r * 0.45), self.dark, 0.0, parent=P))
        elif kind == "dome":
            r = min(a, b) * 0.42
            out.append(cyl("g", r, r * 0.5, (x, y, z + r * 0.25), self.dark, parent=P, segs=12))
            out.append(ico("g", r * 0.82, (x, y, z + r * 0.5), self.metal, 2, parent=P))
        elif kind == "hatch":
            out.append(box("g", (a, b, 0.04), (x, y, z + 0.02), self.dark, 0.0, parent=P))
            out.append(box("g", (a * 0.72, b * 0.72, 0.07), (x, y, z + 0.035), self.metal, 0.0, parent=P))
            out.append(box("g", (a * 0.5, 0.05, 0.09), (x, y, z + 0.045), self.accent, 0.0, parent=P))
        elif kind == "radiator":
            n = max(3, int(a / 0.12))
            h = rng.uniform(0.15, 0.35) * b + 0.1
            for k in range(n):
                out.append(box("g", (0.035, b, h), (x - a / 2 + (k + 0.5) * a / n, y, z + h / 2), self.metal, 0.0, parent=P))
            out.append(box("g", (a, b * 0.1, h * 0.3), (x, y, z + h * 0.15), self.dark, 0.0, parent=P))
        elif kind == "antenna":
            h = rng.uniform(0.6, 1.6) * max(a, b)
            out.append(cyl("g", 0.1, 0.12, (x, y, z + 0.06), self.dark, parent=P, segs=8))
            out.append(cyl("g", 0.03, h, (x, y, z + h / 2), self.metal, parent=P, segs=6))
            out.append(box("g", (0.3, 0.03, 0.03), (x, y, z + h * 0.7), self.metal, 0.0, parent=P))
            if self.lamp is not None:
                out.append(ico("g", 0.06, (x, y, z + h), self.lamp, 1, parent=P))
        return out


def export(rootobj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    stack = [rootobj]
    while stack:
        o = stack.pop()
        o.select_set(True)
        stack.extend(o.children)
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = LOOP + 1
    scene.frame_set(1)
    # one scene-wide clip: every spin and blink in the model plays together and loops cleanly
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                  export_animations=True, export_animation_mode="SCENE")
    for drop in (None, "export_animation_mode", "export_animations"):
        if drop:
            kwargs.pop(drop, None)
        try:
            bpy.ops.export_scene.gltf(**kwargs)
            break
        except TypeError:
            continue
    print("EXPORTED", path)